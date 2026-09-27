#!/usr/bin/env perl
# makedhcp gives dhcpd the host statements of a node through OMAPI, and dhcpd keeps them in
# dhcpd.leases, where it saves them without parentheses. A restart of dhcpd must read back the
# statements of a netboot=ipxe node, which test the iPXE feature options. The test stores them
# through OMAPI, as makedhcp does, and restarts dhcpd with the same configuration.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/lib";

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use Time::HiRes qw(sleep);

use xCAT::DHCP::BootPolicy;
use xCAT::DHCP::OmapiPolicy;
use XCAT::Test::DHCP qw(start_daemon process_running stop_daemons diag_file);

my ($dhcpd) = grep { -x $_ } qw(/usr/sbin/dhcpd /usr/local/sbin/dhcpd);
plan skip_all => 'dhcpd is required' unless $dhcpd;
my $settings = xCAT::DHCP::OmapiPolicy->settings( site_values => {} );
plan skip_all => "$settings->{omshell_path} is required" unless -x $settings->{omshell_path};
plan skip_all => 'root is required to run dhcpd in a network namespace' unless $> == 0;

my $namespace = "xcat-test-$$";
my $interface = "xt$$";
my %children;
my $namespace_created;
END {
    stop_daemons( \%children );
    system( 'ip', 'netns', 'delete', $namespace ) if $namespace_created;
}
plan skip_all => 'ip netns is required' unless system("ip netns add $namespace >/dev/null 2>&1") == 0;
$namespace_created = 1;
for my $command (
    [ 'link', 'set', 'lo', 'up' ],
    [ 'link', 'add', "${interface}a", 'type', 'veth', 'peer', 'name', "${interface}b" ],
    [ 'address', 'add', '192.0.2.1/24', 'dev', "${interface}a" ],
    [ 'link', 'set', "${interface}a", 'up' ],
    [ 'link', 'set', "${interface}b", 'up' ],
  )
{
    system( 'ip', '-n', $namespace, @$command ) == 0 or BAIL_OUT("ip -n $namespace @$command failed");
}

# The dhcpd AppArmor profile of Ubuntu reads only /etc/dhcp and writes only /var/lib/dhcp/dhcpd.leases*.
my $configuration_root = -d '/etc/dhcp' ? '/etc/dhcp' : '/etc';
my $directory = tempdir( DIR => $configuration_root, CLEANUP => 1 );
my $leases = -d '/var/lib/dhcp' ? "/var/lib/dhcp/dhcpd.leases.xcat-test-$$" : "$directory/dhcpd.leases";
END { unlink glob("$leases*") if $leases }

my $secret = 'eGNhdC10ZXN0LW9tYXBpLXNlY3JldC0wMQ==';
my $port   = 7911;
my $configuration = File::Spec->catfile( $directory, 'dhcpd.conf' );
{
    open( my $fh, '>', $configuration ) or die "Cannot create $configuration: $!";
    print {$fh} "option conf-file code 209 = text;\n",
      "option space gpxe;\n",
      "option gpxe-encap-opts code 175 = encapsulate gpxe;\n",
      "option gpxe.bus-id code 177 = string;\n",
      @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() },
      "option user-class-identifier code 77 = string;\n",
      "option client-architecture code 93 = unsigned integer 16;\n",
      "option www-server code 114 = string;\n",
      "omapi-port $port;\n",
      "key $settings->{key_name} {\n  algorithm $settings->{algorithm};\n  secret \"$secret\";\n};\n",
      "omapi-key $settings->{key_name};\n",
      "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
      @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
            next_server => '192.0.2.1',
            portsuffix  => '',
            net         => '192.0.2.0',
            prefix      => 24,
        ) },
      "}\n";
    close($fh) or die "Cannot close $configuration: $!";
}

sub omshell {
    my ($commands) = @_;
    my $input = File::Spec->catfile( $directory, 'omshell.in' );
    open( my $fh, '>', $input ) or die "Cannot create $input: $!";
    print {$fh} xCAT::DHCP::OmapiPolicy->omshell_preamble( $settings, secret => $secret, port => $port ),
      "connect\n", $commands;
    close($fh) or die "Cannot close $input: $!";
    return scalar `ip netns exec $namespace $settings->{omshell_path} < $input 2>&1`;
}

sub start_dhcpd {
    my ($log) = @_;
    my $pid = start_daemon( undef, 'ip', $log, 'netns', 'exec', $namespace, $dhcpd, '-f', '-d',
        '-cf', $configuration, '-lf', $leases, '-pf', "$directory/dhcpd.pid", "${interface}a" );
    $children{$pid} = 1;
    for ( 1 .. 100 ) {
        last unless process_running( $pid, \%children );
        return $pid if omshell('') !~ /not connected|no more/;
        sleep 0.1;
    }
    diag_file($log);
    BAIL_OUT("dhcpd did not open OMAPI port $port");
}

my %common = ( netboot => 'ipxe', next_server => '192.0.2.1', portsuffix => '' );
my @hosts = (
    [ bios          => { currstate => 'install rhels9' } ],
    [ uefi          => { uefi => 1, currstate => 'install rhels9' } ],
    [ iscsi         => { iscsi => 1, currstate => 'boot' } ],
    [ iscsi_install => { uefi => 1, iscsi => 1, currstate => 'install rhels9' } ],
    [ winshell      => { uefi => 2, currstate => 'winshell' } ],
);

open( my $fresh, '>', $leases ) or die "Cannot create $leases: $!";
close($fresh);
start_dhcpd("$directory/dhcpd-first.log");

my $commands = '';
my $index = 0;
for my $host (@hosts) {
    my ( $name, $opts ) = @$host;
    $index++;
    my $statements = xCAT::DHCP::BootPolicy->isc_node_boot_statements( %common, %$opts, node => "cn-$name" );
    $commands .= "new host\nset name = \"cn-$name\"\nset hardware-address = 52:54:00:00:00:0$index\n"
      . "set hardware-type = 1\nset ip-address = 192.0.2.1$index\nset statements = \"$statements\"\ncreate\nclose\n";
}
my $created = omshell($commands);
unlike( $created, qr/can't|error|eof in string|unknown token|not connected/i, 'OMAPI creates every ipxe host' )
  or diag($created);
stop_daemons( \%children );

my $saved = do { local ( @ARGV, $/ ) = ($leases); <> } // '';
for my $host (@hosts) {
    like( $saved, qr/^host cn-$host->[0] \{$/m, "dhcpd.leases holds the $host->[0] host" );
}
like( $saved, qr/exists gpxe\.http/, 'with its iPXE feature tests' );

my $check = `$dhcpd -t -T -cf $configuration -lf $leases 2>&1`;
is( $?, 0, 'dhcpd checks the leases' );
unlike( $check, qr/ line \d+: /, 'and parses every ipxe host statement that it saved' ) or diag($check);

my $restart_log = "$directory/dhcpd-restart.log";
start_dhcpd($restart_log);
for my $host (@hosts) {
    like( omshell("new host\nset name = \"cn-$host->[0]\"\nopen\n"), qr/^ip-address = /m,
        "dhcpd restarts with the $host->[0] host" );
}
unlike( do { local ( @ARGV, $/ ) = ($restart_log); <> } // '', qr/ line \d+: /, 'the restart reports no parse error' );

done_testing();
