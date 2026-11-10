IPv6 provisioning
=================

xCAT provisions a node over an IPv6-only network. The management node answers DHCPv6,
serves the boot loader over TFTP, and serves the installer and the kickstart or AutoYaST
profile over HTTP. The node needs no IPv4 address on the provisioning network.

Requirements
------------

**The node must use a grub2 or an iPXE boot loader.** Only ``netboot=grub2``,
``grub2-http``, ``grub2-tftp`` and ``ipxe`` get a ``bootfile-url`` in their DHCPv6
reservation. A node with ``netboot=pxe``, ``xnba`` or ``petitboot`` receives an address
but no boot file, so it does not netboot over IPv6.

**A grub2 node must boot UEFI with Secure Boot disabled.** The grub2 image under
``/tftpboot/boot/grub2`` is not signed. Firmware that enforces Secure Boot downloads the
image and then refuses to start it::

    NBP file downloaded successfully.
    BdsDxe: failed to load Boot0004 "UEFI PXEv6" : Access Denied

This is a constraint of grub2, not of IPv6. On x86_64 use ``netboot=ipxe``: ``ipxe-xcat``
installs ``xcat/ipxe/x86_64-sb/snponly-shim.efi``, which Microsoft signs, so the node boots
with Secure Boot on. ``netboot=grub2`` does not boot an x86_64 node at all, because no
package installs an x86_64 grub2 image. On ppc64le, aarch64 and riscv64, grub2 is the only
method and Secure Boot must be off.

**The node must resolve only to its IPv6 address.** xCAT installs a node over IPv4 when the
node name also resolves to an IPv4 address. After ``chdef <node> ip=<IPv6 address>``, run
``makehosts <node>``: it replaces the IPv4 line of the node in ``/etc/hosts``. A node that
already has a line of each family is dual-stack, and ``makehosts`` keeps both lines. To move
such a node to IPv6 only, run ``makehosts -d <node>`` and then ``makehosts <node>``.

The DHCPv6 client identifier
----------------------------

A DHCPv6 reservation matches a client identifier (DUID), not a MAC address. xCAT predicts
the DUID from ``vpd.uuid`` as a DUID-UUID (RFC 6355): the type ``00:04`` followed by the 16
bytes of the UUID.

UEFI firmware built on EDK2 copies the UUID out of SMBIOS without changing the byte order.
SMBIOS 2.6 and later store the first three fields of the UUID little-endian, so the DUID
that the firmware sends holds those fields in that order. This is what ``makedhcp`` writes
by default.

The operating system reports the UUID in RFC 4122 order, so a DHCPv6 client in the
installed system can build a different DUID from the same hardware and miss the
reservation. The ``configdhcpv6duid`` postscript prevents this: it writes the DUID that
xCAT reserved into the network configuration of the node, for NetworkManager and for
systemd-networkd.

Use ``mac.duid`` to select a different identifier. The ``mac`` table man page lists the
values it accepts.

The handoff to the installer
----------------------------

On EL 10 and on openEuler, ``nodeset`` writes the address on the kernel command line, so
the installer does not repeat the DHCPv6 exchange::

    ip=[2001:db8:149::10]::[2001:db8:149::1]:64:node01:xcatboot0:none

The final ``none`` turns off DHCPv6 in the initrd. The node keeps the address that
``makedhcp`` reserved for it through the whole installation.

Other families hand off differently, and a node that runs its own DHCPv6 client sends a
DUID that ``makedhcp`` did not reserve. Such a client takes an address from the dynamic
range, so the range is required.

================  =========================================================================
Family            Handoff to the installer
================  =========================================================================
EL 8 and later    ``ip=`` with the address, from ``uses_static_ipv6_boot``
openEuler         ``ip=`` with the address, from ``uses_static_ipv6_boot``
Ubuntu, diskless  ``ip=`` with the address, from ``dracut_static_ip6``
Ubuntu, diskful   ``ip6=dhcp``, and casper runs ``dhcpcd -6`` as a third client
SLES, openSUSE    ``ipv6only=1 hostip=<address>/<prefix>``, from ``static_ipv6_boot_args``
================  =========================================================================
