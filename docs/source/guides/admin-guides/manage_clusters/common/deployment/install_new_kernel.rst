Installing a New Kernel in the Diskless Image
=============================================
[TODO : Verify on ppc64le]

Note: This procedure assumes you are using xCAT 2.6.1 or later.

To add a new kernel, create a directory named <kernelver> under ``/install/kernels`` directory, and ``genimage`` will pick them up from there.

The following examples assume you have the kernel RPM in ``/tmp`` and is using a new kernel in the directory ``/install/kernels/<kernelver>``.


The RPM names below are only examples, substitute your specific level and architecture.


* **[RHEL]**

The RPM kernel package is usually named: kernel-<kernelver>.rpm.
For example, kernel-3.10.0-229.ael7b.ppc64le.rpm means kernelver=3.10.0-229.ael7b.ppc64le. ::

        mkdir -p /install/kernels/3.10.0-229.ael7b.ppc64le
        cp /tmp/kernel-3.10.0-229.ael7b.ppc64le.rpm /install/kernels/3.10.0-229.ael7b.ppc64le
        createrepo /install/kernels/3.10.0-229.ael7b.ppc64le/

Append kernel directory ``/install/kernels/<kernelver>`` in ``pkgdir`` of specific osimage. ::

        chdef -t osimage <imagename> -p pkgdir=/install/kernels/3.10.0-229.ael7b.ppc64le/

Run genimage/packimage to update the image with the new kernel.
Note: If downgrading the kernel, you may need to first remove the rootimg directory. ::

        genimage <imagename> -k 3.10.0-229.ael7b.ppc64le
        packimage <imagename>

* **[SLES]**

The RPM kernel package is usually separated into two parts: kernel-<arch>-base and kernel<arch>.
For example, /tmp contains the following two RPMs: ::

         kernel-default-3.12.28-4.6.ppc64le.rpm
         kernel-default-base-3.12.28-4.6.ppc64le.rpm
         kernel-default-devel-3.12.28-4.6.ppc64le.rpm


3.12.28-4.6.ppc64le is NOT the kernel version,3.12.28-4-ppc64le is the kernel version.
The "4.6.ppc64le" is replaced with "4-ppc64le": ::

         mkdir -p /install/kernels/3.12.28-4-ppc64le/
         cp /tmp/kernel-default-3.12.28-4.6.ppc64le.rpm /install/kernels/3.12.28-4-ppc64le/
         cp /tmp/kernel-default-base-3.12.28-4.6.ppc64le.rpm /install/kernels/3.12.28-4-ppc64le/
         cp /tmp/kernel-default-devel-3.12.28-4.6.ppc64le.rpm /install/kernels/3.12.28-4-ppc64le/

Append kernel directory ``/install/kernels/<kernelver>`` in ``pkgdir`` of specific osimage. ::

         chdef -t osimage <imagename> -p pkgdir=/install/kernels/3.12.28-4-ppc64le/

Run genimage/packimage to update the image with the new kernel.
Note: If downgrading the kernel, you may need to first remove the rootimg directory.

Since the kernel version name is different from the kernel rpm package name, the -k flag MUST to be specified on the genimage command. ::

         genimage <imagename> -k 3.12.28-4-ppc64le 3.12.28-4.6
         packimage <imagename>


Installing New Kernel Drivers to Diskless Initrd
=================================================


The kernel drivers in the diskless initrd are used for the devices during the netboot. If you are missing one or more kernel drivers for specific devices (especially for the network device), the netboot process will fail. xCAT offers two approaches to add additional drivers to the diskless initrd during the running of genimage.

Use the '-n' flag to add new drivers to the diskless initrd: ::

         genimage <imagename> -n <new driver list>


Generally, the genimage command has a default driver list which will be added to the initrd. But if you specify the '-n' flag, the default driver list will be replaced with your <new driver list>. That means you need to include any drivers that you need from the default driver list into your <new driver list>.

The default driver list: ::

         rh-x86:   tg3 bnx2 bnx2x e1000 e1000e igb mlx_en virtio_net be2net
         rh-ppc:   e1000 e1000e igb ibmveth ehea
         rh-ppcle: ext3 ext4
         sles-x86: tg3 bnx2 bnx2x e1000 e1000e igb mlx_en be2net
         sels-ppc: tg3 e1000 e1000e igb ibmveth ehea be2net
         sles-ppcle: scsi_mod libata scsi_tgt jbd2 mbcache crc16 virtio virtio_ring libahci crc-t10dif scsi_transport_srp af_packet ext3 ext4 virtio_pci virtio_blk scsi_dh ahci megaraid_sas sd_mod ibmvscsi

Note: With this approach, xCAT will search for the drivers in the rootimage. You need to make sure the drivers have been included in the rootimage before generating the initrd. You can install the drivers manually in an existing rootimage (using chroot) and run genimage again, or you can use a postinstall script to install drivers to the rootimage during your initial genimage run.

Use the driver rpm package to add new drivers from rpm packages to the diskless initrd. Refer to the :doc:`/guides/admin-guides/manage_clusters/ppc64le/diskless/customize_image/network/cfg_network_adapter` for details.
