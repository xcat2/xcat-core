#!/usr/bin/env python

import os
import re
import errno
import subprocess

USING_COLLECTD=0

try:
    import collectd
    USING_COLLECTD=1
except:
    pass

# ===============================================================================
# [2012-06-19 21:37:04] Checking ring md5sum's on 3 hosts...
# 3/3 hosts matched, 0 error[s] while checking hosts.
# ===============================================================================
def get_md5sums():
    retval = 0
    output = subprocess.Popen(['swift-recon', '--objmd5'], stdout=subprocess.PIPE).communicate()[0]
    for line in output.split("\n"):
        result = re.search("([0-9]+) error", line)
        if result:
            retval = result.group(1)
    return retval


# ===============================================================================
# [2012-06-19 21:36:27] Checking replication times on 3 hosts...
# [Replication Times] shortest: 0.00546943346659, longest: 0.00739345153173, avg: 0.00669538444943
# ===============================================================================
def get_replication_times():
    retval = {}
    output = subprocess.Popen(['swift-recon', '-r'], stdout=subprocess.PIPE).communicate()[0]
    for line in output.split("\n"):
        result = re.search("shortest: ([0-9\.]+), longest: ([0-9\.]+), avg: ([0-9\.]+)", line)
        if result:
            retval['shortest'] = float(result.group(1))
            retval['longest'] = float(result.group(2))
            retval['average'] = float(result.group(3))
    return retval

def get_all():
    stats = {}
    stats['md5sums'] = get_md5sums()
    stats['replication_times'] = get_replication_times()
    return stats

def config_callback(conf):
    pass

def read_callback():
    stats = get_all()

    if not stats:
        return

    # blarg, this should be fixed
    for key in stats.keys():
        path = '%s' % key
        value = stats[key]

        if type(value) != type({}):
            # must be an int
            val = collectd.Values(plugin=path)
            val.type = 'gauge'
            val.values = [int(value)]
            val.dispatch()
        else:
            # must be a hash
            for subvalue in value.keys():
                path = '%s.%s' % (key, subvalue)
                val = collectd.Values(plugin=path)
                val.type = 'gauge'
                if type(value[subvalue]) == type("string"):
                    val.values = [int(value[subvalue])]
                else:
                    val.values = value[subvalue]
                val.dispatch()

if not USING_COLLECTD:
    stats = get_all()
    print stats
else:
    collectd.register_config(config_callback)
    collectd.register_read(read_callback)
