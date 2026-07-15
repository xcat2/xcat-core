#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG}  ||= 'SQLite:/tmp';
$ENV{XCATROOT} ||= "$FindBin::Bin/../../xCAT-server";

my $source_ddns_plugin =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/ddns.pm";
if ( -f $source_ddns_plugin ) {
    require $source_ddns_plugin;
}
else {
    require xCAT_plugin::ddns;
}

my $defaults = xCAT::DHCP::OmapiPolicy->settings(
    site_values => {},
    fips_mode   => 0,
);
is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $defaults,
            privkey        => 'legacy-secret',
        }
    ),
"key \"xcat_key\" {\n\talgorithm hmac-md5;\n\tsecret \"legacy-secret\";\n};\n\n",
    'default DDNS key remains xcat_key with hmac-md5'
);

my $fips_defaults = xCAT::DHCP::OmapiPolicy->settings(
    site_values => {},
    fips_mode   => 1,
);
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $fips_defaults,
        },
        1.35
    ),
    'hmac-sha256',
    'FIPS DDNS does not fall back to hmac-md5 on old Net::DNS'
);
is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $fips_defaults,
            privkey        => 'fips-secret',
        }
    ),
"key \"xcat_key\" {\n\talgorithm hmac-sha256;\n\tsecret \"fips-secret\";\n};\n\n",
    'FIPS DDNS key uses hmac-sha256'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, ' HMAC-SHA512 ', 1.35
    ),
    { algorithm => 'hmac-sha512', replace => 0 },
    'FIPS mode preserves an existing supported non-MD5 algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, 'hmac-md5', 1.36
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode replaces an existing MD5 key'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, 'hmac-unknown', 1.36
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode replaces an unsupported key algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $fips_defaults, undef, 1.36
    ),
    { algorithm => 'hmac-sha256', replace => 1 },
    'FIPS mode repairs a key block without an algorithm'
);
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $fips_defaults,
            tsig_algorithm => 'hmac-sha512',
        },
        1.35
    ),
    'hmac-sha512',
    'FIPS DDNS signs with the preserved algorithm'
);

my $sha512 = xCAT::DHCP::OmapiPolicy->settings(
    site_values => {
        dhcpomapialgorithm => 'hmac-sha512',
        dhcpomapikeyname   => 'provider.key',
    },
    fips_mode => 0,
);

is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $sha512, 'hmac-sha256', 1.35
    ),
    { algorithm => 'hmac-sha512', replace => 1 },
    'an explicit site algorithm replaces a different existing algorithm'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $defaults, 'hmac-sha512', 1.35
    ),
    { algorithm => 'hmac-md5', replace => 1 },
    'old Net::DNS retains the legacy MD5 fallback outside FIPS mode'
);
is_deeply(
    xCAT_plugin::ddns::ddns_reconcile_key_algorithm(
        $defaults, 'hmac-sha512', 1.36
    ),
    { algorithm => 'hmac-sha512', replace => 0 },
    'new Net::DNS preserves the existing algorithm outside FIPS mode'
);
is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $defaults,
        },
        1.35
    ),
    'hmac-md5',
    'old Net::DNS uses the legacy MD5 default outside FIPS mode'
);

is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $sha512,
        },
        1.35
    ),
    'hmac-sha512',
    'explicit non-MD5 DDNS algorithm is honored'
);

is(
    xCAT_plugin::ddns::ddns_key_contents(
        {
            omapi_settings => $sha512,
            privkey        => 'provider-secret',
        }
    ),
"key \"provider.key\" {\n\talgorithm hmac-sha512;\n\tsecret \"provider-secret\";\n};\n\n",
    'custom DDNS key name and algorithm are rendered'
);

done_testing();
