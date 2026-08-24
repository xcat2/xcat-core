#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $plugin = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'xcat', 'plugins', 'mknb.pm' );
plan skip_all => 'mknb.pm not found' unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# mknb.pm needs a management node to load, so lift the routine out and drive
# the real code on its own.
my ($routine) = $source =~ /(sub genesis_lzma_command \{.*?\n\}\n)/s;
BAIL_OUT('could not extract genesis_lzma_command from mknb.pm') unless $routine;
eval "package MknbCompressor; $routine 1;" or BAIL_OUT("could not evaluate: $@");

sub command { return MknbCompressor::genesis_lzma_command(@_); }

# Debian and Ubuntu ship both names, and lzma is the one the plugin has always
# used, so nothing changes on those systems.
is( command( 1, 1 ), 'lzma -C crc32 -9', 'lzma is used when it is there' );

# Red Hat ships xz alone.
is( command( 0, 1 ), 'xz --format=lzma -C crc32 -9',
    'xz stands in for lzma when only xz is there' );

# The gzip path below the caller handles a system with neither.
is( command( 0, 0 ), undef, 'nothing is returned when neither program is there' );

# The container has to stay the one the file name promises. "xz" on its own
# writes the xz container, which the file name does not describe and which a
# reader of a .lzma file cannot open.
my ($xz_form) = command( 0, 1 ) =~ /--format=(\S+)/;
is( $xz_form, 'lzma', 'xz is asked for the lzma container, not its own' );

# The caller has to take the command from the routine, and the name of the
# written file must not change with it.
like( $source, qr/genesis_lzma_command\(-x "\/usr\/bin\/lzma", -x "\/usr\/bin\/xz"\)/,
    'the caller asks the routine which program to run' );
like( $source, qr/cpio -o -H newc \| \$lzma_command > \$tftpdir\/xcat\/genesis\.fs\.\$arch\.lzma\.\$suffix/,
    'the chosen command writes the same file under the same suffix' );

# The fallback to gzip and the atomic rename both have to survive.
like( $source, qr/falling back to gzip/, 'the gzip fallback is still reported' );
like( $source, qr/move\("\$tftpdir\/xcat\/genesis\.fs\.\$arch\.lzma\.\$suffix"/,
    'the finished image is still renamed into place' );

done_testing();
