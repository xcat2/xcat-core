#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use Test::More;
use XCAT::Test::ImageSandbox;

plan skip_all => 'Linux namespaces require Linux' unless $^O eq 'linux';
BAIL_OUT('Run the image caller tests as an unprivileged user') unless $>;

for my $family (qw(rh sles ubuntu)) {
    for my $mode (qw(inbox update explicit)) {
        subtest "$family $mode" => sub {
            my $box = XCAT::Test::ImageSandbox->new();
            my $image = 'work/image/rootimg';
            make_path(map { "$box->{root}/$image/$_" }
                qw(bin dev run tmp boot etc lib/modules/fixture usr/lib/dracut/modules.d));
            $box->write('etc/os-release', "ID=sles\nVERSION=\"15\"\n");
            $box->write('etc/lsb-release', "DISTRIB_ID=Ubuntu\nDISTRIB_RELEASE=24.04\n");
            $box->write("$image/boot/vmlinuz-fixture", "kernel\n");
            $box->write("$image/lib/modules/fixture/$_", '') for qw(modules.dep modules.builtin);
            $box->write('install/postscripts/updateflag.awk', '');
            $box->write("$image/lib/modules/fixture/kernel/mlx5_core.ko", 'inbox module') if $mode ne 'update';
            $box->command('rpm', <<'SH');
case "$*" in
    --version) printf 'RPM version 4.18.2\n' ;;
    '--root /work/image/rootimg -qi dracut') printf 'Version : 059\n' ;;
    *) echo "Unexpected rpm: $*" >&2; exit 97 ;;
esac
SH
            $box->command('chroot', <<'SH');
root=$1
shift
case "$*" in
    'rpm --version') printf 'RPM version 4.18.2\n' ;;
    'rpm -qi dracut') printf 'Version : 059\n' ;;
    'dpkg-query -W dracut') printf 'dracut 059\n' ;;
    'bash -c type -p pigz') exit 1 ;;
    'depmod fixture') : ;;
    dracut\ *)
        cp "$root/etc/dracut.conf" /work/dracut.conf
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '-f' ]; then shift; printf 'initrd\n' >"$root$1"; break; fi
            shift
        done ;;
    *) echo "Unexpected chroot: $*" >&2; exit 97 ;;
esac
SH
            $box->command('mount', <<'SH');
case "$*" in
    'proc /work/image/rootimg/proc -t proc'|'sysfs /work/image/rootimg/sys -t sysfs'|'--bind /run /work/image/rootimg/run') : ;;
    '-o loop '* )
        for destination; do :; done
        cp -a /work/disk/. "$destination/" ;;
    *) echo "Unexpected mount: $*" >&2; exit 97 ;;
esac
SH
            $box->command('umount', "exit 0\n");
            my $os = $family eq 'rh' ? 'rhels10.1' : $family eq 'sles' ? 'sles15.6' : 'ubuntu24.04';
            if ($mode eq 'update') {
                $box->write("install/driverdisk/$os/x86_64/update.img", 'disk fixture');
                if ($family eq 'sles') {
                    $box->write('work/disk/linux/suse/x86_64-sles15.6/modules/mlx4_en.ko', 'updated module');
                } else {
                    $box->write('work/disk/modinfo', "Version 0\nmlx4_en\n");
                    $box->write('work/archive/fixture/x86_64/mlx4_en.ko', 'updated module');
                    my ($rc, $output, $error) = $box->run('sh', '-c',
                        'cd /work/archive && find . | cpio -o -H newc | gzip > /work/disk/modules.cgz');
                    is($rc, 0, 'driver archive is built') or diag($output, $error);
                }
            }
            my @args = ('--onlyinitrd', '-a', 'x86_64', '-o', $os, '-p', 'compute',
                '-k', 'fixture', '-i', 'eth0', '--rootimgdir', '/work/image');
            push @args, '-g', 'fixture' if $family eq 'sles';
            push @args, '-n', ($mode eq 'update' ? 'mlx_en' : 'custom_driver') if $mode ne 'inbox';
            my ($rc, $output, $error) = $box->run('perl', "/repo/xCAT-server/share/xcat/netboot/$family/genimage",
                @args, 'fixture-image');
            is($rc, 0, 'complete genimage caller succeeds') or diag($output, $error);
            unlike($error, qr/Unexpected (?:rpm|chroot|mount):/, 'all command fixtures accept the caller requests');
            my $config = -f "$box->{root}/work/dracut.conf" ? $box->read('work/dracut.conf') : '';
            my ($drivers) = $config =~ /^add_drivers\+="(.*)"$/m;
            ok(defined $drivers, 'dracut receives the generated driver configuration');
            my @mlx = grep { /^mlx/ } split /\s+/, $drivers || '';
            my @expected = $mode eq 'update' ? ('mlx4_en')
                : $family eq 'ubuntu' && $mode eq 'explicit' ? () : ('mlx5_core');
            is_deeply(\@mlx, \@expected,
                'only target-kernel Mellanox drivers reach dracut');
            like($drivers || '', qr/\bcustom_driver\b/, 'explicit requests are preserved') if $mode eq 'explicit';
            is($box->read("$image/lib/modules/fixture/kernel/drivers/driverdisk/mlx4_en.ko"),
                'updated module', 'real driver-disk loading copies the module') if $mode eq 'update';
        };
    }
}
done_testing();
