package xCAT::BMCUtils;

use strict;
use warnings;

use Socket qw(inet_aton inet_ntoa);

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

#-------------------------------------------------------------------------------

=head3 bmc_net_params

    Descriptions:
        The address, netmask and gateway that bmcconfig sends to bmcsetup for one BMC.
        The networks row that contains the address gives the netmask and the gateway.
    Arguments:
        $bmc   the ipmi.bmc value of one BMC, an address or a host name
        $nets  array ref of networks rows, hashes with net, mask and gateway
        %opt   resolve4 => coderef, name to packed IPv4 address, default inet_aton
               facing   => coderef, (address, family) to the MN address on that network
    Returns:
        (address, netmask, gateway), or (undef, error message)

=cut

#-------------------------------------------------------------------------------
sub bmc_net_params {
    my ($bmc, $nets, %opt) = @_;
    my $resolve4 = $opt{resolve4} || \&inet_aton;
    my $facing   = $opt{facing}   || sub { return; };

    my $packed = $resolve4->($bmc);
    return (undef, "Unable to resolve $bmc") unless $packed;
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
