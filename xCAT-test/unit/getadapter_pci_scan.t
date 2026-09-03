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

use XCAT::Test::File qw(repo_path);

my $source_getadapter;
if ( defined $ENV{XCAT_TEST_GETADAPTER} ) {
    $source_getadapter = $ENV{XCAT_TEST_GETADAPTER};
    die "XCAT_TEST_GETADAPTER=$source_getadapter is not a readable file"
      unless length($source_getadapter)
      && -f $source_getadapter
      && -r _;
}
else {
    $source_getadapter =
      repo_path('xCAT-genesis-scripts/usr/bin/getadapter');
}
plan skip_all => "$source_getadapter is required"
  unless -f $source_getadapter && -r _;

my $tmpdir = tempdir( CLEANUP => 1 );
my $test_bin       = File::Spec->catdir( $tmpdir, 'bin' );
my $sys_class_net  = File::Spec->catdir( $tmpdir, 'sys', 'class', 'net' );
my $adapter_file   = File::Spec->catfile( $tmpdir, 'adapterinfo' );
my $scan_log       = File::Spec->catfile( $tmpdir, 'adapterscan.log' );
my $getadapter     = File::Spec->catfile( $tmpdir, 'getadapter' );
my $stdout_file    = File::Spec->catfile( $tmpdir, 'stdout' );
my $stderr_file    = File::Spec->catfile( $tmpdir, 'stderr' );
my $test_interface = File::Spec->catdir( $sys_class_net, 'eth0' );
make_path( $test_bin, $test_interface );

my $getadapter_body = read_file($source_getadapter);
my $adapter_file_rewrites =
  $getadapter_body =~ s{/tmp/adapterinfo}{$adapter_file}g;
my $scan_log_rewrites =
  $getadapter_body =~ s{/tmp/adapterscan\.log}{$scan_log}g;
my $sysfs_rewrites =
  $getadapter_body =~ s{/sys/class/net}{$sys_class_net}g;
die 'Unable to sandbox getadapter adapter file'
  unless $adapter_file_rewrites;
die 'Unable to sandbox getadapter scan log'
  unless $scan_log_rewrites;
die 'Unable to sandbox getadapter sysfs paths'
  unless $sysfs_rewrites;
write_executable( $getadapter, $getadapter_body );
write_file( File::Spec->catfile( $test_interface, 'address' ),
    "aa:bb:cc:dd:ee:ff\n" );

is( system( 'bash', '-n', $getadapter ), 0,
    'getadapter has valid Bash syntax' );

my $lspci_fixture = File::Spec->catfile( $tmpdir, 'lspci.txt' );
my $lspci_log     = File::Spec->catfile( $tmpdir, 'lspci.log' );
my $request_copy  = File::Spec->catfile( $tmpdir, 'request.xml' );

write_executable(
    File::Spec->catfile( $test_bin, 'lspci' ),
    <<'SH'
#!/bin/sh
printf 'lspci\n' >>"$XCAT_TEST_LSPCI_LOG"
/bin/cat "$XCAT_TEST_LSPCI_FIXTURE"
SH
);

write_executable(
    File::Spec->catfile( $test_bin, 'udevadm' ),
    <<'SH'
#!/bin/sh
interface=${2##*/}
printf 'E: INTERFACE=%s\n' "$interface"
printf 'E: DEVPATH=/devices/pci0000:00/0000:01:00.0/net/%s\n' "$interface"
SH
);

write_executable(
    File::Spec->catfile( $test_bin, 'ip' ),
    "#!/bin/sh\nexit 0\n"
);

write_executable(
    File::Spec->catfile( $test_bin, 'openssl' ),
    <<'SH'
#!/bin/sh
/bin/cat >"$XCAT_TEST_REQUEST_COPY"
SH
);

write_file(
    $lspci_fixture,
    <<'LSPCI'
01:00.0 Ethernet controller: Existing Ethernet Adapter
02:00.0 Ethernet controller: Mellanox Ethernet Adapter
03:00.0 Network controller: Mellanox Network Adapter
04:00.0 Network controller: Wireless Adapter
05:00.0 Audio device: Example Audio Device
06:00.0 Infiniband controller: Mellanox Technologies MT27800
LSPCI
);

my ( $status, $stdout, $stderr ) = run_getadapter();
is( $status, 0, 'getadapter completes with overlapping PCI classes' );
is( $stdout, '', 'getadapter keeps stdout empty' );
is( $stderr, '', 'getadapter keeps stderr empty' );

my $request = read_file($adapter_file);
is( read_file($request_copy), $request,
    'getadapter transmits the generated request unchanged' );
like(
    $request,
    qr{\A<xcatrequest>\n<command>getadapter</command>\n<action>update</action>},
    'getadapter preserves the request header'
);
like( $request, qr{</xcatrequest>\n\z},
    'getadapter preserves the request terminator' );

my @missing_pci = $request =~ m{<pcilocation>([0-9][^<]+)</pcilocation>}g;
is_deeply(
    \@missing_pci,
    [ qw(02:00.0 03:00.0 04:00.0 06:00.0) ],
    'missing adapters retain Ethernet, Network, and Mellanox scan order'
);

my @missing_models = $request =~ m{<model>([^<]*)</model>}g;
is_deeply(
    \@missing_models,
    [
        ' Mellanox Ethernet Adapter',
        'Mellanox Network Adapter',
        'Wireless Adapter',
        'Mellanox Technologies MT27800'
    ],
    'missing adapters retain their legacy model spacing'
);
unlike( $request, qr{<model>.*Existing Ethernet Adapter</model>},
    'an adapter already recorded by sysfs is not appended again' );
is( line_count($lspci_log), 7,
    'overlapping Mellanox adapters do not trigger duplicate detail lookups' );

write_file( $lspci_fixture,
    "05:00.0 Audio device: Example Audio Device\n" );
write_file( $lspci_log, '' );

( $status, $stdout, $stderr ) = run_getadapter();
is( $status, 0, 'getadapter completes when no PCI class matches' );
is( $stdout, '', 'an empty PCI scan keeps stdout empty' );
is( $stderr, '', 'an empty PCI scan keeps stderr empty' );
$request = read_file($adapter_file);
my @empty_models = $request =~ m{<model>([^<]*)</model>}g;
is_deeply( \@empty_models, [],
    'an empty PCI scan does not append missing adapter models' );
is( line_count($lspci_log), 3,
    'an empty PCI scan queries each adapter class once' );

done_testing();

sub run_getadapter
{
    local %ENV = (
        %ENV,
        PATH                     => "$test_bin:$ENV{PATH}",
        XCATMASTER               => '192.0.2.1',
        XCAT_TEST_LSPCI_FIXTURE  => $lspci_fixture,
        XCAT_TEST_LSPCI_LOG      => $lspci_log,
        XCAT_TEST_REQUEST_COPY   => $request_copy,
    );

    my $pid = fork();
    die "Unable to fork getadapter: $!" unless defined $pid;
    if ( $pid == 0 ) {
        open( STDOUT, '>:raw', $stdout_file ) or _exit(126);
        open( STDERR, '>:raw', $stderr_file ) or _exit(126);
        exec 'bash', $getadapter or _exit(127);
    }
    my $reaped     = waitpid( $pid, 0 );
    my $raw_status = $?;
    my $status = $reaped == $pid && !( $raw_status & 127 )
      ? $raw_status >> 8
      : 255;
    my $stdout = read_file($stdout_file) // '';
    my $stderr = read_file($stderr_file) // '';
    return ( $status, $stdout, $stderr );
}

sub write_executable
{
    my ( $path, $contents ) = @_;
    write_file( $path, $contents );
    chmod 0755, $path or die "Unable to make $path executable: $!";
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

sub line_count
{
    my ($path) = @_;
    my $contents = read_file($path);
    return scalar grep { length($_) } split /\n/, $contents;
}
