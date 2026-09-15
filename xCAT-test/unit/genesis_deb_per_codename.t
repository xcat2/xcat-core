#!/usr/bin/env perl
# The Genesis image carries the kernel and the kernel modules of the root that built it, so
# builddebs.pl --genesis builds one image per codename, in that codename's chroot. Each
# assertion here reads the value the code returns.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

require XCAT::BuildUtils;

my @WANTED = qw(genesis_chroot_name genesis_target_arch genesis_build_plan genesis_log_errors);
for my $sub (@WANTED) {
    ok(XCAT::BuildUtils->can($sub), "XCAT::BuildUtils provides $sub");
}
unless (scalar(grep { XCAT::BuildUtils->can($_) } @WANTED) == scalar @WANTED) {
    diag('builddebs.pl has no Genesis step: the per-codename build does not exist yet');
    done_testing();
    exit;
}

# --- one build per codename, in that codename's chroot ---------------------------------
my @dists = qw(jammy noble resolute);
my @plan  = XCAT::BuildUtils::genesis_build_plan(\@dists, 'amd64');

is(scalar @plan, scalar @dists, 'one Genesis build per codename');
is_deeply([ map { $_->{codename} } @plan ], \@dists, 'the plan keeps the codename order');
is_deeply([ map { $_->{chroot} } @plan ],
    [ 'jammy-amd64-sbuild', 'noble-amd64-sbuild', 'resolute-amd64-sbuild' ],
    'each codename builds in its own sbuild chroot');
is_deeply([ map { $_->{package} } @plan ],
    [ ('xcat-genesis-base-amd64') x 3 ],
    'every codename produces the same package name');

my @ppc = XCAT::BuildUtils::genesis_build_plan(['noble'], 'ppc64el');
is($ppc[0]{chroot},  'noble-ppc64el-sbuild', 'the architecture selects the chroot');
is($ppc[0]{package}, 'xcat-genesis-base-ppc64el', 'the architecture is in the package name');
is($ppc[0]{target},  'ppc64', 'ppc64el reads its image from the ppc64 directory');
is(XCAT::BuildUtils::genesis_target_arch('amd64'), 'x86_64',
    'amd64 reads its image from the x86_64 directory');

is(scalar(() = XCAT::BuildUtils::genesis_build_plan([qw(noble noble)], 'amd64')), 1,
    'a repeated codename does not build twice');

ok(!eval { XCAT::BuildUtils::genesis_build_plan([], 'amd64'); 1 },
    'a plan with no codename is an error');
ok(!eval { XCAT::BuildUtils::genesis_target_arch('riscv64'); 1 },
    'an architecture with no Genesis image directory is an error');

# --- a per-codename image reaches only its own suite --------------------------------------
ok(XCAT::BuildUtils->can('deb_belongs_to_dist'),
    'XCAT::BuildUtils decides which suite a deb belongs to');
if (XCAT::BuildUtils->can('deb_belongs_to_dist')) {
    my $noble = 'xcat-genesis-base-amd64_2.19.0-snap202609121200~noble_all.deb';
    ok(XCAT::BuildUtils::deb_belongs_to_dist($noble, 'noble'),
        'the noble image is published into noble');
    ok(!XCAT::BuildUtils::deb_belongs_to_dist($noble, 'jammy'),
        'the noble image is not published into jammy');
    # Everything else in xcat-core is the same file for every release.
    ok(XCAT::BuildUtils::deb_belongs_to_dist('perl-xcat_2.19.0-snap1_all.deb', 'jammy'),
        'a deb with no codename in its version reaches every suite');
    ok(XCAT::BuildUtils::deb_belongs_to_dist('xcat_2.19.0-snap1_amd64.deb', 'resolute'),
        'an architecture deb reaches every suite');
}

# --- the log guard ---------------------------------------------------------------------
#
# dracut prints FAILED: for a command it cannot install and exits 0.
my $dracut_log = <<'LOG';
Installing build dependencies...
dracut: Executing: /usr/bin/dracut --compress gzip -m xcat base -N -f /tmp/genesis.rfs 6.8.0-45-generic
dracut-install: ERROR: installing 'dhclient'
dracut: FAILED: /usr/lib/dracut/dracut-install -D /var/tmp/dracut.XXXX -a dhclient
dracut: *** Creating initramfs image file '/tmp/genesis.rfs' done ***
Extracting initramfs...
LOG

my @errors = XCAT::BuildUtils::genesis_log_errors($dracut_log);
ok(scalar @errors, 'a dracut log with a FAILED: line is an error');
like($errors[0]{line}, qr/FAILED:/, 'the offending line is reported');
ok(length $errors[0]{why}, 'the reason is named');

is_deeply([ XCAT::BuildUtils::genesis_log_errors(<<'LOG') ], [], 'a clean build log is not an error');
Installing build dependencies...
dracut: *** Creating initramfs image file '/tmp/genesis.rfs' done ***
Extracting initramfs...
dpkg-deb: building package 'xcat-genesis-base-amd64'
LOG

for my $case (
    [ 'E: Unable to locate package isc-dhcp-client' => 'a package apt cannot find' ],
    [ 'dracut: Cannot find module directory /lib/modules/6.8.0' => 'a module directory dracut cannot find' ],
    [ '/build/builddeb-genesis-base: line 9: dch: command not found' => 'a command the build root lacks' ],
    [ 'E: Unable to correct problems, you have held broken packages.' => 'a build root apt cannot resolve' ],
  )
{
    my ($line, $what) = @{$case};
    ok(scalar XCAT::BuildUtils::genesis_log_errors("before\n$line\nafter\n"),
        "the log guard catches $what");
}

is_deeply([ XCAT::BuildUtils::genesis_log_errors(undef) ], [], 'no log is not an error');

# --- the builder refuses a root of another release -------------------------------------
my $builder = repo_path('xCAT-genesis-base/builddeb-genesis-base');
if (!-f $builder) {
    fail('xCAT-genesis-base/builddeb-genesis-base is missing');
    done_testing();
    exit;
}

my $tmp = tempdir(CLEANUP => 1);
mkdir "$tmp/bin";
# dpkg is shadowed so the guard is tested on any host, and so the test cannot reach apt.
write_text("$tmp/bin/dpkg", "#!/bin/sh\necho amd64\n");
chmod 0755, "$tmp/bin/dpkg";

sub build_in_a_root_of {
    my ($codename, $expected) = @_;
    write_text("$tmp/os-release", "ID=ubuntu\nVERSION_CODENAME=$codename\n");
    my $err = "$tmp/err";
    my $cmd = sprintf('PATH=%s:$PATH OS_RELEASE=%s /bin/bash %s --expect-codename %s >/dev/null 2>%s',
        "'$tmp/bin'", "'$tmp/os-release'", "'$builder'", "'$expected'", "'$err'");
    system('/bin/bash', '-c', $cmd);
    return ($? >> 8, -f $err ? read_text($err) : '');
}

my ($rc, $err) = build_in_a_root_of('jammy', 'noble');
isnt($rc, 0, 'the builder refuses to build noble in a jammy root');
like($err, qr/jammy/, 'the message names the root it woke up in');
like($err, qr/noble/, 'the message names the release that was asked for');

done_testing();
