"""Rules about this tool's own code, not about xCAT.

Two of them, and both are the reason the results mean anything:

  * only `proc.py` starts a process, so nothing a `.conf` supplies can become a
    command;
  * no module reads the xCAT database or runs an xCAT command, so what the
    suite expects never comes from the same place as what it is testing.

A suite that asked xCAT what to expect would pass on a cluster that could not
boot a single node. That is not a style rule, so it is asserted rather than
written down in the README and hoped for.
"""

import ast
import re
import unittest

import context                                   # noqa: F401  (sys.path)


#: The only module allowed to start a child process.
SPAWNER = "proc"

#: Modules and callables that start one.
SPAWNING_MODULES = frozenset(["subprocess", "pty", "multiprocessing"])
SPAWNING_CALLS = frozenset(["system", "popen", "spawn", "spawnl", "spawnv",
                            "execv", "execve", "execvp", "fork", "forkpty"])

#: Database drivers. None of them belongs here: the tool is a client of the
#: wire, not a reader of the rows that produced it.
DATABASE_MODULES = frozenset([
    "sqlite3", "psycopg2", "psycopg", "pymysql", "MySQLdb", "mysql",
    "sqlalchemy", "dbm", "shelve",
])

#: xCAT commands. A string naming one in executable code means the tool asked
#: xCAT what to expect instead of being told by the fixture. `xcatd` is not in
#: the list: it is the daemon under test, and naming it is unavoidable.
XCAT_NAMES = re.compile(
    r"\b(lsdef|mkdef|chdef|rmdef|nodels|nodech|nodeadd|tabdump|tabedit|"
    r"chtab|gettab|nodeset|makedns|makedhcp|makehosts|makeknownhosts|"
    r"xdsh|xdcp|rinstall|rpower|rcons|copycds|genimage|packimage|"
    r"xcatprobe|xcatconfig)\b")

#: Where those commands and the database live.
XCAT_PATHS = re.compile(r"/opt/xcat/(bin|sbin)|/etc/xcat/|xcatdb|site\.tab")


def parse(path):
    with open(path) as handle:
        return ast.parse(handle.read(), filename=path)


def imported_names(tree):
    """Every module name an import statement brings in."""
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                names.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            # `from . import model` is this package importing itself, which is
            # not a dependency on anything.
            if node.level == 0 and node.module:
                names.add(node.module.split(".")[0])
    return names


def strings_in_code(tree):
    """Every string literal that is not a docstring.

    Docstrings are excluded because they explain the behaviour under test and
    routinely name the commands whose output this tool must not depend on --
    saying so is the opposite of doing it.
    """
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef,
                             ast.AsyncFunctionDef)):
            body = getattr(node, "body", None)
            if body and isinstance(body[0], ast.Expr) and \
                    isinstance(body[0].value, ast.Constant) and \
                    isinstance(body[0].value.value, str):
                docstrings.add(id(body[0].value))

    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            if id(node) not in docstrings:
                found.append(node.value)
    return found


def called_attributes(tree):
    """Every `something.name(...)` called, as its attribute name."""
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute):
                names.append(func.attr)
            elif isinstance(func, ast.Name):
                names.append(func.id)
    return names


class SpawningTests(unittest.TestCase):

    def test_only_proc_imports_a_process_module(self):
        for name, path in context.modules():
            found = imported_names(parse(path)) & SPAWNING_MODULES
            if name == SPAWNER:
                continue
            self.assertEqual(found, set(),
                             "%s imports %s; only %s.py may start a process"
                             % (name, ", ".join(sorted(found)), SPAWNER))

    def test_no_module_calls_a_spawning_function(self):
        for name, path in context.modules():
            if name == SPAWNER:
                continue
            found = set(called_attributes(parse(path))) & SPAWNING_CALLS
            self.assertEqual(found, set(),
                             "%s calls %s" % (name, ", ".join(sorted(found))))

    def test_proc_never_uses_a_shell(self):
        # An argument list, never a command string: nothing a .conf supplies
        # may be interpreted by a shell.
        path = dict(context.modules())[SPAWNER]
        for node in ast.walk(parse(path)):
            if isinstance(node, ast.keyword) and node.arg == "shell":
                value = getattr(node.value, "value", True)
                self.assertFalse(value, "proc.py passes shell=True")


class DatabaseTests(unittest.TestCase):

    def test_no_module_imports_a_database_driver(self):
        for name, path in context.modules():
            found = imported_names(parse(path)) & DATABASE_MODULES
            self.assertEqual(found, set(),
                             "%s imports %s" % (name, ", ".join(sorted(found))))


class XcatTests(unittest.TestCase):

    def test_no_module_names_an_xcat_command_in_executable_code(self):
        for name, path in context.modules():
            for text in strings_in_code(parse(path)):
                match = XCAT_NAMES.search(text)
                self.assertIsNone(
                    match,
                    "%s has %r in executable code; what this suite expects "
                    "must come from --set, never from xCAT itself"
                    % (name, match.group(0) if match else ""))

    def test_no_module_names_an_xcat_path(self):
        for name, path in context.modules():
            for text in strings_in_code(parse(path)):
                self.assertIsNone(XCAT_PATHS.search(text),
                                  "%s reaches into xCAT's own files: %r"
                                  % (name, text))

    def test_no_step_type_can_run_a_command(self):
        # The reason a .conf is safe to read from anywhere: the step types are
        # a closed list of protocols, and not one of them takes a program to
        # run. A scenario cannot execute anything, so it cannot ask xCAT.
        from provtest_lib import machine

        protocols = frozenset(["dns", "tftp", "http", "xcatreq", "monitor",
                               "flowrequest", "findme"])
        offline = frozenset(["extract", "sleep", "noop"])
        self.assertEqual(machine.known_step_types(), protocols | offline)
        for name in machine.known_step_types():
            for key in machine.allowed_keys(name):
                self.assertNotIn(key, ("command_line", "exec", "shell",
                                       "program", "script"))

    def test_the_shipped_scenarios_use_only_declared_types(self):
        from provtest_lib import config, machine

        scenarios, _ = config.load(context.conf_files(), {}, raw=True)
        for scenario in scenarios:
            for step in scenario.steps:
                self.assertIn(step.type, machine.known_step_types(),
                              "%s step %s" % (scenario.name, step.name))


class ImportTests(unittest.TestCase):

    def test_nothing_outside_the_standard_library_is_imported(self):
        allowed = set(["provtest_lib", "argparse", "ast", "base64", "binascii",
                       "configparser", "errno", "gzip", "hashlib", "io",
                       "ipaddress", "json", "os", "re", "select", "shutil",
                       "socket", "ssl", "struct", "subprocess", "sys",
                       "tempfile", "threading", "time", "xml"])
        for name, path in context.modules():
            for imported in imported_names(parse(path)):
                if imported in ("", "."):
                    continue
                self.assertIn(imported, allowed,
                              "%s imports %s, which is not in the standard "
                              "library set this tool is allowed" % (name, imported))

    def test_listing_a_file_never_reaches_the_runner(self):
        # `validate` and `list` run in a checkout with no root and no network,
        # so the module that opens sockets is imported inside the run command
        # and nowhere else.
        path = dict(context.modules())["cli"]
        top_level = set()
        for node in parse(path).body:
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                for alias in node.names:
                    top_level.add(alias.name)
        self.assertNotIn("runner", top_level)


if __name__ == "__main__":
    unittest.main()
