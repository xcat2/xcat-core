# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCrflash;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::PPCinv;
use xCAT::DSHCLI;
use xCAT::Table;
use Getopt::Long;
use File::Spec;
use POSIX qw(tmpnam);


my $packages_dir= ();
my $activate    = ();
my $verbose     = 0;
$::POWER_DEST_DIR               = "/tmp";
my $release_level;
my $active_level;
my @dirlist;

#######################################
# This flag tracks the operation to be performed.  If set, it means we need
# to commit a previously applied update or else recover from one.
#######################################
my $housekeeping = undef;

#####################################
#For -V|--verbose,put the $msg into @value
###################################
sub dpush {
    my $value = shift;
    my $msg = shift;

    if($verbose == 1) {
        push(@$value,$msg);
    }
}


##########################################################################
# Parse the command line for options and operands 
##########################################################################

sub parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};


    #############################################
    # Change CEC/Frame node into FSPs/BPAs
    #############################################     
    my @newnodes = ();
    my $nodes = $request->{node};
    foreach my $snode(@$nodes) {
        my $ntype = xCAT::DBobjUtils->getnodetype($snode);
        if ( $ntype =~ /^(cec|frame)$/) {
            my $children = xCAT::DBobjUtils->getchildren($snode);
            unless( $children )  {
                next;
            }
            foreach (@$children)  {
                push @newnodes, $_;
            }
        } else   {
            push @newnodes, $snode;
        }
    }
    $request->{node} = \@newnodes;
    
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
        return(usage( "No arguments specified" ));
    }

    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(h|help v|version V|verbose p=s activate=s commit recover) )) {
        return( usage() );
    }
    
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        return( \$::VERSION );
    }
    
    if ( exists( $opt{h}) || $opt{help}) {
        return( usage());
    }

    #################################
    #Option --activate not valid with --commit or --recover
    #################################
    if( exists( $opt{activate} ) && (exists( $opt{commit}) || exists( $opt{recover}))) {
        return( usage("Option --activate not valid with --commit or --recover ") );
    }    

    #################################
    #Option -p not valid with --commit or --recover
    #################################
    if( exists( $opt{p} ) && (exists( $opt{commit}) || exists( $opt{recover} ))) {
        return( usage("Option -p not valid with --commit or --recover ") );
    }
    

    #################################
    #Option -p required
    #################################
    if( exists( $opt{p} ) && (!exists( $opt{activate}) )) {
        return( usage("Option -p must be used with --activate ") );
    }    
    
    if ( exists( $opt{p} ) && ($opt{p} !~ /^\//) ) {#relative path
        $opt{p} = xCAT::Utils->full_path($opt{p}, $request->{cwd}->[0]);
    }
    ###############################
    #--activate's value only can be concurrent and disruptive
    ################################
    if(exists($opt{activate})) {
        if( ($opt{activate} ne "concurrent") && ($opt{activate} ne "disruptive")) {
            return (usage("--activate's value can only be concurrent or disruptive"));
        }
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
    
    
    #check to see if we are housekeeping or updating
    #
    if( defined( $opt{commit}) ) {
        print "commit flag\n";
        $housekeeping = "commit";
    } elsif( defined( $opt{ recover }) ) {
        print "recover flag\n";
        $housekeeping = "recover";
    } else {
        print "no housekeeping - update mode\n";
        $housekeeping = undef;
    }
    
    $request->{housekeeping} = $housekeeping;

    #############################################
    # Option -V for verbose output
    ############################################
    if ( exists( $opt{V} )) {
        $verbose = 1;
    }
 
    ####################
    #suport for "rflash", copy the rpm and xml packages from user-spcefied-directory to /install/packages_fw
    #####################    
    if ( (!exists($opt{commit})) && (!exists($opt{ recover }))) {
        if( preprocess_for_rflash($request, \%opt) == -1) {
            return( usage() );
        }
    }
    
    if(noderange_validate($request) == -1) {
        return(usage());
    }
  
   $request->{callback}->({data =>[ "It may take considerable time to complete, depending on the number of systems being updated.  In particular, power subsystem updates may take an hour or more if there are many attached managed systems. Please waiting."]});

    ####################################
    # No operands - add command name 
    ####################################
    $request->{method} = $cmd;
    return( \%opt );
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

#####################################
#When run rflash with the \"commit\" or \"recover\" operation, the noderange cannot be BPA and can only be CEC or LPAR.
#####################################
sub noderange_validate {
    my $request = shift;
    #my $opt = shift;    
    my $noderange = $request->{node};
    #my $t = print_var($request, "request");
    #print $t;
    ####################
    ## $f1 and $f2 are the flags for rflash, to check if there are BPAs and CECs at the same time.
    ##################
    my $f1 = 0;
    my $f2 = 0;

    ###########################################
    # Group nodes
    ###########################################
    foreach my $node ( @$noderange ) {
        my $type = undef;
        my $sitetab  = xCAT::Table->new( 'nodetype' );
        if ( defined( $sitetab )) {
            my ($ent) = $sitetab->getAttribs({ node=>$node},'nodetype');
            if ( defined($ent) ) {
               $type = $ent->{nodetype};
            }
        }
        #print "type:$type\n";
        if( $type =~/(fsp|lpar|cec)/) {
            $f1 = 1;
        } else {
            $f2 = 1;
            my $exargs=$request->{arg};
            #my $t = print_var($exargs, "exargs");
            #print $t;
            if ( grep(/commit/,@$exargs) != 0 || grep(/recover/,@$exargs) != 0) {
                send_msg( $request, 1, "When run \"rflash\" with the \"commit\" or \"recover\" operation, the noderange cannot be BPA and can only be CEC or LPAR.");
                send_msg( $request, 1, "And then, it will do the operation for both managed systems and power subsystems.");
                return -1;
             }
        }
    }

    if($f1 * $f2) {
        send_msg( $request, 1, "The argument noderange of rflash can't be BPA and CEC(or LPAR) at the same time");
        return -1;
    }
}


sub preprocess_for_rflash {
    my $request      = shift;
    my $opt = shift;    
    my $callback = $request->{callback}; 
    my $install_dir = xCAT::Utils->getInstallDir();
    my $packages_fw = "$install_dir/packages_fw";
    my $c = 0;
    my $packages_d;
#    foreach (@$exargs) {
#        $c++;
#        if($_ eq "-p") {
#            $packages_d = $$exargs[$c];
#            last;    
#        }
#    } 
    $packages_d = $$opt{p};
    if($packages_d ne $packages_fw ) {
        $$opt{p} = $packages_fw;
        if(! -d $packages_d) {
            #send_msg($request, 1, "The directory $packages_d doesn't exist!");
            $callback->({data=>["The directory $packages_d doesn't exist!"]});      
            $request = ();
                   return -1;
            }
    
            #print "opening directory and reading names\n";
            opendir DIRHANDLE, $packages_d;
            my @dirlist= readdir DIRHANDLE;
               closedir DIRHANDLE;

            @dirlist = File::Spec->no_upwards( @dirlist );

            # Make sure we have some files to process
            #
            if( !scalar( @dirlist ) ) {
            #send_msg($request, 1, "The directory $packages_d is empty !");
            $callback->({data=>["The directory $packages_d is empty !"]});
                  $request = ();
                  return -1;
            }
    
        #Find the rpm lic file
        my @rpmlist = grep /\.rpm$/, @dirlist;
        my @xmllist = grep /\.xml$/, @dirlist;
        if( @rpmlist == 0 | @xmllist == 0) {
            #send_msg($request, 1, "There isn't any rpm and xml files in the  directory $packages_d!");
            $callback->({data=>["There isn't any rpm and xml files in the  directory $packages_d!"]});
            $request = ();
            return -1;
        }
    
        my $rpm_list =  join(" ", @rpmlist);
        my $xml_list = join(" ", @xmllist);
         
        my $cmd;
        if( -d $packages_fw) {
            $cmd = "rm -rf $packages_fw";
            xCAT::Utils->runcmd($cmd, 0);
                if ($::RUNCMD_RC != 0)
                {
                #send_msg($request, 1, "Failed to remove the old packages in $packages_fw.");
                $callback->({data=>["Failed to remove the old packages in $packages_fw."]});
                $request = ();
                return -1;
                }
            }
    
        $cmd = "mkdir $packages_fw";
        xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            #send_msg($request, 1, "$cmd failed.");
            $callback->({data=>["$cmd failed."]});    
            $request = ();
            return;

        }
    
        $cmd = "cp $packages_d/*.rpm  $packages_d/*.xml $packages_fw";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            #send_msg($request, 1, "$cmd failed.");
            $callback->({data=>["$cmd failed."]});
            $request = ();
            return -1;

        }

    #$req->{arg} = $exargs;
    }
    return 0;
}



sub print_var {
    my $j = shift;
    my $msg = shift;
    
    my $var = "+++++++++$msg start--++++\n";
    if(ref($j) eq "ARRAY") {
        my $t;
        foreach $t(@$j) {
            if(ref($t) eq "ARRAY") {
                my $t0 = join(" ", @$t);
                #if(ref($t0) eq "SCALAR") {
                    $var = $var."\t$t0(array)\n";
                #} else {
                #    &print_var($t0);
                #}
            } elsif( ref($t) eq "HASH" ) {
                my $t12;
                my $t23;
                while(($t12, $t23) = each(%$t)) {
                $var = $var. "\t$t12 => \n";    
                #if(ref($t23) eq "SCALAR") {
                    $var = $var. "\t$t23(hash)\n";
                #} else {
                #    &print_var($t23);
                #}
                }
            
            }else {
                $var = $var. "$t\n";
            }
        }
    } elsif (ref($j) eq "HASH") {
        my $t1;
        my $t2;
        while(($t1, $t2) =each (%$j)) {
            $var = $var. "$t1 =>";
            if(ref($t2) eq "HASH") {
                my $t12;
                my $t23;
                while(($t12, $t23) = each(%$t2)) {
                    $var = $var. "\t$t12 => $t23\n";
                }
            } elsif(ref($t2) eq "ARRAY") {
                my $t = join(" ", @$t2);
                $var = $var. "$t (array)\n";
            } else {
                $var = $var. "$t2\n";
            }
        }
    } else {
        $var = $var. "$j(scalar)\n";
    }


    $var = $var. "+++++++++++$msg end+++++++++++\n";
    
    return $var;
}

#-------------------------------------------------------------------------#
# get_lic_filenames - construct and validate the lup filenames for each   #
# each node                                                               #
#-------------------------------------------------------------------------#
#
sub get_lic_filenames {
    my $mtms = shift;
    my $upgrade_required = 0;    
    my $msg = undef;
    my $filename;

    if(! -d $packages_dir) {
        $msg = "The directory $packages_dir doesn't exist!";
        return ("","","", $msg, -1);
    }
        
    #print "opening directory and reading names\n";
    opendir DIRHANDLE, $packages_dir;
    @dirlist= readdir DIRHANDLE;
    closedir DIRHANDLE;

    @dirlist = File::Spec->no_upwards( @dirlist );

    # Make sure we have some files to process
    #
    if( !scalar( @dirlist ) ) {
        $msg = "directory $packages_dir is empty";
            return ("","","",$msg, -1);
    }

    $release_level =~/(\w{4})(\d{3})/;
    my $pns = $1;
    my $fff = $2;
        
    #Find the latest version lic file
    @dirlist = grep /\.rpm$/, @dirlist;
    @dirlist = grep /$1/, @dirlist;
    if( !scalar( @dirlist ) ) {
    $msg = "There isn't a package suitable for $mtms";
            return ("","","",$msg, -1);
    }
    if( scalar(@dirlist) > 1) {
        # Need to find the latest version package.
        @dirlist =reverse sort(@dirlist);
        my $t = "\n";
        foreach $t(@dirlist) {
            $msg =$msg."$t\t";
        }
    }

     $filename = File::Spec->catfile( $packages_dir, $dirlist[0] );
     $dirlist[0] =~ /(\w{4})(\d{3})_(\w{3})_(\d{3}).rpm$/;
    ##############
    #If the release levels are different, it will be upgrade_required.
    #############
    if($fff ne $2) {
        $upgrade_required = 1;
    } else {

        if(($pns eq $1) && ($4 <= $active_level)) {
        $msg = $msg. "Upgrade $mtms $activate!";
    #    if($activate ne "concurrent") {
    #        $msg = "Option --actviate's value should be disruptive";
    #        return ("", "","", $msg, -1);
    #    }
        } else {
        $msg = $msg . "Upgrade $mtms disruptively!";
            if($activate ne "disruptive") {
                $msg = "Option --activate's value shouldn't be concurrent, and it must be disruptive";
                return ("", "","", $msg, -1);
            }
        } 
    }
    #print "filename is $filename\n";
    my $xml_file_name = $filename;
    $xml_file_name =~ s/(.+\.)rpm/\1xml/;
    #print "check_licdd_update: source xml file is $xml_file_name\n";

    if( ( -z $filename)|| ( -z $xml_file_name) ) {
        $msg = "The package $filename or xml $xml_file_name is empty" ;
        return ("", "", "", $msg, -1);
    }
        
    return ($filename, $xml_file_name ,$upgrade_required, $msg, 0);

}


sub get_one_mtms {
    my $exp = shift;
    my $bpa = shift;
    my $cmd = "lssyscfg -r cage -e $bpa";
    my $mtms;
    my $msg;

    my $values = xCAT::PPCcli::send_cmd( $exp, $cmd );
    my $Rc = shift(@$values);

    #####################################
    # Return error
    #####################################
    if ( $Rc != SUCCESS ) {
            $msg = "ERROR: Failed to find a CEC managed by $bpa on the HMC";
            return ("", $msg);
    }

    foreach (@$values) {
        if( $_ =~ /cage_num=(\w*),contents=sys,type_model_serial_num=(\w+)-(\w+)\*(\w+),loc_code=(\w+).(\w+).(\w+)/) {
            $mtms = "$2-$3*$4";
            last;
        }
    }

    
    #    print "the managed system is $mtms!\n";
    return ($mtms, $msg);    
}



##########################
#Performs Licensed Internal Code (LIC) update support for HMC-attached POWER5 and POWER6 Systems
###########################
sub rflash {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $subreq  = $request->{subreq};
    my $hwtype  = @$exp[2];
    my @result;
    my $timeout    = $request->{ppctimeout};
    
    my $housekeeping = $request->{housekeeping};

    $packages_dir = $request->{opt}->{p};
    $activate = $request->{opt}->{activate};    

    my $hmc;
    my $mtms;
    my $component; # system or power
    my $h;
    my $user;
    
    my $tmp_file; #the file handle of the stanza
    my $rpm_file;
    my $xml_file;
    my @rpm_files;
    my @xml_files;
    my $upgrade_required;
    my $stanza = undef;
    my $mtms_t;    
    my @value;
    my %infor;

    $hmc = @$exp[3];
    dpush(\@value, [$hmc, "In rflash()"]);
    dpush(\@value,[$hmc, print_var($request, "request")]);
    dpush(\@value,[$hmc, print_var($hash, "hash")]);
    dpush(\@value,[$hmc, print_var($exp, "exp")]);
    #    print_var($t);
    ########################
    # Now build a temporary file containing the stanzas to be run on the HMC
    ###################
    my $tmp_file = tmpnam();# the file handle of the stanza
    ##############################
    # Open the temp file
    ##########################
    
    dpush(\@value,[$hmc, "opening file $tmp_file"]);
    unless( open TMP, ">$tmp_file" ) {
            push (@value,[ $hmc, "cannot open $tmp_file, $!\n"]);
               return (\@value);
    }

    while(($mtms,$h) = each(%$hash)) {
        dpush(\@value,[$hmc, "mtms:$mtms"]);
        $mtms_t = "$mtms_t $mtms";
        my $lflag = 0;
        my $managed_system = $mtms;
        if( defined( $housekeeping ) ) {
            #$hmc_has_work = 1;
            #$::work_flag = 1;
            &dpush(\@value,[$hmc,"$mtms:creating stanza for housekeeping operation\n"]);
            $stanza = "updlic::" . $managed_system . "::" . $housekeeping . "::::";
                        
            &dpush(\@value,[$hmc, "$mtms:Writing $stanza to file\n"]);
            #push(@result,[$hmc,"$mtms:$housekeeping successfully!"]);
            $infor{$mtms} = [$housekeeping];            
            print TMP "$stanza\n";
        } else {
            while(my ($name, $d) = each(%$h)) {
                if ( @$d[4] !~ /^(fsp|bpa|lpar)$/ ) {
                       push @value, [$name,"Information only available for LPAR/CEC/BPA",RC_ERROR];
                       next;
                }
            
                ###############
                #If $name is a Lpar, the flag will be changed from "lpar" to "fsp"
                #######################
                if ( @$d[4] =~ /^lpar$/ ) {
                                @$d[4] = "fsp";
                                $lflag = 1;
                    push (@value, [$hmc,"$name is a Lpar on MTMS $mtms", 1]);
                }
                if( @$d[4] eq "fsp" ) {
                    $component = "system";
                } else {
                    $component = "power";
                }    
                dpush(\@value, [$hmc,"$mtms:component:$component!"]);
    
                my $values = xCAT::PPCcli::lslic( $exp, $d, $timeout );
                my $Rc = shift(@$values);
                #####################################
                # Return error
                  #####################################
                if ( $Rc != SUCCESS ) {
                    push @value, [$name,@$values[0],$Rc];
                    next;
                }
                
                if ( @$values[0] =~ /ecnumber=(\w+)/ ) {
                    $release_level = $1;
                    &dpush( \@value, [$hmc,"$mtms :release level:$1"]);
                }
                
                if ( @$values[0] =~ /activated_level=(\w+)/ ) {
                    $active_level = $1;
                    &dpush( \@value, [$hmc,"$mtms :activated level:$1"]);
                }    
                my $msg;            
                my $flag = 0;    
                ($rpm_file, $xml_file, $upgrade_required,$msg, $flag) = &get_lic_filenames($mtms);
                if( $flag == -1) {
                    push (@value, [$hmc,"$mtms: $msg"]);
                    push (@value, [$hmc,"Failed to upgrade the firmware of $mtms on $hmc"]);
                    return (\@value);
                }
                dpush ( \@value, [$hmc, $msg]);

                # If we get to this point, the HMC has to attempt an update on the
                # managed system, so set the flag.
                #
                #$hmc_has_work = 1;
                #::work_flag = 1;

                # Collect the rpm and xml file names in a list so we can dcp then
                   # in one call.
                #
                if( scalar( grep /$rpm_file/, @rpm_files ) == 0 ) {
                    push @rpm_files, $rpm_file;
                    push @xml_files, $xml_file;
                }
                my ($volume,$directories,$file) = File::Spec->splitpath($rpm_file);
                #push(@result,[$hmc, "Upgrade $mtms from release level:$release_level activated level:$active_level to $file successfully"]);
            
                #If mtms is a bpa, we should change the managed_system to a cec whose parent is a bpa.    
                if($component eq "power") {
                    ($managed_system, $msg)=  &get_one_mtms($exp, $managed_system);
                    if($managed_system eq "") {
                        push(@value, [$hmc, $msg]);
                        return (\@value);
                    
                    }
                    dpush(\@value,[$hmc, $msg]);
                    $infor{$managed_system} = ["upgrade", $release_level, $active_level, $file, "power", $mtms];                        
                } else {
                    $infor{$managed_system} = ["upgrade", $release_level, $active_level, $file];                        
                }
            }
            
            my $rpm_dest = $::POWER_DEST_DIR."/".$dirlist[0];
            # The contents of the stanza file are slightly different depending
            # on the operation being performed.
            #
            #    $managed_system = "9125-F2A*0262652";
            if( $upgrade_required ) {
                $stanza = "updlic::" . $managed_system . "::upgrade::::$rpm_dest";
            } else {
                $stanza = "updlic::" . $managed_system . "::activate::" . $component . "::" .$rpm_dest;
            }
            dpush(\@value,[$hmc, "Writing $stanza to file"]);
            print TMP "$stanza\n";
            @dirlist = ();
            $rpm_file = ();
            $xml_file = ();
           }
    }
    # Close the file.  dcp the stanza file, rpm update and xml file to the
    # target HMC
    #
    close TMP;
    
    ##################################
    # Get userid/password
    ##################################
    my $cred = $request->{$hmc}{cred};
    $user =  @$cred[0];
    
    dpush(\@value, [$hmc,"user: $user"]);;
    #$password = @$cred[1]    
    

    my $rpm_file_list = join(" ", @rpm_files);    
    my $xml_file_list = join(" ", @xml_files);    
    ###############################
    #Prepare for "xdcp"-----runDcp_api  is removed.
    ##############################
    my $source = "$tmp_file $rpm_file_list $xml_file_list";
    my $target = "/tmp";
    my $current_userid = getpwuid($>);
        
    my $res = xCAT::Utils->runxcmd(  {
                                     command => ['xdcp'],
                                     node    => [$hmc],
                                     arg     => [ "-l", $user, $source, $target  ],
                                     env => ["DSH_FROM_USERID=$current_userid","DSH_TO_USERID=$user"],
                                  },
                                   $subreq, 0, 1);

    if ($::RUNCMD_RC ) {   # error from dcp
        my $rsp={};
        dpush(\@value, [$hmc,"invoking xdcp"]);
        $rsp->{data}->[0] = "Error from xdcp. Return Code = $::RUNCMD_RC";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        push(@value,[$hmc,$rsp->{data}->[0]]);
        push(@value,[$hmc,"Failed to copy $tmp_file $rpm_file_list $xml_file_list to $hmc"]);
        push(@value,[$hmc,"Please check whether the HMC $hmc is configured to allow remote ssh automatic connections"]);
        push (@value, [$hmc,"Failed to upgrade the firmware of $mtms_t  on $hmc"]);
        return(\@value);
        }

    my $r = ();
    foreach $r (@$res){
        push(@value, [$r]);    
    }
        
    
    push(@value,[$hmc, "copy files to $hmc completely"]);

    ###############################################
    # Now that all the stanzas files have been built and copied to the HMCs,
    # we can use a single dsh command to invoke them all.
    ################################################
    #    @res =  xCAT::Utils->runcmd( $cmd, 0, 1);
    #    my @re1 = xCAT::Utils->runxcmd(  {
    #                                 command => ['xdsh'],
    #                                 node    => [$hmc],
    #                                 arg     => [ "-l", $user , $cmd_hmc ]
    #                              },
    #                              , $subreq, 0, 1);
    #
    #$options{ 'user' } = $user; 
    #$options{ 'nodes' } = $hmc; 
    #$options{ 'exit-status' } = 1;
    #$options{ 'stream' } = 1;    
    #$options{ 'command' } = "csmlicutil $tmp_file";
    #$options{ 'command' } = "ls -al";
    
    #@res = xCAT::DSHCLI->runDsh_api(\%options, 0);
    #my $Rc = pop(@res);
    #push(@value, [$Rc]);
    #  The above code isn't supported.
    
    my $cmd_hmc = "csmlicutil $tmp_file";
    #my $cmd_hmc = "ls";
    print "before runxcmd, current_userid = $current_userid\n";
    my $res = xCAT::Utils->runxcmd(  {
                                     command => ['xdsh'],
                                     node    => [$hmc],
                                     arg     => [ "-l", $user , $cmd_hmc ],
                                     env => ["DSH_FROM_USERID=$current_userid","DSH_TO_USERID=$user"],
                                  },
                                   $subreq, 0, 1);

    if ($::RUNCMD_RC ) {    # error from dsh 
        my $rsp={};
        $rsp->{data}->[0] = "Error from xdsh. Return Code = $::RUNCMD_RC";
        xCAT::MsgUtils->message("S", $rsp, $::CALLBACK, 1);
        dpush(\@value,[$hmc,"failed to run  xdsh"]);
        push(@value,[$hmc,$rsp->{data}->[0]]);
        push (@value, [$hmc,"Failed to upgrade the firmware of $mtms_t  on $hmc"]);
        return(\@value);
    }


    my $r = ();
    foreach $r (@$res){
        push(@value, [$r]);    
        #hmc1: mtms : LIC_RC = 0 -- successful
        #hmc1: mtms : LIC_RC = 8 -- failed
        #hmc1: mtms : LIC_RC = 12 -- failed
        if(index($r, "LIC_RC") == -1) {
            next; 
        }
        my @tmp1 = split(/:/, $r);
        $tmp1[1] =~ s/\s+//g;
        # LIC_RC = 0
        # LIC_RC = 8 
        $tmp1[2] =~ /LIC_RC\s=\s(\d*)/;   
        if($1 != 0) {  # failed
            my $tmp3 = $infor{$tmp1[1]};
            if($$tmp3[4] eq "power") {
               $tmp1[1] = $$tmp3[5];
            }
            if($$tmp3[0] eq "upgrade") {
                push(@result,[$hmc, "failed to $$tmp3[0] $tmp1[1] from release level:$$tmp3[1] activated level:$$tmp3[2] to $$tmp3[3]"]);
            } else {
                push(@result,[$hmc, "failed to $$tmp3[0] the firmware for $tmp1[1]"] );
            }
        } else { # successful
            my $tmp3 = $infor{$tmp1[1]};
            if($$tmp3[4] eq "power") {
               $tmp1[1] = $$tmp3[5];
            }
            if($$tmp3[0] eq "upgrade") {
                push(@result,[$hmc, "$$tmp3[0] $tmp1[1] from release level:$$tmp3[1] activated level:$$tmp3[2] to $$tmp3[3] successfully"]);
            } else {
                push(@result,[$hmc, "$$tmp3[0] the firmware for $tmp1[1] successfully"]);   
            }
        } 
    }
    push(@value, @result);
    return (\@value);    

}

1;


