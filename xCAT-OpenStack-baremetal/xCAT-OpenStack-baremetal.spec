Summary: Executables and data of the xCAT baremetal driver for OpenStack
Name: xCAT-OpenStack-baremetal
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: IBM
Group: Applications/System
Source: xCAT-OpenStack-baremetal-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifos linux
BuildArch: noarch
%endif


Provides: xCAT-OpenStack-baremetal = %{epoch}:%{version}

Requires: xCAT-client

%description
xCAT-OpenStack-baremetal provides the baremetal driver for OpenStack.

%prep
%setup -q -n xCAT-OpenStack-baremetal
%build

# Convert pods to man pages and html pages
./xpod2man

%install
# The install phase puts all of the files in the paths they should be in when the rpm is
# installed on a system.  The RPM_BUILD_ROOT is a simulated root file system and usually
# has a value like: /var/tmp/xCAT-OpenStack-baremetal-2.0-snap200802270932-root
rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/python/xcat/openstack/baremetal
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/openstack/postscripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man1
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man1


set +x

cp -R lib/* $RPM_BUILD_ROOT/%{prefix}/lib
cp share/xcat/openstack/postscripts/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/openstack/postscripts


# These were built dynamically in the build phase
cp share/man/man1/* $RPM_BUILD_ROOT/%{prefix}/share/man/man1
chmod 444 $RPM_BUILD_ROOT/%{prefix}/share/man/man1/*

# These were built dynamically during the build phase
cp share/doc/man1/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man1
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man1/*

# These links get made in the RPM_BUILD_ROOT/prefix area
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/sbin/deploy_ops_bm_node
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/sbin/cleanup_ops_bm_node
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/opsaddbmnode
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/opsaddimage

set -x


%clean
# This step does not happen until *after* the %files packaging below
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
# Just package everything that has been copied into RPM_BUILD_ROOT
%{prefix}


%changelog

%post
#copy the postscripts under /installl/postscripts directory on MN only
if [ -f "/etc/xCATMN" ]; then
	cp $RPM_INSTALL_PREFIX0/share/xcat/openstack/postscripts/* /install/postscripts/
fi

%preun
#remove postscripts under /installl/postscripts directory on MN only
if [ -f "/etc/xCATMN" ]; then
	for fn in $RPM_INSTALL_PREFIX0/share/xcat/openstack/postscripts/*
	do
		bn=`basename $fn`
		rm /install/postscripts/$bn
	done
fi
exit 0


