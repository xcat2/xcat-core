#!/bin/sh
cd `dirname $0`
export BDIR=`pwd`
GREP=grep
export DESTDIR=`pwd`/core-snap
export SRCDIR=`pwd`/core-snap-srpms
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
cd xcat-core
svn up > ../coresvnup
if [ `wc -l ../coresvnup|awk '{print $1}'` != 1 ] && ! grep "^At revision" ../coresvnup; then
	SVNREF=r`svn info|grep Revision|awk '{print $2}'`
	BUILDDATE=`date`
	VERADD=". ' (svn $SVNREF\/built $BUILDDATE)'"
	sed -i s/#XCATSVNBUILDSUBHERE/"$VERADD"/ perl-xCAT/xCAT/Utils.pm
	echo perl-xCAT >> ../coresvnup
fi
if $GREP xCAT-client ../coresvnup; then
   UPLOAD=1
   ./makeclientrpm
   rm -f $DESTDIR/xCAT-client*rpm
   rm -f $SRCDIR/xCAT-client*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-client-2.2*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/xCAT-client-2.2*rpm $SRCDIR/
fi
if $GREP perl-xCAT ../coresvnup; then
   UPLOAD=1
   ./makeperlxcatrpm
   rm -f $DESTDIR/perl-xCAT*rpm
   rm -f $SRCDIR/perl-xCAT*rpm
   mv /usr/src/$pkg/RPMS/noarch/perl-xCAT-2.2*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/perl-xCAT-2.2*rpm $SRCDIR/
fi
svn revert perl-xCAT/xCAT/Utils.pm
if $GREP xCAT-web ../coresvnup; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-web*
   rm -f $SRCDIR/xCAT-web*
   ./makewebrpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-web-2.2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-web-2.2*rpm $SRCDIR
fi
if $GREP xCAT-server ../coresvnup; then
   UPLOAD=1
   ./makeserverrpm
   rm -f $DESTDIR/xCAT-server*rpm
   rm -f $SRCDIR/xCAT-server*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-server-2.2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-server-2.2*rpm $SRCDIR
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
   rm -f $DESTDIR/xCATsn-2.2*rpm
   rm -f $SRCDIR/xCATsn-2.2*rpm
   ./mkrpm x86_64
   mv /usr/src/$pkg/RPMS/*/xCATsn-2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-2*rpm $SRCDIR
   ./mkrpm i386
   mv /usr/src/$pkg/RPMS/*/xCATsn-2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-2*rpm $SRCDIR
   ./mkrpm ppc64
   mv /usr/src/$pkg/RPMS/*/xCATsn-2*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-2*rpm $SRCDIR
   cd ..
fi
if $GREP "U    xCAT/" ../coresvnup || $GREP "A    xCAT/" ../coresvnup; then
   UPLOAD=1
   cd xCAT
   rm -f $DESTDIR/xCAT-2.2*rpm
   rm -f $SRCDIR/xCAT-2.2*rpm
   ./mkrpm x86_64
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
$BDIR/sign.exp $DESTDIR/*rpm
$BDIR/sign.exp $SRCDIR/*rpm
createrepo $DESTDIR
createrepo $SRCDIR
rm $SRCDIR/repodata/repomd.xml.asc
rm $DESTDIR/repodata/repomd.xml.asc
gpg -a --detach-sign $DESTDIR/repodata/repomd.xml
gpg -a --detach-sign $SRCDIR/repodata/repomd.xml
cd $DESTDIR/..
export CFNAME=core-rpms-snap.tar.bz2
export DFNAME=dep-rpms-snap.tar.bz2
#tar jcvf $DFNAME dep-snap
tar jcvf $CFNAME core-snap
scp $CFNAME jbjohnso@web.sourceforge.net:/home/groups/x/xc/xcat/htdocs/yum/devel/
rsync -av --delete core-snap jbjohnso@web.sourceforge.net:/home/groups/x/xc/xcat/htdocs/yum/devel/
#ssh jbjohnso@shell2.sourceforge.net "cd /home/groups/x/xc/xcat/htdocs/yum/devel; tar jcvf $CFNAME core-snap"
