#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use POSIX qw(mkfifo);
use Test::More;
use xCAT::FreeBSDRepo;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;

sub write_file {
    my ($path, $bytes) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub tree {
    my $root = "$tmp/tree-" . ++$sequence;
    make_path($root);
    return $root;
}

sub release_tree {
    my $dvd = shift;
    my $root = tree();
    write_file("$root/bin/freebsd-version", "#!/bin/sh\nUSERLAND_VERSION=\"15.1-RELEASE\"\nexit 99\n");
    write_file("$root/bin/sh", "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62));
    for my $repo ('usr/freebsd-packages/offline', $dvd ? 'packages/FreeBSD:15:amd64' : ()) {
        write_file("$root/$repo/$_", "fixture $_\n") for qw(meta meta.conf data.pkg packagesite.pkg);
        write_file("$root/$repo/All/Hashed/pkg-2.6.2_1~ce4334b039.pkg", 'package bytes');
        write_file("$root/$repo/All/Hashed/xcb-util-0.4.1,1~1092b8d74e.pkg", 'epoch package bytes');
    }
    if ($dvd) {
        symlink('FreeBSD:15:amd64', "$root/packages/freebsd:15:x86:64") or croak $!;
        make_path("$root/packages/FreeBSD:15:amd64/Latest");
        symlink('../All/pkg-2.6.2_1.pkg', "$root/packages/FreeBSD:15:amd64/Latest/pkg.pkg") or croak $!;
    }
    make_path("$root/etc");
    symlink('../var/run/os-release', "$root/etc/os-release") or croak $!;
    return $root;
}

sub rejects {
    my ($action, $pattern, $description) = @_;
    my $ok = eval { $action->(); 1 };
    ok(!$ok, $description);
    like($@, $pattern, "$description diagnostic");
    return;
}

sub snapshot_cases {
    my $source = tree();
    write_file("$source/All/Hashed/a-1~abc.pkg", "payload\0bytes\n");
    write_file("$source/data.pkg", 'primary catalogue');
    write_file("$source/packagesite.pkg", 'fallback catalogue');
    make_path("$source/Latest", "$source/empty");
    symlink('../All/Hashed/a-1~abc.pkg', "$source/Latest/a.pkg") or croak $!;
    symlink('All', "$source/alias:15") or croak $!;
    my $snapshot = xCAT::FreeBSDRepo::snapshot_tree($source);
    is($snapshot->{native_validated}, 0, 'tree inspection does not claim native or signature validation');
    is($snapshot->{format}, 'xcat-freebsd-repo-tree-1', 'snapshot has a versioned format');
    is_deeply($snapshot->{entries}{'All/Hashed/a-1~abc.pkg'},
        { type => 'file', size => 14, sha256 => sha256_hex("payload\0bytes\n") },
        'binary archive identity uses complete bytes');
    is_deeply($snapshot->{entries}{'Latest/a.pkg'},
        { type => 'link', target => '../All/Hashed/a-1~abc.pkg' }, 'relative archive link is preserved');
    is_deeply($snapshot->{entries}{'alias:15'}, { type => 'link', target => 'All' },
        'directory alias and colon spelling are preserved');
    is_deeply($snapshot->{entries}{empty}, { type => 'directory' }, 'empty directories are retained');
    is_deeply($snapshot->{unresolved_links}, {}, 'ordinary tree has no unresolved links');
    is($snapshot->{bytes}, 14 + length('primary catalogue') + length('fallback catalogue'),
        'byte total counts regular files once per path and does not follow links');
    is_deeply(xCAT::FreeBSDRepo::snapshot_tree($source), $snapshot, 'unchanged inspection is deterministic');
    write_file("$source/All/Hashed/a-1~abc.pkg", "changed archive");
    isnt(xCAT::FreeBSDRepo::snapshot_tree($source)->{digest}, $snapshot->{digest}, 'archive bytes change snapshot identity');
    write_file("$source/All/Hashed/a-1~abc.pkg", "payload\0bytes\n");
    write_file("$source/data.pkg", 'changed catalogue');
    isnt(xCAT::FreeBSDRepo::snapshot_tree($source)->{digest}, $snapshot->{digest}, 'primary metadata changes snapshot identity');
    write_file("$source/data.pkg", 'primary catalogue');
    write_file("$source/packagesite.pkg", 'changed fallback');
    isnt(xCAT::FreeBSDRepo::snapshot_tree($source)->{digest}, $snapshot->{digest}, 'fallback metadata changes snapshot identity');
    write_file("$source/packagesite.pkg", 'fallback catalogue');
    chmod(0600, "$source/data.pkg") or croak $!;
    is(xCAT::FreeBSDRepo::snapshot_tree($source)->{digest}, $snapshot->{digest}, 'source permissions do not change content identity');
    is((stat("$source/data.pkg"))[2] & oct('0777'), oct('0600'), 'inspection does not change source permissions');
    unlink("$source/Latest/a.pkg") or croak $!;
    symlink('../All//Hashed/./a-1~abc.pkg', "$source/Latest/a.pkg") or croak $!;
    isnt(xCAT::FreeBSDRepo::snapshot_tree($source)->{digest}, $snapshot->{digest}, 'equivalent link spelling has its own snapshot identity');
    return $source;
}

sub link_cases {
    my $source = shift;
    for my $case (
        ['absolute', '/etc/passwd', qr/Invalid repository link/],
        ['escape', '../outside', qr/escapes/],
        ['missing', 'absent', qr/Dangling/],
        ['cycle', 'cycle', qr/Cyclic or excessive/],
        ['newline', "All\nfile", qr/Invalid repository link/],
        ['long-component', 'a' x 256, qr/Invalid repository link/],
    ) {
        my $root = tree();
        symlink($case->[1], "$root/$case->[0]") or croak $!;
        rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($root) }, $case->[2], "rejects $case->[0] link");
    }

    my $linked = tree();
    make_path("$linked/d/sub");
    write_file("$linked/d/file", 'nested');
    write_file("$linked/d/sub/file", 'leaf');
    symlink('d/sub', "$linked/a") or croak $!;
    symlink('a/../file', "$linked/parent") or croak $!;
    symlink('a/../../a/file', "$linked/repeated") or croak $!;
    symlink('d/..', "$linked/root-alias") or croak $!;
    ok(xCAT::FreeBSDRepo::snapshot_tree($linked), 'resolves parent components after symbolic links and permits repeated finite references');
    symlink('root-alias/../outside', "$linked/escape") or croak $!;
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($linked) }, qr/escapes/,
        'rejects an escape hidden behind an in-root directory alias');

    for my $target ('file/child', 'file/', 'file/.', 'file/../other') {
        my $root = tree();
        write_file("$root/file", 'regular');
        symlink($target, "$root/link") or croak $!;
        rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($root) }, qr/non-directory/x,
            "rejects traversal through a regular file: $target");
    }
    for my $name ('white space', "newline\nname", 'dollar$name', 'semi;colon', 'asterisk*') {
        my $root = tree();
        write_file("$root/$name", 'unexpected');
        rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($root) }, qr/entry name/, "rejects unsafe filename $name");
    }
    my $special = tree();
    mkfifo("$special/fifo", 0600) or croak $!;
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($special) }, qr/special file/, 'rejects FIFO without reading it');
    my $rootlink = "$tmp/root-link";
    symlink($source, $rootlink) or croak $!;
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($rootlink) }, qr/symlinked/, 'rejects symlinked root');
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree("$rootlink/") }, qr/symlinked/, 'trailing slash does not hide symlinked root');
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree("$source/../other") }, qr/dot components/, 'rejects ambiguous root components');
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree('relative') }, qr/absolute/, 'requires absolute root');
    return;
}

sub limit_cases {
    my $bounded = tree();
    write_file("$bounded/a", '1234');
    write_file("$bounded/b", '56');
    is(xCAT::FreeBSDRepo::snapshot_tree($bounded, max_entries => 2, max_bytes => 6, max_file_bytes => 4)->{bytes},
        6, 'exact entry, total-byte and file-byte limits pass');
    for my $limit_case ([max_entries => 1, qr/entry limit/], [max_bytes => 5, qr/exceeds/], [max_file_bytes => 3, qr/exceeds/]) {
        rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($bounded, $limit_case->[0] => $limit_case->[1]) },
            $limit_case->[2], "enforces $limit_case->[0]");
    }
    for my $limit_value (0, -1, '1.5', '1e3', '999999999999999999999999', [], undef) {
        rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($bounded, max_bytes => $limit_value) }, qr/Invalid repository limit/,
            'rejects invalid or excessive limit');
    }
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($bounded, unknown => 1) }, qr/Unknown/, 'rejects unknown options');
    my $deep = tree();
    make_path("$deep/" . join('/', ('a') x 65));
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree($deep) }, qr/too long or deep/, 'bounds directory depth');
    return;
}

sub media_cases {
    is(xCAT::FreeBSDRepo::inspect_release_tree(tree()), undef, 'ordinary media is not claimed');
    my $disc = release_tree(0);
    my $base = xCAT::FreeBSDRepo::inspect_release_tree($disc);
    is_deeply([sort keys %{$base->{repositories}}], ['base'], 'base-only media does not require application repository');
    is($base->{release}, '15.1-RELEASE', 'reads static release identity without executing media script');
    is($base->{arch}, 'x86_64', 'normalizes target architecture for xCAT');
    is($base->{media_arch}, 'amd64', 'retains native media architecture');
    is($base->{native_validated}, 0, 'media layout does not claim package/release cross-validation');
    is($base->{repositories}{base}{tree}{native_validated}, 0, 'base snapshot still requires native validation');
    is($base->{repositories}{base}{path}, 'usr/freebsd-packages/offline', 'records base repository path');
    ok(-l "$disc/etc/os-release" && !-e "$disc/etc/os-release", 'runtime os-release symlink is not executed or used for identity');
    my $dvd = release_tree(1);
    my $media = xCAT::FreeBSDRepo::inspect_release_tree($dvd);
    is_deeply([sort keys %{$media->{repositories}}], [qw(applications base)], 'DVD separates base and application repositories');
    is($media->{repositories}{applications}{catalogue_prefix}, 'FreeBSD:15:amd64', 'records native application catalogue subdirectory');
    is_deeply($media->{repositories}{applications}{tree}{unresolved_links},
        { 'FreeBSD:15:amd64/Latest/pkg.pkg' => '../All/pkg-2.6.2_1.pkg' },
        'known shipped bootstrap alias remains unresolved until native catalogue validation');
    is_deeply($media->{repositories}{applications}{tree}{entries}{'freebsd:15:x86:64'},
        { type => 'link', target => 'FreeBSD:15:amd64' }, 'DVD ABI alias is retained');
    ok(-l "$dvd/packages/FreeBSD:15:amd64/Latest/pkg.pkg" && !-e "$dvd/packages/FreeBSD:15:amd64/Latest/pkg.pkg",
        'inspection does not repair or dereference broken bootstrap alias');
    rejects(sub { xCAT::FreeBSDRepo::snapshot_tree("$dvd/packages") }, qr/Dangling/,
        'generic repository inspection does not permit the DVD-specific defect');
    write_file("$dvd/packages/FreeBSD:15:amd64/All/pkg-2.6.2_1.pkg", 'fixed alias target');
    is_deeply(xCAT::FreeBSDRepo::inspect_release_tree($dvd)->{repositories}{applications}{tree}{unresolved_links}, {},
        'existing bootstrap alias target does not require normalization');

    for my $media_case (
        ['release', sub { write_file("$_[0]/bin/freebsd-version", "USERLAND_VERSION=\"15.0-RELEASE\"\n") }, qr/15\.1-RELEASE/x],
        ['duplicate release', sub { write_file("$_[0]/bin/freebsd-version", "USERLAND_VERSION=\"15.1-RELEASE\"\n" x 2) }, qr/15\.1-RELEASE/x],
        ['shell architecture', sub { write_file("$_[0]/bin/sh", "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 183)) }, qr/amd64 shell/],
        ['shell OS ABI', sub { write_file("$_[0]/bin/sh", "\x7fELF\x02\x01\x01\x00" . ("\0" x 10) . pack('v', 62)) }, qr/amd64 shell/],
        ['missing metadata', sub { unlink("$_[0]/usr/freebsd-packages/offline/data.pkg") or croak $! }, qr/metadata/],
        ['empty metadata', sub { write_file("$_[0]/usr/freebsd-packages/offline/meta.conf", '') }, qr/metadata/],
        ['foreign applications', sub { make_path("$_[0]/packages/FreeBSD:15:aarch64") }, qr/directory/],
        ['missing offline base', sub { rename("$_[0]/usr/freebsd-packages/offline", "$_[0]/usr/freebsd-packages/other") or croak $! }, qr/directory/],
    ) {
        my $root = release_tree(0);
        $media_case->[1]->($root);
        rejects(sub { xCAT::FreeBSDRepo::inspect_release_tree($root) }, $media_case->[2], "rejects $media_case->[0]");
    }
    for my $link_target ('../All/missing.pkg', '../All/pkg-2.6.2_2.pkg', '../../../outside') {
        my $root = release_tree(1);
        unlink("$root/packages/FreeBSD:15:amd64/Latest/pkg.pkg") or croak $!;
        symlink($link_target, "$root/packages/FreeBSD:15:amd64/Latest/pkg.pkg") or croak $!;
        rejects(sub { xCAT::FreeBSDRepo::inspect_release_tree($root) }, qr/Dangling|escapes/x,
            "DVD exception does not permit $link_target");
    }
    my $foreign_alias = release_tree(1);
    symlink('absent', "$foreign_alias/packages/another-alias") or croak $!;
    rejects(sub { xCAT::FreeBSDRepo::inspect_release_tree($foreign_alias) }, qr/Dangling/,
        'DVD exception does not permit another dangling alias');
    return;
}

sub open_race_case {
    my $root = tree();
    write_file("$root/swap", 'original');
    my $program = <<'PERL';
use strict;
use warnings;
use POSIX qw(mkfifo);
our $swapped;
BEGIN {
    *CORE::GLOBAL::sysopen = sub (*$$;$) {
        if ($_[1] eq "$ARGV[0]/swap" && !$swapped++) {
            unlink($_[1]) or die $!;
            mkfifo($_[1], 0600) or die $!;
        }
        return @_ == 4 ? CORE::sysopen($_[0], $_[1], $_[2], $_[3])
          : CORE::sysopen($_[0], $_[1], $_[2]);
    };
}
require $ARGV[1];
$SIG{ALRM} = sub { print "open deadline exceeded\n"; exit 2; };
alarm 2;
eval { xCAT::FreeBSDRepo::snapshot_tree($ARGV[0]); 1 };
my $error = $@;
alarm 0;
print $error;
PERL
    open(my $child, '-|', $^X, '-e', $program, $root, abs_path($INC{'xCAT/FreeBSDRepo.pm'})) or croak $!;
    my $output = do { local $/ = undef; <$child> };
    close($child);
    is($?, 0, 'replacement FIFO does not block the regular-file open');
    like($output, qr/changed[ ]while[ ]opening/x, 'opened replacement is rejected by its descriptor identity');
    return;
}

my $source_tree = snapshot_cases();
link_cases($source_tree);
limit_cases();
media_cases();
open_race_case();

done_testing();
