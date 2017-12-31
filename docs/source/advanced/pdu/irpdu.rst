Infrastructure PDU
==================

Users can access Infrastructure PDU via telnet and use the **IBM PDU Configuration Utility** to set up and configure the PDU. xCAT supports PDU commands for power management and monitoring through SNMP.


PDU Commands
------------

Administrators will need to know the exact mapping of the outlets to each server in the frame.  xCAT cannot validate the physical cable is connected to the correct server.

Add a ``pdu`` attribute to the compute node definition in the form "PDU_Name:outlet": ::

    #
    # Compute server cn01 has two power supplies
    # connected to outlet 6 and 7 on pdu=f5pdu3
    #
    chdef cn01 pdu=f5pdu3:6,f5pdu3:7


The following commands are supported against a compute node:

   * Check the pdu status for a compute node: ::

       # rpower cn01 pdustat
         cn01: f5pdu3 outlet 6 is on
         cn01: f5pdu3 outlet 7 is on


   * Power off the PDU outlets for a compute node: ::

       # rpower cn01 pduoff
         cn01: f5pdu3 outlet 6 is off
         cn01: f5pdu3 outlet 7 is off

   * Power on the PDU outlets for a compute node: ::

       # rpower cn01 pduon
         cn01: f5pdu3 outlet 6 is on
         cn01: f5pdu3 outlet 7 is on

   * Power cycling the PDU outlets for a compute node: ::

       # rpower cn01 pdureset
         cn01: f5pdu3 outlet 6 is reset
         cn01: f5pdu3 outlet 7 is reset

The following commands are supported against a PDU:

   * To change hostname of IR PDU: ::

       # rspconfig f5pdu3 hosname=f5pdu3

   * To change ip address of IR PDU: ::

       # rsconfig f5pdu3 ip=x.x.x.x netmaks=255.x.x.x

   * Check the status of the full PDU: ::

       # rpower f5pdu3 stat
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

   * Power reset the full PDU: ::

       # rpower f5pdu3 reset
         f5pdu3: outlet 1 is reset
         f5pdu3: outlet 2 is reset
         f5pdu3: outlet 3 is reset
         f5pdu3: outlet 4 is reset
         f5pdu3: outlet 5 is reset
         f5pdu3: outlet 6 is reset
         f5pdu3: outlet 7 is reset
         f5pdu3: outlet 8 is reset
         f5pdu3: outlet 9 is reset
         f5pdu3: outlet 10 is reset
         f5pdu3: outlet 11 is reset
         f5pdu3: outlet 12 is reset

   * PDU inventory information: ::

       # rinv f6pdu16
         f6pdu16: PDU Software Version: "OPDP_sIBM_v01.3_2"
         f6pdu16: PDU Machine Type: "1U"
         f6pdu16: PDU Model Number: "dPDU4230"
         f6pdu16: PDU Part Number: "46W1608"
         f6pdu16: PDU Name: "IBM PDU"
         f6pdu16: PDU Serial Number: "4571S9"
         f6pdu16: PDU Description: "description"

   * PDU and outlet power information: ::

       # rvitals f6pdu15
         f6pdu15: Voltage Warning: 0
         f6pdu15: outlet 1 Current: 0 mA
         f6pdu15: outlet 1 Max Capacity of the current: 16000 mA
         f6pdu15: outlet 1 Current Threshold Warning: 9600 mA
         f6pdu15: outlet 1 Current Threshold Critical: 12800 mA
         f6pdu15: outlet 1 Last Power Reading: 0 Watts
         f6pdu15: outlet 2 Current: 0 mA
         f6pdu15: outlet 2 Max Capacity of the current: 16000 mA
         f6pdu15: outlet 2 Current Threshold Warning: 9600 mA
         f6pdu15: outlet 2 Current Threshold Critical: 12800 mA
         f6pdu15: outlet 2 Last Power Reading: 0 Watts
         f6pdu15: outlet 3 Current: 1130 mA
         f6pdu15: outlet 3 Max Capacity of the current: 16000 mA
         f6pdu15: outlet 3 Current Threshold Warning: 9600 mA
         f6pdu15: outlet 3 Current Threshold Critical: 12800 mA
         f6pdu15: outlet 3 Last Power Reading: 217 Wattsv

**Note:** For BMC based compute nodes, turning the PDU outlet power on does not automatically power on the compute side.  Users will need to issue ``rpower <node> on`` to power on the compute side after the BMC boots.








