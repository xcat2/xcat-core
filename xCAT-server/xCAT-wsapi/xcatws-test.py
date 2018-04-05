#!/usr/bin/python
import requests
import json

xCAT_MN = "<host name>"
user    = "wsuser"
pw      = "cluster_rest"

get_all_nodes    = "https://" + xCAT_MN + "/xcatws/nodes/"
get_all_osimages = "https://" + xCAT_MN + "/xcatws/osimages/"
get_token        = "https://" + xCAT_MN + "/xcatws/tokens"

# Send request with user and pw
r = requests.get(get_all_nodes + "?userName=" + user + "&userPW=" + pw, verify=False)

# Display output
print r.content

# Send request with a token
user_data = {'userName': 'wsuser','userPW': 'cluster_rest'}
token = requests.post(get_token, verify=False, headers={'Content-Type': 'application/json'}, data=json.dumps(user_data))
r = requests.get(get_all_osimages, verify=False, headers={'X-Auth-Token': token.json()['token']['id']})

# Display output
print r.content
