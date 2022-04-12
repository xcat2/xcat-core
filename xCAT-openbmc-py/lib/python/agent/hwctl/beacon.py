#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class BeaconInterface(object):
    """Interface for beacon-related actions."""
    interface_type = 'beacon'
    version = '1.0'

    def set_beacon_state(self, task, beacon_state, timeout=None):
        """Set the beacon state of the task's nodes.

        :param task: a Task instance containing the nodes to act on.
        :param beacon_state: on|off beacon state.
        :param timeout: timeout (in seconds) positive integer (> 0) for any
          beacon state. ``None`` indicates to use default timeout.
        """
        return task.run('set_state', beacon_state, timeout=timeout)


class DefaultBeaconManager(BeaconInterface):
    """Interface for beacon-related actions."""
    pass
