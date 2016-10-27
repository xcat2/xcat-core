
#######
rcons.1
#######

.. highlight:: perl


****
Name
****


\ **rcons**\  - remotely accesses the serial console of a node


****************
\ **Synopsis**\ 
****************


\ **rcons**\  \ *singlenode*\  [\ *conserver-host*\ ] [\ **-f**\ ] [\ **-s**\ ]

\ **rcons**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **rcons**\  provides access to a single remote node serial console, using the out-of-band infrastructure for the node
(e.g. BMC, Management Module, HMC, KVM, etc.).  It uses the conserver open source package to provide one read-write and
multiple read-only instances of the console, plus console logging.

If \ *conserver-host*\  is specified, the conserver daemon on that host will be contacted, instead of on the local host.

To exit the console session, enter:  <ctrl>e c .


***************
\ **Options**\ 
***************



\ **-f**\ 
 
 If another console for this node is already open in read-write mode, force that console into read-only (spy) mode, and
 open this console in read-write mode.  If -f is not specified, this console will be put in spy mode if another console
 is already open in read-write mode. The -f flag can not be used with the -s flag.
 


\ **-s**\ 
 
 Open the console in read-only (spy) mode, in this mode all the escape sequences work, but all other keyboard input is 
 discarded. The -s flag can not be used with the -f flag.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



*************
\ **Files**\ 
*************


\ **nodehm**\  table -
xCAT  node hardware management table.  See nodehm(5)|nodehm.5 for
further details.  This is used  to  determine  the  console  access
method.


****************
\ **Examples**\ 
****************



.. code-block:: perl

  rcons node5



************************
\ **See**\  \ **Also**\ 
************************


wcons(1)|wcons.1

