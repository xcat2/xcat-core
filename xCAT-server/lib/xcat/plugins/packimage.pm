package xCAT_plugin::packimage;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use Getopt::Long;
use File::Path;
use File::Copy;
use Cwd;
use File::Temp;
use File::Basename;
use File::Path;
use xCAT::Utils qw(genpassword);
use xCAT::SvrUtils;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

sub handled_commands {
     return {
            packimage => "packimage",
   }
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $installroot = xCAT::Utils->getInstallDir();

   @ARGV = @{$request->{arg}};
   my $argc = scalar @ARGV;
   if ($argc == 0) {
       $callback->({info=>["packimage -h \npackimage -v \npackimage [-p profile] [-a architecture] [-o OS] [-m method]\npackimage imagename"]});
       return;
   }
   my $osver;
   my $arch;
   my $profile;
   my $method='cpio';
   my $exlistloc;
   my $syncfile;
   my $rootimg_dir;
   my $destdir;
   my $imagename;

   GetOptions(
      "profile|p=s" => \$profile,
      "arch|a=s" => \$arch,
      "osver|o=s" => \$osver,
      "method|m=s" => \$method,
      "help|h" => \$help,
      "version|v" => \$version
      );
   if ($version) {
      my $version = xCAT::Utils->Version(); 
      $callback->({info=>[$version]});
      return;
   }
   if ($help) {
      $callback->({info=>["packimage -h \npackimage -v \npackimage [-p profile] [-a architecture] [-o OS] [-m method]\npackimage imagename"]});
      return;
   }

   if (@ARGV > 0) {
       $imagename=$ARGV[0];
       if ($arch or $osver or $profile) {
	   $callback->({error=>["-o, -p and -a options are not allowed when a image name is specified."],errorcode=>[1]});
	   return;
       }
       #load the module in memory
       eval {require("$::XCATROOT/lib/perl/xCAT/Table.pm")};
       if ($@) {
	   $callback->({error=>[$@],errorcode=>[1]});
	   return;
       }
   
       #get the info from the osimage and linux 
       my $osimagetab=xCAT::Table->new('osimage', -create=>1);
       if (!$osimagetab) {
	   $callback->({error=>["The osimage table cannot be opened."],errorcode=>[1]});
	   return;
       }
       my $linuximagetab=xCAT::Table->new('linuximage', -create=>1);
       if (!$linuximagetab) {
	   $callback->({error=>["The linuximage table cannot be opened."],errorcode=>[1]});
	   return;
       }
       (my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod', 'synclists');
       if (!$ref) {
	   $callback->({error=>["Cannot find image \'$imagename\' from the osimage table."],errorcode=>[1]});
	   return;
       }
       (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'exlist', 'rootimgdir');
       if (!$ref1) {
	   $callback->({error=>["Cannot find $imagename from the linuximage table."],errorcode=>[1]});
	   return;
       }
       
       $osver=$ref->{'osvers'};
       $arch=$ref->{'osarch'};
       $profile=$ref->{'profile'};
       $syncfile=$ref->{'synclists'};
       my $provmethod=$ref->{'provmethod'};
       
       unless ($osver and $arch and $profile and $provmethod) {
	   $callback->({error=>["osimage.osvers, osimage.osarch, osimage.profile and osimage.provmethod must be specified for the image $imagename in the database."],errorcode=>[1]});
	   return;
       }
       
       if ($provmethod ne 'netboot') {
	   $callback->({error=>["\'$imagename\' cannot be used to build diskless image. Make sure osimage.provmethod is 'netboot'."],errorcode=>[1]});
	   return;
       }
       
       $exlistloc =$ref1->{'exlist'};
       $destdir=$ref1->{'rootimgdir'};
   }

   if (!$destdir)
   {
       $destdir="$installroot/netboot/$osver/$arch/$profile";
   }
   $rootimg_dir="$destdir/rootimg";

   my $distname = $osver;
   until (-r  "$::XCATROOT/share/xcat/netboot/$distname/" or not $distname) {
      chop($distname);
   }
   unless ($distname) {
      $callback->({error=>["Unable to find $::XCATROOT/share/xcat/netboot directory for $osver"],errorcode=>[1]});
      return;
   }
    unless ($installroot) {
        $callback->({error=>["No installdir defined in site table"],errorcode=>[1]});
        return;
    }
    my $oldpath=cwd();
   if (!$imagename) {
       $exlistloc=xCAT::SvrUtils->get_exlist_file_name("$installroot/custom/netboot/$distname", $profile, $osver, $arch);
       if (!$exlistloc) {  $exlistloc=xCAT::SvrUtils->get_exlist_file_name("$::XCATROOT/share/xcat/netboot/$distname", $profile, $osver, $arch); }
   }

    #if (!$exlistloc)
    #{
    #    $callback->({data=>["WARNING: Unable to find file exclusion list under $installroot/custom/netboot/$distname or $::XCATROOT/share/xcat/netboot/$distname/ for $profile/$arch/$osver\n"]});
    #}
 
    my $excludestr = "find . ";
    my $includestr;
    if ($exlistloc) {
        my $exlist;
	my $excludetext;
        open($exlist,"<",$exlistloc);
        system("echo -n > /tmp/xcat_packimg.txt");
        while (<$exlist>) {
	    $excludetext .= $_;
	}   
        close($exlist);
      
        #handle the #INLCUDE# tag recursively
        my $idir = dirname($exlistloc);
        my $doneincludes=0;
	while (not $doneincludes) {
	    $doneincludes=1;
	    if ($excludetext =~ /#INCLUDE:[^#^\n]+#/) {
		$doneincludes=0;
		$excludetext =~ s/#INCLUDE:([^#^\n]+)#/include_file($1,$idir)/eg;                 
	    }

	}

	my @tmp=split("\n", $excludetext);
	foreach (@tmp) {
	    chomp $_;
            s/\s*#.*//;      #-- remove comments 
            next if /^\s*$/; #-- skip empty lines
            if (/^\+/) {
		s/^\+//; #remove '+'	
		$includestr .= "-path '". $_ ."' -o ";                
            } else { 
		s/^\-//;  #remove '-' if any
		$excludestr .= "'!' -path '".$_."' -a ";
	    }
        }
   }
   $excludestr =~ s/-a $//;
   if ($includestr) {
       $includestr =~ s/-o $//;
       $includestr = "find . " .  $includestr;
   }
  # print "\nexcludestr=$excludestr\n\n includestr=$includestr\n\n";

   # add the xCAT post scripts to the image
    if (! -d "$rootimg_dir") {
       $callback->({error=>["$rootimg_dir does not exist, run genimage -o $osver -p $profile on a server with matching architecture"]});
       return;
    }

   #some rpms like atftp mount the rootimg/proc to /proc, we need to make sure rootimg/proc is free of junk 
   #before packaging the image
   `umount $rootimg_dir/proc`;
	copybootscript($installroot, $rootimg_dir, $osver, $arch, $profile, $callback);
   my $passtab = xCAT::Table->new('passwd');
   if ($passtab) {
      (my $pent) = $passtab->getAttribs({key=>'system',username=>'root'},'password');
      if ($pent and defined ($pent->{password})) {
         my $pass = $pent->{password};
         my $shadow;
         open($shadow,"<","$rootimg_dir/etc/shadow");
         my @shadents = <$shadow>;
         close($shadow);
         open($shadow,">","$rootimg_dir/etc/shadow");
         unless ($pass =~ /^\$1\$/) {
            $pass = crypt($pass,'$1$'.genpassword(8));
         }
         print $shadow "root:$pass:13880:0:99999:7:::\n";
         foreach (@shadents) {
             unless (/^root:/) {
                print $shadow "$_";
             }
         }
         close($shadow);
      }
   }

    # sync fils configured in the synclist to the rootimage
   if (!$imagename) {
       $syncfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");
       if (defined ($syncfile) && -f $syncfile
	   && -d $rootimg_dir) {
	   print "sync files from $syncfile to the $rootimg_dir\n";
	   `$::XCATROOT/bin/xdcp -i $rootimg_dir -F $syncfile`;
       }
   }

    my $verb = "Packing";
    if ($method =~ /nfs/) {
      $verb = "Prepping";
    }
    if ($method =~ /nfs/) {
      $callback->({data=>["\nNOTE: Contents of $rootimg_dir\nMUST be available on all service and management nodes and NFS exported."]});
    }
    my $temppath;
    my $oldumask;
    if (! -d $rootimg_dir) {
       $callback->({error=>["$rootimg_dir does not exist, run genimage -o $osver -p $profile on a server with matching architecture"]});
       return;
    }
    $callback->({data=>["$verb contents of $rootimg_dir"]});
    unlink("$destdir/rootimg.gz");
    unlink("$destdir/rootimg.sfs");
    unlink("$destdir/rootimg.nfs");
    if ($method =~ /cpio/) {
        if (!$exlistloc) {
            $excludestr = "find . |cpio -H newc -o | gzip -c - > ../rootimg.gz";
        }else {
	    chdir("$rootimg_dir");
	    system("$excludestr >> /tmp/xcat_packimg.txt"); 
	    if ($includestr) {
		system("$includestr >> /tmp/xcat_packimg.txt"); 
	    }
            #$excludestr =~ s!-a \z!|cpio -H newc -o | gzip -c - > ../rootimg.gz!;
            $excludestr = "cat /tmp/xcat_packimg.txt|cpio -H newc -o | gzip -c - > ../rootimg.gz";
        }
        $oldmask = umask 0077;
    } elsif ($method =~ /squashfs/) {
      $temppath = mkdtemp("/tmp/packimage.$$.XXXXXXXX");
      chmod 0755,$temppath;
      chdir("$rootimg_dir");
      system("$excludestr >> /tmp/xcat_packimg.txt"); 
      if ($includestr) {
	  system("$includestr >> /tmp/xcat_packimg.txt"); 
      }
      $excludestr = "cat /tmp/xcat_packimg.txt|cpio -dump $temppath"; 
    } elsif ($method =~ /nfs/) {
       $excludestr = "touch ../rootimg.nfs";
    } else {
       $callback->({error=>["Invalid method '$method' requested"],errorcode=>[1]});
    }
    chdir("$rootimg_dir");
    system($excludestr);
    if ($method =~ /cpio/) {
        chmod 0644,"$destdir/rootimg.gz";
        umask $oldmask;
    } elsif ($method =~ /squashfs/) {
       my $flags;
       if ($arch =~ /x86/) {
          $flags="-le";
       } elsif ($arch =~ /ppc/) {
          $flags="-be";
       }
       if (! -x "/sbin/mksquashfs") {
          $callback->({error=>["mksquashfs not found, squashfs-tools rpm should be installed on the management node"],errorcode=>[1]});
          return;
       }
       my $rc = system("mksquashfs $temppath ../rootimg.sfs $flags");
       if ($rc) {
          $callback->({error=>["mksquashfs could not be run successfully"],errorcode=>[1]});
          return;
       }
       $rc = system("rm -rf $temppath");
       if ($rc) {
          $callback->({error=>["Failed to clean up temp space"],errorcode=>[1]});
          return;
       }
       chmod(0644,"../rootimg.sfs");
    }
   chdir($oldpath);
   if (!$imagename) {
       my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($osver, $arch, $profile);
       if ($ret[0] != 0) {
	   $callback->({error=>["Error when updating the osimage tables: " . $ret[1]]});
       }
   }
}

###########################################################
#
#  copybootscript - copy the xCAT diskless init scripts to the image
#
#############################################################
sub copybootscript {

    my $installroot  = shift;
    my $rootimg_dir = shift;
    my $osver  = shift;
    my $arch = shift;
    my $profile = shift;
    my $callback = shift;
    my @timezone = xCAT::Utils->get_site_attribute("timezone");

    if ( -f "$installroot/postscripts/xcatdsklspost") {

        # copy the xCAT diskless post script to the image
        mkpath("$rootimg_dir/opt/xcat");  

        copy ("$installroot/postscripts/xcatdsklspost", "$rootimg_dir/opt/xcat/xcatdsklspost");
        if($timezone[0]) {
	    copy ("$rootimg_dir/usr/share/zoneinfo/$timezone[0]", "$rootimg_dir/etc/localtime");
        }


        chmod(0755,"$rootimg_dir/opt/xcat/xcatdsklspost");

    } else {

	my $rsp;
        push @{$rsp->{data}}, "Could not find the script $installroot/postscripts/xcatdsklspost.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # the following block might need to be removed as xcatdsklspost.aix may no longer be used
    if ( -f "$installroot/postscripts/xcatdsklspost.aix") {
       copy ("$installroot/postscripts/xcatdsklspost.aix", "$rootimg_dir/opt/xcat/xcatdsklspost.aix");
       chmod(0755,"$rootimg_dir/opt/xcat/xcatdsklspost.aix");
    }

	#if ( -f "$installroot/postscripts/xcatpostinit") {
        # copy the linux diskless init script to the image
        #   - & set the permissions
        #copy ("$installroot/postscripts/xcatpostinit","$rootimg_dir/etc/init.d/xcatpostinit");

        #chmod(0755,"$rootimg_dir/etc/init.d/xcatpostinit");

        # run chkconfig
        #my $chkcmd = "chroot $rootimg_dir chkconfig --add xcatpostinit";
        #symlink "/etc/init.d/xcatpostinit","$rootimg_dir/etc/rc3.d/S84xcatpostinit";
        #symlink "/etc/init.d/xcatpostinit","$rootimg_dir/etc/rc4.d/S84xcatpostinit";
        #symlink "/etc/init.d/xcatpostinit","$rootimg_dir/etc/rc5.d/S84xcatpostinit";
        #my $rc = system($chkcmd);
        #if ($rc) {
		#my $rsp;
      #  	push @{$rsp->{data}}, "Could not run the chkconfig command.\n";
      #  	xCAT::MsgUtils->message("E", $rsp, $callback);
      #      	return 1;
      #  }
    #} else {
	#my $rsp;
    #    push @{$rsp->{data}}, "Could not find the script $installroot/postscripts/xcatpostinit.\n";
    #    xCAT::MsgUtils->message("E", $rsp, $callback);
    #    return 1;
    #}
	return 0;
}

sub include_file
{
   my $file = shift;
   my $idir = shift;
   my @text = ();
   unless ($file =~ /^\//) {
       $file = $idir."/".$file;
   }
   
   open(INCLUDE,$file) || \
       return "#INCLUDEBAD:cannot open $file#";
   
   while(<INCLUDE>) {
       chomp($_);
       s/\s+$//;  #remove trailing spaces
       next if /^\s*$/; #-- skip empty lines
       push(@text, $_);
   }
   
   close(INCLUDE);
   
   return join("\n", @text);
}
