Summary: RMC monitoring plug-in for xCAT
Name: xCAT-rmc
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: System Environment/Libraries
Source: xCAT-rmc-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif

Requires: perl-xCAT >= %{epoch}:%{version}
Requires: xCAT-server  >= %{epoch}:%{version}

Provides: xCAT-rmc = %{version}

%description
Provides RMC monitoring plug-in module for xCAT, configuration scripts, predefined conditions, responses and sensors.

%prep
%setup -q -n xCAT-rmc
%build
%install

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/rmc
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon
mkdir -p $RPM_BUILD_ROOT/install/postscripts

cp plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring
cp -r resources $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/rmc

cp scripts/* $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon/*

cp scripts/configrmcnode $RPM_BUILD_ROOT/install/postscripts
chmod 755 $RPM_BUILD_ROOT/install/postscripts/configrmcnode

%clean
rm -rf $RPM_BUILD_ROOT

#find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%files
%defattr(-, root, root)
%{prefix}
/install/postscripts

%changelog

%post
%ifos linux
  if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
      /etc/init.d/xcatd restart
    fi
  fi
%else
  #restart the xcatd on if xCAT or xCATsn is installed already
  if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
    XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/xcatstart
  fi
%endif






