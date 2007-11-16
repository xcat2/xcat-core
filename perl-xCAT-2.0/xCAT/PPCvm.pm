# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCvm;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCdb;


##############################################
# Globals
##############################################
my %method = (
    mkvm => \&mkvm_parse_args,
    lsvm => \&lsvm_parse_args,
    rmvm => \&rmvm_parse_args, 
    chvm => \&chvm_parse_args 
);


##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my $cmd     = $request->{command};

    ###############################
    # Invoke correct parse_args 
    ###############################
    my $result = $method{$cmd}( $request );
    return( $result ); 
}


##########################################################################
# Parse the chvm command line for options and operands
##########################################################################
sub chvm_parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0], 
            "chvm -h|--help",
            "chvm -v|--version",
            "chvm [-V|--verbose] noderange",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output" ]);
    };
    ####################################
    # Configuration file required 
    ####################################
    if ( !exists( $request->{stdin} ) ) {
        return(usage( "Configuration file not specified" ));
    }
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        $request->{method} = $cmd;
        return( \%opt );
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
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # No operands - add command name 
    ####################################
    $request->{method} = $cmd;
    return( \%opt );
}


##########################################################################
# Parse the mkvm command line for options and operands
##########################################################################
sub mkvm_parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0], 
            "mkvm -h|--help",
            "mkvm -v|--version",
            "mkvm [-V|--verbose] singlenode -i id -n name",
            "mkvm [-V|--verbose] singlecec -c cec",
            "    -h   writes usage information to standard output",
            "    -c   target cec",
            "    -i   new partition numeric id",
            "    -n   new partition name",
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
    # Only 1 node allowed 
    #############################################
    if ( scalar( @{$request->{node}} ) > 1) {
        return(usage( "multiple nodes specified" ));
    } 
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version i=s n=s c=s) )) {
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
    # Check for non-zero integer 
    ####################################
    if ( exists( $opt{i} )) {
        if ( $opt{i} =~ /^[1-9]{1}$|^[1-9]{1}[0-9]+$/ ) {
            return(usage( "Invalid entry: $opt{i}" ));
        }
    }
    ####################################
    # -i and -n not valid with -c 
    ####################################
    if ( exists( $opt{c} ) ) {
        if ( exists($opt{i}) or exists($opt{n})) {
            return( usage() );
        }
    }
    ####################################
    # If -i and -n, both required
    ####################################
    elsif ( !exists($opt{n}) or !exists($opt{i})) {
        return( usage() );
    }
    ####################################
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # No operands - add command name 
    ####################################
    $request->{method} = $cmd;
    return( \%opt );
}



##########################################################################
# Parse the rmvm command line for options and operands
##########################################################################
sub rmvm_parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub { 
        return( [ $_[0],
            "rmvm -h|--help",
            "rmvm -v|--version",
            "rmvm [-V|--verbose] noderange",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output" ]);
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        $request->{method} = $cmd;
        return( \%opt );
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
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # No operands - add command name 
    ####################################
    $request->{method} = $cmd; 
    return( \%opt );
}


##########################################################################
# Parse the lsvm command line for options and operands
##########################################################################
sub lsvm_parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],       
            "lsvm -h|--help",
            "lsvm -v|--version",
            "lsvm [-V|--verbose] noderange",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output" ]);
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        $request->{method} = $cmd;
        return( \%opt );
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
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # No operands - add command name 
    ####################################
    $request->{method} = $cmd; 
    return( \%opt );
}



##########################################################################
# Clones all the partitions from one CEC to another  
##########################################################################
sub clone {

    my $cfgdata = shift;
    my $d       = shift;
    my $exp     = shift;
    my $opt     = shift;
    my $hwtype  = @$exp[2];
    my $target  = $opt->{c};
    my @values  = ();
    my $cecname;

    #####################################
    # Always one source CEC specified 
    #####################################
    my $lparid = @$d[0];
    my $mtms   = @$d[2];
    my $type   = @$d[4];

    if ( $type ne "fsp" ) {
        return( ["Node must be an FSP"] );
    }
    #####################################
    # Enumerate CECs
    #####################################
    my $cecs = xCAT::PPCcli::lssyscfg( $exp, "fsps", "name" );
    my $Rc = shift(@$cecs);

    #####################################
    # Return error
    #####################################
    if ( $Rc != SUCCESS ) {
        return( [@$cecs[0]] );
    }
    #####################################
    # Find target CEC 
    #####################################
    foreach ( @$cecs ) {
        if ( $target eq $_ ) {
            $cecname = $_;
            last;   
        } 
    }
    #####################################
    # Target CEC not found
    #####################################
    if ( !defined( $cecname )) {
        return( ["CEC '$target' not found"] );
    } 
    #####################################
    # Modify read-back profile:
    #  - Rename "name" to "profile_name"
    #  - Rename "lpar_name" to "name"
    #  - Delete "virtual_serial_adapters" 
    #    completely, these adapters are 
    #    created automatically.
    #  - Preceed all double-quotes with
    #    backslashes.
    #
    #####################################
    foreach ( @$cfgdata ) {
        s/^name=([^,]+)/profile_name=$1/;
        s/lpar_name=/name=/;
        s/\"virtual_serial_adapters=[^\"]+\",//;
        s/\"/\\"/g;
        my $name = $1;

        /lpar_id=([^,]+)/;
        $lparid = $1;

        #################################
        # Create new LPAR  
        #################################
        my @temp = @$d;
        $temp[0] = $lparid;

        my $result = xCAT::PPCcli::mksyscfg( $exp, \@temp, $_ ); 
        $Rc = shift(@$result);

        #################################
        # Success - add LPAR to database 
        #################################
        if ( $Rc == SUCCESS ) {
            xCATdB( "mkvm", $d, $lparid, $name, $hwtype );
            next;
        }
        #################################
        # Error - Save error 
        #################################
        push @values, @$result[0]; 
    }
    if ( !scalar(@values) ) {
        @values = qw(Success);
    } 
    return( \@values );
}


##########################################################################
# Removes logical partitions 
##########################################################################
sub remove {
    
    my $exp    = shift;
    my $d      = shift;
    my $lpar   = shift;
    my $lparid = @$d[0];
    my $mtms   = @$d[2];
    my $type   = @$d[4];
    my @lpars  = ();
    my @values = ();

    ####################################
    # This is a single LPAR
    ####################################
    if ( $type eq "lpar" ) {
        $lpars[0] = "$lpar,$lparid";
    }
    ####################################
    # This is a CEC - remove all LPARs 
    ####################################
    else {
        my $filter = "name,lpar_id";
        my $result = xCAT::PPCcli::lssyscfg( $exp, "lpar", $mtms, $filter );
        my $Rc = shift(@$result);

        ################################
        # Expect error
        ################################
        if ( $Rc != SUCCESS  ) {
            return( [@$result[0]] );
        }
        ################################
        # Success - save LPARs 
        ################################
        foreach ( @$result ) {
            push @lpars, $_; 
        }
    }
    ####################################
    # Remove the LPARs
    ####################################
    foreach ( @lpars ) {
        my ($name,$id) = split /,/;
        my $mtms = @$d[2];

        ################################  
        # id profile mtms hcp type frame
        ################################  
        my @d = ( $id,0,$mtms,0,"lpar",0 );

        ################################
        # Send remove command 
        ################################
        my $result = xCAT::PPCcli::rmsyscfg( $exp, \@d );
        my $Rc = shift(@$result);

        ################################
        # Remove LPAR from database 
        ################################
        if ( $Rc == SUCCESS ) {
            xCATdB( "rmvm", $name );
        }
        push @values, @$result[0];
    }
    return( \@values ); 
}


##########################################################################
# Changes the configuration of an existing partition 
##########################################################################
sub chcfg {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $name    = @{$request->{node}}[0];
    my $cfgdata = $request->{stdin}; 
    my @values;

    #######################################
    # Remove "node: " in case the
    # configuration file was created as
    # the result of an "lsvm" command.
    #  "lpar9: name=lpar9, lpar_name=..." 
    #######################################
    $cfgdata =~ s/^[\w]+: //;

    if ( $cfgdata !~ /^name=/ ) {
        my $text = "Invalid file format: must begin with 'name='";
        return( [[$name,$text]] );
    }
    #######################################
    # Preceed double-quotes with '\'
    #######################################
    $cfgdata =~ s/\"/\\"/g;
    $cfgdata =~ s/\n//g;

    while (my ($cec,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {

            ###############################
            # Change configuration
            ###############################
            my $result = xCAT::PPCcli::chsyscfg( $exp, $d, $cfgdata );
            my $Rc = shift(@$result);

            push @values, [$lpar,@$result[0]];
            return( [[$lpar,@$result[0]]] );
        }
    }
    return( \@values );
}



##########################################################################
# Creates/Removes/Lists logical partitions 
##########################################################################
sub vm {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my $cmd     = $request->{command};
    my @values  = ();
    my $result;

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            my $lparid = @$d[0];
            my $mtms   = @$d[2];
            my $type   = @$d[4];

            #####################################
            # Must be CEC or LPAR 
            #####################################
            if ( $type !~ /^lpar|fsp$/ ) {
                push @values, [$lpar,"Node must be LPAR or CEC"];
                next; 
            }
            #####################################
            # Remove LPAR 
            #####################################
            if ( $cmd eq "rmvm" ) {
                $result = remove( $exp, $d, $lpar );

                #################################
                # Return result 
                #################################
                foreach ( @$result ) {
                    push @values, [$lpar, $_];
                }
                next;
            }
            #####################################
            # Get source LPAR profile  
            #####################################
            my $prof = xCAT::PPCcli::lssyscfg(
                                      $exp,
                                      ($lparid) ? "prof" : "cprof",
                                      $mtms,   
                                      $lparid ); 
            my $Rc = shift(@$prof);

            #####################################
            # Return error
            #####################################
            if ( $Rc != SUCCESS ) {
                push @values, [$lpar, @$prof[0]];
                next;
            } 
            #####################################
            # List LPAR profile 
            #####################################
            if ( $cmd eq "lsvm" ) {
                my $text = join "\n\n", @$prof[0];
                push @values, [$lpar, $text];
                next;
            }
            #####################################
            # Clone all the LPARs on CEC 
            #####################################
            if ( exists( $opt->{c} )) {
                if ( $hwtype eq "ivm" ) {
                    push @values, [$lpar, "Not supported for IVM"];
                }
                else {
                    my $result = clone( $prof, $d, $exp, $opt );
                    foreach ( @$result ) {  
                        push @values, [$lpar, $_];
                    }
                }    
                next; 
            }
            #################################
            # Get command-line options 
            #################################
            my $id   = $opt->{i};
            my $name = $opt->{n};
            my $cfgdata = @$prof[0];

            if ( $hwtype eq "hmc" ) {
                #####################################
                # Modify read-back profile. See
                # HMC mksyscfg man page for valid
                # attributes:
                #
                #  - Rename "name" to "profile_name"
                #  - Rename "lpar_name" to "name"
                #  - Delete "virtual_serial_adapters" 
                #    completely, these adapters are 
                #    created automatically.
                #  - Preceed all double-quotes with
                #    backslashes.
                #
                #####################################
                $cfgdata =~ s/^name=[^,]+/profile_name=$name/;
                $cfgdata =~ s/lpar_name=[^,]+/name=$name/;
                $cfgdata =~ s/lpar_id=[^,]+/lpar_id=$id/;
                $cfgdata =~ s/\"virtual_serial_adapters=[^\"]+\",//;
                $cfgdata =~ s/\"/\\"/g;
            }
            elsif ( $hwtype eq "ivm" ) {
                #####################################
                # Modify read-back profile. See
                # IVM mksyscfg man page for valid
                # attributes:
                #
                #  - Delete
                #        lpar_name 
                #        virtual_serial_adapters
                #        lpar_name 
                #        os_type 
                #        all_resources 
                #        lpar_io_pool_ids 
                #        conn_monitoring 
                #        power_ctrl_lpar_ids  
                #  - Preceed all double-quotes with
                #    backslashes.
                #
                #####################################
                $cfgdata =~ s/^name=[^,]+/name=$name/;
                $cfgdata =~ s/lpar_id=[^,]+/lpar_id=$id/;
                $cfgdata =~ s/lpar_name=[^,]+,//;
                $cfgdata =~ s/os_type=/lpar_env=/;
                $cfgdata =~ s/all_resources=[^,]+,//;
                $cfgdata =~ s/\"virtual_serial_adapters=[^\"]+\",//;
                $cfgdata =~ s/lpar_io_pool_ids=[^,]+,//;
                $cfgdata =~ s/virtual_scsi_adapters=[^,]+,//;
                $cfgdata =~ s/conn_monitoring=[^,]+,//;
                $cfgdata =~ s/,power_ctrl_lpar_ids=.*$//;
                $cfgdata =~ s/\"/\\"/g;
            }
            #####################################
            # Create target LPAR  
            #####################################
            $result = xCAT::PPCcli::mksyscfg( $exp, $d, $cfgdata ); 
            $Rc = shift(@$result);

            #####################################
            # Add new LPAR to database 
            #####################################
            if ( $Rc == SUCCESS ) {
                xCATdB( $cmd, $name, $id, $d, $hwtype );
            }
            push @values, [$name,@$result[0]];
        }
    }
    return( \@values );
}



##########################################################################
# Adds/removes LPARs from the xCAT database
##########################################################################
sub xCATdB {

    my $cmd     = shift;
    my $name    = shift;
    my $lparid  = shift;
    my $d       = shift;
    my $hwtype  = shift;

    #######################################
    # Remove entry 
    #######################################
    if ( $cmd eq "rmvm" ) {
        xCAT::PPCdb::rm_ppchardware( $name ); 
    }
    #######################################
    # Add entry 
    #######################################
    else {
        my ($model,$serial) = split /\*/,@$d[2]; 
        my $prof   = $name;
        my $frame  = @$d[4]; 
        my $server = @$d[3];

        my $values = join( ",",
                "lpar",
                $name,
                $lparid,
                $model,
                $serial,
                $server,
                $prof,
                $frame ); 
        
        xCAT::PPCdb::add_ppc( $hwtype, [$values] ); 
    }
}



##########################################################################
# Creates logical partitions 
##########################################################################
sub mkvm {
    return( vm(@_) );
}

##########################################################################
# Change logical partition 
##########################################################################
sub chvm {
    return( chcfg(@_) );    
}


##########################################################################
# Removes logical partitions 
##########################################################################
sub rmvm  {
    return( vm(@_) );
}

##########################################################################
# Lists logical partition profile
##########################################################################
sub lsvm {
    return( vm(@_) );
}



1;
