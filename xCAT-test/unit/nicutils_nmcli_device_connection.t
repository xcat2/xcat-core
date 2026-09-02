#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3 qw(open3);
use lib "$FindBin::Bin/../lib";
use Symbol qw(gensym);
use Test::More;

use XCAT::Test::File qw(repo_path);

my $nicutils = repo_path(
    File::Spec->catfile( 'xCAT', 'postscripts', 'nicutils.sh' )
);
-r $nicutils or BAIL_OUT("$nicutils is required");

is( system( 'bash', '-n', $nicutils ), 0,
    'nicutils has valid Bash syntax' );

my $tmpdir = tempdir( CLEANUP => 1 );
my $test_bin = File::Spec->catdir( $tmpdir, 'bin' );
make_path($test_bin);

my $command_log = File::Spec->catfile( $tmpdir, 'commands.log' );
my $helper_log = File::Spec->catfile( $tmpdir, 'helper.log' );
my $scope_log = File::Spec->catfile( $tmpdir, 'scope.log' );

my $fake_nmcli = File::Spec->catfile( $test_bin, 'nmcli' );
write_file( $fake_nmcli, <<'SH' );
#!/bin/sh
{
    printf 'nmcli'
    for argument in "$@"; do
        printf '\t<%s>' "$argument"
    done
    printf '\n'
} >>"$XCAT_TEST_COMMAND_LOG"

if [ "$1" = '-g' ] && [ "$2" = 'GENERAL.CON-UUID' ] &&
   [ "$3" = 'device' ] && [ "$4" = 'show' ]; then
    [ "${XCAT_TEST_FORBID_UUID_QUERY-0}" = '0' ] || exit 99
    printf '%s' "${XCAT_TEST_NMCLI_OUTPUT-}"
    printf '%s' "${XCAT_TEST_NMCLI_ERROR-}" >&2
    exit "${XCAT_TEST_NMCLI_STATUS-0}"
fi

if [ "$1" = 'dev' ] && [ "$2" = 'show' ]; then
    printf '%s' "${XCAT_TEST_NMCLI_NAME_OUTPUT-}"
    printf '%s' "${XCAT_TEST_NMCLI_NAME_ERROR-}" >&2
    exit "${XCAT_TEST_NMCLI_NAME_STATUS-0}"
fi
SH
chmod 0755, $fake_nmcli or die "Unable to make $fake_nmcli executable: $!";

my $fake_ip = File::Spec->catfile( $test_bin, 'ip' );
write_file( $fake_ip, <<'SH' );
#!/bin/sh
{
    printf 'ip'
    for argument in "$@"; do
        printf '\t<%s>' "$argument"
    done
    printf '\n'
} >>"$XCAT_TEST_COMMAND_LOG"
SH
chmod 0755, $fake_ip or die "Unable to make $fake_ip executable: $!";

my $helper_driver = File::Spec->catfile( $tmpdir, 'run-helper' );
write_file( $helper_driver, <<'SH' );
#!/bin/bash
source "$XCAT_TEST_NICUTILS" >/dev/null
nmcli=unused-nmcli-variable
case "$1" in
    name)
        nmcli_connection_name_for_device "$2"
        ;;
    uuid)
        nmcli_connection_uuid_for_device "$2"
        ;;
    *)
        exit 2
        ;;
esac
status=$?
printf 'device=%s\n' "${device-<unset>}" >"$XCAT_TEST_SCOPE_LOG"
exit "$status"
SH
chmod 0755, $helper_driver
  or die "Unable to make $helper_driver executable: $!";

my ( $status, $output, $error ) = run_helper(
    'uuid',
    'fabric port',
    output => "11111111-2222-3333-4444-555555555555\n"
);
is( $status, 0, 'device UUID lookup returns nmcli success' );
is( $output, "11111111-2222-3333-4444-555555555555\n",
    'device UUID lookup preserves nmcli output' );
is( $error, '', 'successful device UUID lookup keeps stderr empty' );
is( read_file($scope_log), "device=<unset>\n",
    'device UUID lookup does not leak its local variable' );
is(
    read_file($command_log),
    command_line( 'nmcli', '-g', 'GENERAL.CON-UUID', 'device', 'show',
        'fabric', 'port' ),
    'device expansion preserves the existing literal nmcli arguments'
);

( $status, $output, $error ) = run_helper( 'uuid', 'eth0', output => '' );
is( $status, 0, 'empty UUID output keeps a successful nmcli status' );
is( $output, '', 'empty UUID output remains empty' );
is( $error, '', 'empty UUID output does not add stderr output' );

( $status, $output, $error ) = run_helper(
    'uuid',
    'eth0',
    output => "partial-output\n",
    error  => "nmcli-error\n",
    status => 17,
);
is( $status, 17, 'device UUID lookup preserves nmcli failure status' );
is( $output, "partial-output\n",
    'device UUID lookup preserves output from a failed nmcli command' );
is( $error, "nmcli-error\n",
    'device UUID lookup preserves stderr from a failed nmcli command' );

( $status, $output, $error ) = run_helper(
    'name',
    'eth1',
    name_output => "GENERAL.CONNECTION:  Wired connection 2\n",
);
is( $status, 0, 'device connection name lookup returns pipeline success' );
is( $output, "Wired connection 2\n",
    'device connection name lookup preserves the existing parsed output' );
is( $error, '', 'successful connection name lookup keeps stderr empty' );
is( read_file($scope_log), "device=<unset>\n",
    'device connection name lookup does not leak its local variable' );
is(
    read_file($command_log),
    command_line( 'nmcli', 'dev', 'show', 'eth1' ),
    'device connection name lookup preserves the existing nmcli command'
);

( $status, $output, $error ) = run_helper(
    'name',
    'eth1',
    name_output => "GENERAL.STATE:100 (connected)\n",
    name_error  => "nmcli-error\n",
    name_status => 17,
);
is( $status, 0,
    'connection name lookup preserves the output pipeline status' );
is( $output, '', 'an unmatched connection name remains empty' );
is( $error, "nmcli-error\n",
    'connection name lookup preserves nmcli stderr' );

my $caller_driver = File::Spec->catfile( $tmpdir, 'run-callers' );
write_file( $caller_driver, <<'SH' );
#!/bin/bash
source "$XCAT_TEST_NICUTILS" >/dev/null

nmcli_connection_uuid_for_device()
{
    printf 'uuid\t<%s>\n' "$1" >>"$XCAT_TEST_HELPER_LOG"
    printf 'uuid-%s\n' "$1"
}

nmcli_connection_name_for_device()
{
    printf 'name\t<%s>\n' "$1" >>"$XCAT_TEST_HELPER_LOG"
    printf 'Wired connection 2\n'
}

log_info() { return 0; }
log_warn() { return 0; }
log_error() { return 1; }
log_lines() { cat >/dev/null; }
query_nicnetworks_net() { printf 'test-network\n'; }
get_network_attr()
{
    [ "$2" = 'mask' ] && printf '255.255.255.0\n'
    return 0
}
v4mask2prefix() { printf '24\n'; }
get_first_addr_ipv4() { printf '%s\n' "$1"; }
check_and_set_device_managed() { return 0; }
is_nmcli_connection_exist() { return 1; }
add_extra_params_nmcli() { return 0; }
is_connection_activate_intime() { return 1; }
wait_for_ifstate() { return 0; }

case "$1" in
    bridge)
        create_bridge_interface_nmcli \
            ifname=br0 _brtype=bridge _pretype=ethernet \
            _port=eth0 _ipaddr=192.0.2.10
        ;;
    bond)
        create_bond_interface_nmcli \
            bondname=bond0 _ipaddr= slave_ports=eth1 slave_type=ethernet
        ;;
    *)
        exit 2
        ;;
esac
SH
chmod 0755, $caller_driver
  or die "Unable to make $caller_driver executable: $!";

$status = run_caller('bridge');
is( $status, 0, 'bridge setup completes with the shared device lookups' );
is( read_file($helper_log), "name\t<eth0>\nuuid\t<eth0>\n",
    'bridge setup resolves the existing profile name and UUID by device' );
is(
    read_file($command_log),
    join( '',
        command_line(
            'nmcli', 'con', 'add', 'type', 'bridge', 'con-name',
            'xcat-bridge-br0', 'ifname', 'br0',
            'connection.autoconnect-priority', '9', 'autoconnect', 'yes',
            'connection.autoconnect-retries', '0',
            'connection.autoconnect-slaves', '1'
        ),
        command_line(
            'nmcli', 'con', 'mod', 'uuid-eth0', 'master', 'br0',
            'connection.autoconnect-priority', '9', 'autoconnect', 'yes',
            'connection.autoconnect-slaves', '1',
            'connection.autoconnect-retries', '0'
        ),
        command_line(
            'nmcli', 'con', 'mod', 'xcat-bridge-br0', 'ipv4.method',
            'manual', 'ipv4.addresses', '192.0.2.10/24'
        ),
        command_line( 'nmcli', 'con', 'up', 'xcat-bridge-br0' ),
        command_line( 'nmcli', 'con', 'up', 'uuid-eth0' ),
        command_line( 'ip', 'address', 'show', 'dev', 'br0' ),
    ),
    'bridge setup uses the UUID returned for eth0'
);

$status = run_caller('bond');
is( $status, 0, 'bond setup completes with the shared device lookups' );
is( read_file($helper_log), "name\t<eth1>\nuuid\t<eth1>\n",
    'bond setup resolves a foreign space-containing profile by its device' );
is(
    read_file($command_log),
    join( '',
        command_line(
            'nmcli', 'con', 'add', 'type', 'bond', 'con-name',
            'xcat-bond-bond0', 'ifname', 'bond0', 'bond.options',
            'mode=802.3ad,miimon=100', 'ipv4.method', 'disabled',
            'ipv6.method', 'ignore', 'autoconnect', 'yes',
            'connection.autoconnect-priority', '9',
            'connection.autoconnect-slaves', '1',
            'connection.autoconnect-retries', '0'
        ),
        command_line( 'nmcli', 'con', 'down', 'uuid-eth1' ),
        command_line( 'nmcli', 'con', 'mod', 'uuid-eth1',
            'autoconnect', 'no' ),
        command_line( 'ip', 'link', 'set', 'dev', 'eth1', 'down' ),
        command_line(
            'nmcli', 'con', 'add', 'type', 'Ethernet', 'con-name',
            'xcat-bond-slave-eth1', 'ifname', 'eth1', 'master',
            'xcat-bond-bond0', 'slave-type', 'bond', 'autoconnect', 'yes',
            'connection.autoconnect-priority', '9',
            'connection.autoconnect-retries', '0'
        ),
        command_line( 'nmcli', 'con', 'up', 'xcat-bond-slave-eth1' ),
        command_line( 'nmcli', 'con', 'up', 'xcat-bond-bond0' ),
    ),
    'bond setup uses the distinct UUID returned for eth1'
);

done_testing();

sub run_helper
{
    my ( $helper, $device, %options ) = @_;
    write_file( $command_log, '' );

    local %ENV = %ENV;
    $ENV{PATH} = "$test_bin:$ENV{PATH}";
    $ENV{XCAT_TEST_COMMAND_LOG} = $command_log;
    $ENV{XCAT_TEST_NICUTILS} = $nicutils;
    $ENV{XCAT_TEST_SCOPE_LOG} = $scope_log;
    $ENV{XCAT_TEST_NMCLI_ERROR} = $options{error} // '';
    $ENV{XCAT_TEST_NMCLI_OUTPUT} = $options{output} // '';
    $ENV{XCAT_TEST_NMCLI_STATUS} = $options{status} // 0;
    $ENV{XCAT_TEST_NMCLI_NAME_ERROR} = $options{name_error} // '';
    $ENV{XCAT_TEST_NMCLI_NAME_OUTPUT} = $options{name_output} // '';
    $ENV{XCAT_TEST_NMCLI_NAME_STATUS} = $options{name_status} // 0;
    delete $ENV{XCAT_TEST_FORBID_UUID_QUERY};

    my $stderr = gensym;
    my $pid = open3( my $stdin, my $stdout, $stderr,
        '/bin/bash', $helper_driver, $helper, $device );
    close($stdin) or die "Unable to close helper stdin: $!";
    my $captured_output = do { local $/; <$stdout> };
    my $captured_error = do { local $/; <$stderr> };
    waitpid( $pid, 0 );
    my $exit_status = $? == -1 ? 255 : $? >> 8;
    return ( $exit_status, $captured_output, $captured_error );
}

sub run_caller
{
    my ($scenario) = @_;
    write_file( $command_log, '' );
    write_file( $helper_log, '' );

    local %ENV = %ENV;
    $ENV{PATH} = "$test_bin:$ENV{PATH}";
    $ENV{XCAT_TEST_COMMAND_LOG} = $command_log;
    $ENV{XCAT_TEST_HELPER_LOG} = $helper_log;
    $ENV{XCAT_TEST_NICUTILS} = $nicutils;
    $ENV{XCAT_TEST_FORBID_UUID_QUERY} = 1;
    $ENV{XCAT_TEST_NMCLI_NAME_OUTPUT} =
      "GENERAL.CONNECTION:Wired connection 2\n";

    my $status = system( '/bin/bash', $caller_driver, $scenario );
    return $status == -1 ? 255 : $status >> 8;
}

sub command_line
{
    my ( $command, @arguments ) = @_;
    return join( '', $command, map { "\t<$_>" } @arguments ) . "\n";
}

sub write_file
{
    my ( $path, $contents ) = @_;
    open( my $fh, '>:raw', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh) or die "Unable to close $path: $!";
}

sub read_file
{
    my ($path) = @_;
    open( my $fh, '<:raw', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "Unable to close $path: $!";
    return $contents;
}
