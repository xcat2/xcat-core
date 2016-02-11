
#############
switchblade.1
#############

.. highlight:: perl


********
SYNOPSIS
********


\ **switchblade**\  \ *MM*\  {\ **list**\  | \ **stat**\ }

\ **switchblade**\  \ *node*\  {\ **media**\  | \ **mt**\  | \ **kvm**\  | \ **video**\  | \ **both**\ } [\ *slot_num*\ ]

\ **switchblade**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


\ **switchblade**\  assigns the BladeCenter media tray and/or KVM to the specified blade, so that they can be
used with that blade.  If \ **list**\  or \ **stat**\  are specified instead, \ **switchblade**\  will display the current
assignment.  You can either specify a management module or a node (blade) to \ **switchblade**\ .  If the latter,
\ **switchblade**\  will determine the management module of the node.


*******
OPTIONS
*******



\ **list | stat**\ 
 
 Display which blade the media tray and KVM are currently assigned to.
 


\ **media | mt**\ 
 
 Assign the media tray to the specified blade.
 


\ **kvm | video**\ 
 
 Assign the KVM (video display) to the specified blade.
 


\ **both**\ 
 
 Assign both the media tray and the KVM to the specified blade.
 


\ *slot_num*\ 
 
 The slot # of the blade that the resources should be assigned to.  If not specified, it will use the slot
 # of the node specified.
 



********
EXAMPLES
********



1.
 
 Switch the media tray to be assigned to the blade in slot 4 (assume it is node4):
 
 
 .. code-block:: perl
 
   switchblade node4 media
 
 
 Output will be like:
 
 
 .. code-block:: perl
 
   Media Tray slot: 4
 
 



********
SEE ALSO
********


rbootseq(1)|rbootseq.1

