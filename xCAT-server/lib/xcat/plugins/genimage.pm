package xCAT_plugin::genimage;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use xCAT::SvrUtils;
use xCAT::Table;
use Data::Dumper;

use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $prinic; #TODO be flexible on node primary nic
my $othernics; #TODO be flexible on node primary nic
my $netdriver;
my $arch;
my $profile;
my $osver;
my $rootlimit;
my $tmplimit;
my $installroot = "/install";
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
my $kerneldir;
my $mode;



sub handled_commands {
     return {
            genimage => "genimage",
   }
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $installroot = xCAT::Utils->getInstallDir();

   @ARGV = @{$request->{arg}};

   #my $rsp;
   #$rsp->{data}->[0]="genimage plugin gets called with ARGV=@ARGV" ;
   #$callback->($rsp);

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
       'permission=s' => \$permission
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
       
       (my $ref_linuximage_tab) = $linuximagetab->getAttribs({imagename => $imagename}, 'pkglist', 'pkgdir', 'otherpkglist', 'otherpkgdir', 'postinstall', 'rootimgdir', 'kerneldir', 'krpmver', 'nodebootif', 'otherifce', 'kernelver', 'netdrivers', 'permission');
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
       
       $srcdir = $ref_linuximage_tab->{'pkgdir'};
       $srcdir_otherpkgs = $ref_linuximage_tab->{'otherpkgdir'};
       $otherpkglist = $ref_linuximage_tab->{'otherpkglist'};
       $postinstall_filename = $ref_linuximage_tab->{'postinstall'};
       $destdir = $ref_linuximage_tab->{'rootimgdir'};
       
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

   if ($krpmver) {
       if ($osfamily ne "sles") {
	   $krpmver="";
	   $callback->({error=>["-g flag is valid for Sles only."],errorcode=>[1]});
	   return 1;
       }
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
   
   $cmd.= " --internal";
   if ($srcdir) { $cmd .= " --srcdir $srcdir";}
   if ($pkglist) { $cmd .= " --pkglist $pkglist";}
   if ($srcdir_otherpkgs) { $cmd .= " --otherpkgdir $srcdir_otherpkgs"; }
   if ($otherpkglist) { $cmd .= " --otherpkglist $otherpkglist"; }  
   if ($postinstall_filename)  { $cmd .= " --postinstall $postinstall_filename"; }
   if ($destdir) { $cmd .= " --rootimgdir $destdir"; } 

   if ($imagename) {
       $cmd.= " $imagename";
   }
   

   $callback->({info=>["$cmd"]});
   
   my $output = xCAT::Utils->runcmd("$cmd", 0, 1);

   #save the new settings to the osimage and linuximage tables
   if ($output && (@$output > 0)) {
       my $i=0;
       while ($i < @$output) {
	   if ( $output->[$i] =~ /The output for table updates starts here/) {
	       #print "----got here $i\n";
               my $tn;
               my %keyhash;
               my %updates;
	       my $s1=$output->[$i +1];
               my $s2=$output->[$i +2];
               my $s3=$output->[$i +3];
               if ($s1 =~ /^table::(.*)$/) {
		   $tn=$1;
	       }              
               if ($s2 =~ /^imagename::(.*)$/) {
		   $keyhash{'imagename'} = $1;
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
	       if (($tn) && (keys(%keyhash) > 0) && (keys(%updates) > 0)) {
		   my $tab= xCAT::Table->new($tn, -create=>1);
		   if ($tab) {
		      $tab->setAttribs(\%keyhash, \%updates); 
		      #print "table=$tn,%keyhash,%updates\n";
		      #print Dumper(%keyhash);
		      #print Dumper(%updates);
		   }
	       }
	   } else {
	       $i++;
	   }
       } 
       
       #remove the database upgrade section
       $callback->({info=>$output}); 
   }
}

1;
