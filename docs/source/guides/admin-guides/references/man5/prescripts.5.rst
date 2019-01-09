
############
prescripts.5
############

.. highlight:: perl


****
NAME
****


\ **prescripts**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **prescripts Attributes:**\   \ *node*\ , \ *begin*\ , \ *end*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The scripts that will be run at the beginning and the end of the nodeset(Linux), nimnodeset(AIX) or mkdsklsnode(AIX) command.


**********************
prescripts Attributes:
**********************



\ **node**\ 
 
 The node name or group name.
 


\ **begin**\ 
 
 The scripts to be run at the beginning of the nodeset(Linux), nimnodeset(AIX) or mkdsklsnode(AIX) command.
  The format is:
    [action1:]s1,s2...[| action2:s3,s4,s5...]
  where:
   - action1 and action2 for Linux are the nodeset actions specified in the command. 
     For AIX, action1 and action1 can be 'diskless' for mkdsklsnode command'
     and 'standalone for nimnodeset command. 
   - s1 and s2 are the scripts to run for action1 in order.
   - s3, s4, and s5 are the scripts to run for actions2.
  If actions are omitted, the scripts apply to all actions.
  Examples:
    myscript1,myscript2  (all actions)
    diskless:myscript1,myscript2   (AIX)
    install:myscript1,myscript2|netboot:myscript3   (Linux)
  All the scripts should be copied to /install/prescripts directory.
  The following two environment variables will be passed to each script: 
    NODES a coma separated list of node names that need to run the script for
    ACTION current nodeset action.
  If '#xCAT setting:MAX_INSTANCE=number' is specified in the script, the script
  will get invoked for each node in parallel, but no more than number of instances
  will be invoked at at a time. If it is not specified, the script will be invoked
  once for all the nodes.
 


\ **end**\ 
 
 The scripts to be run at the end of the nodeset(Linux), nimnodeset(AIX),or mkdsklsnode(AIX) command. The format is the same as the 'begin' column.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

