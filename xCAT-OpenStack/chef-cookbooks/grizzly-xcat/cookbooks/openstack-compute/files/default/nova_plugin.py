#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from keystoneclient.v2_0 import Client as KeystoneClient
from novaclient.client import Client as NovaClient
from novaclient import exceptions

import collectd

global NAME, OS_USERNAME, OS_PASSWORD, OS_TENANT_NAME, OS_AUTH_URL, VERBOSE_LOGGING

NAME = "nova_plugin"
OS_USERNAME = "username"
OS_PASSWORD = "password"
OS_TENANT_NAME = "tenantname"
OS_AUTH_URL = "http://localhost:5000/v2.0"
VERBOSE_LOGGING = False

def get_stats(user, passwd, tenant, url):
    keystone = KeystoneClient(username=user, password=passwd, tenant_name=tenant, auth_url=url)

    # Find my uuid
    user_list = keystone.users.list()
    admin_uuid = ""
    for usr in user_list:
        if usr.name == user:
            admin_uuid = usr.id

    # Find out which tenants I have roles in
    tenant_list = keystone.tenants.list()
    my_tenants = list()
    for tenant in tenant_list:
        if keystone.users.list_roles(user=admin_uuid, tenant=tenant.id):
            my_tenants.append( { "name": tenant.name, "id": tenant.id } )

    #prefix = "openstack.nova.cluster"
    prefix = "openstack.nova"

    # Default data structure
    data = dict()

    # Prep counters
    data["%s.total.count" % (prefix)] = 0
    counters = ('ram', 'vcpus', 'disk', 'ephemeral')
    for counter in counters:
        data["%s.total.%s" % (prefix,counter)] = 0

    # for tenant in tenant_list:
    for tenant in my_tenants:
        client = NovaClient("1.1",user,passwd,tenant['name'],url,service_type="compute")

        # Figure out how much ram has been allocated total for all servers
        server_list = client.servers.list()
        data["%s.total.count" % (prefix)] += len(server_list)

        data["%s.tenant.%s.count" % (prefix,tenant['name'])] = 0

        for server in server_list:
            flavor = client.flavors.get(int(server.flavor["id"]))
            tenant_uuid = keystone.tenants.get(server.tenant_id).name
            data["%s.tenant.%s.count" % (prefix,tenant_uuid)] += 1
            for counter in counters:
                data["%s.total.%s" % (prefix,counter)] += int(flavor.__getattribute__(counter))
                if "%s.%s.%s" % (prefix,tenant_uuid, counter) in data:
                    data["%s.tenant.%s.%s" % (prefix,tenant_uuid,counter)] += int(flavor.__getattribute__(counter))
                else:
                    data["%s.tenant.%s.%s" % (prefix,tenant_uuid,counter)] = int(flavor.__getattribute__(counter))

    ##########
    # debug
    for key in data.keys():
        print "%s = %s" % (key, data[key])
    ##########

    return data


def configure_callback(conf):
    """Received configuration information"""
    global OS_USERNAME, OS_PASSWORD, OS_TENANT_NAME, OS_AUTH_URL, VERBOSE_LOGGING
    for node in conf.children:
        if node.key == "Username":
            OS_USERNAME = node.values[0]
        elif node.key == "Password":
            OS_PASSWORD = node.values[0]
        elif node.key == "TenantName":
            OS_TENANT_NAME = node.values[0]
        elif node.key == "AuthURL":
            OS_AUTH_URL = node.values[0]
        elif node.key == "Verbose":
            VERBOSE_LOGGING = node.values[0]
        else:
            logger("warn", "Unknown config key: %s" % node.key)


def read_callback():
    logger("verb", "read_callback")
    info = get_stats(OS_USERNAME, OS_PASSWORD, OS_TENANT_NAME, OS_AUTH_URL)

    if not info:
        logger("err", "No information received")
        return

    for key in info.keys():
        logger('verb', 'Dispatching %s : %i' % (key, int(info[key])))
        val = collectd.Values(plugin=key)
        val.type = 'gauge'
        val.values = [int(info[key])]
        val.dispatch()


def logger(t, msg):
    if t == 'err':
        collectd.error('%s: %s' % (NAME, msg))
    if t == 'warn':
        collectd.warning('%s: %s' % (NAME, msg))
    elif t == 'verb' and VERBOSE_LOGGING == True:
        collectd.info('%s: %s' % (NAME, msg))

collectd.register_config(configure_callback)
collectd.warning("Initializing nova plugin")
collectd.register_read(read_callback)
