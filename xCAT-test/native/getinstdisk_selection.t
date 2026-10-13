#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'disk selection requires Linux namespaces' unless $^O eq 'linux';
die('run as root to create isolated dummy block devices') if $>;
my $script = repo_path('xCAT-server/share/xcat/install/scripts/getinstdisk');
die("missing disk selector: $script") unless -r $script;
my $database;

sub selects {
    my ($expected, $name, $disks, %options) = @_;
    subtest $name => sub {
        my $root = sandbox_root();
        make_path("$root/props", "$root/dev/md");
        my $partitions = "major minor  #blocks  name\n\n";
        my $minor = 0;
        for my $disk (sort keys %$disks) {
            my $attr = $disks->{$disk};
            $partitions .= sprintf "   8 %5d 524288000 %s\n", $minor++, $disk;
            my $properties = "DEVTYPE=disk\n";
            $properties .= "ID_WWN=$attr->{wwn}\n" if $attr->{wwn};
            $properties .= "DEVPATH=$attr->{path}\n" if $attr->{path};
            write_binary("$root/props/$disk.props", $properties);
            my $size = $attr->{size} // 1024000000;
            my $attributes = qq{    ATTRS{size}=="$size"\n};
            $attributes .= qq{    DRIVERS=="$attr->{driver}"\n} if $attr->{driver};
            write_binary("$root/props/$disk.attrs", $attributes);
        }
        write_binary("$root/partitions", $partitions);
        write_binary("$root/bin/udevadm", <<'SH');
#!/bin/sh
name=
query=
while [ "$#" -gt 0 ]; do
    case "$1" in
        info) shift ;;
        --name=*) name=${1#--name=}; shift ;;
        --name|-n) name=$2; shift 2 ;;
        --query=*) query=${1#--query=}; shift ;;
        --query|-q) query=$2; shift 2 ;;
        --attribute-walk|-a) query=attributes; shift ;;
        *) exit 97 ;;
    esac
done
name=${name#/dev/}
case "$query" in
    property) cat "/fixture/props/$name.props" ;;
    attributes) cat "/fixture/props/$name.attrs" ;;
    *) exit 97 ;;
esac
SH
        chmod 0755, "$root/bin/udevadm" or die $!;
        for my $device (@{$options{blocks} // []}) {
            system('mknod', "$root/dev/$device", 'b', '240', '0') == 0 or die "mknod: $?";
        }
        write_binary("$root/dev/$_", '') for @{$options{regular} // []};
        my %mounts = ($script => '/getinstdisk', "$root/partitions" => '/proc/partitions');
        $mounts{"$root/dev/$_"} = "/dev/$_" for @{$options{blocks} // []}, @{$options{regular} // []};
        if ($options{no_awk}) {
            write_binary("$root/bin/find", "#!/bin/sh\nexit 0\n");
            write_binary("$root/bin/awk", "#!/bin/sh\nprintf called >>/fixture/awk-calls\nexit 97\n");
            chmod 0755, "$root/bin/find", "$root/bin/awk" or die $!;
        }
        my $command = $options{logger} ?
            'msgutil_r() { printf "%s\n" "$*" >> /fixture/warnings; }; . /getinstdisk' :
            '. /getinstdisk';
        if ($options{pre}) {
            render_template($database, repo_path('xCAT-server/share/xcat/install/scripts/pre.rhels10'),
                "$database/pre.sh", 'node', "$database/image.pkglist", '/install/rhels10/x86_64',
                'rh', undef, {xcatmaster => '192.0.2.1'}, osarch => 'x86_64');
            make_path("$root/libexec");
            write_binary("$root/libexec/platform-python", "#!/bin/sh\nexit 0\n");
            chmod 0755, "$root/libexec/platform-python" or die $!;
            $mounts{"$root/libexec"} = '/usr/libexec';
            $mounts{"$database/pre.sh"} = '/pre.sh';
            for my $name (qw(logger vgs vgchange vgremove chown)) {
                write_binary("$root/bin/$name", "#!/bin/sh\nexit 0\n");
                chmod 0755, "$root/bin/$name" or die $!;
            }
            write_binary("$root/bin/mknod", "#!/bin/sh\n: >\"\$1\"\n");
            chmod 0755, "$root/bin/mknod" or die $!;
            $command = '. /pre.sh';
        }
        for my $pass (1 .. 2) {
            write_binary("$root/tmp/xcat.install_disk", "/dev/not-selected\n");
            my ($rc, $output) = sandbox_run($root, {read_only => \%mounts,
                env => {MASTER_IP => '192.0.2.1', log_label => 'install'}},
                $options{pre} ? '/bin/bash' : '/bin/sh', '-c', $command);
            is($rc, 0, "pass $pass completes") or diag($output);
            unlike($output, qr/msgutil_r/, "pass $pass needs no absent installer logger") unless $options{logger};
            is(-f "$root/tmp/xcat.install_disk" ? scalar read_binary("$root/tmp/xcat.install_disk") : '',
                "$expected\n", "pass $pass selects the expected disk");
            ok(!-e "$root/tmp/xcat.getinstalldisk", "pass $pass removes scan state");
            ok(!-e "$root/awk-calls", "pass $pass works without calling awk") if $options{no_awk};
            if ($options{pre}) {
                my $partition = "$root/tmp/partitionfile";
                my @disk_rules = grep { /^ignoredisk\b/ } split /\n/,
                    (-f $partition ? scalar read_binary($partition) : '');
                is($disk_rules[-1], "ignoredisk --only-use=$expected",
                    "pass $pass uses the selected disk in the rendered installer partition plan");
            }
        }
        if ($options{logger}) {
            is(scalar read_binary("$root/warnings"),
                "192.0.2.1 warn Disk detection failed, defaulting to /dev/sda /var/log/xcat/xcat.log install\n" x 2,
                'default selection reaches the installer logger');
        }
    };
    return;
}

for my $no_awk (0, 1) {
    subtest $no_awk ? 'without awk discovery' : 'with awk discovery' => sub {
        my @cases = (
            ['/dev/sdb', 'direct disk before RAID', {sda => {driver => 'megaraid_sas'}, sdb => {driver => 'ahci'}}],
            ['/dev/sda', 'RAID alone', {sda => {driver => 'megaraid_sas'}}],
            ['/dev/sdb', 'direct disk before SAS', {sda => {driver => 'mpt3sas'}, sdb => {driver => 'ahci'}}],
            ['/dev/sda', 'SAS before unclassified driver', {sda => {driver => 'mpt3sas'}, sdb => {driver => 'virtio_blk'}}],
            ['/dev/nvme0n1', 'driverless NVMe', {nvme0n1 => {}}],
            ['/dev/sda', 'empty scan', {}],
            ['/dev/sdb', 'group wins over RAID WWN', {sda => {driver => 'megaraid_sas', wwn => '0x5001'}, sdb => {driver => 'ahci'}}],
            ['/dev/sda', 'group wins when scanned first', {sda => {driver => 'ahci'}, sdb => {driver => 'megaraid_sas', wwn => '0x5002'}}],
            ['/dev/sdb', 'WWN before no identifier', {sda => {driver => 'ahci'}, sdb => {driver => 'ahci', wwn => '0x5001'}}],
            ['/dev/sdb', 'lower WWN', {sda => {driver => 'ahci', wwn => '0x5002'}, sdb => {driver => 'ahci', wwn => '0x5001'}}],
            ['/dev/sda', 'path before no identifier', {sda => {driver => 'ahci', path => '/devices/pci/block/sda'}, sdb => {driver => 'ahci'}}],
            ['/dev/xvda', 'scanned Xen disk', {xvda => {driver => 'vbd'}}],
            ['/dev/xvdb', 'Xen driver ordering', {xvda => {driver => 'vbd'}, xvdb => {driver => 'ahci'}}],
            ['/dev/sdb', 'ignore small media', {sda => {driver => 'ahci', size => 100}, sdb => {driver => 'virtio_blk'}}],
        );
        selects(@$_, no_awk => $no_awk) for @cases;
    };
}
selects('/dev/md/Volume0_0', 'VROC numbered fallback', {}, blocks => ['md/Volume0_0']);
selects('/dev/md/Volume0', 'VROC unnumbered fallback', {}, blocks => ['md/Volume0']);
selects('/dev/md/Volume0_0', 'VROC preference over other fallbacks', {}, blocks => ['md/Volume0_0', 'md/Volume0', 'xvda']);
selects('/dev/xvda', 'Xen fallback', {}, blocks => ['xvda']);
selects('/dev/sdb', 'scanned disk before fallback devices', {sdb => {driver => 'ahci'}}, blocks => ['md/Volume0_0', 'xvda']);
selects('/dev/sda', 'regular files are not block devices', {}, regular => ['md/Volume0_0', 'md/Volume0', 'xvda']);
selects('/dev/sda', 'default selection with installer logger', {}, logger => 1);

$database = template_database();
set_row('site', {key => 'nodestatus'}, {value => 0});
set_row('nodetype', {node => 'node'}, {os => 'rhels10', arch => 'x86_64', provmethod => 'install'});
write_binary("$database/image.pkglist", '');
selects('/dev/sdb', 'rendered RHEL 10 installer disk selection',
    {sda => {driver => 'megaraid_sas'}, sdb => {driver => 'ahci'}}, pre => 1);

done_testing();
