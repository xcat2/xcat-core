#!/bin/sh

#
# Package up all the xCAT open source dependencies
# - creating the yum repos
# - tar up the deps package
#
# This script assumes that the individual rpms have already been compiled
# for the relevant architectures from the src & spec files in git.
#
# Dependencies:
# - createrepo command needs to be present on the build machine
#
# Usage:  builddep.sh [attr=value attr=value ...]
#       DESTDIR=<dir> - the dir to place the dep tarball in.  The default is ../../xcat-dep-build,
#                       relative to where this script is located.
#       UP=0 or UP=1  - override the default upload behavior
#       FRSYUM=0      - put the directory of individual rpms in the project web area instead
#                       of the FRS area.
#       CHECK=0 or 1  - verify proper file location and links. Default is to check.
#                       Verifies all noarch files in ..../<OS>/<ARCH>/ are links
#                       Verifies no broken link files in ..../<OS>/<ARCH>/
#                       Verifies there are no multiple, real (non-link) files with the same name
#                       Verifies all real (non-link) files have a link to it
#                       Verifies all files have read permission set for all
#       VERBOSE=1     - Set to 1 to see more VERBOSE output

# This script should only be run on RPM based machines 
# This test is not foolproof, but at least tries to detect
if [ `/bin/rpm -q -f /bin/rpm >/dev/null 2>&1; echo $?` != 0 ]; then
	echo "ERROR: This script should only be executed on a RPM based Operation System."
	exit 1
fi

# you can change this if you need to
USER=xcat
TARGET_MACHINE=xcat.org

BASE_GSA=/gsa/pokgsa/projects/x/xcat/build
GSA=$BASE_GSA/linux/xcat-dep

FRS=/var/www/xcat.org/files/xcat
OSNAME=$(uname)

UP=0
CHECK=1
# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	# upper case the variable name
	varstring=`echo "$i"|cut -d '=' -f 1|tr [a-z] [A-Z]`=`echo "$i"|cut -d '=' -f 2`
	export $varstring
done

DFNAME=xcat-dep-`date +%Y%m%d%H%M`.tar.bz2

if [ ! -d $GSA ]; then
	echo "ERROR: This script is intended to be used by xCAT development..."
	echo "ERROR: The GSA directory ($GSA) directory does not appear to be mounted, cannot continue!"
	exit 1
fi

REQPKG=("rpm-sign" "createrepo")
for pkg in ${REQPKG[*]}; do
	if [ `rpm -q $pkg >> /dev/null; echo $?` != 0 ]; then
		echo "ERROR: $pkg is required to successfully create the xcat-deps package. Install and rerun."
		exit 1
	else
		echo "Checking for package=$pkg ..."
	fi
done

GNU_KEYDIR="$HOME/.gnupg"
MACROS=$HOME/.rpmmacros
if [[ -d ${GNU_KEYDIR} ]]; then
	echo "ERROR: The gnupg key dir: $GNU_KEYDIR exists, it will be overwitten. Stop."
	echo "ERROR:    To continue, remove it and rerun the script."
	exit 1
fi

# set grep to quiet by default
GREP="grep -q"
if [ "$VERBOSE" = "1" -o "$VERBOSE" = "yes" ]; then
	set -x
	VERBOSEMODE=1
	GREP="grep"
fi

# this is needed only when we are transitioning the yum over to frs
if [ "$FRSYUM" != 0 ]; then
	YUMDIR="$FRS/repos"
else
	YUMDIR=htdocs
fi

SCRIPT=$(readlink -f "$0")
XCATCOREDIR=$(dirname "$SCRIPT")
echo "INFO: Running script from here: $XCATCOREDIR ..."

cd $XCATCOREDIR 
if [ -z "$DESTDIR" ]; then
	if [[ $XCATCOREDIR == *"xcat2_autobuild_daily_builds"* ]]; then
		# This shows we are in the daily build environment path, create the 
		# deps package at the top level of the build directory
		DESTDIR=../../xcat-dep-build
	else
		# This means we are building in some other clone of xcat-core, 
		# so just place the destination one level up.
		DESTDIR=../xcat-dep-build
	fi
fi

echo "INFO: Target package name: $DFNAME"
echo "INFO: Target package will be created here: $XCATCOREDIR/$DESTDIR"

# Create a function to check the return code, 
# if non-zero, we should stop or unexpected things may happen 
function checkrc {
    if [[ $? != 0  ]]; then
        echo "[checkrc] non-zero return code, exiting..." 
        exit  1
    fi
}

# Verify files in $GSA
if [[ ${CHECK} -eq 1 ]]; then
    ERROR=0
    LINKED_TO_FILES_ARRAY=[]
    counter=0
    OSes=`find $GSA -maxdepth 1 -mindepth 1 -type d`
    for os in $OSes; do
        ARCHes=`find $os -maxdepth 1 -mindepth 1 -type d`
        for arch in $ARCHes; do

            # Find regular noarch.rpm files in <OS>/<ARCH> directory
            for file in `find $arch -type f -name "*noarch.rpm"`; do
                ERROR=1
                echo -e "\nError: Regular 'noarch' file $file found in 'arch' directory. Expected a link."
            done

            # Find broken links file
            for file in `find $arch -xtype l -name "*noarch.rpm"`; do
                ERROR=1
                echo -e "\nError: Broken link file $file"
            done

            # Save a link of everything being linked to for later use
            for link_file in `find $arch -type l -name "*.rpm"`; do
               LINKED_TO_FILE=`realpath --relative-to=$GSA $link_file`
               LINKED_TO_FILES_ARRAY[$counter]=$LINKED_TO_FILE
               counter=$counter+1
            done


        done
    done

    # Find identical files in $GSA and $GSA/<OS> directory
    for short_file in $GSA/*.rpm; do
        basename=$(basename -- "$short_file")
        DUP_FILES=`find $GSA/*/ -type f -name $basename`
        if [[ ! -z $DUP_FILES ]]; then
            ERROR=1
            echo -e "\nError: Multiple real files with the same name found ($basename):"
            for dup_file in `find $GSA -type f -name $basename`; do
                ls -l $dup_file
            done
        fi
    done

    if [ -n "$VERBOSEMODE" ]; then
        # In verbose mode print contents of array containing all the files someone links to from <OS>/<ARCH>
        for var in "${LINKED_TO_FILES_ARRAY[@]}"; do
            echo "Symlink detected to file: ${var} "
        done
    fi

    echo " "
    # Find all files no one links to
    REAL_FILES=`find $GSA/* -maxdepth 1 -type f -name "*.rpm" | cut -d / -f 10,11 --output-delimiter="/"`
    for file in $REAL_FILES; do
        FOUND=0
        for used_link in "${LINKED_TO_FILES_ARRAY[@]}"; do
            if [[ $file == $used_link ]]; then
                FOUND=1
                break
            fi
        done
        if [[ ${FOUND} -eq 0 ]]; then
            echo "Warning: No symlinks to file: $GSA/$file"
        fi
    done

    # Find files that have read permission missing for "all"
    MISSING_PERMISSION=`find $GSA/* -type f -not -perm -444`
    for file in $MISSING_PERMISSION; do
        echo "Verify permission for file: "
        echo " " $(ls -l $file)
        ERROR=1
    done


    if [[ ${ERROR} -eq 1 ]]; then
        echo -e "\nErrors found verifying files. Rerun this script with CHECK=0 to skip file verification."
        exit 1
    fi
fi

WORKING_TARGET_DIR="${DESTDIR}/xcat-dep"
# Sync from the GSA master copy of the dep rpms
mkdir -p ${WORKING_TARGET_DIR}
checkrc

# Copy over the xcat-dep from master staging area on GSA to the local directory here 
echo "Syncing RPMs from $GSA/ to ${WORKING_TARGET_DIR} ..."
rsync -ilrtpu --delete $GSA/ ${WORKING_TARGET_DIR}
checkrc
ls ${WORKING_TARGET_DIR}
cd ${WORKING_TARGET_DIR}

# add a comment to indicate the latest xcat-dep tar ball name
sed -i -e "s#REPLACE_LATEST_SNAP_LINE#The latest xcat-dep tar ball is ${DFNAME}#g" README

# Get gpg keys in place
mkdir -p ${GNU_KEYDIR}
checkrc
for i in pubring.gpg secring.gpg trustdb.gpg; do
	if [ ! -f ${GNU_KEYDIR}/$i ] || [ `wc -c ${GNU_KEYDIR}/$i|cut -f 1 -d' '` == 0 ]; then
		rm -f ${GNU_KEYDIR}/$i
		cp $GSA/../keys/$i ${GNU_KEYDIR}
		chmod 600 ${GNU_KEYDIR}/$i
	fi
done

# Tell rpm to use gpg to sign
if ! $GREP -q '%_signature gpg' $MACROS 2>/dev/null; then
	echo '%_signature gpg' >> $MACROS
fi
if ! $GREP -q '%_gpg_name' $MACROS 2>/dev/null; then
	echo '%_gpg_name xCAT Automatic Signing Key' >> $MACROS
fi

# Sign the rpms that are not already signed. The "standard input reopened" warnings are normal.
# First, sign all non RH9 RPMS with DEFAULT algorithm, if running this script on RH7, most likely it will be SHA1
echo "===> Signing RPMs with DEFAULT algorithm..."
$XCATCOREDIR/build-utils/rpmsign.exp `find . -type f -name '*.rpm' ! -path './rh9/*'` | grep -v -E '(already contains identical signature|was already signed|rpm --quiet --resign|WARNING: standard input reopened)'

# Update $MACROS file so that RPMS will be signed with SHA256 algorithm
if ! $GREP -q '%_gpg_sign_cmd' $MACROS 2>/dev/null; then
	echo '%__gpg_sign_cmd %{__gpg} gpg --force-v3-sigs --batch --verbose --no-armor --passphrase-fd 3 --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}' >> $MACROS
fi

# Second, sign all RH9 RPMS with SHA256 algorithm
echo "===> Signing RH9 RPMs with SHA265 algorithm..."
$XCATCOREDIR/build-utils/rpmsign.exp `find rh9 -type f -name '*.rpm'` | grep -v -E '(already contains identical signature|was already signed|rpm --quiet --resign|WARNING: standard input reopened)'

# Remove SHA256 algorithm statement from $MACROS file, back to DEFAULT
sed -i '/__gpg_sign_cmd/d' $MACROS

# Create the repodata dirs
echo "===> Creating repodata directories..."
for i in `find -mindepth 2 -maxdepth 2 -type d `; do
	if [ -n "$VERBOSEMODE" ]; then
		createrepo $i            # specifying checksum so the repo will work on rhel5
	else
		createrepo $i >/dev/null
	fi
	rm -f $i/repodata/repomd.xml.asc
	gpg -a --detach-sign --default-key 5619700D $i/repodata/repomd.xml
	if [ ! -f $i/repodata/repomd.xml.key ]; then
		cp $GSA/../keys/repomd.xml.key $i/repodata
	fi
done

echo "===> Making sure that the mklocalrepo.sh file contains execute permission ..." 
ls -ltr ${XCATCOREDIR}/${WORKING_TARGET_DIR}/mklocalrepo.sh
if [[ ! -x "${XCATCOREDIR}/${WORKING_TARGET_DIR}/mklocalrepo.sh" ]]; then
	echo "===> --- found not execute, changing +x ..."
	chmod +x ${XCATCOREDIR}/${WORKING_TARGET_DIR}/mklocalrepo.sh
fi

echo "===> Checking if 'replacelinks' is in the xcat-deps, removing if there ..." 
if [[ -f ${XCATCOREDIR}/${WORKING_TARGET_DIR}/replacelinks ]]; then
	rm -f ${XCATCOREDIR}/${WORKING_TARGET_DIR}/replacelinks
fi

# Get the permissions and group correct
SYSGRP=root
YUM=yum/devel
FRSDIR='2.x_Linux'
chgrp -R -h $SYSGRP *
chmod -R g+w *

# Change permission on all repodata files to be readable by all
chmod a+rx */*/repodata
chmod a+r */*/repodata/*

TARBALL_WORKING_DIR="${XCATCOREDIR}/${DESTDIR}"
echo "===> Building the tarball at: ${TARBALL_WORKING_DIR} ..."
#
# Want to stay one level above xcat-dep so that the script 
# can rsync the directory up to xcat.org. 
#
# DO NOT CHANGE DIRECTORY AFTER THIS POINT!!
#

cd ${TARBALL_WORKING_DIR}

verbosetar=""
if [ -n "$VERBOSEMODE" ]; then
	verbosetar="-v"
fi

echo "===> Creating $DFNAME ..."
tar $verbosetar -jcf $DFNAME xcat-dep
chmod a+r $DFNAME


# Modify all xcat-dep.repo files to point to the correct place: $YUM
echo "===> Modifying the xcat-dep.repo files to point to the correct 'yum/devel' location..."
find ${WORKING_TARGET_DIR} -type f -name "xcat-dep.repo" -exec sed -i s#/yum/xcat-dep#/${YUM}/xcat-dep#g {} \;

if [[ ${UP} -eq 0 ]]; then
	echo "Upload not being done, set UP=1 to upload to xcat.org"
	exit 0;
fi

# Upload the directory structure to xcat.org yum area (xcat/repos/yum).
if [ "$FRSYUM" != 0 ]; then
	links="-L"	# FRS does not support rsyncing sym links
else
	links="-l"
fi

i=0
echo "Uploading the xcat-deps RPMs from xcat-dep to RPMs from xcat-dep to $YUMDIR/$YUM/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync $links -ruv --delete xcat-dep $USER@$TARGET_MACHINE:$YUMDIR/$YUM/
do : ; done

# Upload the tarball to the xcat.org FRS Area
i=0
echo "Uploading $DFNAME to $FRS/xcat-dep/$FRSDIR/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync -v $DFNAME  $USER@$TARGET_MACHINE:$FRS/xcat-dep/$FRSDIR/
do : ; done

# Upload the README to the xcat.org FRS Area
i=0
cd xcat-dep
echo "Uploading README to $FRS/xcat-dep/$FRSDIR/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync -v README  $USER@$TARGET_MACHINE:$FRS/xcat-dep/$FRSDIR/
do : ; done

# For some reason the README is not updated
echo "Uploading README to $YUMDIR/$YUM/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync -v README  $USER@$TARGET_MACHINE:$YUMDIR/$YUM/
do : ; done

