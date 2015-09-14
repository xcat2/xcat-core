GROUPS AND REGULAR EXPRESSIONS IN TABLES
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

In this example, the regular expression in the ``ip`` attribute uses ``|`` to separate the 1st and 2nd part. This means that xCAT will allow arithmetic operations in the 2nd part. In the 1st part, ``(\d+)``, will match the number part of the node name and put that in a variable called ``$1``. The 2nd part is what value to give the ``ip`` attribute. In this case it will set it to the string "10.0.0." and the number that is in ``$1``. (Zero is added to ``$1`` just to remove any leading zeroes.)

A more involved example is with the ``mp`` table. If your blades have node names node01, node02, etc., and your chassis node names are cmm01, cmm02, etc., then you might have an ``mp`` table like ::

    #node,mpa,id,nodetype,comments,disable
    "blade","|\D+(\d+)|cmm(sprintf('%02d',($1-1)/14+1))|","|\D+(\d+)|(($1-1)%14+1)|",,

Before you panic, let me explain each column:

``blade``

    This is a group name. In this example, we are assuming that all of your blades belong to this group. Each time the xCAT software accesses the ``mp`` table to get the management module and slot number of a specific blade (e.g. node20), this row will match (because node20 is in the blade group). Once this row is matched for node20, then the processing described in the following items will take place.

``|\D+(\d+)|cmm(sprintf('%02d',($1-1)/14+1))|``

    This is a perl substitution pattern that will produce the value for the second column of the table (the management module hostname). The text ``\D+(\d+)`` between the 1st two vertical bars is a regular expression that matches the node name that was searched for in this table (in this example node20). The text that matches within the 1st set of parentheses is set to ``$1``. (If there was a 2nd set of parentheses, it would be set to ``$2``, and so on.) In our case, the ``\D+`` matches the non-numeric part of the name (node) and the ``\d+`` matches the numeric part (20). So ``$1`` is set to 20. The text ``cmm(sprintf('%02d',($1-1)/14+1))`` between the 2nd and 3rd vertical bars produces the string that should be used as the value for the ``mpa`` attribute for node20. Since ``$1`` is set to 20, the expression ``($1-1)/14+1`` equals "19/14 + 1", which equals "2". (The division is integer division, so "19/14" equals 1. Fourteen is used as the divisor, because there are 14 blades in each chassis.) The value of 2 is then passed into sprintf() with a format string to add a leading zero, if necessary, to always make the number two digits. Lastly the string cmm is added to the beginning, making the resulting string ``cmm02``, which will be used as the hostname of the management module.

``|\D+(\d+)|(($1-1)%14+1)|``

    This item is similar to the one above. This substituion pattern will produce the value for the 3rd column (the chassis slot number for this blade). Because this row was the match for node20, the parentheses within the 1st set of vertical bars will set ``$1`` to 20. Since ``%`` means modulo division, the expression ``($1-1)%14+1`` will evaluate to 6.

See `perlre <http://www.perl.com/doc/manual/html/pod/perlre.html>`_ for information on perl regular expressions.


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

