"""Exceptions, and the exit codes they map to.

    0   every assertion held
    1   at least one assertion failed
    2   the configuration or the command line is wrong
    3   this host cannot run the test at all

3 is not 0. A host that tested nothing must not report a green run.
"""

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_CONFIG = 2
EXIT_UNSUPPORTED = 3


class BlackboxError(Exception):
    """Base class of every error this tool raises on purpose."""

    exit_code = EXIT_CONFIG


class ConfigError(BlackboxError):
    """A .conf file or the command line asks for something impossible."""

    def __init__(self, message, source=""):
        if source:
            message = "%s: %s" % (source, message)
        BlackboxError.__init__(self, message)


class UnsupportedError(BlackboxError):
    """The host lacks a program, a module or a privilege the run needs."""

    exit_code = EXIT_UNSUPPORTED
