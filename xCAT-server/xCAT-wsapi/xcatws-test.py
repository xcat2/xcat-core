#!/usr/bin/env python3
"""Usage:
  xcatws_test.py [--xcatmn=<xcatmn>] [--user=<user>] [--password=<password>]
"""
import requests
import json
import sys

XCATMN        = "127.0.0.1"
username      = "wsuser"
password      = "cluster_rest"
#
# Gather user inputs if any, otherwise defaults above are used
#
try:
    from docopt import docopt, DocoptExit
    arguments = docopt(__doc__)
    if arguments['--xcatmn']:
        XCATMN = arguments['--xcatmn']
    if arguments['--user']:
        username = arguments['--user']
    if arguments['--password']:
        password = arguments['--password']
except ImportError:
    print "WARNING: docopt is not installed, will continue with hard coded defaults..."
except DocoptExit as e:
    # Invalid arguments
    print e
    sys.exit(1)

REST_ENDPOINT    = "https://" + XCATMN + "/xcatws"
create_node      = REST_ENDPOINT + "/nodes/"
get_all_nodes    = REST_ENDPOINT + "/nodes/"
get_token        = REST_ENDPOINT + "/tokens"

#
# Create a test node object
#
testnode_name  = "rest_api_node"
testnode_group = "all"
testnode_mgt   = "ipmi"
testnode_data = {'groups': testnode_group,'mgt': testnode_mgt}
try:
    new_node = requests.post(create_node + testnode_name + "?userName=" + username + "&userPW=" + password, verify=False, headers={'Content-Type': 'application/json'}, data=json.dumps(testnode_data))

    if new_node.content:
        # Display node creation error
        print "Failed to create new node " + testnode_name
        print new_node.content
        sys.exit(1)
    else:
        print "New node definition created for " + testnode_name + ".\n"
except requests.exceptions.HTTPError as e:
    print ("Http Error:",e)
    sys.exit(1)
except requests.exceptions.ConnectionError as e:
    print "Error connecting to xCAT management node " + XCATMN
    print e
    sys.exit(1)
except requests.exceptions.Timeout as e:
    print "Timeout connecting to xCAT management node " + XCATMN
    print e
    sys.exit(1)
except requests.exceptions.RequestException as e:
    print "Unexpected error connecting to xCAT management node " + XCATMN
    print e
    sys.exit(1)
except AttributeError as e:
    print "AttributeError caught, you may need to update the Perl libraries."
    print e
    sys.exit(1)
except Exception as e:
    print "Unexpected error."
    print e
    sys.exit(1)

#
# Send a request to get all nodes, passing in user and password
#
response = requests.get(get_all_nodes + "?userName=" + username + "&userPW=" + password, verify=False)

# Display returned data
print "List of all nodes extracted with userid and password:"
print response.text
#
# Send a request to get all nodes, passing in a token
#
user_data = {'userName': username,'userPW': password}
token = requests.post(get_token, verify=False, headers={'Content-Type': 'application/json'}, data=json.dumps(user_data))
response = requests.get(get_all_nodes, verify=False, headers={'X-Auth-Token': token.json()['token']['id']})

# Display returned data
print "List of all nodes extracted with authentication token:"
print response.text

sys.exit(0)
