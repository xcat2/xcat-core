
######
mknb.8
######

.. highlight:: perl


****
NAME
****


\ **mknb**\  - creates a network boot root image for node discovery and flashing


********
SYNOPSIS
********


\ **mknb**\  \ *arch*\

\ **mknb**\  \ *arch*\  \ **-**\ **-remove-openembedded**\


***********
DESCRIPTION
***********


The \ **mknb**\  command is run by xCAT automatically when xCAT is installed on the management node.
It creates a network boot root image (used for node discovery, BMC programming, and flashing)
for the same architecture that the management node is.  So you normally do not need to run the
\ **mknb**\  command yourself.

If you make custom changes to the network boot root image, run \ **mknb**\  again to regenerate it. In an xCAT hierarchical cluster where service nodes have local \ ``/tftpboot``\  directories (\ ``site.sharedtftp=0``\ ), install and refresh an OpenEmbedded image on the service nodes before the management node starts using its exact architecture name. Legacy images must still be copied to each service node.

An OpenEmbedded Genesis package installs an exported image under \ ``/opt/xcat/share/xcat/netboot/genesis-openembedded/ARCH``\ . \ **mknb**\  prefers that image when it is installed. Otherwise it uses the old image under \ ``/opt/xcat/share/xcat/netboot/genesis/ARCH``\ .

An export is identified by \ ``xcat-genesis.manifest``\ , which records its format version and architecture. The directory also contains \ ``kernel``\ , \ ``initramfs.cpio.gz``\ , and \ ``SHA256SUMS``\ . \ **mknb**\  verifies the manifest and both boot files before publishing them under the configured TFTP root. An incomplete or invalid export leaves the current boot files unchanged. The legacy \ ``fs/``\  layout remains supported and is packed locally.

When multiple IPv4 addresses are configured for the same network, \ **mknb**\  uses a locally assigned \ ``site.master``\  for the xcatd endpoint, or the first address reported by the operating system when \ ``site.master``\  is not local. POWER discovery configurations also use this address for their kernel and initrd URLs.

OpenEmbedded images use the exact architecture names \ ``x86``\ , \ ``x86_64``\ , \ ``ppc64``\ , \ ``ppc64le``\ , \ ``armv7hf``\ , \ ``aarch64``\ , and \ ``riscv64``\ . If an OpenEmbedded \ ``ppc64le``\  image is not installed, \ **mknb**\  keeps the old behavior and uses the legacy \ ``ppc64``\  image.

Canonical \ ``ppc64``\  images are big-endian. xCAT marks them so \ ``ppc64le``\  nodes do not use them as a legacy little-endian fallback. \ **mknb**\  also refuses to replace a marked \ ``ppc64``\  image with that fallback.

riscv64 nodes boot through UEFI firmware and grub2. For riscv64, \ **mknb**\  publishes the Genesis kernel and initramfs and writes one grub2 configuration per network under ``/tftpboot/boot/grub2``, named ``grub.cfg-`` followed by the network hex prefix, so that ``grub2.riscv64`` loaded by the firmware can start node discovery. The per-node files written by \ **nodeset**\  take priority over these network files. Networks served by a ``:noboot`` interface in ``site.dhcpinterfaces`` get no discovery configuration.


*******
OPTIONS
*******



\ *arch*\

 The hardware architecture for which to build the boot image.



\ **-**\ **-remove-openembedded**\

 Remove the published boot files for the selected OpenEmbedded architecture. Image packages use this option when they are removed.




************
RETURN VALUE
************



0. The command completed successfully.



1. An error has occurred.




********
SEE ALSO
********


makedhcp(8)|makedhcp.8
