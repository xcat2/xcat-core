from glance.client import V1Client
from glance.common import exception

import collectd

global NAME, OS_USERNAME, OS_PASSWORD, OS_TENANT_NAME, OS_AUTH_URL, OS_AUTH_STRATEGY, VERBOSE_LOGGING

NAME = "glance_plugin"
OS_USERNAME = "username"
OS_PASSWORD = "password"
OS_TENANT_NAME = "tenantname"
OS_AUTH_URL = "http://localhost:5000/v2.0"
OS_AUTH_STRATEGY = "keystone"
VERBOSE_LOGGING = False

def get_stats(user, passwd, tenant, url, host=None):
    creds = {"username": user, "password": passwd, "tenant": tenant,"auth_url": url, "strategy": OS_AUTH_STRATEGY}
    client = V1Client(host,creds=creds)
    try:
        image_list = client.get_images_detailed()
    except exception.NotAuthenticated:
        msg = "Client credentials appear to be invalid"
        raise exception.ClientConnectionError(msg)
    else:
        # TODO(shep): this needs to be rewritten more inline with the keystone|nova plugins
        data = dict()
        data["count"] = int(len(image_list))
        data["bytes"] = 0
        data["snapshot.count"] = 0
        data["snapshot.bytes"] = 0
        data["tenant"] = dict()
        for image in image_list:
            data["bytes"] += int(image["size"])
            if "image_type" in image["properties"] and image["properties"]["image_type"] == "snapshot":
                data["snapshot.count"] += 1
                data["snapshot.bytes"] += int(image["size"])
            uuid = str(image["owner"])
            if uuid in data["tenant"]:
                data["tenant"][uuid]["count"] += 1
                data["tenant"][uuid]["bytes"] += int(image["size"])
                if "image_type" in image["properties"] and image["properties"]["image_type"] == "snapshot":
                    data["tenant"][uuid]["snapshot.count"] += 1
                    data["tenant"][uuid]["snapshot.bytes"] += int(image["size"])
            else:
                data["tenant"][uuid] = dict()
                data["tenant"][uuid]["count"] = 1
                data["tenant"][uuid]["bytes"] = int(image["size"])
                data["tenant"][uuid]["snapshot.count"] = 0
                data["tenant"][uuid]["snapshot.bytes"] = 0
                if "image_type" in image["properties"] and image["properties"]["image_type"] == "snapshot":
                    data["tenant"][uuid]["snapshot.count"] += 1
                    data["tenant"][uuid]["snapshot.bytes"] += int(image["size"])
        # debug
        #for key in data.keys():
        #    if key == "tenant":
        #        for uuid in data[key].keys():
        #            for field in data[key][uuid]:
        #                print "glance.images.tenant.%s.%s : %i" % (uuid, field, data[key][uuid][field])
        #    else:
        #        print "glance.images.%s : %i" % (key, data[key])
        ##########
        return data

def configure_callback(conf):
    """Received configuration information"""
    global OS_USERNAME, OS_PASSWORD, OS_TENANT_NAME, OS_AUTH_URL
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
        if key == "tenant":
            for uuid in info[key].keys():
                for field in info[key][uuid]:
                    logger('verb', 'Dispatching glance.images.tenant.%s.%s : %i' % (uuid, field, int(info[key][uuid][field])))
                    path = 'glance.images.%s.%s' % (uuid, field)
                    val = collectd.Values(plugin=path)
                    val.type = 'gauge'
                    val.values = [int(info[key][uuid][field])]
                    val.dispatch()
        else:
            logger('verb', 'Dispatching %s : %i' % (key, int(info[key])))
            path = 'glance.images.%s' % (key)
            val = collectd.Values(plugin=path)
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
collectd.warning("Initializing glance plugin")
collectd.register_read(read_callback)
