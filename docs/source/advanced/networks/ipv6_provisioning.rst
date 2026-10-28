IPv6 provisioning
=================

xCAT provisions a node over an IPv6-only network. The management node answers DHCPv6,
serves the boot loader over TFTP, and serves the installer and the kickstart or AutoYaST
profile over HTTP. The node needs no IPv4 address on the provisioning network.

Requirements
------------

**The node must use a grub2 boot loader.** Only ``netboot=grub2``, ``grub2-http`` and
``grub2-tftp`` get a ``bootfile-url`` in their DHCPv6 reservation. A node with
``netboot=pxe``, ``xnba``, ``ipxe`` or ``petitboot`` receives an address but no boot file,
so it does not netboot over IPv6.

**The node must boot UEFI with Secure Boot disabled.** The grub2 image under
``/tftpboot/boot/grub2`` is not signed. Firmware that enforces Secure Boot downloads the
image and then refuses to start it::

    NBP file downloaded successfully.
    BdsDxe: failed to load Boot0004 "UEFI PXEv6" : Access Denied

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

``nodeset`` writes the address on the kernel command line, so the installer does not
repeat the DHCPv6 exchange::

    ip=[2001:db8:149::10]::[2001:db8:149::1]:64:node01:xcatboot0:none

The final ``none`` turns off DHCPv6 in the initrd. The node keeps the address that
``makedhcp`` reserved for it through the whole installation.
