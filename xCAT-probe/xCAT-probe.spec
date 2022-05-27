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
Requires: xCAT-client = 4:%{version}-%{release}

%ifos linux
BuildArch: noarch
%endif

%ifos linux
#Below tools are required by sub-command 'xcatmn'
Requires: /usr/bin/nslookup
Requires: /usr/bin/tftp
Requires: /usr/bin/wget
# Tool detect_dhcpd requires tcpdump
Requires: /usr/sbin/tcpdump
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
* Thu Aug 30 2018 - GONG Jie <gongjie@linux.vnet.ibm.com>
- Add /usr/sbin/tcpdump as requirement
* Fri Jul 1 2016 - huweihua <huweihua@cn.ibm.com>
- "Create xCAT probe package"

%post
if [ -e %{prefix}/probe/subcmds/bin/switchprobe ]; then
    rm -rf %{prefix}/probe/subcmds/bin/switchprobe
else
    mkdir -p %{prefix}/probe/subcmds/bin/
fi
cd %{prefix}/probe/subcmds/bin/
if [ -e %{prefix}/bin/xcatclient ]; then
    ln -s %{prefix}/bin/xcatclient switchprobe
fi

%preun
#remove the bin directory if not on upgrade
if [ "$1" != "1" ]; then
    rm -rf %{prefix}/probe/subcmds/bin/
fi
