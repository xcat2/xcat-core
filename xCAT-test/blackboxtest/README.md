# blackboxtest

A client-side test of the services a booting node uses. It asks a management
node the questions the node asks -- a DHCP DISCOVER, a DNS lookup, a TFTP
fetch, an HTTP GET, a request to `xcatd` -- and asserts on the answers.

It never reads the xCAT database and never runs an xCAT command. Every value it
expects comes from the command line, from the fixture that set the cluster up.
A suite that asked xCAT what to expect would pass on a cluster that cannot
boot a node.

Requires Python 3.6 or later. DHCP steps also need Scapy (`python3-scapy`)
and root; DNS, TFTP and HTTP steps need `dig`, `tftp` and `curl`. There is
no install step: it runs from a checkout.

## Commands

```
blackboxtest run      [options] CONF [CONF...]   # execute scenarios
blackboxtest validate CONF [CONF...]             # check offline
blackboxtest list     CONF [CONF...]             # show what a file does
```

`validate` and `list` need no root, no network, no Scapy and no client
program. They catch a misspelt reply field, a reference to a step that has not
run, and a DHCP step that is not legal in the client state it runs in.

| Option to `run` | Meaning |
| --- | --- |
| `-i`, `--interface IFACE` | interface the DHCP steps send from; overrides the file |
| `-b`, `--bind ADDR` | source address of every step that sets no `bind` |
| `--set KEY=VALUE` | define `%(KEY)s` (repeatable) |
| `-s`, `--scenario NAME` | run only this scenario (repeatable) |
| `--timeout SECS`, `--retries N` | per attempt, and attempts per step |
| `-v` | print each reply to stderr |

| Exit code | Meaning |
| --- | --- |
| 0 | every assertion held |
| 1 | at least one assertion failed |
| 2 | the configuration or the command line is wrong |
| 3 | this host cannot run the test: no Scapy, no root, no `dig`, ... |

3 is checked before any output. A host that tested nothing must not report a
green run.

## Configuration

INI, read by `configparser`. A `[step]` belongs to the `[scenario]` above it,
and steps run in file order. Unknown keys are an error.

```ini
[vars]
domain = cluster

[defaults]
server = %(server)s
bind   = %(client)s

[scenario boot-file-fetchable]
description = The loader DHCP names can be fetched under that name
interface   = eth1

[step discover]
type            = discover
client_arch     = 0x000b
request_options = 1, 3, 6, 54, 66, 67
assert =
    yiaddr   in %(net)s
    bootfile present

[step loader]
type = tftp
path = $discover.bootfile
assert =
    size > 0
```

`[defaults]` supplies a key to each step whose type takes it. So one
`server =` serves the DNS, TFTP and HTTP steps, and the DHCP step in the same
file is not made illegal by it.

### Variables and references

`%(name)s` is configparser's `BasicInterpolation`, resolved when the file is
loaded, from `[vars]` and `--set`; `--set` wins. It is resolved before `-s`
selects anything, so a file needs all its variables. `validate` prints them.

`$step.field` is a field of an earlier reply, resolved at run time. The step
is any earlier step in the scenario, or a name the DHCP client binds: `$offer`,
`$ack`, `$lease`, `$reply`. A list field is indexed as `data.0`, a mapping read
as `header.content-type`, and the bare name of a list gives its first element.

```ini
[step kernelpath]
type    = extract
from    = $config.text
pattern = ^\s*linux\s+/?(\S+)

[step kernel]
type = tftp
path = $kernelpath.value
```

Nothing there says what the kernel is called. The config is fetched, the name
read out of it, and that name fetched.

### Assertions

One per line under `assert`, as `target op value`.

| Op | Holds when |
| --- | --- |
| `==` `!=` | equal as addresses, then as numbers, then as text. A list equals a value when any element does |
| `in` `not-in` | inside a CIDR (`10.0.0.0/24`), a range (`10.0.0.200-10.0.0.250`) or a comma list |
| `present` `absent` | the field carries a value. An empty list and a zeroed BOOTP field are absent |
| `matches` `contains` `starts-with` `ends-with` | text; `matches` is a multi-line regex |
| `<` `<=` `>` `>=` | numeric |

`!=` and `not-in` hold against an absent target: a reply naming no boot file
has not named the wrong one. Every other operator fails on an absent target.

`attempt` and, on a DHCP step, `offers` (the number of servers that answered)
come from the runner. `$step.field` may be a target.

### Expectations

`expect` states what the transport must do, and it is a test point of its own:

| Family | `expect` | Default |
| --- | --- | --- |
| DHCP | `offer` `ack` `nak` `bootreply` `any` `none` | the reply the client state waits for |
| service | `ok` `fail` `any` | `ok` |
| `extract`, `noop` | `ok` `fail` `any` | `any` |

A step that waited for an answer and got none fails with no assertion. A DHCP
step with `expect = none` fails when anything answers.

## Step types

| `type` | Driven by | Keys | Reply fields |
| --- | --- | --- | --- |
| `discover` `request` `renew` `rebind` `release` `bootrequest` | raw socket | see below | see below |
| `dns` | `dig` | `server` `port` `name` `rrtype` `recursion` `bind` | `status` `rcode` `flags` `count` `data` `type` `ttl` `name` `question` `answers` `authority` `server` |
| `tftp` | `tftp` | `server` `port` `path` `mode` | `ok` `size` `sha256` `text` `error` `path` `server` |
| `http` | `curl` | `server` `port` `path` `url` `method` `header` `insecure` `bind` | `status` `size` `sha256` `text` `url` `header` `content_type` `error` `ok` |
| `xcatreq` | TLS socket | `server` `port` `command` `element` `raw` `source_port` `callback_port` `callback_listen` `callback_reply` `callback_wait` `cert` `key` `bind` | `destiny` `kernel` `initrd` `kcmdline` `imgserver` `name` `error` `serverdone` `elements` `data` `content` `desc` `text` `handshake` `ok` `callback_seen` `callback_data` |
| `monitor` | TCP socket | `server` `port` `send` `source_port` `bind` | `greeting` `lines` `text` `ok` `closed` `error` |
| `flowrequest` | UDP socket | `server` `port` `message` `replies` `source_port` `bind` | `replies` `count` `ok` `error` |
| `findme` | UDP socket | `server` `port` `payload` `encoding` `source_port` `callback_listen` `callback_wait` `bind` | `callbacks` `count` `ok` `error` |
| `extract` | -- | `from` `pattern` `group` | `value` `groups` `matched` `count` |
| `noop` | -- | -- | -- |

Every step also takes `type`, `expect`, `timeout`, `retries` and `assert`.

`bind` is the client's own address. `xcatd` names a client by the reverse
lookup of the address its connection came from, so the source address is
under test and is never left to the kernel.

### DHCP steps

The DHCP client is an RFC 2131 state machine on a raw Layer 2 socket, so it
works on an interface with no address -- the state of a provisioning NIC when a
machine boots. One client runs per scenario:

| State | Legal steps |
| --- | --- |
| INIT | `discover`, `bootrequest`, `request` with `requested_address` (INIT-REBOOT) |
| SELECTING | `request` |
| BOUND | `renew` (unicast), `rebind`, `release` |

A step that waited for an answer and got none leaves the state as it was. A NAK
returns the client to INIT.

Keys: `mac`, `ciaddr`, `giaddr`, `client_id` (`auto` by default, `none`, or
hex), `user_class` with `user_class_form` = `raw` or `rfc3004`, and one key
per option: `requested_address` (50), `server_id` (54), `lease_time` (51),
`hostname` (12), `fqdn` (81), `max_message_size` (57), `vendor_class` (60),
`client_arch` (93), `client_ndi` (94), `client_uuid` (97), `vendor_specific`
(43, hex), `ipxe_options` (175, hex), `request_options` (55).

`fqdn = S:node01` sets the flags before the colon when every character there is
a flag letter (`S` `O` `E` `N`); `E` sends the name in wire format.

Reply fields: the BOOTP header (`msgtype` `xid` `yiaddr` `siaddr` `ciaddr`
`giaddr` `chaddr` `file` `sname` `secs` `flags` `src_ip` `src_mac`), the
aliases `address` `mac` `next_server`, any option as `54`, `option:54`,
`opt54` or `server_id`, and three fields a client reads from two places:

- `bootfile`: option 67 when sent, else the `file` header. ISC fills the
  header, dnsmasq answers in option 67, and firmware reads either.
- `dns_name`: option 81 when sent, else option 12. Kea answers option 81 in
  option 81; ISC with `ignore client-updates` sends option 12 only.
- `fqdn_flags`: option 81's flags as letters, absent without option 81.

Assert on those rather than on `file` or one option, unless the one place is
the point. `msgtype` is `BOOTREPLY` for a reply with no option 53.

The client MAC is a random locally administered address, so the host's own
network stack never takes a reply as its own. The tool answers ARP only for an
address it was granted, so a unicast renewal arrives without the address ever
being configured on the host.

## Shipped scenarios

`conf/dhcp/` asserts the DHCP clauses (`S-nn`), `conf/prov/` the provision
chain clauses (`P-nn`). Each scenario's description names its clause.

| File | What it asserts |
| --- | --- |
| `dhcp/discover-offer.conf` | one DISCOVER draws exactly one OFFER |
| `dhcp/full-lease.conf` | DISCOVER/OFFER/REQUEST/ACK yields the offered address |
| `dhcp/static-vs-dynamic.conf` | a reserved MAC gets its address, another MAC a pool address |
| `dhcp/pxe-arch-matrix.conf` | each client architecture (option 93) is offered its own loader |
| `dhcp/ipxe-userclass.conf` | stage 1 and stage 2 differ, in both user-class encodings |
| `dhcp/renew-rebind.conf` | a lease survives RENEW and REBIND |
| `dhcp/provision-vs-discovery.conf` | a known machine gets its reservation and loader; an unknown one a pool address |
| `dhcp/discovery-bootfile.conf` | an unknown machine is handed a loader too |
| `dhcp/netboot-methods.conf` | a node gets the loader its netboot method names, its own name, and a `*NOIP*` port no answer |
| `dhcp/hierarchy-dhcpserver.conf` | a delegated pool ignores unknown MACs and still serves known ones |
| `dhcp/discovery-adoption.conf` | a machine discovered from the pool gets its own address once defined |
| `dhcp/nak-foreign-address.conf` | a REQUEST for an address off this network is refused |
| `dhcp/next-server-source.conf` | next-server follows each node's attributes |
| `dhcp/multi-mac-node.conf` | a node with two ports gets a different address on each |
| `dhcp/iscsi-root-path.conf` | a diskless node is told its iSCSI target |
| `dhcp/loader-absent.conf` | an architecture whose loader is missing gets an address and no boot file |
| `dhcp/http-port.conf` | an HTTP boot URL names the port the web server listens on |
| `dhcp/dynamic-range-cidr.conf` | a dynamic range written as a CIDR serves from it |
| `dhcp/node-removal.conf` | a withdrawn node stops being offered its old address |
| `dhcp/bootp-client.conf` | a BOOTP client is still given an address |
| `dhcp/localboot.conf` | an installed node is offered its address and no boot script |
| `prov/dns.conf`, `prov/dns-removal.conf` | forward, reverse, alias, forwarded and removed names |
| `prov/tftp-{grub2,pxelinux,xnba,petitboot}.conf` | each netboot method's loader, config, kernel and initrd, by the name the firmware asks for |
| `prov/discovery-artefacts.conf` | the configs and genesis images an unknown machine fetches |
| `prov/http.conf` | the install tree, the TFTP tree over HTTP, and the port the node was told |
| `prov/flowcontrol.conf`, `prov/findme.conf` | UDP 3001: flow control and discovery callbacks |
| `prov/xcatd-{destiny,postscript,credentials,policy}.conf` | TLS 3001: identity by reverse lookup, the node's script, credentials, policy |
| `prov/monitor.conf` | TCP 3002, the install monitor |
| `prov/ordering.conf` | an unreachable master, a missing PTR, a replaced state |

A node has one netboot method, so the four `tftp-*.conf` files are
alternatives: the fixture runs the one the node is defined with.

Not covered: the `getcredentials` form that asks xcatd to sign a CSR, and an
operating system install. The install tree is fabricated; the scenarios fetch
what a node fetches and assert what it contains.

## What it does to the host

Nothing. It opens sockets, starts `dig`, `curl` and `tftp`, and writes only
temporary files it removes. It never runs `ip`, `dhclient` or `nmcli`, and
never configures a leased address.

The addresses it binds to must exist before a run. A `findme` from a port
below 1024 and the `getcredentials` callback listener on port 300 need root.
Setting that up and putting it back is the fixtures' job:
`xCAT-test/autotest/testcase/blackboxtest/{dhcp,prov}fixture.sh`.

## Failure output

TAP version 13, which `prove` and xcattest read:

```
not ok 3 - pxe-bios-x86/bios-discover: bootfile == pxelinux.0
  ---
  expected: 'pxelinux.0'
  received: 'xcat/xnba.kpxe'
  reply: OFFER from 10.99.0.1 (9a:3d:4f:3d:59:1b) xid=0xc45c6376 yiaddr=10.99.0.175 siaddr=10.99.0.1 file=''
  options: {1 (subnet_mask)=255.255.255.0, 54 (server_id)=10.99.0.1, 67 (bootfile_name)=xcat/xnba.kpxe}
  sent: DISCOVER mac=02:da:16:d0:80:dd xid=0xc45c6376 client_arch=0x0000
  attempt: 1 of 3
  ...
```

`sent` is what went out, so a service step can be re-run by hand with a copy
and a paste.

## Running under xcattest

`xCAT-test/autotest/testcase/blackboxtest/`:

| File | Label | What runs |
| --- | --- | --- |
| `cases0` | `ci_test` | the unit tests and `validate`; a checkout is enough |
| `prov_cases` | `prov_wire` | the `conf/prov/` scenarios, through `provfixture.sh` |
| `dhcp_cases` | `dhcp_wire` | the `conf/dhcp/` scenarios, through `dhcpfixture.sh` |

Each wire case sets its fixture up, runs, and tears it down from a `trap`.
The wire cases carry no `ci_test`: while one runs, the management node is
reconfigured. `github_action_xcat_test.pl` runs `prov_wire` after the
`ci_test` set, then `dhcp_wire` once per DHCP backend installed:

```bash
FIX=/opt/xcat/share/xcat/tools/autotest/testcase/blackboxtest/dhcpfixture.sh
for backend in $($FIX backends); do
    $FIX backend-setup $backend
    xcattest -t $(xcattest -s "dhcp_wire" -l | paste -sd,)
    $FIX backend-teardown $backend
done
```

A case that cannot run says so and passes. Read a pass as coverage only when
the log shows the `ok` lines.

## Tests

```bash
cd xCAT-test/blackboxtest
python3 -m unittest discover -s tests
python3 src/blackboxtest validate conf/*/*.conf
```

No root, no network. Tests that need Scapy, `dig` or `tftp` skip without them.
`tests/test_boundaries.py` enforces the rules the results depend on: only
`proc` starts a process, only `dhcp` imports Scapy, and no module names an
xCAT command or a DHCP server implementation.

## Layout

```
src/blackboxtest          entry point
src/blackboxtest_lib/
    cli.py                run, validate, list
    config.py             .conf -> Scenario, Step
    steps.py              what each step type takes and returns
    validate.py           the offline checks
    runner.py             runs scenarios; the service and local steps
    dhcp.py               the DHCP client (the only Scapy user)
    dhcpopts.py           DHCP option coding, the decoded reply
    dnsc.py httpc.py tftpc.py   dig, curl, tftp
    xcatc.py              xcatd: TLS 3001, UDP 3001, TCP 3002, callbacks
    proc.py               the only module that starts a process
    assertions.py         the assertion language
    subst.py              $step.field
    model.py              Scenario, Step, Assertion, Reply
    report.py             TAP
    netutil.py            addresses, MACs, the names loaders ask for
    errors.py             exceptions and exit codes
conf/dhcp/, conf/prov/    shipped scenarios
tests/                    unit tests, standard library only
```
