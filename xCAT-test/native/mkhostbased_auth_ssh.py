import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("hostbased", sys.argv.pop(1))
hostbased = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hostbased)


class HostbasedOpenSSHTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.sshdir = Path(tmp.name)
        self.server = self.sshdir / "sshd_config"
        self.client = self.sshdir / "ssh_config"
        self.key = self.sshdir / "test-key"
        subprocess.run(["/usr/bin/ssh-keygen", "-q", "-N", "", "-t", "ed25519", "-f", self.key], check=True)
        self.server.write_text(f"HostKey {self.key}\nPubkeyAuthentication yes\n")
        self.client.write_text("Host *\n    BatchMode yes\n")
        self.request = {
            "operation": "check",
            "user": "hpc",
            "remove": 0,
            "peers": [
                {"name": "compute01", "address": "10.3.0.1", "keys": ["ssh-ed25519 AQ=="]},
                {"name": "compute02", "address": "10.3.0.2", "keys": ["ssh-ed25519 Ag=="]},
            ],
        }

    def test_effective_options(self):
        server_dir = self.sshdir / "sshd_config.d"
        client_dir = self.sshdir / "ssh_config.d"
        server_dir.mkdir()
        client_dir.mkdir()
        (server_dir / "90-site.conf").write_text("Match User other\n    PermitTTY no\n")
        self.server.write_text(f"Include {server_dir}/*.conf\n" + self.server.read_text())
        self.client.write_text(f"Include {client_dir}/*.conf\n" + self.client.read_text())
        _, after = hostbased.file_contents(self.sshdir, self.sshdir, self.request)
        hostbased.validate(self.sshdir, after, self.request)
        self.assertIn(server_dir / "01-xcat-hostbased-auth.conf", after)
        self.assertIn(client_dir / "01-xcat-hostbased-auth.conf", after)
        for path, content in after.items():
            if content is not None:
                path.write_text(content)
        for user, address, expected in [
            ("hpc", "10.3.0.1", "yes"),
            ("hpc", "10.3.0.2", "yes"),
            ("hpc", "10.3.0.3", "no"),
            ("other", "10.3.0.1", "no"),
            ("root", "10.3.0.1", "no"),
        ]:
            with self.subTest(user=user, address=address):
                effective = hostbased.effective_server(self.server, user, address)
                self.assertEqual(effective["hostbasedauthentication"], expected)
                self.assertEqual(effective["pubkeyauthentication"], "yes")
                self.assertEqual(effective["permittty"], "no" if user == "other" else "yes")

        for hostname, expected in [("compute01", "yes"), ("10.3.0.2", "yes"), ("compute03", "no")]:
            with self.subTest(hostname=hostname):
                result = subprocess.run(["/usr/bin/ssh", "-G", "-F", self.client, hostname],
                                        capture_output=True, check=True, text=True)
                effective = dict(line.split(maxsplit=1) for line in result.stdout.splitlines() if " " in line)
                self.assertEqual(effective["hostbasedauthentication"], expected)
                self.assertEqual(effective["batchmode"], "yes")

    def test_rejects_authentication_methods_without_hostbased(self):
        self.server.write_text(self.server.read_text() + "AuthenticationMethods publickey\n")
        _, after = hostbased.file_contents(self.sshdir, self.sshdir, self.request)
        with self.assertRaisesRegex(ValueError, "AuthenticationMethods policy"):
            hostbased.validate(self.sshdir, after, self.request)


if __name__ == "__main__":
    unittest.main()
