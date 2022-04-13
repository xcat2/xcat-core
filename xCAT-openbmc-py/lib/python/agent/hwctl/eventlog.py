#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class EventlogInterface(object):
    """Interface for eventlog-related actions."""
    interface_type = 'eventlog'
    version = '1.0'

    def get_eventlog_info(self, task, number_of_records="all"):
        """Return the eventlog info of the task's nodes.

        :param number_of_records: number of records to display.
        :param task: a Task instance containing the nodes to act on.
        :return eventlog list
        """
        return task.run('get_ev_info', number_of_records)

    def clear_all_eventlog_records(self, task):
        """Clear all eventlog records.

        :param task: a Task instance containing the nodes to act on.
        :return
        """
        return task.run('clear_all_ev_records')

    def resolve_eventlog_records(self, task, resolve_list="LED"):
        """Return the eventlog info of the task's nodes.

        :param resolve: list of eventlog ids to resolve or LED label.
        :param task: a Task instance containing the nodes to act on.
        :return eventlog list of resolved entries
        """
        return task.run('resolve_ev_records', resolve_list)

class DefaultEventlogManager(EventlogInterface):
    """Interface for eventlog-related actions."""
    pass
