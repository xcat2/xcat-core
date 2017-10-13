Summary: Packages for installation of CSM nodes
Name: xCAT-csm
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
Epoch: 4
License: IBM
Group: Applications/System
Source: xCAT-csm-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifos linux
BuildArch: noarch
%endif

Provides: xCAT-csm = %{epoch}:%{version}

Requires: xCAT

%description
xCAT-csm provides Packages for installation of CSM nodes

%prep
%setup -q -n xCAT-csm


%build

%install
rm -rf %{buildroot}

mkdir -p $RPM_BUILD_ROOT/install/postscripts/
mkdir -p $RPM_BUILD_ROOT/install/custom/netboot/rh/
mkdir -p $RPM_BUILD_ROOT/install/custom/netboot/rh/cuda/
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/install/rh/
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/rh/

cp install.rh/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/install/rh/
cp netboot.rh/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/rh/
cp netboot.rh.cuda/* $RPM_BUILD_ROOT/install/custom/netboot/rh/cuda/
cp install/postscripts/* $RPM_BUILD_ROOT/install/postscripts/

%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%{prefix}
/install/postscripts
/install/custom
%doc



%changelog
