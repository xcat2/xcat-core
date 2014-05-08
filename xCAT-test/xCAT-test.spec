Summary: xCAT automated test tool
Name: xCAT-test
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-test-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

# AIX will build with an arch of "ppc"
%ifos linux
BuildArch: noarch
%endif

Provides: xCAT-test = %{version}

%description
Provides automated test tool and buckets to help test xCAT commands automatically.

%prep
%setup -q -n xCAT-test
%build

# Convert pods to man pages and html pages
mkdir -p share/man/man1
mkdir -p share/doc/man1
pod2man pods/man1/xcattest.1.pod > share/man/man1/xcattest.1
pod2html pods/man1/xcattest.1.pod > share/doc/man1/xcattest.1.html

%install
# The install phase puts all of the files in the paths they should be in when the rpm is
# installed on a system.  The RPM_BUILD_ROOT is a simulated root file system and usually
# has a value like: /var/tmp/xCAT-test-2.0-snap200802270932-root
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools/autotest
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man1
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man1

cp xcattest $RPM_BUILD_ROOT/%{prefix}/bin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/bin/*

cp restapitest $RPM_BUILD_ROOT/%{prefix}/sbin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/*

# These were built dynamically in the build phase
cp share/man/man1/* $RPM_BUILD_ROOT/%{prefix}/share/man/man1
chmod 444 $RPM_BUILD_ROOT/%{prefix}/share/man/man1/*
cp share/doc/man1/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man1
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man1/*

cp -r autotest $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools


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
