PDUs
====

Power Distribution Units (PDUs) are devices that distribute power to servers in a frame.  They have the capability of monitoring the amount of power that is being used by devices plugged into it and cycle power to individual receptacles.  xCAT can support two kinds of PDUs, infrastructure PDU (irpdu) and collaborative PDU (crpdu).  These two types of PDU have different design and implementation.  xCAT has different code path to maintains PDU commands via **pdutype**.  


.. toctree::
   :maxdepth: 2

   pdu.rst
   irpdu.rst
   crpdu.rst
