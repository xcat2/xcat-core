.. _create_image_for_runimage:

How to prepare a image for ``runimage`` in ``chain``
====================================================

* The things needed
    * The pkgs, scripts or other files that you needed
    * The runme.sh script that you create to operate the needed files

* The steps to generate the image
    * create a directory under /install or any other directory that can be accessed with http.
    * modify the permission for runme.sh to make sure it is able to be executed
    * copy or move the needed files and runme.sh to the created directory
    * go to the directory and run `tar -zcvf <image> .`

* Example
    In the example, it shows how to install an independent pkg a.rpm 

    * Create the directory for the image: ::

        mkdir -p /install/my_image

    * Go to the direcotry and copy the rpm file into it: ::

        cd /install/my_image
        cp /tmp/a.rpm /install/my_image

    * Write the runme.sh script and modify the permission: ::

         cat runme.sh
         echo "start installing a.rpm"
         rpm -ivh a.rpm  

    * modify the runme.sh script permission: ::

         chmod +x runme.sh

    * Create the tar ball for the directory: ::

         tar -zcvf my_image.tgz .


