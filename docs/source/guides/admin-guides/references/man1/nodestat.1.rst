
##########
nodestat.1
##########

.. highlight:: perl


****
Name
****


\ **nodestat**\  - display the running status of each node in a noderange


****************
\ **Synopsis**\ 
****************


\ **nodestat**\  [\ *noderange*\ ] [\ **-m | -**\ **-usemon**\ ] [\ **-p | -**\ **-powerstat**\ ] [\ **-f**\ ] [\ **-u | -**\ **-updatedb**\ ]

\ **nodestat**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **nodestat**\   displays and optionally updates the database the running status of a
single or range of nodes or groups.  See noderange(3)|noderange.3.

By default, it works as following:
    1. gets the sshd,pbs_mom,xend port status;
    2. if none of them are open, it gets the fping status;
    3. for pingable nodes that are in the middle of deployment, it gets the deployment status;
    4. for non-pingable nodes, it shows 'noping'.

When -m is specified and there are settings in the monsetting table, it displays the status of the applications specified in the monsetting table. When -p is specified it shows the power status for the nodes that are not pingable. When -u is specified it saves the status info into the xCAT database. Node's pingable status and deployment status is saved in the nodelist.status column. Node's application status is saved in the nodelist.appstatus column.

To specify settings in the \ **monsetting**\  table, use 'xcatmon' as the name, 'apps' as the key and the value will be a list of comma separated list of application names. For each application, you can specify the port number that can be queried on the nodes to get the running status. Or you can specify a command that can be called to get the node status from. The command can be a command that can be run locally at the management node or the service node for hierarchical cluster, or a command that can be run remotely on the nodes.

The following is an example of the settings in the \ **monsetting**\  table:


.. code-block:: perl

     name key value
     xcatmon apps ssh,ll,gpfs,someapp
     xcatmon gpfs cmd=/tmp/mycmd,group=compute,group=service
     xcarmon ll port=9616,group=compute
     xcatmon someapp dcmd=/tmp/somecmd


Keywords to use:


.. code-block:: perl

     apps -- a list of comma separated application names whose status will be queried. For how to get the status of each app, look for app name in the key field in a different row.
     port -- the application daemon port number, if not specified, use internal list, then /etc/services. 
     group -- the name of a node group that needs to get the application status from. If not specified, assume all the nodes in the nodelist table. To specify more than one groups, use group=a,group=b format.
     cmd -- the command that will be run locally on mn or sn.
     lcmd -- the command that will be run the the mn only. 
     dcmd -- the command that will be run distributed on the nodes using xdsh <nodes> ....


For commands specified by 'cmd' and 'lcmd', the input of is a list of comma separated node names, the output must be in the following format:


.. code-block:: perl

   node1:string1
   node2:string2
   ...


For the command specified by 'dcmd', no input is needed, the output can be a string.


***************
\ **Options**\ 
***************



\ **-f**\ 
 
 Uses fping instead of nmap even if nmap is available.  If you seem to be having a problem with false negatives, fping can be more forgiving, but slower.
 


\ **-m | -**\ **-usemon**\ 
 
 Uses the settings from the \ **monsetting**\  talbe to determine a list of applications that need to get status for.
 


\ **-p | -**\ **-powerstat**\ 
 
 Gets the power status for the nodes that are 'noping'.
 


\ **-u | -**\ **-updatedb**\ 
 
 Updates the status and appstatus columns of the nodelist table with the returned running status from the given nodes.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 



****************
\ **Examples**\ 
****************



1.
 
 
 .. code-block:: perl
 
   nodestat compute
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1   sshd
   node2   sshd
   node3   ping
   node4   pbs
   node5   noping
 
 


2.
 
 
 .. code-block:: perl
 
   nodestat compute -p
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1   sshd
   node2   sshd
   node3   ping
   node4   pbs
   node5   noping(Shutting down)
 
 


3.
 
 
 .. code-block:: perl
 
   nodestat compute -u
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1   sshd
   node2   sshd
   node3   ping
   node4   netboot
   node5   noping
 
 


4.
 
 
 .. code-block:: perl
 
   nodestat compute -m
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node1   ping,sshd,ll,gpfs=ok
   node2   ping,sshd,ll,gpfs=not ok,someapp=something is wrong
   node3   netboot
   node4   noping
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, nodels(1)|nodels.1, nodeset(8)|nodeset.8

