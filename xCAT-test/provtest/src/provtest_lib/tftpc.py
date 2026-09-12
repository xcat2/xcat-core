"""TFTP, fetched the way a loader fetches: the `tftp` client.

The names are the thing under test at this stage. A loader asks for
`boot/grub2/grub.cfg-0A63010B` and nothing else; if `nodeset` wrote the hex a
digit out, the transfer fails and the node simply times out at the loader with
no error anywhere on the management node. So the fetch is by exact name, and
the reply carries the size and a digest, which is what lets one scenario assert
that the same bytes come back over TFTP and over HTTP.

The `tftp` client has no way to choose a source address. It does not need one:
TFTP has no notion of who is asking, so nothing at this stage depends on which
end of the veth pair the request left by.
"""

import hashlib
import os
import re
import tempfile

from . import proc
from .model import Reply

ERROR_RE = re.compile(r"Error code (\d+):\s*(.*)")

#: The bytes above which a fetched file is summarised rather than carried.
#: A kernel is tens of megabytes and no assertion reads it as text; a config
#: file is a few hundred bytes and every assertion does.
TEXT_LIMIT = 1 << 20


def build(server, path, port=69, mode="octet", local=None):
    """The `tftp` command line for one fetch."""
    tftp = proc.require("tftp", "TFTP")
    return [tftp, str(server), str(int(port)), "-m", mode,
            "-c", "get", str(path), str(local)]


def fetch(server, path, port=69, mode="octet", timeout=10.0, keep=None):
    """Fetch one file and return a `Reply` describing what arrived."""
    handle, local = tempfile.mkstemp(prefix="provtest-tftp-")
    os.close(handle)
    try:
        argv = build(server, path, port, mode, local)
        done = proc.run(argv, timeout=float(timeout) + 5.0)
        reply = _decode(done, local, server, path)
        if keep and reply.fields.get("ok"):
            _copy(local, keep)
        return reply
    finally:
        try:
            os.unlink(local)
        except OSError:
            pass


def _decode(done, local, server, path):
    size = os.path.getsize(local) if os.path.exists(local) else 0
    body = b""
    if size and size <= TEXT_LIMIT:
        with open(local, "rb") as handle:
            body = handle.read()

    digest = _digest(local) if size else ""
    error = ""
    match = ERROR_RE.search(done.text + done.errtext)
    if match:
        error = "%s (code %s)" % (match.group(2).strip(), match.group(1))
    elif done.timed_out:
        error = "the transfer did not finish within the timeout"
    elif done.rc != 0:
        error = (done.errtext.strip() or done.text.strip()
                 or "tftp exited %d" % (done.rc,))

    # tftp-hpa creates the local file before it knows whether the server will
    # answer, so a zero-length result with no error is still a failure: no
    # file this suite fetches is legitimately empty.
    ok = not error and size > 0

    fields = {
        "ok": ok,
        "size": size,
        "sha256": digest,
        "text": body.decode("utf-8", "replace"),
        "error": error,
        "path": path,
        "server": server,
    }
    reply = Reply(kind="tftp", fields=fields, ok=ok, error=error,
                  sent=done.command(), raw=body)
    return reply


def _digest(local):
    digest = hashlib.sha256()
    with open(local, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _copy(local, target):
    with open(local, "rb") as source:
        with open(target, "wb") as sink:
            for chunk in iter(lambda: source.read(65536), b""):
                sink.write(chunk)
