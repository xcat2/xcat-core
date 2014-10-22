# IBM(c) 2009 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCenergy;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use Getopt::Long;
use xCAT::Usage;
use xCAT::NodeRange;
use xCAT::DBobjUtils;
use xCAT::FSPUtils;
use xCAT::TableUtils;
%::QUERY_ATTRS = (
'savingstatus' => 1,
'dsavingstatus' => 1,
'cappingstatus' => 1,
'cappingmaxmin' => 1,
'cappingvalue' => 1,
'cappingsoftmin' => 1,
'averageAC' => 1,
'averageDC' => 1,
'ambienttemp' => 1,
'exhausttemp' => 1,
'CPUspeed' => 1,
'syssbpower' => 1,
'sysIPLtime' => 1,
# for FFO, only supported when communicating to fsp directly
'ffoMin' => 1,
'ffoVmin' => 1,
'ffoTurbo' => 1,
'ffoNorm' => 1,
'fsavingstatus' => 1,
'ffovalue' => 1,
);

%::SET_ATTRS = (
'savingstatus' => 1,
'dsavingstatus' => 1,
'cappingstatus' => 1,
'cappingwatt' => 1,
'cappingperc' => 1,
# for FFO
'fsavingstatus' => 1,
'ffovalue' => 1,
);

$::CIM_CLIENT_PATH = "$::XCATROOT/sbin/xCAT_cim_client";

# Parse the arguments of the command line for renergy command
sub parse_args {
    my $request = shift;

    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my $nodes   = $request->{node};

    my $query_attrs = ();   # The attributes list for query operation
    my $set_pair = ();      # The attribute need to be set. e.g. savingstatus=on
    my $set_flag = ();      # Indicate there's setting param in the argv  
    my $argv_flag = ();     # Indicate there's param in the argv
    my @notfspnodes = ();    # The nodes list which are not fsp

    # set the usage subroutine
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [ $_[0], $usage_string ] );
    };

    if ($request->{arg}) {
        @ARGV = @{$request->{arg}};
        $Getopt::Long::ignorecase = 0;
        Getopt::Long::Configure( "bundling" );

        if ($nodes) {
            if (!GetOptions( 'V'     => \$::VERBOSE )) {
                return (&usage());
            }

            if ($::VERBOSE) {
                $opt{verbose} = 1;
            }

            if ($#ARGV < 0) {
                return (&usage());
            }

            # Check the validity of the parameters of Query and Set
            foreach my $attr (@ARGV) {
                my ($set_attr, $set_value) = split (/=/, $attr);
                if (defined($set_value)) {
                    if ($argv_flag) {
                        return (&usage());
                    }
                    if ($::SET_ATTRS{$set_attr} != 1) {
                        return (&usage());
                    }
    
                    if (($set_attr eq "savingstatus" || $set_attr eq "fsavingstatus") 
                         && ($set_value ne "on" && $set_value ne "off")) {
                        return (&usage());
                    } elsif ($set_attr eq "dsavingstatus"
                         && ($set_value ne "off"
                             && $set_value ne "on-norm" && $set_value ne "on-maxp")) {
                        return (&usage());
                    } elsif ($set_attr eq "cappingstatus" 
                         && ($set_value ne "on" && $set_value ne "off")) {
                        return (&usage());
                    } elsif ( ($set_attr eq "cappingwatt"  
                         || $set_attr eq "cappingperc" ||  $set_attr eq "ffovalue")
                           && $set_value =~ /\D/) {
                        return (&usage());
                    }
    
                    $set_pair = $set_attr."=".$set_value;
                    $set_flag = 1;
                } else {
                    if ($set_flag) {
                        return (&usage());
                    }
                }

                $argv_flag = 1;
            }

            if (!$set_flag) {
                my @query_list = @ARGV;
           
                if ($query_list[0] eq "all" and $#query_list == 0) {
                    $query_attrs = "all";
                } else {
                    my @no_dup_query_list = ();
                    foreach my $q_attr (@query_list) {
                        chomp($q_attr);
   
                        if ($::QUERY_ATTRS{$q_attr} != 1) {
                            return (&usage());
                        }

                        if (!grep (/^$q_attr$/, @no_dup_query_list)) {
                            push @no_dup_query_list, $q_attr;
                        }
                    }
                    $query_attrs = join (',', @no_dup_query_list);
                }
            }
        } else {
            # If has not nodes, the -h or -v option must be input
            if (!GetOptions( 'h|help'     => \$::HELP,
                             'v|version'  => \$::VERSION)) {
                return (&usage());
            }
            
            if (! ($::HELP || $::VERSION) ) {
                return (&usage());
            }
            if ($::HELP) {
                return (&usage());
            }
            
            if ($::VERSION) {
                my $version_string = xCAT::Usage->getVersion('renergy');
                return( [ $_[0], $version_string] );
            }

            if (scalar(@ARGV)) {
                return (&usage());
            }
        }
    } else {
        return (&usage());
    }

    # Check whether the hardware type of nodes are fsp or cec
    #my $nodetype_tb = xCAT::Table->new('nodetype');
    #unless ($nodetype_tb) {
    #    return ([undef, "Error: Cannot open the nodetype table"]);
    #}

    #my $nodetype_v = $nodetype_tb->getNodesAttribs($nodes, ['nodetype']);
    my $nodetyperef = xCAT::DBobjUtils->getnodetype($nodes, "ppc");  
    my $i = 0;
    foreach my $node (@{$nodes}) {
        if ($$nodetyperef{$node} ne 'fsp' &&
            $$nodetyperef{$node} ne 'cec') {
            push @notfspnodes, $node;
        }
        $i++;
    }
    #$nodetype_tb->close();

    if (@notfspnodes) {
        return ([undef, "Error: The hardware type of following nodes are not fsp or cec: ".join(',', @notfspnodes)]);
    }

    if ($query_attrs) {
        $opt{'query'} = $query_attrs;
    } elsif ($set_pair) {
        $opt{'set'} = $set_pair;
    }

    $request->{method} = $cmd;
    return (\%opt);
}

# Handle the energy query and setting work
sub renergy {
    my $request = shift;
    my $hcphost = shift;
    my $nodehash = shift;

    my @return_msg = ();

    my $opt = $request->{'opt'};
    my $verbose = $opt->{'verbose'};

    # Get the CEC 
    my ($node, $attrs) = %$nodehash;
    my $cec_name = @$attrs[2];
    my $hw_type = @$attrs[4];
    
    if (!$cec_name) {
        return ([[$node, "ERROR: Cannot find the cec name, check the attributes: vpd.serial, vpd.mtm.", 1]]);
    }

    # Check the existence of cim client
    if ( (! -f $::CIM_CLIENT_PATH)
      || (! -x $::CIM_CLIENT_PATH) ) {
        return ([[$node, "ERROR: Cannot find the Energy Management Plugin for xCAT [$::CIM_CLIENT_PATH] or it's NOT executable. Please install the xCAT-cimclient package correctly. Get more information from man page of renergy command.", 1]]);
    }

    my $verb_arg = "";
    if ($verbose) {
        $verb_arg = "-V";
    }

    # get the user and passwd for hcp: hmc, fsp, cec
    my $hcp_type = xCAT::DBobjUtils->getnodetype($hcphost, "ppc");
    my $user;
    my $password;
    if ($hcp_type eq "hmc") {
        ($user, $password) = xCAT::PPCdb::credentials($hcphost, $hcp_type);
    } else { 
        ($user, $password) = xCAT::PPCdb::credentials($hcphost, $hcp_type,'HMC');   
    }

    my $fsps;  #The node of fsp that belong to the cec
    my @hcps_ip;
    if ($hcp_type ne "hmc" && $hw_type eq "cec") {
        $fsps = xCAT::DBobjUtils->getchildren($node);
        if( !defined($fsps) ) {
            return ([[$node, "Failed to get the FSPs for the cec $hcphost.", -1]]);
        }
        #my $hcp_ip = xCAT::NetworkUtils::getNodeIPaddress($hcphost);
        my $hcp_ip = xCAT::FSPUtils::getIPaddress($request, $hw_type, $hcphost);
        if (!defined($hcp_ip) or ($hcp_ip == -3)) {
            return ([[$node, "Failed to get IP address for $hcphost.", -1]]);
        }
        push @hcps_ip, split(',', $hcp_ip);
        my $fsp_node = $$fsps[0];
        ($user, $password) = xCAT::PPCdb::credentials( $fsp_node, "fsp",'HMC');
        if ( !$password) {
            return ([[$node, "Cannot get password of userid 'HMC'. Please check table 'ppchcp' or 'ppcdirect'.", -1]]);
        }
    } else {
        # for the case that hcp is hmc or fsp
        push @hcps_ip, xCAT::NetworkUtils::getNodeIPaddress($hcphost);
    }

    if (!$user || !$password) {
        return ([[$node, "Cannot get user:password for the node. Please check table 'ppchcp' or 'ppcdirect'.", -1]]);
    }

    # secure passwd in verbose mode
    my $tmpv = $verbose;
    $verbose = 0;
    if ($verbose) {
        push @return_msg, [$node, "Attributes of $node:\n User=$user\n Password=$password\n CEC=$cec_name\n nodetype=$hw_type\n inithcp=$hcphost\n hcps=@hcps_ip\n hcptype=$hcp_type", 0];
    }
    $verbose = $tmpv;

    my @pingable_hcp;
    if (-x '/usr/bin/nmap' or -x '/usr/local/bin/nmap') { #use nmap
	#print "use nmap\n";
	if ($verbose) {
	    push @return_msg, [$node, "Checking ping status using nmap for @hcps_ip", 0];
	}
	my %deadnodes;
	foreach (@hcps_ip) {
	    $deadnodes{$_}=1;
	}	 

	# get additional options from site table
	my @nmap_options = xCAT::TableUtils->get_site_attribute("nmapoptions"); 
	my $more_options = $nmap_options[0];

	open (NMAP, "nmap -PE --system-dns --send-ip -sP $more_options ". join(' ',@hcps_ip) . " 2> /dev/null|") or die("Cannot open nmap pipe: $!");
	my $node;
	while (<NMAP>) {
	    #print "$_\n";
	    if (/Host (.*) \((.*)\) appears to be up/) {
		$node=$2;
		unless ($deadnodes{$node}) {
		    foreach (keys %deadnodes) {
			if ($node =~ /^$_\./) {
			    $node = $_;
			    last;
			}
		    }
		}
		delete $deadnodes{$node};
		if ($verbose) {
		    push @return_msg, [$node, $_, 0];
		}
		push(@pingable_hcp, $node);
	    } elsif (/Nmap scan report for ([^ ]*)/) {
		$node=$1;
	    } elsif (/Host is up./) {
		unless ($deadnodes{$node}) {
		    foreach (keys %deadnodes) {
			if ($node =~ /^$_\./) {
			    $node = $_;
			    last;
			}
		    }
		}
		delete $deadnodes{$node};
		push(@pingable_hcp, $node);
	    }
	}	
    } else {
	#use fping
	#print "use fping\n";
	my $master = xCAT::TableUtils->get_site_Master();
	my $masterip = xCAT::NetworkUtils->getipaddr($master);
	if ($masterip =~ /:/) { #IPv6, needs fping6 support 
	    if (!-x '/usr/bin/fping6')
	    {
		push @return_msg, [$node, "fping6 is not availabe for IPv6 ping.", -1];
		return \@return_msg;
	    }
	    open (FPING, "fping6 ".join(' ',@hcps_ip). " 2>&1 |") or die("Cannot open fping pipe: $!");
	} else {
	    open (FPING, "fping ".join(' ',@hcps_ip). " 2>&1 |") or die("Cannot open fping pipe: $!");
	}
	
	while (<FPING>) {
	    if ($verbose) {
		push @return_msg, [$node, $_, 0];
	    }
	    if ($_ =~ /is alive/) {
		s/ is alive//;
		push @pingable_hcp, $_;
	    }
	}
    }

    if (!@pingable_hcp) {
        push @return_msg, [$node, "No hcp can be pinged.", -1];
        return \@return_msg;
    }

    # try the ip of hcp one by one
    my @lastnoerr_msg;
    my @noerr_msg;
    my @last_msg;
    foreach my $hcp (@pingable_hcp) {
        push @noerr_msg, @lastnoerr_msg; 
        @lastnoerr_msg = ();
        @last_msg = ();
        # Generate the url path for CIM communication
        chomp($hcp);
        my $url_path = "https://"."$user".":"."$password"."\@"."$hcp".":5989";

        # Not display password in command outupt.
        my $display_url_path = "https://"."$user".":"."xxxxxx"."\@"."$hcp".":5989";
            
        # Execute the request
        my $cmd = "";
        my $display_cmd = "";
        if ($opt->{'set'}) {
            $cmd = "$::CIM_CLIENT_PATH $verb_arg -u $url_path -n $cec_name -o $opt->{'set'}";
            $display_cmd = "$::CIM_CLIENT_PATH $verb_arg -u $display_url_path -n $cec_name -o $opt->{'set'}";
        } elsif ($opt->{'query'}) {
            $cmd = "$::CIM_CLIENT_PATH $verb_arg -u $url_path -n $cec_name -o $opt->{'query'}";
            $display_cmd = "$::CIM_CLIENT_PATH $verb_arg -u $display_url_path -n $cec_name -o $opt->{'query'}";
        }
        
        if ($verbose) {
            push @noerr_msg, [$node, "Run following command: $display_cmd", 0];
        }
    
        # Disable the CHID signal before run the command. Otherwise the 
        # $? value of `$cmd` will come from handler of CHID signal
        $SIG{CHLD} = 'DEFAULT'; 
    
        # Call the xCAT_cim_client to query or set the energy capabilities
        $cmd .= " 2>&1";

        # secure passwd in verbose mode
        my $tmpv = $::VERBOSE;
        $::VERBOSE = 0;        
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        $::VERBOSE = $tmpv;

        foreach my $line (@result) {
            chomp($line);
            if ($line =~ /^\s*$/) {
                next;
            }
            push @lastnoerr_msg, [$node, $line, 0];
            push @last_msg, [$node, $line, $::RUNCMD_RC];
        }
        if (!$::RUNCMD_RC) {
            last;
        }
    }

    # only display the correct msg when getting correct result from one fsp
    if ($::RUNCMD_RC || $verbose) {
        push @return_msg, @noerr_msg;
    } 
    push @return_msg, @last_msg;

    return \@return_msg;
}


1;
