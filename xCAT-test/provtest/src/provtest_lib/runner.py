"""Executing scenarios: one step at a time, in the order they were written.

A step is dispatched to the client for its protocol, its reply is bound under
the step's name so later steps can refer to it, and its assertions are then
evaluated against that reply. Binding before asserting is what makes the
cross-stage cases work: a TFTP step fetches a grub config, an extract step
pulls the kernel path out of it, and an HTTP step fetches exactly that path --
none of which is possible if a step can only see values written in the file.
"""

import re
import sys
import time

from . import assertions as assertions_mod
from . import dnsc, httpc, machine, report, subst, tftpc, xcatc
from .errors import ConfigError, ProvTestError
from .model import Reply

#: Step types whose "ok" is decided by the step itself rather than a server.
LOCAL_TYPES = frozenset(["extract", "sleep", "noop"])


class RunOptions(object):
    """Command-line overrides, applied on top of what the .conf says."""

    __slots__ = ("bind", "timeout", "retries", "verbose")

    def __init__(self, bind=None, timeout=None, retries=None, verbose=0):
        self.bind = bind
        self.timeout = timeout
        self.retries = retries
        self.verbose = verbose


def run(scenarios, reporter, options):
    """Run every scenario and return the process exit code."""
    reporter.start()
    for scenario in scenarios:
        _run_scenario(scenario, reporter, options)
    reporter.finish()
    return reporter.exit_code()


def _run_scenario(scenario, reporter, options):
    context = subst.Context()
    for step in scenario.steps:
        try:
            reply, attempt, attempts = _execute(step, context, options)
        except ProvTestError as exc:
            reporter.add(report.Record(
                scenario.name, step.name, "step could not be run", ok=False,
                detail=str(exc)))
            return
        context.bind(step.name, reply)
        if options.verbose:
            sys.stderr.write("# %s/%s: %s\n"
                             % (scenario.name, step.name, reply.summary()))

        extras = {"attempt": attempt}
        _check_expectation(scenario, step, reply, reporter, attempt, attempts)
        for assertion in step.assertions:
            try:
                result = assertions_mod.evaluate(assertion, reply, context, extras)
            except ConfigError as exc:
                reporter.add(report.Record(
                    scenario.name, step.name, assertion.render(), ok=False,
                    detail=str(exc), reply=reply, sent=reply.sent))
                continue
            reporter.add(report.Record(
                scenario.name, step.name, assertion.render(), ok=result.ok,
                expected=result.expected, actual=result.actual,
                detail=result.detail, reply=reply, sent=reply.sent,
                attempt=attempt, attempts=attempts))


def _check_expectation(scenario, step, reply, reporter, attempt, attempts):
    """Report the transport outcome itself, unless the step waived it.

    The default is `ok`, so a step whose server never answered fails even when
    the author wrote no assertion about it. Silence is not a pass.
    """
    expect = step.expect or ("any" if step.type in LOCAL_TYPES else "ok")
    if expect == "any":
        return
    wanted = (expect == "ok")
    description = "expect %s" % (expect,)
    reporter.add(report.Record(
        scenario.name, step.name, description, ok=(reply.ok == wanted),
        expected=expect, actual="ok" if reply.ok else "failed",
        detail=reply.error, reply=reply, sent=reply.sent,
        attempt=attempt, attempts=attempts))


def _execute(step, context, options):
    """Run one step, retrying only a transport that was expected to work."""
    retries = options.retries if options.retries is not None else step.retries
    retries = max(1, int(retries))
    expect = step.expect or ("any" if step.type in LOCAL_TYPES else "ok")

    reply = None
    for attempt in range(1, retries + 1):
        reply = _dispatch(step, context, options)
        reply.attempt = attempt
        if expect != "ok" or reply.ok or attempt == retries:
            return reply, attempt, retries
        time.sleep(0.2)
    return reply, retries, retries


def _dispatch(step, context, options):
    handler = HANDLERS.get(step.type)
    if handler is None:
        raise ConfigError("no handler for step type %r" % (step.type,), step.source)
    return handler(step, context, options)


# ---------------------------------------------------------------------------
# per-type handlers


def _dns(step, context, options):
    param = _resolver(step, context)
    return dnsc.query(
        server=param("server"),
        name=param("name"),
        rrtype=param("rrtype") or "A",
        port=_int(param("port"), 53),
        bind=param("bind") or options.bind,
        recursion=_bool(param("recursion"), True),
        timeout=_timeout(step, options),
    )


def _tftp(step, context, options):
    param = _resolver(step, context)
    return tftpc.fetch(
        server=param("server"),
        path=param("path"),
        port=_int(param("port"), 69),
        mode=param("mode") or "octet",
        timeout=_timeout(step, options),
    )


def _http(step, context, options):
    param = _resolver(step, context)
    url = param("url")
    if not url:
        url = httpc.url_for(param("server"), param("path"),
                            _int(param("port"), 80))
    headers = [line.strip() for line in (param("header") or "").splitlines()
               if line.strip()]
    return httpc.fetch(
        url=url,
        method=param("method") or "GET",
        bind=param("bind") or options.bind,
        headers=headers,
        timeout=_timeout(step, options),
        insecure=_bool(param("insecure"), False),
    )


def _xcatreq(step, context, options):
    param = _resolver(step, context)
    return xcatc.request(
        server=param("server"),
        command=param("command"),
        port=_int(param("port"), 3001),
        elements=_pairs(param("element")),
        bind=param("bind") or options.bind,
        timeout=_timeout(step, options),
        cert=param("cert") or None,
        key=param("key") or None,
        callback_port=param("callback_port") or None,
        callback_listen=param("callback_listen") or None,
        callback_reply=param("callback_reply") or None,
        callback_wait=_float(param("callback_wait"), 2.0),
        raw=param("raw") or None,
        source_port=_int(param("source_port"), 0),
    )


def _monitor(step, context, options):
    param = _resolver(step, context)
    send = [line.strip() for line in (param("send") or "").splitlines()
            if line.strip()]
    return xcatc.monitor(
        server=param("server"),
        send=send,
        port=_int(param("port"), 3002),
        bind=param("bind") or options.bind,
        timeout=_timeout(step, options),
        source_port=_int(param("source_port"), 0),
    )


def _flowrequest(step, context, options):
    param = _resolver(step, context)
    return xcatc.flowrequest(
        server=param("server"),
        port=_int(param("port"), 3001),
        message=param("message") or "resourcerequest: xcatd",
        bind=param("bind") or options.bind,
        timeout=_timeout(step, options),
        source_port=_int(param("source_port"), 0),
        expected=_int(param("replies"), 1),
    )


def _findme(step, context, options):
    param = _resolver(step, context)
    payload = param("payload")
    if not payload:
        payload = xcatc.discovery_packet()
    return xcatc.findme(
        server=param("server"),
        payload=payload,
        port=_int(param("port"), 3001),
        encoding=(param("encoding") or "gzip").lower(),
        bind=param("bind") or options.bind,
        source_port=_int(param("source_port"), 301),
        timeout=_timeout(step, options),
        callback_listen=_int(param("callback_listen"), 3001),
        callback_wait=_float(param("callback_wait"), 5.0),
    )


def _extract(step, context, options):
    """Pull a value out of an earlier reply, so a later step can fetch it.

    This is the join between stages. A grub2 config names a kernel; nothing in
    the config file says what that name will be, and hard-coding it would make
    the test assert xCAT's output against a copy of xCAT's output. Extracting
    it and then fetching it asserts the only thing that matters: that what the
    node was told to fetch can be fetched.
    """
    param = _resolver(step, context)
    source = param("from") or ""
    pattern = step.param("pattern") or ""
    try:
        regex = re.compile(pattern, re.MULTILINE)
    except re.error as exc:
        raise ConfigError("bad regex %r: %s" % (pattern, exc), step.source)

    match = regex.search(source)
    groups = list(match.groups()) if match else []
    index = _int(param("group"), 1 if groups else 0)
    value = ""
    if match:
        if index > len(groups):
            raise ConfigError(
                "group=%d, but %r has %d capturing group(s)"
                % (index, pattern, len(groups)), step.source)
        value = match.group(index) or ""

    fields = {
        "value": value,
        "groups": [text or "" for text in groups],
        "matched": bool(match),
        "count": len(groups),
    }
    return Reply(kind="extract", fields=fields, ok=bool(match),
                 error="" if match else "%r matched nothing" % (pattern,),
                 sent="match %r" % (pattern,))


def _sleep(step, context, options):
    param = _resolver(step, context)
    duration = _float(param("duration"), 1.0)
    time.sleep(duration)
    return Reply(kind="sleep", fields={}, ok=True,
                 sent="slept %.1fs" % (duration,))


def _noop(step, context, options):
    return Reply(kind="noop", fields={}, ok=True, sent="")


HANDLERS = {
    "dns": _dns,
    "tftp": _tftp,
    "http": _http,
    "xcatreq": _xcatreq,
    "monitor": _monitor,
    "flowrequest": _flowrequest,
    "findme": _findme,
    "extract": _extract,
    "sleep": _sleep,
    "noop": _noop,
}

assert set(HANDLERS) == machine.known_step_types()


# ---------------------------------------------------------------------------
# parameter handling


def _resolver(step, context):
    """A `param(key)` that resolves `$step.field` against what has run."""

    def param(key, default=""):
        value = step.param(key, default)
        if value in (None, ""):
            return value
        return subst.resolve(value, context)

    return param


def _timeout(step, options):
    return options.timeout if options.timeout is not None else step.timeout


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
    if value in (None, ""):
        return default
    text = str(value).strip().lower()
    if text in ("1", "yes", "true", "on"):
        return True
    if text in ("0", "no", "false", "off"):
        return False
    raise ConfigError("expected a yes/no value, got %r" % (value,))


def _pairs(block):
    """`name = value` lines under an `element` key, as an ordered list."""
    pairs = []
    for line in (block or "").splitlines():
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        name, _, value = text.partition("=")
        pairs.append((name.strip(), value.strip()))
    return pairs
