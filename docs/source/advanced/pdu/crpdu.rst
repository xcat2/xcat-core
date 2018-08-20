Collaborative PDU
=================

Collaborative PDU is also referred as Coral PDU, it controls power for compute Rack. User can access PDU via SSH and can use the **PduManager** command to configure and manage the PDU product.


Pre-Defined PDU Objects
-----------------------

A pre-defined PDU node object is required before running pdudiscover command. ::

        mkdef coralpdu groups=pdu mgt=pdu nodetype=pdu    (required)

all other attributes can be set by chdef command or pdudisocover command. ::

    --switch     required for pdudiscover command to do mapping
    --switchport required for pdudiscover command to do mapping
    --ip         ip address of the pdu.
    --mac        can be filled in by pdudiscover command
    --pdutype    crpdu(for coral pdu) or irpdu(for infrastructure PDUs)


The following attributes need to be set in order to configure snmp with non-default values. ::

    --community  community string for coral pdu
    --snmpversion snmp version number, required if configure snmpv3 for coral pdu
    --snmpuser    snmpv3 user name, required if configure snmpv3 for coral pdu
    --authkey     auth passphrase for snmpv3 configuration
    --authtype    auth protocol (MD5|SHA) for snmpv3 configuration
    --privkey     priv passphrase for snmpv3 configuration
    --privtype    priv protocol (AES|DES) for snmpv3 configuration
    --seclevel    security level (noAuthNoPriv|authNoPriv|authPriv) for snmpv3 configuration

Make sure to run makehosts after pre-defined PDU. ::

    makehosts coralpdu


Configure PDUs
--------------

After pre-defining PDUs, user can use **pdudisocver --range ip_range --setup** to configure the PDUs, or following commands can be used:

    * To configure passwordless of Coral PDU: ::

        # rspconfig coralpdu sshcfg

    * To change hostname of Coral PDU: ::

        # rspconfig coralpdu hosname=f5pdu3

    * To change ip address of PDU: ::

        # rsconfig coralpdu ip=x.x.x.x netmaks=255.x.x.x

    * To configure SNMP community string or snmpv3  of PDU (the attribute needs to pre-defined): ::

        # rspconfig coralpdu snmpcfg


Remote Power Control of PDU
---------------------------

Use the rpower command to remotely power on and off PDU.

    * To check power stat of PDU: ::

        # rpower coralpdu stat

    * To power off the PDU: ::

        # rpower coralpdu off

    * To power on the PDU: ::

        # rpower coralpdu on

Coral PDUs have three relays, the following commands are for individual relay support of PDU:

    * To check power stat of relay: ::

        # rpower coralpdu relay=1 stat

    * To power off the relay: ::

        # rpower coralpdu relay=2 off

    * To power on the relay: ::

        # rpower coralpdu relay=3 on


Show Monitor Data
-----------------

Use the rvitals command to show realtime monitor data(input voltage, current, power) of PDU. ::

    # rvitals coralpdu


Show manufacture information
-----------------------------

Use the rinv command to show MFR information of PDU ::

    # rinv coralpdu



