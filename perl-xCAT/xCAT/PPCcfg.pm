# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCcfg;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCfsp;
use xCAT::Usage;
use Storable qw(freeze thaw);
use POSIX "WNOHANG";
use xCAT::MsgUtils qw(verbose_message);

use LWP;
use HTTP::Cookies;
##########################################
# Globals
##########################################
my %rspconfig = ( 
    sshcfg => \&sshcfg,
    frame  => \&frame,
    hostname => \&hostname
);

my %rsp_result;
my $start;
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
# Do resetnet public entry
##########################################################################
sub resetnet {
    my $request = shift;
    doresetnet($request);
    return 0;
}
##########################################################################
# Reset the network interfraces if necessary
##########################################################################
sub doresetnet {

    my $req = shift;
    my %iphash;
    my $targets;
    my $result;
    my %grouphash;
    my %oihash;
    my %machash;
    my %vpdhash;
    
	unless ($req) {
	    send_msg( $req, 1, "request is empty, return" );
		return;
	}	
    ###########################################
    # prepare to reset network
    ###########################################
    xCAT::MsgUtils->verbose_message($req, "rspconfig :do resetnet begin to phase nodes");
    my $hoststab = xCAT::Table->new( 'hosts' );
    if ( !$hoststab ) {
        send_msg( $req, 1, "Error open hosts table" );
        return;
    } else {
        my @hostslist = $hoststab->getAllNodeAttribs(['node','otherinterfaces']);
        foreach my $otherentry ( @hostslist) {
            $oihash{$otherentry->{node}} = $otherentry->{otherinterfaces};
        }
    }    
    
    my $mactab = xCAT::Table->new( 'mac' );
    if ( !$mactab ) {
        send_msg( $req, 1, "Error open mac table" );
        return;
    }else{
        my @maclist = $mactab->getAllNodeAttribs(['node','mac']);
        foreach my $macentry (@maclist) {
            $machash{$macentry->{node}} = $macentry->{mac};
        }
    }
    $mactab = ();

    my $vpdtab = xCAT::Table->new( 'vpd' );
    if ( !$vpdtab ) {
        send_msg( $req, 1, "Error open vpd table" );
        return;
    } else {
        my @vpdlist = $vpdtab->getAllNodeAttribs(['node','mtm','serial','side']);
        foreach my $vpdentry (@vpdlist) {
            if ($vpdentry->{side} =~ /(\w)\-\w/) {
                my $side = $1;
                $vpdhash{$vpdentry->{node}} = $vpdentry->{mtm}."*".$vpdentry->{serial}."*".$side;
            }   
        }
    } 
    $vpdtab = ();

    unless ( $req->{node} ) {
        send_msg( $req, 0, "no node specified" );
        return;
    }
    ###########################################
    # Process nodes and get network information
    ###########################################
    my $nodetype = $req->{hwtype};
    if ( $nodetype =~ /^(cec|frame)$/ )  {   
        # this brunch is just for the xcat 2.6(or 2.6+) database
        foreach my $nn ( @{ $req->{node}} ) {
            my $cnodep = xCAT::DBobjUtils->getchildren($nn);
            $nodetype = ( $nodetype =~ /^frame$/i ) ? "bpa" : "fsp";
            if ($cnodep) {
                foreach my $cnode (@$cnodep) {
                    my $ip = xCAT::Utils::getNodeIPaddress( $cnode );
                    my $oi = $oihash{$cnode};
                    if(!defined $ip) {
                        send_msg($req, "doresetnet: can't get $cnode ip");
                        next;
                    }           
                    if(!defined $oi) {
                        send_msg($req, "doresetnet: can't get $cnode hosts.otherinterfaces");
                        next;
                    }
                    if ( exists($oihash{$cnode}) and $ip eq $oihash{$cnode}) {
                        send_msg( $req, 0, "$cnode: same ip address, skipping $nn network reset" );  
                    } elsif( ! exists $machash{$cnode}){
                        send_msg( $req, 0, "$cnode: no mac defined, skipping $nn network reset" );
                    } else {
                        $iphash{$cnode}{sip} = $ip;
                        $iphash{$cnode}{tip} = $oihash{$cnode};
                        if(exists $grouphash{$vpdhash{$cnode}}) {
                            $grouphash{$vpdhash{$cnode}} .= ",$cnode";
                        } else {
                            $grouphash{$vpdhash{$cnode}} = "$cnode";
                        }
                        $targets->{$nodetype}->{$ip}->{'args'} = "0.0.0.0,$cnode";
                        $targets->{$nodetype}->{$ip}->{'mac'} = $machash{$cnode};
                        $targets->{$nodetype}->{$ip}->{'name'} = $cnode;
                        $targets->{$nodetype}->{$ip}->{'ip'} = $ip;
                        $targets->{$nodetype}->{$ip}->{'type'} = $nodetype;
                        my %netinfo = xCAT::DBobjUtils->getNetwkInfo( [$ip] );
                        $targets->{$nodetype}->{$ip}->{'args'} .= ",$netinfo{$ip}{'gateway'},$netinfo{$ip}{'mask'}";
                        #xCAT::MsgUtils->verbose_message($req, "doresetnet: get node $cnode info $targets->{$nodetype}->{$ip}->{'args'}, ip is $ip");
                        $targets->{$nodetype}->{$oi}->{'args'} = "0.0.0.0,$cnode";
                        $targets->{$nodetype}->{$oi}->{'mac'} = $machash{$cnode};
                        $targets->{$nodetype}->{$oi}->{'name'} = $cnode;
                        $targets->{$nodetype}->{$oi}->{'ip'} = $oi;
                        $targets->{$nodetype}->{$oi}->{'type'} = $nodetype;
                        %netinfo = xCAT::DBobjUtils->getNetwkInfo( [$oi] );
                        $targets->{$nodetype}->{$oi}->{'args'} .= ",$netinfo{$oi}{'gateway'},$netinfo{$oi}{'mask'}";
                        #xCAT::MsgUtils->verbose_message($req, "doresetnet: get node $cnode info $targets->{$nodetype}->{$oi}->{'args'}, oi is $oi");

                    }
                }
            } else {
                send_msg( $req, 1, "Can't get the fsp/bpa nodes for the $nn" );
                return;
           }
        }              
    # this brunch is just for the xcat 2.5(or 2.5-) databse
    } elsif ( $nodetype =~ /^(fsp|bpa)$/ )  {
        foreach my $nn ( @{ $req->{node}} ) {
            my $ip = xCAT::Utils::getNodeIPaddress( $nn );
            if(!defined $ip) {
                send_msg($req, "doresetnet: can't get $nn ip");
                next;
            }           
            if(!exists $oihash{$nn}) {
                send_msg($req, "doresetnet: can't get $nn hosts.otherinterfaces");
                next;
            }
            my $oi = $oihash{$nn};
            if( exists($oihash{$nn}) and $ip eq $oihash{$nn}) {
                send_msg( $req, 0, "$nn: same ip address, skipping network reset" );  
            } elsif (!exists $machash{$nn}){
                send_msg( $req, 0, "$nn: no mac defined, skipping network reset" );
            } else {
                $iphash{$nn}{sip} = $ip;
                $iphash{$nn}{tip} = $oihash{$nn};
                if(exists $grouphash{$vpdhash{$nn}}) {
                    $grouphash{$vpdhash{$nn}} .= ",$nn";
                } else {
                    $grouphash{$vpdhash{$nn}} = "$nn";
                }
                $targets->{$nodetype}->{$ip}->{'args'} = "0.0.0.0,$nn";
                $targets->{$nodetype}->{$ip}->{'mac'} = $machash{$nn};
                $targets->{$nodetype}->{$ip}->{'name'} = $nn;
                $targets->{$nodetype}->{$ip}->{'ip'} = $ip;
                $targets->{$nodetype}->{$ip}->{'type'} = $nodetype;
                my %netinfo = xCAT::DBobjUtils->getNetwkInfo( [$ip] );
                $targets->{$nodetype}->{$ip}->{'args'} .= ",$netinfo{$ip}{'gateway'},$netinfo{$ip}{'mask'}";
                #xCAT::MsgUtils->verbose_message($req, "doresetnet: get node $nn info $targets->{$nodetype}->{$ip}->{'args'},ip is $ip");
                $targets->{$nodetype}->{$oi}->{'args'} = "0.0.0.0,$nn";
                $targets->{$nodetype}->{$oi}->{'mac'} = $machash{$nn};
                $targets->{$nodetype}->{$oi}->{'name'} = $nn;
                $targets->{$nodetype}->{$oi}->{'ip'} = $oi;
                $targets->{$nodetype}->{$oi}->{'type'} = $nodetype;
                %netinfo = xCAT::DBobjUtils->getNetwkInfo( [$oi] );
                $targets->{$nodetype}->{$oi}->{'args'} .= ",$netinfo{$oi}{'gateway'},$netinfo{$oi}{'mask'}";
                #xCAT::MsgUtils->verbose_message($req, "doresetnet: get node $nn info $targets->{$nodetype}->{$oi}->{'args'}, oi is $oi");
            }
        }                
    } elsif ( !$nodetype ){
        send_msg( $req, 0, "no nodetype defined, skipping network reset" );
        return;
    } else {
        send_msg( $req, 0, "$nodetype not supported, skipping network reset" );
        return;
    }
    
    unless (%grouphash) {
	    send_msg( $req, 0, "Failed to group the nodes, skipping network reset" );
        return;
    }    
    ###########################################
    # Update target hardware w/discovery info
    ###########################################
    my %rsp_dev = get_rsp_dev( $req, $targets);
    
    ######################################################
    # Start to reset network. Fork one process per BPA/FSP
    ######################################################
    %oihash  = ();
    %machash = ();
    %vpdhash = ();
    $start = Time::HiRes::gettimeofday();
    my $children = 0;
    $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
    my $fds = new IO::Select;
    my $callback  = $req->{callback};
    my $ij = 0;
    foreach my $node ( keys %grouphash) {
        my %iphashfornode;
        my $gc = $grouphash{$node};
        my %rsp_devfornode;

        foreach my $tn (split /,/, $gc) {
            $iphashfornode{$tn} = $iphash{$tn};
            for my $ti (keys %{$iphash{$tn}}){
                my $tip = $iphash{$tn}{$ti};
                $rsp_devfornode{$tip} = $rsp_dev{$tip};
            }
        }

        xCAT::MsgUtils->verbose_message($req, "========> begin to fork process for node $node");
        ######################################################
        # Begin fork
        ######################################################
        my $pipe;
        my $rspdevref = \%rsp_devfornode;
        my $grouphashref = $gc;
        my $iphashref = \%iphashfornode;
        my $result;
        my @data = ("RSPCONFIG6sK4ci");

        #######################################
        # Pipe childs output back to parent
        #######################################
        my $parent;
        my $child;
        pipe $parent, $child;
        $ij ++; 
        $ij = int($ij%60);
        my $pid = xCAT::Utils->xfork();

        if ( !defined($pid) ) {
            ###################################
            # Fork error
            ###################################
            send_msg( $req, 1, "Fork error: $!" );
            return undef;
        }
        elsif ( $pid == 0 ) {
            sleep $ij;
            ###################################
            # Child process, clear memory first
            ###################################
            %rsp_dev = ();
            %grouphash = ();
            %iphash = ();
            close( $parent );
            $req->{pipe} = $child;
            my $msgs; 
			my $report;
            #try and try to avoid the fail that caused by refreshing IP when doing resetnet
			my $time = 0;
			while (1) {
			    my $erflag = 0;
			    $msgs = child_process($grouphashref, $iphashref, $rspdevref, $req, $node );
                foreach my $port (keys %$msgs){
                    unless ($msgs->{$port} =~ /successful/) {
                        $erflag = 1;
			    	    last;
			    	}	
                }
				if ($erflag) {
				    $report = ();
				    foreach my $port1 (keys %$msgs){
                        $report .= $port1.":".$msgs->{$port1}.";";
                    }
				    xCAT::MsgUtils->verbose_message($req, "========> try again, $report");
				    #send_msg( $req, 0, "========> try again, $report");
				    sleep 3;
					$time++;
				} else {
                    last;
                }
                last if ($time > 10);				
			}		
			$report = ();
            foreach my $port (keys %$msgs){
                $report .= $port.":".$msgs->{$port}.";";
            }
            send_msg( $req, 0, "Resetnet result for $node is : $report");
            ####################################
            # Pass result array back to parent
            ####################################
            my %data;
			$data{errorcode} = 0;
            my $out = $req->{pipe};
            print $out freeze( [\%data] );
            print $out "\nENDOFFREEZE6sK4ci\n";
            exit(0);
        } else {
            ###################################
            # Parent process
            ###################################
            close( $child );
            $pipe = $parent ;
        }


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

    my $elapsed = Time::HiRes::gettimeofday() - $start;
    my $msg = sprintf( "Total rspconfig Time: %.3f sec\n", $elapsed );
    xCAT::MsgUtils->verbose_message($req, $msg);

    return undef;
}
##########################################################################
# child process
##########################################################################
sub child_process {
    local $SIG{CHLD} = 'DEFAULT';
    my $grouphashref = shift;
    my $iphashref = shift;
    my $rspdevref = shift;
    my $req = shift;
    my $node = shift;
    my %msginfo;
    my @ns = split /,/, $grouphashref;
    my @valid_ips;
    my @portneedreset;
    my @portsuccess;

    ##########################################################
    # ping static ip firstly, if succesufully, skip resetnet
    ##########################################################
    foreach my $fspport (@ns) {
        my $ip = ${$iphashref->{$fspport}}{sip};
        my $rc = system("ping -q -n -c 1 -w 1 $ip > /dev/null") >>8;
        if ($rc == 0) {
            xCAT::MsgUtils->verbose_message( $req, "ping static $ip successfully");
            push @valid_ips, $ip;  # static ip should be used first
            push @portsuccess, $fspport;
            $msginfo{$fspport} = "successful";
        } else {
            xCAT::MsgUtils->verbose_message( $req, "ping static $ip failed, need to do resetnet for $fspport");
            push @portneedreset, $fspport;
        }
    }
    if (scalar (@portneedreset) == 0) {
        return \%msginfo;
    }
    ###########################################
    # ping temp ip secondary
    ###########################################
    foreach my $fspport (@ns) {
        my $ip = ${$iphashref->{$fspport}}{tip};
        my $rc = system("ping -q -n -c 1 -w 1 $ip > /dev/null") >>8;
        if ($rc == 0) {
            push @valid_ips, $ip;
            xCAT::MsgUtils->verbose_message( $req, "ping temp $ip successfully");
        } else {
            xCAT::MsgUtils->verbose_message( $req, "ping temp $ip failed");
        }
    }
    if (scalar (@valid_ips) == 0) {
        foreach my $fspport (@ns) {
		    $msginfo{$fspport} = "failed to find valid ip to log on";
		}	
        return \%msginfo;
    }
    #########################################
    # log on, no retry here
    #########################################
    my @exp;
    my $goodip;
    my $retry = 2;
        foreach my $ip(@valid_ips) {
            @exp = xCAT::PPCcfg::connect(${$rspdevref->{$ip}}{username},${$rspdevref->{$ip}}{password}, $ip);
        ####################################
        # Successfully connected
        ####################################
            if ( ref($exp[0]) eq "LWP::UserAgent" ) {
                $goodip = $ip;
                xCAT::MsgUtils->verbose_message( $req, "log in successfully with $ip");
                last;
            }
        }
    my $msg = "login result is :".join(',', @exp);
    xCAT::MsgUtils->verbose_message( $req, $msg);
    ####################################
    # do resetnet
    ####################################
    unless ($goodip) {
        foreach my $fspport (@ns) {
		    $msginfo{$fspport} = "failed to log on with $exp[0]";
		}
        return \%msginfo;
    }
    my %handled;
    my $port;
	if (scalar(@portneedreset) == 2 ) { ## do resetnet for the other port first
	    $port = $portneedreset[0];
        my $ip = ${$iphashref->{$port}}{sip};
		if ($goodip eq $ip) {
		    $port = $portneedreset[1];
		} 
        xCAT::MsgUtils->verbose_message( $req, "begin to reset for port $port.. good ip is $goodip, ip is $ip....................................");
        my $rc = system("ping -q -n -c 1 -w 1 $ip > /dev/null") >>8;
        unless ($rc == 0) { 
            $ip = ${$iphashref->{$port}}{tip};
            $handled{network} = $ip.",".${$rspdevref->{$ip}}{args};
            my @cmds = ("network=$ip,${$rspdevref->{$ip}}{args}");
            my %request = (
                ppcretry    => 1,
                verbose     => 0,
                ppcmaxp     => 64,
                ppctimeout  => 0,
                fsptimeout  => 0,
                ppcretry    => 3,
                maxssh      => 8,
                arg         => \@cmds,
                method      => \%handled,
                command     => 'rspconfig',
                hwtype      => ${$rspdevref->{$ip}}{type},
                );
            xCAT::MsgUtils->verbose_message( $req, "Begin to do reset for $port, nic is $ip");
            my $result = xCAT::PPCfsp::handler($ip, \%request, \@exp, 1 );	
			if ($result) {
			    my $errcode = ${@$result[0]}{errorcode};
			    if ( $errcode == 0) {
			        $msginfo{$port} = "successful";
			    } else {
                    my $node = 	${@$result[0]}{node};
           	    	$msginfo{$port} = @{${@{${@$node[0]}{data}}[0]}{contents}}[0];
    }
			} else {
			    $msginfo{$port} = "failed with unknown reason";
			}	
		} else {
            $msginfo{$port} = "successful";
        }
    } 
    if ($port) {
        if ($port eq $portneedreset[0] ) {
            $port = $portneedreset[1];
        } else {
            $port = $portneedreset[0];
        }
    } else {
        $port = $portneedreset[0];
    }    
    xCAT::MsgUtils->verbose_message( $req, "begin to reset for port $port......................................");
    my $ip = ${$iphashref->{$port}}{sip};
    my $rc = system("ping -q -n -c 1 -w 1 $ip > /dev/null") >>8;
    unless ($rc == 0) { #should be unless!!!!!!!!!!!!!
        $ip = ${$iphashref->{$port}}{tip};
        $handled{network} = $ip.",".${$rspdevref->{$ip}}{args};
        my @cmds = ("network=$ip,${$rspdevref->{$ip}}{args}");
        my %request = (
            ppcretry    => 1,
            verbose     => 0,
            ppcmaxp     => 64,
            ppctimeout  => 0,
            fsptimeout  => 0,
            ppcretry    => 3,
            maxssh      => 8,
            arg         => \@cmds,
            method      => \%handled,
            command     => 'rspconfig',
            hwtype      => ${$rspdevref->{$ip}}{type},
            );
        xCAT::MsgUtils->verbose_message( $req, "Begin to do reset for $port, nic is $ip");
        my $result = xCAT::PPCfsp::handler($ip, \%request, \@exp);	
		if ($result) {
		    my $errcode = ${@$result[0]}{errorcode};
		    if ( $errcode == 0) {
		        $msginfo{$port} = "successful";
		    } else {
                my $node = 	${@$result[0]}{node};
            	$msginfo{$port} = @{${@{${@$node[0]}{data}}[0]}{contents}}[0];
    }
		} else {
		    $msginfo{$port} = "failed with unknown reason";
		}
    } else {
	    xCAT::PPCfsp::disconnect( \@exp );
                $msginfo{$port} = "successful";
    }	
    return \%msginfo;
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
        # Get userid/password
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
            xCAT::MsgUtils->verbose_message( $request, "user/passwd for $_ is $hmc->{$_}->{username} $hmc->{$_}->{password}");
        }
    }

    if ( %$fsp)
    {
        #############################################
        # Get FSP userid/password
        #############################################
        foreach ( keys %$fsp ) {
            ( $fsp->{$_}->{username}, $fsp->{$_}->{password}) = xCAT::PPCdb::credentials( $fsp->{$_}->{name}, lc($fsp->{$_}->{'type'}), "admin");
            xCAT::MsgUtils->verbose_message( $request, "user/passwd for $_ is $fsp->{$_}->{username} $fsp->{$_}->{password}");
        }
    }

    if ( %$bpa)
    {
        #############################################
        # Get BPA userid/password
        #############################################
        foreach ( keys %$bpa ) {
            ( $bpa->{$_}->{username}, $bpa->{$_}->{password}) = xCAT::PPCdb::credentials( $bpa->{$_}->{name}, lc($bpa->{$_}->{'type'}), "admin");
            xCAT::MsgUtils->verbose_message( $request, "user/passwd for $_ is $bpa->{$_}->{username} $bpa->{$_}->{password}");
        }
    }

    return (%$mm,%$hmc,%$fsp,%$bpa);
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
                #shift @$responses;
                #my $ip = @$responses[0];
                #my @rsp1 = (@$responses[1]);
                #$rsp_result{$ip} = \@rsp1;
                #$ip = @$responses[2];
                #if ($ip) {
                #    my @rsp2 = (@$responses[3]);
                #    $rsp_result{$ip} = \@rsp2;
                #}
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
##########################################################################
# Logon through remote FSP HTTP-interface
##########################################################################
sub connect {

    my $username = shift;
    my $passwd  = shift;
    my $server  = shift;
    my $verbose = shift;
    my $lwp_log;

    ##################################
    # Use timeout
    ##################################
    my $timeout = 10;

    ##################################
    # Redirect STDERR to variable
    ##################################
    if ( $verbose ) {
        close STDERR;
        if ( !open( STDERR, '>', \$lwp_log )) {
             return( "Unable to redirect STDERR: $!" );
        }
    }
    $IO::Socket::SSL::VERSION = undef;
    eval { require Net::SSL };

    ##################################
    # Turn on tracing
    ##################################
    if ( $verbose ) {
        LWP::Debug::level( '+' );
    }
    ##################################
    # Create cookie
    ##################################
    my $cookie = HTTP::Cookies->new();
    $cookie->set_cookie( 0,'asm_session','0','cgi-bin','','443',0,0,3600,0 );

    ##################################
    # Create UserAgent
    ##################################
    my $ua = LWP::UserAgent->new();

    ##################################
    # Set options
    ##################################
    my $url = "https://$server/cgi-bin/cgi?form=2";
    $ua->cookie_jar( $cookie );
    $ua->timeout( $timeout );

    ##################################
    # Submit logon
    ##################################
    my $res = $ua->post( $url,
       [ user     => $username,
         password => $passwd,
         lang     => "0",
         submit   => "Log in" ]
    );

    ##################################
    # Logon failed
    ##################################
    if ( !$res->is_success() ) {
        return( $lwp_log.$res->status_line );
    }
    ##################################
    # To minimize number of GET/POSTs,
    # if we successfully logon, we should
    # get back a valid cookie:
    #    Set-Cookie: asm_session=3038839768778613290
    #
    ##################################
    if ( $res->as_string =~ /Set-Cookie: asm_session=(\d+)/ ) {
        ##############################
        # Successful logon....
        # Return:
        #    UserAgent
        #    Server hostname
        #    UserId
        #    Redirected STDERR/STDOUT
        ##############################
        return( $ua,
                $server,
                $username,
                \$lwp_log );
    }
    ##############################
    # Logon error
    ##############################
    $res = $ua->get( $url );
    ##############################
    # Check for specific failures
    # $res->status_line is like "200 OK"
    # $res->content is like <!doctype html public "-//W3C//DTD HTML 4.01 Transitional//EN" .....Too many users......</html>
    # $res->base is like https://41.17.4.2/cgi-bin/cgi?form=2
    ##############################
    my $err;
    if ( $res->content =~ /Too many users/i ) {
        $err = "Too many users";
    }elsif ( $res->content =~ /Invalid user ID or password/i ) {
        $err = "Invalid user ID or password";
    }else{
        $err = "Logon failure with unknown reason";
    }

    return ($lwp_log.$err);
}



1;


