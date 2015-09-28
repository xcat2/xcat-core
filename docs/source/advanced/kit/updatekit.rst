Completing the software update
------------------------------

updating diskless images
`````````````````````````

For diskless OS images, run the genimage command to update the image with the new software. Example: ::

  genimage <osimage>

Once the osimage has been updated you may follow the normal xCAT procedures for packing and deploying the image to your diskless nodes.

installing diskful nodes
````````````````````````

For new stateful deployments, the kitcomponent will be installed during the otherpkgs processing. Follow the xCAT procedures for your hardware type. Generally, it will be something like: ::

  chdef <nodelist> provmethod=<osimage>
  nodeset <nodelist> osimage
  rpower <nodelist> reset

updating diskful nodes
``````````````````````

For existing active nodes, use the updatenode command to update the OS on those nodes. The updatenode command will use the osimage assigned to the node to determine the software to be updated. Once the osimage has been updated, make sure the correct image is assigned to the node and then run updatenode: ::

  chdef <nodelist> provmethod=<osimage>      
  updatenode <nodelist>

