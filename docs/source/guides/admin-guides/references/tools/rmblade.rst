rmblade
=======

::

    Usage: rmblade [-h|--help]

    Response to SNMP for monsetting to remove blade from xCAT when trap is recieved.
    Pipe the MM IP address and blade slot number into this cmd.

    Example: 
     1.  user removes a blade from the chassis
     2.  snmp trap setup to point here
     3.  this script removes the blade configuration from xCAT
     4.  so if blade is placed in new slot or back in then xCAT goes 
         through rediscover process again.
    
Author:  Jarrod Johnson
