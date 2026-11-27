use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use lib "$RealBin/../../build-utils/lib";
use XCAT::BuildUtils qw(stage_genesis_base_sources);
use Test::More;

plan skip_all => 'requires native openEuler, an unprivileged user, rpmbuild and user namespaces'
    unless $^O eq 'linux' && $> && -f '/etc/openEuler-release'
    && -d '/usr/lib/dracut' && system('sh', '-c', 'command -v rpmbuild >/dev/null && unshare -Ur -m true') == 0;

local $ENV{PATH} = "$ENV{PATH}:/usr/sbin:/sbin";
my $root = abs_path("$RealBin/../..");
my $spec = $ENV{XCAT_GENESIS_RELEASE_SPEC} // "$root/xCAT-genesis-base/xCAT-genesis-base.spec";
my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/build", "$tmp/bin");
stage_genesis_base_sources($root, "$tmp/support.tar.bz2", 1700000000);
system('tar', '-xjf', "$tmp/support.tar.bz2", '-C', "$tmp/build") == 0
    or die "extract Genesis build support: $?";
write_file("$tmp/bin/dracut", <<'SH');
#!/bin/bash
set -eu
while (($#)); do
    if [[ $1 == -f ]]; then
        shift
        image=$1
    fi
    kernel=$1
    shift
done
tree="$GENESIS_RELEASE_CASE/initrd"
mkdir -p "$tree/etc" "$tree/lib/modules/$kernel/kernel" "$tree/usr/share/zoneinfo" "$tree/usr/lib/dracut/hooks"
dracut_install() {
    local item destination
    for item in "$@"; do
        case "$item" in
            /*) destination=$item ;;
            sshd|dhclient|dhcpcd) destination=/usr/sbin/$item ;;
            *) destination=/usr/bin/$item ;;
        esac
        mkdir -p "$(dirname "$tree$destination")" || exit
        if [[ -d "$item" ]]; then
            mkdir -p "$tree$destination" || exit
        elif [[ $item == /usr/bin/awk ]]; then
            cp -L "$item" "$tree$destination" || exit
        else
            printf 'fixture\n' > "$tree$destination" || exit
        fi
    done
}
inst() { :; }
inst_script() { :; }
inst_dir() { :; }
inst_hook() { :; }
openssl() {
    [[ $* == 'version -d' ]] || return 99
    printf 'OPENSSLDIR: "%s"\n' "$GENESIS_RELEASE_BUILD/ssl"
}
(
    set +eu
    moddir="$GENESIS_RELEASE_BUILD/xCAT-genesis-base-build-support/dracut_105/el"
    source "$moddir/module-setup.sh"
    install
)
mkdir -p "$tree/usr/lib/locale/C.utf8"
printf 'fixture\n' > "$tree/usr/lib/locale/C.utf8/LC_CTYPE"
if [[ -f /etc/openEuler-release ]]; then
    cp /etc/openEuler-release "$tree/etc/"
fi
case "$GENESIS_RELEASE_FAILURE" in
    ID|VERSION_ID) sed "/^${GENESIS_RELEASE_FAILURE}=/d" /etc/os-release > "$tree/etc/os-release" ;;
    *) cp /etc/os-release "$tree/etc/os-release" ;;
esac
if [[ $GENESIS_RELEASE_FAILURE == mktemp ]]; then
    rm "$tree/usr/bin/mktemp"
elif [[ $GENESIS_RELEASE_FAILURE == dhclient ]]; then
    rm "$tree/usr/sbin/dhclient"
elif [[ $GENESIS_RELEASE_FAILURE == legacy-zone ]]; then
    rm "$tree/usr/share/zoneinfo/posix/UTC"
elif [[ $GENESIS_RELEASE_FAILURE == legacy-release ]]; then
    rm "$tree/etc/redhat-release"
fi
printf 'kernel/fixture.ko:\n' > "$tree/lib/modules/$kernel/modules.dep"
printf 'fixture\n' > "$tree/lib/modules/$kernel/kernel/fixture.ko"
cp -L /usr/share/zoneinfo/UTC "$tree/usr/share/zoneinfo/UTC"
(cd "$tree" && find . -print0 | cpio --null -o -H newc | gzip > "$image")
SH
chmod 0755, "$tmp/bin/dracut" or die $!;
write_file("$tmp/run.sh", <<'SH');
set -eu
mount --make-rslave /
mount --bind "$GENESIS_RELEASE_CASE/dracut" /usr/lib/dracut
if [[ -d /usr/share/dracut ]]; then
    mount --bind "$GENESIS_RELEASE_CASE/dracut" /usr/share/dracut
fi
mount --bind "$GENESIS_RELEASE_CASE/run" /run
# Private Perl libraries let the verifier run and RPM preserve ownership in the namespace.
for directory in /usr/share/perl5 /usr/lib64/perl5 /usr/local/lib64/perl5 /usr/local/share/perl5 /usr/share/ntp/lib; do
    if [[ -d $directory ]]; then
        runtime="$GENESIS_RELEASE_CASE/runtime$directory"
        mkdir -p "$runtime"
        cp -R "$directory/." "$runtime/"
        mount --bind "$runtime" "$directory"
    fi
done
platform=()
if [[ $GENESIS_RELEASE_FAILURE == legacy-* ]]; then
    mount --bind "$GENESIS_RELEASE_CASE/etc" /etc
    platform=(--define 'openEuler 0' --define 'rhel 9')
fi
exec rpmbuild -bi --short-circuit --nodeps --target x86_64 \
    --define 'version 2.19.0' --define 'release oereleasetest' \
    --define "_topdir $GENESIS_RELEASE_CASE/rpm" \
    --define "_builddir $GENESIS_RELEASE_BUILD" \
    "${platform[@]}" \
    "$GENESIS_RELEASE_SPEC"
SH

make_path("$tmp/build/ssl");
write_file("$tmp/build/ssl/openssl.cnf", '');

for my $failure (qw(none ID VERSION_ID mktemp dhclient legacy-none legacy-zone legacy-release)) {
    my $case = "$tmp/$failure";
    make_path("$case/dracut/modules.d", "$case/run", "$case/rpm");
    if ($failure =~ /^legacy-/) {
        make_path("$case/etc/ssh");
        write_file("$case/etc/os-release", "ID=rocky\nVERSION_ID=9.6\n");
        write_file("$case/etc/redhat-release", "Rocky Linux release 9.6\n");
        write_file("$case/etc/passwd", "root:x:0:0:root:/root:/bin/bash\n");
        write_file("$case/etc/group", "root:x:0:\n");
        write_file("$case/etc/nsswitch.conf", "passwd: files\ngroup: files\n");
    }
    local %ENV = %ENV;
    @ENV{qw(GENESIS_RELEASE_CASE GENESIS_RELEASE_FAILURE GENESIS_RELEASE_BUILD GENESIS_RELEASE_SPEC)} =
        ($case, $failure, "$tmp/build", $spec);
    $ENV{PATH} = "$tmp/bin:$ENV{PATH}";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if (!$pid) {
        open(STDOUT, '>', "$case/output") or die $!;
        open(STDERR, '>&', STDOUT) or die $!;
        exec 'unshare', '--user', '--map-root-user', '--mount', 'bash', "$tmp/run.sh";
        die "exec: $!";
    }
    waitpid($pid, 0);
    my $status = $?;
    open(my $output, '<', "$case/output") or die $!;
    my $text = do { local $/; <$output> };
    close($output) or die $!;
    if ($failure eq 'legacy-none') {
        is($status, 0, 'complete EL spec install accepts its legacy payload') or diag($text);
        like($text, qr/verify-genesis-payload: .* is complete/,
            'complete EL payload passes the real verifier');
    } elsif ($failure =~ /^legacy-/) {
        my $missing = $failure eq 'legacy-zone' ? 'usr/share/zoneinfo/posix/UTC' : 'etc/redhat-release';
        isnt($status, 0, "EL spec install rejects missing $missing") or diag($text);
        like($text, qr/\Q$missing\E \(required by the build\)/,
            'EL payload rejection identifies its missing requirement') or diag($text);
    } elsif ($failure eq 'none') {
        is($status, 0, 'complete native spec install accepts both release identity fields') or diag($text);
        like($text, qr/verify-genesis-payload: .* is complete/,
            'native payload passes the verifier without legacy timezone paths');
    } elsif ($failure eq 'mktemp') {
        isnt($status, 0, 'native spec install rejects a missing payload command') or diag($text);
        like($text, qr/usr\/bin\/mktemp \(getdestiny makes its request file with it\)/,
            'payload rejection identifies the missing command') or diag($text);
    } elsif ($failure eq 'dhclient') {
        isnt($status, 0, 'native spec install rejects a missing DHCP client') or diag($text);
        like($text, qr/usr\/sbin\/dhclient \(required by the build\)/,
            'payload rejection identifies the native DHCP client') or diag($text);
    } else {
        isnt($status, 0, "complete native spec install rejects missing $failure") or diag($text);
        like($text, qr/\Q$failure\E: unbound variable/, "$failure cannot inherit its value from the build host") or diag($text);
    }
}

done_testing();

sub write_file {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or die "write $path: $!";
    print {$file} $text or die $!;
    close($file) or die $!;
}
