"""The one place a child process is started.

DNS, HTTP and TFTP are driven by the clients an operator would reach for --
`dig`, `curl`, `tftp` -- rather than by a hand-rolled implementation of each
protocol. What is under test is whether a real client gets a usable answer,
so using the real client removes a whole class of "the test's own parser was
wrong" from the result.

Confining the spawning to this module is what makes that safe. Output is read
from a pipe with a timeout and a hard kill, never through a shell, and every
argument list is built as a list, so nothing a `.conf` supplies can be
interpreted as a command.
"""

import os
import shutil
import subprocess

from .errors import UnsupportedError


class Completed(object):
    """What a client program did: exit status and the two streams, as bytes."""

    __slots__ = ("argv", "rc", "out", "err", "timed_out")

    def __init__(self, argv, rc, out=b"", err=b"", timed_out=False):
        self.argv = list(argv)
        self.rc = rc
        self.out = out
        self.err = err
        self.timed_out = timed_out

    @property
    def text(self):
        return self.out.decode("utf-8", "replace")

    @property
    def errtext(self):
        return self.err.decode("utf-8", "replace")

    def command(self):
        return " ".join(self.argv)

    def __repr__(self):
        return "Completed(%r, rc=%r)" % (self.command(), self.rc)


def which(program):
    """The path to a client program, or None."""
    return shutil.which(program)


def require(program, why):
    """The path to a client program, or a skip-the-host error saying why."""
    path = which(program)
    if path is None:
        raise UnsupportedError(
            "%s is not installed, so %s cannot be tested" % (program, why))
    return path


def run(argv, timeout=10.0, stdin=None):
    """Run a client program and collect what it said.

    A program that outlives its timeout is killed and reported as timed out
    rather than raising, because "the server did not answer" is a result the
    scenario may be asserting on.
    """
    env = dict(os.environ)
    # A localised client would report its errors in a language the parsers
    # here do not read.
    env["LC_ALL"] = "C"
    env["LANG"] = "C"
    try:
        child = subprocess.Popen(
            list(argv),
            stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
    except OSError as exc:
        return Completed(argv, 127, b"", str(exc).encode())

    try:
        out, err = child.communicate(input=stdin, timeout=timeout)
        return Completed(argv, child.returncode, out, err)
    except subprocess.TimeoutExpired:
        child.kill()
        out, err = child.communicate()
        return Completed(argv, 124, out, err, timed_out=True)
