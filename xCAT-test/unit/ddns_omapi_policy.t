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

sub omapi_settings {
    my (%overrides) = @_;
    return xCAT::DHCP::OmapiPolicy->settings(
        site_values => {
            dhcpomapialgorithm => undef,
            dhcpomapikeyname   => undef,
            dhcpomshellpath    => undef,
            %overrides,
        }
    );
}

# Model a populated xCAT site and require each fixture to override it fully.
our %XCATSITEVALS;
local %XCATSITEVALS = (
    dhcpomapialgorithm => 'hmac-sha256',
    dhcpomapikeyname   => 'site-key',
    dhcpomshellpath    => '/opt/site/bin/omshell',
);

my $defaults = omapi_settings();
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

my $sha512 = omapi_settings(
    dhcpomapialgorithm => 'hmac-sha512',
    dhcpomapikeyname   => 'provider.key',
);

is(
    xCAT_plugin::ddns::ddns_tsig_algorithm(
        {
            omapi_settings => $sha512,
        }
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
