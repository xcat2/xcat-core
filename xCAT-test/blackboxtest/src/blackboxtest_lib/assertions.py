"""The assertion language: `target op value`, one per line under `assert`.

Whether a target names a field the step can produce is checked offline, in
`validate`, because that depends on the step type. This module only parses a
line and evaluates it against a reply.
"""

import re

from . import netutil, subst
from .errors import ConfigError
from .model import Assertion

#: Targets the runner supplies about the step, not read from the reply.
#: `offers` counts the DHCP servers that answered a DISCOVER.
META_TARGETS = frozenset(["attempt", "offers"])

NULLARY_OPS = frozenset(["present", "absent"])

#: Operators that a missing target satisfies: a reply naming no boot file has
#: certainly not named the wrong one.
NEGATIVE_OPS = frozenset(["!=", "not-in"])

OPS = frozenset([
    "==", "!=", "in", "not-in", "present", "absent",
    "matches", "contains", "starts-with", "ends-with",
    "<", "<=", ">", ">=",
])


class Result(object):
    """The outcome of one assertion, with enough to explain a failure."""

    __slots__ = ("assertion", "ok", "expected", "actual", "detail")

    def __init__(self, assertion, ok, expected=None, actual=None, detail=""):
        self.assertion = assertion
        self.ok = ok
        self.expected = expected
        self.actual = actual
        self.detail = detail


def parse(line, source=""):
    """Parse one assertion line."""
    parts = line.strip().split(None, 2)
    if len(parts) < 2:
        raise ConfigError("an assertion needs a target and an operator: %r"
                          % (line.strip(),), source)
    target, op = parts[0], parts[1]
    value = parts[2] if len(parts) > 2 else None

    if op not in OPS:
        raise ConfigError("unknown operator %r in %r (expected one of: %s)"
                          % (op, line.strip(), ", ".join(sorted(OPS))), source)
    if op in NULLARY_OPS:
        if value:
            raise ConfigError("operator %r takes no value: %r"
                              % (op, line.strip()), source)
    elif value is None:
        value = ""
    if op == "matches":
        try:
            re.compile(value)
        except re.error as exc:
            raise ConfigError("bad regex %r: %s" % (value, exc), source)
    return Assertion(target, op, value, source)


def parse_block(block, source=""):
    """Parse a multi-line `assert =` value. Blank and `#` lines are skipped."""
    result = []
    for number, raw in enumerate(str(block or "").splitlines(), start=1):
        line = raw.strip()
        if line and not line.startswith("#"):
            where = "%s line %d of assert" % (source, number) if source else ""
            result.append(parse(line, where))
    return tuple(result)


def evaluate(assertion, reply, context, extras=None):
    """Check one assertion against one reply, which may be None."""
    expected = None
    if assertion.value is not None:
        expected = subst.resolve(assertion.value, context)

    present, actual = _actual(assertion.target, reply, context, extras or {})

    if assertion.op in NULLARY_OPS:
        ok = present if assertion.op == "present" else not present
        return Result(assertion, ok, expected=assertion.op,
                      actual="present" if present else "absent")

    if not present:
        return Result(assertion, assertion.op in NEGATIVE_OPS,
                      expected=expected,
                      detail="%s is not present in the reply" % (assertion.target,))

    return Result(assertion, _compare(assertion.op, actual, expected),
                  expected=expected, actual=subst.format_value(actual))


def _actual(target, reply, context, extras):
    """`(present, value)` for one assertion target."""
    if target in META_TARGETS:
        return (target in extras), extras.get(target)
    if target.startswith("$"):
        try:
            return True, subst.resolve(target, context)
        except ConfigError:
            return False, None
    if reply is None or not reply.has(target):
        return False, None
    return True, reply.whole(target)


def _compare(op, actual, expected):
    if op in ("==", "!="):
        return _equal(actual, expected) == (op == "==")
    if op in ("in", "not-in"):
        return _member(actual, expected) == (op == "in")

    text = subst.format_value(actual)
    if op == "matches":
        return bool(re.search(expected, text, re.MULTILINE))
    if op == "contains":
        return expected in text
    if op == "starts-with":
        return text.startswith(expected)
    if op == "ends-with":
        return text.endswith(expected)

    left, right = _as_numbers(actual, expected)
    if left is None:
        return False
    return {"<": left < right, "<=": left <= right,
            ">": left > right, ">=": left >= right}[op]


def _equal(actual, expected):
    """Compare as addresses, then as numbers, then as text.

    A list equals a value when the whole list, written out, is that value, or
    when any one element is: a name with two A records satisfies
    `data == <either>`.
    """
    if isinstance(actual, (list, tuple)):
        return (subst.format_value(actual) == expected
                or any(_equal(item, expected) for item in actual))

    left_ip = netutil.parse_ip(subst.format_value(actual))
    right_ip = netutil.parse_ip(expected)
    if left_ip is not None and right_ip is not None:
        return left_ip == right_ip

    left, right = _as_numbers(actual, expected)
    if left is not None:
        return left == right
    return subst.format_value(actual) == str(expected)


def _member(actual, expected):
    """Membership of a CIDR, of a `first-last` range, or of a comma list."""
    text = subst.format_value(actual)
    if "/" in expected and netutil.parse_ip(text) is not None:
        return netutil.ip_in(text, expected)
    if netutil.parse_range(expected) is not None:
        return netutil.ip_in_range(text, expected)
    candidates = [item.strip() for item in expected.split(",") if item.strip()]
    return any(_equal(actual, candidate) for candidate in candidates)


def _as_numbers(actual, expected):
    """Both sides as ints, or `(None, None)` when either is not a number."""
    try:
        left = actual if isinstance(actual, int) else int(str(actual).strip(), 0)
        right = int(str(expected).strip(), 0)
    except (TypeError, ValueError):
        return None, None
    return left, right
