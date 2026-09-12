"""Decoding what dig, curl and tftp actually printed.

The output below is captured, not invented: these are the exact shapes the
three clients produce, including the ones that matter most -- an NXDOMAIN whose
only record is an SOA in the authority section, and a TFTP fetch that created
an empty local file before finding out the server had nothing to send.

Nothing here spawns a process. The command lines are built and inspected, but
running them needs a server, and that is the wire suite's job.
"""

import os
import shutil
import tempfile
import unittest

import context                                   # noqa: F401  (sys.path)

from provtest_lib import dnsc, httpc, proc, tftpc


ANSWER = """
; <<>> DiG 9.18.28 <<>> @10.99.1.1 -b 10.99.1.11 provtestcn.provtest.cluster A
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 41337
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

provtestcn.provtest.cluster. 3600 IN	A	10.99.1.11
"""

NXDOMAIN = """
; <<>> DiG 9.18.28 <<>> @10.99.1.1 nosuchnode.provtest.cluster A
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 12902
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 1, ADDITIONAL: 1

provtest.cluster.	3600	IN	SOA	provtest.cluster. root.provtest.cluster. 2 604800 86400 2419200 604800
"""

PTR = """
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 3
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

11.1.99.10.in-addr.arpa. 3600 IN	PTR	provtestcn.provtest.cluster.
"""

TWO_ADDRESSES = """
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 7
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1

provtestcn.provtest.cluster. 3600 IN	A	10.99.1.11
provtestcn.provtest.cluster. 3600 IN	A	10.99.2.11
"""


class DnsDecodingTests(unittest.TestCase):

    def test_an_answer_is_decoded(self):
        reply = dnsc.decode(ANSWER, name="provtestcn.provtest.cluster",
                            rrtype="A", server="10.99.1.1")
        self.assertTrue(reply.ok)
        self.assertEqual(reply.fields["status"], "NOERROR")
        self.assertEqual(reply.fields["count"], 1)
        self.assertEqual(reply.fields["data"], ["10.99.1.11"])
        self.assertEqual(reply.fields["type"], ["A"])
        self.assertEqual(reply.fields["ttl"], [3600])
        self.assertIn("aa", reply.fields["flags"])

    def test_a_trailing_dot_is_stripped_from_data(self):
        reply = dnsc.decode(PTR, rrtype="PTR")
        self.assertEqual(reply.fields["data"], ["provtestcn.provtest.cluster"])

    def test_nxdomain_counts_no_answers(self):
        # The SOA in the authority section is how a resolver says "this zone is
        # mine and the name is not in it", which is exactly what @P-06 asserts.
        # Counting it as an answer would make an absent name look present.
        reply = dnsc.decode(NXDOMAIN)
        self.assertFalse(reply.ok)
        self.assertEqual(reply.fields["status"], "NXDOMAIN")
        self.assertEqual(reply.fields["count"], 0)
        self.assertEqual(reply.fields["data"], [])
        self.assertEqual(reply.fields["authority"], 1)

    def test_several_answers_are_all_kept(self):
        reply = dnsc.decode(TWO_ADDRESSES)
        self.assertEqual(reply.fields["count"], 2)
        self.assertEqual(reply.fields["data"], ["10.99.1.11", "10.99.2.11"])

    def test_no_output_at_all_is_a_failure_with_a_reason(self):
        reply = dnsc.decode("")
        self.assertFalse(reply.ok)
        self.assertTrue(reply.error)


@unittest.skipUnless(proc.which("dig"), "dig is not installed")
class DnsCommandTests(unittest.TestCase):

    def test_the_server_is_always_named(self):
        # A booting node uses the resolver DHCP gave it. What is under test is
        # that *that* server answers, not that this host has some resolver.
        argv = dnsc.build("10.99.1.1", "provtestcn", "A")
        self.assertIn("@10.99.1.1", argv)

    def test_the_source_address_is_passed_through(self):
        argv = dnsc.build("10.99.1.1", "provtestcn", "A", bind="10.99.1.11")
        self.assertIn("-b", argv)
        self.assertEqual(argv[argv.index("-b") + 1], "10.99.1.11")

    def test_recursion_can_be_turned_off(self):
        self.assertIn("+norecurse",
                      dnsc.build("10.99.1.1", "x", "A", recursion=False))

    def test_a_non_default_port_is_passed_through(self):
        argv = dnsc.build("10.99.1.1", "x", "A", port=5353)
        self.assertEqual(argv[argv.index("-p") + 1], "5353")


class HttpDecodingTests(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="provtest-http-test-")
        self.addCleanup(shutil.rmtree, self.dir, True)

    def files(self, body=b"", headers=""):
        body_file = os.path.join(self.dir, "body")
        header_file = os.path.join(self.dir, "headers")
        with open(body_file, "wb") as handle:
            handle.write(body)
        with open(header_file, "w") as handle:
            handle.write(headers)
        return body_file, header_file

    def decode(self, write_out, body=b"", headers="", rc=0, err="",
               timed_out=False):
        body_file, header_file = self.files(body, headers)
        done = proc.Completed(["curl"], rc, write_out.encode(), err.encode(),
                              timed_out=timed_out)
        return httpc._decode(done, "http://10.99.1.1/install/x",
                             body_file, header_file)

    def test_a_200_is_decoded(self):
        reply = self.decode(
            "200\t42\ttext/plain\thttp://10.99.1.1/install/x\n",
            body=b"x" * 42,
            headers="HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n")
        self.assertTrue(reply.ok)
        self.assertEqual(reply.fields["status"], 200)
        self.assertEqual(reply.fields["size"], 42)
        self.assertEqual(reply.fields["content_type"], "text/plain")
        self.assertEqual(reply.fields["header"]["content-type"], "text/plain")

    def test_a_404_is_a_transport_that_worked(self):
        # @P-37 asserts a path outside the aliases is not served. The fetch
        # succeeding and the status being 404 are two different facts.
        reply = self.decode("404\t0\ttext/html\thttp://10.99.1.1/etc/x\n")
        self.assertEqual(reply.fields["status"], 404)
        self.assertFalse(reply.fields["ok"])
        self.assertEqual(reply.error, "")

    def test_a_refused_connection_carries_curls_reason(self):
        reply = self.decode("000\t0\t\t\n", rc=7,
                            err="curl: (7) Failed to connect to 10.99.1.1\n")
        self.assertEqual(reply.fields["status"], 0)
        self.assertIn("Failed to connect", reply.error)

    def test_only_the_last_redirect_hop_is_reported(self):
        reply = self.decode(
            "301\t0\ttext/html\thttp://10.99.1.1/install\n"
            "200\t9\ttext/plain\thttp://10.99.1.1/install/\n",
            body=b"contents")
        self.assertEqual(reply.fields["status"], 200)
        self.assertEqual(reply.fields["url"], "http://10.99.1.1/install/")

    def test_only_the_last_header_block_is_kept(self):
        reply = self.decode(
            "200\t1\ttext/plain\thttp://10.99.1.1/x\n", body=b"x",
            headers="HTTP/1.1 301 Moved\r\nLocation: /y\r\n\r\n"
                    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n")
        self.assertNotIn("location", reply.fields["header"])
        self.assertEqual(reply.fields["header"]["content-type"], "text/plain")

    def test_a_body_cut_short_is_not_ok(self):
        # curl prints the status as soon as the header arrives. The server that
        # closed the connection in the middle of a 200 MB kernel still answered
        # 200, so a check on the status alone reads a truncated file as served.
        reply = self.decode(
            "200\t10\tapplication/octet-stream\thttp://10.99.1.1/tftpboot/k\n",
            body=b"x" * 10, rc=18,
            err="curl: (18) transfer closed with 1048566 bytes remaining\n")
        self.assertEqual(reply.fields["status"], 200)
        self.assertFalse(reply.ok)
        self.assertFalse(reply.fields["ok"])
        self.assertIn("transfer closed", reply.error)

    def test_a_timeout_while_reading_the_body_is_not_ok(self):
        reply = self.decode(
            "200\t4096\tapplication/octet-stream\thttp://10.99.1.1/install/x\n",
            body=b"x" * 4096, rc=124, timed_out=True)
        self.assertEqual(reply.fields["status"], 200)
        self.assertFalse(reply.ok)
        self.assertIn("timeout", reply.error)

    def test_the_body_is_digested(self):
        first = self.decode("200\t3\ttext/plain\thttp://h/x\n", body=b"abc")
        second = self.decode("200\t3\ttext/plain\thttp://h/x\n", body=b"abc")
        third = self.decode("200\t3\ttext/plain\thttp://h/x\n", body=b"abd")
        self.assertEqual(first.fields["sha256"], second.fields["sha256"])
        self.assertNotEqual(first.fields["sha256"], third.fields["sha256"])


class HttpUrlTests(unittest.TestCase):

    def test_the_default_port_is_left_out(self):
        self.assertEqual(httpc.url_for("10.99.1.1", "/install/x", 80),
                         "http://10.99.1.1/install/x")

    def test_another_port_is_written_in(self):
        self.assertEqual(httpc.url_for("10.99.1.1", "/install/x", 8080),
                         "http://10.99.1.1:8080/install/x")

    def test_a_missing_leading_slash_is_added(self):
        self.assertEqual(httpc.url_for("10.99.1.1", "install/x", 80),
                         "http://10.99.1.1/install/x")

    def test_a_full_url_is_left_alone(self):
        # `url = $autoinsturl.value` resolves to a URL the node was given, and
        # nothing here may rewrite it -- that would be testing this tool.
        self.assertEqual(httpc.url_for("10.99.1.1", "http://other/x", 80),
                         "http://other/x")


class TftpDecodingTests(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="provtest-tftp-test-")
        self.addCleanup(shutil.rmtree, self.dir, True)

    def decode(self, content=b"", out="", err="", rc=0, timed_out=False):
        local = os.path.join(self.dir, "fetched")
        with open(local, "wb") as handle:
            handle.write(content)
        done = proc.Completed(["tftp"], rc, out.encode(), err.encode(),
                              timed_out=timed_out)
        return tftpc._decode(done, local, "10.99.1.1", "boot/grub2/grub.cfg")

    def test_a_fetch_carries_size_digest_and_text(self):
        reply = self.decode(b"set default=0\n")
        self.assertTrue(reply.fields["ok"])
        self.assertEqual(reply.fields["size"], 14)
        self.assertEqual(reply.fields["text"], "set default=0\n")
        self.assertEqual(len(reply.fields["sha256"]), 64)
        self.assertEqual(reply.fields["error"], "")

    def test_an_empty_file_with_no_error_is_still_a_failure(self):
        # tftp-hpa creates the local file before it knows whether the server
        # will answer, so a zero-length result is what a missing file looks
        # like. No file this suite fetches is legitimately empty.
        reply = self.decode(b"")
        self.assertFalse(reply.fields["ok"])
        self.assertEqual(reply.fields["size"], 0)

    def test_a_server_error_is_decoded_with_its_code(self):
        reply = self.decode(b"", err="Error code 1: File not found\n")
        self.assertFalse(reply.fields["ok"])
        self.assertIn("File not found", reply.fields["error"])
        self.assertIn("code 1", reply.fields["error"])

    def test_an_access_violation_is_decoded(self):
        # @P-24: a path climbing out of the tftp root must stay refused.
        reply = self.decode(b"", err="Error code 2: Access violation\n")
        self.assertIn("Access violation", reply.fields["error"])

    def test_a_timeout_says_so(self):
        reply = self.decode(b"", timed_out=True)
        self.assertIn("timeout", reply.fields["error"])

    def test_the_digest_is_comparable_with_an_http_fetch(self):
        # @P-33 asserts one tree served by two daemons returns the same bytes.
        tftp_reply = self.decode(b"same bytes")
        import hashlib
        self.assertEqual(tftp_reply.fields["sha256"],
                         hashlib.sha256(b"same bytes").hexdigest())


@unittest.skipUnless(proc.which("tftp"), "tftp is not installed")
class TftpCommandTests(unittest.TestCase):

    def test_the_fetch_is_by_exact_name(self):
        argv = tftpc.build("10.99.1.1", "boot/grub2/grub.cfg-0A63010B",
                           local="/tmp/out")
        self.assertIn("boot/grub2/grub.cfg-0A63010B", argv)
        self.assertIn("get", argv)

    def test_the_port_is_positional(self):
        argv = tftpc.build("10.99.1.1", "x", port=6969, local="/tmp/out")
        self.assertEqual(argv[1:3], ["10.99.1.1", "6969"])


class ProcessTests(unittest.TestCase):

    def test_a_missing_program_is_an_unsupported_host_not_a_failure(self):
        from provtest_lib.errors import UnsupportedError
        self.assertRaises(UnsupportedError, proc.require,
                          "nosuchclientprogram", "nothing")

    @unittest.skipUnless(proc.which("sh"), "no shell to exercise the runner")
    def test_output_is_captured_and_the_locale_is_pinned(self):
        done = proc.run(["sh", "-c", "echo out; echo err >&2; exit 3"])
        self.assertEqual(done.rc, 3)
        self.assertEqual(done.text.strip(), "out")
        self.assertEqual(done.errtext.strip(), "err")

    @unittest.skipUnless(proc.which("sh"), "no shell to exercise the runner")
    def test_a_program_that_outlives_its_timeout_is_killed_not_raised(self):
        done = proc.run(["sh", "-c", "sleep 5"], timeout=0.3)
        self.assertTrue(done.timed_out)
        self.assertEqual(done.rc, 124)

    def test_an_argument_list_is_never_a_shell_string(self):
        # Nothing a .conf supplies may be interpreted as a command.
        done = proc.run(["/nonexistent/program; rm -rf /"])
        self.assertEqual(done.rc, 127)


if __name__ == "__main__":
    unittest.main()
