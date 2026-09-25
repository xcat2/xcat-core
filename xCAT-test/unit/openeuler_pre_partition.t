#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

plan skip_all => 'pre-install scripts require Linux bash' unless $^O eq 'linux' && -x '/bin/bash';
my $tmp = tempdir(CLEANUP => 1);
make_path("$tmp/db", "$tmp/bin");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$tmp/db";
require xCAT::Table;
require xCAT::Template;
%::XCATSITEVALS = (xcatdebugmode => 0, nodestatus => 0, secureroot => 1, httpport => 80, xcatiport => 3002);
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %::XCATSITEVALS) {
    $site->setAttribs({key => $key}, {value => $::XCATSITEVALS{$key}});
}
$site->close();

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die "$path: $!";
}
sub read_file {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    return <$fh> // '';
}
write_file("$tmp/bin/double", <<'SH');
#!/bin/bash
case "${0##*/}" in
    uname) printf '%s\n' "$XCAT_PART_ARCH" ;;
    blockdev) printf '%s\n' "$XCAT_PART_SECTORS" ;;
    udevadm)
        case "$*" in
            *--attribute-walk*) printf 'ATTR{size}=="%s"\nDRIVERS=="virtio_blk"\n' "$XCAT_PART_SECTORS" ;;
            *) printf 'DEVTYPE=disk\nDEVPATH=/devices/pci0000:00/virtio0/block/vda\nID_WWN=0x1234\n' ;;
        esac ;;
    *) exit 0 ;;
esac
SH
chmod 0755, "$tmp/bin/double";
for my $name (qw(uname blockdev udevadm mknod chown vgs vgchange vgremove logger python3)) {
    symlink 'double', "$tmp/bin/$name" or die $!;
}
my $small = 62914560;
my $large = 8589934592;
my @cases = (
    ['native BIOS small', 'openeuler', 'x86_64', 0, $small, 1, 0, 0, 'xfs'],
    ['native BIOS large', 'openeuler', 'x86_64', 0, $large, 1, 0, 0, 'xfs'],
    ['native UEFI small', 'openeuler', 'x86_64', 1, $small, 0, 1, 0, 'xfs'],
    ['native UEFI large', 'openeuler', 'x86_64', 1, $large, 0, 1, 0, 'xfs'],
    ['native POWER small', 'openeuler', 'ppc64le', 0, $small, 0, 0, 1, 'ext4'],
    ['native POWER large', 'openeuler', 'ppc64le', 0, $large, 0, 0, 1, 'ext4'],
    ['legacy BIOS small', 'rhels8', 'x86_64', 0, $small, 0, 0, 0, 'xfs'],
    ['legacy BIOS large', 'rhels8', 'x86_64', 0, $large, 1, 0, 0, 'xfs'],
    ['legacy UEFI small', 'rhels8', 'x86_64', 1, $small, 0, 1, 0, 'xfs'],
    ['legacy UEFI large', 'rhels8', 'x86_64', 1, $large, 1, 1, 0, 'xfs'],
    ['legacy POWER large', 'rhels8', 'ppc64le', 0, $large, 1, 0, 1, 'xfs'],
    ['legacy POWER big endian', 'rhels8', 'ppc64', 0, $small, 0, 0, 1, 'xfs'],
    ['native BIOS static custom', 'openeuler', 'x86_64', 0, $small, 0, 0, 0, 'xfs', 'static'],
    ['native BIOS script custom', 'openeuler', 'x86_64', 0, $small, 0, 0, 0, 'xfs', 'script'],
    ['native UEFI custom', 'openeuler', 'x86_64', 1, $small, 0, 0, 0, 'xfs', 'static'],
    ['native POWER custom', 'openeuler', 'ppc64le', 0, $large, 0, 0, 0, 'ext4', 'static'],
);
for my $case (@cases) {
    my ($label, $platform, $arch, $efi, $sectors, $bios, $esp, $prep, $fstype, $custom) = @$case;
    my $fixture = tempdir(DIR => $tmp, CLEANUP => 1);
    make_path(map { "$fixture/$_" } qw(tmp dev proc sys/firmware var/log/xcat etc));
    make_path("$fixture/sys/firmware/efi") if $efi;
    write_file("$fixture/proc/cmdline", "inst.ks=http://192.0.2.1/node.ks\n");
    write_file("$fixture/proc/partitions", "major minor  #blocks  name\n252 0 " . ($sectors / 2) . " vda\n");
    my $template = "$fixture/input.tmpl";
    write_file($template, "#XCAT_PARTITION_START#\n%include /tmp/partitionfile\n#XCAT_PARTITION_END#\n%pre\n#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/pre.$platform#\n%end\n");
    my $partition = '';
    my $custom_data = "part / --fstype=ext4 --ondisk=vda --size=4096\nbootloader --boot-drive=vda\n";
    if ($custom) {
        $partition = "$fixture/custom";
        if ($custom eq 'script') {
            write_file($partition, "#!/bin/bash\ncat > \"\$XCAT_PART_FIXTURE/tmp/partitionfile\" <<'EOF'\n$custom_data" . "EOF\n");
            $partition = "s:$partition";
        } else {
            write_file($partition, $custom_data);
        }
    }
    local $ENV{PERSKCMDLINE} = '';
    local $ENV{MASTER_IP} = '192.0.2.1';
    my $error = xCAT::Template->subvars($template, "$fixture/output.ks", 'node', undef,
        '/install/media', $platform eq 'openeuler' ? 'openeuler' : 'rh', $partition,
        {xcatmaster => '192.0.2.1'});
    ok(!$error, "$label renders through the production Template entry point") or diag($error);
    my $rendered = read_file("$fixture/output.ks");
    my ($pre) = $rendered =~ /^%pre[^\n]*\n(.*?)^%end/ms;
    defined($pre) or die 'rendered Kickstart did not contain a pre-install script';
    $pre =~ s{(?<![[:alnum:]_/:])(/(?:tmp|dev|proc|sys|etc|var)(?=/|\b)|/foo\.log)}{$fixture$1}g;
    $pre =~ s{/(?:usr/bin/python3|usr/libexec/platform-python)}{$tmp/bin/python3}g;
    write_file("$fixture/pre.sh", $pre);
    my ($rc, $output);
    {
        local %ENV = (%ENV, PATH => "$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin", XCAT_PART_ARCH => $arch,
            XCAT_PART_SECTORS => $sectors, XCAT_PART_FIXTURE => $fixture);
        delete @ENV{qw(XCAT_BIOSBOOT XCAT_BOOT_FSTYPE XCAT_ROOT_FSTYPE XCAT_INSTALL_PYTHON)};
        open(my $pipe, '-|', 'sh', '-c', 'exec "$@" 2>&1', 'sh', '/bin/bash', "$fixture/pre.sh") or die $!;
        $output = do {local $/; <$pipe>};
        close($pipe);
        $rc = (($? & 127) ? 128 + ($? & 127) : $? >> 8);
    }
    is($rc, 0, "$label executes the complete generated pre-install script") or diag($output);
    my $layout = read_file("$fixture/tmp/partitionfile");
    is(scalar(() = $layout =~ /^part biosboot\b/gm), $bios, "$label BIOS boot partition count");
    is(scalar(() = $layout =~ m{^part /boot/efi\b}gm), $esp, "$label EFI system partition count");
    is(scalar(() = $layout =~ /^part prepboot\b/gm), $prep, "$label PReP boot partition count");
    if ($custom) {
        $layout =~ s/\s+\z//;
        $custom_data =~ s/\s+\z//;
        is($layout, $custom_data, "$label replaces all generated defaults with the administrator's layout");
    } else {
        my $disk = "$fixture/dev/vda";
        like($layout, qr/^ignoredisk --only-use=\Q$disk\E$/m, "$label retains actual selected disk");
        like($layout, qr/^part biosboot --ondisk=\Q$disk\E --size=1$/m, "$label reserves one MiB on the selected disk") if $bios;
        like($layout, qr{^part /boot --fstype=$fstype }m, "$label retains boot filesystem policy");
        like($layout, qr{^logvol / --fstype=$fstype }m, "$label retains root filesystem policy");
        like($layout, qr/^bootloader --boot-drive=vda$/m, "$label retains selected boot drive");
        unlike($layout, qr/(?:disklabel|labeltype|--labeltype|--mbr)/, "$label does not force a disk label");
    }
}
done_testing();
