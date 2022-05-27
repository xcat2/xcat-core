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
            number_to_display = 0-int(num_to_display)
        except Exception:
            # All records to display
            number_to_display = 0

        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback, debugmode=self.debugmode, verbose=self.verbose)
        eventlog_info = []
        try:
            obmc.login()

            # Get all eventlog records
            eventlog_info_dict = obmc.get_eventlog_info()

            keys = list(eventlog_info_dict.keys())
            # Sort thy keys in natural order
            keys.sort(key=lambda x : int(x[0:]))

            # Display all, or specified number of records from the end
            for key in list(keys)[number_to_display:]:
                self.callback.info('%s: %s'  % (node, eventlog_info_dict[key]))
                eventlog_info += eventlog_info_dict[key]

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return eventlog_info

    def clear_all_ev_records(self, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback, debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()
            obmc.clear_all_eventlog_records()
            self.callback.info('%s: %s'  % (node, "Logs cleared"))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error('%s'  % e.message, node)


    def resolve_ev_records(self, resolve_list, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback, debugmode=self.debugmode, verbose=self.verbose)
        try:
            obmc.login()

            # Get all eventlog records
            eventlog_info_dict = obmc.get_eventlog_info()

            keys = list(eventlog_info_dict.keys())
            # Sort the keys in natural order
            keys.sort(key=lambda x : int(x[0:]))

            resolved, ids = resolve_list.split('=')
            eventlog_ids_to_resolve = []
            if ids.upper() == "LED":

                # loop through eventlog_info_dict and collect LED ids to be resolved into a eventlog_ids_to_resolve array
                for key in list(keys):
                    if "[LED]" in eventlog_info_dict[key]:
                        if "Resolved: 0" or "Resolved: false" in eventlog_info_dict[key]:
                            eventlog_ids_to_resolve.append(key)
                        else:
                            if self.verbose:
                                self.callback.info('%s: Not resolving already resolved eventlog ID %s'  % (node, key))
            else:
                # loop through list of ids and collect ids to resolve into a eventlog_ids_to_resolve array
                for id_to_resolve in ids.split(','):
                    if id_to_resolve in eventlog_info_dict:
                        if "Resolved: 0" or "Resolved: false" in eventlog_info_dict[id_to_resolve]:
                            eventlog_ids_to_resolve.append(id_to_resolve)
                        else:
                            if self.verbose:
                                self.callback.info('%s: Not resolving already resolved eventlog ID %s'  % (node, id_to_resolve))
                    else:
                        self.callback.error('Invalid ID: %s'  % (id_to_resolve), node)

            if len(eventlog_ids_to_resolve) == 0:
                # At the end and there are no entries to resolve
                self.callback.error('No event log entries needed to be resolved', node)
            else:
                # Resolve entries that were collected into the eventlog_ids_to_resolve array
                obmc.resolve_event_log_entries(eventlog_ids_to_resolve)
                for entry in eventlog_ids_to_resolve:
                    self.callback.info('%s: Resolved %s'  % (node, entry))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error('%s' % e.message, node)

