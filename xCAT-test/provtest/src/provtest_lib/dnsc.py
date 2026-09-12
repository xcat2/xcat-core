"""DNS, asked the way an operator asks: `dig`.

A node resolves three things before it can be provisioned -- its own name, the
master's name, and whatever the kickstart refers to -- and xcatd then resolves
the node's address backwards to decide which node it is talking to. All four
are one resolver query, so one step type covers the whole stage.

The query is always sent to a named server. A booting node uses the resolver
DHCP gave it, and the point of the test is that *that* server answers, not that
the host running the test has some resolver that does.
"""

import re

from . import proc
from .model import Reply

HEADER_RE = re.compile(r"->>HEADER<<-\s+opcode:\s*(\w+),\s*status:\s*(\w+),\s*id:\s*(\d+)")
FLAGS_RE = re.compile(r"^;;\s*flags:\s*([^;]*);\s*(.*)$")
COUNT_RE = re.compile(r"(\w+):\s*(\d+)")


def build(server, name, rrtype="A", port=53, bind=None, recursion=True,
          timeout=5.0, tries=1):
    """The `dig` command line for one query."""
    dig = proc.require("dig", "DNS")
    argv = [dig, "@%s" % (server,), name, rrtype.upper()]
    if port and int(port) != 53:
        argv += ["-p", str(int(port))]
    if bind:
        argv += ["-b", str(bind)]
    argv += [
        "+noall", "+comments", "+answer", "+authority",
        "+tries=%d" % (max(1, int(tries)),),
        "+time=%d" % (max(1, int(round(float(timeout)))),),
        "+norecurse" if not recursion else "+recurse",
    ]
    return argv


def query(server, name, rrtype="A", port=53, bind=None, recursion=True,
          timeout=5.0):
    """Run one query and decode what `dig` printed into a `Reply`."""
    argv = build(server, name, rrtype, port, bind, recursion, timeout)
    done = proc.run(argv, timeout=float(timeout) + 5.0)
    reply = decode(done.text, name=name, rrtype=rrtype, server=server)
    reply.sent = done.command()
    reply.raw = done.out
    if done.timed_out:
        reply.ok = False
        reply.error = "dig did not return within the timeout"
    elif done.rc != 0 and not reply.fields.get("status"):
        reply.ok = False
        reply.error = _why(done)
    return reply


def decode(text, name="", rrtype="", server=""):
    """Turn `dig +noall +comments +answer +authority` output into a `Reply`."""
    status = ""
    flags = ""
    counts = {}
    names, ttls, types, data, records = [], [], [], [], []

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(";"):
            match = HEADER_RE.search(stripped)
            if match:
                status = match.group(2)
                continue
            match = FLAGS_RE.match(stripped)
            if match:
                flags = match.group(1).strip()
                counts = dict((key.upper(), int(value))
                              for key, value in COUNT_RE.findall(match.group(2)))
            continue

        parts = stripped.split(None, 4)
        if len(parts) < 5 or parts[2].upper() != "IN":
            continue
        # An authority section shares the record syntax, and SOA records there
        # are how a resolver says "this zone is mine and the name is not in
        # it", so they are kept apart rather than counted as answers.
        if parts[3].upper() == "SOA":
            continue
        names.append(parts[0].rstrip("."))
        ttls.append(int(parts[1]) if parts[1].isdigit() else 0)
        types.append(parts[3].upper())
        data.append(parts[4].strip().rstrip(".") if parts[3].upper() != "TXT"
                    else parts[4].strip())
        records.append(stripped)

    fields = {
        "status": status,
        "rcode": status,
        "flags": flags,
        "count": counts.get("ANSWER", len(data)),
        "authority": counts.get("AUTHORITY", 0),
        "name": names,
        "ttl": ttls,
        "type": types,
        "data": data,
        "answers": records,
        "question": name,
        "server": server,
    }
    ok = status == "NOERROR"
    return Reply(kind="dns", fields=fields, ok=ok,
                 error="" if status else "no answer was received")


def _why(done):
    """The first line `dig` wrote to stderr, or a fallback."""
    for line in (done.errtext + done.text).splitlines():
        if "error" in line.lower() or "could be reached" in line.lower():
            return line.strip().lstrip(";").strip()
    return "dig exited %d" % (done.rc,)
