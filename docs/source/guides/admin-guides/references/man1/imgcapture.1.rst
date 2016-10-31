
############
imgcapture.1
############

.. highlight:: perl


****
NAME
****


\ **imgcapture**\  - Captures an image from a Linux diskful node and create a diskless or diskful image on the management node.


********
SYNOPSIS
********


\ **imgcapture**\  \ *node*\  \ **-t | -**\ **-type**\  {\ **diskless | sysclone**\ } \ **-o | -**\ **-osimage**\  \ *osimage*\  [\ **-V | -**\ **-verbose**\ ]

\ **imgcapture**\  [\ **-h**\  | \ **-**\ **-help**\ ] | [\ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **imgcapture**\  command will capture an image from one running diskful Linux node and create a diskless or diskful image for later use.

The \ **node**\  should be one diskful Linux node, managed by the xCAT MN, and the remote shell between MN and the \ **node**\  should have been configured. AIX is not supported.

The \ **imgcapture**\  command supports two image types: \ **diskless**\  and \ **sysclone**\ . For the \ **diskless**\  type, it will capture an image from one running diskful Linux node, prepares the rootimg directory, kernel and initial rmadisks for the \ **liteimg**\ /\ **packimage**\  command to generate the statelite/stateless rootimg. For the \ **sysclone**\  type, it will capture an image from one running diskful Linux node, create an osimage which can be used to clone other diskful Linux nodes.

The \ **diskless**\  type:

The attributes of osimage will be used to capture and prepare the root image. The \ **osver**\ , \ **arch**\  and \ **profile**\  attributes for the stateless/statelite image to be created are duplicated from the \ **node**\ 's attribute. If the \ **-p|-**\ **-profile**\  \ *profile*\  option is specified, the image will be created under "/<\ *installroot*\ >/netboot/<osver>/<arch>/<\ *profile*\ >/rootimg".

The default files/directories excluded in the image are specified by /opt/xcat/share/xcat/netboot/<os>/<\ *profile*\ >.<osver>.<arch>.imgcapture.exlist; also, you can put your customized file (<\ *profile*\ >.<osver>.<arch>.imgcapture.exlist) to /install/custom/netboot/<osplatform>. The directories in the default \ *.imgcapture.exlist*\  file are necessary to capture the image from the diskful Linux node managed by xCAT, don't remove it.

The image captured will be extracted into the /<\ *installroot*\ >/netboot/<\ **osver**\ >/<\ **arch**\ >/<\ **profile**\ >/rootimg directory.

After the \ **imgcapture**\  command returns without any errors, you can customize the rootimg and run the \ **liteimg**\ /\ **packimage**\  command with the options you want.

The \ **sysclone**\  type:

xCAT leverages the Open Source Tool - Systemimager to capture the osimage from the \ **node**\ , and put it into /<\ *installroot*\ >/\ **sysclone**\ /\ **images**\  directory.

The \ **imgcapture**\  command will create the \ *osimage*\  definition after the image is captured successfully, you can use this osimage and \ **nodeset**\  command to clone diskful nodes.


*******
OPTIONS
*******



\ **-t | -**\ **-type**\ 
 
 Specify the osimage type you want to capture, two types are supported: diskless and sysclone.
 


\ **-p|-**\ **-profile**\  \ *profile*\ 
 
 Assign \ *profile*\  as the profile of the image to be created.
 


\ **-o|-**\ **-osimage**\  \ *osimage*\ 
 
 The osimage name.
 


\ **-i**\  \ *nodebootif*\ 
 
 The network interface the diskless node will boot over (e.g. eth0), which is used by the \ **genimage**\  command to generate initial ramdisks.
 
 This is optional.
 


\ **-n**\  \ *nodenetdrivers*\ 
 
 The driver modules needed for the network interface, which is used by the \ **genimage**\  command to generate initial ramdisks.
 
 This is optional. By default, the \ **genimage**\  command can provide drivers for the following network interfaces:
 
 For x86 or x86_64 platform:
 
 
 .. code-block:: perl
 
      tg3 bnx2 bnx2x e1000 e1000e igb m1x_en
 
 
 For ppc64 platform:
 
 
 .. code-block:: perl
 
      e1000 e1000e igb ibmveth ehea
 
 
 For S390x:
 
 
 .. code-block:: perl
 
      qdio ccwgroup
 
 
 If the network interface is not in the above list, you'd better specify the driver modules with this option.
 


\ **-h|-**\ **-help**\ 
 
 Display the usage message.
 


\ **-v|-**\ **-version**\ 
 
 Display the version.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 



************
RETRUN VALUE
************


0 The command completed sucessfully.

1 An error has occurred.


********
EXAMPLES
********


\ **node1**\  is one diskful Linux node, which is managed by xCAT.

1. There's one pre-defined \ *osimage*\ . In order to capture and prepare the diskless root image for \ *osimage*\ , run the command:


.. code-block:: perl

  imgcapture node1 -t diskless -o osimage


2. In order to capture the diskful image from \ **node1**\  and create the \ *osimage*\  \ **img1**\ , run the command:


.. code-block:: perl

  imgcapture node1 -t sysclone -o img1



*****
FILES
*****


/opt/xcat/bin/imgcapture


********
SEE ALSO
********


genimage(1)|genimage.1, imgimport(1)|imgimport.1, imgexport(1)|imgexport.1, packimage(1)|packimage.1, liteimg(1)|liteimg.1, nodeset(8)|nodeset.8

