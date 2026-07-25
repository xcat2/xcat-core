use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Path qw/make_path/;
use File::Temp qw/tempdir/;
use Test::More;

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
plan skip_all => 'Kea host-commands hook is required' unless $hook;

my $tmp = tempdir(CLEANUP => 1);
make_path('/var/run/kea');
make_path('/var/lib/kea');

my $socket = "/var/run/kea/kea4-xcat-smoke-$$.sock";
my $lease_file = "/var/lib/kea/kea-leases4-xcat-smoke-$$.csv";
unlink $socket, $lease_file;

my $dhcp_config = "$tmp/kea-dhcp4.conf";
my $ctrl_config = "$tmp/kea-ctrl-agent.conf";
write_file(
    $dhcp_config,
    $backend->render_dhcp4_config(
        {
            interfaces       => ['lo'],
            'lease-database' => {
                type => 'memfile',
                name => $lease_file,
            },
            'control-socket' => {
                'socket-type' => 'unix',
                'socket-name' => $socket,
            },
            'hooks-libraries' => [ { library => $hook } ],
            subnets => [
                {
                    id     => 1,
                    subnet => '127.0.0.0/8',
                    pools  => [],
                },
            ],
        }
    )
);
write_file(
    $ctrl_config,
    $backend->render_ctrl_agent_config(
        {
            'http-port'    => 18000,
            'dhcp4-socket' => $socket,
        }
    )
);

my $dhcp_validation = $backend->validate_dhcp4_config($dhcp_config);
ok( !$dhcp_validation->{error}, 'live smoke DHCPv4 config validates' )
  or diag $dhcp_validation->{error};
my $ctrl_validation = $backend->validate_ctrl_agent_config($ctrl_config);
ok( !$ctrl_validation->{error}, 'live smoke Control Agent config validates' )
  or diag $ctrl_validation->{error};

my @pids;
END {
    kill 'TERM', @pids if @pids;
    unlink grep { defined($_) && $_ ne '' } ( $socket, $lease_file );
}

push @pids, start_daemon($kea_dhcp4, '-c', $dhcp_config, '-d', "$tmp/kea-dhcp4.log");
ok( wait_for_process($pids[-1]), 'kea-dhcp4 stays running for smoke test' );
push @pids, start_daemon($kea_ctrl, '-c', $ctrl_config, '-d', "$tmp/kea-ctrl-agent.log");
ok( wait_for_process($pids[-1]), 'kea-ctrl-agent stays running for smoke test' );

my $live_backend = xCAT::DHCP::Backend::Kea->new(control_agent_port => 18000);
my $add = $live_backend->live_upsert_reservations(
    [
        {
            'subnet-id'  => 1,
            'hw-address' => '52:54:00:12:34:56',
            'ip-address' => '127.0.0.50',
            hostname     => 'node-smoke',
        },
    ],
    service => ['dhcp4']
);
ok( !$add->{error}, 'reservation-add succeeds through Kea Control Agent' )
  or diag $add->{error};

my $delete = $live_backend->live_delete_reservations(
    [
        {
            'subnet-id'  => 1,
            'hw-address' => '52:54:00:12:34:56',
            'ip-address' => '127.0.0.50',
            hostname     => 'node-smoke',
        },
    ],
    service => ['dhcp4']
);
ok( !$delete->{error}, 'reservation-del succeeds through Kea Control Agent' )
  or diag $delete->{error};

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

sub write_file {
    my ( $path, $content ) = @_;

    open(my $fh, '>', $path) or die "Unable to write $path: $!";
    print $fh $content;
    close($fh) or die "Unable to close $path: $!";

    return 1;
}

sub start_daemon {
    my ( $command, @args ) = @_;
    my $log = pop @args;
    my $pid = fork();
    die "Unable to fork $command: $!" unless defined $pid;
    if ($pid == 0) {
        open(STDOUT, '>', $log) or die "Unable to write $log: $!";
        open(STDERR, '>&', \*STDOUT) or die "Unable to redirect stderr: $!";
        exec $command, @args;
        die "Unable to exec $command: $!";
    }
    return $pid;
}

sub wait_for_process {
    my ($pid) = @_;

    for (1 .. 10) {
        sleep 1;
        return 0 unless kill 0, $pid;
        return 1 if $_ >= 2;
    }

    return kill 0, $pid;
}
