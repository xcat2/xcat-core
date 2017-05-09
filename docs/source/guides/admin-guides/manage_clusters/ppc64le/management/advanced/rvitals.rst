``rvitals`` - Remote Hardware Vitals 
==================================== 

Collect runtime information from running physical machine is also a big requirement for real life system administrators. This kind of information includes, temperature of CPU, internal voltage of particular socket, wattage with workload, speed of cooling fan, et al.

In order to get such information, use ``rvitals`` command. This kind of information varies among different model types of the machine. Thus, check the actual output of the ``rvitals`` command against your machine, to verify which kinds of information can be extracted. The information may change after the firmware update of the machine.  ::

    rvitals cn1 all

As an example, get only the temperature information of a particular machine. ::

    rvitals cn1 temp

