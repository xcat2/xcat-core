Summary: Server and configuration utilities of the xCAT management project
Name: xCAT-server
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-server-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifnos linux
AutoReqProv: no
%endif

# AIX will build with an arch of "ppc"
# also need to fix Requires for AIX
%ifos linux
BuildArch: noarch
Requires: perl-IO-Socket-SSL perl-XML-Simple perl-IO-Tty
%endif

Requires: perl-xCAT >= %{epoch}:%(cat Version|cut -d. -f 1,2)
Requires: xCAT-client  >= %{epoch}:%(cat Version|cut -d. -f 1,2)

Provides: xCAT-server = %{epoch}:%{version}

%description
xCAT-server provides the core server and configuration management components of xCAT.  This package should be installed on your management server

%prep
%setup -q -n xCAT-server
%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
#mkdir -p $RPM_BUILD_ROOT/%{prefix}/rc.d
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/install
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ca
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/scripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/rollupdate
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/sles
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
mkdir -p $RPM_BUILD_ROOT/opt/xcat/xdsh/Context
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/samples
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/pcp
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/samples
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT

set +x
%ifos linux
cp -a share/xcat/install/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/install/
cp -a share/xcat/netboot/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/
%else
cp -hpR share/xcat/install/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/install/
cp -hpR share/xcat/netboot/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/netboot/
%endif

%ifos linux
pwd
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

cp share/xcat/scripts/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/scripts
cp share/xcat/tools/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/tools
cp share/xcat/rollupdate/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/rollupdate
cp share/xcat/cons/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons
cp share/xcat/ib/scripts/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts
cp share/xcat/ib/netboot/sles/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/sles
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/scripts/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/share/xcat/ib/netboot/sles/*
ln -sf /%{prefix}/share/xcat/cons/hmc $RPM_BUILD_ROOT/%{prefix}/share/xcat/cons/ivm

cp lib/xcat/plugins/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/*

cp lib/perl/xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*
set -x

# For now, don't ship these plugins - to avoid AIX dependency.
%ifnos linux
rm $RPM_BUILD_ROOT/%{prefix}/sbin/stopstartxcatd
#rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/blade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpblade.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/hpilo.pm
#rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/ipmi.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/nodediscover.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/switch.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/xen.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/kvm.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/vbox.pm
rm $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/activedirectory.pm
%endif

cp lib/xcat/dsh/Context/* $RPM_BUILD_ROOT/opt/xcat/xdsh/Context
chmod 644 $RPM_BUILD_ROOT/opt/xcat/xdsh/Context/*

set +x
cp -r lib/xcat/monitoring/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/*

chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/samples
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/samples/*
chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/pcp
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/pcp/*

cp -r lib/xcat/schema/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/*

chmod 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/samples
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema/samples/*
set -x


cp lib/xcat/shfunctions $RPM_BUILD_ROOT/%{prefix}/lib
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/shfunctions
mkdir -p $RPM_BUILD_ROOT/etc/init.d
cp etc/init.d/xcatd $RPM_BUILD_ROOT/etc/init.d
#TODO: the next has to me moved to postscript, to detect /etc/xcat vs /etc/opt/xcat
mkdir -p $RPM_BUILD_ROOT/etc/xcat
cp etc/xcat/postscripts.rules $RPM_BUILD_ROOT/etc/xcat/

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-server
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-server
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-server/*
#echo $RPM_BUILD_ROOT %{prefix}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
%{prefix}
/etc/xcat
/etc/init.d/xcatd

%changelog
* Fri Nov 20 2007 - Jarrod Johnson <jbjohnso@us.ibm.com>
- Changes for relocatible rpm.

* Wed May 2 2007 - Norm Nott <nott@us.ibm.com>
- Made changes to make this work on AIX

* Tue Feb 27 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Spawn server rpm for the server half of things, fix requires

* Tue Feb 20 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Start core rpm for 1.3 work

%post
%ifos linux
ln -sf $RPM_INSTALL_PREFIX0/sbin/xcatd /usr/sbin/xcatd
if [ -x /usr/lib/lsb/install_initd ]; then
  /usr/lib/lsb/install_initd /etc/init.d/xcatd
elif [ -x /sbin/chkconfig ]; then
  /sbin/chkconfig --add xcatd
else
  echo "Unable to register init scripts on this system"
fi
if [ "$1" -gt "1" ]; then #only on upgrade...
  #migration issue for monitoring
  XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab filename=monitorctrl.pm notification -d
 
  if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    /etc/init.d/xcatd reload
  fi
fi
%else
if [ "$1" -gt "1" ]; then #only on upgrade for AIX...
    #migration issue for monitoring
    XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab filename=monitorctrl.pm notification -d 

    XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/restartxcatd -r
fi  
%endif

%preun
%ifos linux
if [ $1 == 0 ]; then  #This means only on -e
	if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
  		/etc/init.d/xcatd stop
  	fi
  if [ -x /usr/lib/lsb/remove_initd ]; then
      /usr/lib/lsb/remove_initd /etc/init.d/xcatd
  elif [ -x /sbin/chkconfig ]; then
    /sbin/chkconfig --del xcatd
  fi
  rm -f /usr/sbin/xcatd  #remove the symbolic
fi
%endif




