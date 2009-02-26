#!/bin/sh

# Build and upload the xcat-core code.  Run this script from a dir in which you want
# 2 subdirs created:  core-snap and core-snap-srpms.

# Usage:  buildcore.sh [<branch>] [release]
#		<branch> - e.g. 2.1.  If not specified, the trunk/new devel branch is assumed
#		release - if the keyword "release" is specified, means an official dot release.
#					Otherwise, and snap build is assumed.
# You can override the default upload behavior by specifying env var: UP=0 or UP=1

# you can change this if you need to
UPLOADUSER=bp-sawyers

export HOME=/root
if [ -n "$1" ]; then
	export DESTDIR=`pwd`/$1/core-snap
	export SRCDIR=`pwd`/$1/core-snap-srpms
else
	export DESTDIR=`pwd`/core-snap
	export SRCDIR=`pwd`/core-snap-srpms
fi

cd `dirname $0`
VER=`cat Version`
GREP=grep
UPLOAD=0
if [ -f /etc/redhat-release ]
then
  pkg="redhat"
else
  pkg="packages"
fi

mkdir -p $DESTDIR
mkdir -p $SRCDIR
#cd xcat-core
svn up > ../coresvnup

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

# Decide whether to upload or not
if [ -n "$UP" ]; then
	if [ $UP == 0 ]; then
		exit 0;
	fi
	#else we will continue
else
	if [ $UPLOAD == 0 ]; then
		echo "Nothing new detected"
		exit 0;
	fi
	#else we will continue
fi

# Prepare the RPMs for pkging and upload
set -x
build-utils/rpmsign.exp $DESTDIR/*rpm
build-utils/rpmsign.exp $SRCDIR/*rpm
createrepo $DESTDIR
createrepo $SRCDIR
rm $SRCDIR/repodata/repomd.xml.asc
rm $DESTDIR/repodata/repomd.xml.asc
gpg -a --detach-sign $DESTDIR/repodata/repomd.xml
gpg -a --detach-sign $SRCDIR/repodata/repomd.xml
chgrp -R xcat $DESTDIR
chmod -R g+w $DESTDIR
cd $DESTDIR/..
#todo: if $2 == "release" then name the tarball differently and upload to FRS.  Also upload RPMs to xcat-core instead of core-snap.
export CFNAME=core-rpms-snap.tar.bz2
tar jcvf $CFNAME core-snap
chgrp xcat $CFNAME
chmod g+w $CFNAME

# Upload the tarball and individual RPMs
if [ -n "$1" ]; then
	DIR=$1
else
	DIR=devel
fi
scp $CFNAME $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$DIR/
rsync -rlv --delete core-snap $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$DIR/
