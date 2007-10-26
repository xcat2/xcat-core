Summary: xCAT perl libraries
Name: perl-xCAT
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: System Environment/Libraries
Source: perl-xCAT-2.0.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: %{_prefix}
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif

Provides: perl(xCAT) = %{version}

%description
Provides perl xCAT libraries for core functionality.  Required for all xCAT installations.
Includes xCAT::Table, xCAT::NodeRange, among others.

%prep
%setup -q -n perl-xCAT-%{version}

%build
perl Makefile.PL
%{__make} %{?mflags}

%install
%{__make} install DESTDIR=$RPM_BUILD_ROOT %{?mflags_install}
test "x$RPM_BUILD_ROOT" != "x" && rm -rf $RPM_BUILD_ROOT/%{_datadir} ||:
test "x$RPM_BUILD_ROOT" != "x" && rm -rf $RPM_BUILD_ROOT/%{_libdir}/perl5/5* ||:

find %{buildroot} -name "perllocal.pod" \
    -o -name ".packlist"                \
    -o -name "*.bs"                     \
    |xargs -i rm -f {}

#  ndebug - this seems to break the AIX build - need to investigate
%ifos linux
find %{buildroot}%{_prefix}             \
    -type d -depth                      \
    -exec rmdir {} \; 2>/dev/null
%endif

find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%clean
test "x$RPM_BUILD_ROOT" != "x" && rm -rf $RPM_BUILD_ROOT

%files -f files.list
%defattr(-, root, root)
%doc LICENSE.html

%changelog
* Wed May 2 2007 - Norm Nott nott@us.ibm.com
- Made changes to make this work on AIX

* Wed Jan 24 2007 Jarrod Johnson <jbjohnso@us.ibm.com>
-It begins

