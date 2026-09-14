#!/usr/bin/env perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);

my $script = $ENV{XCAT_TEST_GO_XCAT} || repo_path('xCAT-server/share/xcat/tools/go-xcat');
my $root = tempdir(CLEANUP => 1);
my $driver = "$root/driver.sh";
write_file($driver, <<'SH');
source "$GO_XCAT_SOURCE"
awk() {
    local -a args=("$@")
    local i
    for i in "${!args[@]}"; do
        [[ "${args[i]}" != /etc/os-release ]] || args[i]="$FIXTURE/os-release"
    done
    command awk "${args[@]}"
}
dnf() { printf 'dnf'; printf ' <%s>' "$@"; printf '\n'; return "${PACKAGE_STATUS:-0}"; }
yum() { printf 'yum'; printf ' <%s>' "$@"; printf '\n'; return "${PACKAGE_STATUS:-0}"; }
download_file() { return 1; }
add_repo_by_file() { cp "$1" "$FIXTURE/$2.repo"; }
TMP_DIR="$FIXTURE"
GO_XCAT_LINUX_DISTRO="$(check_linux_distro)"
GO_XCAT_LINUX_VERSION="$(check_linux_version)"
detected=$?
GO_XCAT_ARCH="$TEST_ARCH"
case "$1" in
detect)
    printf '%s\n%s\n' "$GO_XCAT_LINUX_DISTRO" "$GO_XCAT_LINUX_VERSION"
    exit "$detected"
    ;;
repos)
    [[ "$detected" = 0 ]] || exit "$detected"
    GO_XCAT_DEFAULT_BASE_URL=https://packages.example.test/xcat
    add_xcat_core_repo_yum_or_zypper "${CORE_URL:-}" "${REPO_VERSION:-latest}" || exit $?
    add_xcat_dep_repo_yum_or_zypper "${DEP_URL:-}" "${REPO_VERSION:-latest}"
    ;;
install-dnf) install_packages_dnf -y xCAT ;;
install-yum) install_packages_yum -y xCAT ;;
refresh) update_repo_dnf ;;
cleanup-dnf)
    type() { [[ "$1" != yum ]] && builtin type "$@"; }
    grep() { return 1; }
    xargs() { return 0; }
    mv() { return 0; }
    remove_repo_yum xcat-core
    ;;
*) exit 64 ;;
esac
SH

my @versions = (
    ['20.03 (LTS-SP4)', '20.03sp4'],
    ['22.03 (LTS-SP4)', '22.03sp4'],
    ['24.03 (LTS-SP1)', '24.03sp1'],
    ['24.03 (LTS-SP3)', '24.03sp3'],
    ['24.03 (LTS-SP4)', '24.03sp4'],
    ['24.03 (LTS)', '24.03'],
);
foreach my $version (@versions) {
    foreach my $arch ('x86_64', 'ppc64le') {
        my $r = run_case(version => $version->[0], arch => $arch, action => 'repos');
        is($r->{status}, 0, "$version->[1] $arch repo creation completes");
        like($r->{core}, qr{^baseurl=https://packages\.example\.test/xcat/yum/latest/xcat-core/openeuler\Q$version->[1]\E/\Q$arch\E$}m,
            'core repository retains native release, service pack and architecture');
        like($r->{dep}, qr{^baseurl=https://packages\.example\.test/xcat/yum/latest/xcat-dep/openeuler\Q$version->[1]\E/\Q$arch\E$}m,
            'dependency repository retains native release, service pack and architecture');
    }
}

foreach my $id ('openEuler', 'openeuler', "'openEuler'") {
    my $r = run_case(id => $id, version => '24.03 (LTS-SP3)', action => 'detect');
    is($r->{stdout}, "openeuler\n24.03sp3\n", "$id selects native identity");
}
my $single = run_case(version_line => "VERSION='24.03 (LTS-SP3)'\n", action => 'detect');
is($single->{stdout}, "openeuler\n24.03sp3\n", 'single-quoted VERSION retains SP');
my $ga = run_case(version_line => '', action => 'detect');
is($ga->{stdout}, "openeuler\n24.03\n", 'missing VERSION uses VERSION_ID for GA');
foreach my $version ('24.09', '25.03 (LTS)', '24.03 (LTS-SP0)', '24.03 (LTS-SP04)', '24.03 (LTS-SP3) trailing') {
    my $r = run_case(version => $version, action => 'repos');
    isnt($r->{status}, 0, "$version is rejected before repo creation");
    is($r->{core}, '', 'invalid release creates no core repository');
}
my $wrong_arch = run_case(arch => 'ppc64', action => 'repos');
isnt($wrong_arch->{status}, 0, 'big-endian POWER is not silently admitted');

my $override = run_case(action => 'repos', env => {CORE_URL => 'https://custom.example.test/native-core', DEP_URL => 'https://custom.example.test/native-dep'});
like($override->{core}, qr{^baseurl=https://custom\.example\.test/native-core$}m, 'explicit core URL is authoritative');
like($override->{dep}, qr{^baseurl=https://custom\.example\.test/native-dep/openeuler24\.03sp3/x86_64$}m, 'explicit dependency root preserves the exact native suffix');
my $devel = run_case(action => 'repos', env => {REPO_VERSION => 'devel'});
like($devel->{core}, qr{/yum/devel/core-snap/openeuler24\.03sp3/x86_64$}m, 'development core uses its native subdirectory');

my $offline = "$root/offline";
make_path("$offline/core", "$offline/dep/openeuler24.03sp3/x86_64");
my $local = run_case(action => 'repos', env => {CORE_URL => "file://$offline/core", DEP_URL => "file://$offline/dep"});
is($local->{status}, 0, 'offline native directories are usable');
like($local->{core}, qr/^gpgcheck=1$/m, 'offline native core still requires signed packages');
like($local->{dep}, qr/^gpgcheck=1$/m, 'offline native dependencies still require signed packages');
unlike($local->{dep}, qr/^gpgcheck=0$/m, 'missing metadata signature cannot disable package verification');

foreach my $action ('install-dnf', 'install-yum', 'refresh') {
    my $r = run_case(action => $action);
    is($r->{status}, 0, "$action completes through its command boundary");
    like($r->{stdout}, qr/<--setopt=\*\.gpgcheck=1>/, "$action enforces repository package signatures");
    unlike($r->{stdout}, qr/nogpgcheck|strict=0|epel|crb/i, "$action has no native signature or dependency bypass");
    if ($action ne 'refresh') {
        like($r->{stdout}, qr/<install> <initscripts> <xCAT>/, 'native packages share one transaction');
        like($r->{stdout}, qr/<--setopt=strict=1>/, 'native DNF cannot inherit skip-broken configuration') if $action eq 'install-dnf';
        my $failed = run_case(action => $action, env => {PACKAGE_STATUS => 37});
        is($failed->{status}, 37, 'native dependency/signature failure is returned to the caller');
    }
}
foreach my $distro (['rocky', '9.6', 'rh9'], ['rhel', '10.1', 'rh10'], ['sles', '15.6', 'sles15']) {
    my $r = run_case(id => $distro->[0], version_id => $distro->[1], action => 'repos');
    is($r->{status}, 0, "$distro->[0] repo mapping still completes");
    like($r->{core}, qr{/yum/latest/xcat-core$}m, 'existing core layout remains flat');
    like($r->{dep}, qr{/xcat-dep/\Q$distro->[2]\E/x86_64$}m, 'existing dependency mapping is preserved');
}
my $el_install = run_case(id => 'rhel', version_id => '10.1', action => 'install-dnf');
like($el_install->{stdout}, qr/<--nogpgcheck> <--setopt=strict=0>/, 'existing EL install options are unchanged');
my $cleanup = run_case(action => 'cleanup-dnf');
is($cleanup->{status}, 0, 'repository replacement works with DNF and no yum command');
is($cleanup->{stdout}, "dnf <clean> <metadata>\n", 'DNF clears metadata during repository replacement');

done_testing();

sub run_case {
    my (%option) = @_;
    my $fixture = tempdir(DIR => $root, CLEANUP => 1);
    my $version_line = exists($option{version_line}) ? $option{version_line}
        : 'VERSION="' . ($option{version} || '24.03 (LTS-SP3)') . "\"\n";
    write_file("$fixture/os-release", 'ID=' . ($option{id} || 'openEuler') . "\n" . $version_line .
        'VERSION_ID="' . ($option{version_id} || '24.03') . "\"\n");
    local %ENV = (%ENV, GO_XCAT_SOURCE => $script, FIXTURE => $fixture,
        TEST_ARCH => $option{arch} || 'x86_64', %{$option{env} || {}});
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        open(STDOUT, '>', "$fixture/stdout") or die $!;
        open(STDERR, '>', "$fixture/stderr") or die $!;
        exec('bash', $driver, $option{action}) or die $!;
    }
    waitpid($pid, 0);
    my $status = $? >> 8;
    return {status => $status, stdout => read_file("$fixture/stdout"), stderr => read_file("$fixture/stderr"),
        core => read_file("$fixture/xcat-core.repo"), dep => read_file("$fixture/xcat-dep.repo")};
}
sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die "$path: $!";
}
sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    return do {local $/; scalar <$fh>} || '';
}
