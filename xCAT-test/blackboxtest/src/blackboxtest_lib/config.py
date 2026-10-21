"""Reading .conf files with configparser.

    [vars]                  optional; %(name)s values, overridden by --set
    [defaults]              optional; step keys for every step that takes them
    [scenario <name>]       starts a scenario
    [step <name>]           belongs to the scenario above it

`%(name)s` is configparser's `BasicInterpolation`, applied per value here
rather than through the parser: both built-in ways of supplying the values
also make each variable an option, so `--set path=x` would overwrite the step
key `path`. `BasicInterpolation` gives `$` no meaning, so `$offer.address`
reaches the runner untouched.

Unknown keys are an error, as an unknown `check:` is in xcattest.
"""

import configparser
import os

from . import assertions, steps
from .errors import ConfigError
from .model import Scenario, Step

SCENARIO_KEYS = frozenset(["description", "interface"])

#: `type` and `assert` are per-step: a default type would turn a misspelt
#: `type=` into another protocol.
DEFAULTS_KEYS = frozenset(
    key for kind in steps.TYPES.values() for key in kind.keys
) - frozenset(["type", "assert"]) | frozenset(["interface"])

INTERPOLATION = configparser.BasicInterpolation()


def load(paths, overrides=None, raw=False):
    """Read every path into a list of scenarios.

    With `raw`, `%(name)s` stays in place, so `validate` can check a file for
    which no value has been supplied.
    """
    scenarios = []
    seen = {}
    for path in paths:
        for scenario in load_file(path, overrides or {}, raw):
            if scenario.name in seen:
                raise ConfigError("scenario %r is defined in both %s and %s"
                                  % (scenario.name, seen[scenario.name], path))
            seen[scenario.name] = path
            scenarios.append(scenario)
    return scenarios


def load_file(path, overrides, raw=False):
    if not os.path.isfile(path):
        raise ConfigError("no such file", path)
    parser = configparser.ConfigParser(interpolation=None, delimiters=("=",),
                                       inline_comment_prefixes=(";",))
    parser.optionxform = str.lower
    try:
        with open(path) as handle:
            parser.read_file(handle, source=path)
    except configparser.Error as exc:
        raise ConfigError(str(exc), path)

    variables = dict(parser["vars"]) if parser.has_section("vars") else {}
    variables.update(overrides)

    scenarios = []
    defaults = {}
    current = None
    for section in parser.sections():
        where = "%s [%s]" % (path, section)
        items = _items(parser, section, where, raw, variables)
        kind, _, name = section.partition(" ")
        kind, name = kind.strip().lower(), name.strip()

        if section.lower() == "vars":
            continue
        if section.lower() == "defaults":
            _reject_unknown(items, DEFAULTS_KEYS, where)
            defaults = items
        elif kind == "scenario" and name:
            _reject_unknown(items, SCENARIO_KEYS, where)
            current = Scenario(name, items.get("description", ""),
                               items.get("interface") or defaults.get("interface"),
                               source=path)
            scenarios.append((current, []))
        elif kind == "step" and name:
            if current is None:
                raise ConfigError("a [step] must follow a [scenario]", where)
            scenarios[-1][1].append(_build_step(name, items, defaults, where))
        else:
            raise ConfigError("unknown section; expected [vars], [defaults], "
                              "[scenario <name>] or [step <name>]", where)

    if not scenarios:
        raise ConfigError("no [scenario ...] section found", path)
    for scenario, found in scenarios:
        if not found:
            raise ConfigError("scenario %r has no steps" % (scenario.name,), path)
        scenario.steps = tuple(found)
    return [scenario for scenario, _ in scenarios]


def _build_step(name, items, defaults, where):
    step_type = (items.get("type") or "").strip().lower()
    if not step_type:
        raise ConfigError("step %r has no type=" % (name,), where)
    if step_type not in steps.TYPES:
        raise ConfigError("unknown step type %r (known: %s)"
                          % (step_type, ", ".join(sorted(steps.TYPES))), where)
    kind = steps.TYPES[step_type]
    _reject_unknown(items, kind.keys, where)

    # A default reaches only the steps that can take it, so one
    # `[defaults] server =` serves dns, tftp and http steps without making a
    # DHCP step in the same file illegal.
    merged = dict((k, v) for k, v in defaults.items() if k in kind.keys)
    merged.update(items)
    return Step(
        name=name,
        type=step_type,
        expect=(merged.pop("expect", "") or "").strip().lower() or None,
        assertions=assertions.parse_block(merged.pop("assert", ""), where),
        timeout=_number(float, merged.pop("timeout", None), kind.timeout,
                        "timeout", where),
        retries=_number(lambda v: int(v, 0), merged.pop("retries", None),
                        kind.retries, "retries", where),
        params=dict((k, v) for k, v in merged.items() if k != "type"),
        source=where,
    )


def _items(parser, section, where, raw, variables):
    """One section's keys, with `%(name)s` resolved out of `variables`."""
    items = {}
    for key in parser.options(section):
        value = parser.get(section, key, raw=True)
        if raw:
            items[key] = value
            continue
        try:
            items[key] = INTERPOLATION.before_get(parser, section, key, value,
                                                  variables)
        except configparser.InterpolationMissingOptionError as exc:
            raise ConfigError("%%(%s)s is not defined; pass --set %s=<value>"
                              % (exc.reference, exc.reference), where)
        except configparser.Error as exc:
            raise ConfigError(str(exc), where)
    return items


def _reject_unknown(items, allowed, where):
    unknown = sorted(set(items) - set(allowed))
    if unknown:
        raise ConfigError("unknown key(s): %s (allowed: %s)"
                          % (", ".join(unknown), ", ".join(sorted(allowed))),
                          where)


def _number(convert, value, default, key, where):
    if value in (None, ""):
        return default
    try:
        return convert(value.strip())
    except ValueError:
        raise ConfigError("%s= must be a number, got %r" % (key, value), where)
