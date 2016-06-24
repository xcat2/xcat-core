
############
getslnodes.1
############

.. highlight:: perl


****
NAME
****


\ **getslnodes**\  - queries your SoftLayer account and gets attributes for each server.


********
SYNOPSIS
********


\ **getslnodes**\  [\ **-v | -**\ **-verbose**\ ] [\ *hostname-match*\ ]

\ **getslnodes**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The \ **getslnodes**\  command queries your SoftLayer account and gets attributes for each
server.  The attributes can be piped to 'mkdef -z' to define the nodes
in the xCAT DB so that xCAT can manage them.

Before using this command, you must download and install the SoftLayer API perl module.
For example:


.. code-block:: perl

    cd /usr/local/lib
    git clone https://github.com/softlayer/softlayer-api-perl-client.git


You also need to follow these directions to get your SoftLayer API key: http://knowledgelayer.softlayer.com/procedure/retrieve-your-api-key

\ **getslnodes**\  requires a .slconfig file in your home directory that contains your
SoftLayer userid, API key, and location of the SoftLayer API perl module, in attr=val format.
For example:


.. code-block:: perl

    # Config file used by the xcat cmd getslnodes
    userid = joe_smith
    apikey = 1234567890abcdef1234567890abcdef1234567890abcdef
    apidir = /usr/local/lib/softlayer-api-perl-client



*******
OPTIONS
*******



\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 Display information about all of the nodes in your SoftLayer account:
 
 
 .. code-block:: perl
 
   getslnodes
 
 


2.
 
 Display information about all of the nodes whose hostname starts with foo:
 
 
 .. code-block:: perl
 
   getslnodes foo
 
 


3.
 
 Create xCAT node defintions in the xCAT DB for all of the nodes in your SoftLayer account:
 
 
 .. code-block:: perl
 
   getslnodes | mkdef -z
 
 



*****
FILES
*****


/opt/xcat/bin/getslnodes


********
SEE ALSO
********


pushinitrd(1)|pushinitrd.1

