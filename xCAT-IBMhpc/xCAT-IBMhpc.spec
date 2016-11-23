Summary: Install and configuration utilities for IBM HPC products in an xCAT cluster
Name: xCAT-IBMhpc
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-IBMhpc-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifnos linux
AutoReqProv: no
%endif

# AIX will build with an arch of "ppc"
# also need to fix Requires for AIX
%ifos linux
BuildArch: noarch
#Requires:
%endif

Requires: perl-xCAT >= %{epoch}:%{version}
Requires: xCAT-client  >= %{epoch}:%{version}

Provides: xCAT-IBMhpc = %{epoch}:%{version}

%description
xCAT-IBMhpc provides sample installation and configuration scripts for running the IBM HPC software stack in an xCAT cluser.  Support for the following IBM products is provided:  GPFS, LoadLeveler, Parallel Environment, ESSL and Parallel ESSL libraries, some compilers (vac, xlC, xlf).

%prep
%setup -q -n xCAT-IBMhpc
%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/compilers
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/essl
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/gpfs
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/loadl
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/pe
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/rsct

%ifos linux
cp -a share/xcat/IBMhpc/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/ping-all/
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/ml-tuning
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/aix-clean-jitter
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/aix-reboot
chmod -R 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/*
%else
cp -hpR share/xcat/IBMhpc/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/
chmod -R 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/IBMhpc/*
%endif

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-IBMhpc
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-IBMhpc
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-IBMhpc/*
#echo $RPM_BUILD_ROOT %{prefix}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
%{prefix}

%changelog

%pre
# only need to check on AIX
%ifnos linux
if [ -x /usr/sbin/emgr ]; then          # Check for emgr cmd
	/usr/sbin/emgr -l 2>&1 |  grep -i xCAT   # Test for any xcat ifixes -  msg and exit if found
	if [ $? = 0 ]; then
		echo "Error: One or more xCAT emgr ifixes are installed. You must use the /usr/sbin/emgr command to uninstall each xCAT emgr ifix prior to RPM installation."
		exit 2
	fi
fi
%endif

%post

%preun
