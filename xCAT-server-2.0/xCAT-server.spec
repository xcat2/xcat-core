Summary: Server and configuration utilities of the xCAT management project
Name: xCAT-server
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
Source: xCAT-server-2.0.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: %{_prefix}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

# AIX will build with an arch of "ppc"
# also need to fix Requires for AIX
%ifos linux
BuildArch: noarch
Requires: perl-IO-Socket-SSL perl-XML-Simple
%endif

Requires: perl-xCAT = %{version}
Requires: xCAT-client  = %{version}

Provides: xCAT-server = %{version}

%description
xCAT-server provides the core server and configuration management components of xCAT.  This package should be installed on your management server

%prep
%setup -q
%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/usr/sbin
mkdir -p $RPM_BUILD_ROOT/usr/share/xcat/install
mkdir -p $RPM_BUILD_ROOT/usr/share/xcat/ca
mkdir -p $RPM_BUILD_ROOT/usr/share/xcat/scripts
mkdir -p $RPM_BUILD_ROOT/usr/share/xcat/cons
mkdir -p $RPM_BUILD_ROOT/usr/lib/xcat/plugins
mkdir -p $RPM_BUILD_ROOT/opt/csm/pm/dsh/Context
mkdir -p $RPM_BUILD_ROOT/usr/lib/xcat/monitoring/samples


%ifos linux
cp -a usr/share/xcat/install/* $RPM_BUILD_ROOT/usr/share/xcat/install/
%else
cp -hpR usr/share/xcat/install/* $RPM_BUILD_ROOT/usr/share/xcat/install/
%endif

cp usr/sbin/* $RPM_BUILD_ROOT/usr/sbin
chmod 755 $RPM_BUILD_ROOT/usr/sbin/*

cp usr/share/xcat/ca/* $RPM_BUILD_ROOT/usr/share/xcat/ca
chmod 644 $RPM_BUILD_ROOT/usr/share/xcat/ca/*

cp usr/share/xcat/scripts/* $RPM_BUILD_ROOT/usr/share/xcat/scripts
cp usr/share/xcat/cons/* $RPM_BUILD_ROOT/usr/share/xcat/cons
chmod 755 $RPM_BUILD_ROOT/usr/share/xcat/cons/*
ln -sf /usr/share/xcat/cons/hmc $RPM_BUILD_ROOT/usr/share/xcat/cons/ivm

cp usr/lib/xcat/plugins/* $RPM_BUILD_ROOT/usr/lib/xcat/plugins
chmod 644 $RPM_BUILD_ROOT/usr/lib/xcat/plugins/*

cp usr/lib/xcat/dsh/Context/* $RPM_BUILD_ROOT/opt/csm/pm/dsh/Context
chmod 644 $RPM_BUILD_ROOT/opt/csm/pm/dsh/Context/*

cp -r usr/lib/xcat/monitoring/* $RPM_BUILD_ROOT/usr/lib/xcat/monitoring
chmod 644 $RPM_BUILD_ROOT/usr/lib/xcat/monitoring/*

chmod 755 $RPM_BUILD_ROOT/usr/lib/xcat/monitoring/samples
#cp usr/lib/xcat/monitoring/samples/* $RPM_BUILD_ROOT/usr/lib/xcat/monitoring/samples
chmod 644 $RPM_BUILD_ROOT/usr/lib/xcat/monitoring/samples/*

cp usr/lib/xcat/shfunctions $RPM_BUILD_ROOT/usr/lib/xcat
chmod 644 $RPM_BUILD_ROOT/usr/lib/xcat/shfunctions
mkdir -p $RPM_BUILD_ROOT/etc/xcat
mkdir -p $RPM_BUILD_ROOT/etc/init.d
cp etc/init.d/xcatd $RPM_BUILD_ROOT/etc/init.d
cp etc/xcat/postscripts.rules $RPM_BUILD_ROOT/etc/xcat/


%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc README
%doc LICENSE.html
/usr/sbin/*
/usr/share/xcat/install
/usr/share/xcat/ca/*
/usr/share/xcat/scripts/*
/usr/share/xcat/cons/*
/usr/lib/xcat/plugins/*
/usr/lib/xcat/monitoring
/usr/lib/xcat/shfunctions
/opt/csm
/etc/xcat
/etc/init.d/xcatd

%changelog
* Wed May 2 2007 - Norm Nott <nott@us.ibm.com>
- Made changes to make this work on AIX

* Tue Feb 27 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Spawn server rpm for the server half of things, fix requires

* Tue Feb 20 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Start core rpm for 1.3 work

%post

if [ -x /usr/lib/lsb/install_initd ]; then
  /usr/lib/lsb/install_initd /etc/init.d/xcatd
elif [ -x /sbin/chkconfig ]; then
  /sbin/chkconfig --add xcatd
else 
  echo "Unable to register init scripts on this system"
fi
if [ "$1" = "2" ]; then #only on upgrade...
    /etc/init.d/xcatd restart
fi

%preun
if [ $1 == 0 ]; then  #This means only on -e
  /etc/init.d/xcatd stop
  if [ -x /usr/lib/lsb/remove_initd ]; then
      /usr/lib/lsb/install_initd /etc/init.d/xcatd
  elif [ -x /sbin/chkconfig ]; then
    /sbin/chkconfig --del xcatd
  fi
fi
  



