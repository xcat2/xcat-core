
##########
rmdocker.1
##########

.. highlight:: perl


********
SYNOPSIS
********


\ **rmdocker**\  \ *noderange*\  [\ **-f | -**\ **-force**\ ]

\ **rmdocker**\  [\ **-h | -**\ **-help**\ ]

\ **rmdocker**\  {\ **-v | -**\ **-version**\ }


***********
DESCRIPTION
***********


\ **rmdocker**\  To remove docker instances with the specified node name


*******
OPTIONS
*******



\ **-f|-**\ **-force**\ 



Force to removal of a running container or failed to disconnect customized network


********
EXAMPLES
********



.. code-block:: perl

     rmdocker host01c01
     host01c01: Disconnect customzied network 'mynet0' done
     host01c01: success



********
SEE ALSO
********


mkdocker(1)|mkdocker.1, lsdocker(1)|lsdocker.1

