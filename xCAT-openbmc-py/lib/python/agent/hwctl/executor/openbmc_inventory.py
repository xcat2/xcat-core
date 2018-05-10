#!/usr/bin/env python
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
        with open(target_file, 'r') as fh:
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
        keys = firm_obj_dict.keys()
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
                              (firm_obj_dict[key].purpose,
                               firm_obj_dict[key].version,
                               firm_obj_dict[key].active,
                               flag))
            if firm_obj_dict[key].extver:
                extendeds = firm_obj_dict[key].extver.split(',')
                extendeds.sort()
                for extended in extendeds:
                    firm_info.append('%s Firmware Product: ' \
                                     '-- additional info: %s' % \
                                      (firm_obj_dict[key].purpose, extended))

        return firm_info

    def get_info(self, inventory_type, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        inventory_info = []
        try:
            obmc.login()
            inventory_info_dict = obmc.get_inventory_info(inventory_type)

            if inventory_type == 'all' or not inventory_type:
                keys = inventory_info_dict.keys()
                keys.sort()
                for key in keys:
                    inventory_info += utils.sort_string_with_numbers(inventory_info_dict[key])

                firm_dict_list = obmc.list_firmware()
                firm_info = self._get_firm_info(firm_dict_list)

                inventory_info += firm_info
            elif inventory_type == 'model' or inventory_type == 'serial':
                key = 'Model' if inventory_type == 'model' else 'SerialNumber'
                if 'SYSTEM' in inventory_info_dict:
                    for system_info in inventory_info_dict['SYSTEM']:
                        if key in system_info:
                            inventory_info = [system_info]
                            break
            else:
                key = inventory_type.upper()
                if key in inventory_info_dict:
                    inventory_info = utils.sort_string_with_numbers(inventory_info_dict[key])

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


            

