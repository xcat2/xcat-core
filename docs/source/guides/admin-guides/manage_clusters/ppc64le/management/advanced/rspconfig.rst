``rspconfig`` - Remote Configuration of Service Processors
==========================================================

Here comes the command, ``rspconfig``. It is used to configure the service processor of a physical machine. On a OpenPower system, the service processor is the BMC, Baseboard Management Controller. Various variables can be set through the command. Also notice, the actual configuration may change among different machine-model types.

Examples

To turn on SNMP alerts for cn5: ::

    rspconfig cn5 alert=on
