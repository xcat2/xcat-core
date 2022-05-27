#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
from __future__ import print_function
import os, stat
import sys
if 'threading' in sys.modules:
    del sys.modules['threading']
from gevent import monkey
monkey.patch_all()
from gevent import sleep
import paramiko
from paramiko.ssh_exception import NoValidConnectionsError

import time

from common import utils
from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc

from scp import SCPClient

import logging
logger = logging.getLogger('xcatagent')

RSPCONFIG_GET_NETINFO=['ip', 'netmask', 'gateway', 'vlan', 'ipsrc', 'hostname', 'ntpservers']
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
        host_name = os.uname()[1].split('.', 1)[0]
        if flag_dump_process:
            self.callback.info('%s: Downloading dump %s to %s:%s' % (node, download_id, host_name, dump_log_file))

        obmc.download_dump(download_id, dump_log_file)
        if os.path.exists(dump_log_file):
            grep_cmd = '/usr/bin/grep -a'
            path_not_found = '"Path not found"'
            check_cmd = grep_cmd + ' ' + path_not_found + ' ' + dump_log_file
            grep_string = os.popen(check_cmd).readlines()
            if grep_string:
                self.callback.error('Invalid dump %s was specified. Use -l option to list.' % download_id, node)
            else:
                self.callback.info('%s: Downloaded dump %s to %s:%s.' % (node, download_id, host_name, dump_log_file))
        else:
            self.callback.error('Failed to download dump %s to %s.' % (download_id, dump_log_file), node)
        return

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

            keys = list(dump_dict.keys())
            keys.sort()
            for key in keys:
                info = '[%d] Generated: %s, Size: %s' % \
                       (key, dump_dict[key]['Generated'], dump_dict[key]['Size'])
                dump_info += info
                self.callback.info('%s: %s'  % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

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
            self.callback.error(e.message, node)

        return dump_id

    def dump_clear(self, clear_arg, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            obmc.clear_dump(clear_arg)

            self.callback.info('%s: [%s] clear' % (node, clear_arg))
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

    def dump_download(self, download_arg, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            if download_arg != 'all':
                self._dump_download(obmc, node, download_arg)
                return

            dump_dict = obmc.list_dump_info()
            keys = list(dump_dict.keys())
            keys.sort()

            for key in keys:
                self._dump_download(obmc, node, str(key))
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

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

                sleep( 15 )

            if flag:
                self._dump_download(obmc, node, str(dump_id), flag_dump_process=True)
            else:
                self.callback.error('Could not find dump %s after waiting %d seconds.' % (dump_id, 20 * 15), node)

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

    def gard_clear(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            obmc.clear_gard()
            self.callback.info('%s: GARD cleared' % node)

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

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
        try:
            ssh_client = paramiko.SSHClient()
            ssh_client.set_missing_host_key_policy(paramiko.MissingHostKeyPolicy())
            ssh_client.connect(nodeinfo['bmcip'], username=nodeinfo['username'], password=nodeinfo['password'])
        except (NoValidConnectionsError) as e:
            return self.callback.error("Unable to connect to bmc %s" % nodeinfo['bmcip'], node)
        if not ssh_client.get_transport().is_active():
            return self.callback.error("SSH session to bmc %s is not active" % nodeinfo['bmcip'], node)
        if not ssh_client.get_transport().is_authenticated():
            return self.callback.error("SSH session to bmc %s is not authenticated" % nodeinfo['bmcip'], node)
        ssh_client.exec_command("/bin/mkdir -p %s\n" % tmp_remote_dir)
        scp = SCPClient(ssh_client.get_transport())
        scp.put(self.copy_sh_file, tmp_remote_dir + "copy.sh")
        scp.put(self.local_public_key, tmp_remote_dir + "id_rsa.pub")
        ssh_client.exec_command("%s/copy.sh %s" % (tmp_remote_dir, nodeinfo['username']))
        ssh_client.close()
        return self.callback.info("ssh keys copied to %s" % nodeinfo['bmcip'])


    def set_ipdhcp(self, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_ipdhcp()
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return

        self.callback.info("%s: BMC Setting IP to DHCP..." % (node))
        try:
            obmc.reboot_bmc()
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

    def get_attributes(self, attributes, **kw):
        netinfo_dict={}
        for attr in attributes:
            if attr in RSPCONFIG_GET_NETINFO:
                netinfo_dict[attr]=True
                getnet=1
            elif attr in openbmc.RSPCONFIG_APIS:
                self._get_apis_values(attr, **kw)
            else:
                self.callback.error("get_attributes can not deal with attr %s" % attr, kw['node'])
        if len(netinfo_dict):
            self._get_netinfo(ip=netinfo_dict.get('ip', False), ipsrc=netinfo_dict.get('ipsrc', False), netmask=netinfo_dict.get('netmask', False),
                              gateway=netinfo_dict.get('gateway', False),vlan= netinfo_dict.get('vlan', False),
                              hostname=netinfo_dict.get('hostname', False),
                              ntpservers=netinfo_dict.get('ntpservers', False), **kw)

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
            elif k == 'ntpservers':
                self._set_ntp_servers(v, **kw)
            elif k in openbmc.RSPCONFIG_APIS:
                self._set_apis_values(k, v, **kw)
            else:
                return self.callback.error("set_attributes unsupported attribute:%s" % k, node)
        if len(netinfo_dict) > 1 and ('ip' not in netinfo_dict or 'netmask' not in netinfo_dict or 'gateway' not in netinfo_dict):
            self.callback.info("set_attributes miss either ip, netmask or gateway to set network information")
        elif len(netinfo_dict) <= 1:
            return
        else:
            self._set_netinfo(netinfo_dict['ip'], netinfo_dict['netmask'],
                              netinfo_dict['gateway'], netinfo_dict['vlan'], **kw)

    def _set_hostname(self, hostname, **kw):
        node = kw['node']
        if hostname == '*':
            if kw['nodeinfo']['bmc'] != kw['nodeinfo']['bmcip']:
                hostname = kw['nodeinfo']['bmc']
            else:
                return self.callback.error("Invalid OpenBMC Hostname %s, can't set to OpenBMC" % kw['nodeinfo']['bmc'], node)
        self._set_apis_values("hostname", hostname, **kw)
        self._get_netinfo(hostname=True, ntpserver=False, **kw)
        return

    def _set_ntp_servers(self, servers, **kw):
        node = kw['node']
        node_info = kw['nodeinfo']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=node_info, messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            netinfo = obmc.get_netinfo()
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return

        if not netinfo:
            return self.callback.error('No network information get', node)

        if 'error' in netinfo:
            self.callback.info('%s: %s' % (node, netinfo['error']))
            return

        bmcip = node_info['bmcip']
        nic = self._get_facing_nic(bmcip, netinfo)
        if not nic:
            return self.callback.error('Can not get facing NIC for %s' % bmcip, node)

        if (netinfo[nic]['ipsrc'] == 'DHCP'):
            return self.callback.error('BMC IP source is DHCP, could not set NTPServers', node)

        try:
            obmc.set_ntp_servers(nic, servers)
            self.callback.info('%s: BMC Setting NTPServers...' % node)
            netinfo = obmc.get_netinfo()
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return

        ntpservers = None
        if nic in netinfo:
            ntpservers = netinfo[nic]['ntpservers']
        self.callback.info('%s: BMC NTP Servers: %s' % (node, ntpservers))
        if ntpservers != None:
            # Display a warning if the host in not powered off
            # Time on the BMC is not synced while the host is powered on
            self.callback.info('%s: Warning: time will not be synchronized until the host is powered off.' % node)

    def _get_facing_nic(self, bmcip, netinfo):
        for k,v in netinfo.items():
            if 'ip' in v and v['ip'] == bmcip:
                return k
        return None

    def _set_admin_password(self, admin_passwd, **kw):
        node = kw['node']
        node_info = kw['nodeinfo']

        origin_passwd, new_passwd = admin_passwd.split(',')

        if origin_passwd != node_info['password']:
            self.callback.error('Current BMC password is incorrect, cannot set the new password.', node)
            return

        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=node_info, messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_admin_passwd(new_passwd)
            self.callback.info("%s: BMC Setting Password..." % node)
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return

        self.callback.info("%s: BMC password changed. Update 'bmcpasswd' for the node or the 'passwd' table with the new password." % node)

    def _set_apis_values(self, key, value, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            obmc.set_apis_values(key, value)
        except SelfServerException as e:
            return self.callback.error(e.message, node)
        except SelfClientException as e:
            if e.code == 404:
                return self.callback.error('404 Not Found - Requested endpoint does not exist or may ' \
                                           'indicate function is not supported on this OpenBMC firmware.', node)
            if e.code == 403:
                return self.callback.error('403 Forbidden - Requested endpoint does not exist or may ' \
                                           'indicate function is not yet supported by OpenBMC firmware.', node)
            return self.callback.error(e.message, node)

        self.callback.info("%s: BMC Setting %s..." % (node, openbmc.RSPCONFIG_APIS[key]['display_name']))

    def _get_powersupplyredundancy_value(self, node, obmc):
        try:
            psr_info = obmc.get_powersupplyredundancy()
            for key, value in psr_info.items():
                if key == 'PowerSupplyRedundancyEnabled':
                   result = '%s: %s: %s' % (node, openbmc.RSPCONFIG_APIS['powersupplyredundancy']['display_name'],
                                             openbmc.RSPCONFIG_APIS['powersupplyredundancy']['attr_values'][str(value)][0])
                   return self.callback.info(result)
        except SelfServerException as e:
            return self.callback.error(e.message, node)
        except SelfClientException as e:
            if e.code == 404:
                return self.callback.error('404 Not Found - Requested endpoint does not exist or may ' \
                                           'indicate function is not supported on this OpenBMC firmware.', node)
            if e.code == 403:
                return self.callback.error('403 Forbidden - Requested endpoint does not exist or may ' \
                                           'indicate function is not yet supported by OpenBMC firmware.', node)
            return self.callback.error(e.message, node)

    def _get_apis_values(self, key, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            value = obmc.get_apis_values(key)

        except SelfServerException as e:
            return self.callback.error(e.message, node)
        except SelfClientException as e:
            if e.code == 404:
                if key == 'powersupplyredundancy':
                    return self._get_powersupplyredundancy_value(node, obmc)

                return self.callback.error('404 Not Found - Requested endpoint does not exist or may ' \
                                           'indicate function is not supported on this OpenBMC firmware.', node)
            if e.code == 403:
                return self.callback.error('403 Forbidden - Requested endpoint does not exist or may ' \
                                           'indicate function is not yet supported by OpenBMC firmware.', node)
            return self.callback.error(e.message, node)

        if isinstance(value, dict):
            str_value = str(list(value.values())[0])
        elif value:
            str_value = str(value)
        else:
            str_value = '0'
        result = '%s: %s: %s' % (node, openbmc.RSPCONFIG_APIS[key]['display_name'], str_value.split('.')[-1])
        self.callback.info(result)

    def _print_bmc_netinfo(self, node, ip, netmask, gateway, vlan):

        self.callback.info('%s: BMC IP: %s' % (node, ip))
        self.callback.info('%s: BMC Netmask: %s' % (node, netmask))
        self.callback.info('%s: BMC Gateway: %s' % (node, gateway))
        if vlan:
            self.callback.info('%s: BMC VLAN ID: %s' % (node, vlan))

    def _set_netinfo(self, ip, netmask, gateway, vlan=False, **kw):

        node = kw['node']
        node_info = kw['nodeinfo']
        zeroconf = "Unknown"
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=node_info, messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            netinfo = obmc.get_netinfo()
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return

        if not netinfo:
            return self.callback.error("Can not get network information", node)
        if 'error' in netinfo:
            return self.callback.info('%s: %s' % (node, netinfo['error']))

        bmcip = node_info['bmcip']
        origin_nic = nic = self._get_facing_nic(bmcip, netinfo)
        if not nic:
            return self.callback.error('Can not get facing NIC for %s' % bmcip, node)

        prefix = int(utils.mask_str2int(netmask))

        if (ip == netinfo[nic]['ip'] and prefix == netinfo[nic]['netmask'] and
           gateway == netinfo[nic]['gateway']):
            if not vlan or vlan == str(netinfo[nic]['vlanid']):
                self._print_bmc_netinfo(node, ip, netmask, gateway, vlan)
                return

        origin_type = netinfo[origin_nic]['ipsrc']
        origin_ip_obj = netinfo[origin_nic]['ipobj']
        zeroconf = netinfo[origin_nic]['zeroconf']

        if vlan:
            pre_nic = nic.split('_')[0]
            try:
                obmc.set_vlan(pre_nic, vlan)
                sleep( 15 )
            except (SelfServerException, SelfClientException) as e:
                self.callback.error(e.message, node)
                return
            nic = pre_nic + '_' + vlan

        try:
            # Display Zero Config information in case IP setting fails or set IP is not accessible
            self.callback.info('%s: Setting BMC IP configuration... [Zero Config IP: %s]' % (node, zeroconf))
            obmc.set_netinfo(nic, ip, prefix, gateway)
            sleep( 5 )
            nic_netinfo = obmc.get_nic_netinfo(nic)
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return

        if not nic_netinfo:
            return self.callback.error('Can not get info for NIC %s' % nic, node)

        set_success = False
        for net_id, attr in nic_netinfo.items():
            if (attr['ip'] == ip and
                attr["netmask"] == prefix and
                attr['gateway'] == gateway):
                set_success = True

        if not set_success:
            return self.callback.error('Setting BMC IP configuration failed. [Zero Config IP: %s]' % zeroconf, node)

        try:
            if origin_type == 'DHCP':
                obmc.disable_dhcp(origin_nic)
            elif origin_type == 'Static':
                obmc.delete_ip_object(origin_nic, origin_ip_obj)
            else:
                self.callback.error('Got wrong origin type %s for NIC %s IP object %s' % (origin_type, nic, origin_ip_obj), node)
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        self. _print_bmc_netinfo(node, ip, netmask, gateway, vlan)

    def _get_netinfo(self, ip=False, ipsrc=False, netmask=False, gateway=False, vlan=False, hostname=False, ntpservers=False, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            netinfo = obmc.get_netinfo()
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
            return
        if not netinfo:
            return self.callback.error("Can not get network information", node)
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

        if 'error' in netinfo:
            return self.callback.info('%s: %s' % (node, netinfo['error']))

        dic_length = len(netinfo)
        netinfodict = {'ip':[], 'netmask':[], 'gateway':[],
                   'vlan':[], 'ipsrc':[], 'ntpservers':[]}
        for nic,attrs in netinfo.items():
            addon_string = ''
            if dic_length > 1:
                addon_string = " for %s" % nic
            netinfodict['ip'].append("BMC IP"+addon_string+": %s" % attrs.get("ip", None))
            netinfodict['netmask'].append("BMC Netmask"+addon_string+": %s" % utils.mask_int2str(attrs.get("netmask", 24)))
            netinfodict['gateway'].append("BMC Gateway"+addon_string+": %s (default: %s)" % (attrs.get("gateway", None), defaultgateway))
            netinfodict['vlan'].append("BMC VLAN ID"+addon_string+": %s" % attrs.get("vlanid", None))
            netinfodict['ipsrc'].append("BMC IP Source"+addon_string+": %s" % attrs.get("ipsrc", None))
            netinfodict['ntpservers'].append("BMC NTP Servers"+addon_string+": %s" % attrs.get("ntpservers", None))
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
        if ntpservers:
            for i in netinfodict['ntpservers']:
                self.callback.info("%s: %s" % (node, i))
        return netinfo
