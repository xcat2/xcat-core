
##########
rmhwconn.1
##########

.. highlight:: perl


****
NAME
****


\ **rmhwconn**\  - Use this command to remove connections from CEC and Frame nodes to HMC nodes.


********
SYNOPSIS
********


\ **rmhwconn**\  [\ **-h**\ | \ **-**\ **-help**\ ]

\ **rmhwconn**\  [\ **-v**\ | \ **-**\ **-version**\ ]

PPC (with HMC) specific:
========================


\ **rmhwconn**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\ 


PPC (without HMC, using FSPAPI) specific:
=========================================


\ **rmhwconn**\  \ *noderange*\  \ **-T**\  \ *tooltype*\ 


PPC (use HMC as SFP) specific:
==============================


\ **rmhwconn**\  \ **-s**\ 



***********
DESCRIPTION
***********


For PPC (with HMC) specific:

This command is used to disconnect CEC and Frame nodes from HMC nodes, according to the connection information defined in ppc talbe in xCAT DB.

Note: If a CEC belongs to a frame with a BPA installed, this CEC cannot be disconnected individually. Instead, the whole frame should be disconnected.

For PPC (without HMC, using FSPAPI) specific:

It's used to disconnection CEC and Frame nodes from hardware server.

For PPC (use HMC as SFP) specific:

It is used to disconnect Frame nodes from HMC nodes.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 


\ **-T**\ 
 
 The tooltype is used to communicate to the CEC/Frame. The value could be \ **lpar**\  or \ **fnm**\ . The tooltype value \ **lpar**\  is for xCAT and \ **fnm**\  is for CNM.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1.
 
 To disconnect all CEC nodes in node group cec from their HMC nodes:
 
 
 .. code-block:: perl
 
   rmhwconn cec
 
 


2.
 
 To remove the connection for Frame node frame1:
 
 
 .. code-block:: perl
 
   rmhwconn frame1
 
 


3.
 
 To disconnect all CEC nodes in node group cec from their related hardware serveri, using lpar tooltype:
 
 
 .. code-block:: perl
 
   rmhwconn cec -T lpar
 
 



*****
FILES
*****


$XCATROOT/bin/rmhwconn

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


lshwconn(1)|lshwconn.1, mkhwconn(1)|mkhwconn.1

