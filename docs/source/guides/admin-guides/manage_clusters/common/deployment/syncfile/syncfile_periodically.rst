Run the Syncing File action periodically
-----------------------------------------

If the admins want to run the Syncing File action automatically or periodically, the ``xdcp -F``, ``xdcp -i -F`` and ``updatenode -F`` commands can be used in the script, crontab or FAM directly.

For example:

Use the cron daemon to sync files in the **/install/custom/<inst_type>/<distro>/<profile>.<os>.synclist** to the nodegroup 'compute' every 10 minutes by the xdcp command by adding this to crontab. : ::
      
       */10 * * * * root /opt/xcat/bin/xdcp compute -F /install/custom/<inst_type>/<distro>/<profile>.<distro>.synclist

Use the cron daemon to sync files for the nodegroup 'compute' every 10 minutes by updatenode command. ::

       */10 * * * * root /opt/xcat/bin/updatenode compute -F

** Related To do**
Add reference







