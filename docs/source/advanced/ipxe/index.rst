x86 Network Boot with iPXE
==========================

xCAT boots x86 nodes with iPXE through two ``netboot`` methods:

* ``ipxe``: the unmodified iPXE release in the ``ipxe-xcat`` package.
* ``xnba``: the xCAT Network Boot Agent in the ``xnba-undi`` package, a patched iPXE. This method is deprecated, and a later release removes it.

Both methods run the same boot scripts. ``nodeset`` writes them under ``xcat/ipxe/nodes`` for ``ipxe`` and under ``xcat/xnba/nodes`` for ``xnba``. The xCAT packages install both ``ipxe-xcat`` and ``xnba-undi``.

New x86 nodes get ``netboot=ipxe``: node discovery, profile-based node definitions and the x86 node templates of ``mkdef --template`` set it.

The upstream loader
-------------------

A node with ``netboot=ipxe`` that boots with the PXE firmware of its network card loads one of these files from ``/tftpboot`` on its TFTP server:

* BIOS: ``xcat/ipxe/i386/undionly.kpxe``. This is the 32-bit build, so it also boots 32-bit x86 nodes.
* UEFI: ``xcat/ipxe/x86_64-sb/snponly-shim.efi``, the shim of the iPXE project, which Microsoft signs. The shim loads ``snponly.efi`` from the same directory, which the iPXE Secure Boot CA signs. The node boots with UEFI Secure Boot on or off.

iPXE then sends a new DHCP request. The node gets its boot script only when it reports the iPXE features that the script needs in DHCP option 175. For BIOS these are HTTP, bzImage and PXE, and for UEFI they are HTTP and EFI. A node with an iSCSI disk in the ``iscsi`` table also needs iSCSI, because iPXE connects that disk before it runs the script. Every other client of the node gets the file above first, including an iPXE in network card firmware that lacks one of these features.

``makedhcp`` names these files even when they are missing on its own server, because a node or a network can use another TFTP server.

Nodes without a definition
--------------------------

An x86 client without a node definition, such as a node in discovery, gets the upstream loader, whatever the method of the other nodes. It then gets the Genesis script of its network from ``xcat/ipxe/nets``, which ``mknb`` writes. These clients load from the DHCP server itself, so ``makedhcp`` names a loader file for them only when it is in the local TFTP directory, as it does for xNBA.

On a server that serves x86 discovery, ``makedhcp -n`` and ``makedhcp -a`` warn when an upstream loader file is missing from the local TFTP directory, or when ``xcat/ipxe/nets`` has no network boot script.

Move nodes to the ipxe method
-----------------------------

#. Upgrade the management node and every service node that runs DHCP or owns a TFTP directory. The package dependencies install ``ipxe-xcat``.
#. List every TFTP directory that serves x86 nodes: the management node, each service node with ``sharedtftp=0``, the host that ``sharedtftp=<hostname>`` names, and each node or network ``tftpserver``.
#. For each TFTP directory, run ``mknb`` on the xCAT server that writes the directory. Run it for each x86 architecture that the cluster serves: ``x86_64``, and ``x86`` for 32-bit nodes. Alternatively, copy the ``xcat/ipxe/nets`` scripts and the ``ipxe-xcat`` files into the directory.
#. In each TFTP directory, make sure that ``xcat/ipxe/i386/undionly.kpxe``, ``xcat/ipxe/x86_64-sb/snponly-shim.efi`` and ``xcat/ipxe/x86_64-sb/snponly.efi`` exist.
#. Run ``makedhcp -n`` and then ``makedhcp -a``, so that every DHCP server writes its configuration again with the reservations of every node. Between the two commands the DHCP servers have no reservations. Unknown x86 clients now get the upstream loader.
#. Set the method of the nodes, and run ``nodeset`` for them again: ::

       chdef <noderange> netboot=ipxe
       nodeset <noderange> osimage=<osimage>

To go back to xNBA, set ``netboot=xnba`` on the nodes, keep ``xnba-undi`` installed on every TFTP directory, and run ``nodeset`` for them again. Site scripts that use ``${netX/machyp}`` do not work with the upstream loader: use ``${netX/mac:hexhyp}``.

UEFI Secure Boot
----------------

With Secure Boot on, the firmware loads the shim only when it trusts the Microsoft third-party UEFI CA, 2011 or 2023, that signs it. Some firmware turns that CA off by default: turn it on in the firmware setup.

The signature database of the firmware does not hold the keys of a Linux distribution, so the firmware refuses the kernel that the boot script loads. The UEFI boot scripts of ``netboot=ipxe`` nodes name a shim, and iPXE runs the kernel through it:

* A node with an ``os`` value in its ``nodetype`` entry uses the shim of its install source, ``EFI/BOOT/BOOTX64.EFI`` or ``EFI/boot/bootx64.efi`` under ``/install/<os>/x86_64``. The vendor certificate of that shim signs the kernel of its own distribution.
* Every other node uses ``xcat/ipxe/x86_64-sb/shimx64.efi``, which ``ipxe-xcat`` installs.

iPXE fetches a shim only when it cannot load the kernel itself, so a node with Secure Boot off reads neither file.

A shim also accepts a kernel that a MOK key signs. Nothing signs the Genesis kernel, so a node boots Genesis with Secure Boot on only after the site signs ``xcat/genesis.kernel.x86_64`` with its own key and enrolls that key with ``mokutil``. The discovery scripts under ``xcat/ipxe/nets`` name the shim of ``ipxe-xcat`` for that purpose.

Two paths stay Secure Boot off. A kernel without an EFI stub boots through ``elilo-x64.efi``, and ESXi boots through ``esxboot-x64.efi``. No key signs either file. Boot these nodes with Secure Boot off.

Known limits of the upstream loader
-----------------------------------

* Local boot on BIOS nodes: ``undionly.kpxe`` unloads the PXE stack of the network card. When a boot script runs ``exit`` to boot from the local disk, iPXE returns to the BIOS through INT 18h. The BIOS then boots the next device in its boot order. Make sure that local boot works on your BIOS hardware before you move nodes.
* UEFI on some older Lenovo laptops: iPXE v2.0.0 stops the UEFI Dhcp6 driver, and some older Lenovo laptops hang (https://github.com/ipxe/ipxe/issues/1358). Use ``netboot=grub2`` for these nodes.
