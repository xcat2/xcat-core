# The shell is commented out so that it will run in bash on linux and ksh on aix
#  !/bin/bash

# Build and upload the xcat-core code, on either linux or aix.

# Getting Started:
#  - Check out the xcat-core svn repository (either the trunk or a branch) into
#    a dir called <rel>/src/xcat-core, where <rel> is the same as the release dir it will be
#    uploaded to in sourceforge (e.g. devel, or 2.3).
#  - You probably also want to put root's pub key from the build machine onto sourceforge for
#    the upload user listed below, so you don't have to keep entering pw's.  You can do this
#    at https://sourceforge.net/account/ssh
#  - On Linux:  make sure createrepo is installed on the build machine
#  - On AIX:  Install openssl and openssh installp pkgs and run updtvpkg.  Install from http://www.perzl.org/aix/
#			apr, apr-util, bash, bzip2, db4, expat, gdbm, gettext, glib2, gmp, info, libidn, neon, openssl (won't
#			conflict with the installp version), pcre, perl-DBD-SQLite, perl-DBI, popt, python, readline, rsynce, sqlite,
#			subversion, unixODBC, wget, zlib.
#  - Run this script from the local svn repository you just created.  It will create the other
#    directories that are needed.

# Usage:  buildcore.sh [attr=value attr=value ...]
#		PROMOTE=1 - if the attribute "PROMOTE" is specified, means an official dot release.
#					Otherwise, and snap build is assumed.
#		PREGA=1 - means this is a branch that has not been released yet, so during the promote, copy the
#					xcat-core tarball to the SF web site instead of the FRS area.
# 		UP=0 or UP=1 - override the default upload behavior 
# 		SVNUP=<filename> - control which rpms get built by specifying a coresvnup file

# you can change this if you need to
UPLOADUSER=bp-sawyers

OSNAME=$(uname)

cd `dirname $0`
# Strip the /src/xcat-core from the end of the dir to get the next dir up and use as the release
CURDIR=`pwd`
#D=${CURDIR/\/src\/xcat-core/}
D=${CURDIR%/src/xcat-core}
REL=`basename $D`

if [ "$OSNAME" != "AIX" ]; then
	GSA=http://pokgsa.ibm.com/projects/x/xcat/build/linux
	
	# Get a lock, so can not do 2 builds at once
	exec 8>/var/lock/xcatbld-$REL.lock
	if ! flock -n 8; then
		echo "Can't get lock /var/lock/xcatbld-$REL.lock.  Someone else must be doing a build right now.  Exiting...."
		exit 1
	fi
fi

set -x

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	#declare `echo $i|cut -d '=' -f 1`=`echo $i|cut -d '=' -f 2`
	export $i
done

if [ "$OSNAME" != "AIX" ]; then
	export HOME=/root		# This is so rpm and gpg will know home, even in sudo
fi

XCATCORE="xcat-core"
svn up Version
VER=`cat Version`
SHORTVER=`cat Version|cut -d. -f 1,2`
SHORTSHORTVER=`cat Version|cut -d. -f 1`
if [ "$PROMOTE" = 1 ]; then
	CORE="xcat-core"
	if [ "$OSNAME" = "AIX" ]; then
		TARNAME=core-aix-$VER.tar.gz
	else
		TARNAME=xcat-core-$VER.tar.bz2
	fi
else
	CORE="core-snap"
	if [ "$OSNAME" = "AIX" ]; then
		TARNAME=core-aix-snap.tar.gz
	else
		TARNAME=core-rpms-snap.tar.bz2
	fi
fi
DESTDIR=../../$XCATCORE
SRCD=core-snap-srpms


if [ "$PROMOTE" != 1 ]; then      # very long if statement to not do builds if we are promoting
mkdir -p $DESTDIR
SRCDIR=../../$SRCD
mkdir -p $SRCDIR
GREP=grep
# currently aix builds ppc rpms, but it should build noarch
if [ "$OSNAME" = "AIX" ]; then
	NOARCH=ppc
else
	NOARCH=noarch
fi
UPLOAD=0
if [ "$OSNAME" = "AIX" ]; then
	source=/opt/freeware/src/packages
else
	if [ -f /etc/redhat-release ]; then
		source="/usr/src/redhat"
	else
		source="/usr/src/packages"
	fi
fi

# If they have not given us a premade update file, do an svn update and capture the results
if [ -z "$SVNUP" ]; then
	SVNUP=../coresvnup
	svn up > $SVNUP
fi

# If anything has changed, we should always rebuild perl-xCAT
if ! $GREP 'At revision' $SVNUP; then		# Use to be:  $GREP perl-xCAT $SVNUP; then
   UPLOAD=1
   ./makeperlxcatrpm
   rm -f $DESTDIR/perl-xCAT*rpm
   rm -f $SRCDIR/perl-xCAT*rpm
   mv $source/RPMS/$NOARCH/perl-xCAT-$VER*rpm $DESTDIR/
   mv $source/SRPMS/perl-xCAT-$VER*rpm $SRCDIR/
fi
if [ "$OSNAME" = "AIX" ]; then
	# For the 1st one we overwrite, not append
	echo "rpm -Uvh perl-xCAT-$SHORTSHORTVER*rpm" > $DESTDIR/instxcat
fi

if $GREP xCAT-client $SVNUP; then
   UPLOAD=1
   ./makeclientrpm
   rm -f $DESTDIR/xCAT-client*rpm
   rm -f $SRCDIR/xCAT-client*rpm
   mv $source/RPMS/$NOARCH/xCAT-client-$VER*rpm $DESTDIR/
   mv $source/SRPMS/xCAT-client-$VER*rpm $SRCDIR/
fi
if [ "$OSNAME" = "AIX" ]; then
	echo "rpm -Uvh xCAT-client-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
fi

if $GREP xCAT-UI $SVNUP; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-UI*rpm
   rm -f $SRCDIR/xCAT-UI*rpm
   ./makeuirpm
   mv $source/RPMS/noarch/xCAT-UI-$VER*rpm $DESTDIR
   mv $source/SRPMS/xCAT-UI-$VER*rpm $SRCDIR
fi
# Do not automatically install xCAT-UI on AIX
#if [ "$OSNAME" = "AIX" ]; then
#	echo "rpm -Uvh xCAT-UI-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
#fi

if $GREP xCAT-IBMhpc $SVNUP; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-IBMhpc*rpm
   rm -f $SRCDIR/xCAT-IBMhpc*rpm
   ./makehpcrpm
   mv $source/RPMS/$NOARCH/xCAT-IBMhpc-$VER*rpm $DESTDIR
   mv $source/SRPMS/xCAT-IBMhpc-$VER*rpm $SRCDIR
fi
# Do not automatically install xCAT-IBMhpc on AIX
#if [ "$OSNAME" = "AIX" ]; then
#	echo "rpm -Uvh xCAT-IBMhpc-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
#fi

if $GREP xCAT-server $SVNUP; then
   UPLOAD=1
   ./makeserverrpm
   rm -f $DESTDIR/xCAT-server*rpm
   rm -f $SRCDIR/xCAT-server*rpm
   mv $source/RPMS/$NOARCH/xCAT-server-$VER*rpm $DESTDIR
   mv $source/SRPMS/xCAT-server-$VER*rpm $SRCDIR
fi
if [ "$OSNAME" = "AIX" ]; then
	echo "rpm -Uvh xCAT-server-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
fi

if $GREP xCAT-rmc $SVNUP; then
   UPLOAD=1
   ./makermcrpm
   rm -f $DESTDIR/xCAT-rmc*rpm
   rm -f $SRCDIR/xCAT-rmc*rpm
   mv $source/RPMS/$NOARCH/xCAT-rmc-$VER*rpm $DESTDIR
   mv $source/SRPMS/xCAT-rmc-$VER*rpm $SRCDIR
fi
# Note: not putting xCAT-rmc into instxcat for aix here, because it has to be installed
#		after xCAT.

if $GREP xCAT-test $SVNUP; then
   UPLOAD=1
   ./maketestrpm
   rm -f $DESTDIR/xCAT-test*rpm
   rm -f $SRCDIR/xCAT-test*rpm
   mv $source/RPMS/$NOARCH/xCAT-test-$VER*rpm $DESTDIR
   mv $source/SRPMS/xCAT-test-$VER*rpm $SRCDIR
fi
# Note: not putting xCAT-test into instxcat for aix, because it is optional

if [ "$OSNAME" != "AIX" ]; then
	if $GREP xCAT-nbroot $SVNUP; then
	   UPLOAD=1
	   ./makenbrootrpm x86_64
	   ./makenbrootrpm ppc64
	   ./makenbrootrpm x86
	   rm -f $DESTDIR/xCAT-nbroot-core*rpm
	   rm -f $SRCDIR/xCAT-nbroot-core*rpm
	   mv $source/RPMS/noarch/xCAT-nbroot-core-*rpm $DESTDIR
	   mv $source/SRPMS/xCAT-nbroot-core-*rpm $SRCDIR
	fi
fi

if $GREP -E '^[UAD] +xCATsn/' $SVNUP; then
   UPLOAD=1
   rm -f $DESTDIR/xCATsn-*rpm
   rm -f $SRCDIR/xCATsn-*rpm
	if [ "$OSNAME" = "AIX" ]; then
		./makexcatsnrpm
		mv $source/RPMS/*/xCATsn-$VER*rpm $DESTDIR
		mv $source/SRPMS/xCATsn-$VER*rpm $SRCDIR
	else
	   ./makexcatsnrpm x86_64
	   mv $source/RPMS/*/xCATsn-$VER*rpm $DESTDIR
	   mv $source/SRPMS/xCATsn-$VER*rpm $SRCDIR
	   ./makexcatsnrpm i386
	   mv $source/RPMS/*/xCATsn-$VER*rpm $DESTDIR
	   ./makexcatsnrpm ppc64
	   mv $source/RPMS/*/xCATsn-$VER*rpm $DESTDIR
	   ./makexcatsnrpm s390x
	   mv $source/RPMS/*/xCATsn-$VER*rpm $DESTDIR
	fi
fi

if $GREP -E '^[UAD] +xCAT/' $SVNUP; then
   UPLOAD=1
   rm -f $DESTDIR/xCAT-$SHORTSHORTVER*rpm
   rm -f $SRCDIR/xCAT-$SHORTSHORTVER*rpm
	if [ "$OSNAME" = "AIX" ]; then
	   ./makexcatrpm
	   mv $source/RPMS/*/xCAT-$VER*rpm $DESTDIR
	   mv $source/SRPMS/xCAT-$VER*rpm $SRCDIR
	else
	   ./makexcatrpm x86_64
	   mv $source/RPMS/*/xCAT-$VER*rpm $DESTDIR
	   mv $source/SRPMS/xCAT-$VER*rpm $SRCDIR
	   ./makexcatrpm i386
	   mv $source/RPMS/*/xCAT-$VER*rpm $DESTDIR
	   ./makexcatrpm ppc64
	   mv $source/RPMS/*/xCAT-$VER*rpm $DESTDIR
	   ./makexcatrpm s390x
	   mv $source/RPMS/*/xCAT-$VER*rpm $DESTDIR
	fi
fi

if [ "$OSNAME" = "AIX" ]; then
	echo "rpm -Uvh xCAT-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
	echo "rpm -Uvh xCAT-rmc-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
	# add the service node bundle files 
	#   these are now shipped as part of xCAT-server !!!!
	#	- installed in /opt/xcat/share/xcat/installp_bundles
	# cp xCATaixSN.bnd xCATaixSN2.bnd xCATaixSSH.bnd xCATaixSSL.bnd $DESTDIR/
fi

# Decide if anything was built or not
if [ $UPLOAD == 0 -a "$UP" != 1 ]; then
	echo "Nothing new detected"
	exit 0;
fi
#else we will continue

# Prepare the RPMs for pkging and upload

# get gpg keys in place
if [ "$OSNAME" != "AIX" ]; then
	mkdir -p $HOME/.gnupg
	for i in pubring.gpg secring.gpg trustdb.gpg; do
		if [ ! -f $HOME/.gnupg/$i ] || [ `wc -c $HOME/.gnupg/$i|cut -f 1 -d' '` == 0 ]; then
			rm -f $HOME/.gnupg/$i
			wget -P $HOME/.gnupg $GSA/keys/$i
			chmod 600 $HOME/.gnupg/$i
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
fi

# make everything have a group of xcat, so anyone can manage them once they get on SF
if [ "$OSNAME" = "AIX" ]; then
	mkgroup xcat 2>/dev/null
	chmod +x $DESTDIR/instxcat
else
	groupadd -f xcat
fi
chgrp -R xcat $DESTDIR
chmod -R g+w $DESTDIR
chgrp -R xcat $SRCDIR
chmod -R g+w $SRCDIR

fi		# end of very long if-not-promote


cd $DESTDIR

if [ "$OSNAME" != "AIX" ]; then
	# Modify the repo file to point to either xcat-core or core-snap
	# Always recreate it, in case the whole dir was copied from devel to 2.x
	cat >xCAT-core.repo << EOF
[xcat-2-core]
name=xCAT 2 Core packages
baseurl=http://xcat.sourceforge.net/yum/$REL/$CORE
enabled=1
gpgcheck=1
gpgkey=http://xcat.sourceforge.net/yum/$REL/$CORE/repodata/repomd.xml.key
EOF

	# Create the mklocalrepo script
	cat >mklocalrepo.sh << 'EOF2'
#!/bin/sh
cd `dirname $0`
REPOFILE=`basename xCAT-*.repo`
sed -e 's|baseurl=.*|baseurl=file://'"`pwd`"'|' $REPOFILE | sed -e 's|gpgkey=.*|gpgkey=file://'"`pwd`"'/repodata/repomd.xml.key|' > /etc/yum.repos.d/$REPOFILE
cd -
EOF2
chmod 775 mklocalrepo.sh

fi	# not AIX

# Build the tarball
cd ..
if [ "$OSNAME" = "AIX" ]; then
	tar -hcvf ${TARNAME%.gz} $XCATCORE
	rm -f $TARNAME
	gzip ${TARNAME%.gz}
else
	tar -hjcvf $TARNAME $XCATCORE
fi
chgrp xcat $TARNAME
chmod g+w $TARNAME

# Decide whether to upload or not
if [ -n "$UP" ] && [ "$UP" == 0 ]; then
	exit 0;
fi
#else we will continue

# Upload the individual RPMs to sourceforge
if [ "$OSNAME" = "AIX" ]; then
	YUM=aix
else
	YUM=yum
fi
if [ ! -e core-snap ]; then
	ln -s xcat-core core-snap
fi
if [ "$REL" = "devel" -o "$PREGA" != 1 ]; then
	while ! rsync -urLv --delete $CORE $UPLOADUSER,xcat@web.sourceforge.net:htdocs/$YUM/$REL/
	do : ; done
fi

# Upload the individual source RPMs to sourceforge
while ! rsync -urLv --delete $SRCD $UPLOADUSER,xcat@web.sourceforge.net:htdocs/$YUM/$REL/
do : ; done

# Upload the tarball to sourceforge
if [ "$PROMOTE" = 1 -a "$REL" != "devel" -a "$PREGA" != 1 ]; then
	# upload tarball to FRS area
	#scp $TARNAME $UPLOADUSER@web.sourceforge.net:uploads/
	while ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:/home/frs/project/x/xc/xcat/xcat/$REL.x_$OSNAME/
	do : ; done
else
	while ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:htdocs/$YUM/$REL/
	do : ; done
fi

# Extract and upload the man pages in html format
if [ "$OSNAME" != "AIX" -a "$REL" = "devel" -a "$PROMOTE" != 1 ]; then
	mkdir -p man
	cd man
	rm -rf opt
	rpm2cpio ../$XCATCORE/xCAT-client-*.$NOARCH.rpm | cpio -id '*.html'
	rpm2cpio ../$XCATCORE/perl-xCAT-*.$NOARCH.rpm | cpio -id '*.html'
	rpm2cpio ../$XCATCORE/xCAT-test-*.$NOARCH.rpm | cpio -id '*.html'
	while ! rsync -rv opt/xcat/share/doc/man1 opt/xcat/share/doc/man3 opt/xcat/share/doc/man5 opt/xcat/share/doc/man7 opt/xcat/share/doc/man8 $UPLOADUSER,xcat@web.sourceforge.net:htdocs/
	do : ; done
	cd ..
fi
