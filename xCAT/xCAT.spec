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
%endif
%endif

Requires: rsync

%ifos linux
Requires: httpd nfs-utils nmap bind perl(CGI)
# on RHEL7, need to specify it explicitly
Requires: net-tools
Requires: /usr/bin/killall
# DHCP backend resolved at INSTALL time (not build time) via an RPM rich
# dependency, so a single flat xcat-core build is correct on every EL: el10+
# dropped ISC dhcp from its distro and uses Kea; el8/el9 use ISC dhcpd. SLES
# has no "system-release" provide, so the condition is false there and it
# falls to dhcp-server (/usr/sbin/dhcpd), preserving prior behavior.
# system-release is versioned per release package (el10=10.x, el9=9.x, el8=8.x).
Requires: (kea if (system-release >= 10) else /usr/sbin/dhcpd)
Requires: (kea-hooks if (system-release >= 10))
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
Requires: xnba-undi >= 1.21.1-1
Requires: syslinux-xcat >= 6.03-1
Requires: ipmitool-xcat >= 1.8.18-4
%endif

%ifos linux
%ifarch ppc ppc64 ppc64le
# Mixed-arch management nodes also need the x86 PXE stack kept current.
Requires: xnba-undi >= 1.21.1-1
Requires: syslinux-xcat >= 6.03-1
Requires: ipmitool-xcat >= 1.8.18-4
%endif
%endif

%ifos linux
%ifarch riscv64
# riscv64 management nodes manage BMC based nodes; the x86 PXE loaders are
# x86-only packages and riscv64 nodes boot through UEFI and grub2.
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
%else
rm -rf postscripts
cp %{SOURCE2} /opt/freeware/src/packages/BUILD
gunzip -f postscripts.tar.gz
tar -xf postscripts.tar
%endif

%build

%ifos linux
# rpm fixes each config file's fate before %pre runs, so a migration there can
# delete an active file rpm has already decided to leave as xcat.conf.rpmnew.
# %pretrans runs before that decision.  It is Lua because a pre-transaction
# scriptlet cannot rely on any dependency being unpacked yet.
%pretrans -p <lua>
-- Older packages shipped xcat.conf as ordinary payload and then rewrote it
-- from conf.orig in %post, so rpm's recorded digest cannot tell a stock file
-- from a customised one.  Compare against the outgoing package's templates,
-- still on disk at this point, and drop only a file that still matches one.
if arg[2] and tonumber(arg[2]) == 1 then return end

local function contents(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local data = handle:read("*a")
    handle:close()
    return data
end

local templates = { contents("/etc/%httpconfigdir/conf.orig/xcat.conf.apach24"),
                    contents("/etc/%httpconfigdir/conf.orig/xcat.conf.apach22") }

for _, active in ipairs({ "/etc/httpd/conf.d/xcat.conf",
                          "/etc/apache2/conf.d/xcat.conf" }) do
    -- A symlink or any other non-regular path is treated as locally managed.
    if posix.stat(active, "type") == "regular" then
        local current = contents(active)
        for _, template in ipairs(templates) do
            if current and current == template then
                os.remove(active)
                break
            end
        end
    end
end
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
%if 0%{?fedora} || 0%{?rhel} >= 7 || 0%{?suse_version} >= 1200
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


%post
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

mkdir -p /var/log/xcat
date >> /var/log/xcat/upgrade.log
xcatupgradeout=$(mktemp /tmp/xcat-upgrade.XXXXXX)
$RPM_INSTALL_PREFIX0/sbin/xcatconfig -u -V > "$xcatupgradeout" 2>&1
cat "$xcatupgradeout" >> /var/log/xcat/upgrade.log

# xcatconfig reports a failed mknb into the log, where an upgrade scrolls past
# it and the node is left without a genesis image for no apparent reason. Repeat
# it on the terminal. Only this run is examined, since the log is appended to.
if grep -q "command returned error code" "$xcatupgradeout"; then
    echo "WARNING: mknb did not complete, so the Genesis netboot image may be missing or out of date."
    echo "         See /var/log/xcat/upgrade.log, then rerun 'mknb <arch>' once the cause is resolved."
fi
rm -f "$xcatupgradeout"

# rpm has either updated a stock xcat.conf or preserved a modified one and left
# the new file as xcat.conf.rpmnew.  Reload an active web server so an updated
# stock configuration takes effect, but do not manage services in a chroot.
if [ -f "/proc/cmdline" ] && [ "x$(stat -c '%i %d' /)" == "x$(stat -c '%i %d' /proc/1/root/. 2>/dev/null)" ]; then
    if [ -e "/etc/redhat-release" ]; then
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
