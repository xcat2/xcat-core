"""The assertion mini-language: `target op value`.

One assertion per line, under a single multi-line `assert` key. A single key
holding many lines sidesteps configparser's one-value-per-key rule and keeps
the grammar uniform, so `status == NXDOMAIN` and `text contains destiny=install`
parse through exactly the same path.

The operator table is dhcptest's, so an operator reads the same in both suites.
"""

import re

from . import netutil, subst
from .errors import ConfigError
from .model import Assertion

#: Targets that describe the step rather than the reply.
META_TARGETS = frozenset(["attempt"])

#: Operators that take no value.
NULLARY_OPS = frozenset(["present", "absent"])

#: Operators asserting that the reply is *not* something, which a reply that
#: says nothing on the subject satisfies.
NEGATIVE_OPS = frozenset(["!=", "not-in"])

OPS = frozenset([
    "==", "!=", "in", "not-in", "present", "absent",
    "matches", "contains", "starts-with", "ends-with",
    "<", "<=", ">", ">=",
])


class Result(object):
    """The outcome of one assertion, carrying enough to explain a failure."""

    __slots__ = ("assertion", "ok", "expected", "actual", "detail")

    def __init__(self, assertion, ok, expected=None, actual=None, detail=""):
        self.assertion = assertion
        self.ok = ok
        self.expected = expected
        self.actual = actual
        self.detail = detail

    def __repr__(self):
        return "Result(%r, ok=%r, expected=%r, actual=%r)" % (
            self.assertion.render(), self.ok, self.expected, self.actual)


def parse(line, source=""):
    """Parse one assertion line into an `Assertion`."""
    text = line.strip()
    if not text:
        raise ConfigError("empty assertion", source)

    parts = text.split(None, 2)
    if len(parts) < 2:
        raise ConfigError("assertion needs at least a target and an operator: %r"
                          % (text,), source)

    target, op = parts[0], parts[1]
    value = parts[2] if len(parts) > 2 else None

    if op not in OPS:
        raise ConfigError(
            "unknown operator %r in %r (expected one of: %s)"
            % (op, text, ", ".join(sorted(OPS))), source)

    if op in NULLARY_OPS:
        if value:
            raise ConfigError("operator %r takes no value: %r" % (op, text), source)
        value = None
    elif value is None:
        # `error != ` with nothing after it is a legitimate "must be non-empty".
        value = ""

    if op == "matches":
        try:
            re.compile(value)
        except re.error as exc:
            raise ConfigError("bad regex %r: %s" % (value, exc), source)

    return Assertion(target=target, op=op, value=value, source=source, text=text)


def parse_block(block, source=""):
    """Parse a multi-line `assert = ...` value into a tuple of assertions."""
    result = []
    for number, raw in enumerate(str(block or "").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        where = "%s line %d of assert block" % (source, number) if source else ""
        result.append(parse(line, where))
    return tuple(result)


# ---------------------------------------------------------------------------
# evaluation


def evaluate(assertion, reply, context, extras=None):
    """Check one assertion against one reply."""
    extras = extras or {}
    expected = None
    if assertion.value is not None:
        expected = subst.resolve(assertion.value, context)

    present, actual = _actual(assertion.target, reply, context, extras)

    if assertion.op == "present":
        return Result(assertion, present, expected="present",
                      actual="present" if present else "absent")
    if assertion.op == "absent":
        return Result(assertion, not present, expected="absent",
                      actual="present" if present else "absent")

    if not present:
        # A negative comparison is satisfied by a target that is not there at
        # all: a config that names no kernel has certainly not named the wrong
        # one. `absent` remains the way to assert the absence itself.
        if assertion.op in NEGATIVE_OPS:
            return Result(assertion, True, expected=expected, actual=None,
                          detail="%s is not present in the reply"
                                 % (assertion.target,))
        return Result(assertion, False, expected=expected, actual=None,
                      detail="%s is not present in the reply" % (assertion.target,))

    ok, detail = _compare(assertion.op, actual, expected)
    return Result(assertion, ok, expected=expected,
                  actual=subst.format_value(actual), detail=detail)


def _actual(target, reply, context, extras):
    """Return `(present, value)` for one assertion target."""
    if target in META_TARGETS:
        if target not in extras:
            return False, None
        return True, extras[target]

    if target.startswith("$"):
        try:
            return True, subst.resolve(target, context)
        except ConfigError:
            return False, None

    if reply is None:
        return False, None
    if not reply.has(target):
        return False, None
    return True, reply.field(target)


def _compare(op, actual, expected):
    """Type-aware comparison. Returns `(ok, detail)`."""
    if op in ("==", "!="):
        same = _equal(actual, expected)
        return (same if op == "==" else not same), ""

    if op in ("in", "not-in"):
        inside = _member(actual, expected)
        return (inside if op == "in" else not inside), ""

    text = subst.format_value(actual)
    if op == "matches":
        return bool(re.search(expected, text, re.MULTILINE)), ""
    if op == "contains":
        return expected in text, ""
    if op == "starts-with":
        return text.startswith(expected), ""
    if op == "ends-with":
        return text.endswith(expected), ""

    left, right = _as_numbers(actual, expected)
    if left is None:
        return False, "%r and %r are not both numbers" % (actual, expected)
    if op == "<":
        return left < right, ""
    if op == "<=":
        return left <= right, ""
    if op == ">":
        return left > right, ""
    if op == ">=":
        return left >= right, ""
    raise ConfigError("unhandled operator %r" % (op,))


def _equal(actual, expected):
    """Compare as addresses, then as numbers, then as text.

    A list on the left means "any of these", so a name with two A records
    satisfies `data == <one of them>`. Writing the whole set is `data.0` and
    `data.1`, or `count == 2`.
    """
    if isinstance(actual, (list, tuple)):
        return any(_equal(item, expected) for item in actual)

    left_ip = netutil.parse_ip(subst.format_value(actual))
    right_ip = netutil.parse_ip(expected)
    if left_ip is not None and right_ip is not None:
        return left_ip == right_ip

    left, right = _as_numbers(actual, expected)
    if left is not None:
        return left == right

    return subst.format_value(actual) == str(expected)


def _member(actual, expected):
    """`in` means membership: of a CIDR, of a `first-last` range, or of a list."""
    text = subst.format_value(actual)
    if "/" in expected and netutil.parse_ip(text) is not None:
        return netutil.ip_in(text, expected)
    if netutil.parse_range(expected) is not None:
        return netutil.ip_in_range(text, expected)
    candidates = [item.strip() for item in expected.split(",") if item.strip()]
    return any(_equal(actual, candidate) for candidate in candidates)


def _as_numbers(actual, expected):
    """Both sides as ints, or `(None, None)` when either is not numeric."""
    try:
        left = actual if isinstance(actual, int) else int(str(actual).strip(), 0)
        right = expected if isinstance(expected, int) else int(str(expected).strip(), 0)
    except (TypeError, ValueError):
        return None, None
    return left, right
