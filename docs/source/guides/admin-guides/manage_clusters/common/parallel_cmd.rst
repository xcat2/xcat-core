Parallel Commands
=================

xCAT delivers a set of commands that can be run remote commands (ssh,scp,rsh,rcp,rsync,ping,cons) in parallel on multiple nodes. In addition the command have the capability of formatting the output from the commands, so the results are easier to process. These commands will make it much easier to administer your large cluster.

For a list of the Parallel Commands and their man pages doc `parallel commands`_.

Examples for xdsh
-----------------

- To set up the SSH keys for root on node1, run as root: ::

    xdsh node1 -K

- To run the ps -ef command on node targets node1 and node2, enter: ::

    xdsh node1,node2 "ps -ef"

- To run the ps command on node targets node1 and run the remote command with the -v and -t flag, enter: ::

    xdsh node1,node2 -o"-v -t" ps =item *

- To execute the commands contained in myfile in the XCAT context on several node targets, with a fanout of 1, enter: ::

    xdsh node1,node2 -f 1 -e myfile

- To run the ps command on node1 and ignore all the dsh environment variable except the DSH_NODE_OPTS, enter: ::

    xdsh node1 -X `DSH_NODE_OPTS' ps

- To run on Linux, the xdsh command "dpkg | grep vim" on the node ubuntu diskless image, enter: ::

    xdsh -i /install/netboot/ubuntu14.04.2/ppc64el/compute/rootimg "dpkg -l|grep vim"

- To run xdsh with the non-root userid "user1" that has been setup as an xCAT userid and with sudo on node1 and node2 to run as root, do the following, see xCAT doc on Granting_Users_xCAT_privileges: ::

    xdsh node1,node2 --sudo -l user1 "cat /etc/passwd"

Examples for xdcp
-----------------

- To copy the /etc/hosts file from all nodes in the cluster to the /tmp/hosts.dir directory on the local host, enter: ::

    xdcp all -P /etc/hosts /tmp/hosts.dir

  A suffix specifying the name of the target is appended to each file name. The contents of the /tmp/hosts.dir directory are similar to: ::

   hosts._node1   hosts._node4   hosts._node7
   hosts._node2   hosts._node5   hosts._node8
   hosts._node3   hosts._node6

- To copy /localnode/smallfile and /tmp/bigfile to /tmp on node1 using rsync and input -t flag to rsync, enter: ::

    xdcp node1 -r /usr/bin/rsync -o "-t" /localnode/smallfile /tmp/bigfile /tmp

- To copy the /etc/hosts file from the local host to all the nodes in the cluster, enter: ::

    xdcp all /etc/hosts /etc/hosts

- To rsync the /etc/hosts file to your compute nodes:

  Create a rsync file /tmp/myrsync, with this line: ::

   /etc/hosts -> /etc/hosts

   or

   /etc/hosts -> /etc/ (last / is required)

  Run: ::

   xdcp compute -F /tmp/myrsync

- To rsync the /etc/file1 and file2 to your compute nodes and rename to filex and filey:

  Create a rsync file /tmp/myrsync, with these line: ::

   /etc/file1 -> /etc/filex

   /etc/file2 -> /etc/filey

  Run: ::

   xdcp compute -F /tmp/myrsync to update the Compute Nodes

- To rsync files in the Linux image at /install/netboot/ubuntu14.04.2/ppc64el/compute/rootimg on the MN:

  Create a rsync file /tmp/myrsync, with this line: ::

   /etc/hosts /etc/passwd -> /etc

  Run: ::

   xdcp -i /install/netboot/ubuntu14.04.2/ppc64el/compute/rootimg -F /tmp/myrsync


