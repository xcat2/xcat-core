#!/usr/bin/env python3
"""Exercise the linked Genesis console through a terminal, including newt dialogs."""

import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest
import uuid

import pyte


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console"


class ConsoleTerminal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build_root = tempfile.TemporaryDirectory(prefix="genesis-dialog-build-")
        cls.addClassCleanup(cls.build_root.cleanup)
        build = Path(cls.build_root.name) / "build"
        subprocess.run(["meson", "setup", str(build), str(SOURCE)], check=True)
        subprocess.run(["meson", "compile", "-C", str(build)], check=True)
        cls.binary = build / "xcat-genesis-console"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="genesis-dialog-state-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.root = root
        environment = {"PATH": os.environ["PATH"], "LC_ALL": "C.UTF-8", "TERM": "xterm"}
        for name in ("CMDLINE_FILE", "UPTIME_FILE", "OS_RELEASE", "STATUS_DIR", "STATE_FILE",
                     "DESTINY_FILE", "RESPONSE_FILE", "SYS_ROOT", "PROC_ROOT", "EXTENSION_DIR", "PROVIDER_DIR"):
            environment["XCAT_" + name] = str(root / name.lower())
        Path(environment["XCAT_RESPONSE_FILE"]).write_text("XCAT_NODE_NAME=dialog-test-node\n")
        self.master, slave = pty.openpty()
        self.addCleanup(os.close, self.master)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        try:
            self.process = subprocess.Popen(self.console_command(), stdin=slave, stdout=slave,
                                            stderr=slave, env=environment, start_new_session=True)
        finally:
            os.close(slave)
        self.addCleanup(self.stop)
        self.screen = pyte.Screen(100, 30)
        self.stream = pyte.ByteStream(self.screen)
        self.wait_text("Genesis status")

    def console_command(self):
        return [str(self.binary)]

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            os.write(self.master, b"\x1b")
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)

    def read_screen(self, timeout):
        if select.select([self.master], [], [], timeout)[0]:
            self.stream.feed(os.read(self.master, 65536))
        return "\n".join(self.screen.display)

    def wait_text(self, text):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            display = self.read_screen(0.1)
            if text in display:
                return display
            self.assertIsNone(self.process.poll(), display)
        self.fail(f"Terminal did not show {text!r}:\n{display}")

    def key(self, sequence):
        os.write(self.master, sequence)


class ConsoleDialogs(ConsoleTerminal):
    def test_help_and_diagnostics_scroll_close_and_reopen(self):
        dialogs = [
            (b"\x1bOP", "Genesis help", "This console reports Genesis status.",
             "Up and Down scroll this page.", "F1 Back", b"\x1bOQ"),
            (b"\x1bOQ", "Genesis diagnostics", "Node: dialog-test-node",
             "Provider names:", "F2 Back", b"\x1bOP"),
        ]
        for key, title, first, last, help_line, other_key in dialogs:
            for close_key in (key, b"\x1b"):
                with self.subTest(dialog=title, close_key=close_key):
                    self.key(key)
                    self.wait_text(title)
                    self.wait_text(first)
                    self.wait_text(help_line)
                    self.key(other_key)
                    self.assertIn(title, self.read_screen(0.2))
                    self.key(b"\x1b[6~" * 20)
                    self.wait_text(last)
                    self.key(close_key)
                    self.wait_text("Genesis status")
                    self.wait_text("F1 Help")
        self.process.send_signal(signal.SIGTERM)
        self.assertEqual(self.process.wait(timeout=5), 0)


class ConsoleJournal(ConsoleTerminal):
    """Read real journal files in a private machine and journal namespace.

    Requires bubblewrap, systemd-journal-remote, journalctl and user namespaces.
    The host filesystem is read-only; /run and /var/log are private mounts.
    No journal service is started and no host journal is read or changed.
    """

    def console_command(self):
        self.machine_id = uuid.uuid4().hex
        self.boot_id = uuid.uuid4().hex
        journal_root = self.root / "journal"
        journal_directory = journal_root / self.machine_id
        journal_directory.mkdir(parents=True)
        self.journal = journal_directory / "system.journal"
        machine_id_file = self.root / "machine-id"
        machine_id_file.write_text(self.machine_id + "\n")
        sandbox = [
            "bwrap", "--unshare-all", "--die-with-parent", "--ro-bind", "/", "/",
            "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/run", "--tmpfs", "/var/log",
            "--ro-bind", str(machine_id_file), "/etc/machine-id",
            "--ro-bind", str(journal_root), "/var/log/journal",
        ]
        result = subprocess.run(sandbox + ["/bin/true"], text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0,
                         "Journal tests require working Bubblewrap namespaces: " + result.stderr)
        return sandbox + [str(self.binary)]

    def write_journal(self, entries):
        records = []
        for sequence, (message, unit, identifier) in enumerate(entries, 1):
            records.append(
                f"__REALTIME_TIMESTAMP={1700000000000000 + sequence * 1000000}\n"
                f"__MONOTONIC_TIMESTAMP={sequence * 1000000}\n"
                f"_MACHINE_ID={self.machine_id}\n_BOOT_ID={self.boot_id}\n"
                f"_SYSTEMD_UNIT={unit}\nSYSLOG_IDENTIFIER={identifier}\n"
                f"MESSAGE={message}\n\n")
        result = subprocess.run(
            ["/usr/lib/systemd/systemd-journal-remote", "--split-mode=none",
             "--output=" + str(self.journal), "-"],
            input="".join(records), text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        exported = subprocess.check_output(
            ["journalctl", "--file=" + str(self.journal), "--output=json", "--no-pager"],
            text=True, timeout=10)
        actual = [json.loads(line) for line in exported.splitlines()]
        self.assertEqual([(entry["MESSAGE"], entry["_SYSTEMD_UNIT"], entry["SYSLOG_IDENTIFIER"])
                          for entry in actual], entries)

    def open_logs(self):
        self.key(b"\x1bOR")
        self.wait_text("Genesis logs")
        self.wait_text("F3 Back")

    def test_empty_journal(self):
        self.open_logs()
        self.wait_text("No Genesis journal entries are available.")

    def test_unrelated_entries_are_excluded(self):
        self.write_journal([("UNRELATED-ENTRY", "other.service", "other")])
        self.open_logs()
        display = self.wait_text("No Genesis journal entries are available.")
        self.assertNotIn("UNRELATED-ENTRY", display)

    def test_single_entry_is_shown(self):
        self.write_journal([("ONLY-ENTRY", "other.service", "xcat-genesis-register")])
        self.open_logs()
        display = self.wait_text("ONLY-ENTRY")
        self.assertEqual(display.count("ONLY-ENTRY"), 1)
        self.assertNotIn("No Genesis journal entries", display)

    def test_first_entry_and_matching_order(self):
        self.write_journal([
            ("FIRST-ENTRY", "xcat-genesis-register.service", "unit-fixture"),
            ("UNRELATED-ENTRY", "other.service", "other"),
            ("LAST-ENTRY", "other.service", "xcat-genesis-discovery"),
        ])
        self.open_logs()
        self.wait_text("LAST-ENTRY")
        display = self.wait_text("FIRST-ENTRY")
        self.assertLess(display.index("FIRST-ENTRY"), display.index("LAST-ENTRY"))
        self.assertEqual(display.count("FIRST-ENTRY"), 1)
        self.assertEqual(display.count("LAST-ENTRY"), 1)
        self.assertNotIn("UNRELATED-ENTRY", display)

    def test_scan_includes_first_of_latest_2048_entries(self):
        self.write_journal([
            ("OUTSIDE-WINDOW", "other.service", "xcat-genesis-register"),
            ("WINDOW-FIRST", "other.service", "xcat-genesis-register"),
        ] + [(f"UNRELATED-{number:04d}", "other.service", "other") for number in range(2046)] + [
            ("WINDOW-LAST", "other.service", "xcat-genesis-discovery"),
        ])
        self.open_logs()
        self.wait_text("WINDOW-LAST")
        display = self.wait_text("WINDOW-FIRST")
        self.assertLess(display.index("WINDOW-FIRST"), display.index("WINDOW-LAST"))
        self.assertNotIn("OUTSIDE-WINDOW", display)
        self.assertNotIn("UNRELATED-", display)

    def test_view_retains_latest_128_matching_entries(self):
        self.write_journal([(f"RECORD-{number:04d}", "other.service", "xcat-genesis-register")
                            for number in range(1, 130)])
        self.open_logs()
        self.wait_text("RECORD-0129")
        self.key(b"\x1b[H")
        display = self.wait_text("RECORD-0002")
        self.assertNotIn("RECORD-0001", display)
        self.key(b"\x1b[F")
        self.wait_text("RECORD-0129")


if __name__ == "__main__":
    unittest.main(verbosity=2)
