
##########
mkdocker.1
##########

.. highlight:: perl


****
NAME
****


\ **mkdocker**\  - Create docker instance.


********
SYNOPSIS
********


\ **mkdocker**\  \ *noderange*\  [\ **image**\ =\ *image_name*\  [\ **command**\ =\ *command*\ ]] [\ **dockerflag**\ =\ *flags_to_create_instance*\ ]

\ **mkdocker**\  [\ **-h | -**\ **-help**\ ]

\ **mkdocker**\  {\ **-v | -**\ **-version**\ }


***********
DESCRIPTION
***********


\ **mkdocker**\  To create docker instances with the specified image, command and/or dockerflags.


*******
OPTIONS
*******



\ **image**\ 
 
 The docker image name that the instance will use.
 


\ **command**\ 
 
 The command that the instance will run based on the \ **image**\  specified. The \ **image**\  option must be specified in order to use this option.
 


\ **dockerflag**\ 
 
 A JSON string which will be used as parameters to create a docker. Reference https://docs.docker.com/engine/reference/api/docker_remote_api_v1.22/ for more information about which parameters can be specified.
 
 Some useful flags are:
 
 
 \ **AttachStdin**\ =\ **true | false**\ 
  
  Whether attaches to stdin.
  
 
 
 \ **AttachStdout**\ =\ **true | false**\ 
  
  Whether attaches to stdout.
  
 
 
 \ **AttachStderr**\ =\ **true | false**\ 
  
  Whether attaches to stderr.
  
 
 
 \ **OpenStdin**\ =\ **true | false**\ 
  
  Whether opens stdin.
  
 
 
 \ **Tty**\ =\ **true | false**\ 
  
  Attach standard streams to a tty, including stdin if it is not closed.
  
 
 
 \ **ExposedPorts**\ 
  
  An object mapping ports to an empty object in the form of:
  
  
  .. code-block:: perl
  
    "ExposedPorts": { "<port>/\<tcp|udp>: {}" }
  
  
 
 
 \ **HostConfig: {"Binds"}**\ 
  
  A list of volume bindings for this docker instance, the form will be:
  
  
  .. code-block:: perl
  
    "HostConfig": {"Binds":["<dir_on_dockerhost>:<dir_in_instance>"]}
  
  
 
 



********
EXAMPLES
********


1. To create a basic docker instance with stdin opened


.. code-block:: perl

     mkdocker host01c01 image=ubuntu command=/bin/bash dockerflag="{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"OpenStdin\":true}"


Output is similar to:


.. code-block:: perl

     host01c01: Pull image ubuntu start
     host01c01: Pull image ubuntu done
     host01c01: Remove default network connection
     host01c01: Connecting customzied network 'mynet0'
     host01c01: success


2. To create a docker instance which have dir "destdir" in docker instance bind from "srcdir" on dockerhost, and have "Tty" opened with which the docker instance can be attached after started to check the files under "destdir".


.. code-block:: perl

     mkdocker host01c01 image=ubuntu command=/bin/bash dockerflag="{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"OpenStdin\":true,\"Tty\":true,\"HostConfig\":{\"Binds\":[\"/srcdir:/destdir\"]}}"


Output is similar to:


.. code-block:: perl

     host01c01: Remove default network connection
     host01c01: Connecting customzied network 'mynet0'
     host01c01: success



********
SEE ALSO
********


rmdocker(1)|rmdocker.1, lsdocker(1)|lsdocker.1

