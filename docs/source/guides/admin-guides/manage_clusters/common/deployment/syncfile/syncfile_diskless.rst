Run the Sync'ing File action in the creating diskless image process
--------------------------------------------------------------------

Different approaches are used to create the diskless image. The **Sync'ing** File action is also different.

The ``packimage`` command is used to prepare the root image files and package the root image. The Syncing File action is performed here.

Steps to make the Sync'ing File working in the packimage command: 

    1. Prepare the synclist file and put it into the appropriate location as describe above in (refer :ref:`the_localtion_of_synclist_file_for_updatenode_label`)
    2. Run packimage as is normally done.

