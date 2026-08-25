package xCAT::BMCUtils;

use strict;
use warnings;

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

1;
