#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
make_path("$dir/db", "$dir/install", "$dir/custom");
symlink(repo_path('xCAT/postscripts'), "$dir/install/postscripts") or die "postscripts link: $!";
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Table;
require xCAT::Template;

my %site_values = (
    installdir => "$dir/install", tftpdir => "$dir/tftpboot", master => '192.0.2.1',
    timezone => 'UTC', xcatiport => 3002, xcatdport => 3001, httpport => 8080,
    xcatdebugmode => 0, nodestatus => 1,
);
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %site_values) {
    $site->setAttribs({ key => $key }, { value => $site_values{$key} });
}
$site->close();
%::XCATSITEVALS = (%site_values, secureroot => 1, managedaddressmode => 'dhcp');

for my $entry (
    ['nodelist', { node => 'oe-node', groups => 'all' }],
    ['nodetype', { node => 'oe-node', os => 'openeuler24.03sp3', arch => 'x86_64', provmethod => 'oe-image' }],
    ['noderes', { node => 'oe-node', xcatmaster => '192.0.2.1', nfsserver => '192.0.2.2', installnic => 'mac' }],
    ['mac', { node => 'oe-node', mac => '52:54:00:12:34:56' }],
) {
    my ($name, $values) = @$entry;
    my $tab = xCAT::Table->new($name, -create => 1);
    $tab->setAttribs({ node => 'oe-node' }, $values);
    $tab->close();
}

for my $profile (qw(compute service)) {
    my $template = "$ENV{XCATROOT}/share/xcat/install/openeuler/$profile.openeuler.tmpl";
    my $pkglist = "$ENV{XCATROOT}/share/xcat/install/openeuler/$profile.openeuler.pkglist";
    my $custom = "$dir/custom/$profile.tmpl";
    write_text($custom, read_text($template));
    my $out = "$dir/$profile.ks";
    my $error = xCAT::Template->subvars($custom, $out, 'oe-node', $pkglist,
        '/install/custom-media,/install/supplementary', 'openeuler', undef, { xcatmaster => '192.0.2.1' });
    ok(!$error, "$profile renders with a template outside the shipped asset directory") or diag($error);
    my $ks = read_text($out);
    like($ks, qr/^network --onboot=yes --bootproto=dhcp --device=52:54:00:12:34:56 --hostname=oe-node$/m,
        "$profile renders its actual node network identity");
    like($ks, qr{url --url http://.*\$nextserver.*:8080//install/custom-media},
        "$profile generates the selected media URL with custom HTTP port");
    like($ks, qr{repo --name=pkg1 --baseurl=http://.*\$nextserver.*:8080//install/supplementary},
        "$profile includes the supplementary repository");
    like($ks, qr/^kernel$/m, "$profile includes the compute kernel package");
    like($ks, qr/^chrony$/m, "$profile includes native time support");
    like($ks, qr/^XCAT_INSTALL_PYTHON=\/usr\/bin\/python3$/m,
        "$profile selects the native installer interpreter");
    like($ks, qr/\$\{XCAT_INSTALL_PYTHON:-\/usr\/libexec\/platform-python\}/,
        "$profile executes the shared monitor with the selected interpreter");
    unlike($ks, qr/#(?:INCLUDE|TABLE|TABLEBLANKOKAY|CRYPT|ENV|XCATVAR|INSTALL_SOURCES)[^\n]*#/,
        "$profile leaves no unresolved input or repository substitutions");
    if ($profile eq 'service') {
        like($ks, qr/^perl-DBD-Pg$/m, 'service includes PostgreSQL support');
        like($ks, qr/^perl-DBD-MySQL$/m, 'service includes MySQL support');
    }
}

done_testing();
