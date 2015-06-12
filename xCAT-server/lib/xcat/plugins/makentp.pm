#!/usr/bin/env perl
# IBM(c) 2015 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::makentp;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use Getopt::Long;
use xCAT::Usage;
use xCAT::NetworkUtils;
use xCAT::TableUtils;
use xCAT::Utils;
use XML::Simple;
no strict;
use Data::Dumper;
use Socket;

my %globalopt;

#-------------------------------------------------------------------------------
=head1  xCAT_plugin:makentp
=head2    Package Description
    Handles ntp server setup on a xCAT management node.
=cut
#-------------------------------------------------------------------------------


#--------------------------------------------------------------------------------
=head3   send_msg
      Invokes the callback with the specified message
    Arguments:
        request: request structure for plguin calls
        ecode: error code. 0 for succeful.
        msg: messages to be displayed.
    Returns:
        none
=cut
#--------------------------------------------------------------------------------
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my $msg     = shift;
    my %output;

    # Called from child process - send to parent
     if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    # Called from parent - invoke callback directly
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};
        $output{errorcode} = $ecode;
        $output{data} = $msg;
        $callback->( \%output );
    }
}


#--------------------------------------------------------------------------------
=head3   handled_commands
      It returns a list of commands handled by this plugin.
    Arguments:
       none
    Returns:
       a list of commands.
=cut
#--------------------------------------------------------------------------------
sub handled_commands {
    return( {makentp=>"makentp"} );
}


#--------------------------------------------------------------------------------
=head3   parse_args
      Parse the command line options and operands.
    Arguments:
        request: the request structure for plugin
    Returns:
        Usage string or error message.
        0 if no user promp needed.

=cut
#--------------------------------------------------------------------------------
sub parse_args {

    my $request  = shift;
    my $args     = $request->{arg};
    my $cmd      = $request->{command};
    my %opt;

    # Responds with usage statement
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [$_[0], $usage_string] );
    };

    # No command-line arguments - use defaults
    if ( !defined( $args )) {
        return(0);
    }

    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    # Process command-line flags
    if (!GetOptions( \%opt,
            qw(h|help V|Verbose v|version a|all))) {
        return( usage() );
    }

    # Option -V for verbose output
    if ( exists( $opt{V} )) {
        $globalopt{verbose} = 1;
    }

    if ( exists( $opt{a} )) {
        $globalopt{a} = 1;
    }

    return;
}


#--------------------------------------------------------------------------------
=head3   preprocess_request
      Parse the arguments and display the usage or the version string. 

=cut
#--------------------------------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;

    my $command = $req->{command}->[0];
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }

    # Build hash to pass around
    my %request;
    $request{arg}      = $extrargs;
    $request{callback} = $callback;
    $request{command}  = $command;

    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }

    my $result = parse_args( \%request );
    if ( ref($result) eq 'ARRAY' ) {
        send_msg( \%request, 1, @$result );
        return(1);
    }
    
    # add current request
    my @result = ();
    my $reqcopy = {%$req};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    push @result, $reqcopy;


    # if on mn and with -a flag, go to the service node that has 
    # ntpserver=1.
    if (xCAT::Utils->isMN() && exists($globalopt{a})) {
        my @servicenodes = xCAT::ServiceNodeUtils->getSNList('ntpserver');
        send_msg(\%request, 0, "servicenodes=@servicenodes" );
        foreach my $sn (@servicenodes) {
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'}=$sn;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @result, $reqcopy;
        }
    }

    return \@result;
}

#--------------------------------------------------------------------------------
=head3   process_request
    Pasrse the arguments and call the correspondent functions
    to do switch discovery. 

=cut
#--------------------------------------------------------------------------------
sub process_request {
    my $req      = shift;
    my $callback = shift;
    my $sub_req  = shift;
  
    # Build hash to pass around
    my %request;
    $request{arg}      = $req->{arg};
    $request{callback} = $callback;
    $request{command}  = $req->{command}->[0];

    my @nodeinfo   = xCAT::NetworkUtils->determinehostname();
    my $nodename   = pop @nodeinfo; 

    #check if ntp is installed or not
    if (!-f "/usr/sbin/ntpd") {
        send_msg(\%request, 1, "Please make sure ntpd is installed on $nodename.");
        return 1;
    }
    
    #configure the ntp configuration file
    my $ntpcfg = "/etc/ntp.conf";
    my $ntpcfgbackup     = "/etc/ntp.conf.orig";
    my $ntpxcatcfgbackup = "/etc/ntp.conf.xcatbackup";
    if (-e $ntpcfg) {
        if (!-e $ntpcfgbackup) {    
            # if original backup does not already exist
            my $cmd = "mv $ntpcfg $ntpcfgbackup";
            my $result = xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0) {
                send_msg(\%request, 1, "Error from command:$cmd");
                return 1;
            }
        }
        else {    
            # backup xcat cfg
            my $cmd = "mv $ntpcfg $ntpxcatcfgbackup";
            my $result = xCAT::Utils->runcmd($cmd, 0);
            system $cmd;
            if ($::RUNCMD_RC != 0) {
                send_msg(\%request, 1, "Error from command:$cmd");
                return 1;
            }
        }
    }

    # get site.extntpservers for mn, for sn use mn as the server
    my $ntp_servers;
    if (xCAT::Utils->isMN()) {
        my @entries = xCAT::TableUtils->get_site_attribute("extntpservers");
        $ntp_servers = $entries[0];
    } else {
        my $retdata = xCAT::ServiceNodeUtils->readSNInfo($nodename);
        $ntp_servers = $retdata->{'master'};
    }

    # create ntp server config file
    open(CFGFILE, ">$ntpcfg")
        or xCAT::MsgUtils->message('SE',
                                   "Cannot open $ntpcfg for NTP update. \n");

    if (defined($ntp_servers) && $ntp_servers) {
        my @npt_server_array = split(',', $ntp_servers);
        # add ntp servers one by one
        foreach my $ntps (@npt_server_array) {
            print CFGFILE "server ";
            print CFGFILE "$ntps\n";
        }
    }
    #add xCAT mn/sn itself as a server
    print CFGFILE "server 127.127.1.0\n";
    print CFGFILE "fudge 127.127.1.0 stratum 10\n";
 
    print CFGFILE "driftfile /var/lib/ntp/drift\n";
    close CFGFILE;

    #restart ntp
    my $rc=xCAT::Utils->startservice("ntpd");
    if ($rc != 0) {
        return 1;
    }
    return;
}


1;

