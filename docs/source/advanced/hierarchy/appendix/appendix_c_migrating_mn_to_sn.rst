Appendix C: Migrating a Management Node to a Service Node
=========================================================

Directly converting an existing Management Node to a Service Node may have some issues and is not recommended.  Do the following steps to convert the xCAT Management Node into a Service node: 

#. backup your xCAT database on the Management Node
#. Install a new xCAT Management node
#. Restore your xCAT database into the new Management Node
#. Re-provision the old xCAT Management Node as a new Service Node 

