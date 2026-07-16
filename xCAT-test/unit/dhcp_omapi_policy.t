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

is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        platform       => 'el9'
    ),
    'hmac-sha256',
    'new EL9 installations default to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        platform       => 'el8'
    ),
    undef,
    'new EL8 installations retain the implicit MD5 default'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        platform       => 'el10'
    ),
    'hmac-sha256',
    'new EL10 installations default DDNS TSIG to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 0,
        platform       => 'el9'
    ),
    undef,
    'existing EL9 installations retain their key algorithm choice'
);

is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        os             => 'ubuntu,18.04'
    ),
    undef,
    'new Ubuntu 18.04 installations retain the implicit MD5 default'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        os             => 'ubuntu,20.04'
    ),
    'hmac-sha256',
    'new Ubuntu 20.04 installations default to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        os             => 'ubuntu,20.04.6'
    ),
    'hmac-sha256',
    'Ubuntu 20.04 point releases default to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        os             => 'ubuntu,22.04'
    ),
    'hmac-sha256',
    'new Ubuntu 22.04 installations default to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        os             => 'ubuntu,24.04'
    ),
    'hmac-sha256',
    'new Ubuntu 24.04 installations default to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 1,
        os             => 'ubuntu,26.04'
    ),
    'hmac-sha256',
    'newer Ubuntu installations default to hmac-sha256'
);
is(
    xCAT::DHCP::OmapiPolicy->new_install_default_algorithm(
        is_new_install => 0,
        os             => 'ubuntu,24.04'
    ),
    undef,
    'existing Ubuntu installations retain their key algorithm choice'
);

my $explicit_md5 = xCAT::DHCP::OmapiPolicy->settings(
    site_values => { dhcpomapialgorithm => 'hmac-md5' }
);
is( $explicit_md5->{algorithm}, 'hmac-md5',
    'an explicit hmac-md5 setting remains supported' );
ok( $explicit_md5->{algorithm_explicit},
    'an explicit hmac-md5 setting remains marked as explicit' );
ok( !$explicit_md5->{needs_omshell_key_algorithm},
    'explicit MD5 keeps the legacy omshell command format' );

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
