#!/bin/sh

# Build and upload the xcat-core code.  Run this script from a dir in which you want
# 2 subdirs created:  core-snap and core-snap-srpms.

# Usage:  buildcore.sh [<branch>] [release]
#		<branch> - e.g. 2.1 or devel (the default).  If not specified, the trunk/new devel branch is assumed
#		promote - if the keyword "promote" is specified, means an official dot release.
#					Otherwise, and snap build is assumed.
# You can override the default upload behavior by specifying env var: UP=0 or UP=1

# you can change this if you need to
UPLOADUSER=bp-sawyers

set -x
CURRENTDIR=`pwd`
export HOME=/root
if [ -n "$1" ]; then
	REL=$1
else
	REL=devel
fi
cd `dirname $0`
VER=`cat Version`
if [ "$2" = "promote" ]; then
	CORE="xcat-core"
	TARNAME=xcat-core-$VER.tar.bz2
else
	CORE="core-snap"
	TARNAME=core-rpms-snap.tar.bz2
fi
DESTDIR=$CURRENTDIR/$REL/$CORE

if [ "$2" != "promote" ]; then      # very long if statement to not do builds if we are promoting
mkdir -p $DESTDIR
SRCDIR=$CURRENTDIR/$REL/core-snap-srpms
mkdir -p $SRCDIR
GREP=grep
UPLOAD=0
if [ -f /etc/redhat-release ]
then
  pkg="redhat"
else
  pkg="packages"
fi

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
if $GREP xCAT-rmc ../coresvnup; then
   UPLOAD=1
   ./makermcrpm
   rm -f $DESTDIR/xCAT-rmc*rpm
   rm -f $SRCDIR/xCAT-rmc*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-rmc-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-rmc-$VER*rpm $SRCDIR
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
if $GREP -E '^[UAD] +xCATsn/' ../coresvnup; then
   UPLOAD=1
   rm -f $DESTDIR/xCATsn-$VER*rpm
   rm -f $SRCDIR/xCATsn-$VER*rpm
   ./makexcatsnrpm x86_64
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCATsn-$VER*rpm $SRCDIR
   ./makexcatsnrpm i386
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
   ./makexcatsnrpm ppc64
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
   ./makexcatsnrpm s390x
   mv /usr/src/$pkg/RPMS/*/xCATsn-$VER*rpm $DESTDIR
fi
if $GREP -E '^[UAD] +xCAT/' ../coresvnup; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-$VER*rpm
   rm -f $SRCDIR/xCAT-$VER*rpm
   ./makexcatrpm x86_64
   mv /usr/src/$pkg/RPMS/*/xCAT-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-$VER*rpm $SRCDIR
   ./makexcatrpm i386
   mv /usr/src/$pkg/RPMS/*/xCAT-$VER*rpm $DESTDIR
   ./makexcatrpm ppc64
   mv /usr/src/$pkg/RPMS/*/xCAT-$VER*rpm $DESTDIR
   ./makexcatrpm s390x
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
fi		# end of very long if-not-promote

set -x
cd $DESTDIR/..
tar -hjcvf $TARNAME $CORE
chgrp xcat $TARNAME
chmod g+w $TARNAME

# Upload the tarball and individual RPMs
rsync -rLv --delete $CORE $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
if [ "$2" = "promote" -a "$1" != "devel" ]; then
	# upload tarball to FRS area
	scp $TARNAME $UPLOADUSER@web.sourceforge.net:uploads/
	echo "$TARNAME has been uploaded to the FRS uploads dir.  Remember to move it into the release."
else
	scp $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
fi
