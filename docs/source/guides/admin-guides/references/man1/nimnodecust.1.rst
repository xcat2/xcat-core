
#############
nimnodecust.1
#############

.. highlight:: perl


****
NAME
****


\ **nimnodecust**\  - Use this xCAT command to customize AIX/NIM standalone machines.


********
SYNOPSIS
********


\ **nimnodecust [-h|-**\ **-help ]**\ 

\ **nimnodecust [-V] -s**\  \ *lpp_source_name*\  [\ **-p**\  \ *packages*\ ] [\ **-b**\  \ *installp_bundles*\ ] \ *noderange [attr=val [attr=val ...]]*\ 


***********
DESCRIPTION
***********


This xCAT command can be used to customize AIX/NIM standalone machines.

The software packages that you wish to install on the nodes must be copied to the appropriate directory locations in the NIM lpp_source resource provided by the "-s" option.  For example, if the location of your lpp_source resource is "/install/nim/lpp_source/61lpp/" then you would copy RPM packages to "/install/nim/lpp_source/61lpp/RPMS/ppc" and you would copy your installp packages to "/install/nim/lpp_source/61lpp/installp/ppc". Typically you would want to copy the packages to the same lpp_source that was used to install the node.  You can find the location for an lpp_source with the AIX lsnim command. (Ex. "lsnim -l <lpp_source_name>")

The packages you wish to install on the nodes may be specified with either a comma-separated list of package names or by a comma-separated list of installp_bundle names. The installp_bundle names are what were used when creating the corresponding NIM installp_bundle definitions. The installp_bundle definitions may also be used when installing the nodes.

A bundle file contains a list of package names.  The RPMs must have a prefix of "R:" and the installp packages must have a prefix of "I:".  For example, the contents of a simple bundle file might look like the following.


.. code-block:: perl

  # RPM
  R:expect-5.42.1-3.aix5.1.ppc.rpm
  R:ping-2.4b2_to-1.aix5.3.ppc.rpm
 
  #installp
  I:openssh.base
  I:openssh.license


To create a NIM installp_bundle definition you can use the "nim -o define" operation.  For example, to create a definition called "mypackages" for a bundle file located at "/install/nim/mypkgs.bnd" you could issue the following command.


.. code-block:: perl

  nim -o define -t installp_bundle -a server=master -a location=/install/nim/mypkgs.bnd mypackages


See the AIX documantation for more information on using installp_bundle files.

The xCAT nimnodecust command will automatically handle the distribution of the packages to AIX service nodes when using an xCAT hierachical environment.


*******
OPTIONS
*******



\ *attr=val [attr=val ...]*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=val pairs must be specified last on the command line. These are used to specify
 additional values that can be passed to the underlying NIM commands, ("nim -o cust..."). See the NIM documentation for valid "nim" command line options.
 


\ **-b**\  \ *installp_bundle_names*\ 
 
 A comma separated list of NIM installp_bundle names.
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-p**\  \ *package_names*\ 
 
 A comma-separated list of software packages to install.  Packages may be RPM or installp.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. See the "noderange" man page for details on additional supported formats.
 


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


1) Install the installp package "openssh.base.server" on an xCAT node named "node01".  Assume that the package has been copied to the NIM lpp_source resource called "61lppsource".


.. code-block:: perl

  nimnodecust -s 61lppsource -p openssh.base.server node01


2) Install the product software contained in the two bundles called "llbnd" and "pebnd" on all AIX nodes contained in the xCAT node group called "aixnodes".  Assume that all the software packages have been copied to the NIM lpp_source resource called "61lppsource".


.. code-block:: perl

  nimnodecust -s 61lppsource -b llbnd,pebnd  aixnodes



*****
FILES
*****


/opt/xcat/bin/nimnodecust


*****
NOTES
*****


This command is part of the xCAT software product.

