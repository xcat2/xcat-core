#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
from __future__ import print_function
import gevent
import time
import os, re

from common import utils
from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc

import logging
logger = logging.getLogger('xcatagent')

XCAT_LOG_DIR = "/var/log/xcat"
XCAT_LOG_RFLASH_DIR = XCAT_LOG_DIR + "/rflash/"

class OpenBMCFlashTask(ParallelNodesCommand):
    """Executor for flash-related actions."""
    activate_result = {}
    firmware = {}
    firmware_file = None
    log_handle = {}
    nodes_num = 0

    def _msg_process(self, node, msg, msg_type='I', update_rc=False, checkv=False):

        if msg_type == 'E':
            self.callback.error(msg, node)
        elif not checkv:
            self.callback.info('%s: %s' % (node, msg))
        elif self.verbose:
            self.callback.info('%s: %s' % (node, msg))

        if update_rc:
            self.activate_result.update({node: msg})

        if node not in self.log_handle:
            log_file = XCAT_LOG_RFLASH_DIR + '/' + node + '.log'
            self.log_handle.update({node: open(log_file, 'a')})
        try:
            self.log_handle[node].writelines(msg + '\n')
            self.log_handle[node].flush()
        except Exception as e:
            self.callback.error('Failed to record rflash log for node %s' % node)

    def _firmware_file_check(self, firmware_file, **kw):

        target_file = utils.get_full_path(self.cwd, firmware_file)
        self.firmware_file = target_file

        if (not os.access(target_file, os.F_OK) or
            not os.access(target_file, os.R_OK)):
            error = 'Cannot access %s. Check the management ' \
                     'node and/or service nodes.' % target_file
            self.callback.error(error)
            raise Exception('Invalid firmware file %s' % target_file)

    def validate_activate_firm(self, task, activate_arg, **kw):

        if activate_arg.endswith('.tar'):
            self._firmware_file_check(activate_arg)
        else:
            if not re.match('\A[0-9a-fA-F]+\Z', activate_arg):
                self.callback.error('Invalid firmware ID %s' % activate_arg)

    def validate_delete_firm(self, task, delete_id, **kw):

        if not re.match('\A[0-9a-fA-F]+\Z', delete_id):
            self.callback.error('Invalid firmware ID %s' % activate_arg)

    def validate_upload_firm(self, task, upload_file, **kw):

        self._firmware_file_check(upload_file)

    def _get_firmware_version(self, target_file):

        version = purpose = None
        with open(target_file, encoding="utf8", errors='ignore') as fh:
            for line in fh:
                if 'version=' in line:
                    version = line.split('=')[-1].strip()
                if 'purpose=' in line:
                    purpose = line.split('=')[-1].strip().split('.')[-1]
                if version and purpose:
                    break

        return { version: {'purpose': purpose} }

    def pre_activate_firm(self, task, activate_arg, **kw):

        if not os.path.exists(XCAT_LOG_RFLASH_DIR):
            os.makedirs(XCAT_LOG_RFLASH_DIR)

        if activate_arg.endswith('.tar'):
            version = self._get_firmware_version(self.firmware_file)
            self.firmware.update(version)
            self.callback.info('Attempting to upload %s, please wait...' % self.firmware_file)
        else:
            self.callback.info('Attempting to activate ID=%s, please wait..' % activate_arg)
        self.nodes_num = len(self.inventory)

    def pre_delete_firm(self, task, delete_id, **kw):

        self.callback.info('Attempting to delete ID=%s, please wait..' % delete_id)

    def pre_flash_process(self, task, directory, no_host_reboot, **kw):

        if not os.path.exists(XCAT_LOG_RFLASH_DIR):
            os.makedirs(XCAT_LOG_RFLASH_DIR)

        directory = utils.get_full_path(self.cwd, directory)
        tmp_dict = {'BMC': [], 'Host': []}
        for filename in os.listdir(directory):
            if filename.endswith('.tar'):
                filename = os.path.join(directory, filename)
                try:
                    version = self._get_firmware_version(filename)
                except Exception as e:
                    continue
                self.firmware.update(version)
                for key, value in version.items():
                    tmp_dict[ value['purpose'] ].append(filename)
                    self.firmware[key].update({'file': filename})

        bmc_file_num = len(tmp_dict['BMC'])
        host_file_num = len(tmp_dict['Host'])
        error = None
        if not bmc_file_num:
            error = 'No BMC tar file found in %s' % directory
        elif not host_file_num:
            error = 'No HOST tar file found in %s' % directory
        elif bmc_file_num > 1:
            error = 'More than 1 BMC tar file %s found in %s' \
                    % (' '.join(tmp_dict['BMC']), directory)
        elif host_file_num > 1:
            error = 'More than 1 HOST tar file %s found in %s' \
                    % (' '.join(tmp_dict['Host']), directory)
        if error:
            self.callback.error(error)
            raise Exception('No or More tar file found')

        self.callback.info('Attempting to upload %s and %s, please wait..' \
                           % (tmp_dict['BMC'][0], tmp_dict['Host'][0]))
        self.nodes_num = len(self.inventory)

    def pre_upload_firm(self, task, upload_arg, **kw):

        if not os.path.exists(XCAT_LOG_RFLASH_DIR):
            os.makedirs(XCAT_LOG_RFLASH_DIR)
        self.callback.info('Attempting to upload %s, please wait...' % self.firmware_file)

    def _get_firm_id(self, obmc, node):

        mapping_ids = []
        if self.firmware:
            version_list = list(self.firmware.keys())
        else:
            return []

        for i in range(6):
            try:
                has_functional, firm_obj_dict = obmc.list_firmware()
            except (SelfServerException, SelfClientException) as e:
                self._msg_process(node, e.message, msg_type='E', update_rc=True)
                return []

            for key, value in firm_obj_dict.items():
                if value.version and value.version in version_list:
                    firm_id = key.split('-')[-1]
                    mapping_ids.append(firm_id)
                    msg = 'Firmware upload successful. ' \
                          'Attempting to activate firmware: %s (ID: %s)' \
                          % (value.version, firm_id)
                    self._msg_process(node, msg, update_rc=True)
                    version_list.remove(value.version)

                if not version_list:
                    return mapping_ids
            for i in version_list:
                msg = 'Could not find ID for firmware %s to '\
                      'activate, waiting %d seconds and retry...' \
                       % (i, 10)
                self._msg_process(node, msg, update_rc=True, checkv=True)
            gevent.sleep ( 10 )

        error = []
        for i in version_list:
            msg = 'Could not find firmware %s after waiting %d seconds.' % (i, 10*6)
            error.qppend(msg)
            self._msg_process(node, msg, msg_type='E')

        if error:
            msg = ' '.join(error)
            self.activate_result.update({node: msg})
            return []

    def _check_id_status(self, obmc, check_ids, node, only_act=True):

        firm_ids = check_ids
        priority_ids = []
        process_status = {}
        for i in range(80):
            try:
                has_functional, firm_obj_dict = obmc.list_firmware()
            except (SelfServerException, SelfClientException) as e:
                return self._msg_process(node, e.message, msg_type='E', update_rc=True)

            for key, value in firm_obj_dict.items():
                key_id = key.split('-')[-1]
                if key_id in firm_ids:
                    activation_state = value.active
                    firm_version = value.version
                    if activation_state == 'Failed':
                        activation_msg = 'Firmware %s activation failed.' % (firm_version)
                        self._msg_process(node, activation_msg, msg_type='E', update_rc=True)
                        firm_ids.remove(key_id)
                    if activation_state == 'Active':
                        activation_msg = 'Firmware %s activation successful.' % (firm_version)
                        self._msg_process(node, activation_msg, update_rc=True)
                        firm_ids.remove(key_id)
                        if value.priority != 0:
                            priority_ids.append(key_id)
                    if activation_state == 'Activating':
                        activating_progress_msg = 'Activating %s ... %s%%' \
                                                  % (firm_version, value.progress)
                        process_status[key_id] = activating_progress_msg
                        self._msg_process(node, activating_progress_msg, checkv=True)

            if not firm_ids:
                break
            gevent.sleep( 15 )

        error = []
        for i in firm_ids:
            msg = 'After %d seconds check the firmware id %s current status is "%s"' \
                  % (80*15, process_status[i], i)
            error.append(msg)
            self._msg_process(node, msg, msg_type='E')

        if error:
            msg = ' '.join(error)
            self.activate_result.update({node: msg})
            return

        for i in priority_ids:
             try:
                obmc.set_priority(i)
             except (SelfServerException, SelfClientException) as e:
                msg = e.message
                error.append(msg)
                self._msg_process(node, msg, msg_type='E')

        if error:
            msg = ' '.join(error)
            self.activate_result.update({node: msg})
            return

        self.activate_result.update({node: 'SUCCESS'})

    def _reboot_to_effect(self, obmc, no_host_reboot, node):

        self._msg_process(node, 'Firmware will be flashed on reboot, deleting all BMC diagnostics...')
        try:
            obmc.clear_dump('all')
        except (SelfServerException, SelfClientException) as e:
            self.callback.warn('%s: Could not clear BMC diagnostics successfully %s, ignoring...' % (node, e.message))

        try:
            obmc.reboot_bmc()
        except (SelfServerException, SelfClientException) as e:
            return self._msg_process(node, e.message, msg_type='E', update_rc=True)

        self._msg_process(node, openbmc.RPOWER_STATES['bmcreboot'], update_rc=True)

        gevent.sleep( 10 )

        bmc_state = None
        for i in range(20):
            try:
                obmc.login()
                state = obmc.get_bmc_state()
                bmc_state = state.get('bmc')

                if bmc_state == 'Ready':
                    break
            except (SelfServerException, SelfClientException) as e:
                self._msg_process(node, e.message, checkv=True)

            self._msg_process(node, 'Retry BMC state, wait for 15 seconds ...', update_rc=True)
            gevent.sleep( 15 )

        if bmc_state != 'Ready':
            error = 'Sent bmcreboot but state did not change to BMC Ready after ' \
                    'waiting %s seconds. (State=BMC %s).' % (20*15, bmc_state)
            return self._msg_process(node, error, msg_type='E', update_rc=True)

        self._msg_process(node, 'BMC %s' % bmc_state, update_rc=True)

        if no_host_reboot:
            self.activate_result.update({node: 'SUCCESS'})
            return

        try:
            obmc.set_power_state('off')
            self.callback.update_node_attributes('status', node, 'powering-off')

            off_flag = False
            start_timeStamp = int(time.time())
            for i in range (0, 30):
                states = obmc.list_power_states()
                state = obmc.get_host_state(states)
                if openbmc.RPOWER_STATES.get(state) == 'off':
                    off_flag = True
                    break
                gevent.sleep( 2 )

            end_timeStamp = int(time.time())

            if not off_flag:
                error = 'Error: Sent power-off command but state did not change ' \
                        'to off after waiting %s seconds. (State= %s).' % (end_timeStamp - start_timeStamp, status)
                return self._msg_process(node, error, update_rc=True)

            ret = obmc.set_power_state('on')
            self.callback.update_node_attributes('status', node, 'powering-on')

            self._msg_process(node, 'reset')
            self.activate_result.update({node: 'SUCCESS'})
        except (SelfServerException, SelfClientException) as e:
            self._msg_process(node, e.message, update_rc=True)

    def activate_firm(self, activate_arg, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
        except (SelfServerException, SelfClientException) as e:
            return self._msg_process(node, e.message, msg_type='E', update_rc=True)

        firmware_version = ''
        if self.firmware_file:
            firmware_version = list(self.firmware.keys())[0]
            try:
                obmc.upload_firmware(self.firmware_file)
            except (SelfServerException, SelfClientException) as e:
                return self._msg_process(node, e.message, msg_type='E', update_rc=True)

            activate_ids = self._get_firm_id(obmc, node)
            if not activate_ids:
                return
            activate_id = activate_ids[0]
        else:
           activate_id = activate_arg

        error = ''
        try:
            obmc.activate_firmware(activate_id)
        except SelfServerException as e:
            error = e.message
        except SelfClientException as e:
            if e.code == 403:
                error = 'Invalid ID provided to activate. ' \
                        'Use the -l option to view valid firmware IDs.'
            else:
                error = e.message
        if error:
            return self._msg_process(node, error, msg_type='E', update_rc=True)

        msg = 'rflash %s started, please wait...' % firmware_version
        self._msg_process(node, msg, checkv=True)

        check_ids = [activate_id]
        self._check_id_status(obmc, check_ids, node)

    def delete_firm(self, delete_id, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        error = ''
        try:
            obmc.login()
        except (SelfServerException, SelfClientException) as e:
            return self.callback.error(e.message, node)

        try:
            has_functional, firm_obj_dict = obmc.list_firmware()
        except (SelfServerException, SelfClientException) as e:
            return self.callback.error(e.message, node)

        host_flag = False
        for key, value in firm_obj_dict.items():
            key_id = key.split('-')[-1]
            if key_id != delete_id:
                continue
            if value.functional or (value.priority == 0 and not has_functional):
                if value.purpose == 'BMC':
                    return self.callback.error('Deleting currently active BMC firmware' \
                                               ' is not supported', node)
                elif value.purpose == 'Host':
                    host_flag = True
                    break
                else:
                    self.callback.error('Unable to determine the purpose of the ' \
                                        'firmware to delete', node)

        if host_flag:
            try:
                states = obmc.list_power_states()
                state = obmc.get_host_state(states)
                if openbmc.RPOWER_STATES.get(state) == 'on':
                    return self.callback.error('Deleting currently active firmware on' \
                                               ' powered on host is not supported', node)
            except (SelfServerException, SelfClientException) as e:
                return self.callback.error(e.message, node)

        try:
            obmc.delete_firmware(delete_id)
        except SelfServerException as e:
            error = e.message
        except SelfClientException as e:
            if e.code == 404:
                error = 'Invalid ID provided to delete. ' \
                        'Use the -l option to view valid firmware IDs.'
            else:
                error = e.message

        if error:
            self.callback.error(error, node)
        else:
            self.callback.info('%s: [%s] Firmware removed' % (node, delete_id))

    def flash_process(self, directory, no_host_reboot, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
        except (SelfServerException, SelfClientException) as e:
            return self._msg_process(node, e.message, msg_type='E', update_rc=True)

        try:
            for key, value in self.firmware.items():
                obmc.upload_firmware(value['file'])
        except (SelfServerException, SelfClientException) as e:
            return self._msg_process(node, e.message, msg_type='E', update_rc=True)

        activate_ids = self._get_firm_id(obmc, node)
        if not activate_ids:
            return

        for i in activate_ids:
            error = ''
            try:
                obmc.activate_firmware(i)
            except SelfServerException as e:
                error = e.message
            except SelfClientException as e:
                if e.code == 403:
                    error = 'Invalid ID %s provided to activate. Use the -l option ' \
                            'to view valid firmware IDs.' % i
                else:
                    error = e.message
            if error:
                return self._msg_process(node, error, msg_type='E', update_rc=True)

        for key in self.firmware:
            msg = 'rflash %s started, please wait...' % key
            self._msg_process(node, msg, checkv=True)

        self._check_id_status(obmc, activate_ids, node, only_act=False)

        self._reboot_to_effect(obmc, no_host_reboot, node)

    def list_firm_info(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        firm_info = []
        try:
            obmc.login()
            has_functional, firm_obj_dict = obmc.list_firmware()

        except (SelfServerException, SelfClientException) as e:
            return self.callback.error(e.message, node)

        firm_info.append('%-8s %-7s %-10s %-s' % ('ID', 'Purpose', 'State', 'Version'))
        firm_info.append('-' * 55)

        for key, value in firm_obj_dict.items():
            status = value.active
            if value.functional:
                status += '(*)'
            elif value.priority == 0:
                if not has_functional:
                    status += '(*)'
                else:
                    status += '(+)'

            firm_info.append('%-8s %-7s %-10s %-s' % (key.split('-')[-1],
                             value.purpose, status, value.version))

        for info in firm_info:
                self.callback.info('%s: %s' % (node, info))

        return firm_info

    def upload_firm(self, upload_file, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            # Before uploading file, check CPU DD version
            inventory_info_dict = obmc.get_inventory_info('cpu')
            cpu_info = inventory_info_dict["CPU"]
            for info in cpu_info:
                if info.startswith("CPU0 Version : 20"):
                    # Display warning the only certain firmware versions are supported on DD 2.0
                    self.callback.info( '%s: Warning: DD 2.0 processor detected on this node, should not have firmware > ibm-v2.0-0-r13.6 (BMC) and > v1.19_1.94 (Host).' % node)
                if info.startswith("CPU0 Version : 21"):
                    if self.verbose:
                        self.callback.info( '%s: DD 2.1 processor' % node)
        except (SelfServerException, SelfClientException) as e:
            return self._msg_process(node, e.message, msg_type='E')

        try:
            obmc.upload_firmware(self.firmware_file)
            self._msg_process(node, 'Firmware upload successful. Use -l option to list.')
        except (SelfServerException, SelfClientException) as e:
            return self._msg_process(node, e.message, msg_type='E')

    def _flash_summary(self):

        if not self.activate_result:
            return self.callback.error('No summary infomation')

        success_num = failed_num = 0
        failed_list = []
        for key, value in self.activate_result.items():
            if value == 'SUCCESS':
                success_num += 1
            else:
                failed_num += 1
                failed_list.append('%s: %s' % (key, value))

        self.callback.info_with_host('-' * 55)
        self.callback.info_with_host('%s complete: Total=%d Success=%d Failed=%d' % \
                           ('Firmware update', self.nodes_num, success_num, failed_num))

        for i in failed_list:
            self.callback.info_with_host(i)
        self.callback.info_with_host('-' * 55)

    def post_activate_firm(self, task, activate_arg, **kw):

        self._flash_summary()

    def post_flash_process(self, task, directory, no_host_reboot, **kw):

        self._flash_summary()
