# dhcptest

A wire-level DHCP client test tool. It builds real DHCP packets, sends them
from a raw Layer 2 socket, decodes what comes back, and asserts on it.

It is agnostic to what is answering. It never reads a server's configuration,
never runs a server's tools, and never looks at an xCAT database — it exchanges
packets and checks fields. Any expectation that differs between servers is
written by whoever writes the `.conf`, never assumed by the tool.

Requires Python 3.6+ and Scapy (`python3-scapy`). Nothing else: no pip, no
`setup.py`. It runs straight from a checkout.

## Why

xCAT's DHCP behaviour was tested from two directions, neither of which touched
the wire: unit tests asserting on *generated config text*, and integration
tests feeding that config to a real `dhcpd`/`kea-dhcp4` to check it parses.
Both stop at "the server accepted our config". Nothing verified that a client
sending option 93 = `0x000b` actually gets `boot/grub2/grub2.aarch64` back.

The one existing wire tool, `xCAT-probe/subcmds/detect_dhcpd`, cannot fill that
gap: it sends no option 60, 77 or 93, so it never reaches any architecture
branch; it parses replies by regexing `tcpdump -vvvvvv` output; and it binds a
UDP socket to an existing local address, so it cannot run on an interface that
has no address yet — the normal state of a provisioning NIC.

## Commands

```
dhcptest run      [-i IFACE] [options] CONF [CONF...]   # execute scenarios
dhcptest validate CONF [CONF...]                        # check offline
dhcptest list     CONF [CONF...]                        # show what a file does
dhcptest discover -i IFACE [--arch N] [--vendor-class S] [--user-class S]
```

`validate` and `list` need no root, no network and no scapy, so they run in a
checkout-only CI job. `run` and `discover` need root, for the raw socket.

| Flag | Meaning |
| --- | --- |
| `-i, --interface` | interface to bind to; overrides the `.conf` |
| `--set KEY=VALUE` | define `%(KEY)s` (repeatable) |
| `-s, --scenario NAME` | run only this scenario (repeatable) |
| `--mac` | `random` (default), `iface`, or an explicit address |
| `--timeout` / `--retries` | per attempt, and attempts per step |
| `--format` | `tap` (default), `pretty`, `json` |
| `--pcap FILE` | write every frame sent and received |
| `-v` / `-vv` | progress / per-packet trace |

Exit codes: `0` everything passed, `1` at least one assertion failed, `2`
configuration or usage error, `3` the host cannot run the test at all (no
scapy, not root). A host that cannot test anything **fails** rather than
reporting a run of skipped tests, because a green result that proves nothing is
worse than a red one.

## Configuration

INI, read with `configparser`. Sections: an optional `[vars]` and `[defaults]`,
then `[scenario NAME]` followed by the `[step NAME]` sections belonging to it.
Unknown keys are a hard error rather than a silent skip.

```ini
[defaults]
interface = eth1
timeout   = 2
retries   = 3

[scenario full-lease]
description = DISCOVER/OFFER/REQUEST/ACK yields the offered address

[step discover]
type            = discover
request_options = 1, 3, 6, 51, 54
expect          = offer
assert =
    msgtype == OFFER
    yiaddr  in %(net)s

[step request]
type              = request
requested_address = $offer.address
server_id         = $offer.server_id
expect            = ack
assert =
    msgtype   == ACK
    yiaddr    == $offer.address
    option:51 present
```

### Variables and references

Two substitutions, resolved at two different times.

`%(name)s` is **configparser's own `BasicInterpolation`**, not something this
tool implements. Values come from the `[vars]` section and from
`--set name=value`, with `--set` winning, and both are folded into
configparser's defaults so a variable resolves from any section. An undefined
name is an error *before* any packet is sent, naming the flag that fixes it:

    conf/discover-offer.conf [step discover]: %(net)s is not defined;
    pass --set net=<value>

`$step.field` is a field of an earlier **reply**, so it cannot exist until the
run reaches that step — which is exactly why it is not configparser's job. The
step name is any earlier step, or one of the bindings the tool maintains:
`$offer`, `$ack`, `$nak`, `$lease`, `$reply`.

The two never collide: `BasicInterpolation` gives `$` no meaning of its own, so
`$offer.address` reaches the runtime untouched and no escaping is needed.
(`ExtendedInterpolation` would have claimed `${...}` and then choked on a bare
`$`, which is why it is not used.)

`validate` and `list` load a file **raw**, leaving `%(name)s` in place, and
report which variables a run would have to supply.

Fields: `address` (`yiaddr`), `bootfile`, `next_server` (`siaddr`), `mac`,
`server_id`, `lease_time`, `subnet_mask`, `router`, any header field by name,
and `optN` for any option by number.

### Assertions

One per line under a single multi-line `assert` key, as `target op value`.
`assert_all` applies to every OFFER collected, not only the selected one.

| Target | Source |
| --- | --- |
| `msgtype` | option 53, by name: `OFFER`, `ACK`, `NAK` |
| `yiaddr` `siaddr` `ciaddr` `giaddr` `file` `sname` `xid` `chaddr` | BOOTP header |
| `bootfile` | option 67 if the server sent one, else the `file` header |
| `option:<num>` / `option:<name>` / bare `<num>` | a DHCP option |
| `offers` | how many *servers* answered |
| `$step.field` | a field of an earlier reply |

| Op | Meaning |
| --- | --- |
| `==` `!=` | type-aware: addresses as addresses, numbers as numbers |
| `in` `not-in` | subnet membership (`10.0.0.0/24`) or a comma list |
| `present` `absent` | option presence, no value |
| `matches` `contains` `starts-with` `ends-with` | text |
| `<` `<=` `>` `>=` | numeric |

Assert on `bootfile`, not on `file`, unless the header itself is the point.
Servers genuinely differ — ISC dhcpd fills the BOOTP header, dnsmasq answers in
option 67 once the client has asked for it — and firmware reads whichever
arrived. `bootfile` is what a client would actually boot.

`offers` counts servers, not packets. A retransmit reuses its xid, as RFC 2131
requires, so the same server can be heard twice; a second answer from a server
already heard from does not inflate the count.

### Step keys

Control: `type`, `expect`, `mac`, `xid`, `timeout`, `retries`,
`broadcast_flag`, `min_size`, `collect_extra`, `select`, `arp_respond`,
`assert`, `assert_all`, `duration`, `dest_mac`.

Message: `request_options` (55), `vendor_class` (60), `user_class` (77) with
`user_class_form` = `raw` or `rfc3004`, `client_arch` (93), `client_ndi` (94),
`client_uuid` (97), `client_id` (61), `hostname` (12), `max_message_size` (57),
`vendor_specific` (43, hex), `ipxe_options` (175, hex), `requested_address`
(50), `server_id` (54), `lease_time` (51), `ciaddr`, `giaddr`, and
`option:<n>` for anything else.

Step types: `discover`, `request`, `renew`, `rebind`, `release`, `decline`,
`inform`, `noop`, `sleep`. `expect` is `offer`, `ack`, `nak`, `any`, or `none`
— with `none`, silence is the passing result.

## Shipped scenarios

| File | What it asserts | Needs |
| --- | --- | --- |
| `discover-offer.conf` | one DISCOVER draws exactly one OFFER | `net`, `server` |
| `full-lease.conf` | DISCOVER/OFFER/REQUEST/ACK yields the offered address | `net` |
| `static-vs-dynamic.conf` | a reserved MAC gets its address; an unreserved one gets a pool address | `reserved_mac`, `reserved_ip`, `unreserved_mac`, `pool` |
| `no-reply.conf` | on a reservations-only subnet, an unreserved MAC is ignored | `unreserved_mac` |
| `pxe-arch-matrix.conf` | each client architecture (option 93) is offered its own loader | `tftp`, `*_loader` |
| `ipxe-userclass.conf` | stage 1 and stage 2 differ, in both user-class encodings | `user_class`, `stage1_loader` |
| `renew-rebind.conf` | a lease survives RENEW and REBIND | `net` |

`static-vs-dynamic.conf` and `no-reply.conf` describe **mutually exclusive**
server configurations. What an unreserved MAC gets is policy, not protocol: a
subnet with a dynamic pool answers it, a reservations-only subnet ignores it.
Run whichever matches the network under test; running both against the same
network will always fail one.

Every expected address and filename comes from `--set`, so no shipped file
states anything about how a server was configured, or by what.

```bash
dhcptest run -i eth1 \
    --set tftp=10.0.0.1 \
    --set bios_loader=xcat/xnba.kpxe \
    --set aarch64_loader=boot/grub2/grub2.aarch64 \
    conf/pxe-arch-matrix.conf
```

## What it does to the host

Nothing. The default MAC is a freshly generated locally-administered address
(`02:…`), so NetworkManager and any running `dhclient` never see the replies as
theirs, and the kernel drops the unicasts because neither the destination MAC
nor the IP is local. No address, route or resolver entry is ever created, and
the leased address is never configured. The tool never calls `ip`, `dhclient`
or `nmcli`; reading `/sys/class/net/<if>/address` for `--mac iface` is the only
host state it touches.

Renewals are unicast from the leased address, and a server may ARP for that
address before replying. Rather than configure the address, the tool answers
ARP itself — only for addresses this session was actually granted, only on its
own synthetic MAC, only on this interface.

## Failure output

TAP version 13, which `prove` consumes directly:

```
not ok 3 - pxe-bios-x86/bios-discover: bootfile == %(bios_loader)s
  ---
  expected: 'WRONG.0'
  received: 'pxelinux.0'
  reply: OFFER from 10.99.0.1 (9a:3d:4f:3d:59:1b) xid=0xc45c6376 yiaddr=10.99.0.175 siaddr=10.99.0.1
  options: {1 (subnet_mask)=255.255.255.0, 3 (router)=['10.99.0.1'], 51 (lease_time)=120, 54 (server_id)=10.99.0.1, 67 (bootfile_name)=pxelinux.0}
  sent: DISCOVER mac=02:da:16:d0:80:dd client_arch=0x0000 vendor_class=PXEClient:Arch:00000:UNDI:002001
  attempt: 1 of 3
  ...
```

A reply of the wrong type is reported as that type rather than as a timeout: a
NAK where an ACK was wanted says so.

## Tests

```bash
cd xCAT-test/dhcptest
python3 -m unittest discover -s tests          # no root, no network
python3 src/dhcptest validate conf/*.conf
```

The suite needs no privileges and no server. `tests/test_wire.py` builds real
frames and reads them back, and skips where scapy is absent.
`tests/test_boundaries.py` enforces the two rules this tool is built on: only
`runner.py` may import scapy, and no module may shell out, open a database, or
name a server implementation or xCAT in code.

## Layout

```
src/dhcptest              entry point
src/dhcptest_lib/
    cli.py                argparse, subcommands, exit codes
    config.py             configparser -> Scenario/Step, strict validation
    model.py              Scenario, Step, Assertion, Reply
    subst.py              $step.field, resolved at run time
    assertions.py         the assertion mini-language
    options.py            DHCP option table, raw-byte encode/decode
    machine.py            RFC 2131 client FSM, offline scenario validation
    runner.py             packets, socket, retransmit  (the only scapy user)
    report.py             TAP / pretty / json
    netutil.py            addresses, /sys/class/net
conf/                     shipped scenarios
tests/                    stdlib unittest
```

Options are encoded and decoded from raw bytes rather than through scapy's
option-name table, so a scapy release that renames an option cannot change what
a `.conf` means.
