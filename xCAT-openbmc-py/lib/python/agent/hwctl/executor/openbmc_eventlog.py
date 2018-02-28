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

    def get_ev_info(self, num_to_display, **kw):

        node = kw['node']
        number_to_display = 0
        try:
            # Number of records to display from the end
            number_to_display = 0-int(num_to_display[0])
        except Exception:
            # All records to display
            number_to_display = 0

        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback, debugmode=self.debugmode, verbose=self.verbose) 
        eventlog_info = []
        try:
            obmc.login()

            # Get all eventlog records
            eventlog_info_dict = obmc.get_eventlog_info()

            keys = eventlog_info_dict.keys()
            # Sort thy keys in natural order
            keys.sort(key=lambda x : int(x[0:]))

            # Display all, or specified number of records from the end
            for key in list(keys)[number_to_display:]:
                self.callback.info('%s: %s'  % (node, eventlog_info_dict[key]))
                eventlog_info += eventlog_info_dict[key]

        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s'  % (node, e.message))

        return eventlog_info

    def clear_all_ev_records(self, **kw):

        node = kw['node']

    def resolve_ev_records(self, resolve_list, **kw):

        node = kw['node']
