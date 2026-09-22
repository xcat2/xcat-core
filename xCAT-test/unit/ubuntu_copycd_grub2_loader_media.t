#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# The stubbed test proves the decisions copycd makes. This one proves the artifact: it runs the
# real grub-mkimage over the grub2 package of real Ubuntu media and checks that what comes out is
# what the management node will serve to a riscv64 node.
#
# It needs copied riscv64 media and the grub2 build tools, so it runs where those exist:
#   XCAT_TEST_UBUNTU_RISCV64_MEDIA=/install/ubuntu24.04.4/riscv64 perl <this test>
# Without them it skips, which is why the stubbed test still covers the decisions.

BEGIN {
    package xCAT::TableUtils;
    our $tftpdir;
    sub getTftpDir { return $tftpdir; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;
}

my $media = $ENV{XCAT_TEST_UBUNTU_RISCV64_MEDIA};
plan skip_all => 'set XCAT_TEST_UBUNTU_RISCV64_MEDIA to copied riscv64 media' unless $media;
plan skip_all => "no media at $media" unless -d $media;
foreach my $tool (qw(dpkg-deb grub-mkimage)) {
    my $found = grep { -x "$_/$tool" } split( /:/, $ENV{PATH} // '' );
    plan skip_all => "$tool is not installed" unless $found;
}

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
plan skip_all => 'debian.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load debian.pm: $@";

$xCAT::TableUtils::tftpdir = tempdir( CLEANUP => 1 );
my @told;
my $target = xCAT_plugin::debian::install_media_grub2_loader(
    $media, 'riscv64',
    sub { push @told, ( $_[0]->{data} // () ), @{ $_[0]->{warning} || [] } } );

ok( defined $target, 'the media produced a loader' )
  or diag( join( "\n", @told ) ), done_testing(), exit;
is( $target, "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64",
    'it is where nodeset serves it from' );
ok( -s $target, '... and it is not empty' );

# The same checks nodeset depends on, against a real grub-mkimage image rather than a fabricated one.
my $build = { machine => 0x5064, format => 'riscv64-efi', package => 'grub-efi-riscv64-bin' };
ok( xCAT_plugin::debian::_is_uefi_image( $target, $build->{machine} ),
    'the image is a riscv64 UEFI application' );
ok( xCAT_plugin::debian::_is_netboot_loader( $target, $build ),
    '... carrying the prefix and the modules a net boot needs' );

# A second import must not rebuild it: the image already in place is the one the nodes booted.
my $before = ( stat($target) )[9];
my $again  = xCAT_plugin::debian::install_media_grub2_loader( $media, 'riscv64', undef );
is( $again, $target, 'a second import returns the loader already in place' );
is( ( stat($target) )[9], $before, '... without rewriting it' );

done_testing();
