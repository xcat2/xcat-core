#!/usr/bin/env python3
"""Exercise the linked Genesis console through a terminal, including newt dialogs."""

import fcntl
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

import pyte


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console"


class ConsoleDialogs(unittest.TestCase):
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
        environment = {"PATH": os.environ["PATH"], "LC_ALL": "C.UTF-8", "TERM": "xterm"}
        for name in ("CMDLINE_FILE", "UPTIME_FILE", "OS_RELEASE", "STATUS_DIR", "STATE_FILE",
                     "DESTINY_FILE", "RESPONSE_FILE", "SYS_ROOT", "PROC_ROOT", "EXTENSION_DIR", "PROVIDER_DIR"):
            environment["XCAT_" + name] = str(root / name.lower())
        Path(environment["XCAT_RESPONSE_FILE"]).write_text("XCAT_NODE_NAME=dialog-test-node\n")
        self.master, slave = pty.openpty()
        self.addCleanup(os.close, self.master)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        try:
            self.process = subprocess.Popen([str(self.binary)], stdin=slave, stdout=slave,
                                            stderr=slave, env=environment, start_new_session=True)
        finally:
            os.close(slave)
        self.addCleanup(self.stop)
        self.screen = pyte.Screen(100, 30)
        self.stream = pyte.ByteStream(self.screen)
        self.wait_text("Genesis status")

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
