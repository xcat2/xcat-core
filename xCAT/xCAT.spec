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
Source9: xcat-apache-pretrans.lua
%endif

Source7: xcat.conf.apach24
Source10: xcat-upgrade-functions.sh

# These postscripts also execute on FreeBSD, which requires /bin/sh.
%global __brp_mangle_shebangs_exclude_from ^/install/postscripts/((syslog|remoteshell|syncfiles|confignetwork)([.]freebsd)?|confignetwork-(dhclient|dhcp6|ipoib-dhcp4)[.]freebsd|ospkgs|otherpkgs|xcatpackages[.]freebsd|(configzfs|configstorage)[.]freebsd)$

Provides: xCAT = %{version}
Conflicts: xCATsn
Requires: perl-DBD-SQLite
Requires: xCAT-client = 4:%{version}-%{release}
Requires: xCAT-server = 4:%{version}-%{release}

%define pcm %(if [ "$pcm" = "1" ];then echo 1; else echo 0; fi)
%define notpcm %(if [ "$pcm" = "1" ];then echo 0; else echo 1; fi)

%define s390x %(if [ "$s390x" = "1" ];then echo 1; else echo 0; fi)
%define nots390x %(if [ "$s390x" = "1" ];then echo 0; else echo 1; fi)

# Match xCAT-genesis-scripts package naming by build architecture.
%ifarch i386 i586 i686 x86
%define genesistarch x86
%endif
%ifarch x86_64
%define genesistarch x86_64
%endif
%ifarch ppc ppc64 ppc64le
%define genesistarch ppc64
%endif
%ifarch aarch64
%define genesistarch aarch64
%endif

# Define a different location for various httpd configs in s390x mode
%define httpconfigdir %(if [ "$s390x" = "1" ];then echo "xcathttpdsave"; else echo "xcat"; fi)

%if %nots390x
Requires: xCAT-probe  = 4:%{version}-%{release}
# Only where a legacy Genesis package exists for the build architecture. riscv64 has
# none: its image ships as xCAT-genesis-openembedded-riscv64, which mknb consumes
# directly, and an unset genesistarch would otherwise emit an unsatisfiable name.
%{?genesistarch:Requires: xCAT-genesis-scripts-%{genesistarch} = 1:%{version}-%{release}}
# RPM 4.11 does not recognize weak dependency tags.
%if 0%{?fedora} || 0%{?rhel} >= 8 || 0%{?suse_version} >= 1500
Recommends: xCAT-genesis-openembedded-x86_64
Recommends: xCAT-genesis-openembedded-ppc64le
Recommends: xCAT-genesis-openembedded-riscv64
Recommends: xCAT-genesis-openembedded-s390x
%endif
%endif

Requires: rsync

%ifos linux
Requires: httpd nfs-utils nmap bind perl(CGI)
# on RHEL7, need to specify it explicitly
Requires: net-tools
Requires: /usr/bin/killall
# makentp/setupntp configure the MN as an NTP server for its compute nodes and support chronyd/ntpd
# only. chrony is the default on EL7+/SLES15+ (and the only option on EL8+); ntp covers the rest.
Requires: (chrony or ntp)
# openEuler's system-release version does not identify an EL release.
Requires: (/usr/sbin/dhcpd if openEuler-release else ((kea and kea-hooks) if (system-release >= 10) else /usr/sbin/dhcpd))
# On RHEL this pulls in openssh-server, on SLES it pulls in openssh
Requires: /usr/bin/ssh
%if %nots390x
Requires: /usr/sbin/in.tftpd
Requires: xCAT-buildkit = 4:%{version}-%{release}
# Stty is only needed for rcons on ppc64 nodes, but for mixed clusters require it on both x and p
Requires: perl-IO-Stty >= 0.04-5
%endif
%endif

%ifos linux
Requires: goconserver >= 0.3.3-snap202011021058
%endif

%ifarch i386 i586 i686 x86 x86_64
Requires: ipxe-xcat >= 2.0.0-1
Requires: xnba-undi >= 1.21.1-1
Requires: syslinux-xcat >= 6.03-1
Requires: ipmitool-xcat >= 1.8.18-4
%endif

%ifos linux
%ifarch ppc ppc64 ppc64le
# Mixed-arch management nodes also need the x86 PXE stack kept current.
Requires: ipxe-xcat >= 2.0.0-1
Requires: xnba-undi >= 1.21.1-1
Requires: syslinux-xcat >= 6.03-1
Requires: ipmitool-xcat >= 1.8.18-4
%endif
%endif

%ifos linux
%ifarch riscv64
# riscv64 nodes boot through UEFI and grub2. A riscv64 management node can serve x86
# nodes, which boot the upstream iPXE loader.
Requires: ipxe-xcat >= 2.0.0-1
Requires: ipmitool-xcat >= 1.8.18-4
%endif
%endif

%ifos linux
%ifarch aarch64
# aarch64 nodes boot through UEFI and grub2. An aarch64 management node can serve x86
# nodes, which boot the upstream iPXE loader.
Requires: ipxe-xcat >= 2.0.0-1
Requires: ipmitool-xcat >= 1.8.18-4
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
cp %{SOURCE9} xcat-apache-pretrans.lua
%else
rm -rf postscripts
cp %{SOURCE2} /opt/freeware/src/packages/BUILD
gunzip -f postscripts.tar.gz
tar -xf postscripts.tar
%endif

%build

%ifos linux
# RPM decides configuration ownership before pre-install scripts run.
%pretrans -p <lua> -f xcat-apache-pretrans.lua
local template_dir = "/etc/%httpconfigdir/conf.orig"
%endif

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
chmod 644 etc/logrotate.d/xcat
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
# Pick the Apache generation at build time.  Selecting it in the post scriptlet
# instead rewrites a file rpm has already checksummed, defeating noreplace.
%if 0%{?fedora} || 0%{?rhel} >= 7 || 0%{?suse_version} >= 1200 || 0%{?openEuler}
cp %{SOURCE7} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf
cp %{SOURCE7} $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat.conf
%else
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat.conf
%endif
cp %{SOURCE7} $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat.conf.apach24
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat.conf.apach22
cp %{SOURCE5} $RPM_BUILD_ROOT/etc/xCATMN

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT


cat %{SOURCE10} > xcat-post.sh
cat >> xcat-post.sh <<'XCAT_POST'
%ifos linux
# On SUSE apache2, mod_headers is not loaded by default; enable it so the
# security response headers in xcat.conf take effect (a no-op where a2enmod
# is absent, e.g. httpd on EL where mod_headers is already loaded).
if [ -e /etc/apache2/conf.d/xcat.conf ] && command -v a2enmod >/dev/null 2>&1; then
    a2enmod headers >/dev/null 2>&1 || :
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

xcat_run_upgrade $RPM_INSTALL_PREFIX0/sbin/xcatconfig -u -V

# rpm has either updated a stock xcat.conf or preserved a modified one and left
# the new file as xcat.conf.rpmnew.  Reload an active web server so an updated
# stock configuration takes effect, but do not manage services in a chroot.
if [ -f "/proc/cmdline" ] && [ "x$(stat -c '%i %d' /)" == "x$(stat -c '%i %d' /proc/1/root/. 2>/dev/null)" ]; then
    if [ -e "/etc/redhat-release" ] || [ -e "/etc/openEuler-release" ]; then
        apachedaemon='httpd'
    else
        apachedaemon='apache2'
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$apachedaemon"; then
            systemctl reload "$apachedaemon" >/dev/null 2>&1 || :
        fi
    elif [ -x "/etc/init.d/$apachedaemon" ]; then
        /etc/init.d/$apachedaemon reload >/dev/null 2>&1 || :
    fi
fi
fi
exit 0
XCAT_POST

%post -f xcat-post.sh

%clean

%files
%{prefix}
# one for sles, one for rhel. yes, it's ugly...
/etc/%httpconfigdir/conf.orig/xcat.conf.apach24
/etc/%httpconfigdir/conf.orig/xcat.conf.apach22
%config(noreplace) /etc/httpd/conf.d/xcat.conf
%config(noreplace) /etc/apache2/conf.d/xcat.conf
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
