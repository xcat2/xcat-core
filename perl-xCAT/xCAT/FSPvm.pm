# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

BEGIN
{
	    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}


package xCAT::FSPvm;
use lib "$::XCATROOT/lib/perl";
use strict;
use Getopt::Long;
use xCAT::PPCdb;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::NodeRange;
use xCAT::FSPUtils;
#use Data::Dumper;
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

sub chvm_parse_extra_options {
	my $args = shift;
	my $opt = shift;
    # Partition used attributes #
    my @support_ops = qw(vmcpus vmmemory vmphyslots vmothersetting);
	if (ref($args) ne 'ARRAY') {
		return "$args";
	}	
	foreach (@$args) {
		my ($cmd, $value) = split (/\=/, $_);
		if (!defined($value)) {
			return "no value specified";
		}
		if ($cmd =~ /^lparname$/) {
			if ($value ne '*' && $value !~ /^[a-zA-Z0-9-_]+$/) {
				return "'$value' invalid";
			}	
			my $len = rindex $value."\$", "\$";
            if ($len > '47') {
                return "'$value' is too long, max 47 characters";
            }
#       } elsif ($cmd =~ /^huge_page$/) {
#			if ($value !~ /^\d+\/\d+\/\d+$/) {
#				return "'$value' invalid";
#			}
        } elsif (grep(/^$cmd$/, @support_ops)) {
            if (exists($opt->{p775})) {
                return "'$cmd' doesn't work for Power 775 machines.";
            } elsif ($cmd eq "vmothersetting") {
                if ($value =~ /hugepage:\s*(\d+)/i) {
                    $opt->{huge_page} = $1;
                }
                if ($value =~ /bsr:\s*(\d+)/i) {
                    $opt->{bsr} = $1;
                }
                next;
            }

        } else {
			return "'$cmd' not support";
		}
		$opt->{$cmd} = $value;
	}
	return undef;
}

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

    if ( !GetOptions( \%opt, qw(V|verbose p=s i=s m=s r=s p775) )) {
        return( usage() );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Configuration file required 
    ####################################
    #if ( !exists( $opt{p}) ) { 
    #    if ( !defined( $request->{stdin} )) { 
    #        return(usage( "Configuration file or attributes not specified" ));
    #    }
    #}
    if (exists($opt{p775})) { 
    my @cfgdata ;
    if ((exists ($opt{p}) || defined($request->{stdin})) && !exists($opt{p775}) ) {
        return(usage("Profile just work for Power 775"));
    }
    if ( exists( $opt{p})) {
        
	if ( exists( $opt{i} ) ||  exists( $opt{r}) || exists( $opt{m} ) ) {
            return(usage("-p should NOT  be used with -i, -r or -m."));
        }
	
        $opt{p} = $request->{cwd}->[0] . '/' . $opt{p} if ( $opt{p} !~ /^\//);
        return ( usage( "Profile $opt{p} cannot be found")) if ( ! -f $opt{p});
        open (PROFFILE, "<$opt{p}") or return ( usage( "Cannot open profile $opt{p}"));
        while(  <PROFFILE>) {
            chomp;
            if( $_ =~ /(\d+):(\s+)(\d+)\/([\w\.\-]+)\/(\w+)\//) {
                push @cfgdata, $_;
            } else {
                return ( usage( "Invalid line in profile: $_"));
            }
        }
        $opt{profile} = \@cfgdata;
    }     

    if (defined( $request->{stdin} )) {
        $opt{p} = 1;
	if ( exists( $opt{i} ) ||  exists( $opt{r} ) || exists( $opt{m} ) ) {
            return(usage("When the profile is piped into the chvm command, the -i, -r and -m could NOT be used."));
        }
    }
    #if (defined( $request->{stdin} )) {
    #     my $p =  $request->{stdin};
    #     my @io = split(/\n/, $p) ;
    #     foreach (@io) {
    #         chomp;
    #         if( $_ =~ /(\d+):(\s+)(\d+),([\w\.\-]+),(\w+),/) {
    #            push @cfgdata, $_;
    #         } else {
    #             return ( usage( "Invalid line in profile: $_"));
    #         }
                  
    #     }
         
    #    $opt{profile} = \@cfgdata;
    #}
    #print "in parse args:\n";
    #print Dumper(\%opt);


    
    if ( exists( $opt{i} ) ) {
	if( !exists( $opt{r} ) ) {
            return(usage( "Option -i should be used with option -r ." ));
	}
	
        if ( $opt{i} !~ /^([1-9]{1}|[1-9]{1}[0-9]+)$/ ) {
            return(usage( "Invalid entry: $opt{i}" ));
        }
        my @id = (1, 5, 9, 13, 17, 21, 25, 29);
        my @found =  grep(/^$opt{i}$/, @id );
	if ( @found != 1) {
            return(usage( "Invalid entry: $opt{i}.\n For Power 775, starting numeric id of the newly created partitions only could be 1, 5, 9, 13, 17, 21, 25 and 29." ));
        }
       
	#if ( !exists($opt{o})  ) {
	#    return(usage("For Power 775, -i should be used with -o"));
	#}
      
	#my @value = (1, 2, 3, 4, 5);
	#if ( grep(/^$opt{i}$/, @id ) != 1) {
	#    return(usage( "Invalid entry: $opt{o}.\n For Power 775, octant configuration values only could be 1, 2, 3, 4, 5. Please see the details in manpage of mkvm." ));
	#}
       
	
    } 
  
    
    # pending memory interleaving mode  (1- interleaved, 2- non-interleaved)
    # non-interleaved mode means the memory cannot be shared across the processors in an octant.
    # interleaved means the memory can be shared.
    if( exists($opt{m}) ) {
        if( $opt{m} =~ /^interleaved$/ || $opt{m} =~ /^1$/ ) {
	    $opt{m} = 1;
	} elsif( $opt{m} =~ /^non-interleaved$/ || $opt{m} =~ /^2$/  ) {
	    $opt{m} = 2;
	} else {
            return(usage( "Invalid entry: $opt{m}.\n For Power 775, the pending memory interleaving mode only could be interleaved(or 1), or non-interleaved(or 2)." ));
	}
    } else {
        $opt{m} = 1 ;# interleaved, which is the default    
    }
   
    my @ratio = (1, 2, 3, 4, 5);
    my %octant_cfg = ();
    if ( exists( $opt{r} ) ) {
    
	if( !exists( $opt{i} ) ) {
            return(usage( "Option -r should be used with option -i ." ));
	}
	    
        my @elems = split(/\,/,$opt{r});
        my $range="";
        while (my $elem = shift @elems) {
            if ($elem !~ /\:/) {
                return (usage("Invalid argument $elem.\n The input format for 'r' should be like this: \"-r Octant_id:Value\"."))
            }
            if($elem !~ /\-/) {
		my @subelems = split(/\:/, $elem);
	        if( $subelems[0] < 0 || $subelems[0] > 7) {
		    return(usage("Octant ID only could be 0 to 7 in the octant configuration value $elem"));
		}
		if( grep(/^$subelems[1]$/, @ratio ) != 1) {
	            return(usage( "Invalid octant configuration value in $elem.\n For Power 775, octant configuration values only could be 1, 2, 3, 4, 5. Please see the details in manpage of chvm." ));
		}
		if( exists($octant_cfg{$subelems[0]}) && $octant_cfg{$subelems[0]} == $subelems[1] ) {
	            return(usage("In the octant configuration rule, same octant with different octant configuration value. Error!"));	
		}
                $octant_cfg{$subelems[0]} = $subelems[1];
	        $range .= "$elem,";
	    } else {
	        my @subelems = split(/\:/, $elem);
		my ($left,$right) = split(/\-/, $subelems[0]);
	        if( $left < 0 || $left > 7 || $right < 0 || $right > 7) {
		       return(usage("Octant ID only could be 0 to 7 in the octant configuration rule $elem"));
		}
                if($left == $right) {
		   if( grep(/^$subelems[1]$/, @ratio ) != 1) {
	               return(usage( "Invalid octant configuration value in $elem.\n For Power 775, octant configuration values only could be 1, 2, 3, 4, 5. Please see the details in manpage of chvm." ));
		   }
		   if( exists($octant_cfg{$left}) || $octant_cfg{$left} == $subelems[1] ) {
	               return(usage("In the octant configuration rule, same octant with different octant configuration value. Error!"));	
		   }
		   $octant_cfg{$left} = $subelems[1];
		   $range .="$left:$subelems[1],"
		} elsif($left < $right ) {
		   my $i = $left;   
		   for( $i; $i <=$right ; $i ++) {
		       if( exists($octant_cfg{$i}) || $octant_cfg{$i} == $subelems[1] ) {
	                   return(usage("In the octant configuration rule, same octant with different octant configuration value. Error!"));	
		       }
		       $octant_cfg{$i} = $subelems[1];

		       $range .= "$i:$subelems[1],";
		   }
		} else {
		   return(usage("In the octant configuration rule $elem, the left octant ID could NOT be bigger than the right octant ID"));  	
		}
	    } # end of "if .. else.."
        } # end of while
    } #end of if
     
    if ( exists( $opt{i} ) &&  exists( $opt{r} ) ) {
        $opt{octant_cfg}{octant_cfg_value} = (\%octant_cfg);
        $opt{octant_cfg}{memory_interleave} = $opt{m};
    
        $opt{target} = \@{$request->{node}};
        my $ppctab = xCAT::Table->new( 'ppc');
        unless($ppctab) {
            return(usage("Cannot open ppc table"));
        }
 
        my $other_p;
        foreach my $node( @{$request->{node}} ) {
            my $parent_hash    = $ppctab->getNodeAttribs( $node,[qw(parent)]);
            my $p = $parent_hash->{parent};
            if ( !$p) {
                return(usage("Not found the parent of $node"));
            }
            if(! defined( $other_p)) {
                $other_p = $p;
            } 
            if ($other_p ne $p) {
                return(usage("For Power 775, please make sure the noderange are in one CEC "));
            }
        } 
        $request->{node} = [$other_p]; 
        $request->{noderange} = $other_p;  
    }
    }
    ####################################
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        my $check_chvm_arg = chvm_parse_extra_options(\@ARGV, \%opt);
        if (defined($check_chvm_arg)) {
            return (usage("Invalid argument: $check_chvm_arg"));
        } elsif (($opt{lparname} ne '*') && (scalar(@{$request->{node}}) > '1')){
            return(usage( "Invalid argument: must specify '*' for more than one node" ));
        }
        if ((exists($opt{lparname}) ||exists($opt{huge_page})) && 
                (exists($opt{p}) || exists($opt{i}) || exists($opt{r}))) {
            return (usage("lparname should NOT be used with -p, -i or -r."));
        }
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
    #if ( !defined( $args )) {
    #    return(usage( "No command specified" ));
    #}
#############################################
# Checks case in GetOptions, allows opts
# to be grouped (e.g. -vx), and terminates
# at the first unrecognized option.
#############################################
    if (defined($args)) {
        @ARGV = @$args;
    }
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );
#    if ( !GetOptions( \%opt, qw(V|verbose ibautocfg ibacap=s i=s l=s c=s p=s m=s r=s full) )) {
#        return( usage() );
#    }
    if ( !GetOptions( \%opt, qw(V|verbose full vios) )) {
        return( usage() );
    }
####################################
# Check for "-" with no option
####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    if (!exists($opt{p775})) {
        my @unsupport_ops = ();
        foreach my $tmpop (keys %opt) {
            if ($tmpop !~ /full|vios|V/) {
                push @unsupport_ops, $tmpop;
            }
        }
        my @support_ops = qw(vmcpus vmmemory vmphyslots vmothersetting);
        if (defined(@ARGV[0]) and defined($opt{full})) {
            return(usage("Option 'full' shall be used alone."));
        } elsif (defined(@ARGV[0])) {
            foreach my $arg (@ARGV) {
                my ($cmd,$val) = split (/=/,$arg);
                if (!grep(/^$cmd$/, @support_ops))  {
                    push @unsupport_ops, $cmd;
                } elsif (!defined($val)) {
                    return(usage("The option $cmd need specific parameters."));
                } else {
                    $opt{$cmd} = $val;
                }
            }
        }

        if (@unsupport_ops) {
            my $tmpops = join(",",@unsupport_ops);
            return(usage( "The options $tmpops can only work(s) with Power 775 machines."));
        }
    } else {
        if (exists($opt{full}) or exists($opt{vios})) {
            return(usage( "Option 'p775' only works for Power 775 machines."));
        }
####################################
# Check for non-zero integer 
####################################
    if ( exists( $opt{i} ) ) {
        if ( $opt{i} !~ /^([1-9]{1}|[1-9]{1}[0-9]+)$/ ) {
            return(usage( "Invalid entry: $opt{i}" ));
        }
        my @id = (1, 5, 9, 13, 17, 21, 25, 29);
        my @found =  grep(/^$opt{i}$/, @id );
	if ( @found != 1) {
            return(usage( "Invalid entry: $opt{i}.\n For Power 775, starting numeric id of the newly created partitions only could be 1, 5, 9, 13, 17, 21, 25 and 29." ));
        }
       
	#if ( !exists($opt{o})  ) {
	#    return(usage("For Power 775, -i should be used with -o"));
	#}
      
	#my @value = (1, 2, 3, 4, 5);
	#if ( grep(/^$opt{i}$/, @id ) != 1) {
	#    return(usage( "Invalid entry: $opt{o}.\n For Power 775, octant configuration values only could be 1, 2, 3, 4, 5. Please see the details in manpage of mkvm." ));
	#}
       
	
    } 
  
    
    # pending memory interleaving mode  (1- interleaved, 2- non-interleaved)
    # non-interleaved mode means the memory cannot be shared across the processors in an octant.
    # interleaved means the memory can be shared.
    if( exists($opt{m}) ) {
        if( $opt{m} =~ /^interleaved$/ || $opt{m} =~ /^1$/ ) {
	    $opt{m} = 1;
	} elsif( $opt{m} =~ /^non-interleaved$/ || $opt{m} =~ /^2$/  ) {
	    $opt{m} = 2;
	} else {
            return(usage( "Invalid entry: $opt{m}.\n For Power 775, the pending memory interleaving mode only could be interleaved(or 1), or non-interleaved(or 2)." ));
	}
    } elsif (exists($opt{p775})){
        $opt{m} = 2 ;# non-interleaved, which is the default    
    }
   
    if ( exists( $opt{r} ) ) {
        my @ratio = (1, 2, 3, 4, 5);
        my %octant_cfg = ();

        my @elems = split(/\,/,$opt{r});
        my $range="";
        while (my $elem = shift @elems) {
            if($elem !~ /\-/) {
		my @subelems = split(/\:/, $elem);
	        if( $subelems[0] < 0 || $subelems[0] > 7) {
		    return(usage("Octant ID only could be 0 to 7 in the octant configuration value $elem"));
		}
		if( grep(/^$subelems[1]$/, @ratio ) != 1) {
	            return(usage( "Invalid octant configuration value in $elem.\n For Power 775, octant configuration values only could be 1, 2, 3, 4, 5. Please see the details in manpage of mkvm." ));
		}
		if( exists($octant_cfg{$subelems[0]}) && $octant_cfg{$subelems[0]} == $subelems[1] ) {
	            return(usage("In the octant configuration rule, same octant with different octant configuration value. Error!"));	
		}
                $octant_cfg{$subelems[0]} = $subelems[1];
	        $range .= "$elem,";
	    } else {
	        my @subelems = split(/\:/, $elem);
		my ($left,$right) = split(/\-/, $subelems[0]);
	        if( $left < 0 || $left > 7 || $right < 0 || $right > 7) {
		       return(usage("Octant ID only could be 0 to 7 in the octant configuration rule $elem"));
		}
                if($left == $right) {
		   if( grep(/^$subelems[1]$/, @ratio ) != 1) {
	               return(usage( "Invalid octant configuration value in $elem.\n For Power 775, octant configuration values only could be 1, 2, 3, 4, 5. Please see the details in manpage of mkvm." ));
		   }
		   if( exists($octant_cfg{$left}) || $octant_cfg{$left} == $subelems[1] ) {
	               return(usage("In the octant configuration rule, same octant with different octant configuration value. Error!"));	
		   }
		   $octant_cfg{$left} = $subelems[1];
		   $range .="$left:$subelems[1],"
		} elsif($left < $right ) {
		   my $i = $left;   
		   for( $i; $i <=$right ; $i ++) {
		       if( exists($octant_cfg{$i}) || $octant_cfg{$i} == $subelems[1] ) {
	                   return(usage("In the octant configuration rule, same octant with different octant configuration value. Error!"));	
		       }
		       $octant_cfg{$i} = $subelems[1];

		       $range .= "$i:$subelems[1],";
		   }
		} else {
		   return(usage("In the octant configuration rule $elem, the left octant ID could NOT be bigger than the right octant ID"));  	
		}
	    } # end of "if .. else.."
        } # end of while
        $opt{octant_cfg}{octant_cfg_value} = (\%octant_cfg);
        $opt{octant_cfg}{memory_interleave} = $opt{m};
    } #end of if
    
        
    if ( (!exists( $opt{i} ) ||  !exists( $opt{r} )) ) {
        return(usage());
    }
    } 
    $opt{target} = \@{$request->{node}};
    my $ppctab = xCAT::Table->new( 'ppc');
    unless($ppctab) {
        return(usage("Cannot open ppc table"));
    }
 
    my $other_p;
    foreach my $node( @{$request->{node}} ) {
        my $parent_hash    = $ppctab->getNodeAttribs( $node,[qw(parent)]);
        my $p = $parent_hash->{parent};
        if ( !$p) {
           return(usage("Not found the parent of $node"));
        }
        if (exists($opt{full}) and defined($other_p) and $other_p eq $p){
            return(usage("Only one full partition can be created in one CEC"));
        }

        if(! defined( $other_p)) {
            $other_p = $p;
        } 
        if ($other_p ne $p) {
            return(usage("For Power 775, please make sure the noderange are in one CEC "));
        }
    } 
    if (exists($opt{p775})) {
        $request->{node} = [$other_p]; 
        $request->{noderange} = $other_p;  
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

    if ( !GetOptions( \%opt, qw(V|verbose service r p775) )) {
        return( usage() );
    }

    if (exists($opt{p775})) {
        return(usage( "rmvm doesn't support for Power 775." ));
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

    if ( !GetOptions( \%opt, qw(V|verbose l|long p775) )) {
        return( usage() );
    }
    if (exists($opt{l}) && !exists($opt{p775})) {
        return(usage( "option 'l' only works for Power 775"));
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
# Changes the configuration of an existing partition 
##########################################################################
sub modify {
    my $request = shift;
    my $hash    = shift;
    my $usage_string = xCAT::Usage->getUsage($request->{command});
    return modify_by_prof( $request, $hash) if ( exists($request->{opt}->{p775}) and ($request->{opt}->{p} || $request->{stdin})); 
    return create( $request, $hash) if ( exists($request->{opt}->{p775}) and $request->{opt}->{i}); 
    return op_extra_cmds ($request, $hash) if (!exists($request->{opt}->{p775}));
    return op_extra_cmds ($request, $hash) if ($request->{opt}->{lparname} || $request->{opt}->{huge_page});
    return ([["Error", "Miss argument\n".$usage_string, 1]]);
}
sub do_op_extra_cmds {
    my $request = shift;
    my $hash = shift;
    my @values = ();

    while (my ($mtms, $h) = each(%$hash)) {
        my $memhash;
        while (my($name, $d) = each(%$h)) {
            foreach my $op (keys %{$request->{opt}}) {
	        my $action;
	        my $param = $request->{opt}->{$op};
	        if ($op eq "lparname") {
		    $action = "set_lpar_name";
	        } elsif ($op eq "huge_page") {
		    $action = "set_huge_page";
	        } elsif ($op eq "vmcpus") {
                    $action = "part_set_lpar_pending_proc";
                } elsif ($op eq "vmphyslots") {
                    $action = "set_io_slot_owner_uber";
                } elsif ($op eq "vmmemory") {
                    my @td = @$d;
                    @td[0] = 0;
                    $memhash = &query_cec_info_actions($request, $name, \@td, 1, ["part_get_hyp_process_and_mem"]);
                    if (!exists($memhash->{run})) {
                        if ($param =~ /(\d+)([G|M]?)\/(\d+)([G|M]?)\/(\d+)([G|M]?)/i) {
                            my $memsize = $memhash->{mem_region_size};
                            my $min = $1;
                            if ($2 == "G" or $2 == '') {
                                $min = $min * 1024;
                            } 
                            $min = $min/$memsize;
                            my $cur = $3;
                            if ($4 == "G" or $4 == '') {
                                $cur = $cur * 1024;
                            }
                            $cur = $cur/$memsize;
                            my $max = $5;
                            if ($6 == "G" or $6 == '') {
                                $max = $max * 1024;
                            }
                            $max = $max/$memsize;
                            $request->{opt}->{$op} ="$min/$cur/$max";
                            $param = $request->{opt}->{$op};
                        } else {
                            return([[$name, "The format of param:$param is incorrect.", 1]]);
                        }
                        $memhash->{run} = 1;
                    }
                    $memhash->{memory} = $param;
                    $memhash->{lpar_used_regions} = 0;
                    my $ret = &deal_with_avail_mem($request, $name, $d, $memhash);
                    if (ref($ret) eq "ARRAY") {
                        return ([[@$ret]]);
                    }
                    $param = $memhash->{memory};
                    $action = "part_set_lpar_pending_mem";
                } elsif ($op eq "bsr") {
                    $action = "set_lpar_bsr";
                } else {
                    last;
                }
                my $tmp_value = ($param eq '*') ? $name : $param;
                xCAT::MsgUtils->verbose_message($request, "$request->{command} $action for node:$name, parm:$tmp_value."); 
                my $value = xCAT::FSPUtils::fsp_api_action($request, $name, $d, $action, 0, $tmp_value);
                if (@$value[1] && ((@$value[1] =~ /Error/i) && (@$value[2] ne '0'))) {
                    return ([[$name, @$value[1], '1']]) ;
                } else {
                    push @values, [$name, "Success", '0'];
                } 
            }
        }
    } 
    return \@values;
}
sub check_node_info {
    my $hash = shift;
    my $not_lpar = undef;
    while (my ($mtms, $h) = each(%$hash)) {
        while (my($name, $d) = each(%$h)) {
            my $node_type = @$d[4];
            if ($node_type !~ /^lpar$/) {
                $not_lpar = $name;
                last; 
            }
        } 
    }
    return $not_lpar;
}

sub op_extra_cmds {
    my $request = shift;
    my $hash = shift;
    my $node = $request->{node};
    my $lpar_flag = &check_node_info($hash);
    if (defined($lpar_flag)) {
        return ([[$lpar_flag,"Node must be LPAR", 1]]);
    }
    return &do_op_extra_cmds($request, $hash);
}


##########################################################################
# Changes the configuration of an existing 
# partition based on the profile specified
##########################################################################
sub modify_by_prof {
    my $request = shift;
    my $hash    = shift;
    my $name    = @{$request->{node}}[0];
    my $opt     = $request->{opt};
    my @values;
    my $cfgdata = $opt->{profile};
    my $profile;
    my $cec_name; 
    my $td; 
    my %io = ();   
    my %lpar_state = ();
    my @result;   
    xCAT::MsgUtils->verbose_message($request, "$request->{command} START."); 
    if (defined( $request->{stdin} )) {
         my $p =  $request->{stdin};
         my @io = split(/\n/, $p) ;
         foreach (@io) {
             chomp;
             if( $_ =~ /(\d+):(\s+)(\d+)\/([\w\.\-]+)\/(\w+)\//) {
                push @$cfgdata, $_;
             } else {
                return (\["Error", "Invalid line in profile: $_", -1]);
             }
                  
         }
    }
    #print Dumper($cfgdata);
    while (my ($cec,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            $td = $d;
            #@$td[4] = "fsp";
            $cec_name = @$d[3]; 
        }
        $td->[4] = "cec";
        #get the current I/O slot information
        xCAT::MsgUtils->verbose_message($request, "$request->{command} :get_io_slot_info for node:$cec_name."); 
        my $action = "get_io_slot_info";
        my $values =  xCAT::FSPUtils::fsp_api_action ($request, $cec_name, $td, $action);
        my $Rc = $$values[2];
        if ( $Rc != 0 ) {
            push @result, [$cec_name, $$values[1], $Rc];
            return (\@result);
        }
        my @data = split(/\n/, $$values[1]);
        foreach my $v (@data) {
            my ($lparid, $busid, $location, $drc_index, $owner_type, $owner, $descr) = split(/,/, $v);
            $io{$drc_index}{lparid} = $lparid;
            $io{$drc_index}{owner_type} = $owner_type;
            $io{$drc_index}{owner} = $owner;
        } 
        
        #get all the nodes state in the same cec
        xCAT::MsgUtils->verbose_message($request, "$request->{command} :get all the nodes state for CEC:$cec_name."); 
        $action = "all_lpars_state";
        undef($values);
        my $values =  xCAT::FSPUtils::fsp_state_action ($request, $cec_name, $td, $action); 
        $Rc = shift(@$values);
        if ( $Rc != 0 ) {
            push @result, [$cec_name, $$values[0], $Rc];
            return (\@result);
        }
        foreach ( @$values ) {
             my ($state,$lparid) = split /,/;
             $lpar_state{$lparid} = $state;
        } 
    } 
    ################################## 
    # Check if LPAR profile exists 
    ###################################
    while (my ($cec,$h) = each(%$hash) ) {
        while (my ($lpar,$d) = each(%$h) ) {
            my $id = @$d[0];
            #print Dumper($cfgdata);
            my @found = grep(/^$id:/, @$cfgdata );
            #print Dumper(\@found); 
            my $action = "set_io_slot_owner";
            my $tooltype = 0; 
            foreach my $f (@found) {
                #'1: 514/U78A9.001.0123456-P1-C17/0x21010202/2/1'
                my ($bus,$location,$drc_index,@t) = split(/\//, $f);
                my $orig_id = $io{$drc_index}{lparid};
                # the current owning lpar and the new owning lpar must be in power off  state
                if (($lpar_state{$orig_id} ne "Not Activated") || ($lpar_state{$id} ne  "Not Activated" )){
                    push @result, [$lpar, "For the I/O $location, the current owning lpar(id=$orig_id) of the I/O  and the new owning lpar(id=$id) must be in Not Activated state at first. And then run chvm again", -1];
                    return ( \@result ); 
                }                   
     
                xCAT::MsgUtils->verbose_message($request, "$request->{command} :set_io_slot_owner io_slot_info:$f,owner:$lpar."); 
                my $values =  xCAT::FSPUtils::fsp_api_action ($request, $lpar, $d, $action, $tooltype, $drc_index);
                #my $Rc = shift(@$values);
                my $Rc = pop(@$values);
                if ( $Rc != 0 ) {
                    push @result, [$lpar, $$values[1],$Rc];
                    next;
                } 
            }
                  
        }
    }
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END."); 
    return( \@result );
}


sub enumerate {

    my $request  = shift;
    my $h    = shift;
    my $mtms    = shift;
    my %outhash = ();
    my $cec;
    my $type;
    my @td;

    xCAT::MsgUtils->verbose_message($request, "lsvm :enumerate START for mtms:$mtms.");
    while (my ($name,$d) = each(%$h) ) {
        $cec = @$d[3];
        $type = @$d[4];
        @td = @$d;
    }
   
    $td[4]="cec"; 
    xCAT::MsgUtils->verbose_message($request, "lsvm :enumerate get_io_slot_info for node:$cec.");
    my $action = "get_io_slot_info";
    my $values =  xCAT::FSPUtils::fsp_api_action ($request, $cec, \@td, $action);
    #my $Rc = shift(@$values);
    my $Rc = $$values[2];
    if ( $Rc != 0 ) {
        $outhash{ 1 } = "The LPARs' I/O slots information could NOT be listed  because the cec is in power off state";
    } else {
        $outhash{ 0 } = $$values[1];
    } 
    #my @t; 
    #foreach my $value ( @$values ) {
    #    my ($lparid, $busid, $slot_location_code, $drc_index,@t ) = split (/,/, $value);
    #    push (@{$outhash{$lparid}}, $value);
    #}
 
    if( $type =~ /^(fsp|cec)$/ )  {
        xCAT::MsgUtils->verbose_message($request, "lsvm :enumerate query_octant_cfg for node:$cec.");
	$action = "query_octant_cfg";
	my $values =  xCAT::FSPUtils::fsp_api_action ($request, $cec, \@td, $action);
	my $Rc = pop(@$values);
	if ( $Rc != 0 ) {
	    return( [$Rc,$$values[1]] );
        }	    
        #$outhash{ $cec } = @$values[0];
        my $data = $$values[1];	
	my @value =  split(/:/, $data);
	my $pendingpumpmode = $value[0];
	my $currentpumpMode = $value[1];
	my $octantcount     = $value[2];
        my $j = 3;
	my $res = "PendingPumpMode=$pendingpumpmode,CurrentPumpMode=$currentpumpMode,OctantCount=$octantcount:\n";
	for(my $i=0; $i < $octantcount; $i++) {
	    $res = $res."OctantID=".$value[$j++].",PendingOctCfg=".$value[$j++].",CurrentOctCfg=".$value[$j++].",PendingMemoryInterleaveMode=".$value[$j++].",CurrentMemoryInterleaveMode=".$value[$j++].";\n";
	}
        $outhash{ $cec } = $res;	
    } 
    
    xCAT::MsgUtils->verbose_message($request, "lsvm :enumerate END for mtms:$mtms.");
    return( [0,\%outhash] );
}

sub get_cec_attr_info {
	my $request = shift;
	my $name = shift;
	my $attr = shift;
	my $op = shift;
	my %op_hash = (
		lpar_info => "get_lpar_info",
		bsr => "get_cec_bsr",
		huge_page => "get_huge_page"	
	);
	my $action = $op_hash{$op};
	my $values = xCAT::FSPUtils::fsp_api_action($request, $name, $attr, $action);
    if (@$values[1] && ((@$values[1] =~ /Error/i) && @$values[2] ne '0')) {
        return ([[$name, @$values[1], '1']]);
    }
    return @$values[1];
}

sub get_cec_lpar_hugepage {
	my $name = shift;
	my $huge_info = shift;
	my $lparid = shift;
	my $lparname = shift;
	my @value = split(/\n/, $huge_info);
    foreach my $v (@value) {
        if($v =~ /\s*([^\s]+)\s*:\s*([\d|\/]+)/) {
	    my $tmp_name = $1;
	    my $tmp_num = $2;
            if($tmp_name =~ /^$lparname$/) {
                return $tmp_num;
            }
        }
    }
    return ([[$name, "can not get huge page info for lpar id $lparid", '1']]);

}

sub get_cec_lpar_name {
    my $name = shift;
    my $lpar_info = shift;
    my $lparid = shift;
    my @value = split(/\n/, $lpar_info);
    foreach my $v (@value) {
        if($v =~ /lparname:\s*([^\,]*),\s*lparid:\s*([\d]+),/) {
            if($2 == $lparid) {
                return $1;
            }
        }
    }
    return ([[$name, "can not get lparname for lpar id $lparid", '1']]);
}
sub get_cec_lpar_bsr {
    my $name = shift;
    my $lpar_info = shift;
    my $lparid = shift;
    my $lparname = shift;
    my @value = split(/\n/, $lpar_info);
    foreach my $v (@value) {
        if($v =~ /\s*([^\s]+)\s*:\s*([\d]+)/) {
	    my $tmp_name = $1;
	    my $tmp_num = $2;
            if($tmp_name =~ /^$lparname$/) {
                return $tmp_num;
            }
        }
    }
    return ([[$name, "can not get BSR info for lpar id $lparid", '1']]);
}
sub get_cec_cec_bsr {
    my $name = shift;
    my $lpar_info = shift;
    my $index = 0;
    my @value = split(/\n/, $lpar_info);
    my $cec_bsr = "";
    foreach my $v (@value) {
	    if ($v =~ /(Number of BSR arrays:)\s*(\d+)/i) {
	        $cec_bsr .= "$1 $2,";
	        $index++; 
	    } elsif ($v =~ /(Bytes per BSR array:)\s*(\d+)/i) {
	        $cec_bsr .= "$1 $2,";
	        $index++;
	    } elsif ($v =~ /(Available BSR array:)\s*(\d+)/i) {
	        $cec_bsr .= "$1 $2;\n";
	        $index++;
	    }
    }
    if ($index != 3) {
	    return undef;
    } else {
	    return $cec_bsr;
    }
}
sub get_cec_cec_hugepage {
	my $name = shift;
	my $huge_info = shift;
	my $index = 0;
	my @value = split (/\n/, $huge_info);
	my $cec_hugepage = "";
	foreach my $v (@value) {
		if ($v =~ /(Available huge page memory\(in pages\):)\s*(\d+)/i) {
			my $tmp = sprintf "%-40s %s;\n", $1, $2;
			$cec_hugepage .= $tmp;
			$index++; 
		} elsif($v =~ /(Configurable huge page memory\(in pages\):)\s*(\d+)/i){
			my $tmp = sprintf "%-40s %s;\n", $1, $2;
			$cec_hugepage .= $tmp;
			$index++;
		} elsif($v =~ /(Page Size\(in GB\):)\s*(\d+)/i) {
			my $tmp = sprintf "%-40s %s;\n", $1, $2;
			$cec_hugepage .= $tmp;
			$index++;
		} elsif($v =~ /(Maximum huge page memory\(in pages\):)\s*(\d+)/i) {
			my $tmp = sprintf "%-40s %s;\n", $1, $2;
			$cec_hugepage .= $tmp;
			$index++;
		} elsif($v =~ /(Requested huge page memory\(in pages\):)\s*(\d+)/i) {
			my $tmp = sprintf "%-40s %s;\n", $1, $2;
			$cec_hugepage .= $tmp;
			$index++;
		}
	}
	if ($index != 5) {
		return undef;
	}
	return $cec_hugepage;
}

##########################################################################
# Lists logical partitions
##########################################################################
sub list {
    my $request = shift;
    my $hash    = shift;
    my $args    = $request->{opt};
    my $values  = ();
    my @value   = ();
    my $node_name; 
    my $d;
    my @result;
    my $lpar_infos;
    my $bsr_infos;
    my $huge_infos;
    my %lpar_huges = ();
    my $l_string = "\n";
    #print Dumper($hash);    
    xCAT::MsgUtils->verbose_message($request, "lsvm START");
    while (my ($mtms,$h) = each(%$hash) ) {
	    my $info = enumerate($request, $h, $mtms );
    	my $Rc = shift(@$info);
	    my $data = @$info[0];
         	
        while (($node_name,$d) = each(%$h) ) {
            my $cec   = @$d[3];
            my $type   = @$d[4];
            
            my $id = @$d[0];
            
	        if ( $Rc != SUCCESS ) {
	            push @result, [$node_name, $data,$Rc]; 
		        next;
	        }
            my $values = $data->{0};
            my $msg = $data->{1};
	   
	   # if ( !exists( $data->{$id} )) {
           #     push @result, [$node_name, "Node not found",1];
           # 	next;
           # }
            xCAT::MsgUtils->verbose_message($request, "lsvm :parse io info for node:$node_name.");           
            if( defined($msg)) { 
                 push @result,[$node_name, $msg, 0];
            } else {
                # get the I/O slot information  
                if($request->{opt}->{l}) {
					if ($type =~ /^(fsp|cec)$/) {
						$bsr_infos = get_cec_attr_info($request, $node_name, $d, "bsr"); 
		            	if (ref($bsr_infos) eq 'ARRAY') {
			            	return $bsr_infos;
		            	}
                        $huge_infos = get_cec_attr_info($request,$node_name, $d, "huge_page");
                        if (ref($huge_infos) eq 'ARRAY') {
                            return $huge_infos;
                        }
                    }
                    $lpar_infos = get_cec_attr_info($request, $node_name, $d, "lpar_info");
                    if (ref($lpar_infos) eq 'ARRAY') {
                        return $lpar_infos;
                    }
		        }
                my $v;
                my @t; 
                my @value = split(/\n/, $values);
                foreach my $v (@value) {
                    my ($lparid, @t ) = split (/,/, $v);  
		            my $ios = join('/', @t);
                    if ($request->{opt}->{l}) {
                        my $lparname = get_cec_lpar_name($node_name, $lpar_infos, $lparid);
                        my $hugepage;
                        if ($type =~ /^(fsp|cec)$/) {
   			                my $lpar_bsr = get_cec_lpar_bsr($node_name, $bsr_infos, $lparid, $lparname);
			                if (ref($lpar_bsr) eq 'ARRAY') {
			                    return $lpar_bsr;
			                }
			                $ios .= ": ".$lpar_bsr;
                            $hugepage = get_cec_lpar_hugepage($node_name, $huge_infos, $lparid, $lparname);
                            if (ref($hugepage) eq 'ARRAY') {
                                return $hugepage;
                            }
                        } else {
							if ($lparid ne $id) {
								next;
                            } 
                            if (defined($lpar_huges{$lparid})) {
                                $hugepage = $lpar_huges{$lparid};
                            } else {
                                $hugepage = get_cec_attr_info($request, $node_name, $d, "huge_page");
                                if (ref($hugepage) eq 'ARRAY') {
                                    return $hugepage;
                                }
                                $lpar_huges{$lparid} = $hugepage;
                            }
						}
                        $ios .= ": ".$hugepage;
                        if (ref($lparname) eq 'ARRAY') {
                            return $lparname;
                        } else {
                            $lparname = "$lparname: $lparid";
                        }
			            $l_string .= "$lparname: ".$ios."\n";
                    } else {
			            if ($type=~/^(fsp|cec)$/) {
                            push @result,[$lparid, $ios, $Rc];
                        } else {
                            if( $lparid eq $id) {
                                push @result,[$lparid, $ios, $Rc];
                            }
                        }
                    }
                } 
            }
            
            # get the octant configuration value    
            if ($type=~/^(fsp|cec)$/) {
                xCAT::MsgUtils->verbose_message($request, "lsvm :parse octant info for $type:$node_name.");           
                my $value = $data->{$cec};
		        if ($request->{opt}->{l}) {
		            my $cec_bsr = get_cec_cec_bsr($node_name, $bsr_infos);
		 	        my $cec_hugepage = get_cec_cec_hugepage($node_name, $huge_infos);
		            $l_string .= $value.$cec_bsr;
			        $l_string .= $cec_hugepage;
		        } else {
                    $l_string = $value;
	 	        }
            } 
            if ($l_string =~ /^\n$/) {
                next;
            }
		    push @result, [$node_name, $l_string, $Rc];
		    $l_string = "\n";
	    } # end of while
    }# end of while
    xCAT::MsgUtils->verbose_message($request, "lsvm END.");
    return( \@result );
}



##########################################################################
# Lists logical partitions
##########################################################################
sub list_orig {

    my $request = shift;
    my $hash    = shift;
    my $args    = $request->{opt};
    my $values  = ();
    my @value   = ();
    my $node_name; 
    my $d;
    my @result;

    while (my ($mtms,$h) = each(%$hash) ) {
        while (($node_name,$d) = each(%$h) ) {
            my $lparid = @$d[0];
            my $mtms   = @$d[2];
            my $type   = @$d[4];
            my $pprofile;

            ####################################
            # Must be CEC or LPAR
            ####################################
            if ( $type !~ /^(lpar|fsp|cec)$/ ) {
		#$values->{$lpar} = [$lpar,"Node must be LPAR or CEC",RC_ERROR];
                return ( [$node_name,"Node must be LPAR or CEC",RC_ERROR]);
		#next;
            }
            
            ####################################
            # This is a single LPAR
            ####################################
            if ( $type eq "lpar" ) {
		#$lpars[0] = "$lpar,$lparid";

            }
            ####################################
            # This is a CEC
            ####################################
            else {
		my $values = xCAT::FSPUtils::fsp_api_action($request, $node_name, $d, "query_octant_cfg");
                my $Rc = @$values[2];
		my $data = @$values[1];
		if ( $Rc != SUCCESS ) {
                    push @result, [$node_name,$data,$Rc];
		} else {
		    my @value =  split(/,/, $data);
		    my $pendingpumpmode = $value[0];
		    my $currentpumpMode = $value[1];
		    my $octantcount     = $value[2];
                    my $j = 3;
		    my $res = "PendingPumpMode=$pendingpumpmode,CurrentPumpMode=$currentpumpMode,OctantCount=$octantcount:";
		    for(my $i=0; $i < $octantcount; $i++) {
		       $res = $res."OctantID=".$value[$j++].",PendingOctCfg=".$value[$j++].",CurrentOctCfg=".$value[$j++].",PendingMemoryInterleaveMode=".$value[$j++].",CurrentMemoryInterleaveMode".$value[$j++].";";
		    }
		    push @result,[$node_name, $res, $Rc];
		}
            }
	}
    }
    return( \@result );
}



##########################################################################
# Creates/changes logical partitions 
##########################################################################
sub create {

    my $request = shift;
    my $hash    = shift;
    my $opt     = $request->{opt};
    my @values  = ();
    my @result;
    my $cec_name;
    my $d;
    my $lparid;
    my $mtms;
    my $type;
    my $profile;
    my $starting_lpar_id = $opt->{i};
    my $octant_cfg = $opt->{octant_cfg};
    my $node_number       =@{$opt->{target}}; 
    my %node_id = (); 
    my @nodes = @{$opt->{target}};	
   
    xCAT::MsgUtils->verbose_message($request, "$request->{command} START."); 
    #print Dumper($request); 
    #####################################
    # Get source node information
    #####################################
    while ( my ($cec,$h) = each(%$hash) ) {
        while ( my ($name,$data) = each(%$h) ) {
            $d      = $data;
            $lparid = @$d[0];
            $mtms   = @$d[2];
            $type   = @$d[4];
            $cec_name = $name;
            #####################################
            # Must be LPAR 
            #####################################
            if ( $type !~ /^(fsp|cec)$/ ) {
                 return( [[$cec_name,"Node's parent must be fsp or CEC",RC_ERROR]] );
            }
        }
        
        xCAT::MsgUtils->verbose_message($request, "$request->{command} :query_octant_cfg for CEC:$cec_name."); 
        my $values =  xCAT::FSPUtils::fsp_api_action ($request, $cec_name, $d, "query_octant_cfg");   
        my $Rc = shift(@$values);
        if ( $Rc != 0 ) {
            return( [[$cec_name,$$values[0],$Rc]] );
        } 
        my @v = split(/:/, $$values[0]);
        $octant_cfg->{pendingpumpmode} = $v[0];        

    
	my $number_of_lpars_per_octant;
        my $octant_num_needed;
        my $starting_octant_id;
        my $octant_conf_value;
        my $octant_cfg_value = $octant_cfg->{octant_cfg_value};
        my $new_pending_interleave_mode = $octant_cfg->{memory_interleave};
 

        $starting_octant_id = int($starting_lpar_id/4);
        my $lparnum_from_octant = 0;
        my $new_pending_pump_mode = $octant_cfg->{pendingpumpmode};
        my $parameters;
        #my $parameters = "$new_pending_pump_mode:$octant_num_needed";
        my $octant_id = $starting_octant_id ;
        my $i = 0;
        my $res;
        for($i=0; $i < (keys %$octant_cfg_value) ; $i++) {
	    if(! exists($octant_cfg_value->{$octant_id})) {
	        $res = "starting LPAR id is $starting_lpar_id, starting octant id is $starting_octant_id. The octants should be used continuously. Octant $octant_id  configuration value isn't provided. Wrong plan.";
	        return ([[$cec_name, $res, -1]]);

            }
	    my $octant_conf_value = $octant_cfg_value->{$octant_id};
            #octant configuration values could be 1,2,3,4,5 ; AS following:
            #  1 - 1 partition with all cpus and memory of the octant
            #  2 - 2 partitions with a 50/50 split of cpus and memory
            #  3 - 3 partitions with a 25/25/50 split of cpus and memory
            #  4 - 4 partitions with a 25/25/25/25 split of cpus and memory
            #  5 - 2 partitions with a 25/75 split of cpus and memory
            if($octant_conf_value  ==  1)  {
	        $number_of_lpars_per_octant  = 1;
            } elsif($octant_conf_value  ==  2 ) {
                $number_of_lpars_per_octant  = 2;
            } elsif($octant_conf_value  ==  3 ) {
                $number_of_lpars_per_octant  = 3;
            } elsif($octant_conf_value  ==  4 ) {
                $number_of_lpars_per_octant  = 4;
            } elsif($octant_conf_value  ==  5 ) {
                $number_of_lpars_per_octant  = 2;
            } else {
                $res = "octant $i, configuration values: $octant_conf_value. Wrong octant configuration values!\n";
	        return ([[$cec_name, $res, -1]]);
            }	   
            my $j;
            for($j = 1; $j < $number_of_lpars_per_octant+1 ; $j++) {
                if(@nodes) {
                    my $node = shift(@nodes);
                    $node_id{$node} = $j + $octant_id * 4;
                }
            }

           $lparnum_from_octant += $number_of_lpars_per_octant;
           $octant_num_needed++; 
           $parameters .= ":$octant_id:$octant_conf_value:$new_pending_interleave_mode";
           $octant_id++; 
        
        }  
        $parameters = "$new_pending_pump_mode:$octant_num_needed".$parameters;
        ##if($node_number != $lparnum_from_octant ) {##
        if($node_number > $lparnum_from_octant ) {
            $res =  "According to the partition split rule and the starting LPAR id, $lparnum_from_octant LPARs will be gotten. But the noderange has $node_number node.  Wrong plan.\n";
            return ([[$cec_name, $res, -1]]);  
        }
   


	
        xCAT::MsgUtils->verbose_message($request, "$request->{command} :set_octant_cfg for CEC:$cec_name,param:$parameters."); 
	#$values = xCAT::FSPUtils::fsp_api_create_parttion( $starting_lpar_id, $octant_cfg, $node_number, $d, "set_octant_cfg");
        $values =  xCAT::FSPUtils::fsp_api_action ($request,$cec_name, $d, "set_octant_cfg", 0, $parameters);   
        my $Rc = $$values[2];
     	my $data = $$values[1];
	if ( $Rc != SUCCESS ) {
	    push @result, [$cec_name,$data,$Rc];
        } else {
            foreach my $name ( @{$opt->{target}} ) {
	        push @result, [$name,"Success", $Rc];   
                xCAT::FSPvm::xCATdB("mkvm", $name, "",$node_id{$name}, $d, "fsp", $name ); 
            }
            push @result, [$cec_name,"Please reboot the CEC $cec_name before using chvm to assign the I/O slots to the LPARs", "mkvm"];   
            #$request->{callback}->({info => ["Please reboot the CEC $cec_name before using chvm to assign the I/O slots to the LPARs"]}); 
	}
        	
    }
    
    xCAT::MsgUtils->verbose_message($request, "$request->{command} END."); 
    return( \@result );
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
        return( xCAT::PPCdb::rm_ppc( $name )); 
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
        
        return( xCAT::PPCdb::add_ppc( $hwtype, [$values] )); 
    }
    return undef;
}
########################
#***** partition related
########################

#my @partition_query_actions = qw(part_get_partition_cap part_get_num_of_lpar_slots part_get_hyp_config_process_and_mem part_get_hyp_avail_process_and_mem part_get_service_authority_lpar_id part_get_shared_processing_resource part_get_all_vio_info lpar_lhea_mac part_get_all_io_bus_info part_get_lpar_processing part_get_lpar_memory get_huge_page get_cec_bsr);
my @partition_query_actions = qw(part_get_partition_cap part_get_hyp_process_and_mem part_get_all_io_bus_info get_huge_page get_cec_bsr);

sub parse_part_get_info {
    my $hash = shift;
    my $data = shift;
    my @array = split /\n/, $data;
    foreach my $line (@array) {
        chomp($line);
        if ($line =~ /Num of lpar slots: (\d+)/i) {
            $hash->{num_of_lpars} = $1;
        } elsif ($line =~ /HYP Configurable Memory[^\(]*\((\d+)\s*regions\)/i) {
            $hash->{hyp_config_mem} = $1;
        } elsif ($line =~ /HYP Available Memory[^\(]*\((\d+)\s*regions\)/i) {
            $hash->{hyp_avail_mem} = $1;
        } elsif ($line =~ /HYP Memory Region Size[^\(]*\((\d+)\s*MB\)/i) {
            $hash->{mem_region_size} = $1;
        } elsif ($line =~ /HYP Configurable Processors: (\d+),\s*Avail Processors: (\d+)/i) {
            $hash->{process_units_config} = $1;
            $hash->{process_units_avail} = $2;
        } elsif ($line =~ /Authority Lpar id:(\w+)/i) {
            $hash->{service_lparid} = $1;
        } elsif ($line =~ /(\d+),(\d+),[^,]*,(\w+),\w*\(([\w| |-|_]*)\)/) {
            $hash->{bus}->{$3}->{cur_lparid} = $1;
            $hash->{bus}->{$3}->{bus_slot} = $2;
            $hash->{bus}->{$3}->{des} = $4;
        } elsif ($line =~ /Phy drc_index:(\w+), Port group: (\w+), Phy port id: (\w+)/) {
            $hash->{phy_drc_group_port}->{$1}->{$2}->{$3} = '1';
        } elsif ($line =~ /adapter_id=(\w+),lpar_id=([\d|-]+).*port_group=(\d+),phys_port_id=(\d+).*drc_index=(\w+),.*/) {
            if (($2 == -1) && ($4 == 255)) {
                $hash->{logic_drc_phydrc}->{$3}->{$5} = $1;
                #$hash->{logic_drc_phydrc}->{$5}->{$1} = [$2,$3,$4];
            }
        #} elsif ($line =~ /lpar 0:: Curr  Memory::min: 1,cur: (\d+),max:/i) {
        } elsif ($line =~ /HYP Reserved Memory Regions:([-]?)(\d+), Min Required Regions:(\d+)/i) {
            if ($1 eq '-') {
                $hash->{lpar0_used_dec} = 1;
            }
            $hash->{lpar0_used_mem} = $2;
            $hash->{phy_min_mem_req} = $3;
            #print "===>lpar0_used_mem:$hash->{lpar0_used_mem}.\n";
        } elsif ($line =~ /Curr Memory Req:[^\(]*\((\d+)\s*regions\)/) {
            $hash->{lpar_used_regions} = $1;
        } elsif ($line =~ /Available huge page memory\(in pages\):\s*(\d+)/) {
            $hash->{huge_page_avail} = $1;
        } elsif ($line =~ /Available BSR array:\s*(\d+)/) {
            $hash->{cec_bsr_avail} = $1;
        }
    }
}

sub query_cec_info_actions {
    my $request = shift;
    my $name = shift;
    my $td = shift;
    my $usage = shift;
    my $action_array = shift;
    my $lparid = @$td[0];
    my $data;
    my @array = ();
    my %hash = ();
    if (!defined($action_array) or ref($action_array) ne "ARRAY") {
        $action_array = \@partition_query_actions;
    }

    foreach my $action (@$action_array) {
	#$data .= "======> ret info for $action:\n";
        my $values = xCAT::FSPUtils::fsp_api_action($request, $name, $td, $action);
        chomp(@$values[1]);
        #if ($action eq "part_get_partition_cap" and (@$values[1] =~ /Error:/i or @$values[2] ne 0)) {
        if (@$values[1] =~ /Error:/i or @$values[2] ne 0) {
            return ([[@$values]]);
        }
        if (@$values[1] =~ /^$/) {
            next;
        }
        if ($usage eq 0) {
            if ($lparid) {
                if ($action eq "lpar_lhea_mac") {
                    my @output = split /\n/,@$values[1];
                    foreach my $line (@output) {
                        if ($line =~ /adapter_id=\w+,lpar_id=$lparid,type=hea/) {
                            #$data .= "$line\n";
                            push @array, [$name, $line, 0];
                        }
                    }
                    #$data .= "\n";
                    next;
                }
                if ($action eq "part_get_all_io_bus_info") {
                    my @output = split /\n/, @$values[1];
                    foreach my $line (@output) {
                        if ($line =~ /^$lparid,/) {
                            #$data .= "$line\n";
                            push @array, [$name, $line, 0];
                        }
                    }
                    #$data .= "\n";
                    next;
                } 
            }
	    #$data .= "@$values[1]\n\n";
            push @array, [$name, @$values[1], @$values[2]];
        } else {
            &parse_part_get_info(\%hash, @$values[1]);
        }
    }
    if ($usage eq 0) {
        #return $data;
        return \@array;
    } else {
        return \%hash; 
    }
}

#my @partition_query_actions = qw(part_get_partition_cap part_get_num_of_lpar_slots part_get_hyp_config_process_and_mem part_get_hyp_avail_process_and_mem part_get_service_authority_lpar_id part_get_shared_processing_resource part_get_all_vio_info lpar_lhea_mac part_get_all_io_bus_info part_get_lpar_processing part_get_lpar_memory get_huge_page get_cec_bsr);
sub query_cec_info {
    my $request = shift;
    my $hash    = shift;
    my $args    = $request->{opt};
    my @td = ();
    my @result = ();
    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name, $d) = each (%$h)) {
            @td = @$d;
            if (@$d[0] == 0 && @$d[4] ne "lpar") {
                last;
            }
            #my $rethash = query_cec_info_actions($request, $name, $d, 0, ["part_get_lpar_processing","part_get_lpar_memory","part_get_all_vio_info","lpar_lhea_mac","part_get_all_io_bus_info","get_huge_page","get_cec_bsr"]);
            my $rethash = query_cec_info_actions($request, $name, $d, 0, ["part_get_lpar_processing","part_get_lpar_memory","part_get_all_io_bus_info","get_huge_page","get_cec_bsr"]);
	        #push @result, [$name, $rethash, 0];
	        push @result, @$rethash;
        }
        if (@td[0] == 0) {
            my $rethash = query_cec_info_actions($request, @td[3],\@td, 0);
            #push @result, [@td[3], $rethash, 0];
            push @result, @$rethash;
        }  
    }
    return \@result;
}

########################
#***** partition related
########################

my @partition_config_actions = qw/part_set_lpar_def_state part_set_lpar_pending_proc part_set_lpar_pending_mem part_set_pending_max_vslots part_set_lpar_shared_pool_util_auth part_set_lpar_group_id part_set_lpar_avail_priority part_set_partition_placement part_set_lhea_assign_info part_set_phea_port_info part_set_lhea_port_info part_set_veth_slot_config part_set_vscsi_slot_config part_set_vfchan_slot_config part_clear_vslot_config set_huge_page set_lpar_name/;

sub set_lpar_undefined {
    my $request = shift;
    my $name = shift;
    my $attr = shift;
    my $values = xCAT::FSPUtils::fsp_api_action($request, $name, $attr, "part_set_lpar_def_state", 0, 0x0); 
    if (!@$values[2]) {
        return ([$name,"Done",0]);
    }
    return $values;
}

sub clear_service_authority_lpar {
    my $request = shift;
    my $name = shift;
    my $attr = shift;
    my $values = xCAT::FSPUtils::fsp_api_action($request, $name, $attr, "part_get_service_authority_lpar_id");
    my @array = split /\n/, @$values[1]; 
    my $service_lparid = undef;
    foreach my $line (@array) {
        if ($line =~ /Authority Lpar id:([-|\d]+)./i) {
            $service_lparid = $1;
        }
    }
    if (defined($service_lparid) and $service_lparid == @$attr[0]) {
        xCAT::FSPUtils::fsp_api_action($request, $name, $attr, "part_set_service_authority_lpar_id");
    }
}

sub remove {
    my $request = shift;
    my $hash = shift;
    my @result = ();
    while (my ($mtms, $h) = each (%$hash)) {
        while (my ($name, $d) = each (%$h)) {
             if (@$d[4] ne "lpar") {
                 push @result, [$name, "Node must be LPAR", 1];
                 last;
             } 
             &clear_service_authority_lpar($request, $name, $d);
             my $values = &set_lpar_undefined($request, $name, $d);
             push @result, $values;
        }
    }
    return \@result;
}

sub deal_with_avail_mem {
    my $request = shift;
    my $name = shift;
    my $d = shift;
    my $lparhash = shift;
    my $max_required_regions;
    if ($lparhash->{memory} =~ /(\d+)\/(\d+)\/(\d+)/) {
        my ($min,$cur,$max);
        my $used_regions = 0;
        my $cur_avail = 0;
        $min = $1;
        $cur = $2;
        $max = $3;
        my %tmphash;
        my $values;
        if (exists($lparhash->{lpar_used_regions})) {
            $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_get_lpar_memory");
            &parse_part_get_info(\%tmphash, @$values[1]);
            if (exists($tmphash{lpar_used_regions})) {
                $used_regions = $tmphash{lpar_used_regions};
            }
        }
        $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_get_hyp_res_mem_regions", 0, $3);
        &parse_part_get_info(\%tmphash, @$values[1]);
        if (exists($tmphash{lpar0_used_mem}) && exists($tmphash{phy_min_mem_req})) {
            if ($min < $tmphash{phy_min_mem_req}) {
                $min = $tmphash{phy_min_mem_req};
            }
 
            if (exists($lparhash->{lpar0_used_dec})) {
                $cur_avail = $lparhash->{hyp_avail_mem} + $used_regions + $tmphash{lpar0_used_mem}; 
            } else {
                $cur_avail = $lparhash->{hyp_avail_mem} + $used_regions - $tmphash{lpar0_used_mem};
            }
            xCAT::MsgUtils->verbose_message($request, "====****====used:$used_regions,avail:$cur_avail,($min:$cur:$max)."); 
            if ($cur_avail < $min) {
                return([$name, "Parse reserverd regions failed, no enough memory, available:$lparhash->{hyp_avail_mem}.", 1]);
            }           
            if ($cur > $cur_avail) {
                my $new_cur = $cur_avail;
                $lparhash->{memory} = "$min/$new_cur/$max";
            }
        } else {
            return ([$name, "Failed to get hypervisor reserved memory regions.", 1]);
        }
    }
    return 0;
}

sub create_lpar {
    my $request = shift;
    my $name = shift;
    my $d = shift;
    my $lparhash = shift;
    my $values;
    if (exists($request->{opt}->{vios})) {
        $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_def_state", 0, 0x03);
    } else {
        $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_def_state", 0, 0x01);
    }
    if (@$values[2] ne 0) {
        return ([[$name, @$values[1], @$values[0]]]);
    }
    $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "set_lpar_name", 0, $name);
    if (@$values[2] ne 0) {
        &set_lpar_undefined($request, $name, $d);
        return ([$name, @$values[1], @$values[0]]);
    }
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_shared_pool_util_auth");
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_group_id");
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_avail_priority");
    #print "======>physlots:$lparhash->{physlots}.\n";
    $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "set_io_slot_owner_uber", 0, $lparhash->{physlots}); 
    #$values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "set_io_slot_owner", 0, join(",",@phy_io_array)); 
    if (@$values[2] ne 0) {
        &set_lpar_undefined($request, $name, $d);
        return ([$name, @$values[1], @$values[2]]);
    }
    if (exists($lparhash->{phy_hea})) {
        my $phy_hash = $lparhash->{phy_hea};
        foreach my $phy_drc (keys %$phy_hash) {
            #print "======> set_lhea_assign_info: drc_index:$phy_drc.\n";
            xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lhea_assign_info", 0, $phy_drc);
            my $group_hash = $phy_hash->{$phy_drc};
            foreach my $group_id (keys %$group_hash) {
                my @lhea_drc = (keys %{$lparhash->{logic_drc_phydrc}->{$group_id}}); 
                foreach my $phy_port_id (keys %{$group_hash->{$group_id}}) {
                    my $tmp_param = "$phy_drc,$group_id,$phy_port_id";
                    #print "======> set_phea_port_info: $tmp_param.\n";
                    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_phea_port_info", 0, $tmp_param);
                    my $tmp_lhea_param = $lhea_drc[$phy_port_id].",$phy_port_id";
                    #print "======> set_lhea_port_info: $tmp_lhea_param.\n";
                    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lhea_port_info", 0, $tmp_lhea_param);
                }
                delete ($lparhash->{logic_drc_phydrc}->{$group_id}->{$lhea_drc[0]});
                delete ($lparhash->{logic_drc_phydrc}->{$group_id}->{$lhea_drc[1]});
            } 
        }
    }

    #print "======>cpus:$lparhash->{cpus}.\n";
    $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_pending_proc", 0, $lparhash->{cpus});
    if (@$values[2] ne 0) {
        &set_lpar_undefined($request, $name, $d);
        return ([$name, @$values[1], @$values[2]]);
    }
    $values = &deal_with_avail_mem($request, $name, $d,$lparhash);
    if (ref($values) eq "ARRAY") {
        &set_lpar_undefined($request, $name, $d);
        return ([@$values]);
    }

    #print "======>memory:$lparhash->{memory}.\n";
    $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_pending_mem", 0, $lparhash->{memory});
    if (@$values[2] ne 0) {
        &set_lpar_undefined($request, $name, $d);
        return ([$name, @$values[1], @$values[2]]);
    }
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_comp_modes"); 
    #print "======>memory:$lparhash->{huge_page}.\n";
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "set_huge_page", 0, $lparhash->{huge_page});
    #print "======>bsr:$lparhash->{bsr_num}.\n";
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "set_lpar_bsr", 0, $lparhash->{bsr_num});
    xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_partition_placement");
    if (exists($request->{opt}->{vios})) { 
        $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_def_state", 0, 0x04);
    } else {
        $values = xCAT::FSPUtils::fsp_api_action($request, $name, $d, "part_set_lpar_def_state", 0, 0x02);
    }
    if (@$values[2] ne 0) {
        return ([$name, @$values[1], @$values[2]]);
    }
    return ([$name, "Done", 0]);
}

sub mkspeclpar {
    my $request = shift;
    my $hash = shift;
    my $opt = $request->{opt};
    my $values;
    my @result = ();
    my $vmtab = xCAT::Table->new( 'vm');
    unless($vmtab) {
        return([["Error","Cannot open vm table", 1]]);
    }
    while (my ($mtms, $h) = each (%$hash)) {
        my $memhash;
        my @nodes = keys(%$h);
        my $ent = $vmtab->getNodesAttribs(\@nodes, ['cpus', 'memory','physlots', 'othersettings']); 
        while (my ($name, $d) = each (%$h)) {
            if (@$d[4] ne 'lpar') {
                push @result, [$name, "Node must be LPAR", 1];
                last;
            }
            if (!exists($memhash->{run})) {
                my @td = @$d;
                @td[0] = 0;
                $memhash = &query_cec_info_actions($request, $name, \@td, 1, ["part_get_hyp_process_and_mem","lpar_lhea_mac"]);
                $memhash->{run} = 1; 
            }
            my $tmp_ent = $ent->{$name}->[0];
            if (exists($opt->{vmcpus})) {
                $tmp_ent->{cpus} = $opt->{vmcpus};
            } 
            if (exists($opt->{vmmemory})) {
                $tmp_ent->{memory} = $opt->{vmmemory};
            }
            if (exists($opt->{vmphyslots})) {
                $tmp_ent->{physlots} = $opt->{vmphyslots};
            }
            if (exists($opt->{vmothersetting})) {
                $tmp_ent->{othersettings} = $opt->{vmothersetting};
            }
            if (!defined($tmp_ent) ) {
                return ([[$name, "Not find params", 1]]);
            } elsif (!exists($tmp_ent->{cpus}) || !exists($tmp_ent->{memory}) || !exists($tmp_ent->{physlots})) {
                return ([[$name, "The attribute 'vmcpus', 'vmmemory' and 'vmphyslots' are all needed to be specified.", 1]]);
            }
            if ($tmp_ent->{memory} =~ /(\d+)([G|M]?)\/(\d+)([G|M]?)\/(\d+)([G|M]?)/i) {
                my $memsize = $memhash->{mem_region_size};
                my $min = $1;
                if ($2 == "G" or $2 == '') {
                    $min = $min * 1024;
                }
                $min = $min/$memsize;
                my $cur = $3;
                if ($4 == "G" or $4 == '') {
                    $cur = $cur * 1024;
                }
                $cur = $cur/$memsize;
                my $max = $5;
                if ($6 == "G" or $6 == '') {
                    $max = $max * 1024;
                }
                $max = $max/$memsize;
                $tmp_ent->{memory} = "$min/$cur/$max";
            }
            $tmp_ent->{hyp_config_mem} = $memhash->{hyp_config_mem};
            $tmp_ent->{hyp_avail_mem} = $memhash->{hyp_avail_mem};
            $tmp_ent->{huge_page} = "0/0/0"; 
            $tmp_ent->{bsr_num} = "0";
            if (exists($tmp_ent->{othersettings}))  {
                my $setting = $tmp_ent->{othersettings};
                if ($setting =~ /hugepage:(\d+)/) {
                    my $tmp = $1;
                    $tmp_ent->{huge_page} = "1/".$tmp."/".$tmp;
                }
                if ($setting =~ /bsr:(\d+)/) {
                    $tmp_ent->{bsr_num} = $1;
                }
            }
            $tmp_ent->{phy_hea} = $memhash->{phy_drc_group_port};
            $tmp_ent->{logic_drc_phydrc} = $memhash->{logic_drc_phydrc};
            $values = &create_lpar($request, $name, $d, $tmp_ent); 
            push @result, $values;
            $name = undef;
            $d = undef;
        }
    }
    return \@result;    
}

sub mkfulllpar {
    my $request = shift;
    my $hash = shift;
    my $values;
    my @result = ();
    while (my ($mtms, $h) = each (%$hash)) {
        my $rethash;
        while (my ($name, $d) = each (%$h)) {
            if (@$d[4] ne 'lpar') {
                push @result, [$name, "Node must be LPAR", 1];
                last;
            }
            if (!exists($rethash->{run})) {
                my @td = @$d;
                @td[0] = 0;
                $rethash = query_cec_info_actions($request, $name, \@td, 1); 
                if (ref($rethash) ne 'HASH') {
                    return ([[$mtms, "Cann't get hypervisor info hash", 1]]);
                }
                $rethash->{run} = 1; 
                #print Dumper($rethash);
            }
            my %lpar_param = ();
            $lpar_param{cpus} = "1/".$rethash->{process_units_avail}."/".$rethash->{process_units_config}; 
            $lpar_param{memory} = "1/".$rethash->{hyp_avail_mem}."/".$rethash->{hyp_config_mem};
            $lpar_param{hyp_config_mem} = $rethash->{hyp_config_mem};
            $lpar_param{hyp_avail_mem} = $rethash->{hyp_avail_mem};
            my @phy_io_array = keys(%{$rethash->{bus}});
            $lpar_param{physlots} = join(",", @phy_io_array);
            $lpar_param{huge_page} = "1/".$rethash->{huge_page_avail}."/".$rethash->{huge_page_avail};
            $lpar_param{bsr_num} = $rethash->{cec_bsr_avail};
            $lpar_param{phy_hea} = $rethash->{phy_drc_group_port};
            $lpar_param{logic_drc_phydrc} = $rethash->{logic_drc_phydrc}; 
            $values = &create_lpar($request, $name, $d, \%lpar_param);
            $rethash->{logic_drc_phydrc} = $lpar_param{logic_drc_phydrc};
            push @result, $values;
            $name = undef;
            $d = undef;
        }    
    }
    return \@result;
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
    if (exists($opt->{p775})) {
        return (create(@_));
    }
    if (exists($opt->{full})) {
        return (mkfulllpar(@_));
    } else {
        return (mkspeclpar(@_));
    }
}

##########################################################################
# Change logical partition 
##########################################################################
sub chvm {
    return( modify(@_) );    
}


##########################################################################
# No rmvm for Power 775 
##########################################################################
sub rmvm  {
    my $request = $_[0];
    my $opt = $request->{opt};
    if (exists($opt->{p775})) {
        return ([["lpar","rmvm only support Power Partitioning.", 1]]); 
    } else {
        return( remove(@_) );
    }
#    return( remove(@_) );
}

##########################################################################
# Lists logical partition profile
##########################################################################
sub lsvm {
    my $request = shift;
    my $hash    = shift;
    my $args    = $request->{opt};
    if (exists($args->{p775})) {    
        return( list($request, $hash) );
    } else {
	return (query_cec_info($request, $hash));
    }
}

1;
