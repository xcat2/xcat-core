#!/usr/bin/env python

"""
Usage: getslnodes.py [-h] [-v] [<hostname-match>]

Description:
Query your SoftLayer account and get attributes for each bare metal server.
The attributes can be piped to 'mkdef -z' to define the nodes into the xCAT 
Database so that xCAT can manage them.  

getslnodes requires a the .softlayer configuration file defined which can
be set by running "sl config setup" on the command line. 

positional arguments:
  hostname-match  Select servers that include this partial hostname.

Optional:
  -h, --help      show this help message and exit
  -v, --verbose   display verbose output
"""

import sys

try:
    import docopt
    import pprint
    import SoftLayer
except ImportError as e:
    print 'Error: install missing python module before running this command: ' + str(e)
    sys.exit(2)

def get_sl_servers(): 

    # username, api_key, endpoint_url come from the .softlayer file
    client = SoftLayer.Client()

    mask = "hostname, fullyQualifiedDomainName, manufacturerSerialNumber, \
            operatingSystem.id, operatingSystem.passwords.username, operatingSystem.passwords.password, \
            remoteManagementAccounts.username, remoteManagementAccounts.password, remoteManagementComponent.ipmiIpAddress, \
            primaryBackendNetworkComponent.primaryIpAddress, primaryBackendNetworkComponent.macAddress"
    #
    # If they specified hnmatch, it would be faster to have softlayer filter the response with something like:
    # filter={'hardware': {'hostname': {'operation': '*= '+hostname}, 'domain': {'operation': '*= '+domain}}}
    # But those 2 operations are ANDed together, so it will not work.  And currently, filtering does not work on fullyQualifiedDomainName.
    #
    servers = client['Account'].getHardware(mask=mask)
    return servers 
   
def print_xcat_node_stanza(servers, hnmatch): 

    for server in servers:
        if hnmatch and server['fullyQualifiedDomainName'].find(hnmatch) == -1:
            continue

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

        if username and password:
            userStr = ", user:"+username+", pw:"+password

        print "\tusercomment=hostname:"+server['fullyQualifiedDomainName']+userStr



if __name__ == '__main__':
    try:
        arguments = (docopt.docopt(__doc__, version="1.0")) 
        # print arguments

        servers = get_sl_servers()
        if arguments['--verbose']: 
            pprint.pprint(servers)

        print_xcat_node_stanza(servers, arguments['<hostname-match>'])

    except docopt.DocoptExit as e:
        print e
    except SoftLayer.exceptions.SoftLayerAPIError as e:
        print e

    sys.exit(1) 


