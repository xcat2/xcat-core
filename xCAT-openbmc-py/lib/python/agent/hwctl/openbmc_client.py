#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

import requests
import json
import time

from common import rest
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

        self.session = rest.RestSession()
        self.root_url = HTTP_PROTOCOL + self.bmcip + PROJECT_URL

    def _print_record_log (self, msg, cmd):

        if self.verbose :
            localtime = time.asctime( time.localtime(time.time()) )
            log = self.name + ': [openbmc_debug] ' + cmd + ' ' + msg
            self.messager.info(localtime + ' ' + log)
            logger.debug(log)

    def _log_request (self, method, url, headers, data=None, files=None, cmd=''):

        header_str = ' '.join([ "%s: %s" % (k, v) for k,v in headers.items() ])
        msg = 'curl -k -c cjar -b cjar -X %s -H \"%s\" ' % (method, header_str)

        if files:
            msg += '-T \'%s\' %s -s' % (files, url)
        elif data:
            if cmd == 'login':
                data = data.replace(self.password, "xxxxxx")
            msg += '%s -d \'%s\'' % (url, data)
        else:
            msg += url

        self._print_record_log(msg, cmd)
        return msg

    def handle_response (self, resp, cmd=''):

        data = resp.json() # it will raise ValueError
        code = resp.status_code
        if code != requests.codes.ok:
            description = ''.join(data['data']['description'])
            error = 'Error: [%d] %s' % (code, description)
            self._print_record_log(error, cmd)
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
            response = self.session.request(method, url, httpheaders, data=data)
            return self.handle_response(response, cmd=cmd)
        except SelfServerException as e:
            e.message = 'Error: BMC did not respond. ' \
                        'Validate BMC configuration and retry the command.'
            self._print_record_log(e.message, cmd)
            raise
        except ValueError:
            error = 'Error: Received wrong format response: %s' % response
            self._print_record_log(error, cmd)
            raise SelfServerException(error)

    def upload (self, method, resource, files, headers=None, cmd=''):

        httpheaders = headers or OpenBMCRest.headers
        url = resource
        if not url.startswith(HTTP_PROTOCOL):
            url = self.root_url + resource

        request_cmd = self._log_request(method, url, httpheaders, files=files, cmd=cmd)

        try:
            response = self.session.request_upload(method, url, httpheaders, files)
        except SelfServerException:
            self._print_record_log(error, cmd=cmd)
            raise
        try:
            data = json.loads(response)
        except ValueError:
            error = 'Error: Received wrong format response when running command \'%s\': %s' % \
                    (request_cmd, response)
            self._print_record_log(error, cmd=cmd)
            raise SelfServerException(error)

        if data['message'] != '200 OK':
            error = 'Error: Failed to upload update file %s : %s-%s' % \
                    (files, data['message'], \
                    ''.join(data['data']['description']))
            self._print_record_log(error, cmd=cmd)
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
            error = 'Error: Received wrong format response: %s' % states
            raise SelfServerException(error)

    def set_power_state(self, state):

        payload = { "data": PROJECT_PAYLOAD + RPOWER_URLS[state]['field'] }
        return self.request('PUT', RPOWER_URLS[state]['path'], payload=payload, cmd='set_power_state')

    def get_bmc_state(self):

        state = self.request('GET', BMC_URLS['state']['path'], cmd='get_bmc_state')
        try:
            return {'bmc': state.split('.')[-1]}
        except KeyError:
            error = 'Error: Received wrong format response: %s' % state
            raise SelfServerException(error)

    def reboot_bmc(self, optype='warm'):

        payload = { "data": PROJECT_PAYLOAD + BMC_URLS['reboot']['field'] }
        try:
            self.request('PUT', BMC_URLS['reboot']['path'], payload=payload, cmd='bmc_reset')
        except SelfServerException,SelfClientException:
            # TODO: Need special handling for bmc reset, as it is normal bmc may return error
            pass

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
            error = 'Error: Received wrong format response: %s' % states
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
            error = 'Error: Received wrong format response: %s' % beacon_data
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
            error = 'Error: Received wrong format response: %s' % sensor_data
            raise SelfServerException(error)
