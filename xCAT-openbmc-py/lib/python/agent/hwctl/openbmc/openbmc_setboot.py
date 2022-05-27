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
from hwctl import openbmc_client as openbmc

import logging
logger = logging.getLogger('xcatagent')


class OpenBMCBootTask(ParallelNodesCommand):
    """Executor for setboot-related actions."""

    def get_state(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        state = 'Unknown'
        try:
            obmc.login()
            state = obmc.get_boot_state()

            self.callback.info('%s: %s' % (node, state))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return state

    def set_state(self, state, persistant, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        try:
            obmc.login()
            if persistant:
                obmc.set_one_time_boot_enable(0)
                obmc.set_boot_state(state)
            else:
                obmc.set_one_time_boot_enable(1)
                obmc.set_one_time_boot_state(state)

            state = obmc.get_boot_state()

            self.callback.info('%s: %s' % (node, state))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)


