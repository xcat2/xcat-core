Run the Syncing File action in the updatenode process
-----------------------------------------------------

Running ``updatenode`` command with **-F** option, will sync files configured in the synclist file to the nodes. ``updatenode`` does not sync images, use ``xdcp -i -F`` command to sync images.

``updatenode`` can be used to sync files to to diskful or diskless nodes. ``updatenode`` cannot be used to sync files to statelite nodes.

Steps to make the Syncing File working in the ``updatenode -F`` command:

   #. Create the synclist file with the entries indicating which files should be synced. (refer to :ref:`The_Format_of_synclist_file_label`)
   #. Put the synclist into the proper location (refer to :ref:`the_localtion_of_synclist_file_for_updatenode_label`).
   #. Run the ``updatenode <noderange> -F`` command to initiate the Syncing File action.

.. note:: Since Syncing File action can be initiated by the ``updatenode -F``, the ``updatenode -P`` does NOT support to re-run the **syncfiles** postscript, even if you specify the **syncfiles** postscript on the ``updatenode`` command line or set the **syncfiles** in the **postscripts.postscripts** attribute.

