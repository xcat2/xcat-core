#!/bin/sh
cd `dirname $0`
GREP=grep
export DESTDIR=`pwd`/core-snap-20
export SRCDIR=`pwd`/core-snap-srpms-20
UPLOAD=0
if [ "$1" == "UPLOAD" ]; then
   UPLOAD=1 
fi
if [ -f /etc/redhat-release ]
then
  pkg="redhat"
else
  pkg="packages"
fi

#rm -rf $DESTDIR
#rm -rf $SRCDIR
mkdir -p $DESTDIR
mkdir -p $SRCDIR
cd 2.0/xcat-core
svn up > ../coresvnup
if $GREP xCAT-client ../coresvnup; then
   UPLOAD=1
   ./makeclientrpm
   rm -f $DESTDIR/xCAT-client*rpm
   rm -f $SRCDIR/xCAT-client*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-client-2.0*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/xCAT-client-2.0*rpm $SRCDIR/
fi
if $GREP perl-xCAT ../coresvnup; then
   UPLOAD=1
   ./makeperlxcatrpm
   rm -f $DESTDIR/perl-xCAT*rpm
   rm -f $SRCDIR/perl-xCAT*rpm
   mv /usr/src/$pkg/RPMS/noarch/perl-xCAT-2.0*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/perl-xCAT-2.0*rpm $SRCDIR/
fi
if $GREP xCAT-server ../coresvnup; then
   UPLOAD=1
   ./makeserverrpm
   rm -f $DESTDIR/xCAT-server*rpm
   rm -f $SRCDIR/xCAT-server*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-server-2.0*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-server-2.0*rpm $SRCDIR
fi
if $GREP xCAT-nbroot ../coresvnup; then
   UPLOAD=1
   cd xCAT-nbroot
   ./mkrpm x86_64
   ./mkrpm ppc64
   ./mkrpm x86
   rm -f $DESTDIR/xCAT-nbroot-core*rpm
   rm -f $SRCDIR/xCAT-nbroot-core*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-nbroot-core-*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-nbroot-core-*rpm $SRCDIR
   cd ..
fi
if $GREP "U    xCATsn/" ../coresvnup || $GREP "A    xCATsn/" ../coresvnup; then
   UPLOAD=1
   cd xCATsn
   ./mkrpm
   rm -f $DESTDIR/xCATsn-2.0*rpm
   rm -f $SRCDIR/xCATsn-2.0*rpm
   mv /usr/src/$pkg/RPMS/*/xCATsn-2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-2*rpm $SRCDIR
   cd ..
fi
if $GREP "U    xCAT/" ../coresvnup || $GREP "A    xCAT/" ../coresvnup; then
   UPLOAD=1
   cd xCAT
   rm -f $DESTDIR/xCAT-2.0*rpm
   rm -f $SRCDIR/xCAT-2.0*rpm
   ./mkrpm
   mv /usr/src/$pkg/RPMS/*/xCAT-2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-2*rpm $SRCDIR
   ./mkrpm ppc64
   mv /usr/src/$pkg/RPMS/*/xCAT-2*rpm $DESTDIR
   ./mkrpm i386
   mv /usr/src/$pkg/RPMS/*/xCAT-2*rpm $DESTDIR
   cd ..
fi
if [ $UPLOAD == 0 ]; then
 echo "Nothing new detected"
 exit 0;
fi
createrepo $DESTDIR
createrepo $SRCDIR
cd $DESTDIR/..
export CFNAME=core-rpms-snap.tar.bz2
export DFNAME=dep-rpms-snap.tar.bz2
#tar jcvf $DFNAME dep-snap
#scp $CFNAME jbjohnso@shell1.sf.net:/home/groups/x/xc/xcat/htdocs/yum/
echo rsync -av --delete core-snap jbjohnso@shell1.sf.net:/home/groups/x/xc/xcat/htdocs/yum/
echo ssh jbjohnso@shell1.sf.net "cd /home/groups/x/xc/xcat/htdocs/yum; tar jcvf $CFNAME core-snap"
#ssh jbjohnso@shell1.sf.net "cd /home/groups/x/xc/xcat/htdocs/yum/; rm -rf core-snap; tar jxvf $CFNAME"
