OpenPOWER Nodes
===============


When compute nodes are physically replaced in the frame, leverage xCAT to re-discover the compute nodes.  The following guide can be used for:

  * IBM OpenPOWER S822LC for HPC


#. Identify the machine(s) to be replaced: ``frame10cn02``.

#. [**Optional**] It's recommended to set the BMC IP address back to DHCP, if it was set to STATIC. ::

    rspconfig frame10cn02 ip=dhcp

#. Set the outgoing machine to ``offline`` and remove attributes of the machine: ::

    nodeset frame10cn02 offline
    chdef frame10cn02 mac=""

#. If using **MTMS**-based discovery, fill in the Model-Type and Serial Number for the machine: ::

    chdef frame10cn02 mtm=8335-GTB serial=<NEW SERIAL NUMBER>

#. If using **SWITCH**-based discovery, go on to the next step. The ``switch`` and ``switch-port`` should already be set in the compute node definition.

   Node attributes will be replaced during the discovery process (mtm, serial, mac, etc.)

#. Search for the new BMC in the open range: ::

    bmcdiscover --range <IP open range> -w -z

#. When the BMC is found, start the discovery with the following commands: ::

    rsetboot /node-8335.* net
    rpower /node-8335.* boot


