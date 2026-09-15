#!/usr/bin/env perl
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path slurp_repo_file);

plan skip_all => 'requires Linux root with mount and network namespaces'
    unless $^O eq 'linux' && $> == 0;
plan skip_all => 'mount and network namespaces unavailable'
    if system('unshare -mn -- true >/dev/null 2>&1');

my $tmp = tempdir(DIR => '/var/tmp', CLEANUP => !$ENV{XCAT_POST_REPOS_KEEP});
diag("fixtures: $tmp") if $ENV{XCAT_POST_REPOS_KEEP};
my $scriptdir = 'xCAT-server/share/xcat/install/scripts';
my $postscript = slurp_repo_file("$scriptdir/post.rhels8");
my $library = slurp_repo_file("$scriptdir/scriptlib");
my $include = '#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/scriptlib#';
$postscript =~ s/^\Q$include\E$/$library/m
    or BAIL_OUT('Unable to render the scriptlib include');
my $preamble = <<'SH';
compgen() { return 1; }
nmcli() { return 0; }
SH
$postscript =~ s/\A(#![^\n]*\n)/$1$preamble/
    or BAIL_OUT('Unable to stage the network fixture');
write_file("$tmp/post.rhels8", $postscript);
is(system('/bin/bash', '-n', "$tmp/post.rhels8"), 0,
    'the complete rendered post owner has valid Bash syntax');
write_file("$tmp/namespace", <<'SH');
#!/bin/bash
set -eu
[ "$(readlink /proc/self/ns/mnt)" != "$XCAT_POST_HOST_MOUNT" ]
[ "$(readlink /proc/self/ns/net)" != "$XCAT_POST_HOST_NET" ]
mount --make-rprivate /
mount --bind "$XCAT_POST_REPOS_FIXTURE/etc" /etc
exec /bin/bash "$XCAT_POST_REPOS_OWNER"
SH
chmod 0755, "$tmp/namespace" or die $!;
my @legacy = qw(
    oracle-linux-ol8.repo oracle-linux-ol9.repo uek-ol8.repo uek-ol9.repo
    Rocky-AppStream.repo Rocky-BaseOS.repo Rocky-Extras.repo rocky.repo
    rocky-extras.repo CentOS-Base.repo centos.repo centos-addons.repo
    almalinux-ha.repo almalinux-nfv.repo almalinux-powertools.repo
    almalinux.repo almalinux-resilientstorage.repo almalinux-rt.repo
);
my $enabled = "[fixture]\nenabled=1\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
my $disabled = "[fixture]\nenabled=0\ngpgcheck=1\nbaseurl=https://repo.invalid/\n";
my $native = "[OS]\nenabled=1\ngpgcheck=1\n[update]\n \tenabled = 1\n[disabled]\nenabled=0\n#enabled=1\n";
my $native_expected = "[OS]\nenabled=0\ngpgcheck=1\n[update]\nenabled=0\n[disabled]\nenabled=0\n#enabled=1\n";
my $host_mount = readlink('/proc/self/ns/mnt');
my $host_net = readlink('/proc/self/ns/net');
my %host_repos = map { $_ => sha256_hex(read_file($_)) }
    glob('/etc/yum.repos.d/*.repo');

for my $case (
    ['enabled', $native, $native_expected],
    ['already-disabled', $native_expected, $native_expected],
    ['absent', undef, undef],
) {
    my ($name, $input, $expected) = @$case;
    my $fixture = "$tmp/$name";
    my $repos = "$fixture/etc/yum.repos.d";
    make_path($repos);
    copy('/etc/ld.so.cache', "$fixture/etc/ld.so.cache") or die $!
        if -f '/etc/ld.so.cache';
    write_file("$repos/$_", $enabled) for @legacy;
    write_file("$repos/openEuler.repo", $input) if defined $input;
    my @preserved = qw(local-repository-0.repo xCAT-custom.repo administrator.repo);
    write_file("$repos/$_", $enabled) for @preserved;
    subtest $name => sub {
        local %ENV = (%ENV, XCATDEBUGMODE => '0', MASTER_IP => '192.0.2.1',
            XCAT_POST_REPOS_FIXTURE => $fixture, XCAT_POST_REPOS_OWNER => "$tmp/post.rhels8",
            XCAT_POST_HOST_MOUNT => $host_mount, XCAT_POST_HOST_NET => $host_net,
            PATH => '/usr/sbin:/usr/bin:/sbin:/bin', LC_ALL => 'C');
        for my $pass (1, 2) {
            my $pid = fork(); die $! unless defined $pid;
            if (!$pid) {
                open(STDIN, '<', '/dev/null') or die $!;
                open(STDOUT, '>', "$fixture/stdout-$pass.log") or die $!;
                open(STDERR, '>', "$fixture/stderr-$pass.log") or die $!;
                exec('unshare', '-mn', '--', "$tmp/namespace") or die $!;
            }
            waitpid($pid, 0);
            is($?, 0, "pass $pass runs the whole post owner in isolation")
                or diag(read_file("$fixture/stderr-$pass.log"));
            if (defined $expected) {
                is(read_file("$repos/openEuler.repo"), $expected,
                    "pass $pass disables only active native repository assignments");
            } else {
                ok(!-e "$repos/openEuler.repo", "pass $pass does not create an absent vendor file");
            }
            is(read_file("$repos/$_"), $disabled, "pass $pass preserves policy for $_") for @legacy;
            is(read_file("$repos/$_"), $enabled, "pass $pass leaves $_ unchanged") for @preserved;
        }
    };
}
is_deeply({map { $_ => sha256_hex(read_file($_)) } glob('/etc/yum.repos.d/*.repo')},
    \%host_repos, 'host repository files remain unchanged');
is(readlink('/proc/self/ns/mnt'), $host_mount, 'host mount namespace remains unchanged');
is(readlink('/proc/self/ns/net'), $host_net, 'host network namespace remains unchanged');
done_testing();

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>:raw', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die "$path: $!";
}

sub read_file {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or die "$path: $!";
    local $/;
    my $contents = <$fh>;
    close($fh) or die "$path: $!";
    return $contents // '';
}
