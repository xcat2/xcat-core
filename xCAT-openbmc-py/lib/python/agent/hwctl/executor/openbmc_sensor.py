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

    def _get_beacon_info(self, beacon_dict, display_type='full'):

        info_list = []
        # display_type == 'full'    for detailed output for 'rvitals leds' command
        # display_type == 'compact' for compact  output for 'rbeacon stat' command
        if display_type == 'compact':
            info_list.append('Front:%s Rear:%s' % (beacon_dict.get('front_id'), beacon_dict.get('rear_id', 'N/A'))) 
            return info_list
        info_list.append('Front . . . . . : Power:%s Fault:%s Identify:%s' %
                         (beacon_dict.get('front_power', 'N/A'),
                          beacon_dict.get('front_fault', 'N/A'),
                          beacon_dict.get('front_id', 'N/A')))
        if (beacon_dict.get('fan0', 'N/A') == 'Off' and beacon_dict.get('fan1', 'N/A') == 'Off' and
            beacon_dict.get('fan2', 'N/A') == 'Off' and beacon_dict.get('fan3', 'N/A') == 'Off'):
            info_list.append('Front Fans  . . : No LEDs On')
        else:
            info_list.append('Front Fans  . . : fan0:%s fan1:%s fan2:%s fan3:%s' %
                             (beacon_dict.get('fan0', 'N/A'), beacon_dict.get('fan1', 'N/A'),
                              beacon_dict.get('fan2', 'N/A'), beacon_dict.get('fan3', 'N/A')))
        info_list.append('Rear  . . . . . : Power:%s Fault:%s Identify:%s' %
                         (beacon_dict.get('rear_power', 'N/A'),
                          beacon_dict.get('rear_fault', 'N/A'),
                          beacon_dict.get('rear_id', 'N/A')))
        return info_list
        

    def get_sensor_info(self, sensor_type, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        sensor_info = []
        try:
            obmc.login()
            sensor_info_dict = obmc.get_sensor_info()

            if sensor_type == 'all' or not sensor_type:
                for sensor_key in sensor_info_dict:
                    sensor_info += sensor_info_dict[sensor_key]
                sensor_info = utils.sort_string_with_numbers(sensor_info)
                beacon_dict = obmc.get_beacon_info()
                sensor_info += self._get_beacon_info(beacon_dict)
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
            self.callback.error(e.message, node)

        return sensor_info

    def get_beacon_info(self, display_type, **kw):

        node = kw['node']
        obmc = openbmc.OpenBMCRest(name=node, nodeinfo=kw['nodeinfo'], messager=self.callback,
                                   debugmode=self.debugmode, verbose=self.verbose)

        beacon_info = []
        try:
            obmc.login()
            beacon_dict = obmc.get_beacon_info()
            beacon_info = self._get_beacon_info(beacon_dict, display_type)

            if not beacon_info:
                beacon_info = ['No attributes returned from the BMC.']

            for info in beacon_info:
                self.callback.info( '%s: %s' % (node, info))

        except (SelfServerException, SelfClientException) as e:
            self.callback.error(e.message, node)

        return beacon_info
                

