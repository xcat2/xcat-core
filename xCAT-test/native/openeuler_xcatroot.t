#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

plan skip_all => 'requires Linux root and private mount namespaces'
  unless $^O eq 'linux' && $> == 0
  && system('unshare', '--mount', '--propagation', 'private', '/bin/true') == 0;
my $netboot = File::Spec->rel2abs("$FindBin::Bin/../../xCAT-server/share/xcat/netboot/rh");
my $dir = tempdir(CLEANUP => 1);
my $wrapper = "$dir/run";
write_file($wrapper, <<'SH');
#!/bin/bash
set -e
root=$1
mount --bind /usr "$root/usr"
mount -o remount,bind,ro "$root/usr"
exec chroot "$root" /bin/bash -c '
    cd /
    /bin/bash /xcatroot eth0 none /sysroot
    rc=$?
    printf "XCATROOT_RC=%s\n" "$rc"
    printf "PAYLOAD="; cat /sysroot/native-marker
    if [ -f /sysroot/localdisk-ran ]; then echo LOCALDISK_RAN; fi
    if [ -f /hooks/initqueue/xcat.sh ]; then echo INITQUEUE_READY; fi
    exit "$rc"
'
SH
chmod 0755, $wrapper;

for my $variant (qw(dracut_047 dracut_105/stateless dracut_105/statelite)) {
    my $source = "$netboot/$variant/xcatroot";
    for my $method (qw(cpio tar)) {
        for my $localdisk (qw(missing executable nonexecutable)) {
            my $case = tempdir(DIR => $dir, CLEANUP => 1);
            my $root = "$case/root";
            my $payload = "$case/payload";
            make_path(map { "$root/$_" } qw(usr lib etc tmp sysroot hooks/initqueue));
            symlink('usr/bin', "$root/bin") or die $!;
            symlink('usr/sbin', "$root/sbin") or die $!;
            symlink('usr/lib64', "$root/lib64") or die $!;
            make_path("$payload/etc/init.d", "$payload/etc/sysconfig/network-scripts", "$payload/var/lib/dhclient");
            write_file("$payload/native-marker", "native payload\n");
            write_file("$payload/etc/os-release", "ID=openEuler\nVERSION_ID=24.03\n");
            if ($localdisk ne 'missing') {
                write_file("$payload/etc/init.d/localdisk", "#!/bin/sh\ntouch /sysroot/localdisk-ran\n");
                chmod($localdisk eq 'executable' ? 0755 : 0644, "$payload/etc/init.d/localdisk");
            }
            write_file("$root/etc/resolv.conf", "nameserver 192.0.2.1\n");
            write_file("$root/tmp/dhclient.eth0.lease", "fixture lease\n");
            write_file("$root/lib/dracut-lib.sh", <<'SH');
hookdir=/hooks
logger() { :; }
getarg()
{
    case "$1" in
        XCAT=) echo 192.0.2.1:3001 ;;
        XCATIPORT=) echo 3002 ;;
        rootlimit=) echo 8M ;;
        xcatdebugmode=) echo 0 ;;
        ifname=) echo eth0:52:54:00:00:00:01 ;;
        nonodestatus) return 0 ;;
        *) return 1 ;;
    esac
}
SH
            copy($source, "$root/xcatroot") or die $!;
            my $archive = "$root/rootimg.$method.gz";
            my @pack = $method eq 'cpio'
              ? ('/bin/bash', '-o', 'pipefail', '-c', 'cd "$1" && find . -print0 | cpio -0 -o -H newc | gzip > "$2"', 'pack', $payload, $archive)
              : ('tar', '-C', $payload, '-czf', $archive, '.');
            is(system(@pack), 0, "$method $localdisk fixture archive is valid");
            my $pid = fork();
            die "fork: $!" unless defined($pid);
            if (!$pid) {
                open(STDOUT, '>', "$case/output") or die $!;
                open(STDERR, '>&', STDOUT) or die $!;
                exec 'unshare', '--mount', '--propagation', 'private', $wrapper, $root;
                die "exec: $!";
            }
            waitpid($pid, 0);
            my $rc = (($? & 127) ? 128 + ($? & 127) : $? >> 8);
            open(my $file, '<', "$case/output") or die $!;
            my $output = do { local $/; <$file> };
            close($file);
            my $label = "$variant $method $localdisk localdisk";
            is($rc, 0, "$label completes the production xcatroot script") or diag($output);
            like($output, qr/^PAYLOAD=native payload$/m, "$label extracts the actual image payload");
            like($output, qr/^INITQUEUE_READY$/m, "$label reaches the initqueue handoff");
            unlike($output, qr{localdisk: (?:No such file|Permission denied)}, "$label avoids an invalid optional script invocation");
            if ($localdisk eq 'executable') {
                like($output, qr/^LOCALDISK_RAN$/m, "$label retains the legacy executable hook");
            } else {
                unlike($output, qr/^LOCALDISK_RAN$/m, "$label does not execute a missing or disabled hook");
            }
        }
    }
}
done_testing();

sub write_file {
    my ($path, $contents) = @_;
    open(my $file, '>', $path) or die "write $path: $!";
    print {$file} $contents or die $!;
    close($file) or die $!;
}
