"""Result reporting: TAP 13 by default, plus human and JSON forms.

TAP is the default because `prove` consumes it directly, which is how this
repository already drives its Perl integration tests. The failure diagnostic
carries expected, received, the whole decoded reply and a summary of what was
sent, so a red test can be understood without re-running it.
"""

import json
import sys

from .errors import EXIT_FAILED, EXIT_OK
from . import options as options_mod


class Record(object):
    """One assertion outcome, with everything needed to explain it."""

    __slots__ = ("scenario", "step", "description", "ok", "skip_reason",
                 "expected", "actual", "detail", "reply", "sent", "attempt",
                 "attempts")

    def __init__(self, scenario, step, description, ok, skip_reason=None,
                 expected=None, actual=None, detail="", reply=None, sent="",
                 attempt=0, attempts=0):
        self.scenario = scenario
        self.step = step
        self.description = description
        self.ok = ok
        self.skip_reason = skip_reason
        self.expected = expected
        self.actual = actual
        self.detail = detail
        self.reply = reply
        self.sent = sent
        self.attempt = attempt
        self.attempts = attempts

    @property
    def name(self):
        return "%s/%s: %s" % (self.scenario, self.step, self.description)


class Reporter(object):
    """Base reporter: counts, and an exit code."""

    def __init__(self, stream=None):
        self.stream = stream or sys.stdout
        self.records = []
        self.passed = 0
        self.failed = 0
        self.skipped = 0

    def add(self, record):
        self.records.append(record)
        if record.skip_reason is not None:
            self.skipped += 1
        elif record.ok:
            self.passed += 1
        else:
            self.failed += 1
        self.emit(record)

    def emit(self, record):
        raise NotImplementedError

    def start(self):
        pass

    def finish(self):
        pass

    def exit_code(self):
        return EXIT_FAILED if self.failed else EXIT_OK

    def write(self, text):
        self.stream.write(text)
        self.stream.flush()


class TapReporter(Reporter):
    """TAP version 13, with a trailing plan and YAML failure diagnostics."""

    def start(self):
        self.write("TAP version 13\n")

    def emit(self, record):
        number = len(self.records)
        status = "ok" if (record.ok or record.skip_reason is not None) else "not ok"
        line = "%s %d - %s" % (status, number, record.name)
        if record.skip_reason is not None:
            line += " # SKIP %s" % (record.skip_reason,)
        self.write(line + "\n")
        if not record.ok and record.skip_reason is None:
            self.write(_yaml_block(record))

    def finish(self):
        self.write("1..%d\n" % (len(self.records),))
        self.write("# passed %d, failed %d, skipped %d\n"
                   % (self.passed, self.failed, self.skipped))


class PrettyReporter(Reporter):
    """Human-first output carrying the same information as the TAP form."""

    def __init__(self, stream=None):
        Reporter.__init__(self, stream)
        self._scenario = None

    def emit(self, record):
        if record.scenario != self._scenario:
            self._scenario = record.scenario
            self.write("\n%s\n" % (record.scenario,))
        if record.skip_reason is not None:
            self.write("  SKIP %s/%s -- %s\n"
                       % (record.step, record.description, record.skip_reason))
            return
        mark = "PASS" if record.ok else "FAIL"
        self.write("  %s %s: %s\n" % (mark, record.step, record.description))
        if not record.ok:
            for line in _diagnostic_lines(record):
                self.write("       %s\n" % (line,))

    def finish(self):
        self.write("\nDHCPTEST SUMMARY: total=%d passed=%d failed=%d skipped=%d\n"
                   % (len(self.records), self.passed, self.failed, self.skipped))


class JsonReporter(Reporter):
    """One JSON object per run, for callers that would rather not parse text."""

    def emit(self, record):
        pass

    def finish(self):
        payload = {
            "total": len(self.records),
            "passed": self.passed,
            "failed": self.failed,
            "skipped": self.skipped,
            "records": [_as_dict(record) for record in self.records],
        }
        self.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")


REPORTERS = {
    "tap": TapReporter,
    "pretty": PrettyReporter,
    "json": JsonReporter,
}


def make(name, stream=None):
    try:
        return REPORTERS[name](stream)
    except KeyError:
        raise ValueError("unknown report format %r" % (name,))


# ---------------------------------------------------------------------------
# diagnostics


def _diagnostic_lines(record):
    lines = []
    if record.expected is not None:
        lines.append("expected: %r" % (record.expected,))
    lines.append("received: %r" % (record.actual,))
    if record.detail:
        lines.append("detail:   %s" % (record.detail,))
    if record.reply is not None:
        lines.append("reply:    %s" % (record.reply.summary(),))
        lines.append("options:  %s" % (_render_options(record.reply),))
    elif record.skip_reason is None:
        lines.append("reply:    none received")
    if record.sent:
        lines.append("sent:     %s" % (record.sent,))
    if record.attempts:
        lines.append("attempt:  %d of %d" % (record.attempt, record.attempts))
    return lines


def _yaml_block(record):
    out = ["  ---\n"]
    for line in _diagnostic_lines(record):
        key, _, value = line.partition(":")
        out.append("  %s: %s\n" % (key.strip(), value.strip()))
    out.append("  ...\n")
    return "".join(out)


def _render_options(reply):
    parts = []
    for code in sorted(reply.options):
        value = reply.options[code]
        parts.append("%s=%s" % (options_mod.option_label(code), value))
    return "{" + ", ".join(parts) + "}"


def _as_dict(record):
    return {
        "scenario": record.scenario,
        "step": record.step,
        "assertion": record.description,
        "ok": bool(record.ok),
        "skip": record.skip_reason,
        "expected": record.expected,
        "actual": record.actual,
        "detail": record.detail,
        "reply": record.reply.summary() if record.reply is not None else None,
        "options": (dict((str(k), v) for k, v in record.reply.options.items())
                    if record.reply is not None else None),
        "sent": record.sent,
        "attempt": record.attempt,
        "attempts": record.attempts,
    }
