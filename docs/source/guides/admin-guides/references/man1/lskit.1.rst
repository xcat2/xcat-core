
#######
lskit.1
#######

.. highlight:: perl


****
NAME
****


\ **lskit**\  - Lists information for one or more Kits.


********
SYNOPSIS
********


\ **lskit**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-F**\  | \ **-**\ **-framework**\  \ *kitattr_names*\ ] [\ **-x**\  | \ **-**\ **-xml**\  | \ **-**\ **-XML**\ ] [\ **-K**\  | \ **-**\ **-kitattr**\  \ *kitattr_names*\ ] [\ **-R**\  | \ **-**\ **-repoattr**\  \ *repoattr_names*\ ] [\ **-C**\  | \ **-**\ **-compattr**\  \ *compattr_names*\ ] [\ *kit_names*\ ]

\ **lskit**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]

\ **lskit**\  [\ **-F**\  | \ **-**\ **-framework**\  \ *kit_path_name*\ ]


***********
DESCRIPTION
***********


The \ **lskit**\  command is used to list information for one or more kits. A kit is a special kind of package that is used to install a software product on one or more nodes in an xCAT cluster.

Note: The xCAT support for Kits is only available for Linux operating systems.

The \ **lskit**\  command outputs the following info for each kit: the kit's basic info, the kit's repositories, and the kit's components.  The command outputs the info in two formats: human-readable format (default), and XML format.  Use the -x option to view the info in XML format.

Input to the command can specify any number or combination of the input options.


*******
OPTIONS
*******



\ **-F|-**\ **-framework**\  \ *kit_path_name*\ 
 
 Use this option to display the framework values of the specified Kit tarfile.  This information is retreived directly from the tarfile and can be done before the Kit has been defined in the xCAT database.  This option cannot be combined with other options.
 


\ **-K|-**\ **-kitattr**\  \ *kitattr_names*\ 
 
 Where \ *kitattr_names*\  is a comma-delimited list of kit attribute names. The names correspond to attribute names in the \ **kit**\  table. The \ **lskit**\  command will only display the specified kit attributes.
 


\ **-R|-**\ **-repoattr**\  \ *repoattr_names*\ 
 
 Where \ *repoattr_names*\  is a comma-delimited list of kit repository attribute names. The names correspond to attribute names in the \ **kitrepo**\  table. The \ **lskit**\  command will only display the specified kit repository attributes.
 


\ **-C|-**\ **-compattr**\  \ *compattr_names*\ 
 
 where \ *compattr_names*\  is a comma-delimited list of kit component attribute names. The names correspond to attribute names in the \ **kitcomponent**\  table. The \ **lskit**\  command will only display the specified kit component attributes.
 


\ *kit_names*\ 
 
 is a comma-delimited list of kit names. The \ **lskit**\  command will only display the kits matching these names.
 


\ **-x|-**\ **-xml|-**\ **-XML**\ 
 
 Need XCATXMLTRACE=1 env when using -x|--xml|--XML, for example: XCATXMLTRACE=1  lskit -x testkit-1.0.0
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
 
 
 Each <kitinfo> tag contains info for one kit.  The info inside <kitinfo> is structured as follows:
 
 
 .. code-block:: perl
 
    The <kit> sub-tag contains the kit's basic info.
    The <kitrepo> sub-tags store info about the kit's repositories.
    The <kitcomponent> sub-tags store info about the kit's components.
 
 
 The data inside <kitinfo> is returned as:
 
 
 .. code-block:: perl
 
    <kitinfo>
       <kit>
         ...
       </kit>
  
       <kitrepo>
         ...
       </kitrepo>
       ...
  
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



1. To list all kits, enter:
 
 
 .. code-block:: perl
 
    lskit
 
 


2. To list the kit "kit-test1-1.0-Linux", enter:
 
 
 .. code-block:: perl
 
    lskit kit-test1-1.0-Linux
 
 


3. To list the kit "kit-test1-1.0-Linux" for selected attributes, enter:
 
 
 .. code-block:: perl
 
    lskit -K basename,description -R kitreponame -C kitcompname kit-test1-1.0-Linux
 
 


4. To list the framework value of a Kit tarfile.
 
 
 .. code-block:: perl
 
    lskit -F /myhome/mykits/pperte-1.3.0.2-0-x86_64.tar.bz2
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
    Extracting the kit.conf file from /myhome/mykits/pperte-1.3.0.2-0-x86_64.tar.bz2. Please wait.
    
          kitframework=2
          compatible_kitframeworks=0,1,2
 
 


5. To list kit "testkit-1.0-1" with XML tags, enter:
 
 
 .. code-block:: perl
 
    XCATXMLTRACE=1 lskit -x testkit-1.0-1
 
 



*****
FILES
*****


/opt/xcat/bin/lskit


********
SEE ALSO
********


lskitcomp(1)|lskitcomp.1, lskitdeployparam(1)|lskitdeployparam.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1

