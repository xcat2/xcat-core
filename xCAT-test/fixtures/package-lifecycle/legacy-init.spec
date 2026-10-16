Name: xCAT-server
Version: 2.18.0
Release: 1
Epoch: 4
Summary: Legacy init payload ownership fixture
License: EPL
BuildArch: noarch
Prefix: /opt/xcat

%description
Init script and service unit owned as ordinary payload before the compatibility helper.

%install
mkdir -p %{buildroot}/etc/init.d %{buildroot}/usr/lib/systemd/system
cp %{xcat_source}/xCAT-server/etc/init.d/xcatd %{buildroot}/etc/init.d/xcatd
cp %{xcat_source}/xCAT-server/etc/init.d/xcatd.service %{buildroot}/usr/lib/systemd/system/xcatd.service
chmod 755 %{buildroot}/etc/init.d/xcatd

%files
%defattr(-,root,root)
/etc/init.d/xcatd
/usr/lib/systemd/system/xcatd.service
