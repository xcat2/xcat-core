#!/bin/bash
if [ -f "/etc/httpd/conf/httpd.conf" ]; then
    config="/etc/httpd/conf/httpd.conf"
elif [ -f "/etc/apache2/ports.conf" ]; then
    config="/etc/apache2/ports.conf"
elif [ -f "/etc/apache2/listen.conf" ]; then
    config="/etc/apache2/listen.conf"
fi
port=`awk -F' ' '/^[Ll]isten / {print $2}' $config`
echo "The original httpd port is $port in $config"

echo "start to change httpd listen port to $2"
sed -i  "s/^Listen $1/Listen $2/g" $config
echo "Restart http service"
service apache2 status > /dev/null 2>&1 
if [ "$?" -eq "0" ]; then
    if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
        sed -i "s/VirtualHost \*:$1/VirtualHost \*:$2/g" /etc/apache2/sites-enabled/000-default.conf
    fi
    service apache2 stop
    sleep 1
    service apache2 start
else
    service httpd stop
    sleep 1
    service httpd start
fi
exit $?
