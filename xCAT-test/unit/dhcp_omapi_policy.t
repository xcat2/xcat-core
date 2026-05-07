#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::OmapiPolicy;

my $defaults = xCAT::DHCP::OmapiPolicy->settings( site_values => {} );
is( $defaults->{algorithm},
    'hmac-md5', 'default OMAPI algorithm remains hmac-md5' );
is( $defaults->{key_name}, 'xcat_key',
    'default OMAPI key name remains xcat_key' );
is( $defaults->{omshell_path},
    '/usr/bin/omshell', 'default omshell path remains /usr/bin/omshell' );
ok(
    !$defaults->{needs_omshell_key_algorithm},
    'default MD5 does not emit key-algorithm'
);
is(
    xCAT::DHCP::OmapiPolicy->omshell_preamble(
        $defaults, secret => 'legacy-secret'
    ),
    "key xcat_key \"legacy-secret\"\n",
    'default omshell preamble keeps legacy key command without key-algorithm'
);

my $sha512 = xCAT::DHCP::OmapiPolicy->settings(
    site_values => {
        dhcpomapialgorithm => ' HMAC-SHA512 ',
        dhcpomapikeyname   => 'external.key-name',
        dhcpomshellpath    => '/opt/dhcp/bin/omshell',
    }
);
is( $sha512->{algorithm},   'hmac-sha512',    'algorithm is canonicalized' );
is( $sha512->{key_rr_type}, 165,              'SHA512 KEY RR type is mapped' );
is( $sha512->{key_name}, 'external.key-name', 'custom key name is accepted' );
is( $sha512->{key_name_for_regex},
    'external\\.key\\-name',
    'custom key name is escaped for named.conf matching' );
is( $sha512->{omshell_path},
    '/opt/dhcp/bin/omshell', 'custom absolute omshell path is accepted' );
ok(
    $sha512->{needs_omshell_key_algorithm},
    'non-MD5 emits key-algorithm for omshell'
);
is(
    xCAT::DHCP::OmapiPolicy->omshell_preamble(
        $sha512,
        secret => 'secret==',
        port   => 7912,
        server => '192.0.2.10'
    ),
"port 7912\nkey-algorithm hmac-sha512\nkey external.key-name \"secret==\"\nserver 192.0.2.10\n",
    'omshell preamble includes port, algorithm, key, and server in order'
);
is( xCAT::DHCP::OmapiPolicy->key_owner($sha512),
    'external.key-name.', 'DNS key owner is fully qualified' );

like(
    xCAT::DHCP::OmapiPolicy->settings(
        site_values => { dhcpomapialgorithm => 'sha512' }
    )->{error},
    qr/site\.dhcpomapialgorithm/,
    'invalid algorithm is rejected'
);

like(
    xCAT::DHCP::OmapiPolicy->settings(
        site_values => { dhcpomapikeyname => 'bad;name' }
    )->{error},
    qr/site\.dhcpomapikeyname/,
    'unsafe key name is rejected'
);

like(
    xCAT::DHCP::OmapiPolicy->settings(
        site_values => { dhcpomshellpath => 'omshell' }
    )->{error},
    qr/site\.dhcpomshellpath/,
    'relative omshell path is rejected'
);

like(
    xCAT::DHCP::OmapiPolicy->settings(
        site_values => { dhcpomshellpath => '/tmp/omshell;touch' }
    )->{error},
    qr/site\.dhcpomshellpath/,
    'shell metacharacters are rejected from omshell path'
);

done_testing();
