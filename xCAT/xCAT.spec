Summary: Meta-package for a common, default xCAT setup
Name: xCAT
Version: %(cat Version)
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
Source2: postscripts.tar.gz
Source3: templates.tar.gz
Source5: xCATMN 

%ifos linux
Source4: prescripts.tar.gz
Source6: winpostscripts.tar.gz
%endif

Source7: xcat.conf.apach24

Provides: xCAT = %{version}
Conflicts: xCATsn
Requires: xCAT-server xCAT-client perl-DBD-SQLite

%define pcm %(if [ "$pcm" = "1" ];then echo 1; else echo 0; fi)
%define notpcm %(if [ "$pcm" = "1" ];then echo 0; else echo 1; fi)

%ifos linux
Requires: httpd nfs-utils nmap bind perl(CGI)
# on RHEL7, need to specify it explicitly
Requires: net-tools
Requires: /usr/bin/killall 
# On RHEL this pulls in dhcp, on SLES it pulls in dhcp-server
Requires: /usr/sbin/dhcpd
# On RHEL this pulls in openssh-server, on SLES it pulls in openssh
Requires: /usr/bin/ssh
%ifnarch s390x
Requires: /etc/xinetd.d/tftp
Requires: xCAT-buildkit
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

%if %notpcm
%ifarch i386 i586 i686 x86 x86_64
# PCM does not need or ship syslinux-xcat
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
mkdir -p $RPM_BUILD_ROOT/etc/xcat/conf.orig
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d
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
cp %{SOURCE7} $RPM_BUILD_ROOT/etc/xcat/conf.orig/xcat.conf.apach24
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/xcat/conf.orig/xcat.conf.apach22
cp %{SOURCE5} $RPM_BUILD_ROOT/etc/xCATMN

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT


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

$RPM_INSTALL_PREFIX0/sbin/xcatconfig -u
fi
exit 0

%clean


%files
%{prefix}
# one for sles, one for rhel. yes, it's ugly...
/etc/xcat/conf.orig/xcat.conf.apach24
/etc/xcat/conf.orig/xcat.conf.apach22
/etc/httpd/conf.d/xcat.conf
/etc/apache2/conf.d/xcat.conf
/etc/xCATMN
/install/postscripts
/install/prescripts
%ifos linux
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

