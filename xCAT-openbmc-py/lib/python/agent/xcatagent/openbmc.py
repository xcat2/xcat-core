from xcatagent import base
import os
import time
import sys
import gevent

import utils
import xcat_exception
import rest

HTTP_PROTOCOL = "https://"
PROJECT_URL = "/xyz/openbmc_project"

RESULT_OK = 'ok'
RESULT_FAIL = 'fail'

DEBUGMODE = False
VERBOSE = False

ALL_NODES_RESULT = {}

# global variables of rflash
RFLASH_OPTIONS = {
    "-a"         : "activate",
    "--activate" : "activate",
    "-c"         : "check",
    "--check"    : "check",
    "-d"         : "direcory",
    "--delete"   : "delete",
    "-l"         : "list",
    "--list"     : "list",
    "-u"         : "upload",
    "--upload"   : "upload",
}

RFLASH_URLS = {
    "activate"  : {
        "url"   : PROJECT_URL + "/software/#ACTIVATE_ID#/attr/RequestedActivation",
        "field" : "xyz.openbmc_project.Software.Activation.RequestedActivations.Active",
    },
    "delete"    : {
        "url"   : PROJECT_URL + "/software/#DELETE_ID#/action/Delete",
        "field" : [],
    },
    "upload"    : {
        "url"   : "/upload/image/",
    },
    "priority"  : {
        "url"   : PROJECT_URL + "/software/#PRIORITY_ID#/attr/Priority",
        "field" : "false",
    }
}

XCAT_LOG_DIR = "/var/log/xcat"
XCAT_LOG_RFLASH_DIR = XCAT_LOG_DIR + "/rflash/"

# global variable of firmware information
FIRM_URL = PROJECT_URL + "/software/enumerate"

# global variables of rpower
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
        for key, value in node_info.items():
            setattr(self, key, value)
        global DEBUGMODE
        self.client = rest.RestSession(messager, DEBUGMODE)
        self.rflash_log_file = XCAT_LOG_RFLASH_DIR + '/' + self.node + '.log'

    def _login(self):
        """ Login
        :raise: error message if failed
        """
        url = HTTP_PROTOCOL + self.bmcip + '/login'
        data = { "data": [ self.username, self.password ] }
        self.client.request('POST', url, OpenBMC.headers, data, self.node, 'login')
        return RESULT_OK

    def _msg_process_rflash (self, msg, update_dict, checkv):
        """deal with msg during rflash
        :param msg: the msg want to process
        """
        if not checkv:
            self.messager.info('%s: %s' % (self.node, msg))
        elif VERBOSE:
            self.messager.info('%s: %s' % (self.node, msg))
        self.rflash_log_handle.writelines(msg + '\n')
        self.rflash_log_handle.flush()
        if update_dict:
            utils.update2Ddict(update_dict, self.node, 'rst', [msg]) 

    def _firm_info(self, status):
        """List firmware information including additional
        called by rflash check and rinv firm
        :returns: firmware information
        """
        firm_output = []
        try:
            (has_functional, firm_info) = self._get_firm_info(status)
        except (xcat_exception.SelfServerException,
                xcat_exception.SelfClientException) as e:
            firm_output.append(e.message)
            return firm_output

        keys = firm_info.keys()
        keys.sort()
        for key in keys:
            flag = ''
            if 'is_functional' in firm_info[key]: 
                flag = '*'
            elif 'Priority' in firm_info[key] and 
                 firm_info[key]['Priority'] == '0':
                if not has_functional:
                    flag = '*'
                else:
                    flag = '+'

            if not flag and not VERBOSE:
                continue

            firm_output.append('%s Firmware Product: %s (%s)%s' % 
                              (firm_info[key]['Purpose'],
                               firm_info[key]['Version'],
                               firm_info[key]['Activation'], flag))
            if 'ExtendedVersion' in firm_info[key]:
                extendeds = firm_info[key]['ExtendedVersion'].split(',')
                extendeds.sort()
                for extended in extendeds:
                    firm_output.append('%s Firmware Product: ' \
                                       '-- additional info: %s' % \
                                       (firm_info[key]['Purpose'], extended))

        return firm_output

    def _get_firm_info(self, status):
        """get firmware information
        :param status: current status
        :returns: firmware version information
        """
        firm_info = {}
        has_functional = False
        url = HTTP_PROTOCOL + self.bmcip + FIRM_URL
        response = self.client.request('GET', url, OpenBMC.headers, '', self.node, status)
        functional_url = PROJECT_URL + '/software/functional'

        for key in response['data']:
            key_id = key.split('/')[-1]
            if key_id == 'functional':
                for endpoint in response['data'][key]['endpoints']:
                    purpose = response['data'][endpoint]['Purpose'].split('.')[-1]
                    key_sort = purpose + '-' + endpoint.split('/')[-1]

                    utils.update2Ddict(firm_info, key_sort, 'is_functional', True)
                    has_functional = True

            if 'Version' in response['data'][key]:
                purpose = response['data'][key]['Purpose'].split('.')[-1]
                key_sort = purpose + '-' + key_id
                if functional_url in response['data'] and 
                   key in response['data'][functional_url]['endpoints']:
                    utils.update2Ddict(firm_info, key_sort, 'is_functional', True)
                utils.update2Ddict(firm_info, key_sort, 'Version', 
                                   response['data'][key]['Version'])
                utils.update2Ddict(firm_info, key_sort, 'Purpose', purpose)
                utils.update2Ddict(firm_info, key_sort, 'Activation', 
                                   response['data'][key]['Activation'].split('.')[-1])
                if 'Priority' in response['data'][key]:
                    utils.update2Ddict(firm_info, key_sort, 'Priority', 
                                       str(response['data'][key]['Priority']))
                if 'ExtendedVersion' in response['data'][key]:
                    utils.update2Ddict(firm_info, key_sort, 'ExtendedVersion', 
                                       response['data'][key]['ExtendedVersion'])
                if 'Progress' in response['data'][key]:
                    utils.update2Ddict(firm_info, key_sort, 'Progress', 
                                       response['data'][key]['Progress'])

        return (has_functional, firm_info)

    def _get_firm_id(self, firm_list):
        """get firmware id 
        :param firm_list: the list of firmware versions 
        :return: result and info list
        """
        firm_ids = []
        url = HTTP_PROTOCOL + self.bmcip + FIRM_URL

        for i in range(6):
            try:
                response = self.client.request('GET', url, OpenBMC.headers, 
                                               '', self.node, 'rflash_check_id')
            except (xcat_exception.SelfServerException,
                    xcat_exception.SelfClientException) as e:
                self._msg_process_rflash(e.message, ALL_NODES_RESULT, False)
                return (RESULT_FAIL, [])

            for key in response['data']:
                if 'Version' in response['data'][key]:
                    if response['data'][key]['Version'] in firm_list:
                        firm_id = key.split('/')[-1]
                        upload_msg = 'Firmware upload successful. ' \
                                     'Attempting to activate firmware: ' \
                                     '%s (ID: %s)' % \
                                     (response['data'][key]['Version'], firm_id)
                        self._msg_process_rflash(upload_msg, {}, False)
                        firm_ids.append(firm_id)
                        firm_list.remove(response['data'][key]['Version']) 

            if firm_list:
                for firm_ver in firm_list:
                    retry_msg = 'Could not find ID for firmware %s to '\
                                'activate, waiting %d seconds and retry...' \
                                 % (firm_ver, 10)
                    self._msg_process_rflash(upload_msg, {}, True)
                gevent.sleep( 10 ) 
            else:
                break

        if firm_list:
            for firm_ver in firm_list:
                error = 'Could not find firmware %s after waiting %d seconds.' \
                        % (firm_ver, 10*6)
                self._msg_process_rflash(upload_msg, {}, False)
                error_list.append(error)
            utils.update2Ddict(ALL_NODES_RESULT, self.node, 'rst', error_list)
            return (RESULT_FAIL, [])

        return (RESULT_OK, firm_ids)

    def _check_id_status(self, firm_id_list):
        """check firm id status
        :param firm_id_list: list of firm ids want to check
        :return: result
        """
        result = RESULT_OK
        set_priority_ids = []
        process_status = {}
        for i in range(80):
            try:
                (has_functional, firm_info) = self._get_firm_info('rflash_check_status')
            except (xcat_exception.SelfServerException,
                    xcat_exception.SelfClientException) as e:
                self._msg_process_rflash(e.message, ALL_NODES_RESULT, False)
                return (RESULT_FAIL, set_priority_ids)

            activation_num = 0
            for key in firm_info:
                firm_id = key.split('-')[-1]
                if firm_id in firm_id_list:
                    activation_state = firm_info[key]['Activation']
                    firm_version = firm_info[key]['Version']
                    if activation_state == 'Failed':
                        activation_msg = 'Firmware %s activation failed.' % (firm_version)
                        self._msg_process_rflash(activation_msg, {}, False)
                        result = RESULT_FAIL
                        firm_id_list.rempove(firm_id)
                    if activation_state == 'Active':
                        activation_msg = 'Firmware %s activation successful.' % (firm_version)
                        self._msg_process_rflash(activation_msg, {}, False)
                        firm_id_list.remove(firm_id)
                        priority = firm_info[key]['Priority'] 
                        if priority != '0':
                            set_priority_ids.append(firm_id)
                    if activation_state == 'Activating':
                        activating_progress_msg = 'Activating %s ... %s%%' \
                                % (firm_version, firm_info[key]['Progress'])
                        self._msg_process_rflash(activating_progress_msg, {}, True)
                        process_status[firm_id] = activating_progress_msg

            if not firm_id_list:
                break
            gevent.sleep( 15 )

        if firm_id_list:
            result = RESULT_FAIL
            for firm_id in firm_id_list:
                if firm_id in process_status: 
                    warn_msg = 'After %d seconds check the current status is %s' \
                               % (80*15, process_status[firm_id])
                    self._msg_process_rflash(warn_msg, ALL_NODES_RESULT, False)
            
        return (result, set_priority_ids)

    def _set_priority(self, priority_ids):
        """set firmware priority to 0
        :param priority_ids: list of firmware ids
        :return ok if success
        :return error msg if failed
        """
        for priority_id in priority_ids:
            url = HTTP_PROTOCOL + self.bmcip + 
                  RFLASH_URLS['priority']['url'].replace('#PRIORITY_ID#', priority_id)
            data = { "data": RFLASH_URLS['priority']['field'] }
            try:
                response = self.client.request('PUT', url, OpenBMC.headers, 
                                               data, self.node, 'rflash_set_priority')
            except (xcat_exception.SelfServerException,
                    xcat_exception.SelfClientException) as e:
                return e.message

        return RESULT_OK

    def _rflash_activate_id(self, activate_id):
        """rflash activate id
        :param activate_id: the id want to activate
        :raise: error message if failed
        """
        url = HTTP_PROTOCOL + self.bmcip + 
              RFLASH_URLS['activate']['url'].replace('#ACTIVATE_ID#', activate_id)
        data = { "data": RFLASH_URLS['activate']['field'] }
        try:
            response = self.client.request('PUT', url, OpenBMC.headers, 
                                           data, self.node, 'rflash_activate')
        except xcat_exception.SelfServerException as e:
            return e.message
        except xcat_exception.SelfClientException as e:
            code = e.code
            if code == 403:
                return 'Error: Invalid ID provided to activate. ' \
                       'Use the -l option to view valid firmware IDs.'
            return e.message

        return RESULT_OK

    def _rflash_activate(self, activate_arg):
        """ACTIVATE firmware
        called by rflash activate
        :param activate_arg: firmware tar ball or firmware id
        :return: ok if success
        :raise: error message if failed
        """
        activate_id = activate_version = ''
        if 'activate_id' in activate_arg:
            activate_id = activate_arg['activate_id']
        if 'activate_version' in activate_arg:
            activate_version = activate_arg['activate_version']
        if 'update_file' in activate_arg:
            result = self._rflash_upload(activate_arg['update_file'])
            if result != RESULT_OK:
                self._msg_process_rflash(result, ALL_NODES_RESULT, False)

            (result, info) = self._get_firm_id([activate_version])
            if result == RESULT_OK:
                activate_id = info.pop(0)

        result = self._rflash_activate_id(activate_id)
        if result != RESULT_OK:
            self._msg_process_rflash(result, ALL_NODES_RESULT, False)
            return
        else:
            flash_started_msg = 'rflash %s started, please wait...' % activate_version
            self._msg_process_rflash(flash_started_msg, {}, False)

        firm_id_list = [activate_id]
        (result, priority_ids) = self._check_id_status(firm_id_list)
        if result == RESULT_OK:
            utils.update2Ddict(ALL_NODES_RESULT, self.node, 'rst', 'OK')
            if priority_ids:
                self._set_priority(priority_ids)

    def _rflash_delete(self, delete_id):
        """Delete firmware on OpenBMC
        called by rflash delete
        :param delete_id: firmware id want to delete
        :returns: ok if success
        :raise: error message if failed
        """ 
        url = HTTP_PROTOCOL + self.bmcip + 
              RFLASH_URLS['delete']['url'].replace('#DELETE_ID#', delete_id)
        data = { "data": RFLASH_URLS['delete']['field'] }
        try:
            response = self.client.request('POST', url, OpenBMC.headers, 
                                           data, self.node, 'rflash_delete')
        except xcat_exception.SelfServerException as e:
            return e.message
        except xcat_exception.SelfClientException as e:
            code = e.code
            if code == 404:
                return 'Error: Invalid ID provided to delete. ' \
                       'Use the -l option to view valid firmware IDs.' 
            return e.message

        return RESULT_OK 


    def _rflash_list(self):
        """List firmware information
        called by rflash list
        :returns: firmware version if success
        :raise: error message if failed
        """
        firm_output = []
        try:
            (has_functional, firm_info) = self._get_firm_info('rflash_list')
        except (xcat_exception.SelfServerException,
                xcat_exception.SelfClientException) as e:
            firm_output.append(e.message)
            return firm_output

        firm_output.append('%-8s %-7s %-10s %-s' % ('ID', 'Purpose', 'State', 'Version'))
        firm_output.append('-' * 55)

        for key in firm_info:
            status = firm_info[key]['Activation']
            if 'is_functional' in firm_info[key]:
                status += '(*)'
            elif 'Priority' in firm_info[key] and firm_info[key]['Priority'] == '0':
                if not has_functional:
                    status += '(*)'
                else:
                    status += '(+)'

            firm_output.append('%-8s %-7s %-10s %-s' % (key.split('-')[-1], 
                               firm_info[key]['Purpose'], status, firm_info[key]['Version']))

        return firm_output

    def _rflash_upload(self, upload_file):
        """ Upload *.tar file to OpenBMC server
        :param upload_file: file to upload
        """
        url = HTTP_PROTOCOL + self.bmcip + RFLASH_URLS['upload']['url']
        headers = {'Content-Type': 'application/octet-stream'}
        uploading_msg = 'Uploading %s ...' % upload_file
        self._msg_process_rflash(uploading_msg, {}, True)
        try:
            self.client.request_upload_curl('PUT', url, headers, upload_file, 
                                            self.node, 'rflash_upload')
        except (xcat_exception.SelfServerException,
                xcat_exception.SelfClientException) as e:
            result = e.message
            return result

        return RESULT_OK

    def _set_power_onoff(self, subcommand):
        """ Set power on/off/softoff/bmcreboot
        :param subcommand: subcommand for rpower
        :returns: ok if success
        :raise: error message if failed
        """
        url = HTTP_PROTOCOL + self.bmcip + RPOWER_URLS[subcommand]['url']
        data = { "data": RPOWER_URLS[subcommand]['field'] }
        try:
            response = self.client.request('PUT', url, OpenBMC.headers, data,
                                           self.node, 'rpower_' + subcommand)
        except (xcat_exception.SelfServerException,
                xcat_exception.SelfClientException) as e:
            if subcommand != 'bmcreboot':
                result = e.message
            return result

        return RESULT_OK


    def _get_power_state(self, subcommand):
        """ Get power current state
        :param subcommand: state/stat/status/bmcstate
        :returns: current state if success
        :raise: error message if failed
        """
        result = ''
        bmc_not_ready = 'NotReady'
        url = HTTP_PROTOCOL + self.bmcip + RPOWER_URLS['state']['url']
        try:
            response = self.client.request('GET', url, OpenBMC.headers, '',
                                           self.node, 'rpower_' + subcommand)
        except xcat_exception.SelfServerException, e:
            if subcommand == 'bmcstate':
                result = bmc_not_ready
            else:
                result = e.message
        except xcat_exception.SelfClientException, e:
            result = e.message

        if result: 
            return result

        for key in response['data']:
            key_type = key.split('/')[-1]
            if key_type == 'bmc0':
                bmc_current_state = response['data'][key]['CurrentBMCState'].split('.')[-1]
            if key_type == 'chassis0':
                chassis_current_state = response['data'][key]['CurrentPowerState'].split('.')[-1]
            if key_type == 'host0':
                host_current_state = response['data'][key]['CurrentHostState'].split('.')[-1]

        if subcommand == 'bmcstate':
            if bmc_current_state == 'Ready':
                return bmc_current_state 
            else:
                return bmc_not_ready

        if chassis_current_state == 'Off':
            return chassis_current_state
        elif chassis_current_state == 'On':
            if host_current_state == 'Off':
                return 'chassison'
            elif host_current_state == 'Quiesced':
                return host_current_state
            elif host_current_state == 'Running':
                return host_current_state
            else:
                return 'Unexpected chassis state=' + host_current_state
        else:
            return 'Unexpected chassis state=' + chassis_current_state


    def _rpower_boot(self):
        """Power boot
        :returns: 'reset' if success
        :raise: error message if failed
        """
        result = self._set_power_onoff('off')
        if result != RESULT_OK:
            return result
        self.messager.update_node_attributes('status', self.node, POWER_STATE_DB['off'])

        start_timeStamp = int(time.time())
        for i in range (0,30):
            status = self._get_power_state('state')
            if status in RPOWER_STATE and RPOWER_STATE[status] == 'off':
                break
            gevent.sleep( 2 )

        end_timeStamp = int(time.time())

        if status not in RPOWER_STATE or RPOWER_STATE[status] != 'off':
            wait_time = str(end_timeStamp - start_timeStamp)
            result = 'Error: Sent power-off command but state did not change ' \
                     'to off after waiting %s seconds. (State= %s).' % (wait_time, status)
            return result

        result = self._set_power_onoff('on')
        return result

    def rflash(self, args):
        """handle rflash command
        :param args: subcommands and parameters for rflash
        """
        subcommand = args[0]
        if subcommand == 'activate' or subcommand == 'upload':
            self.rflash_log_handle = open(self.rflash_log_file, 'a') 

        try:
            result = self._login()
        except (xcat_exception.SelfServerException,
                xcat_exception.SelfClientException) as e:
            result = e.message

        if result != RESULT_OK:
            self.messager.info('%s: %s'% (self.node,result))
            if subcommand == 'activate' or subcommand == 'upload':
                self.rflash_log_handle.writelines(result + '\n')
                self.rflash_log_handle.flush()
                if subcommand == 'activate':
                    utils.update2Ddict(ALL_NODES_RESULT, self.node, 'rst', error_list) 
            return

        if subcommand == 'activate':
            activate_arg = args[1]
            self._rflash_activate(activate_arg) 

        if subcommand == 'check':
            firm_info = self._firm_info('rflash_check')
            for i in firm_info:
                result = '%s: %s' % (self.node, i)
                self.messager.info(result)

        if subcommand == 'delete':
            firmware_id = args[1]
            result = self._rflash_delete(firmware_id)
            if result == RESULT_OK:
                result = '%s: [%s] Firmware removed' % (self.node, firmware_id)
                self.messager.info(result)
            else:
                result = '%s: %s' % (self.node, result)
                self.messager.info(result) 

        if subcommand == 'list':
            firm_info = self._rflash_list()
            for i in firm_info:
                result = '%s: %s' % (self.node, i)
                self.messager.info(result)

        if subcommand == 'upload':
            upload_file = args[1] 
            result = self._rflash_upload(upload_file)
            if result == RESULT_OK:
                result = 'Firmware upload successful. Use -l option to list.'
                self._msg_process_rflash(result, {}, False)
            else:
                self._msg_process_rflash(result, {}, False)

        if subcommand == 'activate' or subcommand == 'upload':        
            self.rflash_log_handle.close()


    def rpower(self, args):
        """handle rpower command
        :param args: subcommands for rpower
        """
        subcommand = args[0]
        try:
            result = self._login()
        except xcat_exception.SelfServerException as e:
            if subcommand == 'bmcstate':
                result = '%s: %s' % (self.node, RPOWER_STATE['NotReady'])
            else:
                result = '%s: %s'  % (self.node, e.message)
        except xcat_exception.SelfClientException as e:
            result = '%s: %s'  % (self.node, e.message)

        if result != RESULT_OK:
            self.messager.info(result)
            return

        if subcommand in POWER_SET_OPTIONS:
            result = self._set_power_onoff(subcommand)
            if result == RESULT_OK:
                result = RPOWER_STATE[subcommand]
                new_status = POWER_STATE_DB.get(subcommand, '')

        if subcommand in POWER_GET_OPTIONS:
            tmp_result = self._get_power_state(subcommand)
            result = RPOWER_STATE.get(tmp_result, tmp_result)

        if subcommand == 'boot':
            result = self._rpower_boot()
            if result == RESULT_OK:
                result = RPOWER_STATE[subcommand]
                new_status = POWER_STATE_DB.get(subcommand, '')

        if subcommand == 'reset':
            status = self._get_power_state('state')
            if status == 'Off' or status == 'chassison':
                result = RPOWER_STATE['Off']
            else:
                result = self._rpower_boot()
                if result == RESULT_OK:
                    result = RPOWER_STATE[subcommand]
                    new_status = POWER_STATE_DB.get(subcommand, '')

        message = '%s: %s' % (self.node, result)
        self.messager.info(message)
        if new_status:
            self.messager.update_node_attributes('status', self.node, new_status)


class OpenBMCManager(base.BaseManager):
    def __init__(self, messager, cwd, nodes, envs):
        super(OpenBMCManager, self).__init__(messager, cwd)
        self.nodes = nodes
        global DEBUGMODE
        DEBUGMODE = envs['debugmode']

    def _get_full_path(self,file_path):
        if type(self.cwd) == 'unicode':
            dir_path = self.cwd
        else:
            dir_path = self.cwd[0]
        return '%s/%s' % (dir_path,file_path)

    def _check_verbose(self, args):
        verbose_list = ('-V', '--verbose')
        for i in verbose_list:
            if i in args:
                global VERBOSE
                VERBOSE = True
                args.remove(i)

    def _summary(self, nodes_num, title):
        if ALL_NODES_RESULT:
            success_num = failed_num = 0
            failed_list = []
            for key in ALL_NODES_RESULT:
                if ALL_NODES_RESULT[key]['rst'] == 'OK':
                    success_num += 1
                else:
                    failed_num += 1
                    for error in ALL_NODES_RESULT[key]['rst']:
                        failed_list.append(error)
            self.messager.info('-' * 55)
            self.messager.info('%s complete: Total=%d Success=%d Failed=%d' % \
                               (title, nodes_num, success_num, failed_num))
            if failed_list:
                 for i in failed_list:
                     self.messager.info(i)
            self.messager.info('-' * 55)

    def rflash(self, nodeinfo, args):
        if not os.path.exists(XCAT_LOG_RFLASH_DIR):
            os.makedirs(XCAT_LOG_RFLASH_DIR)
        nodes_num = len(self.nodes)
        self._check_verbose(args)

        for key,value in RFLASH_OPTIONS.items():
            if key in args:
                args.remove(key)
                args.insert(0, value)
                break

        upload_file = None
        activate_arg = {}
        args_num = len(args)
        subcommand = args[0]
        if subcommand == 'upload' or subcommand == 'activate' or
           (subcommand == 'check' and args_num > 1):
            arg_type = args[1].split('.')[-1]
            if arg_type == 'tar':
                upload_file = args[1]
                if not os.path.isabs(upload_file):
                    upload_file =  self._get_full_path(upload_file)

                if not os.access(upload_file, os.F_OK) or 
                   not os.access(upload_file, os.R_OK):
                    error = 'Error: Cannot access %s. Check the management ' \
                            'node and/or service nodes.' % upload_file
                    self.messager.error(error)
                    return
                activate_arg['update_file'] = upload_file
            else:
                activate_arg['activate_id'] = args[1]

        if (subcommand == 'check' or subcommand == 'activate') and upload_file:
            grep_cmd = '/usr/bin/grep -a'
            version_cmd = grep_cmd + ' ^version= ' + upload_file
            purpose_cmd = grep_cmd + ' purpose= ' + upload_file
            firmware_ver = os.popen(version_cmd).readlines()[0].split('=')[-1].strip()
            purpose_ver = os.popen(purpose_cmd).readlines()[0].split('=')[-1].strip()
            if subcommand == 'check':
                self.messager.info('TAR %s Firmware Product Version: %s' \
                                   % (purpose_ver,firmware_ver))
            else:
                activate_arg['activate_version'] = firmware_ver
                activate_arg['purpose'] = purpose_ver.split('.')[-1]

        if subcommand == 'activate':
            args[1] = activate_arg

        if subcommand == 'upload':
            args[1] = upload_file

        if subcommand == 'upload' or subcommand == 'activate' and upload_file:
            self.messager.info('Attempting to upload %s, please wait...' % upload_file)

        super(OpenBMCManager, self).process_nodes_worker('openbmc', 'OpenBMC', 
                    self.nodes, nodeinfo, 'rflash', args)
        self._summary(nodes_num, 'Firmware update')

    def rpower(self, nodeinfo, args):
        super(OpenBMCManager, self).process_nodes_worker('openbmc', 'OpenBMC', 
                    self.nodes, nodeinfo, 'rpower', args)
