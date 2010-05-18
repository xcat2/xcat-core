#!/bin/sh
# Package up all the xCAT open source dependencies, setting up yum repos and
# also tar it all up.  This assumes that individual rpms have already been built for
# all relevant architectures from the src & spec files in svn.

# When running this script to package xcat-dep:
#  - You need to install gsa-client on the build machine.
#  - You probably want to put root's pub key from the build machine onto sourceforge for
#    the upload user listed below, so you don't have to keep entering pw's.  You can do this
#    at https://sourceforge.net/account/ssh
#  - Also make sure createrepo is installed on the build machine

# Usage:  builddep.sh [attr=value attr=value ...]
#		DESTDIR=<dir> - the dir to place the dep tarball in.  The default is ../../../xcat-dep, relative
#					to where this script is located.
# 		UP=0 or UP=1 - override the default upload behavior 

# you can change this if you need to
UPLOADUSER=bp-sawyers

GSA=/gsa/pokgsa/projects/x/xcat/build/linux/xcat-dep
export HOME=/root		# This is so rpm and gpg will know home, even in sudo

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	declare `echo $i|cut -d '=' -f 1`=`echo $i|cut -d '=' -f 2`
done

if [ ! -d $GSA ]; then
	echo "builddep:  It appears that you do not have gsa installed to access the xcat-dep pkgs."
	exit 1;
fi
set -x
cd `dirname $0`
XCATCOREDIR=`/bin/pwd`
if [ -z "$DESTDIR" ]; then
	DESTDIR=../../../xcat-dep
fi

# Sync from the GSA master copy of the dep rpms
mkdir -p $DESTDIR/xcat-dep
rsync -ilrtpu --delete $GSA/ $DESTDIR/xcat-dep

# Get gpg keys in place
mkdir -p $HOME/.gnupg
for i in pubring.gpg secring.gpg trustdb.gpg; do
	if [ ! -f $HOME/.gnupg/$i ] || [ `wc -c $HOME/.gnupg/$i|cut -f 1 -d' '` == 0 ]; then
		rm -f $HOME/.gnupg/$i
		cp $GSA/../keys/$i $HOME/.gnupg
		chmod 600 $HOME/.gnupg/$i
	fi
done

# Tell rpm to use gpg to sign
MACROS=$HOME/.rpmmacros
if ! $GREP -q '%_signature gpg' $MACROS 2>/dev/null; then
	echo '%_signature gpg' >> $MACROS
fi
if ! $GREP -q '%_gpg_name' $MACROS 2>/dev/null; then
	echo '%_gpg_name Jarrod Johnson' >> $MACROS
fi

# Sign the rpms that are not already signed.  The "standard input reopened" warnings are normal.
cd $DESTDIR/xcat-dep
$XCATCOREDIR/build-utils/rpmsign.exp `find . -type f -name '*.rpm'`

# Create the repodata dirs
for i in `find -mindepth 2 -maxdepth 2 -type d `; do
	createrepo $i
	rm -f $i/repodata/repomd.xml.asc
	gpg -a --detach-sign $i/repodata/repomd.xml
	if [ ! -f $i/repodata/repomd.xml.key ]; then
		cp $GSA/../keys/repomd.xml.key $i/repodata
	fi
done

# Get the permissions correct.  Have to have all dirs/files with a group of xcat
# and have them writeable by group, so any member of the xcat can build.
chgrp -R xcat *
chmod -R g+w *

# Build the tarball
#VER=`cat $XCATCOREDIR/Version`
DFNAME=xcat-dep-`date +%Y%m%d%H%M`.tar.bz2
cd ..
tar jcvf $DFNAME xcat-dep
cd xcat-dep

if [ "$UP" == 0 ]; then
 exit 0;
fi

# Upload the dir structure to SF yum area.  Currently we do not have it preserving permissions
# because that gives errors when different users try to do it.
while ! rsync -rlv --delete * $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/xcat-dep/
do : ; done
#ssh jbjohnso@shell1.sf.net "cd /home/groups/x/xc/xcat/htdocs/yum/; rm -rf dep-snap; tar jxvf $DFNAME"

# Upload the tarball to the SF FRS Area
#scp ../$DFNAME $UPLOADUSER@web.sourceforge.net:/home/frs/project/x/xc/xcat/xcat-dep/2.x_Linux/
while ! rsync -v ../$DFNAME $UPLOADUSER,xcat@web.sourceforge.net:/home/frs/project/x/xc/xcat/xcat-dep/2.x_Linux/
do : ; done
