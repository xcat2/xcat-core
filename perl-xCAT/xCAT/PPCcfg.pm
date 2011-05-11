# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCcfg;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;


##########################################
# Globals
##########################################
my %rspconfig = ( 
    sshcfg => \&sshcfg,
    frame  => \&frame,
    hostname => \&hostname
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
        "memdecfg",
        "decfg",
        "procdecfg",
        "iocap",
        "time",
        "date",
        "autopower",
        "sysdump",
        "spdump",
        "network",
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "hostname"
    );
    my @bpa = (
        "frame",
        "password",
        "newpassword",
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "hostname"
    );
    my @ppc = (
        "sshcfg"
    );
    my %rsp = (
        cec=> \@fsp,
        frame=>\@bpa,
        fsp => \@fsp,
        bpa => \@bpa,
        ivm => \@ppc,
        hmc => \@ppc
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
    if ( $request->{hwtype} =~ /(^hmc|ivm)$/ ) {
        $request->{method} = "cfg";
        return( \%opt );
    }
    ####################################
    # Return method to invoke
    ####################################
    if ( exists($cmds{frame}) or exists($cmds{hostname}) ) {
        $request->{hcp} = "hmc";
        $request->{method} = "cfg";
        return( \%opt );
    }

    ####################################
    # Return method to invoke
    ####################################
    if ( exists($cmds{HMC_passwd}) or exists($cmds{general_passwd}) or exists($cmds{admin_passwd}) or exists($cmds{"*_passwd"}) ) {
        $request->{hcp} = "hmc";
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
    # Set/get time
    ####################################
    if ( $command =~ /^time$/ ) {
        if ( $value !~
          /^([0-1]?[0-9]|2[0-3]):(0?[0-9]|[1-5][0-9]):(0?[0-9]|[1-5][0-9])$/){
            return( "Invalid time format '$value'" );
        }
    }
    ####################################
    # Set/get date 
    ####################################
    if ( $command =~ /^date$/ ) {
        if ( $value !~
          /^(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])-(20[0-9]{2})$/){
            return( "Invalid date format '$value'" );
        }
    }
    ####################################
    # Set/get options
    ####################################
    if ( $command =~ /^(autopower|iocap|sshcfg)$/ ) {
        if ( $value !~ /^(enable|disable)$/i ) {
            return( "Invalid argument '$value'" );
        }
    }
    ####################################
    # Deconfiguration policy 
    ####################################
    if ( $command =~ /^decfg$/ ) {
        if ( $value !~ /^(enable|disable):.*$/i ) {
            return( "Invalid argument '$value'" );
        }
    }
    ####################################
    # Processor deconfiguration 
    ####################################
    if ( $command =~ /^procdecfg$/ ) {
        if ( $value !~ /^(configure|deconfigure):\d+:(all|[\d,]+)$/i ) {
            return( "Invalid argument '$value'" );
        }
    }
    ################################
    # Memory deconfiguration 
    ################################
    elsif ( $command =~ /^memdecfg$/ ) {
       if ($value !~/^(configure|deconfigure):\d+:(unit|bank):(all|[\d,]+)$/i){
           return( "Invalid argument '$value'" );
       }
    }
    if ( $command eq 'network'){
        my ( $adapter_name, $ip, $host, $gateway, $netmask) =
                split /,/, $value;
        return ( "Network interface name is required") if ( ! $adapter_name);
        return ( "Invalide network interface name $adapter_name") if ( $adapter_name !~ /^eth\d$/);
        return undef if ( $ip eq '*');
        return ( "Invalid IP address format") if ( $ip and $ip !~ /\d+\.\d+\.\d+\.\d+/);
        return ( "Invalid netmask format") if ( $netmask and $netmask !~ /\d+\.\d+\.\d+\.\d+/);
    }

    if ( $command eq 'frame' ){
        if ( $value !~ /^\d+$/i && $value ne '*' ) { 
            return( "Invalid frame number '$value'" );
        }
    }

    if ( $command eq 'admin_passwd' or $command eq 'general_passwd' or $command eq '*_passwd' ){
        my ($passwd,$newpasswd) = split /,/, $value;
        if ( !$passwd or !$newpasswd) {
            return( "Current password and new password couldn't be empty" );
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
    my $result;
    my $users;

    foreach my $arg ( @$args ) {
        my ($user,$value) = split /=/, $arg;
        my ($passwd,$newpasswd) = split /,/, $value;
        $user =~ s/_passwd$//;
        $user =~ s/^HMC$/access/g;

        if ( $user eq "*" ) {
            push @$users, "access";
            push @$users, "admin";
            push @$users, "general";
        } else {
            push @$users, $user;
        }

        foreach my $usr ( @$users ) {
            while ( my ($cec,$h) = each(%$hash) ) {
                while ( my ($node,$d) = each(%$h) ) {
                    my $type = @$d[4];
                    my $data = xCAT::PPCcli::chsyspwd( $exp, $usr, $type, $cec, $passwd, $newpasswd );
                    my $Rc = shift(@$data);
                    my $usr_back = $usr;
                    $usr_back =~ s/^access$/HMC/g;
                    push @$result, [$node,"$usr_back: @$data[0]",$Rc];
    
                    ##################################
                    # Write the new password to table
                    ##################################
                    if ( $Rc == SUCCESS ) {
                        xCAT::PPCdb::update_credentials( $node, $type, $usr_back, $newpasswd );
                    }
                }
            }
        }
    }

    return( [@$result] );
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
            $result = $rspconfig{$cmd}( $request, $exp, $value, $hash );
            use strict;
        }
    }
    return( $result );
}

##########################################################################
# Enables/disables/displays SSH access to HMC/IVM  
##########################################################################
sub sshcfg {
    my $request = shift;
    my $exp     = shift;
    my $mode    = shift;
    my $server  = @$exp[3];
    my $userid  = @$exp[4];
    my $fname   = ((xCAT::Utils::isAIX()) ? "/.ssh/":"/root/.ssh/")."id_rsa.pub";
    my $auth    = "/home/$userid/.ssh/authorized_keys2";

    #####################################
    # Get SSH key on Management Node
    #####################################
    unless ( open(RSAKEY,"<$fname") ) {
        return( [[$server,"Error opening '$fname'",RC_ERROR]] );
    } 
    my ($sshkey) = <RSAKEY>;
    close(RSAKEY);

    #####################################
    # userid@host not found in key file
    #####################################
    if ( $sshkey !~ /\s+(\S+\@\S+$)/ ) {
        return( [[$server,"Cannot find userid\@host in '$fname'",RC_ERROR]] );
    }
    my $logon = $1;

    #####################################
    # Determine if SSH is enabled 
    #####################################
    if ( !defined( $mode )) {
        my $result = xCAT::PPCcli::send_cmd( $exp, "cat $auth" );
        my $Rc = shift(@$result);        

        #################################
        # Return error 
        #################################
        if ( $Rc != SUCCESS ) {
            return( [[$server,@$result[0],$Rc]] );
        }
        #################################
        # Find logon in key file 
        #################################
        foreach ( @$result ) {
            if ( /$logon$/ ) {
                return( [[$server,"enabled",SUCCESS]] );
            }
        }
        return( [[$server,"disabled",SUCCESS]] );
    }
    #####################################
    # Enable/disable SSH 
    #####################################
    my $result = xCAT::PPCcli::mkauthkeys( $exp, $mode, $logon, $sshkey );
    my $Rc = shift(@$result);

    #################################
    # Return error
    #################################
    if ( $Rc != SUCCESS ) {
        return( [[$server,@$result[0],$Rc]] );
    }
    return( [[$server,lc($mode."d"),SUCCESS]] );
}

sub frame {
    my $request = shift;
    my $exp     = shift;
    my $value   = shift;
    my $hash    = shift;
    my $arg     = $request->{arg};

    foreach ( @$arg ) {
        my $result;
        my $Rc;
        my $data;

        my ($cmd, $value) = split /=/, $_;
        if ( $cmd ne "frame" ) {
            return( [[@$exp[2],"Multiple option $cmd and frame is not accepted",SUCCESS]] );
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
                    $data = xCAT::PPCcli::lssyscfg( $exp, @$d[4], @$d[2], 'frame_num' );
                    $Rc = shift(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != SUCCESS ) {
                        return( [[$node,@$data[0],$Rc]] );
                    }

                    push @$result, [$node,@$data[0],SUCCESS];

                    #################################
                    # Set frame number to database
                    #################################
                    $tab->setNodeAttribs( $node, { id=>@$data[0] } );

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
                        return( [[$node,"Cannot find frame num in database",RC_ERROR]] );
                    }
                    $data = xCAT::PPCcli::chsyscfg( $exp, "bpa", $d, "frame_num=".$ent->{id} );
                    $Rc = shift(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != SUCCESS ) {
                        return( [[$node,@$data[0],$Rc]] );
                    }

                    push @$result, [$node,@$data[0],SUCCESS];

                } else {
                    #################################
                    # Set frame number
                    # Read the frame number from opt
                    #################################
                    $data = xCAT::PPCcli::chsyscfg( $exp, "bpa", $d, "frame_num=$value" );
                    $Rc = shift(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != SUCCESS ) {
                        return( [[$node,@$data[0],$Rc]] );
                    }

                    push @$result, [$node,@$data[0],SUCCESS];

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

sub hostname {
    my $request = shift;
    my $exp     = shift;
    my $value   = shift;
    my $hash    = shift;
    my $arg     = $request->{arg};
    my $result;

    foreach ( @$arg ) {
        my $data;
        my $Rc;

        my ($cmd, $value) = split /=/, $_;
        if ( $cmd ne "hostname" ) {
            return( [[@$exp[2],"Multiple option $cmd and hostname is not accepted",SUCCESS]] );
        }

        while ( my ($cec,$h) = each(%$hash) ) {
            while ( my ($node,$d) = each(%$h) ) {
                if ( !defined($value) ) {
                    #################################
                    # Get system name
                    #################################
                    $data = xCAT::PPCcli::lssyscfg( $exp, @$d[4], @$d[2], 'name' );
                    $Rc = shift(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != SUCCESS ) {
                        push @$result, [$node,@$data[0],$Rc];
                    }

                    push @$result, [$node,@$data[0],SUCCESS];
                } elsif ( $value eq '*' ) {
                    $data = xCAT::PPCcli::chsyscfg( $exp, @$d[4], $d, "new_name=$node" );
                    $Rc = shift(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != SUCCESS ) {
                        push @$result, [$node,@$data[0],$Rc];
                    }

                    push @$result, [$node,@$data[0],SUCCESS];
                } else {
                    $data = xCAT::PPCcli::chsyscfg( $exp, @$d[4], $d, "new_name=$value" );
                    $Rc = shift(@$data);

                    #################################
                    # Return error
                    #################################
                    if ( $Rc != SUCCESS ) {
                        push @$result, [$node,@$data[0],$Rc];
                    }

                    push @$result, [$node,@$data[0],SUCCESS];
                }
            }
        }
    }

    return( [@$result] );
}

1;




