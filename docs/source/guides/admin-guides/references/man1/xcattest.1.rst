
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

\ **xcattest**\  [\ **-f**\  \ *configure file*\ [\ **:System**\ ]] [\ **-l**\  [{\ **caselist|caseinfo|casenum**\ }]] [\ **-r**\ ] [\ **-q**\ ] [\ **-b**\  \ *testcase bundle list*\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ [\ **:System**\ ]] [\ **-l**\  [{\ **caselist|caseinfo|casenum**\ }]] [\ **-r**\ ] [\ **-q**\ ] [\ **-t**\  \ *testcase name list*\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ [\ **:System**\ ]] [\ **-l**\  [{\ **caselist|caseinfo|casenum**\ }]] [\ **-r**\ ] [\ **-q**\ ] [\ **-c**\  \ *testcase command list*\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ [\ **:System**\ ]] [\ **-l**\  [{\ **caselist|caseinfo|casenum**\ }]] [\ **-r**\ ] [\ **-q**\ ] [\ **-s**\  \ *testcase filter expression*\ ]

\ **xcattest**\  [\ **-f**\  \ *configure file*\ [\ **:System**\ ]] \ **-l bundleinfo**\ 


***********
DESCRIPTION
***********


The \ **xcattest**\  command runs test cases to verify the xCAT functions. It can be used to ensure the code changes you made do not break the existing commands; to run acceptance test for new build you got; to verify the xCAT snapshot build or development build before putting it onto your production system. The \ **xcattest**\  command is part of the xCAT package \ *xCAT-test*\ .

The root directory for the \ *xCAT-test*\  package is \ */opt/xcat/share/xcat/tools/autotest/*\ . All test cases are in the sub directory \ *testcase*\ , indexed by the xCAT command, you can add your own test cases according to the test cases format below. The subdirectory \ *bundle*\  contains all the test cases bundle definition files, you can customize or create any test cases bundle file as required. The testing result information will be written into the subdirectory \ *result*\ , the timestamps are used as the postfixes for all the result files. \ *xCAT-test*\  package ships two configuration file templates: \ *aix.conf.template*\  and \ *linux.conf.template*\  for AIX and Linux environment, you can use the template files as the starting point of making your own configuration file.


*******
OPTIONS
*******



\ **-?|-h**\ 
 
 Display usage message.
 


\ **-f**\  \ *configure file*\ 
 
 Specifies the configuration file with full-path. If not specified, an example config file: \ */opt/xcat/share/xcat/tools/autotest/linux.conf.template*\  is used by default. If \ **System**\  tag is used, only \ *[System]*\  section in the configuration file will be used. If \ **System**\  is not used, all other sections of the configuration file will be used, like \ *[Table]*\ , \ *[Object]*\ , etc.
 


\ **-b**\  \ *testcase bundle list*\ 
 
 Comma separated list of test case bundle files, each test cases bundle can contain multiple lines and each line for one test case name. The bundle files should be placed in \ */opt/xcat/share/xcat/tools/autotest/bundle*\ .
 


\ **-t**\  \ *testcase name list*\ 
 
 Comma separated list of test cases to run.
 


\ **-c**\  \ *testcase command list*\ 
 
 Comma separated list of commands which will be tested, i.e., all the test cases under the command sub directory will be run.
 


\ **-s**\  \ *filter expression*\ 
 
 Run testcases with testcase \ **label**\  attribute matching \ *filter expression*\ . Operators \ **|**\ , \ **+**\ , and \ **-**\  can be used. Expresson \ *"label1+label2-label3|label4|label5"*\  will match testcases that have \ **label**\  attribute matching "label1" and "label2", but not "label3" or testcases that have \ **label**\  attribute matching "label4" or testcases that have \ **label**\  attribute matching "label5"
 


\ **-l {caselist|caseinfo|casenum|bundleinfo}**\ 
 
 Display rather than run the test cases. The \ **caselist**\  is a default and will display a list of testcase names. \ **caseinfo**\  will display testcase names and descriptions. \ **casenum**\  will display the number of testcases. \ **bundleinfo**\  will display testcase bundle names and descriptions.
 


\ **-r**\ 
 
 Back up the original environment settings before running test, and restore them after running test.
 


\ **-q**\ 
 
 Do not print output of test cases to STDOUT, instead, log output to \ */opt/xcat/share/xcat/tools/autotest/result*\ .
 



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
   #optional, label
   label:label1
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
 
 To add a new case to test \ **chvm**\ . In the example, we assume that the min_mem should not be equal to 16 in the lpar profile of computenode. The case name is chvm_custom. It create a test lpar named testnode firstly, that change the min_mem of the lpar to 16 using chvm, then check if min_mem have changed correctly. At last, the testnode be remove to ensure no garbage produced in the cases.
 
 
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
 
 


5.
 
 To run all test cases that have \ *label:kdump*\  or \ *label:parallel_cmds*\ :
 
 
 .. code-block:: perl
 
    xcattest -s kdump|parallel_cmds
 
 


6.
 
 To display all bundles and their descriptions:
 
 
 .. code-block:: perl
 
    xcattest -l bundleinfo
 
 



****************
INLINE FUNCTIONS
****************


The xCAT-test testing framework provides some inline functions. The inline functions can be called in test cases as __FUNCTIONNAME(PARAMTERLIST)__ to get some necessary attributes defined in the configuration file. The inline functions can be used in \ *cmd*\  section and the \ *check:output*\  section.


1.
 
 \ **GETNODEATTR(nodename, attribute)**\  To get the value of specified node's attribute
 


2.
 
 \ **INC(digit)**\  To get value of digit+1.
 
 For example, to run \ **rscan**\  command against the hardware control point of compute node specified in the configuration file:
 
 
 .. code-block:: perl
 
    rscan __GETNODEATTR($$CN, hcp)__ -z
 
 


3.
 
 \ **GETTABLEVALUE(keyname, key, colname, table)**\  To get the value of column where keyname == key in specified table.
 



*****
FILES
*****


/opt/xcat/bin/xcattest

