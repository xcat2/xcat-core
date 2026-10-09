#!/usr/bin/env python3
"""Build the Genesis console with its installed Meson definition."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console"


class ConsoleBuild(unittest.TestCase):
    def test_build_install_and_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="genesis-console-") as temporary:
            root = Path(temporary)
            build = root / "build"
            stage = root / "stage"
            subprocess.run(["meson", "setup", str(build), str(SOURCE), "--prefix=/usr"], check=True)
            options = json.loads(subprocess.check_output(["meson", "introspect", "--buildoptions", str(build)]))
            options = {option["name"]: option["value"] for option in options}
            self.assertEqual(options["c_std"], "c17")
            self.assertIs(options["werror"], True)
            subprocess.run(["meson", "compile", "-C", str(build)], check=True)
            subprocess.run(["meson", "install", "-C", str(build), "--destdir", str(stage)], check=True)
            binary = stage / "usr/sbin/xcat-genesis-console"
            self.assertTrue(os.access(binary, os.X_OK))
            environment = {"PATH": os.environ["PATH"], "LC_ALL": "C"}
            for name in ("CMDLINE_FILE", "UPTIME_FILE", "OS_RELEASE", "STATUS_DIR", "STATE_FILE",
                         "DESTINY_FILE", "RESPONSE_FILE", "SYS_ROOT", "PROC_ROOT", "EXTENSION_DIR", "PROVIDER_DIR"):
                environment["XCAT_" + name] = str(root / name.lower())
            Path(environment["XCAT_RESPONSE_FILE"]).write_text("XCAT_NODE_NAME=console-test-node\n")
            result = subprocess.run([str(binary), "--once"], env=environment, text=True,
                                    capture_output=True, timeout=10, check=True)
            self.assertIn("xCAT Genesis", result.stdout)
            self.assertIn("node: console-test-node", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
