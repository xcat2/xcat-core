
Summary: Web Interface for CSM
Name: xcat.web
Version: 0.1
Release: 7
Group: System Management
Copyright: IBM Corp.
Packager: IBM Corp. <http://xcat.org>
URL: http://xcat.org
Vendor: IBM Corp.
Source0: N/A
NoSource: 0

# AutoReqProv: no

Requires: httpd

%description
Provides a browser-based interface for xCAT (extreme Cluster Administration Tool).

%files
%defattr( 555, root, root, 755 )

/opt/xcat/web/*

# %attr( 555, bin, bin ) /usr/libexec/webmin/csm/GuiUtils.pm



%post
# Post-install script---------------------------------------------------

if [ "$1" = 1 ]    # initial install
then
  # Link to the apache conf file
  if [ -e "/etc/redhat-release" ]; then
  	/bin/rm -f /etc/httpd/conf.d/xcat.conf
  	/bin/ln -s /opt/xcat/web/etc/apache2/conf.d/xcat.conf /etc/httpd/conf.d/xcat.conf
  	/etc/init.d/httpd reload
  else
  	/bin/rm -f /etc/apache2/conf.d/xcat.conf
  	/bin/ln -s /opt/xcat/web/etc/apache2/conf.d/xcat.conf /etc/apache2/conf.d/xcat.conf
  	/etc/init.d/apache2 reload
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

