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
Requires: xCAT-server xCAT-client  perl-xCAT 

%ifos linux
Requires: tftp-server dhcp httpd nfs-utils expect conserver fping bind
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

    mkdir -p /var/log/consoles
    if ! grep /tftpboot /etc/exports; then
        echo '/tftpboot *(ro,root_squash,sync)' >> /etc/exports #SECURITY: this has potential for sharing private host/user keys
    fi
    if ! grep /install /etc/exports; then
        echo '/install *(rw,no_root_squash,sync)' >> /etc/exports #SECURITY: this has potential for sharing private host/user keys
    fi
	chkconfig nfs on
	/etc/rc.d/init.d/nfs stop
	/etc/rc.d/init.d/nfs start

# makes it a service node
  touch /etc/xCATSN    
# setup syslog
  if [ ! -r /etc/syslog.conf.XCATORIG ]; then
  cp /etc/syslog.conf /etc/syslog.conf.XCATORIG
  echo "*.debug   /var/log/messages" > /etc/test.tmp 
  echo "*.crit   /var/log/messages" >> /etc/test.tmp 
  cat /etc/test.tmp >> /etc/syslog.conf
  rm /etc/test.tmp
  touch /var/log/messages

  /etc/rc.d/init.d/syslog stop
  /etc/rc.d/init.d/syslog start
  fi




###  Start the xcatd daemon

    XCATROOT=$RPM_INSTALL_PREFIX0 /etc/init.d/xcatd start
    chkconfig httpd on
	/etc/rc.d/init.d/httpd stop
	/etc/rc.d/init.d/httpd start
    echo "xCATsn is now installed"
fi

%clean

%files
%{prefix}
/etc/httpd/conf.d/xcat.conf
%defattr(-,root,root)
