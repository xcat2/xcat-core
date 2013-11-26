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
Source3: xCATSN 
Provides: xCATsn = %{version}
Requires: xCAT-server xCAT-client perl-xCAT perl-DBD-SQLite 

%ifos linux
Requires: perl-XML-Parser
%endif

Conflicts: xCAT

%ifos linux
Requires: httpd nfs-utils expect nmap fping bind perl-XML-Parser vsftpd
# On RHEL this pulls in dhcp, on SLES it pulls in dhcp-server
Requires: /usr/sbin/dhcpd
%ifnarch s390x
Requires: /etc/xinetd.d/tftp
# yaboot-xcat is pulled in so any SN can manage ppc nodes
Requires: conserver-xcat yaboot-xcat perl-Net-Telnet
%endif
%ifarch ppc64
Requires: perl-IO-Stty
%endif
%endif

%ifarch i386 i586 i686 x86 x86_64
# The xCAT-genesis-x86_64 rpm is used for dhcp-based discovery, and flashing, so for now we do not need it on a ppc MN.
Requires: syslinux xCAT-genesis-x86_64
Requires: ipmitool-xcat >= 1.8.9
Requires: xnba-undi syslinux-xcat
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

%ifos linux
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d/
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
# cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat.conf
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf
cp %{SOURCE3} $RPM_BUILD_ROOT/etc/xCATSN

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
%else
mkdir -p $RPM_BUILD_ROOT/etc/
mkdir -p $RPM_BUILD_ROOT/opt/xcat/
cp %{SOURCE3} $RPM_BUILD_ROOT/etc/xCATSN
%endif

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
# create dir for the current pid and move the original ones from /tmp/xcat to /var/run/xcat
mkdir -p /var/run/xcat
if [ -r "/tmp/xcat/installservice.pid" ]; then
  mv /tmp/xcat/installservice.pid /var/run/xcat/installservice.pid
fi
if [ -r "/tmp/xcat/udpservice.pid" ]; then
  mv /tmp/xcat/udpservice.pid /var/run/xcat/udpservice.pid
fi
if [ -r "/tmp/xcat/mainservice.pid" ]; then
  mv /tmp/xcat/mainservice.pid /var/run/xcat/mainservice.pid
fi

if [ "$1" = "1" ]; then #Only if installing for the first time..

# setup sqlite if no other database

%ifos linux 
if [ -f "/proc/cmdline" ]; then   #check to make sure this is not image install 
 if [ ! -s /etc/xcat/cfgloc ]; then  # database is sqlite 
   $RPM_INSTALL_PREFIX0/sbin/xcatconfig -d
 fi
fi
%endif

# so conserver will start
 mkdir -p /var/log/consoles

# remove any management node file
if [ -f /etc/xCATMN ]; then
  rm  /etc/xCATMN
fi

%ifos linux
if [ -e "/etc/redhat-release" ]; then
    apachedaemon='httpd'
else # SuSE
    apachedaemon='apache2'
fi

# start xcatd
    chkconfig $apachedaemon on
    if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    	XCATROOT=$RPM_INSTALL_PREFIX0 /etc/init.d/xcatd start
		/etc/init.d/$apachedaemon reload 
	fi
    echo "xCATsn is now installed"
%else
# start xcatd on  AIX
  XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/restartxcatd
    echo "xCATsn is now installed"

%endif
fi

%clean

%files
%{prefix}
# one for sles, one for rhel. yes, it's ugly...
%ifos linux
/etc/httpd/conf.d/xcat.conf
/etc/apache2/conf.d/xcat.conf
%endif
/etc/xCATSN
%defattr(-,root,root)
