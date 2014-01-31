#!/usr/bin/perl

# test & doc all current calls
# finish test driver (including calling it natively from perl)
# restructure & comment code
# add debugging and fix bugs:
#  - all put and post calls
#  - and allow put data in url args too
# change structure of json and add Returns lines to doc
# add missing functionality
#  - nodeset stat
#  - osimage create and change and delete and copycds
# do perf test and optimize code

curl -X GET -k 'http://127.0.0.1/xcatws/nodes?userName=bp&password=and9ew88&format=xml'
curl -X GET -k 'https://9.114.34.210/xcatws/nodes?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://9.114.34.210/xcatws/nodes?userName=bp&password=bryan1&format=xml&field=mac'
curl -X GET -k 'https://9.114.34.210/xcatws/nodes/test001-test006?userName=bp&password=bryan1&format=xml'
curl -X GET -k 'https://9.114.34.210/xcatws/nodes/test001-test006?userName=bp&password=bryan1&format=xml&field=mac'
#curl -X PUT -k --data '{"room":"foo"}' 'https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1'
#curl -X POST -k --data '{"groups":"compute,all"}' 'https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1'
curl -X DELETE -k 'http://127.0.0.1/xcatws/nodes/test001?userName=bp&password=and9ew88'

./restapi -u "https://127.0.0.1/xcatws/nodes/test001?userName=bp&password=bryan1" -m GET
./restapi -u "https://10.1.0.210/xcatws/nodes/test001?userName=bp&password=bryan1" -m PUT "nodepos.room=foo"