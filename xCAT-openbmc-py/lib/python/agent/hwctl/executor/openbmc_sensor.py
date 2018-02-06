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


SENSOR_TYPE_UNIT = {
    "altitude" : "Meters",
    "fanspeed" : "RPMS",
    "temp"     : "DegreesC",
    "voltage"  : "Volts",
    "wattage"  : "Watts",
}

SENSOR_POWER_UNITS = ("Amperes", "Joules", "Watts")


class OpenBMCSensorTask(ParallelNodesCommand):
    """Executor for sensor-related actions."""

    def get_info(self, sensor_type, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        sensor_info = []
        try:
            obmc.login()
            sensor_info_dict = obmc.get_sensor_info()

            if sensor_type == 'all':
                for sensor_key in sensor_info_dict:
                    sensor_info += sensor_info_dict[sensor_key]
                sensor_info = utils.sort_string_with_numbers(sensor_info)
                beacon_info = obmc.get_beacon_info()
                sensor_info += beacon_info
            elif sensor_type == 'power':
                for sensor_key in sensor_info_dict:
                    if sensor_key in SENSOR_POWER_UNITS:
                        sensor_info += sensor_info_dict[sensor_key]
                sensor_info = utils.sort_string_with_numbers(sensor_info)
            else:
                sensor_unit = SENSOR_TYPE_UNIT[sensor_type]
                if sensor_unit in sensor_info_dict:
                    sensor_info += sensor_info_dict[sensor_unit]
                    sensor_info = utils.sort_string_with_numbers(sensor_info)

            if not sensor_info:
                sensor_info = ['No attributes returned from the BMC.']

            for info in sensor_info:
                self.callback.info( '%s: %s' % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.info('%s: %s'  % (node, e.message))

        return sensor_info
                

