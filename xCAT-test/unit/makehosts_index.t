#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

BEGIN {
    package xCAT::Table;
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;
}

my $source_hosts_plugin =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/hosts.pm";
require $source_hosts_plugin;

sub set_host_lines
{
    return xCAT_plugin::hosts::_set_host_lines([@_]);
}

{
    my $lines = set_host_lines(
        "127.0.0.1 localhost\n",
        "# retained comment\n",
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node01', '10.0.0.1', 'alias1 alias2', 'cluster.test'
    );

    is_deeply(
        $lines,
        [
            "127.0.0.1 localhost\n",
            "# retained comment\n",
            "10.0.0.1 node01 node01.cluster.test alias1 alias2\n",
        ],
        'new host is appended without changing unrelated lines'
    );
}

{
    my $lines = set_host_lines(
        "10.0.0.1 node01 node01.cluster.test oldalias\n",
        "10.0.0.2 other other.cluster.test\n",
        "10.0.0.3 node01 node01.other.test\n",
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node01', '10.0.0.2', 'newalias', 'cluster.test'
    );

    is_deeply(
        $lines,
        [
            "10.0.0.2 node01 node01.cluster.test newalias\n",
            '',
            '',
        ],
        'first IP or primary-name match is updated and later duplicates are removed'
    );
}

{
    my $lines = set_host_lines(
        "10.0.0.1 node01.cluster.test node01\n",
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node01', '10.0.0.9', '', 'cluster.test'
    );

    is(
        $lines->[0],
        "10.0.0.9 node01 node01.cluster.test \n",
        'short node matches an existing FQDN-first entry'
    );
}

{
    my $lines = set_host_lines(
        "10.0.0.1 node01 node01.cluster.test\n",
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node01-bmc', '10.0.0.1', 'bmc-alias', 'cluster.test', 1
    );
    is(
        $lines->[0],
        "10.0.0.1 node01 node01.cluster.test bmc-alias\n",
        'NIC entry keeps the existing primary node when matching by IP'
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node01', '10.0.0.9', '', 'cluster.test'
    );
    is(
        $lines->[0],
        "10.0.0.9 node01 node01.cluster.test \n",
        'updated line remains indexed for the next host change'
    );
}

{
    my $lines = set_host_lines(
        "10.0.0.1 node01 node01.cluster.test\n",
        "10.0.0.2 node02 node02.cluster.test\n",
        "10.0.0.3 node01 node01.other.test\n",
    );

    xCAT_plugin::hosts::delnode('node01', '10.0.0.2', '', 'cluster.test');
    is_deeply(
        $lines,
        ['', '', ''],
        'delete removes every IP or primary-name match'
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node01', '10.0.0.2', '', 'cluster.test'
    );
    is_deeply(
        $lines,
        ['', '', '', "10.0.0.2 node01 node01.cluster.test \n"],
        'deleted lines are removed from the indexes before a later append'
    );
}

{
    my $lines = set_host_lines(
        "fe80::1 node01 node01.cluster.test\n",
        "10.0.0.1 \n",
    );

    xCAT_plugin::hosts::addnode(
        undef, 'node02', 'fe80::1', '', 'cluster.test'
    );
    xCAT_plugin::hosts::addnode(
        undef, 'node03', '10.0.0.1', '', 'cluster.test'
    );

    is_deeply(
        $lines,
        [
            "fe80::1 node02 node02.cluster.test \n",
            "10.0.0.1 node03 node03.cluster.test \n",
        ],
        'IP index handles IPv6 addresses and entries without a primary name'
    );
}

done_testing();
