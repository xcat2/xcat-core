Summary: xCAT openbmc python
Name: xCAT-openbmc-py
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:snap%(date +"%Y%m%d%H%M")}
Epoch: 1
License: EPL
Group: Applications/System
Source: xCAT-openbmc-py-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifnos linux
AutoReqProv: no
%endif

BuildArch: noarch
Requires: xCAT-server
Requires: python-openbmc-dep

%description
xCAT-openbmc-py provides openbmc related functions. 

%prep
%setup -q -n xCAT-openbmc-py
%build

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/xcatagent
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/common
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/hwctl
install -d $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/hwctl/executor
install -m755 lib/python/agent/*.py $RPM_BUILD_ROOT/%{prefix}/lib/python/agent
install -m644 lib/python/agent/xcatagent/*.py $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/xcatagent
install -m644 lib/python/agent/common/*.py $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/common
install -m644 lib/python/agent/hwctl/*.py $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/hwctl
install -m644 lib/python/agent/hwctl/executor/*.py $RPM_BUILD_ROOT/%{prefix}/lib/python/agent/hwctl/executor

%ifnos linux
rm -rf $RPM_BUILD_ROOT/%{prefix}/lib/python/agent
%endif

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{prefix}

%changelog

%pre

%post

%preun

