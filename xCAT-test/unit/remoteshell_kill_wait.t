#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $script = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT', 'postscripts', 'remoteshell' );
plan skip_all => 'remoteshell not found' unless -r $script;
plan skip_all => 'no bash'               unless -x '/bin/bash';

open( my $fh, '<', $script ) or die "Unable to read $script: $!";
my $source = do { local $/; <$fh> };
close($fh);

my ($loop) = $source =~ /(waited=0\n.*?\n      done)/s;
ok( defined($loop), 'the wait loop was found in the postscript' );

# Run the loop of the postscript against real processes, with a shorter bound
# so that the test does not spend the whole timeout of the postscript.
sub waits_for {
    my (@pids) = @_;
    ( my $body = $loop ) =~ s/\$waited -lt 10/\$waited -lt 3/;
    my $list = join( ' ', @pids );
    my $out = `/bin/bash -c 'PIDLIST="$list"\n$body\necho \$alive' 2>/dev/null`;
    chomp $out;
    return $out;
}

# A process that is still running must be reported as alive, and the loop must
# give up rather than run for ever.
my $child = fork();
if ( !defined $child ) { plan skip_all => 'cannot fork' }
if ( $child == 0 ) { exec( 'sleep', '30' ); exit 1 }
my $start = time;
is( waits_for($child), '1', 'a process that is still running is reported alive' );
cmp_ok( time - $start, '<', 10, 'the loop gives up instead of waiting for ever' );
kill 'KILL', $child;
waitpid( $child, 0 );

# A process that has ended must be reported as gone, without waiting.
my $gone = fork();
if ( $gone == 0 ) { exit 0 }
waitpid( $gone, 0 );
$start = time;
is( waits_for($gone), '0', 'a process that has ended is reported gone' );
cmp_ok( time - $start, '<', 3, 'no time is spent once the process is gone' );

# The bound of the postscript itself, and the shape of the test.
like( $source, qr/while \[ \$waited -lt 10 \]/, 'the postscript waits at most ten seconds' );
like( $source, qr/kill -0 \$pid/, 'the check for a running process sends no signal' );
like( $source, qr/kill -9 \$PIDLIST/, 'the daemon still gets the signal it cannot catch' );

# The wait has to happen before the new daemon starts.
my ($block) = $source =~ /(PIDLIST=.*?\/usr\/sbin\/sshd)/s;
ok( defined($block), 'the fallback block was found' );
cmp_ok( index( $block, 'waited=0' ), '<', index( $block, '/usr/sbin/sshd' ),
    'the wait comes before the new daemon starts' );

done_testing();
