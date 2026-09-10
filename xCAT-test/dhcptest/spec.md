# What xCAT's DHCP server is supposed to do

A specification of the behaviour a machine booting on an xCAT-provisioned
network actually observes, written as scenarios so it can be checked rather
than argued about.

Every scenario is stated from the point of view of the client on the wire: what
it sent, and what came back. That is deliberate. `dhcptest` never reads the
xCAT database and never runs an xCAT command, so a scenario phrased in terms of
tables and plugins cannot be tested by it. Where a behaviour is genuinely not
observable from the wire -- a file's contents, a daemon's command line -- it is
marked **[config]** and belongs to the Perl unit tests under `xCAT-test/unit/`
instead.

Each scenario cites the source it was read from, so a scenario that stops
matching xCAT is a bug in one of the two and it is clear where to look.

Every scenario carries a review number, `@S-nn`, in the Gherkin tag above it.
The numbers are stable: the appendix, the wire scenarios in `conf/` and the
issues raised against this document all cite them, so "S-27 fails on Kea" names
one behaviour rather than a paragraph nobody can find twice.

**No scenario in this document is conditional on the DHCP backend.** The
backend is chosen for the operator by the management node's distribution, so a
Then clause that holds on ISC and not on Kea describes a machine that boots on
RHEL 9 and hangs on RHEL 10. Where the two implementations disagreed, one
answer was chosen; *Appendix A* records each choice, its reason, and which side
has to move.

Terms used throughout:

| Term | Meaning |
| --- | --- |
| **known node** | a node in the xCAT database with a MAC in the `mac` table |
| **unknown machine** | any other MAC: never defined, or defined without a MAC |
| **pool** | `networks.dynamicrange` for the subnet |
| **reservation** | the fixed address a known node's MAC is bound to |
| **loader** | the boot program named in the BOOTP `file` header or option 67 |
| **next-server** | the BOOTP `siaddr` header: where the loader is fetched from |
| **backend** | `site.dhcpbackend`: `isc`, `kea`, or `auto` |

---

## Feature: An address for every machine on a provisioning network

Source: `xCAT-server/lib/xcat/plugins/dhcp.pm` (`addnode`, `kea_reservations_for_node`),
`perl-xCAT/xCAT/DHCP/Range.pm`

```gherkin
@S-01
Scenario: A known node is given the address it was defined with
  Given a node defined with a MAC and an IP outside the dynamic range
  And makedhcp has been run for that node
  When the node sends a DHCPDISCOVER from that MAC
  Then it is offered exactly that IP
  And a DHCPREQUEST for that IP is acknowledged with the same IP

@S-02
Scenario: The same node comes back to the same address
  Given a node that has already been offered its reserved address
  When it discovers again after a reboot
  Then it is offered the same address again
  # A node's name-to-address mapping is what the rest of the deployment is
  # built on: /etc/hosts, DNS, the installer's kickstart URL.

@S-03
Scenario: An unknown machine is given an address out of the pool
  Given a subnet with a dynamic range
  When a MAC with no reservation sends a DHCPDISCOVER
  Then it is offered an address inside the dynamic range
  And that address is not any node's reserved address

@S-04
Scenario: An unknown machine is ignored where there is no pool
  Given a subnet with no dynamic range
  When a MAC with no reservation sends a DHCPDISCOVER
  Then no reply arrives
  # makedhcp warns "No dynamic range specified for <net>. If hardware
  # discovery is being used, a dynamic range is required." -- dhcp.pm:4494

@S-05
Scenario: A dynamic range may be written as a pair or as a CIDR
  Given networks.dynamicrange is "10.0.0.200-10.0.0.250"
  Or networks.dynamicrange is "10.0.0.192/26"
  When an unknown MAC discovers
  Then the offered address falls inside the range either way
  # Range.pm parses both; several ranges may be given separated by ";"

@S-06
Scenario: A node whose IP falls inside the dynamic range is refused
  Given a node whose defined IP is inside networks.dynamicrange
  When makedhcp runs for that node
  Then no reservation is created for it                              # [config]
  And makedhcp reports the collision
  # dhcp.pm:168 -- "Node <n> has <ip> which is inside the DHCP dynamic range."
  # On the wire the node is indistinguishable from an unknown machine.

@S-07
Scenario: A node interface deliberately without an address is denied
  Given a mac table entry whose hostname field is the sentinel *NOIP*
  When that MAC sends a DHCPDISCOVER
  Then it is not offered an address
  And it is not told what to boot
  # An operator marks an interface *NOIP* precisely so nothing boots on it.
  # ISC does it with "deny booting;" on the host statement; whatever mechanism
  # a backend uses, the MAC must not be answered -- a subnet-wide boot class
  # that still matches it defeats the marking. Decision 16.

@S-08
Scenario: A node with several MACs is reachable on any of them
  Given a mac table entry of the form "mac1!host1|mac2!host2"
  When either MAC discovers
  Then each is offered the address of its own hostname
  # dhcp.pm splits on "|" and on "!"; the hostname defaults to the node name.

@S-09
Scenario: An InfiniBand interface is reserved by its full hardware address
  Given a node MAC that is an InfiniBand identity, not a 6-byte Ethernet MAC
  When makedhcp runs for it
  Then the reservation is created with hardware-type 37 and the twin address # [config]
  # dhcp.pm _infiniband_identity_present / _infiniband_twin_update_commands

@S-10
Scenario: A malformed MAC is rejected outright
  Given a mac table entry that is not 6 to 9 colon- or dash-separated octets
  When makedhcp runs for that node
  Then it reports "Invalid mac address <mac> for <node>" and creates nothing  # [config]
```

---

## Feature: Telling a machine what to boot, by client architecture

xCAT signals the loader through **`siaddr` (next-server) and the BOOTP `file`
header**, deliberately not through options 66 and 67
(`dhcp.pm:4446,4610`). Firmware reads the header; a server that answers only in
option 67 will not boot these clients.

Source: `perl-xCAT/xCAT/DHCP/BootPolicy.pm`
(`isc_client_architecture_lines`, `kea_client_classes`,
`kea_httpboot_network_classes`, `kea_s390x_network_classes`)

```gherkin
@S-11
Scenario Outline: The loader follows the client architecture in option 93
  Given a subnet configured by makedhcp -n
  When a client sends a DHCPDISCOVER with option 93 = <arch>
  Then the reply names <loader>
  And siaddr is the tftpserver for that subnet

  Examples:
    | arch   | client                       | loader                    |
    | 0x0000 | x86 BIOS PXE                 | xcat/xnba.kpxe            |
    | 0x0002 | ia64                         | elilo.efi                 |
    | 0x0007 | x86-64 UEFI                  | xcat/xnba.efi             |
    | 0x0009 | x86-64 UEFI, alternate id    | xcat/xnba.efi             |
    | 0x0010 | x86-64 UEFI HTTP boot        | xcat/xnba.efi             |
    | 0x000b | aarch64 UEFI                 | boot/grub2/grub2.aarch64  |
    | 0x000c | ppc64 UEFI                   | /boot/grub2/grub2.ppc     |
    | 0x001b | riscv64 UEFI, TFTP           | boot/grub2/grub2.riscv64  |
  # 0x000e and 0x001f are answered with a conf-file rather than a loader, and
  # 0x001c with a URL; each has its own scenario below. Every row here holds on
  # both backends -- see "Appendix: backend parity decisions".

@S-12
Scenario: A loader is named only when it is there to be fetched
  Given <tftpdir>/xcat/xnba.kpxe does not exist
  When an x86 BIOS client discovers
  Then it is offered an address
  And it is not handed xcat/xnba.kpxe
  And it is not handed some other loader in its place
  # Naming a file the tftp server does not have costs the client a timeout it
  # cannot diagnose; substituting a different loader hides the missing one and
  # boots something nobody asked for. Both backends therefore gate every
  # architecture branch on the loader existing, and neither substitutes.
  # Decision 8/15 in the appendix.

@S-13
Scenario: An HTTP-boot client is given a URL and the tag its firmware demands
  When a client sends option 93 = 0x001c (riscv64 HTTP boot)
  Then the reply names a boot file beginning "http://"
  And that URL ends in the same grub2 image the TFTP path serves
  And the reply carries option 60 = "HTTPClient"
  # UEFI HTTP boot firmware discards a reply that is not tagged HTTPClient.
  # BootPolicy.pm:63-104

@S-14
Scenario: The HTTP boot URL honours a non-default web port
  Given site.httpport is not 80
  When an HTTP-boot client discovers
  Then the URL carries that port
  # BootPolicy.pm:76 -- port 80 is left out of the URL entirely.

@S-15
Scenario: An HTTP boot class is only offered where the image exists
  Given the riscv64 grub2 image is absent from the tftp directory
  When makedhcp -n runs
  Then no HTTP boot class is written for that network              # [config]
  # BootPolicy.pm:85 loader_present. The same rule as the scenario above, at
  # the granularity a class gives: what is not there is not offered.

@S-16
Scenario: A QEMU s390x client is given a conf-file rather than a loader
  When a client sends option 93 = 0x001f
  Then the reply carries option 209 (conf-file) = "s390x/<net>_<prefix>"
  # BootPolicy.pm:106-131 and dhcp.pm:4446. The conf-file is per network.

@S-17
Scenario: An OPAL-v3 client is given a petitboot conf-file URL
  When a client sends option 93 = 0x000e
  Then the reply carries option 209 = "http://<tftp>/tftpboot/pxelinux.cfg/p/<net>_<prefix>"
  # BootPolicy.pm:168

@S-18
Scenario: A client that identifies itself by vendor class alone still boots
  When a client sends vendor class "Etherboot-5.4" and no usable option 93
  Then it is handed xcat/xnba.kpxe
  # BootPolicy.pm:151

@S-19
Scenario: An ONIE switch is offered an installer URL before it is a node
  When a client sends a vendor class beginning "onie_vendor"
  Then the reply carries option 114 (www-server) = the subnet's installer URL
  # A switch announces onie_vendor on its first boot, which is by definition
  # before anyone has defined it as a node, so the offer has to come from the
  # subnet. A node definition refines it -- see the netboot=onie scenario.

@S-20
Scenario: A client that says nothing recognisable falls through to yaboot
  When a client sends no client architecture and no known vendor class
  And no filename has been set by an earlier rule
  Then the reply names "/yaboot"
  # BootPolicy.pm:172. A universal default of "/yaboot" is a poor one, but it
  # is the one xCAT has always had, and changing what an unrecognised client is
  # told to boot is a product decision rather than a parity fix. Decision 7.
```

---

## Feature: Chained network boot -- first stage, then second stage

The loader that firmware runs comes straight back for a second DHCP exchange.
If it were handed the same loader again it would chainload itself forever, so
the second request must be answered differently. The loader announces itself in
the **user class, option 77**.

Source: `BootPolicy.pm:133-257`, `dhcp.pm:1169-1188`

```gherkin
@S-21
Scenario: Firmware with no user class gets the loader binary
  When a client with no option 77 discovers
  Then it is handed a loader binary, not a script URL

@S-22
Scenario: The loader announcing itself gets a script instead
  Given the first stage loader announces user class "xNBA"
  When it discovers with option 93 = 0x0000
  Then it is handed "http://<next-server>/tftpboot/xcat/xnba/nets/<net>_<prefix>"
  And the reply is broadcast rather than unicast
  # always-broadcast on -- BootPolicy.pm:143. The loader has no address yet.

@S-23
Scenario: A UEFI second stage gets the UEFI script
  Given the loader announces user class "xNBA"
  When it discovers with option 93 = 0x0007 or 0x0009
  Then it is handed the same URL with ".uefi" appended
  # BootPolicy.pm:145-148

@S-24
Scenario Outline: The user class is recognised however the client encodes it
  Given the client announces user class "xNBA" encoded as <encoding>
  When it discovers
  Then it is recognised as a second stage and handed the script URL

  Examples:
    | encoding                                  |
    | a bare string, as most clients send it    |
    | RFC 3004 length-prefixed, as the RFC says |
  # Kea accepts both: kea_xnba_user_class_test tests option[77].text, the raw
  # hex, and the length-prefixed substring. ISC accepts both through
  # isc_xnba_user_class_test, which compares the last four bytes:
  # `suffix(option user-class-identifier, 4) = "xNBA"` is true of the bare
  # string and of "\x04xNBA" alike. It has to be one expression rather than an
  # alternation -- dhcpd's grammar has no parenthesised grouping, so `if (a or
  # b) and c {` is a parse error and the daemon will not start.

@S-25
Scenario: A known node's second stage is addressed to that node
  Given a node whose netboot method is xnba
  And that node announces user class "xNBA"
  When it discovers
  Then it is handed "http://<next-server>/tftpboot/xcat/xnba/nodes/<node>"
  And not the per-network script
  # dhcp.pm:1183, BootPolicy.pm:178-212. Two machines chainloading at the same
  # moment must not run the same script.

@S-26
Scenario: A node's first stage is unaffected by its second stage rule
  Given the same node
  When it discovers with no user class
  Then it is handed xcat/xnba.kpxe
```

---

## Feature: The boot file a known node is given follows its netboot method

Source: `dhcp.pm:1169-1232` (ISC), `kea_boot_for_node` (Kea)

```gherkin
@S-27
Scenario Outline: netboot decides the loader for a defined node
  Given a node defined with netboot=<method>
  When that node's MAC discovers
  Then the reply names <loader>

  Examples:
    | method    | loader                                                |
    | xnba      | xcat/xnba.kpxe, or xcat/xnba.efi for x86-64 UEFI      |
    | pxe       | pxelinux.0                                            |
    | grub2     | /boot/grub2/grub2-<node>                              |
    | grub2-*   | /boot/grub2/grub2-<node>                              |
    | yaboot    | /yb/node/yaboot-<node>                                |
    | nimol     | /vios/nodes/<node>                                    |
  # The node's own method decides, on either backend. A subnet-wide boot class
  # answering in its place -- because the backend has no branch for that method
  # -- is a bug, not a fallback: the operator set netboot for a reason, and the
  # subnet class knows only the architecture. Decisions 5 and 6.

@S-28
Scenario: A petitboot node is given a conf-file, not a boot file
  Given a node defined with netboot=petitboot
  When it discovers
  Then the reply carries option 209 = "http://<next-server>/tftpboot/petitboot/<node>"
  And no boot file is named
  # petitboot firmware acts on a filename if it sees one, so naming one as well
  # as the conf-file starts a TFTP fetch the operator did not ask for.
  # Decision 12.

@S-29
Scenario: An ONIE switch is given an installer URL keyed on its vendor class
  Given a node defined with netboot=onie and an osimage whose pkgdir exists
  When it discovers announcing a vendor class beginning "onie_vendor"
  Then the reply carries option 114 (www-server) = the installer URL
  # dhcp.pm:1214, the node's own image; the subnet-wide offer above is what an
  # undefined switch gets. Both exist on both backends -- decision 11.

@S-30
Scenario: A ScaleMP client is given the ScaleMP loader
  Given a node defined with netboot=pxe
  When it discovers announcing vendor class "ScaleMP"
  Then the reply names "vsmp/pxelinux.0"
  # dhcp.pm:1194

@S-31
Scenario: A node told to boot from disk is not handed a loader
  Given a node whose chain.currstate is "boot" or "iscsiboot"
  When it discovers
  Then it is offered its address
  And it is not handed an xNBA script
  # dhcp.pm:1171 -- otherwise a booted node would netboot forever.

@S-32
Scenario: A Windows UEFI install defers to the proxyDHCP daemon
  Given a node in a Windows install or winshell state on UEFI firmware
  And proxydhcp is enabled for it
  When it discovers with option 93 = 0x0000, 0x0007 or 0x0009
  Then the reply names no boot file
  And it carries option 60 = "PXEClient"
  # dhcp.pm:1178 -- the tag tells firmware to ask the proxyDHCP daemon on 4011.

@S-33
Scenario: An iSCSI node is given a root path
  Given a node with an iscsi server and target defined
  When it discovers
  Then the reply carries option 17 (root-path) = "iscsi:<server>:6:3260:<lun>:<target>"

@S-34
Scenario: An IBM iSCSI initiator is given the vendor form of the same thing
  Given the same node, with an initiator name defined
  When it discovers announcing vendor class "ISAN"
  Then the reply carries the iSCSI IQN and root path as vendor options, not option 17
  # dhcp.pm:1153-1163 -- ISAN initiators do not read the standard option.

@S-35
Scenario: The node is told its own name
  Given any known node
  When it discovers
  Then the reply carries option 12 (host-name) = the node name
  # Genesis and every installer that takes its hostname from the lease depend
  # on this. It has to be the option on the wire: ISC's `send host-name` is a
  # parameter for the reply's sname/file handling and is not option 12, so a
  # reservation that carries only that satisfies nothing here. Decision 21.
```

---

## Feature: Where the machine fetches its loader from -- hierarchy

A service node serves the racks behind it. Which server a node is sent to is
what makes a hierarchical cluster work, and it is visible in one field.

Source: `next_server_for_node`, which both backends read, and `dhcp.pm:3441`

```gherkin
@S-36
Scenario: next-server follows noderes.tftpserver
  Given a node whose noderes.tftpserver names a service node
  When it discovers
  Then siaddr is that service node's address

@S-37
Scenario: next-server falls back to xcatmaster
  Given a node with no tftpserver but with an xcatmaster
  When it discovers
  Then siaddr is the xcatmaster's address

@S-38
Scenario: next-server otherwise comes from the subnet
  Given a node with neither tftpserver nor xcatmaster
  When it discovers
  Then siaddr is the tftpserver of the subnet it discovered on
  # '${next-server}' is what a node that named no server of its own is
  # given: ISC leaves the subnet statement to answer it, and Kea says
  # nothing in the reservation, which comes to the same thing.

@S-39
Scenario: A node's URLs point at the same server as its next-server
  Given a node sent to a service node
  When it is handed an xNBA script URL or a petitboot conf-file
  Then the host in that URL is the service node, not the management node

@S-40
Scenario: A pool delegated to another server is not served here
  Given networks.dhcpserver names a machine that is not this one
  When makedhcp -n runs on this machine
  Then this machine serves no dynamic range for that subnet
  And an unknown MAC on it draws no reply from this machine
  # dhcp.pm:3441 -- two servers answering one pool would hand out conflicting
  # addresses.

@S-41
Scenario: Reservations are still served for a delegated subnet
  Given the same subnet, with its pool delegated
  When a known node on it discovers
  Then it is still offered its reserved address by this machine

@S-42
Scenario: A dynamic range without a dhcpserver is an error
  Given a network with a dynamicrange and no dhcpserver in a hierarchy
  When makedhcp runs
  Then it reports the missing dhcpserver                            # [config]
  # dhcp.pm:1593

@S-43
Scenario: A service node serves only the interfaces it was given
  Given a service node with servicenode.dhcpinterfaces set
  When makedhcp -n runs on it
  Then the daemon listens on exactly those interfaces              # [config]
  # dhcp.pm:1965-1978. The ":noboot" suffix is stripped and ignored here; it
  # only matters to mknb.
```

---

## Feature: What else the reply has to carry for a deployment to complete

An address alone does not deploy a node. The installer needs a route, a
resolver and a clock.

Source: `dhcp.pm:4520-4600`

```gherkin
@S-44
Scenario: The reply carries the subnet's gateway
  Given networks.gateway is set for the subnet
  When any client discovers on it
  Then the reply carries option 3 (routers) = that gateway

@S-45
Scenario: A gateway outside its own subnet is rejected
  Given networks.gateway is not inside net/mask
  When makedhcp -n runs
  Then it fails with "Specified gateway <g> is not valid for <net>/<mask>"  # [config]

@S-46
Scenario: The reply carries resolvers and the domain
  Given nameservers are set for the subnet or in site
  When any client discovers
  Then the reply carries option 6 (domain-name-servers)
  And option 15 (domain-name)
  And option 119 (domain-search) listing every known domain
  # dhcp.pm:4563-4589; domain-search is skipped on sles10 and rhel5.

@S-47
Scenario: The reply carries NTP servers when they are configured
  Given ntpservers are set for the subnet or in site
  Then the reply carries option 42 (ntp-servers)

@S-48
Scenario: The reply always carries a log server
  When any client discovers
  Then the reply carries option 7 (log-servers)
  And it is the management node's own address when none was configured
  # dhcp.pm:4560 -- genesis and the installer log to it during discovery.

@S-49
Scenario: The reply carries an MTU where the network defines one
  Given networks.mtu is set
  Then the reply carries option 26 (interface-mtu)
  # A provisioning network on jumbo frames will not complete an install
  # otherwise.

@S-50
Scenario: The lease is as long as site.dhcplease says
  Given site.dhcplease is set
  When a client that is not PXE firmware is acknowledged
  Then option 51 (lease-time) is that value
  And 43200 seconds when site.dhcplease is unset
  # dhcp.pm:4524. "Not PXE firmware" because a client announcing a PXEClient
  # vendor class is answered by S-51 instead, and the two are the same reply
  # field.

@S-51
Scenario: A PXE client gets a short lease
  When a client announcing a vendor class beginning "PXEClient" is acknowledged
  Then option 51 (lease-time) is 600 seconds, not the cluster default
  # dhcp.pm:4939 -- class "pxe" sets max-lease-time 600 so a pool address taken
  # by firmware is returned quickly rather than being held for half a day
  # during a discovery of a few thousand machines. 600 is the number both
  # backends have to land on, and it is asserted on the wire because ISC also
  # sets min-lease-time <dhcplease> on the subnet and the two directives
  # disagree. Decision 22.

@S-52
Scenario: Cumulus switches are told where to find their provisioning script
  When any client discovers
  Then the reply carries option 239 = "http://<tftp>/install/postscripts/cumulusztp"
  # dhcp.pm:4592 -- pushed on every subnet unconditionally.

@S-53
Scenario: The server answers authoritatively
  When a client sends a DHCPREQUEST for an address that is not its own
  Then it receives a DHCPNAK rather than silence
  # dhcp.pm:4521 "authoritative;" -- a node that moved rack must be told to
  # start over rather than waiting out a lease that will never be renewed. The
  # server owns these networks on either backend. Decision 24.

@S-54
Scenario: A BOOTP-only client is served from the dynamic range
  Given a subnet with a dynamic range
  When a client that speaks BOOTP but not DHCP boots on it
  Then it is given an address
  # dhcp.pm:4648 -- "range dynamic-bootp <range>;". Decision 9: the hardware
  # this is for is old enough that it will not be replaced, so dropping it is
  # not on the table; a backend that cannot answer BOOTP has to be made to.
```

---

## Feature: Discovery -- a machine nobody has told the cluster about

Discovery is the case where the server knows nothing about the client and still
has to get it far enough to identify itself.

Source: `dhcp.pm:4481-4498`, `BootPolicy.pm`, xCAT discovery documentation

```gherkin
@S-55
Scenario: An undiscovered machine gets an address and a loader
  Given a subnet with a dynamic range
  When a machine with no reservation PXE boots on it
  Then it is offered a pool address
  And it is told what to boot, chosen by its option 93
  # This is what lets the genesis image run and report the machine's identity.

@S-56
Scenario: An unknown machine is told what to boot from the subnet, not a reservation
  Given a subnet with a dynamic range
  When a MAC with no reservation discovers on it
  Then the boot class that answers is one written on the subnet
  And it is answered whether or not any node holds that MAC
  # Discovery is the case where there is no reservation to read a boot file
  # from, so a backend that only names loaders per host cannot discover
  # anything. kea_client_classes are subnet-wide and the ISC architecture
  # chain is written into the subnet as well (dhcp.pm:4654). Decision 1.

@S-57
Scenario: A machine discovers on the architecture it actually is
  When an aarch64 machine with no reservation PXE boots
  Then it is handed the aarch64 loader, not the x86 one
  # A discovery path that only works for x86 leaves every other architecture
  # undiscoverable.

@S-58
Scenario: A machine adopted during discovery is served without a restart
  Given a machine currently holding a pool address
  When it is defined as a node and makedhcp is run for it
  And it discovers again
  Then it is offered its reserved address
  And no DHCP daemon was restarted in between
  # ISC reservations are injected over OMAPI into dhcpd.leases, not written to
  # dhcpd.conf (dhcp.pm addnode). Discovery depends on this: restarting the
  # daemon mid-discovery drops every machine being discovered.

@S-59
Scenario: A node removed from the cluster stops being served
  Given a node with a reservation
  When makedhcp -d is run for it
  And its MAC discovers again
  Then it is offered a pool address, or none, but not its old reservation
```

---

## Feature: Regenerating and updating the configuration

Source: `dhcp.pm:87` (usage), `xCAT::DHCP::OmapiRunner`, `xCAT::DHCP::OmapiPolicy`

```gherkin
@S-60
Scenario: makedhcp -n rewrites the whole configuration
  When makedhcp -n runs
  Then every network in the networks table has a subnet block          # [config]
  And existing reservations are preserved or re-added

@S-61
Scenario: makedhcp <noderange> adds those nodes only
  When makedhcp is run for a node range
  Then only those nodes' reservations change

@S-62
Scenario: makedhcp -a adds every node with a MAC
  When makedhcp -a runs
  Then every node with a MAC and a resolvable IP has a reservation

@S-63
Scenario: makedhcp -q reports what the server holds
  When makedhcp -q is run for a node
  Then it prints that node's reservation, or reports that there is none

@S-64
Scenario: An external DHCP server is left alone
  Given site.externaldhcpservers is set
  When makedhcp runs
  Then no local configuration file is written                          # [config]
  # dhcp.pm newconfig returns immediately.
```

---

## Feature: The daemon listens where xCAT was told to serve

Wholly **[config]**: the wire cannot show which interfaces a daemon *did not*
bind. Covered by `xCAT-test/unit/dhcp_debian_interfaces.t`.

Source: `dhcp.pm:1980-2030`, `dhcp.pm:2264-2310`, `debian_sysconfig_interface_keys`

```gherkin
@S-65
Scenario: site.dhcpinterfaces names the interfaces to serve
  Given site.dhcpinterfaces = "eth1"
  When makedhcp -n runs
  Then dhcpd is started with eth1 and no other interface

@S-66
Scenario: site.dhcpinterfaces may be scoped per host
  Given site.dhcpinterfaces = "mn|eth1;sn1,sn2|eth2"
  When makedhcp -n runs on each host
  Then each serves only the interfaces named against it

@S-67
Scenario Outline: The Debian default file names the variable the unit reads
  Given isc-dhcp-server version <version>
  When makedhcp -n runs
  Then /etc/default/isc-dhcp-server assigns <variable>
  And dhcpd is launched with the interfaces xCAT serves

  Examples:
    | version           | variable                    |
    | 4.3.3-5ubuntu12   | INTERFACES                  |
    | 4.3.5-3ubuntu7    | INTERFACES                  |
    | 4.4.1-2.1ubuntu5  | INTERFACES                  |
    | 4.4.1-2.3ubuntu2  | INTERFACESv4 / INTERFACESv6 |
    | 4.4.3-P1-4ubuntu2 | INTERFACESv4 / INTERFACESv6 |
  # The split is a Debian packaging change, not an upstream ISC one: 20.04 and
  # 22.04 both ship upstream 4.4.1. An unset variable expands to nothing and
  # leaves dhcpd bound to every interface on the machine.

@S-68
Scenario: A remote interface is not passed to the local daemon
  Given an interface entry marked !remote!
  Then it does not appear on dhcpd's command line
```

---

## Feature: The two backends behave the same on the wire

`xCAT::DHCP::Backend::default_backend` returns `kea` for Ubuntu >= 22.04 and
EL >= 10, `isc` below that; `auto` falls back to `isc` when `kea-dhcp4` is not
installed (`Backend.pm:36-48`). A cluster therefore runs either, and a node must
boot identically on both.

```gherkin
@S-69
Scenario: The same client gets the same answer from either backend
  Given a network and a node defined once
  When the cluster is served by ISC
  And then by Kea, from the same definitions
  Then a client's address, next-server and boot file are the same both times
  And the same options
  # Every scenario in this document is one of "either backend". There is no
  # backend-conditional clause anywhere in it any more, and none may be added:
  # a Then clause that holds on one backend is a bug report, not a
  # specification. Where the two disagreed, the appendix records which answer
  # was chosen and why.
```

---

## Feature: IPv6

Source: `dhcp.pm:568-583`, `addnode6`, `dhcp.pm:4293`

```gherkin
@S-70
Scenario: A node is reserved by DUID rather than by MAC
  Given a node with a vpd.uuid
  When makedhcp runs and the cluster uses IPv6
  Then a DHCPv6 reservation is created against DUID-UUID 00:04:<uuid>
  # dhcp.pm:731-745

@S-71
Scenario: A node without a uuid is skipped
  Given an IPv6 cluster and a node with no vpd.uuid
  When makedhcp runs for it
  Then it warns "Skipping DHCPv6 setup due to missing vpd.uuid information."

@S-72
Scenario: An IPv6 subnet serves a range6
  Given networks.dynamicrange holds an IPv6 CIDR
  Then the DHCPv6 subnet declares range6 with that prefix
  # dhcp.pm:4293; a subnet with no range warns that hosts without a static
  # address will receive none.

@S-73
Scenario: The v6 daemon serves the same interfaces as the v4 one
  Given a Debian management node serving IPv6
  Then INTERFACESv6 names the interfaces xCAT serves            # [config]
```

---

## Notes on testing this specification

- Scenarios not marked **[config]** are wire-observable and belong in
  `xCAT-test/dhcptest/conf/`. They need a real DHCP server answering, which
  `xCAT-test/autotest/testcase/dhcptest/dhcpfixture.sh` builds out of a veth
  pair so a single-node management node can run them.
- Scenarios marked **[config]** assert on generated files or daemon command
  lines and belong in `xCAT-test/unit/dhcp_*.t`, which need neither root nor a
  network.
- A `.conf` file must never encode xCAT policy. Addresses, filenames and
  architectures come in on the command line via `--set`; the fixture supplies
  them from the node and network it defined. That is what keeps the same
  scenarios usable against a server xCAT did not configure.
- Where two behaviours are both legitimate -- an unknown MAC being offered a
  pool address versus being ignored -- they belong in separate `.conf` files,
  chosen by whoever knows how the network under test is configured. Running
  both against one network will always fail one of them.

### What this specification does not cover on the wire

Stated so that a green run is not read as more than it is:

- **DHCPv6.** `dhcptest` speaks IPv4 only: it builds a BOOTP frame on UDP
  68→67. Everything under *Feature: IPv6* is therefore either asserted from the
  generated configuration in `xCAT-test/unit/dhcp_*.t` or not asserted at all.
- **Relay agents.** `giaddr` and option 82 decide which subnet a reply is drawn
  from, and no scenario here sends a relayed request: doing it honestly needs a
  relay agent on a second network, not a forged `giaddr` from the same wire.
  The hierarchy scenarios cover the part that is observable without one -- a
  pool handed to another server stops being offered.
- **Service node deployment as a distinct case.** A service node boots exactly
  as a compute node does; what differs is what it serves afterwards, which is
  `servicenode.dhcpinterfaces` and the delegated pool. Both are covered, as
  `[config]` and as the hierarchy scenarios respectively.
- **The architectures no loader exists for on the machine under test.** The
  fixture skips those by name rather than asserting a filename that was never
  configured; read the log for which ones actually ran.

---

## Appendix A: backend parity decisions

Every row is a place where ISC dhcpd and Kea answered the same frame
differently, or where only one of them answered it at all. They were found by
reading this document against `dhcp.pm` and `BootPolicy.pm` and are enumerated
in VersatusHPC/xcat-internal#175. Rows 26 and 27 are not in that issue: they
were found by the wire cases, which is what the wire cases are for.

The decision column is now the specification: the scenarios above state it
unconditionally, and the wire cases assert it against both backends. "Already
parity" means the source had moved on by the time the finding was checked --
the drift was in the spec text, not in xCAT.

| # | Drift | Decision | Why | Scenario | Has to change |
| --- | --- | --- | --- | --- | --- |
| 1 | Unknown MAC told what to boot: subnet class (Kea) vs per-host block (ISC) | Subnet-wide, both | Discovery has no reservation to read a boot file from; per-host only cannot discover anything | S-55, S-56 | already parity -- the ISC chain is written into the subnet too (dhcp.pm:4654) |
| 2 | 0x000c ppc64: `/boot/grub2/grub2.ppc` (Kea) vs `/yaboot` (ISC) | grub2.ppc | yaboot is not a UEFI loader; ISC's answer is the absence of a branch, not a decision | S-11 | ISC: add the 0x000c branch |
| 3 | 0x0010 UEFI HTTP x86-64: matched (Kea) vs unmatched (ISC) | `xcat/xnba.efi` | 0x0010 is a real client architecture; falling through to `/yaboot` cannot be right for any of them | S-11 | ISC: add the 0x0010 branch |
| 4 | 0x000e OPAL-v3 petitboot conf-file: ISC only | conf-file URL, both | Stated unconditionally; a POWER machine has nowhere to fetch its petitboot config otherwise | S-17 | already parity -- `kea_opal_client_class` |
| 5 | `netboot=xnba`: per-node branch on ISC, none in `kea_boot_for_node` | Per-node, both | The operator set `netboot` deliberately; the subnet class knows only the architecture | S-27 | Kea: add the xnba branch |
| 6 | `netboot=nimol`: `/vios/nodes/<node>` on ISC only | `/vios/nodes/<node>`, both | Same reason; on Kea a NIMOL node is handed the subnet's loader and does not install | S-27 | Kea: add the nimol branch |
| 7 | Unmatched client: `/yaboot` (ISC) vs no boot file (Kea) | `/yaboot`, both | A poor default, but xCAT's long-standing one; changing what an unrecognised client boots is a product decision, not a parity fix | S-20 | Kea: add the fallback |
| 8 | Loader file missing: silence (ISC per-host) vs `pxelinux.0` (Kea) | Name nothing; never substitute | Naming an absent file costs a timeout the client cannot diagnose; substituting boots something nobody asked for | S-12 | Kea: drop the pxelinux.0 fallback. ISC: gate the subnet branches on the loader existing |
| 9 | BOOTP-only client: served by ISC, no Kea counterpart | Served, both | The hardware this is for will not be replaced | S-54 | Kea: serve BOOTP |
| 10 | Vendor class `Etherboot-5.4`: ISC only | `xcat/xnba.kpxe`, both | Stated unconditionally; on Kea such a client then matches nothing at all | S-18 | Kea: add the vendor-class match |
| 11 | `onie_vendor`: per subnet (ISC) vs per node only (Kea) | Both forms, both backends | A switch announces `onie_vendor` on its first boot, before anyone has defined it as a node | S-19, S-29 | Kea: add the subnet class |
| 12 | `netboot=petitboot`: Kea sets `boot-file-name` as well as the conf-file | conf-file only | petitboot acts on a filename if it sees one -- a TFTP fetch that does not happen on ISC | S-28 | Kea: drop `boot-file-name` |
| 13 | 0x001f QEMU s390x: thought to be Kea-only | conf-file `s390x/<net>_<prefix>`, both | Stated unconditionally | S-16 | already parity -- ISC has the 00:1f branch |
| 14 | 0x001c riscv64 HTTP boot: thought to be Kea-only | URL plus option 60 `HTTPClient`, both | Firmware discards a reply that is not tagged | S-13 | already parity -- ISC has the 00:1c branch |
| 15 | HTTP boot class gated on the image existing: Kea only | Gate on both | Same rule as 8, at the granularity a class gives | S-12, S-15 | ISC: gate the branch |
| 16 | `*NOIP*` interface: denied by an ISC statement, no Kea counterpart | Not answered at all, both | The marking exists so nothing boots on that interface; a subnet-wide class that still matches it defeats the marking | S-07 | Kea: drop the packet for that MAC |
| 17 | Boot-from-disk suppression: per-host on ISC, subnet-wide classes on Kea | Suppressed, both | Otherwise an installed node netboots forever instead of booting its disk | S-31 | Kea: suppress per node over the subnet class |
| 18 | Windows UEFI proxyDHCP deferral: ISC only | No boot file plus option 60 `PXEClient`, both | The tag is what hands the client to the proxyDHCP daemon on 4011; a boot file from the subnet class pre-empts it | S-32 | Kea: add the deferral |
| 19 | Vendor class `ScaleMP`: ISC only | `vsmp/pxelinux.0`, both | A different binary; on Kea the reservation's `pxelinux.0` wins and the machine boots the wrong loader | S-30 | Kea: add the vendor-class match |
| 20 | iSCSI root-path and the ISAN vendor form: ISC only | Both forms, both backends | ISAN initiators do not read option 17, so emitting only the standard form does not serve them | S-33, S-34 | Kea: add the ISAN vendor form, including the empty option 43 that carries the space -- Kea sends an encapsulated space only when the option encapsulating it is configured too |
| 21 | option 12 host-name: sent by Kea, `send host-name` on ISC | option 12 = the node name, both | `send host-name` is a parameter for sname/file handling, not option 12; genesis and installers read the option | S-35 | ISC: emit `option host-name`. Kea: write the reservation's hostname fully qualified (trailing dot), or `ddns-qualifying-suffix` is appended to it and the node is told an FQDN. Kea builds option 12 and the DDNS name from that one field, so the suffix still qualifies the dynamic clients that have no reservation |
| 22 | Short PXE lease: ISC class `pxe` against the subnet's `min-lease-time` | option 51 = 600 for a `PXEClient` vendor class | A pool address taken by firmware must come back quickly during a large discovery | S-51 | both: land on 600 and assert it on the wire |
| 23 | Adoption without a daemon restart: an ISC/OMAPI property | No restart, both | Restarting mid-discovery drops every other machine being discovered | S-58 | already asserted on both by `run-adoption` |
| 24 | `authoritative`: an ISC directive, nothing cited for Kea | DHCPNAK rather than silence, both | A node that moved rack must be told to start over | S-53 | Kea: `authoritative` on |
| 25 | The whole common-option block sourced only from the ISC generator | Parity, asserted not assumed | An installer that loses its resolver, route, clock or MTU fails late and obscurely | S-44 to S-52 | neither, so far -- now asserted on the wire on both |
| 26 | `noderes.xcatmaster`: read for every node (Kea) vs only for `petitboot` and `onie` (ISC) | Read for every node, both | An operator sets it per node and deliberately; a hierarchical cluster's compute nodes were being sent to the management node on ISC | S-37 | ISC: honour it whatever the netboot method, and put it in siaddr as well as in the URLs built from it |
| 27 | No server named at all: subnet value (ISC) vs `my_ip_facing` (Kea) | The subnet's value, both | The two agree only while the subnet's tftpserver is this machine; `networks.tftpserver` exists precisely to say otherwise | S-38 | Kea: leave `next-server` out of the reservation and let the subnet answer |

## Appendix B: spec review

What this revision changed, and why. The review numbers are the ones tagged
above.

| Change | Scenarios | Rationale |
| --- | --- | --- |
| Every scenario given a stable review number `@S-nn` | all | So a finding, a `.conf` scenario and a CI failure can name the same behaviour |
| "Known asymmetries between the backends" deleted | was under S-69 | A list of drifts is a bug report; the specification has to say which answer is right. Replaced by Appendix A |
| Backend-conditional discovery scenario rewritten | S-56 | It said the answer was "backend policy". It is not: the operator does not choose the backend |
| Architecture Examples merged into one table, 0x0010 and 0x000c added | S-11 | Two tables, one of them annotated "(Kea only)" per row, is not executable as a scenario outline |
| "told nothing" widened to "and not some other loader in its place" | S-12 | The old Then clause was true on both backends and hid Kea substituting `pxelinux.0` |
| Loader-presence gating stated as one rule for every branch | S-12, S-15 | The two backends gated different things at different granularities |
| Subnet-wide ONIE offer given its own scenario | S-19 | It was only visible as a comment on the per-node one, which hid that Kea has only the per-node form |
| `no boot file is named` justified rather than merely stated | S-28 | It is the clause Kea contradicts, so the reason it exists belongs next to it |
| option 12 stated as the option on the wire | S-35 | `send host-name` satisfied a reading of the old text without sending option 12 |
| PXE lease pinned to 600 seconds | S-51 | "short, not the cluster default" cannot be asserted, and the ISC directives disagree with each other |
| BOOTP and `authoritative` stated for both backends | S-53, S-54 | Both were sourced from the ISC generator alone |
| `*NOIP*`, boot-from-disk and proxyDHCP restated as requirements on the reply | S-07, S-31, S-32 | Each was phrased around the ISC mechanism that implements it, so no Kea gap was visible |
