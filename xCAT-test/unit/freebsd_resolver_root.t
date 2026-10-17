#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempdir);
use JSON;
use POSIX qw(mkfifo);
use Test::More;
use xCAT::FreeBSDPkg;

plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_SOLVER to the pinned resolver executable')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_SOLVER});
plan(skip_all => 'Set XCAT_FREEBSD_NATIVE_LIBDIR to the pinned native library directory')
  unless defined($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
plan(skip_all => 'Native resolver root fixtures require Linux or FreeBSD execution')
  unless $^O eq 'linux' || $^O eq 'freebsd';
plan(skip_all => 'Native resolver root fixtures require root') if $> != 0;

my $tmp = abs_path(tempdir(CLEANUP => 1, DIR => '/tmp'));
my $solver = abs_path($ENV{XCAT_FREEBSD_NATIVE_SOLVER});
my $libraries = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR});
BAIL_OUT('Missing native resolver inputs') unless defined($solver) && -x $solver
  && defined($libraries) && -d $libraries;
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C', LD_LIBRARY_PATH => $libraries);
my $json = JSON->new->utf8->canonical;

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    return defined($bytes) ? $bytes : '';
}

sub write_file {
    my ($path, $bytes) = @_;
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub directory {
    my ($path, $mode) = @_;
    $mode = oct('0700') unless defined($mode);
    mkdir($path, $mode) or croak "$path: $!";
    chmod($mode, $path) or croak "$path: $!";
    my @state = lstat($path);
    croak 'Directory mode fixture was not retained' unless @state && ($state[2] & oct('07777')) == $mode;
    return $path;
}

sub identity {
    my $path = shift;
    my @state = lstat($path);
    return unless @state;
    return [@state[0, 1, 2, 4, 5, 7], -l _ ? readlink($path) : undef];
}

sub run_helper {
    my @arguments = @_;
    return xCAT::FreeBSDPkg::run_command([$solver, @arguments], cwd => $tmp,
        environment => \%environment, timeout => 10, stdout_limit => 1048576, stderr_limit => 1048576);
}

write_file("$tmp/request", "unavailable-root-fixture\n");
directory("$tmp/repos");
my %original = map { $_ => sha256_hex(read_file($_)) } ($solver, "$tmp/request");
my @configurations;
my $case_number = 0;

sub configuration {
    my $label = shift;
    my $paths = { path => "$tmp/$label.conf", db => "$tmp/$label-db", cache => "$tmp/$label-cache" };
    write_file($paths->{path}, $json->encode({ ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
        PKG_DBDIR => $paths->{db}, PKG_CACHEDIR => $paths->{cache}, REPOS_DIR => ["$tmp/repos"],
        REPO_AUTOUPDATE => JSON::false, PKG_ENABLE_PLUGINS => JSON::false,
        PKG_TRIGGERS_ENABLE => JSON::false, HANDLE_RC_SCRIPTS => JSON::false, SYSLOG => JSON::false }));
    $original{$paths->{path}} = sha256_hex(read_file($paths->{path}));
    push @configurations, $paths;
    return $paths;
}

my $version_config = configuration('version');
my @prefix = ('-C', $version_config->{path}, 'resolve', "$tmp/request");
my $empty = directory("$tmp/empty");
my $usage = "FreeBSD resolver: usage: freebsd-pkg-resolve -C /config {-v | resolve /request /empty-root}\n";
my $arguments = "FreeBSD resolver: invalid resolver arguments\n";
my $canonical = "FreeBSD resolver: resolver root must be an absolute canonical directory\n";
my $protection = "FreeBSD resolver: resolver root path must be protected and root-owned\n";
my $nonempty = "FreeBSD resolver: resolver root must be empty\n";

sub rejected {
    my ($label, $argv, $expected, $witness) = @_;
    my $before = identity($witness);
    my $config = configuration('rejection-' . ++$case_number);
    my @arguments = @$argv;
    $arguments[1] = $config->{path};
    my $result = run_helper(@arguments);
    is($result->{exitcode}, 1, "$label fails");
    is($result->{signal}, 0, "$label is not signalled");
    is($result->{stdout}, '', "$label emits no jobs");
    is($result->{stderr}, $expected, "$label reports its exact boundary failure");
    is_deeply(scalar identity($witness), $before, "$label preserves the fixture identity");
    ok(!-e $config->{db} && !-l $config->{db}, "$label does not initialize a package database");
    ok(!-e $config->{cache} && !-l $config->{cache}, "$label does not initialize a package cache");
    return;
}

sub version_cases {
    my $result = run_helper('-C', $version_config->{path}, '-v');
    is($result->{exitcode}, 0, 'version succeeds without a root argument');
    is($result->{signal}, 0, 'version is not signalled');
    like($result->{stdout}, qr/\A2[.](?:8[.]2|6[.]2)\n\z/x, 'version reports a supported exact native pin');
    is($result->{stderr}, '', 'version has no error output');
    return;
}

subtest 'the version interface remains unchanged' => \&version_cases;

sub argument_cases {
    for my $case (
        ['missing root', [@prefix], $usage],
        ['extra root', [@prefix, $empty, $empty], $usage],
        ['blank root', [@prefix, ''], $arguments],
        ['relative root', [@prefix, 'empty'], $arguments],
    ) {
        rejected(@$case, $empty);
    }
    return;
}

subtest 'solve requires exactly one absolute root argument' => \&argument_cases;

sub protected_root_cases {
    write_file("$tmp/regular", "not a directory\n");
    mkfifo("$tmp/fifo", oct('0600')) or croak $!;
    symlink($empty, "$tmp/linked") or croak $!;
    my $parent = directory("$tmp/parent");
    directory("$parent/child");
    symlink($parent, "$tmp/parent-link") or croak $!;
    for my $case (
        ['filesystem root', '/', $canonical],
        ['missing directory', "$tmp/missing", $canonical],
        ['regular file', "$tmp/regular", $protection],
        ['FIFO', "$tmp/fifo", $protection],
        ['final symlink', "$tmp/linked", $canonical],
        ['symlink ancestor', "$tmp/parent-link/child", $canonical],
        ['dot component', "$tmp/./empty", $canonical],
        ['parent component', "$tmp/parent/../empty", $canonical],
        ['repeated separator', "$tmp//empty", $canonical],
        ['trailing separator', "$empty/", $canonical],
    ) {
        rejected($case->[0], [@prefix, $case->[1]], $case->[2], $empty);
    }
    for my $mode (qw(0720 0702 1700 2700 4700)) {
        my $path = directory("$tmp/mode-$mode", oct($mode));
        rejected("final mode $mode", [@prefix, $path], $protection, $path);
    }
    my $foreign = directory("$tmp/foreign");
    chown(65534, 65534, $foreign) == 1 or croak $!;
    rejected('non-root owner', [@prefix, $foreign], $protection, $foreign);
    my $writable = directory("$tmp/writable-parent", oct('0777'));
    my $child = directory("$writable/child");
    rejected('writable nonsticky ancestor', [@prefix, $child], $protection, $child);
    my $foreign_parent = directory("$tmp/foreign-parent");
    $child = directory("$foreign_parent/child");
    chown(65534, 65534, $foreign_parent) == 1 or croak $!;
    rejected('non-root ancestor', [@prefix, $child], $protection, $child);
    return;
}

subtest 'root paths must identify one protected canonical directory' => \&protected_root_cases;

sub nonempty_root_cases {
    for my $kind (qw(file hidden directory link)) {
        my $root = directory("$tmp/entry-$kind");
        write_file("$root/file", "retained fixture\n") if $kind eq 'file';
        write_file("$root/.hidden", "retained fixture\n") if $kind eq 'hidden';
        directory("$root/child") if $kind eq 'directory';
        symlink('absent-target', "$root/link") or croak $! if $kind eq 'link';
        rejected("$kind entry", [@prefix, $root], $nonempty, $root);
        is(read_file("$root/file"), "retained fixture\n", 'the nonempty file is retained') if $kind eq 'file';
        is(read_file("$root/.hidden"), "retained fixture\n", 'the hidden file is retained') if $kind eq 'hidden';
        ok(-d "$root/child" && !-l "$root/child", 'the subdirectory is retained') if $kind eq 'directory';
        is(readlink("$root/link"), 'absent-target', 'the broken link is retained') if $kind eq 'link';
    }
    return;
}

subtest 'every directory entry prevents an empty-root solve' => \&nonempty_root_cases;

for my $path (sort keys %original) {
    is(sha256_hex(read_file($path)), $original{$path}, 'root rejections preserve native inputs');
}
ok(!(grep { -e $_->{db} || -l $_->{db} } @configurations), 'all root rejections precede database creation');
ok(!(grep { -e $_->{cache} || -l $_->{cache} } @configurations), 'all root rejections precede cache creation');
done_testing();
