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
Scenario: A known node is given the address it was defined with
  Given a node defined with a MAC and an IP outside the dynamic range
  And makedhcp has been run for that node
  When the node sends a DHCPDISCOVER from that MAC
  Then it is offered exactly that IP
  And a DHCPREQUEST for that IP is acknowledged with the same IP

Scenario: The same node comes back to the same address
  Given a node that has already been offered its reserved address
  When it discovers again after a reboot
  Then it is offered the same address again
  # A node's name-to-address mapping is what the rest of the deployment is
  # built on: /etc/hosts, DNS, the installer's kickstart URL.

Scenario: An unknown machine is given an address out of the pool
  Given a subnet with a dynamic range
  When a MAC with no reservation sends a DHCPDISCOVER
  Then it is offered an address inside the dynamic range
  And that address is not any node's reserved address

Scenario: An unknown machine is ignored where there is no pool
  Given a subnet with no dynamic range
  When a MAC with no reservation sends a DHCPDISCOVER
  Then no reply arrives
  # makedhcp warns "No dynamic range specified for <net>. If hardware
  # discovery is being used, a dynamic range is required." -- dhcp.pm:4494

Scenario: A dynamic range may be written as a pair or as a CIDR
  Given networks.dynamicrange is "10.0.0.200-10.0.0.250"
  Or networks.dynamicrange is "10.0.0.192/26"
  When an unknown MAC discovers
  Then the offered address falls inside the range either way
  # Range.pm parses both; several ranges may be given separated by ";"

Scenario: A node whose IP falls inside the dynamic range is refused
  Given a node whose defined IP is inside networks.dynamicrange
  When makedhcp runs for that node
  Then no reservation is created for it                              # [config]
  And makedhcp reports the collision
  # dhcp.pm:168 -- "Node <n> has <ip> which is inside the DHCP dynamic range."
  # On the wire the node is indistinguishable from an unknown machine.

Scenario: A node interface deliberately without an address is denied
  Given a mac table entry whose hostname field is the sentinel *NOIP*
  When that MAC sends a DHCPDISCOVER
  Then it is not offered an address
  And it is not told what to boot
  # dhcp.pm sets statements to "deny booting;" for a DENIED address.

Scenario: A node with several MACs is reachable on any of them
  Given a mac table entry of the form "mac1!host1|mac2!host2"
  When either MAC discovers
  Then each is offered the address of its own hostname
  # dhcp.pm splits on "|" and on "!"; the hostname defaults to the node name.

Scenario: An InfiniBand interface is reserved by its full hardware address
  Given a node MAC that is an InfiniBand identity, not a 6-byte Ethernet MAC
  When makedhcp runs for it
  Then the reservation is created with hardware-type 37 and the twin address # [config]
  # dhcp.pm _infiniband_identity_present / _infiniband_twin_update_commands

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
Scenario Outline: The loader follows the client architecture in option 93
  Given a subnet configured by makedhcp -n
  When a client sends a DHCPDISCOVER with option 93 = <arch>
  Then the reply names <loader>
  And siaddr is the tftpserver for that subnet

  Examples: architectures both backends agree on
    | arch   | client                       | loader                    |
    | 0x0000 | x86 BIOS PXE                 | xcat/xnba.kpxe            |
    | 0x0002 | ia64                         | elilo.efi                 |
    | 0x0007 | x86-64 UEFI                  | xcat/xnba.efi             |
    | 0x0009 | x86-64 UEFI, alternate id    | xcat/xnba.efi             |
    | 0x000b | aarch64 UEFI                 | boot/grub2/grub2.aarch64  |
    | 0x001b | riscv64 UEFI, TFTP           | boot/grub2/grub2.riscv64  |

  Examples: architectures only one backend answers -- see backend parity below
    | arch   | client                       | loader                    |
    | 0x0010 | x86-64 UEFI HTTP boot        | xcat/xnba.efi (Kea only)  |
    | 0x000c | ppc64 UEFI                   | /boot/grub2/grub2.ppc (Kea only) |
    | 0x000e | OPAL-v3 (POWER)              | conf-file URL (ISC only)  |

Scenario: A BIOS PXE client with no loader installed is told nothing
  Given <tftpdir>/xcat/xnba.kpxe does not exist
  When an x86 BIOS client discovers
  Then it is offered an address
  And it is not handed xcat/xnba.kpxe
  # dhcp.pm guards every xnba filename on -f "$tftpdir/xcat/xnba.kpxe";
  # Kea falls back to pxelinux.0 -- BootPolicy.pm:11

Scenario: An HTTP-boot client is given a URL and the tag its firmware demands
  When a client sends option 93 = 0x001c (riscv64 HTTP boot)
  Then the reply names a boot file beginning "http://"
  And that URL ends in the same grub2 image the TFTP path serves
  And the reply carries option 60 = "HTTPClient"
  # UEFI HTTP boot firmware discards a reply that is not tagged HTTPClient.
  # BootPolicy.pm:63-104

Scenario: The HTTP boot URL honours a non-default web port
  Given site.httpport is not 80
  When an HTTP-boot client discovers
  Then the URL carries that port
  # BootPolicy.pm:76 -- port 80 is left out of the URL entirely.

Scenario: An HTTP boot class is only offered where the image exists
  Given the riscv64 grub2 image is absent from the tftp directory
  When makedhcp -n runs
  Then no HTTP boot class is written for that network              # [config]
  # BootPolicy.pm:85 loader_present

Scenario: A QEMU s390x client is given a conf-file rather than a loader
  When a client sends option 93 = 0x001f
  Then the reply carries option 209 (conf-file) = "s390x/<net>_<prefix>"
  # BootPolicy.pm:106-131 and dhcp.pm:4446. The conf-file is per network.

Scenario: An OPAL-v3 client is given a petitboot conf-file URL
  When a client sends option 93 = 0x000e
  Then the reply carries option 209 = "http://<tftp>/tftpboot/pxelinux.cfg/p/<net>_<prefix>"
  # BootPolicy.pm:168

Scenario: A client that identifies itself by vendor class alone still boots
  When a client sends vendor class "Etherboot-5.4" and no usable option 93
  Then it is handed xcat/xnba.kpxe
  # BootPolicy.pm:151

Scenario: A client that says nothing recognisable falls through to yaboot
  When a client sends no client architecture and no known vendor class
  And no filename has been set by an earlier rule
  Then the reply names "/yaboot"
  # BootPolicy.pm:172 -- the final else of the ISC chain.
```

---

## Feature: Chained network boot -- first stage, then second stage

The loader that firmware runs comes straight back for a second DHCP exchange.
If it were handed the same loader again it would chainload itself forever, so
the second request must be answered differently. The loader announces itself in
the **user class, option 77**.

Source: `BootPolicy.pm:133-257`, `dhcp.pm:1169-1188`

```gherkin
Scenario: Firmware with no user class gets the loader binary
  When a client with no option 77 discovers
  Then it is handed a loader binary, not a script URL

Scenario: The loader announcing itself gets a script instead
  Given the first stage loader announces user class "xNBA"
  When it discovers with option 93 = 0x0000
  Then it is handed "http://<next-server>/tftpboot/xcat/xnba/nets/<net>_<prefix>"
  And the reply is broadcast rather than unicast
  # always-broadcast on -- BootPolicy.pm:143. The loader has no address yet.

Scenario: A UEFI second stage gets the UEFI script
  Given the loader announces user class "xNBA"
  When it discovers with option 93 = 0x0007 or 0x0009
  Then it is handed the same URL with ".uefi" appended
  # BootPolicy.pm:145-148

Scenario Outline: The user class is recognised however the client encodes it
  Given the client announces user class "xNBA" encoded as <encoding>
  When it discovers
  Then it is recognised as a second stage and handed the script URL

  Examples:
    | encoding                                  |
    | a bare string, as most clients send it    |
    | RFC 3004 length-prefixed, as the RFC says |
  # Kea accepts both -- BootPolicy.pm:252 tests option[77].text, the raw hex,
  # and the length-prefixed substring. The ISC chain compares
  # `option user-class-identifier = "xNBA"` against option 77 declared as a
  # plain string (dhcp.pm:4920), which is the bare form only.

Scenario: A known node's second stage is addressed to that node
  Given a node whose netboot method is xnba
  And that node announces user class "xNBA"
  When it discovers
  Then it is handed "http://<next-server>/tftpboot/xcat/xnba/nodes/<node>"
  And not the per-network script
  # dhcp.pm:1183, BootPolicy.pm:178-212. Two machines chainloading at the same
  # moment must not run the same script.

Scenario: A node's first stage is unaffected by its second stage rule
  Given the same node
  When it discovers with no user class
  Then it is handed xcat/xnba.kpxe
```

---

## Feature: The boot file a known node is given follows its netboot method

Source: `dhcp.pm:1169-1232` (ISC), `kea_boot_for_node` (Kea)

```gherkin
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

Scenario: A petitboot node is given a conf-file, not a boot file
  Given a node defined with netboot=petitboot
  When it discovers
  Then the reply carries option 209 = "http://<next-server>/tftpboot/petitboot/<node>"
  And no boot file is named

Scenario: An ONIE switch is given an installer URL keyed on its vendor class
  Given a node defined with netboot=onie and an osimage whose pkgdir exists
  When it discovers announcing a vendor class beginning "onie_vendor"
  Then the reply carries option 114 (www-server) = the installer URL
  # dhcp.pm:1214; also offered per subnet at BootPolicy.pm:170

Scenario: A ScaleMP client is given the ScaleMP loader
  Given a node defined with netboot=pxe
  When it discovers announcing vendor class "ScaleMP"
  Then the reply names "vsmp/pxelinux.0"
  # dhcp.pm:1194

Scenario: A node told to boot from disk is not handed a loader
  Given a node whose chain.currstate is "boot" or "iscsiboot"
  When it discovers
  Then it is offered its address
  And it is not handed an xNBA script
  # dhcp.pm:1171 -- otherwise a booted node would netboot forever.

Scenario: A Windows UEFI install defers to the proxyDHCP daemon
  Given a node in a Windows install or winshell state on UEFI firmware
  And proxydhcp is enabled for it
  When it discovers with option 93 = 0x0000, 0x0007 or 0x0009
  Then the reply names no boot file
  And it carries option 60 = "PXEClient"
  # dhcp.pm:1178 -- the tag tells firmware to ask the proxyDHCP daemon on 4011.

Scenario: An iSCSI node is given a root path
  Given a node with an iscsi server and target defined
  When it discovers
  Then the reply carries option 17 (root-path) = "iscsi:<server>:6:3260:<lun>:<target>"

Scenario: An IBM iSCSI initiator is given the vendor form of the same thing
  Given the same node, with an initiator name defined
  When it discovers announcing vendor class "ISAN"
  Then the reply carries the iSCSI IQN and root path as vendor options, not option 17
  # dhcp.pm:1153-1163 -- ISAN initiators do not read the standard option.

Scenario: The node is told its own name
  Given any known node
  When it discovers
  Then the reply carries option 12 (host-name) = the node name
  # dhcp.pm:305 -- 'send host-name "<node>"', on every reservation.
```

---

## Feature: Where the machine fetches its loader from -- hierarchy

A service node serves the racks behind it. Which server a node is sent to is
what makes a hierarchical cluster work, and it is visible in one field.

Source: `dhcp.pm:1000-1045`, `kea_next_server_for_node`, `dhcp.pm:3441`

```gherkin
Scenario: next-server follows noderes.tftpserver
  Given a node whose noderes.tftpserver names a service node
  When it discovers
  Then siaddr is that service node's address

Scenario: next-server falls back to xcatmaster
  Given a node with no tftpserver but with an xcatmaster
  When it discovers
  Then siaddr is the xcatmaster's address

Scenario: next-server otherwise comes from the subnet
  Given a node with neither tftpserver nor xcatmaster
  When it discovers
  Then siaddr is the tftpserver of the subnet it discovered on
  # dhcp.pm:1125 -- '${next-server}' defers to the network-level value.

Scenario: A node's URLs point at the same server as its next-server
  Given a node sent to a service node
  When it is handed an xNBA script URL or a petitboot conf-file
  Then the host in that URL is the service node, not the management node

Scenario: A pool delegated to another server is not served here
  Given networks.dhcpserver names a machine that is not this one
  When makedhcp -n runs on this machine
  Then this machine serves no dynamic range for that subnet
  And an unknown MAC on it draws no reply from this machine
  # dhcp.pm:3441 -- two servers answering one pool would hand out conflicting
  # addresses.

Scenario: Reservations are still served for a delegated subnet
  Given the same subnet, with its pool delegated
  When a known node on it discovers
  Then it is still offered its reserved address by this machine

Scenario: A dynamic range without a dhcpserver is an error
  Given a network with a dynamicrange and no dhcpserver in a hierarchy
  When makedhcp runs
  Then it reports the missing dhcpserver                            # [config]
  # dhcp.pm:1593

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
Scenario: The reply carries the subnet's gateway
  Given networks.gateway is set for the subnet
  When any client discovers on it
  Then the reply carries option 3 (routers) = that gateway

Scenario: A gateway outside its own subnet is rejected
  Given networks.gateway is not inside net/mask
  When makedhcp -n runs
  Then it fails with "Specified gateway <g> is not valid for <net>/<mask>"  # [config]

Scenario: The reply carries resolvers and the domain
  Given nameservers are set for the subnet or in site
  When any client discovers
  Then the reply carries option 6 (domain-name-servers)
  And option 15 (domain-name)
  And option 119 (domain-search) listing every known domain
  # dhcp.pm:4563-4589; domain-search is skipped on sles10 and rhel5.

Scenario: The reply carries NTP servers when they are configured
  Given ntpservers are set for the subnet or in site
  Then the reply carries option 42 (ntp-servers)

Scenario: The reply always carries a log server
  When any client discovers
  Then the reply carries option 7 (log-servers)
  And it is the management node's own address when none was configured
  # dhcp.pm:4560 -- genesis and the installer log to it during discovery.

Scenario: The reply carries an MTU where the network defines one
  Given networks.mtu is set
  Then the reply carries option 26 (interface-mtu)
  # A provisioning network on jumbo frames will not complete an install
  # otherwise.

Scenario: The lease is as long as site.dhcplease says
  Given site.dhcplease is set
  When a client is acknowledged
  Then option 51 (lease-time) is that value
  And 43200 seconds when site.dhcplease is unset
  # dhcp.pm:4524

Scenario: A PXE client gets a short lease
  When a client announcing a vendor class beginning "PXEClient" is acknowledged
  Then its lease is short, not the cluster default
  # dhcp.pm:4939 -- class "pxe" sets max-lease-time 600 so a pool address taken
  # by firmware is returned quickly. Note the subnet also sets
  # min-lease-time <dhcplease>, so what a PXE client actually receives is worth
  # asserting on the wire rather than assuming.

Scenario: Cumulus switches are told where to find their provisioning script
  When any client discovers
  Then the reply carries option 239 = "http://<tftp>/install/postscripts/cumulusztp"
  # dhcp.pm:4592 -- pushed on every subnet unconditionally.

Scenario: The server answers authoritatively
  When a client sends a DHCPREQUEST for an address that is not its own
  Then it receives a DHCPNAK rather than silence
  # dhcp.pm:4521 "authoritative;" -- a node that moved rack must be told to
  # start over rather than waiting out a lease that will never be renewed.

Scenario: A BOOTP-only client is served from the dynamic range
  Given a subnet with a dynamic range
  When a client that speaks BOOTP but not DHCP boots on it
  Then it is given an address
  # dhcp.pm:4648 -- "range dynamic-bootp <range>;"
```

---

## Feature: Discovery -- a machine nobody has told the cluster about

Discovery is the case where the server knows nothing about the client and still
has to get it far enough to identify itself.

Source: `dhcp.pm:4481-4498`, `BootPolicy.pm`, xCAT discovery documentation

```gherkin
Scenario: An undiscovered machine gets an address and a loader
  Given a subnet with a dynamic range
  When a machine with no reservation PXE boots on it
  Then it is offered a pool address
  And it is told what to boot, chosen by its option 93
  # This is what lets the genesis image run and report the machine's identity.

Scenario: Whether an unknown machine is told what to boot is backend policy
  Given the Kea backend
  Then an architecture class on the subnet hands every client a loader
  Given the ISC backend
  Then the boot file comes from the per-host block, so an unknown MAC gets none
  # BootPolicy.pm kea_client_classes are subnet-wide; the ISC chain is written
  # into the subnet too (dhcp.pm:4634) -- so this difference is worth
  # asserting on the wire on both backends rather than assumed from the source.

Scenario: A machine discovers on the architecture it actually is
  When an aarch64 machine with no reservation PXE boots
  Then it is handed the aarch64 loader, not the x86 one
  # A discovery path that only works for x86 leaves every other architecture
  # undiscoverable.

Scenario: A machine adopted during discovery is served without a restart
  Given a machine currently holding a pool address
  When it is defined as a node and makedhcp is run for it
  And it discovers again
  Then it is offered its reserved address
  And no DHCP daemon was restarted in between
  # ISC reservations are injected over OMAPI into dhcpd.leases, not written to
  # dhcpd.conf (dhcp.pm addnode). Discovery depends on this: restarting the
  # daemon mid-discovery drops every machine being discovered.

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
Scenario: makedhcp -n rewrites the whole configuration
  When makedhcp -n runs
  Then every network in the networks table has a subnet block          # [config]
  And existing reservations are preserved or re-added

Scenario: makedhcp <noderange> adds those nodes only
  When makedhcp is run for a node range
  Then only those nodes' reservations change

Scenario: makedhcp -a adds every node with a MAC
  When makedhcp -a runs
  Then every node with a MAC and a resolvable IP has a reservation

Scenario: makedhcp -q reports what the server holds
  When makedhcp -q is run for a node
  Then it prints that node's reservation, or reports that there is none

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
Scenario: site.dhcpinterfaces names the interfaces to serve
  Given site.dhcpinterfaces = "eth1"
  When makedhcp -n runs
  Then dhcpd is started with eth1 and no other interface

Scenario: site.dhcpinterfaces may be scoped per host
  Given site.dhcpinterfaces = "mn|eth1;sn1,sn2|eth2"
  When makedhcp -n runs on each host
  Then each serves only the interfaces named against it

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
Scenario: The same client gets the same answer from either backend
  Given a network and a node defined once
  When the cluster is served by ISC
  And then by Kea, from the same definitions
  Then a client's address, next-server and boot file are the same both times

Scenario: Known asymmetries between the backends
  # Read from the source, not yet asserted on the wire. Each is either a real
  # difference a booting machine would notice, or a gap in one backend:
  #   option 93 = 0x000c (ppc64)   Kea offers /boot/grub2/grub2.ppc;
  #                                the ISC chain has no 0x000c branch and
  #                                falls through to /yaboot.
  #   option 93 = 0x0010 (UEFI HTTP x86-64)
  #                                Kea matches it as UEFI x64;
  #                                the ISC chain does not.
  #   option 93 = 0x000e (OPAL-v3) ISC offers a petitboot conf-file;
  #                                Kea writes no such class.
  #   vendor class "Etherboot-5.4" ISC offers xcat/xnba.kpxe; Kea does not.
  #   vendor class "onie_vendor"   ISC offers a per-subnet www-server;
  #                                Kea offers it only per node.
  #   no match at all              ISC falls through to /yaboot; Kea offers
  #                                no boot file.
  #   user class, RFC 3004 form    Kea matches the length-prefixed encoding;
  #                                the ISC chain compares the bare string only.
```

---

## Feature: IPv6

Source: `dhcp.pm:568-583`, `addnode6`, `dhcp.pm:4293`

```gherkin
Scenario: A node is reserved by DUID rather than by MAC
  Given a node with a vpd.uuid
  When makedhcp runs and the cluster uses IPv6
  Then a DHCPv6 reservation is created against DUID-UUID 00:04:<uuid>
  # dhcp.pm:731-745

Scenario: A node without a uuid is skipped
  Given an IPv6 cluster and a node with no vpd.uuid
  When makedhcp runs for it
  Then it warns "Skipping DHCPv6 setup due to missing vpd.uuid information."

Scenario: An IPv6 subnet serves a range6
  Given networks.dynamicrange holds an IPv6 CIDR
  Then the DHCPv6 subnet declares range6 with that prefix
  # dhcp.pm:4293; a subnet with no range warns that hosts without a static
  # address will receive none.

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
