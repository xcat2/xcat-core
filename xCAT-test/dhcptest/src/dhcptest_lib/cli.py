"""Command line interface.

    dhcptest run      [-i IFACE] [options] CONF [CONF...]
    dhcptest validate CONF [CONF...]
    dhcptest list     CONF [CONF...]
    dhcptest discover -i IFACE [options]

`validate` and `list` need neither root nor scapy, which makes them the safe
entry points for a checkout-only CI job.
"""

import argparse
import sys

from . import config, machine, report
from .errors import (DhcpTestError, EXIT_CONFIG, EXIT_FAILED, EXIT_OK)


def build_parser():
    parser = argparse.ArgumentParser(
        prog="dhcptest",
        description="Test a DHCP server from the wire, one declarative "
                    ".conf file at a time.")
    subparsers = parser.add_subparsers(dest="command")

    run = subparsers.add_parser(
        "run", help="execute scenarios against a real DHCP server")
    _add_conf_arguments(run)
    _add_wire_arguments(run)
    run.add_argument("--format", default="tap",
                     choices=sorted(report.REPORTERS),
                     help="output format (default: tap)")
    run.add_argument("--pcap", metavar="FILE",
                     help="write every frame sent and received to FILE")
    run.add_argument("-s", "--scenario", action="append", default=[],
                     metavar="NAME", help="run only this scenario (repeatable)")

    validate = subparsers.add_parser(
        "validate", help="parse and check .conf files without any network I/O")
    _add_conf_arguments(validate)

    listing = subparsers.add_parser(
        "list", help="list the scenarios and steps in .conf files")
    _add_conf_arguments(listing)

    discover = subparsers.add_parser(
        "discover", help="send one DISCOVER and print what comes back")
    _add_wire_arguments(discover)
    discover.add_argument("--arch", metavar="N",
                          help="client architecture, DHCP option 93 "
                               "(e.g. 0x0000 for BIOS, 0x000b for aarch64)")
    discover.add_argument("--vendor-class", metavar="STRING",
                          help="DHCP option 60")
    discover.add_argument("--user-class", metavar="STRING",
                          help="DHCP option 77")
    discover.add_argument("--request-options", metavar="LIST",
                          help="DHCP option 55, e.g. '1,3,6,54,66,67'")
    discover.add_argument("--format", default="pretty",
                          choices=sorted(report.REPORTERS))
    discover.add_argument("--pcap", metavar="FILE")

    return parser


def _add_conf_arguments(parser):
    parser.add_argument("conf", nargs="+", metavar="CONF",
                        help="a .conf file in INI syntax")
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                        dest="settings",
                        help="define ${KEY} for substitution (repeatable)")


def _add_wire_arguments(parser):
    parser.add_argument("-i", "--interface", metavar="IFACE",
                        help="network interface to bind to")
    parser.add_argument("--mac", metavar="ADDR",
                        help="client MAC: 'random' (default), 'iface', "
                             "or an explicit address")
    parser.add_argument("--timeout", type=float, metavar="SECS",
                        help="per-attempt reply timeout (default: 2)")
    parser.add_argument("--retries", type=int, metavar="N",
                        help="attempts per step (default: 3)")
    parser.add_argument("-v", "--verbose", action="count", default=0,
                        help="-v for progress, -vv for a per-packet trace")


def parse_settings(pairs):
    settings = {}
    for pair in pairs:
        if "=" not in pair:
            raise DhcpTestError("--set needs KEY=VALUE, got %r" % (pair,))
        key, _, value = pair.partition("=")
        settings[key.strip()] = value
    return settings


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return EXIT_CONFIG

    try:
        if args.command == "validate":
            return command_validate(args)
        if args.command == "list":
            return command_list(args)
        if args.command == "run":
            return command_run(args)
        if args.command == "discover":
            return command_discover(args)
    except DhcpTestError as exc:
        sys.stderr.write("dhcptest: %s\n" % (exc,))
        return exc.exit_code
    parser.print_help()
    return EXIT_CONFIG


def command_validate(args):
    # Raw: a file is checked in a checkout, where no value has been supplied
    # for %(name)s yet, so interpolating it here would fail every time.
    settings = parse_settings(args.settings)
    scenarios, _ = config.load(args.conf, settings, raw=True)
    problems = []
    for scenario in scenarios:
        problems.extend(machine.validate_scenario(scenario))

    for problem in problems:
        sys.stderr.write("dhcptest: %s\n" % (problem,))
    if problems:
        return EXIT_CONFIG

    needed = sorted(machine.required_variables(scenarios) - set(settings))
    sys.stdout.write("%d scenario(s) OK in %d file(s)\n"
                     % (len(scenarios), len(args.conf)))
    if needed:
        sys.stdout.write("required variables: %s\n" % (", ".join(needed),))
    return EXIT_OK


def command_list(args):
    scenarios, _ = config.load(args.conf, parse_settings(args.settings), raw=True)
    for scenario in scenarios:
        sys.stdout.write("%s\n" % (scenario.name,))
        if scenario.description:
            sys.stdout.write("    %s\n" % (scenario.description,))
        sys.stdout.write("    source: %s\n" % (scenario.source,))
        if scenario.interface:
            sys.stdout.write("    interface: %s\n" % (scenario.interface,))
        for step in scenario.steps:
            sys.stdout.write("    step %-16s type=%-9s expect=%-6s asserts=%d\n"
                             % (step.name, step.type, step.expect or "-",
                                len(step.assertions)))
        needed = sorted(machine.required_variables([scenario]))
        if needed:
            sys.stdout.write("    requires: %s\n" % (", ".join(needed),))
    return EXIT_OK


def command_run(args):
    from . import runner            # imports scapy; keep it out of validate

    scenarios, _ = config.load(
        args.conf, parse_settings(args.settings), args.interface)
    if args.scenario:
        wanted = set(args.scenario)
        missing = wanted - set(s.name for s in scenarios)
        if missing:
            raise DhcpTestError(
                "no such scenario: %s" % (", ".join(sorted(missing)),))
        scenarios = [s for s in scenarios if s.name in wanted]

    problems = []
    for scenario in scenarios:
        problems.extend(machine.validate_scenario(scenario))
    if problems:
        for problem in problems:
            sys.stderr.write("dhcptest: %s\n" % (problem,))
        return EXIT_CONFIG

    reporter = report.make(args.format)
    options = runner.RunOptions(
        interface=args.interface,
        mac=args.mac,
        timeout=args.timeout,
        retries=args.retries,
        pcap=args.pcap,
        verbose=args.verbose,
    )
    return runner.run(scenarios, reporter, options)


def command_discover(args):
    from . import runner

    if not args.interface:
        raise DhcpTestError("discover needs -i/--interface")
    reporter = report.make(args.format)
    options = runner.RunOptions(
        interface=args.interface,
        mac=args.mac,
        timeout=args.timeout,
        retries=args.retries,
        pcap=args.pcap,
        verbose=args.verbose,
    )
    scenario = runner.ad_hoc_discover(
        interface=args.interface,
        client_arch=args.arch,
        vendor_class=args.vendor_class,
        user_class=args.user_class,
        request_options=args.request_options,
    )
    return runner.run([scenario], reporter, options)
