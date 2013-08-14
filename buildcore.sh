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
#  - On AIX:  Install openssl and openssh installp pkgs and run updtvpkg.  Install from http://www.perzl.org/aix/ :
#			apr, apr-util, bash, bzip2, db4, expat, gdbm, gettext, glib2, gmp, info, libidn, neon, openssl (won't
#			conflict with the installp version - but i don't think you need this), pcre, perl-DBD-SQLite, perl-DBI,
#           popt, python, readline, rsynce, sqlite, subversion, unixODBC, zlib.  Install wget from http://www-03.ibm.com/systems/power/software/aix/linux/toolbox/alpha.html
#  - Run this script from the local svn repository you just created.  It will create the other
#    directories that are needed.

# Usage:  buildcore.sh [attr=value attr=value ...]
#       Before running buildcore.sh, you must change the local git repo to the branch you want built, using: git checkout <branch>
#		PROMOTE=1 - if the attribute "PROMOTE" is specified, means an official dot release.
#					Otherwise, and snap build is assumed.
#		PREGA=1 - means this is a branch that has not been released yet, so during the promote, copy the
#					xcat-core tarball to the SF web site instead of the FRS area.
#		BUILDALL=1 - build all rpms, whether they changed or not.  Should be used for snap builds that are in prep for a release.
# 		UP=0 or UP=1 - override the default upload behavior 
# 		SVNUP=<filename> - control which rpms get built by specifying a coresvnup file
# 		GITUP=<filename> - control which rpms get built by specifying a coregitup file
#       FRSYUM=0 - put the yum repo and snap builds in the old project web area instead of the FRS area.
#		EMBED=<embedded-environment> - the environment for which a minimal version of xcat should be built, e.g. zvm or flex
#		VERBOSE=1 - to see lots of verbose output

# you can change this if you need to
UPLOADUSER=bp-sawyers
FRS=/home/frs/project/x/xc/xcat

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	# upper case the variable name
	varstring=`echo "$i"|cut -d '=' -f 1|tr '[a-z]' '[A-Z]'`=`echo "$i"|cut -d '=' -f 2`
	export $varstring
done
if [ "$VERBOSE" = "1" -o "$VERBOSE" = "yes" ]; then
	set -x
	VERBOSEMODE=1
fi

# Find where this script is located to set some build variables
cd `dirname $0`
# strip the /src/xcat-core from the end of the dir to get the next dir up and use as the release
if [ -z "$REL" ]; then
	curdir=`pwd`
	D=${curdir%/src/xcat-core}
	REL=`basename $D`
fi
OSNAME=$(uname)

if [ "$OSNAME" != "AIX" ]; then
	GSA=http://pokgsa.ibm.com/projects/x/xcat/build/linux
	
	# Get a lock, so can not do 2 builds at once
	exec 8>/var/lock/xcatbld-$REL.lock
	if ! flock -n 8; then
		echo "Can't get lock /var/lock/xcatbld-$REL.lock.  Someone else must be doing a build right now.  Exiting...."
		exit 1
	fi
	
	export HOME=/root		# This is so rpm and gpg will know home, even in sudo
fi

# for the git case, query the current branch and set REL (changing master to devel if necessary)
function setbranch {
	#git checkout $BRANCH
	REL=`git rev-parse --abbrev-ref HEAD`
	if [ "$REL" = "master" ]; then
		REL="devel"
	fi
}

if [ "$REL" = "xcat-core" ]; then			# using git
	GIT=1
	setbranch					# this changes the REL variable
fi

# this is needed only when we are transitioning the yum over to frs
if [ "$FRSYUM" != 0 ]; then
	YUMDIR=$FRS
	YUMREPOURL="https://sourceforge.net/projects/xcat/files/yum"
else
	YUMDIR=htdocs
	YUMREPOURL="http://xcat.sourceforge.net/yum"
fi

# Set variables based on which type of build we are doing
if [ -n "$EMBED" ]; then EMBEDDIR="/$EMBED"
else EMBEDDIR=""; fi
XCATCORE="xcat-core"		# core-snap is a sym link to xcat-core

if [ "$GIT" = "1" ]; then                      # using git - need to include REL in the path where we put the built rpms
	DESTDIR=../../$REL$EMBEDDIR/$XCATCORE
else
	DESTDIR=../..$EMBEDDIR/$XCATCORE
fi
SRCD=core-snap-srpms

# currently aix builds ppc rpms, but someday it should build noarch
if [ "$OSNAME" = "AIX" ]; then
	NOARCH=ppc
else
	NOARCH=noarch
fi


if [ "$PROMOTE" != 1 ]; then      # very long if statement to not do builds if we are promoting
# we are doing a snap build
CORE="core-snap"
if [ "$OSNAME" = "AIX" ]; then
	TARNAME=core-aix-snap.tar.gz
else
	TARNAME=core-rpms-snap.tar.bz2
fi
mkdir -p $DESTDIR
SRCDIR=$DESTDIR/../$SRCD
mkdir -p $SRCDIR
if [ -n "$VERBOSEMODE" ]; then
	GREP=grep
else
	GREP="grep -q"
fi
UPLOAD=0
if [ "$OSNAME" = "AIX" ]; then
	source=/opt/freeware/src/packages
else
	source=`rpmbuild --eval '%_topdir' xCATsn/xCATsn.spec`
	if [ $? -gt 0 ]; then
		echo "Error: Could not determine rpmbuild's root directory."
		exit 2
	fi
	#echo "source=$source"
fi

# If they have not given us a premade update file, do an svn update or git pull and capture the results
SOMETHINGCHANGED=0
if [ "$GIT" = "1" ]; then			# using git
	if [ -z "$GITUP" ]; then
		GITUP=../coregitup
		echo "git pull > $GITUP"
		git pull > $GITUP
	fi
	if ! $GREP 'Already up-to-date' $GITUP; then
		SOMETHINGCHANGED=1
	fi
else		# using svn
	GIT=0
	if [ -z "$SVNUP" ]; then
		SVNUP=../coresvnup
		echo "svn up > $SVNUP"
		svn up > $SVNUP
	fi
	if ! $GREP 'At revision' $SVNUP; then
		SOMETHINGCHANGED=1
	fi
	# copy the SVNUP variable to GITUP so the rest of the script doesnt have to worry whether we did svn or git
	GITUP=$SVNUP
fi

function setversionvars {
	VER=`cat Version`
	SHORTVER=`cat Version|cut -d. -f 1,2`
	SHORTSHORTVER=`cat Version|cut -d. -f 1`
}

setversionvars

# Process for making most of the rpms
function maker {
	rpmname="$1"
	./makerpm $rpmname "$EMBED"
	if [ $? -ne 0 ]; then
		FAILEDRPMS="$FAILEDRPMS $rpmname"
	else
		rm -f $DESTDIR/$rpmname*rpm
		rm -f $SRCDIR/$rpmname*rpm
		mv $source/RPMS/$NOARCH/$rpmname-$VER*rpm $DESTDIR
		mv $source/SRPMS/$rpmname-$VER*rpm $SRCDIR
	fi
}

# If anything has changed, we should always rebuild perl-xCAT
if [ $SOMETHINGCHANGED == 1 -o "$BUILDALL" == 1 ]; then		# Use to be:  $GREP perl-xCAT $GITUP; then
	UPLOAD=1
	maker perl-xCAT
fi
if [ "$OSNAME" = "AIX" ]; then
	# For the 1st one we overwrite, not append
	echo "rpm -Uvh perl-xCAT-$SHORTSHORTVER*rpm" > $DESTDIR/instxcat
fi

# Build the rest of the noarch rpms
for rpmname in xCAT-client xCAT-server xCAT-IBMhpc xCAT-rmc xCAT-UI xCAT-test; do
	if $GREP $rpmname $GITUP || [ "$BUILDALL" == 1 ]; then
		UPLOAD=1
		if [ "$EMBED" = "zvm" -a "$rpmname" != "xCAT-server" -a "$rpmname" != "xCAT-UI" ]; then continue; fi		# for embedded envs only need to build server special
		maker $rpmname
	fi
	if [ "$OSNAME" = "AIX" ]; then
		if [ "$rpmname" = "xCAT-client" -o "$rpmname" = "xCAT-server" ]; then		# we do not automatically install the rest of the rpms on AIX
			echo "rpm -Uvh $rpmname-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
		fi
	fi
done

if [ "$OSNAME" != "AIX" -a "$EMBED" != "zvm" ]; then
	if grep -v nbroot2 $GITUP|$GREP xCAT-nbroot || [ "$BUILDALL" == 1 ]; then
		UPLOAD=1
		ORIGFAILEDRPMS="$FAILEDRPMS"
		for arch in x86_64 x86 ppc64; do
			./makerpm xCAT-nbroot-core $arch
			if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS xCAT-nbroot-core-$arch"; fi
		done
		if [ "$FAILEDRPMS" = "$ORIGFAILEDRPMS" ]; then	# all succeeded
			rm -f $DESTDIR/xCAT-nbroot-core*rpm
			rm -f $SRCDIR/xCAT-nbroot-core*rpm
			mv $source/RPMS/noarch/xCAT-nbroot-core-*rpm $DESTDIR
			mv $source/SRPMS/xCAT-nbroot-core-*rpm $SRCDIR
		fi
	fi
fi

# Build the xCAT and xCATsn rpms for all platforms
for rpmname in xCAT xCATsn; do
	if [ "$EMBED" = "zvm" ]; then break; fi
	if [ $SOMETHINGCHANGED == 1 -o "$BUILDALL" == 1 ]; then		# used to be:  if $GREP -E "^[UAD] +$rpmname/" $GITUP; then
		UPLOAD=1
		ORIGFAILEDRPMS="$FAILEDRPMS"
		if [ "$OSNAME" = "AIX" ]; then
			./makerpm $rpmname
			if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS $rpmname"; fi
		else
			for arch in x86_64 i386 ppc64 s390x; do
				./makerpm $rpmname $arch
				if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS $rpmname-$arch"; fi
			done
		fi
		if [ "$FAILEDRPMS" = "$ORIGFAILEDRPMS" ]; then	# all succeeded
			rm -f $DESTDIR/$rpmname-$SHORTSHORTVER*rpm
			rm -f $SRCDIR/$rpmname-$SHORTSHORTVER*rpm
			mv $source/RPMS/*/$rpmname-$VER*rpm $DESTDIR
			mv $source/SRPMS/$rpmname-$VER*rpm $SRCDIR
		fi
	fi
done

if [ "$OSNAME" = "AIX" ]; then
	echo "rpm -Uvh xCAT-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
	echo "rpm -Uvh xCAT-rmc-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
fi

# Make sym links in the embed subdirs for the rpms we do not have to build special
cd $DESTDIR
if [ "$EMBED" = "zvm" ]; then
	maindir="../../$XCATCORE"
	rm -f xCAT-client-$SHORTSHORTVER*rpm
	ln -s $maindir/xCAT-client-$SHORTSHORTVER*rpm .
	rm -f xCAT-$SHORTSHORTVER*rpm
	ln -s $maindir/xCAT-$SHORTSHORTVER*.s390x.rpm .
	rm -f xCATsn-$SHORTSHORTVER*rpm
	ln -s $maindir/xCATsn-$SHORTSHORTVER*.s390x.rpm .
fi
cd - >/dev/null


# Decide if anything was built or not
if [ -n "$FAILEDRPMS" ]; then
	echo "Error:  build of the following RPMs failed: $FAILEDRPMS"
	exit 2
fi
if [ $UPLOAD == 0 -a "$UP" != 1 ]; then
	echo "Nothing new detected"
	exit 0
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
	if ! $GREP '%_signature gpg' $MACROS 2>/dev/null; then
		echo '%_signature gpg' >> $MACROS
	fi
	if ! $GREP '%_gpg_name' $MACROS 2>/dev/null; then
		echo '%_gpg_name Jarrod Johnson' >> $MACROS
	fi
	echo "Signing RPMs..."
	build-utils/rpmsign.exp `find $DESTDIR -type f -name '*.rpm'` | grep -v -E '(was already signed|rpm --quiet --resign|WARNING: standard input reopened)'
	build-utils/rpmsign.exp $SRCDIR/*rpm | grep -v -E '(was already signed|rpm --quiet --resign|WARNING: standard input reopened)'
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
	if ! lsgroup xcat >/dev/null 2>&1; then
		mkgroup xcat
	fi
	chmod +x $DESTDIR/instxcat
else	# linux
	if ! $GREP xcat /etc/group; then
		groupadd xcat
	fi
fi
chgrp -R xcat $DESTDIR
chmod -R g+w $DESTDIR
chgrp -R xcat $SRCDIR
chmod -R g+w $SRCDIR

else		# end of very long if-not-promote
	# we are only promoting (not building)
	setversionvars
	setbranch
	CORE="xcat-core"
	if [ "$OSNAME" = "AIX" ]; then
		TARNAME=core-aix-$VER.tar.gz
	else
		TARNAME=xcat-core-$VER.tar.bz2
	fi
fi

cd $DESTDIR

if [ "$OSNAME" != "AIX" ]; then

	# Modify the repo file to point to either xcat-core or core-snap
	# Always recreate it, in case the whole dir was copied from devel to 2.x
	if [ -n "$1" ]; then embed="$1/"
	else embed=""; fi
	cat >xCAT-core.repo << EOF
[xcat-2-core]
name=xCAT 2 Core packages
baseurl=$YUMREPOURL/$REL$EMBEDDIR/$CORE
enabled=1
gpgcheck=1
gpgkey=$YUMREPOURL/$REL$EMBEDDIR/$CORE/repodata/repomd.xml.key
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
if [ -n "$VERBOSEMODE" ]; then
	verboseflag="-v"
else
	verboseflag=""
fi
echo "Creating $TARNAME ..."
if [ "$OSNAME" = "AIX" ]; then
	tar $verboseflag -hcf ${TARNAME%.gz} $XCATCORE
	rm -f $TARNAME
	gzip ${TARNAME%.gz}
else
	tar $verboseflag -hjcf $TARNAME $XCATCORE
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
	i=0
	echo "Uploading RPMs from $CORE to $YUMDIR/$YUM/$REL$EMBEDDIR/ ..."
	while [ $((i+=1)) -le 5 ] && ! rsync -urLv --delete $CORE $UPLOADUSER,xcat@web.sourceforge.net:$YUMDIR/$YUM/$REL$EMBEDDIR/
	do : ; done
fi

# Upload the individual source RPMs to sourceforge
i=0
echo "Uploading src RPMs from $SRCD to $YUMDIR/$YUM/$REL$EMBEDDIR/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync -urLv --delete $SRCD $UPLOADUSER,xcat@web.sourceforge.net:$YUMDIR/$YUM/$REL$EMBEDDIR/
do : ; done

# Upload the tarball to sourceforge
if [ "$PROMOTE" = 1 -a "$REL" != "devel" -a "$PREGA" != 1 ]; then
	# upload tarball to FRS area
	i=0
	echo "Uploading $TARNAME to $FRS/xcat/$REL.x_$OSNAME$EMBEDDIR/ ..."
	while [ $((i+=1)) -le 5 ] && ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:$FRS/xcat/$REL.x_$OSNAME$EMBEDDIR/
	do : ; done
else
	i=0
	echo "Uploading $TARNAME to $YUMDIR/$YUM/$REL$EMBEDDIR/ ..."
	while [ $((i+=1)) -le 5 ] && ! rsync -v $TARNAME $UPLOADUSER,xcat@web.sourceforge.net:$YUMDIR/$YUM/$REL$EMBEDDIR/
	do : ; done
fi

# Extract and upload the man pages in html format
if [ "$OSNAME" != "AIX" -a "$REL" = "devel" -a "$PROMOTE" != 1 -a -z "$EMBED" ]; then
	echo "Extracting and uploading man pages to htdocs/ ..."
	mkdir -p man
	cd man
	rm -rf opt
	rpm2cpio ../$XCATCORE/xCAT-client-*.$NOARCH.rpm | cpio -id '*.html'
	rpm2cpio ../$XCATCORE/perl-xCAT-*.$NOARCH.rpm | cpio -id '*.html'
	rpm2cpio ../$XCATCORE/xCAT-test-*.$NOARCH.rpm | cpio -id '*.html'
	i=0
	while [ $((i+=1)) -le 5 ] && ! rsync $verboseflag -r opt/xcat/share/doc/man1 opt/xcat/share/doc/man3 opt/xcat/share/doc/man5 opt/xcat/share/doc/man7 opt/xcat/share/doc/man8 $UPLOADUSER,xcat@web.sourceforge.net:htdocs/
	do : ; done
	cd ..
fi
