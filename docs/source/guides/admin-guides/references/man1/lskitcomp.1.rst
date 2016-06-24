
###########
lskitcomp.1
###########

.. highlight:: perl


****
NAME
****


\ **lskitcomp**\  - Used to list information for one or more kit components.


********
SYNOPSIS
********


\ **lskitcomp**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-x**\  | \ **-**\ **-xml**\  | \ **-**\ **-XML**\ ] [\ **-C**\  | \ **-**\ **-compattr**\  \ *compattr_names*\ ] [\ **-O**\  | \ **-**\ **-osdistro**\  \ *os_distro*\ ] [\ **-S**\  | \ **-**\ **-serverrole**\  \ *server_role*\ ] [\ *kitcomp_names*\ ]

\ **lskitcomp**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **lskitcomp**\  command is used to list information for one or more kit components. A kit is made up of one or more kit components. Each kit component is a meta package used to install a software product component on one or more nodes in an xCAT cluster.

The \ **lskitcomp**\  command outputs the kit component info in two formats: human-readable format (default), and XML format. Use the -x option to view the info in XML format.

Input to the command can specify any number or combination of the input options.

Note: The xCAT support for Kits is only available for Linux operating systems.


*******
OPTIONS
*******



\ **-C|-**\ **-compattr**\  \ *compattr_names*\ 
 
 where \ *compattr_names*\  is a comma-delimited list of kit component attribute names. The names correspond to attribute names in the \ **kitcomponent**\  table.  The \ **lskitcomp**\  command will only display the specified kit component attributes.
 


\ **-O|-**\ **-osdistro**\  \ *os_distro*\ 
 
 where \ *os_distro*\  is the name of an osdistro in \ **osdistro**\  table. The \ **lskitcomp**\  command will only display the kit components matching the specified osdistro.
 


\ **-S|-**\ **-serverrole**\  \ *server_role*\ 
 
 where \ *server_role*\  is the name of a server role. The typical server roles are: mgtnode, servicenode, computenode, loginnode, storagennode. The \ **lskitcomp**\  command will only display the kit components matching the specified server role.
 


\ *kitcomp_names*\ 
 
 is a comma-delimited list of kit component names. The \ **lskitcomp**\  command will only display the kit components matching the specified names.
 


\ **-x|-**\ **-xml|-**\ **-XML**\ 
 
 Need XCATXMLTRACE=1 env when using -x|--xml|--XML.
 Return the output with XML tags.  The data is returned as:
 
 
 .. code-block:: perl
 
    <data>
      <kitinfo>
         ...
      </kitinfo>
    </data>
    ...
    <data>
      <kitinfo>
         ...
      </kitinfo>
    </data>
 
 
 Each <kitinfo> tag contains info for a group of kit compoonents belonging to the same kit. The info inside <kitinfo> is structured as follows:
 
 
 .. code-block:: perl
 
    The <kit> sub-tag contains the kit's name.
    The <kitcomponent> sub-tags store info about the kit's components.
 
 
 The data inside <kitinfo> is returned as:
 
 
 .. code-block:: perl
 
    <kitinfo>
       <kit>
         ...
       </kit>
  
       <kitcomponent>
         ...
       </kitcomponent>
       ...
    </kitinfo>
 
 


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
 
 To list all kit components, enter:
 
 
 .. code-block:: perl
 
    lskitcomp
 
 


2.
 
 To list the kit component "comp-server-1.0-1-rhels-6-x86_64", enter:
 
 
 .. code-block:: perl
 
    lskitcomp comp-server-1.0-1-rhels-6-x86_64
 
 


3.
 
 To list the kit component "comp-server-1.0-1-rhels-6-x86_64" for selected kit component attributes, enter:
 
 
 .. code-block:: perl
 
    lskitcomp -C kitcompname,desc comp-server-1.0-1-rhels-6-x86_64
 
 


4.
 
 To list kit components compatible with "rhels-6.2-x86_64" osdistro, enter:
 
 
 .. code-block:: perl
 
    lskitcomp -O rhels-6.2-x86_64
 
 


5.
 
 To list kit components compatible with "rhels-6.2-x86_64" osdistro and "computenode" server role, enter:
 
 
 .. code-block:: perl
 
    lskitcomp -O rhels-6.2-x86_64 -S computenode
 
 


6.
 
 To list the kit component "testkit-compute-1.0-1-ubuntu-14.04-ppc64el" with XML tags, enter:
 
 
 .. code-block:: perl
 
    XCATXMLTRACE=1 lskitcomp -x testkit-compute-1.0-1-ubuntu-14.04-ppc64el
 
 



*****
FILES
*****


/opt/xcat/bin/lskitcomp


********
SEE ALSO
********


lskit(1)|lskit.1, lskitdeployparam(1)|lskitdeployparam.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1

