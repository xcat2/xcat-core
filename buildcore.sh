#!/bin/bash

# Build and upload the xcat-core code, on either linux or aix.

# Getting Started:
#  - Clone the xcat-core GitHub repository
#  - On Linux:  make sure createrepo is installed on the build machine
#  - On AIX:  Install openssl and openssh installp pkgs and run updtvpkg.  Install from http://www.perzl.org/aix/ :
#        apr, apr-util, bash, bzip2, db4, expat, gdbm, gettext, glib2, gmp, info, libidn, neon, openssl (won't
#        conflict with the installp version - but i don't think you need this), pcre, perl-DBD-SQLite, perl-DBI,
#        popt, python, readline, rsynce, sqlite, subversion, unixODBC, zlib.  
#        Install wget from http://www-03.ibm.com/systems/power/software/aix/linux/toolbox/alpha.html
#  - Run this script from the xcat-core directory.  It will create the other directories that are needed.
#
# Usage:  buildcore.sh [attr=value attr=value ...]
#    Before running buildcore.sh, you must change the local git repo to the branch you want built, using: git checkout <branch>
#        PROMOTE=1 - if the attribute "PROMOTE" is specified, means an official dot release.  This does not actually build
#                    xcat, just uploads the most recent snap build to http://xcat.org/files/xcat/ .
#                    If not specified, a snap build is assumed, which uploads to http://xcat.org/files/xcat/repos/yum/
#                    or http//xcat.org/files/aix/.
#        PREGA=1 - use this option with PROMOTE=1 on a branch that already has a released dot release, but this build is
#                  a GA candidate build, not to be released yet.  This will result in the tarball being uploaded to
#                  http://xcar.org/files/xcat/repos/yum/
#                  (but the tarball file name will be like a released tarball, not a snap build).  When you are ready to
#                  release this build, use PROMOTE=1 without PREGA
#        BUILDALL=1 - build all rpms, whether they changed or not.  Should be used for snap builds that are in prep for a release.
#        UP=0 or UP=1 - override the default upload behavior 
#        GITUP=<filename> - control which rpms get built by specifying a coregitup file
#        EMBED=<embedded-environment> - the environment for which a minimal version of xcat should be built, e.g. zvm or flex
#        VERBOSE=1 - to see lots of verbose output
#        LOG=<filename> - provide an LOG file option to redirect some output into log file
#        RPMSIGN=0 or RPMSIGN=1 - Sign the RPMs using the keys on GSA, the default is to sign the rpms without RPMSIGN specified

#
# The following environment variables can be modified if you need
#

UPLOADUSER=litingt
USER=xcat
SERVER=xcat.org
FILES_PATH="files"
FRS=/var/www/${SERVER}/${FILES_PATH}
RELEASE=github.com/xcat2/xcat-core/releases

YUMDIR=$FRS
YUMREPOURL="http://${SERVER}/${FILES_PATH}/xcat/repos/yum"

if [ "$1" = "-h"  ] || [ "$1" = "-help"  ] || [ "$1" = "--help"  ]; then
    echo "Usage:"
    echo "      ./buildcore.sh [-h | --help]"
    echo "      ./buildcore.sh [UP=1] [RPMSIGN=1] [EMBED=<embedded-environment>] [COMMITID=<id>] [GITPULL=0]"
    exit 0
fi

# For users to build from source code, simply run ./buildcore.sh
#  1. Do not sign RPM by default
#  2. Build all packages by default
#  3. Do not upload to sourcefore by default
if [ -z "$RPMSIGN" ]; then
    RPMSIGN=0
fi
if [ -z "$BUILDALL" ]; then
    BUILDALL=1
fi
if [ -z "$UP" ]; then
    UP=0
fi

# These are the rpms that should be built for each kind of xcat build
ALLBUILD="perl-xCAT xCAT-client xCAT-server xCAT-test xCAT-buildkit xCAT xCATsn xCAT-genesis-scripts xCAT-SoftLayer xCAT-vlan xCAT-confluent"
ZVMBUILD="perl-xCAT xCAT-server xCAT-UI"
ZVMLINK="xCAT-client xCAT xCATsn"
# xCAT and xCATsn have PCM specific configuration - conserver-xcat, syslinux-xcat
# xCAT-server has PCM specific configuration - RESTAPI(perl-JSON) 
# xCAT-client has PCM specific configuration - getxcatdocs(perl-JSON) 
PCMBUILD="xCAT xCAT-server xCAT-client xCATsn"
PCMLINK="perl-xCAT xCAT-buildkit xCAT-genesis-scripts-x86_64 xCAT-genesis-scripts-ppc64 xCAT-vlan"
# Note: for FSM, the FlexCAT rpm is built separately from gsa/git
FSMBUILD="perl-xCAT xCAT-client xCAT-server"
FSMLINK=""
# If you add more embed cases, also change the if [ -n "$EMBED" ]... below

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
    
        if [ "$(id -u)" == "0" ]; then
        # Get a lock, so can not do 2 builds at once
        exec 8>/var/lock/xcatbld-$REL.lock
        if ! flock -n 8; then
                echo "Can't get lock /var/lock/xcatbld-$REL.lock.  Someone else must be doing a build right now.  Exiting...."
                exit 1
        fi
        # This is so rpm and gpg will know home, even in sudo
        export HOME=/root
        fi
fi

# for the git case, query the current branch and set REL (changing master to devel if necessary)
function setbranch {
    REL=`git name-rev --name-only HEAD`
    if [ "$REL" = "master" ]; then
        REL="devel"
    fi
}

if [ "$REL" = "xcat-core" ]; then    # using git
    GIT=1
    setbranch            # this changes the REL variable
fi

# Set variables based on which type of build we are doing
if [ -n "$EMBED" ]; then
    EMBEDDIR="/$EMBED"
    if [ "$EMBED" = "zvm" ]; then
        EMBEDBUILD=$ZVMBUILD
        EMBEDLINK=$ZVMLINK
    elif [ "$EMBED" = "pcm" ]; then
        EMBEDBUILD=$PCMBUILD
        EMBEDLINK=$PCMLINK
    elif [ "$EMBED" = "fsm" ]; then
        EMBEDBUILD=$FSMBUILD
        EMBEDLINK=$FSMLINK
    else
        echo "Error: EMBED setting $EMBED not recognized."
        exit 2
    fi
else
    EMBEDDIR=""
    EMBEDBUILD=$ALLBUILD
    EMBEDLINK=""
fi

XCATCORE="xcat-core"        # core-snap is a sym link to xcat-core

if [ "$GIT" = "1" ]; then    # using git - need to include REL in the path where we put the built rpms
    #DESTDIR=../../$REL$EMBEDDIR/$XCATCORE
        DESTDIR=$HOME/xcatbuild/$REL$EMBEDDIR/$XCATCORE
else
    #DESTDIR=../..$EMBEDDIR/$XCATCORE
        DESTDIR=$HOME/xcatbuild/..$EMBEDDIR/$XCATCORE
fi
SRCD=core-snap-srpms

# currently aix builds ppc rpms, but someday it should build noarch
if [ "$OSNAME" = "AIX" ]; then
    NOARCH=ppc
    SYSGRP=system
else
    NOARCH=noarch
    SYSGRP=$(id -g)
fi

function setversionvars {
    VER=`cat Version`
    SHORTVER=`cat Version|cut -d. -f 1,2`
    SHORTSHORTVER=`cat Version|cut -d. -f 1`
}


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

# 
# If no pre-defined update file is provided, do a "git pull" to try and detect 
# if anything has changed in the source directories
# 
SOMETHINGCHANGED=0
if [ "$GIT" = "1" ]; then
    # 
    # To enable local sandbox build, GITPULL is disabled by default. 
    #
    if [ "$GITPULL" = "1" ] || [ ${PWD} == *"autobuild"* ]; then
        # TODO: This is really not necessary since the autobuild scripts
        #       are building the xcat code in a new directory each time
        MODIFIED_FILES=`git ls-files --modified | tr '\n' ', '`
        if [ $MODIFIED_FILES ]; then
                echo "The following files have been modified in the local repository: $MODIFIED_FILES..."
                echo "Not a clean build, aborting..."
                exit 3
        fi
        # check if there's any modifications to git current repo
        UNTRACKED_FILES=`git ls-files --others | tr '\n' ', '`
        if [ -n "$UNTRACKED_FILES" ]; then
            echo "The following files are not tracked in git: $UNTRACKED_FILES..."
            echo "Not a clean build, aborting..."
            exit 3
        fi
        if [ -z "$GITUP" ]; then
            if [ ! -z "$COMMITID" ]; then
                echo "git checkout $COMMITID"
                git checkout $COMMITID
                if [[ $? != 0 ]]; then
                    # do not continue so we do not build with old files
                    echo "The 'git checkout' command failed.  Exiting the build."
                    exit 3
                fi
            else
                GITUP=../coregitup
                echo "git pull > $GITUP"
                git pull > $GITUP
                if [[ $? != 0 ]]; then
                    # do not continue so we do not build with old files
                    echo "The 'git pull' command failed.  Exiting the build."
                    exit 3
                fi
            fi
        fi
        if [ -f "$GITUP" ]; then
            if ! $GREP 'Already up-to-date' $GITUP; then
                SOMETHINGCHANGED=1
            fi
        fi
    fi
fi

setversionvars

# Function for making the noarch rpms
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
if [ $SOMETHINGCHANGED == 1 -o "$BUILDALL" == 1 ]; then        # Use to be:  $GREP perl-xCAT $GITUP; then
    if [[ " $EMBEDBUILD " = *\ perl-xCAT\ * ]]; then
        UPLOAD=1
        maker perl-xCAT
    fi
fi
if [ "$OSNAME" = "AIX" ]; then
    # For the 1st one we overwrite, not append
    echo "rpm -Uvh perl-xCAT-$SHORTSHORTVER*rpm" > $DESTDIR/instxcat
fi

# Build the rest of the noarch rpms
for rpmname in xCAT-client xCAT-server xCAT-IBMhpc xCAT-rmc xCAT-UI xCAT-test xCAT-buildkit xCAT-SoftLayer xCAT-vlan xCAT-confluent; do
    if [[ " $EMBEDBUILD " != *\ $rpmname\ * ]]; then continue; fi
    if [ "$OSNAME" = "AIX" -a "$rpmname" = "xCAT-buildkit" ]; then continue; fi  # do not build xCAT-buildkit on aix
    if [ "$OSNAME" = "AIX" -a "$rpmname" = "xCAT-SoftLayer" ]; then continue; fi # do not build xCAT-softlayer on aix
    if [ "$OSNAME" = "AIX" -a "$rpmname" = "xCAT-vlan" ]; then continue; fi      # do not build xCAT-vlan on aix
    if [ "$OSNAME" = "AIX" -a "$rpmname" = "xCAT-confluent" ]; then continue; fi # do not build xCAT-confluent on aix
    if [ "$BUILDALL" == 1 ] || $GREP $rpmname $GITUP;  then
        UPLOAD=1
        maker $rpmname
    fi
    if [ "$OSNAME" = "AIX" ]; then
        if [ "$rpmname" = "xCAT-client" -o "$rpmname" = "xCAT-server" ]; then
            # we do not automatically install the rest of the rpms on AIX
            echo "rpm -Uvh $rpmname-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
        fi
    fi
done

# Build xCAT-genesis-scripts for xcat-core.  xCAT-genesis-base gets built by hand and put in xcat-dep.
# The mknb cmd combines them at install time.
if [ "$OSNAME" != "AIX" ]; then
    if [[ " $EMBEDBUILD " = *\ xCAT-genesis-scripts\ * ]]; then
        if [ "$BUILDALL" == 1 ] || $GREP xCAT-genesis-scripts $GITUP; then
            UPLOAD=1
            ORIGFAILEDRPMS="$FAILEDRPMS"
            ./makerpm xCAT-genesis-scripts x86_64 "$EMBED"
            if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS xCAT-genesis-scripts-x86_64"; fi
            ./makerpm xCAT-genesis-scripts ppc64 "$EMBED"
            if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS xCAT-genesis-scripts-ppc64"; fi
            if [ "$FAILEDRPMS" = "$ORIGFAILEDRPMS" ]; then    # all succeeded
                rm -f $DESTDIR/xCAT-genesis-scripts*rpm
                rm -f $SRCDIR/xCAT-genesis-scripts*rpm
                mv $source/RPMS/noarch/xCAT-genesis-scripts-*rpm $DESTDIR
                mv $source/SRPMS/xCAT-genesis-scripts-*rpm $SRCDIR
            fi
        fi
    fi
fi

# Build the xCAT and xCATsn rpms for all platforms
for rpmname in xCAT xCATsn; do 
    if [[ " $EMBEDBUILD " != *\ $rpmname\ * ]]; then continue; fi
    if [ $SOMETHINGCHANGED == 1 -o "$BUILDALL" == 1 ]; then        # used to be:  if $GREP -E "^[UAD] +$rpmname/" $GITUP; then
        UPLOAD=1
        ORIGFAILEDRPMS="$FAILEDRPMS"
        if [ "$OSNAME" = "AIX" ]; then
            if [ "$rpmname" = "xCAT-OpenStack" ] || [ "$rpmname" = "xCAT-OpenStack-baremetal" ]; then continue; fi         # do not bld openstack on aix
            ./makerpm $rpmname "$EMBED"
            if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS $rpmname"; fi
        else
            for arch in x86_64 ppc64 ppc64le s390x; do
                if [ "$rpmname" = "xCAT-OpenStack" -a "$arch" != "x86_64" ] || [ "$rpmname" = "xCAT-OpenStack-baremetal" -a "$arch" != "x86_64" ] ; then continue; fi         # only bld openstack for x86_64 for now
                ./makerpm $rpmname $arch "$EMBED"
                if [ $? -ne 0 ]; then FAILEDRPMS="$FAILEDRPMS $rpmname-$arch"; fi
            done
        fi
        if [ "$FAILEDRPMS" = "$ORIGFAILEDRPMS" ]; then    # all succeeded
            rm -f $DESTDIR/$rpmname-$SHORTSHORTVER*rpm
            rm -f $SRCDIR/$rpmname-$SHORTSHORTVER*rpm
            mv $source/RPMS/*/$rpmname-$VER*rpm $DESTDIR
            mv $source/SRPMS/$rpmname-$VER*rpm $SRCDIR
        fi
    fi
done
# no longer put in xCAT-rmc
if [ "$OSNAME" = "AIX" ]; then
    echo "rpm -Uvh xCAT-$SHORTSHORTVER*rpm" >> $DESTDIR/instxcat
fi

# Make sym links in the embed subdirs for the rpms we do not have to build special
if [ -n "$EMBED" -a -n "$EMBEDLINK" ]; then
    cd $DESTDIR
    maindir="../../$XCATCORE"
    for rpmname in $EMBEDLINK; do
        if [ "$rpmname" = "xCAT" -o "$rpmname" = "xCATsn" ]; then
            if [ "$EMBED" = "zvm" ]; then
                echo "Creating link for $rpmname-$SHORTSHORTVER"'*.s390x.rpm'
                rm -f $rpmname-$SHORTSHORTVER*rpm
                ln -s $maindir/$rpmname-$SHORTSHORTVER*.s390x.rpm .
            fi
        else
            echo "Creating link for $rpmname-$SHORTSHORTVER"'*rpm'
            rm -f $rpmname-$SHORTSHORTVER*rpm
            ln -s $maindir/$rpmname-$SHORTSHORTVER*rpm .
        fi
    done
    cd - >/dev/null
fi


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
WGET_CMD="wget"
if [ ! -z ${LOG} ]; then 
    WGET_CMD="wget -o ${LOG}"
fi

# get gpg keys in place
if [ "$OSNAME" != "AIX" ]; then
    if [ -z "$RPMSIGN" -o "$RPMSIGN" == "1" ]; then
    mkdir -p $HOME/.gnupg
    for i in pubring.gpg secring.gpg trustdb.gpg; do
        if [ ! -f $HOME/.gnupg/$i ] || [ `wc -c $HOME/.gnupg/$i|cut -f 1 -d' '` == 0 ]; then
            rm -f $HOME/.gnupg/$i
            ${WGET_CMD} -P $HOME/.gnupg $GSA/keys/$i
            chmod 600 $HOME/.gnupg/$i
        fi
    done
    # tell rpm to use gpg to sign
    MACROS=$HOME/.rpmmacros
    if ! $GREP '%_signature gpg' $MACROS 2>/dev/null; then
        echo '%_signature gpg' >> $MACROS
    fi
    if ! $GREP '%_gpg_name' $MACROS 2>/dev/null; then
        echo '%_gpg_name xCAT Security Key' >> $MACROS
    fi
    echo "Signing RPMs..."
    build-utils/rpmsign.exp `find $DESTDIR -type f -name '*.rpm'` | grep -v -E '(already contains identical signature|was already signed|rpm --quiet --resign|WARNING: standard input reopened)'
    build-utils/rpmsign.exp $SRCDIR/*rpm | grep -v -E '(already contains identical signature|was already signed|rpm --quiet --resign|WARNING: standard input reopened)'
    createrepo --checksum sha $DESTDIR            # specifying checksum so the repo will work on rhel5
    createrepo --checksum sha $SRCDIR
    rm -f $SRCDIR/repodata/repomd.xml.asc
    rm -f $DESTDIR/repodata/repomd.xml.asc
    gpg -a --detach-sign $DESTDIR/repodata/repomd.xml
    gpg -a --detach-sign $SRCDIR/repodata/repomd.xml
    if [ ! -f $DESTDIR/repodata/repomd.xml.key ]; then
        ${WGET_CMD} -q -P $DESTDIR/repodata $GSA/keys/repomd.xml.key
    fi
    if [ ! -f $SRCDIR/repodata/repomd.xml.key ]; then
        ${WGET_CMD} -P $SRCDIR/repodata $GSA/keys/repomd.xml.key
    fi
   else
     createrepo --checksum sha $DESTDIR
     createrepo --checksum sha $SRCDIR 
   fi
fi

# set group and permissions correctly on the built rpms
if [ "$OSNAME" = "AIX" ]; then
    chmod +x $DESTDIR/instxcat
fi
chgrp -R $SYSGRP $DESTDIR
chmod -R g+w $DESTDIR
chgrp -R $SYSGRP $SRCDIR
chmod -R g+w $SRCDIR

else        # end of very long if-not-promote
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
if [[ $REPOFILE == "xCAT-*.repo" ]]; then 
    echo "ERROR: For xcat-dep, please execute $0 in the correct <os>/<arch> subdirectory"
    exit 1
fi
#
# default to RHEL yum, if doesn't exist try Zypper
#
DIRECTORY="/etc/yum.repos.d"
if [[ ! -d ${DIRECTORY} ]]; then                                                                            
    DIRECTORY="/etc/zypp/repos.d"                                                                           
fi
sed -e 's|baseurl=.*|baseurl=file://'"`pwd`"'|' $REPOFILE | sed -e 's|gpgkey=.*|gpgkey=file://'"`pwd`"'/repodata/repomd.xml.key|' > ${DIRECTORY}/$REPOFILE
cd -
EOF2
chmod 775 mklocalrepo.sh

fi    # not AIX

# Build the tarball
cd ..
if [ -n "$VERBOSEMODE" ]; then
    verboseflag="-v"
else
    verboseflag=""
fi
echo "Creating $(dirname $DESTDIR)/$TARNAME ..."
if [[ -e $TARNAME ]]; then
    mkdir -p previous
    mv -f $TARNAME previous
fi
if [ "$OSNAME" = "AIX" ]; then
    tar $verboseflag -hcf ${TARNAME%.gz} $XCATCORE
    gzip ${TARNAME%.gz}
else
    tar $verboseflag -hjcf $TARNAME $XCATCORE
fi
chgrp $SYSGRP $TARNAME
chmod g+w $TARNAME

# Decide whether to upload or not
if [ -n "$UP" ] && [ "$UP" == 0 ]; then
    exit 0;
fi
#else we will continue

# Upload the individual RPMs to xcat.org 
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
    while [ $((i+=1)) -le 5 ] && ! rsync -urLv --delete $CORE $USER@$SERVER:$YUMDIR/$YUM/$REL$EMBEDDIR/
    do : ; done
fi

# Upload the individual source RPMs to xcat.org 
i=0
echo "Uploading src RPMs from $SRCD to $YUMDIR/$YUM/$REL$EMBEDDIR/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync -urLv --delete $SRCD $USER@$SERVER:$YUMDIR/$YUM/$REL$EMBEDDIR/
do : ; done

# Upload the tarball to xcat.org 
if [ "$PROMOTE" = 1 -a "$REL" != "devel" -a "$PREGA" != 1 ]; then
    # upload tarball to FRS area
    i=0
    echo "Uploading $TARNAME to $FRS/xcat/$REL.x_$OSNAME$EMBEDDIR/ ..."
    while [ $((i+=1)) -le 5 ] && ! rsync -v --force $TARNAME $USER@$SERVER:$FRS/xcat/$REL.x_$OSNAME$EMBEDDIR/
    do : ; done

    # upload tarball to github when we release the build.
    i=0
    echo "Uploading $TARNAME to https://github.com/xcat2/xcat-core/releases ..."
    while [ $((i+=1)) -le 5 ] && ! rsync -v --force $TARNAME $UPLOADUSER@$RELEASE/
    do : ; done
else
    i=0
    echo "Uploading $TARNAME to $YUMDIR/$YUM/$REL$EMBEDDIR/ ..."
    while [ $((i+=1)) -le 5 ] && ! rsync -v --force $TARNAME $USER@$SERVER:$YUMDIR/$YUM/$REL$EMBEDDIR/
    do : ; done
fi
