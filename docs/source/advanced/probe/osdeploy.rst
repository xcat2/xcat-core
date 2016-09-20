osdeploy
========

**osdeploy** can be used to probe OS provision process. Realtime monitor or replay history of OS provision process.

If realtime monitor, run this command before ``rpower`` node(including the command rpower node indirectly, e.g ``rinstall``, ``rnetboot``).

**Note**: Currently, hierarchical structure is not supported.

Usage
-----

::

    xcatprobe osdeploy -h
    xcatprobe osdeploy -n <node_range> [-V]
    xcatprobe osdeploy -n <node_range> -r <xxhxxm> [-V]

Options:

* **-n**: The range of nodes for monitor or replay log.
* **-r**: Replay history log for probe provisioniong. Input a start time when probe should begin. Supported time formats are ``xxhxxm``, ``xxh``, or ``xxm``. If units not specified, hour will be used by default.
* **-t**: The maximum time in minutes to wait when doing monitor, default is 60.
* **-V**: Output more information for debug.

``-r`` means replay history of OS provision, if no ``-r`` means to do realtime monitor.

This command will do pre-check before realtime monitor and replay history automatically. If all nodes' definition are valid, will run monitor or replay. Or will exit and show error message.

Realtime monitor
----------------

If want to realtime monitor OS provision, please Open 2 terminal windows at least. One is to run ``osdeploy`` command as below ::

    xcatprobe osdeploy -n cn1 [-V]

after pre-check will wait for provision information and show as below ::

    # xcatprobe osdeploy -n c910f03c17k20
    The install NIC in current server is enp0s1                                                                       [INFO]
    All nodes which will be deployed are valid                                                                        [ OK ]
    -------------------------------------------------------------
    Start capturing every message during OS provision process......
    -------------------------------------------------------------

do provision on another terminal window. ::

    nodeset cn1 osimage=<osimage>
    rpower cn1 boot

When all the nodes complete provision, will exit and output summary as below ::

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
    ==================conclusion_report=================
    All nodes provision successfully                                                                                  [ OK ]

    
If there is something wrong when provision, will exit when timeout or press ``Ctrl+C`` by user. The maximum time can be set by using ``-t`` as below ::

    xcatprobe osdeploy -n cn1 -t 30

The maximum time is set to 30 minites.

Replay history
--------------

It want to replay history of OS provision from 1 hour 20 minutes ago, use command as ::

    xcatprobe osdeploy -n cn1 -r 1h20m

The outout will be as below ::

    # xcatprobe osdeploy -n c910f03c17k20
    The install NIC in current server is enp0s1                                                                       [INFO]
    All nodes which will be deployed are valid                                                                        [ OK ]
    Start to scan logs which are later than *********, waiting for a while.............
    ==================conclusion_report=================
    All nodes provision successfully                                                                                  [ OK ]

