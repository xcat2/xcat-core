use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Path qw/make_path/;
use File::Temp qw/tempdir/;
use IO::Socket::INET;
use POSIX qw/WNOHANG _exit setgid setuid/;
use Test::More;
use Time::HiRes qw/sleep time/;

use xCAT::DHCP::Backend::Kea;

plan skip_all => 'set XCAT_KEA_LIVE_SMOKE=1 to run live Kea daemon smoke test'
  unless $ENV{XCAT_KEA_LIVE_SMOKE};
plan skip_all => 'live Kea daemon smoke test must run as root' unless $> == 0;

my $kea_dhcp4 = command_path('kea-dhcp4');
my $kea_ctrl  = command_path('kea-ctrl-agent');
plan skip_all => 'kea-dhcp4 and kea-ctrl-agent are required'
  unless $kea_dhcp4 && $kea_ctrl;

my $backend = xCAT::DHCP::Backend::Kea->new();
my $hook = $backend->host_cmds_hook_path();
my $service_account = $backend->service_account();
plan skip_all => 'Kea service account is required'
  unless ref($service_account) eq 'HASH'
  && defined( $service_account->{name} )
  && defined( $service_account->{uid} )
  && defined( $service_account->{gid} );

my $tmp = tempdir(CLEANUP => 1);
chmod 0755, $tmp or die "Unable to make $tmp daemon-traversable: $!";

my $runtime_dir = "$tmp/run";
my $data_dir = "$tmp/data";
make_path( $runtime_dir, $data_dir );
chown( $service_account->{uid}, $service_account->{gid}, $runtime_dir, $data_dir ) == 2
  or die "Unable to set Kea fixture directory ownership: $!";
chmod( 0750, $runtime_dir, $data_dir ) == 2
  or die "Unable to set Kea fixture directory permissions: $!";

local $ENV{KEA_CONTROL_SOCKET_DIR} = $runtime_dir;
local $ENV{KEA_DHCP_DATA_DIR}      = $data_dir;
local $ENV{KEA_PIDFILE_DIR}        = $runtime_dir;
local $ENV{KEA_LOCKFILE_DIR}       = $runtime_dir;

$backend = xCAT::DHCP::Backend::Kea->new(kea_socket_dir => $runtime_dir);

my $port_guard = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Listen    => 1,
    Proto     => 'tcp',
) or die "Unable to reserve a Control Agent port: $!";
my $control_agent_port = $port_guard->sockport();

my $socket = $backend->control_socket_path('kea4-ctrl-socket');
my $lease_file = "$data_dir/kea-leases4.csv";

my $dhcp_config = "$tmp/kea-dhcp4.conf";
my $ctrl_config = "$tmp/kea-ctrl-agent.conf";
my $dhcp_settings = {
    interfaces       => [],
    'lease-database' => {
        type => 'memfile',
        name => $lease_file,
    },
    'control-socket' => {
        'socket-type' => 'unix',
        'socket-name' => $socket,
    },
    subnets => [
        {
            id     => 1,
            subnet => '127.0.0.0/8',
            pools  => [],
        },
    ],
};
$dhcp_settings->{'hooks-libraries'} = [ { library => $hook } ] if $hook;

my $dhcp_write = $backend->write_dhcp4_config(
    $dhcp_settings,
    path => $dhcp_config,
);
ok( !$dhcp_write->{error}, 'live smoke DHCPv4 config validates and writes' )
  or diag $dhcp_write->{error};

my $ctrl_write = $backend->write_ctrl_agent_config(
    {
        'http-port' => $control_agent_port,
    },
    path => $ctrl_config,
);
ok( !$ctrl_write->{error}, 'live smoke Control Agent config validates and writes' )
  or diag $ctrl_write->{error};

unless ( !$dhcp_write->{error} && !$ctrl_write->{error} ) {
    done_testing();
    exit 1;
}

my %children;
END { stop_daemons(\%children); }

my $dhcp_log = "$tmp/kea-dhcp4.log";
my $dhcp_pid = start_daemon( $service_account, $kea_dhcp4, $dhcp_log, '-c', $dhcp_config, '-d' );
$children{$dhcp_pid} = 1;
my $dhcp_ready = wait_for_socket( $dhcp_pid, $socket, \%children );
ok( $dhcp_ready, 'kea-dhcp4 creates its Control Agent socket' );
diag_file($dhcp_log) unless $dhcp_ready;
unless ($dhcp_ready) {
    done_testing();
    exit 1;
}
is( ( stat $socket )[4], $service_account->{uid}, 'kea-dhcp4 socket belongs to the service account' );

my $lease_ready = wait_for_file( $dhcp_pid, $lease_file, \%children );
ok( $lease_ready, 'kea-dhcp4 creates its lease file' );
is( ( stat $lease_file )[4], $service_account->{uid}, 'kea-dhcp4 lease file belongs to the service account' )
  if $lease_ready;

close($port_guard) or die "Unable to release the reserved Control Agent port: $!";

my $ctrl_log = "$tmp/kea-ctrl-agent.log";
my $ctrl_pid = start_daemon( $service_account, $kea_ctrl, $ctrl_log, '-c', $ctrl_config, '-d' );
$children{$ctrl_pid} = 1;

my $live_backend = xCAT::DHCP::Backend::Kea->new(control_agent_port => $control_agent_port);
my ( $ctrl_ready, $readiness ) = wait_for_control_agent( $live_backend, $ctrl_pid, \%children );
ok( $ctrl_ready, 'Kea Control Agent forwards commands to kea-dhcp4' );
diag( $readiness->{error} || $readiness->{text} || 'Control Agent returned no response' ) unless $ctrl_ready;
diag_file($ctrl_log) unless $ctrl_ready;
unless ($ctrl_ready) {
    done_testing();
    exit 1;
}

SKIP: {
    skip 'Kea host-commands hook is unavailable', 4 unless $hook;

    my $reservation = {
        'subnet-id'  => 1,
        'hw-address' => '52:54:00:12:34:56',
        'ip-address' => '127.0.0.50',
        hostname     => 'node-smoke',
    };
    my $add = $live_backend->live_upsert_reservations(
        [$reservation],
        service => ['dhcp4']
    );
    ok( !$add->{error}, 'reservation-add succeeds through Kea Control Agent' )
      or diag $add->{error};

    my $lookup = {
        'subnet-id'        => $reservation->{'subnet-id'},
        'identifier-type' => 'hw-address',
        identifier        => $reservation->{'hw-address'},
    };
    my $found = $live_backend->control_agent_command( 'reservation-get', $lookup, service => ['dhcp4'] );
    my $stored = response_arguments($found);
    ok(
        ref($stored) eq 'HASH'
          && defined( $stored->{'ip-address'} )
          && $stored->{'ip-address'} eq $reservation->{'ip-address'},
        'reservation-get confirms the added reservation is stored'
    ) or diag( $found->{error} || $found->{text} || 'reservation-get returned no reservation' );

    my $delete = $live_backend->live_delete_reservations(
        [$reservation],
        service => ['dhcp4']
    );
    ok( !$delete->{error}, 'reservation-del succeeds through Kea Control Agent' )
      or diag $delete->{error};

    my $missing = $live_backend->control_agent_command( 'reservation-get', $lookup, service => ['dhcp4'] );
    my $missing_arguments = response_arguments($missing);
    my $expected_not_found = !$missing->{error}
      || ( defined( $missing->{result} ) && $missing->{result} == 3 )
      || ( defined( $missing->{text} ) && $missing->{text} =~ /not\s+found/i );
    ok(
        defined( $missing->{response} )
          && $expected_not_found
          && ( ref($missing_arguments) ne 'HASH' || !keys %$missing_arguments ),
        'reservation-get confirms the deleted reservation is absent'
    ) or diag( $missing->{error} || $missing->{text} || 'reservation-get returned an unexpected response' );
}

stop_daemons(\%children);
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

sub start_daemon {
    my ( $account, $command, $log, @args ) = @_;
    my $pid = fork();
    die "Unable to fork $command: $!" unless defined $pid;
    if ($pid == 0) {
        open(STDOUT, '>', $log) or child_exit("Unable to write $log: $!");
        open(STDERR, '>&', \*STDOUT) or child_exit("Unable to redirect stderr: $!");
        $) = "$account->{gid} $account->{gid}";
        defined( setgid( $account->{gid} ) )
          or child_exit("Unable to set group identity to $account->{gid}: $!");
        my @group_ids = split /\s+/, $);
        $( == $account->{gid} && @group_ids && !grep { $_ != $account->{gid} } @group_ids
          or child_exit("Kea child did not assume group identity $account->{gid}");
        defined( setuid( $account->{uid} ) )
          or child_exit("Unable to set user identity to $account->{uid}: $!");
        $> == $account->{uid} && $< == $account->{uid}
          or child_exit("Kea child did not assume user identity $account->{uid}");
        {
            no warnings 'exec';
            exec { $command } $command, @args;
            child_exit("Unable to exec $command: $!");
        }
    }
    return $pid;
}

sub child_exit {
    my ($message) = @_;

    warn "$message\n";
    _exit(127);
}

sub wait_for_socket {
    my ( $pid, $socket_path, $children ) = @_;

    for (1 .. 100) {
        return 0 unless process_running( $pid, $children );
        return 1 if -S $socket_path;
        sleep 0.1;
    }

    return 0;
}

sub wait_for_file {
    my ( $pid, $path, $children ) = @_;

    for (1 .. 100) {
        return 0 unless process_running( $pid, $children );
        return 1 if -f $path;
        sleep 0.1;
    }

    return 0;
}

sub wait_for_control_agent {
    my ( $backend, $pid, $children ) = @_;

    my $last_result = {};
    my $deadline = time + 10;
    while ( time < $deadline ) {
        return ( 0, $last_result ) unless process_running( $pid, $children );
        $last_result = $backend->control_agent_command(
            'list-commands',
            {},
            service => ['dhcp4'],
            timeout => 1,
        );
        return ( 1, $last_result ) unless $last_result->{error};
        my $remaining = $deadline - time;
        sleep( $remaining < 0.1 ? $remaining : 0.1 ) if $remaining > 0;
    }

    return ( 0, $last_result );
}

sub process_running {
    my ( $pid, $children ) = @_;

    my $waited = waitpid( $pid, WNOHANG );
    return 1 if $waited == 0;

    delete $children->{$pid};
    return 0;
}

sub stop_daemons {
    my ($children) = @_;

    my @pids = keys %$children;
    kill 'TERM', @pids if @pids;
    foreach my $pid (@pids) {
        for (1 .. 50) {
            last unless process_running( $pid, $children );
            sleep 0.1;
        }
        next unless exists $children->{$pid};

        kill 'KILL', $pid;
        waitpid( $pid, 0 );
        delete $children->{$pid};
    }

    return;
}

sub response_arguments {
    my ($result) = @_;

    return unless ref($result) eq 'HASH';
    my $response = $result->{response};
    my $item = ref($response) eq 'ARRAY' ? $response->[0] : $response;
    return unless ref($item) eq 'HASH';
    return $item->{arguments} if ref( $item->{arguments} ) eq 'HASH';

    return;
}

sub diag_file {
    my ($path) = @_;

    return unless -e $path;
    open( my $fh, '<', $path ) or return;
    local $/;
    my $content = <$fh>;
    close($fh) or diag("Unable to close $path: $!");
    diag($content) if defined($content) && $content ne '';

    return;
}
