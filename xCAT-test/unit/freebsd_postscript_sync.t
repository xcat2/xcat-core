#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use XCAT::Test::PostageFixture qw(fixture);
use xCAT::FreeBSDPostscript;
use xCAT::SvrUtils;

umask 0077;
my $temporary = tempdir(CLEANUP => 1);
my $sequence = 0;
my $tables;

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

sub setup {
    $tables = fixture();
    my $root = "$temporary/case-" . ++$sequence;
    mkdir($root, 0700) or croak $!;
    my @paths = map { "$root/list-$_" } (1 .. 3);
    for my $index (0 .. $#paths) { write_file($paths[$index], "/source/$index -> /target/$index\n"); }
    $tables->{osimage}[0]{synclists} = join(',', @paths);
    return ($root, \@paths);
}

sub success {
    my $callback = shift;
    $callback->({ data => ['node1: Remote_command_successful'], errorcode => 0 });
    $callback->({ serverdone => [undef] });
    return;
}

subtest 'resolved lists are frozen before transport and preserve selection order' => sub {
    my ($root, $paths) = setup();
    my @expected = map { read_file($_) } @$paths;
    my (@copied, @requests);
    my $result = xCAT::FreeBSDPostscript::sync_files('node1', sub {
        my ($request, $callback) = @_;
        push @requests, $request;
        is_deeply($request->{command}, ['xdcp'], 'existing copy command owns synchronization');
        is_deeply($request->{node}, ['node1'], 'copy targets one native node');
        is_deeply($request->{username}, ['operator'], 'authenticated caller is preserved');
        is_deeply($request->{env}, ["DSH_RSYNC_FILE=$request->{arg}[4]"], 'existing synclist transport context is preserved');
        is_deeply([@{$request->{arg}}[0, 1, 3]], ['--nodestatus', '-t', '-F'], 'completion status and timeout are explicit');
        cmp_ok($request->{arg}[2], '<=', 37, 'copy stays within the operation deadline');
        cmp_ok($request->{arg}[2], '>', 0, 'copy has a positive timeout');
        is_deeply([@{$request->{arg}}[5 .. 6]], ['-o', '--rsync-path=/usr/local/bin/rsync'], 'FreeBSD rsync location is passed to the existing transport');
        push @copied, read_file($request->{arg}[4]);
        write_file($paths->[1], "/changed -> /unexpected\n") if @copied == 1;
        success($callback);
    }, 37, directory => "$root/store", username => ['operator']);
    is_deeply(\@copied, \@expected, 'later source edits cannot replace the already-selected list bytes');
    is($result->{lists}, 3, 'every selected list completes');
    my $selection = decode_json(read_file("$result->{directory}/selection.json"));
    is_deeply([map { pack('H*', $_->{path}) } @{$selection->{lists}}], $paths, 'evidence retains the original source paths');
    is_deeply([map { $_->{sha256} } @{$selection->{lists}}], [map { sha256_hex($_) } @expected], 'evidence binds the actual list bytes');
    is_deeply(decode_json(read_file("$result->{directory}/result.json")),
        { complete => 1, lists => 3, completed => 3 }, 'durable evidence records all completions');
    done_testing();
};

subtest 'one deadline covers every selected list' => sub {
    my ($root) = setup();
    my @times = (100, 100.25, 102);
    my $calls = 0;
    local *xCAT::FreeBSDPostscript::clock_gettime = sub { return shift @times; };
    my $ok = eval {
        xCAT::FreeBSDPostscript::sync_files('node1', sub {
            my ($request, $callback) = @_;
            ++$calls;
            is($request->{arg}[2], 2, 'transport receives the remaining whole-second budget');
            success($callback);
        }, 2, directory => "$root/store");
        1;
    };
    ok(!$ok, 'an exhausted operation deadline is a failure');
    like($@, qr/File[ ]synchronization[ ]timed[ ]out/x, 'failure identifies the exhausted deadline');
    is($calls, 1, 'the next list cannot restart the timeout budget');
    done_testing();
};

subtest 'missing or unsafe list fails before any copy starts' => sub {
    for my $fault (qw(missing link writable empty)) {
        my ($root, $paths) = setup();
        if ($fault eq 'missing') { unlink($paths->[1]) or croak $!; }
        if ($fault eq 'link') {
            unlink($paths->[1]) or croak $!;
            symlink($paths->[0], $paths->[1]) or croak $!;
        }
        if ($fault eq 'writable') { chmod(0666, $paths->[1]) or croak $!; }
        if ($fault eq 'empty') { $tables->{osimage}[0]{synclists} .= ','; }
        my $calls = 0;
        my $ok = eval { xCAT::FreeBSDPostscript::sync_files('node1', sub { ++$calls; }, 10, directory => "$root/store"); 1; };
        ok(!$ok, "$fault list is rejected");
        is($calls, 0, 'all list preflight completes before transport');
    }
    done_testing();
};

subtest 'copy failure, missing completion and lost response remain failures' => sub {
    for my $fault (qw(status node error disconnected missing)) {
        my ($root, $paths) = setup();
        my $calls = 0;
        my $ok = eval {
            xCAT::FreeBSDPostscript::sync_files('node1', sub {
                my ($request, $callback) = @_;
                ++$calls;
                croak 'connection lost' if $fault eq 'disconnected';
                if ($fault eq 'status') { success($callback); $callback->({ errorcode => [23] }); }
                elsif ($fault eq 'node') { $callback->({ data => ['node2: Remote_command_successful'] }); }
                elsif ($fault eq 'error') { success($callback); $callback->({ error => ['copy failed'] }); }
                else { $callback->({ errorcode => 0, serverdone => [undef] }); }
            }, 10, directory => "$root/store");
            1;
        };
        ok(!$ok, "$fault cannot produce success");
        is($calls, 1, 'failed list stops this synchronization attempt');
        my @records = glob("$root/store/sync-*/result.json");
        is(scalar(@records), 1, 'failure has durable evidence');
        is(decode_json(read_file($records[0]))->{complete}, 0, 'evidence distinguishes incomplete synchronization');
    }
    done_testing();
};

subtest 'no selected lists is distinct from an unavailable resolver' => sub {
    my ($root, $paths) = setup();
    $tables->{osimage}[0]{synclists} = '';
    my $result = xCAT::FreeBSDPostscript::sync_files('node1', sub { croak 'Unexpected copy'; }, 10, directory => "$root/store");
    is($result->{lists}, 0, 'no configured list is a successful no-op');
    delete $tables->{osimage};
    my $ok = eval { xCAT::FreeBSDPostscript::sync_files('node1', sub { croak 'Unexpected copy'; }, 10, directory => "$root/store"); 1; };
    ok(!$ok, 'failed resolver is not a successful no-op');
    done_testing();
};

done_testing();
