#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

plan skip_all => 'requires a disposable native FreeBSD amd64 builder'
    unless $^O eq 'freebsd' && $> == 0;
my $fixture = $ENV{XCAT_FREEBSD_RUNTIME_ROOT};
my $archive = $ENV{XCAT_FREEBSD_RUNTIME_PKG};
plan skip_all => 'requires a pristine FreeBSD 15.1 RAM root and release pkg archive'
    unless defined($fixture) && -d $fixture && defined($archive) && -f $archive;

my $helper = $ENV{XCAT_FREEBSD_RUNTIME_STAGE}
    || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd/stage-pkgbase-runtime.sh";
my $task = tempdir('xcat-runtime-test.XXXXXX', TMPDIR => 1, CLEANUP => 1);

sub contents {
    my $path = shift;
    open(my $fh, '<', $path) or die "$path: $!";
    binmode($fh);
    local $/ = undef;
    my $data = <$fh>;
    close($fh) or die "$path: $!";
    return $data;
}

sub write_file {
    my ($path, $data) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $data or die "$path: $!";
    close($fh) or die "$path: $!";
}

sub run {
    my @args = @_;
    open(my $pipe, '-|', 'sh', '-c', 'exec "$@" 2>&1', 'sh', @args) or die $!;
    local $/ = undef;
    my $output = <$pipe>;
    close($pipe);
    my $status = $?;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, $output // '');
}

sub root_fixture {
    my $root = tempdir('root.XXXXXX', DIR => $task, CLEANUP => 1);
    my ($status, $output) = run('cp', '-a', "$fixture/.", $root);
    die "Cannot copy pristine root: $output" if $status;
    return $root;
}

sub database_pin {
    return -f '/var/db/pkg/local.sqlite'
        ? sha256_hex(contents('/var/db/pkg/local.sqlite')) : 'absent';
}

my $host_database = database_pin();
is(system('sh', '-n', $helper), 0, 'staging helper has native shell syntax');
is(sha256_hex(contents($archive)),
    'ae22a209d68078786f8804e771b1aa484730d9591d6254b63f8904db3cba86c1',
    'test package is the exact shipped pkg 2.6.2_1 archive');

subtest 'offline activation and repeat preservation' => sub {
    my $root = root_fixture();
    my ($status, $output) = run('sh', $helper, $root, $archive);
    if (!is($status, 0, 'native pkg registers offline inside the staged RAM root')) {
        diag $output;
        for my $log (glob("$root/tmp/xcat-pkgstage.*/pkg-add.log")) {
            diag contents($log);
        }
        done_testing();
        return;
    }
    my $database_exists = ok(-s "$root/var/db/pkg/local.sqlite", 'RAM-root package database exists');
    my $executable_exists = ok(-s "$root/usr/local/sbin/pkg-static", 'RAM-root static executable exists');
    my $configuration_exists = ok(-s "$root/etc/pkg/FreeBSD.conf", 'RAM-root repository configuration exists');
    if (!$database_exists || !$executable_exists || !$configuration_exists) {
        done_testing();
        return;
    }
    is(sha256_hex(contents("$root/usr/local/sbin/pkg-static")),
        'd75db8494ddab4a03fa8d4187305414fcd88ad64a9a76f326e829e9b32ed248b',
        'installed static executable retains the shipped hash');
    is(contents("$root/etc/pkg/FreeBSD.conf"),
        "FreeBSD: { enabled: no }\nFreeBSD-base: { enabled: no }\n",
        'both public repository defaults are disabled');
    make_path("$task/empty-repositories");
    my @pkg = ("$root/usr/local/sbin/pkg-static", '--rootdir', $root,
        '-C', '/dev/null', '--repo-conf-dir', "$task/empty-repositories");
    is((run(@pkg, '-N'))[0], 0, 'native activation probe sees the private registration');
    my ($query_status, $query_output) = run(@pkg, 'query', '-a', '%n-%v');
    is($query_status, 0, 'native package inventory query succeeds');
    is($query_output, "pkg-2.6.2_1\n",
        'the RAM root registers exactly the intended package');
    my $before = sha256_hex(contents("$root/var/db/pkg/local.sqlite"));
    my ($repeat_status, $repeat_output) = run('sh', $helper, $root, $archive);
    isnt($repeat_status, 0, 'staging rejects an already populated package root');
    like($repeat_output, qr/Runtime package state already exists/,
        'repeated staging reports its conflicting state');
    is(sha256_hex(contents("$root/var/db/pkg/local.sqlite")), $before,
        'rejected staging preserves the existing private database');
    done_testing();
};

for my $case (
    ['bad-archive', qr/Unsupported FreeBSD 15\.1 pkg archive checksum/],
    ['bad-native-script', qr/Unsupported native runtime checksum/],
    ['missing-flua', qr/Missing native runtime file/],
    ['missing-flua-library', qr/RAM-root flua dependencies do not load/],
    ['occupied-database', qr/Runtime package state already exists/],
) {
    my ($name, $diagnostic) = @$case;
    my $root = root_fixture();
    my $input = $archive;
    if ($name eq 'bad-archive') {
        $input = "$task/corrupt.pkg";
        write_file($input, 'not a package');
    } elsif ($name eq 'bad-native-script') {
        write_file("$root/usr/libexec/bsdinstall/script", "#!/bin/sh\nexit 0\n");
    } elsif ($name eq 'missing-flua') {
        unlink("$root/usr/libexec/flua") or die $!;
    } elsif ($name eq 'missing-flua-library') {
        unlink("$root/lib/libm.so.5") or die $!;
    } elsif ($name eq 'occupied-database') {
        make_path("$root/var/db/pkg");
        write_file("$root/var/db/pkg/sentinel", 'existing package state');
    }
    my ($status, $output) = run('sh', $helper, $root, $input);
    isnt($status, 0, "$name fails before activation");
    like($output, $diagnostic, "$name reports the rejected precondition");
    ok(!-e "$root/usr/local/sbin/pkg-static", "$name installs no pkg executable");
    ok(!-e "$root/var/db/pkg/local.sqlite", "$name registers no package");
    is(contents("$root/var/db/pkg/sentinel"), 'existing package state',
        'occupied database sentinel survives') if $name eq 'occupied-database';
}

is(database_pin(), $host_database, 'the builder host package database is unchanged');
done_testing();
