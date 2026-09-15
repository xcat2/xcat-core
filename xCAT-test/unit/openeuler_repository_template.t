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
make_path("$dir/db", "$dir/install", "$dir/media/repodata", "$dir/media/extra/repodata");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Table;
require xCAT::Yum;
require xCAT::Template;
my %site_values = (installdir => "$dir/install", timezone => 'UTC', master => '192.0.2.1',
    httpport => 8080, nodestatus => 1, xcatdebugmode => 0, xcatiport => 3002, xcatdport => 3001);
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %site_values) {
    $site->setAttribs({ key => $key }, { value => $site_values{$key} });
}
$site->close();
%::XCATSITEVALS = (%site_values, secureroot => 1, managedaddressmode => 'dhcp');
my $noderes = xCAT::Table->new('noderes', -create => 1);
$noderes->setAttribs({ node => 'oe-node' }, { xcatmaster => '192.0.2.1', nfsserver => '192.0.2.1' });
$noderes->close();

write_text("$dir/input.tmpl", "#INSTALL_SOURCES#\n#WRITEREPO#\n");
for my $case (['openeuler24.03sp3', 'openeuler'], ['rhels9.6', 'rh']) {
    my ($os, $platform) = @$case;
    xCAT::Yum->localize_yumrepo("$dir/media", $os, 'x86_64');
    my $path = "$dir/install/postscripts/repos/$dir/media/local-repository.tmpl";
    ok(-s $path, "$os localizes repositories under the configured install directory");
    my $repo = read_text($path);
    my @sections = $repo =~ /^\[([^\]]+)\]/mg;
    is(scalar(@sections), 2, "$os preserves both media repository roots");
    like($repo, qr{^baseurl=\Q$dir\E/media\n}m, "$os retains the selected media path");
    like($repo, qr{^baseurl=\Q$dir\E/media/extra\n}m, "$os retains the nested repository");
    if ($platform eq 'openeuler') {
        is(scalar(() = $repo =~ /^gpgcheck=1$/mg), 2, 'every native repository verifies RPM signatures');
        is(scalar(() = $repo =~ /^skip_if_unavailable=False$/mg), 2, 'every native repository is required');
        unlike($repo, qr/gpgcheck=0/, 'localization does not disable native signatures');
    } else {
        is(scalar(() = $repo =~ /^gpgcheck=0$/mg), 2, 'legacy repository signature policy is preserved');
        unlike($repo, qr/skip_if_unavailable=/, 'legacy repository availability policy is preserved');
    }
    my $error = xCAT::Template->subvars("$dir/input.tmpl", "$dir/$os.ks", 'oe-node',
        undef, "$dir/media", $platform, undef, { xcatmaster => '192.0.2.1' });
    ok(!$error, "$os renders the localized repository through the production template") or diag($error);
    my $ks = read_text("$dir/$os.ks");
    like($ks, qr{cat >/etc/yum\.repos\.d/local-repository-0\.repo},
        "$os emits the repository for the installed system");
    like($ks, qr{baseurl=http://192\.0\.2\.1:8080/\Q$dir\E/media\n},
        "$os retains the custom HTTP port and package path");
    is(scalar(() = $ks =~ /^gpgcheck=1$/mg), 2, 'rendering retains both native signature checks')
      if $platform eq 'openeuler';
    xCAT::Yum->remove_yumrepo("$dir/media");
    ok(!-e $path, "$os removes the localized repository from the configured install directory");
}
done_testing();
