#!/usr/bin/env perl
# copycds copies the install media with the modes the media carries. EL media ships the EFI
# binaries of its boot loader mode 0700, and xCAT serves /install over HTTP, so the web server
# cannot read them. Measured on an AlmaLinux 10 tree copied by copycds: EFI/BOOT/grub.cfg is
# 0444 and answers 200, EFI/BOOT/BOOTX64.EFI and EFI/BOOT/mmx64.efi are 0700 and answer 403.
#
# make_readable adds read permission for the group and for others, and search permission on a
# directory. It never adds write permission, and it never adds execute permission to a file.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

my %before = %INC;
require xCAT::MediaPerms;
my @xcat_loaded = sort grep { m{^xCAT} and !exists $before{$_} } keys %INC;
is_deeply( \@xcat_loaded, ['xCAT/MediaPerms.pm'], 'xCAT::MediaPerms loads no other xCAT module' );

sub mode_of {
    my ($path) = @_;
    return sprintf '%04o', ( ( stat $path )[2] & 07777 );
}

my $root = tempdir( CLEANUP => 1 );
make_path("$root/EFI/BOOT/fonts");
foreach my $file (qw(EFI/BOOT/BOOTX64.EFI EFI/BOOT/mmx64.efi EFI/BOOT/grub.cfg EFI/BOOT/fonts/unicode.pf2)) {
    open my $fh, '>', "$root/$file" or die "write $file: $!";
    print $fh 'x';
    close $fh or die "close $file: $!";
}
# make_path takes the mode of the umask of the caller, so the modes of the two directories it
# creates are those of whoever runs the test. The count below is a count of the paths that
# change, so every mode in the fixture is set here.
chmod 0755, "$root/EFI", "$root/EFI/BOOT";
chmod 0700, "$root/EFI/BOOT/BOOTX64.EFI", "$root/EFI/BOOT/mmx64.efi";
chmod 0444, "$root/EFI/BOOT/grub.cfg";
chmod 0600, "$root/EFI/BOOT/fonts/unicode.pf2";
chmod 0700, "$root/EFI/BOOT/fonts";

my $changed = xCAT::MediaPerms::make_readable("$root/EFI");

is( mode_of("$root/EFI/BOOT/BOOTX64.EFI"), '0744',
    'a boot loader the media ships 0700 becomes readable, and keeps its owner execute bit' );
is( mode_of("$root/EFI/BOOT/mmx64.efi"), '0744', 'and so does the MOK manager beside it' );
is( mode_of("$root/EFI/BOOT/fonts/unicode.pf2"), '0644',
    'a file with no execute bit stays without one' );
is( mode_of("$root/EFI/BOOT/fonts"), '0755',
    'a directory the media ships 0700 gains search permission, so the files under it can be read' );
is( mode_of("$root/EFI/BOOT/grub.cfg"), '0444', 'a file that is already readable is left alone' );
is( $changed, 4, 'make_readable reports the number of paths it changed' );

is( xCAT::MediaPerms::make_readable("$root/EFI"), 0,
    'a second call changes nothing, so copycds can be re-run' );

is( xCAT::MediaPerms::make_readable("$root/no-such-directory"), 0,
    'a directory that does not exist changes nothing' );

# No write permission is ever added. /install holds the media of every osimage on the
# management node.
my $writable = tempdir( CLEANUP => 1 );
open my $fh, '>', "$writable/kernel" or die "write kernel: $!";
close $fh or die "close kernel: $!";
chmod 0700, "$writable/kernel";
xCAT::MediaPerms::make_readable($writable);
is( mode_of("$writable/kernel"), '0744', 'the file is readable and writable by its owner alone' );

done_testing();
