Prepare the Management Node for xCAT Installation
=================================================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

The hardware requirements for your xCAT management node largely depends on the size of the cluster you plan to manage and the type of provisioning being used (diskful, diskless, system clones, etc).  The majority of system load comes during cluster provisioning.

**Memory Recommendations:**

+--------------+-------------+
| Cluster size | Memory (GB) |
+==============+=============+
| small (< 16) | 4-6         |
+--------------+-------------+
| medium       | 6-8         |
+--------------+-------------+
| large        | > 16        |
+--------------+-------------+

Install any flavor of the supported operating system onto the management node.

The xCAT software RPMs will attempt to automatially install any base software provided by the Operating System if they are not already installed onto the machine.  In order for this to succeed, the node must have a repository set up providing the base operating system packages. 

Configure the Base OS Repository
--------------------------------

xCAT uses Linux Package Managers (yum, zypper, apt, etc) to install and resolve dependency packages provded by the base operating system.  Follow this section to create the repository for the base operating system on the management node

#. Copy the dvd .iso file onto the management node: ::

     mkdir -p /tmp/iso
     scp <user>@<server>:/images/iso/rhels7.1/ppc64le/RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso /tmp/iso
   
#. Mount the dvd iso to a directory on the management node.  ::

     #
     # [rhel] mounting at /mnt/iso/rhels7.1
     #
     mkdir -p /mnt/iso/rhels7.1
     mount -o loop /tmp/iso/RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso /mnt/iso/rhels7.1

     #
     # [sles] mounting at /mnt/iso/sles12
     #
     mkdir -p /mnt/iso/sles12
     mount -o loop /tmp/iso/SLE-12-Server-DVD-ppc64le-GM-DVD1.iso /mnt/iso/sles12

#. Create the local repository configuration file pointing to mounted iso image. ::

     #
     # [rhel]
     #
     vi /etc/yum/yum.repos.d/rhels71-base.repo

     #
     # [sles]
     #
     vi /etc/zypp/repos.d/sles12-base.repo



# Setting up OS Repository on Mgmt Node 

Disable system services
-----------------------

Disable the Firewall


* Set up Network
* Configure Network Interface Cards (NICs)
* Install the Management Node OS
* Supported OS and Hardware
