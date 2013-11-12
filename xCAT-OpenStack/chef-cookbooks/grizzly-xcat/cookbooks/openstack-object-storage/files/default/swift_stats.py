#!/usr/bin/env python

import os
import errno

from resource import getpagesize

USING_COLLECTD=0

try:
    import collectd
    USING_COLLECTD=1
except:
    pass

def get_unmounts(mountpath="/srv/node/"):
    try:
        candidates = [ x for x in os.listdir(mountpath) if os.path.isdir(mountpath + x) ]
    except OSError as e:
        if e.errno != errno.ENOENT:
            raise
        return 0

    mounts = []
    with open('/proc/mounts', 'r') as procmounts:
        for line in procmounts:
            _, mounted_path, _, _, _, _ = line.rstrip().split()
            if mounted_path.startswith(mountpath):
                mounts.append(mounted_path.split('/')[-1])

    return len(set(candidates) - set(mounts))

def get_sockstats():
    sockstat = {}
    try:
        with open('/proc/net/sockstat') as proc_sockstat:
            for entry in proc_sockstat:
                if entry.startswith("TCP: inuse"):
                    tcpstats = entry.split()
                    sockstat['tcp_in_use'] = int(tcpstats[2])
                    sockstat['orphan'] = int(tcpstats[4])
                    sockstat['time_wait'] = int(tcpstats[6])
                    sockstat['tcp_mem_allocated_bytes'] = \
                        int(tcpstats[10]) * getpagesize()
    except OSError as e:
        if e.errno != errno.ENOENT:
                raise
    try:
        with open('/proc/net/sockstat6') as proc_sockstat6:
            for entry in proc_sockstat6:
                if entry.startswith("TCP6: inuse"):
                    sockstat['tcp6_in_use'] = int(entry.split()[2])
    except IOError as e:
        if e.errno != errno.ENOENT:
            raise
    return sockstat

def get_all():
    stats = {}
    stats['socket'] = get_sockstats()
    stats['unmounts'] = get_unmounts()
    return stats

def config_callback(conf):
    pass

def read_callback():
    stats = get_all()

    if not stats:
        return

    # blarg, this should be fixed
    for key in stats.keys():
        path = "%s" % key
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
                val.values = [int(value[subvalue])]
                val.dispatch()

if not USING_COLLECTD:
    stats = get_all()
    print stats
else:
    collectd.register_config(config_callback)
    collectd.register_read(read_callback)
