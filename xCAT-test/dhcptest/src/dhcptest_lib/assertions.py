"""The assertion mini-language: `target op value`.

One assertion per line, under a single multi-line `assert` key. A single key
holding many lines sidesteps configparser's one-value-per-key rule and keeps
the grammar uniform, so `option:54 == 10.0.0.1` and `yiaddr in 10.0.0.0/24`
parse through exactly the same path.
"""

import re

from . import netutil, options, subst
from .errors import ConfigError
from .model import Assertion

#: Targets that come straight out of the BOOTP header.
HEADER_TARGETS = frozenset([
    "msgtype", "xid", "yiaddr", "siaddr", "ciaddr", "giaddr", "chaddr",
    "file", "sname", "secs", "flags", "src_ip", "src_mac",
])

#: Targets that describe the step rather than one reply.
META_TARGETS = frozenset(["offers", "attempt"])

#: Targets a client works out from more than one place in the message. Assert
#: on these rather than on `file` unless the header itself is the point.
DERIVED_TARGETS = frozenset(["bootfile", "fqdn_flags", "dns_name"])

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
        # `file != ` with nothing after it is a legitimate "must be non-empty".
        value = ""

    validate_target(target, source)
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


def validate_target(target, source=""):
    """Reject a target that could never resolve, before any packet is sent."""
    if target in HEADER_TARGETS or target in META_TARGETS \
            or target in DERIVED_TARGETS:
        return
    if target.startswith("$"):
        refs = subst.references(target)
        if len(refs) != 1:
            raise ConfigError(
                "assertion target %r must be a single $step.field reference"
                % (target,), source)
        _, field = refs[0]
        if not subst.check_field(field):
            raise ConfigError("unknown reply field .%s in %r" % (field, target),
                              source)
        return
    # Anything else has to name an option.
    options.option_code(target)


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
        # all: a reply naming no boot file has certainly not named the node's
        # install script. Failing it instead would make "is not X" quietly
        # stronger than it reads, and would fail the one reply that is most
        # obviously right. `absent` remains the assertion to write when the
        # absence itself is the point.
        if assertion.op in NEGATIVE_OPS:
            return Result(assertion, True, expected=expected, actual=None,
                          detail="%s is not present in the reply" % (assertion.target,))
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
        return True, subst.resolve(target, context)

    if target in DERIVED_TARGETS:
        if reply is None:
            return False, None
        value = {
            "fqdn_flags": reply.fqdn_flags,
            "dns_name": reply.dns_name,
            "bootfile": reply.bootfile,
        }[target]()
        return bool(value), value

    if target in HEADER_TARGETS:
        if reply is None:
            return False, None
        value = getattr(reply, target)
        # A zeroed header field counts as absent for present/absent.
        empty = value in ("", 0, "0.0.0.0")
        return (not empty), value

    if reply is None:
        return False, None
    code = options.option_code(target)
    if code not in reply.options:
        return False, None
    return True, reply.options[code]


def _compare(op, actual, expected):
    """Type-aware comparison. Returns `(ok, detail)`."""
    if op in ("==", "!="):
        same = _equal(actual, expected)
        if op == "==":
            return same, ""
        return (not same), ""

    if op in ("in", "not-in"):
        inside = _member(actual, expected)
        if op == "in":
            return inside, ""
        return (not inside), ""

    text = subst.format_value(actual)
    if op == "matches":
        return bool(re.search(expected, text)), ""
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
    """Compare as addresses, then as numbers, then as message types, then text."""
    left_ip = netutil.parse_ip(subst.format_value(actual))
    right_ip = netutil.parse_ip(expected)
    if left_ip is not None and right_ip is not None:
        return left_ip == right_ip

    left, right = _as_numbers(actual, expected)
    if left is not None:
        return left == right

    left_text = subst.format_value(actual)
    if _looks_like_msgtype(left_text) and _looks_like_msgtype(expected):
        return left_text.upper() == expected.upper()
    return left_text == expected


def _member(actual, expected):
    """`in` means membership: of a CIDR, of a `first-last` range, or of a list."""
    text = subst.format_value(actual)
    if "/" in expected:
        return netutil.ip_in(text, expected)
    if netutil.parse_range(expected) is not None:
        return netutil.ip_in_range(text, expected)
    candidates = [item.strip() for item in expected.split(",") if item.strip()]
    for candidate in candidates:
        if _equal(actual, candidate):
            return True
    return False


def _as_numbers(actual, expected):
    """Both sides as ints, or `(None, None)` when either is not numeric."""
    try:
        left = actual if isinstance(actual, int) else int(str(actual).strip(), 0)
        right = expected if isinstance(expected, int) else int(str(expected).strip(), 0)
    except (TypeError, ValueError):
        return None, None
    return left, right


def _looks_like_msgtype(text):
    return str(text).strip().lower().replace("-", "_") in options.MSGTYPE_BY_NAME
