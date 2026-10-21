#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use File::Temp qw(tempdir);
use Test::More;

my $module = $ENV{XCAT_RSYNC_MODULE} || "$FindBin::Bin/../../perl-xCAT/xCAT/RSYNC.pm";
require $module;
$::__DCP_DELIM = 'Xcat,DELIMITER,Xcat' unless defined($::__DCP_DELIM);

my $temporary = tempdir(CLEANUP => 1);
my $sequence = 0;
my @generated;
END { unlink @generated if @generated; }

sub write_file {
    my ($path, $bytes) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

sub read_file {
    open(my $file, '<', shift) or croak $!;
    my $bytes = do { local $/ = undef; <$file> };
    close($file) or croak $!;
    return $bytes;
}

my $boundary = "$temporary/copy";
write_file($boundary, <<'SHELL');
#!/bin/sh
set -eu
count=$(wc -l < "$RSYNC_TEST_LOG")
count=$((count+1))
printf '%s\n' "$*" >> "$RSYNC_TEST_LOG"
[ "$count" -ne "$RSYNC_TEST_FAIL" ] || exit 23
exit 0
SHELL
chmod 0755, $boundary or croak $!;

sub execute {
    my ($directory, @command) = @_;
    my $pid = fork();
    croak $! unless defined($pid);
    unless ($pid) {
        open(STDOUT, '>', "$directory/stdout") or croak $!;
        open(STDERR, '>', "$directory/stderr") or croak $!;
        exec @command or croak $!;
    }
    waitpid($pid, 0) == $pid or croak $!;
    my $status = $?;
    is($status & 127, 0, 'generated command exits normally');
    return $status >> 8;
}

sub fixture {
    my ($kind, $mkdir_failure, $trace) = @_;
    my $directory = "$temporary/case-" . ++$sequence;
    mkdir($directory) or croak $!;
    my $target = "xcat-rsync-status-$$-$sequence";
    my $path = "/tmp/rsync_$target";
    croak 'Generated command already exists' if -e $path || -l $path;
    push @generated, $path;
    my %destinations;
    for my $number (1 .. 3) {
        my $destination = "$directory/destination-$number";
        if ($mkdir_failure && $number == 1) { write_file($destination, "occupied\n"); }
        my $source = "$directory/source-$number";
        write_file($source, "source $number\n");
        $destinations{$destination} = {
            same_dest_name => $kind eq 'same' ? [$source] : [],
            diff_dest_name => $kind eq 'renamed' ? { $source => 'renamed' } : {} };
    }
    my $config = { 'dest-host' => $target, 'dest-user' => scalar(getpwuid($>)),
        destDir_srcFile => \%destinations, options => '', trace => $trace };
    my @command = xCAT::RSYNC->remote_copy_command($config, $boundary, 1);
    write_file("$directory/calls", '');
    return ($directory, \@command);
}

for my $kind (qw(same renamed)) {
    subtest "$kind transfers retain failures and continue later copies" => sub {
        for my $failure (0 .. 3) {
            my ($directory, $command) = fixture($kind, 0, 0);
            local $ENV{RSYNC_TEST_LOG} = "$directory/calls";
            local $ENV{RSYNC_TEST_FAIL} = $failure;
            is(execute($directory, @$command), $failure ? 23 : 0,
                $failure ? "failure at copy $failure remains visible" : 'successful copies succeed');
            my @calls = split(/\n/x, read_file("$directory/calls"));
            is(scalar(@calls), 3, 'all selected transfers are attempted');
        }
        done_testing();
    };
}

subtest 'directory creation failure cannot be hidden by later successful copies' => sub {
    my ($directory, $command) = fixture('same', 1, 0);
    local $ENV{RSYNC_TEST_LOG} = "$directory/calls";
    local $ENV{RSYNC_TEST_FAIL} = 0;
    isnt(execute($directory, @$command), 0, 'directory creation failure is reported');
    like(read_file("$directory/stderr"), qr/mkdir/x, 'real directory creation reached the obstructed path');
    is(scalar(split(/\n/x, read_file("$directory/calls"))), 3, 'later copies retain the continuation contract');
    done_testing();
};

subtest 'trace mode reports the same failure status' => sub {
    my ($directory, $command) = fixture('renamed', 0, 1);
    local $ENV{RSYNC_TEST_LOG} = "$directory/calls";
    local $ENV{RSYNC_TEST_FAIL} = 1;
    is(execute($directory, @$command), 23, 'tracing does not hide the first failure');
    is(scalar(split(/\n/x, read_file("$directory/calls"))), 3, 'tracing retains all transfers');
    done_testing();
};

subtest 'ordinary copy arguments are unchanged' => sub {
    my @command = xCAT::RSYNC->remote_copy_command({
        'src-file' => '/source/file', 'dest-file' => '/destination/file',
        'dest-user' => 'root', 'dest-host' => 'node1', preserve => 1,
        recursive => 1, options => '--checksum' }, '/usr/bin/rsync', 0);
    is_deeply(\@command, ['/usr/bin/rsync', '-p', '-t', '-r', '--checksum',
        '/source/file', 'root@node1:/destination/file'], 'non-synclist command keeps its argv');
    done_testing();
};

done_testing();
