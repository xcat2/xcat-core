#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

my $repo_root  = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $script_dir = File::Spec->catdir( $repo_root, 'xCAT-server', 'share', 'xcat', 'install', 'scripts' );

# One script serves every installer, so one file is exercised here.
my @scripts = map { File::Spec->catfile( $script_dir, $_ ) } qw(getinstdisk);
plan skip_all => 'getinstdisk not found' if grep { !-r $_ } @scripts;
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

    my $body = slurp($script);
    $body =~ s{/proc/partitions}{$sandbox/partitions}g;
    $body =~ s{/tmp/xcat\.install_disk}{$sandbox/xcat.install_disk}g;
    $body =~ s{/tmp/xcat\.getinstalldisk}{$sandbox/xcat.getinstalldisk}g;
    $body =~ s{/dev/md/Volume0}{$sandbox/md/Volume0}g;
    $body =~ s{"/dev/xvda"}{"$sandbox/xvda"}g;
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

    local $ENV{FIXDIR}     = $fixdir;
    local $ENV{PATH}       = "$bindir:$ENV{PATH}";
    local $ENV{MASTER_IP}  = '';
    system("sh $sandbox/getinstdisk >$sandbox/log 2>&1");
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

done_testing();
