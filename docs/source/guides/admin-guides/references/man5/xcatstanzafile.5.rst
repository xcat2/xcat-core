
################
xcatstanzafile.5
################

.. highlight:: perl


****
NAME
****


\ **xcatstanzafile**\  - Format of a stanza file that can be used with xCAT data object definition commands.


***********
DESCRIPTION
***********


A stanza file contains information that can be used to create xCAT data object definitions. A stanza file can be used as input to several xCAT commands. The stanza file contains one or more individual stanzas that provide information for individual object definitions. The following rules must be followed when creating a stanza file:


\*
 
 An object stanza header consists of the object name followed by a colon, (":").
 


\*
 
 Attribute lines must take the form of Attribute=Value.
 


\*
 
 Attribute name might include the character dot ("."), like passwd.HMC and nicips.eth0.
 


\*
 
 Only one stanza can exist for each object name.
 


\*
 
 All stanzas except for default stanzas must have a value set for "objtype".
 


\*
 
 Comments beginning with the "#" pound sign may be added to the file. A comment must be on a separate line.
 


\*
 
 When parsing the file, tab characters and spaces are ignored.
 


\*
 
 Each line of the file can have no more than one header or attribute definition.
 


\*
 
 If the header name is "default-<object type>:" the attribute values in the stanza are considered default values for subsequent definitions in the file that are the same object type.
 


\*
 
 Default stanzas can be specified multiple times and at any point in a stanza file. The values apply to all definitions following the default stanzas in a file. The default values are cumulative; a default attribute value will remain set until it is explicitly unset or changed.
 


\*
 
 To turn off a default value, use another default stanza to set the attribute to have no value using a blank space.
 


\*
 
 When a specific value for an attribute is provided in the stanza, it takes priority over any default value that had been set.
 


The format of a stanza file should look similar to the following.


.. code-block:: perl

  default-<object type>:
     attr=val
     attr=val
     . . .
 
  <object name>:
     objtype=<object type>
     attr=val
     attr=val
     . . .
 
  <object name>:
     objtype=<object type>
     attr=val
     attr=val
     . . .



********
EXAMPLES
********



1)
 
 Sample stanza file:
 
 
 .. code-block:: perl
 
   mysite:
      objtype=site
      rsh=/bin/rsh
      rcp=/bin/rcp
      installdir=/xcatinstall
      domain=ppd.pok.ibm.com
  
   MSnet01:
      objtype=network
      gateway=1.2.3.4
      netmask=255.255.255.0
      nameserver=5.6.7.8
  
   default-node:
      next_osimage=aix61
      network=MSnet01
      groups=all,compute
  
   node01:
      objtype=node
      MAC=A2E26002C003
      xcatmaster=MS02.ppd.pok.com
      nfsserver=IS227.ppd.pok.com
  
   node02:
      objtype=node
      MAC=A2E26002B004
      xcatmaster=MS01.ppd.pok.com
      nfsserver=IS127.ppd.pok.com
  
   grp01:
      objtype=group
      members=node1,node2,node3
 
 



*****
NOTES
*****


This file is part of xCAT software product.


********
SEE ALSO
********


mkdef(1)|mkdef.1, lsdef(1)|lsdef.1, rmdef(1)|rmdef.1, chdef(1)|chdef.1

