#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::openbmc;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::GlobalDef;
use xCAT::NodeRange;
use xCAT::Table;
use xCAT::Usage;
use XML::LibXML; #now that we are in the business of modifying xml data, need something capable of preserving more of the XML structure

use xCAT::Utils qw/genpassword/;
use File::Basename qw/fileparse/;
use File::Path qw/mkpath/;
use IO::Socket;
use IO::Select;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use strict;

#use warnings;
my %vm_comm_pids;
my $parser;

use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw store_fd fd_retrieve);
use IO::Select;
use IO::Handle;
use Time::HiRes qw(gettimeofday sleep);
use xCAT::DBobjUtils;
use Getopt::Long;
use xCAT::SvrUtils;

my $callback;
my $requester;    #used to track the user
my $doreq;
my $node;

sub handled_commands {
    return {
        rpower   => 'nodehm:power,mgt',
        rinv     => 'nodehm:power,mgt',
    };
}


sub rinv {
    shift;
    xCAT::SvrUtils::sendmsg("OpenBMC: rinv", $callback, $node);
}

sub power {
    @ARGV = @_;
    my $subcommand_hash = shift @ARGV;
    my $subcommand = $subcommand_hash->[0];
    my $retstring;
    if ($subcommand eq "boot") {
    }
    my $errstr;

    if ($subcommand eq 'on') {
        xCAT::SvrUtils::sendmsg([0, "OpenBMC: rpower on"], $callback, $node);
    } elsif ($subcommand eq 'off') {
        xCAT::SvrUtils::sendmsg("OpenBMC: rpower off", $callback, $node);
    } elsif ($subcommand eq 'softoff') {
        xCAT::SvrUtils::sendmsg("OpenBMC: rpower softoff", $callback, $node);
    } elsif ($subcommand eq 'reset') {
        xCAT::SvrUtils::sendmsg("OpenBMC: rpower reset", $callback, $node);
    } elsif ($subcommand eq 'stat') {
        xCAT::SvrUtils::sendmsg([ 0, "OpenBMC get status. Issue the following from command line:" ], $callback, $node);
        xCAT::SvrUtils::sendmsg([ 0, "    Provide login credentials" ], $callback, $node);
        xCAT::SvrUtils::sendmsg([ 0, '        curl -c cjar -b cjar -k -H "Content-Type: application/json" -X POST https://' . $node . '/login -d "{\"data\": [ \"root\", \"0penBmc\" ] }"' ], $callback, $node);
        xCAT::SvrUtils::sendmsg([ 0, "    Get status" ], $callback, $node);
        xCAT::SvrUtils::sendmsg([ 0, '        curl -c cjar -b cjar -k -H "Content-Type: application/json" -X POST https://' . $node . '/xyz/openbmc_project/state/host0' ], $callback, $node);
    } else {
        return (1, "Unsupported power directive '$subcommand'");
    }
    return (0, $retstring);
}

sub guestcmd {
    $node = shift;
    my $command = shift;
    my %namedargs = @_;
    my @exargs    = @{ $namedargs{-args} };
    my @args    = \@exargs;
    my $error;
    if ($command eq "rpower") {
        return power(@args);
    } elsif ($command eq "rinv") {
        return rinv($node, @args);
    }

    return (1, "$command not a supported command by openbmc method");
}

sub preprocess_request {
    my $request = shift;
    if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
    $callback = shift;
    my @requests;

    my $noderange = $request->{node};           #Should be arrayref
    my $command   = $request->{command}->[0];
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    my $usage_string = xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({ data => $usage_string });
        $request = {};
        return;
    }

    if (!$noderange) {
        $usage_string = xCAT::Usage->getUsage($command);
        $callback->({ data => $usage_string });
        $request = {};
        return;
    }

    #print "noderange=@$noderange\n";

    # find service nodes for requested nodes
    # build an individual request for each service node
    my $service = "xcat";
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, $service, "MN");

    # build each request for each service node

    foreach my $snkey (keys %$sn)
    {
        my $reqcopy = {%$request};
        $reqcopy->{node}                   = $sn->{$snkey};
        $reqcopy->{'_xcatdest'}            = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        push @requests, $reqcopy;
    }
    return \@requests;
}


sub process_request {
    my $request = shift;
    $callback = shift;
    $doreq = shift;
    $SIG{INT} = $SIG{TERM} = sub {
        foreach (keys %vm_comm_pids) {
            kill 2, $_;
        }
        exit 0;
    };
    unless ($parser) {
        $parser = XML::LibXML->new();
    }
    my $level     = shift;
    my $noderange = $request->{node};
    my $command   = $request->{command}->[0];
    my @exargs;
    unless ($command) {
        return;    #Empty request
    }
    if (ref($request->{arg})) {
        @exargs = @{ $request->{arg} };
    } else {
        @exargs = ($request->{arg});
    }
    guestcmd($noderange->[0], $command, -args => \@exargs);
}

1;
