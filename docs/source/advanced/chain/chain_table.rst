Understand chain table
======================

The **chain** table is designed to store the tasks(For example: 'runcmd=bmcsetup', 'runimage=<URL>', 'osimage=<image name>', 'install', 'boot', 'shell', 'standby' ...). There are three related attributes **currstate**,**currchain** and **chain** in the chain table which are used to perform the **chain** mechanism.

When genesis is running on the node, it will sends 'get_task/get_next_task' request to xcatd. Then, xcatd will first copies the **chain** attribute to the **currchain** attribute, then pops one task from the **currchain** attribute and puts it into the **currstate** attribute. The **currstate** attribute will be send back to the node as the current task. The **currstate** attribute always shows the current task that is running.

The pop function will continue if another 'get_next_task' request got by xCAT. It will continue until all tasks in the **currchain** attribute are completed (removed) then a 'standby' task will be send back. Then the node will standby for random time and send out 'get_task' again. It will keep in standby state until there is new task assign in ``chain`` for the node.

