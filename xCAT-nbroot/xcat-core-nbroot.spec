%define version	%(cat Version)
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
%define name	xCAT-nbroot-core-%{tarch}
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
AutoReq: false
Prefix: /opt/xcat
AutoProv: false



Name:	 %{name}
Version: %{version}
Group: System/Utilities
License: EPL
Vendor: IBM Corp.
Summary: xCAT-nbroot-core provides opensource components of the netboot image
URL:	 http://xcat.org
Source1: xcat-nbrootoverlay.tar.gz

Buildroot: %{_localstatedir}/tmp/xCAT-nbroot-core
Packager: IBM Corp.

%Description
xcat-nbroot-core provides the xCAT scripts for the mini-root environment
All files included are as they were downloadable on 4/7/2007
%Prep


%Build

%Install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/%{tarch}/nbroot
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/%{tarch}/nbroot
tar zxf %{SOURCE1}
chmod 755 etc/init.d/S40network bin/getdestiny bin/getdestiny.awk bin/getipmi bin/getipmi.awk
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
%doc LICENSE.html
/
