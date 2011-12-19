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
#       FRSYUM=1 - put the directory of individual rpms in the FRS area instead of project web area.

# you can change this if you need to
UPLOADUSER=bp-sawyers

FRS=/home/frs/project/x/xc/xcat
OSNAME=$(uname)

if [ "$OSNAME" == "AIX" ]; then
	GSA=/gsa/pokgsa/projects/x/xcat/build/aix/xcat-dep
else
	GSA=/gsa/pokgsa/projects/x/xcat/build/linux/xcat-dep
	export HOME=/root		# This is so rpm and gpg will know home, even in sudo
fi

# Process cmd line variable assignments, assigning each attr=val pair to a variable of same name
for i in $*; do
	#declare `echo $i|cut -d '=' -f 1`=`echo $i|cut -d '=' -f 2`
	export $i
done

# this is needed only when we are transitioning the yum over to frs
if [ "$FRSYUM" = 1 ]; then
	YUMDIR=$FRS
else
	YUMDIR=htdocs
fi

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
fi

if [ "$OSNAME" == "AIX" ]; then
	# Build the instoss file
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
# The only interdependency between the dep rpms so far is that net-snmp requires bash

#  pyodbc is dependent on unixODBC
rpm -Uvh unixODBC*

for i in `ls *.rpm|grep -v -E '^tcl-|^tk-|^expect-|^unixODBC-|^xCAT-UI-deps'`; do
	if [ "$i" == "perl-Net-DNS-0.66-1.aix5.3.ppc.rpm" ]; then
		opts="--nodeps"
	else
		opts=""
	fi
	# this next if stmt means: if i does not start with perl-DBD-DB2
	#if [ "${i#perl-DBD-DB2}" == "$i" ]; then
		echo rpm -Uvh $opts $i
		rpm -Uvh $opts $i
	#fi
done
# don't try to install tcl, tk, or expect if they are already installed!
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

# this is left over from Norms original instoss
#rpm -Uvh perl-DBI-*.rpm
#rpm -Uvh bash-*.rpm
#rpm -Uvh perl-DBD-SQLite-*.rpm
#rpm -Uvh popt-*.rpm
#rpm -Uvh rsync-*.rpm
#rpm -Uvh wget-*.rpm
#rpm -Uvh libxml2-*.rpm
#rpm -Uvh curl-*.rpm
#rpm -Uvh expat-*.rpm
#rpm -Uvh conserver-*.rpm
#rpm -Uvh perl-Expect-*.rpm
#rpm -Uvh perl-IO-Tty-*.rpm
#rpm -Uvh perl-IO-Stty-*.rpm
#rpm -Uvh perl-IO-Socket-SSL-*.rpm
#rpm -Uvh perl-Net_SSLeay.pm-*.rpm
#rpm -Uvh perl-Digest-SHA1-*.rpm
#rpm -Uvh perl-Digest-SHA-*.rpm
#rpm -Uvh perl-Digest-HMAC-*.rpm
#rpm -Uvh --nodeps perl-Net-DNS-*.rpm
#rpm -Uvh perl-Net-IP-*.rpm
#rpm -Uvh perl-Digest-MD5-*.rpm
#rpm -Uvh fping-*.rpm
#rpm -Uvh openslp-xcat-*.rpm
#rpm -Uvh perl-Crypt-SSLeay-*.rpm
#rpm -Uvh perl-Net-Telnet-*.rpm
# this requires bash
#rpm -Uvh net-snmp-5*.rpm
#rpm -Uvh net-snmp-devel-*.rpm
#rpm -Uvh net-snmp-perl-*.rpm
#rpm -Uvh unixODBC-*.rpm
#if [ "$OSVER" == "6.1" ]; then
#	rpm -Uvh perl-version-*.rpm
#fi

	chmod +x instoss
fi

# Get the permissions correct.  Have to have all dirs/files with a group of xcat
# and have them writeable by group, so any member of the xcat can build.
if [ "$OSNAME" == "AIX" ]; then
	mkgroup xcat 2>/dev/null
else
	groupadd -f xcat
fi
chgrp -R xcat *
chmod -R g+w *

# Build the tarball
#VER=`cat $XCATCOREDIR/Version`
cd ..
if [ "$OSNAME" == "AIX" ]; then
	DFNAME=dep-aix-`date +%Y%m%d%H%M`.tar.gz
	tar -cvf ${DFNAME%.gz} xcat-dep
	rm -f $DFNAME
	gzip ${DFNAME%.gz}
else
	DFNAME=xcat-dep-`date +%Y%m%d%H%M`.tar.bz2
	tar -jcvf $DFNAME xcat-dep
fi
cd xcat-dep

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
while [ $((i++)) -lt 10 ] && ! rsync -rlv --delete * $UPLOADUSER,xcat@web.sourceforge.net:$YUMDIR/$YUM/xcat-dep/
do : ; done
#ssh jbjohnso@shell1.sf.net "cd /home/groups/x/xc/xcat/htdocs/yum/; rm -rf dep-snap; tar jxvf $DFNAME"

# Upload the tarball to the SF FRS Area
i=0
while [ $((i++)) -lt 10 ] && ! rsync -v ../$DFNAME $UPLOADUSER,xcat@web.sourceforge.net:$FRS/xcat-dep/$FRSDIR/
do : ; done
