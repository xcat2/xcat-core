#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# nodediscover sets noderes.netboot for a freshly discovered node when the
# admin did not pick a method that fits the reported architecture. The ladder
# lives in _default_netboot() so it can be checked without a database: stub
# the modules the plugin loads at compile time and call the helper directly.

BEGIN {
    package xCAT::Table;
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package XML::Simple;
    sub import { }
    $INC{'XML/Simple.pm'} = __FILE__;

    package xCAT::data::switchinfo;
    our %global_mac_identity;
    $INC{'xCAT/data/switchinfo.pm'} = __FILE__;

    package xCAT::DiscoveryUtils;
    $INC{'xCAT/DiscoveryUtils.pm'} = __FILE__;
}

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/nodediscover.pm');
plan skip_all => "$plugin not found" unless -r $plugin;

require $plugin;

my $warnings = 0;
local $SIG{__WARN__} = sub { $warnings++; diag(@_) };

sub default_netboot {
    return xCAT_plugin::nodediscover::_default_netboot(@_);
}

# riscv64: UEFI + grub2 only
is( default_netboot( 'riscv64', '', '' ),           'grub2', 'riscv64 nodes default to grub2' );
is( default_netboot( 'riscv64', undef, undef ),     'grub2', 'riscv64 defaults to grub2 when no platform or netboot was reported' );
is( default_netboot( 'riscv64', '', 'xnba' ),       'grub2', 'a riscv64 node with an x86 method is corrected to grub2' );
is( default_netboot( 'riscv64', '', 'grub2' ),      undef,   'riscv64 keeps an explicit grub2 method' );
is( default_netboot( 'riscv64', '', 'grub2-http' ), undef,   'riscv64 keeps grub2-http' );
is( default_netboot( 'riscv64', '', 'grub2-tftp' ), undef,   'riscv64 keeps grub2-tftp' );
is( default_netboot( 'riscv32', '', '' ),           undef,   'riscv32 is not treated as riscv64' );

# existing architectures keep their behavior
is( default_netboot( 'x86_64', '', '' ),       'xnba',      'x86_64 nodes default to xnba' );
is( default_netboot( 'x86_64', '', 'pxe' ),    undef,       'x86_64 keeps pxe' );
is( default_netboot( 'x86_64', '', 'xnba' ),   undef,       'x86_64 keeps xnba' );
is( default_netboot( 'x86', '', 'grub2' ),     'xnba',      'x86 with a non-x86 method is corrected to xnba' );
is( default_netboot( 'ppc64le', 'PowerNV', '' ),          'petitboot', 'PowerNV nodes default to petitboot' );
is( default_netboot( 'ppc64le', 'PowerNV', 'petitboot' ), 'petitboot', 'PowerNV nodes are always set to petitboot' );
is( default_netboot( 'ppc64', 'pSeries', '' ),        'yaboot', 'non-PowerNV ppc nodes default to yaboot' );
is( default_netboot( 'ppc64', 'pSeries', 'yaboot' ),  undef,    'ppc nodes keep yaboot' );
is( default_netboot( 'armv7l', '', '' ),      'onie', 'armv7l switches default to onie' );
is( default_netboot( 'armv7l', '', 'onie' ),  undef,  'armv7l keeps onie' );
is( default_netboot( 'aarch64', '', '' ),     undef,  'aarch64 is left untouched, as before' );
is( default_netboot( undef, undef, undef ),   undef,  'a missing arch sets nothing' );

is( $warnings, 0, 'no warnings were emitted for undefined inputs' );

# The discovery request is stored as discovery data key by key, so reading the platform
# of a node that never reported one must not add the key to the request.
my $source = slurp_repo_file('xCAT-server/lib/xcat/plugins/nodediscover.pm');
like(
    $source,
    qr/my \$platform = exists \$request->\{platform\} \? \$request->\{platform\}->\[0\] : undef;/,
    'the netboot ladder only reads the platform of a request that carries one',
);
unlike(
    $source,
    qr/_default_netboot\(\s*\$request->\{arch\}->\[0\],\s*\$request->\{platform\}->\[0\]/,
    'the netboot ladder does not autovivify the platform key of the discovery request',
);

done_testing();
