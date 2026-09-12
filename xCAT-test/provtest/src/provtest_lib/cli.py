"""Command line interface.

    provtest run      [options] CONF [CONF...]   # execute scenarios
    provtest validate CONF [CONF...]             # check offline
    provtest list     CONF [CONF...]             # show what a file does

`validate` and `list` need no root, no network and no client programs, so they
run in a checkout-only CI job -- which is where a typo in a field name or a
reference to a step that has not run yet should be caught, long before a
management node is involved.
"""

import argparse
import sys

from . import config, machine, report
from .errors import EXIT_CONFIG, EXIT_OK, ProvTestError


def build_parser():
    parser = argparse.ArgumentParser(
        prog="provtest",
        description="Drive the xCAT provision chain the way a booting node "
                    "does, one declarative .conf file at a time.")
    subparsers = parser.add_subparsers(dest="command")

    run = subparsers.add_parser(
        "run", help="execute scenarios against a real management node")
    _add_conf_arguments(run)
    run.add_argument("-b", "--bind", metavar="ADDR",
                     help="source address for every request; xcatd names a "
                          "client by the reverse lookup of this address")
    run.add_argument("--timeout", type=float, metavar="SECS",
                     help="per-attempt timeout (default: 5)")
    run.add_argument("--retries", type=int, metavar="N",
                     help="attempts per step (default: 2)")
    run.add_argument("--format", default="tap", choices=sorted(report.REPORTERS),
                     help="output format (default: tap)")
    run.add_argument("-s", "--scenario", action="append", default=[],
                     metavar="NAME", help="run only this scenario (repeatable)")
    run.add_argument("-v", "--verbose", action="count", default=0,
                     help="print each reply as it arrives")

    validate = subparsers.add_parser(
        "validate", help="parse and check .conf files without any network I/O")
    _add_conf_arguments(validate)

    listing = subparsers.add_parser(
        "list", help="list the scenarios and steps in .conf files")
    _add_conf_arguments(listing)

    return parser


def _add_conf_arguments(parser):
    parser.add_argument("conf", nargs="+", metavar="CONF",
                        help="a .conf file in INI syntax")
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                        dest="settings",
                        help="define %%(KEY)s for substitution (repeatable)")


def parse_settings(pairs):
    settings = {}
    for pair in pairs:
        if "=" not in pair:
            raise ProvTestError("--set needs KEY=VALUE, got %r" % (pair,))
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
    except ProvTestError as exc:
        sys.stderr.write("provtest: %s\n" % (exc,))
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
        sys.stderr.write("provtest: %s\n" % (problem,))
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
        for step in scenario.steps:
            sys.stdout.write("    step %-16s type=%-12s expect=%-4s asserts=%d\n"
                             % (step.name, step.type, step.expect or "ok",
                                len(step.assertions)))
        needed = sorted(machine.required_variables([scenario]))
        if needed:
            sys.stdout.write("    requires: %s\n" % (", ".join(needed),))
    return EXIT_OK


def command_run(args):
    from . import runner       # spawns clients and opens sockets; not for list

    scenarios, _ = config.load(args.conf, parse_settings(args.settings))
    if args.scenario:
        wanted = set(args.scenario)
        missing = wanted - set(s.name for s in scenarios)
        if missing:
            raise ProvTestError(
                "no such scenario: %s" % (", ".join(sorted(missing)),))
        scenarios = [s for s in scenarios if s.name in wanted]

    problems = []
    for scenario in scenarios:
        problems.extend(machine.validate_scenario(scenario))
    if problems:
        for problem in problems:
            sys.stderr.write("provtest: %s\n" % (problem,))
        return EXIT_CONFIG

    reporter = report.make(args.format)
    options = runner.RunOptions(
        bind=args.bind,
        timeout=args.timeout,
        retries=args.retries,
        verbose=args.verbose,
    )
    return runner.run(scenarios, reporter, options)
