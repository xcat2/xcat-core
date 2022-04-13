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


class OpenBMCBeaconTask(ParallelNodesCommand):
    """Executor for beacon-related actions."""

    def set_state(self, state, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_beacon_state(state)
            self.callback.info('%s: %s' % (node, state))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

