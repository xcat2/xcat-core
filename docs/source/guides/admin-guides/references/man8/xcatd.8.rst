
#######
xcatd.8
#######

.. highlight:: perl


****
NAME
****


\ **xcatd**\  - The xCAT daemon


********
SYNOPSIS
********


\ **xcatd**\ 


***********
DESCRIPTION
***********


The heart of the xCAT architecture is the xCAT daemon \ **xcatd**\  on the management node. This receives requests from the client, validates the requests, and then invokes the operation. The xcatd daemon also receives status and inventory info from the nodes as they are being discovered and installed/booted.

Errors and information are reported through syslog to the /var/log/messages file.   You can search for xCAT in those messages.

See http://xcat-docs.readthedocs.org/en/latest/overview/index.html#xcat-architecture for more information.


********
EXAMPLES
********



1. To start/stop/restart  xcatd on Linux, enter:
 
 
 .. code-block:: perl
 
   service xcatd start 
  
   service xcatd stop 
  
   service xcatd restart
 
 


2. To start/stop/restart  xcatd on AIX, enter:
 
 
 .. code-block:: perl
 
   restartxcatd
  
     or
  
   startsrc -s xcatd
  
   stopsrc -s xcatd
 
 



*****
FILES
*****


/opt/xcat/sbin/xcatd


********
SEE ALSO
********


