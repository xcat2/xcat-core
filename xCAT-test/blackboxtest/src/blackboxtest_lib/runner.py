"""Running scenarios: one step at a time, in file order.

Each reply is bound under its step's name before the step's assertions run,
so a later step, or an assertion, can use it: TFTP fetches a grub config, an
extract step reads the kernel path out of it, and HTTP fetches that path.
"""

import re
import sys
import time

from . import (assertions, dhcp, dnsc, httpc, netutil, proc, report, steps,
               subst, tftpc, xcatc)
from .errors import BlackboxError, ConfigError
from .model import Reply


class RunOptions(object):
    """Command-line overrides, applied over what the .conf says."""

    def __init__(self, interface=None, bind=None, timeout=None, retries=None,
                 verbose=0):
        self.interface = interface
        self.bind = bind
        self.timeout = timeout
        self.retries = retries
        self.verbose = verbose


def preflight(scenarios):
    """Refuse a host that lacks a client program or DHCP's root and scapy.

    Done before any output: a run of skips would be a green result that
    proves nothing.
    """
    types = set(step.type for scenario in scenarios for step in scenario.steps)
    for step_type in sorted(types):
        kind = steps.TYPES[step_type]
        if kind.program:
            proc.require(kind.program, step_type)
    if any(steps.TYPES[t].family == "dhcp" for t in types):
        dhcp.require()


def run(scenarios, reporter, options):
    """Run every scenario and return the process exit code."""
    preflight(scenarios)
    reporter.start()
    for scenario in scenarios:
        _run_scenario(scenario, reporter, options)
    reporter.finish()
    return reporter.exit_code()


def _run_scenario(scenario, reporter, options):
    session = None
    if any(steps.TYPES[s.type].family == "dhcp" for s in scenario.steps):
        interface = options.interface or scenario.interface
        # A shared .conf may name a NIC that only some hosts have.
        if not interface or not netutil.interface_exists(interface):
            reason = "no such interface: %s" % (interface,) if interface \
                else "no interface; pass -i"
            for step in scenario.steps:
                for assertion in step.assertions:
                    reporter.add(report.Record(scenario.name, step.name,
                                               assertion.render(), True,
                                               skip_reason=reason))
            return
        session = dhcp.Session(dhcp.Wire(interface))

    context = subst.Context()
    try:
        for step in scenario.steps:
            try:
                reply, extras = _run_step(step, context, session, options)
            except BlackboxError as exc:
                reporter.add(report.Record(scenario.name, step.name,
                                           "step could not be run", False,
                                           detail=str(exc)))
                return
            if options.verbose:
                sys.stderr.write("# %s/%s: %s\n" % (
                    scenario.name, step.name,
                    reply.summary() if reply else "no reply"))
            _record(scenario, step, reply, context, extras, reporter)
    finally:
        if session is not None:
            session.wire.close()


def _run_step(step, context, session, options):
    """Run one step; return `(reply or None, extras)`, the step name bound."""
    kind = steps.TYPES[step.type]
    timeout = options.timeout if options.timeout is not None else step.timeout
    retries = max(1, options.retries if options.retries is not None
                  else step.retries)

    if kind.family == "dhcp":
        reply, extras, sent = dhcp.run_step(step, session, context, timeout,
                                            retries)
        extras["sent"] = sent
        extras["attempts"] = retries
    else:
        handler = HANDLERS[step.type]
        param = _resolver(step, context, options)
        expect = step.expect or ("any" if kind.family == "local" else "ok")
        # Retry only a transport that was expected to work.
        for attempt in range(1, retries + 1):
            reply = handler(step, param, timeout)
            reply.attempt = attempt
            if expect != "ok" or reply.ok or attempt == retries:
                break
            time.sleep(0.2)
        extras = {"attempt": attempt, "attempts": retries, "expect": expect,
                  "got": "ok" if reply.ok else "failed",
                  "met": reply.ok == (expect == "ok")}

    if reply is not None:
        context.bind(step.name, reply)
    return reply, extras


def _record(scenario, step, reply, context, extras, reporter):
    common = dict(reply=reply, sent=reply.sent if reply else extras.get("sent", ""),
                  attempt=extras["attempt"], attempts=extras["attempts"])

    # The expectation is a test point of its own. A step that waited for an
    # answer and got none fails with no assertion about it, and an
    # `expect = none` step fails when something does answer.
    expect = extras.get("expect", "any")
    if expect != "any":
        reporter.add(report.Record(
            scenario.name, step.name, "expect %s" % (expect,), extras["met"],
            expected=expect, actual=extras["got"],
            detail=reply.error if reply else "", **common))

    for assertion in step.assertions:
        try:
            result = assertions.evaluate(assertion, reply, context, extras)
        except ConfigError as exc:
            reporter.add(report.Record(scenario.name, step.name,
                                       assertion.render(), False,
                                       detail=str(exc), **common))
            continue
        reporter.add(report.Record(
            scenario.name, step.name, assertion.render(), result.ok,
            expected=result.expected, actual=result.actual,
            detail=result.detail, **common))


# ---------------------------------------------------------------------------
# handlers for the service and local steps


def _resolver(step, context, options):
    """A `param(key)` that resolves `$step.field` and applies `-b`."""

    def param(key, default=""):
        value = step.param(key, default)
        if key == "bind" and not value:
            value = options.bind or ""
        if value in (None, ""):
            return value
        return subst.resolve(value, context)

    return param


def _dns(step, param, timeout):
    return dnsc.query(server=param("server"), name=param("name"),
                      rrtype=param("rrtype") or "A", port=_int(param("port"), 53),
                      bind=param("bind"), timeout=timeout,
                      recursion=_bool(param("recursion"), True))


def _tftp(step, param, timeout):
    return tftpc.fetch(server=param("server"), path=param("path"),
                       port=_int(param("port"), 69),
                       mode=param("mode") or "octet", timeout=timeout)


def _http(step, param, timeout):
    url = param("url") or httpc.url_for(param("server"), param("path"),
                                        _int(param("port"), 80))
    return httpc.fetch(url=url, method=param("method") or "GET",
                       bind=param("bind"), timeout=timeout,
                       headers=_lines(param("header")),
                       insecure=_bool(param("insecure"), False))


def _xcatreq(step, param, timeout):
    elements = [tuple(part.strip() for part in line.partition("=")[::2])
                for line in _lines(param("element")) if not line.startswith("#")]
    return xcatc.request(
        server=param("server"), command=param("command"),
        port=_int(param("port"), 3001), elements=elements, bind=param("bind"),
        timeout=timeout, cert=param("cert") or None, key=param("key") or None,
        callback_port=param("callback_port") or None,
        callback_listen=param("callback_listen") or None,
        callback_reply=param("callback_reply") or None,
        callback_wait=_float(param("callback_wait"), 2.0),
        raw=param("raw") or None, source_port=_int(param("source_port"), 0))


def _monitor(step, param, timeout):
    return xcatc.monitor(server=param("server"), send=_lines(param("send")),
                         port=_int(param("port"), 3002), bind=param("bind"),
                         timeout=timeout,
                         source_port=_int(param("source_port"), 0))


def _flowrequest(step, param, timeout):
    return xcatc.flowrequest(
        server=param("server"), port=_int(param("port"), 3001),
        message=param("message") or "resourcerequest: xcatd",
        bind=param("bind"), timeout=timeout,
        source_port=_int(param("source_port"), 0),
        expected=_int(param("replies"), 1))


def _findme(step, param, timeout):
    return xcatc.findme(
        server=param("server"),
        payload=param("payload") or xcatc.discovery_packet(),
        port=_int(param("port"), 3001),
        encoding=(param("encoding") or "gzip").lower(), bind=param("bind"),
        source_port=_int(param("source_port"), 301), timeout=timeout,
        callback_listen=_int(param("callback_listen"), 3001),
        callback_wait=_float(param("callback_wait"), 5.0))


def _extract(step, param, timeout):
    """Read a value out of an earlier reply, so a later step can fetch it.

    A grub2 config names a kernel. Fetching the name read out of the config
    tests that what the node was told to fetch can be fetched, without the
    scenario stating what xCAT will call it.
    """
    pattern = step.param("pattern") or ""
    try:
        match = re.compile(pattern, re.MULTILINE).search(param("from") or "")
    except re.error as exc:
        raise ConfigError("bad regex %r: %s" % (pattern, exc), step.source)
    groups = list(match.groups()) if match else []
    index = _int(param("group"), 1 if groups else 0)
    if match and index > len(groups):
        raise ConfigError("group=%d, but %r has %d capturing group(s)"
                          % (index, pattern, len(groups)), step.source)
    fields = {
        "value": (match.group(index) or "") if match else "",
        "groups": [text or "" for text in groups],
        "matched": bool(match),
        "count": len(groups),
    }
    return Reply("extract", fields, ok=bool(match),
                 error="" if match else "%r matched nothing" % (pattern,),
                 sent="match %r" % (pattern,))


def _noop(step, param, timeout):
    return Reply("noop")


HANDLERS = {
    "dns": _dns, "tftp": _tftp, "http": _http, "xcatreq": _xcatreq,
    "monitor": _monitor, "flowrequest": _flowrequest, "findme": _findme,
    "extract": _extract, "noop": _noop,
}

assert set(HANDLERS) == set(t for t, k in steps.TYPES.items()
                            if k.family != "dhcp")


def _lines(block):
    return [line.strip() for line in (block or "").splitlines() if line.strip()]


def _int(value, default):
    if value in (None, ""):
        return default
    try:
        return int(str(value).strip(), 0)
    except ValueError:
        raise ConfigError("expected a number, got %r" % (value,))


def _float(value, default):
    if value in (None, ""):
        return default
    try:
        return float(str(value).strip())
    except ValueError:
        raise ConfigError("expected a number, got %r" % (value,))


def _bool(value, default):
    text = str(value or "").strip().lower()
    if not text:
        return default
    if text in ("1", "yes", "true", "on"):
        return True
    if text in ("0", "no", "false", "off"):
        return False
    raise ConfigError("expected yes or no, got %r" % (value,))
