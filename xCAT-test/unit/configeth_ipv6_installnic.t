#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempfile);
use FindBin;
use Test::More;

my $source = "$FindBin::Bin/../../xCAT/postscripts/configeth";
open( my $source_fh, '<', $source ) or die "Unable to read $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh);

sub shell_function {
    my ($name) = @_;
    my ($function) = $content =~ /^(function \Q$name\E\(\)\{.*?^\})/ms;
    die "Unable to extract $name from $source" unless defined($function);
    return $function;
}

is( system( 'bash', '-n', $source ), 0, 'configeth has valid bash syntax' );

my ( $harness_fh, $harness ) = tempfile();
print {$harness_fh} shell_function('discover_install_nic_ipv6'), "\n";
print {$harness_fh} shell_function('configure_install_nic_ipv6_connection'), "\n";
print {$harness_fh} shell_function('configure_install_nic_ipv6_nm'), "\n";
print {$harness_fh} shell_function('configure_install_nic_ipv6_keyfile'), "\n";
print {$harness_fh} <<'SHELL';
set -eu

NMCLI_LOG=$1
KEYFILE=$2

fail() {
    echo "$*" >&2
    exit 1
}

ip() {
    case "$*" in
        '-6 -o addr show dev eth0 scope global')
            printf '%s\n' \
                '2: eth0 inet6 2001:db8:1::88/56 scope global dynamic noprefixroute' \
                '2: eth0 inet6 2001:db8:1::99/64 scope global temporary dynamic' \
                '2: eth0 inet6 2001:db8:1::21/64 scope global dynamic noprefixroute'
            ;;
        '-6 route show default dev eth0')
            printf '%s\n' 'default via fe80::1 dev eth0 proto ra metric 100'
            ;;
        '-o link show dev eth0')
            printf '%s\n' '2: eth0: <BROADCAST,MULTICAST,UP> mtu 9000 state UP'
            ;;
        '-6 -o addr show dev eth1 scope global')
            printf '%s\n' '3: eth1 inet6 2001:db8:2::21/64 scope global dynamic noprefixroute'
            ;;
        '-6 route show default dev eth1')
            return 0
            ;;
        '-o link show dev eth1')
            printf '%s\n' '3: eth1: <BROADCAST,MULTICAST,UP> mtu 1500 state UP'
            ;;
        *)
            return 1
            ;;
    esac
}

nmcli() {
    case "$*" in
        '--escape no -g IP6.DNS device show eth0')
            printf '%s\n' '2001:db8::53' '2001:db8::54'
            ;;
        '--escape no -g IP6.SEARCHES device show eth0')
            printf '%s\n' 'cluster.example' 'lab.example'
            ;;
        '--escape no -g IP6.GATEWAY device show eth0')
            printf '%s\n' 'fe80::2'
            ;;
        '--escape no -g IP6.GATEWAY device show eth1')
            printf '%s\n' 'fe80::2'
            ;;
        '--escape no -g IP6.DNS device show eth1'|'--escape no -g IP6.SEARCHES device show eth1')
            printf '%s\n' '--'
            ;;
        '--offline con add type ethernet con-name xcat-eth0 ifname eth0 ipv4.method disabled ipv6.method manual ipv6.addresses 2001:db8:1::21/64 connection.autoconnect yes connection.autoconnect-priority 9 ipv6.gateway fe80::1 ipv6.dns 2001:db8::53,2001:db8::54 ipv6.dns-search cluster.example,lab.example 802-3-ethernet.mtu 9000')
            printf '%s\n' \
                '[connection]' \
                'id=xcat-eth0' \
                'uuid=01234567-89ab-cdef-0123-456789abcdef' \
                'type=ethernet' \
                'autoconnect-priority=9' \
                'interface-name=eth0' \
                '' \
                '[ethernet]' \
                'mtu=9000' \
                '' \
                '[ipv4]' \
                'method=disabled' \
                '' \
                '[ipv6]' \
                'addr-gen-mode=default' \
                'address1=2001:db8:1::21/64' \
                'dns=2001:db8::53;2001:db8::54;' \
                'dns-search=cluster.example;lab.example;' \
                'gateway=fe80::1' \
                'method=manual' \
                '' \
                '[proxy]'
            ;;
        *)
            printf '%s\n' "$*" >> "$NMCLI_LOG"
            ;;
    esac
}

discover_install_nic_ipv6 eth0 2001:db8:1::21 || fail 'IPv6 discovery failed'
[ "$str_inst_ipv6" = '2001:db8:1::21' ] || fail "unexpected address: $str_inst_ipv6"
[ "$str_inst_ipv6_prefix" = '64' ] || fail "unexpected prefix: $str_inst_ipv6_prefix"
[ "$str_inst_ipv6_gateway" = 'fe80::1' ] || fail "unexpected gateway: $str_inst_ipv6_gateway"
[ "$str_inst_ipv6_dns" = '2001:db8::53,2001:db8::54' ] || fail "unexpected DNS: $str_inst_ipv6_dns"
[ "$str_inst_ipv6_dns_search" = 'cluster.example,lab.example' ] || fail "unexpected DNS search: $str_inst_ipv6_dns_search"
[ "$str_inst_mtu" = '9000' ] || fail "unexpected MTU: $str_inst_mtu"

configure_install_nic_ipv6_nm \
    xcat-eth0 eth0 "$str_inst_ipv6" "$str_inst_ipv6_prefix" \
    "$str_inst_ipv6_gateway" "$str_inst_ipv6_dns" \
    "$str_inst_ipv6_dns_search" "$str_inst_mtu"

configure_install_nic_ipv6_keyfile \
    xcat-eth0 eth0 "$str_inst_ipv6" "$str_inst_ipv6_prefix" \
    "$str_inst_ipv6_gateway" "$str_inst_ipv6_dns" \
    "$str_inst_ipv6_dns_search" "$str_inst_mtu" "$KEYFILE"

discover_install_nic_ipv6 eth1 || fail 'IPv6 discovery with NetworkManager gateway fallback failed'
[ "$str_inst_ipv6_gateway" = 'fe80::2' ] || fail "unexpected fallback gateway: $str_inst_ipv6_gateway"
if discover_install_nic_ipv6 eth2; then
    fail 'IPv6 discovery accepted an interface without a global address'
fi
SHELL
close($harness_fh);

my ( $log_fh, $log ) = tempfile();
close($log_fh);
my ( $keyfile_fh, $keyfile ) = tempfile();
close($keyfile_fh);
unlink($keyfile) or die "Unable to prepare $keyfile: $!";
is( system( 'bash', $harness, $log, $keyfile ), 0, 'IPv6 install-NIC discovery and persistence helpers execute successfully' );

open( my $log_fh_read, '<', $log ) or die "Unable to read $log: $!";
my @nmcli = <$log_fh_read>;
close($log_fh_read);
chomp(@nmcli);

is_deeply(
    \@nmcli,
    [
        'con add type ethernet con-name xcat-eth0 ifname eth0 ipv4.method disabled ipv6.method manual ipv6.addresses 2001:db8:1::21/64 connection.autoconnect yes connection.autoconnect-priority 9 ipv6.gateway fe80::1 ipv6.dns 2001:db8::53,2001:db8::54 ipv6.dns-search cluster.example,lab.example 802-3-ethernet.mtu 9000',
    ],
    'NetworkManager connection is IPv6-only and persists address, route, DNS, search domains, and MTU'
);

unlike(
    join( "\n", @nmcli ),
    qr/ipv4\.(?:addresses|dns)|ipv4\.method (?:auto|manual)/,
    'IPv6-only persistence never configures or enables IPv4'
);

open( my $keyfile_fh_read, '<', $keyfile ) or die "Unable to read $keyfile: $!";
my $keyfile_content = do { local $/; <$keyfile_fh_read> };
close($keyfile_fh_read);
is(
    $keyfile_content,
    <<'KEYFILE',
[connection]
id=xcat-eth0
uuid=01234567-89ab-cdef-0123-456789abcdef
type=ethernet
autoconnect-priority=9
interface-name=eth0

[ethernet]
mtu=9000

[ipv4]
method=disabled

[ipv6]
addr-gen-mode=default
address1=2001:db8:1::21/64
dns=2001:db8::53;2001:db8::54;
dns-search=cluster.example;lab.example;
gateway=fe80::1
method=manual

[proxy]
KEYFILE
    'Anaconda-stage fallback writes the equivalent native NetworkManager keyfile'
);
is(
    ( stat($keyfile) )[2] & oct('07777'),
    oct('0600'),
    'NetworkManager keyfile is private'
);
unlike( $keyfile_content, qr/^address1=\d+\.\d+\.\d+\.\d+/m, 'keyfile does not configure an IPv4 address' );

like(
    $content,
    qr/if \[ \$install_nic_is_ipv6 -ne 1 \]; then\n\s+str_inst_net=\$\(v4calcnet/,
    'legacy IPv4 network calculation remains on the IPv4 path'
);
like(
    $content,
    qr/\[ \$install_nic_is_ipv6 -eq 1 \] && \[ \$networkmanager_active -eq 2 \].*?configure_install_nic_ipv6_keyfile/s,
    'chrooted Anaconda path persists a keyfile instead of an obsolete ifcfg file'
);
like(
    $content,
    qr/Do not tear down the\n\s+# Anaconda-owned live connection from inside the chroot/,
    'Anaconda-stage keyfile persistence leaves the live installer connection up'
);
like(
    $content,
    qr/nmcli con add type ethernet con-name \$con_name ifname \$\{str_inst_nic\} ipv4\.method manual ipv4\.addresses/,
    'legacy IPv4 NetworkManager persistence remains available'
);
like(
    $content,
    qr/discover_install_nic_ipv6 "\$str_inst_nic" "\$str_requested_ipv6"/,
    'configeth -s asks live discovery for the xCAT-defined IPv6 address when IPv4 lease data is absent'
);
like(
    $content,
    qr/\[ -n "\$NAMESERVERS" \] && nmcli con modify "\$con_name" ipv6\.dns "\$NAMESERVERS"/,
    'restart path updates IPv6 DNS without writing IPv4 DNS properties'
);

done_testing();
