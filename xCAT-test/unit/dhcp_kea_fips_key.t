#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server";
    $ENV{XCATCFG} = 'SQLite:' . tempdir(CLEANUP => 1);
}

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
require $plugin;

my $directory = tempdir(CLEANUP => 1);
local $xCAT_plugin::dhcp::kea_ddns_key_path = "$directory/ddns.key";
our %XCATSITEVALS;
local %XCATSITEVALS = (dnshandler => 'ddns');

{
    package Local::KeaKeyTable;
    sub getAttribs { return { password => 'table-secret' }; }
    sub getAllAttribs { return; }
    sub close { return; }
}

{
    no warnings qw(redefine once);
    local *xCAT::Table::new = sub { return bless {}, 'Local::KeaKeyTable'; };
    local *xCAT::Utils::isFIPS = sub { return 1; };

    is_deeply([xCAT_plugin::dhcp::kea_ddns_key()], ['HMAC-SHA256', 'table-secret'],
        'a FIPS service node uses SHA-256 with the shared table secret');

    $XCATSITEVALS{dhcpomapialgorithm} = 'hmac-md5';
    my ($algorithm, $secret, $error) = xCAT_plugin::dhcp::kea_ddns_key();
    ok(!defined($algorithm) && !defined($secret),
        'a rejected policy provides no key material');
    like($error, qr/hmac-md5 is not allowed/, 'the FIPS policy error is retained');
    like(xCAT_plugin::dhcp::kea_build_ddns_intent()->{error},
        qr/hmac-md5 is not allowed/, 'Kea intent reports the policy error');

    delete $XCATSITEVALS{dhcpomapialgorithm};
    write_text($xCAT_plugin::dhcp::kea_ddns_key_path,
        "key \"xcat_key\" { algorithm hmac-md5; secret \"file-secret\"; };\n");
    my @key = xCAT_plugin::dhcp::kea_ddns_key();
    like($key[2], qr/HMAC-MD5.*FIPS/, 'FIPS rejects a stale MD5 key file');
    like(xCAT_plugin::dhcp::kea_build_ddns_intent()->{error},
        qr/makedns -n/, 'the stale-key error identifies the regeneration command');

    write_text($xCAT_plugin::dhcp::kea_ddns_key_path,
        "key \"xcat_key\" { algorithm hmac-sha256; secret \"file-secret\"; };\n");
    is_deeply([xCAT_plugin::dhcp::kea_ddns_key()], ['HMAC-SHA256', 'file-secret'],
        'FIPS accepts the regenerated SHA-256 key file');
}

{
    no warnings qw(redefine once);
    local *xCAT::Utils::isFIPS = sub { return 0; };
    write_text($xCAT_plugin::dhcp::kea_ddns_key_path,
        "key \"xcat_key\" { algorithm hmac-md5; secret \"legacy-secret\"; };\n");
    is_deeply([xCAT_plugin::dhcp::kea_ddns_key()], ['HMAC-MD5', 'legacy-secret'],
        'non-FIPS installations retain existing MD5 key files');
}

done_testing();
