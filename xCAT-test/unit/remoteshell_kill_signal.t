#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $script = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT', 'postscripts', 'remoteshell' );
plan skip_all => 'remoteshell not found' unless -r $script;

open( my $fh, '<', $script ) or die "Unable to read $script: $!";
my $source = do { local $/; <$fh> };
close($fh);

# A kill without the hyphen reads the signal number as one more process id, so
# the target gets the default signal, which a process can catch, and the
# process with that id is signalled as well.
my @bare = ( $source =~ /^[^#\n]*\bkill\s+\d/gm );
is( scalar(@bare), 0, 'no kill gives the signal number without a hyphen' );

like( $source, qr/kill -9 \$PIDLIST/,
    'the ssh daemon gets the signal that a process cannot catch' );

done_testing();
