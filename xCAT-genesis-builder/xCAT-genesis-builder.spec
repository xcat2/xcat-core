BuildArch: noarch
%define name	xCAT-genesis-builder
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
Epoch: 1
AutoReq: false
Requires: ipmitool screen btrfs-progs lldpad rpm-build mstflint xfsprogs nc rpmdevtools libstdc++-devel pciutils bridge-utils ntp ntp-perl iprutils psmisc mdadm bind-utils dosfstools usbutils libusbx
Prefix: /opt/xcat
AutoProv: false



Name:	 %{name}
Group: System/Utilities
License: EPL
Vendor: IBM Corp.
Summary: Tooling to create xCAT's discovery/maintenance/debugging environment
URL:	 https://xcat.org/
Source1: xCAT-genesis-builder.tar.bz2

Buildroot: %{_localstatedir}/tmp/xCAT-genesis-builder
Packager: IBM Corp.

%Description
Genesis (Genesis Enhanced Netboot Environment for System Information and Servicing) is xCAT's netboot environment designed to perform hardware and firmware inventory, perform firmware updates/configuration, and perform troubleshooting.
%Prep


%Build

%Install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/genesis/builder
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/genesis/builder
tar jxvf %{SOURCE1}
chmod +x $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/genesis/builder/buildrpm
cd -


%Files
%defattr(-,root,root)
%doc LICENSE.html
%dir %{prefix}
%dir %{prefix}/share
%dir %{prefix}/share/xcat
%dir %{prefix}/share/xcat/netboot
%dir %{prefix}/share/xcat/netboot/genesis
%dir %{prefix}/share/xcat/netboot/genesis/builder
%{prefix}/share/xcat/netboot/genesis/builder/*
