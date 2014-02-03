#!/bin/bash

# test & doc all current calls
# finish test driver (including calling it natively from perl)
# add debugging and fix bugs:
#  - all put and post calls
#  - is the data sent back given the correct Content/Type?
# change structure of json and add Returns lines to doc
# add missing functionality
#  - nodeset stat
#  - osimage create and change and delete and copycds
#  - return metadata of resources (list of possible attributes of def objects)
#  - eliminate pw in url - api key or certificates (bai yuan)
# do perf test and optimize code

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

curl -X GET -k 'https://127.0.0.1/xcatws/groups?userName=bp&password=bryan1&format=xml'

curl -X GET -k 'https://127.0.0.1/xcatws/images?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/images?userName=bp&password=bryan1&format=xml&field=osvers'
curl -X GET -k 'https://127.0.0.1/xcatws/images/bp-netboot?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://127.0.0.1/xcatws/images/bp-netboot?userName=bp&password=bryan1&format=xml&field=osvers'

./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1" -m GET
./xcatws-test.pl -u "https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1" -m PUT "nodepos.room=foo"