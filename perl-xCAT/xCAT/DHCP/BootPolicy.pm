package xCAT::DHCP::BootPolicy;

use strict;
use warnings;

sub kea_client_classes {
    my ( $class, %opts ) = @_;

    my $loader = $class->x86_loader();
    my $uefi_x64_arch_match = uefi_x64_client_architecture_match_expr();
    my $etherboot = etherboot_vendor_class_test();
    # No substitute when the loader is not on disk: naming a file the TFTP
    # server does not have costs the client a timeout it cannot diagnose, and a
    # different loader boots something nobody asked for.
    my $bios_boot = $opts{xnba_kpxe} ? $loader->{bios} : '';
    my $uefi_boot = $opts{xnba_efi}  ? $loader->{uefi} : '';
    my @classes;

    push @classes, @{ $opts{xnba_node_classes} || [] };

    # The short lease names no boot file, so its place among the classes that do
    # name one changes nothing.
    push @classes, kea_pxe_lease_client_class();

    if ($bios_boot ne '') {
        push @classes, (
            {
                name             => 'xcat-bios',
                test             => "option[93].hex == 0x0000 and not ($loader->{kea_second_stage_bios})",
                'boot-file-name' => $bios_boot,
            },
            # Etherboot predates option 93: it says what it is in option 60 and
            # nothing else.
            {
                name             => 'xcat-etherboot',
                test             => $etherboot,
                'boot-file-name' => $bios_boot,
            },
        );
    }

    if ($uefi_boot ne '') {
        push @classes, {
            name             => 'xcat-uefi-x64',
            test             => "($uefi_x64_arch_match) and not ($loader->{kea_second_stage_uefi})",
            'boot-file-name' => $uefi_boot,
        };
    }

    push @classes, (
        {
            name             => 'xcat-aarch64',
            test             => 'option[93].hex == 0x000b',
            'boot-file-name' => 'boot/grub2/grub2.aarch64',
        },
        {
            name             => 'xcat-riscv64',
            test             => 'option[93].hex == 0x001b',
            'boot-file-name' => 'boot/grub2/grub2.riscv64',
        },
        {
            name             => 'xcat-ppc64',
            test             => 'option[93].hex == 0x000c',
            'boot-file-name' => '/boot/grub2/grub2.ppc',
        },
        {
            name             => 'xcat-ia64',
            test             => 'option[93].hex == 0x0002',
            'boot-file-name' => 'elilo.efi',
        },
    );

    push @classes, kea_fallback_client_class();

    return \@classes;
}

#: Every client architecture some class here, or in the per-network classes
#: beside it, already answers. The fallback is what is left over.
my @RECOGNISED_ARCH_IDS = qw(
  0x0000 0x0002 0x0007 0x0009 0x000b 0x000c 0x000e 0x0010 0x001b 0x001c 0x001f
);

# The answer for a client that said nothing any other rule recognised.
#
# ISC reaches this by falling off the end of an if/else chain, which Kea has no
# equivalent of: every class is evaluated on its own. So the condition is
# written out rather than left to depend on which class Kea consults first.
#
# /yaboot is a poor universal default, but it is the one xCAT has always had on
# ISC. What matters is that both backends answer the same: a client left with an
# address and no boot file cannot tell it was served at all.
sub kea_fallback_client_class {
    my @recognised = map { "option[93].hex == $_" } @RECOGNISED_ARCH_IDS;
    push @recognised, etherboot_vendor_class_test(), onie_vendor_class_test(),
      xnba_user_class_test();

    return {
        name             => 'xcat-fallback',
        test             => join( ' and ', map { "not ($_)" } @recognised ),
        'boot-file-name' => '/yaboot',
    };
}

#: How long firmware keeps a pool address. A discovery of a few thousand
#: machines takes every address through a PXE ROM first, and a cluster-default
#: lease holds each one for half a day afterwards.
our $PXE_LEASE_SECONDS = 600;

# The short lease a PXE client is given, on either backend. ISC has always had
# `class "pxe"` for this, but with `max-lease-time 600` alone: dhcpd applies the
# subnet's min-lease-time after the maximum, so the cluster default won and the
# class did nothing.
sub kea_pxe_lease_client_class {
    return {
        name             => 'xcat-pxe-lease',
        test             => pxe_vendor_class_test(),
        'valid-lifetime' => $PXE_LEASE_SECONDS,
    };
}

sub pxe_vendor_class_test {
    return "substring(option[60].hex,0,9) == 'PXEClient'";
}

# The same decision as an ISC class. A maximum alone shortened nothing: dhcpd
# applies min-lease-time after the maximum, so every pool address a PXE ROM
# touched was held for half a day. All three bounds are named.
sub isc_pxe_lease_class_lines {
    my ($class) = @_;

    return [
        "class \"pxe\" {\n",
        "   match if substring (option vendor-class-identifier, 0, 9) = \"PXEClient\";\n",
        "   ddns-updates off;\n",
        "    min-lease-time $PXE_LEASE_SECONDS;\n",
        "    default-lease-time $PXE_LEASE_SECONDS;\n",
        "    max-lease-time $PXE_LEASE_SECONDS;\n",
        "}\n",
    ];
}

sub etherboot_vendor_class_test {
    return "option[60].text == 'Etherboot-5.4'";
}

sub onie_vendor_class_test {
    return "substring(option[60].text,0,11) == 'onie_vendor'";
}

# Architectures whose UEFI firmware can also boot over HTTP, by DHCP client
# architecture id (RFC 4578 and the IANA registry). An HTTP boot client wants the
# boot file as a URL and only accepts the offer when the reply is tagged
# HTTPClient; the image it downloads is the same grub2 the TFTP path hands out.
my %HTTP_BOOT_ARCHES = (
    riscv64 => { arch_id => '0x001c', loader => 'boot/grub2/grub2.riscv64' },
);

# The HTTP boot classes of one network. They carry the address of the management
# node on that network, so they belong to the subnet rather than to the global
# list, like the other network classes here.
sub kea_httpboot_network_classes {
    my ( $class, %opts ) = @_;

    return [] unless $opts{net} && defined( $opts{prefix} ) && $opts{next_server};

    my $httpport   = $opts{httpport} || '80';
    my $portsuffix = ( $httpport eq '80' ) ? '' : ":$httpport";
    my $tftpdir    = $opts{tftpdir} || '/tftpboot';
    $tftpdir =~ s{/+$}{};
    my $http_tftp_root = '/tftpboot';
    my $present = $opts{loader_present};
    my @classes;

    foreach my $arch ( sort keys %HTTP_BOOT_ARCHES ) {
        my $spec = $HTTP_BOOT_ARCHES{$arch};
        next if $present && !$present->("$tftpdir/$spec->{loader}");
        my $name = "xcat-$arch-http-$opts{net}_$opts{prefix}";
        $name =~ s/[^A-Za-z0-9_.-]/_/g;
        push @classes, {
            name             => $name,
            test             => "option[93].hex == $spec->{arch_id}",
            additional_only  => 1,
            'boot-file-name' => "http://$opts{next_server}$portsuffix$http_tftp_root/$spec->{loader}",
            'option-data'    => [
                {
                    name          => 'vendor-class-identifier',
                    data          => 'HTTPClient',
                    'always-send' => 1,
                },
            ],
        };
    }

    return \@classes;
}

sub kea_s390x_network_classes {
    my ( $class, %opts ) = @_;

    if ( !$opts{net} || !defined $opts{prefix} ) {
        return [];
    }

    my $network_id = "$opts{net}_$opts{prefix}";
    my $safe_network = $network_id;
    $safe_network =~ s{[^A-Za-z0-9_.-]}{_}gxms;

    return [
        {
            name            => "xcat-s390x-qemu-$safe_network",
            test            => 'option[93].hex == 0x001f',
            additional_only => 1,
            'option-data'   => [
                {
                    name          => 'conf-file',
                    data          => "s390x/$network_id",
                    'always-send' => 1,
                },
            ],
        },
    ];
}

# The installer URL an ONIE switch is offered, per subnet. A switch announces
# onie_vendor on its first boot, necessarily before anyone has defined it as a
# node, so a URL only a node definition can produce is one it can never reach.
# Per network, because the URL carries the address of the server.
sub kea_onie_network_classes {
    my ( $class, %opts ) = @_;

    return [] unless $opts{net} && defined( $opts{prefix} ) && $opts{next_server};

    my $httpport   = $opts{httpport} || '80';
    my $portsuffix = ( $httpport eq '80' ) ? '' : ":$httpport";
    my $name = "xcat-onie-$opts{net}_$opts{prefix}";
    $name =~ s{[^A-Za-z0-9_.-]}{_}gxms;

    return [
        {
            name            => $name,
            test            => onie_vendor_class_test(),
            additional_only => 1,
            'option-data'   => [
                kea_onie_url_option( undef, "http://$opts{next_server}$portsuffix/install/onie/onie-installer" ),
            ],
        },
    ];
}

# The installer URL goes in option 114, where ONIE looks for it. xCAT's
# dhcpd.conf declares "option www-server code 114 = string" -- a local
# redefinition, because ISC's own www-server is the standard option 72. Kea has
# no such redefinition, and a URL in option 72 is a configuration error that
# stops the server from starting. Naming the code says the same to both.
sub kea_onie_url_option {
    my ( $class, $url ) = @_;

    return {
        code          => 114,
        data          => $url,
        'always-send' => 1,
    };
}

# The user class a chainloaded second stage announces itself with, as an ISC
# dhcpd condition.
#
# RFC 3004 length-prefixes each string in option 77 and plenty of clients send the
# bare string instead, so both forms have to match. suffix() takes the last N
# bytes, which covers both in one expression -- and it has to be one, because
# dhcpd's grammar has no grouping.
#
# `quote` is " for a config file and \" for a statement reaching dhcpd through
# omshell.
sub isc_xnba_user_class_test {
    my ( $class, %opts ) = @_;

    my $q = defined( $opts{quote} ) ? $opts{quote} : '"';

    return "suffix(option user-class-identifier, 4) = ${q}xNBA${q}";
}

sub isc_client_architecture_lines {
    my ( $class, %opts ) = @_;

    my $tftp       = $opts{next_server} // '';
    my $portsuffix = $opts{portsuffix}  // '';
    my $net        = $opts{net}         // '';
    my $maskbits   = $opts{prefix}      // '';
    my $loader     = $class->x86_loader();

    # Which loaders are actually on disk. A branch naming a file the TFTP server
    # does not have costs the client a full timeout it cannot diagnose, so the
    # branch is left out and the client falls through. The Kea side has always
    # worked this way; until now ISC named all of them unconditionally.
    my $present = $opts{loader_present} || sub { return 1 };
    my $tftpdir = $opts{tftpdir} || '/tftpboot';
    $tftpdir =~ s{/+$}{};
    my $kpxe = $present->("$tftpdir/$loader->{bios}");
    my $efi  = $present->("$tftpdir/$loader->{uefi}");

    # Each entry is the head of one branch and its statements. They are chained
    # afterwards so dropping one still leaves a well-formed if/else chain.
    my @branches;

    if ($kpxe) {
        push @branches, [
            "$loader->{isc_second_stage_bios} and option client-architecture = 00:00 { #x86, xCAT Network Boot Agent\n",
            "        always-broadcast on;\n",
            "        filename = \"http://$tftp$portsuffix/tftpboot/xcat/xnba/nets/${net}_${maskbits}\";\n",
        ];
    }
    if ($efi) {
        push @branches, [
            "$loader->{isc_second_stage_uefi} and option client-architecture = 00:09 { #x86, xCAT Network Boot Agent\n",
            "        filename = \"http://$tftp$portsuffix/tftpboot/xcat/xnba/nets/${net}_${maskbits}.uefi\";\n",
          ],
          [
            "$loader->{isc_second_stage_uefi} and option client-architecture = 00:07 { #x86-64 UEFI, xCAT Network Boot Agent\n",
            "        filename = \"http://$tftp$portsuffix/tftpboot/xcat/xnba/nets/${net}_${maskbits}.uefi\";\n",
          ];
    }
    if ($kpxe) {
        push @branches, [
            "option client-architecture = 00:00  { #x86\n",
            "        filename \"$loader->{bios}\";\n",
          ],
          [
            "option vendor-class-identifier = \"Etherboot-5.4\"  { #x86\n",
            "        filename \"$loader->{bios}\";\n",
          ];
    }
    if ($efi) {
        push @branches, [
            "option client-architecture = 00:07 { #x86_64 uefi\n ",
            "        filename \"$loader->{uefi}\";\n",
          ],
          [
            "option client-architecture = 00:09 { #x86_64 uefi alternative id\n ",
            "        filename \"$loader->{uefi}\";\n",
          ],

          # 0x0010 is the same x86-64 UEFI firmware and loader as 0x0007,
          # announced by a machine set to fetch it over HTTP. Without the branch
          # a mainstream client falls through to /yaboot.
          [
            "option client-architecture = 00:10 { #x86_64 uefi http boot\n ",
            "        filename \"$loader->{uefi}\";\n",
          ];
    }

    push @branches, [
        "option client-architecture = 00:02 { #ia64\n ",
        "        filename \"elilo.efi\";\n",
      ],
      [
        "option client-architecture = 00:0b { #aaarch64\n ",
        "      filename \"boot/grub2/grub2.aarch64\";\n",
      ],

      # yaboot, what a ppc64 client fell through to without this branch, is not
      # a UEFI loader and cannot boot one of these machines.
      [
        "option client-architecture = 00:0c { #ppc64 grub2\n ",
        "      filename \"/boot/grub2/grub2.ppc\";\n",
      ],
      [
        "option client-architecture = 00:1b { #riscv64 uefi\n ",
        "      filename \"boot/grub2/grub2.riscv64\";\n",
      ];

    my $riscv_http = $present->("$tftpdir/boot/grub2/grub2.riscv64");
    if ($riscv_http) {
        push @branches, [
            "option client-architecture = 00:1c { #riscv64 uefi http boot\n ",
            "      option vendor-class-identifier \"HTTPClient\";\n",
            "      filename \"http://$tftp$portsuffix/tftpboot/boot/grub2/grub2.riscv64\";\n",
        ];
    }

    # Leaving a branch out is not the same as answering nothing. ISC evaluates
    # these as one if/else chain, so a client whose branch was dropped falls to
    # the /yaboot catch-all and is handed a loader nobody chose -- the
    # substitution S-12 forbids. So each dropped branch leaves one behind that
    # matches the same client and says nothing.
    my @suppressed;
    push @suppressed, "option client-architecture = 00:00",
      "option vendor-class-identifier = \"Etherboot-5.4\""
      unless $kpxe;
    push @suppressed, map { "option client-architecture = $_" } qw(00:07 00:09 00:10)
      unless $efi;
    push @suppressed, "option client-architecture = 00:1c"
      unless $riscv_http;
    push @branches, ["$_ { #the loader for this client is not on disk\n"]
      foreach @suppressed;

    push @branches, [
        "option client-architecture = 00:1f { #QEMU s390x\n ",
        "      option conf-file = \"s390x/${net}_${maskbits}\";\n",
      ],
      [
        "option client-architecture = 00:0e { #OPAL-v3\n ",
        "        option conf-file = \"http://$tftp$portsuffix/tftpboot/pxelinux.cfg/p/${net}_${maskbits}\";\n",
      ],
      [
        "substring (option vendor-class-identifier,0,11) = \"onie_vendor\" { #for onie on cumulus switch\n",
        "        option www-server = \"http://$tftp$portsuffix/install/onie/onie-installer\";\n",
      ],
      [
        "substring(filename,0,1) = null { #otherwise, provide yaboot if the client isn't specific\n ",
        "        filename \"/yaboot\";\n",
      ];

    my @lines;
    foreach my $branch (@branches) {
        my ( $head, @body ) = @$branch;
        push @lines, ( @lines ? "    } else if " : "    if " ) . $head, @body;
    }
    push @lines, "    }\n";

    return \@lines;
}

sub kea_xnba_node_classes {
    my ( $class, %opts ) = @_;

    my $nodes = $opts{nodes} || [];
    my $loader = $class->x86_loader();
    my $uefi_x64_arch_match = uefi_x64_client_architecture_match_expr();
    my @classes;

    foreach my $node (@$nodes) {
        next unless $node->{node} && $node->{mac} && $node->{next_server};
        my $class_base = _xnba_class_base( $node->{node}, $node->{mac} );
        my $mac_test = _mac_test( $node->{mac} );
        my $httpport = $node->{httpport} || '80';
        my $portsuffix = ( $httpport eq '80' ) ? '' : ":$httpport";
        my $base_url = 'http://' . $node->{next_server} . $portsuffix . '/tftpboot/xcat/xnba/nodes/' . $node->{node};

        push @classes, {
            name             => "$class_base-bios",
            test             => "$loader->{kea_second_stage_bios} and option[93].hex == 0x0000 and $mac_test",
            'boot-file-name' => $base_url,
            'user-context'   => _xnba_user_context($node),
        };

        if ( $opts{xnba_efi} ) {
            push @classes, {
                name             => "$class_base-uefi",
                test             => "$loader->{kea_second_stage_uefi} and ($uefi_x64_arch_match) and $mac_test",
                'boot-file-name' => "$base_url.uefi",
                'user-context'   => _xnba_user_context($node),
            };
        }
    }

    return \@classes;
}

#: A ScaleMP hypervisor is an ordinary BIOS PXE client except for the binary it
#: has to be handed, and the vendor class is the only thing that tells it apart.
sub scalemp_vendor_class_test { return "option[60].text == 'ScaleMP'"; }

#: IBM's iSCSI initiators announce this and then read the initiator name and the
#: root path out of option 43 rather than option 17.
sub isan_vendor_class_test { return "option[60].text == 'ISAN'"; }

# ISC writes the ScaleMP choice as one if/else on the node's own host block:
#
#   if option vendor-class-identifier = "ScaleMP" { filename = "vsmp/pxelinux.0"; }
#   else { filename = "pxelinux.0"; }
#
# Kea has no else, and a reservation's boot-file-name outranks every class, so
# the choice becomes two mutually exclusive classes and the reservation names no
# boot file at all.
sub kea_pxe_node_classes {
    my ( $class, %opts ) = @_;

    my $nodes   = $opts{nodes} || [];
    my $scalemp = scalemp_vendor_class_test();
    my @classes;

    foreach my $node (@$nodes) {
        next unless $node->{node} && $node->{mac};
        my $base     = _node_class_base( 'pxe', $node->{node}, $node->{mac} );
        my $mac_test = _mac_test( $node->{mac} );

        push @classes, {
            name             => "$base-scalemp",
            test             => "$mac_test and $scalemp",
            'boot-file-name' => 'vsmp/pxelinux.0',
            'user-context'   => _node_user_context( $node, 'pxe-vendor' ),
          },
          {
            name             => $base,
            test             => "$mac_test and not ($scalemp)",
            'boot-file-name' => 'pxelinux.0',
            'user-context'   => _node_user_context( $node, 'pxe-vendor' ),
          };
    }

    return \@classes;
}

# The same shape for iSCSI: ISC chooses between the ISAN vendor form and the
# standard one with an if/else, and an ISAN initiator is deliberately not sent
# option 17 at all. Only a node with an initiator name needs the choice.
sub kea_iscsi_node_classes {
    my ( $class, %opts ) = @_;

    my $nodes = $opts{nodes} || [];
    my $isan  = isan_vendor_class_test();
    my @classes;

    foreach my $node (@$nodes) {
        next unless $node->{node} && $node->{mac} && $node->{root_path} && $node->{iname};
        my $base     = _node_class_base( 'iscsi', $node->{node}, $node->{mac} );
        my $mac_test = _mac_test( $node->{mac} );

        push @classes, {
            name          => "$base-isan",
            test          => "$mac_test and $isan",
            'option-data' => [
                # Kea appends an encapsulated space only when the option that
                # carries it is itself configured, and option 43 has no data of
                # its own -- so the empty container is named too, or the
                # initiator is offered an address with no target. ISC needs no
                # equivalent: declaring `option isan.iqn` builds option 43.
                { name => 'isan-encap-opts' },
                { space => 'isan', name => 'iqn',       data => $node->{iname} },
                { space => 'isan', name => 'root-path', data => $node->{root_path} },
            ],
            'user-context' => _node_user_context( $node, 'iscsi-initiator' ),
          },
          {
            name          => $base,
            test          => "$mac_test and not ($isan)",
            'option-data' => [
                { name => 'root-path',           data => $node->{root_path} },
                { name => 'iscsi-initiator-iqn', data => $node->{iname} },
            ],
            'user-context' => _node_user_context( $node, 'iscsi-initiator' ),
          };
    }

    return \@classes;
}

# The tag that hands a client to the proxyDHCP daemon.
#
# Windows UEFI firmware that is offered no boot file, but sees option 60 set to
# PXEClient, asks the daemon listening on port 4011 for one. ISC does this in
# the node's own host block, for the three architecture ids its firmware
# announces.
#
# The empty boot file is the reservation's job, and xcat-localboot keeps the
# boot-file classes off the MAC. What is left for this class is the tag and the
# architectures it is meant for.
sub kea_proxydhcp_node_classes {
    my ( $class, %opts ) = @_;

    my $nodes = $opts{nodes} || [];
    my $arches = join ' or ',
      map { "option[93].hex == $_" } qw(0x0000 0x0007 0x0009);
    my @classes;

    foreach my $node (@$nodes) {
        next unless $node->{node} && $node->{mac};
        push @classes, {
            name          => _node_class_base( 'proxydhcp', $node->{node}, $node->{mac} ),
            test          => _mac_test( $node->{mac} ) . " and ($arches)",
            'option-data' => [
                {
                    name          => 'vendor-class-identifier',
                    data          => 'PXEClient',
                    'always-send' => 1,
                },
            ],
            'user-context' => _node_user_context( $node, 'proxydhcp-deferral' ),
        };
    }

    return \@classes;
}

# The MACs that are to be answered with nothing at all.
#
# ISC writes `deny booting;` into the host block of a NIC marked *NOIP*. Kea has
# one way to do that: a packet assigned to the class named DROP is discarded.
# There can only be one of it, so every such MAC shares it, and the user-context
# records whose they are so a later makedhcp for one node can rebuild it.
#
# Skipping the reservation is not enough: the subnet-wide classes match on
# architecture and would still hand the interface a boot file.
sub kea_drop_client_class {
    my ( $class, %opts ) = @_;

    my @macs = grep { $_->{node} && $_->{mac} } @{ $opts{macs} || [] };
    return unless @macs;

    my @sorted = sort { $a->{node} cmp $b->{node} or $a->{mac} cmp $b->{mac} } @macs;

    return {
        name           => 'DROP',
        test           => join( ' or ', map { _mac_test( $_->{mac} ) } @sorted ),
        'user-context' => {
            'xcat-purpose' => 'noip-drop',
            'xcat-macs'    => [ map { { node => $_->{node}, mac => lc( $_->{mac} ) } } @sorted ],
        },
    };
}

# The name of the class holding every MAC that is to be handed no boot file.
sub kea_localboot_class_name { return 'xcat-localboot'; }

# The test fragment that keeps a class from matching one of those MACs.
sub kea_localboot_guard {
    return "not member('" . kea_localboot_class_name() . "')";
}

# The MACs of nodes that are to be handed no boot file: a node that has an
# operating system and must be left to start it (spec.md S-31), and a Windows
# UEFI install deferred to proxyDHCP.
#
# An empty boot-file-name is not enough: Kea reads it as "not specified" and falls
# through to the classes. So the MACs go into one class every boot-file class
# excludes -- see kea_apply_localboot_guard. A node booting from an iSCSI target is
# deliberately not here: gPXE attaches its root disk, so it does want a loader.
sub kea_localboot_client_class {
    my ( $class, %opts ) = @_;

    my @macs = grep { $_->{node} && $_->{mac} } @{ $opts{macs} || [] };
    return unless @macs;

    my @sorted = sort { $a->{node} cmp $b->{node} or $a->{mac} cmp $b->{mac} } @macs;

    return {
        name           => kea_localboot_class_name(),
        test           => join( ' or ', map { _mac_test( $_->{mac} ) } @sorted ),
        'user-context' => {
            'xcat-purpose' => 'localboot-suppress',
            'xcat-macs'    => [ map { { node => $_->{node}, mac => lc( $_->{mac} ) } } @sorted ],
        },
    };
}

#: The encapsulated space ISC declares as "option space isan": option 43 with
#: the initiator name in 203 and the root path in 201.
sub kea_isan_option_defs {
    return [
        {
            name        => 'isan-encap-opts',
            code        => 43,
            type        => 'empty',
            space       => 'dhcp4',
            encapsulate => 'isan',
        },
        { name => 'iqn',       code => 203, type => 'string', space => 'isan' },
        { name => 'root-path', code => 201, type => 'string', space => 'isan' },
    ];
}

sub kea_xnba_network_classes {
    my ( $class, %opts ) = @_;

    return [] unless $opts{net} && defined $opts{prefix} && $opts{next_server};

    my $loader = $class->x86_loader();
    my $uefi_x64_arch_match = uefi_x64_client_architecture_match_expr();
    my $httpport = $opts{httpport} || '80';
    my $portsuffix = ( $httpport eq '80' ) ? '' : ":$httpport";
    my $network_id = $opts{net} . '_' . $opts{prefix};
    my $safe_network = $network_id;
    $safe_network =~ s/[^A-Za-z0-9_.-]/_/g;
    my $base_url = 'http://' . $opts{next_server} . $portsuffix
      . '/tftpboot/xcat/xnba/nets/' . $network_id;
    my @classes;

    if ( $opts{xnba_kpxe} ) {
        push @classes, {
            name             => "xcat-xnba-net-$safe_network-bios",
            test             => "$loader->{kea_second_stage_bios} and option[93].hex == 0x0000",
            'boot-file-name' => $base_url,
            additional_only  => 1,
        };
    }

    if ( $opts{xnba_efi} ) {
        push @classes, {
            name             => "xcat-xnba-net-$safe_network-uefi",
            test             => "$loader->{kea_second_stage_uefi} and ($uefi_x64_arch_match)",
            'boot-file-name' => "$base_url.uefi",
            additional_only  => 1,
        };
    }

    return \@classes;
}

# iPXE feature indicators: sub-options of DHCP option 175 that iPXE sends, one byte each, for the
# protocols and image formats it was built with.
my @IPXE_FEATURES = (
    [ iscsi   => 17 ],
    [ http    => 19 ],
    [ bzimage => 24 ],
    [ pxe     => 33 ],
    [ efi     => 36 ],
);

# The ISC declarations of the iPXE feature indicators, in the gpxe option space. They decode the
# options and change no rule. OMAPI keeps host statements in dhcpd.leases, so they are always
# declared: a statement that tests them must parse even when no node needs it any more.
sub isc_ipxe_feature_option_lines {
    return [ map { "option gpxe.$_->[0] code $_->[1] = unsigned integer 8;\n" } @IPXE_FEATURES ];
}

# The Kea definition of option 175 and of the iPXE feature indicators it encapsulates. Kea tests a
# sub-option without a definition, but never finds it there.
sub kea_ipxe_option_defs {
    return [
        { name => 'gpxe-encap-opts', code => 175, space => 'dhcp4', type => 'empty', encapsulate => 'gpxe' },
        # The ISC lines use these codes as strings, and JSON::XS then writes them as JSON strings.
        map { { name => $_->[0], code => 0 + $_->[1], space => 'gpxe', type => 'uint8' } } @IPXE_FEATURES,
    ];
}

# An upgrade keeps the configuration of an older makedhcp -n. These add the declarations it lacks
# and return how many they added, or an error when they cannot add them.
sub isc_declare_ipxe_features {
    my ( $class, $conf ) = @_;

    my ($space) = grep { $conf->[$_] =~ /^\s*option\s+space\s+gpxe\s*;/ } 0 .. $#$conf;
    return ( 0, 'it declares no gpxe option space' ) unless defined $space;
    my @missing = grep {
        my ($name) = /^option (\S+) code /;
        !grep { /^\s*option\s+\Q$name\E\s+code\s/ } @$conf;
    } @{ $class->isc_ipxe_feature_option_lines() };
    splice( @$conf, $space + 1, 0, @missing );
    return ( scalar @missing, undef );
}

# The Kea variant also returns an error for an option 175 without the gpxe encapsulation: Kea cannot
# decode the features in it, and option data can name it, so makedhcp does not replace it.
sub kea_declare_ipxe_features {
    my ( $class, $dhcp4 ) = @_;

    # Compare codes as numbers: JSON::XS writes a number used as a string as a JSON string.
    my $defs = $dhcp4->{'option-def'} || [];
    my ($opaque) = grep {
        ( $_->{space} // 'dhcp4' ) eq 'dhcp4' && $_->{code} == 175 && ( $_->{encapsulate} // '' ) ne 'gpxe'
    } @$defs;
    return ( 0, "The Kea option definition $opaque->{name} gives option 175 no gpxe encapsulation, so netboot=ipxe "
          . "clients cannot report their iPXE features. Run makedhcp -n, or give $opaque->{name} the gpxe encapsulation." )
      if $opaque;
    my @missing = grep {
        my $def = $_;
        !grep { ( $_->{space} // 'dhcp4' ) eq $def->{space} && $_->{code} == $def->{code} } @$defs;
    } @{ $class->kea_ipxe_option_defs() };
    push @{ $dhcp4->{'option-def'} }, @missing if @missing;
    return ( scalar @missing, undef );
}

# The x86 loader: its BIOS and UEFI files, and the tests that recognize a client that runs it and
# can fetch the boot script.
sub x86_loader {
    my ($class) = @_;

    return {
        bios                  => 'xcat/xnba.kpxe',
        uefi                  => 'xcat/xnba.efi',
        isc_second_stage_bios => $class->isc_xnba_user_class_test(),
        isc_second_stage_uefi => $class->isc_xnba_user_class_test(),
        isc_san_boot          => 'exists gpxe.bus-id',
        kea_second_stage_bios => xnba_user_class_test(),
        kea_second_stage_uefi => xnba_user_class_test(),
    };
}

# The ISC host statements that choose the boot file of a node with netboot xnba or pxe. They reach
# dhcpd through omshell, so their quotes are escaped.
sub isc_node_boot_statements {
    my ( $class, %opts ) = @_;

    my $netboot = $opts{netboot} // '';
    return '' if $netboot ne 'xnba' && $netboot ne 'pxe';
    return '' unless $opts{loader_present};

    my $loader    = $class->x86_loader();
    my $bios      = $loader->{bios};
    my $uefi      = $loader->{uefi};
    my $bios_next = _omapi_quote( $loader->{isc_second_stage_bios} );
    my $uefi_next = _omapi_quote( $loader->{isc_second_stage_uefi} );
    my $san_boot  = _omapi_quote( $loader->{isc_san_boot} );
    my $currstate = $opts{currstate} // '';
    my $script    = 'http://' . ( $opts{next_server} // '' ) . ( $opts{portsuffix} // '' )
      . '/tftpboot/xcat/xnba/nodes/' . ( $opts{node} // '' );

    # A node in state boot or iscsiboot has an operating system and is left to start it (S-31).
    # An iSCSI root still needs the loader, which attaches the disk.
    if ( $currstate eq 'boot' || $currstate eq 'iscsiboot' ) {
        return 'filename = \"\";' unless $opts{iscsi};
        return 'if ' . $san_boot . ' { filename = \"\"; } else if exists client-architecture { filename = \"' . $bios . '\"; } '
          if $netboot eq 'pxe';
        return 'if option client-architecture = 00:00 and not ' . $san_boot . ' { filename = \"' . $bios . '\"; } else { filename = \"\"; } ';
    }
    return 'if option vendor-class-identifier = \"ScaleMP\" { filename = \"vsmp/pxelinux.0\"; } else { filename = \"pxelinux.0\"; }'
      if $netboot eq 'pxe';

    my $uefi_mode = $opts{uefi} // 0;
    if ( ( $uefi_mode == 2 && $currstate =~ /^install/ ) || $currstate =~ /^winshell/ ) {
        return 'if option client-architecture = 00:00 or option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else { filename = \"\"; }'
          if $opts{proxydhcp} && $opts{proxydhcp}->();
        return 'if ' . $bios_next . ' and option client-architecture = 00:00 { always-broadcast on; filename = \"' . $script . '\"; } else if option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else if option client-architecture = 00:00 { filename = \"' . $bios . '\"; } else { filename = \"\"; }';
    }
    if ($uefi_mode) {
        # dhcpd's expression grammar has no grouping, so each UEFI architecture gets its own branch.
        my $uefi_script = 'filename = \"' . $script . '.uefi\";';
        return 'if ' . $bios_next . ' and option client-architecture = 00:00 { always-broadcast on; filename = \"' . $script . '\"; } else if ' . $uefi_next . ' and option client-architecture = 00:09 { ' . $uefi_script . ' } else if ' . $uefi_next . ' and option client-architecture = 00:07 { ' . $uefi_script . ' } else if option client-architecture = 00:07 { filename = \"' . $uefi . '\"; } else if option client-architecture = 00:00 { filename = \"' . $bios . '\"; } else { filename = \"\"; }';
    }
    return 'if ' . $bios_next . ' and option client-architecture = 00:00 { filename = \"' . $script . '\"; } else if option client-architecture = 00:00 { filename = \"' . $bios . '\"; } else { filename = \"\"; }';
}

sub _omapi_quote {
    my ($text) = @_;
    $text =~ s/"/\\"/g;
    return $text;
}

sub xnba_user_class_test {
    return "(option[77].exists and (option[77].text == 'xNBA' or option[77].hex == 0x784e4241 or substring(option[77].hex,1,4) == 'xNBA'))";
}

sub uefi_x64_client_architecture_match_expr {
    return "option[93].hex == 0x0007 or option[93].hex == 0x0009 or option[93].hex == 0x0010";
}

sub _node_class_base {
    my ( $purpose, $node, $mac ) = @_;

    my $safe_node = $node;
    $safe_node =~ s/[^A-Za-z0-9_.-]/_/g;

    my $safe_mac = lc($mac);
    $safe_mac =~ s/[^0-9a-f]//g;

    return "xcat-$purpose-$safe_node-$safe_mac";
}

sub _xnba_class_base {
    my ( $node, $mac ) = @_;

    return _node_class_base( 'xnba', $node, $mac );
}

sub _mac_test {
    my ($mac) = @_;

    my $mac_hex = lc($mac);
    $mac_hex =~ s/[^0-9a-f]//g;

    return "pkt4.mac == 0x$mac_hex";
}

sub _node_user_context {
    my ( $node, $purpose ) = @_;

    return {
        'xcat-purpose' => $purpose,
        'xcat-node'    => $node->{node},
        'xcat-mac'     => lc( $node->{mac} ),
    };
}

sub _xnba_user_context {
    my ($node) = @_;

    return _node_user_context( $node, 'xnba-second-stage' );
}

1;
