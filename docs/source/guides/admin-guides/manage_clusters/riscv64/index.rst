RISC-V 64-bit (riscv64)
=======================

xCAT manages RISC-V 64-bit (``riscv64``) compute nodes running EL10. Rocky
Linux 10 is the reference distribution; the RHEL 10 RISC-V developer preview
uses the same media layout. The general cluster management documentation under
:doc:`/guides/admin-guides/manage_clusters/common/index` applies; this page
only covers what is specific to the architecture.

What riscv64 nodes need
-----------------------

* **UEFI firmware that can PXE boot.** riscv64 nodes boot through UEFI and
  grub2 only: there is no BIOS/PXELINUX, petitboot or xNBA path. The firmware
  sends DHCP option 93 (client system architecture) value 27 (``0x001b``) and
  xCAT answers with the boot file ``boot/grub2/grub2.riscv64``, from both the
  Kea and the ISC DHCP backends.
* ``noderes.netboot`` is one of ``grub2``, ``grub2-tftp`` or ``grub2-http``.
  ``grub2-http`` is recommended for installers, whose initrd is large.
* ``nodetype.arch`` and ``osimage.osarch`` are ``riscv64``. No alias is
  needed: ``uname -m``, rpm and dpkg all use the same token.
* ``/tftpboot/boot/grub2/grub2.riscv64``: the EL grub2 UEFI image for riscv64.
  It is provided by the ``grub2-xcat`` package where available; otherwise copy
  ``EFI/BOOT/grubriscv64.efi`` from the EL10 riscv64 BaseOS media as described
  in :doc:`/guides/install-guides/yum/grub2`.
* The riscv64 Genesis image (``xCAT-genesis-base-riscv64`` and
  ``xCAT-genesis-scripts-riscv64``) for discovery, BMC setup and flashing. Its
  kernel must be loadable by grub2, that is, built with the EFI stub.

The management node itself can be x86_64 or ppc64le; riscv64 is managed like
any other mixed-architecture cluster (see
:doc:`/advanced/mixed_cluster/support_matrix`).

Node discovery
--------------

``mknb riscv64`` publishes the Genesis kernel and initramfs as
``/tftpboot/xcat/genesis.kernel.riscv64`` and
``/tftpboot/xcat/genesis.fs.riscv64.gz`` and writes one grub2 configuration per
network, ``/tftpboot/boot/grub2/grub.cfg-<hex network prefix>``. A net booted
``grub2.riscv64`` looks for ``grub.cfg-01-<mac>``, then ``grub.cfg-<8 hex digit
ip>``, then shorter prefixes of that ip; the per-node files written by
``nodeset`` therefore take priority and the network file is only used by nodes
that have no configuration yet, which is exactly the discovery case.
``mknb`` runs automatically when the riscv64 Genesis packages are installed or
updated; run ``mknb riscv64`` yourself after changing ``site.master``,
``site.dhcpinterfaces`` or the serial console settings.

Discovered riscv64 nodes get ``nodetype.arch=riscv64`` and, when no compatible
method is set, ``noderes.netboot=grub2``. Use the discovery procedures documented
for the other architectures.

Stateful (diskful) installation
--------------------------------

Import the Rocky Linux 10 riscv64 DVD with ``copycds``; it creates the
``rocky10.x-riscv64-install-compute`` osimage. The installer kernel and initrd
come from ``images/pxeboot`` on the media, like x86_64 and aarch64. The default
kickstart templates and package lists are shared with the other architectures;
``service.rocky10.riscv64.otherpkgs.pkglist`` pulls the service node packages
from the ``rh10/riscv64`` xcat-dep repository.

The installer creates the UEFI boot entry for the installed system; after
``nodeset <node> boot`` the firmware falls through to it because the per-node
``grub2-<node>`` loader link is removed.

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
add others through ``linuximage.netdrivers``.

Management node on riscv64
--------------------------

The EL10 riscv64 BaseOS, AppStream and CRB repositories provide every
dependency that xCAT takes from the distribution on x86_64, including ``kea``.
EPEL has no riscv64 build, so the packages xCAT otherwise takes from EPEL must
come from the riscv64 xcat-dep repository together with the usual xcat-dep
packages:

* from EPEL on x86_64: ``perl-Digest-SHA1``, ``perl-Net-DNS``,
  ``perl-Crypt-CBC``, ``perl-Crypt-Rijndael``, ``perl-DB_File``; optional
  features also use ``perl-Expect``, ``perl-HTML-Form``, ``perl-Sys-Virt``,
  ``perl-Mail-Sender``, ``perl-SOAP-Lite``, ``perl-Crypt-Blowfish``,
  ``perl-Net-IP`` and ``conserver``;
* always from xcat-dep: ``perl-Net-Telnet``, ``perl-IO-Stty``,
  ``perl-Net-HTTPS-NB``, ``perl-HTTP-Async``, ``perl-Crypt-SSLeay``,
  ``goconserver``, ``ipmitool-xcat``, ``conserver-xcat`` and ``grub2-xcat``.

xCAT does not install anything from CPAN; every dependency is an rpm.

Limitations
-----------

* UEFI HTTP boot (client architecture 28, ``0x001c``) is not configured yet;
  use PXE (TFTP) to load ``grub2.riscv64`` and ``grub2-http`` for the payload.
* Ubuntu riscv64 is not supported yet.
* The serial console defaults to ``ttyS<site.defserialport>``; boards whose
  firmware exposes the console on another device need
  ``linuximage.addkcmdline`` or the serial settings adjusted.
