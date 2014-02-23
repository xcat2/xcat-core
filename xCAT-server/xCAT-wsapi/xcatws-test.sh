#!/bin/bash
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html

# Test driver for xcatws.cgi

user = ''
pw = ''
format = 'format=json&pretty=1'

#todo: add a test case for every api call that is documented
#todo: figure out why i currently have to specify -k

curl -X GET -k "https://127.0.0.1/xcatws/nodes?userName=$user&password=$pw&format=xml"
curl -X GET -k "https://127.0.0.1/xcatws/nodes?userName=$user&password=$pw&format=xml&field=mac"
curl -X GET -k "https://127.0.0.1/xcatws/nodes/test001-test006?userName=$user&password=$pw&format=xml"
curl -X GET -k "https://127.0.0.1/xcatws/nodes/test001-test006?userName=$user&password=$pw&format=xml&field=mac"
curl -X DELETE -k "http://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw"
curl -X PUT -k "https://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw&format=xml&debug=0" -H Content-Type:application/json --data '{"room":"hi","unit":"7"}'
curl -X POST -k "https://127.0.0.1/xcatws/nodes/ws1?userName=$user&password=$pw&format=xml&debug=0" -H Content-Type:application/json --data '{"groups":"wstest"}'

curl -X GET -k "https://127.0.0.1/xcatws/groups?userName=$user&password=$pw&format=xml"

curl -X GET -k "https://127.0.0.1/xcatws/images?userName=$user&password=$pw&format=xml"
curl -X GET -k "https://127.0.0.1/xcatws/images?userName=$user&password=$pw&format=xml&field=osvers"
curl -X GET -k "https://127.0.0.1/xcatws/images/bp-netboot?userName=$user&password=$pw&format=xml"
curl -X GET -k "https://127.0.0.1/xcatws/images/bp-netboot?userName=$user&password=$pw&format=xml&field=osvers"

#todo: remove when these test cases are in xcatws-test.pl
./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw" -m GET
./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=$user&password=$pw" -m PUT "nodepos.room=foo"