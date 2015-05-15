#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::switchdiscover;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use Getopt::Long;
use xCAT::Usage;
use xCAT::NodeRange;
use xCAT::Utils;
use XML::Simple;
no strict;
use Data::Dumper;

#global variables for this module
my %globalopt;
my @filternodes;
my %global_scan_type = (
    lldp => "lldp_scan",
    nmap => "nmap_scan",
    snmp => "snmp_scan"
);

#-------------------------------------------------------------------------------
=head1  xCAT_plugin:switchdiscover
=head2    Package Description
    Handles switch discovery functions. It uses lldp, nmap or snmap to scan
    the network to find out the switches attached to the network.
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

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
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
    return( {switchdiscover=>"switchdiscover"} );
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

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [$_[0], $usage_string] );
    };
    #############################################
    # No command-line arguments - use defaults
    #############################################
    if ( !defined( $args )) {
        return(0);
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    #############################################
    # Process command-line flags
    #############################################
    if (!GetOptions( \%opt,
            qw(h|help V|Verbose v|version x z w r n range=s s=s))) {
        return( usage() );
    }

    #############################################
    # Check for node range
    #############################################
    if ( scalar(@ARGV) eq 1 ) {
        my @nodes = xCAT::NodeRange::noderange( @ARGV );
        foreach (@nodes)  {
            push @filternodes, $_;
        }
        unless (@filternodes) {
            return(usage( "Invalid Argument: $ARGV[0]" ));
        }
		if ( exists( $opt{range} )) {
			return(usage( "--range flag cannot be used with noderange." ));
		}
    } elsif ( scalar(@ARGV) > 1 ) {
        return(usage( "Invalid flag, please check and retry." ));
    }

    #############################################
    # Option -V for verbose output
    #############################################
    if ( exists( $opt{V} )) {
        $globalopt{verbose} = 1;
    }

     #############################################
    # Check for mutually-exclusive formatting
    #############################################
    if ( (exists($opt{r}) + exists($opt{x}) + exists($opt{z}) ) > 1 ) {
        return( usage() );
    }

    #############################################
    # Check for unsupported scan types
    #############################################
    if ( exists( $opt{s} )) {
        my @stypes = split ',', $opt{s};
		my $error;
		foreach my $st (@stypes) {
			if (! exists($global_scan_type{$st})) {
				$error = $error . "Invalide scan type: $st\n";	
			}
        }
		if ($error) {
			return usage($error);
		}
        $globalopt{scan_types} = \@stypes;
	}

    #############################################
    # Check the --range ip range option
    #############################################
    if ( exists( $opt{range} )) {
        $globalopt{range} = $opt{range};
    }

    #############################################
    # write to the database
    #############################################
    if ( exists( $opt{w} )) {
        $globalopt{w} = 1;
    }

    #############################################
    # list the raw information
    #############################################
    if ( exists( $opt{r} )) {
        $globalopt{r} = 1;
    }

    #############################################
    # list the xml formate data
    #############################################
    if ( exists( $opt{x} )) {
        $globalopt{x} = 1;
    }

    #############################################
    # list the stanza formate data
    #############################################
    if ( exists( $opt{z} )) {
        $globalopt{z} = 1;
    }


    #########################################################
    # only list the nodes that discovered for the first time
    #########################################################
    if ( exists( $opt{n} )) {
        $globalopt{n} = 1;
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
    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }

    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
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
  
    ###########################################
    # Build hash to pass around
    ###########################################
    my %request;
    $request{arg}      = $req->{arg};
    $request{callback} = $callback;
    $request{command}  = $req->{command}->[0];

    ####################################
    # Process command-specific options
    ####################################
    my $result = parse_args( \%request );
    

    ####################################
    # Return error
    ####################################
    if ( ref($result) eq 'ARRAY' ) {
        send_msg( \%request, 1, @$result );
        return(1);
    }

    # call the relavant functions to start the scan 
	my @scan_types = ("lldp");
	if (exists($globalopt{scan_types})) {
		@scan_types = @{$globalopt{scan_types}};
	}
	
	my $all_result;
	foreach my $st (@scan_types) {
		no strict;
		my $fn = $global_scan_type{$st};
		my $tmp_result = &$fn(\%request, $callback);
		$all_result->{$st} = $tmp_result;
	}

    #consolidate the results by merging the swithes with the same ip
	my $result;
	foreach my $st (keys %$all_result) {
		my $tmp_result = $all_result->{$st};
		foreach my $key (keys %$tmp_result) {
			if (! exists($result->{$key})) {
				$result->{$key} = $tmp_result->{$key};
			} else {
				if (exists($tmp_result->{$key}->{name})) {
					$result->{$key}->{name} = $tmp_result->{$key}->{name};
				}
				if (exists($tmp_result->{$key}->{mac})) {
					$result->{$key}->{mac} = $tmp_result->{$key}->{mac};
				}
				if (exists($tmp_result->{$key}->{vendor})) {
					$result->{$key}->{vendor} .= $tmp_result->{$key}->{vendor};
				}
			}
		}
	}
		
	#display header
    $format = "%-12s\t%-12s\t%-20.20s\t%-12s";
	$header = sprintf $format, "ip", "name","vendor", "mac";
	send_msg(\%request, 0, $header);
	my $sep = "------------";
	send_msg(\%request, 0, sprintf($format, $sep, $sep, $sep, $sep ));

	#display switches one by one
	foreach my $key (keys(%$result)) {
		my $name="   ";
		my $mac = "   ";
		my $vendor = "   ";
		if (exists($result->{$key}->{name})) {
			$name = $result->{$key}->{name};
		}
		if (exists($result->{$key}->{mac})) {
			$mac = $result->{$key}->{mac};
		}
		if (exists($result->{$key}->{vendor})) {
			$vendor = $result->{$key}->{vendor};
		}
		my $msg = sprintf $format, $key, $name, $vendor, $mac;
		send_msg(\%request, 0, $msg);
	}

    # writes the data into xCAT db
	if (exists($globalopt{w})) {
		send_msg(\%request, 0, "Writing the data into xCAT DB....");
	}
    return;

}

#--------------------------------------------------------------------------------
=head3   lldp_scan
      Use lldpd to scan the subnets to do switch discovery.
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A hash containing the swithes discovered. 
        Each element is a hash of switch attributes. For examples:
        {
		   "1.2.3.5" =>{name=>"switch1", vendor=>"ibm", mac=>"AABBCCDDEEFA"},
		   "1.2.4.6" =>{name=>"switch2", vendor=>"cisco", mac=>"AABBCCDDEEFF"}
       } 
       returns 1 if there are errors occurred.
=cut
#--------------------------------------------------------------------------------
sub lldp_scan {
    my $request  = shift;

	send_msg($request, 0, "Discovering switches using lldpd...");

    # get the PID of the currently running lldpd if it is running.
    # If it is not running start it up.
    my $pid;
    chomp($pid= `ps -ef | grep lldpd | grep -v grep | awk '{print \$2}'`);
	unless($pid){
        my $dcmd = "lldpd -c -s -e -f";
        my $outref = xCAT::Utils->runcmd($dcmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            send_msg($request, 1, "Could not start lldpd process. The command was: $dcmd" );
            return 1;
        }
        # TODO: how to determin if the lldpd has done all the scanning or not?
        xCAT::Utils->runcmd("sleep 30");
	}

    #now run the lldpcli to collect the data
	my $ccmd = "lldpcli show neighbors -f xml";
	my $result = xCAT::Utils->runcmd($ccmd, 0);
	if ($::RUNCMD_RC != 0)
	{
		send_msg($request, 1, "Could not start lldpd process. The command was: $ccmd" );
		return 1;
	}

    #display the raw output
	if (exists($globalopt{r})) {
		send_msg($request, 0, "$result\n\n");
	}

    my $result_ref = XMLin($result, KeyAttr => 'interface', ForceArray => 1);
	my $switches; 
	if ($result_ref) {
		if (exists($result_ref->{interface})) {
			my $ref1 = $result_ref->{interface};
            foreach my $interface (@$ref1) {
				if (exists($interface->{chassis})) {
					my $chassis = $interface->{chassis}->[0];	
					my $ip = $chassis->{'mgmt-ip'}->[0]->{content};
					if ($ip) {
						my $name = $chassis->{name}->[0]->{content};
						my $id =  $chassis->{id}->[0]->{content};
						my $desc = $chassis->{descr}->[0]->{content};
						$switches->{$ip}->{name} = $name;
						$switches->{$ip}->{mac} =  $id;
						$switches->{$ip}->{vendor} = $desc;
					}
				}
			}
		}
	}
	return $switches
}


#--------------------------------------------------------------------------------
=head3   nmap_scan
      Use nmap to scan the subnets to do switch discovery.
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A hash containing the swithes discovered. 
        Each element is a hash of switch attributes. For examples:
        {
		   "1.2.3.5" =>{name=>"switch1", vendor=>"ibm", mac=>"AABBCCDDEEFA"},
		   "1.2.4.6" =>{name=>"switch2", vendor=>"cisco", mac=>"AABBCCDDEEFF"}
       } 
       returns 1 if there are errors occurred.
=cut
#--------------------------------------------------------------------------------
sub nmap_scan {
    my $request  = shift;

	send_msg($request, 0, "Discovering switches using nmap...");
	my $switches = {
		"1.2.3.5" => { name=>"switch1", vendor=>"ibm", mac=>"AABBCCDDEEFA" },
		"1.2.4.6" => { name=>"switch2", vendor=>"cisco", mac=>"AABBCCDDEEFF" }
     };
	return $switches
}



#--------------------------------------------------------------------------------
=head3   snmp_scan
      Use lldpd to scan the subnets to do switch discovery.
    Arguments:
       request: request structure with callback pointer.
    Returns:
        A hash containing the swithes discovered. 
        Each element is a hash of switch attributes. For examples:
        {
		   "1.2.3.5" =>{name=>"switch1", vendor=>"ibm", mac=>"AABBCCDDEEFA"},
		   "1.2.4.6" =>{name=>"switch2", vendor=>"cisco", mac=>"AABBCCDDEEFF"}
       } 
       returns 1 if there are errors occurred.
=cut
#--------------------------------------------------------------------------------
sub snmp_scan {
    my $request  = shift;

	send_msg($request, 0, "Discovering switches using snmp...");
	my $switches = {
		"1.2.3.5" => { name=>"switch1", vendor=>"ibm", mac=>"AABBCCDDEEFA" },
		"1.2.4.6" => { name=>"switch2", vendor=>"cisco", mac=>"AABBCCDDEEFF" }
     };
	return $switches
}

1;

