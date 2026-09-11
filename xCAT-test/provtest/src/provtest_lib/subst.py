"""Runtime references to earlier replies: `$step.field`.

Variables are configparser's job. `%(name)s` is interpolated by
`BasicInterpolation` out of `[vars]` and `--set` before a value ever reaches
this module, and `BasicInterpolation` gives `$` no meaning of its own, so the
two schemes share a file with no escaping.

What configparser cannot do is `$grubcfg.text`, because that value is a reply
that has not arrived when the file is read. Cross-stage assertions are the
whole point of this suite -- TFTP fetches a config, HTTP fetches what that
config named -- so this form is resolved at step-execution time instead, when
the earlier replies exist.
"""

import re

from .errors import ConfigError

REF_RE = re.compile(r"\$([A-Za-z_][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_.-]*)")

#: configparser's variable syntax, matched only to report what a file needs.
VAR_RE = re.compile(r"%\(([^)]+)\)s")


class Context(object):
    """Every reply a `$reference` can resolve against, at one point in a run."""

    def __init__(self):
        self.bindings = {}
        self.order = []

    def bind(self, name, reply):
        if name not in self.bindings:
            self.order.append(name)
        self.bindings[name] = reply

    def get_binding(self, name):
        if name not in self.bindings:
            raise ConfigError(
                "$%s is not available here; no step of that name has run yet"
                % (name,))
        return self.bindings[name]

    def __repr__(self):
        return "Context(bindings=%r)" % (self.order,)


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
        name, field = match.group(1), match.group(2).rstrip(".")
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
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    if isinstance(value, (list, tuple)):
        return ", ".join(format_value(item) for item in value)
    if isinstance(value, dict):
        return ", ".join("%s=%s" % (key, format_value(value[key]))
                         for key in sorted(value))
    return str(value)
