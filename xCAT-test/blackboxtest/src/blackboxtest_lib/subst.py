"""Runtime references to earlier replies: `$step.field`.

`%(name)s` is configparser's job and is gone before a value reaches this
module. `$step.field` cannot be: its value is a reply that has not arrived
when the file is read. `BasicInterpolation` gives `$` no meaning, so the two
forms share a file with no escaping.
"""

import re

from .errors import ConfigError

REF_RE = re.compile(r"\$([A-Za-z_][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_.-]*)")

#: configparser's variable syntax, matched only to report what a file needs.
VAR_RE = re.compile(r"%\(([^)]+)\)s")


class Context(object):
    """The replies a `$reference` can resolve against, by binding name."""

    def __init__(self):
        self.bindings = {}

    def bind(self, name, reply):
        self.bindings[name] = reply

    def get(self, name):
        if name not in self.bindings:
            raise ConfigError(
                "$%s is not available here; nothing has bound it yet" % (name,))
        return self.bindings[name]


def references(text):
    """Every `$step.field` in a value, as `[(step, field), ...]`."""
    if text is None:
        return []
    return [(name, field.rstrip(".")) for name, field in REF_RE.findall(str(text))]


def variables(text):
    """Every `%(name)s` in a value."""
    if text is None:
        return set()
    return set(VAR_RE.findall(str(text)))


def resolve(text, context):
    """Substitute every `$step.field` in `text`."""
    if text is None:
        return None

    def replace(match):
        reply = context.get(match.group(1))
        try:
            return format_value(reply.field(match.group(2).rstrip(".")))
        except KeyError as exc:
            raise ConfigError(str(exc).strip("'\""))

    return REF_RE.sub(replace, str(text))


def format_value(value):
    """Render a value the way a .conf author would have typed it."""
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    if isinstance(value, (list, tuple)):
        return ", ".join(format_value(item) for item in value)
    if isinstance(value, dict):
        return ", ".join("%s=%s" % (key, format_value(value[key]))
                         for key in sorted(value))
    return str(value)
