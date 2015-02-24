package xCAT_plugin::genimage;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::SvrUtils;
use xCAT::Table;
#use Data::Dumper;
use File::Path;
use File::Copy;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");


sub handled_commands {
     return {
            genimage => "genimage",
            saveimgdata => "genimage",
   }
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $command = $request->{command}->[0];

   @ARGV = @{$request->{arg}};

   #saveimg
   if ($command eq "saveimgdata") { #it is called by /opt/xcat/bin/genimage with interactive mode
       my $tempfile1=$ARGV[0];
       return save_image_data($callback, $doreq, $tempfile1);
   }

   #my $rsp;
   #$rsp->{data}->[0]="genimage plugin gets called with ARGV=@ARGV" ;
   #$callback->($rsp);

   #now handle genimage
   my $installroot = "/install";
   $installroot = xCAT::TableUtils->getInstallDir();
   my $prinic; #TODO be flexible on node primary nic
   my $othernics; #TODO be flexible on node primary nic
   my $netdriver;
   my $arch;
   my $profile;
   my $osver;
   my $rootlimit;
   my $tmplimit;
   my $kerneldir;
   my $kernelver = ""; 
   my $imagename;
   my $pkglist;
   my $srcdir;
   my $destdir;
   my $srcdir_otherpkgs;
   my $otherpkglist;
   my $postinstall_filename;
   my $rootimg_dir;
   my $mode;
   my $permission; #the permission works only for statelite mode currently
   my $krpmver;
   my $interactive;
   my $onlyinitrd;
   my $tempfile;
   my $dryrun;
   my $ignorekernelchk;
   my $noupdate;

   GetOptions(
       'a=s' => \$arch,
       'p=s' => \$profile,
       'o=s' => \$osver,
       'n=s' => \$netdriver,
       'i=s' => \$prinic,
       'r=s' => \$othernics,
       'l=s' => \$rootlimit,
       't=s' => \$tmplimit,
       'k=s' => \$kernelver,
       'g=s' => \$krpmver,
       'm=s' => \$mode,
       'kerneldir=s' => \$kerneldir,   
       'permission=s' => \$permission,
       'interactive' => \$interactive,
       'onlyinitrd' => \$onlyinitrd,
       'tempfile=s' => \$tempfile,
       'dryrun' => \$dryrun, 
       'ignorekernelchk' => \$ignorekernelchk,
       'noupdate' => \$noupdate,
       );

   my $osimagetab;
   my $linuximagetab;
   my $ref_linuximage_tab;
   my $ref_osimage_tab;
   my %keyhash = ();
   my %updates_os = ();    # the hash for updating osimage table
   my %updates_linux = (); # the hash for updating linuximage table

   #always save the input values to the db
   if ($arch)    { $updates_os{'osarch'}=$arch; }
   if ($profile) { $updates_os{'profile'} = $profile; }
   if ($osver)    { $updates_os{'osvers'} = $osver; }

   if ($netdriver) { $updates_linux{'netdrivers'} = $netdriver; }
   if ($prinic)    { $updates_linux{'nodebootif'} = $prinic; }
   if ($othernics) { $updates_linux{'otherifce'} = $othernics; }
   if ($kernelver) { $updates_linux{'kernelver'} = $kernelver; }
   if ($krpmver)   { $updates_linux{'krpmver'} = $krpmver; }
   if ($kerneldir) { $updates_linux{'kerneldir'} = $kerneldir; }  
   if ($permission){ $updates_linux{'permission'} = $permission; }

    # get the info from the osimage and linuximage table
    $osimagetab = xCAT::Table->new('osimage', -create=>1);
    unless ($osimagetab) {
	$callback->({error=>["The osimage table cannot be open."],errorcode=>[1]});
        return 1;
    }
    
    $linuximagetab = xCAT::Table->new('linuximage', -create=>1);
    unless($linuximagetab) {
	$callback->({error=>["The linuximage table cannot be open."],errorcode=>[1]});
        return 1;
    }

   
   if (@ARGV > 0) {
       $imagename=$ARGV[0];
       if ($arch or $osver or $profile) {
	   $callback->({error=>["-o, -p and -a options are not allowed when a image name is specified."],errorcode=>[1]});
	   return 1;
       }
       
       (my $ref_osimage_tab) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod');
       unless ($ref_osimage_tab) {
	   $callback->({error=>["Cannot find image \'$imagename\' from the osimage table."],errorcode=>[1]});	   
	   return 1;
       }
       
       (my $ref_linuximage_tab) = $linuximagetab->getAttribs({imagename => $imagename}, 'pkglist', 'pkgdir', 'otherpkglist', 'otherpkgdir', 'postinstall', 'rootimgdir', 'kerneldir', 'krpmver', 'nodebootif', 'otherifce', 'kernelver', 'netdrivers', 'permission','driverupdatesrc');
       unless ($ref_linuximage_tab) {
	   $callback->({error=>["Cannot find $imagename from the linuximage table."],errorcode=>[1]});
	   return 1;
       }
       
       $osver=$ref_osimage_tab->{'osvers'};
       $arch=$ref_osimage_tab->{'osarch'};
       $profile=$ref_osimage_tab->{'profile'};
       my $provmethod=$ref_osimage_tab->{'provmethod'}; # TODO: not necessary, and need to update both statelite and stateless modes
       
       unless ($osver and $arch and $profile and $provmethod) {
	   $callback->({error=>["osimage.osvers, osimage.osarch, osimage.profile and osimage.provmethod must be specified for the image $imagename in the database."],errorcode=>[1]});
	   return 1;
       }
       
       unless ($provmethod eq 'netboot' || $provmethod eq 'statelite') {
	   $callback->({error=>["\'$imagename\' cannot be used to build diskless image. Make sure osimage.provmethod is 'netboot'."],errorcode=>[1]});
	   return 1;
       }
       
       unless ( $ref_linuximage_tab->{'pkglist'}) {
	   $callback->({error=>["A .pkglist file must be specified for image \'$imagename\' in the linuximage table."],errorcode=>[1]});
	   return 1;
       }
       $pkglist = $ref_linuximage_tab->{'pkglist'};
       if ($pkglist ne "" and ! -e $pkglist) {
           $callback->({error=>["The pkglist specified \'$pkglist\' does not exist!"],errorcode=>[1]});
	   return 1;
       }
       
       $srcdir = $ref_linuximage_tab->{'pkgdir'};

       $srcdir_otherpkgs = $ref_linuximage_tab->{'otherpkgdir'};
       $otherpkglist = $ref_linuximage_tab->{'otherpkglist'};
       if ($otherpkglist ne "" and ! -e $otherpkglist) {
           $callback->({error=>["The otherpkglist specified \'$otherpkglist\' does not exist!"],errorcode=>[1]});
	   return 1;
       }
       $postinstall_filename = $ref_linuximage_tab->{'postinstall'};
       if ($postinstall_filename ne "" and ! -e $postinstall_filename) {
           $callback->({error=>["The postinstall_filename specified \'$postinstall_filename\' does not exist!"],errorcode=>[1]});
	   return 1;
       }
       $destdir = $ref_linuximage_tab->{'rootimgdir'};
       $rootimg_dir = $ref_linuximage_tab->{'rootimgdir'};
       $driverupdatesrc = $ref_linuximage_tab->{'driverupdatesrc'};
       
       # TODO: how can we do if the user specifies one wrong value to the following attributes?
       # currently, one message is output to indicate the users there will be some updates
       
       if ($prinic) {
	   if ($prinic ne $ref_linuximage_tab->{'nodebootif'}) {
	        $callback->({info=>["The primary nic is different from the value in linuximage table, will update it."]});
		$updates{'nodebootif'} = $prinic;
	   }
       } else {
	   $prinic = $ref_linuximage_tab->{'nodebootif'};
       }
       if ($othernics) {
	   if ($othernics ne $ref_linuximage_tab->{'otherifce'}) {
	       $callback->({info=>["The other ifces are different from  the value in linuximage table, will update it."]});
	       $updates{'otherifce'} = $othernics;
	   }
       } else {
	   $othernics = $ref_linuximage_tab->{'otherifce'};
       }
       if ($kernelver) {
	   if ($kernelver ne $ref_linuximage_tab->{'kernelver'}) {
	       $callback->({info=>["The kernelver is different from the value in linuximage table, will update it."]});
	       $updates{'kernelver'} = $kernelver;
	   }
       } else {
	   $kernelver = $ref_linuximage_tab->{'kernelver'};
       }
       
       if ($krpmver) {
	   if ($krpmver ne $ref_linuximage_tab->{'krpmver'}) {
	       $callback->({info=>["The krpmver is different from the value in linuximage table, will update it."]});
	       $updates{'krpmver'} = $krpmver;
	   }
       } else {
	   $krpmver = $ref_linuximage_tab->{'krpmver'};
       }

       if ($kerneldir) {
	   if ($kerneldir ne $ref_linuximage_tab->{'kerneldir'}) {
	       print "The kerneldir is different from the value in linuximage table, will update it\n";
	       $updates{'kerneldir'} = $kerneldir;
	   }
       } else {
	   $kerneldir = $ref_linuximage_tab->{'kerneldir'};
       }
       if ($netdriver) {
	   if ($netdriver ne $ref_linuximage_tab->{'netdrivers'}) {
	       $callback->({info=>["The netdrivers is different from the value in linuximage table, will update it."]});
	       $updates{'netdrivers'} = $netdriver;
	   }
       } else {
	   $netdriver = $ref_linuximage_tab->{'netdrivers'};
       }
       
       if ($permission) {
	   if ($permission ne $ref_linuximage_tab->{'permission'}) {
	       $callback->({info=>["The permission is different from the value in linuximage table, will update it."]});
	       $updates{'permission'} = $permission;
	   }
       } else {
	   $permission = $ref_linuximage_tab->{'permission'};
       }
    }

    
   ### Get the Profile ####
   my $osfamily = $osver;
   $osfamily  =~ s/\d+//g;
   $osfamily  =~ s/\.//g;
   if($osfamily =~ /rh/){
       $osfamily = "rh";
   }

   # OS version on s390x can contain 'sp', e.g. sles11sp1
   # If the $osfamily contains 'sles' and 'sp', the $osfamily = sles
   if ($osfamily =~ /sles/ && $osfamily =~ /sp/) {
       $osfamily = "sles";
   }

   $osfamily =~ s/ //g;

   #-m flag is used only for ubuntu, debian and ferdora12, for others genimage will create
   #initrd.gz for both netboot and statelite, no -m is needed.
   if ($mode) {
       if (($osfamily ne "ubuntu") && ($osfamily ne "debian") && ($osver !~ /fedora12/)) {
	   $mode="";
	   $callback->({error=>["-m flag is valid for Ubuntu, Debian and Fedora12 only."],errorcode=>[1]});
	   return 1;
       }
   }

   $profDir = "$::XCATROOT/share/xcat/netboot/$osfamily";
   unless(-d $profDir){
       $callback->({error=>["Unable to find genimage script in $profDir."],errorcode=>[1]});
       return 1;
   }

   my $cmd="cd $profDir; ./genimage";
   if ($arch) { $cmd .= " -a $arch";}
   if ($osver) { $cmd .= " -o $osver";}
   if ($profile) { $cmd .= " -p $profile";}

   if ($netdriver) { $cmd .= " -n $netdriver";}
   if ($prinic) { $cmd .= " -i $prinic";}
   if ($othernics) { $cmd .= " -r $othernics";}
   if ($rootlimit) { $cmd .= " -l $rootlimit";}
   if ($tmplimit) { $cmd .= " -t $tmplimit";}
   if ($kernelver) { $cmd .= " -k $kernelver";}
   if ($krpmver) { $cmd .= " -g $krpmver";}
   if ($mode) { $cmd .= " -m $mode";}
   if ($permission) { $cmd .= " --permission $permission"; }
   if ($kerneldir) { $cmd .= " --kerneldir $kerneldir"; }
   if ($interactive) { $cmd .= " --interactive" }
   if ($onlyinitrd) { $cmd .= " --onlyinitrd" }
   
   if ($srcdir) { $cmd .= " --srcdir \"$srcdir\"";}
   if ($pkglist) { $cmd .= " --pkglist $pkglist";}
   if ($srcdir_otherpkgs) { $cmd .= " --otherpkgdir \"$srcdir_otherpkgs\""; }
   if ($otherpkglist) { $cmd .= " --otherpkglist $otherpkglist"; }  
   if ($postinstall_filename)  { $cmd .= " --postinstall $postinstall_filename"; }
   if ($destdir) { $cmd .= " --rootimgdir $destdir"; } 
   if ($tempfile) { 
       if (!$dryrun) { $cmd .= " --tempfile $tempfile"; } 
   }
   if ($driverupdatesrc) { $cmd .= " --driverupdatesrc $driverupdatesrc"; }
   if ($ignorekernelchk) { $cmd .= " --ignorekernelchk $ignorekernelchk"; }
   if ($noupdate) { $cmd .= " --noupdate $noupdate"; }

   if($osfamily eq "sles") {
       my @entries =  xCAT::TableUtils->get_site_attribute("timezone");
       my $tz = $entries[0];
       if($tz) { $cmd .= " --timezone $tz"; }
   }

   if ($imagename) {
       $cmd.= " $imagename";
   }
   

   $callback->({info=>["$cmd"]});
   $::CALLBACK=$callback;
   
   if ($tempfile) {
       #first print the command 
       open(FILE, ">$tempfile");
       print FILE "$cmd\n\n";
       #then print the update info for osimage and linuximage table

       if (keys(%updates_os) > 0) {
	   print FILE "The output for table updates starts here\n";
	   print FILE "table::osimage\n";
	   print FILE "imagename::aaaaa_not_known_yet_aaaaa\n"; #special image name
	   my @a=%updates_os;
	   print FILE join('::',@a) . "\n";
	   print FILE "The output for table updates ends here\n";
       }
       
       if (keys(%updates_linux) > 0) {
	   print FILE "The output for table updates starts here\n";
	   print FILE "table::linuximage\n";
	   print FILE "imagename::aaaaa_not_known_yet_aaaaa\n";  #special image name
	   my @a=%updates_linux;
	   print FILE join('::',@a) . "\n";
	   print FILE "The output for table updates ends here\n";
       }
       close File;
   } else {
       $callback->({error=>["NO temp file provided to store the genimage command."]});
       return;
   }

   #it only shows the underlying  command without actually running the command
   if ($dryrun) { return; }

   
   if ($interactive) {
       return; #back to the client, client will run 
   } else {
       #my $output = xCAT::Utils->runcmd("$cmd", 0, 1); # non-stream 
       my $output = xCAT::Utils->runcmd("$cmd", 0, 1, 1); # stream output 
       #open(FILE, ">>$tempfile");
       #foreach my $entry (@$output) {
       #   print FILE $entry;
       #   print FILE "\n";
       #}
       #close FILE; 

       # update the generated initrd to /tftpboot/xcat so that don't need to rerun nodeset to update them
       if (($::RUNCMD_RC == 0) && $imagename) {
           my $tftpdir  = "/tftpboot";
           my @siteents = xCAT::TableUtils->get_site_attribute("tftpdir");
           if ($#siteents >= 0)
           {
               $tftpdir = $siteents[0];
           }
           my $tftppath = "$tftpdir/xcat/osimage/$imagename";

           my $installdir = "/install";
           @siteents = xCAT::TableUtils->get_site_attribute("installdir");
           if ($#siteents >= 0)
           {
               $installdir = $siteents[0];
           }

           unless (-d $tftppath) {
               mkpath $tftppath;
           }
           copy("$rootimg_dir/initrd-stateless.gz", "$tftppath");
           copy("$rootimg_dir/initrd-statelite.gz", "$tftppath");
           copy("$rootimg_dir/kernel", "$tftppath");
       }
       
       #parse the output and save the image data to osimage and linuximage table
       save_image_data($callback, $doreq, $tempfile);
   }
}

sub save_image_data {
    my $callback=shift;
    my $doreq=shift;
    my $filename=shift;
    #updates_os and updates_linux are defined at the top of the given file with imagename::aaaaa_not_known_yet_aaaaa
    my %updates_os=();
    my %updates_linux=();
    
    my $cmd="cat $filename";
    my $output = xCAT::Utils->runcmd("$cmd", 0, 1); 

    if ($output && (@$output > 0)) {
	my $i=0;
	while ($i < @$output) {
	    if ( $output->[$i] =~ /The output for table updates starts here/) {
		#print "----got here $i\n";
		my $tn;
		my $imgname;
		my %keyhash;
		my %updates;
		my $s1=$output->[$i +1];
		my $s2=$output->[$i +2];
		my $s3=$output->[$i +3];
		if ($s1 =~ /^table::(.*)$/) {
		    $tn=$1;
		}              
		if ($s2 =~ /^imagename::(.*)$/) {
		    $imgname=$1;
		    $keyhash{'imagename'} = $imgname;
		}    
		
		if ($tn eq 'osimage') {
		    %updates=%updates_os;
		} elsif ($tn eq 'linuximage') {
		    %updates=%updates_linux;
		}
		
		
		my @a=split("::", $s3);
		for (my $j=0; $j < @a; $j=$j+2) {
		    $updates{$a[$j]} = $a[$j+1];
		}
		splice(@$output, $i, 5);

		if ($imgname eq "aaaaa_not_known_yet_aaaaa") {
                    #the file contains updates_os and updates_linux at the begining of the file. So read them out and save the to the variables, do not commit yet because the real image name will be provided later in the file. 
		    if (($tn) && (keys(%updates) > 0)) {
			if ($tn eq 'osimage') {
			    %updates_os=%updates;
			}  elsif ($tn eq 'linuximage') {
			    %updates_linux=%updates;
			}
		    }
		} else {
		    
		    if (($tn) && (keys(%keyhash) > 0) && (keys(%updates) > 0)) {
			my $tab= xCAT::Table->new($tn, -create=>1);
			if ($tab) {
			    $tab->setAttribs(\%keyhash, \%updates); 
			    #print "table=$tn,%keyhash,%updates\n";
			    #print "*** keyhash=" . Dumper(%keyhash);
			    #print "*** updates=" . Dumper(%updates);
			}
		    }
		}
	    } else { # if ( $output->[$i] =~ ....)
		$i++;
	    }
	} #if ($output && (@$output > 0)) 
	 
	# remove tmp file
	#`rm /tmp/genimageoutput`; 
	#remove the database upgrade section
	# runcmd_S displays the output
	#$callback->({info=>$output}); 
    }    
}

1;
