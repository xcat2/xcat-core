
##########
rspreset.1
##########

.. highlight:: perl


****
Name
****


\ **rspreset**\  - resets the service processors associated with the specified nodes


****************
\ **Synopsis**\ 
****************


\ **rspreset**\  \ *noderange*\ 

\ **rspreset**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **rspreset**\  resets the service processors associated with the specified nodes.  It searches
the \ **nodehm**\  table and associated tables to find the service processors associated with the nodes
specified.  If the node is a BMC-based node, the node's BMC will be reset.  If the node is a blade,
the blade's on board service processor will be reset.


***************
\ **Options**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



****************
\ **Examples**\ 
****************



1.
 
 Reset the service processor that controls node5:
 
 
 .. code-block:: perl
 
   rspreset node5
 
 



****************
\ **SEE ALSO**\ 
****************


rpower(1)|rpower.1, nodehm(5)|nodehm.5

