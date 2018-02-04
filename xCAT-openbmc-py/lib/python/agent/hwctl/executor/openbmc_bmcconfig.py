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

RSPCONFIG_APIS = {
    'autoreboot' : {
        'baseurl': "/control/host0/auto_reboot/",
        'set_url': "attr/AutoReboot",
        'get_url': "attr/AutoReboot",
        'display_name': "BMC AutoReboot",
    },
    'powersupplyredundancy':{
        'baseurl': "/sensors/chassis/PowerSupplyRedundancy/",
        'set_url': "/action/setValue",
        'get_url': "/action/getValue",
        'get_method': 'POST',
        'get_data': '[]',
        'display_name': "BMC PowerSupplyRedundancy",
        'attr_values': {
            'disabled': "Disables",
            'enabled': "Enabled",
        },
    },
    'powerrestorepolicy': {
        'baseurl': "/control/host0/power_restore_policy/",
        'set_url': "attr/PowerRestorePolicy",
        'get_url': "attr/PowerRestorePolicy",
        'display_name': "BMC PowerRestorePolicy",
         'attr_values': {
             'restore': "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.Restore",
             'always_on': "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.AlwaysOn",
             'always_off': "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.AlwaysOff",
         },
    },
    'bootmode': {
        'baseurl': "/control/host0/boot/",
        'set_url': "attr/BootMode",
        'get_url': "attr/BootMode",
        'display_name':"BMC BootMode",
        'attr_values': {
            'regular': "xyz.openbmc_project.Control.Boot.Mode.Modes.Regular",
            'safe': "xyz.openbmc_project.Control.Boot.Mode.Modes.Safe",
            'setup': "xyz.openbmc_project.Control.Boot.Mode.Modes.Setup",
        },
    },
}

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
        netinfo_dict={'ip':False, 'ipsrc':False, 'netmask':False, 
                       'gateway':False, 'vlan':False, 'hostname':False}
        getnet=0
        for attr in attributes:
            if attr in RSPCONFIG_GET_NETINFO:
                netinfo_dict[attr]=True
                getnet=1
            elif RSPCONFIG_APIS.has_key(attr):
                return self._get_apis_values(attr, **kw)
            else:
                return self.callback.error("get_attributes can not deal with attr %s" % attr)
        if getnet:
            self._get_netinfo(netinfo_dict['ip'], netinfo_dict['ipsrc'], netinfo_dict['netmask'],
                              netinfo_dict['gateway'], netinfo_dict['vlan'], netinfo_dict['hostname'], **kw)

    def set_attributes(self, attributes, **kw):
        netinfo_dict={'vlan':False}
        for attr in attributes:
            k,v = attr.split('=')
            if k in RSPCONFIG_SET_NETINFO:
                netinfo_dict[k] = v
            elif k == 'hostname':
                return self._set_hostname(v, **kw)
            elif RSPCONFIG_APIS.has_key(k):
                return self._set_apis_values(k, v, **kw)
            else:
                return self.callback.error("set_attributes unsupported attribute:%s" % k)
        if (not netinfo_dict['ip']) or (not netinfo_dict['netmask']) or (not netinfo_dict['gateway']):
            return self.callback.error("set_attributes miss either ip, netmask or gateway to set network information")
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
        attr_info = RSPCONFIG_APIS[key]
        if not attr_info.has_key('set_url'):
            return self.callback.error("config %s failed, not url available" % key)
        set_url = attr_info['baseurl']+attr_info['set_url']

        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        if attr_info.has_key('attr_values') and attr_info['attr_values'].has_key(value):
            data = attr_info['attr_values'][value]
        else:
            data = value

        try:
            obmc.login()
            obmc.request('PUT', set_url, payload={"data": data}, cmd="set_%s" % key)
        except (SelfServerException, SelfClientException) as e:
            self.callback.info("%s: %s" % (node, e.message))

        self.callback.info("%s: BMC Setting %s..." % (node, attr_info['display_name']))

    def _get_apis_values(self, key, **kw):
        node = kw['node']
        attr_info = RSPCONFIG_APIS[key]
        if not attr_info.has_key('get_url'):
            return self.callback.error("Reading %s failed, not url available" % key)
        get_url = attr_info['baseurl']+attr_info['get_url']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            method = 'GET'
            if attr_info.has_key('get_method'):
                method = attr_info['get_method']
            data = None
            if attr_info.has_key('get_data'):
                data={"data": attr_info['get_data']}
            value = obmc.request(method, get_url, payload=data, cmd="get_%s" % key)
            str_value = '0.'+str(value)
            result = '%s: %s: %s' % (node, attr_info['display_name'], str_value.split('.')[-1])

        except (SelfServerException, SelfClientException) as e:
            result = '%s: %s'  % (node, e.message)

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
