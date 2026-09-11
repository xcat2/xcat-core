# What xCAT is supposed to answer while a node provisions

A specification of the traffic a machine actually produces between power-on and
a running installer, and of what xCAT must send back, written as scenarios so
it can be checked rather than argued about.

Every scenario is stated from the point of view of the client on the wire: what
it asked for, and what came back. That is deliberate. `provtest` never reads the
xCAT database and never runs an xCAT command, so a scenario phrased in terms of
tables and plugins cannot be tested by it. Where a behaviour is genuinely not
observable from the wire -- a row that changed, a plugin that won -- it is
marked **[config]** and belongs to the Perl unit tests under `xCAT-test/unit/`
instead.

Each scenario cites the source it was read from, so a scenario that stops
matching xCAT is a bug in one of the two and it is clear where to look.

Every scenario carries a review number, `@P-nn`, in the Gherkin tag above it.
The numbers are stable and are the ones in VersatusHPC/xcat-internal#176: the
wire scenarios in `conf/`, the appendices here and any issue raised against this
document all cite them, so "P-42 was wrong" names one behaviour rather than a
paragraph nobody can find twice. They do not collide with `dhcptest`'s `@S-nn`.

**DHCP is not specified here.** It is stage 2 of the chain and it has its own
document, `xCAT-test/dhcptest/spec.md`, because it is the one stage that needs a
raw L2 client and that has two backends to reconcile. This document starts where
a DHCP acknowledgement leaves off and ends where a real installer would take
over.

Terms used throughout:

| Term | Meaning |
| --- | --- |
| **the node** | a node in the xCAT database, with an address on a managed network and a PTR for it |
| **the client** | the forged machine on the wire: an address, and whatever it chooses to send |
| **a known client** | a client whose address reverse-resolves to a name in the node list |
| **an unknown client** | any other client: no PTR, or a PTR naming nothing defined |
| **HEXIP** | the node's IPv4 address as eight uppercase hex digits, e.g. `0A63000B` |
| **HEXNET** | the same encoding applied to a network address |
| **the master** | the address the node is told to talk xCAT to: `site.master`, or `noderes.xcatmaster` where it is set |
| **destiny** | `chain.currstate`: what the node is to do next -- `install`, `netboot`, `boot`, `discover`, `shell`, `runcmd` |
| **the chain** | `chain.currchain`: the states queued after this one |

---

## Why forging a client is enough

This is the load-bearing fact for the whole suite, so it is stated with
citations rather than assumed. Everything a booting node sends can be produced
by a script on a veth peer, with no VM, no genesis image and no client
certificate:

- **TLS 3001 accepts a client with no certificate.** `SSL_verify_mode => 1` is
  set without `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` (`xCAT-server/sbin/xcatd`
  around the SSL listener setup), so a certless client completes the handshake
  and simply leaves the peer name undefined.
- **Identity otherwise comes from the reverse DNS of the peer address**, with
  `-eth\d*`, `-myri\d*` and `-ib\d*` suffixes stripped. A client that owns an
  address with a matching PTR *is* that node as far as xcatd is concerned.
- **The default policy grants the node-boot command set to certless clients.**
  `xcatconfig` installs policy rows for `getdestiny`, `nextdestiny`,
  `getpostscript`, `getcredentials`, `lsxcatd`, `syncfiles`, `litefile`,
  `litetree`, `getadapter`, `getbmcconfig` and `remoteimmsetup`, none of them
  carrying a `name` field -- i.e. none of them requiring a client certificate.
- **TCP 3002 has no TLS at all** and rests entirely on the reverse lookup.
- **findme is not signed for authentication.** `xcatd` gates it on the command
  being `findme`, the UDP source port being below 1000, and the source address
  being on a network xCAT manages (`xcatd:708-711`). Nothing verifies a
  signature. See *Appendix B, row 3*.

The one exception is `getcredentials`, which additionally requires the client to
answer a callback on its own TCP port 300.

---

## Feature: DNS answers for a node and for the cluster

Source: `xCAT-server/lib/xcat/plugins/ddns.pm` (`"$name IN A $ip"` at 1758,
`"$_ IN CNAME $name"` at 1758ff, `"$rname IN PTR $name"` at 1766, reverse zone
name built at 1663-1669, `site.domain` required at 369-377, forwarders at
672-676)

```gherkin
@P-01
Scenario: The node's own name resolves forward
  Given a node defined with an address on a managed network
  And makedns has been run
  When a resolver queries the node's short name in the cluster domain
  Then an A record is returned
  And it holds the address the node was defined with

@P-02
Scenario: The node's address resolves in reverse
  Given a node defined with an address on a managed network
  When a resolver queries the IN-ADDR.ARPA name for that address
  Then a PTR record is returned
  And it holds the node's fully qualified name

@P-03
Scenario: Reverse resolution is what xcatd will use to name the client
  Given a PTR exists for the node's address
  When the cluster domain is stripped from the name it returns
  Then the result is the node's name
  # Not a DNS scenario at heart: this is the identity xcatd will act on, so a
  # PTR that resolves to something else is an authentication bug, not a
  # cosmetic one. P-74 asserts the consequence.

@P-04
Scenario: Each configured alias resolves to the node
  Given a node with one or more aliases
  When a resolver queries an alias
  Then a CNAME to the node's fully qualified name is returned

@P-05
Scenario: A name outside the cluster domain is forwarded
  Given forwarders are configured
  When a resolver queries a name in no local zone
  Then the query is answered from a forwarder, not refused
  # Skipped where the fixture's network has no route to a forwarder: an
  # unreachable forwarder is the operator's problem, not xCAT's.

@P-06
Scenario: A name inside the cluster domain that has no record is refused locally
  When a resolver queries an undefined short name in the cluster domain
  Then NXDOMAIN is returned
  And the answer is authoritative

@P-07
Scenario: The master's name resolves
  When a resolver queries the name the node will be handed as its xCAT master
  Then it resolves to the address on the node's own network
  # The node has one route. A master that resolves to the management node's
  # other address is a name that answers and an address that does not.

@P-08
Scenario: Removing a node removes both directions
  Given a node that resolves forward and in reverse
  When the node is removed and makedns is re-run
  Then neither the A record nor the PTR is returned
```

---

## Feature: TFTP serves what DHCP named

Source: `xCAT-server/lib/xcat/plugins/grub2.pm` (`boot/grub2/grub2.<arch>` at
179 and 194, `grub.cfg-<HEXIP>` and `grub.cfg-01-<mac>` at 379-382),
`pxe.pm` (`pxelinux.cfg/<node>` plus the HEXIP link, in `setstate`),
`xnba.pm:254` (`xcat/xnba/nodes/<node>`), `petitboot.pm:149,196-203`,
`perl-xCAT/xCAT/DHCP/BootPolicy.pm:429,433` (s390x and OPAL conf-file URLs),
`xCAT-server/lib/xcat/plugins/AAsn.pm:1145` (`in.tftpd` is the daemon)

```gherkin
@P-09
Scenario: The architecture loader is present before any node is defined
  Given the tftp root has been populated
  When a client fetches the grub2 binary for the node's architecture
  Then the transfer succeeds and the file is non-empty

@P-10
Scenario: A missing architecture loader is a hard error at nodeset time
  Given the grub2 binary for the node's architecture is absent
  When nodeset is run for the node
  Then nodeset reports an error
  And no per-node configuration file is written              # [config]
  # The wire half of this is P-70: whatever DHCP named must be fetchable.

@P-11
Scenario: The per-node grub2 config is fetchable by hex-IP name
  Given a node set to install and using the grub2 netboot method
  When a client fetches boot/grub2/grub.cfg-<HEXIP>
  Then the transfer succeeds

@P-12
Scenario: The per-node grub2 config is also fetchable by MAC name
  Given the same node
  When a client fetches boot/grub2/grub.cfg-01-<node MAC with dashes>
  Then the transfer succeeds
  And the content is byte-identical to the hex-IP name
  # grub2 tries the MAC form first and the hex-IP form second. Two names, one
  # file: a node whose MAC changed must not get a stale config.

@P-13
Scenario: The grub2 config names a kernel that is itself fetchable
  When a client fetches the per-node grub2 config
  And extracts the kernel path from the linux line
  Then that path is fetchable over the transport the config names

@P-14
Scenario: The grub2 config names an initrd that is itself fetchable
  When a client fetches the per-node grub2 config
  And extracts the initrd path from the initrd line
  Then that path is fetchable over the transport the config names

@P-15
Scenario: The grub2 config carries the node's MAC in BOOTIF
  When a client fetches the per-node grub2 config
  Then the linux line contains BOOTIF set to the node's MAC
  # The installer picks its interface from BOOTIF. A node with two NICs that
  # is given the wrong one installs onto the wrong network.

@P-16
Scenario: The kernel command line carries the xCAT master and port
  When a client fetches the per-node config for a node in a boot state
  Then the kernel command line contains xcatd=<master>:<port>

@P-17
Scenario: The kernel command line carries the destiny the node was set to
  When a client fetches the per-node config
  Then the kernel command line contains destiny=<state>

@P-18
Scenario: A pxelinux node gets a config under its node name
  Given a node whose netboot method is pxe
  When a client fetches pxelinux.cfg/<node name>
  Then the transfer succeeds
  And the content begins with a DEFAULT stanza

@P-19
Scenario: The pxelinux config is reachable by hex-IP as well
  When a client fetches pxelinux.cfg/<HEXIP>
  Then the transfer succeeds
  And the content is identical to the by-name fetch

@P-20
Scenario: A node set to boot from local disk is told to do so
  Given a node set to boot
  When a client fetches its boot config
  Then it directs the client to the local disk
  And it names no kernel
  # The DHCP half of this is S-31: a node that has finished installing must
  # stop being handed a boot file at all. This half asserts the other
  # direction -- that if a config is served, it does not netboot.

@P-21
Scenario: An xnba node gets a gpxe script
  Given a node whose netboot method is xnba
  When a client fetches xcat/xnba/nodes/<node>
  Then the first line is the gpxe shebang

@P-22
Scenario: The xnba script fetches its kernel over HTTP, not TFTP
  When a client fetches the xnba script
  Then it contains an imgfetch whose URL scheme is http
  And the URL host is the address DHCP gave as next-server
  # xnba.pm:339,347

@P-23
Scenario: A petitboot node gets a config hardlinked under its hex IP
  Given a node whose netboot method is petitboot
  When a client fetches <HEXIP> at the tftp root
  Then the transfer succeeds
  And it is byte-identical to petitboot/<node>

@P-24
Scenario: Fetching a path outside the tftp root fails
  When a client fetches a path containing parent-directory components
  Then the transfer is refused
```

---

## Feature: The discovery artefacts are per network, not per node

Source: `xCAT-server/lib/xcat/plugins/mknb.pm` (`xcat/xnba/nets/<net>` at 826,
`pxelinux.cfg/<HEXNET>` and the `p/` and `s390x/` forms at 918,
`boot/grub2/grub.cfg-<HEXNET>` and `set fallback=1` at 1018)

A machine nobody has defined has no node name to look a file up by. Everything
in this section is keyed on the network it booted on, which is the only thing
the server knows about it before discovery.

```gherkin
@P-25
Scenario: A discovery config exists per network, not per node
  Given mknb has been run for the management node architecture
  When a client fetches boot/grub2/grub.cfg-<HEXNET> for the managed network
  Then the transfer succeeds

@P-26
Scenario: The discovery config falls back from HTTP to TFTP
  When a client fetches the grub2 discovery config
  Then it contains two menu entries naming the same kernel
  And the first uses http and the second does not
  And fallback is set to the second

@P-27
Scenario: The discovery kernel command line asks for the discover destiny
  When a client fetches the grub2 discovery config
  Then its kernel command line contains destiny=discover

@P-28
Scenario: The discovery kernel command line names the xCAT master
  When a client fetches the grub2 discovery config
  Then its kernel command line contains xcatd=<master>:<port>

@P-29
Scenario: The pxelinux discovery config is reachable by hex network address
  When a client fetches pxelinux.cfg/<HEXNET>
  Then the transfer succeeds

@P-30
Scenario: The genesis kernel named by the discovery config is fetchable
  When the kernel path is extracted from the discovery config
  Then it is fetchable over TFTP

@P-31
Scenario: The genesis initrd named by the discovery config is fetchable
  When the initrd path is extracted from the discovery config
  Then it is fetchable over TFTP
  # The initrd is tens of megabytes and is the artefact most likely to be
  # half-written by an interrupted mknb. A HEAD is not enough; fetch it.
```

---

## Feature: HTTP serves the install tree and the boot tree

Source: `xCAT/xcat.conf` and `xCAT/xcat.conf.apach24` (`AliasMatch
^/install/(.*)`, `^/tftpboot/(.*)`), `site.httpport` read at
`anaconda.pm:268`, `debian.pm:1236-1239`, `xnba.pm:164`; `grub2.pm:267-268`
(`set root=http,$serverip:$httpport`); autoinst served from
`/install/autoinst/<node>` (`anaconda.pm:1477`, `debian.pm:771,1260`)

```gherkin
@P-32
Scenario: The install tree is served on the configured port
  Given a site http port
  When a client requests a known path under /install on that port
  Then the response status is 200

@P-33
Scenario: The tftp tree is also served over HTTP
  When a client requests a known path under /tftpboot over HTTP
  Then the response status is 200
  And the body is byte-identical to the same file fetched over TFTP
  # Two daemons, one tree. grub2-http and xnba fetch the kernel over HTTP
  # having been told its name by a TFTP fetch, so a divergence here is a node
  # that boots a different kernel than the one it was told about.

@P-34
Scenario: The autoinst file for a node is served
  Given a node set to install
  When a client requests /install/autoinst/<node>
  Then the response status is 200

@P-35
Scenario: The autoinst URL in the kernel command line is the one that is served
  When a client fetches the node's boot config
  And extracts the kickstart or preseed URL from the kernel command line
  Then a request to that exact URL returns 200
  # Not the same assertion as P-34. P-34 says the file is where this document
  # says it is; P-35 says the node was told where it is.

@P-36
Scenario: The repository URL in the kernel command line is served
  When the install repository URL is extracted from the kernel command line
  Then a request for the repository metadata under it returns 200

@P-37
Scenario: A path outside the served aliases is not reachable
  When a client requests a path under neither /install nor /tftpboot
  Then the response status is not 200

@P-38
Scenario: Directory listing is available where postscripts live
  When a client requests the postscripts directory
  Then a listing is returned

@P-39
Scenario: The HTTP port the node is told about is the port that answers
  When the port is extracted from the node's boot config
  Then a request to that port succeeds
```

---

## Feature: Flow control on UDP 3001

Source: `xCAT-server/sbin/xcatd:647-672` (the requestor table and
`resourcerequest: ok`), `xcatd:877-880` (`ackresourcerequest`),
`xCAT-genesis-scripts/usr/bin/udpcat.awk`

A large discovery has hundreds of machines asking for the same slots. The
protocol is two datagrams: an acknowledgement that the request was heard, and
later a grant.

```gherkin
@P-40
Scenario: A flow-control request is acknowledged immediately
  When a client sends "resourcerequest: xcatd" to UDP 3001
  Then an acknowledgement datagram is returned

@P-41
Scenario: A flow-control request is eventually granted
  When a client sends a resource request and waits
  Then a grant datagram is returned within the timeout
  # An acknowledgement without a grant is exactly the failure a node cannot
  # diagnose: it waits forever and reports nothing.
```

---

## Feature: findme, and the callback it produces

Source: `xcatd:708-711` (the command, the source port below 1000, and
`nodeonmynet`), `xcatd:861-876` (the `processing` callback, sent on receipt),
`xCAT-server/lib/xcat/plugins/zzzdiscovery.pm:34-41` (the `processed`
callback), `xCAT-genesis-scripts/usr/bin/dodiscovery`,
`xCAT-genesis-scripts/usr/bin/udpcat.awk` (`/inet/udp/301/`)

Read the gates carefully: they are not where the issue that proposed these
scenarios placed them. The `processing` callback is sent by the UDP listener as
soon as a datagram arrives that starts with the gzip magic or with `<xcat`,
before anything has looked at the source port. The privileged-port and
managed-network checks happen later, in the discovery worker, and what they gate
is the *plugin dispatch* -- and therefore the second callback, not the first.
See *Appendix A, rows 1 and 2*.

```gherkin
@P-42
Scenario: A findme from an unprivileged source port is not dispatched
  Given a client listening on TCP 3001
  When a findme packet is sent from a source port at or above 1000
  Then the processing callback is still received
  And no second callback follows it
  # xcatd:863 sends "processing" from the listener; xcatd:708 drops the
  # request in the worker. The node is told its request is being handled and
  # then never hears again -- which is the bug this scenario pins, not a
  # behaviour to be proud of.

@P-43
Scenario: A findme from an address on no managed network is not dispatched
  Given a client whose address is outside every defined network
  When a findme packet is sent from a privileged source port
  Then no discovery is attempted for it
  # "xcatd: Skipping discovery from <ip> because we either have no discovery
  # plugins or the client address does not match an IP network that xCAT is
  # managing" -- xcatd:721

@P-44
Scenario: A well-formed findme produces a callback on the client's TCP 3001
  Given a client listening on TCP 3001
  When a findme packet is sent from a privileged source port on a managed network
  Then the server connects back to the client on TCP 3001

@P-45
Scenario: The callback says the request is being processed
  When the callback connection is accepted
  Then the first message on it is the processing token

@P-46
Scenario: A findme that no discovery method claims ends in a failure callback
  Given no discovery method is configured to match the client
  When a findme is sent from a privileged source port on a managed network
  Then a second callback carrying the processed token is received
  # zzzdiscovery runs last and exists to say "nobody claimed this". A node
  # that gets no such callback cannot tell failure from slowness.

@P-47
Scenario: A findme declaring a virtual node type is not claimed by switch or sequential discovery
  When a findme carrying a virtual node type is sent
  Then no node is claimed by those methods                   # [config]

@P-48
Scenario: Both the gzipped and the plain XML findme encodings are accepted
  When the same findme payload is sent gzipped, and again as plain XML
  Then both produce a callback
  # xcatd:861 tests for the RFC 1952 magic and xcatd:869 for a "<xcat"
  # prefix. Anything else falls through to the flow-control branch and is
  # silently discarded.
```

---

## Feature: xcatd request and response over TLS 3001

Source: `xCAT-server/lib/xcat/plugins/destiny.pm` (certless and unknown clients
get `discover` at 95 and 100; the install and netboot response elements at
894-1000; `kcmdline` carrying `xcatd=$master:$xcatdport destiny=$state` at
688-698; the image-server fallback chain at 975-987),
`xCAT-genesis-scripts/usr/bin/getdestiny` and `nextdestiny` (the request bytes
and the `<callback_port>300</callback_port>` element)

```gherkin
@P-49
Scenario: A client with no certificate can open the TLS port
  When a client connects to 3001 with no client certificate
  Then the handshake completes
  # If this ever stops being true, every scenario below it is untestable and
  # genesis stops booting. It is asserted first for that reason.

@P-50
Scenario: An unknown client is told to discover itself
  Given a client whose address has no reverse mapping to a defined node
  When it sends a getdestiny request
  Then the response destiny is discover

@P-51
Scenario: A known node is told the destiny it was set to
  Given a node set to install, and a client owning that node's address and PTR
  When it sends getdestiny
  Then the response destiny matches the state nodeset was given

@P-52
Scenario: An install destiny carries a kernel and an initrd
  When a node set to install sends getdestiny
  Then the response contains both a kernel and an initrd element

@P-53
Scenario: An install destiny carries a kernel command line
  When a node set to install sends getdestiny
  Then the response contains a kcmdline element
  And it names the xCAT master and the destiny

@P-54
Scenario: The image server in the response answers
  When a node set to install sends getdestiny
  Then the response names an image server
  And a request to that address on the xCAT port is answered

@P-55
Scenario: The image server falls back through the documented chain
  Given the node has neither a tftpserver nor an xcatmaster attribute
  When it sends getdestiny
  Then the image server in the response is the site master
  # destiny.pm:975-987 tries noderes.tftpserver, then noderes.xcatmaster,
  # then the network's tftpserver, then site.master. Four sources, no error
  # if the wrong one wins -- the node boots and then fetches from an address
  # that does not answer.

@P-56
Scenario: nextdestiny advances the chain
  Given a node with more than one state in its chain
  When the client sends nextdestiny and then getdestiny
  Then the second destiny differs from the first

@P-57
Scenario: getpostscript returns a script terminated by the end marker
  When a known client sends getpostscript
  Then the response body ends with the end-of-script marker
  # The client reads until the marker. A truncated script with no marker is
  # read as a hang, not as an error.

@P-58
Scenario: getpostscript from an unknown client does not return another node's script
  Given a client whose address maps to no node
  When it sends getpostscript
  Then no node-specific script is returned

@P-59
Scenario: A command outside the default policy is refused to a certless client
  When a certless client sends a command that has no policy row granting it
  Then the response is a refusal, not a result

@P-60
Scenario: A malformed request does not kill the listener
  When a client sends bytes that are not well-formed XML
  And a second client then sends a valid getdestiny
  Then the second client is answered

@P-61
Scenario: getcredentials requires the node callback to agree
  Given a client with no listener on the credential callback port
  When it requests credentials
  Then no signed certificate is returned

@P-62
Scenario: getcredentials succeeds when the node callback agrees
  Given a client listening on the credential callback port
  And that listener answers the challenge affirmatively
  When it requests credentials
  Then a signed certificate is returned
  # credentials.pm:611 sends "CREDOKBYYOU?\n" and requires "CREDOKBYME".
  # The callback is what stops an address that merely has a PTR from
  # collecting a signed certificate.

@P-63
Scenario: The credential callback is made to the port the protocol specifies
  When a client requests credentials naming a callback port
  Then the server's callback connection arrives on that port
  # credentials.pm:130-136
```

---

## Feature: The install monitor on TCP 3002

Source: `xcatd:330-400` (the listener, and `site.xcatiport`), `xcatd:404-520`
(the `ready` / `done` framing and the verbs),
`xCAT-server/lib/xcat/plugins/xcatdsklspost:1058-1078`
(`updateflag.awk $MASTER 3002 "installstatus ..."`)

```gherkin
@P-64
Scenario: The install monitor port answers with a readiness token
  When a client connects to TCP 3002
  Then a readiness token is received before any request is sent

@P-65
Scenario: An install status report is accepted and terminated
  When a known client sends an install status line
  Then a completion token is received

@P-66
Scenario: A report from a client that maps to no node is not accepted
  Given a client whose address has no reverse mapping
  When it connects to the monitor port
  Then it is given no readiness token
  # xcatd closes the connection on a peer it cannot name, so the absence of
  # a greeting is the observable. It is not a transport error and provtest
  # records it as a result.

@P-67
Scenario: getpostscript over the monitor port returns the same body as over TLS
  When the same node requests its postscript on 3002 and on 3001
  Then the two bodies are identical

@P-68
Scenario: An unknown verb on the monitor port is rejected without hanging
  When a client sends a verb the service does not implement
  Then the connection is closed or an error returned within the timeout

@P-69
Scenario: The monitor port is plain text, not TLS
  When a client sends a TLS client hello to 3002
  Then no TLS handshake completes
```

---

## Feature: Failing at exactly one place

Each of these is the interesting case: every stage before it is correct, so the
node gets far enough to fail visibly at one identifiable point. They exist
because the whole argument for a wire suite is that these failures are currently
indistinguishable from each other -- all of them look like "the node timed out".

```gherkin
@P-70
Scenario: Correct DHCP with a missing boot file is visible as a TFTP failure
  Given an acknowledgement naming a boot file
  When a client fetches that exact file name over TFTP
  And the file was never written
  Then the fetch returns file-not-found

@P-71
Scenario: A boot file present but naming an absent kernel fails one fetch later
  Given the per-node config fetches successfully
  When the kernel path it names is fetched
  Then the failure is at the kernel fetch, not at the config fetch

@P-72
Scenario: A boot config naming an unreachable master is detectable without booting
  When the master address is extracted from the kernel command line
  And a TLS connection is attempted to it on the xCAT port
  Then a connection failure is distinguishable from a protocol failure

@P-73
Scenario: A node whose findme is unanswered receives only the failure callback
  When a findme is sent and no discovery method claims it
  Then the client's listener records the processing token
  And then the processed token
  And nothing else

@P-74
Scenario: A missing PTR turns a known node into an unknown client
  Given a node set to install whose reverse record has been removed
  When it sends getdestiny
  Then the response destiny is discover, not the state it was set to
  # The whole authentication story in one scenario. A PTR that makedns did
  # not write costs a node its identity and nothing anywhere reports it.

@P-75
Scenario: nodeset for a new state leaves no trace of the previous one
  Given a node set to install, then set to boot
  When the per-node config is fetched
  Then it reflects the second state only
```

---

## Notes on testing this specification

- Scenarios not marked **[config]** are wire-observable and belong in
  `xCAT-test/provtest/conf/`. They need real daemons answering, which
  `xCAT-test/autotest/testcase/provtest/provfixture.sh` builds out of a veth
  pair so a single-node management node can run them.
- Scenarios marked **[config]** assert on database rows, generated files or
  plugin dispatch and belong in `xCAT-test/unit/`, which needs neither root nor
  a network.
- **A `.conf` file must never encode xCAT policy.** The hex-IP file name, the
  kernel path, the master address, the destiny string, the HTTP port: every
  expected value comes in on the command line via `--set`, and the fixture
  supplies it from the node and network it defined. A test that asks xCAT what
  it wrote and then checks that xCAT wrote it proves nothing.
- **No scenario may be conditional on a netboot method.** Where the artefact
  names genuinely differ between grub2, pxelinux, xnba and petitboot, that
  belongs in the `.conf` file as a parameter, not in the scenario as a branch.
  The four TFTP groups are four files, chosen by whoever knows how the node
  under test is configured; running all four against one node will always fail
  three of them.
- The client end of the veth pair carries **the node's** address, not a spare
  one. That is not a convenience: xcatd names a client by the reverse lookup of
  the address it connected from, so the address is the credential and binding to
  it is what makes P-50 and P-51 different scenarios.

### What this specification does not cover on the wire

Stated so that a green run is not read as more than it is:

- **DHCP.** Stage 2 has its own document and its own suite.
- **IPv6.** Every scenario here is IPv4.
- **A real installer installing.** The suite asserts that the artefacts and the
  answers are correct, not that a distribution installs from them. Postscripts
  running, `updatenode` against a live node and console access are all out.
- **Service-node hierarchy.** Every scenario assumes one management node serving
  directly. A service node boots exactly as a compute node does; what differs is
  what it serves afterwards.
- **Which discovery plugin claimed a findme.** Only the callbacks are asserted.
  `switch.pm`, `typemtms.pm`, `seqdiscovery.pm`, `blade.pm` and `hpblade.pm` are
  reached through state changes that belong to the unit suite.

---

## Appendix A: corrections to the proposal these scenarios came from

VersatusHPC/xcat-internal#176 stated seventy-five scenarios from a reading of
the source. Three of them did not survive being read against it again. The
numbers are kept -- an issue that cites P-42 should still find P-42 -- and what
changed is recorded here rather than silently rewritten.

| # | Scenario | As proposed | As specified | Why |
| --- | --- | --- | --- | --- |
| 1 | P-42 | "no callback connection is made to the client" | the processing callback still arrives; no second callback follows | `xcatd:863` sends `processing` from the UDP listener on the gzip magic alone. The source-port test is at `xcatd:708`, in the worker, after the callback has gone out |
| 2 | P-43 | "no callback connection is made" | no discovery is attempted | Same reason. `nodeonmynet` is checked at `xcatd:711`, also after the callback |
| 3 | P-47, and open question 3 | whether an unsigned findme is rejected was "not confirmed" | nothing verifies a signature | `xcatd:706-711` parses the XML and tests the command name, the source port and the network. There is no signature check on the path, so forging findme needs no key |
| 4 | P-66 | "no node's state is claimed to have changed" | no readiness token is given | The proposed Then clause is a database assertion, which this suite may not make. xcatd closes the connection on an unnameable peer, and the missing greeting is the wire-observable form of the same fact |
| 5 | P-72 | "the failure is a connection failure, not a protocol failure" | a connection failure is distinguishable from a protocol failure | The original asserts which failure occurs, on a machine where neither may. What is under test is that the two are told apart |

## Appendix B: what the fixture deviates from, and why

| Decision | The issue proposed | Here | Why |
| --- | --- | --- | --- |
| Network | reuse `dhcptest0`/`dhcptest1`, `10.99.0.0/24`, `dhcptest.cluster` | `provtest0`/`provtest1`, `10.99.1.0/24`, `provtest.cluster` | The two suites run back to back in the same CI job. Sharing constants means a leaked `site.dhcpinterfaces` or an undeleted node from the DHCP run silently changes what the provision run is testing. Adjacent networks cost nothing and cannot collide |
| Client address | the client end carries the node's address | unchanged | This is the credential. See *Notes* above |
| Daemons | stand up `named`, `httpd`, `in.tftpd`, `xcatd` | per stage, each skipped independently | A management node that cannot free port 53 -- `dnsmasq`, `systemd-resolved`, libvirt -- must still be able to run the TFTP, HTTP and xcatd stages. One unusable daemon skips its own scenarios and nothing else |
| Port proof | `ss` before running anything | unchanged, per stage | A suite that passes because nothing was listening is worse than one that fails |

## Appendix C: open questions

Carried from the issue, with what has since been settled.

1. **Can `xcatd` run against a scratch database?** Still open, and still the
   largest unknown. Until it is settled, the 3001 and 3002 scenarios mutate the
   real cluster database, and the fixture saves and restores the node
   definitions and the `site` rows it touches. The suite is labelled
   `prov_wire` and is not part of `ci_test` for this reason.
2. **`getbootparams` and `getinstallpkgs`** do not exist in this tree. No
   scenario depends on them.
3. **The findme signature.** Settled: there is no verification. *Appendix A,
   row 3*.
4. **`nodestat` state transitions.** The mapping from an `installstatus` report
   on 3002 to an observable `nodelist.status` value has not been traced. P-66
   is written conservatively because of it.
5. **`in.tftpd` on a non-standard port.** The fixture takes port 69 and restores
   it, as `dhcpfixture.sh` does with 67. `tftpflags` (`Schema.pm:1303`) may
   offer a cleaner path; it has not been tried.
6. **ONIE and HTTPClient boot URLs.** The HTTP boot paths above are confirmed
   for grub2-http and xnba. ONIE's URL shape is not traced and no scenario
   asserts it.
7. **Callback timing.** P-44 asserts a callback arrives, not how soon.
   `dodiscovery` retries with a 180-second cap, and no bound on the server side
   is confirmed.
