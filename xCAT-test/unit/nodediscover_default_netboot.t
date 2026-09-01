#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

# nodediscover sets noderes.netboot for a freshly discovered node when the
# admin did not pick a method that fits the reported architecture. The ladder
# lives in _default_netboot() so it can be checked without a database: stub
# the modules the plugin loads at compile time and call the helper directly.

BEGIN {
    package xCAT::Table;
    sub new {
        my ( $class, $name ) = @_;
        return bless { name => $name }, 'Local::DiscoveryTable';
    }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package Local::DiscoveryTable;
    our @writes;
    sub getNodeAttribs { return {}; }
    sub setNodeAttribs {
        my ( $self, $node, $attrs ) = @_;
        push @writes, [ $self->{name}, $node, { %{$attrs} } ];
        return;
    }
    sub close  { return; }
    sub commit { return; }

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

# Discovery data are later stored key by key. Exercise the real request path to
# prove that an absent platform is not added while selecting the netboot method.
@Local::DiscoveryTable::writes = ();
my $request = {
    node => ['node1'],
    arch => ['riscv64'],
};
my @callbacks;
xCAT_plugin::nodediscover::process_request(
    $request,
    sub { push @callbacks, @_ },
    sub { },
);
ok( !exists $request->{platform}, 'discovery does not add a missing platform to the request' );
ok(
    scalar( grep {
        $_->[0] eq 'noderes'
          && $_->[1] eq 'node1'
          && $_->[2]->{netboot} eq 'grub2'
    } @Local::DiscoveryTable::writes ),
    'the request path applies the riscv64 grub2 default',
);
is( scalar @callbacks, 1, 'the isolated request stops at the missing client address boundary' );

done_testing();
