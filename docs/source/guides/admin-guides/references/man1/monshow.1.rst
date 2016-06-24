
#########
monshow.1
#########

.. highlight:: perl


****
NAME
****


\ **monshow**\  - Shows event data for monitoring.


********
SYNOPSIS
********


\ **monshow [-h| -**\ **-help]**\ 

\ **monshow [-v| -**\ **-version]**\ 

\ **monshow**\  \ *name*\  \ *[noderange]*\  [\ **-s**\ ] [\ **-t**\  \ *time*\ ] [\ **-a**\  \ *attributes*\ ] [\ **-w**\  \ *attr*\  < \ *operator*\  > \ *val*\  [\ **-w**\  \ *attr*\  < \ *operator*\  > \ *val*\ ] ... ][\ **-o {p|e}**\ ]


***********
DESCRIPTION
***********


This command displays the events that happened on the given nodes or the monitoring data that is collected from the given nodes for a monitoring plugin.


**********
PARAMETERS
**********


\ *name*\  is the name of the monitoring plug-in module to be invoked.

\ *noderange*\  is a list of nodes to be showed for. If omitted, the data for all the nodes will be displayed.


*******
OPTIONS
*******


\ **-h | -**\ **-help**\           Display usage message.

\ **-v | -**\ **-version**\       Command Version.

\ **-s**\ 	shows the summary data.

\ **-t**\ 	specifies a range of time for the data, The default is last 60 minutes. For example -t 6-4, it will display the data from last 6 minutes to 4 minutes; If it is -t 6, it will display the data from last 6 minutes until now.

\ **-a**\ 	specifies a comma-separated list of attributes or metrics names. The default is all.

\ **-w**\ 	specify one or multiple selection string that can be used to select events. The operators ==, !=, =,!,>,<,>=,<= are available.  Wildcards % and _ are supported in the pattern string. % allows you to match any string of any length(including zero length) and _ allows you to match on a single character. The valid attributes are eventtype, monitor, monnode, application, component, id, serverity, message, rawdata, comments. Valid severity are: Informational, Warning, Critical.

Operator descriptions:


\ **==**\  Select event where the attribute value is exactly this value.



\ **!=**\  Select event where the attribute value is not this specific value.



\ **=~**\  Select event where the attribute value matches this pattern string. Not work with severity.



\ **!~>**\  Select event where the attribute value does not match this pattern string. Not work with severity.



\ **>**\  Select event where the severity is higher than this value. Only work with severity.



\ **<**\  Select event where the severity is lower than this value. Only work with severity.



\ **>=**\  Select event where the severity is higher than this value(include). Only work with severity.



\ **<=**\  Select event where the severity is lower than this value(include). Only work with severity.



Note: if the "val" or "operator" fields includes spaces or any other characters that will be parsed by shell, the "attr<operator>val" needs to be quoted. If the operator is "!~", the "attr<operator>val" needs to be quoted using single quote.

\ **-o**\ 	specifies montype, it can be p or e. p means performance, e means events.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To show summary data about PctRealMemFree and PctTotalTimeIdle of cluster in last 6 minutes, enter:


.. code-block:: perl

   monshow rmcmon -s -a PctRealMemFree,PctTotalTimeIdle -t 6


2. To show all data of node1 and node2, enter:


.. code-block:: perl

   monshow rmcmon node1,node2


3. To show summary data of nodes which managed by servicenode1, enter:


.. code-block:: perl

   monshow rmcmon servicenode1 -s


4. To show RMC event with severity Critical, enter:


.. code-block:: perl

   monshow rmcmon -w severity==Critical



*****
FILES
*****


/opt/xcat/bin/monshow


********
SEE ALSO
********


monls(1)|monls.1, monstart(1)|monstart.1, monstop(1)|monstop.1, monadd(1)|monadd.1, monrm(1)|monrm.1, moncfg(1)|moncfg.1, mondecfg(1)|mondecfg.1

