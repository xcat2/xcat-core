#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../lib";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempdir);
use JSON;
use POSIX ();
use Test::More;
use XCAT::Test::PostageFixture qw(fixture write_file read_file $root $custom $stock $template $expected);
use xCAT::FreeBSDPostscript;
require xCAT::Postage;

my $private = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;
my $json = JSON->new->canonical->utf8;
my ($hook_mode, $hook_path);

{
    package XCAT::SourceTest;
    sub observe {
        if ($hook_mode eq 'bytes') {
            XCAT::Test::PostageFixture::write_file($hook_path, 'NEW');
        } elsif ($hook_mode eq 'mode') {
            chmod(oct('0750'), $hook_path) == 1 or die $!;
        } elsif ($hook_mode eq 'template') {
            XCAT::Test::PostageFixture::write_file($hook_path, "changed template\n");
        } elsif ($hook_mode eq 'context') {
            $::XCATSITEVALS{installdir} .= '/changed';
        } else {
            die 'Unknown source fixture hook';
        }
        return 'observed';
    }
}

sub store { return "$private/store-" . ++$sequence; }
sub hexname { return unpack('H*', $_[0]); }
sub manifest { return $json->decode(read_file("$_[0]{directory}/manifest.json")); }
sub seal { return xCAT::FreeBSDPostscript::seal_source('node1', 'install', @_); }

sub reject {
    my ($operation, $description) = @_;
    my $result;
    my $ok = eval { $result = $operation->(); 1; };
    my $error = $@;
    ok(!$ok, "$description rejects the operation");
    like($error, qr/\AFreeBSD[ ]postscript[ ](?:source[ ]sealing[ ]failed[ ]during[ ][a-z ]+|source[ ]verification[ ]failed)\n\z/x,
        "$description returns only the fixed public error");
    ok(!defined($result), "$description returns no source descriptor");
    return;
}

sub source_file {
    my ($name, $bytes, $mode) = @_;
    my $path = "$root/install/postscripts/$name";
    write_file($path, $bytes);
    chmod($mode, $path) == 1 or croak $!;
    return $path;
}

sub artifact_cases {
    fixture(1);
    my $source = "$root/install/postscripts";
    mkdir("$source/nested", oct('0750')) or croak $!;
    my $script = source_file('syslog', "administrator override\0bytes\n", oct('0640'));
    my $helper = source_file('nested/helper', 'helper bytes', oct('0755'));
    my $odd = "quoted 'name\n" . pack('C', 255);
    source_file($odd, '', oct('0600'));
    link($helper, "$source/hard-helper") or croak $!;
    symlink('nested/helper', "$source/alias") or croak $!;
    my $directory = store();
    my $sealed = seal(directory => $directory);
    my $record = manifest($sealed);
    is($sealed->{kind}, 'freebsd-postscript-source-v1', 'source artifact is not an execution snapshot');
    is($record->{capture_id}, sha256_hex($json->encode($record->{capture}) . "\n"), 'source binds the exact A2 record');
    is(read_file("$sealed->{directory}/rendered"), $expected, 'real Postage output is preserved');
    is($record->{template}{kind}, 'custom', 'actual custom template is selected');
    is($record->{template}{member}, hexname('mypostscript.tmpl'), 'custom template is bound to its tree member');
    my $entry = $record->{entries}{hexname('syslog')};
    is(read_file("$sealed->{directory}/blob-$entry->{sha256}"), "administrator override\0bytes\n",
        'administrator replacement retains binary bytes instead of a stock backend');
    is($entry->{mode}, oct('0640'), 'nonexecutable original mode is recorded exactly');
    is($entry->{uid}, $>, 'source UID is recorded');
    is($entry->{gid}, (lstat($script))[5], 'source GID is recorded');
    is($record->{entries}{hexname('nested/helper')}{mode}, oct('0755'), 'executable original mode is recorded exactly');
    is($record->{entries}{hexname('nested')}{mode}, oct('0750'), 'directory original mode is recorded exactly');
    is($record->{entries}{hexname($odd)}{bytes}, 0, 'opaque byte-bearing filename retains its empty file');
    is($record->{entries}{hexname('alias')}{target}, hexname('nested/helper'), 'internal link target bytes are exact');
    is($record->{entries}{hexname('hard-helper')}{group}, hexname('hard-helper'), 'hard-link group uses its canonical member');
    is($record->{entries}{hexname('nested/helper')}{group}, hexname('hard-helper'), 'hard-link aliases retain their relationship');
    is($record->{entries}{hexname('nested/helper')}{links}, 2, 'complete internal hard-link count is recorded');
    is((lstat($script))[2] & oct('7777'), oct('0640'), 'source mode is not repaired or normalized');
    is((lstat("$sealed->{directory}/blob-$entry->{sha256}"))[2] & oct('7777'), oct('0600'), 'private storage mode is not an execution mode');
    isnt((lstat("$sealed->{directory}/blob-$entry->{sha256}"))[1], (lstat($script))[1], 'private content never links back to source');
    my $second = seal(directory => $directory);
    is($second->{id}, $sealed->{id}, 'identical source and render reuse exact identity');
    isnt($second->{attempt}, $sealed->{attempt}, 'attempt evidence remains distinct');
    write_file($script, 'later administrator change');
    $xCAT::Table::rows{postscripts}[0]{postscripts} = 'later-table-change';
    @xCAT::Table::opened = ();
    my $loaded = xCAT::FreeBSDPostscript::read_source($sealed->{id}, directory => $directory);
    is($loaded->{id}, $sealed->{id}, 'readback uses only the sealed source');
    is_deeply(\@xCAT::Table::opened, [], 'source readback opens no tables');
    ok(!exists($loaded->{attempt}), 'readback does not invent a successful attempt');
    reject(sub { xCAT::FreeBSDPostscript::read_source($record->{capture_id}, directory => $directory) }, 'A2 capture as source artifact');
    return;
}

sub template_cases {
    fixture(0);
    my $sealed = seal(directory => store());
    my $record = manifest($sealed);
    is($record->{template}{kind}, 'stock', 'missing custom template uses actual stock selection');
    my $stock_entry = $record->{template}{file};
    is(read_file("$sealed->{directory}/blob-$stock_entry->{sha256}"), read_file($stock), 'stock template outside tree is sealed exactly');
    ok(!exists($record->{entries}{hexname('mypostscript.tmpl')}), 'stock fallback does not invent a custom member');
    fixture(1);
    my $source = "$root/install/postscripts";
    rename($custom, "$source/template-copy") or croak $!;
    symlink('template-copy', $custom) or croak $!;
    $sealed = seal(directory => store());
    $record = manifest($sealed);
    is($record->{template}{kind}, 'custom', 'internal linked custom template remains authoritative');
    is($record->{template}{member}, hexname('template-copy'), 'custom link resolves to the sealed file');
    is(read_file("$sealed->{directory}/rendered"), $expected, 'linked custom template reaches real renderer');
    fixture(1);
    my $script = source_file('mode-only', 'same', oct('0644'));
    my $directory = store();
    my $before = seal(directory => $directory);
    chmod(oct('0755'), $script) == 1 or croak $!;
    my $after = seal(directory => $directory);
    isnt($before->{id}, $after->{id}, 'mode-only source change produces a different identity');
    return;
}

sub unsafe_cases {
    for my $case (qw(escape absolute dangling cycle directory-cycle external-hardlink public-file public-directory fifo symlink-root)) {
        fixture(1);
        my $source = "$root/install/postscripts";
        my $file = source_file('helper', 'inside', oct('0644'));
        write_file("$root/install/helper", 'outside');
        symlink('../helper', "$source/alias") or croak $! if $case eq 'escape';
        symlink($file, "$source/alias") or croak $! if $case eq 'absolute';
        symlink('missing', "$source/alias") or croak $! if $case eq 'dangling';
        if ($case eq 'cycle') {
            symlink('second', "$source/first") or croak $!;
            symlink('first', "$source/second") or croak $!;
        }
        symlink('.', "$source/loop") or croak $! if $case eq 'directory-cycle';
        link($file, "$root/outside-alias") or croak $! if $case eq 'external-hardlink';
        chmod(oct('0666'), $file) == 1 or croak $! if $case eq 'public-file';
        chmod(oct('0777'), $source) == 1 or croak $! if $case eq 'public-directory';
        POSIX::mkfifo("$source/fifo", oct('0600')) == 0 or croak $! if $case eq 'fifo';
        if ($case eq 'symlink-root') {
            rename($source, "$root/install/original") or croak $!;
            symlink('original', $source) or croak $!;
        }
        reject(sub { seal(directory => store()) }, $case);
        is((lstat($file))[2] & oct('7777'), oct('0666'), 'unsafe source mode is not repaired') if $case eq 'public-file';
    }
    fixture(1);
    reject(sub { seal(directory => "$root/install/postscripts/private") }, 'overlapping source storage');
    ok(!-e "$root/install/postscripts/private", 'overlap rejection creates no private directory in source');
    return;
}

sub drift_cases {
    for my $case (qw(bytes mode template context)) {
        fixture(1);
        $hook_mode = $case;
        $hook_path = $case eq 'template' ? $custom : source_file('helper', 'OLD', oct('0755'));
        write_file($custom, $template . 'HOOK=#Subroutine:XCAT::SourceTest::observe:$NODE#' . "\n");
        my $directory = store();
        reject(sub { seal(directory => $directory) }, "$case changes during actual rendering");
        is(read_file($hook_path), 'NEW', 'real inherited hook reaches the source byte mutation') if $case eq 'bytes';
        is((lstat($hook_path))[2] & oct('7777'), oct('0750'), 'real hook reaches source mode mutation') if $case eq 'mode';
        is($::XCATSITEVALS{installdir}, "$root/install", 'child context mutation does not alter parent selection') if $case eq 'context';
    }
    return;
}

sub corruption_cases {
    for my $case (qw(bytes mode manifest extra storage-mode hardlink)) {
        fixture(1);
        source_file('helper', 'ORIGINAL', oct('0755'));
        my $directory = store();
        my $sealed = seal(directory => $directory);
        my $record = manifest($sealed);
        my $entry = $record->{entries}{hexname('helper')};
        my $blob = "$sealed->{directory}/blob-$entry->{sha256}";
        write_file($blob, 'MUTATION') if $case eq 'bytes';
        if ($case eq 'mode') {
            $entry->{mode} = oct('0644');
            write_file("$sealed->{directory}/manifest.json", $json->encode($record) . "\n");
        }
        write_file("$sealed->{directory}/manifest.json", "{}\n") if $case eq 'manifest';
        write_file("$sealed->{directory}/extra", 'unexpected') if $case eq 'extra';
        chmod(oct('0644'), $blob) == 1 or croak $! if $case eq 'storage-mode';
        link($blob, "$directory/outside") or croak $! if $case eq 'hardlink';
        reject(sub { xCAT::FreeBSDPostscript::read_source($sealed->{id}, directory => $directory) }, "$case corruption");
    }
    return;
}

sub bound_cases {
    fixture(1);
    source_file('large', 'x' x 4096, oct('0644'));
    my $bytes = 4096 + length($template);
    my $limits = { max_entries => 3, max_bytes => $bytes, max_file_bytes => 4096 };
    my $sealed = seal(directory => store(), limits => $limits);
    is($sealed->{entries}, 3, 'exact source entry limit includes the root');
    is($sealed->{bytes}, $bytes, 'exact aggregate byte limit includes the custom template');
    my $record = manifest($sealed);
    my $entry = $record->{entries}{hexname('large')};
    ok(read_file("$sealed->{directory}/blob-$entry->{sha256}") eq ('x' x 4096), 'exact file limit preserves all bytes');
    for my $key (qw(max_entries max_bytes max_file_bytes)) {
        my %reduced = %$limits;
        --$reduced{$key};
        reject(sub { seal(directory => store(), limits => \%reduced) }, "$key one-over input");
    }
    for (1 .. 5) {
        $record->{limits}{max_manifest_bytes} = length($json->encode($record) . "\n");
    }
    my $manifest_limit = $record->{limits}{max_manifest_bytes};
    my %exact = (%$limits, max_manifest_bytes => $manifest_limit);
    $sealed = seal(directory => store(), limits => \%exact);
    is(length(read_file("$sealed->{directory}/manifest.json")), $manifest_limit, 'exact canonical manifest limit succeeds');
    --$exact{max_manifest_bytes};
    reject(sub { seal(directory => store(), limits => \%exact) }, 'manifest one-over input');
    reject(sub { seal(directory => store(), limits => { max_bytes => 67108865 }) }, 'limit increase');
    fixture(0);
    $sealed = seal(directory => store(), limits => { max_entries => 2, max_bytes => length(read_file($stock)) });
    is($sealed->{entries}, 2, 'stock template consumes its own entry beyond the tree root');
    is($sealed->{bytes}, length(read_file($stock)), 'stock template consumes aggregate bytes');
    return;
}

sub publication_case {
    fixture(1);
    source_file('helper', 'ORIGINAL', oct('0755'));
    my $directory = store();
    my $calls = "$private/sync-witness-" . ++$sequence;
    my $native_sync = \&IO::Handle::sync;
    {
        no warnings 'redefine';
        local *IO::Handle::sync = sub {
            my ($handle) = @_;
            my $path = readlink('/proc/' . $$ . '/fd/' . fileno($handle));
            if (defined($path) && $path =~ m{\A\Q$directory\E/[.]source-attempt[.][^/]+/content/blob-[0-9a-f]{64}\z}x) {
                write_file($calls, 'actual source blob');
                return 0;
            }
            return $native_sync->(@_);
        };
        reject(sub { seal(directory => $directory) }, 'source blob durable-write failure');
    }
    is(read_file($calls), 'actual source blob', 'fault reaches an actual private source member');
    is(\&IO::Handle::sync, $native_sync, 'native sync is restored');
    fixture(1);
    $directory = store();
    $calls = "$private/parent-sync-witness-" . ++$sequence;
    {
        no warnings 'redefine';
        local *IO::Handle::sync = sub {
            my ($handle) = @_;
            my $path = readlink('/proc/' . $$ . '/fd/' . fileno($handle));
            if (defined($path) && $path eq $directory) {
                opendir(my $parent, $directory) or croak $!;
                my @names = grep { /\A[0-9a-f]{64}\z/x } readdir($parent);
                closedir($parent) or croak $!;
                for my $name (@names) {
                    my $record = $json->decode(read_file("$directory/$name/manifest.json"));
                    next unless $record->{kind} eq 'freebsd-postscript-source-v1';
                    write_file($calls, $name);
                    return 0;
                }
            }
            return $native_sync->(@_);
        };
        reject(sub { seal(directory => $directory) }, 'source parent fsync after rename');
    }
    my $visible = read_file($calls);
    my $readback = xCAT::FreeBSDPostscript::read_source($visible, directory => $directory);
    is($readback->{id}, $visible, 'readback verifies current source identity, not historical durability');
    ok(!exists($readback->{attempt}), 'visible failed publication supplies no successful attempt');
    is(\&IO::Handle::sync, $native_sync, 'parent fsync observer is restored');
    return;
}

subtest 'exact administrator tree and real capture binding' => sub { artifact_cases(); done_testing(); };
subtest 'actual template selection and mode-sensitive identities' => sub { template_cases(); done_testing(); };
subtest 'source admission rejects unsafe topology and modes' => sub { unsafe_cases(); done_testing(); };
subtest 'actual renderer observes source and context drift' => sub { drift_cases(); done_testing(); };
subtest 'source readback rejects stored corruption' => sub { corruption_cases(); done_testing(); };
subtest 'exact reduced source bounds and one-over failures' => sub { bound_cases(); done_testing(); };
subtest 'source publication retains failed private evidence' => sub { publication_case(); done_testing(); };
done_testing();
