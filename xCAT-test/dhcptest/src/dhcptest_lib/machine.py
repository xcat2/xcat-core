"""The DHCP client state machine.

The transition table below is a subset of the RFC 2131 client FSM. Keeping it
as data rather than as control flow buys two things:

  * `dhcptest validate` can walk a scenario without touching the network, so a
    `request` step with no preceding `discover` is a configuration error caught
    in CI rather than a mystery in a lab;
  * the table is the protocol documentation, and is trivially unit testable.

This module stays importable without scapy. `run_step` imports the packet and
transport layers lazily, so `validate` and `list` work on a host that has no
scapy and no privileges.
"""

from . import assertions as assertions_mod
from . import subst
from .errors import ConfigError

# States
INIT = "INIT"
SELECTING = "SELECTING"
REQUESTING = "REQUESTING"
BOUND = "BOUND"
RENEWING = "RENEWING"
REBINDING = "REBINDING"

ANY = "*"

#: Step types that send nothing and therefore have no transition.
PASSIVE_TYPES = frozenset(["noop", "sleep"])


class Transition(object):
    """One legal (state, step type) pair and what it does."""

    __slots__ = ("expects", "default_expect", "next_state", "nak_state",
                 "requires", "binds", "unicast")

    def __init__(self, expects, default_expect, next_state, nak_state=None,
                 requires=(), binds=(), unicast=False):
        self.expects = frozenset(expects)
        self.default_expect = default_expect
        self.next_state = next_state
        self.nak_state = nak_state
        self.requires = tuple(requires)
        self.binds = tuple(binds)
        self.unicast = unicast


TRANSITIONS = {
    (INIT, "discover"): Transition(
        expects=["offer"], default_expect="offer", next_state=SELECTING,
        binds=("offer",)),

    # A BOOTREQUEST is what a client that predates DHCP sends: the same BOOTP
    # header with no option 53 at all. There is no handshake to follow it --
    # the single BOOTREPLY is the whole exchange -- so it leaves the session in
    # INIT rather than moving on to SELECTING.
    (INIT, "bootrequest"): Transition(
        expects=["bootreply"], default_expect="bootreply", next_state=INIT,
        binds=("reply",)),

    (SELECTING, "request"): Transition(
        expects=["ack", "nak"], default_expect="ack", next_state=BOUND,
        nak_state=INIT, binds=("ack", "lease")),

    # INIT-REBOOT: a REQUEST with option 50 and no option 54.
    (INIT, "request"): Transition(
        expects=["ack", "nak"], default_expect="ack", next_state=BOUND,
        nak_state=INIT, requires=("requested_address",), binds=("ack", "lease")),

    (BOUND, "renew"): Transition(
        expects=["ack", "nak"], default_expect="ack", next_state=BOUND,
        nak_state=INIT, binds=("ack", "lease"), unicast=True),

    (RENEWING, "renew"): Transition(
        expects=["ack", "nak"], default_expect="ack", next_state=BOUND,
        nak_state=INIT, binds=("ack", "lease"), unicast=True),

    (BOUND, "rebind"): Transition(
        expects=["ack", "nak"], default_expect="ack", next_state=BOUND,
        nak_state=INIT, binds=("ack", "lease")),

    (RENEWING, "rebind"): Transition(
        expects=["ack", "nak"], default_expect="ack", next_state=BOUND,
        nak_state=INIT, binds=("ack", "lease")),

    (BOUND, "release"): Transition(
        expects=[], default_expect="none", next_state=INIT, unicast=True),

    (BOUND, "decline"): Transition(
        expects=[], default_expect="none", next_state=INIT),

    # INFORM asks for configuration without asking for an address, and is legal
    # from any state.
    (ANY, "inform"): Transition(
        expects=["ack"], default_expect="ack", next_state=None,
        binds=("ack",)),
}

#: Bindings that exist before any step runs.
INITIAL_BINDINGS = frozenset()


def transition_for(state, step_type):
    """The transition for `(state, step_type)`, or None."""
    if (state, step_type) in TRANSITIONS:
        return TRANSITIONS[(state, step_type)]
    return TRANSITIONS.get((ANY, step_type))


def known_step_types():
    types = set(PASSIVE_TYPES)
    types.update(step_type for _, step_type in TRANSITIONS)
    return types


def states_allowing(step_type):
    """Which states a step type is legal in -- used to explain a rejection."""
    states = [state for state, kind in TRANSITIONS if kind == step_type]
    return sorted(states)


# ---------------------------------------------------------------------------
# offline validation


def validate_scenario(scenario):
    """Walk a scenario without sending anything.

    Returns a list of human-readable problems; empty means the scenario is
    internally consistent. Nothing here needs root, a network, or scapy.
    """
    problems = []
    state = INIT
    available = set()          # no binding exists until a step produces one
    seen_names = set()

    for step in scenario.steps:
        where = "%s/%s" % (scenario.name, step.name)

        if step.name in seen_names:
            problems.append("%s: duplicate step name %r" % (where, step.name))
        seen_names.add(step.name)

        problems.extend(_check_references(step, available, where))

        if step.type in PASSIVE_TYPES:
            available.add(step.name)
            continue

        if step.type not in known_step_types():
            problems.append(
                "%s: unknown step type %r (known: %s)"
                % (where, step.type, ", ".join(sorted(known_step_types()))))
            continue

        transition = transition_for(state, step.type)
        if transition is None:
            allowed = states_allowing(step.type)
            problems.append(
                "%s: a %r step is not legal in state %s (legal in: %s)"
                % (where, step.type, state, ", ".join(allowed) or "no state"))
            continue

        for required in transition.requires:
            if not step.param(required):
                problems.append(
                    "%s: a %r step in state %s needs %s="
                    % (where, step.type, state, required))

        expect = step.expect or transition.default_expect
        if expect not in ("none", "any") and expect not in transition.expects:
            problems.append(
                "%s: expect=%s is not a possible reply to %r in state %s "
                "(possible: %s)"
                % (where, expect, step.type, state,
                   ", ".join(sorted(transition.expects)) or "nothing"))

        available.add(step.name)
        if expect not in ("none",):
            available.add("reply")
            for name in transition.binds:
                available.add(name)

        # A step that expected a reply and got none leaves the client where it
        # was: a DISCOVER nobody answers does not put it in SELECTING. RELEASE
        # and DECLINE are the other kind of silence -- no reply is ever sent to
        # them, and giving the lease up is the whole point of the step -- so
        # they move the client on regardless.
        if expect == "none" and transition.expects:
            continue
        if transition.next_state:
            state = transition.next_state

    return problems


def _check_references(step, available, where):
    """Every `$binding.field` a step uses must already be bound."""
    problems = []
    values = list(step.params.values())
    values.extend(a.value for a in step.assertions if a.value is not None)
    values.extend(a.target for a in step.assertions)
    values.extend(a.value for a in step.assertions_all if a.value is not None)
    values.extend(a.target for a in step.assertions_all)

    for value in values:
        for name, field in subst.references(value):
            if name not in available:
                problems.append(
                    "%s: $%s.%s is used before anything binds $%s"
                    % (where, name, field, name))
            elif not subst.check_field(field):
                problems.append(
                    "%s: $%s.%s is not a field of a DHCP reply"
                    % (where, name, field))
    return problems


def required_variables(scenarios):
    """Every `%(name)s` the given scenarios still need.

    Only meaningful on scenarios loaded raw: once configparser has
    interpolated a value, the name it came from is gone.
    """
    names = set()
    for scenario in scenarios:
        for step in scenario.steps:
            values = list(step.params.values())
            values.extend(a.value for a in step.assertions if a.value is not None)
            values.extend(a.value for a in step.assertions_all
                          if a.value is not None)
            for value in values:
                names.update(subst.variables(value))
    return names


def expected_types(step, state):
    """The DHCP message types a step will accept as its reply."""
    transition = transition_for(state, step.type)
    if transition is None:
        raise ConfigError("no transition for %s in state %s" % (step.type, state))
    expect = step.expect or transition.default_expect
    if expect == "none":
        return frozenset()
    if expect == "any":
        return transition.expects
    return frozenset([expect])


def evaluate_step(step, reply, context, extras=None):
    """Run a step's assertions against its reply. Returns a list of Results."""
    results = []
    for assertion in step.assertions:
        results.append(
            assertions_mod.evaluate(assertion, reply, context, extras))
    return results
