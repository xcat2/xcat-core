# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPcfg;
use strict;
use Getopt::Long;
use xCAT::Usage;
use Data::Dumper;
#use xCAT::PPCcli;


##########################################
# Globals
##########################################



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
        "*_passwd"
    );
    my @bpa = (
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd"
    );
    my @cec = (
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd"
    );
    my @frame = (
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd"
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
    my $sitetab  = xCAT::Table->new( 'nodetype' );
    my $nodes = $request->{node};
    foreach (@$nodes) {
        if ( defined( $sitetab )) {      
            my ($ent) = $sitetab->getAttribs({ node=>$_},'nodetype');
            if ( defined($ent) ) {
                   $request->{hwtype} = $ent->{nodetype};
                   last;
            }

        }

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

    if ( !GetOptions( \%opt, qw(V|Verbose) )) {
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
        if ( !grep( /^$command$/, @$supported )) {
            return(usage( "Invalid command: $arg" ));
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
    #if ( exists($cmds{frame}) ) {
    #    $request->{hcp} = "hmc";
    #    $request->{method} = "cfg";
    #    return( \%opt );
    #}
#
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
    if ( $command eq 'admin_passwd' or $command eq 'general_passwd' or $command eq "*_passwd"){
        my ($passwd,$newpasswd) = split /,/, $value;
        if ( !$passwd or !$newpasswd) {
            return( "Current password and new password couldn't be empty for user 'admin' and 'general'" );
        }
    }

    if ( $command eq 'HMC_passwd' ) {
        my ($passwd,$newpasswd) = split /,/, $value;
        if ( !$newpasswd ) {
            return( "New password couldn't be empty for user 'HMC'" );
        }
    }
    return undef;
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

	foreach my $arg ( @$args ) {
        my ($user,$value) = split /=/, $arg;
        my ($passwd,$newpasswd) = split /,/, $value;
        $user =~ s/_passwd$//;
        #$user =~ s/^HMC$/access/g;

        if ( $user eq "*" ) {
            push @$users, "HMC";
            push @$users, "admin";
            push @$users, "general";
        } else {
            push @$users, $user;
        }

        foreach my $usr ( @$users ) {

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
    if($$attrs[4] =~ /^fsp$/ || $$attrs[4] =~ /^lpar$/) {
        $type = 0;
    } else {
        $type = 1;
    }

    ############################
    # Get IP address
    ############################
    $fsp_ip = xCAT::Utils::get_hdwr_ip($fsp_name);
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

1;

