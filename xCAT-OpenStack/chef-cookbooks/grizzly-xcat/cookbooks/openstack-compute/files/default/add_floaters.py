#! /usr/bin/env python
# vim: tabstop=4 shiftwidth=4 softtabstop=4

# Copyright 2013 AT&T Services, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import argparse
import subprocess

import netaddr

DESCRIPTION = "A `nova-manage floating create` and `quantum net create` wrapper."


class FloatingAddress(object):
    """
    A simple wrapper class for creating networks.  Often
    times there are reserved addresses at the start of a
    network, nova-manage doesn't account for this.

    TODO(retr0h): This should really be added to nova-manage.
    TODO(jaypipes): Instead of subprocess calls, just use the quantumclient
    """

    def __init__(self, args):
        self._args = args

    def nova_add_cidr(self, cidr):
        """
        Validates the provided cider address, and passes it to nova-manage.

        :param cidr: A string containing a valid CIDR address.
        """
        netaddr.IPNetwork(cidr)
        self.nova_add_floating(cidr)

    def nova_add_range(self, start, end):
        """
        Takes a start and end range, and creates individual host addresses.

        :param start: A string containing the start of the range.
        :param end: A string containing the end of the range.
        """
        ip_list = list(netaddr.iter_iprange(start, end))
        for ip in ip_list:
            self.nova_add_floating(ip)

    def nova_add_floating(self, ip):
        cmd = "nova-manage floating create --ip_range={0}".format(ip)
        if self._args.pool:
            cmd += ' --pool={0}'.format(self._args.pool)
        if self._args.interface:
            cmd += ' --interface={0}'.format(self._args.interface)

        subprocess.check_call(cmd, shell=True)

    def neutron_add_floating(self, cidr):

        # convert cidr string to IPNetwork object
        cidr = netaddr.IPNetwork(cidr)

        # ensure we have a public network and we only ever create one
        cmd = "NETLIST=$(quantum net-list -c name); if [ $? -eq 0 ]; then if ! echo $NETLIST | grep -q %s; then quantum net-create %s -- --router:external=True; fi; fi;" % (self._args.pool, self._args.pool)

        try:
            subprocess.check_call(cmd, shell=True)
        except:
            # we failed to query the quanutm api, we'll ignore this error
            # and return now so any surrounding chef runs can continue
            # since this script may actually be running on the quantum api
            print "ERROR: Failed to query the quantum api for the public network"
            return

        cmd = "quantum subnet-list -Fcidr -fcsv --quote=none | grep '%s'" % cidr

        res = subprocess.call(cmd, shell=True)
        if res == 0:
            # Subnet has already been created...
            return

        # calculate the start and end values
        ip_start = cidr.ip
        ip_end = netaddr.IPAddress(cidr.last-1)

        # create a new subnet
        cmd = "quantum subnet-create --allocation-pool start=%s,end=%s %s %s -- --enable_dhcp=False" % \
              (ip_start, ip_end, self._args.pool, cidr)
        subprocess.check_call(cmd, shell=True)


def parse_args():
    ap = argparse.ArgumentParser(description=DESCRIPTION)
    subparsers = ap.add_subparsers(help='sub-command help', dest='subparser_name')

    # create the parser for the "nova" command
    parser_nova = subparsers.add_parser('nova', help='Use Nova Backend')
    parser_nova.add_argument('--pool',
                             required=True,
                             help="Name of the floating pool")
    parser_nova.add_argument('--interface',
                             required=False,
                             help="Network interface to bring the floating "
                                  "addresses up on")
    group = parser_nova.add_mutually_exclusive_group(required=True)
    group.add_argument('--cidr',
                       help="A CIDR notation of addresses to add "
                            "(e.g. 192.168.0.0/24)")
    group.add_argument('--ip-range',
                       help="A range of addresses to add "
                            "(e.g. 192.168.0.10,192.168.0.50)")

    # create the parser for the "neutron command"
    parser_neutron = subparsers.add_parser('neutron', help='Use Neutron Backend')
    parser_neutron.add_argument('--cidr',
                                required=True,
                                help="A CIDR notation of addresses to add "
                                     "(e.g. 192.168.0.11/24 to start at .11 "
                                     "and end at .254)")
    parser_neutron.add_argument('--pool',
                                required=True,
                                help="Name of the public network")
    return ap.parse_args()

if __name__ == '__main__':
    args = parse_args()
    fa = FloatingAddress(args)

    if args.subparser_name == 'nova':
        if args.cidr:
            fa.nova_add_cidr(args.cidr)
        elif args.ip_range:
            start, end = args.ip_range.split(',')
            fa.nova_add_range(start, end)

    elif args.subparser_name == 'neutron':
        fa.neutron_add_floating(args.cidr)
