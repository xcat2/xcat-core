"""Exception types and the exit codes they map to.

Exit codes are part of the tool's contract, because callers such as `xcattest`
check them:

    0   every assertion passed (or everything was skipped)
    1   at least one assertion failed
    2   the configuration or command line was wrong
    3   the environment was wrong (no such interface, not root, no scapy)
"""

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_CONFIG = 2
EXIT_ENVIRONMENT = 3


class DhcpTestError(Exception):
    """Base class for every error this tool raises deliberately."""

    exit_code = EXIT_CONFIG


class ConfigError(DhcpTestError):
    """A .conf file is malformed, or references something that cannot exist."""

    exit_code = EXIT_CONFIG

    def __init__(self, message, source=None):
        if source:
            message = "%s: %s" % (source, message)
        Exception.__init__(self, message)
        self.source = source


class EnvironmentError_(DhcpTestError):
    """The host cannot run this test: no interface, no privileges, no scapy."""

    exit_code = EXIT_ENVIRONMENT
