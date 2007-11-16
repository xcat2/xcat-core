# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCinv;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);


##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {

    my $request = shift;
    my $args    = $request->{arg};
    my %opt     = ();
    my @rinv    = qw(bus config model serial all);
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],
            "rinv -h|--help",
            "rinv -v|--version",
            "rinv [-V|--verbose] noderange " . join( '|', @rinv ),
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output" ]);
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

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version) )) { 
        return( usage() );
    }
    ####################################
    # Option -h for Help
    ####################################
    if ( exists( $opt{h} )) {
        return( usage() );
    }
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        return( \@VERSION );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Unsupported command
    ####################################
    my ($cmd) = grep(/^$ARGV[0]$/, @rinv );
    if ( !defined( $cmd )) {
        return(usage( "Invalid command: $ARGV[0]" ));
    }
    ####################################
    # Check for an extra argument
    ####################################
    shift @ARGV;
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # Set method to invoke 
    ####################################
    $request->{method} = $cmd; 
    return( \%opt );
}


##########################################################################
# Returns VPD (model-type,serial-number) 
##########################################################################
sub enumerate_vpd {

    my $exp     = shift;
    my $mtms    = shift;
    my $hash    = shift;
    my $filter  = shift;
    my $cecname;
    my @vpd;

    my ($name) = keys %{$hash->{$mtms}};
    my $type   = @{$hash->{$mtms}->{$name}}[4];

    ######################################
    # HMCs and IVMs 
    ######################################
    if ( $type =~ /^hmc|ivm$/ ) {
        my $hcp = xCAT::PPCcli::lshmc( $exp );
        my $Rc  = shift(@$hcp);

        ##############################
        # Return error
        ##############################
        if ( $Rc != SUCCESS ) {
            return( [$Rc,@$hcp[0]] );
        }
        ##############################
        # Success
        ##############################
        @vpd = split /,/, @$hcp[0];
    }
    ######################################
    # BPAs  
    ######################################
    elsif ( $type =~ /^bpa$/ ) {
        my $filter = "type_model,serial_num";
        my $frame  = xCAT::PPCcli::lssyscfg( $exp, $type, $mtms, $filter );
        my $Rc = shift(@$frame);

        ##############################
        # Return error
        ##############################
        if ( $Rc != SUCCESS ) {
            return( [$Rc,@$frame[0]] );
        }
        ##############################
        # Success
        ##############################
        @vpd = split /,/, @$frame[0];
    }
    ######################################
    # CECs and LPARs  
    ######################################
    else {
        ##############################
        # Send command for CEC only
        ##############################
        my $cec = xCAT::PPCcli::lssyscfg( $exp, "fsp", $mtms, $filter );
        my $Rc = shift(@$cec);

        ##############################
        # Return error
        ##############################
        if ( $Rc != SUCCESS ) {
            return( [$Rc,@$cec[0]] );
        }
        ##############################
        # Success 
        ##############################
        @vpd = split /,/, @$cec[0];
    }
    my %outhash = (
        model  => $vpd[0],
        serial => $vpd[1]   
    );
    return( [SUCCESS,\%outhash] );
}


##########################################################################
# Returns memory/processor information for CEC/LPARs 
##########################################################################
sub enumerate_cfg {

    my $exp     = shift;
    my $mtms    = shift;
    my $hash    = shift;
    my %outhash = ();
    my $sys     = 0;
    my @cmds    = (
        [ "sys", "proc", "installed_sys_proc_units" ],
        [ "sys", "mem",  "installed_sys_mem" ],
        [ "lpar","proc", "lpar_name,curr_procs" ],
        [ "lpar","mem",  "lpar_name,curr_mem" ]
    );
    my $cecname;

    my ($name) = keys %{$hash->{$mtms}};
    my $type   = @{$hash->{$mtms}->{$name}}[4];

    ######################################
    # Invalid target hardware
    ######################################
    if ( $type !~ /^fsp|lpar$/ ) {
        return( [RC_ERROR,"Information only available for CEC/LPAR"] );
    }
    ######################################
    # Check for CECs in list
    ######################################
    while (my ($name,$d) = each(%{$hash->{$mtms}}) ) { 
        if ( @$d[4] eq "fsp" ) {
            $cecname = $name;
            last;
        }
    }
    ######################################
    # No CECs - Skip command for CEC
    ######################################
    if ( !defined( $cecname )) {
        shift @cmds;
        shift @cmds;
    }
    ######################################
    # No LPARs - Skip command for LPAR
    ######################################
    if (( keys %{$hash->{$mtms}} == 1 ) and ( scalar(@cmds) == 4 )) {
        pop @cmds;
        pop @cmds;
    }
            
    foreach my $cmd( @cmds ) {
        my $result = xCAT::PPCcli::lshwres( $exp, $cmd, $mtms ); 
        my $Rc = shift(@$result);

        ##################################
        # Expect error
        ##################################
        if ( $Rc != SUCCESS ) {
            return( [$Rc,@$result[0]] );
        }
        ##################################
        # Success...
        # lshwres does not return CEC name
        # For CEC commands, insert name 
        ##################################
        if ( @$cmd[0] eq "sys" ) {
            foreach ( @$result[0] ) {
                s/(.*)/$cecname,$1/;
            }
        }
        ##################################
        # Save by CEC/LPAR name 
        ##################################
        foreach ( @$result ) {
            my ($name,$value) = split /,/;
            push @{$outhash{ $name }}, $value;
        }
    }
    return( [SUCCESS,\%outhash] );
}


##########################################################################
# Returns I/O bus information  
##########################################################################
sub enumerate_bus {

    my $exp     = shift;
    my $mtms    = shift;
    my $hash    = shift;
    my $filter  = shift;
    my %outhash = ();
    my @res     = qw(lpar);
    my @cmds    = (
        undef, 
        "io --rsubtype slot", 
        $filter
    );
    my $cecname;

    my ($name) = keys %{$hash->{$mtms}};
    my $type   = @{$hash->{$mtms}->{$name}}[4];

    ##################################
    # Invalid target hardware 
    ##################################
    if ( $type !~ /^fsp|lpar$/ ) {
        return( [RC_ERROR,"Bus information only available for CEC/LPAR"] );
    }
    ##################################
    # Send command for CEC only 
    ##################################
    my $cecs = xCAT::PPCcli::lshwres( $exp, \@cmds, $mtms );
    my $Rc = shift(@$cecs);

    ##################################
    # Return error
    ##################################
    if ( $Rc != SUCCESS ) {
        return( [$Rc,@$cecs[0]] );
    }
    ##################################
    # Success 
    ##################################
    my @bus = @$cecs;

    ##################################
    # Check for CECs in list
    ##################################
    foreach ( keys %{$hash->{$mtms}} ) {
        if ( @{$hash->{$mtms}->{$_}}[4] eq "fsp" ) {
            $cecname = $_;
            last;
        }
    }
    ##################################
    # Get LPAR names
    ##################################
    my $lpars = xCAT::PPCcli::lssyscfg( $exp, "lpar", $mtms, "name" );
    $Rc = shift(@$lpars);

    ##################################
    # Return error
    ##################################
    if ( $Rc != SUCCESS ) {
        return( [$Rc,@$lpars[0]] );
    }
    ##################################
    # Save LPARs by name
    ##################################
    foreach ( @$lpars ) {
        $outhash{$_} = \@bus;
    }
    ##################################
    # Save CEC by name too
    ##################################
    if ( defined( $cecname )) {
        $outhash{$cecname} = \@bus;
    }
    return( [SUCCESS,\%outhash] );
}



##########################################################################
# Returns I/O bus information 
##########################################################################
sub bus {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my @result  = ();
    my $filter  = "drc_name,bus_id,description";

    while (my ($mtms,$h) = each(%$hash) ) {
        #####################################
        # Get information for this CEC
        #####################################
        my $bus = enumerate_bus( $exp, $mtms, $hash, $filter );
        my $Rc = shift(@$bus);
        my $data = @$bus[0];

        while (my ($name) = each(%$h) ) {
            #################################
            # Output header 
            #################################
            push @result, [$name,"I/O Bus Information"];

            #################################
            # Output error 
            #################################
            if ( $Rc != SUCCESS ) {
                push @result, [$name,@$bus[0]];
                next;
            }
            #################################
            # Node not found 
            #################################
            if ( !exists( $data->{$name} )) {
                push @result, [$name,"Node not found"];
                next;
            } 
            #################################
            # Output values 
            #################################
            foreach ( @{$data->{$name}} ) {
                s/,/:/;
                push @result, [$name,$_];
            }
        }
    }
    return( \@result );
}


##########################################################################
# Returns VPD information 
##########################################################################
sub vpd {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my @cmds    = $request->{method};
    my @result  = ();
    my $filter  = "type_model,serial_num";
    my %prefix  = (
       model  => ["Machine Type/Model",0],
       serial => ["Serial Number",     1]
    );

    ######################################### 
    # Convert "all"
    ######################################### 
    if ( $cmds[0] eq "all" )  {
        @cmds = qw( model serial );
    }

    while (my ($mtms,$h) = each(%$hash) ) {
        #####################################
        # Get information for this CEC
        #####################################
        my $vpd = enumerate_vpd( $exp, $mtms, $hash, $filter );
        my $Rc = shift(@$vpd);
        my $data = @$vpd[0];

        while (my ($name) = each(%$h) ) {
            foreach ( @cmds ) {
                #############################
                # Output error
                #############################
                if ( $Rc != SUCCESS ) {
                    push @result, [$name,"@{$prefix{$_}}[0]: @$vpd[0]"];  
                    next;
                } 
                #############################
                # Output value 
                #############################
                my $value = "@{$prefix{$_}}[0]: $data->{$_}"; 
                push @result, [$name,$value];   
            }
        }
    }
    return( \@result );
}



##########################################################################
# Returns memory/processor information 
##########################################################################
sub config {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my @result  = ();
    my @prefix  = ( 
        "Number of Processors: %s", 
        "Total Memory (MB): %s"
    );

    while (my ($mtms,$h) = each(%$hash) ) {
        #####################################
        # Get information for this CEC
        #####################################
        my $cfg = enumerate_cfg( $exp, $mtms, $hash );
        my $Rc = shift(@$cfg);
        my $data = @$cfg[0];
            
        while (my ($name) = each(%$h) ) {
            #################################
            # Output header
            #################################
            push @result, [$name,"Machine Configuration Info"];
            my $i;

            foreach ( @prefix ) {
                #############################
                # Output error
                #############################
                if ( $Rc != SUCCESS ) {
                    my $value = sprintf( "$_", $data );
                    push @result, [$name,$value];
                    next;
                }
                #############################
                # Node not found
                #############################
                if (!exists( $data->{$name} )) {
                    push @result, [$name,"Node not found"];
                    next;
                }
                #############################
                # Output value
                #############################
                my $value = sprintf( $_, @{$data->{$name}}[$i++] );
                push @result, [$name,$value];
            }
        }
    }
    return( \@result );
}


##########################################################################
# Returns serial-number
##########################################################################
sub serial {
    return( vpd(@_) );
}

##########################################################################
# Returns machine-type-model
##########################################################################
sub model {
    return( vpd(@_) );
}


##########################################################################
# Returns all inventory information
##########################################################################
sub all {

    my @result = ( 
        @{vpd(@_)}, 
        @{bus(@_)}, 
        @{config(@_)} 
    );       
    return( \@result );
}


1;
