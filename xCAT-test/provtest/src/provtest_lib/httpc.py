"""HTTP, fetched the way an installer fetches: `curl`.

Two different things are served over HTTP during a provision and both are
tested here. grub2-http and xnba fetch the kernel and initrd from
`/tftpboot/...`; the installer fetches the repository and its kickstart or
preseed from `/install/...`. They are two Apache aliases over the same port,
and a cluster that has moved off port 80 has to have moved the URL in the
kernel command line with it -- which is why the port comes out of the config
the node was handed, not out of a constant.

The body is written to a file rather than captured through a pipe, so a digest
of a kernel can be compared against the same kernel fetched over TFTP without
either ever being decoded as text.
"""

import hashlib
import os
import tempfile

from . import proc
from .model import Reply

#: Above this, a body is measured and digested but not carried as text.
TEXT_LIMIT = 1 << 20

#: What `-w` prints, in this order, on one line.
WRITE_OUT = "%{http_code}\\t%{size_download}\\t%{content_type}\\t%{url_effective}\\n"


def url_for(server, path, port=80, scheme="http"):
    """Join a server, a port and a path into a URL."""
    text = str(path)
    if text.startswith("http://") or text.startswith("https://"):
        return text
    if not text.startswith("/"):
        text = "/" + text
    port = int(port or 80)
    if (scheme == "http" and port == 80) or (scheme == "https" and port == 443):
        return "%s://%s%s" % (scheme, server, text)
    return "%s://%s:%d%s" % (scheme, server, port, text)


def build(url, method="GET", bind=None, headers=(), timeout=10.0,
          body_file=None, header_file=None, insecure=False):
    """The `curl` command line for one request."""
    curl = proc.require("curl", "HTTP")
    argv = [curl, "-sS", "--globoff", "--max-time", str(int(float(timeout))),
            "-o", body_file, "-D", header_file, "-w", WRITE_OUT]
    if bind:
        argv += ["--interface", str(bind)]
    if insecure:
        argv += ["-k"]
    method = (method or "GET").upper()
    if method == "HEAD":
        argv += ["-I"]
    elif method != "GET":
        argv += ["-X", method]
    for header in headers:
        argv += ["-H", header]
    argv += [url]
    return argv


def fetch(url, method="GET", bind=None, headers=(), timeout=10.0,
          insecure=False):
    """Make one request and return a `Reply` describing the response."""
    body_handle, body_file = tempfile.mkstemp(prefix="provtest-http-")
    head_handle, header_file = tempfile.mkstemp(prefix="provtest-hdr-")
    os.close(body_handle)
    os.close(head_handle)
    try:
        argv = build(url, method, bind, headers, timeout, body_file,
                     header_file, insecure)
        done = proc.run(argv, timeout=float(timeout) + 5.0)
        return _decode(done, url, body_file, header_file)
    finally:
        for path in (body_file, header_file):
            try:
                os.unlink(path)
            except OSError:
                pass


def _decode(done, url, body_file, header_file):
    status, size, content_type, effective = _write_out(done.text, url)
    disk_size = os.path.getsize(body_file) if os.path.exists(body_file) else 0
    body = b""
    if 0 < disk_size <= TEXT_LIMIT:
        with open(body_file, "rb") as handle:
            body = handle.read()
    digest = _digest(body_file) if disk_size else ""

    error = ""
    if done.timed_out:
        error = "the request did not finish within the timeout"
    elif done.rc != 0:
        error = (done.errtext.strip().replace("curl: ", "", 1)
                 or "curl exited %d" % (done.rc,))

    fields = {
        "status": status,
        "size": size or disk_size,
        "sha256": digest,
        "text": body.decode("utf-8", "replace"),
        "url": effective,
        "header": _headers(header_file),
        "content_type": content_type,
        "error": error,
        # curl prints the status as soon as the response header arrives. A
        # transfer that then stopped -- the connection closed mid-body, the
        # clock ran out -- leaves a status of 200 and a file holding part of a
        # kernel, so the status alone does not say the fetch worked.
        "ok": bool(status and 200 <= status < 400 and not error),
    }
    return Reply(kind="http", fields=fields, ok=fields["ok"], error=error,
                 sent=done.command(), raw=body)


def _write_out(text, url):
    """The last `-w` line: status, size, content type, effective URL.

    The last line, not the first: a redirect that `curl` was asked to follow
    would print one per hop, and the response under test is the final one.
    """
    for line in reversed(text.strip().splitlines()):
        parts = line.split("\t")
        if len(parts) != 4:
            continue
        try:
            status = int(parts[0])
        except ValueError:
            status = 0
        try:
            size = int(parts[1])
        except ValueError:
            size = 0
        return status, size, parts[2].strip(), parts[3].strip() or url
    return 0, 0, "", url


def _headers(path):
    """The response headers, lowercased, as a mapping.

    Only the last response block is kept, for the same reason as above.
    """
    headers = {}
    if not os.path.exists(path):
        return headers
    with open(path, "rb") as handle:
        text = handle.read().decode("utf-8", "replace")
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.upper().startswith("HTTP/"):
            headers = {}
            continue
        key, _, value = stripped.partition(":")
        if value:
            headers[key.strip().lower()] = value.strip()
    return headers


def _digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()
