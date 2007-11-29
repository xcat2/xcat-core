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
            "mkvm [-V|--verbose] srccec -c destcec",
            "    -h   writes usage information to standard output",
            "    -c   copy lpars from srccec to destcec on single HMC",
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
        if ( $opt{i} !~ /^[1-9]{1}|[1-9]{1}[0-9]+$/ ) {
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
# Clones all the LPARs from one CEC to another (must be on same HMC) 
##########################################################################
sub clone {

    my $exp     = shift;
    my $src     = shift;
    my $dest    = shift;
    my $srcd    = shift;
    my $hwtype  = @$exp[2];
    my $server  = @$exp[3];
    my @values  = ();
    my @lpars   = ();
    my $srccec;
    my $destcec;
    my @cfgdata;
 
    #####################################
    # Always one source CEC specified 
    #####################################
    my $lparid = @$srcd[0];
    my $type   = @$srcd[4];

    #####################################
    # Not supported on IVM 
    #####################################
    if ( $hwtype eq "ivm" ) {
        return( ["Not supported for IVM"] );
    }
    #####################################
    # Source must be CEC 
    #####################################
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
    # Find source CEC 
    #####################################
    foreach ( @$cecs ) {
        if ( $src eq $_ ) {
            $srccec = $_;
            last;
        } 
    }
    #####################################
    # Source CEC not found
    #####################################
    if ( !defined( $srccec )) {
        return( ["Source CEC '$src' not found"] );
    } 
    #####################################
    # Find destination CEC 
    #####################################
    foreach ( @$cecs ) {
        if ( $dest eq $_ ) {
            $destcec = $_;
            last;
        } 
    }
    #####################################
    # Destination CEC not found
    #####################################
    if ( !defined( $destcec )) {
        return( ["Destination CEC '$dest' not found on '$server'"] );
    }
    
    #####################################
    # Get all LPARs on source CEC 
    #####################################
    my $filter = "name,lpar_id";
    my $result = xCAT::PPCcli::lssyscfg(
                                    $exp,
                                    "lpar",
                                    $src,
                                    $filter );
    $Rc = shift(@$result);

    #####################################
    # Return error
    #####################################
    if ( $Rc != SUCCESS  ) {
        return( [@$result[0]] );
    }
    #####################################
    # Get profile for each LPAR
    #####################################
    foreach ( @$result ) {
        my ($name,$id) = split /,/;

        #################################
        # Get source LPAR profile
        #################################
        my $prof = xCAT::PPCcli::lssyscfg(
                              $exp,
                              "prof",
                              $src,
                              $id );

        $Rc = shift(@$prof); 

        #################################
        # Return error
        #################################
        if ( $Rc != SUCCESS ) {
            return( [@$prof[0]] );
        }
        #################################
        # Save LPAR profile 
        #################################
        push @cfgdata, @$prof[0];
    }
    #####################################
    # Modify read back profile
    #####################################
    foreach my $cfg ( @cfgdata ) {
        $cfg =~ s/^name=([^,]+|$)/profile_name=$1/;
        $cfg =~ s/lpar_name=/name=/;
        $cfg = strip_profile( $cfg, $hwtype);
        my $name = $1;

        $cfg =~ /lpar_id=([^,]+)/;
        $lparid = $1;

        #################################
        # Create new LPAR  
        #################################
        my @temp = @$srcd;
        $temp[0] = $lparid;
        $temp[2] = $dest;

        my $result = xCAT::PPCcli::mksyscfg( $exp, \@temp, $cfg ); 
        $Rc = shift(@$result);

        #################################
        # Success - add LPAR to database 
        #################################
        if ( $Rc == SUCCESS ) {
            my $err = xCATdB( "mkvm", $srcd, $lparid, $name, $hwtype );
            if ( defined( $err )) {
                push @values, $err; 
            } 
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
   
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my @lpars   = ();
    my @values  = ();

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            my $lparid = @$d[0];
            my $mtms   = @$d[2];
            my $type   = @$d[4];

            ####################################
            # Must be CEC or LPAR
            ####################################
            if ( $type !~ /^lpar|fsp$/ ) {
                push @values, [$lpar,"Node must be LPAR or CEC"];
                next;
            } 
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
                my $result = xCAT::PPCcli::lssyscfg( 
                                             $exp,
                                             "lpar",
                                             $mtms,
                                             $filter );
                my $Rc = shift(@$result);

                ################################
                # Expect error
                ################################
                if ( $Rc != SUCCESS  ) {
                    push @values, [$lpar, @$result[0]];
                    next;
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
                    my $err = xCATdB( "rmvm", $name );
                    if ( defined( $err )) {
                        push @values, [$lpar,$err];
                        next;
                    }
                }
                push @values, [$lpar,@$result[0]];
            }
        }
    }
    return( \@values ); 
}



##########################################################################
# Changes the configuration of an existing partition 
##########################################################################
sub modify {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
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
    # Send change profile command
    #######################################
    while (my ($cec,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {

            ###############################
            # Change configuration
            ###############################
            my $cfg = strip_profile( $cfgdata, $hwtype );
            my $result = xCAT::PPCcli::chsyscfg( $exp, $d, $cfg );
            my $Rc = shift(@$result);

            push @values, [$lpar,@$result[0]];
            return( [[$lpar,@$result[0]]] );
        }
    }
    return( \@values );
}


##########################################################################
# Lists logical partitions
##########################################################################
sub list {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my @values  = ();
    my @lpars   = ();
    my $result;

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            my $lparid = @$d[0];
            my $mtms   = @$d[2];
            my $type   = @$d[4];
            my $profile;

            ####################################
            # Must be CEC or LPAR
            ####################################
            if ( $type !~ /^lpar|fsp$/ ) {
                push @values, [$lpar,"Node must be LPAR or CEC"];
                next;
            }
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
                my $result = xCAT::PPCcli::lssyscfg(
                                             $exp,
                                             "lpar",
                                             $mtms,
                                             $filter );
                my $Rc = shift(@$result);

                ################################
                # Expect error
                ################################
                if ( $Rc != SUCCESS  ) {
                    push @values, [$lpar, @$result[0]];
                    next;
                }
                ################################
                # Success - save LPARs
                ################################
                foreach ( @$result ) {
                    push @lpars, $_;
                }
            }
            ####################################
            # Get LPAR profile 
            ####################################
            foreach ( @lpars ) {
                my ($name,$id) = split /,/;
            
                #################################
                # Get source LPAR profile
                #################################
                my $prof = xCAT::PPCcli::lssyscfg(
                                      $exp,
                                      "prof",
                                      $mtms,
                                      $id );
                my $Rc = shift(@$prof);

                #################################
                # Return error
                #################################
                if ( $Rc != SUCCESS ) {
                    push @values, [$lpar, @$prof[0]];
                    next;
                }
                #################################
                # List LPAR profile
                #################################
                $profile .= "@$prof[0]\n\n";
            }                
            push @values, [$lpar, $profile];
        }
    }
    return( \@values );
}




##########################################################################
# Creates/changes logical partitions 
##########################################################################
sub create {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
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
            # Clone all the LPARs on CEC 
            #####################################
            if ( exists( $opt->{c} )) {
                my $result = clone( $exp, $lpar, $opt->{c}, $d );
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
                                      "prof",
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
            # Get command-line options 
            #####################################
            my $id   = $opt->{i};
            my $name = $opt->{n};
            my $cfgdata = @$prof[0];

            #####################################
            # Modify read-back profile. 
            # See HMC or IVM mksyscfg man  
            # page for valid attributes.
            #
            #####################################
            if ( $hwtype eq "hmc" ) {
                $cfgdata =~ s/^name=[^,]+|$/profile_name=$name/;
                $cfgdata =~ s/lpar_name=[^,]+|$/name=$name/;
                $cfgdata =~ s/lpar_id=[^,]+|$/lpar_id=$id/;
            }
            elsif ( $hwtype eq "ivm" ) {
                $cfgdata =~ s/^name=[^,]+|$/name=$name/;
                $cfgdata =~ s/lpar_id=[^,]+|$/lpar_id=$id/;
            }
            $cfgdata = strip_profile( $cfgdata, $hwtype );

            #####################################
            # Create new LPAR  
            #####################################
            $result = xCAT::PPCcli::mksyscfg( $exp, $d, $cfgdata ); 
            $Rc = shift(@$result);

            #####################################
            # Add new LPAR to database 
            #####################################
            if ( $Rc == SUCCESS ) {
                my $err = xCATdB( "mkvm", $name, $id, $d, $hwtype, $lpar );
                if ( defined( $err )) {
                    push @values, [$name,$err];
                    next;
                }
            }
            push @values, [$name,@$result[0]];
        }
    }
    return( \@values );
}


##########################################################################
# Strips attributes from profile not valid for creation 
##########################################################################
sub strip_profile {

    my $cfgdata = shift;
    my $hwtype  = shift;

    #####################################
    # Modify read-back profile. See
    # HMC mksyscfg man page for valid
    # attributes.
    #####################################
    if ( $hwtype eq "hmc" ) {
        $cfgdata =~ s/,*\"virtual_serial_adapters=[^\"]+\"//;
        $cfgdata =~ s/,*electronic_err_reporting=[^,]+|$//;
        $cfgdata =~ s/,*shared_proc_pool_id=[^,]+|$//;
        $cfgdata =~ s/\"/\\"/g;
        $cfgdata =~ s/\n//g;
        return( $cfgdata );
    }
    #####################################
    # Modify read-back profile. See
    # IVM mksyscfg man page for valid
    # attributes.
    #####################################
    $cfgdata =~ s/,*lpar_name=[^,]+|$//;
    $cfgdata =~ s/os_type=/lpar_env=/;
    $cfgdata =~ s/,*all_resources=[^,]+|$//;
    $cfgdata =~ s/,*\"virtual_serial_adapters=[^\"]+\"//;
    $cfgdata =~ s/,*lpar_io_pool_ids=[^,]+|$//;
    $cfgdata =~ s/,*virtual_scsi_adapters=[^,]+|$//;
    $cfgdata =~ s/,*conn_monitoring=[^,]+|$//;
    $cfgdata =~ s/,*power_ctrl_lpar_ids=[^,]+|$//;
    $cfgdata =~ s/\"/\\"/g;
    return( $cfgdata );
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
    my $lpar    = shift;

    #######################################
    # Remove entry 
    #######################################
    if ( $cmd eq "rmvm" ) {
        return( xCAT::PPCdb::rm_ppc( $name )); 
    }
    #######################################
    # Add entry 
    #######################################
    else {
        my ($model,$serial) = split /\*/,@$d[2]; 
        my $profile = $name;
        my $server  = @$d[3]; 
        my $fsp     = @$d[2];

        ###################################
        # Find FSP name in ppc database
        ###################################
        my $tab = xCAT::Table->new( "ppc" );

        ###################################
        # Error opening ppc database
        ###################################
        if ( !defined( $tab )) {
            return( "Error opening 'ppc' database" );
        }
        my ($ent) = $tab->getAttribs({node=>$lpar}, "parent" );

        ###################################
        # Node not found 
        ###################################
        if ( !defined( $ent )) { 
            return( "'$lpar' not found in 'ppc' database" );
        }
        ###################################
        # Attributes not found 
        ###################################
        if ( !exists( $ent->{parent} )) {
            return( "'parent' attribute not found in 'ppc' database" );
        }
        my $values = join( ",",
                "lpar",
                $name,
                $lparid,
                $model,
                $serial,
                $server,
                $profile,
                $ent->{parent} ); 
        
        return( xCAT::PPCdb::add_ppc( $hwtype, [$values] )); 
    }
    return undef;
}



##########################################################################
# Creates logical partitions 
##########################################################################
sub mkvm {
    return( create(@_) );
}

##########################################################################
# Change logical partition 
##########################################################################
sub chvm {
    return( modify(@_) );    
}


##########################################################################
# Removes logical partitions 
##########################################################################
sub rmvm  {
    return( remove(@_) );
}

##########################################################################
# Lists logical partition profile
##########################################################################
sub lsvm {
    return( list(@_) );
}



1;
