#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
from __future__ import print_function
import gevent
import time

from common.task import ParallelNodesCommand
from common.exceptions import SelfClientException, SelfServerException
from hwctl import redfish_client as redfish

import logging
logger = logging.getLogger('xcatagent')

POWER_STATE_DB = {
    "on"      : "powering-on",
    "off"     : "powering-off",
    "boot"    : "powering-on",
}

class RedfishPowerTask(ParallelNodesCommand):
    """Executor for power-related actions."""

    def get_state(self, **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)

        state = 'Unknown'
        try:
            rf.login()
            chassis_state = rf.get_chassis_power_state()
            if chassis_state == 'On':
                state = rf.get_systems_power_state().lower()
            else:
                state = chassis_state.lower()
            self.callback.info('%s: %s' % (node, state))
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return state

    def get_bmcstate (self, **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)

        state = 'Unknown'
        try:
            rf.login()
            state = rf.get_bmc_state().lower()
            self.callback.info('%s: %s' % (node, state))
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
        return state

    def set_state(self, state, **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)

        try:
            rf.login()
            rf.set_power_state(state)
            new_status = POWER_STATE_DB.get(state, '')
            self.callback.info('%s: %s' % (node, state))
            if new_status:
                self.callback.update_node_attributes('status', node, new_status)
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node) 

    def reboot(self, optype='boot', **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)
        resettype = 'boot'

        try:
            rf.login()
            chassis_state = rf.get_chassis_power_state()
            if chassis_state == 'Off':
                status = chassis_state 
            else:
                status = rf.get_systems_power_state()

            if status == 'Off':
                if optype == 'reset':
                    return self.callback.info('%s: %s' % (node, status.lower()))
                else:
                    resettype = 'on'
            
            rf.set_power_state(resettype)
            new_status = POWER_STATE_DB.get(optype, '')
            self.callback.info('%s: %s' % (node, optype))
            if new_status:
                self.callback.update_node_attributes('status', node, new_status)
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

    def reboot_bmc(self, optype='warm', **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)

        try:
            rf.login()
        except (SelfServerException, SelfClientException) as e:
            return self.callback.error(e.message, node)

        try:
            rf.reboot_bmc(optype)
        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
        else:
            self.callback.info('%s: %s' % (node, 'bmcreboot')) 
