# The shell is commented out so that it will run in bash on linux and ksh on aix
#  !/bin/sh
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
#       FRSYUM=0 - put the directory of individual rpms in the project web area instead of the FRS area.
#		VERBOSE=1 - to see lots of verbose output

# you can change this if you need to
UPLOADUSER=bp-sawyers

FRS=/home/frs/project/x/xc/xcat
OSNAME=$(uname)

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	# upper case the variable name
	varstring=`echo "$i"|cut -d '=' -f 1|tr [a-z] [A-Z]`=`echo "$i"|cut -d '=' -f 2`
	export $varstring
done
if [ "$VERBOSE" = "1" -o "$VERBOSE" = "yes" ]; then
	set -x
	VERBOSEMODE=1
fi

if [ "$OSNAME" == "AIX" ]; then
	GSA=/gsa/pokgsa/projects/x/xcat/build/aix/xcat-dep
else
	GSA=/gsa/pokgsa/projects/x/xcat/build/linux/xcat-dep
	export HOME=/root		# This is so rpm and gpg will know home, even in sudo
fi

# this is needed only when we are transitioning the yum over to frs
YUMREPOURL1="http://xcat.sourceforge.net/yum"
YUMREPOURL2="https://sourceforge.net/projects/xcat/files/yum"
if [ "$FRSYUM" != 0 ]; then
	YUMDIR=$FRS
	YUMREPOURL="$YUMREPOURL2"
else
	YUMDIR=htdocs
	YUMREPOURL="$YUMREPOURL1"
fi

if [ -n "$VERBOSEMODE" ]; then
	GREP=grep
else
	GREP="grep -q"
fi

if [ ! -d $GSA ]; then
	echo "builddep:  It appears that you do not have gsa installed to access the xcat-dep pkgs."
	exit 1;
fi
cd `dirname $0`
XCATCOREDIR=`/bin/pwd`
if [ -z "$DESTDIR" ]; then
	DESTDIR=../../../xcat-dep
fi

# Sync from the GSA master copy of the dep rpms
mkdir -p $DESTDIR/xcat-dep
echo "Syncing RPMs from $GSA/ to $DESTDIR/xcat-dep ..."
rsync -ilrtpu --delete $GSA/ $DESTDIR/xcat-dep
cd $DESTDIR/xcat-dep

if [ "$OSNAME" != "AIX" ]; then
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
	echo "Signing RPMs..."
	$XCATCOREDIR/build-utils/rpmsign.exp `find . -type f -name '*.rpm'` | grep -v -E '(already contains identical signature|was already signed|rpm --quiet --resign|WARNING: standard input reopened)'

	# Create the repodata dirs
	echo "Creating repodata directories..."
	for i in `find -mindepth 2 -maxdepth 2 -type d `; do
		if [ -n "$VERBOSEMODE" ]; then
			createrepo --checksum sha $i            # specifying checksum so the repo will work on rhel5
		else
			createrepo --checksum sha $i >/dev/null
		fi
		rm -f $i/repodata/repomd.xml.asc
		gpg -a --detach-sign $i/repodata/repomd.xml
		if [ ! -f $i/repodata/repomd.xml.key ]; then
			cp $GSA/../keys/repomd.xml.key $i/repodata
		fi
	done

	# Modify xCAT-dep.repo files to point to the correct place
	if [ "$FRSYUM" != 0 ]; then
		newurl="$YUMREPOURL2"
		oldurl="$YUMREPOURL1"
	else
		newurl="$YUMREPOURL1"
		oldurl="$YUMREPOURL2"
	fi
	sed -i -e "s|=$oldurl|=$newurl|g" `find . -name "xCAT-dep.repo" `
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
elif [ "$PERLVER" == "v5.10.1" ]; then
        OSVER='7.1'
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

rpm -Uvh unixODBC*
for i in `ls *.rpm|grep -v -E '^tcl-|^tk-|^expect-|^unixODBC-|^xCAT-UI-deps|^perl-DBD-DB2Lite'`; do
	if [ "$i" == "perl-Net-DNS-0.66-1.aix5.3.ppc.rpm" ]; then
		opts="--nodeps"
	else
		opts=""
	fi
	
	# just in case we need it sometime, this next if stmt would mean: if it does not start with perl-DBD-DB2
	#if [ "${i#perl-DBD-DB2}" == "$i" ]; then
	
	echo rpm -Uvh $opts $i
	rpm -Uvh $opts $i
done
# don't try to install tcl, tk, or expect if they are already installed!
# this section about expect/tcl/tk can be removed once 2.8 releases, because 2.8 no longer requires expect
lslpp -l | grep expect.base > /dev/null 2>&1
if [ $? -gt 0 ]; then
	if [ "$OSVER" == "5.3" ]; then
		for i in tcl-*.rpm tk-*.rpm expect-*.rpm; do
			echo rpm -Uvh $i
			rpm -Uvh $i
		done
	else
		echo "The expect.base, tcl.base, and tk.base filesets must also be installed before installing the xCAT RPMs from xcat-core."
	fi
fi
EOF
# end of instoss file content ---------------------------------------------


	chmod +x instoss
fi

# Get the permissions and group correct
if [ "$OSNAME" == "AIX" ]; then
	SYSGRP=system
else
	SYSGRP=root
fi
chgrp -R $SYSGRP *
chmod -R g+w *

# Build the tarball
#VER=`cat $XCATCOREDIR/Version`
cd ..
if [ -n "$VERBOSEMODE" ]; then
	verbosetar="-v"
else
	verbosetar=""
fi
if [ "$OSNAME" == "AIX" ]; then
	DFNAME=dep-aix-`date +%Y%m%d%H%M`.tar.gz
	echo "Creating $DFNAME ..."
	tar $verbosetar -cf ${DFNAME%.gz} xcat-dep
	rm -f $DFNAME
	gzip ${DFNAME%.gz}
else
	DFNAME=xcat-dep-`date +%Y%m%d%H%M`.tar.bz2
	echo "Creating $DFNAME ..."
	tar $verbosetar -jcf $DFNAME xcat-dep
fi

#cd xcat-dep  <-- now we want to stay above xcat-dep, so we can rsync the whole dir

if [ "$UP" == 0 ]; then
 exit 0;
fi

if [ "$OSNAME" == "AIX" ]; then
	YUM=aix
	FRSDIR='2.x_AIX'
else
	YUM=yum
	FRSDIR='2.x_Linux'
fi

# Upload the dir structure to SF yum area.  Currently we do not have it preserving permissions
# because that gives errors when different users try to do it.
i=0
if [ "$FRSYUM" != 0 ]; then
	links="-L"		# FRS does not support rsyncing sym links
else
	links="-l"
fi
echo "Uploading RPMs from xcat-dep to $YUMDIR/$YUM/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync $links -ruv --delete xcat-dep $UPLOADUSER,xcat@web.sourceforge.net:$YUMDIR/$YUM/
do : ; done

# Upload the tarball to the SF FRS Area
i=0
echo "Uploading $DFNAME to $FRS/xcat-dep/$FRSDIR/ ..."
while [ $((i+=1)) -le 5 ] && ! rsync -v $DFNAME $UPLOADUSER,xcat@web.sourceforge.net:$FRS/xcat-dep/$FRSDIR/
do : ; done
