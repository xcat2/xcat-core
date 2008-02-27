# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCscan;
use strict;
use Getopt::Long;
use Socket;
use XML::Simple;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCdb;
use xCAT::GlobalDef;


##############################################
# Globals
##############################################
my @header = ( 
    ["type",          "%-8s" ],
    ["name",          "placeholder" ],
    ["id",            "%-8s" ],
    ["type-model",    "%-12s" ],
    ["serial-number", "%-15s" ],
    ["address",       "%s\n" ]);

my @attribs = qw(nodetype name id model serial hcp profile parent groups mgt);
my %nodetype = (
    fsp  => $::NODETYPE_FSP,
    bpa  => $::NODETYPE_BPA,
    lpar =>"$::NODETYPE_LPAR,$::NODETYPE_OSI"
);


##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

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
            "rscan -h|--help",
            "rscan -v|--version",
            "rscan [-V|--verbose] noderange [-w][-x|-z]",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output",
            "    -w   writes output to xCat database",
            "    -x   xml formatted output",
            "    -z   stanza formatted output." ]); 
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

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version w x z) )){
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
    # Check for an argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    #############################################
    # Check for mutually-exclusive formatting
    #############################################
    if (( exists($opt{x}) + exists($opt{z})) > 1 ) {
        return( usage() );
    }
    ####################################
    # No operands - add command name
    ####################################
    $request->{method} = $cmd; 
    return( \%opt );
}



##########################################################################
# Returns short-hostname given an IP 
##########################################################################
sub getshorthost {

    my $ip = shift;

    my $host = gethostbyaddr( inet_aton($ip), AF_INET );
    if ( $host and !$! ) {
        ##############################
        # Get short-hostname
        ##############################
        if ( $host =~ /([^\.]+)\./ ) {
           return($1);
        }
    }
    ##################################
    # Failed
    ##################################
    return undef;
}


##########################################################################
# Returns I/O bus information
##########################################################################
sub enumerate {

    my $exp    = shift;
    my $hwtype = @$exp[2];
    my $server = @$exp[3];
    my @values = (); 
    my %cage   = ();
    my $Rc;
    my $filter;

    #########################################
    # Get hardware control point info 
    #########################################
    {
    my $hcp = xCAT::PPCcli::lshmc( $exp );
    $Rc = shift(@$hcp);

    #########################################
    # Return error 
    #########################################
    if ( $Rc != SUCCESS ) {
        return( @$hcp[0] );
    }
    #########################################
    # Success 
    #########################################
    my ($model,$serial) = split /,/, @$hcp[0];
    my $id   = "";
    my $prof = "";
    my $ips  = "";
    my $bpa  = "";

    push @values, join( ",",
        $hwtype,$server,$id,$model,$serial,$server,$prof,$bpa,$ips );
    }
 
    #########################################
    # Enumerate frames (IVM has no frame)
    #########################################
    if ( $hwtype ne "ivm" ) { 
        $filter    = "type_model,serial_num,name,frame_num,ipaddr_a,ipaddr_b";
        my $frames = xCAT::PPCcli::lssyscfg( $exp, "bpas", $filter );
        $Rc = shift(@$frames);

        #####################################
        # Expect error 
        #####################################
        if ( $Rc == EXPECT_ERROR ) {
            return( @$frames[0] );
        }
        #####################################
        # CLI error 
        #####################################
        if ( $Rc == RC_ERROR ) {
            return( @$frames[0] );
        }
        #####################################
        # If frames found, enumerate cages 
        #####################################
        if ( $Rc != NR_ERROR ) {
            $filter = "cage_num,type_model_serial_num";

            foreach my $val ( @$frames ) {
                my ($model,$serial) = split /,/, $val;
                my $mtms = "$model*$serial";

                my $cages = xCAT::PPCcli::lssyscfg($exp,"cage",$mtms,$filter);
                $Rc = shift(@$cages);

                #############################
                # Return error 
                #############################
                if ( $Rc != SUCCESS ) {
                    return( @$cages[0] );
                }
                #############################
                # Success 
                #############################
                foreach ( @$cages ) {
                    my ($cageid,$mtms) = split /,/;
                    $cage{$mtms} = "$cageid,$val";
                }          
            }
        }
    }
    #########################################
    # Enumerate CECs 
    #########################################
    $filter  = "name,type_model,serial_num,ipaddr";
    my $cecs = xCAT::PPCcli::lssyscfg( $exp, "fsps", $filter );
    $Rc = shift(@$cecs);

    #########################################
    # Return error
    #########################################
    if ( $Rc != SUCCESS ) {
        return( @$cecs[0] );
    }
    foreach ( @$cecs ) {
        #####################################
        # Get CEC information
        #####################################
        my ($fsp,$model,$serial,$ips) = split /,/;
        my $mtms   = "$model*$serial";
        my $cageid = "";
        my $fname  = "";

        #####################################
        # Get cage CEC is in
        #####################################
        my $frame = $cage{$mtms};

        #####################################
        # Save frame information
        #####################################
        if ( defined($frame) ) {
            my ($cage,$model,$serial,$name,$id,$ipa,$ipb) = split /,/, $frame;
            my $prof = "";
            my $bpa  = ""; 
            $cageid  = $cage;
            $fname   = $name;

            #######################################
            # Convert IP-A to short-hostname.
            # If fails, use user-defined FSP name
            #######################################
            my $host = getshorthost( $ipa );
            if ( defined($host) ) {
                $fname = $host;
            }
            push @values, join( ",",
                "bpa",$fname,$id,$model,$serial,$server,$prof,$bpa,"$ipa $ipb");
        }
        #####################################
        # Save CEC information
        #####################################
        my $prof = "";

        #######################################
        # Convert IP to short-hostname.
        # If fails, use user-defined FSP name
        #######################################
        my $host = getshorthost( $ips );
        if ( defined($host) ) {
            $fsp = $host;
        }
        push @values, join( ",",
            "fsp",$fsp,$cageid,$model,$serial,$server,$prof,$fname,$ips );

        #####################################
        # Enumerate LPARs 
        #####################################
        $filter    = "name,lpar_id,default_profile,curr_profile"; 
        my $lpars  = xCAT::PPCcli::lssyscfg( $exp, "lpar", $mtms, $filter );
        $Rc = shift(@$lpars); 

        ####################################
        # Expect error 
        ####################################
        if ( $Rc == EXPECT_ERROR ) {
            return( @$lpars[0] );
        }
        ####################################
        # Skip...
        # CEC could be "Incomplete" state
        ####################################
        if ( $Rc == RC_ERROR ) {
            next;
        }
        ####################################
        # No results found 
        ####################################
        if ( $Rc == NR_ERROR ) {
            next;
        }
        foreach ( @$lpars ) {
            my ($name,$lparid,$dprof,$curprof) = split /,/;
            my $prof = (length($curprof)) ? $curprof : $dprof;
            my $ips  = "";
            
            #####################################
            # Save LPAR information
            #####################################
            push @values, join( ",",
              "lpar",$name,$lparid,$model,$serial,$server,$prof,$fsp,$ips );
        }
    }
    return( \@values );
}



##########################################################################
# Format responses
##########################################################################
sub format_output {

    my $request = shift;
    my $exp     = shift;
    my $values  = shift;
    my $opt     = $request->{opt};
    my %output  = ();
    my $hwtype  = @$exp[2];
    my $max_length = 0;
    my $result;

    ###########################################
    # -w flag for write to xCat database
    ###########################################
    if ( exists( $opt->{w} )) {
        my $server = @$exp[3];
        my $uid    = @$exp[4];
        my $pw     = @$exp[5];

        xCAT::PPCdb::add_ppc( $hwtype, $values );
    }
    ###########################################
    # -x flag for xml format
    ###########################################
    if ( exists( $opt->{x} )) {
        $result = format_xml( $hwtype, $values );
    }
    ###########################################
    # -z flag for stanza format
    ###########################################
    elsif ( exists( $opt->{z} )) {
        $result = format_stanza( $hwtype, $values );
    }
    else {
        #######################################
        # Get longest name for formatting
        #######################################
        foreach ( @$values ) {
            /[^\,]+,([^\,]+),/;
            my $length  = length( $1 );
            $max_length = ($length > $max_length) ? $length : $max_length;
        }
        my $format = sprintf( "%%-%ds", ($max_length + 2 ));
        $header[1][1] = $format;

        #######################################
        # Add header
        #######################################
        foreach ( @header ) {
            $result .= sprintf( @$_[1], @$_[0] );
        }
        #######################################
        # Add node information
        #######################################
        foreach ( @$values ) {
            my @data = split /,/;
            my $i = 0;

            foreach ( @header ) {
                my $d = $data[$i++]; 

                ###############################
                # Use IPs instead of 
                # hardware control address 
                ###############################
                if ( @$_[0] eq "address" ) {
                    if ( $data[0] !~ /^hmc|ivm$/ ) {
                        $d = $data[8]; 
                    }
                }
                $result .= sprintf( @$_[1], $d );
            }
        }
    }
    $output{data} = [$result];
    return( [\%output] );
}



##########################################################################
# Stanza formatting
##########################################################################
sub format_stanza {

    my $hwtype = shift;
    my $values = shift;
    my $result;

    #####################################
    # Skip hardware control point 
    #####################################
    shift(@$values);

    foreach ( @$values ) {
        my @data = split /,/;
        my $type = $data[0];
        my $i = 0;

        #################################
        # Node attributes
        #################################
        $result .= "$data[1]:\n\tobjtype=node\n";

        #################################
        # Add each attribute
        #################################
        foreach ( @attribs ) {
            my $d = $data[$i++];

            if ( /^name$/ ) {
                next;
            } elsif ( /^nodetype$/ ) {
                $d = $nodetype{$d}; 
            } elsif ( /^groups$/ ) {
                $d = "$type,all";
            } elsif ( /^mgt$/ ) {
                $d = $hwtype;
            } elsif ( /^model|serial$/ ) {
                if ( $type eq "lpar" ) {
                    $d = undef;                    
                }     
            }
            $result .= "\t$_=$d\n";
        }
    }
    return( $result );
}


##########################################################################
# XML formatting
##########################################################################
sub format_xml {

    my $hwtype = shift;
    my $values = shift;
    my $xml;

    #####################################
    # Skip hardware control point 
    #####################################
    shift(@$values);

    #####################################
    # Create XML formatted attributes
    #####################################
    foreach ( @$values ) {
        my @data = split /,/;
        my $type = $data[0];
        my $i = 0;

        #################################
        # Initialize hash reference
        #################################
        my $href = {
            Node => { }
        };
        #################################
        # Add each attribute 
        #################################
        foreach ( @attribs ) {
            my $d = $data[$i++];

            if ( /^name$/ ) {
                next;
            } elsif ( /^nodetype$/ ) {
                $d = $nodetype{$d};
            } elsif ( /^groups$/ ) {
                $d = "$type,all";
            } elsif ( /^mgt$/ ) {
                $d = $hwtype;
            } elsif ( /^model|serial$/ ) {
                if ( $type eq "lpar" ) {
                    $d = undef;
                }
            }
            $href->{Node}->{$_} = $d;
        }
        #################################
        # XML encoding
        #################################
        $xml.= XMLout($href,
                     NoAttr   => 1,
                     KeyAttr  => [],
                     RootName => undef );
    }
    return( $xml ); 
}



##########################################################################
# Returns I/O bus information
##########################################################################
sub rscan {

    my $request = shift;
    my $dummy   = shift;
    my $exp     = shift;
    my $args    = $request->{arg};
    my $server  = @$exp[3];

    ###################################
    # Enumerate all the hardware
    ###################################
    my $values = enumerate( $exp );
    if ( ref($values) ne 'ARRAY' ) {
        return( [[$server,$values]] );
    }
    ###################################
    # Success 
    ###################################
    my $result = format_output( $request, $exp, $values );
    unshift @$result, "FORMATDATA6sK4ci";
    return( $result );

}



1;




