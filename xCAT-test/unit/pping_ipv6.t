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
        [ xCAT::NetworkUtils->nmap_alive_targets(
            [qw(v4only v6only dual missing)],
            \@nmap_output
        ) ],
        [qw(v4only v6only dual)],
        'old and current nmap output maps IPv4 and IPv6 reports to original targets'
    );

    is(
        xCAT::NetworkUtils->match_ping_target(
            'foo.bar.example', [ 'foo', 'foo.bar.example' ]
        ),
        'foo',
        'direct matching preserves first-target prefix precedence'
    );

    my @literal_nmap_output = (
        "Nmap scan report for head.example.test (192.0.2.40)\n",
        "Host is up (0.00010s latency).\n",
        "Nmap scan report for head.example.test (2001:db8::40)\n",
        "Host is up.\n",
    );
    is_deeply(
        [ xCAT::NetworkUtils->nmap_alive_targets(
            [ '192.0.2.40', '2001:db8::40' ],
            \@literal_nmap_output
        ) ],
        [ '192.0.2.40', '2001:db8::40' ],
        'reverse-resolved nmap reports retain IPv4 and IPv6 literal targets'
    );

    is_deeply(
        [ xCAT::NetworkUtils->nmap_alive_targets(
            [ '2001:db8::40' ],
            [
                "Host head.example.test (2001:db8::40) "
                  . "appears to be up ... good.\n"
            ]
        ) ],
        [ '2001:db8::40' ],
        'legacy nmap output retains a reverse-resolved IPv6 literal target'
    );

    is_deeply(
        [ xCAT::NetworkUtils->nmap_alive_targets(
            [qw(v4only v6only)],
            [
                "Nmap scan report for 2001:0DB8:0:0:0:0:0:20\n",
                "Host is up.\n",
                "Nmap scan report for v4only (192.0.2.10)\n",
                "Host is up.\n",
                "Nmap scan report for 2001:db8::20\n",
                "Host is up.\n",
            ]
        ) ],
        [qw(v6only v4only)],
        'shared nmap parsing matches equivalent IPv6 spellings and preserves first report order'
    );

    is_deeply(
        [ xCAT::NetworkUtils->nmap_alive_targets(
            [qw(v4only v6only)],
            [
                "Nmap scan report for v4only (192.0.2.10)\n",
                "Host is up.\n",
                "Nmap scan report for unknown.example.test (192.0.2.99)\n",
                "Host is up.\n",
            ]
        ) ],
        [qw(v4only)],
        'an unmatched report clears parser state before a following Host is up line'
    );

    {
        my @batch = map { "batch$_" } 1 .. 5;
        my %batch_addresses = map {
            $batch[$_ - 1] => "192.0.2." . (40 + $_)
        } 1 .. 5;
        my $lookups = 0;
        local *xCAT::NetworkUtils::getipaddr = sub {
            my ( $class, $target, $family ) = @_;
            $lookups++;
            return unless $family eq 'OnlyV4';
            return $batch_addresses{$target};
        };
        my @batch_output;
        foreach my $target (@batch) {
            my $address = $batch_addresses{$target};
            push @batch_output,
              "Nmap scan report for reverse-$target.example.test ($address)\n",
              "Host is up.\n",
              "Nmap scan report for reverse-$target.example.test ($address)\n",
              "Host is up.\n";
        }

        is_deeply(
            [ xCAT::NetworkUtils->nmap_alive_targets(
                \@batch, \@batch_output
            ) ],
            \@batch,
            'batch nmap parsing preserves first report order and deduplicates targets'
        );
        is(
            $lookups,
            2 * scalar(@batch),
            'batch nmap parsing resolves each hostname once per address family'
        );

        $lookups = 0;
        is_deeply(
            [ xCAT::NetworkUtils->nmap_alive_targets(
                \@batch,
                [
                    "Nmap scan report for batch1.example.test\n",
                    "Host is up.\n",
                ]
            ) ],
            ['batch1'],
            'direct hostname reports match without address resolution'
        );
        is(
            $lookups,
            0,
            'direct hostname reports do not trigger DNS lookups'
        );
    }
}

{
    no warnings 'redefine';
    local $::STATUS_ACTIVE = 'active';
    local $::STATUS_INACTIVE = 'inactive';
    local *xCAT::NetworkUtils::_nmap_ping_available = sub { return 1; };
    local *xCAT::NetworkUtils::_nmap_ping_output = sub {
        return (
            "Nmap scan report for node3 (192.0.2.53)\n",
            "Host is up.\n",
            "Nmap scan report for node1 (192.0.2.51)\n",
            "Host is up.\n",
        );
    };
    local *xCAT::NetworkUtils::getipaddr = sub {
        my ( $class, $target, $family ) = @_;
        return unless $family eq 'OnlyV4';
        return {
            node1 => '192.0.2.51',
            node2 => '192.0.2.52',
            node3 => '192.0.2.53',
        }->{$target};
    };
    local *xCAT::TableUtils::get_site_attribute = sub { return; };

    my %status = xCAT::NetworkUtils->pingNodeStatus(
        qw(node1 node2 node3)
    );
    is_deeply(
        $status{active},
        [qw(node3 node1)],
        'pingNodeStatus preserves nmap report order for active nodes'
    );
    is_deeply(
        $status{inactive},
        ['node2'],
        'pingNodeStatus reports the remaining node as inactive'
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

# pping runs nmap or fping as a list, never through a shell, so the command it
# builds is the thing to measure. The two builders below carry that decision.
is_deeply(
    [   xCAT::DSHCore->nmap_ping_command( 6, '', [ '2001:db8::20', 'v6only' ] )
    ],
    [   'nmap', '-6', '-PE', '--system-dns', '--send-ip', '-sP',
        '--unprivileged', '-PA80,443,22', '2001:db8::20', 'v6only'
    ],
    'the nmap command for an IPv6 partition selects nmap -6'
);
is_deeply(
    [ xCAT::DSHCore->nmap_ping_command( 4, '', ['192.0.2.10'] ) ],
    [   'nmap', '-PE', '--system-dns', '--send-ip', '-sP',
        '--unprivileged', '-PA80,443,22', '192.0.2.10'
    ],
    'the nmap command for an IPv4 partition does not select nmap -6'
);
is_deeply(
    [   xCAT::DSHCore->nmap_ping_command(
            4, '--max-retries 2 -T4', ['192.0.2.10']
        )
    ],
    [   'nmap', '-PE', '--system-dns', '--send-ip', '-sP',
        '--unprivileged', '-PA80,443,22', '--max-retries', '2', '-T4',
        '192.0.2.10'
    ],
    'the site nmap options become separate command arguments'
);
is_deeply(
    [   xCAT::DSHCore->nmap_ping_command(
            4, q{--script 'a b'}, ['192.0.2.10']
        )
    ],
    [   'nmap', '-PE', '--system-dns', '--send-ip', '-sP',
        '--unprivileged', '-PA80,443,22', '--script', 'a b', '192.0.2.10'
    ],
    'a quoted site nmap option stays one argument'
);
is_deeply(
    [ xCAT::DSHCore->nmap_ping_command( 4, undef, ['192.0.2.10'] ) ],
    [   'nmap', '-PE', '--system-dns', '--send-ip', '-sP',
        '--unprivileged', '-PA80,443,22', '192.0.2.10'
    ],
    'no site nmap options adds no empty argument'
);

is_deeply(
    [   xCAT::DSHCore->fping_ping_command(
            6, { fping => '/usr/bin/fping', fping6 => '/usr/sbin/fping6' },
            ['2001:db8::20']
        )
    ],
    [ '/usr/sbin/fping6', '-a', '2001:db8::20' ],
    'fping6 probes an IPv6 partition where the host has it'
);
is_deeply(
    [   xCAT::DSHCore->fping_ping_command(
            6, { fping => '/usr/bin/fping' }, ['2001:db8::20']
        )
    ],
    [ '/usr/bin/fping', '-6', '-a', '2001:db8::20' ],
    'fping -6 probes an IPv6 partition on a host that ships no fping6'
);
is_deeply(
    [   xCAT::DSHCore->fping_ping_command(
            4, { fping => '/usr/bin/fping', fping6 => '/usr/sbin/fping6' },
            ['192.0.2.10']
        )
    ],
    [ '/usr/bin/fping', '-a', '192.0.2.10' ],
    'fping probes an IPv4 partition without a family option'
);
is_deeply(
    [ xCAT::DSHCore->fping_ping_command( 6, {}, ['2001:db8::20'] ) ],
    [],
    'no fping on the host gives no command, so pping reports noping'
);

done_testing();
