"""Offline checks: what `validate` reports without opening a socket.

Walks each scenario the way the runner will, so a REQUEST with no DISCOVER
before it, a misspelt reply field, or a reference to a step that has not run
is reported in a checkout, with no root, no network and no server.
"""

from . import dhcp, netutil, steps, subst
from .assertions import META_TARGETS


def scenario_problems(scenario):
    """Every problem in one scenario, as strings. Empty means consistent."""
    problems = []
    bound = {}                 # binding name -> the step type that bound it
    state = dhcp.INIT

    for step in scenario.steps:
        where = "%s: %s/%s" % (scenario.source, scenario.name, step.name)
        kind = steps.TYPES[step.type]

        def check(text, names):
            for name, field in subst.references(text):
                if name not in names:
                    problems.append("%s: $%s.%s is used before anything binds $%s"
                                    % (where, name, field, name))
                elif not steps.known_field(names[name], field):
                    problems.append("%s: a %s reply has no field .%s"
                                    % (where, names[name], field))

        if step.name in bound:
            problems.append("%s: step name %r is used twice" % (where, step.name))
        for key in kind.required:
            if not step.param(key):
                problems.append("%s: a %s step needs %s=" % (where, step.type, key))
        if step.type == "http" and not step.param("url") \
                and not (step.param("server") and step.param("path")):
            problems.append("%s: an http step needs url=, or server= and path="
                            % (where,))
        if step.expect and step.expect not in kind.expectations():
            problems.append("%s: unknown expect=%s (known: %s)"
                            % (where, step.expect,
                               ", ".join(sorted(kind.expectations()))))
        for value in step.params.values():
            check(value, bound)

        if kind.family == "dhcp":
            state = _walk_dhcp(step, state, bound, where, problems)
        bound[step.name] = step.type

        # An assertion runs after its own step has bound its reply.
        for assertion in step.assertions:
            check(assertion.value, bound)
            target = assertion.target
            if target.startswith("$"):
                if len(subst.references(target)) != 1:
                    problems.append("%s: target %r must be one $step.field"
                                    % (where, target))
                check(target, bound)
            elif target not in META_TARGETS \
                    and not steps.known_field(step.type, target):
                problems.append("%s: a %s reply has no field %r"
                                % (where, step.type, target))
    return problems


def _walk_dhcp(step, state, bound, where, problems):
    """Check one DHCP step against the client state; return the next state."""
    mac = step.param("mac") or ""
    if mac and "$" not in mac and not subst.variables(mac):
        try:
            netutil.normalise_mac(mac)
        except Exception as exc:
            problems.append("%s: %s" % (where, exc))

    trans = dhcp.transition(state, step.type)
    if trans is None:
        legal = sorted(s for s, kind in dhcp.TRANSITIONS if kind == step.type)
        problems.append("%s: a %s step is not legal in state %s (legal in: %s)"
                        % (where, step.type, state, ", ".join(legal)))
        return state
    for key in trans.requires:
        if not step.param(key):
            problems.append("%s: a %s step in state %s needs %s="
                            % (where, step.type, state, key))
    expect = step.expect or trans.default_expect
    if expect not in ("none", "any") and expect not in trans.expects:
        problems.append("%s: expect=%s is not a reply to %s in state %s "
                        "(possible: %s)"
                        % (where, expect, step.type, state,
                           ", ".join(sorted(trans.expects)) or "nothing"))
    answered = expect != "none"
    if answered:
        bound["reply"] = step.type
        for name in trans.binds:
            bound[name] = step.type
    return dhcp.advance(state, trans, answered)


def required_variables(scenarios):
    """Every `%(name)s` the scenarios, loaded raw, still need a value for."""
    names = set()
    for scenario in scenarios:
        for step in scenario.steps:
            for value in step.params.values():
                names.update(subst.variables(value))
            for assertion in step.assertions:
                names.update(subst.variables(assertion.value))
                names.update(subst.variables(assertion.target))
    return names
