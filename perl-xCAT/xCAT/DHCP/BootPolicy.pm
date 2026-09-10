package xCAT::DHCP::BootPolicy;

use strict;
use warnings;

sub kea_client_classes {
    my ( $class, %opts ) = @_;

    my $xnba_user_class = xnba_user_class_test();
    my $uefi_x64_arch_match = uefi_x64_client_architecture_match_expr();
    my $bios_boot = $opts{xnba_kpxe} ? 'xcat/xnba.kpxe' : 'pxelinux.0';
    my $uefi_boot = $opts{xnba_efi}  ? 'xcat/xnba.efi'  : '';
    my @classes;

    push @classes, @{ $opts{xnba_node_classes} || [] };

    push @classes, (
        {
            name             => 'xcat-bios',
            test             => "option[93].hex == 0x0000 and not ($xnba_user_class)",
            'boot-file-name' => $bios_boot,
        },
    );

    if ($uefi_boot ne '') {
        push @classes, {
            name             => 'xcat-uefi-x64',
            test             => "($uefi_x64_arch_match) and not ($xnba_user_class)",
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

    return \@classes;
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

# The user class a chainloaded second stage announces itself with, as an ISC
# dhcpd condition.
#
# RFC 3004 length-prefixes each string in option 77; plenty of clients send the
# bare string instead, and both are seen in the field from the same firmware
# depending on how it was built. Matching only the bare form means a loader
# that follows the RFC is handed the first stage again and chainloads itself
# forever, which is why the Kea policy has always accepted both
# (xnba_user_class_test) and why this one has to as well.
#
# suffix() takes the last N bytes, so one expression covers both encodings: the
# bare "xNBA" is its own last four bytes, and the RFC 3004 form "\x04xNBA" ends
# in the same four. It has to be a single expression, because dhcpd's grammar
# has no parenthesised grouping -- writing the two forms as `(a or b)` is a
# parse error ("left brace expected") that stops the daemon from starting.
#
# `quote` is the quoting the caller's context needs: a plain " for a config
# file written directly, and \" for a statement that reaches dhcpd through
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
    my $xnba       = $class->isc_xnba_user_class_test();

    return [
        "    if $xnba and option client-architecture = 00:00 { #x86, xCAT Network Boot Agent\n",
        "        always-broadcast on;\n",
        "        filename = \"http://$tftp$portsuffix/tftpboot/xcat/xnba/nets/${net}_${maskbits}\";\n",
        "    } else if $xnba and option client-architecture = 00:09 { #x86, xCAT Network Boot Agent\n",
        "        filename = \"http://$tftp$portsuffix/tftpboot/xcat/xnba/nets/${net}_${maskbits}.uefi\";\n",
        "    } else if $xnba and option client-architecture = 00:07 { #x86-64 UEFI, xCAT Network Boot Agent\n",
        "        filename = \"http://$tftp$portsuffix/tftpboot/xcat/xnba/nets/${net}_${maskbits}.uefi\";\n",
        "    } else if option client-architecture = 00:00  { #x86\n",
        "        filename \"xcat/xnba.kpxe\";\n",
        "    } else if option vendor-class-identifier = \"Etherboot-5.4\"  { #x86\n",
        "        filename \"xcat/xnba.kpxe\";\n",
        "    } else if option client-architecture = 00:07 { #x86_64 uefi\n ",
        "        filename \"xcat/xnba.efi\";\n",
        "    } else if option client-architecture = 00:09 { #x86_64 uefi alternative id\n ",
        "        filename \"xcat/xnba.efi\";\n",
        "    } else if option client-architecture = 00:02 { #ia64\n ",
        "        filename \"elilo.efi\";\n",
        "    } else if option client-architecture = 00:0b { #aaarch64\n ",
        "      filename \"boot/grub2/grub2.aarch64\";\n",
        "    } else if option client-architecture = 00:1b { #riscv64 uefi\n ",
        "      filename \"boot/grub2/grub2.riscv64\";\n",
        "    } else if option client-architecture = 00:1c { #riscv64 uefi http boot\n ",
        "      option vendor-class-identifier \"HTTPClient\";\n",
        "      filename \"http://$tftp$portsuffix/tftpboot/boot/grub2/grub2.riscv64\";\n",
        "    } else if option client-architecture = 00:1f { #QEMU s390x\n ",
        "      option conf-file = \"s390x/${net}_${maskbits}\";\n",
        "    } else if option client-architecture = 00:0e { #OPAL-v3\n ",
        "        option conf-file = \"http://$tftp$portsuffix/tftpboot/pxelinux.cfg/p/${net}_${maskbits}\";\n",
        "    } else if substring (option vendor-class-identifier,0,11) = \"onie_vendor\" { #for onie on cumulus switch\n",
        "        option www-server = \"http://$tftp$portsuffix/install/onie/onie-installer\";\n",
        "    } else if substring(filename,0,1) = null { #otherwise, provide yaboot if the client isn't specific\n ",
        "        filename \"/yaboot\";\n",
        "    }\n",
    ];
}

sub kea_xnba_node_classes {
    my ( $class, %opts ) = @_;

    my $nodes = $opts{nodes} || [];
    my $xnba_user_class = xnba_user_class_test();
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
            test             => "$xnba_user_class and option[93].hex == 0x0000 and $mac_test",
            'boot-file-name' => $base_url,
            'user-context'   => _xnba_user_context($node),
        };

        if ( $opts{xnba_efi} ) {
            push @classes, {
                name             => "$class_base-uefi",
                test             => "$xnba_user_class and ($uefi_x64_arch_match) and $mac_test",
                'boot-file-name' => "$base_url.uefi",
                'user-context'   => _xnba_user_context($node),
            };
        }
    }

    return \@classes;
}

sub kea_xnba_network_classes {
    my ( $class, %opts ) = @_;

    return [] unless $opts{net} && defined $opts{prefix} && $opts{next_server};

    my $xnba_user_class = xnba_user_class_test();
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
            test             => "$xnba_user_class and option[93].hex == 0x0000",
            'boot-file-name' => $base_url,
            additional_only  => 1,
        };
    }

    if ( $opts{xnba_efi} ) {
        push @classes, {
            name             => "xcat-xnba-net-$safe_network-uefi",
            test             => "$xnba_user_class and ($uefi_x64_arch_match)",
            'boot-file-name' => "$base_url.uefi",
            additional_only  => 1,
        };
    }

    return \@classes;
}

sub xnba_user_class_test {
    return "(option[77].exists and (option[77].text == 'xNBA' or option[77].hex == 0x784e4241 or substring(option[77].hex,1,4) == 'xNBA'))";
}

sub uefi_x64_client_architecture_match_expr {
    return "option[93].hex == 0x0007 or option[93].hex == 0x0009 or option[93].hex == 0x0010";
}

sub _xnba_class_base {
    my ( $node, $mac ) = @_;

    my $safe_node = $node;
    $safe_node =~ s/[^A-Za-z0-9_.-]/_/g;

    my $safe_mac = lc($mac);
    $safe_mac =~ s/[^0-9a-f]//g;

    return "xcat-xnba-$safe_node-$safe_mac";
}

sub _mac_test {
    my ($mac) = @_;

    my $mac_hex = lc($mac);
    $mac_hex =~ s/[^0-9a-f]//g;

    return "pkt4.mac == 0x$mac_hex";
}

sub _xnba_user_context {
    my ($node) = @_;

    return {
        'xcat-purpose' => 'xnba-second-stage',
        'xcat-node'    => $node->{node},
        'xcat-mac'     => lc( $node->{mac} ),
    };
}

1;
