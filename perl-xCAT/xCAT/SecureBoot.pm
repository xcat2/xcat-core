package xCAT::SecureBoot;

use strict;
use warnings;

# The first-stage EFI binary of an install source, per architecture. copycds keeps the names that
# the DVD carries, and the distributions disagree on their case: EL and openEuler ship
# EFI/BOOT/BOOTX64.EFI, Ubuntu EFI/boot/bootx64.efi and openSUSE EFI/BOOT/bootx64.efi.
# Only x86_64 is here: the ipxe method boots x86 nodes, and the UEFI script carries a kernel that
# iPXE recognized as an x86_64 PE image.
my %INSTALL_SHIM = (
    x86_64 => [ 'EFI/BOOT/BOOTX64.EFI', 'EFI/BOOT/bootx64.efi', 'EFI/boot/bootx64.efi' ],
);

# The shim of the ipxe-xcat package. Every shim reads the MOK list from the firmware, so this one
# verifies a kernel that the site signs with a key it enrolls.
my %LOADER_SHIM = (
    x86_64 => 'xcat/ipxe/x86_64-sb/shimx64.efi',
);

# The kernel of the Genesis image, as the boot scripts name it. mknb builds it and the site signs
# it, or leaves it unsigned, so no vendor certificate of a distribution verifies it.
my $GENESIS_KERNEL = qr{(?:\A|/)genesis\.kernel\.};

#-------------------------------------------------------------------------------

=head3 shim_url_path

    Descriptions:
        The HTTP path of a shim that verifies the kernel of one node. The shim of the install
        source comes first, because its vendor certificate signs the kernel of its own
        distribution. The shim of ipxe-xcat is the answer for a kernel that the site signs
        itself, such as the Genesis kernel.

        iPXE fetches the shim only when it cannot load the kernel directly, so a node with
        Secure Boot off never reads the file.

    Arguments:
        arch        - the architecture of the node, as the nodetype table spells it
        os          - the operating system of the node, or undef for an unknown client
        kernel      - the kernel the boot script loads, relative to the TFTP root. A Genesis
                      kernel takes the shim of ipxe-xcat whatever the os of the node is.
        installroot - the install directory, /install by default
        tftpdir     - the TFTP directory of the node, /tftpboot by default

    Returns:
        The path under the document root of the xCAT web server, or undef when no shim is
        available. xcat.conf serves /install and /tftpboot at those names.

=cut

#-------------------------------------------------------------------------------
sub shim_url_path {
    my ($class, %opts) = @_;

    my $arch = $opts{arch};
    return unless defined($arch) and $INSTALL_SHIM{$arch};

    # nodeset writes the Genesis kernel into the UEFI script of a node for the shell, discover,
    # standby and runcmd destinies, beside the install source of the os of that node. The vendor
    # certificate of that install source signs its own kernel and not this one.
    my $genesis = defined($opts{kernel}) && $opts{kernel} =~ $GENESIS_KERNEL;

    if (!$genesis and defined($opts{os}) and length($opts{os})) {
        my $installroot = defined($opts{installroot}) ? $opts{installroot} : '/install';
        $installroot =~ s{/+$}{};
        foreach my $name (@{ $INSTALL_SHIM{$arch} }) {
            return "/install/$opts{os}/$arch/$name"
              if -f "$installroot/$opts{os}/$arch/$name";
        }
    }

    my $tftpdir = defined($opts{tftpdir}) ? $opts{tftpdir} : '/tftpboot';
    $tftpdir =~ s{/+$}{};
    my $loader = $LOADER_SHIM{$arch};
    return "/tftpboot/$loader" if -f "$tftpdir/$loader";
    return;
}

1;
