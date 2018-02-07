#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
from __future__ import print_function
import gevent
import time

from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc

import logging
logger = logging.getLogger('xcatagent')

RSPCONFIG_GET_NETINFO=['ip', 'netmask', 'gateway', 'vlan', 'ipsrc', 'hostname']
RSPCONFIG_SET_NETINFO=['ip', 'netmask', 'gateway', 'vlan']

class OpenBMCBmcConfigTask(ParallelNodesCommand):
        
    def dump_list(self, **kw):
        return self.callback.info('dump_list') 

    def dump_generate(self, **kw):
        return self.callback.info("dump_generate")

    def dump_clear(self, id, **kw):
        return self.callback.info("dump_clear id: %s" % id)

    def dump_download(self, id, **kw):
        return self.callback.info("dump_download id: %s" % id)

    def dump_process(self, **kw):
        return self.callback.info("dump_process: trigger, list and download")

    def set_sshcfg(self, **kw):
        return self.callback.info("set_sshcfg")

    def set_ipdhcp(self, **kw):
        return self.callback.info("set_ipdhcp")

    def get_attributes(self, attributes, **kw):
        netinfo_dict={}
        for attr in attributes:
            if attr in RSPCONFIG_GET_NETINFO:
                netinfo_dict[attr]=True
                getnet=1
            elif openbmc.RSPCONFIG_APIS.has_key(attr):
                self._get_apis_values(attr, **kw)
            else:
                self.callback.error("get_attributes can not deal with attr %s" % attr)
        if len(netinfo_dict):
            self._get_netinfo(netinfo_dict.has_key('ip'), netinfo_dict.has_key('ipsrc'), netinfo_dict.has_key('netmask'),
                              netinfo_dict.has_key('gateway'), netinfo_dict.has_key('vlan'), netinfo_dict.has_key('hostname'), **kw)

    def set_attributes(self, attributes, **kw):
        netinfo_dict={'vlan':False}
        for attr in attributes:
            k,v = attr.split('=')
            if k in RSPCONFIG_SET_NETINFO:
                netinfo_dict[k] = v
            elif k == 'hostname':
                self._set_hostname(v, **kw)
            elif openbmc.RSPCONFIG_APIS.has_key(k):
                self._set_apis_values(k, v, **kw)
            else:
                return self.callback.error("set_attributes unsupported attribute:%s" % k)
        if len(netinfo_dict) > 1 and (not netinfo_dict.has_key('ip') or not netinfo_dict.has_key('netmask') or not netinfo_dict.has_key('gateway')):
            self.callback.info("set_attributes miss either ip, netmask or gateway to set network information")
        else:
            self._set_netinfo(netinfo_dict['ip'], netinfo_dict['netmask'],
                              netinfo_dict['gateway'], netinfo_dict['vlan'])

    def _set_hostname(self, hostname, **kw):
        if hostname == '*':
            if kw['nodeinfo']['bmc'] != kw['nodeinfo']['bmcip']:
                hostname = kw['nodeinfo']['bmc']
            else:
                hostname = '%s-bmc' % kw['node']
        return self.callback.info("set_hostname: %s" % hostname)

    def _set_apis_values(self, key, value, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_apis_values(key, value)
        except (SelfServerException, SelfClientException) as e:
            self.callback.info("%s: %s" % (node, e.message))

        self.callback.info("%s: BMC Setting %s..." % (node, openbmc.RSPCONFIG_APIS[key]['display_name']))

    def _get_apis_values(self, key, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            value = obmc.get_apis_values(key)

        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s' % (node, e.message))

        str_value = '0.'+str(value)
        result = '%s: %s: %s' % (node, openbmc.RSPCONFIG_APIS[key]['display_name'], str_value.split('.')[-1])
        self.callback.info(result)

    def _set_netinfo(self, ip, netmask, gateway, vlan=False, **kw):
        if vlan:
            result = "set net(%s, %s, %s) for vlan %s" % (ip, netmask, gateway, vlan)
        else:
            result = "set net(%s, %s, %s) for eth0" % (ip, netmask, gateway)
        return self.callback.info("set_netinfo %s" % result)

    def _get_netinfo(self, ip=False, ipsrc=False, netmask=False, gateway=False, vlan=False, hostname=False, **kw):
        result = ''
        if ip:
            result += "Get IP, "
        if netmask:
            result += "Get Mask, "
        if gateway:
            result += "Get Gateway, "
        if ipsrc:
            result += "Get IP source, "
        if hostname:
            result += "Get BMC hostname, "
        if vlan:
            result += "Get BMC vlan."
        return self.callback.info("get_netinfo: %s" % result)
