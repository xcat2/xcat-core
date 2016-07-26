Summary: Web Client for xCAT 2
Name: xCAT-UI
Version: %(cat Version)
Release: snap%(date +"%Y%m%d%H%M")
License: EPL
Group: Applications/System
URL: http://xcat.org
Packager: IBM
Vendor: IBM

Source: xCAT-UI-%(cat Version).tar.gz
BuildRoot: /var/tmp/%{name}-%{version}-%{release}-root
%ifos linux
BuildArch: noarch
%endif
Provides: xCAT-UI = %{version}
Requires: xCAT-UI-deps >= 2.6

Distribution: %{?_distribution:%{_distribution}}%{!?_distribution:%{_vendor}}
Prefix: /opt/xcat

%define s390x %(if [ "$s390x" = "1" ];then echo 1; else echo 0; fi)
%define nots390x %(if [ "$s390x" = "1" ];then echo 0; else echo 1; fi)

# Define a different location for various httpd configs in s390x mode
%define httpconfigdir %(if [ "$s390x" = "1" ];then echo "xcathttpdsave"; else echo "xcat"; fi)

%ifos linux
# httpd is provided as apache2 on SLES and httpd on RHEL
Requires: httpd
%endif

%description
Provides a browser-based interface for xCAT (Extreme Cloud Administration Toolkit).

%prep
%setup -q -n xCAT-UI

%build
#********** Build **********
# Minify Javascript files using Google Compiler
echo "Minifying Javascripts... This will take a couple of minutes."

#COMPILER_JAR='/xcat2/build/tools/compiler.jar'
COMPILER_JAR='/root/scripts/compiler.jar'
UI_JS="js/"

%ifos linux
JAVA='/usr/bin/java'
# Find all Javascript files
declare -a FILES
FILES=`find ${UI_JS} -name '*.js'`
for i in ${FILES[*]}; do
    # Ignore Javascripts that are already minified
    if [[ ! $i =~ '.*\.min\.js$' ]]; then
        echo "  Minifying $i ..."
        `${JAVA} -jar ${COMPILER_JAR} --warning_level=QUIET --js=$i --js_output_file=$i.min`

        # Remove old Javascript and replace it with minified version
        rm -rf $i
        mv $i.min $i
    fi
done
%endif

IFS='
'

%install
#********** Install **********
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{prefix}/ui
cp -r * $RPM_BUILD_ROOT%{prefix}/ui
chmod 755 $RPM_BUILD_ROOT%{prefix}/ui/*
mkdir -p $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig
mkdir -p $RPM_BUILD_ROOT/etc/apache2/conf.d
mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d
mkdir -p $RPM_BUILD_ROOT%{prefix}/etc/%httpconfigdir/conf.orig
#mkdir -p $RPM_BUILD_ROOT%{prefix}/etc/apache2/conf.d
#mkdir -p $RPM_BUILD_ROOT%{prefix}/etc/httpd/conf.d

# Copy over xCAT UI plugins
mkdir -p $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
cp xcat/plugins/* $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/web.pm
chmod 644 $RPM_BUILD_ROOT/%{prefix}/lib/perl/xCAT_plugin/webportal.pm

#Copy the different conf files for httpd
cp etc/apache2/conf.d/xcat-ui.conf.apach22 $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach22
cp etc/apache2/conf.d/xcat-ui.conf.apach24 $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24

#install lower version(<2.4) apache/httpd conf files by default
cp $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach22 $RPM_BUILD_ROOT/etc/apache2/conf.d/xcat-ui.conf
cp $RPM_BUILD_ROOT/etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach22 $RPM_BUILD_ROOT/etc/httpd/conf.d/xcat-ui.conf

# Create symbolic link to webportal command
mkdir -p $RPM_BUILD_ROOT%{prefix}/bin
ln -sf ../bin/xcatclientnnr $RPM_BUILD_ROOT%{prefix}/bin/webportal

%files
/etc/apache2/conf.d/xcat-ui.conf
/etc/httpd/conf.d/xcat-ui.conf
/etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach22
/etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24

%defattr(-,root,root)
%{prefix}

%pre
#********** Pre-install **********
# Inspect whether PHP related RPM packages are installed
%ifos linux
    if [ -e "/etc/redhat-release" ]; then
        rpm -q php >/dev/null
        if [ $? != 0 ]; then
            echo ""
            echo "Error! php has not been installed. Please run 'yum install php' before installing xCAT-UI.";
            exit -1;
        fi
    elif [ -e "/opt/ibm/cmo/version" ]; then  # IBM Cloud Manager Appliance
        rpm -q php >/dev/null
        if [ $? != 0 ]; then
            echo ""
            echo "Error! Can not find php. Please make sure php is installed before installing xCAT-UI.";
            exit -1;
        fi
    else    # SUSE
        rpm -q apache2-mod_php5 php5 >/dev/null
        if [ $? != 0 ]; then
            echo ""
            echo "Error! apache2-mod_php5 and php5 have not been installed. Please run 'zypper install apache2-mod_php5 php5' before installing xCAT-UI."
            exit -1;
        fi
    fi
%else   # AIX
    if [ -e "/usr/IBM/HTTPServer/conf/httpd.conf" ]; then
        echo "Installing xCAT-UI on AIX..."
    else
        echo ""
        echo "Error! IBM HTTP Server has not been installed or has not been installed in the default directory (/usr/IBM/HTTPServer/)."
        exit -1;
    fi
%endif

%post
#********** Post-install **********
# Get apache name
%ifos linux
    if [ "$1" = 1 ]    # Install
    then
        # Automatically put encrypted password into the xCAT passwd database
          %{prefix}/sbin/chtab key=xcat,username=root passwd.password=`grep root /etc/shadow|cut -d : -f 2`

          echo "To use xCAT-UI, point your browser to http://"`hostname -f`"/xcat"
    fi

    # If httpd is 2.4 or newer, use the file with the new configuration options
    #Apply the correct httpd/apache configuration file according to the httpd/apache version
    if [ -n "$(httpd -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
    then
        /bin/rm -rf /etc/httpd/conf.d/xcat-ui.conf
        /bin/rm -rf /opt/xcat/ui/etc/apache2/conf.d/xcat-ui.conf
        /bin/cp -f /etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24 /etc/httpd/conf.d/xcat-ui.conf
        /bin/cp -f /etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24 /etc/apache2/conf.d/xcat-ui.conf
    fi

    if [ -n "$(apachectl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
    then
        /bin/rm -rf /etc/httpd/conf.d/xcat-ui.conf
        /bin/rm -rf /opt/xcat/ui/etc/apache2/conf.d/xcat-ui.conf
        /bin/cp -f /etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24 /etc/httpd/conf.d/xcat-ui.conf
        /bin/cp -f /etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24 /etc/apache2/conf.d/xcat-ui.conf
    fi

    if [ -n "$(apache2ctl -v 2>&1 |grep -e '^Server version\s*:.*\/2.4')" ]
    then
        /bin/rm -rf /etc/httpd/conf.d/xcat-ui.conf
        /bin/rm -rf /opt/xcat/ui/etc/apache2/conf.d/xcat-ui.conf
        /bin/cp -f /etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24 /etc/httpd/conf.d/xcat-ui.conf
        /bin/cp -f /etc/%httpconfigdir/conf.orig/xcat-ui.conf.apach24 /etc/apache2/conf.d/xcat-ui.conf
    fi


    if [ "$1" = 1 ] || [ "$1" = 2 ]             # Install or upgrade
    then
        # Restart xCAT
        /etc/init.d/xcatd restart

        # Copy php.ini file into /opt/xcat/ui and turn off output_buffering
        if [ -e "/etc/redhat-release" ]; then
            /bin/sed /etc/php.ini -e 's/output_buffering = 4096/output_buffering = Off/g' > %{prefix}/ui/php.ini
        elif [ -e "/opt/ibm/cmo/version" ]; then  # IBM Cloud Manager Appliance
            /bin/sed /etc/php.ini -e 's/output_buffering = 4096/output_buffering = Off/g' > %{prefix}/ui/php.ini
        else    # SUSE
            /bin/sed /etc/php5/apache2/php.ini -e 's/output_buffering = 4096/output_buffering = Off/g' > %{prefix}/ui/php.ini
        fi

        # Restart Apache Server
        /etc/init.d/httpd restart
        true
    fi
%else   # AIX
    ihs_config_dir='/usr/IBM/HTTPServer/conf'
    if [ "$1" = 1 ] #initial install
    then
        # Check if IBM HTTP Server is installed in the default directory
        # Update the apache config
        echo "Updating IBM HTTP server configuration for xCAT..."
        bin/rm -f /usr/IBM/HTTPServer/conf/xcat-ui.conf
        cp /usr/IBM/HTTPServer/conf/httpd.conf /usr/IBM/HTTPServer/conf/httpd.conf.xcat.ui.bak
        cat ../ui/etc/apache2/conf.d/xcat-ui.conf >> /usr/IBM/HTTPServer/conf/httpd.conf
        /usr/IBM/HTTPServer/bin/apachectl restart

        # Put the encrypted password in /etc/security/passwd into the xcat passwd database
        CONT=`cat /etc/security/passwd`
        %{prefix}/sbin/chtab key=xcat,username=root passwd.password=`echo $CONT |cut -d ' ' -f 4`
    fi

%endif
