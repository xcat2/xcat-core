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

        led_label = 'LEDs'
        info_list = []
        # display_type == 'full'    for detailed output for 'rvitals leds' command
        # display_type == 'compact' for compact  output for 'rbeacon stat' command
        if display_type == 'compact':
            info_list.append('Front:%s Rear:%s' % (beacon_dict.get('front_id'), beacon_dict.get('rear_id', 'N/A')))
            return info_list

        for i in range(4):
            info_list.append('%s Fan%s: %s' % (led_label, i, beacon_dict.get('fan' + str(i), 'N/A')))

        led_types = ('Fault', 'Identify', 'Power')
        for i in ('Front', 'Rear'):
            for led_type in led_types:
                tmp_type = led_type.lower()
                if led_type == 'Identify':
                    tmp_type = 'id'
                key_type = i.lower() + '_' + tmp_type
                info_list.append('%s %s %s: %s' % (led_label, i, led_type, beacon_dict.get(key_type, 'N/A')))

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


