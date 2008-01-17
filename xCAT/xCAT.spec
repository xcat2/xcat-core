Summary: Metapackage for a common, default xCAT setup
Name: xCAT
Version: 2.0
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
Vendor: IBM Corp.
Packager: IBM Corp.
Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
#BuildArch: noarch
Source1: xcat.conf
Source2: postscripts.tar.gz
Source3: templates.tar.gz

Provides: xCAT = %{version}

Requires: xCAT-server xCAT-client perl-DBD-SQLite perl-xCAT 
%ifos linux
Requires: tftp-server dhcp httpd nfs-utils expect conserver fping bind
%endif
%ifarch i386 i586 i686 x86 x86_64
Requires: xCAT-nbroot-oss-x86_64 xCAT-nbroot-core-x86_64 xCAT-nbkernel-x86_64 
Requires: ipmitool >= 1.8.9
%endif

%description
xCAT is a server management package intended for at-scale management, including
hardware management and software management.

%prep
tar zxvf %{SOURCE2}
%build
%install
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d/
mkdir -p $RPM_BUILD_ROOT/install/postscripts
mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/xcat/
cd $RPM_BUILD_ROOT/%{prefix}/share/xcat/
tar zxvf %{SOURCE3}
cd -
cd $RPM_BUILD_ROOT/install
tar zxvf %{SOURCE2}
rm LICENSE.html
mkdir -p postscripts/hostkeys
cd -
cp %{SOURCE1} $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat.conf

mkdir -p $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT
cp LICENSE.html $RPM_BUILD_ROOT/%{prefix}/share/doc/packages/xCAT

%post
if [ ! -f /install/postscripts/hostkeys/ssh_host_key ]; then 
    echo Generating SSH1 RSA Key...
    /usr/bin/ssh-keygen -t rsa1 -f /install/postscripts/hostkeys/ssh_host_key -C '' -N ''
    echo Generating SSH2 RSA Key...
    /usr/bin/ssh-keygen -t rsa -f /install/postscripts/hostkeys/ssh_host_rsa_key -C '' -N ''
    echo Generating SSH2 DSA Key...
    /usr/bin/ssh-keygen -t dsa -f /install/postscripts/hostkeys/ssh_host_dsa_key -C '' -N ''
fi
if [ "$1" = "1" ]; then #Only if installing for the fist time..
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo StrictHostKeyChecking no >> /root/.ssh/config
    chmod 600 /root/.ssh/config
    if [ ! -r /root/.ssh/id_rsa.pub ]; then
        ssh-keygen -t rsa -q -b 2048 -N "" -f /root/.ssh/id_rsa
    fi
    mkdir /install/postscripts/.ssh
    cp /root/.ssh/id_rsa.pub /install/postscripts/.ssh/authorized_keys

    mkdir -p /var/log/consoles
    if ! grep /tftpboot /etc/exports; then
        echo '/tftpboot *(rw,root_squash,sync)' >> /etc/exports #SECURITY: this has potential for sharing private host/user keys
    fi
    if ! grep /install /etc/exports; then
        echo '/install *(ro,no_root_squash,sync)' >> /etc/exports #SECURITY: this has potential for sharing private host/user keys
        service nfs restart
	chkconfig nfs on
    fi
    if [ ! -r /etc/xcat/site.sqlite ]; then 
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=xcatdport site.value=3001
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=xcatiport site.value=3002
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=master site.value=$(getent hosts `hostname`|awk '{print $1}')
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=domain site.value=$(hostname -d)
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=installdir site.value=/install
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=timezone site.value=`grep ^ZONE /etc/sysconfig/clock|cut -d= -f 2|sed -e 's/"//g'`
    fi
    if [ ! -r /etc/xcat/policy.sqlite ]; then 
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab priority=1 policy.name=root policy.rule=allow
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab priority=2 policy.commands=getbmcconfig policy.rule=allow
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab priority=3 policy.commands=nextdestiny policy.rule=allow
      XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab priority=4 policy.commands=getdestiny policy.rule=allow
    fi
    
    if [ ! -d /etc/xcat/ca ]; then 
      yes | $RPM_INSTALL_PREFIX0/share/xcat/scripts/setup-xcat-ca.sh "xCAT CA"
    fi
    if [ ! -d /etc/xcat/cert ]; then 
      yes | $RPM_INSTALL_PREFIX0/share/xcat/scripts/setup-server-cert.sh `hostname`
    fi
    if [ ! -r /root/.xcat/client-key.pem ]; then
      yes | $RPM_INSTALL_PREFIX0/share/xcat/scripts/setup-local-client.sh root
    fi
    #Zap the almost certainly wrong pxelinux.cfg file
    rm /tftpboot/pxelinux.cfg/default
    XCATROOT=$RPM_INSTALL_PREFIX0 /etc/init.d/xcatd start
    if [ -x $RPM_INSTALL_PREFIX0/sbin/mknb ]; then
       $RPM_INSTALL_PREFIX0/sbin/mknb x86_64
    fi
    $RPM_INSTALL_PREFIX0/sbin/makenetworks
    XCATROOT=$RPM_INSTALL_PREFIX0 $RPM_INSTALL_PREFIX0/sbin/chtab key=nameservers site.value=`grep nameserver /etc/resolv.conf|awk '{printf $2 ","}'|sed -e s/,$//`
    service httpd restart
    chkconfig httpd on
    echo "xCAT is now installed, it is recommended to tabedit networks and set a dynamic ip address range on any networks where nodes are to be discovered"
    echo "Then, run makedhcp -n to create a new dhcpd.configuration file, and /etc/init.d/dhcpd restart"
    echo "Either examine sample configuration templates, or write your own, or specify a value per node with nodeadd or tabedit."
fi

%clean

%files
%{prefix}
/etc/httpd/conf.d/xcat.conf
/install/postscripts
%defattr(-,root,root)
