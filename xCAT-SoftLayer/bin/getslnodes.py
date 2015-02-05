#!/usr/bin/env python

# Query the softlayer account for info about all of the bare metal servers and
# put the info in mkdef stanza format, so the node can be defined in the xcat db
# so that xcat can manage/deploy them.

try:
    import sys
    import pprint
    import argparse
    import SoftLayer
except ImportError as e:
    print 'Error: install missing python module before running this command: '+str(e)
    sys.exit(2)

# Process the cmd line args
# --help is automatically provided by this
parser = argparse.ArgumentParser(description="Query your SoftLayer account and get attributes for each bare metal server. The attributes can be piped to 'mkdef -z' to define the nodes in the xCAT DB so that xCAT can manage them.  getslnodes requires a .softlayer file in your home directory that contains your SoftLayer username, api_key, and optionally endpoint_url.")
parser.add_argument('hnmatch', metavar='hostname-match', nargs='?', help='Select servers that include this partial hostname.')
parser.add_argument('-v', "--verbose", action="store_true", help="display verbose output")
args = parser.parse_args()
hnmatch = args.hnmatch     # if they specified a hostname match, only show svrs that start with that

# Get info from softlayer
try:
    # username, api_key, endpoint_url come from the .softlayer file
    client = SoftLayer.Client()

    mask = "hostname, fullyQualifiedDomainName, manufacturerSerialNumber, \
            operatingSystem.id, operatingSystem.passwords.username, operatingSystem.passwords.password, \
            remoteManagementAccounts.username, remoteManagementAccounts.password, remoteManagementComponent.ipmiIpAddress, \
            primaryBackendNetworkComponent.primaryIpAddress, primaryBackendNetworkComponent.macAddress"
    # If they specified hnmatch, it would be faster to have softlayer filter the response with something like:
    # filter={'hardware': {'hostname': {'operation': '*= '+hostname}, 'domain': {'operation': '*= '+domain}}}
    # But those 2 operations are ANDed together, so it will not work.  And currently, filtering does not work on fullyQualifiedDomainName.
    servers = client['Account'].getHardware(mask=mask)
    if args.verbose:  pprint.pprint(servers)
except SoftLayer.exceptions.SoftLayerAPIError as e:
    print 'Error: '+str(e)

# print info out in xcat node stanza format    
for server in servers:
    if hnmatch and server['fullyQualifiedDomainName'].find(hnmatch) == -1:  continue
    print "\n"+server['hostname']+":"
    print "\tobjtype=node"
    print "\tgroups=slnode,ipmi,all"
    print "\tmgt=ipmi"
    print "\tbmc="+server['remoteManagementComponent']['ipmiIpAddress']

    # I have seen svrs with no remoteManagementAccounts entries
    if len(server['remoteManagementAccounts']):
        print "\tbmcusername="+server['remoteManagementAccounts'][0]['username']
        print "\tbmcpassword="+server['remoteManagementAccounts'][0]['password']

    print "\tip="+server['primaryBackendNetworkComponent']['primaryIpAddress']
    print "\tmac="+server['primaryBackendNetworkComponent']['macAddress']
    print "\tserial="+server['manufacturerSerialNumber']
    print "\tnetboot=xnba"
    print "\tarch=x86_64"

    # Find the root or Administrator username and pw
    username = None
    password = None
    for entry in server['operatingSystem']['passwords']:
        if entry['username'] == 'root' or entry['username'] == 'Administrator':
            # found it
            username = entry['username']
            password = entry['password']
            break
        elif not username:
            # save the 1st entry, in case we never find root or Administrator
            username = entry['username']
            password = entry['password']
    if username and password:  userStr = ", user:"+username+", pw:"+password
    print "\tusercomment=hostname:"+server['fullyQualifiedDomainName']+userStr
sys.exit(0)


def verbose(text):
    '''Print msg only if -v was specified.'''
    if args.verbose:  print text

