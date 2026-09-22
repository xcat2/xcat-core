#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path slurp_repo_file);

plan skip_all => 'requires unprivileged Linux RPM tooling'
    unless $^O eq 'linux' && $>
    && system('sh', '-c', 'command -v rpmbuild >/dev/null && command -v rpm2cpio >/dev/null && command -v cpio >/dev/null') == 0;

my $root = tempdir(CLEANUP => !$ENV{XCAT_RELEASE_TEST_KEEP});
diag("Release contract fixtures: $root") if $ENV{XCAT_RELEASE_TEST_KEEP};
my $builder = $ENV{XCAT_RELEASE_TEST_BUILDER} || repo_path('buildrpms.pl');
my $spec = $ENV{XCAT_RELEASE_TEST_SPEC} || repo_path('xCAT-release/xCAT-release.spec');
my @files = qw(xcat-core.repo xcat-dep.repo xcat-dep-common.repo RPM-GPG-KEY-xCAT);
my %original = map {$_ => slurp_repo_file("xCAT-release/$_")} @files;
my @cases = (
    ['openeuler-20.03sp4-x86_64', 'openeuler20.03sp4/x86_64'],
    ['openeuler-22.03sp4-x86_64', 'openeuler22.03sp4/x86_64'],
    ['openeuler-24.03sp1-x86_64', 'openeuler24.03sp1/x86_64'],
    ['openeuler-24.03sp3-x86_64', 'openeuler24.03sp3/x86_64', 'default'],
    ['openeuler-24.03sp4-x86_64', 'openeuler24.03sp4/x86_64'],
    ['openeuler-24.03-ppc64le', 'openeuler24.03/ppc64le'],
    ['alma+epel-10-x86_64', undef],
    ['rocky+epel-9-ppc64le', undef],
);

for my $case (@cases) {
    my ($target, $subdir, $default) = @$case;
    my $result = run_builder($target, $subdir, $default);
    is($result->{status}, 0, "$target full builder completes") or diag($result->{output});
    next if $result->{status};
    my $fixture = $result->{fixture};
    my $archive = "$fixture/home/rpmbuild/SOURCES/xCAT-release-2.19.0.tar.gz";
    my $rpm = "$fixture/dist/$target/rpms/xCAT-release-2.19.0-releasecontract.noarch.rpm";
    ok(-f $archive, "$target stages a source archive");
    ok(-f $rpm, "$target emits a real binary RPM");
    next unless -f $archive && -f $rpm;
    make_path("$fixture/staged", "$fixture/payload");
    my ($tar_rc, $tar_output) = run($fixture, 'tar', '-xzf', $archive, '-C', "$fixture/staged");
    is($tar_rc, 0, "$target source archive extracts") or diag($tar_output);
    my ($cpio_rc, $cpio_output) = run($fixture, 'bash', '-o', 'pipefail', '-c',
        'cd "$1" && rpm2cpio "$2" | cpio -idm', 'bash', "$fixture/payload", $rpm);
    is($cpio_rc, 0, "$target real RPM payload extracts") or diag($cpio_output);
    for my $repo (qw(xcat-core xcat-dep)) {
        my $staged = read_file("$fixture/staged/xCAT-release/$repo.repo");
        my $payload = read_file("$fixture/payload/etc/yum.repos.d/$repo.repo");
        is($payload, $staged, "$target $repo RPM consumes the staged bytes");
        if (defined $subdir) {
            like($payload, qr{^baseurl=https://xcat\.org/files/xcat/repos/yum/latest/\Q$repo/$subdir\E$}m,
                "$target $repo retains the exact native release and architecture");
        } else {
            is($payload, $original{"$repo.repo"}, "$target $repo preserves EL bytes");
        }
        for my $setting ('enabled=1', 'gpgcheck=1', 'repo_gpgcheck=1',
                         'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-xCAT') {
            is(scalar(grep {$_ eq $setting} split /\n/, $payload), 1, "$target $repo preserves $setting");
        }
    }
    my $common = "$fixture/payload/etc/yum.repos.d/xcat-dep-common.repo";
    if (defined $subdir) {
        ok(!-e $common, "$target does not install the common dependency repository");
    } else {
        is(read_file($common), $original{'xcat-dep-common.repo'}, "$target preserves common repository bytes");
    }
    is(read_file("$fixture/payload/etc/pki/rpm-gpg/RPM-GPG-KEY-xCAT"), $original{'RPM-GPG-KEY-xCAT'},
        "$target preserves the packaged trust key");
    my ($query_rc, $metadata) = run($fixture, 'rpm', '-qp', '--qf',
        '[%{FILENAMES}\t%{FILEFLAGS}\t%{FILEMODES:perms}\n]', $rpm);
    is($query_rc, 0, "$target RPM file metadata is queryable");
    for my $repo ('xcat-core', 'xcat-dep', defined($subdir) ? () : 'xcat-dep-common') {
        like($metadata, qr{^/etc/yum\.repos\.d/\Q$repo\E\.repo\t17\t-rw-r--r--$}m,
            "$target $repo remains config(noreplace), mode 0644");
    }
    is(read_file("$fixture/xCAT-release/$_"), $original{$_}, "$target leaves input $_ unchanged") for @files;
}

for my $failure (qw(missing-core duplicate-dep copy tar)) {
    my $result = run_builder('openeuler-24.03sp3-x86_64', 'openeuler24.03sp3/x86_64', undef, $failure);
    isnt($result->{status}, 0, "$failure stops the native builder");
    my $fixture = $result->{fixture};
    is(read_file("$fixture/home/rpmbuild/SOURCES/xCAT-release-2.19.0.tar.gz"), 'prior archive',
        "$failure preserves the preceding source archive");
    is(read_file("$fixture/mock.commands"), '', "$failure stops before mock initialization or SRPM creation");
    ok(!-e "$fixture/dist/openeuler-24.03sp3-x86_64/rpms/xCAT-release-latest.noarch.rpm",
        "$failure does not publish a bootstrap alias");
    is_deeply([glob("$fixture/home/rpmbuild/SOURCES/.xCAT-release-*")], [],
        "$failure removes an incomplete temporary archive");
    is_deeply([glob("$fixture/tmp/xcat-release-source.*")], [], "$failure cleans the staged source copy");
}
my $invalid = run_builder('openeuler-24.03-ppc64', 'invalid');
isnt($invalid->{status}, 0, 'an unsupported native architecture is rejected');
like($invalid->{output}, qr/Unsupported openEuler build target/, 'invalid target reports the native mapping error');
is(read_file("$invalid->{fixture}/mock.commands"), '', 'an invalid target never reaches mock');
my $missing_common = run_builder('alma+epel-10-x86_64', undef, undef, 'missing-common');
isnt($missing_common->{status}, 0, 'EL still rejects a missing common repository input');
like($missing_common->{output}, qr/cannot stat .*xcat-dep-common\.repo/,
    'the EL RPM install requires its common repository file');
ok(!-e "$missing_common->{fixture}/dist/alma+epel-10-x86_64/rpms/xCAT-release-latest.noarch.rpm",
    'a failed EL payload does not publish a bootstrap alias');

done_testing();

sub run_builder {
    my ($target, $subdir, $default, $failure) = @_;
    my $fixture = tempdir(DIR => $root, CLEANUP => !$ENV{XCAT_RELEASE_TEST_KEEP});
    make_path(map {"$fixture/$_"} qw(build-utils/lib/XCAT bin mock locks tmp xCAT-release home/rpmbuild/SOURCES));
    my $body = read_file($builder);
    $body =~ s{'/etc/os-release'}{'$fixture/os-release'}g;
    $body =~ s{/etc/mock/}{$fixture/mock/}g;
    $body =~ s{/var/lock/}{$fixture/locks/}g;
    $body =~ s/\$ENV\{HOME\}/\$ENV{XCAT_RELEASE_TEST_HOME}/g;
    write_file("$fixture/buildrpms.pl", $body);
    copy(repo_path('build-utils/lib/XCAT/BuildUtils.pm'), "$fixture/build-utils/lib/XCAT/BuildUtils.pm") or die $!;
    copy($spec, "$fixture/xCAT-release/xCAT-release.spec") or die $!;
    write_file("$fixture/xCAT-release/$_", $original{$_}) for @files;
    write_file("$fixture/Version", "2.19.0\n");
    write_file("$fixture/Gitepoch", "1756000000\n");
    write_file("$fixture/Gitinfo", ('a' x 40) . "\n");
    write_file("$fixture/os-release", $default
        ? "ID=openEuler\nVERSION=\"24.03 (LTS-SP3)\"\nVERSION_ID=24.03\n"
        : "ID=rocky\nVERSION=9.6\nVERSION_ID=9.6\n");
    write_file("$fixture/mock/$target.cfg", "config_opts['root'] = '$target'\n");
    write_file("$fixture/bin/createrepo_c", "#!/bin/sh\nexit 0\n");
    write_file("$fixture/bin/rpmsign", "#!/bin/sh\nexit 0\n");
    write_file("$fixture/bin/gpg", "#!/bin/sh\nexit 0\n");
    write_file("$fixture/bin/cp", "#!/bin/sh\n[ \"\$XCAT_RELEASE_TEST_FAILURE\" != cp ] || exit 41\nexec /usr/bin/cp \"\$@\"\n");
    write_file("$fixture/bin/tar", <<'SH');
#!/bin/sh
if [ "$XCAT_RELEASE_TEST_FAILURE" = tar ]; then
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -cf|-czf) shift; printf 'partial archive' > "$1"; exit 41 ;;
        esac
        shift
    done
    exit 42
fi
exec /usr/bin/tar "$@"
SH
    write_file("$fixture/bin/mock", mock_command());
    chmod 0755, map {"$fixture/bin/$_"} qw(mock createrepo_c rpmsign gpg cp tar);
    if ($failure) {
        write_file("$fixture/home/rpmbuild/SOURCES/xCAT-release-2.19.0.tar.gz", 'prior archive');
        unlink "$fixture/xCAT-release/xcat-core.repo" if $failure eq 'missing-core';
        unlink "$fixture/xCAT-release/xcat-dep-common.repo" if $failure eq 'missing-common';
        write_file("$fixture/xCAT-release/xcat-dep.repo", $original{'xcat-dep.repo'} .
            "baseurl=https://xcat.org/files/xcat/repos/yum/latest/xcat-dep/rh\$releasever/\$basearch\n")
            if $failure eq 'duplicate-dep';
    }
    local %ENV = (%ENV, PATH => "$fixture/bin:$ENV{PATH}", TMPDIR => "$fixture/tmp", XCAT_RELEASE_TEST_FIXTURE => $fixture,
        XCAT_RELEASE_TEST_HOME => "$fixture/home", XCAT_RELEASE_TEST_NATIVE => defined($subdir) ? 1 : 0,
        XCAT_RELEASE_TEST_FAILURE => ($failure && $failure eq 'copy' ? 'cp' : $failure || ''));
    my @target = $default ? () : ('--target', $target);
    my ($status, $output) = run($fixture, $^X, 'buildrpms.pl', '--package', 'xCAT-release', @target,
        (defined($subdir) ? '--gpg-sign' : ()),
        '--release', 'releasecontract', '--mock-uniqueext', 'release-contract', '--nproc', '1');
    write_file("$fixture/builder-output", $output);
    return {fixture => $fixture, status => $status, output => $output};
}

sub mock_command {
    return <<'PERL';
#!/usr/bin/perl
use strict;
use warnings;
use File::Copy qw(copy);
use File::Path qw(make_path);
my $fixture = $ENV{XCAT_RELEASE_TEST_FIXTURE};
open(my $log, '>>', "$fixture/mock.commands") or die $!;
print {$log} join(' ', @ARGV), "\n";
close($log) or die $!;
my (%args, @defines);
while (@ARGV) {
    my $arg = shift;
    if ($arg eq '--define') {push @defines, $arg, shift;}
    elsif ($arg =~ /^(?:-r|--spec|--sources|--resultdir|--rebuild)$/) {$args{$arg} = shift;}
    else {$args{$arg} = 1;}
}
exit 0 if $args{'--init'};
my $top = "$fixture/mock-rpm";
make_path(map {"$top/$_"} qw(BUILD BUILDROOT RPMS SOURCES SPECS SRPMS));
my @command = ('rpmbuild', @defines, '--define', "_topdir $top", '--undefine', 'openEuler');
push @command, '--define', 'openEuler 2' if $ENV{XCAT_RELEASE_TEST_NATIVE};
my @built;
if ($args{'--buildsrpm'}) {
    push @command, '--define', "_sourcedir $args{'--sources'}", '-bs', $args{'--spec'};
    @built = ("$top/SRPMS/*.src.rpm");
} elsif ($args{'--rebuild'}) {
    push @command, '--rebuild', $args{'--rebuild'};
    @built = ("$top/RPMS/noarch/*.rpm");
} else {die "Unexpected mock operation\n";}
system(@command) == 0 or exit(($? >> 8) || 1);
make_path($args{'--resultdir'});
for my $file (map {glob($_)} @built) {copy($file, $args{'--resultdir'}) or die $!;}
PERL
}

sub run {
    my ($directory, @command) = @_;
    my $log = "$directory/command-output";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if (!$pid) {
        chdir($directory) or die $!;
        open(STDOUT, '>', $log) or die $!;
        open(STDERR, '>&', STDOUT) or die $!;
        exec(@command) or die "exec @command: $!";
    }
    waitpid($pid, 0);
    return ($? ? (($? >> 8) || 1) : 0, read_file($log));
}
sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents or die $!;
    close($fh) or die $!;
}
sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    return do {local $/; scalar <$fh>} || '';
}
