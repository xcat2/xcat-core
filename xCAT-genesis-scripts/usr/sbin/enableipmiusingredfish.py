#!/usr/bin/python
import base64
import httplib
import os
import subprocess
import ssl

iface = os.environ['INTERFACE']
# This should be run in an isolated context.  Since cert validation
# is currently not in the cards, we are realistically at the mercy
# of the OS routing table
subprocess.check_call(['/sbin/ip', 'link', 'set', iface, 'up'])
subprocess.check_call(['/sbin/ip', 'addr', 'add', 'dev', iface, '169.254.95.120/24'])
subprocess.check_call(['/sbin/ip', 'route', 'add', '169.254.95.0/24', 'dev', iface])
client = httplib.HTTPSConnection('169.254.95.118', context=ssl._create_unverified_context())
headers = {
        'Authorization': 'Basic {0}'.format(base64.b64encode(':'.join((os.environ['user'], os.environ['bmcp'])))),
        'Content-Type': 'application/json',
        'Host': '169.254.95.118',
}
client.request('PATCH', '/redfish/v1/Managers/1/NetworkProtocol', '{"IPMI": {"ProtocolEnabled": true}}', headers)
rsp = client.getresponse()
rsp.read()



