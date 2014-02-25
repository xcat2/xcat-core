#!/bin/bash
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html

# Test driver for xcatws.cgi, pass two arguments to it, user and password.
# Usage example: ./xcatws-test.sh wsuer cluster


user=$1
pw=$2
format='format=json&pretty=1'

#todo: add a test case for every api call that is documented
#curl [options] [URL...]:
#     -X/--request <command> : commands include PUT,POST,GET and DELETE.
#     -k/--insecure : This option explicitly allows curl to perform "insecure" SSL connections and transfers. 

curl -X GET -k "https://127.0.0.1/xcatws/nodes?userName=$user&password=$pw&$format"
curl -X GET -k "https://127.0.0.1/xcatws/nodes?userName=$user&password=$pw&$format&field=mac"
curl -X GET -k "https://127.0.0.1/xcatws/nodes/test001-test006?userName=$user&password=$pw&$format"
curl -X GET -k "https://127.0.0.1/xcatws/nodes/test001-test006?userName=$user&password=$pw&$format&field=mac"
curl -X DELETE -k "http://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw"
curl -X PUT -k "https://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw&$format" -H Content-Type:application/json --data '{"room":"hi","unit":"7"}'
curl -X POST -k "https://127.0.0.1/xcatws/nodes/ws1?userName=$user&password=$pw&$format" -H Content-Type:application/json --data '{"groups":"wstest"}'
curl -X POST -k "https://127.0.0.1/xcatws/nodes/bruce/dsh?userName=$user&password=$pw&$format" -H Content-Type:application/json --data '["command=date"]'

curl -X GET -k "https://127.0.0.1/xcatws/groups?userName=$user&password=$pw&$format"

curl -X GET -k "https://127.0.0.1/xcatws/images?userName=$user&password=$pw&$format"
curl -X GET -k "https://127.0.0.1/xcatws/images?userName=$user&password=$pw&$format&field=osvers"
curl -X GET -k "https://127.0.0.1/xcatws/images/bp-netboot?userName=$user&password=$pw&$format"
curl -X GET -k "https://127.0.0.1/xcatws/images/bp-netboot?userName=$user&password=$pw&$format&field=osvers"

#todo: remove when these test cases are in xcatws-test.pl
./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw" -m GET
./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw" -m PUT "nodepos.room=foo"
