# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPinv;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
require xCAT::Usage;
require xCAT::PPCinv;
require xCAT::FSPUtils;
use XML::Simple;
#use Data::Dumper;

##########################################
# Maps fsp-api attributes to text
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
#    xCAT::PPCinv::parse_args(@_);
    my $request = shift;
    my $command = $request->{command};
    my $args    = $request->{arg};
    my %opt     = ();
#    my @rinv    = qw(bus config model serial firm all);
    my @rinv    = qw( deconfig firm );

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
# Returns FSP/BPA firmware information
##########################################################################
sub firmware {

    my $request = shift;
    my $hash    = shift;
    my @result;
 
    # print "in FSPinv \n";
    #print Dumper($request);
    #print Dumper($hash);

    ####################################
    # FSPinv with firm command is grouped by hardware control point
    # In FSPinv, the hcp is the related fsp.  
    ####################################
    
    # Example of $hash.    
    #VAR1 = {
    #	          '9110-51A*1075ECF' => {
    #                                   'Server-9110-51A-SN1075ECF' => [
    #    	                                                          0,
    #		                                                          0,
    #                           									  '9110-51A*1075ECF',
    #							                            		  'fsp1_name',
    #				                            					  'fsp',
    #									                               0
    #									                               ]
    #					                }
    # 	   };

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {

            #####################################
            # Command only supported on FSP/BPA/LPARs 
            #####################################
            if ( @$d[4] !~ /^(cec|frame|fsp|bpa|lpar)$/ ) {
                push @result, 
                    [$name,"Information only available for CEC/FSP/Frame/BPA/LPAR",RC_ERROR];
                next; 
            }
	       #################
	       #For support on  Lpars, the flag need to be changed.
	       ##########
	       if(@$d[4] eq "lpar")	{
		        @$d[4] = "fsp";
			    @$d[0] = 0;
	       }
           my $values = xCAT::FSPUtils::fsp_api_action( $name, $d, "list_firmware_level");
           my $Rc = @$values[2];
   	       my $data = @$values[1];
           #print "values";
           #print Dumper($values); 
           #####################################
           # Return error
           #####################################
           if ( $Rc != SUCCESS ) {
                push @result, [$name,$data,$Rc];
                next; 
            }
            
	        #####################################
            # Format fsp-api results
            #####################################
            my $val;
            foreach $val ( @licmap ) {  
                if ( $data =~ /@$val[0]=(\w+)/ ) {
                    push @result, [$name,"@$val[1]: $1",$Rc];
                }
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
}

sub vpd {
}

sub bus {
}

sub deconfig {

    my $request = shift;
    my $hash    = shift;
    my @result;
 
    # print "in FSPinv \n";
    #print Dumper($request);
    #print Dumper($hash);

    ####################################
    # FSPinv with deconfig command is grouped by hardware control point
    # In FSPinv, the hcp is the related fsp.  
    ####################################
    
    # Example of $hash.    
    #VAR1 = {
    #	          '9110-51A*1075ECF' => {
    #                                   'Server-9110-51A-SN1075ECF' => [
    #    	                                                          0,
    #		                                                          0,
    #                           									  '9110-51A*1075ECF',
    #							                            		  'fsp1_name',
    #				                            					  'fsp',
    #									                               0
    #									                               ]
    #					                }
    # 	   };

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {

            #####################################
            # Command only supported on FSP/BPA/LPARs 
            #####################################
            if ( @$d[4] !~ /^(cec|fsp)$/ ) {
                push @result, 
                    [$name,"Deconfigured resource information only available for CEC/FSP",RC_ERROR];
                next; 
            }
	    #################
	    #For support on  Lpars, the flag need to be changed.
	    ##########
	    #if(@$d[4] eq "lpar")	{
	    #    @$d[4] = "fsp";
	    #    @$d[0] = 0;
	    #}
	    my $values = xCAT::FSPUtils::fsp_api_action( $name, $d, "get_cec_deconfigured");
	    my $Rc = @$values[2];
	    my $data = @$values[1];
	    #print "values";
            #print Dumper($values); 
            #####################################
            # Return error
            #####################################
            if ( $Rc != SUCCESS ) {
                 push @result, [$name,$data,$Rc];
                 next; 
             }
            
	     #####################################
             # Format fsp-api results
             #####################################
             my $decfg = XMLin($data);
	     my $node =  $decfg->{NODE};
	     if( !defined($node) ) {
		 push @result,[$name,"Deconfigured resources", 0];
	         push @result,[$name,$node->{Location_code}.",".$node->{RID}, 0];
		 foreach my $unit(@{$node->{GARDRECORD}}) {
		      my $Call_Out_Hardware_State = $unit->{GARDUNIT}->{Call_Out_Hardware_State};
		      my $Call_Out_Method = $unit->{GARDUNIT}->{Call_Out_Method};
		      my $Location_code = $unit->{GARDUNIT}->{Location_code};
		      my $RID = $unit->{GARDUNIT}->{RID};
		      my $TYPE = $unit->{GARDUNIT}->{TYPE};

		      push @result,[$name,"$Location_code,$RID,$Call_Out_Method,$Call_Out_Hardware_State,$TYPE",0]; 
		 }
	     
	     } else {
		 push @result,[$name,"NO Deconfigured resources", 0];
             }
	         
        }
    }
    return( \@result );


}

##########################################################################
# Returns machine-type-model
##########################################################################
sub model {
}

##########################################################################
# Returns all inventory information
##########################################################################
sub all {

    my @result = ( 
        @{deconfig(@_)},
        @{firmware(@_)} 
    );       
    return( \@result );
}


1;


