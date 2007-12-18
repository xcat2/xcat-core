Summary: Web Interface for xCAT
Name: xCAT-web
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")

License: EPL
Group: Applications/System
Source: xCAT-web-2.0.tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
URL: http://xcat.org
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root

BuildArch: noarch
Provides: xCAT-web = %{version}

# httpd is provided by apache2 on SLES and httpd on RHEL
Requires: httpd
# we also require php4-session on SLES, but this does not exist on RHEL, so do not know how to do the Require

%description
Provides a browser-based interface for xCAT (extreme Cluster Administration Tool).

%prep
%setup -q
%build
%install

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT%{prefix}/web

cp -r * $RPM_BUILD_ROOT%{prefix}/web
chmod 755 $RPM_BUILD_ROOT%{prefix}/web/*

%files
%defattr(-,root,root)
# %defattr( 555, root, root, 755 )
%{prefix}


%post
# Post-install script---------------------------------------------------

if [ "$1" = 1 ]    # initial install
then
  # Set variables for apache because the names vary on redhat and suse
  if [ -e "/etc/redhat-release" ]; then
  	apachedaemon='httpd'
  	apacheuser='apache'
  else
  	apachedaemon='apache2'
  	apacheuser='wwwrun'
  fi

  # Update the apache config
  /bin/rm -f /etc/$apachedaemon/conf.d/xcat.conf
  /bin/ln -s /opt/xcat/web/etc/apache2/conf.d/xcat.conf /etc/$apachedaemon/conf.d/xcat.conf
  /etc/init.d/$apachedaemon reload

  # Config sudo - todo: change this when switch to xcat 2
  if ! egrep "^$apacheuser ALL=\(ALL\) NOPASSWD:ALL" /etc/sudoers; then
  	echo "$apacheuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
  fi

  #cp /etc/webmin/webmin.acl /etc/webmin/webmin.acl.orig
  #perl -e 'while (<>) { if (/^root:/ && !/\bcsm\b/) {s/$/ csm/;} print $_; }' /etc/webmin/webmin.acl.orig >/etc/webmin/webmin.acl
  #if [ `uname` = "Linux" ]; then
  # 	kill -1 `cat /var/webmin/miniserv.pid`
  #fi
fi

if [ "$1" = 1 ] || [ "$1" = 2 ]        # initial install, or upgrade and this is the newer rpm
then
  true
fi

%preun
# Pre-uninstall script -------------------------------------------------

if [ "$1" = 0 ]         # final rpm being removed
then
  # Remove link to the apache conf file
  if [ -e "/etc/redhat-release" ]; then
  	/bin/rm -f /etc/httpd/conf.d/xcat.conf
  else
  	/bin/rm -f /etc/apache2/conf.d/xcat.conf
  fi
fi

