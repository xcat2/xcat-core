#!/usr/bin/env perl
# netboot=ipxe runs the boot scripts of the xnba method under xcat/ipxe/nodes, and netboot=xnba keeps
# them under xcat/xnba/nodes. nodeset writes them through the real plugins, and the nodeset state
# comes back through SvrUtils, into a scratch TFTP root. Tables, name resolution and the destiny
# subrequest are stand-ins.
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo = "$FindBin::Bin/../..";
my $tftp = tempdir( CLEANUP => 1 );
our %rows;

BEGIN {
    package xCAT::Table;
    sub new { my ( $class, $table ) = @_; return bless { table => $table }, $class }
    sub getNodesAttribs {
        my ( $self, $nodes ) = @_;
        return { map { $_ => [ $main::rows{ $self->{table} }{$_} ] } @$nodes };
    }
    sub getNodeAttribs { my ( $self, $node ) = @_; return $main::rows{ $self->{table} }{$node} }
    sub getAttribs { return }
    sub close      { return }

    package xCAT::NetworkUtils;
    sub determinehostname  { return ('mn') }
    sub checkNodeIPaddress { return { ip => '192.0.2.10' } }
    sub nodeonmynet        { return 1 }

    package xCAT::TableUtils;
    sub getTftpDir         { return $tftp }
    sub get_site_attribute { return $_[1] eq 'dhcpsetup' ? ('n') : () }    # no makedhcp from nodeset here

    package xCAT::MsgUtils;
    sub trace   { return }
    sub message { return }

    package main;
    for my $module (qw(Table NetworkUtils TableUtils MsgUtils Utils NodeRange Scope ServiceNodeUtils Usage BootUtils)) {
        $INC{"xCAT/$module.pm"} = __FILE__;
    }
}

# xcatd loads the plugins from their files. SvrUtils loads them by module name, so xCAT_plugin names
# the plugin directory of this checkout.
my $inc = tempdir( CLEANUP => 1 );
symlink( "$repo/xCAT-server/lib/xcat/plugins", "$inc/xCAT_plugin" ) or die "symlink: $!";
unshift @INC, $inc, "$repo/xCAT-server/lib/perl", "$repo/perl-xCAT";
require xCAT_plugin::ipxe;
require xCAT::SvrUtils;

# What setdestiny leaves for each node: its currstate, and the kernel that bootparams names.
sub nodeset {
    my ( $plugin, $node, %kernel ) = @_;
    $rows{noderes}{$node}  = { tftpdir => $tftp, netboot => $plugin };
    $rows{chain}{$node}    = { currstate => "install rhels9-x86_64-compute" };
    $rows{nodetype}{$node} = { provmethod => 'install' };
    my @calls;
    my $subreq = sub {
        my ($request) = @_;
        push @calls, $request->{command}[0];
        $request->{bootparams}{$node} = [ {%kernel} ] if $request->{command}[0] eq 'setdestiny';
        return;
    };
    "xCAT_plugin::$plugin"->can('process_request')->(
        { command => ['nodeset'], node => [$node], arg => ['osimage'] }, sub { }, $subreq );
    return @calls;
}

sub content {
    my ($path) = @_;
    open( my $fh, '<', "$tftp/$path" ) or return;
    local $/;
    return <$fh>;
}

my %linux = ( kernel => 'xcat/osimage/vmlinuz', initrd => 'xcat/osimage/initrd.img', kcmdline => 'quiet' );

ok( ( grep { $_ eq 'setdestiny' } nodeset( ipxe => 'cn01', %linux ) ), 'nodeset for an ipxe node runs its destiny' );
like( content('xcat/ipxe/nodes/cn01'), qr{imgfetch -n kernel http://\$\{next-server\}/tftpboot/xcat/osimage/vmlinuz},
    'the ipxe method writes the BIOS boot script under xcat/ipxe/nodes' );
# Without an EFI stub in the kernel, UEFI boots through elilo, which reads its configuration beside
# the script.
like( content('xcat/ipxe/nodes/cn01.uefi'), qr{-C /tftpboot/xcat/ipxe/nodes/cn01\.elilo$}m,
    'the UEFI boot script beside it points elilo at xcat/ipxe/nodes' );
like( content('xcat/ipxe/nodes/cn01.elilo'), qr{image=/tftpboot/xcat/osimage/vmlinuz}, 'where the ipxe method writes it' );
ok( !-e "$tftp/xcat/xnba/nodes/cn01", 'and nothing under xcat/xnba/nodes' );

nodeset( xnba => 'cn02', %linux );
ok( -e "$tftp/xcat/xnba/nodes/cn02" && !-e "$tftp/xcat/ipxe/nodes/cn02",
    'an xnba node keeps its boot script under xcat/xnba/nodes after an ipxe node' );

# A kernel that iPXE cannot run chains pxelinux, which reads its configuration beside the script.
nodeset( ipxe => 'cn03', kernel => 'xcat/tools/memdisk', initrd => 'xcat/tools/disk.img' );
like( content('xcat/ipxe/nodes/cn03'), qr{set 209:string xcat/ipxe/nodes/cn03\.pxelinux},
    'pxelinux of an ipxe node reads its configuration from xcat/ipxe/nodes' );
ok( -e "$tftp/xcat/ipxe/nodes/cn03.pxelinux", 'where the ipxe method writes that configuration' );

# nodeset stat reads the state that the boot script records, not the chain table.
$rows{chain}{$_} = { currstate => 'boot' } for qw(cn01 cn02);
my %states;
my ($rc) = xCAT::SvrUtils->getNodesetStates( [qw(cn01 cn02)], \%states );
is( $rc, 0, 'SvrUtils reads the nodeset state of ipxe and xnba nodes' );
is_deeply( [ sort @{ $states{install} || [] } ], [qw(cn01 cn02)], 'both nodes report the state their script records' );
is( xCAT::SvrUtils->get_nodeset_state( 'cn01', global_tab_hash => { noderes => { cn01 => $rows{noderes}{cn01} } } ),
    'install', 'and the state of one ipxe node' );

done_testing();
