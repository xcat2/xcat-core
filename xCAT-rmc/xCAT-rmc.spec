Summary: RMC monitoring plug-in for xCAT
Name: xCAT-rmc
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
Epoch: 4
License: EPL
Group: System Environment/Libraries
Source: xCAT-rmc-%(cat Version).tar.gz
Packager: IBM Corp.
Vendor: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif

Requires: perl-xCAT >= %{epoch}:%(cat Version)
Requires: xCAT-server  >= %{epoch}:%(cat Version|cut -d. -f 1,2)

Provides: xCAT-rmc = %{version}

%description
Provides RMC monitoring plug-in module for xCAT, configuration scripts, predefined conditions, responses and sensors.

%prep
%setup -q -n xCAT-rmc
%build
%install

rm -rf $RPM_BUILD_ROOT

mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/rmc
mkdir -p $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/TEAL

cp plugin/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring
cp -r resources $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_monitoring/rmc

cp scripts/* $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon
chmod 755 $RPM_BUILD_ROOT/%{prefix}/sbin/rmcmon/*

cp lib/perl/TEAL/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/TEAL


%clean
rm -rf $RPM_BUILD_ROOT

#find $RPM_BUILD_ROOT -type f | sed -e "s@$RPM_BUILD_ROOT@/@" > files.list

%files
%defattr(-, root, root)
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
needCopyFiles=0
if [ -f /etc/xCATMN ]; then
    #on MN
    needCopyFiles=1;
else
    #om SN
    mounted=0
    result=`mount |grep "/install " | grep nfs`
    if [ $? -eq 0 ]; then
	mounted=1
    fi
    if [ $mounted -eq 0 ]; then
	 needCopyFiles=1;
    fi
fi
    
if [ $needCopyFiles -eq 1 ]; then
    echo "Copying files to /install/postscripts directory..."
    mkdir -p /install/postscripts
    mkdir -p /install/postscripts/rmcmon/resources/node
    mkdir -p /install/postscripts/rmcmon/scripts
    cp $RPM_INSTALL_PREFIX0/sbin/rmcmon/configrmcnode /install/postscripts
    chmod 755 /install/postscripts/configrmcnode
    
    FILES_TO_COPY=`cat $RPM_INSTALL_PREFIX0/sbin/rmcmon/scripts_to_node|tr '\n' ' '` 
    for file in $FILES_TO_COPY
    do
	#echo "file=$file"
	cp $RPM_INSTALL_PREFIX0/sbin/rmcmon/$file /install/postscripts/rmcmon/scripts
    done
    chmod 755 /install/postscripts/rmcmon/scripts/*
    
    cp -r $RPM_INSTALL_PREFIX0/lib/perl/xCAT_monitoring/rmc/resources/node/* /install/postscripts/rmcmon/resources/node
fi  
    

%ifos linux
  if [ -f "/proc/cmdline" ]; then   # prevent running it during install into chroot image
    if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
      /etc/init.d/xcatd restart 
    fi
  fi
%else
  #restart the xcatd on if xCAT or xCATsn is installed already
  if [ -f $RPM_INSTALL_PREFIX0/sbin/xcatd  ]; then
    if [ -n "$INUCLIENTS" ] && [ $INUCLIENTS -eq 1 ]; then
      #Do nothing in not running system
      echo "Do not restartxcatd in not running system"
    else
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/restartxcatd -r
    fi     
  fi
%endif
exit 0






