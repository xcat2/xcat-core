#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# riscv64 nodes have no boot loader unless one reaches /tftpboot/boot/grub2. The image on
# the media cannot be used: it carries a built-in configuration that looks for the live
# filesystem, so a node that loads it drops to a grub prompt instead of reading the network
# configuration. copycd builds a netboot image from the grub2 package the media ship.
#
# dpkg-deb and grub-mkimage are shadowed by stubs ahead of $PATH, because a management node
# is the only place they exist. They record what copycd asked for, so the arguments that
# decide whether the image can boot over the network are what the assertions read.

BEGIN {
    package xCAT::TableUtils;
    our $tftpdir;
    sub getTftpDir { return $tftpdir; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;
}

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
plan skip_all => 'debian.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load debian.pm: $@";

my $stubs = tempdir(CLEANUP => 1);
my $log   = "$stubs/mkimage.args";

sub write_stub {
    my ($name, $body) = @_;
    open(my $fh, '>', "$stubs/$name") or die $!;
    print {$fh} "#!/bin/bash\n$body";
    close($fh);
    chmod 0755, "$stubs/$name";
}

# dpkg-deb -x <package> <dir> lays down the module tree the package carries.
write_stub('dpkg-deb', <<'SH');
dir="${!#}"
mkdir -p "$dir/usr/lib/grub/riscv64-efi"
: > "$dir/usr/lib/grub/riscv64-efi/kernel.img"
SH

# grub-mkimage records its arguments and writes a riscv64 PE image to the -o path. Like the real
# one it embeds the prefix and the name of every module it was asked for, which is what tells a
# grub2 image apart from a file that merely carries the headers.
write_stub('grub-mkimage', <<'SH');
echo "$@" >> "$MKIMAGE_LOG"
[ -n "$MKIMAGE_FAIL" ] && exit 1
out=""; prefix=""; modules=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -p) prefix="$2"; shift 2 ;;
    -O|-d) shift 2 ;;
    *) modules+=("$1"); shift ;;
  esac
done
perl -e 'my ($prefix, @modules) = @ARGV;
  my $i = "MZ" . "\0" x 58 . pack("V", 64) . "PE\0\0" . pack("v", 0x5064)
  . pack("v", 1) . "\0" x 16 . pack("v", 0x20b) . "\0" x 14 . pack("V", 0x1000)
  . "\0" x 36 . pack("V", 4096) . pack("V", 4096) . "\0" x 4 . pack("v", 10) . "\0" x 2;
  $i .= "$prefix\0";
  $i .= "\0$_\0" for @modules;
  print $i, "\0" x (4096 - length $i)' "$prefix" "${modules[@]}" > "$out"
SH

$ENV{PATH}        = "$stubs:$ENV{PATH}";
$ENV{MKIMAGE_LOG} = $log;

sub media_with {
    my (@files) = @_;
    my $root = tempdir(CLEANUP => 1);
    foreach my $file (@files) {
        my $full = "$root/$file";
        ($full =~ m{^(.*)/[^/]+$}) and make_path($1);
        open(my $fh, '>', $full) or die $!;
        print {$fh} "content of $file";
        close($fh);
    }
    return $root;
}

sub publish {
    my ($arch, $media) = @_;
    $xCAT::TableUtils::tftpdir = tempdir(CLEANUP => 1);
    unlink $log;
    my @said;
    xCAT_plugin::debian::install_media_grub2_loader(
        $media, $arch,
        sub { push @said, ($_[0]->{data} // ()), @{ $_[0]->{warning} || [] } });
    my $target = "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.$arch";
    return {
        published => (-e $target ? 1 : 0),
        built     => (-r $log ? do { open my $fh, '<', $log; local $/; <$fh> } : ''),
        said      => join(' ', @said),
    };
}

my $package = 'pool/main/g/grub2/grub-efi-riscv64-bin_2.12-1ubuntu7.3_riscv64.deb';

my $riscv = publish('riscv64', media_with($package, 'casper/vmlinux'));
is($riscv->{published}, 1, 'riscv64 media publish a grub2 loader');
like($riscv->{built}, qr/-O riscv64-efi/, 'the image is built for the riscv64 firmware');
like($riscv->{built}, qr{-p /boot/grub2},
    'the image looks for its configuration where nodeset writes it');
like($riscv->{built}, qr{-d \S+/usr/lib/grub/riscv64-efi},
    'the modules come from the package the media ship');
like($riscv->{built}, qr/\befinet\b.*\btftp\b/s, 'the image can reach the network');
like($riscv->{built}, qr/\bhttp\b/, 'the image can read a configuration over HTTP');
like($riscv->{said}, qr/Installed .*grub2\.riscv64 from the media/,
    'copycd says where the loader came from');

my $x86 = publish('x86_64', media_with('EFI/boot/bootx64.efi', 'casper/vmlinuz'));
is($x86->{published}, 0, 'media of another architecture publish nothing');

my $none = publish('riscv64', media_with('casper/vmlinux'));
is($none->{published}, 0, 'riscv64 media without the grub2 package publish nothing');
like($none->{said}, qr/No grub2\.riscv64 boot loader was installed/,
    'copycd says a riscv64 node will not boot without a loader');

# a build that fails must leave no loader behind, so nodeset reports the missing file
$ENV{MKIMAGE_FAIL} = 1;
my $failed = publish('riscv64', media_with($package));
delete $ENV{MKIMAGE_FAIL};
is($failed->{published}, 0, 'a failed build leaves no loader');
like($failed->{said}, qr/No grub2\.riscv64 boot loader was installed/,
    'copycd reports a build that failed');

# The image is built beside the target and renamed, so an interrupted run cannot leave a
# partial loader behind for nodeset to hand out.
$xCAT::TableUtils::tftpdir = tempdir(CLEANUP => 1);
make_path("$xCAT::TableUtils::tftpdir/boot/grub2");
$ENV{MKIMAGE_FAIL} = 1;
xCAT_plugin::debian::install_media_grub2_loader(media_with($package), 'riscv64', undef);
delete $ENV{MKIMAGE_FAIL};
my @leftovers = glob("$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64*");
is(scalar @leftovers, 0, 'a failed build leaves nothing beside the target either');

# An empty target is what an interrupted older run left behind, so it must not be mistaken
# for an installed loader.
$xCAT::TableUtils::tftpdir = tempdir(CLEANUP => 1);
make_path("$xCAT::TableUtils::tftpdir/boot/grub2");
open(my $efh, '>', "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64") or die $!;
close($efh);
unlink $log;
xCAT_plugin::debian::install_media_grub2_loader(media_with($package), 'riscv64', undef);
ok(-s "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64",
    'an empty loader left by an earlier run is replaced');

# UEFI loads the loader as a PE image for one machine. A real riscv64 one is kept, and
# anything else -- text, a header-only stub, another architecture's loader -- is replaced,
# because a node given one of those cannot boot.
sub uefi_image {
    my (%f) = @_;
    my $size = $f{size} // 4096;
    my $image =
        "MZ" . ( "\0" x 58 ) . pack( 'V', 64 )
      . "PE\0\0"
      . pack( 'v', $f{machine}  // 0x5064 )
      . pack( 'v', $f{sections} // 1 ) . ( "\0" x 16 )
      . pack( 'v', 0x20b ) . ( "\0" x 14 )
      . pack( 'V', $f{entry} // 0x1000 ) . ( "\0" x 36 )
      . pack( 'V', $size ) . pack( 'V', $size ) . ( "\0" x 4 )
      . pack( 'v', $f{subsystem} // 10 ) . ( "\0" x 2 );
    my $prefix = exists $f{prefix} ? $f{prefix} : '/boot/grub2';
    $image .= "$prefix\0" if length $prefix;
    # grub-mkimage records the name of every embedded module, so a real loader carries them.
    my @modules = exists $f{modules}
      ? @{ $f{modules} }
      : qw(efinet tftp http linux normal configfile search);
    $image .= "\0$_\0" for @modules;
    return $image . ( "\0" x ( $size - length $image ) );
}

sub existing_loader_kept {
    my ($bytes) = @_;
    $xCAT::TableUtils::tftpdir = tempdir( CLEANUP => 1 );
    make_path("$xCAT::TableUtils::tftpdir/boot/grub2");
    my $target = "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64";
    open( my $fh, '>', $target ) or die $!;
    binmode($fh);
    print {$fh} $bytes;
    close($fh);
    xCAT_plugin::debian::install_media_grub2_loader( media_with($package), 'riscv64', undef );
    open( my $rfh, '<', $target ) or die $!;
    binmode($rfh);
    my $now = do { local $/; <$rfh> };
    close($rfh);
    return $now eq $bytes;
}

ok( existing_loader_kept( uefi_image() ), 'a riscv64 loader already in place is kept' );

ok( !existing_loader_kept('not a loader at all'),
    'a file that is not a UEFI image is replaced' );
ok( !existing_loader_kept('MZ and nothing else'),
    'a file that only starts with the DOS signature is replaced' );
ok( !existing_loader_kept( substr( uefi_image(), 0, 200 ) ),
    'a loader truncated to its headers is replaced' );
ok( !existing_loader_kept( uefi_image( machine => 0x8664 ) ),
    "another architecture's loader is replaced" );

# The fields below are what makes a PE image executable at all. A file carrying the
# signatures but none of them cannot boot a node, so it must not be mistaken for a loader.
ok( !existing_loader_kept( uefi_image( sections => 0 ) ),
    'an image with no sections to load is replaced' );
ok( !existing_loader_kept( uefi_image( entry => 0 ) ),
    'an image with no entry point is replaced' );
ok( !existing_loader_kept( uefi_image( subsystem => 3 ) ),
    'an image that is not an EFI application is replaced' );

# The image on the media carries the same modules but not the prefix this plugin builds with,
# so it looks for the live filesystem instead of the configuration nodeset writes.
ok( !existing_loader_kept( uefi_image( prefix => '' ) ),
    'a valid EFI image built for another boot path is replaced' );

# Headers and a prefix are cheap to fabricate and say nothing about what the image can do.
# Without the modules a net boot goes through, the file cannot fetch a kernel over the network.
ok( !existing_loader_kept( uefi_image( modules => [] ) ),
    'an image carrying no grub2 modules is replaced' );
ok( !existing_loader_kept( uefi_image( modules => [qw(linux normal configfile search)] ) ),
    'an image with no network modules is replaced' );
ok( existing_loader_kept( uefi_image( modules => [qw(efinet tftp http linux normal configfile search gzio)] ) ),
    'an image carrying more modules than the minimum is kept' );

# A rebuild that cannot run must leave the loader alone. The check cannot tell an image this
# plugin did not build from one built for another boot path -- the media loader carries the same
# modules -- so removing one on that evidence can take a working loader away from every node.
$xCAT::TableUtils::tftpdir = tempdir( CLEANUP => 1 );
make_path("$xCAT::TableUtils::tftpdir/boot/grub2");
my $rejected = "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64";
open( my $bad, '>', $rejected ) or die $!;
print {$bad} 'not a loader at all';
close($bad);
my @told;
xCAT_plugin::debian::install_media_grub2_loader(
    media_with('casper/vmlinux'), 'riscv64',
    sub { push @told, ( $_[0]->{data} // () ), @{ $_[0]->{warning} || [] } } );
ok( -e $rejected, 'a rejected loader survives a media that cannot replace it' );
my $left = -e $rejected
  ? do { open my $fh, '<', $rejected or die $!; local $/; <$fh> }
  : '(removed)';
is( $left, 'not a loader at all', '... byte for byte' );
like( join( ' ', @told ), qr/No grub2\.riscv64 boot loader was installed/,
    'and copycd says no loader was installed' );
like( join( ' ', @told ), qr/was left alone/,
    '... and that it did not touch what was there' );

done_testing();
