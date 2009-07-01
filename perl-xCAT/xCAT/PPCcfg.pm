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
    sshcfg => \&sshcfg
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
        "network"
    );
    my @bpa = (
        "network"
    );
    my @ppc = (
        "sshcfg"
    );
    my %rsp = (
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

    return undef;
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
            $result = $rspconfig{$cmd}( $exp, $value );
            use strict;
        }
    }
    return( $result );
}


##########################################################################
# Enables/disables/displays SSH access to HMC/IVM  
##########################################################################
sub sshcfg {

    my $exp    = shift;
    my $mode   = shift;
    my $server = @$exp[3];
    my $userid = @$exp[4];
    my $fname  = ((xCAT::Utils::isAIX()) ? "/.ssh/":"/root/.ssh/")."id_rsa.pub";
    my $auth   = "/home/$userid/.ssh/authorized_keys2";

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
            if ( /= $logon$/ ) {
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

1;





