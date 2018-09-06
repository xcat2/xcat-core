
#######
wkill.1
#######

.. highlight:: perl


****
Name
****


\ **wkill**\  - kill windowed remote consoles


****************
\ **Synopsis**\ 
****************


\ **wkill**\  [\ *noderange*\ ]

\ **wkill**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **wkill**\   will  kill  the  wcons  windows on your $DISPLAY for a single or
range or nodes or groups.

\ **wkill**\  was written because I'm too lazy to point and click off  64  windows.

\ **wkill**\   will  only  kill  windows  on  your  display  and  for  only the
noderange(3)|noderange.3 you specify.  If no noderange(3)|noderange.3 is  specified,  then  all
wcons windows on your $DISPLAY will be killed.


***************
\ **Options**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



****************
\ **Examples**\ 
****************



.. code-block:: perl

  wkill node1-node5



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, wcons(1)|wcons.1

