PDUs
====

Power Distribution Units (PDUs) are devices that distribute power to servers in a frame.  They have the capability of monitoring the amount of power that is being used by devices plugged into it and cycle power to individual receptacles.  xCAT can support two kinds of PDUs, infrastructure PDU (irpdu) and collaborative PDU (crpdu).

The Infrastructure rack PDUs are switched and monitored 1U PDU products which can connect up to nine C19 devices or up to 12 C13 devices and an additional three C13 peripheral devices to a signle dedicated power source.  The Collaborative PDU is on the compute rack and has the 6x IEC 320-C13 receptacles that feed the rack switches. These two types of PDU have different design and implementation.  xCAT has different code path to maintains PDU commands via **pdutype**.


.. toctree::
   :maxdepth: 2

   pdu.rst
   irpdu.rst
   crpdu.rst
