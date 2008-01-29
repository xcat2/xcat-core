#!/bin/sh
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

while ! /bin/getdestiny
do
    echo "Retrying destiny retrieval"
    sleep 3
    ifconfig 
done
. /bin/dodestiny
