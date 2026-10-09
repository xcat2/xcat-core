Summary: SELinux policy module for the xCAT management and service nodes
Name: xCAT-selinux
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-selinux-%{version}.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
BuildArch: noarch

BuildRequires: selinux-policy-devel
BuildRequires: bzip2
Requires: selinux-policy-targeted
Requires(pre): libselinux-utils
Requires(post): policycoreutils
Requires(post): libselinux-utils
Requires(posttrans): policycoreutils
Requires(posttrans): libselinux-utils

%description
xCAT-selinux labels /install for the services that read it, and lets httpd
serve /tftpboot and xcatws.cgi connect to xcatd. It does not change the
SELinux mode.

%prep
%setup -q -n xCAT-selinux

%build
# One noarch package serves EL8 to EL10, and EL8 reads module versions up to 19.
make -f %{_datadir}/selinux/devel/Makefile CHECKMODULE="%{_bindir}/checkmodule -M -c 19" xcat.pp
bzip2 -9 xcat.pp

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_datadir}/selinux/packages/targeted
install -m 0644 xcat.pp.bz2 $RPM_BUILD_ROOT%{_datadir}/selinux/packages/targeted/

%files
%defattr(-,root,root)
%{_datadir}/selinux/packages/targeted/xcat.pp.bz2

%pre
%selinux_relabel_pre -s targeted

%post
%selinux_modules_install -s targeted %{_datadir}/selinux/packages/targeted/xcat.pp.bz2

%postun
%selinux_modules_uninstall -s targeted xcat

%posttrans
%selinux_relabel_post -s targeted
if selinuxenabled && [ -d /install ]; then
    restorecon -R /install || :
fi
