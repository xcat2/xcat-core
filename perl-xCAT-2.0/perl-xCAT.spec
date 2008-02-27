Summary: xCAT perl libraries
Name: perl-xCAT
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: System Environment/Libraries
Source: perl-xCAT-2.0.tar.gz
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

# Build the pod version of the man pages for each DB table.  It puts them in the man5 subdir.
./db2man

# Convert pods to man pages, e.g.:  pod2man pods/man5/chain.5.pod share/man/man5/chain.1
for i in pods/*/*.pod; do
  man=${i/pods/share\/man}
  mkdir -p ${man%/*}
  pod2man $i ${man%.pod}
done

%install
# The install phase puts all of the files in the paths they should be in when the rpm is
# installed on a system.  The RPM_BUILD_ROOT is a simulated root file system and usually
# has a value like: /var/tmp/perl-xCAT-2.0-snap200802270932-root

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man5

cp -r xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data/*

cp xCAT2.0.doc $RPM_BUILD_ROOT/%{prefix}/share/doc
cp xCAT2.0.pdf $RPM_BUILD_ROOT/%{prefix}/share/doc
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/*

cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
cp README $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT/*

# These were built dynamically in the build phase
cp share/man/man5/* $RPM_BUILD_ROOT/%{prefix}/share/man/man5
chmod 444 $RPM_BUILD_ROOT/%{prefix}/share/man/man5/*

%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

#find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%files
%defattr(-, root, root)
#%doc LICENSE.html
#%doc README
#%doc xCAT2.0.doc
#%doc xCAT2.0.pdf
# Just package everything that has been copied into RPM_BUILD_ROOT
%{prefix}

%changelog
* Wed May 2 2007 - Norm Nott nott@us.ibm.com
- Made changes to make this work on AIX

* Wed Jan 24 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
-It begins

