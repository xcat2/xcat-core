# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPcfg;
use strict;
use Getopt::Long;
use xCAT::Usage;
use xCAT::Utils;
use xCAT::PPCcfg;
#use Data::Dumper;
#use xCAT::PPCcli;


##########################################
# Globals
##########################################
my %rspconfig = ( 
    frame  => \&frame,
    cec_off_policy  => \&cec_off_policy,
);

my %default_passwd = ( 
    HMC      => "",
    admin   => "admin",
    general => "general",
);

##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my $command = $request->{command};
    my $args    = $request->{arg};
    my %opt     = ();
    my %cmds    = ();
    my @fsp = (
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "resetnet",
    );
    my @bpa = (
	"frame",
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "resetnet"
    );
    my @cec = (
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "cec_off_policy",
        "resetnet",
	    "sysname"
    );
    my @frame = (
	"frame",
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "resetnet",
	    "sysname"
    );

    
    my %rsp = (
        fsp   => \@fsp,
        bpa   => \@bpa,
        cec   => \@cec,
        frame => \@frame,
    );
    #############################################
    # Get support command list
    #############################################
    #my $typetab  = xCAT::Table->new( 'nodetype' );
    #my $nodes = $request->{node};
    #foreach (@$nodes) {
    #    if ( defined( $typetab )) {      
    #        my ($ent) = $typetab->getAttribs({ node=>$_},'nodetype');
    #        if ( defined($ent) ) {
    #               $request->{hwtype} = $ent->{nodetype};
    #               last;
    #        }
    #
    #    }
    #
    #}
    
    my $nodes = $request->{node};
    foreach my $nn (@$nodes) {
        $request->{hwtype} = xCAT::DBobjUtils->getnodetype($nn);
        last if ($request->{hwtype});
    }
 
    my $supported = $rsp{$request->{hwtype}};
  
    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($command);
        return( [$_[0], $usage_string] );
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return(usage( "No command specified" ));
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );
    $request->{method} = undef;

    if ( !GetOptions( \%opt, qw(V|Verbose resetnet))) {
        return( usage() );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Check for "=" with no argument 
    ####################################
    if (my ($c) = grep(/=$/, @ARGV )) {
        return(usage( "Missing argument: $c" ));
    }
    ####################################
    # Check for unsupported commands
    ####################################
    foreach my $arg ( @ARGV ) {
        my ($command,$value) = split( /=/, $arg );
        if ( !grep( /^$command$/, @$supported) and !$opt{resetnet}) {
            my @enableASMI = xCAT::Utils->get_site_attribute("enableASMI");
            if (defined($enableASMI[0])) {
                $enableASMI[0] =~ tr/a-z/A-Z/;    # convert to upper
                    if (($enableASMI[0] eq "1") || ($enableASMI[0] eq "YES"))
                    {
                        $request->{enableASMI} = 1;
                        return xCAT::PPCcfg::parse_args($request, @_);
                    }
            }
            return(usage( "Invalid command for $request->{hwtype} : $arg" ));
        } 
        if ( exists( $cmds{$command} )) {
            return(usage( "Command multiple times: $command" ));
        }
        $cmds{$command} = $value;
    } 

    ####################################
    # Check command arguments 
    ####################################
    foreach ( keys %cmds ) {
        if ( $cmds{$_} ) {
            my $result = parse_option( $request, $_, $cmds{$_} );
            if ( $result ) {
                return( usage($result) );
            }
        } 
    }
    ####################################
    # Return method to invoke 
    ####################################
    #if ( $request->{hwtype} =~ /(^hmc|ivm)$/ ) {
    #    $request->{method} = "cfg";
    #    return( \%opt );
    #}
    ####################################
    # Return method to invoke
    ####################################
    if ( exists($cmds{frame}) or exists($cmds{cec_off_policy})) {
        $request->{hcp} = "bpa";
        $request->{method} = "cfg";
        return( \%opt );
    }

    ####################################
    # Return method to invoke
    ####################################
    if ( $opt{resetnet}  ) {
        $request->{hcp} = "fsp";
        $request->{method} = "resetnet";
        return( \%opt );
    }
    if(exists($cmds{sysname})) {
		$request->{hcp} = $request->{hwtype} eq 'frame' ? "bpa":"fsp";
		$request->{method} = "sysname";
		return (\%opt);
	}
    ####################################
    # Return method to invoke
    ####################################
    if ( exists($cmds{HMC_passwd}) or exists($cmds{general_passwd}) or exists($cmds{admin_passwd}) or exists($cmds{"*_passwd"}) ) {
        $request->{hcp} = "fsp";
        $request->{method} = "passwd";
        return( \%opt );
    }

    $request->{method} = \%cmds;
    return( \%opt );
}


##########################################################################
# Parse the command line optional arguments 
##########################################################################
sub parse_option {

    my $request = shift;
    my $command = shift;
    my $value   = shift;

  
    ####################################
    # Password
    ####################################
    #if ( $command eq 'admin_passwd' or $command eq 'general_passwd' or $command eq "*_passwd"){
    #    my ($passwd,$newpasswd) = split /,/, $value;
    #    if ( !$passwd or !$newpasswd) {
    #        return( "Current password and new password couldn't be empty for user 'admin' and 'general'" );
    #    }
    #}

    if ( $command eq 'HMC_passwd' or $command eq 'admin_passwd' or $command eq 'general_passwd' or $command eq "*_passwd" ) {
        my ($passwd,$newpasswd) = split /,/, $value;
        if ( !$newpasswd ) {
            return( "New password couldn't be empty for user 'HMC', 'admin' or 'general'" );
        }
    }

    if ( $command eq 'frame' ){
        if ( $value !~ /^\d+$/i && $value ne '*' ) { 
            return( "Invalid frame number '$value'" );
        }
    }

    if ( $command eq 'cec_off_policy' ){
        if ( $value !~ /^poweroff$/i && $value !~ /^stayon$/i ) { 
            return( "Invalid cec_off_policy '$value'" );
        }
    }
    if ($command eq 'sysname') {
        if ($value ne '*') {
            if ($value !~ /^[a-zA-Z0-9-_]+$/) {
                return( "Invalid sysname '$value'" );
            } elsif (scalar(@{$request->{node}}) gt '1') {
                return( "Invalid sysname '$value'" );
            }
            my $len = rindex $value."\$", "\$";
            if ($len > '31') {
                return ("Invalid sysname '$value', name is too long, max 31 characters");
            }
        }
    }
    return undef;
}
sub sysname_check_node_info {
	my $hash = shift;
	my $invalid_node = undef;
	while (my ($mtsm, $h) = each (%$hash)) {
		while (my ($name, $d) = each(%$h)) {
			if (@$d[4] !~ /^(cec|frame)$/) {
				$invalid_node = $name;
				last;
			}
		}
	}
	return $invalid_node;
}

my %sysname_action = (
    query => {
        cec => "get_cec_name",
        frame => "get_frame_name"
    },
    set => {
        cec => "set_cec_name",
        frame => "set_frame_name"
    }
);
sub do_query_sysname {
    my $request = shift;
    my $hash = shift;
    my @result = ();
    while (my ($mtms, $h) = each(%$hash)) {
        while (my($name, $d) = each(%$h)) {
            my $action = $sysname_action{query}{@$d[4]};
            my $values = xCAT::FSPUtils::fsp_api_action($name, $d, $action);
            push @result, $values;
            if (@$values[2] != 0)  {
                last;
            } else {
                my $len = rindex @$values[1]."\$", "\$";
                if ($len > '31') {
                    return ([[$name, "Get sysname failed, name is too long, max 31 characters", "1"]]);
                }
            }
        }
    }
    return (\@result);
}
sub do_set_sysname {
    my $request = shift;
    my $hash = shift;
    my $value = shift;
    my @result = ();
    while (my ($mtms, $h) = each(%$hash)) {
        while (my($name, $d) = each(%$h)) {
           my $sysname = ($value eq '*') ? $name : $value;
           my $action = $sysname_action{set}{@$d[4]};
           my $values = xCAT::FSPUtils::fsp_api_action($name, $d, $action, 0, $sysname);
           push @result, $values;
           if (@$values[2] != 0)  {
               last;
           }
        }
    }
    return (\@result);
}
sub sysname {
	my $request = shift;
	my $hash = shift;
	my $exp = shift;
	my $args = $request->{arg};
	my $invalid_node = &sysname_check_node_info($hash);
	if (defined($invalid_node)) {
		retrun ([[$invalid_node, "Node must be CEC or Frame", '1']]);
	}
	foreach my $arg (@$args) {
		my ($cmd, $value) = split /=/, $arg;
		if ($cmd !~ /^sysname$/) {
			return ([[$cmd, "Can't be exec with sysname", 1]]);
		}
		if ($value) {
			return &do_set_sysname($request, $hash, $value)
		} else {
			return &do_query_sysname($request, $hash);
		}
	}
    return ([["Error", "Arguments invalid", 1]]);
}
##########################################################################
# Update passwords for different users on FSP/BPA
##########################################################################
sub passwd {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $args    = $request->{arg};
    my $user    = ();
    my $users   = ();
    my @output  = ();
    my $default;

	foreach my $arg ( @$args ) {
        my ($user,$value) = split /=/, $arg;
        my ($passwd,$newpasswd) = split /,/, $value;
        $user =~ s/_passwd$//;
        #$user =~ s/^HMC$/access/g;
        
        if( !$passwd) {
            $default = 1;    
        }
         
        if ( $user eq "*" ) {
            push @$users, "HMC";
            push @$users, "admin";
            push @$users, "general";
        } else {
            push @$users, $user;
        }

        foreach my $usr ( @$users ) {
	       if( $default == 1 ) {
	           $passwd = $default_passwd{$usr};
	       }
                
        	while ( my ($cec,$h) = each(%$hash) ) {
           			while ( my ($node,$d) = each(%$h) ) {
               			my $type = @$d[4];
				my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api";
				my $cmd = xCAT::FSPcfg::fsp_api_passwd ($node, $d, $usr, $passwd, $newpasswd);
                		my $Rc = @$cmd[2];
				my $data = @$cmd[1];
                		my $usr_back = $usr;
                		$usr_back =~ s/^access$/HMC/g;
				push @output,[$node,"$usr_back: $data",$Rc];


                		##################################
                		# Write the new password to table
                		##################################
                		if ( $Rc == 0 ) {
                		    xCAT::PPCdb::update_credentials( $node, $type, $usr, $newpasswd );
                		}
            			}
        		}
		}
	}
 
    return( \@output );
}

##########################################################################
# Handles all PPC rspconfig commands
##########################################################################
sub cfg {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $args    = $request->{arg};
    my $result;

    foreach ( @$args ) {
        ##################################
        # Ignore switches in command-line
        ##################################
        unless ( /^-/ ) {
            my ($cmd,$value) = split /=/;

            no strict 'refs';
            $result = $rspconfig{$cmd}( $request, $value, $hash );
            use strict;
        }
    }
    return( $result );
}

sub frame {
    my $request = shift;
    my $value   = shift;
    my $hash    = shift;
    my $arg     = $request->{arg};

    foreach ( @$arg ) {
        my $result;
        my $Rc;
        my $data;

        my ($cmd, $value) = split /=/, $_;
        if ( $cmd ne "frame" ) {
            return( [["Error","Multiple option $cmd and frame is not accepted", -1]] );
        }

        #################################
        # Open xCAT database to sync with
        # the frame number between hcp
        # and database
        #################################
        my $tab = xCAT::Table->new( "ppc" );
        
        while ( my ($cec,$h) = each(%$hash) ) {
            while ( my ($node,$d) = each(%$h) ) {
                if ( !defined($value) ) {

                    #################################
                    # Get frame number
                    #################################
		    #$data = xCAT::PPCcli::lssyscfg( $exp, @$d[4], @$d[2], 'frame_num' );
		    $data = xCAT::FSPUtils::fsp_api_action( $node, $d, "get_frame_number");
                    $Rc = pop(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != 0 ) {
                        return( [[$node,@$data[1],$Rc]] );
                    }

                    push @$result, [$node,@$data[1], 0];

                    #################################
                    # Set frame number to database
                    #################################
                    $tab->setNodeAttribs( $node, { id=>@$data[1] } );

                } elsif ( $value eq '*' ) {
                    #################################
                    # Set frame number
                    # Read the settings from database 
                    #################################
                    my $ent=$tab->getNodeAttribs( $node,['id'] );

                    #################################
                    # Return error
                    #################################
                    if ( !defined($ent) or !defined($ent->{id}) ) {
                        return( [[$node,"Cannot find frame num in database", -1]] );
                    }
		    #$data = xCAT::PPCcli::chsyscfg( $exp, "bpa", $d, "frame_num=".$ent->{id} );
		    $data = xCAT::FSPUtils::fsp_api_action( $node, $d, "set_frame_number", 0, $ent->{id});
                    $Rc = pop(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != 0 ) {
                        return( [[$node,@$data[1],$Rc]] );
                    }

                    push @$result, [$node,@$data[1], 0];
                    push @$result, [$node,"It will take several minutes to complete. So please wait for several minutes, then the other operations could be done. Otherwise, the other operation will fail.", 0];

                } else {
                    #################################
                    # Set frame number
                    # Read the frame number from opt
                    #################################
		    #$data = xCAT::PPCcli::chsyscfg( $exp, "bpa", $d, "frame_num=$value" );
                    $data = xCAT::FSPUtils::fsp_api_action( $node, $d, "set_frame_number", 0, $value);
		    $Rc = pop(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != 0 ) {
                        return( [[$node,@$data[1],$Rc]] );
                    }

                    push @$result, [$node,@$data[1],0];
                    push @$result, [$node,"It will take several minutes to complete. So please wait for several minutes, then the other operations could be done. Otherwise, the other operation will fail.", 0];

                    #################################
                    # Set frame number to database
                    #################################
                    $tab->setNodeAttribs( $node, { id=>$value } );
                }
            }

            return( [@$result] );
        }  
    }
}

sub cec_off_policy {
    my $request = shift;
    my $value   = shift;
    my $hash    = shift;
    my $arg     = $request->{arg};

    foreach ( @$arg ) {
        my $result;
        my $Rc;
        my $data;

        my ($cmd, $value) = split /=/, $_;
        if ( $cmd ne "cec_off_policy" ) {
            return( [["Error","Multiple option $cmd and cec is not accepted", -1]] );
        }

        while ( my ($cec,$h) = each(%$hash) ) {
            while ( my ($node,$d) = each(%$h) ) {
                if ( !defined($value) ) {

                    #################################
                    # Get platform IPL parameters 
                    #################################
		    $data = xCAT::FSPUtils::fsp_api_action( $node, $d, "get_phyp_cfg_power_off_policy");
                    $Rc = pop(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != 0 ) {
                        return( [[$node,@$data[1],$Rc]] );
                    }
                     
                    @$data[1] =~ /cec_off_policy=(\w*);/;                    

                    push @$result, [$node, $1, 0];


                 } else {
                    #################################
                    # Set cec off policy 
                    #################################
		    if( $value eq "poweroff") {
		        $value = "cec_off_policy_poweroff";
		    } else {
		        $value = "cec_off_policy_stayon";
		    }
                    $data = xCAT::FSPUtils::fsp_api_action( $node, $d, $value);
		    $Rc = pop(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != 0 ) {
                        return( [[$node,@$data[1],$Rc]] );
                    }

                    push @$result, [$node,"Success",0];

                }
            }

            return( [@$result] );
        }  
    }
}









##########################################################################
# Invoke fsp_api to change the passwords and store updated passwd in db
##########################################################################
sub fsp_api_passwd {
    my $node_name  = shift;
    my $attrs      = shift;
    my $user       = shift;
    my $passwd     = shift;
    my $newpasswd  = shift;
    my $id         = 1;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my $res = 0 ;
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api";

    $id = $$attrs[0];
    $fsp_name = $$attrs[3];

    ############################
    # Set type for FSP or BPA
    ############################
    if($$attrs[4] =~ /^fsp$/ || $$attrs[4] =~ /^lpar$/ ||  $$attrs[4] =~ /^cec$/) {
        $type = 0;
    } else {
        $type = 1;
    }

    ############################
    # Get IP address
    ############################
    #$fsp_ip = xCAT::Utils::get_hdwr_ip($fsp_name);
    $fsp_ip = xCAT::Utils::getNodeIPaddress($fsp_name);
    if($fsp_ip == -1) {
        $res = "Failed to get the $fsp_name\'s ip";
        return ([$node_name, $res, -1]);
    }

    #################################
    # Create command and run command
    #################################
    my $cmd;
    if( $passwd ne "" ) {
        $cmd = "$fsp_api -a set_fsp_pw -u $user -p $passwd -P $newpasswd -t $type:$fsp_ip:$id:$node_name: ";
    } else {
        $cmd = "$fsp_api -a set_fsp_pw -u $user -P $newpasswd -t $type:$fsp_ip:$id:$node_name: "; 
    }
    $SIG{CHLD} = ();
    $res = xCAT::Utils->runcmd($cmd, -1);
    $Rc = $::RUNCMD_RC;

    if($Rc == 0) {
        $res = "Success";
    }


    ##################
    # output the prompt
    ##################
    #$outhash{ $node_name } = $res;

    return( [$node_name,$res, $Rc] );

}


##########################################################################
# Do resetnet 
##########################################################################
sub resetnet {
    my $request = shift;
    my $hash    = shift;
    my %nodehash;
    foreach ( @{$request->{noderange}}) {
       $nodehash{$_} = 1;
    }
    # go to use lsslp do_resetnet
    my $result = xCAT_plugin::lsslp::do_resetnet($request, \%nodehash);
	return [$result];
}
1;

