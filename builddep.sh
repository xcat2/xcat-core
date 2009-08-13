#!/bin/sh
# Package up all the xCAT open source dependencies, setting up yum repos and
# also tar it all up.  This assumes that individual rpms have already been built for
# all relevant architectures from the src & spec files in svn.

# When running this script to package xcat-dep:
#  - run it from the root dir of where all the built dep rpms are
#  - use sudo to execute it with root privilege:  sudo builddep.sh
#  - the root userid's home dir on the build machine should have:
#    - .rpmmacros that contains values for %_signature and %_gpg_name
#    - .gnupg dir with appropriate files

# you can change this if you need to
UPLOADUSER=bp-sawyers

if [ ! -d rh5 ]; then
	echo "builddep:  It appears that you are not running this from the top level of the xcat-dep directory structure."
	exit 1;
fi
XCATCOREDIR=`dirname $0`
#export DESTDIR=.
UPLOAD=1
if [ "$1" == "NOUPLOAD" ]; then
   UPLOAD=0
fi
set -x

# Sign the rpms that are not already signed.  The "standard input reopened" warnings are normal.
$XCATCOREDIR/build-utils/rpmsign.exp `find . -type f -name '*.rpm'`

# Create the repodata dirs
for i in `find -mindepth 2 -maxdepth 2 -type d `; do createrepo $i; done

# Get the permissions correct.  Have to have all dirs/files with a group of xcat
# and have them writeable by group, so any member of the xcat can build.
chgrp -R xcat *
chmod -R g+w *

# Build the tarball
VER=`cat $XCATCOREDIR/Version`
DFNAME=xcat-dep-$VER-`date +%Y%m%d%H%M`.tar.bz2
cd ..
tar jcvf $DFNAME xcat-dep
cd xcat-dep

if [ $UPLOAD == 0 ]; then
 exit 0;
fi

# Upload the dir structure to SF yum area.  Currently we do not have it preserving permissions
# because that gives errors when different users try to do it.
while ! rsync -rlv --delete * $UPLOADUSER,xcat@web.sourceforge.net:htdocs/yum/xcat-dep/
do : ; done
#ssh jbjohnso@shell1.sf.net "cd /home/groups/x/xc/xcat/htdocs/yum/; rm -rf dep-snap; tar jxvf $DFNAME"

# Upload the tarball to the SF FRS Area
#scp ../$DFNAME "$UPLOADUSER@web.sourceforge.net:/home/frs/project/x/xc/xcat/xcat-dep/2.x Linux/"
while ! rsync -v ../$DFNAME "$UPLOADUSER,xcat@web.sourceforge.net:/home/frs/project/x/xc/xcat/xcat-dep/2.x Linux/"
do : ; done
