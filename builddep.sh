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

if [ "$OSNAME" == "AIX" ]; then
	DFNAME=dep-aix-`date +%Y%m%d%H%M`.tar.gz
	GSA=/gsa/pokgsa/projects/x/xcat/build/aix/xcat-dep
else
	DFNAME=xcat-dep-`date +%Y%m%d%H%M`.tar.bz2
	GSA=/gsa/pokgsa/projects/x/xcat/build/linux/xcat-dep
fi

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
                echo "Error: Regular 'noarch' file $file found in 'arch' directory. Expected a link."
            done

            # Find broken links file
            for file in `find $arch -xtype l -name "*noarch.rpm"`; do
                ERROR=1
                echo "Error: Broken link file $file"
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
            echo "Someone links to file: ${var} "
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
            echo "Warning: no one links to real file: $GSA/$file"
        fi
    done

    if [[ ${ERROR} -eq 1 ]]; then
        echo -e "\nErrors found verifying files. Rerun this secript with CHECK=0 to skip file verification."
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

if [ "$OSNAME" != "AIX" ]; then
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

	# Sign the rpms that are not already signed.  The "standard input reopened" warnings are normal.
	echo "===> Signing RPMs..."
	$XCATCOREDIR/build-utils/rpmsign.exp `find . -type f -name '*.rpm'` | grep -v -E '(already contains identical signature|was already signed|rpm --quiet --resign|WARNING: standard input reopened)'

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

	# Modify xcat-dep.repo files to point to the correct place
	echo "===> Modifying the xcat-dep.repo files to point to the correct location..."

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
fi

if [ "$OSNAME" == "AIX" ]; then
	# Build the instoss file ------------------------------------------

	cat >instoss << 'EOF'
#!/bin/ksh
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# xCAT on AIX - prerequisite install script
cd `dirname $0`
PERLVER=`perl -v|grep 'This is perl'|cut -d' ' -f 4`
if [ "$PERLVER" == "v5.8.2" ]; then
        OSVER='5.3'
elif [ "$PERLVER" == "v5.8.8" ]; then
        OSVER='6.1'
        aixver=`lslpp -lc|grep 'bos.rte:'|head -1|cut -d: -f3`
                if [[ $aixver < '6.1.9.0' ]]; then
                        AIX61Y=0
                else
                        AIX61Y=1
                fi
elif [ "$PERLVER" == "v5.10.1" ]; then
        OSVER='7.1'
        aixver=`lslpp -lc|grep 'bos.rte:'|head -1|cut -d: -f3`
		if [[ $aixver < '7.1.3.0' ]]; then
			AIX71L=0
		else
			AIX71L=1
		fi

else
        echo "Error: the perl version of '$PERLVER' is not one that instoss understands.  Exiting..."
        exit 2
fi
cd $OSVER
# Have to install rpms 1 at a time, since some may be already installed.
# The only interdependency between the dep rpms so far is that net-snmp requires bash, and
# pyodbc requires unixODBC.  (The bash dependency is taken care of automatically because it
# comes earlier in the alphabet.)

# first run /usr/sbin/updtvpkg to make sure any installp software is
# registered with RPM.
echo "Running updtvpkg. This could take a few minutes."
/usr/sbin/updtvpkg
echo "updtvpkg has completed."

# unixODBC is required by pyodbc, so install it first
rpm -Uvh unixODBC*
# Now install the bulk of the rpms, one at a time, in case some are already installed
for i in `ls *.rpm|grep -v -E '^tcl-|^tk-|^expect-|^unixODBC-|^xCAT-UI-deps|^perl-DBD-DB2Lite|^net-snmp'`; do
	if [ "$i" == "perl-Net-DNS-0.66-1.aix5.3.ppc.rpm" ]; then
		opts="--nodeps"
	else
		opts=""
	fi

	# On 7.1L and 6.1Y we need a newer version of perl-Net_SSLeay.pm
	if [[ $AIX71L -eq 1 || $AIX61Y -eq 1 ]]; then
		if [[ $i == perl-Net_SSLeay.pm-1.30-* ]]; then continue; fi 	# skip the old rpm
	else
		if [[ $i == perl-Net_SSLeay.pm-1.55-* ]]; then continue; fi 	# skip the new rpm
	fi
	
	echo rpm -Uvh $opts $i
	rpm -Uvh $opts $i
done
# Have to upgrade all of the net-snmp rpms together because they depend on each other.
# Also, they require bash, so do it after the loop, rather than before
rpm -Uvh net-snmp*

EOF
# end of instoss file content ---------------------------------------------


	chmod +x instoss
fi

# Get the permissions and group correct
if [ "$OSNAME" == "AIX" ]; then
	# AIX
	SYSGRP=system
	YUM=aix
	FRSDIR='2.x_AIX'
else
	# Linux
	SYSGRP=root
	YUM=yum/devel
	FRSDIR='2.x_Linux'
fi
chgrp -R -h $SYSGRP *
chmod -R g+w *

# Change permission on all repodata files to be readable by all
chmod a+r */*/repodata/*.gz
chmod a+r */*/repodata/*.bz2

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
if [ "$OSNAME" == "AIX" ]; then
	tar $verbosetar -cf ${DFNAME%.gz} xcat-dep
	rm -f $DFNAME
	gzip ${DFNAME%.gz}
else
	# Linux
	tar $verbosetar -jcf $DFNAME xcat-dep
fi

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

