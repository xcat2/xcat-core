"""Command line interface.

    blackboxtest run      [options] CONF [CONF...]   # execute scenarios
    blackboxtest validate CONF [CONF...]             # check offline
    blackboxtest list     CONF [CONF...]             # show what a file does

`validate` and `list` need no root, no network, no scapy and no client
program, so they run in a checkout.
"""

import argparse
import sys

from . import config, report, validate
from .errors import EXIT_CONFIG, EXIT_OK, BlackboxError


def build_parser():
    parser = argparse.ArgumentParser(
        prog="blackboxtest",
        description="Ask a management node what a booting node asks, and "
                    "check the answers.")
    sub = parser.add_subparsers(dest="command")

    run = sub.add_parser("run", help="execute scenarios against a real server")
    _conf_arguments(run)
    run.add_argument("-i", "--interface", metavar="IFACE",
                     help="interface the DHCP steps send from")
    run.add_argument("-b", "--bind", metavar="ADDR",
                     help="source address of every step that sets no bind=")
    run.add_argument("--timeout", type=float, metavar="SECS",
                     help="per-attempt timeout, over the files")
    run.add_argument("--retries", type=int, metavar="N",
                     help="attempts per step, over the files")
    run.add_argument("-s", "--scenario", action="append", default=[],
                     metavar="NAME", help="run only this scenario (repeatable)")
    run.add_argument("-v", "--verbose", action="count", default=0,
                     help="print each reply to stderr")

    _conf_arguments(sub.add_parser("validate", help="check .conf files offline"))
    _conf_arguments(sub.add_parser("list", help="show scenarios and steps"))
    return parser


def _conf_arguments(parser):
    parser.add_argument("conf", nargs="+", metavar="CONF")
    parser.add_argument("--set", action="append", default=[], dest="settings",
                        metavar="KEY=VALUE",
                        help="define %%(KEY)s (repeatable)")


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help()
        return EXIT_CONFIG
    try:
        settings = {}
        for pair in args.settings:
            key, sep, value = pair.partition("=")
            if not sep:
                raise BlackboxError("--set needs KEY=VALUE, got %r" % (pair,))
            settings[key.strip()] = value
        return COMMANDS[args.command](args, settings)
    except BlackboxError as exc:
        sys.stderr.write("blackboxtest: %s\n" % (exc,))
        return exc.exit_code


def _problems(scenarios):
    problems = [p for s in scenarios for p in validate.scenario_problems(s)]
    for problem in problems:
        sys.stderr.write("blackboxtest: %s\n" % (problem,))
    return problems


def command_validate(args, settings):
    # Raw: in a checkout no value has been supplied for %(name)s yet.
    scenarios = config.load(args.conf, settings, raw=True)
    if _problems(scenarios):
        return EXIT_CONFIG
    sys.stdout.write("%d scenario(s) OK in %d file(s)\n"
                     % (len(scenarios), len(args.conf)))
    needed = sorted(validate.required_variables(scenarios) - set(settings))
    if needed:
        sys.stdout.write("required variables: %s\n" % (", ".join(needed),))
    return EXIT_OK


def command_list(args, settings):
    for scenario in config.load(args.conf, settings, raw=True):
        sys.stdout.write("%s\n" % (scenario.name,))
        if scenario.description:
            sys.stdout.write("    %s\n" % (scenario.description,))
        sys.stdout.write("    source: %s\n" % (scenario.source,))
        for step in scenario.steps:
            sys.stdout.write("    step %-16s type=%-12s expect=%-6s asserts=%d\n"
                             % (step.name, step.type, step.expect or "-",
                                len(step.assertions)))
        needed = sorted(validate.required_variables([scenario]))
        if needed:
            sys.stdout.write("    requires: %s\n" % (", ".join(needed),))
    return EXIT_OK


def command_run(args, settings):
    from . import runner          # opens sockets and spawns clients

    scenarios = config.load(args.conf, settings)
    if args.scenario:
        missing = set(args.scenario) - set(s.name for s in scenarios)
        if missing:
            raise BlackboxError("no such scenario: %s"
                                % (", ".join(sorted(missing)),))
        scenarios = [s for s in scenarios if s.name in args.scenario]
    if _problems(scenarios):
        return EXIT_CONFIG
    options = runner.RunOptions(interface=args.interface, bind=args.bind,
                                timeout=args.timeout, retries=args.retries,
                                verbose=args.verbose)
    return runner.run(scenarios, report.TapReporter(), options)


COMMANDS = {"run": command_run, "validate": command_validate,
            "list": command_list}
