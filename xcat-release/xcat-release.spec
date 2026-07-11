Summary: xCAT repository configuration
Name: xcat-release
Version: %{?version:%{version}}%{!?version:%(cat Version)}
Release: %{?release:%{release}}%{!?release:%(cat Release)}
License: EPL
URL: https://xcat.org/
Source0: xcat-release-%{version}.tar.gz
BuildArch: noarch

%description
Installs the xCAT core and dependency repository definitions and the public
signing key used to verify their packages.

%prep
%setup -q -n xcat-release

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{_sysconfdir}/yum.repos.d
mkdir -p %{buildroot}%{_sysconfdir}/pki/rpm-gpg
install -m 0644 xcat-core.repo %{buildroot}%{_sysconfdir}/yum.repos.d/xcat-core.repo
install -m 0644 xcat-dep.repo %{buildroot}%{_sysconfdir}/yum.repos.d/xcat-dep.repo
install -m 0644 RPM-GPG-KEY-xCAT %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-xCAT

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/xcat-core.repo
%config(noreplace) %{_sysconfdir}/yum.repos.d/xcat-dep.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-xCAT

%changelog
* Sat Jul 11 2026 xCAT Project <xcat-user@lists.sourceforge.net>
- Add the xCAT repository bootstrap package
