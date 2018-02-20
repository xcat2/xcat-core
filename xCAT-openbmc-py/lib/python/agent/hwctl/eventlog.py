#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class EventlogInterface(object):
    """Interface for eventlog-related actions."""
    interface_type = 'eventlog'
    version = '1.0'

    def get_eventlog_info(self, task, eventlog_type=None):
        """Return the eventlog info of the task's nodes.

        :param eventlog_type: type of eventlog info want to get.
        :param task: a Task instance containing the nodes to act on.
        :return eventlog list
        """
        return task.run('get_ev_info', eventlog_type)

class DefaultEventlogManager(EventlogInterface):
    """Interface for eventlog-related actions."""
    pass
