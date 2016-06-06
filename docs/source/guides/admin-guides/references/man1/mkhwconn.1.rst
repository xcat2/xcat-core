
##########
mkhwconn.1
##########

.. highlight:: perl


****
NAME
****


\ **mkhwconn**\  - Sets up connections for CEC and Frame nodes to HMC nodes or hardware server.


********
SYNOPSIS
********


\ **mkhwconn**\  [\ **-h**\ | \ **-**\ **-help**\ ]

\ **mkhwconn**\  [\ **-v**\ | \ **-**\ **-version**\ ]

PPC (with HMC) specific:
========================


\ **mkhwconn**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ **-t**\  [\ **-**\ **-port**\  \ *port_value*\ ]

\ **mkhwconn**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ **-s**\  [\ *hmcnode*\  \ **-**\ **-port**\  \ *port_value*\ ]

\ **mkhwconn**\  [\ **-V**\ | \ **-**\ **-verbose**\ ] \ *noderange*\  \ **-p**\  \ *hmc*\  [\ **-P**\  \ *passwd*\ ] [\ **-**\ **-port**\  \ *port_value*\ ]


PPC (using Direct FSP Management) specific:
===========================================


\ **mkhwconn**\  \ *noderange*\  \ **-t**\  [\ **-T tooltype**\ ] [\ **-**\ **-port**\  \ *port_value*\ ]



***********
DESCRIPTION
***********


For PPC (with HMC) specific:

This command is used to set up connections for CEC and Frame nodes to HMC nodes. (If the connection already exists, it will not break it.)
This command is useful when you have multiple HMCs, each of which will manage a subset of the CECs/Frames.  Use \ **mkhwconn**\  to tell
each HMC which CECs/Frames it should manage.  When using this, you should turn off the self-discovery on each HMC.  You also need
to put all the HMCs and all the Frames on a single flat service network.

When \ **-t**\  is specified, this command reads the connection information from the xCAT ppc table (e.g. the parent attribute), and read the user/password from the ppcdirect table. Then this command will assign CEC nodes and Frame nodes to HMC nodes.

When \ **-p**\  is specified, this command gets the connection information from command line arguments. If \ **-P**\  is not specified, the default password for CEC and Frame nodes is used.

The flag \ **-s**\  is used to make the connection between the frame and its Service focal point(HMC). Makehwconn will also set the connections between the CECs within this Frame and the HMC. The sfp of the frame/CEC can either be defined in ppc table beforehand or specified in command line after the flag -s. If the user use mkhwconn noderange -s HMC_name, it will not only make the connections but also set the sfp attributes for these nodes in PPC table.

In any case, before running this command, the CEC and Frame nodes need be defined with correct nodetype.nodetype value (cec or frame) and nodehm.mgt value (hmc).

Note: If a CEC belongs to a frame, which has a BPA installed, this CEC should not be assigned to an HMC individually. Instead, the whole frame should be assigned to the HMC.

For PPC (using Direct FSP Management) specific:

It is used to set up connections for CEC and Frame node to Hardware Server on management node (or service node ). It only could be done according to the node definition in xCAT DB. And this command will try to read the user/password from the ppcdirect table first. If fails, then read them from passwd table. Commonly , the username is \ **HMC**\ . If using the \ **ppcdirect**\  table,  each CEC/Frame and user/password should be  stored in \ **ppcdirect**\  table. If using the \ **passwd**\  table, the key should be "\ **cec**\ " or "\ **frame**\ ", and the related user/password are stored in \ **passwd**\  table.

When \ **-**\ **-port**\  is specified, this command will create the connections for CECs/Frames whose side in \ **vpd**\  table is equal to port value.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-t**\ 
 
 Read connection information from xCAT DB (ppc and ppcdirect tables).  Use this option if you need to connect multiple CECs/Frames
 to multiple HMCs in a single command.
 


\ **-p**\ 
 
 The HMC node name. Only one HMC nodes can be specified by this flag. To setup connection for multiple HMC nodes, use flag \ **-t**\ .
 


\ **-P**\ 
 
 The password of HMC based CEC/Frame login user(Default user name is 'HMC'). This flag is optional.
 


\ **-T**\ 
 
 The tooltype is used to communicate to the CEC/Frame. The value could be \ **lpar**\  or \ **fnm**\ . The tooltype value \ **lpar**\  is for xCAT and \ **fnm**\  is for CNM. The default value is "\ **lpar**\ ".
 


\ **-**\ **-port**\ 
 
 The port value specifies which special side will be used to create the connection to the CEC/Frame. The value could only be specified as "\ **0**\ " or "\ **1**\ " and the default value is "\ **0,1**\ ". If the user wants to use all ports to create the connection, he should not specify this value. If the port value is specified as "\ **0**\ ", in the vpd table, the side column should be \ **A-0**\  and \ **B-0**\ ; If the port value is specified as "\ **1**\ ", the side column should be \ **A-1**\  and \ **B-1**\ . When making hardware connection between CEC/Frame and HMC, the value is used to specify the fsp/bpa port of the cec/frame and will be organized in order of "\ **A-0,A-1,B-0,B-1**\ ". If any side does not exist, the side would simply be ignored. Generally, only one port of a fsp/bap can be connected while another port be used as backup.
 


\ **-s**\ 
 
 The flag -s is used to make the connection between the frame and its Service Focal Point(HMC). -s flag is not supposed to work with other functional flags.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1.
 
 To setup the connection for all CEC nodes in node group cec to HMC node, according to the definition in xCAT DB:
 
 
 .. code-block:: perl
 
   mkhwconn cec -t
 
 


2.
 
 To setup the connection for Frame nodes in node group frame to HMC node hmc1, with password 'abc123':
 
 
 .. code-block:: perl
 
   mkhwconn frame -p hmc1 -P abc123
 
 


3.
 
 To setup the connections for all CEC nodes in node group cec to hardware server, and the tooltype value is lpar:
 
 
 .. code-block:: perl
 
   mkhwconn cec -t -T lpar
 
 


4.
 
 To setup the connections for all cecs nodes in node group cec to hardware server, and the tooltype value is lpar, and the port value is 1:
 
 
 .. code-block:: perl
 
   mkhwconn cec -t -T lpar --port 1
 
 


5.
 
 To setup the connection between the frame and it's SFP node. This command will also set the connections between the CECs within this frame and their SFP node. User need to define HMC_name in the database in advance, but no need to set the sfp attribute for these node, xCAT will set the HMC_name as ppc.sfp for these nodes. The CECs within this frame should have the same sfp attribute as the frame.
 
 
 .. code-block:: perl
 
   mkhwconn cec -s HMC_name -P HMC_passwd
 
 



*****
FILES
*****


$XCATROOT/bin/mkhwconn

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


lshwconn(1)|lshwconn.1, rmhwconn(1)|rmhwconn.1

