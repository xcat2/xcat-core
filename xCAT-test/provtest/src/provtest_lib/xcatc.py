"""A small xCAT client: the four ways a booting node talks to xcatd.

A node being provisioned makes exactly four kinds of request, and none of them
needs an xCAT command or an xCAT library to make:

  * **TLS on 3001** -- `getdestiny`, `nextdestiny`, `getpostscript`,
    `getcredentials`. The genesis scripts send a few lines of XML down
    `openssl s_client` and read a few lines back; this does the same over a
    socket, so a request can be sent from a chosen source address.
  * **Plain TCP on 3002** -- the install monitor. A line protocol with no TLS
    at all, framed by `ready` and `done`.
  * **UDP on 3001** -- flow control (`resourcerequest: xcatd`) and `findme`.
  * **A connection back to the node** -- xcatd answers a findme by connecting
    out to the client's TCP 3001, and signs a certificate only after the
    client's TCP 300 agrees. Both are listeners this module can stand up.

Two things about xcatd make all of this reachable from a script, and both are
why this suite can exist at all. The TLS listener accepts a client with no
certificate, and identity comes from the reverse lookup of the address the
connection arrived from. So the address a request leaves by *is* the identity,
which is why every call here takes a `bind`.
"""

import gzip
import re
import socket
import ssl
import threading
import time

from .model import Reply

#: The elements a node's own scripts read out of a response. Everything else
#: found in the XML is still available through `elements.<name>`.
NAMED_ELEMENTS = ("destiny", "kernel", "initrd", "kcmdline", "imgserver",
                  "name", "data", "error", "content", "desc")

ELEMENT_RE = re.compile(r"<([A-Za-z_][\w.-]*)>([^<]*)</\1>")

#: What the install monitor prints before it will read anything.
GREETING = "ready"

#: The default callback port the genesis scripts declare.
CALLBACK_PORT = 300


# ---------------------------------------------------------------------------
# listeners on the client's side


class Listener(object):
    """A socket on the client end, for the connections xcatd makes outward.

    Started before the request that provokes the callback and stopped after
    it, so a scenario can assert both that a callback arrived and -- the more
    interesting case -- that it did not.
    """

    def __init__(self, address, port, reply=None, backlog=4):
        self.address = address
        self.port = int(port)
        self.reply = reply
        self.received = []
        self.peers = []
        self.error = ""
        self._socket = None
        self._thread = None
        self._stop = threading.Event()
        self._backlog = backlog

    def start(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((self.address or "", self.port))
            sock.listen(self._backlog)
            sock.settimeout(0.2)
        except OSError as exc:
            self.error = "cannot listen on %s:%d: %s" % (
                self.address or "*", self.port, exc)
            return self
        self._socket = sock
        self._thread = threading.Thread(target=self._serve)
        self._thread.daemon = True
        self._thread.start()
        return self

    def _serve(self):
        while not self._stop.is_set():
            try:
                conn, peer = self._socket.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            try:
                conn.settimeout(2.0)
                data = b""
                while True:
                    try:
                        chunk = conn.recv(4096)
                    except (socket.timeout, OSError):
                        break
                    if not chunk:
                        break
                    data += chunk
                    if self.reply is not None:
                        break
                if self.reply is not None:
                    try:
                        conn.sendall(self.reply.encode())
                    except OSError:
                        pass
                self.received.append(data.decode("utf-8", "replace").strip())
                self.peers.append(peer[0])
            finally:
                try:
                    conn.close()
                except OSError:
                    pass

    def stop(self):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2.0)
        if self._socket is not None:
            try:
                self._socket.close()
            except OSError:
                pass
        return self.received

    def wait(self, seconds):
        """Block until something arrives, or the time runs out."""
        deadline = time.time() + float(seconds)
        while time.time() < deadline and not self.received:
            time.sleep(0.05)
        return self.received


# ---------------------------------------------------------------------------
# TLS on 3001


def request(server, command, port=3001, elements=(), bind=None, timeout=10.0,
            cert=None, key=None, callback_port=None, callback_listen=None,
            callback_reply=None, callback_wait=2.0, raw=None,
            source_port=None):
    """Send one `<xcatrequest>` over TLS and decode what came back."""
    body = raw if raw is not None else _xml(command, elements, callback_port)
    listener = None
    if callback_listen:
        listener = Listener(bind, int(callback_listen), callback_reply).start()

    # Always present, listener or not: "no callback arrived" is an assertion a
    # scenario makes, and a field that is missing rather than false cannot be
    # asserted against.
    fields = {"callback_seen": False, "callback_data": []}
    error = ""
    handshake = False
    text = ""
    try:
        sock = _tcp(server, int(port), bind, timeout, source_port)
        context = _tls_context(cert, key)
        try:
            stream = context.wrap_socket(sock, server_hostname=None)
        except ssl.SSLError as exc:
            sock.close()
            raise OSError("TLS handshake failed: %s" % (exc,))
        handshake = True
        try:
            stream.sendall(body.encode())
            text = _drain(stream, timeout)
        finally:
            try:
                stream.close()
            except OSError:
                pass
    except OSError as exc:
        error = str(exc)

    if listener is not None:
        listener.wait(callback_wait)
        fields["callback_data"] = listener.stop()
        fields["callback_seen"] = bool(fields["callback_data"])
        if listener.error and not error:
            error = listener.error

    fields.update(decode_elements(text))
    fields["text"] = text
    fields["handshake"] = handshake
    fields["ok"] = handshake and bool(text) and not fields.get("error")
    return Reply(kind="xcatreq", fields=fields, ok=fields["ok"], error=error,
                 sent=body.strip().replace("\n", " "),
                 raw=text.encode("utf-8", "replace"))


def decode_elements(text):
    """Every `<tag>value</tag>` in a response, flattened.

    Flattened deliberately: the genesis scripts read the response with `sed`,
    one element at a time and with no regard for nesting, so a test that
    parsed it as a tree could pass where a node fails.
    """
    elements = {}
    for name, value in ELEMENT_RE.findall(text):
        elements.setdefault(name, value.strip())
    fields = {"elements": elements, "serverdone": "<serverdone" in text}
    for name in NAMED_ELEMENTS:
        if name in elements:
            fields[name] = elements[name]
    return fields


def _xml(command, elements=(), callback_port=None):
    lines = ["<xcatrequest>", "<command>%s</command>" % (command,)]
    if callback_port:
        lines.append("<callback_port>%s</callback_port>" % (callback_port,))
    for name, value in elements:
        lines.append("<%s>%s</%s>" % (name, value, name))
    lines.append("</xcatrequest>")
    return "\n".join(lines) + "\n"


def _tls_context(cert=None, key=None):
    """A client context that verifies nothing.

    That is not a shortcut: it is what the genesis scripts do. `openssl
    s_client` with no `-CAfile` accepts whatever certificate it is shown, and
    a node has no CA to check against until xcatd has signed one for it.
    """
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    if cert:
        context.load_cert_chain(cert, key or None)
    return context


def _drain(stream, timeout):
    """Read until the server is done, or the timeout, whichever is first."""
    stream.settimeout(timeout)
    deadline = time.time() + float(timeout)
    text = ""
    while time.time() < deadline:
        try:
            chunk = stream.recv(8192)
        except (socket.timeout, ssl.SSLError):
            break
        except OSError:
            break
        if not chunk:
            break
        text += chunk.decode("utf-8", "replace")
        if "<serverdone" in text:
            break
    return text


# ---------------------------------------------------------------------------
# plain TCP on 3002


def monitor(server, send=(), port=3002, bind=None, timeout=10.0,
            source_port=None):
    """Speak the install monitor's line protocol.

    xcatd closes the connection without a greeting when the peer's address
    does not reverse-resolve to a node, so an empty greeting is a result and
    not an error.
    """
    lines = []
    greeting = ""
    error = ""
    closed = False
    try:
        sock = _tcp(server, int(port), bind, timeout, source_port)
        sock.settimeout(timeout)
        try:
            greeting, rest = _read_line(sock, b"")
            for line in send:
                sock.sendall((line.rstrip("\n") + "\n").encode())
                answer, rest = _read_line(sock, rest)
                if answer == "":
                    closed = True
                    break
                lines.append(answer)
            if not closed:
                # Everything the server says after the framing token. Several
                # verbs answer `done` and then keep writing -- getpostscript
                # sends the whole script and `#END OF SCRIPT` afterwards -- so
                # a reader that stopped at the first line would report a
                # complete exchange and an empty script.
                trailing, closed = _drain_lines(sock, rest)
                lines.extend(trailing)
        finally:
            sock.close()
    except OSError as exc:
        error = str(exc)

    fields = {
        "greeting": greeting,
        "lines": lines,
        "text": "\n".join([greeting] + lines).strip(),
        "closed": closed,
        "ok": greeting == GREETING,
        "error": error,
    }
    return Reply(kind="monitor", fields=fields, ok=fields["ok"], error=error,
                 sent="; ".join(send))


def _read_line(sock, buffered):
    """One newline-terminated line, and whatever was read past it."""
    data = buffered
    while b"\n" not in data:
        try:
            chunk = sock.recv(4096)
        except (socket.timeout, OSError):
            break
        if not chunk:
            break
        data += chunk
    line, sep, rest = data.partition(b"\n")
    if not sep and not line:
        return "", b""
    return line.decode("utf-8", "replace").strip(), rest


def _drain_lines(sock, rest):
    """Whatever the server writes before it closes, as `(lines, closed)`."""
    data = rest
    closed = False
    try:
        sock.settimeout(2.0)
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                closed = True
                break
            data += chunk
    except (socket.timeout, OSError):
        pass
    text = data.decode("utf-8", "replace")
    return [line.strip() for line in text.splitlines() if line.strip()], closed


# ---------------------------------------------------------------------------
# UDP on 3001


def flowrequest(server, port=3001, message="resourcerequest: xcatd",
                bind=None, timeout=10.0, source_port=None, expected=1):
    """Send a flow-control request and collect the datagrams that answer it.

    Two answers are expected in turn and they are not the same: an immediate
    acknowledgement, and a grant once a slot frees. A scenario that only wants
    the first sets `replies = 1`.
    """
    replies = []
    error = ""
    try:
        sock = _udp(bind, source_port)
        sock.settimeout(timeout)
        sock.sendto(message.encode(), (server, int(port)))
        deadline = time.time() + float(timeout)
        while len(replies) < int(expected) and time.time() < deadline:
            try:
                data, _ = sock.recvfrom(4096)
            except socket.timeout:
                break
            except OSError as exc:
                error = str(exc)
                break
            replies.append(data.decode("utf-8", "replace").strip())
        sock.close()
    except OSError as exc:
        error = str(exc)

    fields = {
        "replies": replies,
        "count": len(replies),
        "ok": bool(replies),
        "error": error,
    }
    return Reply(kind="flowrequest", fields=fields, ok=fields["ok"],
                 error=error, sent=message)


def findme(server, payload, port=3001, encoding="gzip", bind=None,
           source_port=301, timeout=10.0, callback_listen=3001,
           callback_wait=5.0):
    """Send a discovery packet and record the callback it provokes.

    The interesting assertions here are negative -- an unprivileged source
    port, or an address on no managed network, must draw no callback at all --
    so the listener is stood up before the datagram leaves and the absence of
    a connection is the recorded result.
    """
    listener = None
    error = ""
    if callback_listen:
        listener = Listener(bind, int(callback_listen)).start()
        if listener.error:
            error = listener.error

    body = payload.encode() if isinstance(payload, str) else payload
    if encoding == "gzip":
        body = gzip.compress(body)

    try:
        sock = _udp(bind, source_port)
        sock.settimeout(timeout)
        sock.sendto(body, (server, int(port)))
        sock.close()
    except OSError as exc:
        error = error or str(exc)

    callbacks = []
    if listener is not None:
        listener.wait(callback_wait)
        callbacks = listener.stop()

    fields = {
        "callbacks": callbacks,
        "count": len(callbacks),
        "ok": bool(callbacks),
        "error": error,
    }
    return Reply(kind="findme", fields=fields, ok=fields["ok"], error=error,
                 sent="findme %d bytes from port %s (%s)"
                      % (len(body), source_port, encoding), raw=body)


def discovery_packet(elements=()):
    """The XML a genesis image sends, without the signature it cannot forge.

    `xcatd` gates a findme on three things -- the gzip or `<xcat` prefix, a
    source port below 1000, and an address on a managed network -- and none of
    them is the signature, so an unsigned packet reaches the same code path and
    provokes the same callback. What a discovery *plugin* then does with an
    unsigned packet is a different question, and no scenario here asserts it.
    """
    lines = ["<xcatrequest>", "<command>findme</command>"]
    for name, value in elements:
        lines.append("<%s>%s</%s>" % (name, value, name))
    lines.append("</xcatrequest>")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# sockets


def _tcp(server, port, bind, timeout, source_port=None):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    if bind or source_port:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((bind or "", int(source_port or 0)))
    sock.connect((server, int(port)))
    return sock


def _udp(bind, source_port=None):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if bind or source_port:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((bind or "", int(source_port or 0)))
    return sock
