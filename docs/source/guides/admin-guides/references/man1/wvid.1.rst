
######
wvid.1
######

.. highlight:: perl


************
\ **Name**\ 
************


wvid - windowed remote video console for nodes


****************
\ **Synopsis**\ 
****************


\ **wvid**\  \ *noderange*\ 


*******************
\ **Description**\ 
*******************


\ **wvid**\  provides access to the remote node video console of a single node, or range of nodes or groups.
\ **wvid**\  provides a simple front-end to the hardware's remote console capability.
Currently this command is supported for:  blades, BMC/IMM, KVM, and Xen

The \ **nodehm.cons**\  attribute of the node determines the method used to open the console.  See nodehm(5)|nodehm.5 for further details.


***************
\ **Options**\ 
***************


No options are supported at this time.


****************
\ **Examples**\ 
****************



1.
 
 To open video consoles for the 1st 2 nodes:
 
 
 .. code-block:: perl
 
   wvid node1,node2
 
 



****************
\ **See Also**\ 
****************


noderange(3)|noderange.3, rcons(1)|rcons.1, wcons(1)|wcons.1

