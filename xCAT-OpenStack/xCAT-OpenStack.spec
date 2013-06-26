Summary: Meta-Metapackage for a common, default xCAT management node setup with OpenStack 
Name: xCAT-OpenStack
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: noarch
Source:  xCAT-OpenStack-%(cat Version).tar.gz

Provides: xCAT-OpenStack = %{version}
Requires: xCAT

%description
xCAT-OpenStack is an xCAT management node package intended for at-scale 
management with OpenStack, including hardware management and software 
management.

%prep
%setup -q -n xCAT-OpenStack

%build


%install
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema

cp -a lib/perl/xCAT_schema/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema
find $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema -type d -exec chmod 755 {} \;
find $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema -type f -exec chmod 644 {} \;


%clean
rm -rf $RPM_BUILD_ROOT

%files
%{prefix}
%defattr(-,root,root)


