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
        environment = {"PATH": os.environ["PATH"], "LC_ALL": "C.UTF-8", "TERM": "xterm",
                       "NEWT_COLORS": "listbox=black,white\nactlistbox=black,white\n"
                                      "sellistbox=white,red\nactsellistbox=white,red"}
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
        return self.wait_screen(lambda display: text in display, repr(text))

    def wait_screen(self, predicate, description):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            display = self.read_screen(0.1)
            if predicate(display):
                return display
            self.assertIsNone(self.process.poll(), display)
        self.fail(f"Terminal did not show {description}:\n{display}")

    def assert_screen_stays(self, predicate, description, duration):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            display = self.read_screen(0.1)
            self.assertTrue(predicate(display), f"{description}:\n{display}")
            self.assertIsNone(self.process.poll(), display)

    def key(self, sequence):
        os.write(self.master, sequence)

    def visible_text(self, display):
        return " ".join("".join(character if character.isascii() else " "
                                for character in display).split())


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
                    self.key(b"\x1b[6~" * 20)
                    self.assertIn(title, self.wait_text(last))
                    self.key(close_key)
                    self.wait_text("Genesis status")
                    self.wait_text("F1 Help")
        self.process.send_signal(signal.SIGTERM)
        self.assertEqual(self.process.wait(timeout=5), 0)

    def publish(self, name, text):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(".tmp")
        temporary.write_text(text)
        temporary.replace(target)

    def test_status_refresh_and_diagnostic_snapshot(self):
        self.publish("response_file", "XCAT_NODE_NAME=updated-node\n")
        self.assertRegex(self.wait_text("updated-node"), r"Node +updated-node")
        self.publish("status_dir/action.env", "SCHEMA=1\nSTATE=RUNNING\n"
                     "DETAIL=Preparing test action\nUPDATED_SECONDS=100\n")
        self.assertIn("RUNNING", self.wait_text("Preparing test action"))
        self.key(b"\x1bOQ")
        self.wait_text("Node: updated-node")
        self.publish("response_file", "XCAT_NODE_NAME=short-node\n")
        self.publish("status_dir/action.env", "SCHEMA=1\nSTATE=FAILED\n"
                     "DETAIL=Test action failed\nRECOVERY=Check test input\nUPDATED_SECONDS=101\n")
        self.key(b"\x1b[6~" * 20)
        self.wait_text("Provider names:")
        self.key(b"\x1b[5~" * 20)
        display = self.wait_text("Node: updated-node")
        self.assertNotIn("short-node", display)
        self.assert_screen_stays(lambda display: "Node: updated-node" in display
                                 and "short-node" not in display,
                                 "Diagnostics changed before reopening", 2)
        self.key(b"\x1bOQ")
        display = self.wait_text("Check test input")
        self.assertRegex(display, r"Node +short-node +")
        self.assertIn("FAILED", display)
        self.assertIn("Test action failed", display)
        self.assertNotIn("updated-node", display)
        self.key(b"\x1bOQ")
        self.wait_text("Node: short-node")

    def test_rendered_help_explains_read_only_pages_logs_and_shell(self):
        self.key(b"\x1bOP")
        display = self.wait_text("Screen fields")
        text = self.visible_text(display)
        self.assertIn("Status pages are read-only.", text)
        self.assertIn("confirmed root maintenance shell", text)
        self.key(b"\x1b[6~" * 20)
        display = self.wait_text("Up and Down scroll this page.")
        text = self.visible_text(display)
        self.assertIn("F3 opens recent Genesis logs", text)
        self.assertIn("press End to resume.", text)
        self.assertIn("F12 asks before opening", text)
        self.assertIn("Exit returns here.", text)


class ConsoleJournal(ConsoleTerminal):
    """Read real journal files in a private machine and journal namespace.

    Requires bubblewrap, systemd-journal-remote, journalctl and user namespaces.
    The host filesystem is read-only except for the fixture directory.
    /run and /var/log are private tmpfs mounts with the journal bound read-only.
    No journal service is started and no host journal is read or changed.
    """

    def console_command(self):
        self.machine_id = uuid.uuid4().hex
        self.boot_id = uuid.uuid4().hex
        journal_root = self.root / "journal"
        journal_directory = journal_root / self.machine_id
        journal_directory.mkdir(parents=True)
        self.journal = journal_directory / "system.journal"
        self.entries = []
        machine_id_file = self.root / "machine-id"
        machine_id_file.write_text(self.machine_id + "\n")
        sandbox = [
            "bwrap", "--unshare-all", "--die-with-parent", "--ro-bind", "/", "/",
            "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/run", "--tmpfs", "/var/log",
            "--bind", str(self.root), str(self.root),
            "--ro-bind", str(machine_id_file), "/etc/machine-id",
            "--ro-bind", str(journal_root), "/var/log/journal",
        ]
        result = subprocess.run(sandbox + ["/bin/true"], text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0,
                         "Journal tests require working Bubblewrap namespaces: " + result.stderr)
        self.sandbox = sandbox
        return sandbox + [str(self.binary)]

    def write_journal(self, entries, interval=1000000):
        records = []
        for sequence, (message, unit, identifier) in enumerate(entries, len(self.entries) + 1):
            records.append(
                f"__REALTIME_TIMESTAMP={1700000000000000 + sequence * interval}\n"
                f"__MONOTONIC_TIMESTAMP={sequence * interval}\n"
                f"_MACHINE_ID={self.machine_id}\n_BOOT_ID={self.boot_id}\n"
                f"_SYSTEMD_UNIT={unit}\nSYSLOG_IDENTIFIER={identifier}\n"
                f"MESSAGE={message}\n\n")
        result = subprocess.run(
            self.sandbox + ["/usr/lib/systemd/systemd-journal-remote", "--split-mode=none",
             "--output=" + str(self.journal), "-"],
            input="".join(records), text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.entries.extend(entries)
        exported = subprocess.check_output(
            ["journalctl", "--file=" + str(self.journal), "--output=json", "--no-pager"],
            text=True, timeout=10)
        actual = [json.loads(line) for line in exported.splitlines()]
        self.assertEqual([(entry["MESSAGE"], entry["_SYSTEMD_UNIT"], entry["SYSLOG_IDENTIFIER"])
                          for entry in actual], self.entries)

    def open_logs(self):
        self.key(b"\x1bOR")
        self.wait_text("Genesis logs")
        self.wait_text("F3 Back")

    def selected_rows(self):
        return ["".join(self.screen.buffer[row][column].data
                        for column in range(self.screen.columns)
                        if self.screen.buffer[row][column].bg == "red").strip()
                for row in range(self.screen.lines)]

    def selected_text(self):
        return "\n".join(self.selected_rows()).strip()

    def wait_selected(self, text):
        return self.wait_screen(lambda display: self.selected_text().endswith(text),
                                f"selected log entry {text!r}")

    def assert_selection_stays(self, text):
        self.assert_screen_stays(lambda display: self.selected_text() == text,
                                 "Selected journal entry changed", 3)

    def test_paused_entry_survives_history_rollover(self):
        self.write_journal([(f"RECORD-{number:04d}", "other.service", "xcat-genesis-register")
                            for number in range(1, 130)])
        self.open_logs()
        self.wait_selected("RECORD-0129")
        self.key(b"\x1b[H")
        self.wait_selected("RECORD-0002")
        self.key(b"\x1b[B" * 60)
        self.wait_selected("RECORD-0062")
        selected = self.selected_text()
        for number in (130, 131):
            self.write_journal([(f"RECORD-{number:04d}", "other.service", "xcat-genesis-register")])
            self.assert_selection_stays(selected)
        self.key(b"\x1b[F")
        self.wait_selected("RECORD-0131")
        self.write_journal([("FOLLOWED", "other.service", "xcat-genesis-register")])
        self.wait_selected("FOLLOWED")

    def test_expired_selection_stays_paused_at_oldest_entry(self):
        self.write_journal([(f"RECORD-{number:04d}", "other.service", "xcat-genesis-register")
                            for number in range(1, 130)])
        self.open_logs()
        self.wait_selected("RECORD-0129")
        self.key(b"\x1b[H")
        self.wait_selected("RECORD-0002")
        for first, last, oldest in ((130, 140, 12), (140, 270, 142)):
            self.write_journal([(f"RECORD-{number:04d}", "other.service", "xcat-genesis-register")
                                for number in range(first, last)])
            self.wait_selected(f"RECORD-{oldest:04d}")
            self.assert_selection_stays(self.selected_text())
            if first == 130:
                self.key(b"\x1b[B" * 50)
                self.wait_selected("RECORD-0062")
        self.write_journal([("STILL-PAUSED", "other.service", "xcat-genesis-register")])
        self.wait_selected("RECORD-0143")
        self.key(b"\x1b[F")
        self.wait_selected("STILL-PAUSED")

    def test_duplicate_text_keeps_the_selected_record(self):
        self.write_journal([("DUPLICATE" if number in (60, 62, 63) else f"RECORD-{number:04d}",
                             "other.service", "xcat-genesis-register")
                            for number in range(1, 130)], interval=1)
        self.open_logs()
        self.wait_selected("RECORD-0129")
        self.key(b"\x1b[H")
        self.wait_selected("RECORD-0002")
        self.key(b"\x1b[B" * 58)
        self.wait_selected("DUPLICATE")
        duplicate = self.selected_text()
        self.key(b"\x1b[B")
        self.wait_selected("RECORD-0061")
        self.key(b"\x1b[B")
        self.wait_selected("DUPLICATE")
        self.assertEqual(self.selected_text(), duplicate)
        self.write_journal([("APPENDED", "other.service", "xcat-genesis-register")], interval=1)
        self.assert_selection_stays(duplicate)
        self.key(b"\x1b[A")
        self.wait_selected("RECORD-0061")
        self.key(b"\x1b[H")
        self.wait_selected("RECORD-0003")

    def test_wrapped_selection_survives_history_rollover(self):
        self.write_journal([
            (" ".join(f"OLD-{number:02d}" for number in range(20)),
             "other.service", "xcat-genesis-register"),
            (" ".join(f"CONTEXT-{number:02d}" for number in range(16)) + " SELECTED-TAIL",
             "other.service", "xcat-genesis-register"),
        ] + [(f"RECORD-{number:04d}", "other.service", "xcat-genesis-register")
             for number in range(3, 129)])
        self.open_logs()
        self.wait_selected("RECORD-0128")
        self.key(b"\x1b[H")
        self.wait_screen(lambda display: "OLD-00" in self.selected_text(), "oldest wrapped entry")
        for _ in range(12):
            if self.selected_text().endswith("CONTEXT-08"):
                break
            previous = self.selected_text()
            self.key(b"\x1b[B")
            self.wait_screen(lambda display: self.selected_text() != previous, "next wrapped row")
        self.assertTrue(self.selected_text().endswith("CONTEXT-08"), self.selected_text())
        selected = self.selected_text()
        self.assertIn("OLD-00", self.read_screen(0))
        self.write_journal([("APPENDED", "other.service", "xcat-genesis-register")])
        self.wait_screen(lambda display: "OLD-00" not in display, "expired wrapped entry removed")
        self.assert_selection_stays(selected)
        self.key(b"\x1b[B")
        self.wait_selected("CONTEXT-14")
        self.key(b"\x1b[B")
        self.wait_selected("SELECTED-TAIL")
        self.key(b"\x1b[B")
        self.wait_selected("RECORD-0003")

    def visible_entries(self):
        return [message for message, unit, identifier in self.entries
                if any(message in line for line in self.screen.display)]

    def assert_paused(self, text):
        before = self.selected_rows()
        self.assertIn(text, self.selected_text())
        self.assert_screen_stays(lambda display: self.selected_rows() == before,
                                 "Paused journal selection moved", 5)

    def test_logs_follow_pause_and_reopen(self):
        self.write_journal([
            ("FIRST", "xcat-genesis-register.service", "unit-fixture"),
            ("TAIL", "other.service", "xcat-genesis-discovery"),
        ])
        self.open_logs()
        self.wait_selected("TAIL")
        self.write_journal([("FOLLOWED", "other.service", "xcat-genesis-register")])
        self.wait_selected("FOLLOWED")
        self.key(b"\x1b[H")
        self.wait_selected("FIRST")
        self.write_journal([("PAUSED", "other.service", "xcat-genesis-register")])
        self.wait_text("PAUSED")
        self.assert_paused("FIRST")
        self.key(b"\x1b[F")
        self.wait_selected("PAUSED")
        self.write_journal([("END-FOLLOWED", "other.service", "xcat-genesis-register")])
        self.wait_selected("END-FOLLOWED")
        for index, close_key in enumerate((b"\x1bOR", b"\x1b")):
            with self.subTest(close_key=close_key):
                self.key(b"\x1b[H")
                self.wait_selected("FIRST")
                self.key(close_key)
                self.wait_text("Genesis status")
                self.open_logs()
                self.wait_selected("END-FOLLOWED" if index == 0 else "REOPENED-0")
                message = f"REOPENED-{index}"
                self.write_journal([(message, "other.service", "xcat-genesis-register")])
                self.wait_selected(message)

    def test_logs_arrow_and_page_keys_pause_and_resume(self):
        self.write_journal([(f"HISTORY-{number:03d}", "other.service", "xcat-genesis-register")
                            for number in range(40)])
        self.open_logs()
        self.wait_selected("HISTORY-039")
        for up, down in ((b"\x1b[A", b"\x1b[B"), (b"\x1b[5~", b"\x1b[6~")):
            with self.subTest(up=up):
                previous_tail = f"HISTORY-{len(self.entries) - 1:03d}"
                if up == b"\x1b[A":
                    paused = f"HISTORY-{len(self.entries) - 2:03d}"
                else:
                    visible = self.visible_entries()
                    self.assertGreater(len(visible), 2)
                    paused = visible[0]
                self.key(up)
                self.wait_selected(paused)
                message = f"HISTORY-{len(self.entries):03d}"
                self.write_journal([(message, "other.service", "xcat-genesis-register")])
                self.assert_paused(paused)
                self.key(down)
                self.wait_selected(previous_tail)
                message = f"HISTORY-{len(self.entries):03d}"
                self.write_journal([(message, "other.service", "xcat-genesis-register")])
                self.assert_paused(previous_tail)
                self.key(down)
                self.key(down)
                self.wait_selected(message)
                following = f"HISTORY-{len(self.entries):03d}"
                self.write_journal([(following, "other.service", "xcat-genesis-register")])
                self.wait_selected(following)

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
