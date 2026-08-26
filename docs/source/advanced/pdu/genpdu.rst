Generic SNMP PDU
================

The generic SNMP PDU support (``pdutype=genpdu``) drives any PDU that implements the Raritan **PDU2-MIB**. A single MIB covers the Raritan PX2, PX3, PX4, PXC, SRC, PXO and BCM series, the Server Technology PRO3X and PRO4X series, and the Legrand intelligent PDUs, so the same code path applies to all of them without per-model configuration.

xCAT communicates with these PDUs over SNMP v1, v2c or v3, using the credentials in the ``pdu`` table. Unlike the other PDU types, the sensor scaling factors and units are read from the device rather than hardcoded, so readings are correct on any model regardless of the precision it reports.


Defining a PDU
--------------

Create the PDU node definition and set the SNMP credentials in the ``pdu`` table.

For SNMP v2c: ::

    mkdef mypdu groups=pdu nodetype=pdu mgt=pdu pdutype=genpdu
    chdef mypdu snmpversion=2 community=<community>

For SNMP v3: ::

    mkdef mypdu groups=pdu nodetype=pdu mgt=pdu pdutype=genpdu
    chdef mypdu snmpversion=3 snmpuser=<user> \
                authtype=SHA authkey=<passphrase> \
                privtype=AES privkey=<passphrase> seclevel=authPriv

The ``seclevel`` attribute is optional. When it is not set, ``authPriv`` is used if ``privtype`` is set and ``authNoPriv`` otherwise. When ``privkey`` is not set it falls back to ``authkey``. If ``authtype`` or ``privtype`` are not set they default to ``SHA`` and ``DES``.

The ``outlet`` attribute is discovered automatically from the MIB on first use and cached in the ``pdu`` table. It can also be set explicitly to skip the discovery query.


Switched and metered PDUs
-------------------------

PDU2-MIB covers both switched models and metered-only models. xCAT detects which it is talking to at connection time, so no configuration is needed to distinguish them.

On a metered-only PDU, ``rinv`` and ``rvitals`` work normally, and the power control commands report that switching is unavailable rather than failing per outlet: ::

    # rpower mypdu stat
      mypdu: this PDU does not support outlet switching

Writing to a switched PDU requires credentials with write access. SNMP agents on these devices commonly grant read-only access by default, in which case xCAT reports ``noAccess`` on power commands while read commands continue to work. Configure a read-write community, or an SNMP v3 user with write permission, on the PDU itself.


PDU Commands
------------

Administrators will need to know the exact mapping of the outlets to each server in the frame.  xCAT cannot validate the physical cable is connected to the correct server.

Add a ``pdu`` attribute to the compute node definition in the form "PDU_Name:outlet": ::

    #
    # Compute server cn01 has two power supplies
    # connected to outlet 6 and 7 on pdu=mypdu
    #
    chdef cn01 pdu=mypdu:6,mypdu:7

The following commands are supported against a compute node:

   * Check the pdu status for a compute node: ::

       # rpower cn01 pdustat
         cn01: mypdu operational state for outlet 6 is on
         cn01: mypdu operational state for outlet 7 is on

   * Power off the PDU outlets for a compute node: ::

       # rpower cn01 pduoff
         cn01: mypdu operational state for outlet 6 is off
         cn01: mypdu operational state for outlet 7 is off

   * Power on the PDU outlets for a compute node: ::

       # rpower cn01 pduon
         cn01: mypdu operational state for outlet 6 is on
         cn01: mypdu operational state for outlet 7 is on

   * Power cycling the PDU outlets for a compute node: ::

       # rpower cn01 pdureset
         cn01: mypdu operational state for outlet 6 is reset
         cn01: mypdu operational state for outlet 7 is reset

The following commands are supported against a PDU:

   * Check the status of the full PDU: ::

       # rpower mypdu stat
         mypdu: operational state for the outlet 1 is on
         mypdu: operational state for the outlet 2 is on
         mypdu: operational state for the outlet 3 is on

   * Power off, on or reset the full PDU: ::

       # rpower mypdu off
       # rpower mypdu on
       # rpower mypdu reset

   * PDU inventory information: ::

       # rinv mypdu
         mypdu: PDU Manufacturer: Raritan
         mypdu: PDU Model: PX4-5851-E7V2
         mypdu: PDU Serial Number: XXXXXXXXXX
         mypdu: PDU Rated Voltage: 360-415V
         mypdu: PDU Rated Current: 24A
         mypdu: PDU Rated Frequency: 50/60Hz
         mypdu: PDU Rated VA: 15.0-17.3kVA
         mypdu: PDU Inlet Count: 1
         mypdu: PDU Overcurrent Protector Count: 6
         mypdu: PDU Outlet Count: 36
         mypdu: PDU Description: Raritan PDU, MD:PX4-5851-E7V2 HW:0x1D FW:4.2.10.5-50400

   * PDU and outlet power information: ::

       # rvitals mypdu
         mypdu: inlet 1 RMS Voltage: 412 V
         mypdu: inlet 1 RMS Current: 13.959 A
         mypdu: inlet 1 Active Power: 8879 W
         mypdu: inlet 1 Apparent Power: 8950 VA
         mypdu: inlet 1 Power Factor: 0.99
         mypdu: inlet 1 Frequency: 60.0 Hz
         mypdu: inlet 1 Unbalanced Current: 11 %
         mypdu: inlet 1 Reactive Power: -1360 var
         mypdu: inlet 1 Active Energy: 145702407 Wh
         mypdu: inlet 1 Apparent Energy: 147093631 VAh
         mypdu: outlet 1 RMS Current: 0.000 A
         mypdu: outlet 1 Active Power: 0 W
         mypdu: outlet 1 Active Energy: 0 Wh
         mypdu: outlet 2 RMS Current: 2.793 A
         mypdu: outlet 2 Active Power: 660 W
         mypdu: outlet 2 Active Energy: 9794434 Wh

     Units and decimal precision are read from the MIB for each sensor rather
     than being hardcoded, so readings are correct on any model without
     per-model configuration. The same sensor can therefore be reported at
     different precision on different models: for example inlet RMS current
     appears as ``13.959 A`` on a PX4 and ``18.1 A`` on a PX2, because the two
     devices declare a different number of decimal digits for it.

     Sensors that can read negative, such as reactive power, are taken from the
     signed value column of the MIB, which the device selects through the
     sensor's signed minimum. The unsigned column is used for every other
     sensor, including wide-range ones such as active energy, where the signed
     column does not apply.

     Sensors that the device does not report are omitted, so the exact set of
     lines varies by model. Per-outlet sensors are skipped entirely on models
     that do not meter individual outlets. The reported sensor types are a
     fixed list in the plugin and can be extended by adding entries to it;
     types with no name defined are reported as ``sensor <N>``.

**Note:** ``rspconfig`` is not supported for ``pdutype=genpdu``. Network and hostname configuration should be done on the PDU itself.

**Note:** For BMC based compute nodes, turning the PDU outlet power on does not automatically power on the compute side.  Users will need to issue ``rpower <node> on`` to power on the compute side after the BMC boots.


Limitations
-----------

   * PDU linking (cascading multiple PDUs behind one management interface) is not supported. The MIB indexes outlets by link ID, and xCAT assumes the value used by unlinked units, so only the primary unit is managed. BCM2 and PMC power meters are out of scope for the same reason. A PDU reporting more than one unit is not refused, but every command against it warns that only the primary unit is being driven.

   * ``authtype``, ``privtype`` and the other SNMP attributes are per-PDU attributes in the ``pdu`` table, so PDUs using different SNMP protocols need their values set individually.


Tested hardware
---------------

   * Raritan PX4-5851-E7V2, firmware 4.2.10.5-50400 (switched, 36 outlets)
   * Raritan PX3-1901U-N1 and PX3-1901U-N1A6, firmware 4.0.20.5-49038 (metered, 48 outlets)
   * Raritan PX2-1901U-N1A6, firmware 4.0.20.5-49038 (metered, 48 outlets)
