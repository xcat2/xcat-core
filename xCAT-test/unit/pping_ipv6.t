#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::DSHCore;

my %addresses = (
    v4only => { OnlyV4 => '192.0.2.10' },
    v6only => { OnlyV6 => '2001:db8::20' },
    dual   => {
        OnlyV4 => '192.0.2.30',
        OnlyV6 => '2001:db8::30',
    },
);

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::getipaddr = sub {
        my ($class, $target, $family) = @_;
        return unless exists($addresses{$target});
        return $addresses{$target}{$family};
    };

    my ($ipv4, $ipv6, $unresolved) =
      xCAT::DSHCore->partition_ping_targets(qw(v4only v6only dual missing));
    is_deeply(
        $ipv4,
        [qw(v4only dual)],
        'IPv4-only and dual-stack targets use the existing IPv4 probe path'
    );
    is_deeply(
        $ipv6,
        [qw(v6only)],
        'an IPv6-only target is assigned to the IPv6 probe path'
    );
    is_deeply(
        $unresolved,
        [qw(missing)],
        'an unresolved target is not passed to either address-family probe'
    );

    my @nmap_output = (
        "Nmap scan report for v4only (192.0.2.10)\n",
        "Host is up (0.00012s latency).\n",
        "Nmap scan report for 2001:db8::20\n",
        "Host is up.\n",
        "Host dual.example.test (192.0.2.30) appears to be up ... good.\n",
    );
    is_deeply(
        [ xCAT::DSHCore->nmap_alive_targets(
            [qw(v4only v6only dual missing)],
            \@nmap_output
        ) ],
        [qw(v4only v6only dual)],
        'old and current nmap output maps IPv4 and IPv6 reports to original targets'
    );

    my @literal_nmap_output = (
        "Nmap scan report for head.example.test (192.0.2.40)\n",
        "Host is up (0.00010s latency).\n",
        "Nmap scan report for head.example.test (2001:db8::40)\n",
        "Host is up.\n",
    );
    is_deeply(
        [ xCAT::DSHCore->nmap_alive_targets(
            [ '192.0.2.40', '2001:db8::40' ],
            \@literal_nmap_output
        ) ],
        [ '192.0.2.40', '2001:db8::40' ],
        'reverse-resolved nmap reports retain IPv4 and IPv6 literal targets'
    );

    is_deeply(
        [ xCAT::DSHCore->nmap_alive_targets(
            [ '2001:db8::40' ],
            [
                "Host head.example.test (2001:db8::40) "
                  . "appears to be up ... good.\n"
            ]
        ) ],
        [ '2001:db8::40' ],
        'legacy nmap output retains a reverse-resolved IPv6 literal target'
    );
}

is_deeply(
    [ xCAT::DSHCore->parse_pping_result_line('v4only: ping') ],
    [qw(v4only ping)],
    'pping result parser accepts the IPv4 and hostname output form'
);
is_deeply(
    [ xCAT::DSHCore->parse_pping_result_line('2001:db8::20: noping') ],
    [ '2001:db8::20', 'noping' ],
    'pping result parser preserves a complete IPv6 literal target'
);
is_deeply(
    [ xCAT::DSHCore->parse_pping_result_line('nmap diagnostic') ],
    [],
    'pping result parser ignores non-result diagnostics'
);

my $pping_source = "$FindBin::Bin/../../xCAT-client/bin/pping";
open(my $fh, '<', $pping_source) or die "Unable to read $pping_source: $!";
my $content = do { local $/; <$fh> };
close($fh);

like(
    $content,
    qr/nmap_pping\(\$ipv6_nodes,\s*6\)/,
    'pping sends its IPv6 target partition through the IPv6 nmap path'
);
like(
    $content,
    qr/push \@command, '-6' if \$family == 6;/,
    'the IPv6 nmap path explicitly selects nmap -6'
);
like(
    $content,
    qr/push \@command, shellwords\(\$more_options\)/,
    'site nmap options are parsed into list-form command arguments'
);
like(
    $content,
    qr/open\(my \$nmap_output, '-\|'\)/,
    'nmap output uses a lexical pipe'
);
like(
    $content,
    qr/exec \{ \$command\[0\] \} \@command;/,
    'nmap executes without an interpolated shell command'
);
unlike(
    $content,
    qr/open\(NMAP,/,
    'pping no longer uses the legacy bareword two-argument nmap pipe'
);

done_testing();
