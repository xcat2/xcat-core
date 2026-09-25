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
  systemd-sysv hwdata btrfs-progs netcat-openbsd iputils-ping fdisk ncurses-term
  dpkg-dev debhelper fakeroot devscripts vim-tiny
);

# Two commands the image needs changed package between releases: nslookup left dnsutils for
# bind9-dnsutils in 22.04, and hwclock left util-linux for util-linux-extra in 23.04.
my @RENAMED_PACKAGES = ([qw(bind9-dnsutils dnsutils)], [qw(util-linux-extra util-linux)]);

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
        For a renamed package, apt says which name the release carries, so the list does
        not branch on the codename. 26.04 moved the backward-compatibility zone names that
        the dracut module installs out of tzdata into tzdata-legacy.
    Arguments:
        $arch: the dpkg architecture (amd64, ppc64el)
        $codename: the release name, used in the error message
        $carries: optional code ref. It takes a package name and returns true when the
                  release carries that package. The default is apt_carries.
    Returns:
        the package names, in install order.
        Dies with "ERROR: <codename> carries none of these packages: ..." when the release
        carries neither name of a renamed package.

=cut

#-------------------------------------------------------------------------------
sub required_packages {
    my ($arch, $codename, $carries) = @_;
    $carries ||= \&apt_carries;

    my @packages = @BASE_PACKAGES;
    push @packages, qw(dmidecode efibootmgr) if $arch eq 'amd64';

  RENAMED:
    for my $alternatives (@RENAMED_PACKAGES) {
        for my $package (@$alternatives) {
            if ($carries->($package)) {
                push @packages, $package;
                next RENAMED;
            }
        }
        die "ERROR: $codename carries none of these packages: @$alternatives\n";
    }
    push @packages, 'tzdata-legacy' if $carries->('tzdata-legacy');
    return @packages;
}

1;
