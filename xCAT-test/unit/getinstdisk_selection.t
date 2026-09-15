#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source;

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::Sandbox qw(replace_required assert_no_host_paths stub_bin run_confined);

my $repo_root  = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $script_dir = File::Spec->catdir( $repo_root, 'xCAT-server', 'share', 'xcat', 'install', 'scripts' );

# One script serves every installer, so one file is exercised here.
my @scripts = map { File::Spec->catfile( $script_dir, $_ ) } qw(getinstdisk);
die "getinstdisk not found\n" if grep { !-r $_ } @scripts;
our $script;

sub slurp {
    open( my $fh, '<', $_[0] ) or die "Unable to read $_[0]: $!";
    my $c = do { local $/; <$fh> };
    close($fh);
    return $c;
}

# The script reads /proc/partitions and writes under /tmp, so each scenario
# runs a copy with those paths moved into its own sandbox, and a stub udevadm
# serves the device properties from fixture files.
sub run_scenario {
    my (%disk) = @_;
    my $sandbox = tempdir( CLEANUP => 1 );
    my $fixdir  = "$sandbox/fix";
    my $bindir  = "$sandbox/bin";
    mkdir $fixdir;
    mkdir $bindir;
    # The udevadm fake written below replaces its wrapper; any other command is not found.
    stub_bin( dir => $bindir, tools => [qw(bash sh cat grep sed awk cut tr sort uniq head tail wc ls basename dirname mkdir rm mv cp touch date sleep xargs expr env readlink)] );

    my $body = slurp($script);
    replace_required( \$body, '/proc/partitions',         "$sandbox/partitions" );
    replace_required( \$body, '/tmp/xcat.install_disk',   "$sandbox/xcat.install_disk" );
    replace_required( \$body, '/tmp/xcat.getinstalldisk', "$sandbox/xcat.getinstalldisk" );
    replace_required( \$body, '/dev/md/Volume0',          "$sandbox/md/Volume0" );
    replace_required( \$body, '"/dev/xvda"',              "\"$sandbox/xvda\"" );
    # msgutil_r comes from the installer script that includes this one, and writes this log.
    replace_required( \$body, '/var/log/xcat/xcat.log',   "$sandbox/xcat.log" );
    assert_no_host_paths( $body, root => $sandbox, prefixes => [qw(/etc /var /root /home /boot /opt /srv /install /tftpboot /xcatpost /proc /tmp)], allow => [qr/^\s*#/] );
    open( my $sh, '>', "$sandbox/getinstdisk" ) or die $!;
    print $sh $body;
    close($sh);

    open( my $parts, '>', "$sandbox/partitions" ) or die $!;
    print $parts "major minor  #blocks  name\n\n";
    my $minor = 0;
    for my $name ( sort keys %disk ) {
        printf $parts "   8 %5d  524288000 %s\n", $minor++, $name;
    }
    close($parts);

    for my $name ( sort keys %disk ) {
        my %attr = %{ $disk{$name} };
        open( my $props, '>', "$fixdir/$name.props" ) or die $!;
        print $props "ID_WWN=$attr{wwn}\n" if $attr{wwn};
        print $props "DEVPATH=$attr{path}\n" if $attr{path};
        print $props "DEVTYPE=disk\n";
        close($props);
        open( my $attrs, '>', "$fixdir/$name.attrs" ) or die $!;
        print $attrs qq{    ATTRS{size}=="1024000000"\n};
        print $attrs qq{    DRIVERS=="$attr{driver}"\n} if $attr{driver};
        my @models = $attr{models} ? @{ $attr{models} } : ( $attr{model} ? $attr{model} : () );
        print $attrs qq{    ATTRS{model}=="$_"\n} for @models;
        close($attrs);
    }

    open( my $udev, '>', "$bindir/udevadm" ) or die $!;
    print $udev <<'UDEV';
#!/bin/sh
for a in "$@"; do
    case "$a" in
    --name=*) name=${a#--name=} ;;
    esac
done
name=${name#/dev/}
case "$*" in
*--query=property*) cat "$FIXDIR/$name.props" 2>/dev/null ;;
*--attribute-walk*) cat "$FIXDIR/$name.attrs" 2>/dev/null ;;
esac
exit 0
UDEV
    close($udev);
    chmod 0755, "$bindir/udevadm";

    my ( undef, $log ) = run_confined(
        cmd      => [ 'sh', "$sandbox/getinstdisk" ],
        bin      => $bindir,
        env      => { FIXDIR => $fixdir, MASTER_IP => '' },
        writable => [$sandbox],
    );
    open( my $log_fh, '>', "$sandbox/log" ) or die "Unable to write $sandbox/log: $!";
    print {$log_fh} $log;
    close($log_fh);
    my $chosen = -r "$sandbox/xcat.install_disk" ? slurp("$sandbox/xcat.install_disk") : '';
    chomp $chosen;
    return $chosen;
}

# Every scenario asserts against both copies of the script.
sub selects {
    my ( $expected, $name, %disk ) = @_;
    for my $candidate (@scripts) {
        local $script = $candidate;
        my $variant = ( File::Spec->splitpath($candidate) )[2];
        is( run_scenario(%disk), $expected, "$name ($variant)" );
    }
    return;
}

# A direct attached disk wins over a RAID volume when both are present. The
# RAID volume sorts first by name, so the choice comes from the driver group.
selects( '/dev/sdb', 'the direct attached disk wins over the RAID volume',
    sda => { driver => 'megaraid_sas' },
    sdb => { driver => 'ahci' } );

# A server with only RAID volumes still selects one.
selects( '/dev/sda', 'a RAID volume is selected when nothing better exists',
    sda => { driver => 'megaraid_sas' } );

# A SAS host adapter loses to a direct attached disk, and still wins over a
# driver with no group of its own.
selects( '/dev/sdb', 'the direct attached disk wins over the host adapter',
    sda => { driver => 'mpt3sas' },
    sdb => { driver => 'ahci' } );

selects( '/dev/sda', 'the host adapter wins over an unknown driver',
    sda => { driver => 'mpt3sas' },
    sdb => { driver => 'virtio_blk' } );

# A driverless NVMe device still gets selected from the last group.
selects( '/dev/nvme0n1', 'an NVMe device is selected from the last group',
    nvme0n1 => {} );

# No usable disk falls back to the documented default.
selects( '/dev/sda', 'no disks fall back to the default' );

# The driver group decides before the identifier. A disk that reports no WWN
# used to be dropped when another disk reported one, or to be ignored because
# the readback only opened the files of the last identifier class seen.
selects( '/dev/sdb', 'the direct attached disk wins when only the RAID volume reports a WWN',
    sda => { driver => 'megaraid_sas', wwn => '0x5000cca0aaaa0001' },
    sdb => { driver => 'ahci' } );

selects( '/dev/sda', 'the direct attached disk wins when it is scanned first without a WWN',
    sda => { driver => 'ahci' },
    sdb => { driver => 'megaraid_sas', wwn => '0x5000cca0aaaa0002' } );

# Within one driver group the identifier decides, and a disk that reports one
# is preferred, because that name is stable across reboots.
selects( '/dev/sdb', 'the disk with a WWN wins inside the group',
    sda => { driver => 'ahci' },
    sdb => { driver => 'ahci', wwn => '0x5000cca0bbbb0001' } );

selects( '/dev/sdb', 'the lower WWN wins inside the group',
    sda => { driver => 'ahci', wwn => '0x5000cca0bbbb0002' },
    sdb => { driver => 'ahci', wwn => '0x5000cca0bbbb0001' } );

selects( '/dev/sda', 'a path is preferred over no identifier at all',
    sda => { driver => 'ahci', path => '/devices/pci0000:00/0000:00:1f.2/ata1/host0/target0:0:0/0:0:0:0/block/sda' },
    sdb => { driver => 'ahci' } );

# A Xen guest presents xvd names. The scan has to see them, because the
# fallback below it would take the first one without looking.
selects( '/dev/xvda', 'a Xen disk is scanned rather than assumed',
    xvda => { driver => 'vbd' } );

selects( '/dev/xvdb', 'the better driver group wins among Xen disks',
    xvda => { driver => 'vbd' },
    xvdb => { driver => 'ahci' } );

# Every installer includes the one script, which carries the fallbacks and the
# logging that the separate RHEL 10 copy used to hold on its own.
my $common = slurp( $scripts[0] );
ok( !-e File::Spec->catfile( $script_dir, 'getinstdisk.rhels10' ),
    'the RHEL 10 copy of the script is gone' );
like( slurp( File::Spec->catfile( $script_dir, 'pre.rhels10' ) ),
    qr{/share/xcat/install/scripts/getinstdisk#},
    'the RHEL 10 installer includes the common script' );
like( $common, qr{-b /dev/md/Volume0_0}, 'the common script keeps the VROC fallback' );
like( $common, qr{-b "/dev/xvda"},       'the common script carries the Xen fallback' );
like( $common, qr{command -v msgutil_r [^\n]*\n\s*msgutil_r },
    'the failure log is guarded, because one installer does not define it' );

done_testing();
