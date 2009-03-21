Summary: Metapackage for a common, default xCAT service node setup
Name: xCATsn
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
#BuildArch: noarch
Source1: xcat.conf
Source2: license.tar.gz
Provides: xCATsn = %{version}
Requires: xCAT-server xCAT-client  perl-xCAT perl-XML-Parser

%ifos linux
Requires: atftp dhcp httpd nfs-utils expect conserver fping bind
%endif

%ifarch i386 i586 i686 x86 x86_64
Requires: xCAT-nbroot-oss-x86_64 xCAT-nbroot-core-x86_64 xCAT-nbkernel-x86_64 syslinux
Requires: ipmitool >= 1.8.9
%endif

%description
xCATsn is a service node management package intended for at-scale management,
including hardware management and software management. 


%prep
%ifos linux
tar zxf %{SOURCE2}
%else
cp %{SOURCE2} /opt/freeware/src/packages/BUILD
gunzip -f license.tar.gz
tar -xf license.tar
%endif

%build

%install
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d/
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
# cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat.conf
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT


%post

if [ "$1" = "1" ]; then #Only if installing for the first time..
# so conserver will start
 mkdir -p /var/log/consoles

# makes it a service node
  touch /etc/xCATSN
# remove any management node file
if [ -f /etc/xCATMN ]; then
  rm  /etc/xCATMN
fi


###  Start the xcatd daemon

    chkconfig httpd on
    if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    	XCATROOT=$RPM_INSTALL_PREFIX0 /etc/init.d/xcatd start
		/etc/init.d/httpd stop
		/etc/init.d/httpd start
	fi
    echo "xCATsn is now installed"
fi

%clean

%files
%{prefix}
# one for sles, one for rhel. yes, it's ugly...
/etc/httpd/conf.d/xcat.conf
/etc/apache2/conf.d/xcat.conf
%defattr(-,root,root)
