Summary: Metapackage for a common, default xCAT service node setup
Name: xCATsn
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
#BuildArch: noarch
Source1: xcat.conf
Provides: xCATsn = %{version}
Requires: xCAT-server xCAT-client  perl-xCAT perl-XML-Parser

%ifos linux
Requires: atftp dhcp httpd nfs-utils expect conserver fping bind perl-DBD-Pg postgresql-server postgresql syslinux
%endif

%ifarch i386 i586 i686 x86 x86_64
Requires: xCAT-nbroot-oss-x86_64 xCAT-nbroot-core-x86_64 xCAT-nbkernel-x86_64
Requires: ipmitool >= 1.8.9
%endif

%description
xCATsn is a service node management package intended for at-scale management,
including hardware management and software management.


%prep

%build

%install
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d/
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT


%post

if [ "$1" = "1" ]; then #Only if installing for the first time..
# so conserver will start
 mkdir -p /var/log/consoles

# makes it a service node
  touch /etc/xCATSN




###  Start the xcatd daemon

    chkconfig httpd on
    if (-f '/proc/cmdline') {      # this check avoids running these when being installed into a chroot image
    	XCATROOT=$RPM_INSTALL_PREFIX0 /etc/init.d/xcatd start
		/etc/rc.d/init.d/httpd stop
		/etc/rc.d/init.d/httpd start
	}
    echo "xCATsn is now installed"
fi

%clean

%files
%{prefix}
/etc/httpd/conf.d/xcat.conf
%defattr(-,root,root)
