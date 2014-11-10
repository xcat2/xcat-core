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
Source5: templates.tar.gz
Source6: xcat.conf.apach24
Provides: xCATsn = %{version}
Requires: xCAT-server xCAT-client perl-DBD-SQLite 

Conflicts: xCAT

%define pcm %(if [ "$pcm" = "1" ];then echo 1; else echo 0; fi)
%define notpcm %(if [ "$pcm" = "1" ];then echo 0; else echo 1; fi)

%ifos linux
# on RHEL7, need to specify it explicitly
Requires: net-tools
Requires: /usr/bin/killall
# yaboot-xcat is pulled in so any SN can manage ppc nodes
Requires: httpd nfs-utils nmap bind
# On RHEL this pulls in dhcp, on SLES it pulls in dhcp-server
Requires: /usr/sbin/dhcpd
# On RHEL this pulls in openssh-server, on SLES it pulls in openssh
Requires: /usr/bin/ssh
%ifnarch s390x
Requires: /etc/xinetd.d/tftp
# yaboot-xcat is pulled in so any MN can manage ppc nodes
#Requires: yaboot-xcat 
# Stty is only needed for rcons on ppc64 nodes, but for mixed clusters require it on both x and p
Requires: perl-IO-Stty
%endif
%endif

# The aix rpm cmd forces us to do this outside of ifos type stmts
%if %notpcm
%ifos linux
%ifnarch s390x
# PCM does not use or ship conserver
Requires: conserver-xcat
%endif
%endif
%endif

%ifarch i386 i586 i686 x86 x86_64
Requires: syslinux xCAT-genesis-scripts-x86_64 elilo-xcat
Requires: ipmitool-xcat >= 1.8.9
Requires: xnba-undi
%endif
%ifos linux
%ifarch ppc ppc64 ppc64le
Requires: xCAT-genesis-scripts-ppc64
Requires: ipmitool-xcat >= 1.8.9
%endif
%endif

%if %notpcm
%ifarch i386 i586 i686 x86 x86_64
# PCM does not need or ship syslinux-xcat
Requires: syslinux-xcat
%endif
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
mkdir -p $RPM_BUILD_ROOT/etc/xcat/conf.orig
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d/
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
# cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat.conf
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf
cp %{SOURCE3} $RPM_BUILD_ROOT/etc/xCATSN
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/xcat/conf.orig/xcat.conf.apach22
cp %{SOURCE6} $RPM_BUILD_ROOT/etc/xcat/conf.orig/xcat.conf.apach24

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/
tar zxf %{SOURCE5}

%else
mkdir -p $RPM_BUILD_ROOT/etc/
mkdir -p $RPM_BUILD_ROOT/opt/xcat/
cp %{SOURCE3} $RPM_BUILD_ROOT/etc/xCATSN

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cp %{SOURCE5} $RPM_BUILD_ROOT/%{prefix}/share/xcat
gunzip -f templates.tar.gz
tar -xf templates.tar
rm templates.tar

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
%ifos linux
#Apply the correct httpd/apache configuration file according to the httpd/apache version
if [ -n "$(httpd -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/httpd/conf.d/xcat.conf
   cp /etc/xcat/conf.orig/xcat.conf.apach24 /etc/httpd/conf.d/xcat.conf
fi

if [ -n "$(apachectl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/apache2/conf.d/xcat.conf
   cp /etc/xcat/conf.orig/xcat.conf.apach24 /etc/apache2/conf.d/xcat.conf
fi


%endif

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
fi
# for install or upgrade restart the daemon
%ifos linux
if [ -e "/etc/redhat-release" ]; then
    apachedaemon='httpd'
    apacheserviceunit='httpd.service'
else # SuSE
    apachedaemon='apache2'
fi
# start xcatd on linux
[ -e "/etc/init.d/$apachedaemon" ] && chkconfig $apachedaemon on
[ -e "/usr/lib/systemd/system/$apacheserviceunit"  ] && systemctl enable $apacheserviceunit 
if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
          XCATROOT=$RPM_INSTALL_PREFIX0 /etc/init.d/xcatd restart
          [ -e "/etc/init.d/$apachedaemon" ] && /etc/init.d/$apachedaemon reload 
          [ -e "/usr/lib/systemd/system/$apacheserviceunit"  ] && systemctl reload $apacheserviceunit 
fi
    echo "xCATsn is now installed"
%else
# start xcatd on  AIX
  XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/restartxcatd 
    echo "xCATsn is now installed"

%endif

# Run mknb if xCAT-genesis-scripts-x86_64 changed
%ifos linux
# prevent running it during install into chroot image and only run it if xCAT-genesis-scripts-x86_64
# was recently updated.
if [ -f "/proc/cmdline" -a -f "/etc/xcat/genesis-scripts-updated" ]; then
  rm -f /etc/xcat/genesis-scripts-updated
  # On the SN do not run mknb if we are sharing /tftpboot with the MN
  SHAREDTFTP=`/opt/xcat/sbin/tabdump site | grep sharedtftp | cut -d'"' -f 4`
  if [ "$SHAREDTFTP" != "1" ]; then
      . /etc/profile.d/xcat.sh
      echo Running '"'mknb `uname -m`'"', triggered by the installation/update of xCAT-genesis-scripts-x86_64 ...
      mknb `uname -m`
    fi
fi
%endif


%clean

%files
%{prefix}
# one for sles, one for rhel. yes, it's ugly...
%ifos linux
/etc/xcat/conf.orig/xcat.conf.apach24
/etc/xcat/conf.orig/xcat.conf.apach22
/etc/httpd/conf.d/xcat.conf
/etc/apache2/conf.d/xcat.conf
%endif
/etc/xCATSN
%defattr(-,root,root)
