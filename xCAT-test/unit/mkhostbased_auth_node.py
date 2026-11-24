import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hostbased", sys.argv.pop(1))
hostbased = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hostbased)


class HostbasedConfigTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sshdir = Path(self.tmp.name)
        self.server = self.sshdir / "sshd_config"
        self.client = self.sshdir / "ssh_config"
        self.server_text = "# previous settings\nHostKey /not-needed-for-fixtures\nPubkeyAuthentication yes\n"
        self.client_text = "# previous settings\nHost *\n    BatchMode yes\n"
        self.server.write_text(self.server_text)
        self.client.write_text(self.client_text)
        self.request = {
            "operation": "check",
            "user": "hpc",
            "remove": 0,
            "peers": [
                {"name": "compute01", "address": "10.3.0.1", "keys": ["ssh-ed25519 AQ=="]},
                {"name": "compute02", "address": "10.3.0.2", "keys": ["ssh-ed25519 Ag=="]},
            ],
        }

    def contents(self):
        return hostbased.file_contents(self.sshdir, self.sshdir, self.request)

    def include_directory(self, config):
        directory = config.with_suffix(".d")
        directory.mkdir()
        include = f"Include {directory}/*.conf\n"
        config.write_text(include + config.read_text())
        return directory, include

    def test_migrates_managed_blocks_to_drop_ins(self):
        self.request["operation"] = "apply"
        with patch.object(hostbased, "validate"), patch.object(hostbased, "run") as run, \
                patch.object(hostbased, "ssh_service", return_value="sshd.service"), \
                patch.object(hostbased.shutil, "which", return_value=None):
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            expected_match = "Match User hpc Address 10.3.0.1,10.3.0.2"
            expected_hosts = "Host compute01 10.3.0.1 compute02 10.3.0.2"
            self.assertIn(expected_match, self.server.read_text())
            self.assertIn(expected_hosts, self.client.read_text())

            server_dir, server_include = self.include_directory(self.server)
            client_dir, client_include = self.include_directory(self.client)
            server_drop_in = server_dir / "01-xcat-hostbased-auth.conf"
            client_drop_in = client_dir / "01-xcat-hostbased-auth.conf"
            server_site = server_dir / "90-site.conf"
            server_site.write_text("PermitTTY yes\n")
            hostbased.configure(self.sshdir, self.sshdir, self.request)

            self.assertEqual(self.server.read_text(), server_include + self.server_text)
            self.assertEqual(self.client.read_text(), client_include + self.client_text)
            self.assertIn(expected_match, server_drop_in.read_text())
            self.assertIn(expected_hosts, client_drop_in.read_text())
            self.assertEqual(client_drop_in.stat().st_mode & 0o777, 0o644)
            self.assertEqual(server_site.read_text(), "PermitTTY yes\n")
            reload_calls = run.call_count
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            self.assertEqual(run.call_count, reload_calls)

            client_drop_in.chmod(0o600)
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            self.assertEqual(client_drop_in.stat().st_mode & 0o777, 0o644)
            self.assertIn(expected_hosts, client_drop_in.read_text())

            self.request["remove"] = 1
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            self.assertEqual(self.server.read_text(), server_include + self.server_text)
            self.assertEqual(self.client.read_text(), client_include + self.client_text)
            self.assertEqual(server_site.read_text(), "PermitTTY yes\n")
            self.assertFalse(server_drop_in.exists())
            self.assertFalse(client_drop_in.exists())
            self.assertFalse((self.sshdir / "ssh_known_hosts").exists())
            self.assertFalse((self.sshdir / "shosts.equiv").exists())

    def test_apply_is_idempotent_and_remove_restores_configuration(self):
        self.request["operation"] = "apply"
        self.server.chmod(0o600)
        with patch.object(hostbased, "validate"), patch.object(hostbased, "run") as run, \
                patch.object(hostbased, "ssh_service", return_value="sshd.service"), \
                patch.object(hostbased.shutil, "which", return_value=None):
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            after = self.server.read_text()
            self.assertIn(self.server_text, after)
            self.assertIn("Match User hpc Address 10.3.0.1,10.3.0.2", after)
            self.assertEqual(self.server.stat().st_mode & 0o777, 0o600)
            self.assertIn("Host compute01 10.3.0.1 compute02 10.3.0.2", self.client.read_text())
            self.assertEqual(hostbased.active_lines((self.sshdir / "shosts.equiv").read_text()), ["10.3.0.1", "10.3.0.2"])
            self.assertEqual(run.call_count, 2)
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            self.assertEqual(run.call_count, 2)
            self.request["remove"] = 1
            hostbased.configure(self.sshdir, self.sshdir, self.request)
            self.assertEqual(self.server.read_text(), self.server_text)
            self.assertEqual(self.client.read_text(), self.client_text)
            self.assertFalse((self.sshdir / "ssh_known_hosts").exists())
            self.assertFalse((self.sshdir / "shosts.equiv").exists())

    def test_reload_failure_restores_previous_files(self):
        self.request["operation"] = "apply"
        with patch.object(hostbased, "validate"), \
                patch.object(hostbased, "ssh_service", return_value="sshd.service"), \
                patch.object(hostbased.shutil, "which", return_value=None), \
                patch.object(hostbased, "run", side_effect=["", ValueError("reload failed"), ""]):
            with self.assertRaisesRegex(ValueError, "reload failed"):
                hostbased.configure(self.sshdir, self.sshdir, self.request)
        self.assertEqual(self.server.read_text(), self.server_text)
        self.assertEqual(self.client.read_text(), self.client_text)
        self.assertFalse((self.sshdir / "ssh_known_hosts").exists())
        self.assertFalse((self.sshdir / "shosts.equiv").exists())

    def test_rejects_an_unmanaged_drop_in(self):
        server_dir, _ = self.include_directory(self.server)
        conflict = server_dir / "01-xcat-hostbased-auth.conf"
        conflict.write_text("PermitTTY no\n")
        for remove in (0, 1):
            self.request["remove"] = remove
            with self.assertRaisesRegex(ValueError, "is not managed by xCAT"):
                self.contents()
            self.assertEqual(conflict.read_text(), "PermitTTY no\n")

    def test_rejects_overlapping_policy_and_membership_change(self):
        (self.sshdir / "other.conf").write_text("Match User other\n    HostbasedAuthentication YES\n")
        self.server.write_text(self.server_text + "Include other.conf\n")
        with self.assertRaisesRegex(ValueError, "already enables host-based authentication"):
            self.contents()
        self.server.write_text(self.server_text)
        path = self.sshdir / "hosts.equiv"
        path.write_text("compute01 other\n")
        with self.assertRaisesRegex(ValueError, "Existing host equivalence rules"):
            self.contents()
        path.unlink()
        _, after = self.contents()
        for path, content in after.items():
            if content is not None:
                path.write_text(content)
        self.request["user"] = "other"
        with self.assertRaisesRegex(ValueError, "Remove the previous xCAT configuration"):
            self.contents()


if __name__ == "__main__":
    unittest.main()
