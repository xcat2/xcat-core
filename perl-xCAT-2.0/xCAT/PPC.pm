# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPC;
use strict;
use xCAT::Table;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use Time::HiRes qw(gettimeofday);
use IO::Select;
use xCAT::PPCcli;
use xCAT::PPCfsp;   


##########################################
# Globals
##########################################
my %modules = (
  rinv      => "xCAT::PPCinv",
  rpower    => "xCAT::PPCpower",
  rvitals   => "xCAT::PPCvitals",
  rscan     => "xCAT::PPCscan",
  mkvm      => "xCAT::PPCvm",
  rmvm      => "xCAT::PPCvm",
  lsvm      => "xCAT::PPCvm",
  chvm      => "xCAT::PPCvm",
  rnetboot  => "xCAT::PPCboot",
  getmacs   => "xCAT::PPCmac",
  reventlog => "xCAT::PPClog"
);

##########################################
# Database errors
##########################################
my %errmsg = (
  NODE_UNDEF =>"Node not defined in '%s' database",
  NO_ATTR    =>"'%s' not defined in '%s' database",  
  DB_UNDEF   =>"'%s' database not defined"
);


##########################################################################
# Invokes the callback with the specified message                    
##########################################################################
sub send_msg {

    my $request = shift;
    my %output;

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};

        $output{data} = \@_;
        $callback->( \%output );
    }
}


##########################################################################
# Fork child to execute remote commands
##########################################################################
sub process_command {

    my $request  = shift;
    my $maxp     = 64;
    my %nodes    = ();
    my $callback = $request->{callback};
    my $start;

    #######################################
    # Get max processes to fork
    #######################################
    my $sitetab = xCAT::Table->new('site');
    if ( defined( $sitetab )) {
        my ($ent) = $sitetab->getAttribs({'key'=>'ppcmaxp'},'value');
        if ( defined($ent) ) { 
            $maxp = $ent->{value}; 
        }
    }
    if ( exists( $request->{verbose} )) {
        $start = Time::HiRes::gettimeofday();
    }
    #######################################
    # Group nodes based on command
    #######################################
    my $nodes = preprocess_nodes( $request );
    if ( !defined( $nodes )) {
        return(1);
    }
    #######################################
    # Fork process
    #######################################
    my $children = 0;
    $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
    my $fds = new IO::Select;

    foreach ( @$nodes ) {
        while ( $children > $maxp ) {
            sleep(0.1);
        }
        my $pipe = fork_cmd( @$_[0], @$_[1], $request );
        if ( $pipe ) {
            $fds->add( $pipe );
            $children++;
        }
    }
    #######################################
    # Process responses from children
    #######################################
    while ( $children > 0 ) {
        child_response( $callback, $fds );
    } 
    if ( exists( $request->{verbose} )) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $msg = sprintf( "Total Elapsed Time: %.3f sec\n", $elapsed );
        trace( $request, $msg );
    }
    return(0);
}


##########################################################################
# Verbose mode (-V)
##########################################################################
sub trace {

    my $request = shift;
    my $msg     = shift;

    my ($sec,$min,$hour,$mday,$mon,$yr,$wday,$yday,$dst) = localtime(time);
    my $msg = sprintf "%02d:%02d:%02d %5d %s", $hour,$min,$sec,$$,$msg;
    send_msg( $request, $msg );
}


##########################################################################
# Send response from child process back to xCAT client
##########################################################################
sub child_response {

    my $callback = shift;
    my $fds = shift;
    my @ready_fds = $fds->can_read(1);

    foreach my $rfh (@ready_fds) {
        my $data;

        #################################
        # Read from child process
        #################################
        if ( $data = <$rfh> ) {
            while ($data !~ /ENDOFFREEZE6sK4ci/) {
                $data .= <$rfh>;
            }
            my $responses = thaw($data);
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
# Group nodes depending on command
##########################################################################
sub preprocess_nodes {

    my $request   = shift;
    my $noderange = $request->{node};
    my $method    = $request->{method};
    my %nodehash  = ();
    my @nodegroup = ();
    my %tabs      = ();

    ########################################
    # Special cases
    #   rscan - Nodes are hardware control pts 
    #   Direct-attached FSP 
    ########################################
    if (( $request->{command} eq "rscan" ) or
        ( $request->{hwtype} eq "fsp" )) {

        my $tab = ($request->{hwtype} eq "fsp") ? "ppcdirect" : "ppchcp"; 
        my $db  = xCAT::Table->new( $tab );

        if ( !defined( $db )) {
            send_msg( $request, sprintf( $errmsg{DB_UNDEF}, $tab )); 
            return undef;
        } 
        ####################################
        # Process each node
        ####################################
        foreach ( @$noderange ) {
            my ($ent) = $db->getAttribs( {hcp=>$_},"hcp" );

            if ( !defined( $ent )) {
                my $msg = sprintf( "$_: $errmsg{NODE_UNDEF}", $tab );
                send_msg( $request, $msg );
                next;
            }
            ################################
            # Save values
            ################################
            push @nodegroup,[$_];
        }
        return( \@nodegroup );
    }

    ##########################################
    # Open databases needed
    ##########################################
    foreach ( qw(ppc vpd nodelist) ) {
        $tabs{$_} = xCAT::Table->new($_);

        if ( !exists( $tabs{$_} )) { 
            send_msg( $request, sprintf( $errmsg{DB_UNDEF}, $_ )); 
            return undef;
        }
    }
    ##########################################
    # Group nodes
    ##########################################
    foreach my $node ( @$noderange ) {
        my $d = resolve( $request, $node, \%tabs );

        ######################################
        # Error locating node attributes
        ######################################
        if ( ref($d) ne 'ARRAY' ) {
            send_msg( $request,"$node: $d");
            next;
        }
        ######################################
        # Get data values 
        ######################################
        my $hcp  = @$d[3];
        my $mtms = @$d[2];

        $nodehash{$hcp}{$mtms}{$node} = $d;
    } 
    ##########################################
    # Group the nodes - we will fork one 
    # process per nodegroup array element. 
    ##########################################

    ##########################################
    # These commands are grouped on an
    # LPAR-by-LPAR basis - fork one process
    # per LPAR.  
    ##########################################
    if ( $method =~ /^getmacs|rnetboot$/ ) {
        while (my ($hcp,$hash) = each(%nodehash) ) {    
            while (my ($mtms,$h) = each(%$hash) ) {
                while (my ($lpar,$d) = each(%$h)) {
                    push @$d, $lpar;
                    push @nodegroup,[$hcp,$d]; 
                }
            }
        }
        return( \@nodegroup );
    }
    ##########################################
    # Power control commands are grouped 
    # by CEC which is the smallest entity 
    # that commands can be sent to in parallel.  
    # If commands are sent in parallel to a
    # single CEC, the CEC itself will serialize 
    # them - fork one process per CEC.
    ##########################################
    elsif ( $method =~ /^powercmd/ ) {
        while (my ($hcp,$hash) = each(%nodehash) ) {    
            while (my ($mtms,$h) = each(%$hash) ) {    
                push @nodegroup,[$hcp,$h]; 
            }
        }
        return( \@nodegroup );
    }
    ##########################################
    # All other commands are grouped by
    # hardware control point - fork one
    # process per hardware control point.
    ##########################################
    while (my ($hcp,$hash) = each(%nodehash) ) {    
        push @nodegroup,[$hcp,$hash]; 
    }
    return( \@nodegroup );
}



##########################################################################
# Findis attributes for given node is various databases 
##########################################################################
sub resolve {

    my $request = shift;
    my $node    = shift;
    my $tabs    = shift;
    my @attribs = qw(id profile parent hcp);
    my @values  = ();

    #################################
    # Get node type 
    #################################
    my ($ent) = $tabs->{nodelist}->getAttribs({'node'=>$node}, "nodetype" );
    if ( !defined( $ent )) {
        return( sprintf( $errmsg{NODE_UNDEF}, "nodelist" )); 
    }
    #################################
    # Check for type
    #################################
    if ( !exists( $ent->{nodetype} )) {
        return( sprintf( $errmsg{NO_ATTR}, $ent->{nodetype}, "nodelist" ));
    }
    #################################
    # Check for valid "type"
    #################################
    if ( $ent->{nodetype} !~ /^fsp|bpa|osi$/ ) { 
        return( "Invalid node type: $ent->{nodetype}" );
    }
    my $type = $ent->{nodetype};

    #################################
    # Get attributes 
    #################################
    my ($att) = $tabs->{ppc}->getAttribs({'node'=>$node}, @attribs );
 
    if ( !defined( $att )) { 
        return( sprintf( $errmsg{NODE_UNDEF}, "ppc" )); 
    }
    #################################
    # Special lpar processing 
    #################################
    if ( $type =~ /^osi$/ ) {
        $att->{bpa}  = 0;
        $att->{type} = "lpar";
        $att->{node} = $att->{parent};

        if ( !exists( $att->{parent} )) {
            return( sprintf( $errmsg{NO_ATTR}, "parent", "ppc" )); 
        }
        #############################
        # Get BPA (if any)
        #############################
        if (( $request->{command} eq "rvitals" ) &&
            ( $request->{method}  =~ /^all|temp$/ )) { 
           my ($ent) = $tabs->{ppc}->getAttribs(
                                 {node=>$att->{parent}}, "parent" );
     
           #############################
           # Find MTMS in vpd database 
           #############################
           if (( defined( $ent )) && exists( $ent->{parent} )) {
               my @attrs = qw(mtm serial);
               my ($vpd) = $tabs->{vpd}->getAttribs(
                                 {node=>$ent->{parent}},@attrs );

               if ( !defined( $vpd )) {
                   return( sprintf( $errmsg{NO_UNDEF}, "vpd" )); 
                }
                ########################
                # Verify attributes
                ########################
                foreach ( @attrs ) {
                    if ( !exists( $vpd->{$_} )) {
                        return( sprintf( $errmsg{NO_ATTR}, $_, "vpd" ));
                    }
                }
                $att->{bpa} = "$vpd->{mtm}*$vpd->{serial}";
            }
        }
    }
    #################################
    # Optional and N/A fields 
    #################################
    elsif ( $type =~ /^fsp$/ ) {
        $att->{profile} = 0;
        $att->{id}      = 0;
        $att->{fsp}     = 0;
        $att->{node}    = $node;
        $att->{type}    = $type;
        $att->{parent}  = exists($att->{parent}) ? $att->{parent} : 0;
        $att->{bpa}     = $att->{parent};
    }
    elsif ( $type =~ /^bpa$/ ) {
        $att->{profile} = 0;
        $att->{id}      = 0;
        $att->{bpa}     = 0;
        $att->{parent}  = 0;
        $att->{fsp}     = 0;
        $att->{node}    = $node;
        $att->{type}    = $type;
    }
    #################################
    # Find MTMS in vpd database 
    #################################
    my @attrs = qw(mtm serial);
    my ($vpd) = $tabs->{vpd}->getAttribs({node=>$att->{node}}, @attrs );

    if ( !defined( $vpd )) {
        return( sprintf( $errmsg{NODE_UNDEF}, "vpd" )); 
    }
    ################################
    # Verify both vpd attributes
    ################################
    foreach ( @attrs ) {
        if ( !exists( $vpd->{$_} )) {
            return( sprintf( $errmsg{NO_ATTR}, $_, "vpd" ));
        }
    }
    $att->{fsp} = "$vpd->{mtm}*$vpd->{serial}";

    #################################
    # Verify required attributes
    #################################
    foreach my $at ( @attribs ) {
        if ( !exists( $att->{$at} )) {
            return( sprintf( $errmsg{NO_ATTR}, $at, "ppc" ));
        } 
    }
    #################################
    # Build array of data 
    #################################
    foreach ( qw(id profile fsp hcp type bpa) ) {
        push @values, $att->{$_};
    }
    return( \@values );
}



##########################################################################
# Forks a process to run the ssh command
##########################################################################
sub fork_cmd {

    my $host    = shift;
    my $nodes   = shift;
    my $request = shift;

    #######################################
    # Pipe childs output back to parent
    #######################################
    my $parent;
    my $child;
    pipe $parent, $child;
    my $pid = fork;

    if ( !defined($pid) ) {
        ###################################
        # Fork error
        ###################################
        send_msg( $request, "Fork error: $!" );
        return undef;
    }
    elsif ( $pid == 0 ) {
        ###################################
        # Child process
        ###################################
        close( $parent );
        $request->{pipe} = $child;

        invoke_cmd( $host, $nodes, $request );
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
# Run the command, process the response, and send to parent
##########################################################################
sub invoke_cmd {

    my $host    = shift;
    my $nodes   = shift;
    my $request = shift;
    my $hwtype  = $request->{hwtype};
    my $verbose = $request->{verbose};
    my @exp;
    my @outhash;

    ########################################
    # Direct-attached FSP handler 
    ########################################
    if ( $hwtype eq "fsp" ) {
        my $result = xCAT::PPCfsp::handler( $host, $request );

        my $out = $request->{pipe};
        print $out freeze( $result );
        print $out "\nENDOFFREEZE6sK4ci\n";
        return;
    }
    ########################################
    # Connect to list of remote servers
    ########################################
    foreach ( split /,/, $host ) {
        @exp = xCAT::PPCcli::connect( $hwtype, $_, $verbose );

        ####################################
        # Successfully connected 
        ####################################
        if ( ref($exp[0]) eq "Expect" ) {
            last;
        }
    }
    ########################################
    # Error connecting 
    ########################################
    if ( ref($exp[0]) ne "Expect" ) {
        send_msg( $request, $exp[0] );
        return;
    }
    ########################################
    # Process specific command 
    ########################################
    my $result = runcmd( $request, $nodes, \@exp );

    ########################################
    # Output verbose Expect 
    ########################################
    if ( $verbose ) {
        my $expect_log = $exp[6];
        send_msg( $request, $$expect_log );
    }
    ########################################
    # Close connection to remote server
    ########################################
    xCAT::PPCcli::disconnect( \@exp );

    ########################################
    # Return error
    ######################################## 
    if ( ref($result) ne 'ARRAY' ) {
        send_msg( $request, $result );
        return;
    }
    ########################################
    # Send result back to parent process
    ########################################
    if ( @$result[0] eq "FORMATDATA6sK4ci" ) {
        shift(@$result);
        my $out = $request->{pipe};
        print $out freeze( [@$result] );
        print $out "\nENDOFFREEZE6sK4ci\n";
        return;
    }
    ########################################
    # Format and send back to parent
    ########################################
    foreach ( @$result ) {
        my %output;
        $output{node}->[0]->{name}->[0] = @$_[0];
        $output{node}->[0]->{data}->[0]->{contents}->[0] = @$_[1];
        push @outhash, \%output;
    }
    my $out = $request->{pipe};
    print $out freeze( [@outhash] );
    print $out "\nENDOFFREEZE6sK4ci\n";
}


##########################################################################
# Run the command method specified
##########################################################################
sub runcmd {

    my $request = shift;
    my $cmd     = $request->{command};
    my $method  = $request->{method};
    my $hwtype  = $request->{hwtype};
    my $modname = $modules{$cmd};

    ######################################
    # Command not supported
    ######################################
    if ( !defined( $modname )) {
        return( ["$cmd not a supported command by $hwtype method"] );
    }   
    ######################################
    # Load specific module
    ######################################
    unless ( eval "require $modname" ) {
        return( ["Can't locate $modname"] );
    }
    ######################################
    # Invoke  method 
    ######################################
    no strict 'refs';
    my $result = ${$modname."::"}{$method}->($request,@_);
    use strict;

    return( $result );

}


##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {

    my $package  = shift;
    my $req      = shift;
    my $callback = shift;

    ####################################
    # Get hwtype 
    ####################################
    $package =~ s/xCAT_plugin:://;

    ####################################
    # Build hash to pass around 
    ####################################
    my %request; 
    $request{command}  = $req->{command}->[0];
    $request{arg}      = $req->{arg};
    $request{node}     = $req->{node};
    $request{stdin}    = $req->{stdin}->[0]; 
    $request{hwtype}   = $package; 
    $request{callback} = $callback; 
    $request{method}   = "parse_args";

    ####################################
    # Process command-specific options
    ####################################
    my $opt = runcmd( \%request );

    ####################################
    # Return error
    ####################################
    if ( ref($opt) eq 'ARRAY' ) {
        send_msg( \%request, @$opt );
        return(1);
    }
    ####################################
    # Option -V for verbose output
    ####################################
    if ( exists( $opt->{V} )) {
        $request{verbose} = 1;
    }
    ####################################
    # Process remote command
    ####################################
    $request{opt} = $opt; 
    process_command( \%request );
}




1;



