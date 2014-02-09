#!/bin/bash

# * test & doc all current calls
# - finish test driver (both curl and natively from perl)
# * add debugging and fix bugs
# - change xdsh/xdcp to post and compact that code
# - change format of all put and post calls
# - change structure of output json and add Returns lines to doc
# - add nodeset stat
# - change table routines to use lissa's xml interface and doc them as an alternative to the node def calls
# - add: osimage def create, change, delete and copycds (bai yuan)
# - eliminate pw in url - api key or certificates (bai yuan)
# - send output back to client as it comes from xcatd, and compare code to Client.pm (bai yuan)
# - is the data sent back given the correct Content/Type? (bai yuan)
# - test, fix, doc the other resource handlers in there: groups, logs, notifications, policies, accounts, hypervisor(bai yuan)
# - do perf/scale tests and optimize code, incl breaking resource handlers into separate pms
# - return metadata of resources (list of possible attributes of def objects)(bai yuan)

userpw = 'userName=bp&password=bryan1'
format = 'format=xml'

#curl -X GET -k 'http://127.0.0.1/xcatws/nodes?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/nodes?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/nodes?userName=bp&password=bryan1&format=xml&field=mac'
curl -X GET -k 'https://127.0.0.1/xcatws/nodes/test001-test006?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/nodes/test001-test006?userName=bp&password=bryan1&format=xml&field=mac'
#curl -X PUT -k --data '{"room":"foo"}' 'https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1'
#curl -X POST -k --data '{"groups":"compute,all"}' 'https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1'
curl -X DELETE -k 'http://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1'
curl -X PUT -k 'https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1&format=xml&debug=0' -H Content-Type:application/json --data '{"room":"hi","unit":"7"}'
curl -X POST -k 'https://127.0.0.1/xcatws/nodes/ws1?userName=bp&password=bryan1&format=xml&debug=0' -H Content-Type:application/json --data '{"groups":"wstest"}'

curl -X GET -k 'https://127.0.0.1/xcatws/groups?userName=bp&password=bryan1&format=xml'

curl -X GET -k 'https://127.0.0.1/xcatws/images?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/images?userName=bp&password=bryan1&format=xml&field=osvers'
curl -X GET -k 'https://127.0.0.1/xcatws/images/bp-netboot?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/images/bp-netboot?userName=bp&password=bryan1&format=xml&field=osvers'

./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1" -m GET
./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1" -m PUT "nodepos.room=foo"