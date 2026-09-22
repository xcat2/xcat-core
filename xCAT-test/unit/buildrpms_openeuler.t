#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use XCAT::Test::File qw(repo_path slurp_repo_file);
use XCAT::BuildUtils qw(openeuler_build_target openeuler_repo_subdir targetarch_from_target);

foreach my $version (['20.03 (LTS-SP4)', '20.03sp4'], ['22.03 (LTS-SP4)', '22.03sp4'],
                    ['24.03 (LTS-SP1)', '24.03sp1'], ['24.03 (LTS-SP3)', '24.03sp3'],
                    ['24.03 (LTS-SP4)', '24.03sp4'], ['24.03 (LTS)', '24.03']) {
    foreach my $arch ('x86_64', 'ppc64le') {
        my $target = "openeuler-$version->[1]-$arch";
        is(openeuler_build_target({ID => 'openEuler', VERSION => $version->[0], VERSION_ID => '24.03'}, $arch),
            $target, "$target retains native host service pack");
        is(openeuler_repo_subdir($target), "openeuler$version->[1]/$arch", 'repository subdirectory matches bootstrap');
        is(targetarch_from_target($target), $arch, 'existing architecture parser handles the native target');
    }
}
is(openeuler_build_target({ID => 'openeuler', VERSION_ID => '24.03'}, 'ppc64le'), 'openeuler-24.03-ppc64le',
    'VERSION_ID supplies GA when VERSION is absent');
is(openeuler_build_target({ID => 'rocky', VERSION_ID => '9.6'}, 'x86_64'), undef, 'EL host selection remains outside native mapping');
is(openeuler_repo_subdir('alma+epel-10-x86_64'), undef, 'EL repository layout remains outside native mapping');
foreach my $invalid ('openeuler-24.09-x86_64', 'openeuler-25.03-x86_64', 'openeuler-24.03sp0-x86_64', 'openeuler-24.03-ppc64') {
    eval {openeuler_repo_subdir($invalid)};
    like($@, qr/Unsupported openEuler build target/, "$invalid is rejected");
}

my $root = tempdir(CLEANUP => 1);
my $driver = "$root/driver.pl";
write_file($driver, <<'PERL');
BEGIN {
    require File::Slurper;
    require Parallel::ForkManager;
    no warnings 'redefine';
    *Parallel::ForkManager::new = sub { die "BUILD_BOUNDARY\n" } if $ENV{BUILD_STOP};
    my $write = \&File::Slurper::write_text;
    *File::Slurper::write_text = sub {
        my ($path, @rest) = @_;
        $path =~ s{^/etc/yum\.repos\.d/}{$ENV{BUILD_FIXTURE}/repos/};
        return $write->($path, @rest);
    };
    *CORE::GLOBAL::readpipe = sub {
        return "$ENV{BUILD_ARCH}\n" if $_[0] eq 'uname -m';
        return CORE::readpipe($_[0]);
    };
    *CORE::GLOBAL::system = sub {
        if (@_ == 1 && $_[0] =~ /source \/etc\/os-release/) {
            my $shell = "$ENV{BUILD_FIXTURE}/install.sh";
            CORE::open(my $fh, '>', $shell) or die $!;
            print {$fh} 'source() { . "$BUILD_FIXTURE/os-release"; }', "\n", $_[0];
            close($fh);
            return CORE::system('bash', $shell);
        }
        return 0;
    };
}
do './buildrpms.pl';
die $@ if $@;
PERL

my $native = run_builder('openEuler', '24.03 (LTS-SP3)', '24.03', 'x86_64', '--setup_local_repos');
is($native->{status}, 0, 'full builder creates local repositories for the native default target');
like($native->{core}, qr{/dist/openeuler-24\.03sp3-x86_64/rpms$}m, 'full builder selects the exact native mock target');
like($native->{dep}, qr{/openeuler24\.03sp3/x86_64$}m, 'full builder selects matching dependency artifacts');
like($native->{core}, qr/^gpgcheck=1$/m, 'native core repository requires signatures');
like($native->{dep}, qr/^gpgcheck=1$/m, 'native dependency repository requires signatures');
my $explicit = run_builder('rocky', '9.6', '9.6', 'x86_64', '--setup_local_repos', '--target', 'openeuler-24.03-ppc64le');
is($explicit->{status}, 0, 'an explicit native target overrides the host default for repository setup');
like($explicit->{dep}, qr{/openeuler24\.03/ppc64le$}m, 'explicit native target chooses its own release and architecture');
my $el = run_builder('rocky', '9.6', '9.6', 'x86_64', '--setup_local_repos');
is($el->{status}, 0, 'existing EL local repository setup completes');
like($el->{core}, qr{/dist/rocky\+epel-10-x86_64/rpms$}m, 'existing EL default target is unchanged');
like($el->{dep}, qr{/el9/x86_64$}m, 'existing EL dependency path is unchanged');
for my $missing (qw(core dep)) {
    local $ENV{BUILD_MISSING_KEY} = $missing;
    my $result = run_builder('openEuler', '24.03 (LTS-SP3)', '24.03', 'x86_64', '--setup_local_repos');
    isnt($result->{status}, 0, "setup rejects the missing $missing exported key");
    like($result->{stderr}, qr/Missing openEuler repository signing key/, 'setup identifies the absent trust input');
    is($result->{core} . $result->{dep}, '', 'setup fails before writing either repository configuration');
}
{
    local $ENV{BUILD_STOP} = 1;
    my $unsigned = run_builder('openEuler', '24.03 (LTS-SP3)', '24.03', 'x86_64', '--package', 'xCAT-client');
    isnt($unsigned->{status}, 0, 'unsigned native binary builds are rejected');
    like($unsigned->{stderr}, qr/openEuler binary repository builds require --gpg-sign/, 'the CLI reports the signing requirement');
    unlike($unsigned->{stderr}, qr/BUILD_BOUNDARY/, 'unsigned native builds stop before the build scheduler');
    for my $case (['native signed', 'openEuler', '--gpg-sign'], ['native source only', 'openEuler', '--source-only'],
                  ['legacy unsigned', 'rocky']) {
        my ($label, $id, @args) = @$case;
        my $result = run_builder($id, '24.03 (LTS-SP3)', '24.03', 'x86_64', '--package', 'xCAT-client', @args);
        like($result->{stderr}, qr/BUILD_BOUNDARY/, "$label reaches the existing build scheduler");
        unlike($result->{stderr}, qr/repository builds require --gpg-sign/, "$label preserves its signing policy");
    }
}
my $install = run_builder('openEuler', '24.03 (LTS-SP3)', '24.03', 'x86_64', '--install_deps');
is($install->{status}, 0, 'full native prerequisite entry point completes through process boundaries');
unlike($install->{commands}, qr/epel|crb|codeready/i, 'native prerequisites do not enable EL repositories');
unlike($install->{commands}, qr/\bpodman\b/, 'native prerequisites do not request an unrelated container bootstrap');
like($install->{commands}, qr/--setopt=install_weak_deps=False/, 'native prerequisites do not pull optional container dependencies');
like($install->{commands}, qr/--setopt=\*\.gpgcheck=1/, 'native prerequisite installation enforces signatures');
like($install->{commands}, qr/--setopt=strict=1/, 'native prerequisite installation does not skip missing packages');
like($install->{commands}, qr/\bsystemd-nspawn\b/, 'native prerequisites provide the mock isolation executable');
my $el_install = run_builder('rocky', '9.6', '9.6', 'x86_64', '--install_deps');
like($el_install->{commands}, qr/epel-release-latest-10/, 'existing EL prerequisite repository choice is preserved');
my $merge = run_builder('openEuler', '24.03 (LTS-SP3)', '24.03', 'x86_64', '--merge-core-repos');
isnt($merge->{status}, 0, 'native flat repository assembly is rejected');
like($merge->{stderr}, qr/openEuler repositories must retain their release and architecture/, 'native assembly error preserves the per-cell output contract');
my $el_merge = run_builder('rocky', '9.6', '9.6', 'x86_64', '--merge-core-repos', '--output-dir', 'merged', '--input-core-repos', 'native-input');
isnt($el_merge->{status}, 0, 'an EL host cannot flatten copied native inputs');
like($el_merge->{stderr}, qr/openEuler repositories must retain their release and architecture/, 'native build provenance survives copying to an unrelated path');
{
    local $ENV{BUILD_DNF_FAILURE} = 37;
    my $failed = run_builder('openEuler', '24.03 (LTS-SP3)', '24.03', 'x86_64', '--install_deps');
    is($failed->{status}, 37, 'native prerequisite failure terminates the entry point');
}
done_testing();

sub run_builder {
    my ($id, $version, $version_id, $arch, @args) = @_;
    my $fixture = tempdir(DIR => $root, CLEANUP => 1);
    make_path("$fixture/build-utils/lib/XCAT", "$fixture/bin", "$fixture/repos", "$fixture/native-input", "$fixture/locks", "$fixture/home",
        "$fixture/dep/openeuler24.03sp3/x86_64", "$fixture/dep/openeuler24.03/ppc64le", "$fixture/dep/el9/x86_64");
    my $body = read_file($ENV{XCAT_TEST_BUILDRPMS} || repo_path('buildrpms.pl'));
    $body =~ s{'/etc/os-release'}{'$fixture/os-release'}g;
    $body =~ s{/var/lock/}{$fixture/locks/}g;
    write_file("$fixture/buildrpms.pl", $body);
    copy(repo_path('build-utils/lib/XCAT/BuildUtils.pm'), "$fixture/build-utils/lib/XCAT/BuildUtils.pm") or die $!;
    copy($driver, "$fixture/driver.pl") or die $!;
    write_file("$fixture/Version", "2.18.0\n");
    write_file("$fixture/Gitepoch", "1756000000\n");
    write_file("$fixture/native-input/buildinfo.txt", "BUILD_TARGET=openeuler-24.03sp3-x86_64\n");
    write_file("$fixture/os-release", "ID=$id\nVERSION=\"$version\"\nVERSION_ID=$version_id\n");
    for my $target ('openeuler-24.03sp3-x86_64', 'openeuler-24.03-ppc64le') {
        my $subdir = openeuler_repo_subdir($target);
        for my $key (['core', "$fixture/dist/$target/rpms"], ['dep', "$fixture/dep/$subdir"]) {
            make_path("$key->[1]/repodata");
            write_file("$key->[1]/repodata/repomd.xml.key", 'existing exported key')
                unless ($ENV{BUILD_MISSING_KEY} || '') eq $key->[0];
        }
    }
    write_file("$fixture/bin/dnf", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >> \"\$BUILD_FIXTURE/commands\"\nexit \"\${BUILD_DNF_FAILURE:-0}\"\n");
    write_file("$fixture/bin/systemctl", "#!/bin/sh\nexit 0\n");
    write_file("$fixture/bin/rpmdev-setuptree", "#!/bin/sh\nexit 0\n");
    chmod 0755, map {"$fixture/bin/$_"} qw(dnf systemctl rpmdev-setuptree);
    local %ENV = (%ENV, HOME => "$fixture/home", BUILD_FIXTURE => $fixture, BUILD_ARCH => $arch, PATH => "$fixture/bin:$ENV{PATH}");
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        chdir($fixture) or die $!;
        open(STDOUT, '>', 'stdout') or die $!;
        open(STDERR, '>', 'stderr') or die $!;
        exec($^X, 'driver.pl', @args, '--xcat_dep_path', "$fixture/dep") or die $!;
    }
    waitpid($pid, 0);
    my $status = $? >> 8;
    my $result = {status => $status, core => read_file("$fixture/repos/xcat-core-local.repo"),
        dep => read_file("$fixture/repos/xcat-dep.repo"), commands => read_file("$fixture/commands"), stderr => read_file("$fixture/stderr")};
    diag(read_file("$fixture/stderr")) if $status && !$ENV{BUILD_DNF_FAILURE} && !$ENV{BUILD_MISSING_KEY}
        && !$ENV{BUILD_STOP} && !grep {$_ eq '--merge-core-repos'} @args;
    return $result;
}
sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die $!;
}
sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die $!;
    return do {local $/; scalar <$fh>} || '';
}
