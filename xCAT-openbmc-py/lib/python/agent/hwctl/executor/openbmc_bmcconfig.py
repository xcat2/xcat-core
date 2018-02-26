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

from common import utils
from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc

#For rspconfig sshcfg
from pssh.ssh_client import SSHClient
from pssh.exceptions import UnknownHostException, AuthenticationException, \
     ConnectionErrorException, SSHException
from scp import SCPClient

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
                return dump_info

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

    def gard_clear(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            obmc.clear_gard()
            self.callback.info('%s: GARD cleared' % node)

        except SelfServerException as e:
            self.callback.info('%s: %s'  % (node, e.message))

    def pre_set_sshcfg(self, *arg, **kw):
        local_home_dir=os.path.expanduser('~')
        self.local_ssh_dir = local_home_dir + "/.ssh/"
        self.local_public_key = self.local_ssh_dir + "id_rsa.pub"
        self.copy_sh_file = self.local_ssh_dir + "./copy.sh"
        f = open(self.copy_sh_file, 'w')
        f.write("#!/bin/sh \n\
umask 0077 \n\
userid=$1 \n\
home=`egrep \"^$userid:\" /etc/passwd | cut -f6 -d :` \n\
if [ -n \"$home\" ]; then \n\
  dest_dir=\"$home/.ssh\" \n\
else \n\
  home=`su - root -c pwd` \n\
  dest_dir=\"$home/.ssh\" \n\
fi \n\
mkdir -p $dest_dir \n\
cat /tmp/$userid/.ssh/id_rsa.pub >> $home/.ssh/authorized_keys 2>&1 \n\
rm -f /tmp/$userid/.ssh/* 2>&1 \n\
rmdir \"/tmp/$userid/.ssh\" \n\
rmdir \"/tmp/$userid\" \n")

        f.close()
        os.chmod(self.copy_sh_file,stat.S_IRWXU)
        if self.verbose:
            self.callback.info("Prepared %s file done" % self.copy_sh_file)

    def set_sshcfg(self, **kw):
        node = kw['node']
        nodeinfo = kw['nodeinfo']
        tmp_remote_dir = "/tmp/%s/.ssh/" % nodeinfo['username']
        #try: 
        ssh_client = SSHClient(nodeinfo['bmcip'], user=nodeinfo['username'], password=nodeinfo['password'])
        #except (SSHException, NoValidConnectionsError,BadHostKeyException) as e: 
        #    self.callback.info("%s: %s" % (node, e))
        if not ssh_client.client.get_transport().is_active():
            self.callback.info("SSH session is not active")
        if not ssh_client.client.get_transport().is_authenticated():
            self.callback.info("SSH session is not authenticated")
        try:
            ssh_client.client.exec_command("/bin/mkdir -p %s\n" % tmp_remote_dir)
        except (SSHException, ConnectionErrorException) as e: 
            self.callback.info("%s: ----%s------" % (host, e))
        scp = SCPClient(ssh_client.client.get_transport()) 
        scp.put(self.copy_sh_file, tmp_remote_dir + "copy.sh")
        scp.put(self.local_public_key, tmp_remote_dir + "id_rsa.pub")
        ssh_client.client.exec_command("%s/copy.sh %s" % (tmp_remote_dir, nodeinfo['username']))
        ssh_client.client.close()
        return self.callback.info("ssh keys copied to %s" % nodeinfo['bmcip'])



    def set_ipdhcp(self, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_ipdhcp()
        except (SelfServerException, SelfClientException) as e:
            self.callback.info("%s: %s" % (node, e.message))
            return

        self.callback.info("%s: BMC Setting IP to DHCP..." % (node))
        try:
            obmc.reboot_bmc()
        except (SelfServerException, SelfClientException) as e:
            self.callback.info("%s: %s" % (node, e.message))

    def get_attributes(self, attributes, **kw):
        netinfo_dict={}
        for attr in attributes:
            if attr in RSPCONFIG_GET_NETINFO:
                netinfo_dict[attr]=True
                getnet=1
            elif attr in openbmc.RSPCONFIG_APIS:
                self._get_apis_values(attr, **kw)
            else:
                self.callback.error("get_attributes can not deal with attr %s" % attr)
        if len(netinfo_dict):
            self._get_netinfo(ip=netinfo_dict.get('ip', False), ipsrc=netinfo_dict.get('ipsrc', False), netmask=netinfo_dict.get('netmask', False),
                              gateway=netinfo_dict.get('gateway', False),vlan= netinfo_dict.get('vlan', False), 
                              hostname=netinfo_dict.get('hostname', False), **kw)

    def set_attributes(self, attributes, **kw):
        netinfo_dict={'vlan':False}
        for attr in attributes:
            k,v = attr.split('=')
            if k in RSPCONFIG_SET_NETINFO:
                netinfo_dict[k] = v
            elif k == 'hostname':
                self._set_hostname(v, **kw)
            elif k == 'admin_passwd':
                self._set_admin_password(v, **kw)
            elif k in openbmc.RSPCONFIG_APIS:
                self._set_apis_values(k, v, **kw)
            else:
                return self.callback.error("set_attributes unsupported attribute:%s" % k)
        if len(netinfo_dict) > 1 and ('ip' not in netinfo_dict or 'netmask' not in netinfo_dict or 'gateway' not in netinfo_dict):
            self.callback.info("set_attributes miss either ip, netmask or gateway to set network information")
        elif len(netinfo_dict) <= 1:
            return
        else:
            self._set_netinfo(netinfo_dict['ip'], netinfo_dict['netmask'],
                              netinfo_dict['gateway'], netinfo_dict['vlan'])

    def _set_hostname(self, hostname, **kw):
        node = kw['node']
        if hostname == '*':
            if kw['nodeinfo']['bmc'] == kw['nodeinfo']['bmcip']:
                self.callback.info("%s: set BMC ip as BMC Hostname" % node)
            hostname = kw['nodeinfo']['bmc']
        self._set_apis_values("hostname", hostname, **kw)
        self._get_netinfo(hostname=True, ntpserver=False, **kw) 
        return

    def _set_admin_password(self, admin_passwd, **kw):
        node = kw['node']
        node_info = kw['nodeinfo']

        origin_passwd, new_passwd = admin_passwd.split(',')

        if origin_passwd != node_info['password']:
            self.callback.info('%s: Current BMC password is incorrect, cannot set the new password.' % node)
            return

        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=node_info, messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_admin_passwd(new_passwd)
            self.callback.info("%s: BMC Setting Password..." % node)
        except (SelfServerException, SelfClientException) as e:
            self.callback.info("%s: %s" % (node, e.message))

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

    def _get_netinfo(self, ip=False, ipsrc=False, netmask=False, gateway=False, vlan=False, hostname=False, ntpserver=True, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            netinfo = obmc.get_netinfo()
        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s' % (node, e.message))
            return
        if not netinfo:
            return self.callback.error("%s: No network information get" % node)
        defaultgateway = "n/a"
        bmchostname = ""
        if 'defaultgateway' in netinfo:
            defaultgateway = netinfo["defaultgateway"]
            del netinfo["defaultgateway"]
        if 'hostname' in netinfo:
            bmchostname = netinfo["hostname"]
            del netinfo["hostname"]

        if hostname:
            self.callback.info("%s: BMC Hostname: %s" %(node, bmchostname))
        dic_length = len(netinfo) 
        netinfodict = {'ip':[], 'netmask':[], 'gateway':[],
                   'vlan':[], 'ipsrc':[], 'ntpserver':[]}
        for nic,attrs in netinfo.items():
            addon_string = ''
            if dic_length > 1:
                addon_string = " for %s" % nic
            netinfodict['ip'].append("BMC IP"+addon_string+": %s" % attrs["ip"])
            netinfodict['netmask'].append("BMC Netmask"+addon_string+": %s" % attrs["netmask"])
            netinfodict['gateway'].append("BMC Gateway"+addon_string+": %s (default: %s)" % (attrs["gateway"], defaultgateway))
            netinfodict['vlan'].append("BMC VLAN ID"+addon_string+": %s" % attrs["vlanid"])
            netinfodict['ipsrc'].append("BMC IP Source"+addon_string+": %s" % attrs["ipsrc"])
            netinfodict['ntpserver'].append("BMC NTP Servers"+addon_string+": %s" % attrs["ntpservers"])
        if ip:
            for i in netinfodict['ip']:
                self.callback.info("%s: %s" % (node, i))
        if netmask:
            for i in netinfodict['netmask']:
                self.callback.info("%s: %s" % (node, i))
        if gateway:
            for i in netinfodict['gateway']:
                self.callback.info("%s: %s" % (node, i))
        if ipsrc:
            for i in netinfodict['ipsrc']:
                self.callback.info("%s: %s" % (node, i))
        if vlan:
            for i in netinfodict['vlan']:
                self.callback.info("%s: %s" % (node, i))
        if ntpserver:
            for i in netinfodict['netserver']:
                self.callback.info("%s: %s" % (node, i))
        return netinfo
