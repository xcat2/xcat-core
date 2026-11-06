#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use XCAT::Test::File qw(repo_path);

my $tftp = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$tftp/config";
make_path("$tftp/xcat", $ENV{XCATCFG});
require xCAT::TableUtils;
{
    no warnings qw(redefine once);
    local *xCAT::TableUtils::get_site_attribute = sub { return (0); };
    local $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
    require(repo_path('xCAT-server/lib/xcat/plugins/destiny.pm'));
}

is(
    xCAT_plugin::destiny::_genesis_boot_arch($tftp, 'ppc64le'),
    'ppc64',
    'ppc64le keeps the legacy POWER fallback when no exact image exists',
);

open(my $marker_fh, '>', "$tftp/xcat/genesis.exact-arch.ppc64")
  or die "create exact POWER marker: $!";
close($marker_fh) or die "close exact POWER marker: $!";

is(
    xCAT_plugin::destiny::_genesis_boot_arch($tftp, 'ppc64le'),
    'ppc64le',
    'ppc64le does not fall back to a canonical big-endian ppc64 image',
);
unlink("$tftp/xcat/genesis.exact-arch.ppc64")
  or die "remove exact POWER marker: $!";

open(my $kernel_fh, '>', "$tftp/xcat/genesis.kernel.ppc64le")
  or die "create exact POWER kernel: $!";
close($kernel_fh) or die "close exact POWER kernel: $!";

is(
    xCAT_plugin::destiny::_genesis_boot_arch($tftp, 'ppc64le'),
    'ppc64le',
    'ppc64le uses the exact OpenEmbedded boot artifact',
);
is(
    xCAT_plugin::destiny::_genesis_boot_arch($tftp, 'ppc64el'),
    'ppc64le',
    'the Debian spelling resolves to the exact ppc64le artifact',
);
is(xCAT_plugin::destiny::_genesis_boot_arch($tftp, 'x86_64'), 'x86_64', 'other architectures are unchanged');

# The console device of each architecture moved to xCAT::ConsolePolicy, which destiny.pm now
# calls. console_policy.t covers every architecture, aarch64 among them.

done_testing();
