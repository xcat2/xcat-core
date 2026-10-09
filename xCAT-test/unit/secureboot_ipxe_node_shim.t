#!/usr/bin/env perl
# A UEFI node with netboot=ipxe loads the shim that Microsoft signs, so it reaches iPXE with Secure
# Boot on and stops at the kernel. Its boot script must name a shim that verifies that kernel.
# nodeset writes the scripts through the real plugins into a scratch TFTP root. Tables, name
# resolution and the destiny subrequest are stand-ins.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_binary);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo        = "$FindBin::Bin/../..";
my $tftp        = tempdir( CLEANUP => 1 );
my $installroot = tempdir( CLEANUP => 1 );
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
    sub getTftpDir     { return $tftp }
    sub getInstallDir  { return $installroot }
    sub get_site_attribute { return $_[1] eq 'dhcpsetup' ? ('n') : () }    # no makedhcp from nodeset

    package xCAT::MsgUtils;
    sub trace   { return }
    sub message { return }

    package main;
    for my $module (qw(Table NetworkUtils TableUtils MsgUtils Utils NodeRange Scope ServiceNodeUtils Usage BootUtils)) {
        $INC{"xCAT/$module.pm"} = __FILE__;
    }
}

# xcatd loads the plugins from their files, and ipxe.pm requires xnba.pm by module name.
my $inc = tempdir( CLEANUP => 1 );
symlink( "$repo/xCAT-server/lib/xcat/plugins", "$inc/xCAT_plugin" ) or die "symlink: $!";
unshift @INC, $inc, "$repo/xCAT-server/lib/perl", "$repo/perl-xCAT";
require xCAT_plugin::ipxe;

# iPXE boots a kernel that carries an EFI stub as an EFI image, which is the path the shim verifies.
# xnba.pm reads the PE header of the file to recognize it.
sub kernel_with_efistub {
    my ($relative) = @_;
    ( my $dir = "$tftp/$relative" ) =~ s{/[^/]+$}{};
    make_path($dir);
    write_binary( "$tftp/$relative", "MZ" . ( "\0" x 64 ) . pack( 'H*', '504500006486' ) );
    return $relative;
}

sub install_source {
    my ( $os, $arch, @shims ) = @_;
    for my $shim (@shims) {
        ( my $dir = "$installroot/$os/$arch/$shim" ) =~ s{/[^/]+$}{};
        make_path($dir);
        write_binary( "$installroot/$os/$arch/$shim", 'shim' );
    }
    return;
}

sub nodeset {
    my ( $plugin, $node, %attrib ) = @_;
    $rows{noderes}{$node} = { tftpdir => $tftp, netboot => $plugin };
    $rows{chain}{$node} =
      { currstate => $attrib{currstate} || 'install rhels9-x86_64-compute' };
    $rows{nodetype}{$node} = {
        provmethod => exists( $attrib{provmethod} ) ? $attrib{provmethod} : 'install',
        os         => $attrib{os},
        arch       => $attrib{arch},
    };
    my $subreq = sub {
        my ($request) = @_;
        $request->{bootparams}{$node} = [ { map { $_ => $attrib{$_} } qw(kernel initrd kcmdline) } ]
          if $request->{command}[0] eq 'setdestiny';
        return;
    };
    "xCAT_plugin::$plugin"->can('process_request')
      ->( { command => ['nodeset'], node => [$node], arg => ['osimage'] }, sub { }, $subreq );
    return;
}

sub script {
    my ($relative) = @_;
    return -f "$tftp/$relative" ? read_text("$tftp/$relative") : '';
}

sub ipxe_shim_line {
    my ($path) = @_;
    return qr{^imgload kernel\nshim http://\$\{next-server\}\Q$path\E$}m;
}

# An EL install source: copycds keeps the upper-case names of the DVD.
install_source( 'alma9.8', 'x86_64', 'EFI/BOOT/BOOTX64.EFI' );
nodeset(
    ipxe => 'cn01',
    os   => 'alma9.8', arch => 'x86_64',
    kernel => kernel_with_efistub('xcat/osimage/alma9.8-install/vmlinuz'),
    initrd => 'xcat/osimage/alma9.8-install/initrd.img', kcmdline => 'quiet',
);
like(
    script('xcat/ipxe/nodes/cn01.uefi'),
    ipxe_shim_line('/install/alma9.8/x86_64/EFI/BOOT/BOOTX64.EFI'),
    'the UEFI script of an ipxe node names the shim of its install source, after it selects the kernel'
);
like( script('xcat/ipxe/nodes/cn01.uefi'), qr{^shim \S+\nimgargs kernel }m,
    'and names it before the kernel runs' );
unlike( script('xcat/ipxe/nodes/cn01'), qr{^shim }m,
    'the BIOS script of the same node names no shim' );

# An Ubuntu install source: the same files, in lower case.
install_source( 'ubuntu24.04.4', 'x86_64', 'EFI/boot/bootx64.efi' );
nodeset(
    ipxe => 'cn02',
    os   => 'ubuntu24.04.4', arch => 'x86_64',
    kernel => kernel_with_efistub('xcat/osimage/ubuntu24.04.4-install/vmlinuz'),
    initrd => 'xcat/osimage/ubuntu24.04.4-install/initrd.img', kcmdline => 'quiet',
);
like(
    script('xcat/ipxe/nodes/cn02.uefi'),
    ipxe_shim_line('/install/ubuntu24.04.4/x86_64/EFI/boot/bootx64.efi'),
    'an install source that names the shim in lower case is found as well'
);

# No install source for this node. ipxe-xcat always installs its own Secure Boot shim, and every
# shim reads the MOK list from the firmware.
make_path("$tftp/xcat/ipxe/x86_64-sb");
write_binary( "$tftp/xcat/ipxe/x86_64-sb/shimx64.efi", 'shim' );
nodeset(
    ipxe => 'cn03',
    os   => 'alma10.1', arch => 'x86_64',
    kernel => kernel_with_efistub('xcat/osimage/alma10.1-install/vmlinuz'),
    initrd => 'xcat/osimage/alma10.1-install/initrd.img', kcmdline => 'quiet',
);
like(
    script('xcat/ipxe/nodes/cn03.uefi'),
    ipxe_shim_line('/tftpboot/xcat/ipxe/x86_64-sb/shimx64.efi'),
    'a node whose install source carries no shim falls back to the shim of ipxe-xcat'
);

# The vendor certificate of the distribution shim signs the kernel of that distribution, so the
# install source answers before the shim of ipxe-xcat.
nodeset(
    ipxe => 'cn07',
    os   => 'alma9.8', arch => 'x86_64',
    kernel => kernel_with_efistub('xcat/osimage/alma9.8-again/vmlinuz'),
    initrd => 'xcat/osimage/alma9.8-again/initrd.img', kcmdline => 'quiet',
);
like(
    script('xcat/ipxe/nodes/cn07.uefi'),
    ipxe_shim_line('/install/alma9.8/x86_64/EFI/BOOT/BOOTX64.EFI'),
    'the install source answers even when the shim of ipxe-xcat is also on disk'
);

# The shell, discover, standby and runcmd destinies load the Genesis kernel through the same UEFI
# script. No distribution signs that kernel, so the vendor certificate of an install source cannot
# verify it and only the shim of ipxe-xcat can. cn08 keeps the install source of cn01, which does
# carry a shim.
nodeset(
    ipxe       => 'cn08',
    os         => 'alma9.8', arch => 'x86_64',
    currstate  => 'shell',
    provmethod => '',
    kernel     => kernel_with_efistub('xcat/genesis.kernel.x86_64'),
    initrd     => 'xcat/genesis.fs.x86_64.gz', kcmdline => 'quiet destiny=shell',
);
like(
    script('xcat/ipxe/nodes/cn08.uefi'),
    ipxe_shim_line('/tftpboot/xcat/ipxe/x86_64-sb/shimx64.efi'),
    'a node that loads the Genesis kernel names the shim of ipxe-xcat'
);
unlike( script('xcat/ipxe/nodes/cn08.uefi'), qr{^shim \S*/install/}m,
    'and never the shim of an install source, which signs no Genesis kernel' );

# ppc64le has no UEFI shim, and netboot=xnba loads an unsigned loader that Secure Boot refuses.
nodeset(
    ipxe => 'cn04',
    os   => 'alma9.8', arch => 'ppc64le',
    kernel => kernel_with_efistub('xcat/osimage/alma9.8-ppc/vmlinuz'),
    initrd => 'xcat/osimage/alma9.8-ppc/initrd.img', kcmdline => 'quiet',
);
unlike( script('xcat/ipxe/nodes/cn04.uefi'), qr{^shim }m, 'a ppc64le node names no shim' );

nodeset(
    xnba => 'cn05',
    os   => 'alma9.8', arch => 'x86_64',
    kernel => kernel_with_efistub('xcat/osimage/alma9.8-install/vmlinuz'),
    initrd => 'xcat/osimage/alma9.8-install/initrd.img', kcmdline => 'quiet',
);
unlike( script('xcat/xnba/nodes/cn05.uefi'), qr{^shim }m, 'an xnba node names no shim' );

# Without an EFI stub the UEFI script chains elilo, which no key signs.
nodeset(
    ipxe => 'cn06',
    os   => 'alma9.8', arch => 'x86_64',
    kernel => 'xcat/osimage/alma9.8-noefi/vmlinuz',
    initrd => 'xcat/osimage/alma9.8-noefi/initrd.img', kcmdline => 'quiet',
);
like( script('xcat/ipxe/nodes/cn06.uefi'), qr{elilo-x64\.efi}, 'a kernel without an EFI stub keeps the elilo chain' );
unlike( script('xcat/ipxe/nodes/cn06.uefi'), qr{^shim }m, 'and names no shim' );

done_testing();
