"""The two boundaries this tool promises to keep.

Both are checked by reading the source rather than by convention, because both
are easy to break with one convenient import and neither breaks visibly.
"""

import ast
import os
import unittest

import helper

LIB = os.path.join(helper.SRC, "dhcptest_lib")

#: The one module allowed to touch scapy.
SCAPY_MODULE = "runner.py"

#: Modules that must import on a host with no scapy and no privileges, because
#: `dhcptest validate` and `dhcptest list` run in CI on exactly such a host.
OFFLINE_MODULES = [
    "assertions", "cli", "config", "errors", "machine", "model", "netutil",
    "options", "report", "subst",
]


def sources():
    for name in sorted(os.listdir(LIB)):
        if name.endswith(".py"):
            path = os.path.join(LIB, name)
            with open(path) as handle:
                yield name, ast.parse(handle.read(), filename=path)


def imported_roots(tree):
    roots = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            roots.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            roots.add(node.module.split(".")[0])
    return roots


def strings(tree):
    """Every string literal that is not a docstring.

    Docstrings are prose about the design, and prose is allowed to explain what
    the tool deliberately does not do. Only strings the code actually uses are
    evidence of coupling.
    """
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) \
                and isinstance(node.value.value, str):
            docstrings.add(id(node.value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and id(node) not in docstrings:
            yield node.value


class Layering(unittest.TestCase):
    """Only runner.py may import scapy."""

    def test_scapy_is_confined_to_one_module(self):
        for name, tree in sources():
            if name == SCAPY_MODULE:
                continue
            self.assertNotIn("scapy", imported_roots(tree),
                             "%s imports scapy; only %s may"
                             % (name, SCAPY_MODULE))

    def test_the_offline_modules_import_without_scapy(self):
        # They are already imported by the rest of the suite, but importing
        # them here states the requirement rather than relying on it.
        for name in OFFLINE_MODULES:
            __import__("dhcptest_lib." + name)

    def test_runner_is_imported_lazily(self):
        # cli.py must not pull scapy in at start-up, or `validate` would need it.
        for name, tree in sources():
            if name not in ("cli.py", "config.py", "machine.py"):
                continue
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.col_offset == 0:
                    names = [alias.name for alias in node.names]
                    self.assertNotIn("runner", names,
                                     "%s imports runner at module level" % (name,))


class NoXcatCoupling(unittest.TestCase):
    """The tool talks to a DHCP server over the wire and to nothing else.

    No xCAT database, no xCAT commands, no xCAT paths -- so it can be pointed
    at any DHCP server, and so a change inside xCAT cannot silently change what
    a test means.
    """

    #: Anything that would mean shelling out or reading a local database.
    FORBIDDEN_IMPORTS = frozenset(["subprocess", "sqlite3", "xcat", "xCAT"])

    #: Substrings that would mean the tool knows what is answering it. Checked
    #: against string literals only, so the AST has already dropped comments.
    FORBIDDEN_TEXT = ("xcat", "makedhcp", "lsdef", "tabdump", "nodels",
                      "dhcpd.conf", "kea", "dnsmasq")

    def test_no_module_shells_out_or_opens_a_database(self):
        for name, tree in sources():
            clash = imported_roots(tree) & self.FORBIDDEN_IMPORTS
            self.assertFalse(clash, "%s imports %s" % (name, sorted(clash)))

    def test_no_module_names_a_server_implementation_or_xcat(self):
        for name, tree in sources():
            for text in strings(tree):
                lowered = text.lower()
                for bad in self.FORBIDDEN_TEXT:
                    self.assertNotIn(
                        bad, lowered,
                        "%s has a string mentioning %r: %r" % (name, bad, text))

    def test_no_module_calls_os_system_or_popen(self):
        for name, tree in sources():
            for node in ast.walk(tree):
                if not isinstance(node, ast.Attribute):
                    continue
                self.assertNotIn(
                    node.attr, ("system", "popen", "spawnv", "execv"),
                    "%s calls os.%s" % (name, node.attr))

    def test_the_shipped_scenarios_name_no_implementation(self):
        # A .conf may state what an address or a loader must be -- that is the
        # operator's knowledge -- but never who is meant to be serving it.
        #
        # Comments are skipped: naming two servers to explain how they differ
        # on the wire is exactly the prose a reader needs. What must stay
        # implementation-free is the part that decides whether a test passes.
        for name in sorted(os.listdir(helper.CONF)):
            if not name.endswith(".conf"):
                continue
            with open(os.path.join(helper.CONF, name)) as handle:
                text = "\n".join(
                    line for line in handle.read().lower().splitlines()
                    if not line.lstrip().startswith("#"))
            for bad in ("makedhcp", "lsdef", "tabdump", "dhcpd.conf",
                        "kea-dhcp4", "dnsmasq"):
                self.assertNotIn(bad, text, "%s mentions %r" % (name, bad))


if __name__ == "__main__":
    unittest.main()
