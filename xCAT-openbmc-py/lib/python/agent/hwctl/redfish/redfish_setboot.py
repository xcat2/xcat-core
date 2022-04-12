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

class RedfishBootTask(ParallelNodesCommand):
    """Executor for setboot-related actions."""

    def get_state(self, **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)

        state = 'Unknown'
        try:
            rf.login()
            state = rf.get_boot_state()
            self.callback.info('%s: %s' % (node, state))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return state 

    def set_state(self, setboot_state, persistant, **kw):

        node = kw['node']
        rf = redfish.RedfishRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                 debugmode=self.debugmode, verbose=self.verbose)

        try:
            rf.login()
            rf.set_boot_state(persistant, setboot_state)
            state = rf.get_boot_state()
            self.callback.info('%s: %s' % (node, state))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)
