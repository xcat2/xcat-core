"""Exceptions and exit codes.

The codes are dhcptest's, so a caller driving both suites reads one table:

    0   every assertion held
    1   at least one assertion failed
    2   the configuration or the command line is wrong
    3   this host cannot run the test at all

3 is deliberately not 0. A host with no `dig` reports that it tested nothing
rather than reporting a green run, because a pass that proves nothing is worse
than a failure that says why.
"""

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_CONFIG = 2
EXIT_UNSUPPORTED = 3


class ProvTestError(Exception):
    """Base class: every failure this tool raises on purpose."""

    exit_code = EXIT_CONFIG


class ConfigError(ProvTestError):
    """A .conf file says something that cannot be carried out."""

    exit_code = EXIT_CONFIG

    def __init__(self, message, source=""):
        self.message = message
        self.source = source
        Exception.__init__(self, self.__str__())

    def __str__(self):
        if self.source:
            return "%s: %s" % (self.source, self.message)
        return self.message


class UnsupportedError(ProvTestError):
    """The host is missing something the run cannot go on without."""

    exit_code = EXIT_UNSUPPORTED
