Changing the Hostname/IP address
================================

Change compute node definition relevant to the service node
-----------------------------------------------------------

Change the settings in database. Below shows a method to find out where the old
IP address settings (take 10.6.0.1 as a example) are used in Hierarchy
environment.

* Query the old attribute ::

    lsdef -t node -l | grep "10.6.0.1"
    # below is output of the above command. We can find out that nfsserver
    # and servicenode are using the old IP address setting.
    nfsserver=10.6.0.1
    servicenode=10.6.0.1


* Query the nodes whose nfsserver is 10.6.0.1 ::

    lsdef -w nfsserver==10.6.0.1
    # below is output of the above command
    cn1  (node)
    cn2  (node)
    cn3  (node)
    cn4  (node)

* Change the nfsserver address for cn1,cn2,cn3,cn4 by running the following
  command: ::

    chdef -t node cn1-cn4 nfsserver=<new service node IP addresss>

Database Connection Changes
---------------------------

Granting or revoking access privilege in the database for the service node.

* For MySQL, refer to :ref:`grante_revoke_mysql_access_label`.

Update Provision Environment on Service Node
--------------------------------------------

If you are using service nodes to install the nodes and using ``/etc/hosts``
for hostname resolution, you need to copy the new ``/etc/hosts`` from the
management node to the service nodes, then run ``makedns -n`` on the service
nodes. For example: ::

  xdcp <servicenodes>  /etc/hosts /etc/hosts
  xdsh <servicenodes> makedns -n

Reinstall the nodes to pick up all changes  ::

  nodeset <noderange> osimage=<osimagename>

Then use your normal command to install the nodes like rinstall, rnetboot, etc.
