"""Rules about this tool's own code, which are why its results mean anything.

  * It never asks xCAT what to expect: no database, no xCAT command, no xCAT
    path. A suite that asked xCAT would pass on a cluster that cannot boot.
  * It never knows which DHCP server answers, so ISC and Kea get one test.
  * Only `proc` starts a process, and never through a shell, so nothing a
    .conf supplies becomes a command.
  * Only `dhcp` imports scapy, lazily, so `validate` runs without it.
"""

import ast
import re
import unittest

import context

from blackboxtest_lib import steps

SPAWNING_MODULES = frozenset(["subprocess", "pty", "multiprocessing"])
SPAWNING_CALLS = frozenset(["system", "popen", "spawn", "spawnl", "spawnv",
                            "execv", "execve", "execvp", "fork", "forkpty"])
DATABASE_MODULES = frozenset(["sqlite3", "psycopg2", "psycopg", "pymysql",
                              "MySQLdb", "mysql", "sqlalchemy", "dbm", "shelve"])
STDLIB = frozenset([
    "argparse", "binascii", "configparser", "gzip", "hashlib", "ipaddress",
    "os", "random", "re", "select", "shutil", "socket", "ssl", "subprocess",
    "sys", "tempfile", "threading", "time"])

#: xCAT commands. `xcatd` is absent: it is the daemon under test.
XCAT = re.compile(
    r"\b(lsdef|mkdef|chdef|rmdef|nodels|nodech|tabdump|chtab|gettab|nodeset|"
    r"makedns|makedhcp|makehosts|rinstall|copycds|genimage|xcatconfig)\b")

#: xCAT's own files. A scenario may request one to assert it is refused.
XCAT_FILES = re.compile(r"/opt/xcat/s?bin|/etc/xcat/|site\.tab")

#: DHCP server implementations.
SERVERS = re.compile(r"\bkea\b|kea-dhcp4|dnsmasq|dhcpd\.conf", re.IGNORECASE)


def trees():
    for name, path in context.modules():
        with open(path) as handle:
            yield name, ast.parse(handle.read(), filename=path)


def imports(tree):
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0:
            names.add(node.module.split(".")[0])
    return names


def code_strings(tree):
    """String literals that are not docstrings: prose may name what the code
    must not use."""
    docs = set(id(node.body[0].value) for node in ast.walk(tree)
               if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef))
               and node.body and isinstance(node.body[0], ast.Expr)
               and isinstance(node.body[0].value, ast.Constant))
    return [node.value for node in ast.walk(tree)
            if isinstance(node, ast.Constant) and isinstance(node.value, str)
            and id(node) not in docs]


class Boundaries(unittest.TestCase):

    def test_only_proc_starts_a_process_and_never_through_a_shell(self):
        for name, tree in trees():
            calls = set(getattr(node.func, "attr", getattr(node.func, "id", ""))
                        for node in ast.walk(tree) if isinstance(node, ast.Call))
            if name != "proc":
                self.assertFalse(imports(tree) & SPAWNING_MODULES, name)
                self.assertFalse(calls & SPAWNING_CALLS, name)
            for node in ast.walk(tree):
                if isinstance(node, ast.keyword) and node.arg == "shell":
                    self.assertFalse(getattr(node.value, "value", True), name)

    def test_only_the_standard_library_and_scapy_in_dhcp(self):
        for name, tree in trees():
            outside = imports(tree) - STDLIB - set(["blackboxtest_lib"])
            if name == "dhcp":
                outside -= set(["scapy"])
            self.assertEqual(outside, set(), name)
            self.assertFalse(imports(tree) & DATABASE_MODULES, name)

    def test_scapy_is_imported_inside_a_function(self):
        for name, tree in trees():
            for node in tree.body:
                if isinstance(node, (ast.Import, ast.ImportFrom)):
                    self.assertNotIn("scapy", imports(ast.Module(body=[node])),
                                     name)

    def test_no_module_names_an_xcat_command_or_a_dhcp_server(self):
        for name, tree in trees():
            for text in code_strings(tree):
                self.assertIsNone(XCAT.search(text), "%s: %r" % (name, text))
                self.assertIsNone(XCAT_FILES.search(text), "%s: %r" % (name, text))
                self.assertIsNone(SERVERS.search(text), "%s: %r" % (name, text))

    def test_the_shipped_scenarios_name_neither(self):
        # Comments and descriptions are prose, and may explain how two
        # servers differ. What decides a verdict may not know which answers.
        for path in context.conf_files():
            with open(path) as handle:
                text = "\n".join(
                    line for line in handle.read().splitlines()
                    if not re.match(r"\s*(#|description\s*=)", line))
            self.assertIsNone(XCAT.search(text), path)
            self.assertIsNone(SERVERS.search(text), path)

    def test_no_step_type_runs_a_program_of_the_confs_choosing(self):
        for name, kind in steps.TYPES.items():
            for key in ("exec", "shell", "program", "script", "command_line"):
                self.assertNotIn(key, kind.keys, name)

    def test_the_offline_commands_never_import_the_runner(self):
        cli = dict(trees())["cli"]
        top = set(alias.name for node in cli.body
                  if isinstance(node, (ast.Import, ast.ImportFrom))
                  for alias in node.names)
        self.assertNotIn("runner", top)


if __name__ == "__main__":
    unittest.main()
