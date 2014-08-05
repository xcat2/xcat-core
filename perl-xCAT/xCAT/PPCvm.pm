# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCvm;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCdb;
use xCAT::Usage;
use xCAT::NodeRange;
use Data::Dumper;
use xCAT::MsgUtils qw(verbose_message);

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

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [ $_[0], $usage_string] );
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args ) && !defined( $request->{stdin} ) ) {
        $request->{method} = $cmd;
        return( usage() );
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    if ($args) { @ARGV = @$args; }
    else { @ARGV = (); }
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(V|verbose p=s) )) {
        return( usage() );
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
        $opt{a} = [@ARGV];
        for my $attr ( @{$opt{a}})
        {
            if ( $attr !~ /(\w+)=(\w*)/)
            {
                return(usage( "Invalid argument or attribute: $attr" ));
            }
        }
    }
    ####################################
    # Configuration file required 
    ####################################
    if ( !exists( $opt{p}) and !exists( $opt{a})) { 
        if ( !defined( $request->{stdin} )) { 
            return(usage( "Configuration file or attributes not specified" ));
        }
    }
    ####################################
    # Both configuration file and
    # attributes are specified
    ####################################
    if ( exists( $opt{p}) and exists( $opt{a})) {
        return(usage( "Flag -p cannot be used together with attribute list"));
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

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
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
    if ( !GetOptions( \%opt, qw(V|verbose ibautocfg ibacap=s i=s l=s c=s p=s full) )) {
        return( usage() );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    #############################################################
    # Check if only ibacap or ibautocfg specified with the other
    #############################################################
    #if ( exists $opt{ibautocfg} and ! exists $opt{ibacap})
    #{
    #   return(usage( "Missing option ibacap when ibautocfg is specified"));
    #}    
    #elsif ( exists $opt{ibacap} and !exists $opt{ibautocfg})
    #{
    #    return(usage( "Missing option ibautocfg when ibacap is specified"));
    #}    
    #if ( $opt{ibacap} ne '1' and $opt{ibacap} ne '2' and $opt{ibacap} ne '3' and $opt{ibacap} ne '4')
    #{
    #    return(usage( "IB adapter virtual capability (option --ibacap) can only be number 1,2,3,4. \n\t 1 means 'Low utilization': 6.25% of HCA resources (1/16 of an HCA); \n\t 2 means 'Medium utilization': 12.5% of HCA resources (1/8 of an HCA); \n\t 3 means 'High utilization': 25% of HCA resources (1/4 of an HCA);\n\t 4 means 'Dedicated HCA': 100% of HCA resources (complete HCA).\n"));
    #}

    ####################################
    # Check for non-zero integer 
    ####################################
    if ( exists( $opt{i} )) {
        if ( $opt{i} !~ /^([1-9]{1}|[1-9]{1}[0-9]+)$/ ) {
            return(usage( "Invalid entry: $opt{i}" ));

        }
    }
    ####################################
    # -i and -l not valid with -c 
    ####################################
    if ( exists( $opt{c} ) ) {
        if ( exists($opt{i}) or exists($opt{l}) or exists($opt{full})) {
            return( usage() );
        }
    ####################################
    # -p is required for -c
    ####################################
        if ( !exists($opt{p})) {
            return( usage() );
        }
    }
    ####################################
    # -i, -l and -c not valid with -f 
    ####################################
    elsif ( exists( $opt{full} ) ) {
        if ( exists($opt{c}) or exists($opt{i}) or exists($opt{l})) {
            return( usage() );
        }
    }
    ####################################
    # If -i and -l, both required
    ####################################
    elsif ( !exists($opt{l}) or !exists($opt{i})) {
        return( usage() );
    }
    ####################################
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # Expand -l noderange
    ####################################
    if ( exists( $opt{l} )) {
        my @noderange = xCAT::NodeRange::noderange( $opt{l},0 );
        if ( !@noderange ) {
            return(usage( "Invalid noderange: '$opt{l}'" ));
        }
        @noderange = sort @noderange;
        $opt{lpar} = \@noderange;
    }
    ####################################
    # Expand -c noderange
    ####################################
    if ( exists( $opt{c} )) {
        my @noderange = xCAT::NodeRange::noderange( $opt{c},0 );
        if ( !@noderange ) {
            return(usage( "Invalid noderange: '$opt{l}'" ));
        }
        $opt{cec} = \@noderange;
    }
    #################################################
    # Swap the targets to be processed in PPC.pm
    #################################################
    $opt{target} = [@{$request->{node}}];
    if ( $opt{l})
    {
        $request->{node} = [@{$opt{lpar}}];
        $request->{noderange} = $opt{l};
    }

    if ( $opt{c})
    {
        $request->{node} = [@{$opt{cec}}];
        $request->{noderange} = $opt{c};
    }    
    #############################################
    # Only 1 node allowed 
    #############################################
    if ( !exists($opt{full}) && scalar( @{$request->{node}} ) > 1) {
        return(usage( "Multiple source specified" ));
    } 

    ################################################
    # Check if the multiple nodes of  the same CEC are specified with -f
    ################################################

    if ( (exists($opt{full})) && (scalar (@{$opt{target}}) > 1) ) {
        my $lparparent;
        my $ppctab  = xCAT::Table->new('ppc');
        foreach my $vnode (@{$opt{target}}) {
            my $vcon = $ppctab->getNodeAttribs( $vnode, ('node','parent'));
            if ($vcon and $vcon->{"node"} and $vcon->{"parent"}) {
                my $lparent = $vcon->{"parent"};
                $lparparent->{$lparent}->{$vnode} = $vnode;
            }
        }

        $ppctab->close;
        my $cbmsg        = "mkvm: multiple LPAR nodes which belong to the same CEC have been defined.\n";
            my $sameflag    = 0;
            foreach my $iparent (keys %$lparparent) {
                 if (scalar (keys %{$lparparent->{$iparent}}) > 1) {
                       $sameflag       = 1;
                       $cbmsg    = $cbmsg .  $iparent . ":" . "\t";
                        foreach my $inode (keys %{$lparparent->{$iparent}}) {
                        $cbmsg  = $cbmsg . $inode . ",";
                        }
                    }
            
            $cbmsg =~ s/,$/ /;
            $cbmsg = $cbmsg . "\n";
            }
        if ($sameflag) {
            return(usage( $cbmsg ));
        }
    } 

    ####################################
    # Read and check profile
    ####################################
    if ( exists( $opt{p})) {
        $opt{p} = $request->{cwd}->[0] . '/' . $opt{p} if ( $opt{p} !~ /^\//);
        return ( usage( "Profile $opt{p} cannot be found")) if ( ! -f $opt{p});
        open (PROFFILE, "<$opt{p}") or return ( usage( "Cannot open profile $opt{p}"));
        my @cfgdata = ();
        while(  <PROFFILE>)
        {
            chomp;
            /\w+/ or next;
            if ( /name=/ and /lpar_name/ and /lpar_id/ and /lpar_env/)
            {
                push @cfgdata, $_;
            }
            else
            {
                s/^[^,]*:\s*(name=.*)$/$1/;
                return ( usage( "Invalid line in profile: $_"));
            }
        }
        return ( usage( "No valid line was found in profile $opt{p}.")) if ( scalar( @cfgdata) < 1);

        my @lpars = @{$opt{target}};
        my $min_lpar_num = scalar( @cfgdata);
        if ( scalar(@cfgdata) > scalar( @lpars))
        {
            xCAT::MsgUtils->message('W', "Warning: Lpar configuration number in profile is greater than lpars in command line. Only first " . scalar(@lpars) . " lpars will be created.\n");
            $min_lpar_num = scalar( @lpars);
        }
        elsif ( scalar(@cfgdata) < scalar( @lpars))
        {
            my $lparlist = join ",", @lpars[0..($min_lpar_num-1)];
            xCAT::MsgUtils->message('W', "Warning: Lpar number in command line is greater than lpar configuration number in profile. Only lpars " . $lparlist . " will be created.\n");
        }

        $opt{profile} = \@cfgdata;
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

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub { 
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [ $_[0], $usage_string] );
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

    if ( !GetOptions( \%opt, qw(V|verbose service r) )) {
        return( usage() );
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

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [ $_[0], $usage_string] );
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

    if ( !GetOptions( \%opt, qw(V|verbose a|all) )) {
        return( usage() );
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
    my $request = shift;
    my $exp     = shift;
    my $targets = shift;
    my $profile = shift;
    my $destd   = shift;
    my $destname= shift;
    my $hwtype  = @$exp[2];
    my $server  = @$exp[3];
    my @values  = ();
    my @lpars   = @$targets;
    my $destcec;
    my $opt     = $request->{opt};

   #####################################
   # Always one source CEC specified 
   #####################################
    my $lparid = @$destd[0];
    my $mtms   = @$destd[2];
    my $type   = @$destd[4];

    #####################################
    # Not supported on IVM 
    #####################################
    if ( $hwtype eq "ivm" ) {
        return( [[RC_ERROR,"Not supported for IVM"]] );
    }
    #####################################
    # Source must be CEC 
    #####################################
    #if ( $type ne "fsp" ) {
    unless ( $type =~ /^(cec|fsp)$/) {
        return( [[RC_ERROR,"Node must be an FSP"]] );
    }
    #####################################
    # Attributes not found
    #####################################
    if ( !$mtms) {
        return( [[RC_ERROR,"Cannot found serial and mtm for $destname"]] );
    }

    #####################################
    # Enumerate CECs
    #####################################
    my $filter = "type_model,serial_num";
    xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg fsps.filter:'$filter'.");
    my $cecs = xCAT::PPCcli::lssyscfg( $exp, "fsps", $filter );
    my $Rc = shift(@$cecs);

    #####################################
    # Return error
    #####################################
    if ( $Rc != SUCCESS ) {
        return( [[$Rc, @$cecs[0]]] );
    }

    #####################################
    # Get HCA info
    #####################################
    my $unassigned_iba = undef;
    my $iba_replace_pair = undef;
    if ( exists $opt->{ibautocfg})
    {
        $unassigned_iba = get_unassigned_iba( $exp, $mtms, $opt->{ibacap});
    }
    else
    {
        $unassigned_iba = get_unassigned_iba( $exp, $mtms, undef);
        $iba_replace_pair = get_iba_replace_pair( $unassigned_iba, $profile);
    }

    #####################################
    # Find source/dest CEC 
    #####################################
    foreach ( @$cecs ) {
        s/(.*),(.*)/$1*$2/;

        if ( $_ eq $mtms ) {
            $destcec = $_;
        }
    }
    #####################################
    # Destination CEC not found
    #####################################
    if ( !defined( $destcec )) {
        return([[RC_ERROR,"Destination CEC '$destname' not found on '$server'"]]);
    }
    #####################################
    # Modify read back profile
    #####################################
    my $min_lpar_num = scalar(@$profile) < scalar(@$targets) ? scalar(@$profile) : scalar(@$targets) ;
    my $i;
    for ($i = 0; $i < $min_lpar_num; $i++)
    {
        my $cfg = $profile->[$i];
        $cfg =~ s/^[^,]*:\s*(name=.*)$/$1/;
        $cfg =~ s/^name=([^,]+|$)/profile_name=$1/;
        my $profile = $1;

        $cfg =~ s/\blpar_name=([^,]+|$)/name=$targets->[$i]/;

        $cfg = strip_profile( $cfg, $hwtype);
        $cfg =~ /lpar_id=([^,]+)/;
        $lparid = $1;

        if (exists $opt->{ibautocfg})
        {
            $cfg = hcaautoconf( $cfg, $unassigned_iba);
        }   
        else
        {
            $cfg = hcasubst( $cfg, $iba_replace_pair);
        }
        #################################
        # Create new LPAR  
        #################################
        my @temp = @$destd;
        $temp[0] = $lparid;
        $temp[2] = $destcec;
        $temp[4] = 'lpar';

        xCAT::MsgUtils->verbose_message($request, "$request->{command} :mksyscfg lpar.cfg:'$cfg'.");
        my $result = xCAT::PPCcli::mksyscfg( $exp, "lpar", \@temp, $cfg ); 
        $Rc = shift(@$result);

        #################################
        # Success - add LPAR to database 
        #################################
        if ( $Rc == SUCCESS ) {
            my $err = xCATdB( 
                    "mkvm", $targets->[$i], $profile, $lparid, $destd, $hwtype, $targets->[$i], $destname );

            if ( defined( $err )) {
                push @values, [$err, RC_ERROR];
            }
            next;
        }
        #################################
        # Error - Save error 
        #################################
        push @values, [@$result[0], $Rc]; 
    }
    if ( !scalar(@values) ) {
        return( [[SUCCESS,"Success"]]);
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
    my $opt     = $request->{opt};
    my @lpars   = ();
    my @values  = ();
    
    xCAT::MsgUtils->verbose_message($request, "$request->{command} START.");
    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            my $lparid = @$d[0];
            my $mtms   = @$d[2];
            my $type   = @$d[4];
            ####################################
            # Must be CEC or LPAR
            ####################################
            if ( $type !~ /^(lpar|fsp|cec)$/ ) {
                push @values, [$lpar, "Node must be LPAR or CEC", RC_ERROR];
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
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg lpar.filter:'$filter'.");
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
                    push @values, [$lpar, @$result[0], $Rc];
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
            my $lparinfo   = $_;     # shift(@lpars);
                my ($name,$id) = split /,/, $lparinfo;
                my $mtms = @$d[2];
                
                if ($opt->{service}) {
                    ###############################################
                    # begin to retrieve the CEC's service lpar id
                    ############################################### 
                    xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg fsp.filter:'service_lpar_id'.");
                    my $service_lparid = xCAT::PPCcli::lssyscfg(
                                                  $exp,
                                                  "fsp",
                                                  $mtms,
                                                  "service_lpar_id" );
                    my $Rc = shift(@$service_lparid);
                
                    #####################################################
                    # Change the CEC's state to standby and set it's service lpar id to none
                    #####################################################
                    if ( $Rc == SUCCESS ) {
                        my $cfgdata = @$service_lparid[0];
                            if ( ($id == $cfgdata) && ($cfgdata !~ /none/) ) {
                                $cfgdata = "service_lpar_id=none";
                                xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg fsp.filter:'$cfgdata'.");
                                my $result = xCAT::PPCcli::chsyscfg( $exp, "fsp", $d, $cfgdata );
                                $Rc = shift(@$result);
                                if ( $Rc != SUCCESS ) {
                                    return( [[$lpar, @$service_lparid[0], $Rc]] );
                                }
                            }
                    }
                }
 
                ################################  
                # id profile mtms hcp type frame
                ################################  
                my @d = ( $id,0,$mtms,0,"lpar",0 );
                ################################
                # Send remove command 
                ################################
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :rmsyscfg lpar.id:$id.");
                my $result = xCAT::PPCcli::rmsyscfg( $exp, \@d );
                my $Rc = shift(@$result);

                ################################
                # Remove LPAR from database 
                ################################
                if ( $Rc == SUCCESS and !exists( $opt->{r} ) ) {
                    xCAT::MsgUtils->verbose_message($request, "$request->{command} :remove lpar:$name from xCATdb.");
                    my $err = xCATdB( "rmvm", $name,"", $id,"", $type,"" , $lpar );
                    if ( defined( $err )) {
                        push @values, [$lpar,$err,RC_ERROR];
                        next;
                    }
                }
                push @values, [$lpar,@$result[0],$Rc];
            }
        }
    }
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END.");
    return( \@values ); 
}


##########################################################################
# Finds the partition profile specified by examining all CECs
##########################################################################
sub getprofile {

    my $exp  = shift; 
    my $name = shift;

    ###############################
    # Get all CECs
    ###############################
    my $cecs = xCAT::PPCcli::lssyscfg( $exp, "fsps", "name" );

    ###############################
    # Return error
    ###############################
    if ( @$cecs[0] != NR_ERROR ) {
        if ( @$cecs[0] != SUCCESS ) {
            return( $cecs );
        }
        my $Rc = shift(@$cecs);

        ###########################
        # List profiles for CECs 
        ###########################
        foreach my $mtms ( @$cecs ) {
            my $prof = xCAT::PPCcli::lssyscfg(
                               $exp,
                               "prof",
                               $mtms,
                               "profile_names=$name" );

            my $Rc = shift(@$prof);
            if ( $Rc == SUCCESS ) {
                return( [SUCCESS,$mtms,@$prof[0]] );
            }
        }
    }
    return( [RC_ERROR,"The partition profile named '$name' was not found"] );
}


##########################################################################
# Changes the configuration of an existing partition 
##########################################################################
sub modify {
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    return modify_by_prof( $request, $hash, $exp) if ( $request->{opt}->{p});
    return modify_by_attr( $request, $hash, $exp);
}

##########################################################################
# Changes the configuration of an existing 
# partition based on the attributes specified
##########################################################################
sub modify_by_attr {
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $name    = @{$request->{node}}[0];
    my $opt     = $request->{opt};
    my $attrstr= $opt->{a};
    my @values;

    xCAT::MsgUtils->verbose_message($request, "$request->{command} START.");
    # attrstr will be in stdin for "cat vmdef | chvm nodename"
    if (!defined($attrstr) && defined($request->{stdin})) {
        my $tempattr = $request->{stdin};
        $tempattr =~ s/\s+$//;
        $tempattr =~ s/^[\w]+: //;
        my $newcfg = strip_profile( $tempattr, $hwtype );
        $newcfg =~ s/,*lpar_env=[^,]+|$//;
        $newcfg =~ s/,*all_resources=[^,]+|$//;
        $newcfg =~ s/,*lpar_name=[^,]+|$//;
        $newcfg =~ s/\\\"/\"/g;
        my @cfgarray = split /,/, $newcfg;
        ##########################################
        # Repair those lines splitted incorrectly
        ##########################################
        my @newcfgarray;
        my $full_line;
        while (my $line = shift( @cfgarray))
        {
            if ( !$full_line)
            {
                $full_line = $line;
            }
            else
            {
                $full_line = "$full_line,$line";
            }
            if ( $full_line =~ /^[^\"]/ or $full_line =~ /^\".+\"$/)
            {
                $full_line =~ s/^\"(.+)\"$/$1/;
                push @newcfgarray, $full_line;
                $full_line = undef;
                next;
            }
        }
        $attrstr = \@newcfgarray;
    }
    if ( defined( $attrstr )) { 
        ###################################
        # Get LPAR active profiles 
        ###################################
        while (my ($cec,$h) = each(%$hash) ) {
            while (my ($lpar,$d) = each(%$h) ) {
                ###########################
                # Get current profile
                ###########################
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg node.id:'@$d[0]'.");
                my $cfg_res = xCAT::PPCcli::lssyscfg(
                             $exp,
                             "node",
                             $cec,
                             'curr_profile',
                             @$d[0]);
                my $Rc = shift(@$cfg_res);
                if ( $Rc != SUCCESS ) {
                    push @values, [$lpar, @$cfg_res[0], $Rc];
                    next;
                }
                ##############################################
                # If there is no curr_profile, which means no
                # profile has been applied yet (before first 
                # boot?), use the default_profile
                ##############################################
                if ( (!@$cfg_res[0]) || (@$cfg_res[0] =~ /^none$/) )
                {
                    $cfg_res = xCAT::PPCcli::lssyscfg(
                            $exp,
                            "node",
                            $cec,
                            'default_profile',
                            @$d[0]);
                    $Rc = shift(@$cfg_res);
                    if ( $Rc != SUCCESS ) {
                        push @values, [$lpar, @$cfg_res[0], $Rc];
                        next;
                    }
                }


               xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg prof.filter:'lpar_ids=@$d[0],profile_names=@$cfg_res[0]'.");
                my $prof = xCAT::PPCcli::lssyscfg(
                             $exp,
                             "prof",
                             $cec,
                             "lpar_ids=@$d[0],profile_names=@$cfg_res[0]" );
                $Rc = shift(@$prof);

                if ( $Rc != SUCCESS ) {
                    push @values, [$lpar, @$prof[0], $Rc];
                    next;
                }
                my $cfgdata = @$prof[0];
                ###########################
                # Modify profile
                ###########################
                $cfgdata = strip_profile( $cfgdata, $hwtype );
                $cfgdata =~ s/,*lpar_env=[^,]+|$//;
                $cfgdata =~ s/,*all_resources=[^,]+|$//;
                $cfgdata =~ s/,*lpar_name=[^,]+|$//;
                my $err_msg;
                ($Rc, $err_msg, $cfgdata) = subst_profile( $cfgdata, $attrstr);
                if ( $Rc != SUCCESS ) {
                    push @values, [$lpar, $err_msg, $Rc];
                    next;
                }
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :chsyscfg prof.cfg:'$cfgdata'.");
                my $result = xCAT::PPCcli::chsyscfg( $exp, "prof", $d, $cfgdata );
                $Rc = shift(@$result);
                push @values, [$lpar,@$result[0],$Rc];
            }
        }
    }
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END.");
    return (\@values);
}

##########################################################################
# Substitue attributes-value pairs in profile
##########################################################################
sub subst_profile
{
    my $cfgdata = shift;
    my $attrlist = shift;

    $cfgdata =~ s/\\\"/\"/g;
    my @cfgarray = split /,/, $cfgdata;
    ##########################################
    # Repair those lines splitted incorrectly
    ##########################################
    my @newcfgarray;
    my $full_line;
    while (my $line = shift( @cfgarray))
    {
        if ( !$full_line)
        {
            $full_line = $line;
        }
        else
        {
            $full_line = "$full_line,$line";
        }
        if ( $full_line =~ /^[^\"]/ or $full_line =~ /^\".+\"$/)
        {
            $full_line =~ s/^\"(.+)\"$/$1/;
            push @newcfgarray, $full_line;
            $full_line = undef;
            next;
        }
    }

    ##########################################
    # Substitute attributes in new array
    ##########################################
    my @final_array;
    my @attrs = @$attrlist;
    for my $cfgline ( @newcfgarray)
    {
        for ( my $i = 0; $i < scalar(@attrs); $i++ )
        {
            my $av_pair = $attrs[$i];
            next if ( !$av_pair);
            #assuming there will not be too many attributes to be changed
            my ($attr,$value) = $av_pair =~ /^\s*(\S+?)\s*=\s*(\S+)\s*$/;
            if ( $cfgline =~ /^$attr=/)
            {
                if ( $cfgline =~ /lhea_logical_ports/)
                {
                    $cfgline = "$attr=\\\"\\\"$value\\\"\\\"";
                } else 
                {
                    $cfgline = "$attr=$value";
                }
               
                delete $attrs[$i];
                last;
            }
            
        }
        if ( $cfgline =~ /,/)
        {
            $cfgline = "\\\"$cfgline\\\"";
        }
        push @final_array, $cfgline;
    }
    $cfgdata = join ',',@final_array;

    ##########################################
    # Get not found attribute list
    ##########################################
    my %not_found = ();
    for (@attrs)
    {
        if ( $_)
        {
            my ($a) = split /=/;
            $not_found{$a} = 1;
        }
    }
    my $Rc = scalar(keys %not_found);
    my $incorrect_attrs = join ',', (keys %not_found);
    return ($Rc, "Incorrect attribute(s) $incorrect_attrs", $cfgdata);
}

##########################################################################
# Changes the configuration of an existing 
# partition based on the profile specified
##########################################################################
sub modify_by_prof {
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $name    = @{$request->{node}}[0];
    my $opt     = $request->{opt};
    my $cfgdata = $request->{stdin}; 
    my $profile = $opt->{p};
    my @values;

    xCAT::MsgUtils->verbose_message($request, "$request->{command} START.");
    #######################################
    # -p flag, find profile specified
    #######################################
    if ( defined( $profile )) { 
        my $prof = getprofile( $exp, $profile );

        ###################################
        # Return error
        ###################################
        my $Rc = shift(@$prof);
        if ( $Rc != SUCCESS ) {
            return( [[$name,@$prof,RC_ERROR]] );
        }
        $cfgdata = @$prof[1];
        my $mtms = @$prof[0];

        ###################################
        # Check if LPAR profile exists 
        ###################################
        while (my ($cec,$h) = each(%$hash) ) {
            while (my ($lpar,$d) = each(%$h) ) {

                ###########################
                # Get LPAR profiles 
                ###########################
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg prof.filter:'lpar_ids=@$d[0],profile_names=$profile'.");
                my $prof = xCAT::PPCcli::lssyscfg(
                             $exp,
                             "prof",
                             $cec,
                             "lpar_ids=@$d[0],profile_names=$profile" );
                my $Rc = shift(@$prof);

                ###########################
                # Already has that profile 
                ###########################
                if ( $Rc == SUCCESS ) {
                    push @values, [$lpar,"Success",$Rc];
                    xCATdB( "chvm", $lpar, $profile );
                    delete $h->{$lpar};  
                }
            }
        }
    }
    #######################################
    # Remove "node: " in case the
    # configuration file was created as
    # the result of an "lsvm" command.
    #  "lpar9: name=lpar9, lpar_name=..." 
    #######################################
    $cfgdata =~ s/^[\w]+: //;
    if ( $cfgdata !~ /^name=/ ) {
        my $text = "Invalid file format: must begin with 'name='";
        return( [[$name,$text,RC_ERROR]] );
    }
    my $cfg = strip_profile( $cfgdata, $hwtype );
    $cfg =~ s/,*lpar_env=[^,]+|$//;
    $cfg =~ s/,*all_resources=[^,]+|$//;
    $cfg =~ s/,*lpar_name=[^,]+|$//;

    #######################################
    # Send change profile command
    #######################################
    while (my ($cec,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
 
            ###############################
            # Only valid for LPARs 
            ###############################
            if ( @$d[4] ne "lpar" ) {
                push @values, [$lpar,"Command not supported on '@$d[4]'",RC_ERROR];
                next;
            }
            ###############################
            # Change LPAR Id 
            ###############################
            $cfg =~ s/lpar_id=[^,]+/lpar_id=@$d[0]/;          

            #################################
            # Modify SCSI/LHEA adapters
            #################################
            if ( exists( $opt->{p} )) { 
                if ( $cfg =~ /virtual_scsi_adapters=(\w+)/ ) {
                    if ( $1 !~ /^none$/i ) {
                        $cfg = scsi_adapter( $cfg );
                    }
                }
                if ( $cfg =~ /lhea_logical_ports=(\w+)/ ) {
                    if ( $1 !~ /^none$/i ) {
                        $cfg = lhea_adapter( $cfg );
                    }
                }
            }
            ###############################
            # Send command 
            ###############################
            if ( defined( $profile )) {
               xCAT::MsgUtils->verbose_message($request, "$request->{command} :mksyscfg prof.cfg:'$cfg'.");
               my $result = xCAT::PPCcli::mksyscfg( $exp, "prof", $d, $cfg );
               my $Rc = shift(@$result);

               ############################
               # Update database
               ############################
               if ( $Rc == SUCCESS ) {
                   xCATdB( "chvm", $lpar, $profile );
               }
               push @values, [$lpar,@$result[0],$Rc];
            }
            else {
               xCAT::MsgUtils->verbose_message($request, "$request->{command} :chsyscfg prof.cfg:'$cfg'.");
               my $result = xCAT::PPCcli::chsyscfg( $exp, "prof", $d, $cfg );
               my $Rc = shift(@$result);
               push @values, [$lpar,@$result[0],$Rc];
            }
        }
    }
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END.");
    return( \@values );
}


##########################################################################
# Lists logical partitions
##########################################################################
sub list {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $args    = $request->{opt};
    my $values  = ();
    my @value   = ();
    my @lpars   = ();
    my $result;

    xCAT::MsgUtils->verbose_message($request, "$request->{command} START.");
    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            my $lparid = @$d[0];
            my $mtms   = @$d[2];
            my $type   = @$d[4];
            my $pprofile;

            ####################################
            # Must be CEC or LPAR
            ####################################
            if ( $type !~ /^(lpar|fsp|cec)$/ ) {
                $values->{$lpar} = [$lpar,"Node must be LPAR or CEC",RC_ERROR];
                next;
            }
            ####################################
            # This is a single LPAR
            ####################################
            if ( $type eq "lpar" ) {
                $lpars[0] = "$lpar,$lparid";
            }
            ####################################
            # This is a CEC
            ####################################
            else {
                my $filter = "name,lpar_id";
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg lpar.filter:'$filter'.");
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
                    $values->{$lpar} = [$lpar,@$result[0], $Rc];
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
            foreach ( sort @lpars ) {
                my ($name,$id) = split /,/;
            
                #################################
                # Get source LPAR profile
                #################################
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg prof.filter:'lpar_ids=$id'.");
                my $prof = xCAT::PPCcli::lssyscfg(
                                      $exp,
                                      "prof",
                                      $mtms,
                                      "lpar_ids=$id" );
                my $Rc = shift(@$prof);

                #################################
                # Return error
                #################################
                if ( $Rc != SUCCESS ) {
                    $values->{$lpar} = [$lpar,@$prof[0], $Rc];
                    next;
                }
                #################################
                # List the default LPAR profile,
                # or all the profiles if option
                # -a|--all is assigned
                #################################
                if (exists( $args->{a} )) {
                    my $count = 0;
                    foreach (@$prof) {
                        $pprofile .= "@$prof[$count]\n\n";
                        $count++;
                    }
                } else {
                    #$pprofile .= "@$prof[0]\n\n";
                    my $lparprof = xCAT::PPCcli::lssyscfg(
                                      $exp,
                                      "lpar2",
                                      $mtms,
                                      "lpar_ids=$id" );
                    my $Rc = shift(@$lparprof);
                    if ( $Rc != SUCCESS ) {
                        $pprofile .= "@$lparprof[0]\n\n";
                    } else {
                        @$lparprof[0] =~ /curr_profile=(\w+)/;
                        my $pname = $1;
                        foreach my $pr (@$prof) {
                            if ($pr =~ /name=$pname/) {
                                $pprofile .= "$pr\n\n";
                            }    
                        }
                    }                   
                }
            }                
            $values->{$lpar} = [$lpar, $pprofile, SUCCESS];
        }
    }

    foreach ( sort keys %$values ) {
        push @value,$values->{$_};
    }
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END.");
    return( \@value );
}
##########################################################################
# Increments hca adapter in partition profile
##########################################################################
sub hca_adapter {

    my $cfgdata = shift;

    #########################################
    # Increment HCA adapters if present
    # "23001eff/2550010250300/2,23001eff/2550010250400/2"  
    # Increment the last 2 number of 2550010250300 and 
    # 2550010250400 in example above.
    #########################################
    if ( $cfgdata =~ /(\"*hca_adapters)/ ) {

        #####################################
        # If double-quoted, has comma-
        # seperated list of adapters
        #####################################
        my $delim = ( $1 =~ /^\"/ ) ? "\\\\\"" : ","; 
        $cfgdata  =~ /hca_adapters=([^$delim]+)|$/;
        my @hcas = split ",", $1;
        my $adapters = "hca_adapters=";
        for my $hca ( @hcas)
        {
            my @hcainfo = split /\//, $hca;
            ######################################################
            # split it to 2 part, only increase the last 2 number
            # otherwise it can overflow if change it to dec
            ######################################################
            my $portlen = length( $hcainfo[1]);
            my $portprefix = substr($hcainfo[1],0,$portlen-2);
            my $portpostfix = substr($hcainfo[1],$portlen-2);
            my $portnum = hex $portpostfix;
            $portnum++;
            $portpostfix = sprintf '%x', $portnum;
            if ( length( $portpostfix) == 1)
            {
                $portpostfix = '0' . $portpostfix;
            }    
            $hcainfo[1] = $portprefix . $portpostfix;
                
            $adapters = $adapters . join( "/", @hcainfo ) . ',';
        }
        $adapters =~ s/^(.*),$/$1/;
        $cfgdata =~ s/hca_adapters=[^$delim]+/$adapters/;
    }
    return( $cfgdata );
}
##########################################################################
# Get unassigned hca guid
##########################################################################
sub get_unassigned_iba
{
    my $exp     = shift;
    my $mtms    = shift;
    my $ibacap  = shift;
    my $max_ib_num = 0;
    if ( ! $ibacap)
    {
        $ibacap = '1';
    }
    if ( $ibacap eq '1')
    {
        $max_ib_num = 16;
    }
    elsif ( $ibacap eq '2')
    {
        $max_ib_num = 8;
    }
    elsif ( $ibacap eq '3')
    {
        $max_ib_num = 4;
    }
    elsif ( $ibacap eq '4')
    {
        $max_ib_num = 1;
    }
    else
    {
        return undef;
    }

    my $hwres = xCAT::PPCcli::lshwres( $exp, ['sys','hca', 'adapter_id:phys_loc:unassigned_guids'], $mtms);
    my $Rc = shift(@$hwres);
    if ( $Rc == SUCCESS)
    {
        my @unassigned_ibas;
        my $ib_hash = {};
        for my $hca_info (@$hwres)
        {
            chomp $hca_info;
            if ($hca_info =~ /^(.+):(.+):(.+)$/)
            {
                my $adapter_id       = $1;
                my $phys_loc         = $2;
                my $unassigned_guids = $3;
                if ( $phys_loc =~ /C65$/ or $phys_loc =~ /C66$/ or $phys_loc =~ /C7$/)
                {
                    my @guids = split /,/, $unassigned_guids;
                    $max_ib_num = scalar( @guids) if (scalar( @guids) < $max_ib_num);
                    for (my $i = 0; $i < $max_ib_num; $i++)
                    {
                        my $guid = @guids[$i];
                        $guid =~ s/\s*(\S+)\s*/$1/;
                        unshift @{$ib_hash->{$phys_loc}->{$adapter_id}}, "$adapter_id/$guid/$ibacap";  
                    }
                }
            }
        }
        for my $loc ( sort keys %$ib_hash)
        {
            my $min_guid_num = -1;
            for my $id (keys %{$ib_hash->{$loc}})
            {
                if ( $min_guid_num == -1 or $min_guid_num > scalar( @{$ib_hash->{$loc}->{$id}}))
                {
                    $min_guid_num = scalar( @{$ib_hash->{$loc}->{$id}});
                }
            }
            for (my $i = 0; $i < $min_guid_num; $i++)
            {
                my $unassigned_iba = undef;
                for my $adp_id (sort keys %{$ib_hash->{$loc}})
                {
                    my $iba = $ib_hash->{$loc}->{$adp_id}->[$i];
                    $unassigned_iba .= ",$iba";
                }
                if ($unassigned_iba)
                {
                    $unassigned_iba =~ s/^,//;
                    push @unassigned_ibas, $unassigned_iba;
                }
            }
        }
        return \@unassigned_ibas;
    }
    else
    {
        return undef;
    }
}

##########################################################################
# get iba replacement pair (from source profile to target)
##########################################################################
sub get_iba_replace_pair
{
    my $unassigned_iba = shift;
    my $profile        = shift;

    #############################
    # Get hca info from profile
    #############################
    my @oldhca_prefixes;
    for my $cfg (@$profile)
    {
        if ( $cfg =~ /(\"*hca_adapters)/ )
        {
            my $delim = ( $1 =~ /^\"/ ) ? "\\\\\"" : ",";
            $cfg  =~ /hca_adapters=([^$delim]+)|$/;
            my $oldhca = $1;
            my @oldhcas = split /,/, $oldhca;
            for my $oldhca_entry (@oldhcas)
            {
                if ( $oldhca_entry =~ /(.+\/.+)..\/\d+/)
                {
                    my $oldhca_prefix = $1;
                    if (!grep /\Q$oldhca_prefix\E/, @oldhca_prefixes)
                    {
                        push @oldhca_prefixes, $oldhca_prefix;
                    }
                }
            }
        }
    }
    ###########################################
    # Get hca info from unasigned hca array
    ###########################################
    my @newhca_prefixes;
    for my $newhca ( @$unassigned_iba)
    {
        my @newhcas = split /,/, $newhca;
        for my $newhca_entry ( @newhcas)
        {
            if ( $newhca_entry =~ /(.+\/.+)..\/\d+/)
            {
                my $newhca_prefix = $1;
                if (!grep /\Q$newhca_prefix\E/,@newhca_prefixes)
                {
                    push @newhca_prefixes, $newhca_prefix;
                }
            }
        }
    }
    #############################    
    # Create replacement pair
    #############################
    my %pair_hash;
    for ( my $i = 0; $i < scalar @oldhca_prefixes; $i++)
    {
        $pair_hash{ @oldhca_prefixes[$i]} = @newhca_prefixes[$i];
    }

    return \%pair_hash;
}
##########################################################################
# Substitue hca info
##########################################################################
sub hcasubst
{
    my $cfgdata = shift;
    my $replace_hash = shift;
    if ( $cfgdata =~ /(\"*hca_adapters)/ ) {
        for my $oldhca_prefix (keys %$replace_hash)
        {
            $cfgdata =~ s/\Q$oldhca_prefix\E/$replace_hash->{$oldhca_prefix}/g;
        }
    }
    return $cfgdata;
}
##########################################################################
# Automatically configure HCA adapters
##########################################################################
sub hcaautoconf
{
    my $cfgdata = shift;
    my $unassignedhca = shift;
    $unassignedhca = [] if (!$unassignedhca);

    if ( $cfgdata =~ /(\"*hca_adapters)/ ) {
    
    #####################################
    # If double-quoted, has comma-
    # seperated list of adapters
    #####################################
        my $delim = ( $1 =~ /^\"/ ) ? "\\\\\"" : ","; 
        $cfgdata  =~ /hca_adapters=([^$delim]+)|$/;
        my $oldhca = $1;
        my $newhca;
        $newhca = shift @$unassignedhca;
            
        my $adapters = undef;
        if ( $newhca )
        {
            $adapters  = "hca_adapters=$newhca";
        }
        else
        {
            $adapters = "hca_adapters=none";
        }
        if ( $adapters =~ /,/ and $delim ne "\\\\\"")
        {
            $adapters = "\\\\\"" . $adapters . "\\\\\"";
        }
        $cfgdata =~ s/hca_adapters=[^$delim]+/$adapters/;
    }
    return $cfgdata ;
}

##########################################################################
# Increments virtual lhea adapter in partition profile 
##########################################################################
sub lhea_adapter {

    my $cfgdata = shift;

    #########################################
    # Increment LHEA adapters if present
    #   23000000/2/1/7/none,23000008/2/1/4/none 
    # Increment 7 and 4 in example above.
    #########################################
    if ( $cfgdata =~ /(\"*lhea_logical_ports)/ ) {

        #####################################
        # If double-quoted, has comma-
        # seperated list of adapters
        #####################################
        #my $delim = ( $1 =~ /^\"/ ) ? "\\\\\"" : ","; 
        #$cfgdata  =~ /lhea_logical_ports=([^$delim]+)|$/;
        $cfgdata  =~ /lhea_logical_ports=(.*)lhea_capabilities/;                                     
        my @lhea = split ",", $1;
        foreach ( @lhea ) 
        {
            if ( /(\d+)\/(\d+)\/(\d+)\/(\d+)/) 
            {
                my $id = $4;
                if($id =~ /\d+/) 
                {
                    $id = $id + 1;
                }
                s/(\d+)\/(\d+)\/(\d+)\/(\d+)/$1\/$2\/$3\/$id/;
            } 
        }        
        my $adapters = "lhea_logical_ports=".join( ",", @lhea );
        #$cfgdata =~ s/lhea_logical_ports=[^$delim]+/$adapters/;
        $cfgdata =~ s/lhea_logical_ports=(.*)lhea_capabilities/$adapters,lhea_capabilities/;        
    }
    return( $cfgdata );
}


##########################################################################
# Increments virtual scsi adapter in partition profile 
##########################################################################
sub scsi_adapter {

    my $cfgdata = shift;

    #########################################
    # Increment SCSI adapters if present
    #   15/server/6/1ae0-node1/11/1,
    #   14/server/5/1ae0-ms04/12/1,
    #   20/server/any//any/1 
    # Increment 11 and 12 in example above.
    #########################################
    if ( $cfgdata =~ /(\"*virtual_scsi_adapters)/ ) {

        #####################################
        # If double-quoted, has comma-
        # seperated list of adapters
        #####################################
        my $delim = ( $1 =~ /^\"/ ) ? "\\\\\"" : ","; 
        $cfgdata  =~ /virtual_scsi_adapters=([^$delim]+)|$/;
                                              
        my @scsi = split ",", $1;
        foreach ( @scsi ) {
            if ( /(\w+)\/(\w+)$/ ) {
                my $id = ($1 =~ /(\d+)/) ? $1+1 : $1;
                s/(\w+)\/(\w+)$/$id\/$2/;
            } 
        }
        my $adapters = "virtual_scsi_adapters=".join( ",", @scsi );
        $cfgdata =~ s/virtual_scsi_adapters=[^$delim]+/$adapters/;
    }
    return( $cfgdata );
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
    my $lpar;
    my $d;
    my $lparid;
    my $mtms;
    my $type;
    my $profile;
    xCAT::MsgUtils->verbose_message($request, "$request->{command} START.");
    #####################################
    # Get source node information
    #####################################
    while ( my ($cec,$h) = each(%$hash) ) {
        while ( my ($name,$data) = each(%$h) ) {
            $d      = $data;
            $lparid = @$d[0];
            $mtms   = @$d[2];
            $type   = @$d[4];
            $lpar   = $name;
        }
    }
    #####################################
    # Must be CEC or LPAR 
    #####################################
    if ( $type !~ /^(lpar|fsp|cec)$/ ) {
        return( [[$lpar,"Node must be LPAR or CEC",RC_ERROR]] );
    }
    #####################################
    # Clone all the LPARs on CEC 
    #####################################
    if ( exists( $opt->{c} )) {
        my $result = clone( $request,
                            $exp, 
                            $opt->{target}, 
                            $opt->{profile}, 
                            $d, 
                            $request->{node}->[0]
                          );
        foreach ( @$result ) { 
            my $Rc = shift(@$_);
            push @values, [$opt->{c}, @$_[0], $Rc];
        }
        return( \@values ); 
    }
    #####################################
    # Get source LPAR profile  
    #####################################
    xCAT::MsgUtils->verbose_message($request, "$request->{command} :lssyscfg prof.filter:'lpar_ids=$lparid'.");
    my $prof = xCAT::PPCcli::lssyscfg(
                              $exp,
                              "prof",
                              $mtms,   
                              "lpar_ids=$lparid" ); 
    my $Rc = shift(@$prof);

    #####################################
    # Return error
    #####################################
    if ( $Rc != SUCCESS ) {
        return( [[$lpar, @$prof[0], $Rc]] );
    } 
    #####################################
    # Get source node pprofile attribute
    #####################################
    my $pprofile = @$d[1];

    #####################################
    # Find pprofile on source node
    #####################################
    my ($prof) = grep /^name=$pprofile\,/, @$prof;
    if ( !$prof ) {
        return( [[$lpar, "'pprofile=$pprofile' not found on '$lpar'", RC_ERROR]] );
    }
    #####################################
    # Get command-line options
    #####################################
    my $id   = $opt->{i};
    my $cfgdata = strip_profile( $prof, $hwtype );
    
    #####################################
    # Set profile name for all LPARs
    #####################################
    if ( $hwtype eq "hmc" ) {
        $cfgdata =~ s/^name=([^,]+|$)/profile_name=$1/;
        $profile = $1;
        $cfgdata =~ s/lpar_name=/name=/;
    }
    
    foreach my $name ( @{$opt->{target}} ) {

        #################################
        # Modify read-back profile.
        # See HMC or IVM mksyscfg man
        # page for valid attributes.
        #
        #################################
        $cfgdata =~ s/\blpar_id=[^,]+|$/lpar_id=$id/;
        $cfgdata =~ s/\bname=[^,]+|$/name=$name/;

        #################################
        # Modify LHEA adapters
        #################################
        if ( $cfgdata =~ /lhea_logical_ports=(\w+)/ ) {
            if ( $1 !~ /^none$/i ) {
                $cfgdata = lhea_adapter( $cfgdata );
            }
        }
        #################################
        # Modify HCA adapters
        #################################
        if ( $cfgdata =~ /hca_adapters=(\w+)/ ) {
            if ( $1 !~ /^none$/i ) {
                $cfgdata = hca_adapter( $cfgdata );
            }
        }
        #################################
        # Modify SCSI adapters
        #################################
        if ( $cfgdata =~ /virtual_scsi_adapters=(\w+)/ ) {
            if ( $1 !~ /^none$/i ) {
                $cfgdata = scsi_adapter( $cfgdata );
            }
        }
        #################################
        # Create new LPAR  
        #################################
        xCAT::MsgUtils->verbose_message($request, "$request->{command} :mksyscfg lpar.cfg:'$cfgdata'.");
        $result = xCAT::PPCcli::mksyscfg( $exp, "lpar", $d, $cfgdata ); 
        $Rc = shift(@$result);

        #################################
        # Add new LPAR to database 
        #################################
        if ( $Rc == SUCCESS ) {
            xCAT::MsgUtils->verbose_message($request, "$request->{command} :add lpar:$name from xCATdb.");
            my $err = xCATdB( "mkvm", $name, $profile, $id, $d, $hwtype, $lpar);
            if ( defined( $err )) {
                push @values, [$name,$err,RC_ERROR];
                $id++;
                next;
            }
        }
        push @values, [$name,@$result[0],$Rc];
        $id++;
    }
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END.");
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
        $cfgdata =~ s/,*lpar_proc_compat_mode=[^,]+|$//;
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
    my $profile = shift;
    my $lparid  = shift;
    my $d       = shift;
    my $hwtype  = shift;
    my $lpar    = shift;
    my $parent  = shift;

    #######################################
    # Remove entry 
    #######################################
    if ( $cmd eq "rmvm" ) {

        my $ppctab = xCAT::Table->new('ppc');
        unless ($ppctab) {   # no ppc table
            return( "Error opening 'ppc' database" );
        }

        my @nodes = $ppctab->getAllNodeAttribs(['node','id','parent']);

        foreach my $node (@nodes) {
            my $type = xCAT::DBobjUtils->getnodetype($node->{node});
            if ( $type =~ /lpar/ and $lparid eq $node->{id} and $parent eq $node->{parent} ) {
                return( xCAT::PPCdb::rm_ppc( $node->{node} ));
            }
        }
    }
    #######################################
    # Change entry 
    #######################################
    elsif ( $cmd eq "chvm" ) {
        my $ppctab = xCAT::Table->new( "ppc", -create=>1, -autocommit=>1 );

        ###################################
        # Error opening ppc database
        ###################################
        if ( !defined( $ppctab )) {
            return( "Error opening 'ppc' database" );
        }
        $ppctab->setNodeAttribs( $name, {pprofile=>$profile} );
    }
    #######################################
    # Add entry 
    #######################################
    else {
        if ( !defined( $profile )) {
            $profile = $name;
        }
        my ($model,$serial) = split /\*/,@$d[2];
        my $server   = @$d[3];
        my $fsp      = @$d[2];
        
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
        ###################################
        # If there is no parent provided
        # this lpar should be the cloned 
        # in the same cec
        # Otherwise it should be cloned 
        # between cecs
        ###################################
        if ( ! $parent) 
        {
            my ($ent) = $tab->getNodeAttribs($lpar, ['parent'] );

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
            $parent = $ent->{parent};
        }

        my $values = join( ",",
                "lpar",
                $name,
                $lparid,
                $model,
                $serial,
                "",
                $server,
                $profile,
                $parent ); 
        
        return( xCAT::PPCdb::add_ppc( $hwtype, [$values],'','',"PPC" )); 
    }
    return undef;
}


##########################################################################
# The mkfulllpar function is written in ksh, and used to create a full
# system partition for each CECs Managed by the HMC. It will use ssh to
# login the HMC with the hscroot userid in order to rename the CECs based
# on a certain pattern specified through command line and create full
# partition for all the CECs.
##########################################################################

sub mkfulllpar {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @values  = ();
    my $result;
    my $lpar;
    my $d;
    my $lparid;
    my $mtms;
    my $type;
    my $profile;
   
    my $ppctab  = xCAT::Table->new('ppc'); 
    #####################################
    # Get source node information
    #####################################
    while ( my ($cec,$h) = each(%$hash) ) {
        my ($name,$data) = each(%$h);
            $d      = $data;
            $lparid = @$d[0];
            $mtms   = @$d[2];
            $type   = @$d[4];
            $lpar   = $name;
    #####################################
    # Must be CEC or LPAR 
    #####################################
    if ( $type !~ /^(lpar|fsp|cec)$/ ) {
        return( [[$lpar,"Node must be LPAR or CEC",RC_ERROR]] );
    }

    my $ppctab  = xCAT::Table->new('ppc');
        #####################################
        # Check if a existing with requested LPAR ID has existed  
        #####################################
        my $value = xCAT::PPCcli::lssyscfg(
                                  $exp,
                                  "profs",
                                  $mtms,
                      "all_resources",   
                                  "lpar_ids=$lparid" ); 
        my $Rc = shift(@$value);
        #######################################
        # make how to handle according to the result of lssyscfg
        #######################################
        if ( $Rc == SUCCESS ) {
            # close the DB handler of the ppc table
            $ppctab->close;
            # change the lpar's attribute before removing it.            
            my $all_res_flag = @$value[0];
            if ( $all_res_flag != 1 ) {
                return( [[$lpar,"The LPAR ID has been occupied",RC_ERROR]] );
            }
            else {
                return( [[$lpar,"This full LPAR has been created",RC_ERROR]] );
            }
        }
        
        #################################
        # Create the new full LPAR's configure data  
        #################################
        my ($lpar_id, $profname);
        my $vcon = $ppctab->getAttribs($name, ('id','pprofile'));
           if ($vcon) {
               if ($vcon->{"id"}) {
                $lpar_id = $vcon->{"id"};
               } else {
                $lpar_id = 1;
               }

               if ($vcon->{"pprofile"}) {
                $profname = $vcon->{"pprofile"};
               } else {
                $profname = $name;
               }
           } else {
            $lpar_id    = 1;
            $profname    = $name;
           }
           
        my $cfgdata    = "name=$name,profile_name=$profname,lpar_id=$lpar_id,lpar_env=aixlinux,all_resources=1,boot_mode=norm,conn_monitoring=0";
                
        #################################
        # Create a new full LPAR
        #################################
        $result = xCAT::PPCcli::mksyscfg( $exp, "lpar", $d, $cfgdata ); 
        $Rc        = shift(@$result);

        ###########################################
        # Set the CEC's service_lpar_id to the lpar_id of the full LPAR
        ###########################################
        if ( $Rc == SUCCESS) {
            $cfgdata    = "service_lpar_id=$lpar_id";  
            $result        = xCAT::PPCcli::chsyscfg( $exp, "fsp", $d, $cfgdata  );
            $Rc            = shift(@$result);
            if ( $Rc != SUCCESS ) {
                $ppctab->close;
                return( [[$lpar, @$result[0], $Rc]] );
            }
        }
        
        #################################
        # Add a new full LPAR to database 
        #################################
        if ( $Rc == SUCCESS ) {
            $profile = $profname;
            my $id = $lpar_id;
            my $err = xCATdB( "mkvm", $name, $profile, $id, $d, $hwtype, $lpar);
            if ( defined( $err )) {
                push @values, [$name,$err,RC_ERROR];
                next;
            }
        }
        push @values, [$name,@$result[0],$Rc];
    }

    $ppctab->close;
    return( \@values );
}


##########################################################################
# Creates logical partitions 
##########################################################################
sub mkvm {
    my $request = $_[0];
    my $opt     = $request->{opt};
    
    # decide if issuing mkvm with the option '-f'.
    # if yes, mklpar will be invoked to
    # create a full system partition for each CECs managed by the HMC.
        if ( exists($opt->{full})) {
                return( mkfulllpar(@_) );
        }
        else {
        # if no, it will execute the original function.
    return( create(@_) );
    }
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










