Summary: RMC monitoring plug-in for xCAT
Name: xCAT-rmc
Version: 2.1
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 2
License: EPL
Group: System Environment/Libraries
Source: xCAT-rmc-2.1.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif

Requires: perl-xCAT = %{version}
Requires: xCAT-server  = %{version}

Provides: xCAT-rmc = %{version}

%description
Provides RMC monitoring plug-in module for xCAT, configuration scripts, predefined conditions, responses and sensors. 

%prep
%setup -q
%build
%install

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/rmc
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon

cp plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring
cp -r resources $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/rmc

cp scripts/perl/* $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon/*

%clean
rm -rf $RPM_BUILD_ROOT

#find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%files
%defattr(-, root, root)
%{prefix}

%changelog


