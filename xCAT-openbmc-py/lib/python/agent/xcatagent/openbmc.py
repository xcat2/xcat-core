#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

import os
import time
import sys
import gevent
import re
from docopt import docopt,DocoptExit

from common import utils
from common import exceptions as xcat_exception
from hwctl.openbmc.openbmc_beacon import OpenBMCBeaconTask
from hwctl.openbmc.openbmc_setboot import OpenBMCBootTask
from hwctl.openbmc.openbmc_flash import OpenBMCFlashTask
from hwctl.openbmc.openbmc_inventory import OpenBMCInventoryTask
from hwctl.openbmc.openbmc_power import OpenBMCPowerTask
from hwctl.openbmc.openbmc_sensor import OpenBMCSensorTask
from hwctl.openbmc.openbmc_eventlog import OpenBMCEventlogTask
from hwctl.beacon import DefaultBeaconManager
from hwctl.setboot import DefaultBootManager
from hwctl.flash import DefaultFlashManager
from hwctl.inventory import DefaultInventoryManager
from hwctl.power import DefaultPowerManager
from hwctl.sensor import DefaultSensorManager
from hwctl.bmcconfig import DefaultBmcConfigManager
from hwctl.eventlog import DefaultEventlogManager

from xcatagent import base
import logging
logger = logging.getLogger('xcatagent')
try:
    if not logger.handlers:
        utils.enableSyslog('xcat.agent')
except:
    pass

HTTP_PROTOCOL = "https://"
PROJECT_URL = "/xyz/openbmc_project"

RESULT_OK = 'ok'
RESULT_FAIL = 'fail'

DEBUGMODE = False
VERBOSE = False

all_nodes_result = {}

# global variables of rbeacon
BEACON_OPTIONS = ('on', 'off', 'stat')

RSPCONFIG_GET_OPTIONS = ['ip','ipsrc','netmask','gateway','vlan','ntpservers','hostname','bootmode','thermalmode','autoreboot','powersupplyredundancy','powerrestorepolicy', 'timesyncmethod']

RSPCONFIG_SET_OPTIONS = {
    'ip':'.*',
    'netmask':'.*',
    'gateway':'.*',
    'vlan':'\d+',
    'hostname':"\*|.*",
    'ntpservers':'.*',
    'autoreboot':"^0|1$",
    'powersupplyredundancy':"^enabled$|^disabled$",
    'powerrestorepolicy':"^always_on$|^always_off$|^restore$",
    'bootmode':"^regular$|^safe$|^setup$",
    'thermalmode':"^default$|^custom$|^heavy_io$|^max_base_fan_floor$",
    'admin_passwd':'.*,.*',
    'timesyncmethod':'^ntp$|^manual$',
}
RSPCONFIG_USAGE = """
Handle rspconfig operations.

Usage:
       rspconfig -h|--help
       rspconfig dump [[-l|--list] | [-g|--generate] | [-c|--clear --id <arg>] | [-d|--download --id <arg>]] [-V|--verbose]
       rspconfig gard -c|--clear [-V|--verbose]
       rspconfig sshcfg [-V|--verbose]
       rspconfig ip=dhcp [-V|--verbose]
       rspconfig get [<args>...] [-V|--verbose]
       rspconfig set [<args>...] [-V|--verbose]

Options:
  -V,--verbose        Show verbose message
  -l,--list           List are dump files
  -g,--generate       Trigger a new dump file
  -c,--clear          To clear the specified dump file
  -d,--download       To download specified dump file
  --id <arg>          The dump file id or 'all'

The supported attributes to get are: %s

The supported attributes and its values to set are:
   ip=<ip address> netmask=<mask> gateway=<gateway> [vlan=<vlanid>]
   hostname=*|<string>
   autoreboot={0|1}
   powersupplyredundancy={enabled|disabled}
   powerrestorepolicy={always_on|always_off|restore}
   timesyncmethod={ntp|manual}
""" % RSPCONFIG_GET_OPTIONS

#global variables of rinv
INVENTORY_OPTIONS = ('all', 'cpu', 'dimm', 'firm', 'model', 'serial')

# global variables of rpower
POWER_REBOOT_OPTIONS = ('boot', 'reset')
POWER_SET_OPTIONS = ('on', 'off', 'bmcreboot', 'softoff')
POWER_GET_OPTIONS = ('bmcstate', 'state', 'stat', 'status')

# global variables of rsetboot
SETBOOT_GET_OPTIONS = ('stat', '')
SETBOOT_SET_OPTIONS = ('cd', 'def', 'default', 'hd', 'net')

# global variables of rvitals
VITALS_OPTIONS = ('all', 'altitude', 'fanspeed', 'leds', 'power',
                  'temp', 'voltage', 'wattage')

# global variables of reventlog
EVENTLOG_OPTIONS = ('list', 'clear', 'resolved')

class OpenBMCManager(base.BaseManager):
    def __init__(self, messager, cwd, nodes=None, envs=None):
        super(OpenBMCManager, self).__init__(messager, cwd)
        self.nodes = nodes
        self.debugmode = (envs and envs.get('debugmode')) or None
        #TODO, remove the global variable DEBUGMODE
        global DEBUGMODE
        DEBUGMODE = envs['debugmode']

        if self.debugmode:
            logger.setLevel(logging.DEBUG)

    def rbeacon(self, nodesinfo, args):

        # 1, parse args
        rbeacon_usage = """
        Usage:
            rbeacon [-V|--verbose] [on|off|stat]

        Options:
            -V --verbose   rbeacon verbose mode.
        """

        try:
            opts = docopt(rbeacon_usage, argv=args)

            self.verbose = opts.pop('--verbose')
            action = [k for k,v in opts.items() if v][0]
        except Exception as e:
            self.messager.error("Failed to parse arguments for rbeacon: %s" % args)
            return

        # 2, validate the args
        if action is None:
            self.messager.error("Subcommand for rbeacon was not specified")
            return

        if action not in BEACON_OPTIONS:
            self.messager.error("Not supported subcommand for rbeacon: %s" % action)
            return

        # 3, run the subcommands
        if action == 'stat':
            runner = OpenBMCSensorTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)

            DefaultSensorManager().get_beacon_info(runner, display_type='compact')
        else:
            runner = OpenBMCBeaconTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
            DefaultBeaconManager().set_beacon_state(runner, beacon_state=action)

    def rflash(self, nodesinfo, args):

        # 1, parse agrs
        rflash_usage = """
        Usage:
            rflash [[-a|--activate <arg>] | [-c|--check <arg>] | [-d <arg> [--no-host-reboot]] | [--delete <arg>] | [-l|--list] |  [-u|--upload <arg>]] [-V|--verbose]

        Options:
            -V,--verbose          Show verbose message
            -a,--activate <arg>   Activate firmware
            -c,--check            Check firmware info
            -d <arg>              Upload and activate all firmware files under directory
            -l,--list             List firmware info
            -u,--upload <arg>     Upload firmware file
            --delete <arg>        Delete firmware
            --no-host-reboot      Not reboot host after activate
        """

        try:
            opts = docopt(rflash_usage, argv=args)
            self.verbose = opts.pop('--verbose')
        except DocoptExit as e:
            self.messager.error("Failed to parse args by docopt: %s" % e)
            return
        except Exception as e:
            self.messager.error("Failed to parse arguments for rflash: %s" % args)
            return

        if opts['--check']:
            check_arg = None
            if opts['<arg>']:
                 check_arg = opts['<arg>']
            runner = runner = OpenBMCInventoryTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose, cwd=self.cwd[0])
            DefaultInventoryManager().get_firm_info(runner, check_arg)
            return

        runner = OpenBMCFlashTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose, cwd=self.cwd[0])
        if opts['--activate']:
            DefaultFlashManager().activate_firm(runner, opts['--activate'][0])
        elif opts['--list']:
            DefaultFlashManager().list_firm_info(runner)
        elif opts['-d']:
            DefaultFlashManager().flash_process(runner, opts['-d'], opts['--no-host-reboot'])
        elif opts['--delete']:
            DefaultFlashManager().delete_firm(runner, opts['--delete'])
        elif opts['--upload']:
            DefaultFlashManager().upload_firm(runner, opts['--upload'][0])

    def rinv(self, nodesinfo, args):

        # 1, parse agrs
        if not args or (len(args) == 1 and args[0] in ['-V', '--verbose']):
            args.append('all')

        # We are not using a standard Python options (with - or --) because
        # of that, we need to specify multiple identical choices. If only
        # one optional choice is specified - [all|cpu|dimm|firm|model|serial]
        # only one option at a time is allowed.
        # If specified - [all][cpu][dimm][firm][model][serial], then multiple
        # options are accepted, but they are required to be ordered,
        # e.g "cpu dimm" will work, but not "dimm cpu"
        rinv_usage = """
        Usage:
            rinv [-V|--verbose] [all|cpu|dimm|firm|model|serial] [all|cpu|dimm|firm|model|serial] [all|cpu|dimm|firm|model|serial] [all|cpu|dimm|firm|model|serial] [all|cpu|dimm|firm|model|serial]

        Options:
            -V --verbose   rinv verbose mode.
        """

        try:
            opts = docopt(rinv_usage, argv=args)

            self.verbose = opts.pop('--verbose')
            actions = [k for k,v in opts.items() if v]
        except Exception as e:
            self.messager.error("Failed to parse arguments for rinv: %s" % args)
            return

        # 2, validate the args
        run_firmware_inventory = 0
        run_other_inventory = 0
        for action in actions:
            # Check if each action is valid
            if action not in INVENTORY_OPTIONS:
                self.messager.error("Not supported subcommand for rinv: %s" % action)
                return
            else:
                # Valid action, set flags for which calls to make later
                if action == 'all':
                    run_firmware_inventory = 0
                    run_other_inventory = 1
                    break # get all inventory, nothing else matters
                elif action == 'firm':
                    run_firmware_inventory = 1
                else:
                    run_other_inventory = 1

        # 3, run the subcommands
        runner = OpenBMCInventoryTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
        if run_firmware_inventory == 1:
            DefaultInventoryManager().get_firm_info(runner)
            actions.remove('firm') # Remove element from actions array
        if run_other_inventory == 1:
            DefaultInventoryManager().get_inventory_info(runner, actions)

    def rpower(self, nodesinfo, args):

        # 1, parse args
        rpower_usage = """
        Usage:
            rpower [-V|--verbose] [on|off|softoff|reset|boot|bmcreboot|bmcstate|stat|state|status]

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
        runner = OpenBMCPowerTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
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

    def rspconfig(self, nodesinfo, args):

        from hwctl.openbmc.openbmc_bmcconfig import OpenBMCBmcConfigTask

        try:
            opts=docopt(RSPCONFIG_USAGE, argv=args)
        except DocoptExit as e:
            self.messager.error("Failed to parse args by docopt: %s" % e)
            return
        except Exception as e:
            self.messager.error("Failed to parse arguments for rspconfig: %s" % args)
            return
        self.verbose=opts.pop('--verbose')
        runner = OpenBMCBmcConfigTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)

        if opts['dump']:
            if opts['--list']:
                DefaultBmcConfigManager().dump_list(runner)
            elif opts['--generate']:
                DefaultBmcConfigManager().dump_generate(runner)
            elif opts['--clear']:
                DefaultBmcConfigManager().dump_clear(runner, opts['--id'])
            elif opts['--download']:
                DefaultBmcConfigManager().dump_download(runner, opts['--id'])
            else:
                DefaultBmcConfigManager().dump_process(runner)
        elif opts['gard']:
            if opts['--clear']:
                DefaultBmcConfigManager().gard_clear(runner)
        elif opts['sshcfg']:
            DefaultBmcConfigManager().set_sshcfg(runner)
        elif opts['ip=dhcp']:
            DefaultBmcConfigManager().set_ipdhcp(runner)
        elif opts['get']:
            unsupport_list=list(set(opts['<args>']) - set(RSPCONFIG_GET_OPTIONS))
            if len(unsupport_list) > 0:
                self.messager.error("Have unsupported option: %s" % unsupport_list)
                return
            else:
                DefaultBmcConfigManager().get_attributes(runner, opts['<args>'])
        elif opts['set']:
            rc=0
            for attr in opts['<args>']:
                k,v = attr.split('=')
                if k not in RSPCONFIG_SET_OPTIONS:
                    self.messager.error("The attribute %s is not support to set" % k)
                    rc=1
                elif not re.match(RSPCONFIG_SET_OPTIONS[k], v):
                    self.messager.error("The value %s is invalid for %s" %(v, k))
                    rc=1
            if rc:
                return
            else:
                DefaultBmcConfigManager().set_attributes(runner, opts['<args>'])
        else:
            self.messager.error("Failed to deal with rspconfig: %s" % args)

    def rsetboot(self, nodesinfo, args):

        # 1, parse args
        if not args:
            args = ['stat']

        rsetboot_usage = """
        Usage:
            rsetboot [-V|--verbose] [cd|def|default|hd|net|stat] [-p]

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
        runner = OpenBMCBootTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
        if action in SETBOOT_GET_OPTIONS:
            DefaultBootManager().get_boot_state(runner)
        else:
            DefaultBootManager().set_boot_state(runner, setboot_state=action, persistant=action_type)

    def rvitals(self, nodesinfo, args):

        # 1, parse agrs
        if not args or (len(args) == 1 and args[0] in ['-V', '--verbose']):
            args.append('all')

        rvitals_usage = """
        Usage:
            rvitals [-V|--verbose] [all|altitude|fanspeed|leds|power|temp|voltage|wattage]

        Options:
            -V --verbose   rvitals verbose mode.
        """

        try:
            opts = docopt(rvitals_usage, argv=args)

            self.verbose = opts.pop('--verbose')
            action = [k for k,v in opts.items() if v][0]
        except Exception as e:
            self.messager.error("Failed to parse arguments for rvitals: %s" % args)
            return

        # 2, validate the args
        if action not in VITALS_OPTIONS:
            self.messager.error("Not supported subcommand for rvitals: %s" % action)
            return

        # 3, run the subcommands
        runner = OpenBMCSensorTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
        if action == 'leds':
            DefaultSensorManager().get_beacon_info(runner)
        else:
            DefaultSensorManager().get_sensor_info(runner, action)

    def reventlog(self, nodesinfo, args):

        # 1, parse agrs
        if not args:
            args = ['all']

        reventlog_usage = """
        Usage:
            reventlog [-V|--verbose] resolved <id_list>
            reventlog [-V|--verbose] clear
            reventlog [-V|--verbose] list <number_of_records>

        Options:
            -V --verbose   eventlog verbose mode.
        """

        try:
            opts = docopt(reventlog_usage, argv=args)

            self.verbose = opts.pop('--verbose')
            action = [k for k,v in opts.items() if v][0]
        except Exception as e:
            self.messager.error("Failed to parse arguments for reventlog: %s" % args)
            return

        # 2, validate the args
        if action not in EVENTLOG_OPTIONS:
            self.messager.error("Not supported subcommand for reventlog: %s" % action)
            return

        # 3, run the subcommands
        runner = OpenBMCEventlogTask(nodesinfo, callback=self.messager, debugmode=self.debugmode, verbose=self.verbose)
        if action == 'clear':
            DefaultEventlogManager().clear_all_eventlog_records(runner)
        elif action == 'resolved':
            eventlog_id_list = opts.pop('<id_list>')
            DefaultEventlogManager().resolve_eventlog_records(runner, eventlog_id_list)
        elif action == 'list':
            eventlog_number_of_records = opts.pop('<number_of_records>')
            DefaultEventlogManager().get_eventlog_info(runner, eventlog_number_of_records)
        else:
            DefaultEventlogManager().get_eventlog_info(runner, "all")

