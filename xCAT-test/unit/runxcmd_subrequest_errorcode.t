#!/usr/bin/env perl
# The result of an internal subrequest is the errorcode of its responses. A plugin of the
# subrequest runs commands of its own, and xCAT::Utils::runcmd and the service helpers write
# the exit status of each one to $::RUNCMD_RC, so a caller that reads that global after the
# subrequest can read a command it never asked for.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

# xCAT::Utils puts $XCATROOT/lib/perl in front of @INC. On a host with xCAT installed that is
# the installed product, so point it at the checkout under test.
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server" }

use Test::More;
use xCAT::Utils;

my $request = { command => ['nodeset'], node => ['node1'], arg => ['osimage'] };

# makedhcp restarts dhcpd6 through xCAT::Utils::restartservice, which assigns the exit status
# of the restart to $::RUNCMD_RC. The stub writes the same value without running a command.
sub leftover_status {
    my ($status) = @_;
    return sub {
        my ( $req, $cb ) = @_;
        $cb->({ node => [ { name => ['node1'], data => ['netboot alma8.10-x86_64-compute'] } ] });
        $::RUNCMD_RC = $status;
        return;
    };
}

my $output = xCAT::Utils->runxcmd( $request, leftover_status(256), -1, 1 );
is( $::RUNCMD_RC, 0,
    'a subrequest whose responses carry no errorcode reports 0, whatever its commands returned' );
is_deeply( $output, ['node1: netboot alma8.10-x86_64-compute'],
    'the node response still reaches the caller' );

xCAT::Utils->runxcmd(
    $request,
    sub {
        my ( $req, $cb ) = @_;
        $cb->({ node => [ { name => ['node1'], error => ['no MAC address available'], errorcode => [1] } ] });
        return;
    },
    -1, 1
);
is( $::RUNCMD_RC, 1, 'the errorcode of a node response reaches the caller' );

xCAT::Utils->runxcmd(
    $request,
    sub {
        my ( $req, $cb ) = @_;
        $cb->({ error => ['unknown state requested'], errorcode => [2] });
        $::RUNCMD_RC = 0;
        return;
    },
    -1, 1
);
is( $::RUNCMD_RC, 2, 'a response errorcode survives a command that returned 0' );

# The hash form, which runxcmd collects with runxcmd_output2.
my $hash = xCAT::Utils->runxcmd( $request, leftover_status(1), -1, 2 );
is( $::RUNCMD_RC, 0, 'the hash form reports 0 for a subrequest that reported no error' );

done_testing();
