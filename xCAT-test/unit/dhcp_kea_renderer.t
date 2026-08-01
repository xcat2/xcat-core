use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw/tempdir/;
use JSON;
use Test::More;

use xCAT::DHCP::Backend::Kea;

my $backend = xCAT::DHCP::Backend::Kea->new( kea_version => '2.4.1' );

my @additional_class_syntax_cases = (
    [ '2.7.3',       0, 'Kea release below 2.7.4 uses legacy additional-class fields' ],
    [ '2.7.4',       1, 'Kea 2.7.4 uses modern additional-class fields' ],
    [ '2.10',        1, 'Kea two-digit minor release uses modern additional-class fields' ],
    [ '2.7',         0, 'Kea release with fewer components stays below 2.7.4' ],
    [ '2.7.4.0',     1, 'Kea release with a trailing zero component meets the minimum' ],
    [ '2.7.4-rc1',   1, 'Kea suffix above the 2.7.4 numeric core keeps modern fields' ],
    [ '2.7.3-rc1',   0, 'Kea suffix below the 2.7.4 numeric core keeps legacy fields' ],
    [ '',            0, 'empty Kea version keeps legacy additional-class fields' ],
    [ 'not-a-version', 0, 'malformed Kea version keeps legacy additional-class fields' ],
    [ '2.7foo',      0, 'digit-leading malformed Kea version keeps legacy additional-class fields' ],
    [ 'v2.7.4',      0, 'prefixed Kea version keeps legacy additional-class fields' ],
);

foreach my $case (@additional_class_syntax_cases) {
    my ( $version, $modern, $description ) = @$case;
    my $version_backend = xCAT::DHCP::Backend::Kea->new( kea_version => $version );
    is( $version_backend->_use_modern_additional_class_syntax(), $modern, $description );
}

my $unit_dir = tempdir( CLEANUP => 1 );
foreach my $unit (qw/kea-dhcp4-server.service kea-dhcp6-server.service kea-dhcp-ddns-server.service kea-ctrl-agent.service/) {
    open( my $unit_fh, '>', "$unit_dir/$unit" ) or die "Unable to write $unit_dir/$unit: $!";
    close($unit_fh);
}
my $service_backend = xCAT::DHCP::Backend::Kea->new( service_unit_dirs => [$unit_dir] );
is( $service_backend->_kea_service('kea-dhcp4'),      'kea-dhcp4-server',      'Debian-style DHCPv4 service name is detected' );
is( $service_backend->_kea_service('kea-dhcp6'),      'kea-dhcp6-server',      'Debian-style DHCPv6 service name is detected' );
is( $service_backend->_kea_service('kea-dhcp-ddns'),  'kea-dhcp-ddns-server',  'Debian-style DHCP-DDNS service name is detected' );
is( $service_backend->_kea_service('kea-ctrl-agent'), 'kea-ctrl-agent',        'control agent service keeps canonical name' );

open( my $canonical_unit_fh, '>', "$unit_dir/kea-dhcp4.service" ) or die "Unable to write canonical Kea unit: $!";
close($canonical_unit_fh);
is( $service_backend->_kea_service('kea-dhcp4'), 'kea-dhcp4', 'canonical Kea service name is preferred when present' );

my $json = $backend->render_dhcp4_config(
    {
        interfaces     => ['eth0'],
        valid_lifetime => '600',
        subnets        => [
            {
                id           => '1',
                subnet       => '10.0.0.0/24',
                interface    => 'eth0',
                dynamicrange => '10.0.0.100-10.0.0.120;10.0.0.130,10.0.0.140',
                next_server  => '10.0.0.1',
                additional_client_classes => ['xcat-opal-v3-10.0.0.0-24'],
                option_data  => [
                    { name => 'routers',             data => '10.0.0.1' },
                    { name => 'domain-name-servers', data => '10.0.0.2, 10.0.0.3' },
                    { name => 'domain-name',         data => 'cluster.example.com' },
                ],
                reservations => [
                    {
                        'hw-address' => 'aa:bb:cc:dd:ee:ff',
                        'ip-address' => '10.0.0.10',
                        hostname     => 'node01',
                    },
                ],
            },
        ],
        'client-classes' => [
            {
                name             => 'xcat-uefi-x64',
                test             => 'option[93].hex == 0x0007',
                'boot-file-name' => 'xcat/xnba.efi',
            },
            {
                name            => 'xcat-opal-v3-10.0.0.0-24',
                test            => 'option[93].hex == 0x000e',
                additional_only => JSON::true,
                'option-data'   => [
                    { name => 'conf-file', data => 'http://10.0.0.1/tftpboot/pxelinux.cfg/p/10.0.0.0_24' },
                ],
            },
        ],
    }
);

my $config = decode_json($json);
ok( $config->{Dhcp4}, 'renderer creates a Dhcp4 document' );
is_deeply( $config->{Dhcp4}{'interfaces-config'}{interfaces}, ['eth0'], 'interfaces are rendered' );
is( $config->{Dhcp4}{'valid-lifetime'}, 600, 'valid lifetime is rendered' );
is( $config->{Dhcp4}{'lease-database'}{type}, 'memfile', 'memfile lease backend is the default' );
is( $config->{Dhcp4}{'reservations-in-subnet'}, JSON::true, 'subnet host reservations are enabled by default' );
is( $config->{Dhcp4}{'reservations-out-of-pool'}, JSON::true, 'out-of-pool host reservations are enabled for xCAT static addresses' );
is( $config->{Dhcp4}{'match-client-id'}, JSON::false, 'DHCPv4 leases match MAC reservations when client-id changes across boot stages' );

my $subnet = $config->{Dhcp4}{subnet4}[0];
is( $subnet->{id}, 1, 'subnet id is rendered' );
is( $subnet->{subnet}, '10.0.0.0/24', 'subnet CIDR is rendered' );
is( $subnet->{interface}, 'eth0', 'subnet interface is rendered' );
is( $subnet->{'next-server'}, '10.0.0.1', 'next-server is rendered' );

is_deeply(
    $subnet->{pools},
    [
        { pool => '10.0.0.100 - 10.0.0.120' },
        { pool => '10.0.0.130 - 10.0.0.140' },
    ],
    'dynamicrange is rendered as Kea pools'
);

is_deeply(
    $subnet->{'option-data'},
    [
        { name => 'routers',             data => '10.0.0.1' },
        { name => 'domain-name-servers', data => '10.0.0.2, 10.0.0.3' },
        { name => 'domain-name',         data => 'cluster.example.com' },
    ],
    'subnet option-data is preserved'
);
is_deeply(
    $subnet->{'require-client-classes'},
    ['xcat-opal-v3-10.0.0.0-24'],
    'subnet requests second-pass OPAL class evaluation for subnet-specific conf-file'
);

is_deeply(
    $subnet->{reservations},
    [
        {
            'hw-address' => 'aa:bb:cc:dd:ee:ff',
            'ip-address' => '10.0.0.10',
            hostname     => 'node01',
        },
    ],
    'host reservations are preserved'
);

is_deeply(
    $config->{Dhcp4}{'client-classes'},
    [
        {
            name             => 'xcat-uefi-x64',
            test             => 'option[93].hex == 0x0007',
            'boot-file-name' => 'xcat/xnba.efi',
        },
        {
            name               => 'xcat-opal-v3-10.0.0.0-24',
            test               => 'option[93].hex == 0x000e',
            'only-if-required' => JSON::true,
            'option-data'      => [
                { name => 'conf-file', data => 'http://10.0.0.1/tftpboot/pxelinux.cfg/p/10.0.0.0_24' },
            ],
        },
    ],
    'client classes are preserved, including subnet-specific OPAL conf-file class'
);

my $modern_backend = xCAT::DHCP::Backend::Kea->new( kea_version => '3.0.1' );
my $modern_json = $modern_backend->render_dhcp4_config(
    {
        subnets => [
            {
                id                        => 3,
                subnet                    => '10.0.2.0/24',
                pools                     => [],
                additional_client_classes => ['xcat-opal-v3-10.0.2.0-24'],
            },
        ],
        'client-classes' => [
            {
                name            => 'xcat-opal-v3-10.0.2.0-24',
                test            => 'option[93].hex == 0x000e',
                additional_only => JSON::true,
            },
        ],
    }
);
my $modern_config = decode_json($modern_json);
my $modern_subnet = $modern_config->{Dhcp4}{subnet4}[0];
my $modern_class  = $modern_config->{Dhcp4}{'client-classes'}[0];
is_deeply(
    $modern_subnet->{'evaluate-additional-classes'},
    ['xcat-opal-v3-10.0.2.0-24'],
    'Kea 3.x renders modern subnet additional-class evaluation field'
);
ok( !exists $modern_subnet->{'require-client-classes'}, 'Kea 3.x output omits deprecated subnet additional-class field' );
is( $modern_class->{'only-in-additional-list'}, JSON::true, 'Kea 3.x renders modern class additional-evaluation flag' );
ok( !exists $modern_class->{'only-if-required'}, 'Kea 3.x output omits deprecated class additional-evaluation flag' );

my $empty_boot_json = $backend->render_dhcp4_config(
    {
        subnets => [
            {
                id             => 2,
                subnet         => '10.0.1.0/24',
                pools          => [],
                next_server    => '0.0.0.0',
                boot_file_name => '',
            },
        ],
    }
);
my $empty_boot_subnet = decode_json($empty_boot_json)->{Dhcp4}{subnet4}[0];
is( $empty_boot_subnet->{'next-server'}, '0.0.0.0', 'false-looking next-server value is preserved' );
is( $empty_boot_subnet->{'boot-file-name'}, '', 'empty boot-file-name is preserved' );

my $reservation_policy_json = $backend->render_dhcp4_config(
    {
        'reservations-in-subnet'   => 0,
        'reservations-out-of-pool' => 0,
        'match-client-id'          => 1,
        subnets => [
            {
                id     => 9,
                subnet => '10.0.9.0/24',
                pools  => [],
            },
        ],
    }
);
my $reservation_policy_config = decode_json($reservation_policy_json);
is( $reservation_policy_config->{Dhcp4}{'reservations-in-subnet'}, JSON::false, 'reservation in-subnet policy can be overridden' );
is( $reservation_policy_config->{Dhcp4}{'reservations-out-of-pool'}, JSON::false, 'reservation out-of-pool policy can be overridden' );
is( $reservation_policy_config->{Dhcp4}{'match-client-id'}, JSON::true, 'client-id lease matching policy can be overridden' );

my $client_id_policy_json = $backend->render_dhcp4_config(
    {
        interfaces        => ['eth0'],
        match_client_id   => 1,
        subnets           => [],
    }
);
my $client_id_policy_config = decode_json($client_id_policy_json);
is( $client_id_policy_config->{Dhcp4}{'match-client-id'}, JSON::true, 'DHCPv4 client-id matching can be explicitly restored' );

my $comment_dir = tempdir(CLEANUP => 1);
my $commented_config = "$comment_dir/kea-dhcp4.conf";
my $commented_content = <<'COMMENTED_JSON';
// Packaged Kea configs may contain comments before xCAT rewrites them.
{
  "Dhcp4": {
    "valid-lifetime": 600,
    "subnet4": [
      {
        "id": 1,
        "subnet": "10.20.0.0/24",
        "pools": [], // Keep URLs such as "http://server/path" intact.
      }
    ],
    "loggers": [
      {
        "name": "kea-dhcp4",
        "output-options": [
          {
            "output": "stdout",
            "pattern": "%-5p %m\n",
            // "flush": false
          },
        ],
      },
    ],
  }
}
COMMENTED_JSON
open( my $comment_fh, '>', $commented_config ) or die "Unable to write $commented_config: $!";
print {$comment_fh} $commented_content;
close($comment_fh);
my $loaded_commented = $backend->load_dhcp4_config($commented_config);
ok( !$loaded_commented->{error}, 'Kea DHCPv4 loader accepts packaged JSON comments' );
is( $loaded_commented->{Dhcp4}{subnet4}[0]{subnet}, '10.20.0.0/24', 'commented Kea config is decoded' );

my $reservation_config = decode_json(
    $backend->render_dhcp4_config(
        {
            subnets => [
                {
                    id     => 10,
                    subnet => '10.10.0.0/24',
                    pools  => [],
                },
            ],
        }
    )
);

$backend->upsert_reservations(
    $reservation_config,
    [
        {
            'subnet-id'  => 10,
            'hw-address' => '00:11:22:33:44:55',
            'ip-address' => '10.10.0.12',
            hostname     => 'node12',
        },
    ]
);
is( scalar @{ $reservation_config->{Dhcp4}{subnet4}[0]{reservations} }, 1, 'reservation is added to matching subnet' );
is_deeply( $reservation_config->{Dhcp4}{subnet4}[0]{pools}, [], 'out-of-pool static reservation does not require a dynamic pool' );

$backend->upsert_reservations(
    $reservation_config,
    [
        {
            'subnet-id'  => 10,
            'hw-address' => '00:11:22:33:44:55',
            'ip-address' => '10.10.0.13',
            hostname     => 'node12',
        },
    ]
);
is( scalar @{ $reservation_config->{Dhcp4}{subnet4}[0]{reservations} }, 1, 'matching reservation is replaced, not duplicated' );
is( $reservation_config->{Dhcp4}{subnet4}[0]{reservations}[0]{'ip-address'}, '10.10.0.13', 'replacement reservation is stored' );

my $subnet_id = $backend->subnet_id_for_ip( $reservation_config, '10.10.0.13' );
is( $subnet_id, 10, 'subnet lookup by IPv4 address finds the reservation subnet' );

my $found = $backend->query_reservations( $reservation_config, { hostname => 'node12' } );
is( scalar @$found, 1, 'reservation query finds hostname match' );
is( $found->[0]{'subnet-id'}, 10, 'reservation query includes subnet id' );

my $deleted = $backend->delete_reservations( $reservation_config, { 'hw-address' => '00:11:22:33:44:55' } );
is( scalar @$deleted, 1, 'reservation delete returns deleted reservation' );
is( scalar @{ $reservation_config->{Dhcp4}{subnet4}[0]{reservations} }, 0, 'reservation is removed from config' );

my $hookdir = tempdir(CLEANUP => 1);
my $hook = "$hookdir/libdhcp_host_cmds.so";
open(my $hookfh, '>', $hook) or die "Unable to create fake hook: $!";
close($hookfh);
is( $backend->host_cmds_hook_path($hook), $hook, 'host commands hook lookup accepts an explicit existing path' );
my $backend_without_default_hooks = xCAT::DHCP::Backend::Kea->new(host_cmds_hook_paths => []);
is( $backend_without_default_hooks->host_cmds_hook_path("$hookdir/missing.so"), undef, 'host commands hook lookup returns undef when no hook exists' );

my $backupdir = tempdir(CLEANUP => 1);
my $config_path = "$backupdir/kea-dhcp4.conf";
open(my $configfh, '>', $config_path) or die "Unable to create fake config: $!";
print $configfh '{"old":true}';
close($configfh);
my $write_result = $backend->write_dhcp4_json('{"new":true}', path => $config_path, skip_validate => 1, backup_existing => 1);
ok( !$write_result->{error}, 'write_dhcp4_json succeeds with backup_existing' );
is( $write_result->{backup}, "$config_path.xcatbak", 'backup path is reported' );
my $config_mode = ( stat($config_path) )[2] & oct('7777');
ok( $config_mode == oct('640') || $config_mode == oct('644'), 'written config is readable by the Kea service user' );
open(my $backupfh, '<', "$config_path.xcatbak") or die "Unable to read backup config: $!";
my $backup_content = <$backupfh>;
close($backupfh);
is( $backup_content, '{"old":true}', 'existing Kea config is backed up before replacement' );

my $dhcp6_json = $backend->render_dhcp6_config(
    {
        interfaces       => ['eth0'],
        valid_lifetime   => '700',
        preferred_lifetime => '500',
        subnets    => [
            {
                id           => '11',
                subnet       => '2001:db8:1::/64',
                dynamicrange => '2001:db8:1::100/120',
                option_data  => [
                    { name => 'dns-servers',   data => '2001:db8:1::1' },
                    { name => 'domain-search', data => 'cluster.example.com' },
                ],
                reservations => [
                    {
                        duid           => '00:04:52:54:00:12:34:56',
                        'ip-addresses' => ['2001:db8:1::50'],
                        hostname       => 'nodev6',
                    },
                ],
            },
        ],
    }
);
my $dhcp6_config = decode_json($dhcp6_json);
ok( $dhcp6_config->{Dhcp6}, 'renderer creates a Dhcp6 document' );
is( $dhcp6_config->{Dhcp6}{subnet6}[0]{subnet}, '2001:db8:1::/64', 'DHCPv6 subnet is rendered' );
is( $dhcp6_config->{Dhcp6}{'valid-lifetime'}, 700, 'DHCPv6 valid lifetime is numeric' );
is( $dhcp6_config->{Dhcp6}{'preferred-lifetime'}, 500, 'DHCPv6 preferred lifetime is numeric' );
is( $dhcp6_config->{Dhcp6}{subnet6}[0]{id}, 11, 'DHCPv6 subnet id is numeric' );
is( $dhcp6_config->{Dhcp6}{subnet6}[0]{reservations}[0]{duid}, '00:04:52:54:00:12:34:56', 'DHCPv6 DUID reservation is rendered' );

my $ddns_json = $backend->render_ddns_config(
    {
        port => '53001',
        'dns-server-timeout' => '500',
        'tsig-keys' => [
            { name => 'xcat_key', algorithm => 'HMAC-SHA256', secret => 'abc123==' },
        ],
        forward_domains => [
            {
                name          => 'cluster.example.com.',
                'key-name'    => 'xcat_key',
                'dns-servers' => [ { 'ip-address' => '10.0.0.1', port => 53 } ],
            },
        ],
        reverse_domains => [
            {
                name          => '0.0.10.in-addr.arpa.',
                'key-name'    => 'xcat_key',
                'dns-servers' => [ { 'ip-address' => '10.0.0.1', port => 53 } ],
            },
        ],
    }
);
my $ddns_config = decode_json($ddns_json);
ok( $ddns_config->{DhcpDdns}, 'renderer creates a DhcpDdns document' );
is( $ddns_config->{DhcpDdns}{port}, 53001, 'DDNS port is numeric' );
is( $ddns_config->{DhcpDdns}{'dns-server-timeout'}, 500, 'DDNS timeout is numeric' );
is( $ddns_config->{DhcpDdns}{'forward-ddns'}{'ddns-domains'}[0]{name}, 'cluster.example.com.', 'DDNS forward domain is rendered' );

my $ctrl_agent_backend = xCAT::DHCP::Backend::Kea->new( kea_socket_dirs => [] );
my $ctrl_agent_config = decode_json($ctrl_agent_backend->render_ctrl_agent_config({ 'http-port' => '8000' }));
is( $ctrl_agent_config->{'Control-agent'}{'http-port'}, 8000, 'Control Agent HTTP port is numeric' );

my $runtime_socket_dir = "$unit_dir/run/kea";
mkdir "$unit_dir/run" or die "Unable to create $unit_dir/run: $!";
mkdir $runtime_socket_dir or die "Unable to create $runtime_socket_dir: $!";

my $runtime_socket_backend = xCAT::DHCP::Backend::Kea->new( kea_socket_dirs => [ $runtime_socket_dir, "$unit_dir/var/run/kea" ] );
my $runtime_socket_config = decode_json($runtime_socket_backend->render_ctrl_agent_config({}));
is( $runtime_socket_config->{'Control-agent'}{'control-sockets'}{dhcp4}{'socket-name'}, "$runtime_socket_dir/kea4-ctrl-socket", 'Control Agent socket uses the detected runtime directory' );

my $legacy_socket_backend = xCAT::DHCP::Backend::Kea->new( kea_socket_dirs => [] );
my $legacy_socket_config = decode_json($legacy_socket_backend->render_ctrl_agent_config({}));
is( $legacy_socket_config->{'Control-agent'}{'control-sockets'}{dhcp4}{'socket-name'}, '/var/run/kea/kea4-ctrl-socket', 'Control Agent socket falls back to the legacy runtime path when no runtime directory exists' );

my $meson_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => 'Build Options: -Dprefix=/usr -Dlocalstatedir=/var -Drunstatedir=/xcat-test-meson-run',
);
is( $meson_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-meson-run/kea/kea4-ctrl-socket', 'Meson runstatedir selects the socket path before the runtime directory exists' );

my $autoconf_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => q{Configure arguments: '--prefix=/usr' '--localstatedir=/var' '--runstatedir=/xcat-test-autoconf-run'},
);
is( $autoconf_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-autoconf-run/kea/kea4-ctrl-socket', 'Autoconf runstatedir selects the socket path before the runtime directory exists' );

my $local_state_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => q{Configure arguments: '--prefix=/usr' '--localstatedir=/xcat-test-local-state'},
);
is( $local_state_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-local-state/run/kea/kea4-ctrl-socket', 'localstatedir supplies the runtime path when runstatedir is not configured' );

my $variable_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => q{Configure arguments:
  '--prefix=/usr/local' '--localstatedir=${prefix}/var' '--runstatedir=${localstatedir}/run'},
);
is( $variable_socket_backend->control_socket_path('kea4-ctrl-socket'), '/usr/local/var/run/kea/kea4-ctrl-socket', 'Autoconf build variables resolve through the configured prefix' );

my $undefined_candidates_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_socket_dirs => undef,
    kea_build_report => 'Build Options: -Dprefix=/usr -Drunstatedir=/xcat-test-undefined-candidates',
);
is( $undefined_candidates_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-undefined-candidates/kea/kea4-ctrl-socket', 'undefined socket candidates preserve build-report detection' );

my $source_default_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => 'Prefix: /usr/local',
);
is( $source_default_socket_backend->control_socket_path('kea4-ctrl-socket'), '/usr/local/var/run/kea/kea4-ctrl-socket', 'source build defaults resolve through the configured prefix' );

my $meson_default_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => "Meson Version: 1.10.1\nBuild Options: -Dprefix=/usr",
);
is( $meson_default_socket_backend->control_socket_path('kea4-ctrl-socket'), '/var/run/kea/kea4-ctrl-socket', 'Meson system prefix defaults local state to /var' );

my $meson_local_default_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => "Prefix: /usr/local\nMeson Version: 1.10.1\nBuild Options:\n\nC++ Compiler:\n",
);
is( $meson_local_default_socket_backend->control_socket_path('kea4-ctrl-socket'), '/usr/local/var/run/kea/kea4-ctrl-socket', 'Kea keeps local state prefix-relative for a Meson local prefix' );

my $meson_local_override_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => "Prefix: /usr/local\nMeson Version: 1.10.1\nBuild Options: -Dprefix=/usr/local -Dlocalstatedir=/srv/kea -Drunstatedir=/run/kea-custom\n",
);
is( $meson_local_override_socket_backend->control_socket_path('kea4-ctrl-socket'), '/usr/local/var/run/kea/kea4-ctrl-socket', 'Kea overrides Meson state-directory options for a /usr/local prefix' );

my $split_option_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => q{Configure arguments: '--prefix=/usr' '--localstatedir=/xcat-test-first' '--localstatedir' '/xcat-test-split-last'},
);
is( $split_option_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-split-last/run/kea/kea4-ctrl-socket', 'a space-separated Autoconf option can override an earlier value' );

my $last_option_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => <<'BUILD_REPORT',
Configure arguments: '--prefix=/usr' '--runstatedir=/xcat-test-first' '--runstatedir=/xcat-test-last' 'CXXFLAGS=-O2 -Drunstatedir=/xcat-test-embedded-compiler'

C++ Compiler:
  CXX_ARGS: -Drunstatedir=/xcat-test-compiler-only
BUILD_REPORT
);
is( $last_option_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-last/kea/kea4-ctrl-socket', 'last build option wins without reading embedded or compiler-only flags' );

my $root_socket_backend = xCAT::DHCP::Backend::Kea->new(
    kea_build_report => 'Build Options: -Dprefix=/ -Dlocalstatedir=/ -Drunstatedir=/',
);
is( $root_socket_backend->control_socket_path('kea4-ctrl-socket'), '/kea/kea4-ctrl-socket', 'root runstatedir joins the socket path without a duplicate separator' );

my $fake_kea_dhcp4 = "$unit_dir/kea-dhcp4-build-report";
open( my $fake_kea_fh, '>', $fake_kea_dhcp4 ) or die "Unable to write fake Kea command: $!";
print {$fake_kea_fh} "#!$^X\n";
print {$fake_kea_fh} <<'FAKE_KEA';
use strict;
use warnings;
exit 2 unless @ARGV == 1 && $ARGV[0] eq '-W';
print "Build Options: -Dprefix=/usr -Drunstatedir=/xcat-test-command-run\n";
FAKE_KEA
close($fake_kea_fh) or die "Unable to close fake Kea command: $!";
chmod 0755, $fake_kea_dhcp4 or die "Unable to make fake Kea command executable: $!";

my $command_socket_backend = xCAT::DHCP::Backend::Kea->new(kea_dhcp4_command => $fake_kea_dhcp4);
is( $command_socket_backend->control_socket_path('kea4-ctrl-socket'), '/xcat-test-command-run/kea/kea4-ctrl-socket', 'socket path comes from the Kea build-report command' );

my $socket_backend = xCAT::DHCP::Backend::Kea->new( kea_socket_dir => '/run/kea' );
my $ctrl_agent_socket_config = decode_json($socket_backend->render_ctrl_agent_config({ dhcp6 => 1, ddns => 1 }));
is( $ctrl_agent_socket_config->{'Control-agent'}{'control-sockets'}{dhcp4}{'socket-name'}, '/run/kea/kea4-ctrl-socket', 'Control Agent DHCPv4 socket uses the detected Kea socket directory' );
is( $ctrl_agent_socket_config->{'Control-agent'}{'control-sockets'}{dhcp6}{'socket-name'}, '/run/kea/kea6-ctrl-socket', 'Control Agent DHCPv6 socket uses the detected Kea socket directory' );
is( $ctrl_agent_socket_config->{'Control-agent'}{'control-sockets'}{d2}{'socket-name'}, '/run/kea/kea-ddns-ctrl-socket', 'Control Agent DDNS socket uses the detected Kea socket directory' );

my $explicit_socket_config = decode_json($socket_backend->render_ctrl_agent_config({ 'dhcp4-socket' => '/tmp/kea4.sock' }));
is( $explicit_socket_config->{'Control-agent'}{'control-sockets'}{dhcp4}{'socket-name'}, '/tmp/kea4.sock', 'explicit Control Agent socket path overrides the default' );

my @commands;
my $ca_backend = xCAT::DHCP::Backend::Kea->new(
    control_agent_handler => sub {
        my ($payload) = @_;
        push @commands, $payload;
        return { ok => 1, result => 0, response => { result => 0 } };
    },
);
my $live_result = $ca_backend->live_upsert_reservations(
    [
        {
            'subnet-id'      => 10,
            'hw-address'     => '00:11:22:33:44:55',
            'ip-address'     => '10.10.0.20',
            hostname         => 'node20',
            'boot-file-name' => 'pxelinux.0',
        },
    ]
);
ok( !$live_result->{error}, 'live reservation upsert succeeds through injected Control Agent handler' );
is( $commands[0]{command}, 'reservation-del', 'live upsert deletes any existing reservation first' );
is( $commands[0]{arguments}{'operation-target'}, 'memory', 'live delete targets runtime memory' );
is( $commands[1]{command}, 'reservation-add', 'live upsert adds reservation through host-commands' );
is( $commands[1]{arguments}{reservation}{'subnet-id'}, 10, 'live add includes subnet id in reservation body' );
is_deeply( $commands[1]{service}, ['dhcp4'], 'live add targets dhcp4 service by default' );

done_testing();
