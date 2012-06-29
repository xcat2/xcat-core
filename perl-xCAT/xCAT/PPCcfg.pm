# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCcfg;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use Storable qw(freeze thaw);
use POSIX "WNOHANG";
use xCAT::MsgUtils qw(verbose_message);

##########################################
# Globals
##########################################
my %rspconfig = ( 
    sshcfg => \&sshcfg,
    frame  => \&frame,
    hostname => \&hostname
);

my %rsp_result;

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
        "hostname",
        "resetnet",
        "dev",
        "celogin1"
    );
    my @bpa = (
        "frame",
        "password",
        "newpassword",
        "HMC_passwd",
        "admin_passwd",
        "general_passwd",
        "*_passwd",
        "hostname",
        "resetnet",
        "dev",
        "celogin1"
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
    my $typehash = xCAT::DBobjUtils->getnodetype($nodes);
    foreach my $nn (@$nodes) {
        $request->{hwtype} = $$typehash{$nn};
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

    if ( !GetOptions( \%opt, qw(V|verbose resetnet))) {
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
        } elsif ($_ =~ /_passwd$/) {
            return( usage("No argument specified for '$_'"));
        } 
    }
    {
        if ($request->{dev} eq '1' && $request->{other} eq '1') {
            return ( usage("Invalid command arrays"));
        } 
#       my $result = parse_dev_option( $request, \%cmds);
#       if ($result) {
#           return ( usage($result));
#       }
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
    if ( $opt{resetnet}  ) {
        $request->{hcp} = "hmc";
        $request->{method} = "resetnet";
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


sub parse_dev_option{
    my $req = shift;
    my $cmds = shift;
    foreach my $cmd (keys %$cmds) {
        if ( $cmd =~ /^(dev|celogin1)$/ ) {
            if ($cmds->{$cmd} and ($cmds->{$cmd} !~ /^(enable|disable)$/i) ) {
                return( "Invalid argument ".$cmds->{$cmd}." for ".$cmd );
            }
            $req->{dev} = 1;
        } else {
            $req->{other} = 1; 
        }
    }
    if ($req->{dev} eq '1' && $req->{other} eq '1') {
        return ("Invalid command arrays");
    } 
    return undef;
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
    
    if ( $command eq 'dev' or $command eq 'celogin1' ) {
       if ($value !~ /^(enable|disable)$/i ) {
           return( "Invalid argument '$value'" );
       }
       $request->{dev} = 1;
    } else {
       $request->{other} = 1; 
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :modify password of $usr for node:$node.");
                    my $data = xCAT::PPCcli::chsyspwd( $exp, $usr, $type, $cec, $passwd, $newpasswd );
                    my $Rc = shift(@$data);
                    my $usr_back = $usr;
                    $usr_back =~ s/^access$/HMC/g;
                    push @$result, [$node,"$usr_back: @$data[0]",$Rc];
    
                    ##################################
                    # Write the new password to table
                    ##################################
                    if ( $Rc == SUCCESS ) {
                        xCAT::MsgUtils->verbose_message($request, "rspconfig :update xCATdb for node:$node,ID:$usr_back.");
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
        xCAT::MsgUtils->verbose_message($request, "rspconfig :check sshcfg for user:$logon on node:$server.");
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
    xCAT::MsgUtils->verbose_message($request, "rspconfig :sshcfg $mode for user:$logon on node:$server.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :get frame_num for node:$node.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :set frame_num=".$ent->{id}." for node:$node.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :set frame_num=$value for node:$node.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig : set frame_num, update node:$node attr id=$value.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :get system name for node:$node.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :set system name:$node for node:$node.");
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
                    xCAT::MsgUtils->verbose_message($request, "rspconfig :set system name:$value for node:$node.");
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
    my $result = doresetnet($request, \%nodehash);
	return [$result];
}
##########################################################################
# Reset the network interfraces if necessary
##########################################################################
sub doresetnet {

    my $req     = shift;
    my $outhash = shift;
    my $reset_all = 1;
    my $namehash;
    my $targets;
    my $result;
    my $nodetype;


    # when invoked by rspconfig, the input data are different.
    # so I re-write this part.
    #if ( $outhash ) {
    #    $reset_all = 0;
    #    foreach my $name ( keys %$outhash ) {
    #        my $data = $outhash->{$name};
    #        my $ip = @$data[4];
    #        if ( $name =~ /^([^\(]+)\(([^\)]+)\)$/) {
    #            $name = $1;
    #            $ip = $2;
    #        }
    #        $namehash->{$name} = $ip;
    #    }
    #}
    my $hoststab = xCAT::Table->new( 'hosts' );
    if ( !$hoststab ) {
        send_msg( $req, 1, "Error open hosts table" );
        return( [RC_ERROR] );
    }

    my $mactab = xCAT::Table->new( 'mac' );
    if ( !$mactab ) {
        send_msg( $req, 1, "Error open mac table" );
        return( [RC_ERROR] );
    }

    if ( $req->{node} ) {
        $reset_all = 0;
        my $typehash = xCAT::DBobjUtils->getnodetype(\@{ $req->{node}});
        foreach my $nn ( @{ $req->{node}} ) {
            $nodetype = $$typehash{$nn};
            # this brunch is just for the xcat 2.6(+) database
            if ( $nodetype =~ /^(cec|frame)$/ )  {
                my $cnodep = xCAT::DBobjUtils->getchildren($nn);
                $nodetype = ( $nodetype =~ /^frame$/i ) ? "bpa" : "fsp";
                if ($cnodep) {
                    foreach my $cnode (@$cnodep) {
                        my $ip = xCAT::Utils::getNodeIPaddress( $cnode );
                        $namehash->{$cnode} = $ip;
                    }
                } else {
                    send_msg( $req, 1, "Can't get the fsp/bpa nodes for the $nn" );
                    return( [RC_ERROR] );
                }
            # this brunch is just for the xcat 2.5(-) databse
            } elsif ( $nodetype =~ /^(fsp|bpa)$/ )  {
                my $ip = xCAT::Utils::getNodeIPaddress( $nn );
                $namehash->{$nn} = $ip;
            } elsif ( !$nodetype ){
                send_msg( $req, 0, "$nn: no nodetype defined, skipping network reset" );
            }
        }
    }
    send_msg( $req, 0, "\nStart to reset network..\n" );

    my $ip_host;
    my @hostslist = $hoststab->getAllNodeAttribs(['node','otherinterfaces']);
    foreach my $host ( @hostslist ) {
        my $name = $host->{node};
        my $oi = $host->{otherinterfaces};

        #####################################
        # find the otherinterfaces for the
        # specified nodes, or the all nodes
        # Skip the node if the IP attributes
        # is same as otherinterfaces
        #####################################
        if ( $reset_all eq 0 && !exists( $namehash->{$name}) ){
            next;
        }

        #if ( $namehash->{$name} ) {
        #    $hoststab->setNodeAttribs( $name,{otherinterfaces=>$namehash->{$name}} );
        #}

        if (!$oi or $oi eq $namehash->{$name}) {
            send_msg( $req, 0, "$name: same ip address, skipping network reset" );
            next;
        }

        my $mac = $mactab->getNodeAttribs( $name, [qw(mac)]);
        if ( !$mac or !$mac->{mac} ) {
            send_msg( $req, 0, "$name: no mac defined, skipping network reset" );
            next;
        }

        #####################################
        # Make the target that will reset its
        # network interface
        #####################################
        $targets->{$nodetype}->{$oi}->{'args'} = "0.0.0.0,$name";
        $targets->{$nodetype}->{$oi}->{'mac'} = $mac->{mac};
        $targets->{$nodetype}->{$oi}->{'name'} = $name;
        $targets->{$nodetype}->{$oi}->{'ip'} = $oi;
        $targets->{$nodetype}->{$oi}->{'type'} = $nodetype;
        if ( $nodetype !~ /^mm$/ ) {
            my %netinfo = xCAT::DBobjUtils->getNetwkInfo( [$oi] );
            $targets->{$nodetype}->{$oi}->{'args'} .= ",$netinfo{$oi}{'gateway'},$netinfo{$oi}{'mask'}";
        }
        $ip_host->{$oi} = $name;
        xCAT::MsgUtils->verbose_message($req, "rspconfig :resetnet collecting information for node:$name.");
    }

    $result = undef;
    ###########################################
    # Update target hardware w/discovery info
    ###########################################
    my ($fail_nodes,$succeed_nodes) = rspconfig( $req, $targets );
    $result = "\nReset network failed nodes:\n";
    foreach my $ip ( @$fail_nodes ) {
        if ( $ip_host->{$ip} ) {
            $result .= $ip_host->{$ip} . ",";
        }
    }
    $result .= "\nReset network succeed nodes:\n";
    foreach my $ip ( @$succeed_nodes ) {
        if ( $ip_host->{$ip} ) {
            $result .= $ip_host->{$ip} . ",";
            my $new_ip = $hoststab->getNodeAttribs( $ip_host->{$ip}, [qw(ip)]);
            $hoststab->setNodeAttribs( $ip_host->{$ip},{otherinterfaces=>$new_ip->{ip}} );
        }
    }
    $result .= "\nReset network finished.\n";
    $hoststab->close();

    send_msg( $req, 0, $result );

    return undef;
}
##########################################################################
# Run rspconfig against targets
##########################################################################
sub rspconfig {

    my $request   = shift;
    my $targets   = shift;
    my $callback  = $request->{callback};
    my $start = Time::HiRes::gettimeofday();

    my %rsp_dev = get_rsp_dev( $request, $targets);
    #############################################
    # Fork one process per MM/HMC
    #############################################
    my $children = 0;
    $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
    my $fds = new IO::Select;

    foreach my $ip ( keys %rsp_dev) {
        my $pipe = fork_cmd( $request, $ip, \%rsp_dev);
        if ( $pipe ) {
            $fds->add( $pipe );
            $children++;
        }
    }
    #############################################
    # Process responses from children
    #############################################
    while ( $children > 0 ) {
        child_response( $callback, $fds );
    }
    while (child_response($callback,$fds)) {}

    #if ( $verbose ) {
    #    my $elapsed = Time::HiRes::gettimeofday() - $start;
    #    my $msg = sprintf( "Total rspconfig Time: %.3f sec\n", $elapsed );
    #    trace( $request, $msg );
    #}

    my $result;
    my @failed_node;
    my @succeed_node;
    foreach my $ip ( keys %rsp_result ) {
        #################################
        # Error logging on to MM
        #################################
        my $result = $rsp_result{$ip};
        my $Rc = shift(@$result);
    
        if ( $Rc != SUCCESS ) {
            push @failed_node, $ip;
        } else {
            push @succeed_node, $ip;
        }
    
        if ( $Rc != SUCCESS ) {
            #############################
            # MM connect error
            #############################
            if ( ref(@$result[0]) ne 'ARRAY' ) {
                #if ( $verbose ) {
                #    trace( $request, "$ip: @$result[0]" );
                #}
                delete $rsp_dev{$ip};
                next;
            }
        }
    
        ##################################
        # Process each response
        ##################################
        if ( defined(@$result[0]) ) {
            foreach ( @{@$result[0]} ) {
                #if ( $verbose ) {
                #    trace( $request, "$ip: $_" );
                #}
                /^(\S+)\s+(\d+)/;
                my $cmd = $1;
                $Rc = $2;
    
                if ( $cmd =~ /^network_reset/ ) {
                    if ( $Rc != SUCCESS ) {
                        delete $rsp_dev{$ip};
                        next;
                    }
                    #if ( $verbose ) {
                    #    trace( $request,"Resetting management-module ($ip)...." );
                    #}
                }
            }
        }
    }

    return( \@failed_node, \@succeed_node );
}
#############################################
# Get rsp devices and their logon info
#############################################
sub get_rsp_dev
{
    my $request = shift;
    my $targets = shift;

    my $mm  = $targets->{'mm'}  ? $targets->{'mm'} : {};
    my $hmc = $targets->{'hmc'} ? $targets->{'hmc'}: {};
    my $fsp = $targets->{'fsp'} ? $targets->{'fsp'}: {};
    my $bpa = $targets->{'bpa'} ? $targets->{'bpa'}: {};

    if (%$mm)
    {
        my $bladeuser = 'USERID';
        my $bladepass = 'PASSW0RD';
        #if ( $verbose ) {
        #    trace( $request, "telneting to management-modules....." );
        #}
        #############################################
        # Check passwd table for userid/password
        #############################################
        my $passtab = xCAT::Table->new('passwd');
        if ( $passtab ) {
            #my ($ent) = $passtab->getAttribs({key=>'blade'},'username','password');
            my $ent = $passtab->getNodeAttribs('blade', ['username','password']);
            if ( defined( $ent )) {
                $bladeuser = $ent->{username};
                $bladepass = $ent->{password};
            }
        }
        #############################################
        # Get MM userid/password
        #############################################
        my $mpatab = xCAT::Table->new('mpa');
        for my $nd ( keys %$mm ) {
            my $user = $bladeuser;
            my $pass = $bladepass;

            if ( defined( $mpatab )) {
                #my ($ent) = $mpatab->getAttribs({mpa=>$_},'username','password');
                my $ent = $mpatab->getNodeAttribs($nd, ['username','password']);
                if ( defined( $ent->{password} )) { $pass = $ent->{password}; }
                if ( defined( $ent->{username} )) { $user = $ent->{username}; }
            }
            $mm->{$nd}->{username} = $user;
            $mm->{$nd}->{password} = $pass;
        }
    }
    if (%$hmc )
    {
        #############################################
        # Get HMC userid/password
        #############################################
        foreach ( keys %$hmc ) {
            ( $hmc->{$_}->{username}, $hmc->{$_}->{password}) = xCAT::PPCdb::credentials( $hmc->{$_}->{name}, lc($hmc->{$_}->{'type'}), "hscroot" );
            #trace( $request, "user/passwd for $_ is $hmc->{$_}->{username} $hmc->{$_}->{password}");
        }
    }

    if ( %$fsp)
    {
        #############################################
        # Get FSP userid/password
        #############################################
        foreach ( keys %$fsp ) {
            ( $fsp->{$_}->{username}, $fsp->{$_}->{password}) = xCAT::PPCdb::credentials( $fsp->{$_}->{name}, lc($fsp->{$_}->{'type'}), "admin");
            #trace( $request, "user/passwd for $_ is $fsp->{$_}->{username} $fsp->{$_}->{password}");
        }
    }

    if ( %$bpa)
    {
        #############################################
        # Get BPA userid/password
        #############################################
        foreach ( keys %$bpa ) {
            ( $bpa->{$_}->{username}, $bpa->{$_}->{password}) = xCAT::PPCdb::credentials( $bpa->{$_}->{name}, lc($bpa->{$_}->{'type'}), "admin");
            #trace( $request, "user/passwd for $_ is $bpa->{$_}->{username} $bpa->{$_}->{password}");
        }
    }

    return (%$mm,%$hmc,%$fsp,%$bpa);
}
##########################################################################
# Forks a process to run the slp command (1 per adapter)
##########################################################################
sub fork_cmd {

    my $request  = shift;
    my $ip       = shift;
    my $arg      = shift;
    my $services = shift;

    #######################################
    # Pipe childs output back to parent
    #######################################
    my $parent;
    my $child;
    pipe $parent, $child;
    my $pid = xCAT::Utils->xfork();

    if ( !defined($pid) ) {
        ###################################
        # Fork error
        ###################################
        send_msg( $request, 1, "Fork error: $!" );
        return undef;
    }
    elsif ( $pid == 0 ) {
        ###################################
        # Child process
        ###################################
        close( $parent );
        $request->{pipe} = $child;

        invoke_cmd( $request, $ip, $arg, $services );
        exit(0);
    }
    else {
        ###################################
        # Parent process
        ###################################
        close( $child );
        return( $parent );
    }
    return(0);
}

##########################################################################
# Run the forked command and send reply to parent
##########################################################################
sub invoke_cmd {

    my $request  = shift;
    my $ip       = shift;
    my $args     = shift;


    ########################################
    # Telnet (rspconfig) command
    ########################################
    my $target_dev = $args->{$ip};
    my @cmds;
    my $result;
    #if ( $verbose ) {
    #    trace( $request, "Forked: ($ip)->($target_dev->{args})" );
    #}
    if ($target_dev->{'type'} eq 'mm')
    {
        @cmds = (
                "snmpcfg=enable",
                "sshcfg=enable",
                "network_reset=$target_dev->{args}"
                );
        xCAT::MsgUtils->verbose_message($request, "rspconfig :doresetnet run xCAT_plugin::blade::clicmds for node:$target_dev->{name},ip:$ip.");
        $result = xCAT_plugin::blade::clicmds(
                $ip,
                $target_dev->{username},
                $target_dev->{password},
                0,
                @cmds );
    }
    elsif($target_dev->{'type'} eq 'hmc')
    {
        @cmds = ("network_reset=$target_dev->{args}");
        #trace( $request, "sshcmds on hmc $ip");
        xCAT::MsgUtils->verbose_message($request, "rspconfig :doresetnet run xCAT::PPC::sshcmds_on_hmc for node:$target_dev->{name},ip:$ip.");
        $result = xCAT::PPC::sshcmds_on_hmc(
                $ip,
                $target_dev->{username},
                $target_dev->{password},
                @cmds );
    }
    else #The rest must be fsp or bpa
    {
        @cmds = ("network=$ip,$target_dev->{args}");
        #trace( $request, "update config on $target_dev->{'type'} $ip");
        xCAT::MsgUtils->verbose_message($request, "rspconfig :doresetnet run xCAT::PPC::updconf_in_asm for node:$target_dev->{name},ip:$ip.");
        $result = xCAT::PPC::updconf_in_asm(
                $ip,
                $target_dev,
                @cmds );
    }

    ####################################
    # Pass result array back to parent
    ####################################
    my @data = ("RSPCONFIG6sK4ci", $ip, @$result[0], @$result[2]);
    my $out = $request->{pipe};


    print $out freeze( \@data );
    print $out "\nENDOFFREEZE6sK4ci\n";
    return;
}
    

##########################################################################
# Invokes the callback with the specified message
##########################################################################
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
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
        $output{data} = \@_;
        $callback->( \%output );
    }
}
##########################################################################
# Collect output from the child processes
##########################################################################
sub child_response {

    my $callback = shift;
    my $fds = shift;
    my @ready_fds = $fds->can_read(1);

    foreach my $rfh (@ready_fds) {
        my $data = <$rfh>;

        #################################
        # Read from child process
        #################################
        if ( defined( $data )) {
            while ($data !~ /ENDOFFREEZE6sK4ci/) {
                $data .= <$rfh>;
            }
            my $responses = thaw($data);

            #############################
            # rspconfig results
            #############################
            if ( @$responses[0] =~ /^RSPCONFIG6sK4ci$/ ) {
                shift @$responses;
                my $ip = shift(@$responses);

                $rsp_result{$ip} = $responses;
                next;
            }
            #############################
            # Message or verbose trace
            #############################
            foreach ( @$responses ) {
                $callback->( $_ );
            }
            next;
        }
        #################################
        # Done - close handle
        #################################
        $fds->remove($rfh);
        close($rfh);
    }
}

1;




