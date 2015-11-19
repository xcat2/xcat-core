Set Up the Management Node for KVM
====================================


Install the kvm related packages
--------------------------------

Additional packages need to be installed on the management node for kvm support.

Please make sure the following packages have been installed on the management node, if not, install them manually. 

``perl-Sys-Virt``


Set Up the kvm storage directory on the management node(optional)
-----------------------------------------------------------------

It is a recommended configuration to create a shared file system for virtual machines hosting. The shared file system, usually on a SAN, NAS or GPFS, is shared among KVM hypevisors, which simplifies VM migration from one hypervisor to another with xCAT.

The easiest shared file system is ``/install`` directory on the management node, it can be shared among hypervisors via NFS. Please refer to the following steps :

  * Create a directory to store the virtual disk files ::

      mkdir -p /install/vms

  * export the storage directory ::

      echo "/install/vms *(rw,no_root_squash,sync,fsid=0)" >> /etc/exports
      exportfs -r

**Note**: make sure the root permission is turned on for nfs clients (i.e. use the ``no_root_squash`` option). Otherwise, the virtual disk file can not work.  
