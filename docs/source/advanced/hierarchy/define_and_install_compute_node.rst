Define and install your Compute Nodes
=====================================

Make /install available on the Service Nodes
--------------------------------------------

Note that all of the files and directories pointed to by your osimages should
be placed under the directory referred to in site.installdir (usually
/install), so they will be available to the service nodes. The installdir
directory is mounted or copied to the service nodes during the hierarchical
installation.

If you are not using the NFS-based statelite method of booting your compute
nodes and you are not using service node pools, set the installloc attribute
to "/install". This instructs the service node to mount /install from the
management node. (If you don't do this, you have to manually sync /install
between the management node and the service nodes.)

::

  chdef -t site  clustersite installloc="/install"

Make compute node syncfiles available on the servicenodes
---------------------------------------------------------

If you are not using the NFS-based statelite method of booting your compute
nodes, and you plan to use the syncfiles postscript to update files on the
nodes during install, you must ensure that those files are sync'd to the
servicenodes before the install of the compute nodes. To do this after your
nodes are defined, you will need to run the following whenever the files in
your synclist change on the Management Node:
::

  updatenode <computenoderange> -f

At this point you can return to the documentation for your cluster environment
to define and deploy your compute nodes.


