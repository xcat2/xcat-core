osdeploy
========

**osdeploy** operating system provision process. Supports two modes - 'Realtime monitor' and 'Replay history'.
  
Realtime monitor: This is a default. This tool with monitor provision state of the node. Trigger 'Realtime monitor' before rebooting target node to do provisioning.
    
Replay history: Used after provisioning is finished to probe the previously completed provisioning.

**Note**: Currently, hierarchical structure is not supported.

Usage
-----

::

    xcatprobe osdeploy -h
    xcatprobe osdeploy -n <node_range>  [-t <max_waiting_time>] [-V]
    xcatprobe osdeploy -n <node_range> -r <xxhxxm> [-V]

Options:

* **-n**: The range of nodes to be monitored or replayed.
* **-r**: Trigger 'Replay history' mode. Follow the duration of rolling back. Units are 'h' (hour) or 'm' (minute). If unit is not specified, hour will be used by default.
* **-t**: The maximum time to wait when doing monitor, unit is minutes. default is 60.
* **-V**: Output more information.

``-r`` means replay history of OS provision, if no ``-r`` means to do realtime monitor.

Realtime monitor
----------------

To monitor OS provisioning in real time, open at least 2 terminal windows. One to run ``osdeploy`` probe: ::

    xcatprobe osdeploy -n cn1 [-V]

After some pre-checks, the probe will wait for provisioning information, similar to output below:  ::

    # xcatprobe osdeploy -n c910f03c17k20
    The install NIC in current server is enp0s1                                                                       [INFO]
    All nodes which will be deployed are valid                                                                        [ OK ]
    -------------------------------------------------------------
    Start capturing every message during OS provision process......
    -------------------------------------------------------------

Open second terminal window to run provisioning: ::

    nodeset cn1 osimage=<osimage>
    rpower cn1 boot

When all the nodes complete provisioning, the probe will exit and display output similar to: ::

    # xcatprobe osdeploy -n c910f03c17k20
    The install NIC in current server is enp0s1                                                                       [INFO]
    All nodes which will be deployed are valid                                                                        [ OK ]
    -------------------------------------------------------------
    Start capturing every message during OS provision process......
    -------------------------------------------------------------
    
    [c910f03c17k20] Use command rinstall to reboot node c910f03c17k20
    [c910f03c17k20] Node status is changed to powering-on
    [c910f03c17k20] Receive DHCPDISCOVER via enp0s1
    [c910f03c17k20] Send DHCPOFFER on 10.3.17.20 back to 42:d0:0a:03:11:14 via enp0s1
    [c910f03c17k20] DHCPREQUEST for 10.3.17.20 (10.3.5.4) from 42:d0:0a:03:11:14 via enp0s1
    [c910f03c17k20] Send DHCPACK on 10.3.17.20 back to 42:d0:0a:03:11:14 via enp0s1
    [c910f03c17k20] Via TFTP download /boot/grub2/grub2-c910f03c17k20
    [c910f03c17k20] Via TFTP download /boot/grub2/powerpc-ieee1275/normal.mod
    ......
    [c910f03c17k20] Postscript: otherpkgs exited with code 0
    [c910f03c17k20] Node status is changed to booted
    [c910f03c17k20] done
    [c910f03c17k20] provision completed.(c910f03c17k20)
    [c910f03c17k20] provision completed                                                                               [ OK ]
    All nodes specified to monitor, have finished OS provision process                                                [ OK ]
    ==================osdeploy_probe_report=================
    All nodes provisioned successfully                                                                                [ OK ]

    
If there is something wrong when provisioning, this probe will exit when timeout is reachedd or ``Ctrl+C`` is pressed by user. The maximum time can be set by using ``-t`` as below(default 30 minutes) ::


    xcatprobe osdeploy -n cn1 -t 30

Replay history
--------------

To replay history of OS provision from 1 hour 20 minutes ago, use command as ::

    xcatprobe osdeploy -n cn1 -r 1h20m

Outout will be similar to: ::

    # xcatprobe osdeploy -n c910f03c17k20
    The install NIC in current server is enp0s1                                                                       [INFO]
    All nodes which will be deployed are valid                                                                        [ OK ]
    Start to scan logs which are later than *********, waiting for a while.............
    ==================osdeploy_probe_report=================
    All nodes provisioned successfully                                                                                [ OK ]

