"""Runtime references to earlier replies.

Variables are configparser's job: `%(name)s` is interpolated by
`BasicInterpolation` out of the `[vars]` section and `--set`, before a value
ever reaches this module.

What configparser cannot do is `$offer.address`, because that value is a reply
that has not arrived when the file is read. So exactly one form is resolved
here, at step-execution time, when the earlier replies exist:

    $step.field     a field of an earlier step's reply

`BasicInterpolation` gives `$` no meaning of its own, which is why the two
schemes can share a file without escaping.
"""

import re

from .errors import ConfigError
from .model import Reply

REF_RE = re.compile(r"\$([A-Za-z_][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_]*)")

#: configparser's variable syntax, matched only to report what a file needs.
VAR_RE = re.compile(r"%\(([^)]+)\)s")

#: Bindings the tool maintains itself, in addition to one per named step.
ALIASES = ("offer", "ack", "nak", "lease", "reply")


class Context(object):
    """Everything a `$reference` can resolve against, at one point in a run.

    Only replies: variables were interpolated by configparser at load time and
    are gone by the time a step runs.
    """

    def __init__(self):
        self.bindings = {}

    def bind(self, name, reply):
        self.bindings[name] = reply

    def get_binding(self, name):
        if name not in self.bindings:
            raise ConfigError(
                "$%s is not available here; nothing has bound it yet" % (name,))
        return self.bindings[name]

    def __repr__(self):
        return "Context(bindings=%r)" % (sorted(self.bindings),)


def references(text):
    """Every `$step.field` in a value, as `[(step, field), ...]`.

    Static analysis: `validate` uses this to reject a typo like
    `$offer.addres` without sending a single packet.
    """
    if text is None:
        return []
    return REF_RE.findall(str(text))


def variables(text):
    """Every `%(name)s` in a value.

    Only used to tell an operator what a file needs. Resolving them is
    configparser's job, not ours.
    """
    if text is None:
        return set()
    return set(VAR_RE.findall(str(text)))


def resolve(text, context):
    """Substitute every `$step.field` in `text`."""
    if text is None:
        return None

    def replace(match):
        name, field = match.group(1), match.group(2)
        reply = context.get_binding(name)
        try:
            return format_value(reply.field(field))
        except KeyError as exc:
            raise ConfigError(str(exc))

    return REF_RE.sub(replace, str(text))


def format_value(value):
    """Render a resolved value the way a .conf author would have typed it."""
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, (list, tuple)):
        return ", ".join(format_value(item) for item in value)
    return str(value)


def check_field(field):
    """True when `field` is a name `Reply.field()` could ever resolve."""
    if field.startswith("opt") and field[3:]:
        try:
            int(field[3:], 0)
        except ValueError:
            return False
        return True
    return field in Reply.known_fields()
