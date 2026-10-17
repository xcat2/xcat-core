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
delete @ENV{qw(PERL5OPT PERL5LIB PERLLIB XCATROOT)};
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
my @genesis = glob "$root/xCAT-genesis-scripts/opt/xcat/share/xcat/netboot/genesis/*/fs/usr/lib/xcat/fips.sh";
is(scalar @genesis, 1, 'the Genesis package contains one standalone FIPS library')
    or die 'missing Genesis library';
my $cumulus = "$root/xCAT/install/postscripts/xcatlib.sh";
ok(-f $cumulus, 'the xCAT package contains the Cumulus library') or die 'missing postscript library';
local $ENV{XCAT_TEST_FIPS_GENESIS_LIBRARY} = $genesis[0];
local $ENV{XCAT_TEST_FIPS_CUMULUS_LIBRARY} = $cumulus;
my ($rc, $output) = run_command('prove', '-v', repo_path('xCAT-test/unit/fips_shell_runtime.t'));
is($rc, 0, 'packaged libraries pass the same real-crypto characterization') or diag($output);
unlike($output, qr/#\s*skip.*required/i,
    'runtime prerequisites are available for the packaged libraries');

done_testing();
