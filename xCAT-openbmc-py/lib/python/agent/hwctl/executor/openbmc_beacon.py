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
from hwctl import openbmc_client as openbmc

import logging
logger = logging.getLogger('xcatagent')


class OpenBMCBeaconTask(ParallelNodesCommand):
    """Executor for beacon-related actions."""

    def get_state(self, **kw):
        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        beacon_info = []
        try:
            obmc.login()
            beacon_info = obmc.get_beacon_info()
            for info in beacon_info:
                self.callback.info( '%s: %s' % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s'  % (node, e.message))

        return beacon_info


    def set_state(self, state, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.set_beacon_state(state)
            result = '%s: %s' % (node, state)

        except (SelfServerException, SelfClientException) as e:
            result = '%s: %s'  % (node, e.message)

        self.callback.info(result)
