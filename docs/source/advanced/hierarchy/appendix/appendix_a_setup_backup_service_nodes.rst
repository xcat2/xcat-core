Appendix A: Setup backup Service Nodes
======================================

For reliability, availability, and serviceability purposes you may wish to
designate backup Service Nodes in your hierarchical cluster. The backup
Service Node will be another active Service Node that is set up to easily
take over from the original Service Node if a problem occurs. This is not an
automatic failover feature. You will have to initiate the switch from the
primary Service Node to the backup manually. The xCAT support will handle most
of the setup and transfer of the nodes to the new Service Node. This
procedure can also be used to simply switch some compute nodes to a new
Service Node, for example, for planned maintenance.

Initial deployment
------------------

Integrate the following steps into the hierarchical deployment process described above.


#. Make sure both the primary and backup service nodes are installed,
   configured, and can access the MN database.
#. When defining the CNs add the necessary service node values to the
   "servicenode" and "xcatmaster" attributes of the :doc:`node </guides/admin-guides/references/man7/node.7>` definitions.
#. (Optional) Create an xCAT group for the nodes that are assigned to each SN.
   This will be useful when setting node attributes as well as providing an
   easy way to switch a set of nodes back to their original server.

To specify a backup service node you must specify a comma-separated list of
two **service nodes** for the servicenode value of the compute node. The first
one is the primary and the second is the backup (or new SN) for that node.
Use the hostnames of the SNs as known by the MN.

For the **xcatmaster** value you should only include the primary SN, as known
by the compute node.

In most hierarchical clusters, the networking is such that the name of the
SN as known by the MN is different than the name as known by the CN. (If
they are on different networks.)

The following example assume the SN interface to the MN is on the "a"
network and the interface to the CN is on the "b" network. To set the
attributes you would run a command similar to the following. ::

  chdef <noderange>  servicenode="xcatsn1a,xcatsn2a" xcatmaster="xcatsn1b"

The process can be simplified by creating xCAT node groups to use as the <noderange> in the :doc:`chdef </guides/admin-guides/references/man1/chdef.1>` command to create a
xCAT node group containing all the nodes that belong to service node "SN27".  For example: ::

  mkdef -t group sn1group members=node[01-20]

**Note: Normally backup service nodes are the primary SNs for other compute
nodes. So, for example, if you have 2 SNs, configure half of the CNs to use
the 1st SN as their primary SN, and the other half of CNs to use the 2nd SN
as their primary SN. Then each SN would be configured to be the backup SN
for the other half of CNs.**

When you run :doc:`makedhcp </guides/admin-guides/references/man8/makedhcp.8>` command, it will configure dhcp and tftp on both the primary and backup SNs, assuming they both have network access to the CNs. This will make it possible to do a quick SN takeover without having to wait for replication when you need to switch.

xdcp Behaviour with backup servicenodes
---------------------------------------

The xdcp command in a hierarchical environment must first copy (scp) the
files to the service nodes for them to be available to scp to the node from
the service node that is it's master. The files are placed in
``/var/xcat/syncfiles`` directory by default, or what is set in site table
SNsyncfiledir attribute. If the node has multiple service nodes assigned,
then xdcp will copy the file to each of the service nodes assigned to the
node. For example, here the files will be copied (scp) to both service1 and
rhsn. lsdef cn4 | grep servicenode. ::

  servicenode=service1,rhsn

If a service node is offline (e.g. service1), then you will see errors on
your xdcp command, and yet if rhsn is online then the xdcp will actually
work. This may be a little confusing. For example, here service1 is offline,
but we are able to use rhsn to complete the xdcp. ::

  xdcp cn4  /tmp/lissa/file1 /tmp/file1

  service1: Permission denied (publickey,password,keyboard-interactive).
  service1: Permission denied (publickey,password,keyboard-interactive).
  service1: lost connection
  The following servicenodes: service1, have errors and cannot be updated
  Until the error is fixed, xdcp will not work to nodes serviced by these service nodes.

  xdsh cn4 ls /tmp/file1
  cn4: /tmp/file1

Switch to the backup SN
-----------------------

When an SN fails, or you want to bring it down for maintenance, use this
procedure to move its CNs over to the backup SN.

Move the nodes to the new service nodes
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Use the :doc:`snmove </guides/admin-guides/references/man1/snmove.1>` command to make the database changes necessary to move a set of compute nodes from one Service Node to another. 

To switch all the compute nodes from Service Node ``sn1`` to the backup Service Node ``sn2``, run: ::

    snmove -s sn1

Modified database attributes
""""""""""""""""""""""""""""

The ``snmove`` command will check and set several node attribute values.

* **servicenode**: This will be set to either the second server name in the servicenode attribute list or the value provided on the command line.

* **xcatmaster**: Set with either the value provided on the command line or it will be automatically determined from the servicenode attribute.

* **nfsserver**: If the value is set with the source service node then it will be set to the destination service node.

* **tftpserver**: If the value is set with the source service node then it will be reset to the destination service node.

* **monserver**: If set to the source service node then reset it to the destination servicenode and xcatmaster values.
* **conserver**: If set to the source service node then reset it to the destination servicenode and run ``makeconservercf``

Run postscripts on the nodes
""""""""""""""""""""""""""""

If the CNs are up at the time the ``snmove`` command is run then ``snmove`` will run postscripts on the CNs to reconfigure them for the new SN. The "syslog" postscript is always run. The ``mkresolvconf`` and ``setupntp`` scripts will be run if they were included in the nodes postscript list.

You can also specify an additional list of postscripts to run.

Modify system configuration on the nodes
""""""""""""""""""""""""""""""""""""""""

If the CNs are up the ``snmove`` command will also perform some configuration on the nodes such as setting the default gateway and modifying some configuration files used by xCAT.

Switching back
--------------

The process for switching nodes back will depend on what must be done to
recover the original service node. If the SN needed to be reinstalled, you
need to set it up as an SN again and make sure the CN images are replicated
to it. Once you've done this, or if the SN's configuration was not lost,
then follow these steps to move the CNs back to their original SN:

* Use ``snmove``: ::

      snmove sn1group -d sn1

