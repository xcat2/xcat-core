#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $dispatcher = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-hardware-control files genesis-hardware)
);
my $nvme_provider = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-hardware-control files provider-nvme)
);
my $mstflint_provider = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-hardware-control files provider-mstflint)
);
my $iprutils_provider = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-hardware-control files provider-iprutils)
);

sub write_file {
    my ( $path, $contents, $mode ) = @_;
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh);
    chmod( $mode, $path ) if defined($mode);
}

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

sub shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub run_command {
    my ( $environment, @command ) = @_;
    local %ENV = ( %ENV, %{$environment} );
    my $shell_command = join( ' ', map { shell_quote($_) } @command );
    my $output = qx{$shell_command 2>&1};
    return ( $? >> 8, $output );
}

sub decode_output {
    my ($output) = @_;
    return JSON::PP->new->decode($output);
}

my $root = tempdir( CLEANUP => 1 );
my $bin = File::Spec->catdir( $root, 'bin' );
my $manifests = File::Spec->catdir( $root, 'manifests' );
my $executables = File::Spec->catdir( $root, 'providers' );
my $audit = File::Spec->catfile( $root, 'audit', 'hardware.jsonl' );
my $request = File::Spec->catfile( $root, 'request.json' );
make_path( $bin, $manifests, $executables );

write_file(
    File::Spec->catfile( $bin, 'timeout' ),
    <<'SH', 0755
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        --signal=*|--kill-after=*) shift ;;
        *) break ;;
    esac
done
shift
exec "$@"
SH
);
write_file( File::Spec->catfile( $bin, 'flock' ), "#!/bin/sh\nexit 0\n", 0755 );
write_file(
    File::Spec->catfile( $executables, 'mock' ),
    <<'SH', 0755
#!/bin/sh
case "$1" in
    probe)
        printf '%s\n' '{"detected":true,"devices":["controller0"]}'
        ;;
    run)
        case "$2" in
            storage.inventory) printf '%s\n' '{"devices":["controller0"]}' ;;
            storage.array.create) printf '{"created":"%s"}\n' "$3" ;;
            storage.array.delete) printf '%s\n' 'delete failed' >&2; exit 9 ;;
            storage.logs) printf '%s\n' 'not-json' ;;
            *) exit 8 ;;
        esac
        ;;
    *) exit 7 ;;
esac
SH
);
write_file(
    File::Spec->catfile( $manifests, 'mock.json' ),
    JSON::PP->new->canonical->pretty->encode(
        {
            capabilities => [
                { destructive => JSON::PP::false, name => 'storage.inventory' },
                { destructive => JSON::PP::false, name => 'storage.logs' },
                { destructive => JSON::PP::true,  name => 'storage.array.create' },
                { destructive => JSON::PP::true,  name => 'storage.array.delete' },
            ],
            kind    => 'storage',
            name    => 'mock',
            schema  => 1,
            version => '1.0',
        }
    )
);
write_file( $request, "{\"level\":\"1\"}\n" );

my %environment = (
    PATH                           => "$bin:$ENV{PATH}",
    XCAT_GENESIS_HARDWARE_AUDIT   => $audit,
    XCAT_GENESIS_PROVIDER_DIR     => $manifests,
    XCAT_GENESIS_PROVIDER_EXEC_DIR => $executables,
    XCAT_GENESIS_PROVIDER_TIMEOUT => 5,
);

my ( $status, $output ) =
  run_command( \%environment, '/bin/bash', $dispatcher, 'providers' );
is( $status, 0, 'provider list is accepted' ) or diag($output);
is( decode_output($output)->{providers}->[0]->{name}, 'mock',
    'provider list returns the manifest' );

( $status, $output ) =
  run_command( \%environment, '/bin/bash', $dispatcher, 'capabilities', 'mock' );
is( $status, 0, 'provider capabilities are accepted' ) or diag($output);
is( scalar @{ decode_output($output)->{capabilities} }, 4,
    'provider capabilities are returned' );

( $status, $output ) =
  run_command( \%environment, '/bin/bash', $dispatcher, 'probe', 'mock' );
is( $status, 0, 'provider probe succeeds' ) or diag($output);
ok( decode_output($output)->{probes}->[0]->{result}->{detected},
    'provider probe returns detected hardware' );

( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock', 'storage.inventory'
);
is( $status, 0, 'read-only capability succeeds' ) or diag($output);
is( decode_output($output)->{result}->{devices}->[0], 'controller0',
    'read-only result is normalized' );
ok( !-e $audit, 'read-only capability is not audited as a change' );

for my $case (
    [ [], 'destructive capability requires a task identity' ],
    [ [ '--task-id', 'task-1', '--request', $request ],
        'destructive capability requires an exact device' ],
    [ [ '--task-id', 'task-1', '--device-id', 'controller0' ],
        'destructive capability requires a request' ],
    [ [ '--task-id', 'task-1', '--device-id', 'all', '--request', $request ],
        'destructive capability rejects a wildcard device' ],
  )
{
    ( $status, $output ) = run_command(
        \%environment, '/bin/bash', $dispatcher, 'run', 'mock',
        'storage.array.create', @{ $case->[0] }
    );
    isnt( $status, 0, $case->[1] );
}

( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock',
    'storage.array.create', '--task-id', 'task-1', '--device-id', 'controller0',
    '--request', $request
);
is( $status, 0, 'authorized destructive capability succeeds' ) or diag($output);
is( decode_output($output)->{result}->{created}, 'controller0',
    'destructive result is normalized' );
my @audit_records = map { decode_output($_) } split( /\n/, read_file($audit) );
is_deeply( [ map { $_->{phase} } @audit_records ], [ 'started', 'completed' ],
    'successful change has a closed audit trail' );
is( $audit_records[0]->{task_id}, 'task-1',
    'audit record carries the task identity' );
like( $audit_records[0]->{request_sha256}, qr/^[0-9a-f]{64}$/,
    'audit record carries the request digest' );

( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock',
    'storage.array.delete', '--task-id', 'task-2', '--device-id', 'controller0',
    '--request', $request
);
isnt( $status, 0, 'provider failure is returned' );
@audit_records = map { decode_output($_) } split( /\n/, read_file($audit) );
is_deeply( [ map { $_->{phase} } @audit_records ],
    [ 'started', 'completed', 'started', 'failed' ],
    'failed change has a closed audit trail' );

( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock', 'storage.logs'
);
isnt( $status, 0, 'invalid provider JSON is rejected' );
( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock', 'storage.unknown'
);
isnt( $status, 0, 'undeclared capability is rejected' );

my $linked_manifest = File::Spec->catfile( $manifests, 'linked.json' );
symlink( File::Spec->catfile( $manifests, 'mock.json' ), $linked_manifest )
  or die "Unable to create $linked_manifest: $!";
( $status, $output ) =
  run_command( \%environment, '/bin/bash', $dispatcher, 'providers' );
isnt( $status, 0, 'linked provider manifest is rejected' );
unlink($linked_manifest) or die "Unable to remove $linked_manifest: $!";

my $invalid_manifest = File::Spec->catfile( $manifests, 'invalid.json' );
write_file( $invalid_manifest, "{}\n" );
( $status, $output ) =
  run_command( \%environment, '/bin/bash', $dispatcher, 'providers' );
isnt( $status, 0, 'invalid provider manifest is rejected' );
unlink($invalid_manifest) or die "Unable to remove $invalid_manifest: $!";

my $mock_executable = File::Spec->catfile( $executables, 'mock' );
my $real_executable = File::Spec->catfile( $executables, 'mock.real' );
rename( $mock_executable, $real_executable )
  or die "Unable to rename $mock_executable: $!";
symlink( $real_executable, $mock_executable )
  or die "Unable to link $mock_executable: $!";
( $status, $output ) =
  run_command( \%environment, '/bin/bash', $dispatcher, 'probe', 'mock' );
isnt( $status, 0, 'linked provider executable is rejected' );
unlink($mock_executable) or die "Unable to remove $mock_executable: $!";
rename( $real_executable, $mock_executable )
  or die "Unable to restore $mock_executable: $!";

my $linked_request = File::Spec->catfile( $root, 'linked-request.json' );
symlink( $request, $linked_request ) or die "Unable to link $linked_request: $!";
( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock',
    'storage.array.create', '--task-id', 'task-3', '--device-id', 'controller0',
    '--request', $linked_request
);
isnt( $status, 0, 'linked hardware request is rejected' );

my %bad_timeout = ( %environment, XCAT_GENESIS_PROVIDER_TIMEOUT => 0 );
( $status, $output ) =
  run_command( \%bad_timeout, '/bin/bash', $dispatcher, 'providers' );
isnt( $status, 0, 'invalid provider timeout is rejected' );

unlink("$audit.lock") or die "Unable to remove $audit.lock: $!";
my $lock_target = File::Spec->catfile( $root, 'lock-target' );
write_file( $lock_target, "unchanged\n" );
symlink( $lock_target, "$audit.lock" ) or die "Unable to link audit lock: $!";
( $status, $output ) = run_command(
    \%environment, '/bin/bash', $dispatcher, 'run', 'mock',
    'storage.array.create', '--task-id', 'task-3', '--device-id', 'controller0',
    '--request', $request
);
isnt( $status, 0, 'linked audit lock is rejected' );
is( read_file($lock_target), "unchanged\n", 'linked audit target is untouched' );

write_file(
    File::Spec->catfile( $bin, 'nvme' ),
    "#!/bin/sh\nprintf '{\"arguments\":\"%s\"}\\n' \"\$*\"\n", 0755
);
my $sys_nvme = File::Spec->catdir( $root, 'sys', 'class', 'nvme' );
my $dev = File::Spec->catdir( $root, 'dev' );
make_path( File::Spec->catdir( $sys_nvme, 'nvme0' ), $dev );
write_file( File::Spec->catfile( $dev, 'nvme0' ), '' );
my %nvme_environment = (
    PATH                        => "$bin:$ENV{PATH}",
    XCAT_GENESIS_DEV_DIR        => $dev,
    XCAT_GENESIS_SYS_CLASS_NVME => $sys_nvme,
);
( $status, $output ) =
  run_command( \%nvme_environment, '/bin/bash', $nvme_provider, 'probe' );
is( $status, 0, 'NVMe probe succeeds' ) or diag($output);
is( decode_output($output)->{devices}->[0], 'nvme0',
    'NVMe probe returns an exact controller identity' );
( $status, $output ) = run_command(
    \%nvme_environment, '/bin/bash', $nvme_provider, 'run', 'storage.health',
    'nvme0', '-'
);
is( $status, 0, 'NVMe health query succeeds' ) or diag($output);
like( decode_output($output)->{arguments}, qr{smart-log .*/nvme0 -o json},
    'NVMe health query uses the selected controller' );
( $status, $output ) = run_command(
    \%nvme_environment, '/bin/bash', $nvme_provider, 'run', 'storage.health',
    'nvme0n1', '-'
);
isnt( $status, 0, 'NVMe provider rejects a namespace identity' );

write_file(
    File::Spec->catfile( $bin, 'mstflint' ),
    "#!/bin/sh\nprintf '%s\\n' 'firmware query'\n", 0755
);
my $pci = File::Spec->catdir( $root, 'sys', 'bus', 'pci', 'devices' );
my $mellanox = File::Spec->catdir( $pci, '0000:03:00.0' );
my $other = File::Spec->catdir( $pci, '0000:04:00.0' );
make_path( $mellanox, $other );
write_file( File::Spec->catfile( $mellanox, 'vendor' ), "0x15b3\n" );
write_file( File::Spec->catfile( $other, 'vendor' ), "0x8086\n" );
my %mstflint_environment = (
    PATH                         => "$bin:$ENV{PATH}",
    XCAT_GENESIS_SYS_PCI_DEVICES => $pci,
);
( $status, $output ) =
  run_command( \%mstflint_environment, '/bin/bash', $mstflint_provider, 'probe' );
is( $status, 0, 'mstflint probe succeeds' ) or diag($output);
is_deeply( decode_output($output)->{devices}, ['0000:03:00.0'],
    'mstflint probe returns supported PCI devices' );
( $status, $output ) = run_command(
    \%mstflint_environment, '/bin/bash', $mstflint_provider, 'run',
    'network.firmware.inventory', '0000:03:00.0', '-'
);
is( $status, 0, 'mstflint inventory succeeds' ) or diag($output);
is( decode_output($output)->{raw}, 'firmware query',
    'mstflint inventory returns the tool output' );
( $status, $output ) = run_command(
    \%mstflint_environment, '/bin/bash', $mstflint_provider, 'run',
    'network.firmware.inventory', '0000:04:00.0', '-'
);
isnt( $status, 0, 'mstflint provider rejects another vendor' );

write_file(
    File::Spec->catfile( $bin, 'iprconfig' ),
    <<'SH', 0755
#!/bin/sh
case "$*" in
    '-c show-config') printf '%s\n' 'Power RAID configuration' ;;
    '-c show-arrays') printf '%s\n' 'Power RAID arrays healthy' ;;
    '-c show-ucode-levels') printf '%s\n' 'Power RAID firmware levels' ;;
    *) exit 2 ;;
esac
SH
);
my $scsi_hosts = File::Spec->catdir( $root, 'sys', 'class', 'scsi_host' );
my $ipr_host = File::Spec->catdir( $scsi_hosts, 'host0' );
my $other_host = File::Spec->catdir( $scsi_hosts, 'host1' );
make_path( $ipr_host, $other_host );
write_file( File::Spec->catfile( $ipr_host, 'proc_name' ), "ipr\n" );
write_file( File::Spec->catfile( $other_host, 'proc_name' ), "megaraid_sas\n" );
my %iprutils_environment = (
    PATH                       => "$bin:$ENV{PATH}",
    XCAT_GENESIS_SYS_SCSI_HOSTS => $scsi_hosts,
);
( $status, $output ) =
  run_command( \%iprutils_environment, '/bin/bash', $iprutils_provider, 'probe' );
is( $status, 0, 'iprutils probe succeeds' ) or diag($output);
is_deeply( decode_output($output)->{devices}, ['host0'],
    'iprutils probe returns Power RAID hosts' );

for my $case (
    [ 'storage.inventory',          'Power RAID configuration' ],
    [ 'storage.health',             'Power RAID arrays healthy' ],
    [ 'storage.firmware.inventory', 'Power RAID firmware levels' ],
  )
{
    ( $status, $output ) = run_command(
        \%iprutils_environment, '/bin/bash', $iprutils_provider, 'run',
        $case->[0], 'host0', '-'
    );
    is( $status, 0, "iprutils $case->[0] succeeds" ) or diag($output);
    is( decode_output($output)->{raw}, $case->[1],
        "iprutils $case->[0] returns the tool output" );
}

( $status, $output ) = run_command(
    \%iprutils_environment, '/bin/bash', $iprutils_provider, 'run',
    'storage.array.create', 'host0', '-'
);
isnt( $status, 0, 'iprutils provider rejects destructive operations' );

done_testing();
