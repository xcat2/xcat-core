
############
xcatchroot.1
############

.. highlight:: perl


****
NAME
****


\ **xcatchroot**\  - Use this xCAT command to modify an xCAT AIX diskless operating system image.


********
SYNOPSIS
********


\ **xcatchroot -h**\ 

\ **xcatchroot [-V] -i**\  \ *osimage_name cmd_string*\ 


***********
DESCRIPTION
***********


For AIX diskless images this command will modify the AIX SPOT resource using 
the chroot command.  You must include the name of an xCAT osimage
definition and the command that you wish to have run in the spot.

\ **WARNING:**\ 


Be very careful when using this command!!!  Make sure you are
very clear about exactly what you are changing so that you do
not accidently corrupt the image.

As a precaution it is advisable to make a copy of the original
spot in case your changes wind up corrupting the image.

When you are done updating a NIM spot resource you should always run the NIM
check operation on the spot.



.. code-block:: perl

  nim -Fo check <spot_name>


The xcatchroot command will take care of any of the required setup so that 
the command you provide will be able to run in the spot chroot environment.
It will also mount the lpp_source resource listed in the osimage definition
so that you can access additional software that you may wish to install.

For example, assume that the location of the spot named in the xCAT osimage 
definition is /install/nim/spot/614spot/usr. The associated root directory in
this spot would be /install/nim/spot/614spot/usr/lpp/bos/inst_root.  The chroot
is automatically done to this new root directory.  The spot location is 
mounted on /.../inst_root/usr so that when your command is run in the chroot
environment it is actually running commands from the spot usr location.

Also, the location of the lpp_source resource specified in the osimage 
definition will be mounted to a subdirectory of the spot /.../inst_root
directory.  For example, if the lpp_source location is 
/install/nim/lpp_source/614lpp_lpp_source then that would be mounted over
/install/nim/spot/614spot/usr/lpp/bos/inst_root/lpp_source.

When you provide a command string to run make sure you give the full paths
of all commands and files assuming the /.../inst_root directory is you root
directory.

If you wish to install software from the lpp_source location you would
provide a directory location of /lpp_source (or /lpp_source/installp/ppc 
or /lpp_source/RPMS/ppc etc.) See the example below.

Always run the NIM check operation after you are done updating your spot.
(ex. "nim -o check <spot_name>")


*******
OPTIONS
*******



\ *cmd_string*\ 
 
 The command you wish to have run in the chroot environment.  (Use a quoted 
 string.)
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-i**\  \ *osimage_name*\ 
 
 The name of the xCAT osimage definition.
 


\ **-V |-**\ **-verbose**\ 
 
 Verbose mode.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********


1) Set the root password to "cluster" in the spot so that when the diskless 
node boots it will have a root password set.


.. code-block:: perl

  xcatchroot -i 614spot "/usr/bin/echo root:cluster | /usr/bin/chpasswd -c"


2) Install the bash rpm package.


.. code-block:: perl

  xcatchroot -i 614spot "/usr/bin/rpm -Uvh /lpp_source/RPMS/ppc bash-3.2-1.aix5.2.ppc.rpm"


3) To enable system debug.


.. code-block:: perl

  xcatchroot -i 614spot "bosdebug -D -M"


4) To set the "ipforwarding" system tunable.


.. code-block:: perl

  xcatchroot -i 614spot "/usr/sbin/no -r -o ipforwarding=1"



*****
FILES
*****


/opt/xcat/bin/xcatchroot


*****
NOTES
*****


This command is part of the xCAT software product.

