SSH Access: Accessing the installer via "ssh"
---------------------------------------------

**This mode is supported with debug level set to 2**

When ssh access to the installer is enabled, the admin can login into the installer through:

#. For RHEL, the installation won't halt, just login into the installer with ``ssh root@<node>``.

#. For SLES, the installation will halt after the ssh server is started, the console output looks like: ::

    ***  sshd has been started  ***


    ***  login using 'ssh -X root@<node>'  ***
    ***  run 'yast' to start the installation  ***

   xCAT configures the SLES installer with the temporary root password ``cluster``.
   This password is used only by the installer; it is not the installed system's
   root password from the ``passwd`` table.

   To use a different temporary installer password, add the SUSE SSH parameters
   to the node's kernel command line and regenerate its boot configuration: ::

     chdef -t node -o <node> addkcmdline="ssh=1 ssh.password=<temporary-password>"
     nodeset <node> osimage=<osimage>

   The temporary password is stored in the generated boot configuration and is
   visible in the kernel command line. Do not reuse the installed system's root
   password. Restore the node's previous ``addkcmdline`` value after debugging
   and run ``nodeset`` again.

   The admin can open 2 sessions and run ``ssh -X root@<node>`` with the
   temporary installer password, then run ``yast`` to continue installation in
   one session and inspect the installation process in the other session.

   After the installation is finished, the system requires a reboot. The installation will halt again before the system configuration, the console output looks like: ::

    *** Preparing SSH installation for reboot ***
    *** NOTE: after reboot, you have to reconnect and call yast.ssh ***

   Just as the message above suggests, the admin should run ``ssh -X root@<node>`` to access the installer and run ``yast.ssh`` to finish the installation.

   **Note**: For sles12, during the second stage of an SSH installation YaST freezes. It is blocked by the SuSEFirewall service because the ``SYSTEMCTL_OPTIONS`` environment variable is not set properly. Workaround: When logged in for the second time to start the second stage of the SSH installation, call **yast.ssh** with the ``--ignore-dependencies`` as follows: ::

    SYSTEMCTL_OPTIONS=--ignore-dependencies yast.ssh

#. For UBT, the installation will halt on the message in the console similar to: ::

    ┌───────────┤ [!!] Continue installation remotely using SSH ├───────────┐
    │                                                                       │
    │                               Start SSH                               │
    │ To continue the installation, please use an SSH client to connect to  │
    │ the IP address <node> and log in as the "installer" user. For         │
    │ example:                                                              │
    │                                                                       │
    │    ssh installer@<node>                                               │
    │                                                                       │
    │ The fingerprint of this SSH server's host key is:                     │
    │ <SSH_host_key>                                                        │
    │                                                                       │
    │ Please check this carefully against the fingerprint reported by your  │
    │ SSH client.                                                           │
    │                                                                       │
    │                              <Continue>                               │
    │                                                                       │
    └───────────────────────────────────────────────────────────────────────┘

   Just as the message above suggests, the admin can run ``ssh installer@<node>`` with the password "cluster" to login into the installer, the following message shows on login: ::

    ┌────────────────────┤ [!!] Configuring d-i ├─────────────────────┐
    │                                                                 │
    │ This is the network console for the Debian installer. From      │
    │ here, you may start the Debian installer, or execute an         │
    │ interactive shell.                                              │
    │                                                                 │
    │ To return to this menu, you will need to log in again.          │
    │                                                                 │
    │ Network console option:                                         │
    │                                                                 │
    │                Start installer                                  │
    │                Start installer (expert mode)                    │
    │                Start shell                                      │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘

   The admin can open 2 sessions and then select "Start installer" to continue installation in one session and select "Start shell" in the other session to inspect the installation process in the installer.

