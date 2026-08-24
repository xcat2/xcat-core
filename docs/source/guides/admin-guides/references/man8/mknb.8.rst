
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


***********
DESCRIPTION
***********


The \ **mknb**\  command is run by xCAT automatically when xCAT is installed on the management node.
It creates a network boot root image (used for node discovery, BMC programming, and flashing)
for the same architecture that the management node is.  So you normally do not need to run the
\ **mknb**\  command yourself.

If you make custom changes to the network boot root image, you will need to run \ **mknb**\  again to regenerate the diskless image to include your changes.  If you have an xCAT Hierarchical Cluster with Service Nodes having local /tftpboot directories (site.sharedtftp=0), you will need to copy the generated root image to each Service Node.

An OpenEmbedded Genesis package installs an exported image under
``/opt/xcat/share/xcat/netboot/genesis-openembedded/ARCH``.  \ **mknb**\
prefers that image when it is installed.  Otherwise it uses the old image under
``/opt/xcat/share/xcat/netboot/genesis/ARCH``.

An export is identified by ``xcat-genesis.manifest``, which records its format
version and architecture.  The directory also contains ``kernel``,
``initramfs.cpio.gz``, and ``SHA256SUMS``.  \ **mknb**\  verifies the manifest
and both boot files before publishing them under the configured TFTP root.  An
incomplete or invalid export leaves the current boot files unchanged.  The
legacy ``fs/`` layout remains supported and is packed locally.

When multiple IPv4 addresses are configured for the same network, \ **mknb**\  uses a locally assigned ``site.master`` for the xcatd endpoint, or the first address reported by the operating system when ``site.master`` is not local. POWER discovery configurations also use this address for their kernel and initrd URLs.

OpenEmbedded images use the exact architecture names ``x86``, ``x86_64``,
``ppc64``, ``ppc64le``, ``armv7hf``, ``aarch64``, and ``riscv64``.  If an
OpenEmbedded ``ppc64le`` image is not installed, \ **mknb**\  keeps the old
behavior and uses the legacy ``ppc64`` image.


*******
OPTIONS
*******



\ *arch*\ 
 
 The hardware architecture for which to build the boot image.
 



************
RETURN VALUE
************



0. The command completed successfully.



1. An error has occurred.




********
SEE ALSO
********


makedhcp(8)|makedhcp.8
