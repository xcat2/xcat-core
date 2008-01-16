Summary: Metapackage for a common, default xCAT on AIX setup
Name: xCAT-aix
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: noarch
Source1: xcat.conf
Source2: postscripts.tar.gz
Source3: templates.tar.gz

Provides: xCAT-aix = %{version}
Requires: xCAT-server xCAT-client perl-DBD-SQLite perl-xCAT
%description
xCAT-aix is a meta-package which provides some basic xCAT configuration for AIX management nodes.

%prep
tar -xvf %{SOURCE2}
%build
%install
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d/
mkdir -p $RPM_BUILD_ROOT/install/postscripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/
tar -xvf %{SOURCE3}
cd -
cd $RPM_BUILD_ROOT/install
tar -xvf %{SOURCE2}
rm LICENSE.html
mkdir -p postscripts/hostkeys
cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT

%post
xcataixcfg

%clean

%files
%{prefix}
/etc/httpd/conf.d/xcat.conf
/install/postscripts
%defattr(-,root,root)
