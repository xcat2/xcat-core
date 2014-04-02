Summary: xCAT perl libraries
Name: perl-xCAT
Version: %(cat Version; cat LastGitCommit)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: System Environment/Libraries
Source: perl-xCAT-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
# Do not need the SOAP rpm require, because rpm will generate it automatically if hpoa.pm is included
#Requires: perl-SOAP-Lite
%endif

Provides: perl-xCAT = %{epoch}:%{version}

%description
Provides perl xCAT libraries for core functionality.  Required for all xCAT installations.
Includes xCAT::Table, xCAT::NodeRange, among others.

%define gitinfo %(git log -n 1 | head -n 1)

%define zvm %(if [ "$zvm" = "1" ];then echo 1; else echo 0; fi)
%define fsm %(if [ "$fsm" = "1" ];then echo 1; else echo 0; fi)

%prep
%setup -q -n perl-xCAT
%build
# This phase is done in (for RH): /usr/src/redhat/BUILD/perl-xCAT-2.0
# All of the tarball source has been unpacked there and is in the same file structure
# as it is in svn.

%if %fsm
%else
# Modify the Version() function in xCAT/Utils.pm to automatically have the correct version
./modifyUtils %{version} %{gitinfo}

# Build the pod version of the man pages for each DB table.  It puts them in the man5 and man7 subdirs.
# Then convert the pods to man pages and html pages.
./db2man
%endif

%install
# The install phase puts all of the files in the paths they should be in when the rpm is
# installed on a system.  The RPM_BUILD_ROOT is a simulated root file system and usually
# has a value like: /var/tmp/perl-xCAT-2.0-snap200802270932-root

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man5
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man5
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man7
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man7

cp -r xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data/*


# For now, don't ship these plugins on AIX, to avoid AIX dependency error.
%ifnos linux
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/hpoa.pm
%endif

# Don't ship these on zVM, to reduce dependencies
%if %zvm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/hpoa.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/vboxService.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/FSP*.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/PPC*.pm
# have to put PPCdb.pm back because it is needed by Postage.pm
cp xCAT/PPCdb.pm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/PPCdb.pm
%endif
# Don't ship these on FSM, to reduce dependencies
%if %fsm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/hpoa.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/vboxService.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/FSP*.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/RemoteShellExp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/LparNetbootExp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/PPC*.pm
# have to put PPCdb.pm back because it is needed by Postage.pm
cp xCAT/PPCdb.pm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/PPCdb.pm
%endif

cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT/*

cp README $RPM_BUILD_ROOT/%{prefix}
chmod 644 $RPM_BUILD_ROOT/%{prefix}/README

%if %fsm
%else
# These were built dynamically in the build phase
cp share/man/man5/* $RPM_BUILD_ROOT/%{prefix}/share/man/man5
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/man/man5/*
cp share/doc/man5/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man5
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man5/*
cp share/man/man7/* $RPM_BUILD_ROOT/%{prefix}/share/man/man7
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/man/man7/*
cp share/doc/man7/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man7
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man7/*
%endif

%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

#find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%files
%defattr(-, root, root)
#%doc LICENSE.html
#%doc README
# Just package everything that has been copied into RPM_BUILD_ROOT
%{prefix}

%pre
# only need to check on AIX
%ifnos linux
if [ -x /usr/sbin/emgr ]; then          # Check for emgr cmd
	/usr/sbin/emgr -l 2>&1 |  grep -i xCAT   # Test for any xcat ifixes -  msg and exit if found
	if [ $? = 0 ]; then
		echo "Error: One or more xCAT emgr ifixes are installed. You must use the /usr/sbin/emgr command to uninstall each xCAT emgr ifix prior to RPM installation."
		exit 2
	fi
fi
%endif

%post
%ifos linux
if [ "$1" -gt 1 ]; then #Ugrade only, restart daemon and migrate settings
   if [ -x /etc/init.d/xcatd ] && [ -f "/proc/cmdline" ]; then
      . /etc/profile.d/xcat.sh
   fi
fi
%endif
exit 0

%changelog
* Wed May 2 2007 - Norm Nott nott@us.ibm.com
- Made changes to make this work on AIX

* Wed Jan 24 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
-It begins

