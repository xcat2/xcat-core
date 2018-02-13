#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
from __future__ import print_function
import os, stat

from common import utils
from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc
#from paramiko import SSHClient
from pssh.pssh_client import ParallelSSHClient
from gevent import joinall

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

    def _create_copy_file(self, filename):
        f = open(filename, 'w')
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
cat /tmp/$userid/.ssh/id_rsa.pub >> $dest_dir/authorized_keys 2>&1 \n\
rm -f /tmp/$userid/.ssh/* 2>&1 \n\
rmdir \"/tmp/$userid/.ssh\" \n\
rmdir \"/tmp/$userid\" \n")

        f.close()
        os.chmod(filename,stat.S_IRWXU)
        return

    def _prepare_hosts_cfg(self, nodesinfo):
        host_config = {}
        for node in nodesinfo.keys():
            nodeinfo = nodesinfo[node]
            utils.update2Ddict(host_config, nodeinfo['bmcip'], 'user', nodeinfo['username'])
            utils.update2Ddict(host_config, nodeinfo['bmcip'], 'password', nodeinfo['password'])
        return host_config 

    def pre_set_sshcfg(self, *arg, **kw):
        self.callback.syslog("Run into pre_set_sshcfg")
        local_home_dir=os.path.expanduser('~')
        local_ssh_dir = local_home_dir + "/.ssh/"
        local_public_key = local_ssh_dir + "id_rsa.pub"
        copy_sh_file = local_ssh_dir + "./copy.sh"
        tmp_remote_dir = "/tmp/root/.ssh/"
        self._create_copy_file(copy_sh_file) 
        self.callback.syslog("Generate %s file done" % copy_sh_file)
        hosts_config = self._prepare_hosts_cfg(self.inventory)

        self.callback.syslog("Start to run SSH parallelly")
        client = ParallelSSHClient(hosts_config.keys(), host_config=hosts_config)
        self.callback.syslog("mkdir -p %s" % tmp_remote_dir)
        client.run_command("/bin/mkdir -p %s" % tmp_remote_dir)
        self.callback.info("Copy files to remote hosts: %s-->%s" % (local_ssh_dir, tmp_remote_dir))
        nodes_copy = client.copy_file(local_ssh_dir, tmp_remote_dir, recurse=True)
        try:
            joinall(nodes_copy, raise_error=True)
        except Exception as e:
            self.callback.info("Error: %s" % e)
        self.callback.info("run copy.sh")
        client.run_command("%s/copy.sh root" %(tmp_remote_dir, )) 
        return

    def set_sshcfg(self, **kw):
        node = kw['node']
        nodeinfo = kw['nodeinfo']
        return self.callback.info("%s: ssh keys copied to %s" %(node, nodeinfo['bmcip']))

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
            self._get_netinfo(ip=netinfo_dict.has_key('ip'), ipsrc=netinfo_dict.has_key('ipsrc'), netmask=netinfo_dict.has_key('netmask'),
                              gateway=netinfo_dict.has_key('gateway'),vlan= netinfo_dict.has_key('vlan'), 
                              hostname=netinfo_dict.has_key('hostname'), **kw)

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

    def _get_and_parse_netinfo(self, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            data = obmc.get_netinfo()
        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s' % (node, e.message))
            return
        netinfo = {}
        for k, v in data.items():
            if k.find("network/config") >= 0:
                if v.has_key("HostName"):
                    netinfo["hostname"] = v["HostName"]
                if v.has_key("DefaultGateway"):
                    netinfo["defaultgateway"] = v["DefaultGateway"]
                continue
            dev,match,netid = k.partition("/ipv4/")
            if netid:
                if v["Origin"].find("LinkLocal") >= 0 or v["Address"].startswith("169.254"):
                    self.callback.info("%s: Found LinkLocal address %s for interface %s, Ignoring..." % (node, v["Address"], dev))
                    continue
                nicid = dev.split('/')[-1]
                if not netinfo.has_key(nicid):
                    netinfo[nicid] = {}
                if netinfo[nicid].has_key("ip"):
                    self.callback.error("%s: Another valid ip %s found." % (node, v["Address"]))
                    continue
                utils.update2Ddict(netinfo, nicid, "ipsrc", v["Origin"].split('.')[-1])
                utils.update2Ddict(netinfo, nicid, "netmask", v["PrefixLength"])
                utils.update2Ddict(netinfo, nicid, "gateway", v["Gateway"])
                utils.update2Ddict(netinfo, nicid, "ip", v["Address"])
                if data.has_key(dev):
                    info = data[dev]
                    utils.update2Ddict(netinfo, nicid, "vlanid", info["Id"])
                    utils.update2Ddict(netinfo, nicid, "mac", info["MACAddress"])
                    utils.update2Ddict(netinfo, nicid, "ntpservers", info["NTPServers"])
        self.callback.info("Netinfo: %s" % netinfo) 
        return netinfo
    def _get_netinfo(self, ip=False, ipsrc=False, netmask=False, gateway=False, vlan=False, hostname=False, ntpserver=True, **kw):
        node = kw["node"]
        netinfo = self._get_and_parse_netinfo(**kw)
        if not netinfo:
            return self.callback.error("%s: No network information get" % node)
        defaultgateway = "n/a"
        bmchostname = ""
        if netinfo.has_key("defaultgateway"):
            defaultgateway = netinfo["defaultgateway"]
            del netinfo["defaultgateway"]
        if netinfo.has_key("hostname"):
            bmchostname = netinfo["hostname"]
            del netinfo["hostname"]

        if hostname:
            self.callback.info("%s: BMC Hostname: %s" %(node, bmchostname))
        dic_length = len(netinfo) 
        self.callback.info("dic_length: %s: %s" %(dic_length, netinfo))
        ip_list = []
        ipsrc_list = []
        netmask_list = []
        gateway_list = []
        vlan_list = []
        ntpserver_list = []
        for nic,attrs in netinfo.items():
            addon_string = ''
            if dic_length > 1:
                addon_string = " for %s" % nic
            ip_list.append("BMC IP"+addon_string+": %s" % attrs["ip"])
            netmask_list.append("BMC Netmask"+addon_string+": %s" % attrs["netmask"])
            gateway_list.append("BMC Gateway"+addon_string+": %s (default: %s)" % (attrs["gateway"], defaultgateway))
            vlan_list.append("BMC VLAN ID"+addon_string+": %s" % attrs["vlanid"])
            ipsrc_list.append("BMC IP Source"+addon_string+": %s" % attrs["ipsrc"])
            ntpserver_list.append("BMC NTP Servers"+addon_string+": %s" % attrs["ntpservers"])
        if ip:
            for i in ip_list:
                self.callback.info("%s: %s" % (node, i))
        if netmask:
            for i in netmask_list:
                self.callback.info("%s: %s" % (node, i))
        if gateway:
            for i in gateway_list:
                self.callback.info("%s: %s" % (node, i))
        if ipsrc:
            for i in ipsrc_list:
                self.callback.info("%s: %s" % (node, i))
        if vlan:
            for i in vlan_list:
                self.callback.info("%s: %s" % (node, i))
        if ntpserver:
            for i in ntpserver_list:
                self.callback.info("%s: %s" % (node, i))
        return
