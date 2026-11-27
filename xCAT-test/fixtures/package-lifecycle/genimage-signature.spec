Name: xcat-gpg-%{fixture_role}
Version: 1
Release: 1
Summary: Image signature test payload
License: EPL-1.0
BuildArch: noarch
AutoReqProv: no

%description
Payload for image package signature tests.

%install
mkdir -p %{buildroot}/usr/share/xcat-signature-test
printf '%s\n' '%{fixture_role}' > %{buildroot}/usr/share/xcat-signature-test/%{fixture_role}

%files
/usr/share/xcat-signature-test/%{fixture_role}
