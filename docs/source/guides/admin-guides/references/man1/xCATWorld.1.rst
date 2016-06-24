
###########
xCATWorld.1
###########

.. highlight:: perl


****
NAME
****


\ **xCATWorld**\  - Sample client program for xCAT.


********
SYNOPSIS
********


\ **xCATWorld**\  \ *noderange*\ 


***********
DESCRIPTION
***********


The xCATWorld program gives you a sample client program that interfaces to the /opt/xcat/lib/perl/xCAT_plugin/xCATWorld.pm plugin.  
For debugging purposes we have an Environment Variable XCATBYPASS.  If export XCATBYPASS=yes, the client will call the plugin without going through the xcat daemon, xcatd.


*******
OPTIONS
*******


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1.To run , enter:


.. code-block:: perl

  xCATWorld nodegrp1



*****
FILES
*****


/opt/xcat/bin/xCATWorld


*****
NOTES
*****


This command is part of the xCAT software product.

