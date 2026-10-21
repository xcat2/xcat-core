#!/usr/bin/env perl
# makedhcp holds the DHCP lock while it reads omshell output, and stops the read at a deadline. omshell
# writes its prompt without a newline, so a line read waits past that deadline for an omshell that stalls.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;
use Time::HiRes qw(time);

$ENV{XCATCFG} ||= 'SQLite:/tmp';
my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

my $dir     = tempdir( CLEANUP => 1 );
my $omshell = "$dir/omshell";
open( my $fh, '>', $omshell ) or die "Cannot create $omshell: $!";
print {$fh} "#!/bin/sh\necho \$\$ > '$dir/pid'\nprintf '> '\nexec sleep 60\n";
close($fh) or die "Cannot close $omshell: $!";
chmod 0755, $omshell or die "Cannot make $omshell executable: $!";

my $pid;
END { kill 'KILL', $pid if $pid; }

my @output;
my $started  = time;
my $returned = eval {
    local $SIG{ALRM} = sub { die "the omshell read did not return\n" };
    alarm 30;
    @output = xCAT_plugin::dhcp::_run_omshell( "connect\n", { omshell_path => $omshell } );
    alarm 0;
    1;
};
alarm 0;
my $elapsed = time - $started;

if ( open( my $pidfh, '<', "$dir/pid" ) ) {
    ($pid) = <$pidfh> =~ /^(\d+)/;
    close($pidfh);
}

ok( $returned, 'an omshell that stalls after its prompt returns the read' ) or diag($@);
cmp_ok( $elapsed, '<', 20, 'at the deadline of the read' );
is_deeply( \@output, ['> '], 'with the prompt that omshell wrote' );
ok( $pid && !kill( 0, $pid ), 'and stops that omshell' ) and $pid = undef;

done_testing();
