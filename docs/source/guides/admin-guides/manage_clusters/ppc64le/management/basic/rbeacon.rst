``rbeacon`` - Beacon Light 
==========================

See :doc:`rbeacon manpage </guides/admin-guides/references/man1/rbeacon.1>` for more information.


Most enterprise level servers have LEDs on their front and/or rear panels, one of which is a beacon light.  If turned on, this light can help assist the system administrator locate one physical machine out of a large number of machines in a frame.

Using xCAT, administrators can turn on and off the beacon light using: ``rbeacon <node> on|off`` 

There's currently no way to query whether the beacon light is on or off.  To work around, first turn off all the lights and then turn on the beacon for the machine you wish to identify: ::

    rbeacon <noderange> off 
    rbeacon <node> on 
