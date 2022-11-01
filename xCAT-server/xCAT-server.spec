Summary: Server and configuration utilities of the xCAT management project
Name: xCAT-server
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-server-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifnos linux
AutoReqProv: no
%endif
%define debug_package %{nil}

%define fsm %(if [ "$fsm" = "1" ];then echo 1; else echo 0; fi)

# Define local variable from environment variable
%define pcm %(if [ "$pcm" = "1" ];then echo 1; else echo 0; fi)
%define notpcm %(if [ "$pcm" = "1" ];then echo 0; else echo 1; fi)
%define s390x %(if [ "$s390x" = "1" ];then echo 1; else echo 0; fi)
%define nots390x %(if [ "$s390x" = "1" ];then echo 0; else echo 1; fi)

# Define a different location for various httpd configs in s390x mode
%define httpconfigdir %(if [ "$s390x" = "1" ];then echo "xcathttpdsave"; else echo "xcat"; fi)

# Disable shebang mangling of python scripts
%undefine __brp_mangle_shebangs

# AIX will build with an arch of "ppc"
# also need to fix Requires for AIX
%ifos linux
BuildArch: noarch
# Note: ifarch/ifnarch does not work for noarch package, use environment variable instead

%if %s390x
Requires: perl-IO-Socket-SSL perl-XML-Simple perl-XML-Parser
%else
BuildRequires: perl-generators
Requires: perl-IO-Socket-SSL perl-XML-Simple perl-XML-Parser perl-Digest-SHA1 perl(LWP::Protocol::https) perl-XML-LibXML
%endif
Obsoletes: atftp-xcat
%endif

# The aix rpm cmd forces us to do this outside of ifos type stmts
%if %notpcm
%ifos linux
#
# PCM does not use or ship grub2-xcat
%if %nots390x
Requires: grub2-xcat >= 2.02-0.76.el7.1.snap201905160255 perl-Net-HTTPS-NB perl-HTTP-Async
%endif
%endif
%endif

%if %fsm
# nothing needed here
%else
%ifos linux
# do this for non-fsm linux
Requires: perl-IO-Tty perl-Crypt-SSLeay make httpd
%endif
%endif

Requires: perl-xCAT   = 4:%{version}-%{release}
Requires: xCAT-client = 4:%{version}-%{release}

%description
xCAT-server provides the core server and configuration management components of xCAT.  This package should be installed on your management server

%define zvm %(if [ "$zvm" = "1" ];then echo 1; else echo 0; fi)

%prep
# %if %NOVERBOSE
# echo NOVERBOSE is on
# set +x
# %elseif
# set -x
# %endif

%setup -q -n xCAT-server
%build
# build the tools readme files from the --help output of all of the tools
./build-readme

%install
rm -rf $RPM_BUILD_ROOT
#cp foo bar
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
#mkdir -p $RPM_BUILD_ROOT/%{prefix}/rc.d
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/install
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ca
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/mypostscript
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/scripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/samples
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/conf
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/rollupdate
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/installp_bundles
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/image_data
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/sles
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/rh
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts/Mellanox
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/devicetype
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/hamn
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/xdsh/Context
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/samples
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/pcp
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/Confluent
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/samples
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT

%ifos linux
cp -a share/xcat/install/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/install/
cp -a share/xcat/netboot/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/
%else
cp -hpR share/xcat/install/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/install/
cp -hpR share/xcat/netboot/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/
%endif

%ifos linux
# pwd
cp -d sbin/* $RPM_BUILD_ROOT/%{prefix}/sbin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/*
cp -d bin/* $RPM_BUILD_ROOT/%{prefix}/bin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/bin/*
%else
cp -h sbin/* $RPM_BUILD_ROOT/%{prefix}/sbin
chmod -h 755 $RPM_BUILD_ROOT/%{prefix}/sbin/*
cp -h bin/* $RPM_BUILD_ROOT/%{prefix}/bin
chmod -h 755 $RPM_BUILD_ROOT/%{prefix}/bin/*
%endif
#cp rc.d/* $RPM_BUILD_ROOT/%{prefix}/rc.d
#chmod 755 $RPM_BUILD_ROOT/%{prefix}/rc.d/*

cp share/xcat/ca/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/ca
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/xcat/ca/*

cp share/xcat/mypostscript/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/mypostscript
cp share/xcat/scripts/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/scripts
cp share/xcat/conf/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/conf
cp -r share/xcat/samples/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/samples
cp -r share/xcat/tools/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools
cp -r share/xcat/hamn/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/hamn
cp share/xcat/rollupdate/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/rollupdate
cp share/xcat/installp_bundles/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/installp_bundles
cp share/xcat/image_data/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/image_data
cp share/xcat/cons/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons
ln -sf kvm $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/mic
cp -r share/xcat/ib/scripts/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts
cp share/xcat/ib/netboot/sles/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/sles
cp share/xcat/ib/netboot/rh/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/rh
cp -r share/xcat/devicetype/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/devicetype
ln -sf Jun $RPM_BUILD_ROOT/%{prefix}/share/xcat/devicetype/EthSwitch/Juniper

chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/sles/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/rh/*

cp lib/xcat/plugins/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/*

cp lib/perl/xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*

chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/sles/*.postinstall
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/rh/*.postinstall

# For now, don't ship these plugins on AIX to avoid AIX dependency.
%ifnos linux
rm $RPM_BUILD_ROOT/%{prefix}/sbin/stopstartxcatd
#rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/blade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpblade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpilo.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ipmi.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/nodediscover.pm
#rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/switch.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xen.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/kvm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/vbox.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/activedirectory.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/kit.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/confluent.pm
%endif

cp lib/xcat/dsh/Context/* $RPM_BUILD_ROOT/%{prefix}/xdsh/Context
chmod 644 $RPM_BUILD_ROOT/%{prefix}/xdsh/Context/*

cp -r lib/xcat/monitoring/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/*

chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/samples
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/samples/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/pcp
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/pcp/*

cp -r lib/xcat/Confluent/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/Confluent
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/Confluent/*

cp -r lib/xcat/schema/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/*

chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/samples
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/samples/*

# Don't ship these on zVM, to reduce dependencies
%if %zvm
rm $RPM_BUILD_ROOT/%{prefix}/sbin/stopstartxcatd
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/activedirectory.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/blade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpblade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpilo.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ipmi.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/nodediscover.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/switch.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xen.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/kvm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/vbox.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/aixinstall.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/slpdiscover.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/remoteimmsetup.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/IMMUtils.pm
#rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/RShellAPI.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/bmcconfig.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/bpa.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/esx.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/FIP.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/fsp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hmc.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ivm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/lsslp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/pxe.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/toolscenter.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/windows.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xcat2nim.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/rhevm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xnba.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/IPMI.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/SSHInteract.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/MellanoxIB.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/PPC.pm
# Can not remove this, because it is needed by Templates.pm
#rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/ADUtils.pm
rm $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/hmc
rm $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/ivm
rm $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/multiple
rm $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/fsp
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/snmpmon.pm
rm $RPM_BUILD_ROOT/%{prefix}/sbin/xcat_traphandler
%endif

# Don't ship these on FSM, to reduce dependencies
%if %fsm
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/installp_bundles
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/install
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/add-on
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/aix
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/centos
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/debian
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/esxi/48.esxifixup
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/esxi/xcatsplash
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/fedora*
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/imgutils
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/mic
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/rh
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/ol
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/devicetype
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/SL
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/sles
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/suse
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/syslinux
rm -rf $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/ubuntu

rm $RPM_BUILD_ROOT/%{prefix}/sbin/stopstartxcatd
rm $RPM_BUILD_ROOT/%{prefix}/sbin/rshell_api
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpblade.pm
rm $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools/detect_dhcpd
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/AAsn.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpilo.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ipmi.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/blade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/nodediscover.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/switch.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xen.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/kvm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/vbox.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/aixinstall.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/bmcconfig.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/bpa.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ddns.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/dhcp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/FIP.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/fsp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hmc.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ivm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/lsslp.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/slpdiscover.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/remoteimmsetup.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/IMMUtils.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/RShellAPI.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/pxe.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/toolscenter.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xcat2nim.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xnba.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/IPMI.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/SSHInteract.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/MellanoxIB.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/PPC.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/snmpmon.pm
rm $RPM_BUILD_ROOT/%{prefix}/sbin/xcat_traphandler
%endif


cp lib/xcat/shfunctions $RPM_BUILD_ROOT/%{prefix}/lib
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/shfunctions
%if %fsm
%else
mkdir -p $RPM_BUILD_ROOT/etc/init.d
cp etc/init.d/xcatd $RPM_BUILD_ROOT/etc/init.d
mkdir -p $RPM_BUILD_ROOT/usr/lib/systemd/system
cp etc/init.d/xcatd.service $RPM_BUILD_ROOT/usr/lib/systemd/system
%endif
#TODO: the next has to me moved to postscript, to detect /etc/xcat vs /etc/opt/xcat
mkdir -p $RPM_BUILD_ROOT/etc/%httpconfigdir

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-server
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-server
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-server/*
#echo $RPM_BUILD_ROOT %{prefix}

# genereate the configuration files for web service (REST API)
mkdir -p $RPM_BUILD_ROOT/%{prefix}/ws
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig

cp xCAT-wsapi/* $RPM_BUILD_ROOT/%{prefix}/ws

# PCM does not need xcatws.cgi
# xcatws.cgi causes xCAT-server requires perl-JSON, which is not shipped with PCM
%if %pcm
rm -f $RPM_BUILD_ROOT/%{prefix}/ws/xcatws.cgi
%endif

%if %nots390x
rm -f $RPM_BUILD_ROOT/%{prefix}/ws/zvmxcatws.cgi
%endif

%if %fsm
%else
echo "ScriptAlias /xcatrhevh %{prefix}/ws/xcatrhevh.cgi" > $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22
echo "ScriptAlias /xcatrhevh %{prefix}/ws/xcatrhevh.cgi" > $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24
%if %notpcm
%if %nots390x
echo "ScriptAlias /xcatws %{prefix}/ws/xcatws.cgi" >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22
echo "ScriptAlias /xcatws %{prefix}/ws/xcatws.cgi" >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24
%else
# Add in old version 1 REST-API and version 2 REST-API to z/VM, default to version 1
echo "ScriptAlias /xcatwsv2 %{prefix}/ws/xcatws.cgi" >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22
echo "ScriptAlias /xcatwsv2 %{prefix}/ws/xcatws.cgi" >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24
echo "ScriptAlias /xcatws %{prefix}/ws/zvmxcatws.cgi" >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22
echo "ScriptAlias /xcatws %{prefix}/ws/zvmxcatws.cgi" >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24
%endif
%endif

cat $RPM_BUILD_ROOT/%{prefix}/ws/xcat-ws.conf.apache22 >>  $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22
cat $RPM_BUILD_ROOT/%{prefix}/ws/xcat-ws.conf.apache24 >> $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24
#install lower version(<2.4) apache/httpd conf files by default
cp $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22 $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat-ws.conf
cp $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache22 $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat-ws.conf
%endif



rm -f $RPM_BUILD_ROOT/%{prefix}/ws/xcat-ws.conf.apache22
rm -f $RPM_BUILD_ROOT/%{prefix}/ws/xcat-ws.conf.apache24

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
%{prefix}
/etc/%httpconfigdir
%if %fsm
%else
/etc/init.d/xcatd
/usr/lib/systemd/system/xcatd.service
/etc/apache2/conf.d/xcat-ws.conf
/etc/httpd/conf.d/xcat-ws.conf
%endif

%changelog
* Fri Jul 6 2018 - Bin Xu <bxuxa@cn.ibm.com>
- Added systemd unit file

* Tue Nov 20 2007 - Jarrod Johnson <jbjohnso@us.ibm.com>
- Changes for relocatible rpm.

* Wed May 2 2007 - Norm Nott <nott@us.ibm.com>
- Made changes to make this work on AIX

* Tue Feb 27 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Spawn server rpm for the server half of things, fix requires

* Tue Feb 20 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Start core rpm for 1.3 work

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

# The Juniper directory is switched to Jun and a sylink is created
if [ -d $RPM_INSTALL_PREFIX0/share/xcat/devicetype/EthSwitch/Juniper ]; then
    # need to remove the old directory otherwise the symlink won't get creatd correctly
    rm -rf $RPM_INSTALL_PREFIX0/share/xcat/devicetype/EthSwitch/Juniper
fi

%post
%ifos linux
ln -sf $RPM_INSTALL_PREFIX0/sbin/xcatd /usr/sbin/xcatd
ln -sf $RPM_INSTALL_PREFIX0/share/xcat/install/sles $RPM_INSTALL_PREFIX0/share/xcat/install/sle
ln -sf $RPM_INSTALL_PREFIX0/share/xcat/netboot/sles $RPM_INSTALL_PREFIX0/share/xcat/netboot/sle

ln -sf $RPM_INSTALL_PREFIX0/share/xcat/install/centos $RPM_INSTALL_PREFIX0/share/xcat/install/centos-stream
ln -sf $RPM_INSTALL_PREFIX0/share/xcat/netboot/centos $RPM_INSTALL_PREFIX0/share/xcat/netboot/centos-stream
if [ "$1" = "1" ]; then #Only if installing for the first time..
   if [ -x /usr/lib/systemd/systemd ]; then
       /usr/bin/systemctl daemon-reload
       /usr/bin/systemctl enable xcatd.service
   elif [ -x /sbin/chkconfig ]; then
       /sbin/chkconfig --add xcatd
   elif [ -x /usr/lib/lsb/install_initd ]; then
       /usr/lib/lsb/install_initd /etc/init.d/xcatd
   else
     echo "Unable to register init scripts on this system"
   fi
fi

if [ "$1" -gt "1" ]; then #only on upgrade...
  if [ -x /usr/lib/systemd/systemd ]; then
    if [ -f /run/systemd/generator.late/xcatd.service ]; then
        # To cover the case upgrade from no xcatd systemd unit file (cannot enable by default for HA case)
        ls /etc/rc.d/rc?.d/S??xcatd >/dev/null 2>&1
        if [ "$?" = "0" ]; then
           [ -x /sbin/chkconfig ] && /sbin/chkconfig --del xcatd
           /usr/bin/systemctl daemon-reload
           /usr/bin/systemctl enable xcatd.service
        fi
    else
        /usr/bin/systemctl daemon-reload
    fi
  fi
  #migration issue for monitoring
  XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab filename=monitorctrl.pm notification -d
fi

%else
if [ "$1" -gt "1" ]; then #only on upgrade for AIX...
    #migration issue for monitoring
    XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab filename=monitorctrl.pm notification -d

fi
%endif

#Apply the correct httpd/apache configuration file according to the httpd/apache version
if [ -n "$(httpd -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/httpd/conf.d/xcat-ws.conf
   cp /etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24 /etc/httpd/conf.d/xcat-ws.conf
fi

if [ -n "$(apachectl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/apache2/conf.d/xcat-ws.conf
   cp /etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24 /etc/apache2/conf.d/xcat-ws.conf
fi

if [ -n "$(apache2ctl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
then
   rm -rf /etc/apache2/conf.d/xcat-ws.conf
   cp /etc/%httpconfigdir/conf.orig/xcat-ws.conf.apache24 /etc/apache2/conf.d/xcat-ws.conf
fi

exit 0

%preun
%ifos linux
if [ $1 == 0 ]; then  #This means only on -e
	if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
  		/etc/init.d/xcatd stop
  	fi

  if [ -x /usr/lib/systemd/systemd ]; then
       /usr/bin/systemctl disable xcatd.service
  elif [ -x /sbin/chkconfig ]; then
      /sbin/chkconfig --del xcatd
  elif [ -x /usr/lib/lsb/remove_initd ]; then
      /usr/lib/lsb/remove_initd /etc/init.d/xcatd
  fi
  rm -f /usr/sbin/xcatd  #remove the symbolic

fi
%endif

