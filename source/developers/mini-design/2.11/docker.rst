Mini-design for Docker Support
==============================

Overview
--------

Docker technology is very hot recently, xCAT plans to support it as a way to deploy applictions.

Interface
---------

General Command Line
^^^^^^^^^^^^^^^^^^^^

Will add several new commands to support docker.

* docker create

  * Create only
  * Start after creating

* docker stop

Stop the docker container

* docker remove

Rest API
^^^^^^^^

Add xCAT Rest API to support docker.

* docker create

URI - /xcatws/<node>/start

::
  #curl 
  #wget

Add a Table
^^^^^^^^^^^
+-----------+------------+-------------+
|Operation  |Params      |Result       |
+===========+============+=============+
|GET        |node        |on/off       |
+-----------+------------+-------------+
|PUT        |node        |on/off       |
+-----------+------------+-------------+
