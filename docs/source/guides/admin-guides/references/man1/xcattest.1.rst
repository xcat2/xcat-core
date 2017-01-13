
##########
xcattest.1
##########

.. highlight:: perl


****
NAME
****


\ **xcattest**\  - Run automated xCAT test cases.


********
SYNOPSIS
********


\ **xcattest**\  [\ **-?|-h**\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ ] [\ **-b**\  \ *case bundle list*\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ ] [\ **-t**\  \ *case list*\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ ] [\ **-c**\  \ *cmd list*\ ]

\ **xcattest**\  [\ **-b**\  \ *case bundle list*\ ] [\ **-l**\ ]

\ **xcattest**\  [\ **-t**\  \ *case list*\ ] [\ **-l**\ ]

\ **xcattest**\  [\ **-c**\  \ *cmd list*\ ] [\ **-l**\ ]

\ **xcattest**\  [\ **-s**\  \ **command**\ ]

\ **xcattest**\  [\ **-s**\  \ **bundle**\ ]


***********
DESCRIPTION
***********


The xcattest command runs test cases to verify the xCAT functions, it can be used when you want to verify the xCAT functions for whatever reason, for example, to ensure the code changes you made do not break the existing commands; to run acceptance test for new build you got; to verify the xCAT snapshot build or development build before putting it onto your production system. The xcattest command is part of the xCAT package xCAT-test.

The root directory for the xCAT-test package is /opt/xcat/share/xcat/tools/autotest/. All test cases are in the sub directory \ *testcase*\ , indexed by the xCAT command, you can add your own test cases according to the test cases format below. The subdirectory \ *bundle*\  contains all the test cases bundles definition files, you can customize or create any test cases bundle file as required. The testing result information will be written into the subdirectory \ *result*\ , the timestamps are used as the postfixes for all the result files. xCAT-test package ships two configuration files template \ *aix.conf.template*\  and \ *linux.conf.template*\  for AIX and Linux environment, you can use the template files as the start point of making your own configuration file.


*******
OPTIONS
*******



\ **-?|-h**\ 
 
 Display usage message.
 


\ **-f**\  \ *configure file*\ 
 
 Specifies the configuration file with full-path. xCAT supports an example config file: /opt/xcat/share/xcat/tools/autotest/linux.conf.template
 


\ **-b**\  \ *case bundle list*\ 
 
 Comma separated list of test cases bundle files, each test cases bundle can contain multiple lines and each line for one test case name. The bundle files should be listed in: /opt/xcat/share/xcat/tools/autotest/bundle.
 


\ **-t**\  \ *cases list*\ 
 
 Comma separated list of test cases that will be run.
 


\ **-c**\  \ *cmd list*\ 
 
 Comma separated list of commands which will be tested, i.e., all the test cases under the command sub directory will be run.
 


\ **-l**\ 
 
 Display the test cases names specified by the flag -b, -t or -c.
 


\ **-s**\ 
 
 Display the bundle files and command with value: bundle or command.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


****************
TEST CASE FORMAT
****************


The xCAT-test test cases are in flat text format, the testing framework will parse the test cases line by line, here is an example of the test case:


.. code-block:: perl

   #required, case name
   start:case name
   #optional, description of the test case
   description: what the test case is for?
   #optional, environment requirements 
   os:AIX/Linux
   #optional, environment requirements
   arch:ppc/x86
   #optional, environment requirements
   hcp:hmc/mm/bmc/fsp
   #required, command need to run
   cmd:comand
   #optional, check return code of last executed command
   check:rc == or != return code
   #optional, check output of last executed command
   check:output== or != or =~ or !~ output check string
   end


\ **Note**\ : Each test case can have more than one \ *cmd*\  sections and each \ *cmd*\  section can have more than one \ *check:rc*\  sections and more than one \ *check:output*\  sections, the \ *output check string*\  can include regular expressions.


********
EXAMPLES
********



1.
 
 To run all  test cases related command rpower:
 
 
 .. code-block:: perl
 
    xcattest -f /tmp/config -c rpower
 
 


2.
 
 To run customized bundle with /tmp/config file:
 
 
 .. code-block:: perl
 
    xcattest -c lsdef -l  > /opt/xcat/share/xcat/tools/autotest/bundle/custom.bundle
    Modify custom.bundle
    xcattest -f /tmp/config -b custom.bundle
 
 


3.
 
 To run specified test cases with /tmp/config file:
 
 
 .. code-block:: perl
 
    xcattest -f /tmp/config -t lsdef_t_o_l_z
 
 


4.
 
 To add a new case to test chvm. In the example, we assume that the min_mem should not be equal to 16 in the lpar profile of computenode. The case name is chvm_custom. It create a test lpar named testnode firstly, that change the min_mem of the lpar to 16 using chvm, then check if min_mem have changed correctly. At last, the testnode be remove to ensure no garbage produced in the cases.
 
 
 .. code-block:: perl
 
    add a new test case file in /opt/xcat/share/xcat/tools/autotest/chvm
    edit filename
    start:chvm_custom
    hcp:hmc
    cmd:lsvm $$CN > /tmp/autotest.profile
    check:rc==0
    cmd:mkdef -t node -o testnode mgt=hmc groups=all
    cmd:mkvm testnode -i $$MaxLparID -l $$CN
    check:rc==0
    cmd:perl -pi -e 's/min_mem=\d+/min_mem=16/g' /tmp/autotest.profile
    cmd:cat /tmp/autotest.profile|chvm testnode
    check:rc==0
    cmd:lsvm testnode
    check:output=~min_mem=16
    cmd:rmvm testnode
    cmd:rm -f /tmp/autotest.profile
    end
 
 



****************
INLINE FUNCTIONS
****************


The xCAT-test testing framework provides some inline functions. The inline functions can be called in test cases as __FUNCTIONNAME(PARAMTERLIST)__ to get some necessary attributes defined in the configuration file. The inline functions can be used in \ *cmd*\  section and the \ *check:output*\  section.

1. \ **GETNODEATTR(nodename, attribute)**\  To get the value of specified node's attribute

2. \ **INC(digit)**\  To get value of digit+1.

For example, to run rscan command against the hardware control point of compute node specified in the configuration file:


.. code-block:: perl

   rscan __GETNODEATTR($$CN, hcp)__ -z
 3. B<GETTABLEVALUE(keyname, key, colname, table)> To get the value of column where keyname == key in specified table.



*****
FILES
*****


/opt/xcat/bin/xcattest

