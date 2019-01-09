
##########
lshwconn.1
##########

.. highlight:: perl


****
NAME
****


\ **lshwconn**\  - Use this command to display the connection status for CEC and Frame nodes.


********
SYNOPSIS
********


\ **lshwconn**\  [\ **-h**\ | \ **-**\ **-help**\ ]

\ **lshwconn**\  [\ **-v**\ | \ **-**\ **-version**\ ]

PPC (with HMC) specific:
========================


\ **lshwconn**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\ 


PPC (without HMC, using FSPAPI) specific:
=========================================


\ **lshwconn**\  \ *noderange*\  \ **-T**\  \ *tooltype*\ 



***********
DESCRIPTION
***********


This command is used to display the connection status for CEC and Frame node.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 


\ **-T**\ 
 
 The tooltype is used to communicate to the CEC/Frame. The value could be lpar or fnm. The tooltype value lpar is for xCAT and fnm is for CNM.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1.
 
 To display connection status for all CEC nodes in node group CEC:
 
 
 .. code-block:: perl
 
   lshwconn cec
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   cec1: ipaddr=192.168.200.245,alt_ipaddr=unavailable,state=Connected
   cec2: Connection not found
 
 


2.
 
 To display connection status for Frame node frame1:
 
 
 .. code-block:: perl
 
   lshwconn frame1
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   frame1: side=a,ipaddr=192.168.200.247,alt_ipaddr=unavailable,state=Connected
   frame1: side=b,ipaddr=192.168.200.248,alt_ipaddr=unavailable,state=Connected
 
 


3.
 
 To display connection status for all CEC nodes in node group CEC to hardware server, and using lpar tooltype:
 
 
 .. code-block:: perl
 
   lshwconn cec -T lpar
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   cec1: sp=primary,ipadd=40.3.7.1,alt_ipadd=unavailable,state=LINE UP
   cec2: Connection not found
 
 



*****
FILES
*****


$XCATROOT/bin/lshwconn

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


rmhwconn(1)|rmhwconn.1, mkhwconn(1)|mkhwconn.1

