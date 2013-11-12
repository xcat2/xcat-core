Summary: Meta-Metapackage for a common, default xCAT management node setup with OpenStack 
Name: xCAT-OpenStack
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
Source:  xCAT-OpenStack-%(cat Version).tar.gz

Provides: xCAT-OpenStack = %{version}
Requires: xCAT

%description
xCAT-OpenStack is an xCAT management node package intended for at-scale 
management with OpenStack, including hardware management and software 
management.

%prep
%setup -q -n xCAT-OpenStack

%build
# Build the pod version of the man pages for each DB table.  It puts them in the man5 and man7 subdirs.
# Then convert the pods to man pages and html pages.
./db2man


%install
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
mkdir -p $RPM_BUILD_ROOT/install/postscripts
mkdir -p $RPM_BUILD_ROOT/install/chef-cookbooks
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/templates
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man5
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man5
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man7
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man7

cp -a lib/perl/xCAT_schema/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema
find $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema -type d -exec chmod 755 {} \;
find $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_schema -type f -exec chmod 644 {} \;

cp -a lib/perl/xCAT_plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/*

cp -a lib/perl/xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*

cp sbin/* $RPM_BUILD_ROOT/%{prefix}/sbin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/*

# These were built dynamically in the build phase
cp share/man/man5/* $RPM_BUILD_ROOT/%{prefix}/share/man/man5
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/man/man5/*
cp share/doc/man5/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man5
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man5/*
cp share/man/man7/* $RPM_BUILD_ROOT/%{prefix}/share/man/man7
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/man/man7/*
cp share/doc/man7/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man7
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man7/*

#ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/sbin/makeclouddata

#cd -
cp -a postscripts/* $RPM_BUILD_ROOT/install/postscripts
chmod 755 $RPM_BUILD_ROOT/install/postscripts/*

cp -a chef-cookbooks/* $RPM_BUILD_ROOT/install/chef-cookbooks
chmod 644 $RPM_BUILD_ROOT/install/chef-cookbooks/*

cp -a templates/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/templates
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/xcat/templates/*

%clean
rm -rf $RPM_BUILD_ROOT

%files
%{prefix}
/install/postscripts
%defattr(-,root,root)


%post
%ifos linux
  if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
      /etc/init.d/xcatd reload
    fi
  fi
%endif
exit 0

