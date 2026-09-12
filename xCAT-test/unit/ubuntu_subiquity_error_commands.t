#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use Test::More;

# Subiquity waits for every error command to return before it reports the failure. The template
# used to offer the installer logs with "nc -l 8080", which waits for a collector that an
# unattended install never has, so a failed install stopped there: the node answered ping with no
# disk or network activity for as long as the provisioning timeout allowed, and the reason for the
# failure stayed on the node. That is how a missing grub-ieee1275 on ppc64el read as a wedged
# curtin extract.
#
# Run the error commands, with the programs that would reach the host or the network replaced, and
# check that they return and that they write the end of the curtin log where the caller points.

my $tmpl = "$FindBin::Bin/../../xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl";
plan skip_all => 'compute.subiquity.tmpl not found' unless -r $tmpl;

open(my $fh, '<', $tmpl) or die "open $tmpl: $!";
my $source = do { local $/; <$fh> };
close $fh;

my ($block) = $source =~ m{^  error-commands:\n((?:    [-#].*\n)+)}m;
BAIL_OUT('the template declares no error-commands') unless $block;

# One command per list item. The list form ['sh', '-c', '...'] carries the command in its last
# element; a plain item is the command itself.
my @commands;
foreach my $line (split /\n/, $block) {
    next unless $line =~ m{^    - (.*)$};
    my $item = $1;
    if ($item =~ m{^\['[^']+', '-c', '(.*)'\]$}) { push @commands, $1; }
    else                                         { push @commands, $item; }
}
BAIL_OUT('no error command found in the block') unless @commands;

my $root = tempdir(CLEANUP => 1);
my $console = "$root/console";
my $script  = "$root/error-commands.sh";

# nc, tar and tail are shadowed: bash resolves a function ahead of PATH, so the commands run as
# written while nothing reaches the host or the network. nc waits the way a listener with no
# collector waits.
open(my $out, '>', $script) or die "open $script: $!";
print {$out} "export XCAT_ERROR_CONSOLE='$console'\n";
print {$out} "nc() { sleep 300; }\n";
print {$out} "tar() { :; }\n";
print {$out} "tail() { echo XCAT_CURTIN_LOG_TAIL; }\n";
foreach my $command (@commands) {
    ( my $rendered = $command ) =~ s/#HOSTNAME#/testnode/g;
    # Subiquity runs each error command on its own, so a command that ends in "exit 0" must not
    # end the others.
    print {$out} "( $rendered )\n";
}
close $out;

my $rc = system('timeout', '10', 'bash', $script);
my $status = $rc == -1 ? -1 : $rc >> 8;
isnt( $status, 124, 'the error commands return instead of waiting for someone to collect the logs' );

my $written = '';
if (open(my $log, '<', $console)) { local $/; $written = <$log>; close $log; }
like( $written, qr/XCAT_CURTIN_LOG_TAIL/, 'and write the end of the curtin log to the console the installer names' );

done_testing();
