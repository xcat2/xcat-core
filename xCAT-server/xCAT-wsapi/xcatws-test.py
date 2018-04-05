#!/usr/bin/env python
import requests
import json

XCATMN        = "127.0.0.1"
REST_ENDPOINT = "https://" + XCATMN + "/xcatws"
username      = "wsuser"
password      = "cluster_rest"

get_all_nodes    = REST_ENDPOINT + "/nodes/"
get_all_osimages = REST_ENDPOINT + "/osimages/"
get_token        = REST_ENDPOINT + "/tokens"

#
# Send a request to get all nodes, passing in user and password
#
r = requests.get(get_all_nodes + "?userName=" + username + "&userPW=" + password, verify=False)

# Display returned data
print r.content

#
# Send a request to get all osimages, passing in a token
#
user_data = {'userName': username,'userPW': password}
token = requests.post(get_token, verify=False, headers={'Content-Type': 'application/json'}, data=json.dumps(user_data))
r = requests.get(get_all_osimages, verify=False, headers={'X-Auth-Token': token.json()['token']['id']})

# Display returned data
print r.content
