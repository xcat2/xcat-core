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
from common import utils

import logging
logger = logging.getLogger('xcatagent')

class OpenBMCEventlogTask(ParallelNodesCommand):
    """Executor for eventlog-related actions."""

    def get_ev_info(self, eventlog_type, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback, debugmode=self.debugmode, verbose=self.verbose) 
        eventlog_info = []
        try:
            obmc.login()
            eventlog_info_dict = obmc.get_eventlog_info()
        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s'  % (node, e.message))
