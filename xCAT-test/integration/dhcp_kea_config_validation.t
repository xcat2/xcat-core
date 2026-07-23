use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw/tempfile/;
use JSON ();
use Test::More;

use xCAT::DHCP::Backend::Kea;

my $kea_dhcp4 = command_path('kea-dhcp4');
plan skip_all => 'kea-dhcp4 is not installed' unless $kea_dhcp4;

my $validation_dir = validation_temp_dir($kea_dhcp4);
plan skip_all => 'kea-dhcp4 cannot read temporary config files; run as root to validate from /etc/kea'
  unless defined $validation_dir;

my $backend = xCAT::DHCP::Backend::Kea->new();
my $json = $backend->render_dhcp4_config(
    {
        interfaces => ['*'],
        'option-def' => [
            { name => 'conf-file', code => 209, type => 'string', space => 'dhcp4' },
            { name => 'iscsi-initiator-iqn', code => 203, type => 'string', space => 'dhcp4' },
            { name => 'cumulus-provision-url', code => 239, type => 'string', space => 'dhcp4' },
        ],
        'client-classes' => [
            {
                name             => 'xcat-xnba-node01-525400123456-bios',
                test             => "(option[77].exists and (option[77].text == 'xNBA' or option[77].hex == 0x784e4241 or substring(option[77].hex,1,4) == 'xNBA')) and option[93].hex == 0x0000 and pkt4.mac == 0x525400123456",
                'boot-file-name' => 'http://192.168.122.1:80/tftpboot/xcat/xnba/nodes/node01',
            },
            {
                name            => 'xcat-opal-v3-192.168.122.0-24',
                test            => 'option[93].hex == 0x000e',
                additional_only => JSON::true,
                'option-data'   => [
                    { name => 'conf-file', data => 'http://192.168.122.1:80/tftpboot/pxelinux.cfg/p/192.168.122.0_24' },
                ],
            },
            {
                name             => 'xcat-uefi-x64',
                test             => "(option[93].hex == 0x0007 or option[93].hex == 0x0009 or option[93].hex == 0x0010) and not ((option[77].exists and (option[77].text == 'xNBA' or option[77].hex == 0x784e4241 or substring(option[77].hex,1,4) == 'xNBA')))",
                'boot-file-name' => 'xcat/xnba.efi',
            },
        ],
        'dhcp-ddns' => {
            'enable-updates' => JSON::true,
            'server-ip'      => '127.0.0.1',
            'server-port'    => 53001,
            'ncr-protocol'   => 'UDP',
            'ncr-format'     => 'JSON',
        },
        'ddns-send-updates'          => JSON::true,
        'ddns-override-no-update'    => JSON::true,
        'ddns-override-client-update' => JSON::true,
        'ddns-qualifying-suffix'     => 'cluster.test.',
        'ddns-update-on-renew'       => JSON::true,
        subnets => [
            {
                id           => 1,
                subnet       => '192.168.122.0/24',
                dynamicrange => '192.168.122.100-192.168.122.120',
                next_server  => '192.168.122.1',
                additional_client_classes => ['xcat-opal-v3-192.168.122.0-24'],
                option_data  => [
                    { name => 'routers',             data => '192.168.122.1' },
                    { name => 'domain-name',         data => 'cluster.test' },
                    { name => 'domain-name-servers', data => '192.168.122.1' },
                    { name => 'cumulus-provision-url', data => 'http://192.168.122.1:80/install/postscripts/cumulusztp' },
                ],
                reservations => [
                    {
                        'hw-address'    => '52:54:00:12:34:56',
                        'ip-address'    => '192.168.122.50',
                        hostname        => 'node01',
                        'next-server'   => '192.168.122.1',
                        'boot-file-name' => 'pxelinux.0',
                        'option-data'   => [ { name => 'host-name', data => 'node01' } ],
                    },
                ],
            },
            {
                id     => 2,
                subnet => '192.168.123.0/24',
                pools  => [],
                reservations => [
                    {
                        'hw-address' => '52:54:00:65:43:21',
                        'ip-address' => '192.168.123.50',
                        hostname     => 'node02',
                    },
                ],
            },
        ],
    }
);

my $path = write_validation_file( $json, 'xcat-test-kea-dhcp4' );

my $result = $backend->validate_dhcp4_config($path);
ok( !$result->{error}, 'generated Kea DHCPv4 config validates with kea-dhcp4 -t' )
  or diag $result->{error};

unlink $path;
SKIP: {
    skip 'kea-dhcp6 is not installed', 1 unless command_path('kea-dhcp6');
    my $dhcp6_json = $backend->render_dhcp6_config(
        {
            interfaces => ['*'],
            'dhcp-ddns' => {
                'enable-updates' => JSON::true,
                'server-ip'      => '127.0.0.1',
                'server-port'    => 53001,
                'ncr-protocol'   => 'UDP',
                'ncr-format'     => 'JSON',
            },
            'ddns-send-updates'          => JSON::true,
            'ddns-override-no-update'    => JSON::true,
            'ddns-override-client-update' => JSON::true,
            'ddns-qualifying-suffix'     => 'cluster.test.',
            'ddns-update-on-renew'       => JSON::true,
            subnets    => [
                {
                    id           => 6,
                    subnet       => '2001:db8:1::/64',
                    dynamicrange => '2001:db8:1::100/120',
                    option_data  => [
                        { name => 'dns-servers',   data => '2001:db8:1::1' },
                        { name => 'domain-search', data => 'cluster.test' },
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
    my $dhcp6_path = write_validation_file( $dhcp6_json, 'xcat-test-kea-dhcp6' );
    my $dhcp6_result = $backend->validate_dhcp6_config($dhcp6_path);
    ok( !$dhcp6_result->{error}, 'generated Kea DHCPv6 config validates with kea-dhcp6 -t' )
      or diag $dhcp6_result->{error};
    unlink $dhcp6_path;
}

SKIP: {
    skip 'kea-dhcp-ddns is not installed', 1 unless command_path('kea-dhcp-ddns');
    my $ddns_json = $backend->render_ddns_config(
        {
            'tsig-keys' => [
                { name => 'xcat_key', algorithm => 'HMAC-SHA256', secret => 'YWJjMTIz' },
            ],
            forward_domains => [
                {
                    name          => 'cluster.test.',
                    'key-name'    => 'xcat_key',
                    'dns-servers' => [ { 'ip-address' => '127.0.0.1', port => 53 } ],
                },
            ],
            reverse_domains => [
                {
                    name          => '122.168.192.in-addr.arpa.',
                    'key-name'    => 'xcat_key',
                    'dns-servers' => [ { 'ip-address' => '127.0.0.1', port => 53 } ],
                },
            ],
        }
    );
    my $ddns_path = write_validation_file( $ddns_json, 'xcat-test-kea-ddns' );
    my $ddns_result = $backend->validate_ddns_config($ddns_path);
    ok( !$ddns_result->{error}, 'generated Kea DHCP-DDNS config validates with kea-dhcp-ddns -t' )
      or diag $ddns_result->{error};
    unlink $ddns_path;
}

SKIP: {
    skip 'kea-ctrl-agent is not installed', 1 unless command_path('kea-ctrl-agent');
    my $ctrl_agent_json = $backend->render_ctrl_agent_config(
        {
            dhcp6 => 1,
            ddns  => 1,
        }
    );
    my $ctrl_path = write_validation_file( $ctrl_agent_json, 'xcat-test-kea-ctrl-agent' );
    my $ctrl_result = $backend->validate_ctrl_agent_config($ctrl_path);
    ok( !$ctrl_result->{error}, 'generated Kea Control Agent config validates with kea-ctrl-agent -t' )
      or diag $ctrl_result->{error};
    unlink $ctrl_path;
}
done_testing();

sub command_path {
    my ($command) = @_;

    foreach my $dir ( split /:/, $ENV{PATH} || '' ) {
        next unless $dir;
        return "$dir/$command" if -x "$dir/$command";
    }

    foreach my $path ( "/usr/sbin/$command", "/usr/bin/$command", "/sbin/$command", "/bin/$command" ) {
        return $path if -x $path;
    }

    return;
}

sub validation_temp_dir {
    my ($kea_dhcp4) = @_;

    return '/etc/kea' if -d '/etc/kea' && -w '/etc/kea';

    my ( $fh, $path ) = tempfile();
    print $fh '{"Dhcp4":{"interfaces-config":{"interfaces":[]},"lease-database":{"type":"memfile","name":"/tmp/xcat-test-kea-leases4.csv"},"valid-lifetime":600,"subnet4":[]}}';
    close($fh);
    chmod 0644, $path or die "Unable to set $path permissions: $!";

    my $command = shell_quote($kea_dhcp4) . ' -t ' . shell_quote($path) . ' 2>&1';
    my $output = `$command`;
    unlink $path;
    if ( $output =~ /Unable to open file/ ) {
        return;
    }

    return '';
}

sub write_validation_file {
    my ( $content, $template ) = @_;

    my %opts = ( TEMPLATE => "$template-XXXXXX", UNLINK => 0 );
    $opts{DIR} = $validation_dir if defined $validation_dir;

    my ( $fh, $path ) = tempfile(%opts);
    print $fh $content;
    close($fh);
    chmod 0644, $path or die "Unable to set $path permissions: $!";

    return $path;
}

sub shell_quote {
    my ($value) = @_;

    $value =~ s/'/'\\''/g;
    return "'$value'";
}
