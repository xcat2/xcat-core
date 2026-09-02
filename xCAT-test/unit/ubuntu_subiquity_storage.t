#!/usr/bin/env perl
# The partitioning pre.ubuntu.subiquity hands to Subiquity.
#
# Every assertion here used to be a regex against the script's own text, which
# passes when the block is moved somewhere it never runs and fails when the YAML
# is reindented or its keys reordered -- a pure reformat broke the old efi-part
# match while the emitted config was identical. The block is executed instead and
# the config it writes is parsed, so the assertions are about what Subiquity gets.
use strict;
use warnings;

use File::Spec;
use File::Temp ();
use Test::More;

my $pre_path = defined $ENV{XCATROOT} ? "$ENV{XCATROOT}/share/xcat/install/scripts/pre.ubuntu.subiquity" : '';
$pre_path = "xCAT-server/share/xcat/install/scripts/pre.ubuntu.subiquity"
    unless -f $pre_path;

plan skip_all => "pre.ubuntu.subiquity not found" unless -f $pre_path;

my $script = do { local $/; open my $fh, '<', $pre_path or die $!; <$fh> };

is( system("bash -n $pre_path 2>/dev/null"), 0,
    'pre.ubuntu.subiquity passes bash -n syntax check' );

# ------------------------------------------------------ the emitted partitioning --
# pre.ubuntu.subiquity cannot run here -- it stops syslog and carries xCAT template
# markers -- so the block that writes the partition file is lifted out and executed,
# with its one bracket test shadowed to choose the firmware branch and its output
# redirected into a scratch tree. Both substitutions are asserted: if either stops
# matching, this bails out rather than silently covering nothing or writing to /tmp.
my ($storage_block) = $script =~ /(^if \[ -d \/sys\/firmware\/efi \]; then\n.*?\n^fi$)/ms;
BAIL_OUT('the firmware branch that writes the partition file no longer matches')
    unless $storage_block;

my $brackets = () = $storage_block =~ /\[ /g;
BAIL_OUT("the partitioning block now has $brackets bracket tests; the shadow below covers one")
    unless $brackets == 1;

my $sandbox   = File::Temp::tempdir( CLEANUP => 1 );
my $partfile  = File::Spec->catfile( $sandbox, 'partitionfile' );
my $rewrites  = ( $storage_block =~ s{/tmp/partitionfile}{$partfile}g );
BAIL_OUT("expected two partition-file redirects to sandbox, rewrote $rewrites")
    unless $rewrites == 2;

my %YAML_FOR;

sub partition_yaml_for { return $YAML_FOR{ $_[0] }; }

sub partition_config_for {
    my ($firmware) = @_;
    my $script = File::Spec->catfile( $sandbox, 'storage.sh' );
    open( my $fh, '>', $script ) or die "Unable to write $script: $!";
    # `[` is shadowed rather than the condition rewritten: bash resolves a function
    # ahead of the builtin, so the script's own test runs unmodified.
    print {$fh} <<"SHELL";
INSTALL_DISK=/dev/sdz
logger() { :; }
[() {
  case "\$1 \$2" in
    "-d /sys/firmware/efi") return @{[ $firmware eq 'uefi' ? 0 : 1 ]} ;;
    *) builtin echo "unexpected bracket test: \$*" >&2; builtin return 2 ;;
  esac
}
$storage_block
SHELL
    close($fh);

    unlink $partfile;
    system( 'bash', $script ) == 0
        or BAIL_OUT("the extracted partitioning block failed to run for $firmware");
    open( my $out_fh, '<', $partfile )
        or BAIL_OUT("the partitioning block wrote no file for $firmware: $!");
    my $yaml = do { local $/; <$out_fh> };
    close($out_fh);
    $YAML_FOR{$firmware} = $yaml;

    # Parse the curtin config into id => {key => value} so the assertions survive
    # reordering and reindentation, which is what the source match could not do.
    my %entry;
    my $current;
    foreach my $line ( split /\n/, $yaml ) {
        if ( $line =~ /^\s+- id:\s*(\S+)/ ) {
            $current = $1;
            $entry{$current} = { id => $1 };
        }
        elsif ( defined $current && $line =~ /^\s+(\S+):\s*(\S*)\s*$/ ) {
            $entry{$current}{$1} = $2;
        }
    }
    return \%entry;
}

my $uefi = partition_config_for('uefi');
is( $uefi->{'efi-part'}{type},        'partition',     'UEFI installs get an EFI partition' );
is( $uefi->{'efi-part'}{device},      'disk-detected', 'on the detected install disk' );
is( $uefi->{'efi-part'}{size},        '512M',          'sized for an ESP' );
is( $uefi->{'efi-part'}{flag},        'boot',          'flagged bootable' );
is( $uefi->{'efi-part'}{number},      '1',             'as the first partition' );
is( $uefi->{'efi-part'}{grub_device}, 'true',          'and it is where grub is installed' );
is( $uefi->{'efi-part-fs'}{type},   'format',   'the ESP is formatted' );
is( $uefi->{'efi-part-fs'}{fstype}, 'fat32',    'as fat32, which firmware can read' );
is( $uefi->{'efi-part-fs'}{volume}, 'efi-part', 'on the partition just created' );
is( $uefi->{'efi-part-mount'}{path}, '/boot/efi', 'and mounted where the kernel expects it' );

# The BIOS branch must not carry the ESP, and puts grub on the disk itself.
my $bios = partition_config_for('bios');
ok( !exists $bios->{'efi-part'}, 'BIOS installs get no EFI partition' );
is( $bios->{'bios-grub'}{flag}, 'bios_grub', 'they get a bios_grub partition instead' );
is( $bios->{'disk-detected'}{grub_device}, 'true', 'and grub is installed to the disk' );

foreach my $firmware ( [ UEFI => $uefi ], [ BIOS => $bios ] ) {
    my ( $name, $config ) = @{$firmware};
    is( $config->{'root-part-fs'}{fstype}, 'ext4', "$name root filesystem is ext4" );
    is( $config->{'root-part-mount'}{path}, '/',   "$name mounts root at /" );
    is( $config->{'swap-part-fs'}{fstype}, 'swap', "$name has swap formatted" );
    is( $config->{'root-part'}{size}, '-1',
        "$name gives the remaining space to root" );
}


# Subiquity re-serializes autoinstall.yaml and appends this file, so the block has
# to start at column 0 -- asserted on what was written, not on the heredoc.
foreach my $firmware ( [ UEFI => 'uefi' ], [ BIOS => 'bios' ] ) {
    my ( $name, $key ) = @{$firmware};
    like( partition_yaml_for($key), qr/\Astorage:\n  version: 1\n/,
        "$name config starts at column 0 with storage: version: 1" );
}

done_testing();
