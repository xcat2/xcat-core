Installing other packages with Ubuntu official mirror
=====================================================

The Ubuntu iso is being used to install the compute nodes only include packages to run a base operating system, it is likely that users will need to install additional Ubuntu packages from the internet Ubuntu repo or local repo, this section describes how to install additional Ubuntu packages.

A1: Compute nodes can access the internet
-----------------------------------------

step1: Specify the repository

Use the internet repository directly when define the otherpkgdir attribute: ::

    chdef -t osimage <osimage name> otherpkgdir="http://us.archive.ubuntu.com/ubuntu/ $(lsb_release -sc) main,http://us.archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-update main"

step2: Specify otherpkglist file

create an otherpkglist file,**/install/custom/install/ubuntu/compute.otherpkgs.pkglist**. Add the packages' name into thist file. And modify the otherpkglist attribute for osimage object. ::

    chdef -t osimage <osimage name> otherpkglist=/install/custom/install/ubuntu/compute.otherpkgs.pkglist

step3: Run ``updatenode <nodename> -S`` or ``updatenode <nodename> -P otherpkgs`` 

Run ``updatenode -S`` to **install/update** the packages on the compute nodes ::

    updatenode <nodename> -S

Run ``updatenode`` otherpkgs to **install/update** the packages on the compute nodes ::

    updatenode <nodename> -P otherpkgs

A2: Compute nodes can not access the internet
----------------------------------------------

If compute nodes cannot access the internet, there are two ways to install additional packages:use apt proxy or use local mirror;

optional 1: Use apt proxy
~~~~~~~~~~~~~~~~~~~~~~~~~

Step 1: Install **Squid** on the server which can access the internet (Here uses management node as the proxy server)::

    apt-get install squid

Step 2: Edit the **Squid** configuration file **/etc/squid3/squid.conf**, find the line **"#http_access deny to_localhost"**. Add the following 2 lines behind this line.::

    acl cn_apt src <compute node sub network>/<net mask length>
    http_access allow cn_apt

For more refer Squid configuring.

Step 3: Restart the proxy service ::

    service squid3 restart

Step 4: Create a postscript under **/install/postscripts/** directory, called aptproxy, add following lines ::

    #!/bin/sh
    PROXYSERVER=$1
    if [ -z $PROXYSERVER ];then
        PROXYSERVER=$MASTER
    fi

    PROXYPORT=$2
    if [ -z $PROXYPORT ];then
        PROXYPORT=3128
    fi

    if [ -e "/etc/apt/apt.conf" ];then
        sed '/^Acquire::http::Proxy/d' /etc/apt/apt.conf &gt; /etc/apt/apt.conf.new
        mv -f /etc/apt/apt.conf.new /etc/apt/apt.conf
    fi
    echo "Acquire::http::Proxy \"http://${PROXYSERVER}:$PROXYPORT\";" &gt;&gt; /etc/apt/apt.conf

Step 5: add this postscript to compute nodes, the **[proxy server ip]** and **[proxy server port]** are optional parameters for this postscript. If they are not specified, xCAT will use the management node ip and 3128 by default. ::

    chdef <node range> -p postscripts="aptproxy [proxy server ip] [proxy server port]"

Step 6: Edit the otherpkglist file, add the require software packages' name. 

Step 7: Edit the otherpkgdir attribute for os image object, can use the internet repositories directly.

Step 8: Run ``nodeset``, ``rsetboot``, rpower commands to provision the compute nodes.

Optional 2: Use local mirror
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Find a server witch can connect the internet, and can be accessed by the compute nodes.

step 1: Install apt-mirror ::

    apt-get install apt-mirror

step 2: Configure apt-mirror ::

    vim /etc/apt/mirror.list

step 3: Run apt-mirror to download the repositories(The needed space can be found in Ubuntu Mirrors )::

    apt-mirror /etc/apt/mirror.list

step 4: Install apache ::

    apt-get install apache2

step 5: Setup links to link our local repository folder to our shared apache directory ::

    ln -s /var/spool/apt-mirror/mirror/archive.ubuntu.com /var/www/archive-ubuntu

When setting the otherpkgdir attribute for the osimages, can use **http://<local mirror server ip>/archive-ubuntu/ $(lsb_release -sc) main**

For more information about setting local repository mirror can refer How to Setup Local Repository Mirror
