package XCAT::GenesisBuildRoot;

# builddeb-genesis-base runs this module inside an Ubuntu build root, where only perl-base is
# installed. Use core modules only.
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(required_packages apt_carries);

my @BASE_PACKAGES = qw(
  dracut linux-image-generic
  ipmitool lldpad ethtool iproute2 kexec-tools screen
  openssh-server openssh-client rsyslog chrony
  nfs-common rpcbind pciutils usbutils parted
  dosfstools e2fsprogs lvm2 mdadm net-tools
  bc psmisc rsync wget cpio
  isc-dhcp-client ifenslave
  dpkg-dev debhelper fakeroot devscripts vim-tiny
);

# hwclock moved out of util-linux into util-linux-extra. focal and jammy have no such package,
# and naming it there fails the whole install. util-linux only Suggests it, and the build
# passes --no-install-recommends, so the releases that split it must name it.
my @OPTIONAL_PACKAGES = qw(util-linux-extra);

#-------------------------------------------------------------------------------

=head3 apt_carries

    Descriptions: ask apt-cache whether the release carries a package.
    Arguments:
        $package: the package name
    Returns:
        1 when apt-cache knows the package, 0 when it does not

=cut

#-------------------------------------------------------------------------------
sub apt_carries {
    my ($package) = @_;
    return system('sh', '-c', 'apt-cache show "$1" >/dev/null 2>&1', 'sh', $package) == 0
      ? 1 : 0;
}

#-------------------------------------------------------------------------------

=head3 required_packages

    Descriptions: list the packages the Genesis build root needs.
        An optional package is listed only when the release carries it.
    Arguments:
        $arch: the dpkg architecture (amd64, ppc64el)
        $codename: the release name
        $carries: optional code ref. It takes a package name and returns true when the
                  release carries that package. The default is apt_carries.
    Returns:
        the package names, in install order.

=cut

#-------------------------------------------------------------------------------
sub required_packages {
    my ($arch, $codename, $carries) = @_;
    $carries ||= \&apt_carries;

    my @packages = @BASE_PACKAGES;
    push @packages, qw(dmidecode efibootmgr) if $arch eq 'amd64';
    push @packages, grep { $carries->($_) } @OPTIONAL_PACKAGES;
    return @packages;
}

1;
