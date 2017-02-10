/nodes/{noderange}/vitals/{temp|voltage|wattage|fanspeed|power|leds...}
=======================================================================

GET - Get the specific vitals attibutes
---------------------------------------

Refer to the man page: :doc:`rvitals </guides/admin-guides/references/man1/rvitals.1>`

**Returns:**

* Json format: An object which includes multiple '<name> : {att:value, attr:value ...}' pairs.

**Example:** 

Get the 'fanspeed' vitals attribute. :: 

    curl -X GET -k 'https://127.0.0.1/xcatws/nodes/node1/vitals/fanspeed?userName=root&userPW=cluster&pretty=1'
    {
       "node1":{
          "Fan 1A Tach":"3219 RPM",
          "Fan 4B Tach":"2688 RPM",
          "Fan 3B Tach":"2560 RPM",
          "Fan 4A Tach":"3330 RPM",
          "Fan 2A Tach":"3293 RPM",
          "Fan 1B Tach":"2592 RPM",
          "Fan 3A Tach":"3182 RPM",
          "Fan 2B Tach":"2592 RPM"
       }
    }
