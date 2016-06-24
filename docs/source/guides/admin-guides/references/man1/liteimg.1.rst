
#########
liteimg.1
#########

.. highlight:: perl


****
NAME
****


\ **liteimg**\  - Modify statelite image by creating a series of links.


********
SYNOPSIS
********


\ **liteimg [-h| -**\ **-help]**\ 

\ **liteimg  [-v| -**\ **-version]**\ 

\ **liteimg**\  \ *imagename*\ 


***********
DESCRIPTION
***********


This command modifies the statelite image by creating a series of links. 
It creates 2 levels of indirection so that files can be modified while in
their image state as well as during runtime. For example, a file like
<$imgroot>/etc/ntp.conf will have the following operations done to it:

\ *    mkdir -p $imgroot/.default/etc*\ 

\ *    mkdir -p $imgroot/.statelite/tmpfs/etc*\ 

\ *    mv $imgroot/etc/ntp.conf $imgroot/.default/etc*\ 

\ *    cd $imgroot/.statelite/tmpfs/etc*\ 

\ *    ln -sf ../../../.default/etc/ntp.conf .*\ 

\ *    cd $imgroot/etc*\ 

\ *    ln -sf ../.statelite/tmpfs/etc/ntp.conf .*\ 

When finished, the original file will reside in
\ *$imgroot/.default/etc/ntp.conf*\ . \ *$imgroot/etc/ntp.conf*\  will link to
\ *$imgroot/.statelite/tmpfs/etc/ntp.conf*\  which will in turn link to
\ *$imgroot/.default/etc/ntp.conf*\ 

Note: If you make any changes to your litefile table after running liteimg then you will need to rerun liteimg again.


**********
PARAMETERS
**********


\ *imagename*\  specifies the name of a os image definition to be used. The specification for the image is storted in the \ *osimage*\  table and \ *linuximage*\  table.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\           Display usage message.

\ **-v|-**\ **-version**\           Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To lite a RHEL 6.6 statelite image for a compute node architecture x86_64 enter:


.. code-block:: perl

  liteimg rhels6.6-x86_64-statelite-compute



*****
FILES
*****


/opt/xcat/bin/liteimg


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


genimage(1)|genimage.1

