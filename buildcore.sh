#!/bin/bash

# Build and upload the xcat-core code.
# Getting Started:
#  - Check out the xcat-core svn repository (either the trunk or a branch) into
#    a dir called <rel>/src/xcat-core, where <rel> is the same as the release dir it will be
#    uploaded to in sourceforge (e.g. devel, or 2.3).
#  - You probably also want to put root's pub key from the build machine onto sourceforge for
#    the upload user listed below, so you don't have to keep entering pw's.  You can do this
#    at https://sourceforge.net/account/ssh
#  - Also make sure createrepo is installed on the build machine
#  - Run this script from the local svn repository you just created.  It will create the other
#    directories that are needed.

# Usage:  buildcore.sh [attr=value attr=value ...]
#		PROMOTE=1 - if the attribute "PROMOTE" is specified, means an official dot release.
#					Otherwise, and snap build is assumed.
# 		UP=0 or UP=1 - override the default upload behavior 
# 		SVNUP=<filename> - control which rpms get built by specifying a coresvnup file

# you can change this if you need to
UPLOADUSER=bp-sawyers

GSA=http://pokgsa.ibm.com/projects/x/xcat/build/linux

set -x

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	declare `echo $i|cut -d '=' -f 1`=`echo $i|cut -d '=' -f 2`
done

export HOME=/root		# This is so rpm and gpg will know home, even in sudo
cd `dirname $0`

# Strip the /src/xcat-core from the end of the dir to get the next dir up and use as the release
CURDIR=`pwd`
D=${CURDIR/\/src\/xcat-core/}
REL=`basename $D`

XCATCORE="xcat-core"
VER=`cat Version`
if [ "$PROMOTE" = 1 ]; then
	CORE="xcat-core"
	TARNAME=xcat-core-$VER.tar.bz2
else
	CORE="core-snap"
	TARNAME=core-rpms-snap.tar.bz2
fi
DESTDIR=../../$XCATCORE
SRCD=core-snap-srpms


if [ "$PROMOTE" != 1 ]; then      # very long if statement to not do builds if we are promoting
mkdir -p $DESTDIR
SRCDIR=../../$SRCD
mkdir -p $SRCDIR
GREP=grep
UPLOAD=0
if [ -f /etc/redhat-release ]
then
  pkg="redhat"
else
  pkg="packages"
fi

# If they have not given us a premade update file, do an svn update and capture the results
if [ -z "$SVNUP" ]; then
	SVNUP=../coresvnup
	svn up > $SVNUP
fi

# If anything has changed, we should rebuild perl-xCAT
BUILDIT=0
if ! $GREP 'At revision' $SVNUP; then
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
if $GREP xCAT-UI $SVNUP; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-UI*
   rm -f $SRCDIR/xCAT-UI*
   ./makeuirpm
   mv /usr/src/$pkg/RPMS/noarch/xCAT-UI-$VER*rpm $DESTDIR
   mv /usr/src/$pkg/SRPMS/xCAT-UI-$VER*rpm $SRCDIR
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
# get gpg keys in place
mkdir -p $HOME/.gnupg
for i in pubring.gpg secring.gpg trustdb.gpg; do
	if [ ! -f $HOME/.gnupg/$i ] || [ `wc -c $HOME/.gnupg/$i|cut -f 1 -d' '` == 0 ]; then
		wget -P $HOME/.gnupg $GSA/keys/$i
	fi
done
# tell rpm to use gpg to sign
MACROS=$HOME/.rpmmacros
if ! $GREP -q '%_signature gpg' $MACROS 2>/dev/null; then
	echo '%_signature gpg' >> $MACROS
fi
if ! $GREP -q '%_gpg_name' $MACROS 2>/dev/null; then
	echo '%_gpg_name Jarrod Johnson' >> $MACROS
fi
build-utils/rpmsign.exp $DESTDIR/*rpm
build-utils/rpmsign.exp $SRCDIR/*rpm
createrepo $DESTDIR
createrepo $SRCDIR
rm -f $SRCDIR/repodata/repomd.xml.asc
rm -f $DESTDIR/repodata/repomd.xml.asc
gpg -a --detach-sign $DESTDIR/repodata/repomd.xml
gpg -a --detach-sign $SRCDIR/repodata/repomd.xml
if [ ! -f $DESTDIR/repodata/repomd.xml.key ]; then
	wget -P $DESTDIR/repodata $GSA/keys/repomd.xml.key
fi
if [ ! -f $SRCDIR/repodata/repomd.xml.key ]; then
	wget -P $SRCDIR/repodata $GSA/keys/repomd.xml.key
fi
# make everything have a group of xcat, so anyone can manage them once they get on SF
groupadd -f xcat
chgrp -R xcat $DESTDIR
chmod -R g+w $DESTDIR
chgrp -R xcat $SRCDIR
chmod -R g+w $SRCDIR
fi		# end of very long if-not-promote


# Modify the repo file to point to either xcat-core or core-snap
# Always recreate it, in case the whole dir was copied from devel to 2.x
cd $DESTDIR
cat >xCAT-core.repo << EOF
[xcat-2-core]
name=xCAT 2 Core packages
baseurl=http://xcat.sourceforge.net/yum/$REL/$CORE
enabled=1
gpgcheck=1
gpgkey=http://xcat.sourceforge.net/yum/$REL/$CORE/repodata/repomd.xml.key
EOF

#if [ "$PROMOTE" = 1 ]; then
#	sed -e 's|/core-snap|/xcat-core|' xCAT-core.repo > xCAT-core.repo.new
#	mv -f xCAT-core.repo.new xCAT-core.repo
#else
#	sed -e 's|/xcat-core|/core-snap|' xCAT-core.repo > xCAT-core.repo.new
#	mv -f xCAT-core.repo.new xCAT-core.repo
#fi

# Build the tarball
cd ..
tar -hjcvf $TARNAME $XCATCORE
chgrp xcat $TARNAME
chmod g+w $TARNAME

# Upload the individual RPMs to sourceforge
if [ ! -e core-snap ]; then
	ln -s xcat-core core-snap
fi
while ! rsync -urLv --delete $CORE $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
do : ; done

# Upload the individual source RPMs to sourceforge
while ! rsync -urLv --delete $SRCD $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
do : ; done

# Upload the tarball to sourceforge
if [ "$PROMOTE" = 1 -a "$REL" != "devel" ]; then
	# upload tarball to FRS area
	#scp $TARNAME $UPLOADUSER@web.sourceforge.net:uploads/
	while ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:/home/frs/project/x/xc/xcat/xcat/$REL.x_Linux/
	do : ; done
else
	while ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/$REL/
	do : ; done
fi

# Extract and upload the man pages in html format
if [ "$REL" = "devel" -a "$PROMOTE" != 1 ]; then
	mkdir -p man
	cd man
	rm -rf opt
	rpm2cpio ../$XCATCORE/xCAT-client-*.noarch.rpm | cpio -id '*.html'
	rpm2cpio ../$XCATCORE/perl-xCAT-*.noarch.rpm | cpio -id '*.html'
	while ! rsync -rv opt/xcat/share/doc/man1 opt/xcat/share/doc/man3 opt/xcat/share/doc/man5 opt/xcat/share/doc/man8 $UPLOADUSER,xcat@web.sourceforge.net:htdocs/
	do : ; done
	cd ..
fi
