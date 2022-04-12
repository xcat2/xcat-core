#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

import os
import gevent
import re
import sys
from docopt import docopt,DocoptExit

from common import utils
from common import exceptions as xcat_exception
from hwctl.redfish.redfish_power import RedfishPowerTask
from hwctl.redfish.redfish_setboot import RedfishBootTask
from hwctl.power import DefaultPowerManager
from hwctl.setboot import DefaultBootManager

from xcatagent import base
import logging
logger = logging.getLogger('xcatagent')
try:
    if not logger.handlers:
        utils.enableSyslog('xcat.agent')
except:
    pass

DEBUGMODE = False
VERBOSE = False

# global variables of rpower
POWER_REBOOT_OPTIONS = ('boot', 'reset')
POWER_SET_OPTIONS = ('on', 'off', 'bmcreboot')
POWER_GET_OPTIONS = ('bmcstate', 'state', 'stat', 'status')

# global variables of rsetboot
SETBOOT_GET_OPTIONS = ('stat', '')
SETBOOT_SET_OPTIONS = ('cd', 'def', 'default', 'floppy', 'hd', 'net', 'setup')

class RedfishManager(base.BaseManager):
    def __init__(self, messager, cwd, nodes=None, envs=None):
        super(RedfishManager, self).__init__(messager, cwd)
        self.nodes = nodes
        self.debugmode = (envs and envs.get('debugmode')) or None
        #TODO, remove the global variable DEBUGMODE
        global DEBUGMODE
        DEBUGMODE = envs['debugmode']

        if self.debugmode:
            logger.setLevel(logging.DEBUG)

    def rpower(self, nodesinfo, args):

        # 1, parse args
        rpower_usage = """
        Usage:
            rpower [-V|--verbose] [boot|bmcreboot|bmcstate|off|on|reset|stat|state|status]

        Options:
            -V --verbose   rpower verbose mode.
        """

        try:
            opts=docopt(rpower_usage, argv=args)

            self.verbose=opts.pop('--verbose')
            action=[k for k,v in opts.items() if v][0]
        except Exception as e:
            # It will not be here as perl has validation for args
            self.messager.error("Failed to parse arguments for rpower: %s" % args)
            return

        # 2, validate the args
        if action not in (POWER_GET_OPTIONS + POWER_SET_OPTIONS + POWER_REBOOT_OPTIONS):
            self.messager.error("Not supported subcommand for rpower: %s" % action)
            return

        # 3, run the subcommands
        runner = RedfishPowerTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
        if action == 'bmcstate':
            DefaultPowerManager().get_bmc_state(runner)
        elif action == 'bmcreboot':
            DefaultPowerManager().reboot_bmc(runner)
        elif action in POWER_GET_OPTIONS:
            DefaultPowerManager().get_power_state(runner)
        elif action in POWER_REBOOT_OPTIONS:
            DefaultPowerManager().reboot(runner, optype=action)
        else:
            DefaultPowerManager().set_power_state(runner, power_state=action)


    def rsetboot(self, nodesinfo, args):

        # 1, parse args
        if not args:
            args = ['stat']

        rsetboot_usage = """
        Usage:
            rsetboot [-V|--verbose] [cd|def|default|floppy||hd|net|stat|setup] [-p]

        Options:
            -V --verbose    rsetboot verbose mode.
            -p              persistant boot source.
        """

        try:
            opts = docopt(rsetboot_usage, argv=args)

            self.verbose = opts.pop('--verbose')
            action_type = opts.pop('-p')
            action = [k for k,v in opts.items() if v][0]
        except Exception as e:
            self.messager.error("Failed to parse arguments for rsetboot: %s" % args)
            return

        # 2, validate the args
        if action not in (SETBOOT_GET_OPTIONS + SETBOOT_SET_OPTIONS):
            self.messager.error("Not supported subcommand for rsetboot: %s" % action)
            return

        # 3, run the subcommands
        runner = RedfishBootTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
        if action in SETBOOT_GET_OPTIONS:
            DefaultBootManager().get_boot_state(runner)
        else:
            DefaultBootManager().set_boot_state(runner, setboot_state=action, persistant=action_type)
