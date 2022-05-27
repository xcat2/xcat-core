#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

import os
import requests
import json
import time

from common import utils, rest
from common.exceptions import SelfClientException, SelfServerException

import logging
logger = logging.getLogger('xcatagent')

HTTP_PROTOCOL = "https://"
PROJECT_URL = "/xyz/openbmc_project"
PROJECT_PAYLOAD = "xyz.openbmc_project."

RBEACON_URLS = {
    "path"      : "/led/groups/enclosure_identify/attr/Asserted",
    "on"        : {
        "field" : True,
    },
    "off"        : {
        "field" : False,
    },
}

DUMP_URLS = {
    "clear"     : {
        "path"  : "/dump/entry/#ID#/action/Delete",
        "field" : [],
    },
    "clear_all" : {
        "path"  : "/dump/action/DeleteAll",
        "field" : [],
    },
    "create"    : {
        "path"  : "/dump/action/CreateDump",
        "field" : [],
    },
    "download"  : "download/dump/#ID#",
    "list"      : "/dump/enumerate",
}

GARD_CLEAR_URL = "/org/open_power/control/gard/action/Reset"

INVENTORY_URLS = {
    "all"       : "/inventory/enumerate",
    "model"     : "/inventory/system",
    "serial"    : "/inventory/system",
    "cpu"       : "/inventory/system/chassis/motherboard/enumerate",
    "dimm"      : "/inventory/system/chassis/motherboard/enumerate",
}

LEDS_URL = "/led/physical/enumerate"

LEDS_KEY_LIST = ("fan0", "fan1", "fan2", "fan3",
                 "front_id", "front_fault", "front_power",
                 "rear_id", "rear_fault", "rear_power")

SENSOR_URL = "/sensors/enumerate"

SENSOR_UNITS = {
    "Amperes"  : "Amps",
    "DegreesC" : "C",
    "Joules"   : "Joules",
    "Meters"   : "Meters",
    "RPMS"     : "RPMS",
    "Volts"    : "Volts",
    "Watts"    : "Watts",
}

RPOWER_STATES = {
    "on"        : "on",
    "off"       : "off",
    "Off"       : "off",
    "softoff"   : "softoff",
    "boot"      : "reset",
    "reset"     : "reset",
    "bmcreboot" : "BMC reboot",
    "Ready"     : "BMC Ready",
    "NotReady"  : "BMC NotReady",
    "chassison" : "on (Chassis)",
    "Running"   : "on",
    "Quiesced"  : "quiesced",
}

RPOWER_URLS = {
    "on"        : {
        "path"  : "/state/host0/attr/RequestedHostTransition",
        "field" : "State.Host.Transition.On",
    },
    "off"       : {
        "path"  : "/state/chassis0/attr/RequestedPowerTransition",
        "field" : "State.Chassis.Transition.Off",
    },
    "softoff"   : {
        "path"  : "/state/host0/attr/RequestedHostTransition",
        "field" : "State.Host.Transition.Off",
    },
    "state"     : {
        "path"  : "/state/enumerate",
    },
}

BMC_URLS = {
    "reboot" : {
        "path"  : "/state/bmc0/attr/RequestedBMCTransition",
        "field" : "State.BMC.Transition.Reboot",
    },
    "state"     : {
        "path"  : "/state/bmc0/attr/CurrentBMCState",
    },
}

BOOTSOURCE_URLS = {
    "enable"       : {
        "path"      : "/control/host0/boot/one_time/attr/Enabled",
    },
    "get"          : {
        "path"      : "/control/host0/enumerate",
    },
    "set_one_time" : {
        "path"      : "/control/host0/boot/one_time/attr/BootSource",
    },
    "set"          : {
        "path"      : "/control/host0/boot/attr/BootSource",
    },
    "field"        : "xyz.openbmc_project.Control.Boot.Source.Sources.",
}

BOOTSOURCE_GET_STATE = {
    "Default"       : "Default",
    "Disk"          : "Hard Drive",
    "ExternalMedia" : "CD/DVD",
    "Network"       : "Network",
}

BOOTSOURCE_SET_STATE = {
    "cd"      : "ExternalMedia",
    "def"     : "Default",
    "default" : "Default",
    "hd"      : "Disk",
    "net"     : "Network",
}

FIRM_URLS = {
    "activate"  : {
        "path"   : "/software/%s/attr/RequestedActivation",
        "field" : "xyz.openbmc_project.Software.Activation.RequestedActivations.Active",
    },
    "delete"    : {
        "path"   : "/software/%s/action/Delete",
        "field" : [],
    },
    "priority"  : {
        "path"   : "/software/%s/attr/Priority",
        "field" : False,
    },
    "list"      : {
        "path"   : "/software/enumerate",
    }
}

RSPCONFIG_NETINFO_URL = {
    'delete_ip_object': "/network/#NIC#/ipv4/#OBJ#",
    'disable_dhcp': "/network/#NIC#/attr/DHCPEnabled",
    'get_netinfo': "/network/enumerate",
    'get_nic_netinfo': "/network/#NIC#/ipv4/enumerate",
    'ipdhcp': "/network/action/Reset",
    'nic_ip': "/network/#NIC#/action/IP",
    'ntpservers': "/network/#NIC#/attr/NTPServers",
    'vlan': "/network/action/VLAN",
}

PASSWD_URL = '/user/root/action/SetPassword'

RSPCONFIG_APIS = {
    'hostname': {
        'baseurl': "/network/config/",
        'set_url': "attr/HostName",
        'display_name': "BMC Hostname",
    },
    'autoreboot' : {
        'baseurl': "/control/host0/auto_reboot",
        'set_url': "/attr/AutoReboot",
        'get_url': "",
        'display_name': "BMC AutoReboot",
        'attr_values': {
            '0': False,
            '1': True,
         },
    },
    'powersupplyredundancy':{
        'baseurl': "/sensors/chassis/PowerSupplyRedundancy/",
        'set_url': "action/setValue",
        'get_url': "action/getValue",
        'get_url_new': '/control/power_supply_redundancy',
        'get_method': 'POST',
        'get_method_new': 'GET',
        'get_data': [],
        'display_name': "BMC PowerSupplyRedundancy",
        'attr_values': {
            'disabled': ["Disabled"],
            'enabled': ["Enabled"],
            'False': ['Disabled'],
            'True':  ["Enabled"],
        },
    },
    'powerrestorepolicy': {
        'baseurl': "/control/host0/power_restore_policy",
        'set_url': "/attr/PowerRestorePolicy",
        'get_url': "",
        'display_name': "BMC PowerRestorePolicy",
         'attr_values': {
             'restore': "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.Restore",
             'always_on': "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.AlwaysOn",
             'always_off': "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.AlwaysOff",
         },
    },
    'bootmode': {
        'baseurl': "/control/host0/boot",
        'set_url': "/attr/BootMode",
        'get_url': "",
        'display_name':"BMC BootMode",
        'attr_values': {
            'regular': "xyz.openbmc_project.Control.Boot.Mode.Modes.Regular",
            'safe': "xyz.openbmc_project.Control.Boot.Mode.Modes.Safe",
            'setup': "xyz.openbmc_project.Control.Boot.Mode.Modes.Setup",
        },
    },
    'thermalmode': {
        'baseurl': "/control/thermal/0",
        'set_url': "/attr/Current",
        'get_url': "/attr/Current",
        'display_name':"BMC ThermalMode",
        'attr_values': {
            'default': "DEFAULT",
            'custom': "CUSTOM",
            'heavy_io': "HEAVY_IO",
            'max_base_fan_floor': "MAX_BASE_FAN_FLOOR",
        },
    },
    'timesyncmethod': {
        'baseurl': '/time/sync_method',
        'get_url': '',
        'set_url': '/attr/TimeSyncMethod',
        'display_name': 'BMC TimeSyncMethod',
        'attr_values': {
            'ntp': 'xyz.openbmc_project.Time.Synchronization.Method.NTP',
            'manual': 'xyz.openbmc_project.Time.Synchronization.Method.Manual',
        },
    },
}

EVENTLOG_URLS     = {
        "list":      "/logging/enumerate",
        "clear_all": "/logging/action/DeleteAll",
        "resolve":   "/logging/entry/{}/attr/Resolved",
}

RAS_POLICY_TABLE  = "/opt/ibm/ras/lib/policyTable.json"
RAS_POLICY_TABLE_RPM_LOC = "https://www.ibm.com/support/customercare/sas/f/lopdiags/scaleOutLCdebugtool.html#OpenBMC"
RAS_POLICY_MSG    = "Install the openbmctool rpm from " + RAS_POLICY_TABLE_RPM_LOC + " to obtain more detailed logging messages."
RAS_NOT_FOUND_MSG = " Not found in policy table: "

RESULT_OK = 'ok'
RESULT_FAIL = 'fail'

class OpenBMCRest(object):

    headers = {'Content-Type': 'application/json'}

    def __init__(self, name, **kwargs):

        #set default user/passwd
        self.name = name
        self.username, self.password = ('root', '0penBmc')

        if 'nodeinfo' in kwargs:
            for key, value in kwargs['nodeinfo'].items():
                setattr(self, key, value)
        if not hasattr(self, 'bmcip'):
            self.bmcip = self.name

        self.verbose = kwargs.get('debugmode')
        # print back to xcatd or just stdout
        self.messager = kwargs.get('messager')

        self.session = rest.RestSession((self.username,self.password))
        self.root_url = HTTP_PROTOCOL + self.bmcip + PROJECT_URL
        self.download_root_url = HTTP_PROTOCOL + self.bmcip + '/'

    def _print_record_log (self, msg, cmd, error_flag=False):

        if self.verbose or error_flag:
            localtime = time.asctime( time.localtime(time.time()) )
            log = self.name + ': [openbmc_debug] ' + cmd + ' ' + msg
            if self.verbose:
                self.messager.info(localtime + ' ' + log)
            logger.debug(log)

    def _print_error_log (self, msg, cmd):

        self._print_record_log(msg, cmd, True)

    def _log_request (self, method, url, headers, data=None, files=None, file_path=None, cmd=''):

        header_str = ' '.join([ "%s: %s" % (k, v) for k,v in headers.items() ])
        msg = 'curl -k -c cjar -b cjar -X %s -H \"%s\" ' % (method, header_str)

        if files:
            msg += '-T \'%s\' %s -s' % (files, url)
        elif file_path:
            msg = 'curl -J -k -c cjar -b cjar -X %s -H \"%s\" %s -o %s' % \
                  (method, header_str, url, file_path)
        elif data:
            if cmd == 'login':
                data = data.replace(self.password, "xxxxxx")
            msg += '%s -d \'%s\'' % (url, data)
        else:
            msg += url

        self._print_record_log(msg, cmd)
        return msg

    def handle_response (self, resp, cmd=''):

        code = resp.status_code
        if code == requests.codes.bad_gateway:
            error = "(Verify REST server is running on the BMC)"
            self._print_error_log(error, cmd)
            raise SelfServerException(code, error, host_and_port=self.bmcip)
        data = resp.json() # it will raise ValueError
        if code != requests.codes.ok:
            description = ''.join(data['data']['description'])
            error = '[%d] %s' % (code, description)
            self._print_error_log(error, cmd)
            raise SelfClientException(error, code)

        self._print_record_log(data['message'], cmd)
        return data['data']

    def request (self, method, resource, headers=None, payload=None, timeout=30, cmd=''):

        httpheaders = headers or OpenBMCRest.headers
        url = resource
        if not url.startswith(HTTP_PROTOCOL):
            url = self.root_url + resource

        data = None
        if payload:
            data=json.dumps(payload)

        self._log_request(method, url, httpheaders, data=data, cmd=cmd)
        try:
            response = self.session.request(method, url, httpheaders, data=data, timeout=timeout)
            return self.handle_response(response, cmd=cmd)
        except SelfServerException as e:
            if cmd == 'login':
                e.message = "Login to BMC failed: Can't connect to {0} {1}.".format(e.host_and_port, e.detail_msg)
            else:
                e.message = 'BMC did not respond. ' \
                            'Validate BMC configuration and retry the command. ' + e.detail_msg
            self._print_error_log(e.message, cmd)
            raise
        except ValueError:
            error = 'Received wrong format response: %s' % response
            self._print_error_log(error, cmd)
            raise SelfServerException(error)

    def download(self, method, resource, file_path, headers=None, cmd=''):

        httpheaders = headers or OpenBMCRest.headers
        url = resource
        if not url.startswith(HTTP_PROTOCOL):
            url = self.download_root_url + resource

        request_cmd = self._log_request(method, url, httpheaders, file_path=file_path, cmd=cmd)

        try:
            response = self.session.request_download(method, url, httpheaders, file_path)
        except SelfServerException as e:
            self._print_error_log(e.message, cmd=cmd)
            raise
        except SelfClientException as e:
            error = e.message
            self._print_error_log(error, cmd=cmd)
            raise

        if not response:
            self._print_error_log('No response received for command %s' % request_cmd, cmd)
            return True

        self._print_record_log(str(response.status_code), cmd=cmd)
        return True

    def upload (self, method, resource, files, headers=None, cmd=''):

        httpheaders = headers or OpenBMCRest.headers
        url = resource
        if not url.startswith(HTTP_PROTOCOL):
            url = self.root_url + resource

        request_cmd = self._log_request(method, url, httpheaders, files=files, cmd=cmd)

        try:
            response = self.session.request_upload(method, url, httpheaders, files)
        except SelfServerException as e:
            self._print_error_log(e.message, cmd=cmd)
            raise
        try:
            data = json.loads(response)
        except ValueError:
            error = 'Received wrong format response when running command \'%s\': %s' % \
                    (request_cmd, response)
            self._print_error_log(error, cmd=cmd)
            raise SelfServerException(error)

        if data['message'] != '200 OK':
            error = 'Failed to upload update file %s : %s-%s' % \
                    (files, data['message'], \
                    ''.join(data['data']['description']))
            self._print_error_log(error, cmd=cmd)
            raise SelfClientException(error, code)

        self._print_record_log(data['message'], cmd=cmd)

        return True

    def login(self):

        payload = { "data": [ self.username, self.password ] }

        url = HTTP_PROTOCOL + self.bmcip + '/login'
        self.request('POST', url, payload=payload, timeout=20, cmd='login')

    def list_power_states(self):

        states = self.request('GET', RPOWER_URLS['state']['path'], cmd='list_power_states')
        #filter non used states
        try:
            host_stat = states[PROJECT_URL + '/state/host0']['CurrentHostState']
            chassis_stat = states[PROJECT_URL + '/state/chassis0']['CurrentPowerState']
            return {'host': host_stat.split('.')[-1], 'chassis': chassis_stat.split('.')[-1]}
        except KeyError:
            error = 'Received wrong format response: %s' % states
            raise SelfServerException(error)

    def set_power_state(self, state):

        payload = { "data": PROJECT_PAYLOAD + RPOWER_URLS[state]['field'] }
        return self.request('PUT', RPOWER_URLS[state]['path'], payload=payload, cmd='set_power_state')

    def get_bmc_state(self):

        try:
            state = self.request('GET', BMC_URLS['state']['path'], cmd='get_bmc_state')
            return {'bmc': state.split('.')[-1]}
        except KeyError:
            error = 'Received wrong format response: %s' % state
            raise SelfServerException(error)

    def reboot_bmc(self, optype='warm'):

        payload = { "data": PROJECT_PAYLOAD + BMC_URLS['reboot']['field'] }
        try:
            self.request('PUT', BMC_URLS['reboot']['path'], payload=payload, cmd='bmc_reset')
        except (SelfServerException,SelfClientException) as e:
            # TODO: Need special handling for bmc reset, as it is normal bmc may return error
            pass

    def get_host_state(self, states):

        chassis_state = states.get('chassis')
        host_state = states.get('host')
        state = 'Unknown'
        if chassis_state == 'Off':
            state = chassis_state

        elif chassis_state == 'On':
            if host_state == 'Off':
                state = 'chassison'
            elif host_state in ['Quiesced', 'Running']:
                state = host_state
            else:
                state = 'Unexpected host state=%s' % host_state
        else:
            state = 'Unexpected chassis state=%s' % chassis_state
        return state

    def set_one_time_boot_enable(self, enabled):

        payload = { "data": enabled }
        self.request('PUT', BOOTSOURCE_URLS['enable']['path'], payload=payload, cmd='set_one_time_boot_enable')

    def set_boot_state(self, state):

        payload = { "data": BOOTSOURCE_URLS['field'] + BOOTSOURCE_SET_STATE[state] }
        self.request('PUT', BOOTSOURCE_URLS['set']['path'], payload=payload, cmd='set_boot_state')

    def set_one_time_boot_state(self, state):

        payload = { "data": BOOTSOURCE_URLS['field'] + BOOTSOURCE_SET_STATE[state] }
        self.request('PUT', BOOTSOURCE_URLS['set_one_time']['path'], payload=payload, cmd='set_one_time_boot_state')

    def get_boot_state(self):

        state = self.request('GET', BOOTSOURCE_URLS['get']['path'], cmd='get_boot_state')
        try:
            one_time_path = PROJECT_URL + '/control/host0/boot/one_time'
            one_time_enabled =  state[one_time_path]['Enabled']
            if one_time_enabled:
                boot_source = state[one_time_path]['BootSource'].split('.')[-1]
            else:
                boot_source = state[PROJECT_URL + '/control/host0/boot']['BootSource'].split('.')[-1]

            error = 'Can not get valid rsetboot status, the data is %s' % boot_source
            boot_state = BOOTSOURCE_GET_STATE.get(boot_source.split('.')[-1], error)
            return boot_state
        except KeyError:
            error = 'Received wrong format response: %s' % states
            raise SelfServerException(error)

    def get_beacon_info(self):

        beacon_data = self.request('GET', LEDS_URL, cmd='get_beacon_info')
        try:
            beacon_dict = {}
            for key, value in beacon_data.items():
                key_id = key.split('/')[-1]
                if key_id in LEDS_KEY_LIST:
                    beacon_dict[key_id] = value['State'].split('.')[-1]
            return beacon_dict
        except KeyError:
            error = 'Received wrong format response: %s' % beacon_data
            raise SelfServerException(error)

    def set_beacon_state(self, state):

        payload = { "data": RBEACON_URLS[state]['field'] }
        self.request('PUT', RBEACON_URLS['path'], payload=payload, cmd='set_beacon_state')

    def get_sensor_info(self):

        sensor_data = self.request('GET', SENSOR_URL, cmd='get_sensor_info')
        try:
            sensor_dict = {}
            for k, v in sensor_data.items():
                if 'Unit' in v:
                    unit = v['Unit'].split('.')[-1]
                    if unit in SENSOR_UNITS:
                        label = k.split('/')[-1].replace('_', ' ').title()
                        value = v['Value']
                        scale = v['Scale']
                        value = value * pow(10, scale)
                        value = '{:g}'.format(value)
                        if unit not in sensor_dict:
                            sensor_dict[unit] = []
                        sensor_dict[unit].append('%s: %s %s' % (label, value, SENSOR_UNITS[unit]))
                elif 'units' in v and 'value' in v:
                    label = k.split('/')[-1]
                    value = v['value']
                    sensor_dict[label] = ['%s: %s' % (label, value)]

            return sensor_dict
        except KeyError:
            error = 'Received wrong format response: %s' % sensor_data
            raise SelfServerException(error)

    def get_inventory_info(self, inventory_type):

        inventory_data = self.request('GET', INVENTORY_URLS[inventory_type], cmd='get_inventory_info')
        try:
            inventory_dict = {}
            if inventory_type == 'model' or inventory_type == 'serial':
                # The format of returned data for model and serial a different from other inventory types
                inventory_dict['SYSTEM'] = []
                for key, value in inventory_data.items():
                    inventory_dict['SYSTEM'].append('%s %s : %s' % ("SYSTEM", key, value))

                return inventory_dict

            for key, value in inventory_data.items():
                if 'Present' not in value:
                    logger.debug('Not "Present" for %s' % key)
                    continue

                key_list = key.split('/')
                try:
                    key_id = key_list[-1]
                    key_tmp = key_list[-2]
                except IndexError:
                    logger.debug('IndexError (-2) for %s' % key)
                    continue

                key_type_list = [x for x in key_id if x not in '0123456789']
                key_type = ''.join(key_type_list).upper()

                if key_type == 'CORE':
                    key_type = 'CPU'
                    source = '%s %s' % (key_tmp, key_id)
                else:
                    source = key_id

                if key_type not in inventory_dict:
                    inventory_dict[key_type] = []

                for (sub_key, v) in value.items():
                    inventory_dict[key_type].append('%s %s : %s' % (source.upper(), sub_key, v))

            return inventory_dict
        except KeyError:
            error = 'Received wrong format response: %s' % inventory_data
            raise SelfServerException(error)

    def activate_firmware(self, activate_id):

        payload = { "data": FIRM_URLS['activate']['field'] }
        url = FIRM_URLS['activate']['path'] % activate_id
        return self.request('PUT', url, payload=payload, cmd='activate_firmware')

    def delete_firmware(self, delete_id):

        payload = { "data": FIRM_URLS['delete']['field'] }
        url = FIRM_URLS['delete']['path'] % delete_id
        return self.request('POST', url, payload=payload, cmd='delete_firmware')

    def list_firmware(self):

        data = self.request('GET', FIRM_URLS['list']['path'], cmd='list_firmware')
        try:
            func_list = data.pop('/xyz/openbmc_project/software/functional')['endpoints']
        except:
            logger.debug('Not found functional firmwares')
            func_list = []

        fw_dict={}
        for key, swinfo in data.items():
            if 'Version' not in swinfo:
                logger.debug('Not found version information for %s' % key)
                continue
            fw = OpenBMCImage(key, swinfo)
            if func_list:
                fw.functional = key in func_list

            fw_dict[str(fw)]=fw

        return bool(func_list), fw_dict

    def upload_firmware(self, upload_file):

        headers = {'Content-Type': 'application/octet-stream'}
        path = HTTP_PROTOCOL + self.bmcip + '/upload/image/'
        self.upload('PUT', path, upload_file, headers=headers, cmd='upload_firmware')

    def set_priority(self, firm_id):

        payload = { "data": FIRM_URLS['priority']['field'] }
        url = FIRM_URLS['priority']['path'] % firm_id
        return self.request('PUT', url, payload=payload, cmd='set_priority')

    # Extract all eventlog info and parse it
    def get_eventlog_info(self):

        eventlog_data = self.request('GET', EVENTLOG_URLS['list'], cmd='get_eventlog_info')

        return self.parse_eventlog_data(eventlog_data)

    # Parse eventlog data and build a dictionary with eventid as a key
    def parse_eventlog_data(self, eventlog_data):

        # Check if policy table file is there
        ras_event_mapping = {}
        if os.path.isfile(RAS_POLICY_TABLE):
            with open(RAS_POLICY_TABLE) as data_file:
                policy_hash = json.load(data_file)
                if policy_hash:
                    ras_event_mapping = policy_hash['events']
                else:
                    self.messager.info(RAS_POLICY_MSG)
                data_file.close()
        else:
            self.messager.info(RAS_POLICY_MSG)
        try:
            eventlog_dict = {}
            for key, value in sorted(eventlog_data.items()):
                id, event_log_line = self.parse_eventlog_data_record(value, ras_event_mapping)
                if int(id) != 0:
                    eventlog_dict[str(id)] = event_log_line

            if not eventlog_dict:
                # Nothing was returned from BMC
                eventlog_dict['0'] ='No attributes returned from the BMC.'

            return eventlog_dict
        except KeyError:
            error = 'Received wrong format response: %s' % eventlog_data
            raise SelfServerException(error)

    # Parse a single eventlog entry and return data in formatted string
    def parse_eventlog_data_record(self, event_log_entry, ras_event_mapping):
        formatted_line = ""
        callout_data = ""
        LED_tag = " [LED]"
        timestamp_str = ""
        message_str = ""
        pid_str = ""
        resolved_str = ""
        id_str = "0"
        callout = False
        for (sub_key, v) in event_log_entry.items():
            if sub_key == 'AdditionalData':
                for (data_key) in v:
                    additional_data = data_key.split("=");
                    if additional_data[0] == 'ESEL':
                        esel = additional_data[1]
                        # Placeholder, not currently used
                    elif additional_data[0] == '_PID':
                        pid_str = "PID: " + str(additional_data[1]) + "),"
                    elif 'CALLOUT_DEVICE_PATH' in additional_data[0]:
                        callout = True
                        callout_data = "I2C"
                    elif 'CALLOUT_INVENTORY_PATH' in additional_data[0]:
                        callout = True
                        callout_data = additional_data[1]
                    elif 'CALLOUT' in additional_data[0]:
                        callout = True
                    elif 'GPU' in additional_data[0]:
                        callout_data="/xyz/openbmc_project/inventory/system/chassis/motherboard/gpu"
                    elif 'PROCEDURE' in additional_data[0]:
                        callout_data = '{:x}'.format(int(additional_data[1])) #Convert to hext
            elif sub_key == 'Timestamp':
                timestamp = time.localtime(v / 1000)
                timestamp_str = time.strftime("%m/%d/%Y %T", timestamp)
            elif sub_key == 'Id':
                id_str = str(v)
            elif sub_key == 'Resolved':
                resolved_str = " Resolved: " + str(v)
            elif sub_key == 'Message':
                message_str = v
        if callout_data:
            message_str += "||" + callout_data

        # If event data mapping was read in from RAS policy table, display a more detailed message
        if ras_event_mapping:
            if message_str in ras_event_mapping:
                event_type = ras_event_mapping[message_str]['EventType']
                event_message = ras_event_mapping[message_str]['Message']
                severity = ras_event_mapping[message_str]['Severity']
                affect = ras_event_mapping[message_str]['AffectedSubsystem']
                formatted_line = timestamp_str + " [" + id_str +"]" + ": " + event_type + ", " + "(" + severity + ") " + event_message + " (AffectedSubsystem: " + affect + ", " + pid_str + resolved_str
            else:
                formatted_line = timestamp_str + " [" + id_str +"]" + ":" + RAS_NOT_FOUND_MSG + message_str + " (" + pid_str + resolved_str
        else:
            formatted_line = timestamp_str + " [" + id_str +"]" + ": " + message_str + " (" + pid_str + resolved_str
        if callout:
            formatted_line += LED_tag
        return id_str, formatted_line

    # Clear all eventlog records
    def clear_all_eventlog_records(self):

        payload = { "data": [] }
        return self.request('POST', EVENTLOG_URLS['clear_all'], payload=payload, cmd='clear_all_eventlog_records')

    # Resolve eventlog records
    def resolve_event_log_entries(self, eventlog_ids_to_resolve):

        payload = { "data": "1" }
        for event_id in eventlog_ids_to_resolve:
            self.request('PUT', EVENTLOG_URLS['resolve'].format(event_id), payload=payload, cmd='resolve_event_log_entries')

        return

    def set_apis_values(self, key, value):
        attr_info = RSPCONFIG_APIS[key]
        if 'set_url' not in attr_info:
            raise SelfServerException("config %s failed, not url available" % key)
        set_url = attr_info['baseurl']+attr_info['set_url']
        if 'attr_values' in attr_info and value in attr_info['attr_values']:
            data = attr_info['attr_values'][value]
        else:
            data = value

        method = 'PUT'
        if key == 'powersupplyredundancy':
            method = 'POST'
        self.request(method, set_url, payload={"data": data}, cmd="set_%s" % key)

    def get_apis_values(self, key):
        attr_info = RSPCONFIG_APIS[key]
        if 'get_url' not in attr_info:
            raise SelfServerException("Reading %s failed, not url available" % key)
        get_url = attr_info['baseurl']+attr_info['get_url']

        method = 'GET'
        if 'get_method' in attr_info:
            method = attr_info['get_method']
        data = None
        if 'get_data' in attr_info:
            data={"data": attr_info['get_data']}
        return self.request(method, get_url, payload=data, cmd="get_%s" % key)

    def get_powersupplyredundancy(self):
        attr_info = RSPCONFIG_APIS['powersupplyredundancy']
        return self.request(attr_info['get_method_new'], attr_info['get_url_new'], cmd='get_powersupplyredundancy')

    def set_admin_passwd(self, passwd):

        payload = { "data": [passwd] }
        self.request('POST', PASSWD_URL, payload=payload, cmd='set_admin_password')

    def set_ntp_servers(self, nic, servers):

        payload = { "data": servers.split(',') }
        url = RSPCONFIG_NETINFO_URL['ntpservers'].replace('#NIC#', nic)
        self.request('PUT', url, payload=payload, cmd='set_ntp_servers')

    def clear_dump(self, clear_arg):

        if clear_arg == 'all':
            payload = { "data": DUMP_URLS['clear_all']['field'] }
            self.request('POST', DUMP_URLS['clear_all']['path'], payload=payload, cmd='clear_dump_all')
        else:
            path = DUMP_URLS['clear']['path'].replace('#ID#', clear_arg)
            payload = { "data": DUMP_URLS['clear']['field'] }
            self.request('POST', path, payload=payload, cmd='clear_dump')

    def create_dump(self):

        payload = { "data": DUMP_URLS['create']['field'] }
        return self.request('POST', DUMP_URLS['create']['path'], payload=payload, cmd='create_dump')

    def list_dump_info(self):

        dump_data = self.request('GET', DUMP_URLS['list'], cmd='list_dump_info')

        try:
            dump_dict = {}
            for key, value in dump_data.items():
                if 'Size' not in value or 'Elapsed' not in value:
                    continue

                key_id = int(key.split('/')[-1])
                timestamp = value['Elapsed']
                gen_time = time.strftime("%m/%d/%Y %H:%M:%S", time.localtime(timestamp))
                dump_dict.update({key_id: {'Size': value['Size'], 'Generated': gen_time}})

            return dump_dict
        except KeyError:
            error = 'Received wrong format response: %s' % dump_data
            raise SelfServerException(error)

    def download_dump(self, download_id, file_path):

        headers = {'Content-Type': 'application/octet-stream'}
        path = DUMP_URLS['download'].replace('#ID#', download_id)
        self.download('GET', path, file_path, headers=headers, cmd='download_dump')

    def clear_gard(self):

        payload = { "data": [] }
        url = HTTP_PROTOCOL + self.bmcip + GARD_CLEAR_URL
        return self.request('POST', url, payload=payload, cmd='clear_gard')

    def set_vlan(self, nic, vlan_id):

        payload = { "data": [nic, vlan_id] }
        return self.request('POST', RSPCONFIG_NETINFO_URL['vlan'], payload=payload, cmd='set_vlan')

    def set_netinfo(self, nic, ip, netmask, gateway):

        payload = { "data": ["xyz.openbmc_project.Network.IP.Protocol.IPv4", ip, netmask, gateway] }
        path = RSPCONFIG_NETINFO_URL['nic_ip'].replace('#NIC#', nic)
        return self.request('POST', path, payload=payload, cmd='set_netinfo')

    def disable_dhcp(self, nic):

        payload = { "data": 0 }
        path = RSPCONFIG_NETINFO_URL['disable_dhcp'].replace('#NIC#', nic)
        return self.request('PUT', path, payload=payload, cmd='disable_dhcp')

    def delete_ip_object(self, nic, ip_object):

        path = RSPCONFIG_NETINFO_URL['delete_ip_object'].replace('#OBJ#', ip_object).replace('#NIC#', nic)
        return self.request('DELETE', path, cmd='delete_ip_object')

    def get_nic_netinfo(self, nic):

        path = RSPCONFIG_NETINFO_URL['get_nic_netinfo'].replace('#NIC#', nic)
        data = self.request('GET', path, cmd='get_nic_netinfo')

        try:
            netinfo = {}
            for k, v in data.items():
                dev,match,netid = k.partition("/ipv4/")
                if 'LinkLocal' in v["Origin"] or v["Address"].startswith("169.254"):
                    msg = "Found LinkLocal address %s for interface %s, Ignoring..." % (v["Address"], dev)
                    self._print_record_log(msg, 'get_netinfo')
                    continue
                utils.update2Ddict(netinfo, netid, 'ip', v['Address'])
                utils.update2Ddict(netinfo, netid, 'ipsrc', v['Origin'].split('.')[-1])
                utils.update2Ddict(netinfo, netid, 'netmask', v['PrefixLength'])
                utils.update2Ddict(netinfo, netid, 'gateway', v['Gateway'])
            return netinfo
        except KeyError:
            error = 'Received wrong format response: %s' % data
            raise SelfServerException(error)

    def get_netinfo(self):
        data = self.request('GET', RSPCONFIG_NETINFO_URL['get_netinfo'], cmd="get_netinfo")
        try:
            netinfo = {}
            for k, v in data.items():
                if 'network/config' in k:
                    if 'HostName' in v:
                        netinfo["hostname"] = v["HostName"]
                    if 'DefaultGateway' in v:
                        netinfo["defaultgateway"] = v["DefaultGateway"]
                    continue
                dev,match,netid = k.partition("/ipv4/")
                if netid:
                    nicid = dev.split('/')[-1]
                    if nicid not in netinfo:
                        netinfo[nicid] = {}
                    if 'LinkLocal' in v["Origin"] or v["Address"].startswith("169.254"):
                        msg = "Found LinkLocal address %s for interface %s, Ignoring..." % (v["Address"], dev)
                        self._print_record_log(msg, 'get_netinfo')
                        # Save Zero Conf information
                        netinfo[nicid]["zeroconf"] = v["Address"]
                        continue
                    if 'ip' in netinfo[nicid]:
                        msg = "Another valid ip %s found." % (v["Address"])
                        self._print_record_log(msg, 'get_netinfo')
                        del netinfo[nicid]
                        netinfo['error'] = 'Interfaces with multiple IP addresses are not supported'
                        break
                    utils.update2Ddict(netinfo, nicid, "ipsrc", v["Origin"].split('.')[-1])
                    utils.update2Ddict(netinfo, nicid, "netmask", v["PrefixLength"])
                    utils.update2Ddict(netinfo, nicid, "gateway", v["Gateway"])
                    utils.update2Ddict(netinfo, nicid, "ip", v["Address"])
                    utils.update2Ddict(netinfo, nicid, "ipobj", netid)
                    if dev in data:
                        info = data[dev]
                        utils.update2Ddict(netinfo, nicid, "vlanid", info.get("Id", "Disable"))
                        utils.update2Ddict(netinfo, nicid, "mac", info["MACAddress"])
                        ntpservers = None
                        tmp_ntpservers = ','.join(info["NTPServers"])
                        if tmp_ntpservers:
                            ntpservers = tmp_ntpservers
                        utils.update2Ddict(netinfo, nicid, "ntpservers", ntpservers)
            return netinfo
        except KeyError:
            error = 'Received wrong format response: %s' % data
            raise SelfServerException(error)


    def set_ipdhcp(self):
        payload = { "data": [] }
        return self.request('POST', RSPCONFIG_NETINFO_URL['ipdhcp'], payload=payload, cmd="set_bmcip_dhcp")


class OpenBMCImage(object):
    def __init__(self, rawid, data=None):
        self.id = rawid.split('/')[-1]
        self.extver = None
        self.functional = False
        self.priority = None
        self.progress = None
        self.purpose = 'Unknown'

        if data:
            self.version = data.get('Version')
            self.purpose = data.get('Purpose', self.purpose).split('.')[-1]
            self.priority = data.get('Priority')
            self.extver   = data.get('ExtendedVersion')
            self.progress   = data.get('Progress')
            self.active = data.get('Activation')
            if self.active:
                self.active = self.active.split('.')[-1]

    def __str__(self):
        return '%s-%s' % (self.purpose, self.id)

