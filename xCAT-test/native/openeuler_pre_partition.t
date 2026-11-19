#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'pre-install scripts require Linux namespaces' unless $^O eq 'linux';
my $database = template_database();
set_row('site', {key => 'nodestatus'}, {value => 0});

sub installer_root {
    my ($efi, $sectors) = @_;
    my $root = sandbox_root();
    make_path("$root/proc", "$root/firmware", "$root/libexec", "$root/log/xcat");
    make_path("$root/firmware/efi") if $efi;
    write_text("$root/proc/cmdline", "inst.ks=http://192.0.2.1/node.ks\n");
    write_text("$root/proc/partitions", "major minor  #blocks  name\n252 0 " . ($sectors / 2) . " vda\n");
    write_text("$root/libexec/platform-python", '#!/bin/sh' . "\n" . 'exec /usr/bin/python3 "$@"' . "\n");
    chmod 0755, "$root/libexec/platform-python" or die $!;
    write_text("$root/bin/double", <<'SH');
#!/bin/bash
case "${0##*/}" in
    uname) printf '%s\n' "$XCAT_PART_ARCH" ;;
    blockdev) printf '%s\n' "$XCAT_PART_SECTORS" ;;
    udevadm)
        case "$*" in
            *--attribute-walk*) printf 'ATTR{size}=="%s"\nDRIVERS=="virtio_blk"\n' "$XCAT_PART_SECTORS" ;;
            *) printf 'DEVTYPE=disk\nDEVPATH=/devices/pci0000:00/virtio0/block/vda\nID_WWN=0x1234\n' ;;
        esac ;;
    mknod) : >"$1" ;;
    *) exit 0 ;;
esac
SH
    chmod 0755, "$root/bin/double" or die $!;
    for my $name (qw(uname blockdev udevadm mknod chown vgs vgchange vgremove logger)) {
        symlink 'double', "$root/bin/$name" or die $!;
    }
    return $root;
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
my $sequence = 0;
for my $case (@cases) {
    my ($label, $platform, $arch, $efi, $sectors, $bios, $esp, $prep, $fstype, $custom) = @$case;
    my $fixture = installer_root($efi, $sectors);
    my $render = "$database/case-" . ++$sequence;
    make_path($render);
    my $template = "$render/input.tmpl";
    write_text($template, "#XCAT_PARTITION_START#\n%include /tmp/partitionfile\n#XCAT_PARTITION_END#\n%pre\n#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/pre.$platform#\n%end\n");
    my $partition = '';
    my $custom_data = "part / --fstype=ext4 --ondisk=vda --size=4096\nbootloader --boot-drive=vda\n";
    if ($custom) {
        $partition = "$render/custom";
        if ($custom eq 'script') {
            write_text($partition, "#!/bin/bash\ncat > /tmp/partitionfile <<'EOF'\n$custom_data" . "EOF\n");
            $partition = "s:$partition";
        } else {
            write_text($partition, $custom_data);
        }
    }
    render_template($database, $template, "$render/output.ks", 'node', undef,
        '/install/media', $platform eq 'openeuler' ? 'openeuler' : 'rh', $partition,
        {xcatmaster => '192.0.2.1'});
    my $rendered = read_text("$render/output.ks");
    my ($pre) = $rendered =~ /^%pre[^\n]*\n(.*?)^%end/ms;
    ok(defined $pre, "$label renders a Kickstart pre-install script") or die 'missing %pre block';
    write_text("$fixture/pre.sh", $pre);
    my ($rc, $output) = sandbox_run($fixture, {
        read_only => {"$fixture/proc/cmdline" => '/proc/cmdline', "$fixture/proc/partitions" => '/proc/partitions',
            "$fixture/firmware" => '/sys/firmware', "$fixture/libexec" => '/usr/libexec'},
        env => {XCAT_PART_ARCH => $arch, XCAT_PART_SECTORS => $sectors},
    }, '/bin/bash', '/fixture/pre.sh');
    is($rc, 0, "$label executes the complete generated pre-install script") or diag($output);
    my $layout = -f "$fixture/tmp/partitionfile" ? read_text("$fixture/tmp/partitionfile") : '';
    is(scalar(() = $layout =~ /^part biosboot\b/gm), $bios, "$label BIOS boot partition count");
    is(scalar(() = $layout =~ m{^part /boot/efi\b}gm), $esp, "$label EFI system partition count");
    is(scalar(() = $layout =~ /^part prepboot\b/gm), $prep, "$label PReP boot partition count");
    if ($custom) {
        $layout =~ s/\s+\z//;
        $custom_data =~ s/\s+\z//;
        is($layout, $custom_data, "$label replaces all generated defaults with the administrator's layout");
    } else {
        my $disk = '/dev/vda';
        like($layout, qr/^ignoredisk --only-use=\Q$disk\E$/m, "$label retains actual selected disk");
        like($layout, qr/^part biosboot --ondisk=\Q$disk\E --size=1$/m, "$label reserves one MiB on the selected disk") if $bios;
        like($layout, qr{^part /boot --fstype=$fstype }m, "$label retains boot filesystem policy");
        like($layout, qr{^logvol / --fstype=$fstype }m, "$label retains root filesystem policy");
        like($layout, qr/^bootloader --boot-drive=vda$/m, "$label retains selected boot drive");
        unlike($layout, qr/(?:disklabel|labeltype|--labeltype|--mbr)/, "$label does not force a disk label");
    }
}
done_testing();
