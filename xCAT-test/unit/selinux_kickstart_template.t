#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
make_path("$dir/db", "$dir/install");
symlink(repo_path('xCAT/postscripts'), "$dir/install/postscripts") or die "postscripts link: $!";
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Table;
require xCAT::Template;
require xCAT::SELinux;

like($INC{'xCAT/SELinux.pm'}, qr/\Q$FindBin::Bin\E/,
    'xCAT::SELinux comes from this checkout, not from /opt/xcat');

my %site_values = (
    installdir => "$dir/install", tftpdir => "$dir/tftpboot", master => '192.0.2.1',
    timezone => 'UTC', xcatiport => 3002, xcatdport => 3001, httpport => 80,
    xcatdebugmode => 0, nodestatus => 1,
);
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %site_values) {
    $site->setAttribs({ key => $key }, { value => $site_values{$key} });
}
$site->close();
%::XCATSITEVALS = (%site_values, secureroot => 1, managedaddressmode => 'dhcp');

# The maintained kickstart templates, each with an OS that uses it.
my @templates = (
    [ 'rh/compute.rhels10.tmpl',          'rhels10.0',         'rh' ],
    [ 'rh/compute.rhels9.tmpl',           'alma9.6',           'rh' ],
    [ 'rh/compute.rhels8.tmpl',           'rocky8.10',         'rh' ],
    [ 'rh/compute.rhels10.riscv64.tmpl',  'rhels10.0',         'rh' ],
    [ 'openeuler/compute.openeuler.tmpl', 'openeuler24.03sp3', 'openeuler' ],
);

my $relabel = qr{^/usr/sbin/restorecon -RF /xcatpost /opt/xcat /etc /root /var/log\b}m;

sub set_node {
    my ($os, $mode) = @_;
    for my $entry (
        [ 'nodelist', { groups => 'all' } ],
        [ 'nodetype', { os => $os, arch => 'x86_64', provmethod => 'install' } ],
        [ 'noderes', { xcatmaster => '192.0.2.1', nfsserver => '192.0.2.2', installnic => 'mac', selinux => $mode } ],
        [ 'mac', { mac => '52:54:00:12:34:56' } ],
    ) {
        my ($name, $values) = @$entry;
        my $tab = xCAT::Table->new($name, -create => 1);
        $tab->setAttribs({ node => 'cn1' }, $values);
        $tab->close();
    }
}

# The text of the first %post section: where the xCAT post scripts run.
sub main_post {
    my ($ks) = @_;
    my ($post) = $ks =~ /^(%post --interpreter=\/bin\/bash.*?^%end)$/ms;
    return $post;
}

foreach my $case (@templates) {
    my ($template, $os, $platform) = @$case;
    my $path = "$ENV{XCATROOT}/share/xcat/install/$template";
    (my $pkglist = $path) =~ s/\.tmpl$/.pkglist/;
    $pkglist = '' unless -r $pkglist;

    foreach my $mode (qw(enforcing permissive disabled)) {
        set_node($os, $mode);
        my $out = "$dir/ks.$mode";
        my $error = xCAT::Template->subvars($path, $out, 'cn1', $pkglist,
            '/install/media', $platform, undef, { xcatmaster => '192.0.2.1' });
        ok(!$error, "$template renders for $mode") or diag($error);
        my $ks = read_text($out);

        my @lines = $ks =~ /^(selinux\s.*)$/mg;
        is_deeply(\@lines, ["selinux --$mode"], "$template sets selinux --$mode for a $mode node");
        is(xCAT::SELinux->kickstart_mode($ks), $mode, "the $template kickstart asks anaconda for $mode");
        unlike($ks, qr/#SELINUX[A-Z]*#/, "$template leaves no SELinux directive unresolved");

        my $post = main_post($ks);
        ok(defined $post, "$template has a main %post section");
        if ($mode eq 'disabled') {
            unlike($ks, $relabel, "$template does not relabel a $mode node");
        } else {
            like($post, $relabel, "$template relabels the xCAT files in %post for a $mode node");

            # The relabel has to run after the xCAT post scripts wrote their files, so
            # compare where each one lands. A regex that only spans from the relabel to
            # the end of %post passes wherever the relabel sits.
            my @post_lines = split(/\n/, $post);
            my ($relabel_at) = grep { $post_lines[$_] =~ $relabel } 0 .. $#post_lines;
            my @xcat_at = grep {
                $_ != $relabel_at && $post_lines[$_] =~ /mypostscript|xcatdsklspost|updateflag/
            } 0 .. $#post_lines;
            ok(scalar(@xcat_at) > 0, "$template runs the xCAT post scripts in %post");
            ok(defined $relabel_at && $relabel_at > $xcat_at[-1],
                "$template relabels at line $relabel_at, after the last xCAT post script at line $xcat_at[-1]");
        }
    }
}

# A custom template that keeps the old line cannot express the mode of the node.
is(xCAT::SELinux->kickstart_mode("text\nselinux --disable\nreboot\n"), 'disabled',
    'selinux --disable asks for disabled');
is(xCAT::SELinux->kickstart_mode("text\nselinux --enforcing\n"), 'enforcing',
    'selinux --enforcing asks for enforcing');
is(xCAT::SELinux->kickstart_mode("text\nreboot\n"), 'enforcing',
    'a kickstart with no selinux line gets the anaconda default, enforcing');

like(xCAT::SELinux->kickstart_mismatch('enforcing', "selinux --disabled\n"), qr/enforcing.*disabled/,
    'an enforcing node with a template that says --disabled gets a warning');
like(xCAT::SELinux->kickstart_mismatch('disabled', "reboot\n"), qr/disabled.*enforcing/,
    'a disabled node with a template that has no selinux line gets a warning');
is(xCAT::SELinux->kickstart_mismatch('permissive', "selinux --permissive\n"), undef,
    'a template that matches the mode of the node gets no warning');

done_testing();
