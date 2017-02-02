# IBM(c) 2016 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

    xCAT plugin to support z/VM (s390x) diagnostics command

=cut

#-------------------------------------------------------
package xCAT_plugin::zvmdiagnostics;

#use xCAT::Client;
use xCAT::zvmUtils;

#use xCAT::zvmCPUtils;
#use xCAT::MsgUtils;
use Sys::Hostname;

#use xCAT::Table;
#use xCAT::Utils;
#use xCAT::TableUtils;
#use xCAT::ServiceNodeUtils;
#use xCAT::NetworkUtils;
#use XML::Simple;
#use File::Basename;
#use File::Copy;
#use File::Path;
#use File::Temp;
use Time::HiRes;
use POSIX;
use Getopt::Long;
use strict;
use warnings;

#use Cwd;
# Set $DEBUGGING = 1 to get extra message logging
my $DEBUGGING = 0;

# Common prefix for log messages
my $ROUTINE = "zvmdiagnostics";
my $COMMAND = "diagnostics";

my $NOTIFY_FILENAME = "/var/lib/sspmod/appliance_system_role";
my $NOTIFY_KEYWORD = "notify";
my $NOTIFY_KEYWORD_DELIMITER = "=";

# If the following line ("1;") is not included, you get:
# /opt/xcat/lib/perl/xCAT_plugin/... did not return a true value
# where ... is the name of this file
1;

#-------------------------------------------------------

=head3  handled_commands

    Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return { $COMMAND => $ROUTINE, };
}

#-------------------------------------------------------

=head3  preprocess_request

    Check and setup for hierarchy

=cut

#-------------------------------------------------------
sub preprocess_request {
    my $req      = shift;
    my $callback = shift;
    my $SUBROUTINE = "preprocess_request";

    # Hash array
    my %sn;

    # Scalar variable
    my $sn;

    # Array
    my @requests;

    if ( $DEBUGGING == 1 ) {
        xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE entry");
    }

    # If already preprocessed, go straight to request
    if ( $req->{_xcatpreprocessed}->[0] == 1 ) {
        return [$req];
    }
    my $nodes   = $req->{node};
    my $service = "xcat";

    # Find service nodes for requested nodes
    # Build an individual request for each service node
    if ($nodes) {
        $sn = xCAT::ServiceNodeUtils->get_ServiceNode( $nodes, $service, "MN" );

        # Build each request for each service node
        foreach my $snkey ( keys %$sn ) {
            my $n = $sn->{$snkey};
            print "snkey=$snkey, nodes=@$n\n";
            my $reqcopy = {%$req};
            $reqcopy->{node}                   = $sn->{$snkey};
            $reqcopy->{'_xcatdest'}            = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;
        }

        return \@requests;
    }
    else {

        # Input error
        my %rsp;
        my $rsp;
        $rsp->{data}->[0] =
          "Input noderange missing. Usage: $ROUTINE <noderange> \n";
        xCAT::MsgUtils->message( "I", $rsp, $callback, 0 );
        return 1;
    }
}

#-------------------------------------------------------

=head3  process_request

    Process the command.  This is the main call.

=cut

#-------------------------------------------------------
sub process_request {
    my $SUBROUTINE = "process_request";
    my $request  = shift;
    my $callback = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    $::STDIN = $request->{stdin}->[0];
    my %rsp;
    my $rsp;
    my @nodes = @$nodes;
    my $host  = hostname();

    if ( $DEBUGGING == 1 ) {
        xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE entry");
    }

    # Process ID for xfork()
    my $pid;

    # Child process IDs
    my @children = ();

    #*** Collect or manage diagnostics***
    if ( $command eq $COMMAND ) {
        foreach (@nodes) {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid) {
                push( @children, $pid );
            }

            # Child process
            elsif ( $pid == 0 ) {
                if ( xCAT::zvmUtils->isHypervisor($_) ) {
                    #TODO should this be handled inside the subroutine, ala rmvm?
                    if ( $DEBUGGING == 1 ) {
                          xCAT::zvmUtils->printSyslog("$ROUTINE for hypervisor - semantically coherent?");
                    }
                }
                else {
                    collectDiags( $callback, $_, $args );
                }

                # Exit process
                exit(0);
            }
            else {

                # Ran out of resources
                die "Error: Could not fork\n";
            }

        }    # End of foreach
    }    # End of case

    # Wait for all processes to end
    foreach (@children) {
        waitpid( $_, 0 );
    }

    return;
}

#-------------------------------------------------------

=head3  collectDiags

    Description  : Collect diagnostics
    Arguments    : Node to collect diagnostics about
    Returns      : Nothing
    Example      : collectDiags($callback, $node);

=cut

#-------------------------------------------------------
sub collectDiags {
    my $SUBROUTINE = "collectDiags";

    # Get inputs
    my ( $callback, $node, $args ) = @_;
    my $rc;

    if ( $DEBUGGING == 1 ) {
          xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE entry");
    }

    # Get node properties from 'zvm' table
    my @propNames = ( 'hcp', 'userid', 'discovered' );
    my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

    # Get zHCP
    my $hcp = $propVals->{'hcp'};
    if ( !$hcp ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
        return;
    }

    # Get node user ID
    my $userId = $propVals->{'userid'};
    if ( !$userId ) {
        xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing user ID" );
        return;
    }

    # Capitalize user ID
    $userId =~ tr/a-z/A-Z/;

    if ( $DEBUGGING == 1 ) {
        xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE sudoer:$::SUDOER zHCP:$hcp sudo:$::SUDO userid:$::userId");
    }
    my $out;

    my $requestId   = "NoUpstreamRequestID";
    my $objectId    = "NoUpstreamObjectID";
    my $projectName = "NoUpstreamProjectName";
    my $userUuid    = "NoUpstreamUserUuid";
    if ($args) {
        @ARGV = @$args;
        xCAT::zvmUtils->printSyslog(
            "$ROUTINE $SUBROUTINE for node:$node on zhcp:$hcp args @$args");

        # Parse options
        GetOptions(
            'requestid=s' => \$requestId    # Optional
            , 'objectid=s' => \$objectId    # Optional
        );
    }

    my $xcatnotify = "OPERATOR";  # Default value
    my $xcatnotify_found = 0;     # Not found yet
    my (@array, $varname);
    open( FILE, "<$NOTIFY_FILENAME" );
    #TODO If file not found ("should never happen"), log error but continue
    while (<FILE>) {
        # Find record in file with NOTIFY=something on it, optionally delimited with whitespace
        next unless ( /^[\s]*$NOTIFY_KEYWORD[\s]*$NOTIFY_KEYWORD_DELIMITER[\s]*(\S+)[\s]*$/iaa );
        $xcatnotify_found = 1;
        $xcatnotify = $1;  # First parenthesized expression in regex above, that is: \S+
        if ( $DEBUGGING == 1 ) {
            xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE xCAT will notify $xcatnotify.");
        }
        last; # Ignore anything past the first matching record.  Absent a bug elsewhere, there is only one value to find.
    }
    close(FILE);
    if (not $xcatnotify_found) {
        xCAT::zvmUtils->printSyslog(
            "$ROUTINE $SUBROUTINE error: failed to parse $NOTIFY_KEYWORD$NOTIFY_KEYWORD_DELIMITER " .
            "from $NOTIFY_FILENAME, defaulting to notify $xcatnotify");
    }
    #TODO add COZ... message ID
    my $msg = "vmcp MSG $xcatnotify deployment failed: node $node userid $userId on zHCP $hcp";
    xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE $msg");
    system($msg);
    #TODO check system()'s rc
    
    #TODO Capture diagnostic files

    xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE ... rest of implementation stubbed out ");

    if ( $DEBUGGING == 1 ) {
        xCAT::zvmUtils->printSyslog("$ROUTINE $SUBROUTINE exit");
    }
    return;
}

