"""Reading declarative .conf files with configparser.

Layout of a file::

    [vars]                  optional; %(name)s values, overridable with --set
    [defaults]              optional; step keys applied to every step
    [scenario <name>]       starts a scenario
    [step <name>]           belongs to the scenario above it

Variables use configparser's own `BasicInterpolation`: `%(name)s` is resolved
by the library, out of the `[vars]` section and of anything passed with
`--set`. `BasicInterpolation` gives `$` no meaning, so `$offer.address` reaches
us untouched -- and that one has to, because its value is a reply that has not
arrived yet when the file is read. `ExtendedInterpolation` would have taken
`${...}` for itself and then raised on the bare `$`.

The interpolation is applied per value in `_items()` rather than through the
parser, to keep variable names out of the sections' key space -- see the note
on `INTERPOLATION` below.

Unknown keys are a hard error rather than a silent skip, matching `xcattest`,
where an unrecognised `check:` fails the case instead of passing it.
"""

import configparser
import os

from . import assertions as assertions_mod
from . import machine, netutil, subst
from .errors import ConfigError
from .model import Scenario, Step

#: Keys accepted in a `[scenario ...]` section.
SCENARIO_KEYS = frozenset(["description", "interface"])

#: Keys that control how a step is run.
STEP_CONTROL_KEYS = frozenset([
    "type", "expect", "timeout", "retries", "mac", "xid", "broadcast_flag",
    "min_size", "collect_extra", "select", "arp_respond", "assert",
    "assert_all", "duration", "server", "dest_mac",
])

#: Keys that put something into the packet.
STEP_FIELD_KEYS = frozenset([
    "ciaddr", "giaddr", "requested_address", "server_id", "lease_time",
    "hostname", "client_id", "vendor_class", "user_class", "user_class_form",
    "client_arch", "client_ndi", "client_uuid", "max_message_size",
    "request_options", "vendor_specific", "ipxe_options", "relay",
    "bootfile", "sname",
])

STEP_KEYS = STEP_CONTROL_KEYS | STEP_FIELD_KEYS

#: Keys `[defaults]` may carry: step keys, minus the ones that must be per-step.
DEFAULTS_KEYS = (STEP_KEYS - frozenset(["type", "assert", "assert_all"])) | \
    frozenset(["interface"])

BOOLEAN_TRUE = frozenset(["1", "yes", "true", "on"])
BOOLEAN_FALSE = frozenset(["0", "no", "false", "off"])


def load(paths, overrides=None, interface=None, raw=False):
    """Read every path and return `(scenarios, variables)`.

    With `raw`, `%(name)s` is left in place instead of being interpolated, so
    `validate` can check a file in a checkout where no value has been supplied
    for it yet.
    """
    scenarios = []
    variables = {}
    for path in paths:
        file_scenarios, file_vars = load_file(path, overrides, raw)
        scenarios.extend(file_scenarios)
        variables.update(file_vars)
    variables.update(overrides or {})

    if interface:
        scenarios = [
            Scenario(s.name, s.description, interface, s.steps, s.source)
            for s in scenarios
        ]

    _reject_duplicate_scenarios(scenarios)
    return scenarios, variables


def load_file(path, overrides=None, raw=False):
    """Read one .conf file into `(scenarios, variables)`."""
    if not os.path.isfile(path):
        raise ConfigError("no such file", path)

    parser = configparser.ConfigParser(
        interpolation=None,
        inline_comment_prefixes=(";",),
        delimiters=("=",),
    )
    parser.optionxform = str.lower
    try:
        with open(path) as handle:
            parser.read_file(handle, source=path)
    except configparser.Error as exc:
        raise ConfigError(str(exc), path)

    # `[vars]` supplies the values, `--set` overrides them, so one file can
    # carry sensible defaults and a run can point it at another network.
    variables = dict(parser["vars"]) if parser.has_section("vars") else {}
    variables.update(overrides or {})

    scenarios = []
    defaults = {}
    current = None
    steps = []

    for section in parser.sections():
        items = _items(parser, section, path, raw, variables)
        kind, _, name = section.partition(" ")
        kind = kind.strip().lower()
        name = name.strip()
        where = "%s [%s]" % (path, section)

        if section.lower() == "vars":
            continue                      # read above, into `variables`

        if section.lower() == "defaults":
            _reject_unknown(items, DEFAULTS_KEYS, where)
            defaults = items
            continue

        if kind == "scenario":
            if not name:
                raise ConfigError("a [scenario] section needs a name", where)
            if current is not None:
                scenarios.append(_build_scenario(current, steps, defaults, path))
            _reject_unknown(items, SCENARIO_KEYS, where)
            current = (name, items)
            steps = []
            continue

        if kind == "step":
            if current is None:
                raise ConfigError(
                    "a [step] section must follow a [scenario] section", where)
            if not name:
                raise ConfigError("a [step] section needs a name", where)
            steps.append(_build_step(name, items, defaults, where))
            continue

        raise ConfigError(
            "unknown section; expected [vars], [defaults], [scenario <name>] "
            "or [step <name>]", where)

    if current is not None:
        scenarios.append(_build_scenario(current, steps, defaults, path))
    elif steps:
        raise ConfigError("steps without a scenario", path)

    if not scenarios:
        raise ConfigError("no [scenario ...] section found", path)

    return scenarios, variables


def _build_scenario(current, steps, defaults, path):
    name, items = current
    if not steps:
        raise ConfigError("scenario %r has no steps" % (name,), path)
    interface = items.get("interface") or defaults.get("interface")
    return Scenario(
        name=name,
        description=items.get("description", ""),
        interface=interface,
        steps=steps,
        source=path,
    )


def _build_step(name, items, defaults, where):
    _reject_unknown(items, STEP_KEYS, where)

    merged = {}
    for key, value in defaults.items():
        if key in STEP_KEYS:
            merged[key] = value
    merged.update(items)

    step_type = merged.get("type")
    if not step_type:
        raise ConfigError("step %r has no type=" % (name,), where)
    step_type = step_type.strip().lower()
    if step_type not in machine.known_step_types():
        raise ConfigError(
            "unknown step type %r (known: %s)"
            % (step_type, ", ".join(sorted(machine.known_step_types()))), where)

    expect = (merged.get("expect") or "").strip().lower() or None
    timeout = _float(merged.get("timeout"), 2.0, "timeout", where)
    retries = _int(merged.get("retries"), 3, "retries", where)

    # Validate a literal MAC now so a typo fails offline. A $reference is a
    # reply that has not arrived; a %(name)s survives only a raw load, where
    # the values were deliberately not supplied. Neither can be checked here.
    mac = merged.get("mac", "")
    if mac not in ("random", "iface", "") and "$" not in mac \
            and not subst.variables(mac):
        netutil.normalise_mac(mac)

    parsed = assertions_mod.parse_block(merged.pop("assert", ""), where)
    parsed_all = assertions_mod.parse_block(merged.pop("assert_all", ""), where)

    for key in ("type", "expect", "timeout", "retries"):
        merged.pop(key, None)

    return Step(
        name=name,
        type=step_type,
        expect=expect,
        params=merged,
        assertions=parsed,
        assertions_all=parsed_all,
        timeout=timeout,
        retries=retries,
        source=where,
    )


#: configparser's own variable syntax, `%(name)s`. The parser is built with
#: `interpolation=None` and this is applied by hand, per value, because both of
#: the built-in ways of supplying the values -- DEFAULTSECT and `get(vars=...)`
#: -- also make each variable an *option*, so `--set user_class=xNBA` would
#: overwrite the step key of the same name. Interpolating explicitly keeps the
#: two namespaces apart: variables are only ever read through `%(...)s`.
INTERPOLATION = configparser.BasicInterpolation()


def _items(parser, section, path, raw, variables=None):
    """One section's keys, with `%(name)s` resolved out of `variables`."""
    items = {}
    for key in parser.options(section):
        value = parser.get(section, key, raw=True)
        if raw:
            items[key] = value
            continue
        try:
            items[key] = INTERPOLATION.before_get(
                parser, section, key, value, variables or {})
        except configparser.InterpolationMissingOptionError as exc:
            raise ConfigError(
                "%%(%s)s is not defined; pass --set %s=<value>"
                % (exc.reference, exc.reference), "%s [%s]" % (path, section))
        except configparser.Error as exc:
            raise ConfigError(str(exc), "%s [%s]" % (path, section))
    return items


def _reject_unknown(items, allowed, where):
    unknown = sorted(set(items) - set(allowed))
    if unknown:
        raise ConfigError(
            "unknown key(s): %s (allowed: %s)"
            % (", ".join(unknown), ", ".join(sorted(allowed))), where)


def _reject_duplicate_scenarios(scenarios):
    seen = {}
    for scenario in scenarios:
        if scenario.name in seen:
            raise ConfigError(
                "scenario %r is defined in both %s and %s"
                % (scenario.name, seen[scenario.name], scenario.source))
        seen[scenario.name] = scenario.source


def _float(value, default, key, where):
    if value is None or value == "":
        return default
    try:
        return float(value)
    except ValueError:
        raise ConfigError("%s= must be a number, got %r" % (key, value), where)


def _int(value, default, key, where):
    if value is None or value == "":
        return default
    try:
        return int(value, 0) if isinstance(value, str) else int(value)
    except ValueError:
        raise ConfigError("%s= must be an integer, got %r" % (key, value), where)


def to_bool(value, default=False):
    if value is None or value == "":
        return default
    text = str(value).strip().lower()
    if text in BOOLEAN_TRUE:
        return True
    if text in BOOLEAN_FALSE:
        return False
    raise ConfigError("expected a yes/no value, got %r" % (value,))
