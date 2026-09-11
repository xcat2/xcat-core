# provtest

A wire-level test of the xCAT provision chain. It asks the management node the
questions a booting node asks -- a DNS lookup, a TFTP fetch, an HTTP GET, an
XML request to `xcatd` -- and asserts on the answers that come back.

Scenarios are `.conf` files, not Perl. The tool knows nothing about xCAT's
database and never runs an xCAT command to decide what to expect: everything it
expects arrives on the command line, from the fixture that set the cluster up.

The specification the scenarios implement is `specs/provision-chain.md` in the
internal repository; every scenario carries the `@P-nn` tag of the clause it
covers, so a failure names the clause without the document being at hand.

## Why

`ci_test` proves that xCAT's commands accept their arguments and write the rows
they are supposed to write. It does not prove that a node can boot. Between
`nodeset osimage` returning zero and a node reaching its installer there are six
daemons, four file trees and two authentication models, and every one of them
fails silently: a `grub.cfg` named with one wrong hex digit produces no error
anywhere, just a loader prompt nobody is watching.

The gap this fills is the one between "the database says the node will boot" and
"a client on the provisioning network can fetch what it needs to boot". Only a
client can answer the second question, so provtest is a client.

`dhcptest` covers DHCP the same way, and provtest deliberately does not: the two
suites meet at one assertion, `@P-70`, where the boot file name DHCP handed out
is fetched over TFTP under exactly that name.

## Commands

    provtest run      [options] CONF [CONF...]   # execute scenarios
    provtest validate CONF [CONF...]             # check offline
    provtest list     CONF [CONF...]             # show what a file does

`validate` and `list` open no socket, spawn no client and need no root, so they
run in a checkout with no management node anywhere near. They are the check that
catches a misspelt reply field or a reference to a step that has not run yet.

    provtest run --set server=10.99.1.1 --set client=10.99.1.11 \
        --set node=provtestcn --set domain=provtest.cluster \
        --set nodeip=10.99.1.11 --set revname=11.1.99.10 \
        --set alias=provtestcn-alias --set forwarded=example.com \
        --set missing=nosuchnode --set master=10.99.1.1 --set net=10.99.1.0 \
        conf/dns.conf

Options to `run`:

| Option | Meaning |
| --- | --- |
| `-b`, `--bind ADDR` | source address for every step that does not set its own |
| `--timeout SECS` | per-attempt timeout, overriding the files |
| `--retries N` | attempts per step, overriding the files |
| `--format tap\|pretty\|json` | output format (default `tap`) |
| `-s`, `--scenario NAME` | run only this scenario; repeatable |
| `-v`, `--verbose` | print each reply as it arrives |

Exit codes, which are dhcptest's:

| Code | Meaning |
| --- | --- |
| 0 | every assertion held |
| 1 | at least one assertion failed |
| 2 | the configuration or the command line is wrong |
| 3 | this host cannot run the test at all |

3 is not 0 on purpose. A host with no `dig` reports that it tested nothing,
because a pass that proves nothing is worse than a failure that says why.

## Configuration

INI syntax, read by `configparser`. Three kinds of section:

    [vars]
    domain = provtest.cluster

    [defaults]
    server  = %(server)s
    bind    = %(client)s
    timeout = 8

    [scenario node-reverse]
    description = The node's address resolves to its fully qualified name

    [step ptr]
    type   = dns
    name   = %(revname)s.in-addr.arpa
    rrtype = PTR
    assert =
        status == NOERROR
        data   contains %(node)s.%(domain)s

`[vars]` and `--set` feed `%(name)s` substitution; `--set` wins. `[defaults]`
supplies any key a later step does not set for itself. A `[step]` belongs to the
`[scenario]` above it, and steps run in file order.

Section names are unique per file, which `configparser` enforces and not merely
per scenario -- so two scenarios in one file may not both have a `[step config]`.

## Variables and references

Two substitutions, resolved at different times.

`%(name)s` is resolved when the file is loaded, from `[vars]` and `--set`. It is
resolved before `-s` selects anything, so every variable a file mentions must be
supplied even for scenarios that will not run. Each file's header comment lists
the `--set` values it needs, and `validate` prints the union for a set of files.

`$step.field` is resolved at run time, from the reply of an earlier step in the
same scenario. This is what makes a scenario a chain rather than a list:

    [step config]
    type = tftp
    path = boot/grub2/grub.cfg-%(hexip)s

    [step kernelpath]
    type    = extract
    from    = $config.text
    pattern = ^\s*linux(?:efi|16)?\s+/?(?:tftpboot/)?(\S+)

    [step kernel]
    type = tftp
    path = $kernelpath.value

Nothing in that scenario says what the kernel is called. The config is fetched,
the name is read out of it, and *that* name is fetched -- which is the difference
between testing xCAT and comparing xCAT's output to a copy of xCAT's output.

A reference to a step that has not run yet is a configuration error, reported by
`validate`.

## Assertions

One per line, under a single multi-line `assert` key, as `target op value`:

    assert =
        status  == 200
        size    > 0
        sha256  == $overtftp.sha256
        text    contains destiny=install
        error   absent

| Operator | Holds when |
| --- | --- |
| `==`, `!=` | the field equals, or does not equal, the value |
| `<`, `<=`, `>`, `>=` | numeric comparison |
| `in`, `not-in` | the field is, or is not, one of a space-separated list |
| `contains`, `starts-with`, `ends-with` | substring tests |
| `matches` | the field matches the regular expression |
| `present`, `absent` | the field is, or is not, non-empty; no value |

`not-in` is membership, not negative containment. "This text must not contain
X" is written as an `extract` step asserting `matched == no`.

A field that is a list is addressed by index (`lines.0`), a field that is a
mapping by key (`header.content-type`, `elements.destiny`).

Each step also carries `expect`, which says what the transport itself must do:

| `expect` | Meaning |
| --- | --- |
| `ok` (default) | the request must have got an answer |
| `fail` | the request must not have got one |
| `any` | either; only the assertions decide |

The default is `ok` so that a step whose server never answered fails even with
no assertions at all. Silence is not a pass.

## Step keys

Every step takes `type`, `expect`, `timeout`, `retries`, `assert` and `bind`.

`bind` is the client's own address, and it is the most important key in the
file. `xcatd` names a client by the reverse lookup of the address the connection
arrived from, so which end of the veth pair a request leaves by decides who the
server thinks is asking. It is never left to the kernel's source selection.

| `type` | Driven by | Keys | Reply fields |
| --- | --- | --- | --- |
| `dns` | `dig` | `server`, `port`, `name`, `rrtype`, `recursion` | `status`, `flags`, `count`, `data`, `type`, `ttl`, `name`, `question`, `answers`, `authority` |
| `tftp` | `tftp` | `server`, `port`, `path`, `mode` | `ok`, `size`, `sha256`, `text`, `error`, `path` |
| `http` | `curl` | `server`, `port`, `path`, `url`, `method`, `header`, `insecure` | `status`, `size`, `sha256`, `text`, `url`, `header`, `content_type`, `error`, `ok` |
| `xcatreq` | socket | `server`, `port`, `command`, `element`, `raw`, `source_port`, `callback_port`, `callback_listen`, `callback_reply`, `callback_wait`, `cert`, `key` | `destiny`, `kernel`, `initrd`, `kcmdline`, `imgserver`, `name`, `error`, `serverdone`, `elements`, `data`, `text`, `handshake`, `ok`, `callback_seen`, `callback_data` |
| `monitor` | socket | `server`, `port`, `send`, `source_port` | `greeting`, `lines`, `text`, `ok`, `closed`, `error` |
| `flowrequest` | socket | `server`, `port`, `message`, `replies`, `source_port` | `replies`, `count`, `ok`, `error` |
| `findme` | socket | `server`, `port`, `payload`, `encoding`, `source_port`, `callback_listen`, `callback_wait` | `callbacks`, `count`, `ok`, `error` |
| `extract` | -- | `from`, `pattern`, `group` | `value`, `groups`, `matched`, `count` |
| `sleep` | -- | `duration` | -- |
| `noop` | -- | -- | -- |

`dig`, `curl` and `tftp` are the clients an operator would reach for, which
removes "the test's own protocol parser was wrong" from every result they
produce. The xCAT stages use sockets instead, because binding a source address
and holding a callback listener open while a request is in flight is not
something those programs will do.

## Shipped scenarios

| File | Stage | Scenarios | Clauses |
| --- | --- | --- | --- |
| `dns.conf` | DNS | `node-forward`, `node-reverse`, `node-alias`, `forwarded-name`, `local-nxdomain`, `master-resolves` | P-01..P-07 |
| `dns-removal.conf` | DNS | `removed-node` | P-08 |
| `tftp-grub2.conf` | TFTP | `grub2-binary`, `grub2-node-config`, `grub2-config-by-mac`, `grub2-kernel-and-initrd`, `tftp-escape`, `dhcp-named-file-must-exist` | P-09, P-11..P-17, P-24, P-70, P-71 |
| `tftp-pxelinux.conf` | TFTP | `pxelinux-node-config`, `pxelinux-boot-from-disk` | P-18..P-20 |
| `tftp-xnba.conf` | TFTP | `xnba-script`, `xnba-kernel` | P-21, P-22 |
| `tftp-petitboot.conf` | TFTP | `petitboot-config` | P-23 |
| `discovery-artefacts.conf` | TFTP | `grub2-discovery-config`, `pxelinux-discovery-config`, `xnba-discovery-config`, `genesis-images-pxelinux`, `genesis-images-grub2` | P-25..P-31 |
| `http.conf` | HTTP | `install-tree`, `tftp-tree-over-http`, `urls-the-node-was-given`, `boot-images-over-http`, `outside-the-aliases`, `postscripts-listing`, `port-the-node-was-told`, `default-port-the-node-was-told` | P-32..P-39 |
| `flowcontrol.conf` | UDP 3001 | `acknowledged`, `granted` | P-40, P-41 |
| `findme.conf` | UDP 3001 | `findme-callbacks`, `findme-plain-xml`, `findme-unprivileged-port`, `findme-foreign-address` | P-42..P-46, P-48, P-73 |
| `xcatd-destiny.conf` | TLS 3001 | `certless-handshake`, `unknown-client`, `known-node`, `chain-advances` | P-49..P-56 |
| `xcatd-postscript.conf` | TLS 3001, TCP 3002 | `postscript-terminated`, `postscript-unknown-client`, `postscript-both-transports` | P-57, P-58, P-67 |
| `xcatd-credentials.conf` | TLS 3001 | `credentials-granted`, `credentials-refused`, `credentials-unprivileged-callback`, `credentials-nameless` | P-61..P-63, P-76 |
| `xcatd-policy.conf` | TLS 3001 | `command-outside-policy`, `malformed-request` | P-59, P-60 |
| `monitor.conf` | TCP 3002 | `monitor-accepts-status`, `monitor-unknown-client`, `monitor-unknown-verb`, `monitor-is-not-tls` | P-64..P-66, P-68, P-69 |
| `ordering.conf` | whole chain | `unreachable-master`, `missing-ptr`, `state-replaced` | P-72, P-74, P-75 |

A node has exactly one netboot method, so the four `tftp-*.conf` files are
alternatives, not a set: running all four against one node fails three of them.
The fixture selects the one the node is defined with.

### What is deliberately not covered

`getcredentials` has a second form: genesis asks for `x509cert` and encloses a
certificate signing request, and `xcatd` signs it and returns the certificate.
None of these scenarios exercise it. A CSR is not something a wire test can
fabricate meaningfully — a signature over a key that belongs to nothing proves
only that OpenSSL works — and the part of the exchange that decides whether a
node gets a credential at all is the callback on port 300, which is the same for
both forms and is asserted three ways here. A cluster where signing itself is
broken fails at `credentials-granted`; one where the x509 path alone is broken
is not caught, and that is the gap.

Nothing here installs an operating system either. The install tree the nodes
point at is fabricated, not produced by `copycds`: the scenarios fetch the files
a node fetches and assert what they contain, and the media that would have to be
staged to do more is measured in gigabytes.

## What it does to the host

`provtest` itself changes nothing. It opens sockets and spawns `dig`, `curl` and
`tftp`; it writes no file outside a temporary directory it removes, touches no
xCAT table and restarts no daemon.

What it does need is an address to bind to. Every step binds a source address,
because the address is the credential; that address has to exist on the host
before the run. Two things also need privilege: a `findme` from a source port
below 1024, which `xcatd` requires before it will dispatch the request, and the
callback listener on port 300 that `getcredentials` connects back to.

Setting those addresses up, defining the node, and putting them all back
afterwards is the fixture's job, not the tool's:
`xCAT-test/autotest/testcase/provtest/provfixture.sh`.

## Failure output

TAP 13, so `prove` and the xcattest harness both read it:

    TAP version 13
    1..6
    ok 1 - node-forward
    not ok 2 - node-reverse
      ---
      scenario: node-reverse
      source: conf/dns.conf
      step: ptr
      sent: dig @10.99.1.1 -b 10.99.1.11 PTR 11.1.99.10.in-addr.arpa
      assertion: data contains provtestcn.provtest.cluster
      expected: provtestcn.provtest.cluster
      actual: (no answer records)
      status: NXDOMAIN
      ...

The command that was sent is printed as it was sent, so the first thing an
operator does after a failure -- run it again by hand -- is a copy and a paste.

## Running under xcattest

The cases live in `xCAT-test/autotest/testcase/provtest/cases0`.

Two labels, because they cost different things:

| Label | What runs | Needs |
| --- | --- | --- |
| `mn_only,ci_test,prov` | `validate`, `list`, and the unit tests | a checkout |
| `mn_only,prov,prov_wire` | the scenarios above | a management node and root |

    xcattest -t ci_test          # includes the offline half
    xcattest -t prov_wire        # the wire half

Each wire case sets its fixture up, runs one stage, and tears it down from a
`trap` so an interrupted run does not leave a veth pair and half a zone file
behind.

In CI, `github_action_xcat_test.pl` runs the offline cases with the rest of
`ci_test`, then `prov_wire`, then `dhcp_wire` -- provision chain before DHCP,
because a DHCP failure on a cluster whose TFTP tree is empty is the less
interesting of the two findings.

## Tests

    python3 -m unittest discover -s tests -v

Standard library only, no network, no root. They cover the config parser, the
assertion language, substitution, the offline machine, and the decoding of
captured `dig`, `curl` and `tftp` output.

One of them, `test_boundaries.py`, is a test about the code rather than about
xCAT: it asserts that `proc.py` is the only module that starts a process, and
that no module opens a database or runs an xCAT command. That rule is the reason
the results mean anything -- a suite that asked xCAT what to expect would pass
on a cluster that could not boot a single node.

## Layout

    provtest/
      README.md              this file
      src/provtest           entry point; runs from a checkout, no install
      src/provtest_lib/
        cli.py               argument parsing and the three subcommands
        config.py            INI parsing, %(name)s substitution
        model.py             Scenario, Step, Assertion, Reply
        machine.py           what each step type accepts and returns
        assertions.py        the assertion mini-language
        subst.py             $step.field resolution
        proc.py              the only module that spawns a process
        dnsc.py              dig
        httpc.py             curl
        tftpc.py             tftp
        xcatc.py             the xCAT client: 3001 TLS, 3001 UDP, 3002 plain
        netutil.py           address and hex-name helpers
        runner.py            executes scenarios, retries, collects results
        report.py            TAP, pretty and JSON output
        errors.py            exceptions and exit codes
      conf/                  the scenarios
      tests/                 unit tests
