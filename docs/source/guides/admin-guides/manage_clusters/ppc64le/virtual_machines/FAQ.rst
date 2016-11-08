Trouble Shooting
================


VNC client complains the credentials are not valid
--------------------------------------------------

   **Issue**: 
     While connecting to the hypervisor with VNC, the vnc client complains "Authentication failed".

   **Solution**: 
     Check whether the clocks on the hypervisor and headnode are synced

rpower fails with "Error: internal error Process exited while reading console log qemu: Permission denied" 
----------------------------------------------------------------------------------------------------------

   **Issue**: ::

    #rpower vm1 on
    vm1: Error: internal error Process exited while reading console log output: char device redirected to /dev/pts/1
    qemu: could not open disk image /var/lib/xcat/pools/2e66895a-e09a-53d5-74d3-eccdd9746eb5/vm1.sda.qcow2: Permission denied: internal error Process exited while reading console log output: char device redirected to /dev/pts/1
    qemu: could not open disk image /var/lib/xcat/pools/2e66895a-e09a-53d5-74d3-eccdd9746eb5/vm1.sda.qcow2: Permission denied

   **Solution**: 
     Usually caused by incorrect permission in NFS server/client configuration. NFSv4 is enabled in some Linux distributions such as CentOS6 by default. The solution is simply to disable NFSv4 support on the NFS server by uncommenting the following line in "/etc/sysconfig/nfs": ::

       RPCNFSDARGS="-N 4"

     Then restart the NFS services and try to power on the VM again...
   
     **Note**: For stateless hypervisor, purge the VM by ``rmvm -p vm1``, reboot the hypervisor and then create the VM.

rpower fails with "Error: internal error: process exited while connecting to monitor qemu: Permission denied"
-------------------------------------------------------------------------------------------------------------

   **Issue**: ::

    #rpower vm1 on
    vm1: Error: internal error: process exited while connecting to monitor: 2016-02-03T08:28:54.104601Z qemu-system-ppc64: -drive file=/var/lib/xcat/pools/c7953a80-89ca-53c7-64fb-2dcfc549bd45/vm1.sda.qcow2,if=none,id=drive-scsi0-0-0-0,format=qcow2,cache=none: Could not open '/var/lib/xcat/pools/c7953a80-89ca-53c7-64fb-2dcfc549bd45/vm1.sda.qcow2': Permission denied

   **Solution**:
     Usually caused by SELinux policies. The solution is simply to disable SELinux on the vmhost/hypervisor by editing "/etc/selinux/config" and change the SELINUX line to SELINUX=disabled: ::

       SELINUX=disabled

     Then reboot the hypervisor...

rmigrate fails with "Error: libvirt error code: 38, message: unable to connect to server at 'c910f05c35:49152': No route to host."
----------------------------------------------------------------------------------------------------------------------------------

   **Issue**: ::

    #rmigrate vm1 kvmhost2
    vm1: Error: libvirt error code: 38, message: unable to connect to server at 'kvmhost2:49152': No route to host: Failed migration of vm1 from kvmhost1 to kvmhost2

   **Solution**:
     Usually caused by active firewall. To disable the firewall issue: ::

       systemctl disable firewalld

rmigrate fails with "Error: 38, message: failed to create directory '<dir-name>': File exists: Unknown issue libvirt error code."
---------------------------------------------------------------------------------------------------------------------------------

   **Issue**: ::

    #rmigrate vm1 kvmhost2
    vm1: Error: 38, message: failed to create directory '<dir-name>': File exists: Unknown issue libvirt error code.

   **Solution**:
     Ususally happens when `nfs:` is specified for vmstorage attribute but that NFS directory is no longer mounted. Make sure the directory /var/lib/xcat/pools is empty on the destination kvmhost.


Error: Cannot communicate via libvirt to kvmhost1
-------------------------------------------------

   **Issue**: 
     The kvm related commands complain "Error: Cannot communicate via libvirt to kvmhost1"

   **Solution**: 
     Usually caused by incorrect ssh configuration between xCAT management node and hypervisor. Make sure it is possible to access the hypervisor from management node via ssh without password.


Fail to ping the installed VM
-----------------------------

   **Issue**: 
     The newly installed stateful VM node is not pingable, the following message can be observed in the console during VM booting: ::

       ADDRCONF(NETDEV_UP): eth0 link is not ready.

   **Solutoin**: 
     Usually caused by the incorrect VM NIC model. Try the following steps to specify "virtio": :: 

       rmvm vm1
       chdef vm1 vmnicnicmodel=virtio
       mkvm vm1

