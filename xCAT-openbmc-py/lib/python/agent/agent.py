#!/usr/bin/env python3
# -*- encoding: utf-8 -*-
from __future__ import print_function
import argparse
import sys
from xcatagent import server


class AgentShell(object):
    def get_base_parser(self):
        parser = argparse.ArgumentParser(
            prog='xcatagent',
            add_help=False,
            formatter_class=HelpFormatter,
        )
        parser.add_argument('-h', '--help',
                            action='store_true',
                            help=argparse.SUPPRESS,
                            )
        parser.add_argument('--standalone',
                            help="Start xcat agent as a standalone service, "
                                 "mostly work for test purpose. ",
                            action='store_true')
        parser.add_argument('--sock',
                            help="The unix domain sock file to communicate "
                                 "with the client",
                            default='/var/run/xcat/agent.sock',
                            type=str)
        parser.add_argument('--lockfile',
                            help="The lock file to communicate "
                                 "with the xcat",
                            default='/var/lock/xcat/agent.lock',
                            type=str)
        return parser

    def do_help(self, args):
        self.parser.print_help()

    def main(self, argv):
        self.parser = self.get_base_parser()
        (options, args) = self.parser.parse_known_args(argv)

        if options.help:
            self.do_help(options)
            return 0

        s = server.Server(options.sock, options.standalone, options.lockfile)
        s.start()

class HelpFormatter(argparse.HelpFormatter):
    def start_section(self, heading):
        # Title-case the headings
        heading = '%s%s' % (heading[0].upper(), heading[1:])
        super(HelpFormatter, self).start_section(heading)


if __name__ == '__main__':
    AgentShell().main(sys.argv[1:])
