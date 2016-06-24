Install xCAT
------------

The xCAT GPG Public Key must be added for apt to verify the xCAT packages ::

        wget -O - "http://xcat.org/files/xcat/repos/apt/apt.key" | apt-key add -

Add the necessary apt-repositories to the management node ::

        # Install the add-apt-repository command
        apt-get install software-properties-common

        # For x86_64:
        add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main"
        add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main"
        add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"
        add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates universe"

        # For ppc64el:
        add-apt-repository "deb http://ports.ubuntu.com/ubuntu-ports $(lsb_release -sc) main"
        add-apt-repository "deb http://ports.ubuntu.com/ubuntu-ports $(lsb_release -sc)-updates main"
        add-apt-repository "deb http://ports.ubuntu.com/ubuntu-ports $(lsb_release -sc) universe"
        add-apt-repository "deb http://ports.ubuntu.com/ubuntu-ports $(lsb_release -sc)-updates universe"

Install xCAT [#]_ with the following command: ::

        apt-get clean all
        apt-get update
        apt-get install xcat

.. [#] Starting with Ubuntu 16.04, the package name 'xCAT' is required to be all lowercase


