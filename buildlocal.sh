#######################################################################
#build script for local usage
#used for Linux/AIX/Ubuntu
#
###########################################################################


OSNAME=$(uname)
NAMEALL=$(uname -a)

for i in $*; do
        # upper case the variable name
        varstring=`echo "$i"|cut -d '=' -f 1|tr '[a-z]' '[A-Z]'`=`echo "$i"|cut -d '=' -f 2`
        export $varstring
done

if [ -z "$CURDIR" ]; then
   echo "get current directory!"
   CURDIR=$(pwd)
fi

echo "CURDIR is $CURDIR"
echo "OSNAME is $OSNAME!"
echo "NAMEALL is $NAMEALL"

ls $CURDIR/makerpm

if [ $? -gt 0 ]; then
                echo "Error:no repo exist, exit 1."
                exit 1 
fi

# Get a lock, so can not do 2 builds at once
exec 8>/var/lock/xcatbld.lock
if ! flock -n 8; then
    echo "Can't get lock /var/lock/xcatbld.lock.  Someone else must be doing a build right now.  Exiting...."
    exit 1
fi

#delete old package if there is
rm -rf $CURDIR/build/
cd $CURDIR

echo "==============================================="
echo $NAMEALL |  egrep "Ubuntu"

#Check if it is an Ubuntu system
if [ $? -eq 0 ]; then

echo "This is an Ubuntu system"
     pkg_type="snap"
     build_string="Snap_Build"
     cur_date=`date +%Y%m%d`
     short_ver=`cat Version|cut -d. -f 1,2`
     pkg_version="${short_ver}-${pkg_type}${cur_date}"

     mkdir -p $CURDIR/build

 for rpmname in xCAT-client xCAT-genesis-scripts perl-xCAT xCAT-server xCAT xCATsn xCAT-test; do
     rpmname_low=`echo $rpmname | tr '[A-Z]' '[a-z]'`
     echo "============================================"
     echo "$rpmname_low"
     cd $rpmname
     dch -v $pkg_version -b -c debian/changelog $build_string
     dpkg-buildpackage -uc -us
     rc=$?
     if [ $rc -gt 0 ]; then
                  echo "Error: $rpmname build package failed exit code $rc"
     fi
     cd -
     mv ${rpmname_low}* $CURDIR/build
 
 done 
     #delete all files except  .deb file
     find $CURDIR/build/* ! -name *.deb | xargs rm -f

else
#This is not an Ubuntu system
echo "This is an $OSNAME system"

     rm -rf /root/rpmbuild/RPMS/noarch/*
     rm -rf /root/rpmbuild/RPMS/x86_64/*
     rm -rf /root/rpmbuild/RPMS/ppc64/*
     mkdir -p $CURDIR/build/
  
   #always build perl-xCAT
   $CURDIR/makerpm  perl-xCAT  
 

   # Build the rest of the noarch rpms
   for rpmname in xCAT-client xCAT-server xCAT-IBMhpc xCAT-rmc xCAT-test xCAT-buildkit; do
        if [ "$OSNAME" = "AIX" -a "$rpmname" = "xCAT-buildkit" ]; then continue; fi     
        $CURDIR/makerpm $rpmname
   done
  
  #build xCAT-genesis-scripts if it is x86_64 platform
  ARCH=$(uname -p)
  if [ "$ARCH" = "x64_64" ]; then 
       $CURDIR/makerpm xCAT-genesis-scripts x86_64  
  fi

  
  # Build the xCAT and xCATsn rpms for all platforms
  for rpmname in xCAT xCATsn; do
                if [ "$OSNAME" = "AIX" ]; then
                        $CURDIR/makerpm $rpmname
                        if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS $rpmname"; fi 
                else
                        for arch in x86_64 ppc64 s390x; do
                                $CURDIR/makerpm $rpmname $arch
                                if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS $rpmname-$arch"; fi
                        done
                fi
  done

  cp /root/rpmbuild/RPMS/noarch/* $CURDIR/build/
  cp  /root/rpmbuild/RPMS/x86_64/* $CURDIR/build/
  cp /root/rpmbuild/RPMS/ppc64/* $CURDIR/build/

  #begin to create repo for redhat platform

  if [ "$OSNAME" != "AIX" ]; then  
        cat >$CURDIR/build/xCAT-core.repo << EOF
[xcat-2-core]
name=xCAT 2 Core packages
baseurl=file://$CURDIR/build
enabled=1
gpgcheck=0
EOF

  cp $CURDIR/build/xCAT-core.repo /etc/yum.repos.d/

  fi
   
fi


