grub2 support for x86_64, aarch64 and riscv64
=============================================

xCAT 2.17 enables grub2 boot support for x86_64 and aarch64 but does not ship the necessary grub2 binaries for those architectures.
If you want to use grub2 for x86_64 or aarch64 you need to download the binaries from some EL OS repository.

riscv64 nodes can only boot through UEFI firmware and grub2, so they always need ``grub2.riscv64``. Recent ``grub2-xcat`` packages from xcat-dep install it; if the package on your management node does not (``ls /tftpboot/boot/grub2/grub2.riscv64``), copy the binary by hand as described below.

#. Download files from an BaseOS EL repository mirror

        For EL these files are named ``grubx64.efi`` (x86_64), ``grubaa64.efi`` (aarch64) and ``grubriscv64.efi`` (riscv64) and usually in ``BaseOS/<arch>/os/EFI/BOOT``.
        For very recent hardware you might need to use a newer grub version. Therefore, it's recommended to use a binary from the latest operationg system release available.
        You can use Red Hat Enterprise Linux, AlmaLinux, Rocky Linux or even Fedora repositories to download the grub files.

#. Copy downloaded files to ``/tftpboot/boot/grub2``:

        * x86_64: ``/tftpboot/boot/grub2/grub2.x86_64``
        * aarch64: ``/tftpboot/boot/grub2/grub2.aarch64``
        * riscv64: ``/tftpboot/boot/grub2/grub2.riscv64``

