Removing Kit
------------

Removing Kit Components from an OS Image Definition
````````````````````````````````````````````````````
To remove a kit component from an OS image definition, first list the existing kitcomponents to get the name to remove: ::

  lsdef -t osimage -o <image> -i kitcomponents

Then, use that name to remove it from the image definition: ::

  rmkitcomp -i <image> <kitcomponent name>

Or, if know the basename of the kitcomponent, simply: ::

  rmkitcomp -i <image> <kitcompent basename>

Note that this ONLY removes the kitcomponent from the image definition in the xCAT database, and it will NOT remove any product packages from the actual OS image. To set up for an uninstall of the kitcomponent from the diskless image or the stateful node, specify the uninstall option: ::

  rmkitcomp -u -i <image> <kitcomponent>

The next time when run genimage for the diskless image, or updatenode to the fulldisk nodes, the software product will be un-installed.

Removing a Kit from the xCAT Management Node
````````````````````````````````````````````

To remove a kit from xCAT, first make sure that no OS images are assigned any of the kitcomponents. To do this, run the following database queries: ::

  lsdef -t kitcomponent -w 'kitname==<kitname>'

For each kitcomponent returned: ::

  lsdef -t osimage -i kitcomponents -c | grep <kitcomponent>

If no osimages have been assigned any of the kitcomponents from this kit, can safely remove the kit by running: ::

  rmkit <kitname>

