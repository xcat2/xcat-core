
#######
wcons.1
#######

.. highlight:: perl


****
Name
****


wcons - windowed remote console


****************
\ **Synopsis**\ 
****************


\ **wcons**\   [\ **-t | -**\ **-tile**\ =\ *n*\ ] [\ *xterm-options*\ ] \ *noderange*\ 

\ **wcons**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **wcons**\  provides access to the remote node serial console of a single  or
range or nodes or groups.

\ **wcons**\   is a simple front-end to rcons in an xterm session for each console.


***************
\ **Options**\ 
***************



\ **-t | -**\ **-tile**\ =\ *n*\ 
 
 Tile \ **wcons**\  windows from top left to bottom right.  If \ *n*\  is spec-
 ified  then  tile  \ *n*\  across.  If \ *n*\  is not specified then tile to
 edge of screen.  If tiled \ **wcons**\  windows reach bottom right, then
 the windows start at top left overlaying existing \ **wcons**\  windows.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 


\ *xterm options*\ 
 
 See xterm(1). Any options other than those listed above are passed
 directly to xterm. \ **Note:**\  when given multiple nodes, wcons will
 override \ **-title**\  and tries to figure out optimal \ **-geometry**\ 
 options for the xterms (however, \ **-geometry**\  can still be
 specified).
 



*************
\ **Files**\ 
*************


\ **nodehm**\  table -
xCAT  node hardware management table.  See nodehm(5)|nodehm.5 for further details.  This is used  to  determine  the  console  access
method.


****************
\ **Examples**\ 
****************


\ **wcons**\  \ *node1-node5*\ 

\ **wcons**\  \ **-**\ **-tile**\  \ **-**\ **-font**\ =\ *nil2*\  \ *all*\ 

\ **wcons**\  \ **-t**\  \ *4*\  \ *node1-node16*\ 

\ **wcons**\  \ **-f**\  \ *vs*\  \ **-t**\  \ *4*\  \ *node1-node4*\ 


************
\ **Bugs**\ 
************


Tile mode assumes that the width of the left window border is also  the
width  of  the  right  and  bottom window border.  Most window managers
should not have a problem.  If you really need  support  for  a  screwy
window manager let me know.


************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, rcons(1)|rcons.1, xterm(1)

