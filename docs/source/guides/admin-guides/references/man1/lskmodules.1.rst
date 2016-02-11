
############
lskmodules.1
############

.. highlight:: perl


****
NAME
****


\ **lskmodules**\  - list kernel driver modules in rpms or driver disk image files


********
SYNOPSIS
********


\ **lskmodules**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-i**\  | \ **-**\ **-osimage**\  \ *osimage_names*\ ] [\ **-c**\  | \ **-**\ **-kitcomponent**\  \ *kitcomp_names*\ ] [\ **-o**\  | \ **-**\ **-osdistro**\  \ *osdistro_names*\ ] [\ **-u**\  | \ **-**\ **-osdistropudate**\  \ *osdistroupdate_names*\ ] [\ **-x**\  | \ **-**\ **-xml**\  | \ **-**\ **-XML**\ ]

\ **lskmodules**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **lskmodules**\  command finds the kernel driver module files (\*.ko) in the specified input locations, runs the modinfo command against each file, and returns the driver name and description.  If -x is specified, the output is returned with XML tags.

Input to the command can specify any number or combination of the input options.


*******
OPTIONS
*******



\ **-i|-**\ **-osimage**\  \ *osimage_names*\ 
 
 where \ *osimage_names*\  is a comma-delimited list of xCAT database osimage object names.  For each \ *osimage_name*\ , lskmodules will use the entries in osimage.driverupdatesrc for the rpms and driver disk image files to search.
 


\ **-c|-**\ **-kitcomponent**\  \ *kitcomponent_names*\ 
 
 where \ *kitcomponent_names*\  is a comma-delimited list of xCAT database kitcomponent object names.  For each \ *kitcomponent_name*\ , lskmodules will use the entries in kitcomponent.driverpacks for the rpm list and the repodir of the kitcomponent.kitreponame for the location of the rpm files to search.
 


\ **-o|-**\ **-osdistro**\  \ *osdistro_names*\ 
 
 where \ *osdistro_names*\  is a comma-delimited list of xCAT database osdistro object names.  For each \ *osdistro_name*\ , lskmodules will search each <osdistro.dirpaths>/Packages/kernel-<kernelversion>.rpm file.
 


\ **-u|-**\ **-osdistroupdate**\  \ *osdistroupdate_names*\ 
 
 where \ *osdistroupdate_names*\  is a comma-delimited list of xCAT database osdistroupdate table entries.  For each \ *osdistroupdate_name*\ , lskmodules will search the <osdistroupdate.dirpath>/kernel-<kernelversion>.rpm file.
 


\ **-x|-**\ **-xml|-**\ **-XML**\ 
 
 Return the output with XML tags.  The data is returned as:
 
 
 .. code-block:: perl
 
    <module>
      <name> xxx.ko </name>
      <description> this is module xxx </description>
    </module>
 
 
 This option is intended for use by other programs.  The XML will not be displayed.  To view the returned XML, set the XCATSHOWXML=yes environment variable before running this command.
 


\ **-V|-**\ **-verbose**\ 
 
 Display additional progress and error messages.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********



1.
 
 To list the kernel modules included in the driverpacks shipped with kitcomponent kit1_comp1-x86_64, enter:
 
 
 .. code-block:: perl
 
    lskmodules -c kit1_comp1-x86_64
 
 



*****
FILES
*****



********
SEE ALSO
********


