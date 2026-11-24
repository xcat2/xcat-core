#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Slurper qw(read_binary);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::ImageSandbox;

plan skip_all => 'Linux namespaces require Linux' unless $^O eq 'linux';
die('Run the image caller tests as an unprivileged user') unless $>;

for my $case ([rh => '033'], [rh => '047'], [rh => '105'], [sles => '033'], [ubuntu => '059']) {
    my ($family, $version) = @$case;
    subtest "$family dracut $version" => sub {
        my $box = XCAT::Test::ImageSandbox->new();
        my $image = 'work/image/rootimg';
        make_path(map { "$box->{root}/$image/$_" }
            qw(bin dev run tmp boot etc lib/modules/fixture usr/lib/dracut/modules.d));
        $box->write('etc/os-release', "ID=sles\nVERSION=\"15\"\n");
        $box->write('etc/lsb-release', "DISTRIB_ID=Ubuntu\nDISTRIB_RELEASE=24.04\n");
        $box->write("$image/boot/vmlinuz-fixture", "kernel\n");
        $box->write("$image/lib/modules/fixture/$_", '') for qw(modules.dep modules.builtin);
        $box->write('install/postscripts/updateflag.awk', '');
        $box->write('work/dracut-version', "Version : $version\n");
        $box->command('rpm', <<'SH');
case "$*" in
    --version) echo 'RPM version 4.18.2' ;;
    '--root /work/image/rootimg -qi dracut') cat /work/dracut-version ;;
    *) echo "Unexpected rpm: $*" >&2; exit 97 ;;
esac
SH
        $box->command('chroot', <<'SH');
root=$1
shift
case "$*" in
    'rpm --version') echo 'RPM version 4.18.2' ;;
    'rpm -qi dracut') cat /work/dracut-version ;;
    'dpkg-query -W dracut') echo 'dracut 059' ;;
    'bash -c type -p pigz') exit 1 ;;
    'depmod fixture') : ;;
    dracut\ *)
        index=1
        while [ -d "/work/staged-$index" ]; do index=$((index + 1)); done
        cp -a "$root/usr/lib/dracut/modules.d" "/work/staged-$index" || exit
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '-f' ]; then shift; echo initrd >"$root$1"; break; fi
            shift
        done ;;
    *) echo "Unexpected chroot: $*" >&2; exit 97 ;;
esac
SH
        $box->command('mount', <<'SH');
case "$*" in
    'proc /work/image/rootimg/proc -t proc'|'sysfs /work/image/rootimg/sys -t sysfs'|'--bind /run /work/image/rootimg/run') : ;;
    *) echo "Unexpected mount: $*" >&2; exit 97 ;;
esac
SH
        $box->command('umount', "exit 0\n");
        my $os = $family eq 'rh' ? 'rhels10.1' : $family eq 'sles' ? 'sles15.6' : 'ubuntu24.04';
        my @args = ('--onlyinitrd', '-a', 'x86_64', '-o', $os, '-p', 'compute',
            '-k', 'fixture', '-i', 'eth0', '--rootimgdir', '/work/image');
        push @args, '-g', 'fixture' if $family eq 'sles';
        my ($rc, $out, $err) = $box->run('perl', "/repo/xCAT-server/share/xcat/netboot/$family/genimage",
            @args, 'fixture-image');
        is($rc, 0, 'complete genimage caller succeeds') or diag($out, $err);
        my $module = $family eq 'rh' ? '98xcat' : '97xcat';
        my $stateless = $family eq 'ubuntu' ? 2 : 1;
        for my $index (1, 2) {
            my $path = "$box->{root}/work/staged-$index/$module";
            ok(-d $path, 'dracut receives the generated module');
            for my $name (qw(xcat-rootimg-checksum.sh xcat-rootimg-install.sh)) {
                if ($index == $stateless || $family eq 'sles') {
                    ok(-f "$path/$name", "dracut module retains $name without a UFTP receiver");
                    is(scalar(read_binary("$path/$name")),
                        scalar(read_binary(repo_path("xCAT-server/share/xcat/netboot/imgutils/$name"))),
                        'the delivered helper matches the packaged asset') if -f "$path/$name";
                } else {
                    ok(!-e "$path/$name", "statelite dracut receives no $name");
                }
            }
            ok(!-e "$path/xcat-rootimg-fetch.sh", 'an image without a receiver gets no UFTP fetch helper');
        }
        if ($family eq 'sles') {
            make_path("$box->{root}/work/xcat/lib/perl", "$box->{root}/work/xcat/share");
            symlink('/repo/perl-xCAT/xCAT', "$box->{root}/work/xcat/lib/perl/xCAT") or die $!;
            symlink('/repo/xCAT-server/share/xcat', "$box->{root}/work/xcat/share/xcat") or die $!;
            $box->write('install/postscripts/xcatdsklspost', "#!/bin/sh\nexit 0\n");
            $box->write("$image/etc/shadow", "root:*:1:0:99999:7:::\n");
            $box->write('work/pack.pl', <<'PERL');
use strict;
use warnings;
use xCAT::Table;
require '/repo/xCAT-server/lib/xcat/plugins/packimage.pm';
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'installdir' }, { value => '/install' });
xCAT::Table->new('passwd', -create => 1)->setAttribs(
    { key => 'system', username => 'root' }, { password => '*', cryptmethod => 'sha512' });
xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => 'fixture-image' },
    { osvers => 'sles15.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' });
xCAT::Table->new('linuximage', -create => 1)->setAttribs(
    { imagename => 'fixture-image' }, { rootimgdir => '/work/image' });
my @errors;
xCAT_plugin::packimage::process_request(
    { arg => ['--nosyncfiles', '-m', 'cpio', '-c', 'gzip', 'fixture-image'] },
    sub { push @errors, @{ $_[0]{error} || [] } });
die join("\n", @errors) if @errors;
PERL
            ($rc, $out, $err) = $box->run('env', 'XCATROOT=/work/xcat', 'perl', '/work/pack.pl');
            is($rc, 0, 'packimage packs the SLES root left by genimage') or diag($out, $err);
            ($rc, $out, $err) = $box->run('bash', '-o', 'pipefail', '-c', <<'SH');
mkdir -p /work/unpacked /work/initrd
cd /work/unpacked || exit
gzip -dc /work/image/rootimg.cpio.gz | cpio -id --quiet || exit
moddir=/work/unpacked/usr/lib/dracut/modules.d/97xcat
inst() { mkdir -p "/work/initrd$(dirname "$2")" && cp "$1" "/work/initrd$2"; }
inst_hook() { :; }
dracut_install() { :; }
. "$moddir/install"
SH
            is($rc, 0, 'the restored stateless hook runs from the packed SLES root') or diag($out, $err);
            my $checksum = "$box->{root}/work/initrd/lib/xcat-rootimg-checksum.sh";
            ok(-f $checksum, 'the restored hook delivers the checksum helper for a later dracut build');
            is(scalar(read_binary($checksum)),
                scalar(read_binary(repo_path('xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-checksum.sh'))),
                'the later build receives the packaged checksum helper') if -f $checksum;
        }
    };
}
done_testing();
