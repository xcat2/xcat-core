Summary: xCAT integration with confluent systems management server
Name: xCAT-confluent
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-confluent-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif
Requires: confluent_server

Provides: xCAT-confluent = %{epoch}:%{version}

%description
xCAT confluent provides the necessary integration pieces to utilize the confluent
system management server

%prep

%setup -q -n xCAT-confluent

%build
# Convert pods to man pages and html pages
#./xpod2man

%install
rm -rf $RPM_BUILD_ROOT

# Uncomment the following line if we ship bin files
# mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
# cp -d bin/* $RPM_BUILD_ROOT/%{prefix}/bin/
# chmod 755 $RPM_BUILD_ROOT/%{prefix}/bin/*

mkdir -p $RPM_BUILD_ROOT/opt/confluent
cp -dr confluent/* $RPM_BUILD_ROOT/opt/confluent/

#cp share/man/man1/* $RPM_BUILD_ROOT/%{prefix}/share/man/man1
#chmod 444 $RPM_BUILD_ROOT/%{prefix}/share/man/man1/*
#cp share/doc/man1/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man1
#chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man1/*

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
# Uncomment the following line if we ship bin files
# %{prefix}
/opt/confluent

%post
