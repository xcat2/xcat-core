#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
from __future__ import print_function
import os, stat
import gevent
import time

from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc

import logging
logger = logging.getLogger('xcatagent')

RSPCONFIG_GET_NETINFO=['ip', 'netmask', 'gateway', 'vlan', 'ipsrc', 'hostname']
RSPCONFIG_SET_NETINFO=['ip', 'netmask', 'gateway', 'vlan']

XCAT_LOG_DUMP_DIR = "/var/log/xcat/dump/"

class OpenBMCBmcConfigTask(ParallelNodesCommand):

    def pre_dump_download(self, task, download_arg, **kw):

       if download_arg == 'all':
            self.callback.info('Downloading all dumps...')
       if not os.path.exists(XCAT_LOG_DUMP_DIR):
            os.makedirs(XCAT_LOG_DUMP_DIR) 

    def pre_dump_process(self, task, **kw):

        self.callback.info('Capturing BMC Diagnostic information, this will take some time...')

    def _dump_download(self, obmc, node, download_id, flag_dump_process=False):

        formatted_time = time.strftime("%Y%m%d-%H%M", time.localtime(time.time()))
        dump_log_file = '%s%s_%s_dump_%s.tar.xz' % (XCAT_LOG_DUMP_DIR, formatted_time, node, download_id)
        if flag_dump_process:
            self.callback.info('%s: Downloading dump %s to %s' % (node, download_id, dump_log_file))

        obmc.download_dump(download_id, dump_log_file)
        if os.path.exists(dump_log_file):
            grep_cmd = '/usr/bin/grep -a'
            path_not_found = '"Path not found"'
            check_cmd = grep_cmd + ' ' + path_not_found + ' ' + dump_log_file
            grep_string = os.popen(check_cmd).readlines()
            if grep_string:
                result = 'Invalid dump %s was specified. Use -l option to list.' % download_id
            else:
                result = 'Downloaded dump %s to %s.' % (download_id, dump_log_file)
        else:
            result = 'Failed to download dump %s to %s.' % (download_id, dump_log_file)
        return result

    def dump_list(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        dump_info = []
        try:
            obmc.login()
            dump_dict = obmc.list_dump_info()

            if not dump_dict:
                self.callback.info('%s: No attributes returned from the BMC.' % node)

            keys = dump_dict.keys()
            keys.sort()
            for key in keys:
                info = '[%d] Generated: %s, Size: %s' % \
                       (key, dump_dict[key]['Generated'], dump_dict[key]['Size'])
                dump_info += info
                self.callback.info('%s: %s'  % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s'  % (node, e.message))

        return dump_info

    def dump_generate(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        dump_id = None
        try:
            obmc.login()
            dump_id = obmc.create_dump()
            if not dump_id:
                self.callback.info('%s: BMC returned 200 OK but no ID was returned.  Verify manually on the BMC.' % node)
            else:
                self.callback.info('%s: [%s] success'  % (node, dump_id))
        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s'  % (node, e.message))

        return dump_id

    def dump_clear(self, clear_arg, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            obmc.clear_dump(clear_arg)

            result = '%s: [%s] clear' % (node, clear_arg)  
        except (SelfServerException, SelfClientException) as e:
            result = '%s: %s'  % (node, e.message)

        self.callback.info(result) 

    def dump_download(self, download_arg, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            if download_arg != 'all':
                result = self._dump_download(obmc, node, download_arg)
                self.callback.info('%s: %s'  % (node, result))
                return

            dump_dict = obmc.list_dump_info()
            keys = dump_dict.keys()
            keys.sort()

            for key in keys:
                result = self._dump_download(obmc, node, str(key))
                self.callback.info('%s: %s'  % (node, result))
        except SelfServerException as e:
            self.callback.info('%s: %s'  % (node, e.message))

    def dump_process(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            flag = False
            dump_id = obmc.create_dump()
            self.callback.info('%s: Dump requested. Target ID is %s, waiting for BMC to generate...'  % (node, dump_id)) 
            for i in range(20):
                dump_dict = obmc.list_dump_info()            
                if dump_id in dump_dict:
                    flag = True
                    break
                if (20-i) % 8 == 0:
                    self.callback.info('%s: Still waiting for dump %s to be generated... '  % (node, dump_id))

                gevent.sleep( 15 )

            if flag: 
                result = self._dump_download(obmc, node, str(dump_id), flag_dump_process=True)
            else:
                result = 'Could not find dump %s after waiting %d seconds.' % (dump_id, 20 * 15) 

            self.callback.info('%s: %s'  % (node, result))

        except SelfServerException as e:
            self.callback.info('%s: %s'  % (node, e.message))

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
