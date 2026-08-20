#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IO::Compress::Gzip qw(gzip $GzipError);
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $report = File::Spec->catfile(
    $repo_root, qw(xCAT-genesis-builder oe report)
);
my $metrics = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-metrics)
);
my $recipe = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init xcat-genesis-init_1.0.bb)
);
my $service = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files xcat-genesis-metrics.service)
);

sub write_file {
    my ( $path, $contents ) = @_;
    open( my $stream, '>', $path ) or die "Unable to write $path: $!";
    print {$stream} $contents;
    close($stream);
}

sub read_file {
    my ($path) = @_;
    open( my $stream, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$stream> };
    close($stream);
    return $contents;
}

sub run_command {
    my ( $environment, @command ) = @_;
    local %ENV = ( %ENV, %{$environment} );
    open( my $stream, '-|', @command )
      or die "Unable to run @command: $!";
    my $output = do { local $/; <$stream> };
    close($stream);
    return ( $? >> 8, $output );
}

sub parse_report {
    my ($contents) = @_;
    my %values;
    foreach my $line ( split( /\n/, $contents ) ) {
        my ( $name, $value ) = split( /=/, $line, 2 );
        $values{$name} = $value;
    }
    return \%values;
}

my $recipe_contents = read_file($recipe);
like( $recipe_contents, qr/file:\/\/genesis-metrics/,
    'metrics collector is included in the init package' );
like( $recipe_contents, qr/SYSTEMD_SERVICE.*?xcat-genesis-metrics\.service/s,
    'metrics service is enabled with the init package' );

my $service_contents = read_file($service);
like( $service_contents,
    qr/Requires=xcat-genesis-register\.service\nAfter=xcat-genesis-register\.service/,
    'metrics are captured after successful registration' );
like( $service_contents,
    qr{ExecStart=/usr/libexec/xcat/genesis-metrics --output /run/xcat/metrics\.env},
    'metrics are stored in the runtime state directory' );

my $root = tempdir( CLEANUP => 1 );
my $registration = File::Spec->catfile( $root, 'registration.env' );
my $meminfo = File::Spec->catfile( $root, 'meminfo' );
my $uptime = File::Spec->catfile( $root, 'uptime' );
my $runtime = File::Spec->catfile( $root, 'metrics.env' );

write_file(
    $registration,
    "SCHEMA=1\nSTATE=ACTION_RECEIVED\nDETAIL=Destiny shell\nUPDATED_SECONDS=42\n"
);
write_file(
    $meminfo,
    "MemTotal:       1048576 kB\nMemFree:         524288 kB\n"
      . "MemAvailable:   786432 kB\n"
);
write_file( $uptime, "45.92 12.34\n" );

my %metrics_environment = (
    XCAT_REGISTRATION_STATUS_FILE => $registration,
    XCAT_MEMINFO_FILE             => $meminfo,
    XCAT_UPTIME_FILE              => $uptime,
);
my ( $status, $output ) = run_command( \%metrics_environment, $metrics );
is( $status, 0, 'runtime metrics are collected' );
is_deeply(
    parse_report($output),
    {
        SCHEMA                 => '1',
        BOOT_READY_SECONDS     => '42',
        CAPTURE_UPTIME_SECONDS => '45',
        MEMORY_TOTAL_KIB       => '1048576',
        MEMORY_AVAILABLE_KIB   => '786432',
        MEMORY_USED_KIB        => '262144',
    },
    'runtime report records boot time and memory use'
);

( $status, $output ) = run_command(
    \%metrics_environment, $metrics, '--output', $runtime
);
is( $status, 0, 'runtime metrics can be stored atomically' );
is( read_file($runtime),
    "SCHEMA=1\nBOOT_READY_SECONDS=42\nCAPTURE_UPTIME_SECONDS=45\n"
      . "MEMORY_TOTAL_KIB=1048576\nMEMORY_AVAILABLE_KIB=786432\n"
      . "MEMORY_USED_KIB=262144\n",
    'stored runtime report is complete' );
is( ( stat($runtime) )[2] & 07777, 0644,
    'stored runtime report is readable' );

my $image_dir = File::Spec->catdir( $root, 'image' );
make_path($image_dir);
my $kernel = File::Spec->catfile( $image_dir, 'kernel' );
my $initramfs = File::Spec->catfile( $image_dir, 'initramfs.cpio.gz' );
my $payload = "cpio payload\n";
write_file( $kernel, "kernel\n" );
gzip( \$payload => $initramfs )
  or die "Unable to create test initramfs: $GzipError";

( $status, $output ) = run_command(
    {}, $report, '--runtime', $runtime, 'x86_64', $image_dir
);
is( $status, 0, 'image and runtime metrics are reported together' );
my $current = parse_report($output);
is( $current->{ARCHITECTURE}, 'x86_64',
    'report records the Genesis architecture' );
is( $current->{KERNEL_BYTES}, -s $kernel,
    'report measures the kernel' );
is( $current->{COMPRESSED_INITRAMFS_BYTES}, -s $initramfs,
    'report measures the compressed initramfs' );
is( $current->{UNPACKED_INITRAMFS_BYTES}, length($payload),
    'report measures the unpacked initramfs' );
is( $current->{BOOT_READY_SECONDS}, 42,
    'report includes the registration-ready time' );
is( $current->{MEMORY_USED_KIB}, 262144,
    'report includes captured memory use' );

my $baseline = File::Spec->catfile( $root, 'baseline.env' );
write_file(
    $baseline,
    "SCHEMA=1\nARCHITECTURE=x86_64\nKERNEL_BYTES="
      . ( ( -s $kernel ) - 2 )
      . "\nCOMPRESSED_INITRAMFS_BYTES="
      . ( ( -s $initramfs ) - 3 )
      . "\nUNPACKED_INITRAMFS_BYTES="
      . ( length($payload) - 4 )
      . "\nBOOT_READY_SECONDS=40\nMEMORY_USED_KIB=250000\n"
);

( $status, $output ) = run_command(
    {}, $report, '--runtime', $runtime, '--baseline', $baseline,
    'x86_64', $image_dir
);
is( $status, 0, 'report compares against a matching baseline' );
my $comparison = parse_report($output);
is( $comparison->{KERNEL_BYTES_DELTA}, 2,
    'kernel growth is reported' );
is( $comparison->{COMPRESSED_INITRAMFS_BYTES_DELTA}, 3,
    'compressed image growth is reported' );
is( $comparison->{UNPACKED_INITRAMFS_BYTES_DELTA}, 4,
    'unpacked image growth is reported' );
is( $comparison->{BOOT_READY_SECONDS_DELTA}, 2,
    'slower registration is reported' );
is( $comparison->{MEMORY_USED_KIB_DELTA}, 12144,
    'additional memory use is reported' );

done_testing();
