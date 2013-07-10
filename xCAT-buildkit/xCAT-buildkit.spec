Summary: xCAT buildkit tools and sample kit
Name: xCAT-buildkit
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: Applications/System
Source: xCAT-buildkit-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

#%ifnos linux
AutoReqProv: no
#%endif

# AIX will build with an arch of "ppc"
# also need to fix Requires for AIX
%ifos linux
BuildArch: noarch
#Requires: 
%endif

# No dependencies on any other xCAT rpms
# so that this rpm can be installed in a separate build server
Requires: /usr/bin/rpmbuild

Provides: xCAT-buildkit = %{epoch}:%{version}

%description
xCAT-buildkit provides the buildkit tool and sample kit files to build an xCAT kit.

%prep
%setup -q -n xCAT-buildkit
%build
# Convert pods to man pages and html pages
mkdir -p share/man/man1
mkdir -p share/doc/man1
pod2man pods/man1/buildkit.1.pod > share/man/man1/buildkit.1
pod2html pods/man1/buildkit.1.pod > share/doc/man1/buildkit.1.html



%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits
mkdir -p $RPM_BUILD_ROOT/%{prefix}/bin
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/man/man1
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/man1

# These were built dynamically in the build phase
cp share/man/man1/* $RPM_BUILD_ROOT/%{prefix}/share/man/man1
chmod 444 $RPM_BUILD_ROOT/%{prefix}/share/man/man1/*
cp share/doc/man1/* $RPM_BUILD_ROOT/%{prefix}/share/doc/man1
chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/man1/*


%ifos linux
cp -aR share/xcat/kits/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits/
#chmod -R 644 $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits/*
find $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits -type d -exec chmod 755 {} \;
find $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits -type f -exec chmod 644 {} \;
cp -a lib/perl/xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT
#chmod -R 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*
find $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT -type d -exec chmod 755 {} \;
find $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT -type f -exec chmod 644 {} \;
cp -a bin/* $RPM_BUILD_ROOT/%{prefix}/bin/
chmod -R 755 $RPM_BUILD_ROOT/%{prefix}/bin/*
%else
cp -hpR share/xcat/kits/* $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits/
chmod -R 644 $RPM_BUILD_ROOT/%{prefix}/share/xcat/kits/*
cp -hpR lib/perl/xCAT/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/
chmod -R 755 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT/*
cp -hpR bin/* $RPM_BUILD_ROOT/%{prefix}/bin/
chmod -R 755 $RPM_BUILD_ROOT/%{prefix}/bin/*
%endif

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-buildkit
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-buildkit
#chmod 644 $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-buildkit/*
find $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-buildkit -type d -exec chmod 755 {} \;
find $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT-buildkit -type f -exec chmod 644 {} \;
#echo $RPM_BUILD_ROOT %{prefix}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)
#%doc LICENSE.html
%{prefix}

%changelog

%pre
# only need to check on AIX
%ifnos linux
if [ -x /usr/sbin/emgr ]; then          # Check for emgr cmd
	/usr/sbin/emgr -l 2>&1 |  grep -i xCAT   # Test for any xcat ifixes -  msg and exit if found
	if [ $? = 0 ]; then
		echo "Error: One or more xCAT emgr ifixes are installed. You must use the /usr/sbin/emgr command to uninstall each xCAT emgr ifix prior to RPM installation."
		exit 2
	fi
fi
%endif

%post

%preun




