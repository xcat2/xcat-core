Run xdcp command to perform Syncing File action
------------------------------------------------

``xdcp`` command supplies three options **'-F' , -s, and '-i'** to support the Syncing File function.

   * -F|--File rsync input file

Specifies the full path to the synclist file that will be used to build the ``rsync`` command

    * -s

Specifies to rsync to the service nodes only for the input compute noderange.

    * -i|--rootimg install image for Linux

Specifies the full path to the install image on the local node. By default, if the -F option is specified, the **'rsync'** command is used to perform the syncing file function. For the ``rsync`` in ``xdcp``, only the ***ssh** remote shell is supported for ``rsync``. ``xdcp`` uses the **'-Lpotz'** as the default flags to call the rsync command. More flags for rsync command can be specified by adding **'-o'** flag to the call to ``xdcp``.

For example: ::

    Using xdcp '-F' option to sync files which are listed in the /install/custom/commonsyncfiles/<profile>.synclist directory to the node group named 'compute'. If the node group compute is serviced by servicenodes, then the files will be automatically staged to the correct service nodes, and then synced to the compute nodes from those service nodes. The files will be stored in /var/xcat/syncfiles directory on the service nodes by default, or in the directory indicated in the site.SNsyncfiledir attribute. See -s option below. 
    xdcp compute -F /install/custom/commonsynfiles/<profile>.synclist

For Linux nodes, using **xdcp '-i'** option with **'-F'** to sync files created in the **/install/custom/<inst_type>/<os><profile>.synclist** to the osimage in the directory **/install/<inst_type>/<os>/<arch>/<profile>/rootimg**: ::
      
    xdcp -i /install/<inst_type>/<os>/<arch>/<profile>/rootimg -F /install/custom/<inst_type>/<os>/<profile>.synclist

Using the **xdcp '-s'** option to sync the files only to the service nodes for the node group named 'compute'. The files will be placed in the default **/var/xcat/syncfiles** directory or in the directory as indicated in the **site.SNsyncfiledir** attribute. If you want the files synched to the same directory on the service node that they come from on the Management Node, set **site.SNsyncfiledir=/**. This can be setup before a node install, to have the files available to be synced during the install: ::
   
    xdcp compute -s -F /install/custom/<inst_type>/<os>/<profile>.synclist

