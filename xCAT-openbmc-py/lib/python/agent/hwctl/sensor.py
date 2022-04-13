#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class SensorInterface(object):
    """Interface for sensor-related actions."""
    interface_type = 'sensor'
    version = '1.0'

    def get_sensor_info(self, task, sensor_type=None):
        """Return the sensor info of the task's nodes.

        :param sensor_type: type of sensor info want to get.
        :param task: a Task instance containing the nodes to act on.
        :return: sensor info list
        """
        return task.run('get_sensor_info', sensor_type)

    def get_beacon_info(self, task, display_type='full'):
        """Return the beacon info of the task's nodes.

        :param task: type of display to produce - full (rvitals leds) or compact (rbeacon stat)
        :param task: a Task instance containing the nodes to act on.
        :return: beacon info list
        """
        return task.run('get_beacon_info', display_type)

class DefaultSensorManager(SensorInterface):
    """Interface for sensor-related actions."""
    pass
