use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($RealBin);
use Test::More;

plan skip_all => 'requires native openEuler, an unprivileged user, rpmbuild and user namespaces'
    unless $^O eq 'linux' && $> && -f '/etc/openEuler-release'
    && -d '/usr/lib/dracut' && system('sh', '-c', 'command -v rpmbuild >/dev/null && unshare -Ur -m true') == 0;

my $root = abs_path("$RealBin/../..");
my $spec = $ENV{XCAT_GENESIS_RELEASE_SPEC} // "$root/xCAT-genesis-builder/xCAT-genesis-base.spec";
my $tmp = tempdir(CLEANUP => 1);
my $support = "$tmp/build/xCAT-genesis-base-build-support";
make_path("$support/dracut_105/el", "$tmp/bin");
find({ no_chdir => 1, wanted => sub {
    return unless -f $_;
    my $relative = substr($_, length("$root/xCAT-genesis-builder/dracut_105/el/"));
    my $target = "$support/dracut_105/el/$relative";
    make_path(dirname($target));
    copy($_, $target) or die "copy $_: $!";
} }, "$root/xCAT-genesis-builder/dracut_105/el");
copy("$root/xCAT-genesis-builder/80-net-name-slot.rules", "$support/80-net-name-slot.rules") or die $!;
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
cp /etc/openEuler-release "$tree/etc/"
case "$GENESIS_RELEASE_FAILURE" in
    ID|VERSION_ID) sed "/^${GENESIS_RELEASE_FAILURE}=/d" /etc/os-release > "$tree/etc/os-release" ;;
    none) cp /etc/os-release "$tree/etc/os-release" ;;
esac
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
for directory in /usr/share/perl5 /usr/lib64/perl5 /usr/local/lib64/perl5 /usr/local/share/perl5 /usr/share/ntp/lib; do
    if [[ -d $directory ]]; then
        mount --bind "$GENESIS_RELEASE_CASE/empty" "$directory"
    fi
done
exec rpmbuild -bi --short-circuit --nodeps --target x86_64 \
    --define 'version 2.19.0' --define 'release oereleasetest' \
    --define "_topdir $GENESIS_RELEASE_CASE/rpm" \
    --define "_builddir $GENESIS_RELEASE_BUILD" \
    "$GENESIS_RELEASE_SPEC"
SH

for my $failure (qw(none ID VERSION_ID)) {
    my $case = "$tmp/$failure";
    make_path("$case/dracut/modules.d", "$case/run", "$case/rpm", "$case/empty");
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
    if ($failure eq 'none') {
        is($status, 0, 'complete native spec install accepts both release identity fields') or diag($text);
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
