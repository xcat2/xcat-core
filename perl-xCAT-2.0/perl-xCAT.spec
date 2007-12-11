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
%install

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT

cp -r xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/data/*

cp xCAT2.0.doc $RPM_BUILD_ROOT/%{prefix}/share/doc
cp xCAT2.0.pdf $RPM_BUILD_ROOT/%{prefix}/share/doc
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/*

cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
cp README $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/perl-xCAT/*

%clean
rm -rf $RPM_BUILD_ROOT

#find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%files
%defattr(-, root, root)
#%doc LICENSE.html
#%doc README 
#%doc xCAT2.0.doc 
#%doc xCAT2.0.pdf
%{prefix}

%changelog
* Wed May 2 2007 - Norm Nott nott@us.ibm.com
- Made changes to make this work on AIX

* Wed Jan 24 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
-It begins

