#!/bin/sh
cd `dirname $0`
VER=`cat Version`
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

# This update of Utils.pm is now done in the perl-xCAT spec file
#if [ `wc -l ../coresvnup|awk '{print $1}'` != 1 ] && ! grep "^At revision" ../coresvnup; then
#	SVNREF=r`svn info|grep Revision|awk '{print $2}'`
#	BUILDDATE=`date`
#	VERADD=". ' (svn $SVNREF\/built $BUILDDATE)'"
#	sed -i s/#XCATSVNBUILDSUBHERE/"$VERADD"/ perl-xCAT/xCAT/Utils.pm
#	echo perl-xCAT >> ../coresvnup
#fi

if $GREP xCAT-client ../coresvnup; then
   UPLOAD=1
   ./makeclientrpm
   rm -f $DESTDIR/xCAT-client*rpm
   rm -f $SRCDIR/xCAT-client*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-client-$VER*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/xCAT-client-$VER*rpm $SRCDIR/
fi
if $GREP perl-xCAT ../coresvnup; then
   UPLOAD=1
   ./makeperlxcatrpm
   rm -f $DESTDIR/perl-xCAT*rpm
   rm -f $SRCDIR/perl-xCAT*rpm
   mv /usr/src/$pkg/RPMS/noarch/perl-xCAT-$VER*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/perl-xCAT-$VER*rpm $SRCDIR/
fi
#svn revert perl-xCAT/xCAT/Utils.pm
if $GREP xCAT-web ../coresvnup; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-web*
   rm -f $SRCDIR/xCAT-web*
   ./makewebrpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-web-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-web-$VER*rpm $SRCDIR
fi
if $GREP xCAT-server ../coresvnup; then
   UPLOAD=1
   ./makeserverrpm
   rm -f $DESTDIR/xCAT-server*rpm
   rm -f $SRCDIR/xCAT-server*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-server-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-server-$VER*rpm $SRCDIR
fi
if $GREP xCAT-nbroot ../coresvnup; then
   UPLOAD=1
   ./makenbrootrpm x86_64
   ./makenbrootrpm ppc64
   ./makenbrootrpm x86
   rm -f $DESTDIR/xCAT-nbroot-core*rpm
   rm -f $SRCDIR/xCAT-nbroot-core*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-nbroot-core-*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-nbroot-core-*rpm $SRCDIR
fi
if $GREP "U    xCATsn/" ../coresvnup || $GREP "A    xCATsn/" ../coresvnup; then
   UPLOAD=1
   rm -f $DESTDIR/xCATsn-$VER*rpm
   rm -f $SRCDIR/xCATsn-$VER*rpm
   ./makexcatsnrpm x86_64
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-$VER*rpm $SRCDIR
   ./makexcatsnrpm i386
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-$VER*rpm $SRCDIR
   ./makexcatsnrpm ppc64
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-$VER*rpm $SRCDIR
fi
if $GREP "U    xCAT/" ../coresvnup || $GREP "A    xCAT/" ../coresvnup; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-$VER*rpm
   rm -f $SRCDIR/xCAT-$VER*rpm
   ./makexcatrpm x86_64
   mv /usr/src/$pkg/RPMS/*/xCAT-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-$VER*rpm $SRCDIR
   ./makexcatrpm ppc64
   mv /usr/src/$pkg/RPMS/*/xCAT-$VER*rpm $DESTDIR
   ./makexcatrpm i386
   mv /usr/src/$pkg/RPMS/*/xCAT-$VER*rpm $DESTDIR
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
