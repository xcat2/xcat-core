Discovering PDUs
================

xCAT provides `pdudiscover` command to discover the PDUs that are attached to the neighboring subnets on xCAT management node. ::

    pdudiscover [<noderange>|--range ipranges] [-r|-x|-z] [-w] [-V|--verbose] [--setup]

xCAT uses snmp scan method to discover PDU.  Make sure net-snmp-utils package is installed on xCAT MN in order to use snmpwalk command. ::

    Options:
     --range   Specify one or more IP ranges. Each can be an ip address (10.1.2.3) or an ip range
                 (10.1.2.0/24). If the range is huge, for example, 192.168.1.1/8, the pdu
                 discover may take a very long time to scan. So the range should be exactly
                 specified.  It accepts multiple formats. For example:
                 192.168.1.1/24, 40-41.1-2.3-4.1-100.

                 If the range is not specified, the command scans all the subnets that the active
                 network interfaces (eth0, eth1) are on where this command is issued.
       -r        Display Raw responses.
       -x        XML formatted output.
       -z        Stanza formatted output.
       -w        Writes output to xCAT database.
       --setup   Process switch-based pdu discovery and configure the PDUs. For crpdu, --setup options will configure passwordless , change ip address from dhcp to static, hostname changes and snmp v3 configuration. For irpdu, it will configure ip address and hostname.  It required predefined PDU node definition with switch name and switch port attributes for mapping.


Define PDU Objects
------------------


#. Define pdu object ::

    mkdef f5pdu3 groups=pdu ip=50.0.0.8 mgt=pdu nodetype=pdu pdutype=irpdu

#. Define switch attribute for pdu object which will be used for pdudiscover **--setup** options. ::

    chdef f5pdu3 switch=mid08 switchport=3

#. Add hostname to /etc/hosts::

    makehosts f5pdu3

#. Verify the SNMP command responds against the PDU: ::

    snmpwalk -v1 -cpublic -mALL f5pdu3 system


