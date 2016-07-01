Summary: xCAT automated test tool
Name: xCAT-probe
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-probe-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

# AIX will build with an arch of "ppc"
%ifos linux
BuildArch: noarch
%endif

Provides: xCAT-probe = %{version}

%description
Provides a toolkits to help probe all the possible issues in xCAT 

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
chmod 755 $RPM_BUILD_ROOT/%{prefix}/bin/*

cp -r subcmds  $RPM_BUILD_ROOT/%{prefix}/probe/
chmod 755 $RPM_BUILD_ROOT/%{prefix}/probe/subcmds/*

cp -r lib $RPM_BUILD_ROOT/%{prefix}/probe/
chmod 644 $RPM_BUILD_ROOT/%{prefix}/probe/lib/perl/*
chmod 644 $RPM_BUILD_ROOT/%{prefix}/probe/lib/perl/xCAT/*

%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
# Just package everything that has been copied into RPM_BUILD_ROOT
%{prefix}

%changelog
* Tue Sep 14 2010 - Airong Zheng <zhengar@us.ibm.com>
- "Create xCAT autotest package"

%post

%preun
