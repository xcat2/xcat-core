use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

plan skip_all => 'Linux native RPM and user namespace tools required'
    unless $^O eq 'linux' && system('sh', '-c', 'command -v rpmspec >/dev/null && command -v unshare >/dev/null') == 0;

my $root = abs_path("$RealBin/../..");
my $spec = $ENV{XCAT_GENESIS_SPEC} // "$root/xCAT-genesis-builder/xCAT-genesis-base.spec";
my $module = $ENV{XCAT_GENESIS_MODULE} // "$root/xCAT-genesis-builder/dracut_105/el/module-setup.sh";
my $tmp = tempdir(CLEANUP => 1);
my $sequence = 0;

for my $arch (qw(x86_64 ppc64le)) {
    my ($status, $requires) = query_spec($spec, $arch, 2, 0);
    is($status, 0, "$arch native spec renders successfully");
    my %requires = map { $_ => 1 } split /\n/, $requires;
    ok($requires{kernel}, "$arch native kernel provides the boot image and module tree");
    ok(!grep($requires{$_}, qw(kernel-core kernel-modules kernel-modules-extra)),
        "$arch native spec does not select EL kernel splits or unrelated module providers");
    ok($requires{tar}, "$arch explicitly requests its archive tool");
    ok($requires{openssl}, "$arch explicitly requests its TLS command");
    ok($requires{tzdata}, "$arch explicitly requests the native timezone database");
    is(!!$requires{dmidecode}, $arch eq 'x86_64' ? 1 : '', "$arch retains the correct DMI tool requirement");
    is(!!$requires{efibootmgr}, $arch eq 'x86_64' ? 1 : '', "$arch retains the correct EFI tool requirement");
    SKIP: {
        skip 'Set XCAT_GENESIS_BASE_SPEC for a committed legacy baseline', 3
            unless $ENV{XCAT_GENESIS_BASE_SPEC};
        for my $rhel (8, 9, 10) {
            my ($old_status, $old_requires) = query_spec($ENV{XCAT_GENESIS_BASE_SPEC}, $arch, 0, $rhel);
            my ($new_status, $new_requires) = query_spec($spec, $arch, 0, $rhel);
            is_deeply([$new_status, $new_requires], [$old_status, $old_requires],
                "$arch EL$rhel BuildRequires match the committed baseline");
        }
    }
}

SKIP: {
    my ($probe_status) = run('unshare', '--user', '--map-root-user', '--mount', 'true');
    skip 'Unprivileged user/mount namespaces unavailable', 13 if $probe_status;
    make_path("$tmp/native-etc", "$tmp/legacy-etc", "$tmp/zones/Etc", "$tmp/zones/Native", "$tmp/modules/fixture", "$tmp/empty-zones");
    write_file("$tmp/native-etc/openEuler-release", "openEuler release 24.03 (LTS-SP3)\n");
    write_file("$tmp/native-etc/os-release", "ID=openEuler\n");
    write_file("$tmp/legacy-etc/redhat-release", "Rocky Linux release 10\n");
    write_file("$tmp/legacy-etc/os-release", "ID=rocky\n");
    write_file("$tmp/zones/Etc/UTC", "native UTC fixture\n");
    write_file("$tmp/zones/Native/Fixture", "native timezone fixture\n");
    symlink('Etc/UTC', "$tmp/zones/UTC") or die $!;
    write_file("$tmp/modules/fixture/modules.dep", join("\n",
        'kernel/drivers/infiniband/ulp/ipoib/ib_ipoib.ko.xz:',
        'kernel/drivers/net/ethernet/intel/e1000e/e1000e.ko:',
        'kernel/drivers/infiniband/hw/mlx5/mlx5_ib.ko.zst:', ''));
    my $wrapper = "$tmp/module-trace.sh";
    write_file($wrapper, <<'SH');
mount --make-rslave / || exit
mount --bind "$2" /etc || exit
mount --bind "$3" /usr/share/zoneinfo || exit
mount --bind "$4" /lib/modules || exit
source "$1"
moddir=${1%/*}
dracut_install() { printf 'file\t%s\n' "$@"; }
inst() {
    [[ ${FAIL_TIMEZONE:-} == "$1" ]] && return 73
    printf 'file\t%s\n' "${2:-$1}"
}
find() {
    [[ ${FAIL_FIND:-0} == 1 ]] && return 74
    command find "$@"
}
inst_script() { printf 'script\t%s\n' "${1##*/}"; }
inst_dir() { printf 'directory\t%s\n' "$@"; }
inst_hook() { printf 'hook\t%s\t%s\t%s\n' "$1" "$2" "${3##*/}"; }
instmods() { printf 'module\t%s\n' "$@"; }
kernel=fixture
if [[ $5 == kernel ]]; then installkernel; else install; fi
SH
    my ($native_status, $native) = trace_module($module, "$tmp/native-etc", 'install');
    is($native_status, 0, 'native full dracut module installation requests succeed');
    like($native, qr{^file\t/etc/openEuler-release$}m, 'native release file is a mandatory install request');
    like($native, qr{^file\t/etc/os-release$}m, 'native os-release is a mandatory install request');
    unlike($native, qr{^file\t/etc/redhat-release$}m, 'native payload retains its own distribution identity');
    my @zones = sort grep { /^file\t\/usr\/share\/zoneinfo\// } split /\n/, $native;
    is_deeply(\@zones, [map { "file\t/usr/share/zoneinfo/$_" } qw(Etc/UTC Native/Fixture UTC)],
        'native payload copies every packaged timezone file and symlink');
    {
        local $ENV{FAIL_TIMEZONE} = '/usr/share/zoneinfo/Native/Fixture';
        my ($status, $output) = trace_module($module, "$tmp/native-etc", 'install');
        is($status, 73, 'a native timezone install failure fails dracut');
        unlike($output, qr{^file\t/sbin/xcatroot$}m, 'a later successful copy cannot hide a timezone failure');
    }
    {
        local $ENV{FAIL_FIND} = 1;
        my ($status, $output) = trace_module($module, "$tmp/native-etc", 'install');
        is($status, 74, 'a native timezone enumeration failure fails dracut');
        unlike($output, qr{^file\t/sbin/xcatroot$}m, 'installation stops when timezone enumeration fails');
    }
    my ($empty_status) = trace_module($module, "$tmp/native-etc", 'install', "$tmp/empty-zones");
    isnt($empty_status, 0, 'an empty native timezone database fails dracut');
    my ($kernel_status, $drivers) = trace_module($module, "$tmp/native-etc", 'kernel');
    is_deeply([$kernel_status, $drivers], [0, "module\tib_ipoib\nmodule\te1000e\nmodule\tmlx5_ib\n"],
        'the full kernel installer retains Ethernet and InfiniBand modules across compression formats');
    my ($legacy_status, $legacy) = trace_module($module, "$tmp/legacy-etc", 'install');
    is($legacy_status, 0, 'legacy full module installation requests succeed');
    SKIP: {
        skip 'Set XCAT_GENESIS_BASE_MODULE for a committed legacy baseline', 1
            unless $ENV{XCAT_GENESIS_BASE_MODULE};
        my ($old_status, $old) = trace_module($ENV{XCAT_GENESIS_BASE_MODULE}, "$tmp/legacy-etc", 'install');
        my @old_requests = sort split /\n/, $old;
        my @new_requests = sort split /\n/, $legacy;
        is_deeply([$legacy_status, \@new_requests], [$old_status, \@old_requests],
            'all legacy install requests match the committed module baseline');
    }

    sub trace_module {
        my ($path, $etc, $mode, $zones) = @_;
        return run('unshare', '--user', '--map-root-user', '--mount', 'bash',
            "$tmp/module-trace.sh", $path, $etc, $zones // "$tmp/zones", "$tmp/modules", $mode);
    }
}

done_testing();

sub query_spec {
    my ($path, $arch, $native, $rhel) = @_;
    return run('rpmspec', '-q', '--buildrequires', '--target', $arch,
        '--define', 'version 2.19.0', '--define', 'release oevalidation',
        '--define', "openEuler $native", '--define', "rhel $rhel", $path);
}

sub run {
    my @command = @_;
    my $log = "$tmp/command-" . ++$sequence;
    my $pid = fork();
    die $! unless defined($pid);
    if (!$pid) {
        open(STDOUT, '>', $log) or die $!;
        open(STDERR, '>', "$log.stderr") or die $!;
        exec(@command) or die $!;
    }
    waitpid($pid, 0);
    my $status = $? >> 8;
    open(my $fh, '<', $log) or die $!;
    my $output = do { local $/; <$fh> } // '';
    close($fh);
    return ($status, $output);
}

sub write_file {
    my ($path, $text) = @_;
    open(my $fh, '>', $path) or die $!;
    print {$fh} $text;
    close($fh) or die $!;
}
