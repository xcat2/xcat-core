#!/usr/bin/env perl
use strict;
use warnings;
use Capture::Tiny qw(capture);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'requires a Debian-family package builder'
    unless $^O eq 'linux' && -f '/etc/debian_version';
require Dpkg::Control::Info;

my $build = tempdir(CLEANUP => 1);
make_path("$build/source", "$build/home");
for my $entry (qw(builddebs.pl build-utils Version Release xCAT-buildkit)) {
    system('cp', '-a', repo_path($entry), "$build/source/") == 0 or die "Cannot copy $entry";
}
{
    local %ENV = (%ENV, HOME => "$build/home", SOURCE_DATE_EPOCH => 1750000000,
        PATH => '/usr/bin:/bin', LC_ALL => 'C');
    my ($stdout, $stderr, $status) = capture {
        system($^X, "$build/source/builddebs.pl", '--package', 'xCAT-buildkit',
            '--dist', 'noble', '--release', 'test1', '--dest', "$build/output")
    };
    is($status, 0, 'the real Debian builder creates a package and repository') or diag($stdout . $stderr);
    die 'the builder did not complete' if $status;
}
my $repository = "$build/output/xcat-core";
ok(-x "$repository/mklocalrepo.sh", 'the builder delivers an executable repository helper');
ok(-f "$repository/dists/noble/Release", 'the helper accompanies a published repository');

for my $case (['riscv64', 'riscv64'], ['ppc64le', 'ppc64el'], ['x86_64', 'amd64']) {
    my ($machine, $architecture) = @$case;
    for my $release (qw(noble jammy)) {
        subtest "$machine $release" => sub {
            my $root = sandbox_root();
            make_path("$root/etc/apt/sources.list.d");
            write_text("$root/etc/lsb-release", "DISTRIB_CODENAME=$release\n");
            write_text("$root/bin/uname", "#!/bin/sh\n[ \"\$*\" = -m ] || exit 2\nprintf '%s\\n' '$machine'\n");
            chmod 0755, "$root/bin/uname" or die $!;
            write_text("$root/etc/apt/sources.list.d/administrator.list", "preserved\n");
            for my $pass (1, 2) {
                my ($status, $output) = sandbox_run($root,
                    {read_only => {$repository => '/repo'}}, '/repo/mklocalrepo.sh');
                is($status, 0, "pass $pass executes the generated helper unchanged") or diag($output);
                is(read_text("$root/etc/apt/sources.list.d/xcat-core.list"),
                    "deb [arch=$architecture] file:///repo $release main\n",
                    "pass $pass selects the host architecture and distribution");
                is(read_text("$root/etc/apt/sources.list.d/administrator.list"), "preserved\n",
                    "pass $pass preserves unrelated sources");
            }
        };
    }
}

for my $case (['xCAT', 'xcat'], ['xCATsn', 'xcatsn']) {
    my ($component, $package) = @$case;
    my $control = Dpkg::Control::Info->new(repo_path("$component/debian/control"));
    my ($binary) = grep { $_->{Package} eq $package } $control->get_packages();
    ok($binary, "$package has a binary package stanza");
    my %architecture = map { $_ => 1 } split /\s+/, $binary->{Architecture} // '';
    ok($architecture{$_}, "$package supports $_") for qw(riscv64 amd64 ppc64el);
}

done_testing();
