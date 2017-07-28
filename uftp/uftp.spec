Name:           uftp
Version:        4.9.3
Release:        1
Summary:        UFTP - Encrypted UDP based FTP with multicast

Group:          FTP Server
License:        GPL
URL:            http://uftp-multicast.sourceforge.net
Source0:        http://sourceforge.net/projects/uftp-multicast/files/source-tar/uftp-4.9.3.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:  openssl-devel

%description
UFTP is an encrypted multicast file transfer program, designed to securely, reliably, and efficiently transfer files to multiple receivers simultaneously. This is useful for distributing large files to a large number of receivers, and is especially useful for data distribution over a satellite link (with two way communication), where the inherent delay makes any TCP based communication highly inefficient. The multicast encryption scheme is based on TLS with extensions to allow multiple receivers to share a common key. UFTP also has the capability to communicate over disjoint networks separated by one or more firewalls (NAT traversal) and without full end-to-end multicast capability (multicast tunneling) through the use of a UFTP proxy server. These proxies also provide scalability by aggregating responses from a group of receivers.

%prep
%setup -q

%build
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
/usr/bin/uftp
/usr/sbin/uftpd
/usr/sbin/uftpproxyd
/usr/bin/uftp_keymgt
/usr/share/man/man1/uftp.1.gz
/usr/share/man/man1/uftp_keymgt.1.gz
/usr/share/man/man1/uftpd.1.gz
/usr/share/man/man1/uftpproxyd.1.gz

%changelog
