"""Plain data structures shared across the tool.

No network and no subprocess: everything here can be built by hand in a unit
test, which is how the assertion language is tested without a server.

Written for Python 3.6, so no dataclasses.
"""

from .errors import ConfigError


class Assertion(object):
    """One line of the assertion mini-language: `target op value`.

    For example::

        status   == NOERROR
        data     == 10.99.1.11
        text     contains destiny=install
        sha256   == $tftpfetch.sha256
    """

    __slots__ = ("target", "op", "value", "source", "text")

    def __init__(self, target, op, value, source="", text=""):
        self.target = target
        self.op = op
        self.value = value
        self.source = source
        self.text = text or self.render()

    def render(self):
        if self.value is None:
            return "%s %s" % (self.target, self.op)
        return "%s %s %s" % (self.target, self.op, self.value)

    def __repr__(self):
        return "Assertion(%r)" % (self.render(),)


class Step(object):
    """One client action plus the assertions made about what came back."""

    __slots__ = ("name", "type", "expect", "params", "assertions", "timeout",
                 "retries", "source")

    def __init__(self, name, type, expect, params, assertions,
                 timeout=5.0, retries=2, source=""):
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
    """A named sequence of steps, run in order against one server."""

    __slots__ = ("name", "description", "steps", "source")

    def __init__(self, name, description="", steps=(), source=""):
        self.name = name
        self.description = description
        self.steps = tuple(steps)
        self.source = source

    def step(self, name):
        for step in self.steps:
            if step.name == name:
                return step
        raise ConfigError("no such step %r in scenario %r" % (name, self.name))

    def __repr__(self):
        return "Scenario(%r, steps=%d)" % (self.name, len(self.steps))


class Reply(object):
    """What one step got back, as a flat namespace of fields.

    Unlike DHCP, the five protocols here share no header, so a reply is a bag
    of named values rather than a fixed record. What each step type puts in it
    is declared in `machine.REPLY_FIELDS`, so a `.conf` naming a field no step
    of that type ever produces is rejected before any socket is opened.

    A field may hold a list -- DNS answers, monitor lines, findme callbacks.
    Indexing is written `data.0`, and the bare name of a list resolves to its
    first element, so `data == 10.99.1.11` reads the way an operator expects
    for the ordinary one-answer case.
    """

    __slots__ = ("kind", "fields", "ok", "error", "sent", "attempt", "raw")

    def __init__(self, kind="", fields=None, ok=True, error="", sent="",
                 attempt=0, raw=b""):
        self.kind = kind
        self.fields = dict(fields or {})
        self.ok = ok
        self.error = error
        self.sent = sent
        self.attempt = attempt
        self.raw = raw

    def field(self, name):
        """Resolve one `$step.<name>` reference, or raise KeyError.

        `a.b` is looked up whole first, so a header written into the reply as
        `header.content-type` wins over any attempt to index a list called
        `header`. Only then is the name split into container and index.
        """
        if name in self.fields:
            return self._first(self.fields[name])
        head, _, tail = name.rpartition(".")
        if head and head in self.fields:
            container = self.fields[head]
            if isinstance(container, (list, tuple)):
                try:
                    index = int(tail)
                except ValueError:
                    raise KeyError("%s is not an index into .%s" % (tail, head))
                if index >= len(container) or index < -len(container):
                    raise KeyError(
                        "%s reply has %d item(s) in .%s, so .%s does not exist"
                        % (self.kind, len(container), head, name))
                return container[index]
            if isinstance(container, dict):
                if tail not in container:
                    raise KeyError("%s reply has no .%s" % (self.kind, name))
                return container[tail]
        raise KeyError("%s reply has no field .%s" % (self.kind or "this", name))

    def has(self, name):
        try:
            value = self.field(name)
        except KeyError:
            return False
        # An empty list is "nothing came back", which is absence, not a value.
        if isinstance(value, (list, tuple)):
            return bool(value)
        return value not in (None, "")

    @staticmethod
    def _first(value):
        if isinstance(value, (list, tuple)):
            return value[0] if value else []
        return value

    def summary(self):
        parts = []
        for key in sorted(self.fields):
            value = self.fields[key]
            if key in ("text", "raw", "body"):
                continue
            parts.append("%s=%s" % (key, _short(value)))
        head = "%s %s" % (self.kind or "reply", "ok" if self.ok else "failed")
        if self.error:
            head += " (%s)" % (self.error,)
        return "%s %s" % (head, " ".join(parts))

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
