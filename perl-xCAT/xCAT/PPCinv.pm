# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCinv;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::TableUtils;
require xCAT::data::ibmhwtypes;


##########################################
# Maps HMC "lslic" attributes to text
##########################################
my @licmap = (
    ["ecnumber",               "Release Level  "],
    ["activated_level",        "Active Level   "],
    ["installed_level",        "Installed Level"],
    ["accepted_level",         "Accepted Level "],
    ["curr_ecnumber_a",        "Release Level A"],
    ["curr_level_a",           "Level A        "],
    ["curr_ecnumber_b",        "Release Level B"],
    ["curr_level_b",           "Level B        "],
    ["curr_ecnumber_primary",  "Release Level Primary"],
    ["curr_level_primary",     "Level Primary  "],
    ["curr_ecnumber_secondary","Release Level Secondary"],
    ["curr_level_secondary",   "Level Secondary"]
);


##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {

    my $request = shift;
    my $command = $request->{command};
    my $args    = $request->{arg};
    my %opt     = ();
    my @rinv    = qw(bus config model serial firm all);

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($command);
        return( [ $_[0], $usage_string] );
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

    if ( !GetOptions( \%opt, qw(V|verbose t) )) { 
        return( usage() );
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
    if (exists($opt{t}) and $cmd ne "model") {
        return(["Option 't' can only work with 'model'."]);
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
    my $filter  = "type_model,serial_num";
    my @vpd;

    my ($name) = keys %{$hash->{$mtms}};
    my $type   = @{$hash->{$mtms}->{$name}}[4];

    ##################################
    # BPAs  
    ##################################
    if ( $type =~ /^bpa$/ ) {
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
    ##################################
    # CECs and LPARs  
    ##################################
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
        [ "lpar","proc", "lpar_id,curr_procs" ],
        [ "lpar","mem",  "lpar_id,curr_mem" ]
    );
    my $cec;
    my ($name) = keys %{$hash->{$mtms}};
    my $type   = @{$hash->{$mtms}->{$name}}[4];

    ######################################
    # Invalid target hardware
    ######################################
    if ( $type !~ /^(fsp|lpar|cec)$/ ) {
        return( [RC_ERROR,"Information only available for CEC/LPAR"] );
    }
    ######################################
    # Check for CECs in list
    ######################################
    while (my ($name,$d) = each(%{$hash->{$mtms}}) ) { 
        if ( @$d[4] =~ /^(fsp|cec)$/ ) {
            $cec = $name;
            last;
        }
    }
    ######################################
    # No CECs - Skip command for CEC
    ######################################
    if ( !defined( $cec )) {
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
        ##################################
        if ( @$cmd[0] eq "sys" ) {
            foreach ( @$result[0] ) {
                s/(.*)/0,$1/;
            }
        }
        ##################################
        # Save by CEC/LPAR id 
        ##################################
        foreach ( @$result ) {
            my ($id,$value) = split /,/;
            push @{$outhash{$id}}, $value;
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
    my %outhash = ();
    my @res     = qw(lpar);
    my $filter  = "drc_name,bus_id,description";
    my @cmds    = (
        undef, 
        "io --rsubtype slot", 
        $filter
    );
    my $cec;
    my ($name) = keys %{$hash->{$mtms}};
    my $type   = @{$hash->{$mtms}->{$name}}[4];

    ##################################
    # Invalid target hardware 
    ##################################
    if ( $type !~ /^(fsp|lpar|cec)$/ ) {
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
        if ( @{$hash->{$mtms}->{$_}}[4] =~ /^(fsp|cec)$/ ) {
            $cec = $_;
            last;
        }
    }
    ##################################
    # Get LPAR ids 
    ##################################
    my $lpars = xCAT::PPCcli::lssyscfg( $exp, "lpar", $mtms, "lpar_id" );
    $Rc = shift(@$lpars);

    ##################################
    # Return error
    ##################################
    if ( $Rc != SUCCESS ) {
        return( [$Rc,@$lpars[0]] );
    }
    ##################################
    # Save LPARs by id 
    ##################################
    foreach ( @$lpars ) {
        $outhash{$_} = \@bus;
    }
    ##################################
    # Save CEC by id
    ##################################
    if ( defined( $cec )) {
        $outhash{"0"} = \@bus;
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

    while (my ($mtms,$h) = each(%$hash) ) {
        #####################################
        # Get information for this CEC
        #####################################
        my $bus = enumerate_bus( $exp, $mtms, $hash );
        my $Rc = shift(@$bus);
        my $data = @$bus[0];

        while (my ($name,$d) = each(%$h) ) {
            ##################################
            # Look up by lparid
            ##################################
            my $type = @$d[4];
            my $id   = ($type=~/^(fsp|cec)$/) ? 0 : @$d[0];

            #################################
            # Output header 
            #################################
            push @result, [$name,"I/O Bus Information"];

            #################################
            # Output error 
            #################################
            if ( $Rc != SUCCESS ) {
                push @result, [$name,@$bus[0],$Rc];
                next;
            }
            #################################
            # Node not found 
            #################################
            if ( !exists( $data->{$id} )) {
                push @result, [$name,"Node not found",1];
                next;
            } 
            #################################
            # Output values 
            #################################
            foreach ( @{$data->{$id}} ) {
                push @result, [$name,$_,$Rc];
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
        my $vpd = enumerate_vpd( $exp, $mtms, $hash );
        my $Rc = shift(@$vpd);
        my $data = @$vpd[0];

        while (my ($name) = each(%$h) ) {
            foreach ( @cmds ) {
                #############################
                # Output error
                #############################
                if ( $Rc != SUCCESS ) {
                    push @result, [$name,"@{$prefix{$_}}[0]: @$vpd[0]",$Rc];  
                    next;
                } 
                #############################
                # Output value 
                #############################
                if ($_ eq 'model' and exists($request->{opt}->{t})) {
		            my $tmp_pre = xCAT::data::ibmhwtypes::parse_args($data->{$_});
		            if (defined($tmp_pre))  {
			            xCAT::TableUtils->updatenodegroups($name, $tmp_pre);
		            }
		        }
                my $value = "@{$prefix{$_}}[0]: $data->{$_}"; 
                push @result, [$name,$value,$Rc];   
            }
        }
    }
    return( \@result );
}


##########################################################################
# Returns FSP/BPA firmware information
##########################################################################
sub firmware {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my @result;

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {

            #####################################
            # Command only supported on FSP/BPA/LPARs 
            #####################################
            if ( @$d[4] !~ /^(fsp|bpa|cec|frame|lpar)$/ ) {
                push @result, 
                    [$name,"Information only available for CEC/BPA/LPAR",RC_ERROR];
                next; 
            }
	        #################
	        #For support on  Lpars, the flag need to be changed.
	        ##########
	        if(@$d[4] =~ /^(lpar|cec)$/)	{
		        @$d[4] = "fsp";
	        }
	        if(@$d[4] =~ /^frame$/)	{
		        @$d[4] = "bpa";
	        }            
           my $values = xCAT::PPCcli::lslic( $exp, $d );
            my $Rc = shift(@$values);
    
            #####################################
            # Return error
            #####################################
            if ( $Rc != SUCCESS ) {
                push @result, [$name,@$values[0],$Rc];
                next; 
            }
            #####################################
            # Success - format IVM results
            #####################################
            if ( $hwtype eq "ivm" ) {
                if ( @$values[0] !~ 
                      /^system:(\w+)\s+\(t\)\s+(\w+)\s+\(p\)\s+(\w+)\s+/ ) {
                    push @result, [$name,@$values[0],$Rc];
                    next;
                }
                push @result, [$name,"Activated Level: $1",$Rc]; 
                push @result, [$name,"Permanent Level: $2",$Rc]; 
                push @result, [$name,"Temporary Level: $3",$Rc]; 
                next;
            }
            #####################################
            # Format HMC results
            #####################################
            foreach ( @licmap ) {  
                if ( @$values[0] =~ /@$_[0]=(\w+)/ ) {
                    push @result, [$name,"@$_[1]: $1",$Rc];
                }
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
            
        while (my ($name,$d) = each(%$h) ) {
            ##################################
            # Look up by lparid
            ##################################
            my $type = @$d[4];
            my $id   = ($type=~/^(fsp|cec)$/) ? 0 : @$d[0];

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
                    push @result, [$name,$value,$Rc];
                    next;
                }
                #############################
                # Node not found
                #############################
                if (!exists( $data->{$id} )) {
                    push @result, [$name,"Node not found",1];
                    next;
                }
                #############################
                # Output value
                #############################
                my $value = sprintf( $_, @{$data->{$id}}[$i++] );
                push @result, [$name,$value,$Rc];
            }
        }
    }
    return( \@result );
}


##########################################################################
# Returns firmware version 
##########################################################################
sub firm {
    return( firmware(@_) );
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
        @{config(@_)},
        @{firmware(@_)} 
    );       
    return( \@result );
}


1;


