Synchronizing Files during the installation process
----------------------------------------------------

The policy table must have the entry to allow syncfiles postscript to access the Management Node. Make sure this entry is in your table:

 ``tabdump policy`` ::

       #priority,name,host,commands,noderange,parameters,time,rule,comments,disable
       .
       .
       "4.6",,,"syncfiles",,,,"allow",,
       .
       .

Hierarchy and Service Nodes
~~~~~~~~~~~~~~~~~~~~~~~~~~~

If using Service nodes to manage you nodes, you should make sure that the service nodes have been synchronized with the latest files from the Management Node before installing. If you have a group of compute nodes (compute) that are going to be installed that are serviced by SN1, then run the following before the install to sync the current files to SN1. Note: the noderange is the compute node names, updatenode will figure out which service nodes need updating. 

``updatenode compute -f``

Diskful installation
~~~~~~~~~~~~~~~~~~~~



The 'syncfiles' postscript is in the defaults section of the postscripts table. To enable the syn files postscript to sync files to the nodes during install the user need to do the following:

   * Create the synclist file with the entries indicating which files should be synced.  (refer to :ref:`The_Format_of_synclist_file_label` )
   * Put the synclist into the proper location for the node type (refer to :ref:`the_localtion_of_synclist_file_for_updatenode_label`)
     
Make sure your postscripts table has the syncfiles postscript listed 

``tabdump postscripts`` ::

       #node,postscripts,postbootscripts,comments,disable
       "xcatdefaults","syslog,remoteshell,syncfiles","otherpkgs",,

Diskless Installation
~~~~~~~~~~~~~~~~~~~~~

The diskless boot is similar with the diskful installation for the synchronizing files operation, except that the packimage  commands will sync files to the root directories of image during the creating image process.

Creating the synclist file as the steps in Diskful installation section, then the synced files will be synced to the os image during the packimage and mkdsklsnode commands running.

Also the files will always be re-synced during the booting up of the diskless node. 

