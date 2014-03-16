#!/bin/bash
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html

# Test driver for xcatws.cgi, pass 3 arguments to it: user, password, noderange
# This test driver will create to dummy nodes, wstest1 and wstest2, so make sure those
# names don't conflict with your nodes on this MN.
# You also have to pass in a noderange of 2 real system x nodes that can be used
# to test some of the r cmds, xdsh, xdcp, nodestat.

user=$1
pw=$2
nr=$3
if [ -z "$3" ]; then
	echo "Usage: chkrc <user> <pw> <noderange>"
	exit
fi

format='format=json&pretty=1'
ctype='-H Content-Type:application/json'

function chkrc
{
	rc=$?
	{ set +x; } 2>/dev/null
	if [[ $1 == "not" ]]; then
		if [[ $rc -eq 0 ]]; then
			echo "Test failed!"
			exit
		fi
	else
		if [[ $rc -gt 0 ]]; then
			echo "Test failed!"
			exit
		fi
	fi
	echo ''
	set -x
}

# pcregrep -M  'abc.*(\n|.)*efg' test.txt

#todo: add a test case for every api call that is documented
set -x
# clean up from last time
curl -# -X DELETE -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw" >/dev/null; echo ''

# create test nodes
curl -# -X POST -k "https://127.0.0.1/xcatws/node/wstest1-wstest2?userName=$user&password=$pw&$format" $ctype --data '{"groups":"wstest","netboot":"xnba"}' \
 | grep -q '2 object definitions have been created'; chkrc

# list all nodes and make sure they are in the list
curl -# -X GET -k "https://127.0.0.1/xcatws/node?userName=$user&password=$pw&$format" \
 | pcregrep -qM '"wstest1",\n\s*"wstest2"'; chkrc

# list all node's group and netboot attributes
curl -# -X GET -k "https://127.0.0.1/xcatws/node?userName=$user&password=$pw&field=groups&field=netboot" \
 | grep -qE '"nodename":"wstest1".*"groups":"wstest"'; chkrc

# list all attributes of all nodes
curl -# -X GET -k "https://127.0.0.1/xcatws/node?userName=$user&password=$pw&field=ALL" \
 | grep -qE '"nodename":"wstest1".*"groups":"wstest"'; chkrc

# list the noderange and make sure they are in the list
curl -# -X GET -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw&$format" \
 | pcregrep -qM '"wstest1",\n\s*"wstest2"'; chkrc

# list all node's group and netboot attributes
curl -# -X GET -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw&field=groups&field=netboot" \
 | grep -qE '"nodename":"wstest1".*"groups":"wstest"'; chkrc

# list all attributes of all nodes
curl -# -X GET -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw&field=ALL" \
 | grep -qE '"nodename":"wstest1".*"groups":"wstest"'; chkrc

# change some attributes
curl -# -X PUT -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw&$format" $ctype --data '{"room":"222","netboot":"pxe"}' \
 | grep -q '2 object definitions have been created or modified'; chkrc

# verify they got the new values
curl -# -X GET -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw&field=room&field=netboot" \
 | grep -qE '"nodename":"wstest1".*"room":"222"'; chkrc

# delete the nodes
curl -# -X DELETE -k "https://127.0.0.1/xcatws/node/wstest?userName=$user&password=$pw&$format" \
 | grep -q '2 object definitions have been removed'; chkrc

# list all nodes and make sure they are not in the list
curl -# -X GET -k "https://127.0.0.1/xcatws/node?userName=$user&password=$pw&$format" \
 | pcregrep -qM '"wstest1",\n\s*"wstest2"'; chkrc not

# list the power state of the noderange
curl -# -X GET -k "https://127.0.0.1/xcatws/node/$nr/power?userName=$user&password=$pw&$format" \
 | grep -q '"power":"on"'; chkrc

# list the nodestat state of the noderange
curl -# -X GET -k "https://127.0.0.1/xcatws/node/$nr/status?userName=$user&password=$pw&$format" \
 | grep -q '":"sshd"'; chkrc

# list the node inventory of the noderange
curl -# -X GET -k "https://127.0.0.1/xcatws/node/$nr/inventory?userName=$user&password=$pw&$format" \
 | grep -q '"Board manufacturer":"IBM"'; chkrc

# list the node vitals of the noderange
curl -# -X GET -k "https://127.0.0.1/xcatws/node/$nr/vitals?userName=$user&password=$pw&$format" \
 | grep -q '"Cooling Fault":"false"'; chkrc

# list the node energy settings of the noderange
curl -# -X GET -k "https://127.0.0.1/xcatws/node/$nr/energy?userName=$user&password=$pw&$format&field=cappingstatus&field=cappingmaxmin" \
 | grep -q '"cappingstatus":"off"'; chkrc

# run a cmd on the noderange
curl -# -X POST -k "https://127.0.0.1/xcatws/node/$nr/dsh?userName=$user&password=$pw&$format" $ctype --data '{"command":"pwd"}' \
 | grep -q '"/root"'; chkrc

# copy a file to the noderange
curl -# -X POST -k "https://127.0.0.1/xcatws/node/$nr/dcp?userName=$user&password=$pw&$format" $ctype --data '{"source":"/root/.bashrc","target":"/tmp/"}' \
 | grep -q '"errorcode":"0"'; chkrc

# test the table calls
#curl -# -X GET -k "https://127.0.0.1/xcatws/table/nodelist/test001?userName=$user&password=$pw&$format"


exit


#curl -X GET -k "https://127.0.0.1/xcatws/groups?userName=$user&password=$pw&$format"

#curl -X GET -k "https://127.0.0.1/xcatws/images?userName=$user&password=$pw&$format"
#curl -X GET -k "https://127.0.0.1/xcatws/images?userName=$user&password=$pw&$format&field=osvers"
#curl -X GET -k "https://127.0.0.1/xcatws/images/bp-netboot?userName=$user&password=$pw&$format"
#curl -X GET -k "https://127.0.0.1/xcatws/images/bp-netboot?userName=$user&password=$pw&$format&field=osvers"

#todo: remove when these test cases are in xcatws-test.pl
#./xcatws-test.pl -u "https://127.0.0.1/xcatws/node/test001?userName=$user&password=$pw" -m GET
#./xcatws-test.pl -u "https://127.0.0.1/xcatws/node/test001?userName=$user&password=$pw" -m PUT "nodepos.room=foo"
