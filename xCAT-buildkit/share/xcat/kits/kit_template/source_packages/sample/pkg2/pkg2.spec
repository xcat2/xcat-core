Summary: Pkg2 for Sample Kit
Name: pkg2
Version: 1
Release: 1
Epoch: 1
License: EPL
Group: Applications/System
Source: pkg2.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat-kitsample
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

%ifos linux
BuildArch: noarch
%endif

Provides: pkg2 = %{epoch}:%{version}

%description
Testing package builds for xCAT Sample Kit

%prep
%setup -q -n pkg2
%build
%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/%{name}/files
mkdir -p $RPM_BUILD_ROOT/etc/%{name}


set +x

%ifos linux
cp -a files/* $RPM_BUILD_ROOT/%{prefix}/%{name}/files/
chmod -R 755 $RPM_BUILD_ROOT/%{prefix}/%{name}/files/*
cp -a cfg/* $RPM_BUILD_ROOT/etc/%{name}/
chmod -R 644 $RPM_BUILD_ROOT/etc/%{name}/*
%endif

set -x


%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%{prefix}
/etc/%{name}

%changelog

%pre
if [ "$1" = "1" ] ; then
   echo "running pkg2 rpm pre section"
elif [ "$1" = "2" ] ; then
   echo "running pkg2 rpm preup section"
fi

%post
if [ "$1" = "1" ] ; then
   echo "running pkg2 rpm post section"
elif [ "$1" = "2" ] ; then
    echo "running pkg2 rpm postup section"
fi

%preun
echo "running pkg2 rpm preun section"

%postun
echo "running pkg2 rpm postun section"


