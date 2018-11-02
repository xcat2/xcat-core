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

echo "start to change httpd listen port to 8899"
sed -i  "s/^Listen 80/Listen 8899/g" $config
if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
    sed -i "s/VirtualHost \*:80/VirtualHost \*:8899/g" /etc/apache2/sites-enabled/000-default.conf
    service apache2 stop
    sleep 1
    service apache2 start
else
    service httpd stop
    sleep 1
    service httpd start
fi
exit
