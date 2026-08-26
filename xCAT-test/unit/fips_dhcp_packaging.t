#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

foreach my $spec ('xCAT/xCAT.spec', 'xCATsn/xCATsn.spec') {
    my $source = slurp_repo_file($spec);
    like(
        $source,
        qr{
            Requires:\ \(kea\ if\ \(system-release\ >=\ 10\)\ else\ /usr/sbin/dhcpd\)\n
            Requires:\ \(kea-hooks\ if\ \(system-release\ >=\ 10\)\)\n
            %if\ 0%\{\?rhel\}\ ==\ 8\n
            \#\ EL8[^\n]*\n
            Requires:\ dhcp-server\ >=\ 12:4\.3\.6-48\n
            %endif
        }x,
        "$spec requires the EL8 non-MD5 OMAPI backport"
    );
}

done_testing();
