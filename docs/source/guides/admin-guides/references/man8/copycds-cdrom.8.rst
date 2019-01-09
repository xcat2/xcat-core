
###############
copycds-cdrom.8
###############

.. highlight:: perl


********
SYNOPSIS
********


\ **copycds-cdrom**\  \ *[copycds options]*\  \ *[drive]*\ 


***********
DESCRIPTION
***********


\ **copycds-cdrom**\  is a wrapper scripts for \ **copycds**\  to copy from physical CD/DVD-ROM drives located on the management server.

\ *[copycds options]*\  are passed unchanged to copycds.

If \ *[drive]*\  is not specified, /dev/cdrom is assumed.

The copycds command copies all contents of Distribution CDs or Service Pack CDs to the install directory as
designated in the \ **site**\  table attribute: \ **installdir**\ .


********
SEE ALSO
********


copycds(8)|copycds.8


******
AUTHOR
******


Isaac Freeman <ifreeman@us.ibm.com>

