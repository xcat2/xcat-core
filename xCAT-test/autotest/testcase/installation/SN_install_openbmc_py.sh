#!/bin/bash
if [ -z $1 ]; then
   echo "ARCH parameter not provided";
   exit 1;
fi
if [ -z $2 ]; then
   echo "OS parameter not provided";
   exit 1;
fi
ARCH=$1;
OS=$2;
PYTHON_DEP_FED_DIR=$3;
PYTHON_DEP_EPEL_DIR=$4;
PYTHON_DEP_EXTRAS_DIR=$5;
echo "Checking if xCAT-openbmc-py installation is needed on $OS $ARCH service node";
if [[ $ARCH =~ "ppc64" ]] && [[ $OS =~ "rhels7" ]]; then
    if rpm -qa|grep xCAT-openbmc-py 2>&1; then 
        echo "Setting up for xCAT-openbmc-py installation on $OS $ARCH service node";
        osimage="$OS-$ARCH-install-service";
        otherpkgdir=$(lsdef -t osimage $osimage -i otherpkgdir -c|awk -F"=" '{print $2}'); 
        otherpkglist=$(lsdef -t osimage $osimage -i otherpkglist -c|awk -F"=" '{print $2}');
        mkdir -p $otherpkgdir/xcat/Packages; 
        cp -r $PYTHON_DEP_FED_DIR/Packages/*.rpm $otherpkgdir/xcat/Packages;
        cp -r $PYTHON_DEP_EPEL_DIR/Packages/* $otherpkgdir/xcat/Packages;
        cp -r $PYTHON_DEP_EXTRAS_DIR/Packages/* $otherpkgdir/xcat/Packages;
        cd $otherpkgdir/xcat/Packages && createrepo .;
        if [ -e /tmp/xCAT-openbmc-py-RH7.noarch.rpm ]; then
            echo "Replacing installed xCAT-openbmc-py RPM with RH7 version";
            rm -f $otherpkgdir/xcat/xcat-core/xCAT-openbmc-py-*;
            cp /tmp/xCAT-openbmc-py-RH7.noarch.rpm $otherpkgdir/xcat/xcat-core/xCAT-openbmc-py-RH7.noarch.rpm;
            cd $otherpkgdir/xcat/xcat-core && createrepo .;
        fi
        echo "xcat/Packages/python2-gevent" >> $otherpkglist;
        echo "xcat/Packages/python2-greenlet" >> $otherpkglist;
        echo "xcat/xcat-core/xCAT-openbmc-py" >> $otherpkglist;
        echo "--Checking otherpkgdir";
        ls -Rl $otherpkgdir/xcat/Packages;
        if ! ls -l $otherpkgdir/xcat/Packages|grep python2-gevent- > /dev/null 2>&1; then 
            echo "There is no python2-gevent package under $otherpkgdir/xcat/Packages";
            exit 1;
        fi;
        if ! ls -l $otherpkgdir/xcat/Packages|grep python2-greenlet- > /dev/null 2>&1; then 
            echo "There is no python2-greenlet under $otherpkgdir/xcat/Packages";
            exit 1;
        fi; 
        echo "--Checking otherpkglist";
        cat $otherpkglist;
        if ! grep python2-gevent  $otherpkglist > /dev/null 2>&1; then 
            echo "There is no python2-gevent entry in $otherpkglist";
            exit 1;
        fi;
        if ! grep python2-greenlet $otherpkglist  > /dev/null 2>&1; then 
            echo "There is no python2-greenlet entry in $otherpkglist";
            exit 1;
        fi;
        exit 0;
    else 
        echo "There is no xCAT-openbmc-py installed on $ARCH $OS MN, skip installing xCAT-openbmc-py on SN";
        exit 0;
    fi
fi
if [[ $ARCH =~ "ppc64" ]] && [[ $OS =~ "rhels8" ]]; then
    if rpm -qa|grep xCAT-openbmc-py 2>&1; then 
        echo "Setting up for xCAT-openbmc-py installation on $OS $ARCH service node";
        osimage="$OS-$ARCH-install-service";
        otherpkgdir=$(lsdef -t osimage $osimage -i otherpkgdir -c|awk -F"=" '{print $2}'); 
        otherpkglist=$(lsdef -t osimage $osimage -i otherpkglist -c|awk -F"=" '{print $2}');
        mkdir -p $otherpkgdir/epel/Packages; 
        wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm --no-check-certificate -O $otherpkgdir/epel/Packages/epel-release-latest-8.noarch.rpm
        if [ -e $otherpkgdir/epel/Packages/epel-release-latest-8.noarch.rpm ]; then
            # Downloaded epel-release-latest-8.noarch.rpm
            # once it is installed on SN, it will setup the repo for
            # required python3 packages
            cd $otherpkgdir/epel/Packages && createrepo .;
            echo "--Checking otherpkgdir";
            ls -Rl $otherpkgdir/epel/Packages;
            # Add separator, so epel-release-latest-8 will be called by yum separately
            echo "#NEW_INSTALL_LIST#" >> $otherpkglist;
            echo "epel/Packages/epel-release-latest-8" >> $otherpkglist;
            # Add separator, so xCAT-openbmc-py will be called by yum separately
            echo "#NEW_INSTALL_LIST#" >> $otherpkglist;
            echo "xcat/xcat-core/xCAT-openbmc-py" >> $otherpkglist;
            echo "--Checking otherpkglist";
            cat $otherpkglist;
        else
            echo "Could not download https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm";
            exit 1;
        fi
    else 
        echo "There is no xCAT-openbmc-py installed on $ARCH $OS MN, skip installing xCAT-openbmc-py on SN";
        exit 0;
    fi
fi
