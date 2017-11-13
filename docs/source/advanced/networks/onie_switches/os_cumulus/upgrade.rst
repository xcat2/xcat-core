Cumulus OS upgrade
==================

The Cumulus OS on the ONIE switches can be upgraded in 2 ways: 

* Upgrade only the changed packages, using ``apt-get update`` and ``apt-get upgrade``. If the ONIE switches has internet access, this is the preferred method, otherwise, you need to build up a local cumulus mirror in the cluster. 

 Since in a typical cluster setup, the switches usually do not have internet access, you can create a local mirror on the server which has internet access and can be reached from the switches, the steps are ::
 
   mkdir -p /install/mirror/cumulus
   cd /install/mirror/cumulus
   #the wget might take a long time, it will be better if you can set up 
   #a cron job to sync the local mirror with upstream
   wget -m --no-parent http://repo3.cumulusnetworks.com/repo/ 
   
 then compose a ``sources.list`` file  on MN like this(take 172.21.253.37 as ip address of the local mirror server) ::

   #cat /tmp/sources.list
   deb     http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3 cumulus upstream
   deb-src http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3 cumulus upstream
   
   deb     http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-security-updates cumulus upstream
   deb-src http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-security-updates cumulus upstream
   
   deb     http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-updates cumulus upstream
   deb-src http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-updates cumulus upstream   

 distribute the ``sources.list`` file to the switches to upgrade  with ``xdcp``, take "switch1" as an example here ::

   xdcp switch1 /tmp/sources.list  /etc/apt/sources.list 

 then invoke ``apt-get update`` and ``apt-get install`` on the switches to start package upgrade, a reboot might be needed after upgrading ::

   xdsh switch1 'apt-get update && apt-get upgrade && reboot' 

 check the `/etc/os-release` file to make sure the Cumulus OS has been upgraded ::

   cat /etc/os-release



* Performe a binary (full image) install of the new version, using ONIE. If you expect to upgrade between major versions or if you have the binary image to upgrade to, this way is the recommended one. Make sure to backup your data and configuration files because binary install will erase all the configuration and data on the switch.
 
 The steps to perform a binary (full image) install of the new version are:
    
 1) place the binary image "cumulus-linux-3.4.1.bin" under ``/install`` directory on MN("172.21.253.37") ::

      mkdir -p /install/onie/
      cp cumulus-linux-3.4.1.bin /install/onie/
      
 2) invoke the upgrade on switches with ``xdsh`` ::
    
      xdsh switch1 "/usr/cumulus/bin/onie-install -a -f -i http://172.21.253.37/install/onie/cumulus-linux-3.4.1.bin && reboot"

    The full upgrade process might cost 30 min, you can ping the switch with ``ping switch1`` to check whether it finishes upgrade. 
   
 3) After upgrading, the license should be installed, see :ref:`Activate the License <activate-the-license>` for detailed steps.
 
 4) Restore your data and configuration files on the switch.



