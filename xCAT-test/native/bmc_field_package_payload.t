#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use XCAT::Test::Lifecycle;
use XCAT::Test::RPM;

plan skip_all => 'requires Linux package tools' unless $^O eq 'linux';
die 'run package builds as an ordinary user' unless $>;
my $root = tempdir(CLEANUP => 1);
make_path("$root/home");
local %ENV = (%ENV, HOME => "$root/home", LC_ALL => 'C');
delete @ENV{qw(PERL5OPT PERL5LIB PERLLIB XCATROOT XCAT_TEST_BMCSETUP)};
my $format = -f '/etc/debian_version' ? 'deb' : 'rpm';
for my $package (qw(xCAT xCAT-genesis-scripts)) {
    my $artifact = $format eq 'deb' ? XCAT::Test::Lifecycle::build_deb($package)
        : XCAT::Test::RPM->build($package, 1, '--define', 'rhel 9');
    make_path("$root/$package");
    if ($format eq 'deb') {
        XCAT::Test::Lifecycle::checked('dpkg-deb', '-x', $artifact, "$root/$package");
    } else {
        XCAT::Test::Lifecycle::checked('bash', '-o', 'pipefail', '-c',
            'cd "$1" && rpm2cpio "$2" | cpio -idm --quiet',
            'extract-package', "$root/$package", $artifact);
    }
}
my @genesis = glob "$root/xCAT-genesis-scripts/opt/xcat/share/xcat/netboot/genesis/*/fs/usr/bin/bmcsetup";
is(scalar @genesis, 1, 'the package contains one Genesis BMC script')
    or die 'missing Genesis script';
my $postscript = "$root/xCAT/install/postscripts/bmcsetup";
ok(-f $postscript, 'the xCAT package contains the BMC postscript') or die 'missing postscript';
for my $script ($genesis[0], $postscript) {
    local $ENV{XCAT_TEST_BMCSETUP} = $script;
    my ($rc, $output) = run_command('bats', '--tap',
        repo_path('xCAT-test/bats/genesis_bmcsetup_users.bats'));
    is($rc, 0, "$script preserves field parsing and command behavior") or diag($output);
    like($output, qr/^1\.\.12$/m, 'all common characterization cases ran');
    unlike($output, qr/#\s*skip/i, 'no packaged-script case was skipped');
}
{
    local $ENV{XCAT_TEST_BMCSETUP} = $postscript;
    my ($rc, $output) = run_command('bats', '--tap',
        repo_path('xCAT-test/bats/genesis_bmcsetup_ipv6.bats'));
    is($rc, 0, 'a postscript override leaves Genesis-only cases on Genesis') or diag($output);
    like($output, qr/^1\.\.14$/m, 'all Genesis-specific cases ran');
    unlike($output, qr/#\s*skip/i, 'no Genesis-specific case was skipped');
}
done_testing();
