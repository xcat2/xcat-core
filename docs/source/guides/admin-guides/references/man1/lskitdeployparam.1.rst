
##################
lskitdeployparam.1
##################

.. highlight:: perl


****
NAME
****


\ **lskitdeployparam**\  - Lists the deployment parameters for one or more Kits or Kit components


********
SYNOPSIS
********


\ **lskitdeployparam**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-x**\  | \ **-**\ **-xml**\  | \ **-**\ **-XML**\ ] [\ **-k**\  | \ **-**\ **-kitname**\  \ *kit_names*\ ] [\ **-c**\  | \ **-**\ **-compname**\  \ *comp_names*\ ]

\ **lskitdeployparam**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **lskitdeployparam**\  command is used to list the kit deployment parameters for one or more kits, or one or more kit components. Kit deployment parameters are used to customize the installation or upgrade of kit components.

The \ **lskitdeployparam**\  command outputs the kit component information in two formats: human-readable format (default), and XML format.  Use the -x option to view the information in XML format.

Input to the command can specify any combination of the input options.

Note: The xCAT support for Kits is only available for Linux operating systems.


*******
OPTIONS
*******



\ **-k|-**\ **-kitname**\  \ *kit_names*\ 
 
 Where \ *kit_names*\  is a comma-delimited list of kit names. The \ **lskitdeployparam**\  command will only display the deployment parameters for the kits with the matching names.
 


\ **-c|-**\ **-compname**\  \ *comp_names*\ 
 
 Where \ *comp_names*\  is a comma-delimited list of kit component names. The \ **lskitdeployparam**\  command will only display the deployment parameters for the kit components with the matching names.
 


\ **-x|-**\ **-xml|-**\ **-XML**\ 
 
 Return the output with XML tags.  The data is returned as:
 
 
 .. code-block:: perl
 
    <data>
      <kitdeployparam>
        <name>KIT_KIT1_PARAM1</name>
        <value>value11</value>
      </kitdeployparam>
    </data>
    <data>
      <kitdeployparam>
        <name>KIT_KIT1_PARAM2</name>
        <value>value12</value>
      </kitdeployparam>
    </data>
    ...
 
 


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
 
 To list kit deployment parameters for kit "kit-test1-1.0-Linux", enter:
 
 
 .. code-block:: perl
 
    lskitdeployparam -k kit-test1-1.0-Linux
 
 


2.
 
 To list kit deployment parameters for kit component "comp-server-1.0-1-rhels-6-x86_64", enter:
 
 
 .. code-block:: perl
 
    lskitdeployparam -c comp-server-1.0-1-rhels-6-x86_64
 
 



*****
FILES
*****


/opt/xcat/bin/lskitdeployparam


********
SEE ALSO
********


lskit(1)|lskit.1, lskitcomp(1)|lskitcomp.1, addkit(1)|addkit.1, rmkit(1)|rmkit.1, addkitcomp(1)|addkitcomp.1, rmkitcomp(1)|rmkitcomp.1

