"""What a step of each type may say, and what its reply will hold.

This is the offline half of the tool. `validate` runs it in a checkout with no
network, no root and no server, so a typo in a field name or a step that names
no server is a configuration error reported before anything is sent.

Every table here is declarative on purpose: adding a protocol means adding a
row, not a branch in the runner.
"""

from . import subst
from .errors import ConfigError

#: Keys every step may carry, whatever its type. `bind` is the client's own
#: address: xcatd names a client by the reverse lookup of the address it
#: connected from, so which end of the veth pair a request leaves by is itself
#: under test, and cannot be left to the kernel's source selection.
COMMON_KEYS = frozenset(["type", "expect", "timeout", "retries", "assert",
                         "bind"])

#: Per type: the keys it accepts, beyond COMMON_KEYS.
STEP_KEYS = {
    "dns": frozenset(["server", "port", "name", "rrtype", "recursion"]),
    "tftp": frozenset(["server", "port", "path", "mode"]),
    "http": frozenset(["server", "port", "path", "url", "method", "header",
                       "insecure"]),
    "xcatreq": frozenset(["server", "port", "command", "element", "raw",
                          "callback_port", "callback_listen", "callback_reply",
                          "callback_wait", "cert", "key", "source_port"]),
    "monitor": frozenset(["server", "port", "send", "source_port"]),
    "flowrequest": frozenset(["server", "port", "message", "source_port",
                              "replies"]),
    "findme": frozenset(["server", "port", "payload", "encoding", "source_port",
                         "callback_listen", "callback_wait"]),
    "extract": frozenset(["from", "pattern", "group"]),
    "sleep": frozenset(["duration"]),
    "noop": frozenset([]),
}

#: Keys naming a value that must be present for the step to mean anything.
REQUIRED_KEYS = {
    "dns": ("server", "name"),
    "tftp": ("server", "path"),
    "http": (),                 # url, or server+path; checked below
    "xcatreq": ("server", "command"),
    "monitor": ("server", "send"),
    "flowrequest": ("server",),
    "findme": ("server",),
    "extract": ("from", "pattern"),
    "sleep": ("duration",),
    "noop": (),
}

#: Per type: the reply fields a `.conf` may name, as an assertion target or
#: through `$step.field`. A name not in this set is a typo, and is reported as
#: one rather than silently never matching.
REPLY_FIELDS = {
    "dns": frozenset(["status", "flags", "count", "data", "type", "ttl",
                      "name", "question", "answers", "authority", "server",
                      "rcode", "raw"]),
    "tftp": frozenset(["ok", "size", "sha256", "text", "error", "path",
                       "server", "raw"]),
    "http": frozenset(["status", "size", "sha256", "text", "url", "header",
                       "content_type", "error", "ok", "raw"]),
    "xcatreq": frozenset(["destiny", "kernel", "initrd", "kcmdline",
                          "imgserver", "name", "error", "serverdone",
                          "elements", "data", "text", "handshake", "ok",
                          "callback_seen", "callback_data", "raw"]),
    "monitor": frozenset(["greeting", "lines", "raw", "text", "ok", "closed",
                          "error"]),
    "flowrequest": frozenset(["replies", "count", "ok", "error", "raw"]),
    "findme": frozenset(["callbacks", "count", "ok", "error", "raw"]),
    "extract": frozenset(["value", "groups", "matched", "count"]),
    "sleep": frozenset([]),
    "noop": frozenset([]),
}

#: Reply fields that are a mapping rather than a scalar or a list, and so are
#: addressed as `header.content-type` or `elements.destiny`.
MAPPING_FIELDS = frozenset(["header", "elements"])

#: `expect=` values. `fail` is not an error: a scenario asserting that a path
#: outside the tftp root is refused wants the refusal to be the passing result.
EXPECTATIONS = frozenset(["ok", "fail", "any"])


def known_step_types():
    return frozenset(STEP_KEYS)


def allowed_keys(step_type):
    return COMMON_KEYS | STEP_KEYS.get(step_type, frozenset())


def all_reply_fields():
    """Every field name any step type can produce."""
    names = set()
    for fields in REPLY_FIELDS.values():
        names.update(fields)
    return names


def check_field(field):
    """True when `field` is a name some step type's reply could carry.

    Cross-type: a `$step.field` reference is resolved against whichever step
    it names, and which step that is cannot be known from the text alone when
    the reference is written in `[defaults]`. Validation is therefore that the
    name exists *somewhere*; naming a field of the wrong type fails at run
    time, where the reply is in hand and the message can say so.
    """
    head, _, tail = field.rpartition(".")
    if head:
        if head in MAPPING_FIELDS:
            return bool(tail)
        if head not in all_reply_fields():
            return False
        try:
            int(tail)
        except ValueError:
            return False
        return True
    return field in all_reply_fields()


def validate_scenario(scenario):
    """Every problem in one scenario, as a list of strings.

    Returns rather than raises, so one pass over a file reports everything
    wrong with it instead of the first thing.
    """
    problems = []
    seen = set()
    for step in scenario.steps:
        where = "%s scenario %r step %r" % (scenario.source, scenario.name, step.name)
        if step.name in seen:
            problems.append("%s: step %r is defined twice" % (where, step.name))
        seen.add(step.name)

        problems.extend(_validate_required(step, where))
        problems.extend(_validate_expect(step, where))
        problems.extend(_validate_targets(step, where))
        problems.extend(_validate_references(step, scenario, seen, where))
    return problems


def _validate_required(step, where):
    problems = []
    for key in REQUIRED_KEYS.get(step.type, ()):
        if not step.param(key):
            problems.append("%s: a %s step needs %s=" % (where, step.type, key))
    if step.type == "http" and not step.param("url"):
        if not (step.param("server") and step.param("path")):
            problems.append(
                "%s: an http step needs url=, or server= and path=" % (where,))
    if step.type == "extract":
        group = step.param("group")
        if group not in (None, ""):
            try:
                int(group)
            except ValueError:
                problems.append("%s: group= must be a number, got %r"
                                % (where, group))
    return problems


def _validate_expect(step, where):
    if step.expect and step.expect not in EXPECTATIONS:
        return ["%s: unknown expect=%r (known: %s)"
                % (where, step.expect, ", ".join(sorted(EXPECTATIONS)))]
    return []


def _validate_targets(step, where):
    problems = []
    fields = REPLY_FIELDS.get(step.type, frozenset())
    for assertion in step.assertions:
        target = assertion.target
        if target.startswith("$"):
            continue
        head, _, tail = target.rpartition(".")
        if head in MAPPING_FIELDS:
            if head not in fields:
                problems.append("%s: a %s reply carries no %s"
                                % (where, step.type, head))
            continue
        base = head or target
        if base not in fields:
            problems.append(
                "%s: a %s reply has no field %r (it has: %s)"
                % (where, step.type, target, ", ".join(sorted(fields))))
    return problems


def _validate_references(step, scenario, seen, where):
    """Reject a `$step.field` naming a step that does not run before this one."""
    problems = []
    texts = [assertion.value for assertion in step.assertions]
    texts.extend(str(value) for value in step.params.values())
    texts.extend(assertion.target for assertion in step.assertions)
    for text in texts:
        for name, field in subst.references(text):
            if name not in seen:
                problems.append(
                    "%s: $%s.%s refers to a step that has not run yet"
                    % (where, name, field))
            elif not check_field(field):
                problems.append("%s: no reply field is called .%s" % (where, field))
    return problems


def required_variables(scenarios):
    """Every `%(name)s` a run of these scenarios would have to be given."""
    names = set()
    for scenario in scenarios:
        for step in scenario.steps:
            for value in step.params.values():
                names.update(subst.variables(value))
            for assertion in step.assertions:
                names.update(subst.variables(assertion.value))
                names.update(subst.variables(assertion.target))
    return names


def check_type(step_type, where=""):
    if step_type not in STEP_KEYS:
        raise ConfigError(
            "unknown step type %r (known: %s)"
            % (step_type, ", ".join(sorted(STEP_KEYS))), where)
