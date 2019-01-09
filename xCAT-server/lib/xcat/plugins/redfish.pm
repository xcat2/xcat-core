#!/usr/bin/perl
### IBM(c) 2017 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::redfish;

BEGIN
    {
        $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
    }
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use Getopt::Long;
use xCAT::Usage;
use xCAT::SvrUtils;
use xCAT::AGENT;
use Data::Dumper;

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
    return {
        rbeacon        => 'nodehm:mgt',
        reventlog      => 'nodehm:mgt',
        rinv           => 'nodehm:mgt',
        rpower         => 'nodehm:mgt',
        rsetboot       => 'nodehm:mgt',
        rspconfig      => 'nodehm:mgt',
        rvitals        => 'nodehm:mgt',
    };
}

my %node_info = ();
my $callback;
$::VERBOSE = 0;

#-------------------------------------------------------

=head3  preprocess_request

  preprocess the command

=cut

#-------------------------------------------------------

sub preprocess_request {
    my $request = shift;
    $callback  = shift;
    my $command   = $request->{command}->[0];
    my $noderange = $request->{node};
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    my @requests;

    if (ref($extrargs)) {
        @exargs = @$extrargs;
    } 

    my $usage_string = xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({ data => [$usage_string] });
        $request = {};
        return;
    }

    my $parse_result = parse_args($command, $extrargs, $noderange);
    if (ref($parse_result) eq 'ARRAY') {
        my $error_data;
        foreach my $node (@$noderange) {
            $error_data .= "\n" if ($error_data);
            $error_data .= "$node: Error: " . "$parse_result->[1]";
        }
        $callback->({ errorcode => [$parse_result->[0]], data => [$error_data] });
        $request = {};
        return;
    }

    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, "xcat", "MN");
    foreach my $snkey (keys %$sn) {
        my $reqcopy = {%$request};
        $reqcopy->{node}                   = $sn->{$snkey};
        $reqcopy->{'_xcatdest'}            = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        push @requests, $reqcopy;
    }

    return \@requests;
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------

sub process_request {
    my $request = shift;
    $callback = shift;

    if (!xCAT::AGENT::exists_python_agent()) {
        xCAT::MsgUtils->message("E", { data => ["The xCAT Python agent does not exist. Check if xCAT-openbmc-py package is installed on management node and service nodes."] }, $callback);
        return;
    }

    my $noderange = $request->{node};
    my $check = xCAT::AGENT::parse_node_info($noderange, "redfish", \%node_info, $callback);
    $callback->({ errorcode => [$check] }) if ($check);
    return unless(%node_info);

    my $pid = xCAT::AGENT::start_python_agent();
    if (!defined($pid)) {
        xCAT::MsgUtils->message("E", { data => ["Failed to start the xCAT Python agent. Check /var/log/xcat/cluster.log for more information."] }, $callback);
        return;
    }

    xCAT::AGENT::submit_agent_request($pid, $request, "redfish", \%node_info, $callback);
    xCAT::AGENT::wait_agent($pid, $callback);
}

#-------------------------------------------------------

=head3  parse_args

  Parse the command line options and operands

=cut

#-------------------------------------------------------

sub parse_args {
    my $command  = shift;
    my $extrargs = shift;
    my $noderange = shift;
    my $subcommand = undef;

    unless (GetOptions(
        'V|verbose'  => \$::VERBOSE,
    )) {
        return ([ 1, "Error parsing arguments." ]);
    }

    if (scalar(@ARGV) >= 2 and ($command =~ /rbeacon|rpower|rvitals/)) {
        return ([ 1, "Only one option is supported at the same time for $command" ]);
    } elsif (scalar(@ARGV) == 0 and $command =~ /rbeacon|rspconfig|rpower/) {
        return ([ 1, "No option specified for $command" ]);
    } else {
        $subcommand = $ARGV[0];
    }

    if ($command eq "rpower") {
        unless ($subcommand =~ /^on$|^off$|^reset$|^boot$|^bmcreboot$|^bmcstate$|^status$|^stat$|^state$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } elsif ($command eq "rsetboot") {
        my $persistant;
        GetOptions('p'  => \$persistant);
        return ([ 1, "Only one option is supported at the same time for $command" ]) if (@ARGV > 1);
        $subcommand = "stat" if (!defined($ARGV[0]));
        unless ($subcommand =~ /^net$|^hd$|^cd$|^def$|^default$|^stat$|^setup$|^floppy$/) {
            return ([ 1, "Unsupported command: $command $subcommand" ]);
        }
    } else {
        return ([ 1, "Unsupported command: $command" ]);
    }
}

1;
