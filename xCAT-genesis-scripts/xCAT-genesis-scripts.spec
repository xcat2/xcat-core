%define version	2.8
%ifarch i386 i586 i686 x86
%define tarch x86
%endif
%ifarch x86_64
%define tarch x86_64
%endif
%ifarch ppc ppc64
%define tarch ppc64
%endif
BuildArch: noarch
%define name	xCAT-genesis-scripts-%{tarch}
%define __spec_install_post :
%define debug_package %{nil}
%define __prelink_undo_cmd %{nil}
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 1
AutoReq: false
Prefix: /opt/xcat
AutoProv: false
Obsoletes: xCAT-genesis-${tarch}



Name:	 %{name}
Version: %{version}
Group: System/Utilities
License: EPL
Vendor: IBM Corp
Summary: xCAT Genesis netboot image - Core content
URL:	 http://xcat.org
Source1: xCAT-genesis-scripts-%{tarch}.tar.bz2

Buildroot: %{_localstatedir}/tmp/xCAT-genesis
Packager: IBM Corp.

%Description
xCAT genesis (Genesis Enhanced Netboot Environment for System Information and Servicing) is a small, embedded-like environment for xCAT's use in discovery and management actions when interaction with an OS is infeasible.
This package reperesents the EPL content that is more tightly bound to specific xcat-core versions
%Prep


%Build

%Install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT
tar jxf %{SOURCE1}
cd -


%post
if [ "$1" == "2" ]; then #only on upgrade, as on install it's probably not going to work...
	if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
   		. /etc/profile.d/xcat.sh
   		mknb %{tarch}
   	fi
fi

%Files
%defattr(-,root,root)
/
