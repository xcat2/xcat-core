Summary: Executables and data of the xCAT vlan management project
Name: xCAT-vlan
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: IBM
Group: Applications/System
Source: xCAT-vlan-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifos linux
BuildArch: noarch
%endif


Provides: xCAT-vlan = %{epoch}:%{version}


Requires: xCAT-client

%description
xCAT-vlan provides the xCAT vlan confiuration.

%prep
%setup -q -n xCAT-vlan
%build

# Convert pods to man pages and html pages
./xpod2man

%install
# The install phase puts all of the files in the paths they should be in when the rpm is
# installed on a system.  The RPM_BUILD_ROOT is a simulated root file system and usually
# has a value like: /var/tmp/xCAT-vlan-2.0-snap200802270932-root
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
mkdir -p $RPM_BUILD_ROOT/install/postscripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man1
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man1


set +x

cp xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
cp -R xCAT_plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
cp install/postscripts/* $RPM_BUILD_ROOT/install/postscripts


# These were built dynamically in the build phase
cp share/man/man1/* $RPM_BUILD_ROOT/%{prefix}/share/man/man1
chmod 444 $RPM_BUILD_ROOT/%{prefix}/share/man/man1/*

# These were built dynamically during the build phase
cp share/doc/man1/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man1
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man1/*

# These links get made in the RPM_BUILD_ROOT/prefix area
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/mkvlan
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/chvlan
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/rmvlan
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/lsvlan
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/chvlanports


%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
# Just package everything that has been copied into RPM_BUILD_ROOT
%{prefix}
/install/postscripts


%changelog

%post
%ifos linux
  if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
      /etc/init.d/xcatd reload
    fi
  fi
%else
  #restart the xcatd on if xCAT or xCATsn is installed already
  if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
    if [ -n "$INUCLIENTS" ] && [ $INUCLIENTS -eq 1 ]; then
      #Do nothing in not running system
      echo "Do not restartxcatd in not running system"
    else
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/restartxcatd -r
    fi
  fi
%endif
exit 0

%preun


