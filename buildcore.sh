#!/bin/bash

# Build and upload the xcat-core code.  This script and the rest of the xcat-core source should
# be in a dir called <rel>/src/xcat-core, where <rel> is the same as the release dir it will be
# uploaded to in sourceforge (e.g. devel, or 2.2).

# Usage:  buildcore.sh [attr=value attr=value ...]
#		PROMOTE=1 - if the attribute "PROMOTE" is specified, means an official dot release.
#					Otherwise, and snap build is assumed.
# 		UP=0 or UP=1 - override the default upload behavior 
# 		SVNUP=<filename> - control which rpms get built by specifying a coresvnup file

# you can change this if you need to
UPLOADUSER=bp-sawyers

set -x

# Process cmd line variable assignments
for i in $*; do
	declare `echo $i|cut -d '=' -f 1`=`echo $i|cut -d '=' -f 2`
done

export HOME=/root
cd `dirname $0`

# Strip the /src/xcat-core from the end of the dir to get the next dir up and use as the release
CURDIR=`pwd`
D=${CURDIR/\/src\/xcat-core/}
REL=`basename $D`

VER=`cat Version`
if [ "$PROMOTE" = 1 ]; then
	CORE="xcat-core"
	TARNAME=xcat-core-$VER.tar.bz2
else
	CORE="core-snap"
	TARNAME=core-rpms-snap.tar.bz2
fi
DESTDIR=../../$CORE


if [ "$PROMOTE" != 1 ]; then      # very long if statement to not do builds if we are promoting
mkdir -p $DESTDIR
SRCDIR=../../core-snap-srpms
mkdir -p $SRCDIR
GREP=grep
UPLOAD=0
if [ -f /etc/redhat-release ]
then
  pkg="redhat"
else
  pkg="packages"
fi

if [ -z "$SVNUP" ]; then
	SVNUP=../coresvnup
	svn up > $SVNUP
fi
BUILDIT=0
if ! grep 'At revision' $SVNUP; then
   BUILDIT=1
fi

if $GREP xCAT-client $SVNUP; then
   UPLOAD=1
   ./makeclientrpm
   rm -f $DESTDIR/xCAT-client*rpm
   rm -f $SRCDIR/xCAT-client*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-client-$VER*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/xCAT-client-$VER*rpm $SRCDIR/
fi
if [ $BUILDIT -eq 1 ]; then		# Use to be:  $GREP perl-xCAT $SVNUP; then
   UPLOAD=1
   ./makeperlxcatrpm
   rm -f $DESTDIR/perl-xCAT*rpm
   rm -f $SRCDIR/perl-xCAT*rpm
   mv /usr/src/$pkg/RPMS/noarch/perl-xCAT-$VER*rpm $DESTDIR/
   mv /usr/src/$pkg/SRPMS/perl-xCAT-$VER*rpm $SRCDIR/
fi
# Starting in 2.3 we should build xCAT-UI instead of xCAT-web
if [ "$REL" = "devel" ]; then
	UI="UI"
	MAKEUI=makeuirpm
else
	UI="web"
	MAKEUI=makewebrpm
fi
if $GREP xCAT-$UI $SVNUP; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-$UI*
   rm -f $SRCDIR/xCAT-$UI*
   ./$MAKEUI
   mv /usr/src/$pkg/RPMS/noarch/xCAT-$UI-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-$UI-$VER*rpm $SRCDIR
fi
if $GREP xCAT-server $SVNUP; then
   UPLOAD=1
   ./makeserverrpm
   rm -f $DESTDIR/xCAT-server*rpm
   rm -f $SRCDIR/xCAT-server*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-server-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-server-$VER*rpm $SRCDIR
fi
if $GREP xCAT-rmc $SVNUP; then
   UPLOAD=1
   ./makermcrpm
   rm -f $DESTDIR/xCAT-rmc*rpm
   rm -f $SRCDIR/xCAT-rmc*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-rmc-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-rmc-$VER*rpm $SRCDIR
fi
if $GREP xCAT-nbroot $SVNUP; then
   UPLOAD=1
   ./makenbrootrpm x86_64
   ./makenbrootrpm ppc64
   ./makenbrootrpm x86
   rm -f $DESTDIR/xCAT-nbroot-core*rpm
   rm -f $SRCDIR/xCAT-nbroot-core*rpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-nbroot-core-*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-nbroot-core-*rpm $SRCDIR
fi
if $GREP -E '^[UAD] +xCATsn/' $SVNUP; then
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
if $GREP -E '^[UAD] +xCAT/' $SVNUP; then
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


# Modify the repo file to point to either xcat-core or core-snap
cd $DESTDIR
if [ "$PROMOTE" = 1 ]; then
	sed -e 's|/core-snap|/xcat-core|' xCAT-core.repo > xCAT-core.repo.new
	mv -f xCAT-core.repo.new xCAT-core.repo
else
	sed -e 's|/xcat-core|/core-snap|' xCAT-core.repo > xCAT-core.repo.new
	mv -f xCAT-core.repo.new xCAT-core.repo
fi

# Build the tarball
cd ..
tar -hjcvf $TARNAME $CORE
chgrp xcat $TARNAME
chmod g+w $TARNAME

# Upload the individual RPMs to sourceforge
while ! rsync -urLv --delete $CORE $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
do : ; done

# Upload the tarball to sourceforge
if [ "$PROMOTE" = 1 -a "$REL" != "devel" ]; then
	# upload tarball to FRS area
	#scp $TARNAME $UPLOADUSER@web.sourceforge.net:uploads/
	echo "$TARNAME has been built.  Remember to upload it to sourceforge using its File Manager."
else
	while ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
	do : ; done
fi

# Extract and upload the man pages in html format
if [ "$REL" = "devel" -a "$PROMOTE" != 1 ]; then
	mkdir -p man
	cd man
	rm -rf opt
	rpm2cpio ../$CORE/xCAT-client-*.noarch.rpm | cpio -id '*.html'
	rpm2cpio ../$CORE/perl-xCAT-*.noarch.rpm | cpio -id '*.html'
	# Note: for some reason scp kept getting "Connection reset by peer" part way thru
	while ! rsync -rv opt/xcat/share/doc/man1 opt/xcat/share/doc/man3 opt/xcat/share/doc/man5 opt/xcat/share/doc/man7 opt/xcat/share/doc/man8 $UPLOADUSER,xcat@web.sourceforge.net:htdocs/
	do : ; done
	cd ..
fi
