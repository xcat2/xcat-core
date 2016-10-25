Groups and Regular Expressions in Tables
========================================

Using Regular Expressions in the xCAT Tables
--------------------------------------------

The xCAT database has a number of tables, some with rows that are keyed by node name (such as ``noderes`` and ``nodehm`` ) and others that are not keyed by node name (for example, the ``policy`` table). The tables that are keyed by node name have some extra features that enable a more template-based style to be used:

Any group name can be used in lieu of a node name in the node field, and that row will then provide "default" attribute values for any node in that group. A row with a specific node name can then override one or more attribute values for that specific node. For example, if the ``nodehm`` table contains ::

    #node,power,mgt,cons,termserver,termport,conserver,serialport,serialspeed,serialflow,getmac,cmdmapping,comments,disable
    "mygroup",,"ipmi",,,,,,"19200",,,,,
    "node1",,,,,,,,"115200",,,,,

In the above example, the node group called "mygroup" sets ``mgt=ipmi`` and ``serialspeed=19200``. Any nodes that are in this group will have those attribute values, unless overridden. For example, if "node2" is a member of "mygroup", it will automatically inherit these attribute values (even though it is not explicitly listed in this table). In the case of "node1" above, it inherits ``mgt=ipmi``, but overrides the ``serialspeed`` to be 115200, instead of 19200. A useful, typical way to use this capability is to create a node group for your nodes and for all the attribute values that are the same for every node, set them at the group level. Then you only have to set attributes for each node that vary from node to node.

xCAT extends the group capability so that it can also be used for attribute values that vary from node to node in a very regular pattern. For example, if in the ``ipmi`` table you want the ``bmc`` attribute to be set to whatever the nodename is with "-bmc" appended to the end of it, then use this in the ``ipmi`` table ::

    #node,bmc,bmcport,taggedvlan,bmcid,username,password,comments,disable
    "compute","/\z/-bmc/",,,,,,,

In this example, "compute" is a node group that contains all of the compute nodes. The 2nd attribute (``bmc``) is a regular expression that is similar to a substitution pattern. The 1st part ``\z`` matches the end of the node name and substitutes ``-bmc``, effectively appending it to the node name.

Another example is if "node1" is assigned the IP address "10.0.0.1", node2 is assigned the IP address "10.0.0.2", etc., then this could be represented in the ``hosts`` table with the single row ::

    #node,ip,hostnames,otherinterfaces,comments,disable
    "compute","|node(\d+)|10.0.0.($1+0)|",,,,

In this example, the regular expression in the ``ip`` attribute uses ``|`` to separate the 1st and 2nd part. This means that xCAT will allow arithmetic operations in the 2nd part. In the 1st part, ``(\d+)``, will match the number part of the node name and put that in a variable called ``$1``. The 2nd part is what value to give the ``ip`` attribute. In this case it will set it to the string "10.0.0." and the number that is in ``$1``. (Zero is added to ``$1`` just to remove any leading zeros.)

A more involved example is with the ``vm`` table. If your kvm nodes have node names c01f01x01v01, c01f02x03v04, etc., and the kvm host names are c01f01x01, c01f02x03, etc., then you might have an ``vm`` table like ::

    #node,mgr,host,migrationdest,storage,storagemodel,storagecache,storageformat,cfgstore,memory,cpus,nics,nicmodel,bootorder,clockoffset,virtflags,master,vncport,textconsole,powerstate,beacon,datacenter,cluster,guestostype,othersettings,physlots,vidmodel,vidproto,vidpassword,comments,disable
   "kvms",,"|\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)|c($1)f($2)x($3)|",,"|\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)|dir:///install/vms/vm($4+0)|",,,,,"3072","2","virbr2","virtio",,,,,,,,,,,,,,,,,,   

Before you panic, let me explain each column:

``kvms``

    This is a group name. In this example, we are assuming that all of your kvm nodes belong to this group. Each time the xCAT software accesses the ``vm`` table to get the kvm host ``host`` and storage file ``vmstorage`` of a specific kvm node (e.g. c01f02x03v04), this row will match (because c01f02x03v04 is in the kvms group). Once this row is matched for c01f02x03v04, then the processing described in the following items will take place.

``|\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)|c($1)f($2)x($3)|``

    This is a perl substitution pattern that will produce the value for the 3rd column of the table (the kvm host). The text ``\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)`` between the 1st two vertical bars is a regular expression that matches the node name that was searched for in this table (in this example c01f02x03v04). The text that matches within the 1st set of parentheses is set to ``$1``, 2nd set of parentheses is set to ``$2`` ,3rd set of parentheses is set to ``$3``,and so on. In our case, the ``\D+`` matches the non-numeric part of the name ("c","f","x","v") and the ``\d+`` matches the numeric part ("01","02","03","04"). So ``$1`` is set to "01", ``$2`` is set to "02", ``$3`` is set to "03", and ``$4`` is set to "04". The text ``c($1)f($2)x($3)`` between the 2nd and 3rd vertical bars produces the string that should be used as the value for the ``host`` attribute for c01f02x03v04, i.e,"c01f02x03".

``|\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)|dir:///install/vms/vm($4+0)|``

    This item is similar to the one above. This substitution pattern will produce the value for the 5th column (a list of storage files or devices to be used). Because this row was the match for "c01f02x03v04", the produced value is "dir:///install/vms/vm4".

Just as the explained above, when the node definition "c01f02x03v04" is created  with ::

    # mkdef -t node -o c01f02x03v04 groups=kvms
    1 object definitions have been created or modified.

The generated node definition is ::

    # lsdef c01f02x03v04
    Object name: c01f02x03v04
        groups=kvms
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles
        vmcpus=2
        vmhost=c01f02x03
        vmmemory=3072
        vmnicnicmodel=virtio
        vmnics=virbr2
        vmstorage=dir:///install/vms/vm4

See `perlre <http://www.perl.com/doc/manual/html/pod/perlre.html>`_ for more information on perl regular expressions.


Easy Regular expressions
------------------------

As of xCAT 2.8.1, you can use a modified version of the regular expression support described in the previous section. You do not need to enter the node information (1st part of the expression), it will be derived from the input nodename. You only need to supply the 2nd part of the expression to determine the value to give the attribute. 

For example:

If node1 is assigned the IP address 10.0.0.1, node2 is assigned the IP address 10.0.0.2, etc., then this could be represented in the ``hosts`` table with the single row:

Using full regular expression support you would put this in the ``hosts`` table. ::

    chdef -t group compute ip="|node(\d+)|10.0.0.($1+0)|"
    tabdump hosts
    #node,ip,hostnames,otherinterfaces,comments,disable
    "compute","|node(\d+)|10.0.0.($1+0)|",,,,

Using easy regular expression support you would put this in the hosts table. ::

    chdef -t group compute ip="|10.0.0.($1+0)|"
    tabdump hosts
    #node,ip,hostnames,otherinterfaces,comments,disable
    "compute","|10.0.0.($1+0)|",,,,

In the easy regx example, the expression only has the 2nd part of the expression from the previous example. xCAT will evaluate the node name, matching the number part of the node name, and create the 1st part of the expression . The 2nd part supplied is what value to give the ip attribute. The resulting output is the same.


Verify your regular expression
------------------------------

After you create your table with regular expression, make sure they are evaluating as you expect. ::

     lsdef node1 | grep ip
       ip=10.0.0.1

