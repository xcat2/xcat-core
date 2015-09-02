.. _deploy_os:

Initialize the Compute for Deployment
=====================================

XCAT use '**nodeset**' command to associate a specific image to a node which will be installed with this image.
::
    nodeset <nodename> osimage=<osimage>

There are more attributes of nodeset used for some specific purpose or specific machines, for example:

* **runimage**: If you would like to run a task after deployment, you can define that task with this attribute.
* **runcmd**: This instructs the node to boot to the xCAT nbfs environment and proceed to configure BMC for basic remote access.  This causes the IP, netmask, gateway, username, and password to be programmed according to the configuration table.
* **shell**: This instructs tho node to boot to the xCAT genesis environment, and present a shell prompt on console.  The node will also be able to be sshed into and have utilities such as wget, tftp, scp, nfs, and cifs.  It will have storage drivers available for many common systems.

Choose such additional attribute of nodeset according to your requirement, if want to get more informantion about nodeset, refer to nodeset's man page.

Start the OS Deployment
=======================

Start the deployment involves two key operations. One is setup node boot from network, another is reboot ndoe:

For Power machine, those two operations can be completed by one command '**rnetboot**', 
::
    rnetboot <node>

But for x server, those two operations need two independent commands.
Set x server boot from network, run	
::
    rsetboot <node> net

Reboot x server:
::
    rpower <node> reset

	

