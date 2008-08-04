Summary: xCAT perl libraries
Name: perl-xCAT
Version: 2.1
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: System Environment/Libraries
Source: perl-xCAT-2.1.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif

Provides: perl(xCAT) = %{version}

%description
Provides perl xCAT libraries for core functionality.  Required for all xCAT installations.
Includes xCAT::Table, xCAT::NodeRange, among others.

%prep
%setup -q
%build
# This phase is done in (for RH): /usr/src/redhat/BUILD/perl-xCAT-2.0
# All of the tarball source has been unpacked there and is in the same file structure
# as it is in svn.

# Build the pod version of the man pages for each DB table.  It puts them in the man5 and man7 subdirs.
# Then convert the pods to man pages and html pages.
./db2man

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
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data/*

cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT/*

cp README $RPM_BUILD_ROOT/%{prefix}
chmod 644 $RPM_BUILD_ROOT/%{prefix}/README

# These were built dynamically in the build phase
cp share/man/man5/* $RPM_BUILD_ROOT/%{prefix}/share/man/man5
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/man/man5/*
cp share/doc/man5/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man5
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man5/*
cp share/man/man7/* $RPM_BUILD_ROOT/%{prefix}/share/man/man7
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/man/man7/*
cp share/doc/man7/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man7
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man7/*

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

%post
%ifos linux
if [ "$1" -gt 1 ]; then #Ugrade only, restart daemon and migrate settings
   if [ -x /etc/init.d/xcatd ] && [ -f "/proc/cmdline" ]; then
      . /etc/profile.d/xcat.sh
      /etc/init.d/xcatd restart
      #THE NEXT BIT SHOULD NOT BE RELEVANT TO RELEASE, IT SHOULD HELP A BETA INSTALL UPDATE GRACEFULLY
      BOOTPCHECK=`tabdump bootparams|grep -v '^#node'`
      if [ -z "$BOOTPCHECK" ]; then
      echo -n "Old schema use detected, migrating settings, may take a while..."
      for node in `nodels`; do
         MIGSETTING=`nodels $node noderes.serialport|sed -e 's/^.*:.*:\s*//'`
         nodech $node noderes.serialport=
         if [ ! -z "$MIGSETTING" ]; then
           nodech $node "nodehm.serialport=$MIGSETTING"
         fi
         MIGSETTING=`nodels $node noderes.kernel|sed -e 's/^.*:.*:\s*//'`
         nodech $node noderes.kernel=
         if [ ! -z "$MIGSETTING" ]; then
           nodech $node "bootparams.kernel=$MIGSETTING"
         fi
         MIGSETTING=`nodels $node noderes.initrd|sed -e 's/^.*:.*:\s*//'`
         nodech $node noderes.initrd=
         if [ ! -z "$MIGSETTING" ]; then
           nodech $node "bootparams.initrd=$MIGSETTING"
         fi
         MIGSETTING=`nodels $node noderes.kcmdline|sed -e 's/^.*:.*:\s*//'`
         nodech $node noderes.kcmdline=
         if [ ! -z "$MIGSETTING" ]; then
           nodech $node "bootparams.kcmdline=$MIGSETTING"
         fi
      done
      echo "Done"
   fi
   fi
fi
%endif

%changelog
* Wed May 2 2007 - Norm Nott nott@us.ibm.com
- Made changes to make this work on AIX

* Wed Jan 24 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
-It begins

