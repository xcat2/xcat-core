Name: %{test_package}
Version: 2.0
Release: 1
%if "%{test_package}" == "xCATsn"
Epoch: 4
%endif
Summary: Legacy Apache configuration ownership fixture
License: EPL
BuildArch: noarch

%description
Ordinary payload and saved defaults from before configuration-file ownership.

%install
mkdir -p %{buildroot}/etc/httpd/conf.d %{buildroot}/etc/apache2/conf.d %{buildroot}/etc/xcat/conf.orig
printf '# recorded payload\n' > %{buildroot}/etc/httpd/conf.d/xcat.conf
printf '# recorded payload\n' > %{buildroot}/etc/apache2/conf.d/xcat.conf
printf '# prior Apache 2.4 default\n' > %{buildroot}/etc/xcat/conf.orig/xcat.conf.apach24
printf '# prior Apache 2.2 default\n' > %{buildroot}/etc/xcat/conf.orig/xcat.conf.apach22

%files
%defattr(-,root,root)
/etc/httpd/conf.d/xcat.conf
/etc/apache2/conf.d/xcat.conf
/etc/xcat/conf.orig
