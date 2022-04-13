#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

from __future__ import print_function
import gevent
import time
import os

from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import openbmc_client as openbmc
from common import utils

import logging
logger = logging.getLogger('xcatagent')

class OpenBMCInventoryTask(ParallelNodesCommand):
    """Executor for inventory-related actions."""

    def pre_get_firm_info(self, task, target_file=None, **kw):

        if not target_file:
            return

        target_file = utils.get_full_path(self.cwd, target_file)

        version = purpose = None
        with open(target_file, encoding="utf8", errors='ignore') as fh:
            for line in fh:
                if 'version=' in line:
                    version = line.split('=')[-1].strip()
                if 'purpose=' in line:
                    purpose = line.split('=')[-1].strip()
                if version and purpose:
                    break

        self.callback.info('TAR %s Firmware Product Version: %s' \
                            % (purpose, version))

    def _get_firm_info(self, firm_info_list):
        (has_functional, firm_obj_dict) = firm_info_list
        firm_info = []
        keys = list(firm_obj_dict.keys())
        keys.sort()
        for key in keys:
            flag = ''
            if firm_obj_dict[key].functional:
                flag = '*'
            elif firm_obj_dict[key].priority == 0:
                if not has_functional:
                    flag = '*'
                else:
                    flag = '+'

            if flag != '*' and not self.verbose:
                continue

            firm_info.append('%s Firmware Product: %s (%s)%s' %
                              (firm_obj_dict[key].purpose.upper(),
                               firm_obj_dict[key].version,
                               firm_obj_dict[key].active,
                               flag))
            if firm_obj_dict[key].extver:
                extendeds = firm_obj_dict[key].extver.split(',')
                extendeds.sort()
                for extended in extendeds:
                    firm_info.append('%s Firmware Product: ' \
                                     '-- additional info: %s' % \
                                      (firm_obj_dict[key].purpose.upper(), extended))

        return firm_info

    def get_info(self, inventory_types, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        inventory_info = []

        # inventory_types contains an array of different inventories to get
        # Go through the array and set flags to optimize invnetory calls
        model_or_serial = 0
        cpu_or_dimm = 0
        all = 0
        inventory_type = 'all'
        for type in inventory_types:
            if type == 'model' or type == 'serial':
                # For model and serial we can make a single call
                model_or_serial = 1
            if type == 'cpu' or type == 'dimm':
                # For cpu and dimm we can make a single call
                cpu_or_dimm = 1
            if type == 'all':
                all = 1
        if all == 1:
            inventory_type = 'all'
        elif model_or_serial == 1 and cpu_or_dimm == 1:
            # Both model_or_serial and cpu_or_dimm were set, might as well ask for all
            inventory_type = 'all'
        elif model_or_serial == 1:
            inventory_type = 'model'
        elif cpu_or_dimm == 1:
            inventory_type = 'cpu'

        try:
            obmc.login()
            # Extract the data from the BMC
            inventory_info_dict = obmc.get_inventory_info(inventory_type)

            # Process returned inventory_info_dict depending on the inventory requested
            if all == 1:
                # Everything gets displayed, even firmware
                keys = list(inventory_info_dict.keys())
                keys.sort()
                for key in keys:
                    inventory_info += utils.sort_string_with_numbers(inventory_info_dict[key])

                firm_dict_list = obmc.list_firmware()
                firm_info = self._get_firm_info(firm_dict_list)

                inventory_info += firm_info
            else:
                if model_or_serial == 1:
                    # Model or serial was requested
                    for one_inventory_type in inventory_types:
                        if one_inventory_type == 'model':
                            key = 'Model'
                        elif one_inventory_type == 'serial':
                            key = 'SerialNumber'
                        else:
                            continue

                        if 'SYSTEM' in inventory_info_dict:
                            for system_info in inventory_info_dict['SYSTEM']:
                                if key in system_info:
                                    inventory_info += [system_info]
                                    break
                if cpu_or_dimm:
                    # cpu or dimm was requested
                    for one_inventory_type in inventory_types:
                        key = one_inventory_type.upper()
                        if key in inventory_info_dict:
                            inventory_info += utils.sort_string_with_numbers(inventory_info_dict[key])

            if not inventory_info:
                inventory_info = ['No attributes returned from the BMC.']

            for info in inventory_info:
                self.callback.info( '%s: %s' % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return inventory_info

    def get_firm_info(self, target_file=None, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        firm_info = []
        try:
            obmc.login()
            firm_dict_list = obmc.list_firmware()
            firm_info = self._get_firm_info(firm_dict_list)

            for info in firm_info:
                self.callback.info( '%s: %s' % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return firm_info




