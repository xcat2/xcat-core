
##########
lsdocker.1
##########

.. highlight:: perl


****
NAME
****


\ **lsdocker**\  - List docker instance.


********
SYNOPSIS
********


\ **lsdocker**\  \ *noderange*\  [\ **-l | -**\ **-logs**\ ]

\ **lsdocker**\  \ *dockerhost*\ 

\ **lsdocker**\  [\ **-h | -**\ **-help**\ ]

\ **lsdocker**\  {\ **-v | -**\ **-version**\ }


***********
DESCRIPTION
***********


\ **lsdocker**\  To list docker instance info or all the running docker instance info if dockerhost is specified.


*******
OPTIONS
*******



\ **-l|-**\ **-logs**\ 



To return the logs of docker instance. Only works for docker instance.


********
EXAMPLES
********



1. To get info for docker instance "host01c01"
 
 
 .. code-block:: perl
 
   lsdocker host01c01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   host01c01: 50800dfd8b5f	ubuntu	/bin/bash	2016-01-13T06:32:59	running	/host01c01
 
 


2. To get info for running docker instance on dockerhost "host01"
 
 
 .. code-block:: perl
 
   lsdocker host01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   host01: 50800dfd8b5f	ubuntu	/bin/bash	2016-1-13 - 1:32:59	Up 12 minutes	/host01c01
   host01: 875ce11d5987	ubuntu	/bin/bash	2016-1-21 - 1:12:37	Up 5 seconds	/host01c02
 
 



********
SEE ALSO
********


mkdocker(1)|mkdocker.1, rmdocker(1)|rmdocker.1

