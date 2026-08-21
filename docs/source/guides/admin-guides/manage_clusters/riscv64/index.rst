RISC-V 64-bit (riscv64)
=======================

xCAT manages RISC-V 64-bit (``riscv64``) compute nodes running EL10. Rocky
Linux 10 is the reference distribution; the RHEL 10 RISC-V developer preview
uses the same media layout. The general cluster management documentation under
:doc:`/guides/admin-guides/manage_clusters/index` applies; this page
only covers what is specific to the architecture.

What riscv64 nodes need
-----------------------

* **UEFI firmware that can PXE boot.** riscv64 nodes boot through UEFI and
  grub2 only: there is no BIOS/PXELINUX, petitboot or xNBA path. The firmware
  sends DHCP option 93 (client system architecture) value 27 (``0x001b``) and
  xCAT answers with the boot file ``boot/grub2/grub2.riscv64``, from both the
  Kea and the ISC DHCP backends.
  Firmware configured for UEFI HTTP boot (client architecture 28, ``0x001c``)
  is served the same image over HTTP.
* ``noderes.netboot`` is one of ``grub2``, ``grub2-tftp`` or ``grub2-http``.
  ``grub2-http`` is recommended for installers, whose initrd is large.
* ``nodetype.arch`` and ``osimage.osarch`` are ``riscv64``. No alias is
  needed: ``uname -m``, rpm and dpkg all use the same token.
* ``/tftpboot/boot/grub2/grub2.riscv64``: the EL grub2 UEFI image for riscv64
  (the ``EFI/BOOT/grubriscv64.efi`` of the EL10 riscv64 BaseOS tree).
  ``copycds`` publishes it from the installation media when the management node
  does not have it yet, the ``grub2-xcat`` package installs the same image, and
  :doc:`/guides/install-guides/yum/grub2` describes copying it by hand. An image
  that is already there is never replaced.
* The riscv64 Genesis image (``xCAT-genesis-openembedded-riscv64``) for
  discovery, BMC setup and flashing. Its kernel is loaded by grub2 through the
  EFI stub. ``go-xcat`` installs the package; on a management node built another
  way, install it explicitly (``dnf install xCAT-genesis-openembedded-riscv64``),
  the same way the images of other architectures are installed for a mixed
  cluster. ``xcatconfig`` runs ``mknb riscv64`` for every installed image.
The management node itself is x86_64 (the validated combination, see
:doc:`/advanced/mixed_cluster/support_matrix`) or riscv64 (see below); riscv64
nodes are managed like any other mixed-architecture cluster.

Node discovery
--------------

``mknb riscv64`` publishes the Genesis kernel and initramfs as
``/tftpboot/xcat/genesis.kernel.riscv64`` and
``/tftpboot/xcat/genesis.fs.riscv64.lzma`` (or ``.gz``) and writes one grub2 configuration per
network, ``/tftpboot/boot/grub2/grub.cfg-<hex network prefix>``. A net booted
``grub2.riscv64`` looks for ``grub.cfg-01-<mac>``, then ``grub.cfg-<8 hex digit
ip>``, then shorter prefixes of that ip; the per-node files written by
``nodeset`` therefore take priority and the network file is only used by nodes
that have no configuration yet, which is exactly the discovery case.
Each configuration holds two entries. The default one fetches the Genesis kernel
and initramfs over HTTP, because a TFTP server hands the image to one client at a
time and the initramfs is tens of megabytes; the second entry loads the same
files over TFTP and is there for a management node that does not serve the TFTP
root over HTTP. ``site.httpport`` is honoured.
``mknb`` runs automatically when the riscv64 Genesis packages are installed or
updated; run ``mknb riscv64`` yourself after changing ``site.master``,
``site.dhcpinterfaces`` or the serial console settings. It also warns when
``grub2.riscv64`` is missing, since nothing would reach these configurations.

Discovered riscv64 nodes get ``nodetype.arch=riscv64`` and, when no compatible
method is set, ``noderes.netboot=grub2``. Use the discovery procedures documented
for the other architectures.

Stateful (diskful) installation
--------------------------------

Import the Rocky Linux 10 riscv64 DVD with ``copycds``; it creates the
``rocky10.x-riscv64-install-compute`` osimage. The installer kernel and initrd
come from ``images/pxeboot`` on the media, like x86_64 and aarch64.
``service.rocky10.riscv64.otherpkgs.pkglist`` pulls the service node packages
from the ``rh10/riscv64`` xcat-dep repository.

The EL10 installer (anaconda) has no RISC-V EFI platform: on riscv64 it asks
for the x86 UEFI boot loader packages (``grub2-efi-x64``, ``shim-x64``), which
do not exist, and registers the UEFI boot entry as ``\EFI\<distro>\shimx64.efi``.
xCAT therefore ships riscv64 variants of the EL10 templates and package lists
(``compute.rocky10.riscv64.tmpl``, ``compute.rhels10.riscv64.tmpl`` and the
service profiles): ``%packages --ignoremissing`` tolerates the request, the
package lists add ``grub2-efi-riscv64`` and ``efibootmgr``, and the
``post.rhels10.riscv64`` script run from ``%post`` points the UEFI boot entry at
``\EFI\<distro>\grubriscv64.efi`` and places the removable-media fallback loader
``\EFI\BOOT\BOOTRISCV64.EFI``. Custom templates for riscv64 should start from
these files. After ``nodeset <node> boot`` the firmware boots the installed
system because the per-node ``grub2-<node>`` loader link is removed.

Crash dumps
~~~~~~~~~~~

EL10 defines no default crash kernel reservation for riscv64
(``kdumpctl get-default-crashkernel`` is empty there), so the installer's kdump
add-on writes the literal ``crashkernel=auto``, which the kernel ignores: no
memory is reserved and ``kdump.service`` fails on every installed node. The
riscv64 templates therefore turn that add-on off. To take crash dumps on a
riscv64 node, reserve the memory yourself with a real value, for example::

    chdef -t osimage rocky10.2-riscv64-install-compute addkcmdline="crashkernel=256M"

Diskless images use ``linuximage.dump`` and ``linuximage.crashkernelsize`` as on
the other architectures; a riscv64 image with ``dump`` set and no explicit size
reserves 256M.

Stateless (diskless) images
---------------------------

``genimage`` builds riscv64 images with the ``compute.rocky10.riscv64.*`` and
``compute.rhels10.riscv64.*`` profiles (package list, exclude list and
postinstall). On an x86_64 management node this needs ``qemu-user-static``
registered for riscv64 through ``systemd-binfmt``; see
:doc:`/advanced/mixed_cluster/building_stateless_images`. EL10 has no
``qemu-user-static`` package of its own, so take the static riscv64 emulator
from a distribution that ships one. The default network driver list for
riscv64 images covers virtio, Intel, Realtek, Broadcom and Mellanox adapters;
add others through ``linuximage.netdrivers``. Cross-building on an x86_64
management node needs the riscv64 user-mode emulator registered with
systemd-binfmt, as described in
:doc:`/advanced/mixed_cluster/building_stateless_images`.

Management node on riscv64
--------------------------

The EL10 riscv64 BaseOS, AppStream and CRB repositories provide every
dependency that xCAT takes from the distribution on x86_64, including ``kea``.
EPEL has no riscv64 build, so the packages xCAT otherwise takes from EPEL must
come from the riscv64 xcat-dep repository together with the usual xcat-dep
packages:

* from EPEL on x86_64: ``perl-Digest-SHA1``, ``perl-Net-DNS``,
  ``perl-Crypt-CBC`` and ``perl-Crypt-Rijndael``; optional features also use
  ``perl-Expect``, ``perl-HTML-Form``, ``perl-Sys-Virt``, ``perl-Mail-Sender``,
  ``perl-SOAP-Lite``, ``perl-Crypt-Blowfish``, ``perl-Net-IP`` and
  ``conserver``;
* always from xcat-dep: ``perl-Net-Telnet``, ``perl-IO-Stty``,
  ``perl-Net-HTTPS-NB``, ``perl-HTTP-Async``, ``perl-Crypt-SSLeay``,
  ``goconserver``, ``ipmitool-xcat``, ``conserver-xcat`` and ``grub2-xcat``.

``perl-DB_File`` is deliberately not in that list: it cannot be built for
riscv64 (EL10 has no libdb). It is only used by the optional Confluent client,
so ``xCAT-server`` recommends it instead of requiring it. On the architectures
that do have it, the weak dependency installs it as before; a management node
that disables weak dependencies (``install_weak_deps=False``) has to install
``perl-DB_File`` explicitly to keep the Confluent client working.
xCAT does not install anything from CPAN; every dependency is an rpm.

Limitations
-----------

* UEFI HTTP boot (client architecture 28, ``0x001c``): a client without a
  reservation is offered the boot loader as a URL with the ``HTTPClient`` vendor
  class, which is what such firmware requires. It has not been exercised against
  HTTP boot firmware yet, and a node that ``nodeset`` has configured is offered
  its per-node boot loader over TFTP, as on the other architectures, so keep PXE
  boot enabled in the firmware.
* Ubuntu riscv64 is not supported yet.
* The serial console defaults to ``ttyS<site.defserialport>``; boards whose
  firmware exposes the console on another device need
  ``linuximage.addkcmdline`` or the serial settings adjusted.
