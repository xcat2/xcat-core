#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class BootInterface(object):
    """Interface for setboot-related actions."""
    interface_type = 'setboot'
    version = '1.0'

    def get_boot_state(self, task):
        """Return the setboot state of the task's nodes.

        :param task: a Task instance containing the nodes to act on.
        :returns: a setboot state.
        """
        return task.run('get_state')

    def set_boot_state(self, task, setboot_state, persistant=False, timeout=None):
        """Set the setboot state of the task's nodes.

        :param task: a Task instance containing the nodes to act on.
        :param setboot_state: Any boot state allowed.
        :param persistant: whether set boot state persistant
        :param timeout: timeout (in seconds) positive integer (> 0) for any
          setboot state. ``None`` indicates to use default timeout.
        """
        return task.run('set_state', setboot_state, persistant, timeout=timeout)

class DefaultBootManager(BootInterface):
    """Interface for setboot-related actions."""
    pass
