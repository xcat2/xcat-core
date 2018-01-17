from xcatagent import base
import time
import sys
import gevent

import xcat_exception
import rest

HTTP_PROTOCOL = "https://"
PROJECT_URL = "/xyz/openbmc_project"

RESULT_OK = 'ok'

DEBUGMODE = False

POWER_SET_OPTIONS = ('on', 'off', 'bmcreboot', 'softoff')
POWER_GET_OPTIONS = ('bmcstate', 'state', 'stat', 'status')

RPOWER_URLS = {
    "on"        : {
        "url"   : PROJECT_URL + "/state/host0/attr/RequestedHostTransition",
        "field" : "xyz.openbmc_project.State.Host.Transition.On",
    },
    "off"       : {
        "url"   : PROJECT_URL + "/state/chassis0/attr/RequestedPowerTransition",
        "field" : "xyz.openbmc_project.State.Chassis.Transition.Off",
    },
    "softoff"   : {
        "url"   : PROJECT_URL + "/state/host0/attr/RequestedHostTransition",
        "field" : "xyz.openbmc_project.State.Host.Transition.Off",
    },
    "bmcreboot" : {
        "url"   : PROJECT_URL + "/state/bmc0/attr/RequestedBMCTransition",
        "field" : "xyz.openbmc_project.State.BMC.Transition.Reboot",
    },
    "state"     : {
        "url"   : PROJECT_URL + "/state/enumerate",
    },
}

RPOWER_STATE = {
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

POWER_STATE_DB = {
    "on"      : "powering-on",
    "off"     : "powering-off",
    "softoff" : "powering-off",
    "boot"    : "powering-on",
    "reset"   : "powering-on",
}

class OpenBMC(base.BaseDriver):

    headers = {'Content-Type': 'application/json'}

    def __init__(self, messager, name, node_info):
        super(OpenBMC, self).__init__(messager)        
        self.node = name
        for key, value in node_info.items() :
            setattr(self, key, value)
        global DEBUGMODE
        self.client = rest.RestSession(messager, DEBUGMODE)

    def _login(self) :
        """ Login
        :raise: error message if failed
        """
        url = HTTP_PROTOCOL + self.bmcip + '/login'
        data = { "data": [ self.username, self.password ] }
        self.client.request('POST', url, OpenBMC.headers, data, self.node, 'login')
        return RESULT_OK

    def _set_power_onoff(self, subcommand) :
        """ Set power on/off/softoff/bmcreboot
        :param subcommand: subcommand for rpower
        :returns: ok if success
        :raise: error message if failed
        """
        url = HTTP_PROTOCOL + self.bmcip + RPOWER_URLS[subcommand]['url']
        data = { "data": RPOWER_URLS[subcommand]['field'] }
        try :
            response = self.client.request('PUT', url, OpenBMC.headers, data, self.node, 'rpower_' + subcommand)
        except (xcat_exception.SelfServerException,
                xcat_exception.SelfClientException) as e :
            if subcommand != 'bmcreboot':
                result = e.message
            return result

        return RESULT_OK

    def _get_power_state(self, subcommand) :
        """ Get power current state
        :param subcommand: state/stat/status/bmcstate
        :returns: current state if success
        :raise: error message if failed
        """
        result = ''
        bmc_not_ready = 'NotReady'
        url = HTTP_PROTOCOL + self.bmcip + RPOWER_URLS['state']['url']
        try :
            response = self.client.request('GET', url, OpenBMC.headers, '', self.node, 'rpower_' + subcommand)
        except xcat_exception.SelfServerException, e :
            if subcommand == 'bmcstate':
                result = bmc_not_ready
            else :
                result = e.message
        except xcat_exception.SelfClientException, e :
            result = e.message

        if result : 
            return result

        for key in response['data'] :
            key_type = key.split('/')[-1]
            if key_type == 'bmc0' :
                bmc_current_state = response['data'][key]['CurrentBMCState'].split('.')[-1]
            if key_type == 'chassis0' :
                chassis_current_state = response['data'][key]['CurrentPowerState'].split('.')[-1]
            if key_type == 'host0' :
                host_current_state = response['data'][key]['CurrentHostState'].split('.')[-1]

        if subcommand == 'bmcstate' :
            if bmc_current_state == 'Ready' :
                return bmc_current_state 
            else :
                return bmc_not_ready

        if chassis_current_state == 'Off' :
            return chassis_current_state
        elif chassis_current_state == 'On' :
            if host_current_state == 'Off' :
                return 'chassison'
            elif host_current_state == 'Quiesced' :
                return host_current_state
            elif host_current_state == 'Running' :
                return host_current_state
            else :
                return 'Unexpected chassis state=' + host_current_state
        else :
            return 'Unexpected chassis state=' + chassis_current_state


    def _rpower_boot(self) :
        """Power boot
        :returns: 'reset' if success
        :raise: error message if failed
        """
        result = self._set_power_onoff('off')
        if result != RESULT_OK :
            return result
        self.messager.update_node_attributes('status', self.node, POWER_STATE_DB['off'])

        start_timeStamp = int(time.time())
        for i in range (0,30) :
            status = self._get_power_state('state')
            if status in RPOWER_STATE and RPOWER_STATE[status] == 'off':
                break
            gevent.sleep( 2 )

        end_timeStamp = int(time.time())

        if status not in RPOWER_STATE or RPOWER_STATE[status] != 'off':
            wait_time = str(end_timeStamp - start_timeStamp)
            result = 'Error: Sent power-off command but state did not change to off after waiting ' + wait_time + ' seconds. (State=' + status + ').'
            return result

        result = self._set_power_onoff('on')
        return result


    def rpower(self, args) :
        """handle rpower command
        :param args: subcommands for rpower
        """
        subcommand = args[0]
        try :
            result = self._login()
        except xcat_exception.SelfServerException as e :
            if subcommand == 'bmcstate' :
                result = '%s: %s' % (self.node, RPOWER_STATE['NotReady'])
            else :
                result = '%s: %s'  % (self.node, e.message)
        except xcat_exception.SelfClientException as e :
            result = '%s: %s'  % (self.node, e.message)

        if result != RESULT_OK :
            self.messager.info(result)
            self._update2Ddict(node_rst, self.node, 'rst', result)
            return
        new_status = ''
        if subcommand in POWER_SET_OPTIONS :
            result = self._set_power_onoff(subcommand)
            if result == RESULT_OK :
                result = RPOWER_STATE[subcommand]
                new_status = POWER_STATE_DB.get(subcommand, '')

        if subcommand in POWER_GET_OPTIONS :
            tmp_result = self._get_power_state(subcommand)
            result = RPOWER_STATE.get(tmp_result, tmp_result)

        if subcommand == 'boot' :
            result = self._rpower_boot()
            if result == RESULT_OK :
                result = RPOWER_STATE[subcommand]
                new_status = POWER_STATE_DB.get(subcommand, '')

        if subcommand == 'reset' :
            status = self._get_power_state('state')
            if status == 'Off' or status == 'chassison':
                result = RPOWER_STATE['Off']
            else :
                result = self._rpower_boot()
                if result == RESULT_OK :
                    result = RPOWER_STATE[subcommand]
                    new_status = POWER_STATE_DB.get(subcommand, '')

        message = '%s: %s' % (self.node, result)
        self.messager.info(message)
        if new_status :
            self.messager.update_node_attributes('status', self.node, new_status)

class OpenBMCManager(base.BaseManager):
    def __init__(self, messager, cwd, nodes, envs):
        super(OpenBMCManager, self).__init__(messager, cwd)
        self.nodes = nodes
        global DEBUGMODE
        DEBUGMODE = envs['debugmode']

    def rpower(self, nodeinfo, args):
        super(OpenBMCManager, self).process_nodes_worker('openbmc', 'OpenBMC', self.nodes, nodeinfo, 'rpower', args)
