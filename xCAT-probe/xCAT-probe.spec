Summary: xCAT diagnostic tool
Name: xCAT-probe
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-probe-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifos linux
BuildArch: noarch
%endif

%ifos linux
#Below tools are required by sub-command 'xcatmn'
Requires: /usr/bin/nslookup
Requires: /usr/bin/tftp
Requires: /usr/bin/wget
%endif

%description
xCAT-probe provides a toolkits to probe potential issues with the xCAT cluster.

%prep
%setup -q -n xCAT-probe
%build

# Convert pods to man pages and html pages

%install
# The install phase puts all of the files in the paths they should be in when the rpm is
# installed on a system.  The RPM_BUILD_ROOT is a simulated root file system and usually
# has a value like: /var/tmp/xCAT-probe-2.0-snap200802270932-root
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/probe/

cp xcatprobe $RPM_BUILD_ROOT/%{prefix}/bin
cp -r subcmds  $RPM_BUILD_ROOT/%{prefix}/probe/
cp -r lib $RPM_BUILD_ROOT/%{prefix}/probe/
cp -r scripts $RPM_BUILD_ROOT/%{prefix}/probe/

%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
# Just package everything that has been copied into RPM_BUILD_ROOT
%{prefix}

%changelog
* Fri Jul 1 2016 - huweihua <huweihua@cn.ibm.com>
- "Create xCAT probe package"

%post

%preun
