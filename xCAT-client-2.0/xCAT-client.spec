Summary: Core executables and data of the xCAT management project
Name: xCAT-client
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
Source: xCAT-client-2.0.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: %{_prefix}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

# AIX will build with an arch of "ppc"
%ifos linux
BuildArch: noarch
%endif

Provides: xCAT-client = %{version}

%description
xCAT-client provides the fundamental xCAT commands (chtab, chnode, rpower, etc) helpful in administrating systems at scale, with particular attention paid to large HPC clusters.

%prep
%setup -q
%build
%install

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/usr/bin
mkdir -p $RPM_BUILD_ROOT/usr/sbin
mkdir -p $RPM_BUILD_ROOT/usr/share/xcat/scripts

cp usr/bin/* $RPM_BUILD_ROOT/usr/bin
chmod 755 $RPM_BUILD_ROOT/usr/bin/*
cp usr/sbin/* $RPM_BUILD_ROOT/usr/sbin
chmod 755 $RPM_BUILD_ROOT/usr/sbin/*

#cp usr/share/xcat/scripts/setup-local-client.sh $RPM_BUILD_ROOT/usr/share/xcat/scripts/setup-local-client.sh
#chmod 755 $RPM_BUILD_ROOT/usr/share/xcat/scripts/setup-local-client.sh

ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rpower
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rscan
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/sbin/makedhcp
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/sbin/makehosts
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/sbin/nodeset
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/sbin/makeconservercf
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rbeacon
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rvitals
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rinv
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rspreset
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rsetboot
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rbootseq
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/reventlog
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/nodels
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/nodech
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/noderm
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rnetboot
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/getmacs
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/mkvm
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/rmvm
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/lsvm
ln -sf /usr/bin/xcatclient $RPM_BUILD_ROOT/usr/bin/chvm
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/sbin/tabdump
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/sbin/makedns
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/bin/gettab
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/sbin/nodeadd
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/sbin/makenetworks
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/sbin/copycds
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/bin/regnotif
ln -sf /usr/bin/xcatclientnnr $RPM_BUILD_ROOT/usr/bin/unregnotif
ln -sf /usr/bin/xcatDBcmds $RPM_BUILD_ROOT/usr/bin/mkdef
ln -sf /usr/bin/xcatDBcmds $RPM_BUILD_ROOT/usr/bin/chdef
ln -sf /usr/bin/xcatDBcmds $RPM_BUILD_ROOT/usr/bin/lsdef
ln -sf /usr/bin/xcatDBcmds $RPM_BUILD_ROOT/usr/bin/rmdef
ln -sf /usr/bin/xdsh $RPM_BUILD_ROOT/usr/bin/xdcp

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc README
%doc LICENSE.html
/usr/bin/*
/usr/sbin/*
#/usr/share/xcat/scripts/setup-local-client.sh

%changelog
* Wed May 2 2007 - Norm Nott <nott@us.ibm.com>
- Made changes to make this work on AIX

* Tue Feb 20 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Start core rpm for 1.3 work

