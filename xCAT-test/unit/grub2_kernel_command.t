#!/usr/bin/env perl
#
# Which commands a grub2 configuration may use to load a kernel.
#
# linuxefi and initrdefi come from a downstream patch. grub2.pm chose them for every x86
# node, from the architecture alone. An image built from upstream grub carries neither, so
# such a node stopped at the grub menu with "can't find command `linuxefi'", asked for no
# kernel over TFTP, and the boot never started. Measured on grub2-xcat 2.12-2 for Ubuntu,
# whose image carries linux and not linuxefi.
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More tests => 8;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::BootUtils;

my $dir = tempdir(CLEANUP => 1);

# grub records the name of each command its modules register, so the name appears in the
# image exactly when the command can be run. The names are NUL delimited.
sub write_image {
    my ($name, @commands) = @_;
    my $path = File::Spec->catfile($dir, $name);
    open(my $fh, '>:raw', $path) or die "cannot write $path: $!";
    print {$fh} "\x7fELF", "\0" x 32;
    print {$fh} "\0$_\0" for @commands;
    print {$fh} "\0" x 16;
    close($fh);
    return $path;
}

my $downstream = write_image('grub2.downstream', qw(linux linuxefi initrd initrdefi));
my $upstream   = write_image('grub2.upstream',   qw(linux initrd));

is_deeply( [ xCAT::BootUtils::grub2_kernel_commands($downstream) ],
    [ 'linuxefi', 'initrdefi' ],
    'an image that carries linuxefi is given linuxefi and initrdefi' );

is_deeply( [ xCAT::BootUtils::grub2_kernel_commands($upstream) ],
    [ 'linux', 'initrd' ],
    'an image built from upstream grub is given linux and initrd' );

# A missing or unreadable image must not produce a command the node cannot run. linux is
# carried by every grub2 image, so it is the safe answer.
is_deeply( [ xCAT::BootUtils::grub2_kernel_commands( File::Spec->catfile($dir, 'absent') ) ],
    [ 'linux', 'initrd' ], 'a missing image is given linux and initrd' );
is_deeply( [ xCAT::BootUtils::grub2_kernel_commands(undef) ],
    [ 'linux', 'initrd' ], 'an undefined image is given linux and initrd' );

ok( xCAT::BootUtils::grub2_image_provides($downstream, 'linuxefi'),
    'the downstream image reports linuxefi' );
ok( !xCAT::BootUtils::grub2_image_provides($upstream, 'linuxefi'),
    'the upstream image does not report linuxefi' );
ok( xCAT::BootUtils::grub2_image_provides($upstream, 'linux'),
    'the upstream image does report linux, so the search is not refusing everything' );

# The name has to be the whole command, or linux would match linuxefi and every image
# would look downstream.
ok( !xCAT::BootUtils::grub2_image_provides( write_image('grub2.efionly', 'linuxefi'), 'linux' ),
    'a longer command name does not satisfy a shorter one' );
