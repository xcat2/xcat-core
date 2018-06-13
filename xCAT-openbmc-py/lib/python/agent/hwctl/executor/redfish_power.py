#!/usr/bin/env python
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
    "softoff" : "powering-off",
    "boot"    : "powering-on",
    "reset"   : "powering-on",
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
            state = rf.get_power_state()
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
            state = rf.get_bmc_state()
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

    def rebootbmc(self, optype='warm', **kw):

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
