
############
chkosimage.1
############

.. highlight:: perl


****
NAME
****


\ **chkosimage**\  - Use this xCAT command to check an xCAT osimage.


********
SYNOPSIS
********


\ **chkosimage [-h | -**\ **-help ]**\ 

\ **chkosimage [-V] [-c|-**\ **-clean]**\  \ *osimage_name*\ 


***********
DESCRIPTION
***********


This command is currently supported for AIX osimages only.

Use this command to verify if the NIM lpp_source directories contain the 
correct software.  The lpp_source directory must contain all the software
that is specified in the "installp_bundle" and "otherpkgs" 
attributes of the osimage definition.

The command gets the name of the lpp_source resource from the xCAT osimage 
definition and the location of the lpp_source directory from the NIM resource
definition.

It will check for installp, rpm and emgr type packages.

Note: Remember to use the prefixes, "I:", "R:", and "E:", respectively,
when specifying package names in an installp_bundle file or an otherpkgs list.

In addition to checking for missing software the chkosimage command will
also check to see if there are multiple matches.  This could happen 
when you use wildcards in the software file names. For example,  if you
have perl-xCAT\* in a bundle file it could match multiple versions of the xCAT 
rpm package saved in your lpp_source directory.

If this happens you must remove the unwanted versions of the rpms.  If the
extra rpms are not removed you will get install errors.

To help with this process you can use the "-c|--clean" option.  This 
option will keep the rpm package with the most recent timestamp and 
remove the others.

The chkosimage command should always be used to verify the lpp_source content
before using the osimage to install any AIX cluster nodes.


*******
OPTIONS
*******



\ **-c |-**\ **-clean**\ 
 
 Remove any older versions of the rpms.  Keep the version with the latest
 timestamp.
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ *osimage_name*\ 
 
 The name of the xCAT for AIX osimage definition.
 


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



1. Check the XCAT osimage called "61image" to verify that the lpp_source 
directories contain all the software that is specified in the
"installp_bundle" and "otherpkgs" attributes.
 
 
 .. code-block:: perl
 
   chkosimage -V 61image
 
 


2. Clean up the lpp_source directory for the osimage named "61img" by removing
any older rpms with the same names but different versions.
 
 
 .. code-block:: perl
 
   chkosimage -c 61img
 
 



*****
FILES
*****


/opt/xcat/bin/chkosimage


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mknimimage(1)|mknimimage.1

