
################
groupfiles4dsh.1
################

.. highlight:: perl


****
NAME
****


\ **groupfiles4dsh**\  - Builds a directory of files for each defined nodegroup in xCAT.


********
SYNOPSIS
********


\ **groupfiles4dsh**\  [{\ **-p | -**\ **-path**\ } \ *path*\ ]

\ **groupfiles4dsh**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


This tool will build a directory of files, one for each defined
nodegroup in xCAT.  The file will be named the nodegroup name and
contain a list of nodes that belong to the nodegroup.
The file can be used as input to the AIX dsh command.
The purpose of this tool is to allow backward compatiblity with scripts
that were created using the AIX or CSM dsh command

Reference: man dsh.


*******
OPTIONS
*******


\ **-h**\           Display usage message.

\ **-v**\           Command Version.

\ **-p**\           Path to the directory to create the nodegroup files (must exist).


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To create the nodegroup files in directory /tmp/nodegroupfiles, enter:


.. code-block:: perl

  groupfiles4dsh -p /tmp/nodegroupfiles


To use with dsh:


.. code-block:: perl

    export DSH_CONTEXT=DSH  ( default unless CSM is installed)
    export DSH_NODE_RSH=/bin/ssh   (default is rsh)
    export DSH_NODEGROUP_PATH= /tmp/nodegroupfiles
 
    dsh  -N all  date   (where all is a group defined in xCAT)
    dsh -a date  (will look in all nodegroupfiles and build a list of all nodes)



*****
FILES
*****


/opt/xcat/share/xcat/tools/groupfiles4dsh


********
SEE ALSO
********


xdsh(1)|xdsh.1

