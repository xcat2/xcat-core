"""TAP version 13 output, which `prove` and xcattest both read.

A failure carries what was expected, what came back, the reply and what was
sent, so it can be understood from the log after the test network is gone.
"""

import sys

from .errors import EXIT_FAILED, EXIT_OK


class Record(object):
    """One assertion outcome."""

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


class TapReporter(object):
    """Writes one TAP line per record, and the plan at the end."""

    def __init__(self, stream=None):
        self.stream = stream or sys.stdout
        self.count = 0
        self.failed = 0
        self.skipped = 0

    def write(self, text):
        self.stream.write(text)
        self.stream.flush()

    def start(self):
        self.write("TAP version 13\n")

    def add(self, record):
        self.count += 1
        line = "%s %d - %s/%s: %s" % (
            "not ok" if not record.ok and record.skip_reason is None else "ok",
            self.count, record.scenario, record.step, record.description)
        if record.skip_reason is not None:
            self.skipped += 1
            self.write("%s # SKIP %s\n" % (line, record.skip_reason))
        elif record.ok:
            self.write(line + "\n")
        else:
            self.failed += 1
            self.write(line + "\n  ---\n")
            for key, value in diagnostics(record):
                self.write("  %s: %s\n" % (key, value))
            self.write("  ...\n")

    def finish(self):
        self.write("1..%d\n# passed %d, failed %d, skipped %d\n"
                   % (self.count, self.count - self.failed - self.skipped,
                      self.failed, self.skipped))

    def exit_code(self):
        return EXIT_FAILED if self.failed else EXIT_OK


def diagnostics(record):
    """`(key, value)` lines explaining a failed record."""
    lines = []
    if record.expected is not None:
        lines.append(("expected", repr(record.expected)))
    lines.append(("received", repr(record.actual)))
    if record.detail:
        lines.append(("detail", _oneline(record.detail)))
    if record.reply is not None:
        lines.append(("reply", _oneline(record.reply.summary())))
        lines.extend((key, _oneline(text, 2000))
                     for key, text in record.reply.detail_lines())
    else:
        lines.append(("reply", "none received"))
    if record.sent:
        lines.append(("sent", _oneline(record.sent)))
    if record.attempts:
        lines.append(("attempt", "%d of %d" % (record.attempt, record.attempts)))
    return lines


def _oneline(text, limit=400):
    """One line, because a TAP diagnostic is read line by line."""
    flat = " ".join(str(text).split())
    return flat if len(flat) <= limit else flat[:limit - 3] + "..."
