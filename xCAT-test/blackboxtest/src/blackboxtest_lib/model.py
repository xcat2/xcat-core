"""Plain data structures: no network, no subprocess, no scapy.

Written for Python 3.6, so no dataclasses.
"""


class Assertion(object):
    """One line of the assertion language: `target op value`."""

    __slots__ = ("target", "op", "value", "source")

    def __init__(self, target, op, value, source=""):
        self.target = target
        self.op = op
        self.value = value
        self.source = source

    def render(self):
        if self.value is None:
            return "%s %s" % (self.target, self.op)
        return "%s %s %s" % (self.target, self.op, self.value)

    def __repr__(self):
        return "Assertion(%r)" % (self.render(),)


class Step(object):
    """One client action, and the assertions made about its reply."""

    __slots__ = ("name", "type", "expect", "params", "assertions", "timeout",
                 "retries", "source")

    def __init__(self, name, type, expect, params, assertions, timeout,
                 retries, source=""):
        self.name = name
        self.type = type
        self.expect = expect
        self.params = dict(params)
        self.assertions = tuple(assertions)
        self.timeout = timeout
        self.retries = retries
        self.source = source

    def param(self, key, default=None):
        value = self.params.get(key, default)
        if isinstance(value, str):
            value = value.strip()
        return value

    def __repr__(self):
        return "Step(%r, type=%r, expect=%r)" % (self.name, self.type, self.expect)


class Scenario(object):
    """A named sequence of steps, run in file order.

    `interface` is where the DHCP steps send from. The other steps choose their
    source by address, through `bind`.
    """

    __slots__ = ("name", "description", "interface", "steps", "source")

    def __init__(self, name, description="", interface=None, steps=(),
                 source=""):
        self.name = name
        self.description = description
        self.interface = interface
        self.steps = tuple(steps)
        self.source = source

    def __repr__(self):
        return "Scenario(%r, steps=%d)" % (self.name, len(self.steps))


class Reply(object):
    """What one step got back, as a flat namespace of named fields.

    A field may hold a list or a mapping. `data.0` indexes a list and
    `header.content-type` reads a mapping. The bare name of a list resolves to
    its first element in `$step.field`, because a substitution wants one value;
    an assertion reads the whole list through `whole()`.
    """

    __slots__ = ("kind", "fields", "ok", "error", "sent", "attempt")

    def __init__(self, kind="", fields=None, ok=True, error="", sent="",
                 attempt=0):
        self.kind = kind
        self.fields = dict(fields or {})
        self.ok = ok
        self.error = error
        self.sent = sent
        self.attempt = attempt

    def whole(self, name):
        """The value of `name`, a list kept whole, or KeyError."""
        if name in self.fields:
            return self.fields[name]
        head, _, tail = name.partition(".")
        container = self.fields.get(head)
        if isinstance(container, dict):
            if tail not in container:
                raise KeyError("%s reply has no .%s" % (self.kind, name))
            return container[tail]
        if isinstance(container, (list, tuple)):
            try:
                return container[int(tail)]
            except ValueError:
                raise KeyError("%s is not an index into .%s" % (tail, head))
            except IndexError:
                raise KeyError("%s reply has %d item(s) in .%s"
                               % (self.kind, len(container), head))
        raise KeyError("%s reply has no field .%s" % (self.kind or "this", name))

    def field(self, name):
        """The value `$step.name` substitutes: a list gives its first item."""
        value = self.whole(name)
        if isinstance(value, (list, tuple)):
            return value[0] if value else ""
        return value

    def has(self, name):
        """True when `name` carries a value. An empty list is absence."""
        try:
            value = self.whole(name)
        except KeyError:
            return False
        if isinstance(value, (list, tuple)):
            return bool(value)
        return value not in (None, "")

    def summary(self):
        parts = ["%s %s" % (self.kind or "reply", "ok" if self.ok else "failed")]
        if self.error:
            parts.append("(%s)" % (self.error,))
        for key in sorted(self.fields):
            if key not in ("text", "raw"):
                parts.append("%s=%s" % (key, _short(self.fields[key])))
        return " ".join(parts)

    def detail_lines(self):
        """Extra `(label, text)` lines for a failure report."""
        return []

    def __repr__(self):
        return "Reply(%s)" % (self.summary(),)


def _short(value, limit=60):
    if isinstance(value, (list, tuple)):
        text = "[" + ", ".join(str(item) for item in value) + "]"
    elif isinstance(value, dict):
        text = "{" + ", ".join("%s=%s" % (k, v) for k, v in sorted(value.items())) + "}"
    else:
        text = str(value)
    if len(text) > limit:
        text = text[:limit - 3] + "..."
    return text
