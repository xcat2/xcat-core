#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class SensorInterface(object):
    """Interface for sensor-related actions."""
    interface_type = 'sensor'
    version = '1.0'

    def get_sensor_info(self, task, sensor_type):
        """Return the sensor info of the task's nodes.

        :param sensor_type: type of sensor info want to get.
        :param task: a Task instance containing the nodes to act on.
        :return: sensor info list
        """
        return task.run('get_info', sensor_type) 

class DefaultSensorManager(SensorInterface):
    """Interface for sensor-related actions."""
    pass
