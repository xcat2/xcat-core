PDU
===

xCAT provides basic remote management for each power outlet plugged into the PDUs using SNMP communication.  This documentation will focus on configuration of the PDU and Node objects to allow xCAT to control power at the PDU outlet level.  


Define PDU Objects
------------------



#. Define pdu object ::

    mkdef f5pdu3 groups=pdu ip=50.0.0.8 mgt=pdu nodetype=pdu

#. Add hostname to /etc/hosts::

    makehosts f5pdu3

#. Verify the SNMP command responds against the PDU: ::

    snmpwalk -v1 -cpublic -mALL f5pdu3 .1.3.6.1.2.1.1


Define PDU Attribute
--------------------

Administrators will need to know the exact mapping of the outlets to each server in the frame.  xCAT cannot validate the physical cable is connected to the correct server. 

Add a ``pdu`` attribute to the compute node definition in the form "PDU_Name:outlet": ::

    #
    # Compute server cn01 has two power supplies 
    # connected to outlet 6 and 7 on pdu=f5pdu3
    #
    chdef cn01 pdu=f5pdu3:6,f5pdu3:7


Verify the setting: ``lsdef cn01 -i pdu``


PDU Commands
------------

The following commands are supported against a compute node: 

   * Check the pdu status for a compute node: ::
   
       # rpower cn01 pdustat
         cn01: f5pdu3 outlet 6 is on
         cn01: f5pdu3 outlet 7 is on


   * Power off the PDU outlets on a compute node: :: 
   
       # rpower cn01 pduoff
         cn01: f5pdu3 outlet 6 is off
         cn01: f5pdu3 outlet 7 is off

   * Power on the PDU outlets on a compute node: :: 
   
       # rpower cn01 pduon
         cn01: f5pdu3 outlet 6 is on
         cn01: f5pdu3 outlet 7 is on

The following commands are supported against a PDU: 

   * Check the status of the full PDU: ::

       # rinv f5pdu3
         f5pdu3: outlet 1 is on
         f5pdu3: outlet 2 is on
         f5pdu3: outlet 3 is on
         f5pdu3: outlet 4 is on
         f5pdu3: outlet 5 is on
         f5pdu3: outlet 6 is off
         f5pdu3: outlet 7 is off
         f5pdu3: outlet 8 is on
         f5pdu3: outlet 9 is on
         f5pdu3: outlet 10 is on
         f5pdu3: outlet 11 is on
         f5pdu3: outlet 12 is on

   * Power off the full PDU: ::
   
       # rpower f5pdu3 off
         f5pdu3: outlet 1 is off
         f5pdu3: outlet 2 is off
         f5pdu3: outlet 3 is off
         f5pdu3: outlet 4 is off
         f5pdu3: outlet 5 is off
         f5pdu3: outlet 6 is off
         f5pdu3: outlet 7 is off
         f5pdu3: outlet 8 is off
         f5pdu3: outlet 9 is off
         f5pdu3: outlet 10 is off
         f5pdu3: outlet 11 is off
         f5pdu3: outlet 12 is off

   * Power on the full PDU: ::
   
       # rpower f5pdu3 on
         f5pdu3: outlet 1 is on
         f5pdu3: outlet 2 is on
         f5pdu3: outlet 3 is on
         f5pdu3: outlet 4 is on
         f5pdu3: outlet 5 is on
         f5pdu3: outlet 6 is on
         f5pdu3: outlet 7 is on
         f5pdu3: outlet 8 is on
         f5pdu3: outlet 9 is on
         f5pdu3: outlet 10 is on
         f5pdu3: outlet 11 is on
         f5pdu3: outlet 12 is on
   
   
**Note:** For BMC based compute nodes, turning the PDU outlet power on does not automatically power on the compute side.  Users will need to issue ``rpower <node> on`` to power on the compute node after the BMC boots. 








