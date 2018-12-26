Summary: Meta-package for a common, default xCAT setup
Name: xCAT
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
License: EPL
Group: Applications/System
URL: https://xcat.org/
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
Source1: xcat.conf
Source2: postscripts.tar.gz
Source3: templates.tar.gz
Source5: xCATMN

%ifos linux
Source4: prescripts.tar.gz
Source6: winpostscripts.tar.gz
Source8: etc.tar.gz
%endif

Source7: xcat.conf.apach24

Provides: xCAT = %{version}
Conflicts: xCATsn
Requires: perl-DBD-SQLite
Requires: xCAT-client = 4:%{version}-%{release}
Requires: xCAT-server = 4:%{version}-%{release}

%define pcm %(if [ "$pcm" = "1" ];then echo 1; else echo 0; fi)
%define notpcm %(if [ "$pcm" = "1" ];then echo 0; else echo 1; fi)

%define s390x %(if [ "$s390x" = "1" ];then echo 1; else echo 0; fi)
%define nots390x %(if [ "$s390x" = "1" ];then echo 0; else echo 1; fi)

# Define a different location for various httpd configs in s390x mode
%define httpconfigdir %(if [ "$s390x" = "1" ];then echo "xcathttpdsave"; else echo "xcat"; fi)

%if %nots390x
Requires: xCAT-probe  = 4:%{version}-%{release}
Requires: xCAT-genesis-scripts-x86_64 = 1:%{version}-%{release}
Requires: xCAT-genesis-scripts-ppc64  = 1:%{version}-%{release}
%endif

Requires: rsync

%ifos linux
Requires: httpd nfs-utils nmap bind perl(CGI)
# on RHEL7, need to specify it explicitly
Requires: net-tools
Requires: /usr/bin/killall
# On RHEL this pulls in dhcp, on SLES it pulls in dhcp-server
Requires: /usr/sbin/dhcpd
# On RHEL this pulls in openssh-server, on SLES it pulls in openssh
Requires: /usr/bin/ssh
%if %nots390x
Requires: /usr/sbin/in.tftpd
Requires: xCAT-buildkit
# Stty is only needed for rcons on ppc64 nodes, but for mixed clusters require it on both x and p
Requires: perl-IO-Stty
%endif
%endif

# The aix rpm cmd forces us to do this outside of ifos type stmts
%if %notpcm
%ifos linux
%if %nots390x
# PCM does not use or ship conserver
Requires: conserver-xcat
%endif
%endif
%endif

%ifos linux
Requires: goconserver
%endif

#support mixed cluster
%if %nots390x
Requires: elilo-xcat xnba-undi
%endif

%ifarch i386 i586 i686 x86 x86_64
Requires: syslinux
Requires: ipmitool-xcat >= 1.8.17-1
%endif

%ifos linux
%ifarch ppc ppc64 ppc64le
Requires: ipmitool-xcat >= 1.8.17-1
%endif
%endif

%if %notpcm
# PCM does not need or ship syslinux-xcat
%if %nots390x
Requires: syslinux-xcat
%endif
%endif

%description
xCAT is a server management package intended for at-scale management, including
hardware management and software management.

%prep
%ifos linux
tar zxf %{SOURCE2}
tar zxf %{SOURCE4}
tar zxf %{SOURCE6}
tar zxf %{SOURCE8}
%else
rm -rf postscripts
cp %{SOURCE2} /opt/freeware/src/packages/BUILD
gunzip -f postscripts.tar.gz
tar -xf postscripts.tar
%endif

%build

%pre
# this is now handled by requiring /usr/sbin/dhcpd
#if [ -e "/etc/SuSE-release" ]; then
    # In SuSE, dhcp-server provides the dhcp server, which is different from the RedHat.
    # When building the package, we cannot add "dhcp-server" into the "Requires", because RedHat doesn't
    # have such one package.
    # so there's only one solution, Yes, it looks ugly.
    #rpm -q dhcp-server >/dev/null
    #if [ $? != 0 ]; then
    #    echo ""
    #    echo "!! On SuSE, the dhcp-server package should be installed before installing xCAT !!"
    #    exit -1;
    #fi
#fi
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


%install
mkdir -p $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/logrotate.d
mkdir -p $RPM_BUILD_ROOT/etc/rsyslog.d
mkdir -p $RPM_BUILD_ROOT/install/postscripts
mkdir -p $RPM_BUILD_ROOT/install/prescripts
mkdir -p $RPM_BUILD_ROOT/install/kdump
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/

%ifos linux
tar zxf %{SOURCE3}
%else
cp %{SOURCE3} $RPM_BUILD_ROOT/%{prefix}/share/xcat
gunzip -f templates.tar.gz
tar -xf templates.tar
rm templates.tar
%endif

cd -
cd $RPM_BUILD_ROOT

%ifos linux
tar zxf %{SOURCE8}
%endif

cd -
cd $RPM_BUILD_ROOT/install

%ifos linux
tar zxf %{SOURCE2}
tar zxf %{SOURCE4}
tar zxf %{SOURCE6}
%else
cp %{SOURCE2} $RPM_BUILD_ROOT/install
gunzip -f postscripts.tar.gz
tar -xf postscripts.tar
rm postscripts.tar
%endif

chmod 755 $RPM_BUILD_ROOT/install/postscripts/*

rm LICENSE.html
mkdir -p postscripts/hostkeys
cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat.conf
cp %{SOURCE7} $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat.conf.apach24
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat.conf.apach22
cp %{SOURCE5} $RPM_BUILD_ROOT/etc/xCATMN

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT


%post
%ifos linux
#Apply the correct httpd/apache configuration file according to the httpd/apache version
if [ -n "$(httpd -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/httpd/conf.d/xcat.conf
   cp /etc/%httpconfigdir/conf.orig/xcat.conf.apach24 /etc/httpd/conf.d/xcat.conf
fi

if [ -n "$(apachectl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/apache2/conf.d/xcat.conf
   cp /etc/%httpconfigdir/conf.orig/xcat.conf.apach24 /etc/apache2/conf.d/xcat.conf
fi

if [ -n "$(apache2ctl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/apache2/conf.d/xcat.conf
   cp /etc/%httpconfigdir/conf.orig/xcat.conf.apach24 /etc/apache2/conf.d/xcat.conf
fi

# Let rsyslogd perform close of any open files
if [ -e /var/run/rsyslogd.pid ]; then
    kill -HUP $(</var/run/rsyslogd.pid) >/dev/null 2>&1 || :
elif [ -e /var/run/syslogd.pid ]; then
    kill -HUP $(</var/run/syslogd.pid) >/dev/null 2>&1 || :
fi
%endif

# create dir for the current pid
mkdir -p /var/run/xcat

%ifnos linux
. /etc/profile
%else
cp -f $RPM_INSTALL_PREFIX0/share/xcat/scripts/xHRM /install/postscripts/
. /etc/profile.d/xcat.sh
%endif
if [ "$1" = "1" ]; then #Only if installing for the first time..
$RPM_INSTALL_PREFIX0/sbin/xcatconfig -i
else
if [ -r "/tmp/xcat/installservice.pid" ]; then
  mv /tmp/xcat/installservice.pid /var/run/xcat/installservice.pid
fi
if [ -r "/tmp/xcat/udpservice.pid" ]; then
  mv /tmp/xcat/udpservice.pid /var/run/xcat/udpservice.pid
fi
if [ -r "/tmp/xcat/mainservice.pid" ]; then
  mv /tmp/xcat/mainservice.pid /var/run/xcat/mainservice.pid
fi

mkdir -p /var/log/xcat
date >> /var/log/xcat/upgrade.log
$RPM_INSTALL_PREFIX0/sbin/xcatconfig -u -V >> /var/log/xcat/upgrade.log
fi
exit 0

%clean

%files
%{prefix}
# one for sles, one for rhel. yes, it's ugly...
/etc/%httpconfigdir/conf.orig/xcat.conf.apach24
/etc/%httpconfigdir/conf.orig/xcat.conf.apach22
/etc/httpd/conf.d/xcat.conf
/etc/apache2/conf.d/xcat.conf
/etc/xCATMN
/install/postscripts
/install/prescripts
%ifos linux
%config /etc/logrotate.d/xcat
/etc/rsyslog.d/xcat-cluster.conf
/etc/rsyslog.d/xcat-compute.conf
/etc/rsyslog.d/xcat-debug.conf
/install/winpostscripts
%endif
%defattr(-,root,root)

%postun

if [ "$1" = "0" ]; then

%ifnos linux
if grep "^xcatd" /etc/inittab >/dev/null
then
/usr/sbin/rmitab xcatd >/dev/null
fi
%endif
true    # so on aix we do not end up with an empty if stmt
fi
