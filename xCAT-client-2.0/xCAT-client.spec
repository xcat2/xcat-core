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
Prefix: /usr
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

mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/scripts

cp bin/* $RPM_BUILD_ROOT/%{prefix}/bin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/bin/*
cp sbin/* $RPM_BUILD_ROOT/%{prefix}/sbin
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/*

#cp usr/share/xcat/scripts/setup-local-client.sh $RPM_BUILD_ROOT/usr/share/xcat/scripts/setup-local-client.sh
#chmod 755 $RPM_BUILD_ROOT/usr/share/xcat/scripts/setup-local-client.sh

ln -sf xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rpower
ln -sf xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rscan
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/sbin/makedhcp
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/sbin/makehosts
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/sbin/nodeset
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/sbin/makeconservercf
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rbeacon
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rvitals
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rinv
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rspreset
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rsetboot
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rbootseq
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/reventlog
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/nodels
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/nodech
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/noderm
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rnetboot
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/getmacs
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/mkvm
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/rmvm
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/lsvm
ln -sf ../bin/xcatclient $RPM_BUILD_ROOT/%{prefix}/bin/chvm
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/sbin/tabdump
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/sbin/makedns
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/gettab
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/sbin/nodeadd
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/sbin/makenetworks
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/sbin/copycds
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/regnotif
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/unregnotif
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/startmon
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/stopmon
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT/%{prefix}/bin/updatemon
ln -sf ../bin/xcatDBcmds $RPM_BUILD_ROOT/%{prefix}/bin/mkdef
ln -sf ../bin/xcatDBcmds $RPM_BUILD_ROOT/%{prefix}/bin/chdef
ln -sf ../bin/xcatDBcmds $RPM_BUILD_ROOT/%{prefix}/bin/lsdef
ln -sf ../bin/xcatDBcmds $RPM_BUILD_ROOT/%{prefix}/bin/rmdef
ln -sf ../bin/xdsh $RPM_BUILD_ROOT/%{prefix}/bin/xdcp

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc README
%doc LICENSE.html
%{prefix}

%changelog
* Wed May 2 2007 - Norm Nott <nott@us.ibm.com>
- Made changes to make this work on AIX

* Tue Feb 20 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
- Start core rpm for 1.3 work

