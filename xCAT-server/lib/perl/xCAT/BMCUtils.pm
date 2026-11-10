package xCAT::BMCUtils;

use strict;
use warnings;

use Socket qw(AF_INET6 inet_aton inet_ntoa inet_pton);

my %per_bmc_setting = map { $_ => 1 } qw(ip netmask gateway);

sub rspconfig_bmc_setting {
    my ( $subcommand, $argument, $bmcnum ) = @_;

    return { argument => $argument }
      unless defined $subcommand
      and $per_bmc_setting{$subcommand}
      and defined $argument
      and $argument =~ /,/x;

    if (not defined $bmcnum or $bmcnum !~ /^\d+$/x or $bmcnum < 1) {
        $bmcnum = 1;
    }
    my @arguments = split /,/x, $argument, -1;
    my $value = $arguments[ $bmcnum - 1 ];
    if (not defined $value or $value eq q{}) {
        return {
            error => "The value $argument does not carry a setting for BMC $bmcnum, give one value per BMC",
        };
    }

    return {
        argument           => $value,
        session_subcommand => "$subcommand=$value",
    };
}

sub _ipv4_number {
    my ($dotted) = @_;
    return unless defined($dotted)
      && $dotted =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
    return ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
}

sub _ipv6_packed {
    my ($address) = @_;
    return unless defined($address) && $address =~ /:/;
    return eval { inet_pton(AF_INET6, $address) };
}

sub _ipv6_in_prefix {
    my ($address, $network, $prefix) = @_;
    my $addr = _ipv6_packed($address);
    my $netp = _ipv6_packed($network);
    return 0 unless $addr && $netp;
    my $bits = '1' x $prefix . '0' x (128 - $prefix);
    my $mask = pack('B128', $bits);
    return (($addr & $mask) eq ($netp & $mask)) ? 1 : 0;
}

# networks.mask holds "/64" for an IPv6 network, or the length is on networks.net.
sub _bmc_net6_params {
    my ($ip, $nets, $facing) = @_;
    foreach my $row (@{ $nets || [] }) {
        my ($net, $prefix, $gw) = @{$row}{qw(net mask gateway)};
        next unless defined($net) && $net =~ /:/;
        if ($net =~ s{/([0-9]+)$}{}) {
            $prefix = $1 unless defined($prefix) && length($prefix);
        }
        next unless defined($prefix);
        $prefix =~ s{^/}{};
        next unless $prefix =~ /^\d+$/ && $prefix <= 128;
        next unless _ipv6_in_prefix($ip, $net, $prefix);

        if (defined($gw) && $gw eq '<xcatmaster>') {
            $gw = $facing->($ip, 6);
        }
        return ($ip, $prefix, $gw, $net);
    }
    return (undef, "xCAT BMC configuration error, no appropriate network for $ip found in networks, unable to determine the prefix length");
}

#-------------------------------------------------------------------------------

=head3 bmc_net_params

    Descriptions:
        The address, netmask and gateway that bmcconfig sends to bmcsetup for one BMC.
        The networks row that contains the address gives the netmask and the gateway.
        For an IPv6 BMC the netmask is the prefix length, and a fourth value is the
        prefix of the network, which bmcsetup writes with the static router.
        A name that resolves to both families gives the IPv4 address.
    Arguments:
        $bmc   the ipmi.bmc value of one BMC, an address or a host name
        $nets  array ref of networks rows, hashes with net, mask and gateway
        %opt   resolve4 => coderef, name to packed IPv4 address, default inet_aton
               resolve6 => coderef, name to IPv6 address, default no IPv6
               facing   => coderef, (address, family) to the MN address on that network
    Returns:
        (address, netmask, gateway), (address, prefix length, gateway, prefix) for
        IPv6, or (undef, error message)

=cut

#-------------------------------------------------------------------------------
sub bmc_net_params {
    my ($bmc, $nets, %opt) = @_;
    my $resolve4 = $opt{resolve4} || \&inet_aton;
    my $facing   = $opt{facing}   || sub { return; };

    my $packed = $resolve4->($bmc);
    unless ($packed) {
        my $ip6 = $bmc =~ /:/ ? $bmc : ($opt{resolve6} || sub { return; })->($bmc);
        return _bmc_net6_params($ip6, $nets, $facing)
          if defined($ip6) && _ipv6_packed($ip6);
        return (undef, "Unable to resolve $bmc");
    }
    my $ip    = inet_ntoa($packed);
    my $ipnum = unpack('N', $packed);

    foreach my $row (@{ $nets || [] }) {
        my ($net, $mask, $gw) = @{$row}{qw(net mask gateway)};
        my $netnum  = _ipv4_number($net);
        my $masknum = _ipv4_number($mask);
        next unless defined($netnum) && defined($masknum);
        next unless ($ipnum & $masknum) == $netnum;

        if (defined($gw) && $gw eq '<xcatmaster>') {
            my $mn = $facing->($ip, 4);
            $gw = $mn if defined $mn;
        }
        return ($ip, $mask, $gw);
    }
    return (undef, "xCAT BMC configuration error, no appropriate network for $ip found in networks, unable to determine netmask");
}

1;
