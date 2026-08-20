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
