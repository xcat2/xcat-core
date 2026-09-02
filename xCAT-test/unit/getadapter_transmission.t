#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use POSIX qw(_exit);
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $getadapter_relative = 'xCAT-genesis-scripts/usr/bin/getadapter';
my ( $source_getadapter, $getadapter_source );
if ( defined $ENV{XCAT_TEST_GETADAPTER} ) {
    $source_getadapter = $ENV{XCAT_TEST_GETADAPTER};
    die 'XCAT_TEST_GETADAPTER must name a readable regular file'
      unless length($source_getadapter)
      && -f $source_getadapter
      && -r _;
    $getadapter_source = read_file($source_getadapter);
}
else {
    $source_getadapter = repo_path($getadapter_relative);
    plan skip_all => "$source_getadapter is required"
      unless -f $source_getadapter && -r _;
    $getadapter_source = slurp_repo_file($getadapter_relative);
}

is( system( 'bash', '-n', $source_getadapter ), 0,
    'getadapter has valid Bash syntax' );

my $expected_request = <<'XML';
<xcatrequest>
<command>getadapter</command>
<action>update</action>
</xcatrequest>
XML

my $master_plain = run_scenario(
    master         => '198.51.100.10',
    lease          => "option dhcp-server-identifier 192.0.2.20;\n",
    openssl_status => 7,
    openssl_stdout => "TLS output\n",
    openssl_stderr => "TLS error\n",
);
is( $master_plain->{status}, 7,
    'master transmission preserves the OpenSSL failure status' );
is( $master_plain->{stdout}, '', 'master transmission keeps stdout empty' );
is( $master_plain->{stderr}, '', 'master transmission keeps stderr empty' );
is(
    $master_plain->{args},
    "s_client\n-connect\n198.51.100.10:3001\n",
    'master transmission without certificates preserves OpenSSL arguments'
);
is( $master_plain->{sent}, $master_plain->{request},
    'master transmission sends the generated request unchanged' );
is( $master_plain->{request}, $expected_request,
    'master transmission preserves the generated request' );
is(
    $master_plain->{log},
    "transmit scan result without customer certificate to 198.51.100.10\n"
      . "TLS output\nTLS error\n",
    'master transmission preserves its log message and OpenSSL output'
);

my $master_cert = run_scenario(
    master         => '198.51.100.11',
    lease          => "option dhcp-server-identifier 192.0.2.21;\n",
    certificates   => 'both',
    openssl_status => 8,
    openssl_stdout => "authenticated TLS output\n",
    openssl_stderr => "authenticated TLS error\n",
);
is( $master_cert->{status}, 8,
    'master certificate transmission preserves the OpenSSL failure status' );
is( $master_cert->{stdout}, '',
    'master certificate transmission keeps stdout empty' );
is( $master_cert->{stderr}, '',
    'master certificate transmission keeps stderr empty' );
is(
    $master_cert->{args},
    "s_client\n-key\n$master_cert->{key_file}\n-cert\n"
      . "$master_cert->{cert_file}\n-connect\n198.51.100.11:3001\n",
    'master transmission with certificates preserves OpenSSL arguments'
);
is( $master_cert->{sent}, $master_cert->{request},
    'certificate transmission sends the generated request unchanged' );
is( $master_cert->{request}, $expected_request,
    'certificate transmission preserves the generated request' );
is(
    $master_cert->{log},
    "using $master_cert->{key_file} and $master_cert->{cert_file} "
      . "to transmit scan result to 198.51.100.11\n"
      . "authenticated TLS output\nauthenticated TLS error\n",
    'master certificate transmission preserves its log and OpenSSL output'
);

my $stale_adapter = run_scenario(
    master          => '198.51.100.14',
    initial_adapter => "stale adapter data\n",
    openssl_stdout  => "replacement TLS output\n",
);
is( $stale_adapter->{status}, 0,
    'transmission after stale adapter cleanup completes' );
is( $stale_adapter->{request}, $expected_request,
    'stale adapter data is replaced by the generated request' );
is(
    $stale_adapter->{log},
    "rm -f $stale_adapter->{adapter_file}\n"
      . "transmit scan result without customer certificate to 198.51.100.14\n"
      . "replacement TLS output\n",
    'transmission appends its message and output to the cleanup log'
);

my $dhcp_plain = run_scenario(
    lease          => "option dhcp-server-identifier 192.0.2.30;\n"
      . "option dhcp-server-identifier 198.51.100.30;\n",
    openssl_status => 9,
);
is( $dhcp_plain->{status}, 9,
    'DHCP-derived transmission preserves the OpenSSL failure status' );
is(
    $dhcp_plain->{args},
    "s_client\n-connect\n198.51.100.30:3001\n",
    'the latest DHCP-derived target is transmitted without certificates'
);
is(
    $dhcp_plain->{log},
    "transmit scan result without customer certificate to 198.51.100.30\n",
    'DHCP-derived transmission without certificates preserves its log message'
);

my $dhcp_cert = run_scenario(
    lease        => "option dhcp-server-identifier 198.51.100.31;\n",
    certificates => 'both',
);
is( $dhcp_cert->{status}, 0,
    'DHCP-derived transmission with certificates completes' );
is(
    $dhcp_cert->{args},
    "s_client\n-key\n$dhcp_cert->{key_file}\n-cert\n"
      . "$dhcp_cert->{cert_file}\n-connect\n198.51.100.31:3001\n",
    'DHCP-derived transmission with certificates preserves OpenSSL arguments'
);
is(
    $dhcp_cert->{log},
    "using $dhcp_cert->{key_file} and $dhcp_cert->{cert_file} "
      . "to transmit scan result to 198.51.100.31\n",
    'DHCP-derived certificate transmission preserves its log message'
);

my $partial_cert = run_scenario(
    master       => '198.51.100.12',
    certificates => 'cert_only',
);
is( $partial_cert->{status}, 0,
    'transmission with only one certificate file completes' );
is(
    $partial_cert->{args},
    "s_client\n-connect\n198.51.100.12:3001\n",
    'one certificate file retains the unauthenticated transport path'
);
is(
    $partial_cert->{log},
    "transmit scan result without customer certificate to 198.51.100.12\n",
    'one certificate file retains the unauthenticated log message'
);

my $partial_key = run_scenario(
    master       => '198.51.100.13',
    certificates => 'key_only',
);
is( $partial_key->{status}, 0,
    'transmission with only the private-key file completes' );
is(
    $partial_key->{args},
    "s_client\n-connect\n198.51.100.13:3001\n",
    'one private-key file retains the unauthenticated transport path'
);
is(
    $partial_key->{log},
    "transmit scan result without customer certificate to 198.51.100.13\n",
    'one private-key file retains the unauthenticated log message'
);

my $no_target = run_scenario( lease => '' );
is( $no_target->{status}, 0, 'no transmission target remains a no-op' );
is( $no_target->{stdout}, '', 'no target keeps stdout empty' );
is( $no_target->{stderr}, '', 'no target keeps stderr empty' );
is( $no_target->{args}, '', 'no target does not invoke OpenSSL' );
is( $no_target->{sent}, '', 'no target does not transmit a request' );
is( $no_target->{log}, '', 'no target does not create a scan log' );
is( $no_target->{request}, $expected_request,
    'no target still preserves the generated request' );

done_testing();

sub run_scenario
{
    my (%option) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $bin = File::Spec->catdir( $root, 'bin' );
    my $sys_class_net = File::Spec->catdir( $root, 'net-fixture' );
    my $cert_dir = File::Spec->catdir( $root, 'cert-fixture' );
    my $lease_dir = File::Spec->catdir( $root, 'lease-fixture' );
    make_path( $bin, File::Spec->catdir( $sys_class_net, 'lo' ),
        $cert_dir, $lease_dir );

    my $adapter_file = File::Spec->catfile( $root, 'adapterinfo' );
    my $scan_log = File::Spec->catfile( $root, 'adapterscan.log' );
    my $cert_file = File::Spec->catfile( $cert_dir, 'cert.pem' );
    my $key_file = File::Spec->catfile( $cert_dir, 'certkey.pem' );
    my $lease_file = File::Spec->catfile( $lease_dir, 'dhclient.leases' );
    my $getadapter = File::Spec->catfile( $root, 'getadapter' );
    my $args_file = File::Spec->catfile( $root, 'openssl.args' );
    my $request_copy = File::Spec->catfile( $root, 'request.xml' );
    my $stdout_file = File::Spec->catfile( $root, 'stdout' );
    my $stderr_file = File::Spec->catfile( $root, 'stderr' );

    my $body = $getadapter_source;
    replace_required( \$body, '/tmp/adapterinfo', $adapter_file );
    replace_required( \$body, '/tmp/adapterscan.log', $scan_log );
    replace_required( \$body, '/sys/class/net', $sys_class_net );
    replace_required( \$body, '/etc/xcat/cert.pem', $cert_file );
    replace_required( \$body, '/etc/xcat/certkey.pem', $key_file );
    replace_required( \$body, '/var/lib/dhclient/dhclient.leases',
        $lease_file );
    write_executable( $getadapter, $body );

    write_executable( File::Spec->catfile( $bin, 'lspci' ),
        "#!/bin/sh\nexit 0\n" );
    write_executable(
        File::Spec->catfile( $bin, 'openssl' ),
        <<'SH'
#!/bin/sh
: >"$XCAT_TEST_OPENSSL_ARGS"
for argument in "$@"; do
    printf '%s\n' "$argument" >>"$XCAT_TEST_OPENSSL_ARGS"
done
printf '%s' "$XCAT_TEST_OPENSSL_STDOUT"
printf '%s' "$XCAT_TEST_OPENSSL_STDERR" >&2
/bin/cat >"$XCAT_TEST_REQUEST_COPY"
exit "$XCAT_TEST_OPENSSL_STATUS"
SH
    );

    write_file( $lease_file, $option{lease} // '' );
    if ( ( $option{certificates} // '' ) =~ /^(?:both|cert_only)$/ ) {
        write_file( $cert_file, "certificate\n" );
    }
    if ( ( $option{certificates} // '' ) =~ /^(?:both|key_only)$/ ) {
        write_file( $key_file, "private key\n" );
    }
    if ( defined $option{initial_adapter} ) {
        write_file( $adapter_file, $option{initial_adapter} );
    }

    local %ENV = (
        %ENV,
        PATH                     => "$bin:$ENV{PATH}",
        XCAT_TEST_OPENSSL_ARGS   => $args_file,
        XCAT_TEST_OPENSSL_STATUS => $option{openssl_status} // 0,
        XCAT_TEST_OPENSSL_STDOUT => $option{openssl_stdout} // '',
        XCAT_TEST_OPENSSL_STDERR => $option{openssl_stderr} // '',
        XCAT_TEST_REQUEST_COPY   => $request_copy,
    );
    if ( defined $option{master} ) {
        $ENV{XCATMASTER} = $option{master};
    }
    else {
        delete $ENV{XCATMASTER};
    }

    my $pid = fork();
    die "Unable to fork getadapter: $!" unless defined $pid;
    if ( $pid == 0 ) {
        open( STDIN, '<', '/dev/null' ) or _exit(126);
        open( STDOUT, '>:raw', $stdout_file ) or _exit(126);
        open( STDERR, '>:raw', $stderr_file ) or _exit(126);
        exec 'bash', $getadapter or _exit(127);
    }
    my $reaped = waitpid( $pid, 0 );
    my $raw_status = $?;
    my $status = $reaped == $pid && !( $raw_status & 127 )
      ? $raw_status >> 8
      : 255;

    return {
        status    => $status,
        stdout    => read_optional($stdout_file),
        stderr    => read_optional($stderr_file),
        args      => read_optional($args_file),
        sent      => read_optional($request_copy),
        log       => read_optional($scan_log),
        request   => read_optional($adapter_file),
        cert_file => $cert_file,
        key_file  => $key_file,
        adapter_file => $adapter_file,
    };
}

sub replace_required
{
    my ( $body_ref, $from, $to ) = @_;
    my $count = $$body_ref =~ s/\Q$from\E/$to/g;
    die "Unable to sandbox $from" unless $count;
    die "Sandbox rewrite left $from in getadapter"
      if index( $$body_ref, $from ) >= 0;
}

sub write_executable
{
    my ( $file, $contents ) = @_;
    write_file( $file, $contents );
    chmod 0755, $file or die "Unable to make $file executable: $!";
}

sub write_file
{
    my ( $file, $contents ) = @_;
    open( my $fh, '>:raw', $file ) or die "Unable to write $file: $!";
    print {$fh} $contents;
    close($fh) or die "Unable to close $file: $!";
}

sub read_file
{
    my ($file) = @_;
    open( my $fh, '<:raw', $file ) or die "Unable to read $file: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "Unable to close $file: $!";
    return $contents;
}

sub read_optional
{
    my ($file) = @_;
    return '' unless -f $file;
    return read_file($file) // '';
}
