node
====

Description
-----------

The definition of physical units in the cluster, such as lpar, virtual machine, frame, cec, hmc, switch. 

Key Attrubutes
--------------

* os: 
    The operating system deployed on this node. Valid values: AIX, rhels*, rhelc*, rhas*, centos*, SL*, fedora*, sles* (where * is the version #)

* arch: 
    The hardware architecture of this node. Valid values: x86_64, ppc64, x86, ia64.

* groups:
    Usually, there are a set of nodes with some attributes in common, xCAT admin can define a node group containing these nodes, so that the management task can be issued against the group instead of individual nodes. A node can be a memeber of different groups, so the value of this attributes is a comma-delimited list of groups. At least one group is required to create a node. The new created group names should not be prefixed with "__" as this token has been preserverd as the internal group name.

* mgt:
    The method to do general hardware management of the node. This attribute can be determined by the machine type of the node. Valid values: ipmi, blade, hmc, ivm, fsp, bpa, kvm, esx, rhevm. 

* mac: 
    The mac address of the network card on the node, which is connected with the installation server and can be used as the network installation device.
     
* ip: 
    The IP address of the node.

* netboot: 
    The type of network boot method for this node, determined by the OS to provision, the architecture and machine type of the node. Valid values:

              +--------------------------+----------------------+-----------------------------------+        
              | Arch and Machine Type    |   OS                 |       valid netboot options       |
              +==========================+======================+===================================+
              |       x86, x86_64        |   ALL                |       pxe, xnba                   |
              +--------------------------+----------------------+-----------------------------------+
              |         ppc64            | <=rhel6, <=sles11.3  |       yaboot                      |
              +--------------------------+----------------------+-----------------------------------+       
              |         ppc64            | >=rhels7, >=sles11.4 |       grub2,grub2-http,grub2-tftp |
              +--------------------------+----------------------+-----------------------------------+ 
              |   ppc64le NonVirtualize  |    ALL               |       petitboot                   |
              +--------------------------+----------------------+-----------------------------------+
              |   ppc64le PowerKVM Guest |    ALL               |       grub2,grub2-http,grub2-tftp |
              +-------------------------------------------------+-----------------------------------+
 
* postscripts: 
    Comma separated list of scripts, that should be run on this node after diskful installation or diskless boot, finish some system configuration and maintenance work. For installation of RedHat, CentOS, Fedora, the scripts will be run before the reboot. For installation of SLES, the scripts will be run after the reboot but before the init.d process. 

* postbootscripts: 
    Comma separated list of scripts, that should be run on this node as a SysV init job on the 1st reboot after installation or diskless boot, finish some system configuration and maintenance work. 

* provmethod:
    The provisioning method for node deployment. Usually, this attribute is an ``osimage`` object name. 

* status:
    The current status of the node, which is updated by xCAT. This value can be used to monitor the provision process. Valid values: powering-off, installing, booting/netbooting, booted.

Use Cases
---------

* Case 1: 
  There is a ppc64le node named "cn1", the mac of installation NIC is "ca:68:d3:ae:db:03", the ip assigned is "10.0.0.100", the network boot method is "grub2", place it into the group "all". Use the following command ::

    mkdef -t node -o cn1 arch=ppc64 mac="ca:68:d3:ae:db:03" ip="10.0.0.100" netboot="grub2" groups="all"

* Case 2:

  List all the node objects ::

    nodels

  This can also be done with ::

    lsdef -t node

* Case 3:
  List the mac of object "cn1" ::

    lsdef -t node -o cn1 -i mac

* Case 4: 
  There is a node definition "cn1", modify its network boot method  to "yaboot" ::

    chdef -t node -o cn1 netboot=yaboot
    
* Case 5:
  There is a node definition "cn1", create a node definition "cn2" with the same attributes with "cn1", except the mac addr(ca:68:d3:ae:db:04) and ip address(10.0.0.101) 

  *step 1*:  write the definition of "cn1" to a stanza file named "cn.stanza" ::

      lsdef -z cn1 > /tmp/cn.stanza

  The content of "/tmp/cn.stanza" will look like ::

      # <xCAT data object stanza file>
      cn1:
          objtype=node
          groups=all
          ip=10.0.0.100
          mac=ca:68:d3:ae:db:03
          netboot=grub2
  
  *step 2*: modify the "/tmp/cn.stanza" according to the "cn2" attributes ::
  
      # <xCAT data object stanza file>
      cn2:
          objtype=node
          groups=all
          ip=10.0.0.101
          mac=ca:68:d3:ae:db:04
          netboot=grub2
  
  *step 3*: create "cn2" definition with "cn.stanza" ::

      cat /tmp/cn.stanza |mkdef -z   

