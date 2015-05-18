package xCAT_plugin::packimage;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Data::Dumper;
use xCAT::Table;
use Getopt::Long;
use File::Path;
use File::Copy;
use Cwd;
use File::Temp;
use File::Basename;
use File::Path;
#use xCAT::Utils qw(genpassword);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::SvrUtils;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");


my $verbose = 0;
#$verbose = 1;

sub handled_commands {
     return {
            packimage => "packimage",
   }
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $installroot = xCAT::TableUtils->getInstallDir();

   @ARGV = @{$request->{arg}};
   my $argc = scalar @ARGV;
   if ($argc == 0) {
       $callback->({info=>["packimage -h \npackimage -v \npackimage imagename"]});
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
   my $dotorrent;

   GetOptions(
      "profile|p=s" => \$profile,
      "arch|a=s" => \$arch,
      "osver|o=s" => \$osver,
      "method|m=s" => \$method,
      "tracker=s" => \$dotorrent,
      "help|h" => \$help,
      "version|v" => \$version
      );
   if ($version) {
      my $version = xCAT::Utils->Version(); 
      $callback->({info=>[$version]});
      return;
   }
   if ($help) {
      $callback->({info=>["packimage -h \npackimage -v \npackimage imagename"]});
      return;
   }

   if (@ARGV > 0) {
       $imagename=$ARGV[0];
       if ($arch or $osver or $profile) {
           $callback->({error=>["-o, -p and -a options are not allowed when a image name is specified."],errorcode=>[1]});
           return;
       }
       # load the module in memory
       eval {require("$::XCATROOT/lib/perl/xCAT/Table.pm")};
       if ($@) {
           $callback->({error=>[$@],errorcode=>[1]});
           return;
       }
   
       # get the info from the osimage and linux 
       my $osimagetab=xCAT::Table->new('osimage', -create=>1);
       unless ($osimagetab) {
           $callback->({error=>["The osimage table cannot be opened."],errorcode=>[1]});
           return;
       }
       my $linuximagetab=xCAT::Table->new('linuximage', -create=>1);
       unless ($linuximagetab) {
           $callback->({error=>["The linuximage table cannot be opened."],errorcode=>[1]});
           return;
       }
       (my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod', 'synclists');
       unless ($ref) {
           $callback->({error=>["Cannot find image \'$imagename\' from the osimage table."],errorcode=>[1]});
           return;
       }
       (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'exlist', 'rootimgdir');
       unless ($ref1) {
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
   } else {
       $provmethod="netboot";
       unless ($osver) {
	   $callback->({error=>["Please specify a os version with the -o flag"],errorcode=>[1]});
           return;
       }
       unless ($arch) {
	   $arch = `uname -m`;
	   chomp($arch);
	   $arch = "x86" if ($arch =~ /i.86$/);
       }

       unless ($profile) {
	   $callback->({error=>["Please specify a profile name with -p flag"],errorcode=>[1]});
           return;
       }
   }

   unless ($destdir) {
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
   unless ($imagename) {
       $exlistloc=xCAT::SvrUtils->get_exlist_file_name("$installroot/custom/netboot/$distname", $profile, $osver, $arch);
       unless ($exlistloc) {  $exlistloc=xCAT::SvrUtils->get_exlist_file_name("$::XCATROOT/share/xcat/netboot/$distname", $profile, $osver, $arch); }
      
       #save the settings into DB, it will not update if the image already exist
       my @ret = xCAT::SvrUtils->update_tables_with_diskless_image($osver, $arch, $profile, "netboot");
       unless ($ret[0] eq 0) {
	   $callback->({error=>["Error when updating the osimage tables: " . $ret[1]], errorcode=>[1]});
	   return;
       }
   }

    #before generating rootimg.gz, copy $installroot/postscripts into the image at /xcatpost
    if( -e "$rootimg_dir/xcatpost" ) {  
        system("rm -rf $rootimg_dir/xcatpost");
    }

    system("mkdir -p $rootimg_dir/xcatpost");
    system("cp -r $installroot/postscripts/* $rootimg_dir/xcatpost/");

    #put the image name and timestamp into diskless image when it is packed.
    `echo IMAGENAME="'$imagename'" > $rootimg_dir/opt/xcat/xcatinfo`;
    
    my $timestamp = `date`;
    chomp $timestamp;
    `echo TIMESTAMP="'$timestamp'" >> $rootimg_dir/opt/xcat/xcatinfo`;


    # before generating rootimg.gz or rootimg.sfs, need to switch the rootimg to stateless mode if necessary
    my $rootimg_status = 0; # 0 means stateless mode, while 1 means statelite mode
    $rootimg_status = 1 if (-f "$rootimg_dir/.statelite/litefile.save");
    
    my $ref_liteList; # get the litefile entries

    my @ret = xCAT::Utils->runcmd("ilitefile $osver-$arch-statelite-$profile" , 0, 1);
    $ref_liteList = $ret[0];

    my %liteHash;   # create hash table for the entries in @listList
    if (parseLiteFiles($ref_liteList, \%liteHash)) {
        $callback->({error=>["Failed for parsing litefile table!"], errorcode=>[1]});
        return;
    }

    $verbose && $callback->({data=>["rootimg_status = $rootimg_status at line " . __LINE__ ]});

    if($rootimg_status) {
        xCAT::Utils->runcmd("mkdir $rootimg_dir/.statebackup", 0, 1);
        # read through the litefile table to decide which file/directory should be restore
        my $defaultloc = "$rootimg_dir/.default";
        foreach my $entry (keys %liteHash) {
            my @tmp = split /\s+/, $entry;
            my $filename = $tmp[1];
            my $fileopt = $tmp[0];

            if ($fileopt =~ m/link/) {
                # backup them into .statebackup dirctory
                # restore the files with "link" options
                if ($filename =~ m/\/$/) {
                    chop $filename;
                }
                # create the parent directory if $filename's directory is not there, 
                my $parent = dirname $filename;
                unless ( -d "$rootimg_dir/.statebackup$parent" ) {
                    unlink "$rootimg_dir/.statebackup$parent";
                    $verbose && $callback->({data=>["mkdir -p $rootimg_dir/.statebackup$parent"]});
                    xCAT::Utils->runcmd("mkdir -p $rootimg_dir/.statebackup$parent", 0, 1);
                }
                $verbose && $callback->({data=>["backing up the file $filename.. at line " . __LINE__ ]});
                $verbose && print "++ $defaultloc$filename ++ $rootimg_dir$filename ++ at " . __LINE__ . "\n";
                xCAT::Utils->runcmd("mv $rootimg_dir$filename $rootimg_dir/.statebackup$filename", 0, 1);
                xCAT::Utils->runcmd("cp -r -a $defaultloc$filename $rootimg_dir$filename", 0, 1);
            }
        }
    }

    # TODO: following the old genimage code, to update the stateles-only files/directories
    # # another file should be /opt/xcat/xcatdsklspost, but it seems  not necessary
    xCAT::Utils->runcmd("mv $rootimg_dir/etc/init.d/statelite $rootimg_dir/.statebackup/statelite ", 0, 1) if ( -e "$rootimg_dir/etc/init.d/statelite");
    if ( -e "$rootimg_dir/usr/share/dracut" ) {
        # currently only used for redhat families, not available for SuSE families
        if ( -e "$rootimg_dir/etc/rc.sysinit.backup" ) {
            xCAT::Utils->runcmd("mv $rootimg_dir/etc/rc.sysinit.backup $rootimg_dir/etc/rc.sysinit", 0, 1);
        }
    }

    #restore the install.netboot of xcat dracut module 
    if(-e "$rootimg_dir/usr/lib/dracut/modules.d/97xcat/install"){
         xCAT::Utils->runcmd("mv $rootimg_dir/usr/lib/dracut/modules.d/97xcat/install $rootimg_dir/.statebackup/install", 0, 1);
    }
    xCAT::Utils->runcmd("cp /opt/xcat/share/xcat/netboot/rh/dracut_033/install.netboot $rootimg_dir/usr/lib/dracut/modules.d/97xcat/install", 0, 1);
    

    my $xcat_packimg_tmpfile = "/tmp/xcat_packimg.$$";
    my $excludestr = "find . -xdev ";
    my $includestr;
    if ($exlistloc) {
        my @excludeslist = split ',', $exlistloc;
        foreach my $exlistlocname ( @excludeslist ) {
            my $exlist;
            my $excludetext;
            open($exlist,"<",$exlistlocname);
            system("echo -n > $xcat_packimg_tmpfile");
            while (<$exlist>) {
                $excludetext .= $_;
            }   
            close($exlist);
      
            #handle the #INLCUDE# tag recursively
            my $idir = dirname($exlistlocname);
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
    }

    # the files specified for statelite should be excluded
    my @excludeStatelite = ("./etc/init.d/statelite", "./etc/rc.sysinit.backup", "./.statelite*", "./.default*", "./.statebackup*");
    foreach my $entry (@excludeStatelite) {
        $excludestr .= "'!' -path '" . $entry . "' -a ";
    }

   $excludestr =~ s/-a $//;
   if ($includestr) {
       $includestr =~ s/-o $//;
       $includestr = "find . -xdev " .  $includestr;
   }

  print "\nexcludestr=$excludestr\n\n includestr=$includestr\n\n"; # debug

   # add the xCAT post scripts to the image
    unless ( -d "$rootimg_dir") {
       $callback->({error=>["$rootimg_dir does not exist, run genimage -o $osver -p $profile on a server with matching architecture"], errorcode=>[1]});
       return;
    }

   # some rpms like atftp mount the rootimg/proc to /proc, we need to make sure rootimg/proc is free of junk 
   # before packaging the image
   system("umount $rootimg_dir/proc");
   copybootscript($installroot, $rootimg_dir, $osver, $arch, $profile, $callback);
   my $passtab = xCAT::Table->new('passwd');
   if ($passtab) {
       my $pass = 'cluster';
       (my $pent) = $passtab->getAttribs({key=>'system',username=>'root'},'password');
       if ($pent and defined ($pent->{password})) {
           $pass = $pent->{password};
       }
       my $oldmask=umask(0077);
       my $shadow;
       open($shadow,"<","$rootimg_dir/etc/shadow");
       my @shadents = <$shadow>;
       close($shadow);
       open($shadow,">","$rootimg_dir/etc/shadow");
       # 1 - MD5, 5 - SHA256, 6 - SHA512
       unless (($pass =~ /^\$1\$/) || ($pass =~ /^\$5\$/) || ($pass =~ /^\$6\$/)) {
          $pass = crypt($pass,'$1$'.xCAT::Utils::genpassword(8));
       }
       print $shadow "root:$pass:13880:0:99999:7:::\n";
       foreach (@shadents) {
           unless (/^root:/) {
               print $shadow "$_";
           }
       }
       close($shadow);
       umask($oldmask);
   }

   # sync fils configured in the synclist to the rootimage
   $syncfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot", $imagename);
   if (defined ($syncfile) && -f $syncfile
       && -d $rootimg_dir) {
            print "sync files from $syncfile to the $rootimg_dir\n";
           system("$::XCATROOT/bin/xdcp -i $rootimg_dir -F $syncfile");
   }

    my $verb = "Packing";

    my $temppath;
    my $oldmask;
    unless ( -d $rootimg_dir) {
       $callback->({error=>["$rootimg_dir does not exist, run genimage -o $osver -p $profile on a server with matching architecture"]});
       return;
    }
    $callback->({data=>["$verb contents of $rootimg_dir"]});
    unlink("$destdir/rootimg.gz");
    unlink("$destdir/rootimg.sfs");
    if ($method =~ /cpio/) {
        if ( ! $exlistloc ) {
            $excludestr = "find . -xdev |cpio -H newc -o | gzip -c - > ../rootimg.gz";
        }else {
            chdir("$rootimg_dir");
            system("$excludestr >> $xcat_packimg_tmpfile"); 
            if ($includestr) {
            	system("$includestr >> $xcat_packimg_tmpfile"); 
            }
            #$excludestr =~ s!-a \z!|cpio -H newc -o | gzip -c - > ../rootimg.gz!;
            $excludestr = "cat $xcat_packimg_tmpfile|cpio -H newc -o | gzip -c - > ../rootimg.gz";
        }
        $oldmask = umask 0077;
    } elsif ($method =~ /squashfs/) {
      $temppath = mkdtemp("/tmp/packimage.$$.XXXXXXXX");
      chmod 0755,$temppath;
      chdir("$rootimg_dir");
      system("$excludestr >> $xcat_packimg_tmpfile"); 
      if ($includestr) {
	  system("$includestr >> $xcat_packimg_tmpfile"); 
      }
      $excludestr = "cat $xcat_packimg_tmpfile|cpio -dump $temppath"; 
    } else {
       $callback->({error=>["Invalid method '$method' requested"],errorcode=>[1]});
    }
    chdir("$rootimg_dir");
    `$excludestr`;
    if ($method =~ /cpio/) {
        chmod 0644,"$destdir/rootimg.gz";
        if ($dotorrent) {
            my $currdir = getcwd;
            chdir($destdir);
            unlink("rootimg.gz.metainfo");
            system("ctorrent -t -u $dotorrent -l 1048576 -s rootimg.gz.metainfo rootimg.gz");
            chmod 0644, "rootimg.gz.metainfo";
            chdir($currdir);
        }
        umask $oldmask;
    } elsif ($method =~ /squashfs/) {
       my $flags;
       if ($arch =~ /x86/) {
          $flags="-le";
       } elsif ($arch =~ /ppc/) {
          $flags="-be";
       }

       if( $osver =~ /rhels/ && $osver !~ /rhels5/) {
           $flags="";
       }
       
       if (! -x "/sbin/mksquashfs" && ! -x "/usr/bin/mksquashfs" ) {
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
   system("rm -f $xcat_packimg_tmpfile");
    
    # move the files in /.statebackup back to rootimg_dir
    if ($rootimg_status) { #  statelite mode
        foreach my $entry (keys %liteHash) {
            my @tmp = split /\s+/, $entry;
            my $filename = $tmp[1];
            my $fileopt = $tmp[0];
            if ($fileopt =~ m/link/) {
                chop $filename if ($filename =~ m/\/$/);
                xCAT::Utils->runcmd("rm -rf $rootimg_dir$filename", 0, 1);
                xCAT::Utils->runcmd("mv $rootimg_dir/.statebackup$filename $rootimg_dir$filename", 0, 1);
            }
        }

         xCAT::Utils->runcmd("mv $rootimg_dir/.statebackup/install $rootimg_dir/usr/lib/dracut/modules.d/97xcat/install", 0, 1);
        xCAT::Utils->runcmd("mv $rootimg_dir/.statebackup/statelite $rootimg_dir/etc/init.d/statelite", 0, 1);
        xCAT::Utils->runcmd("rm -rf $rootimg_dir/.statebackup", 0, 1);
    }


   chdir($oldpath);
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
    my @timezone = xCAT::TableUtils->get_site_attribute("timezone");

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

=head3 parseLiteFiles
In the liteentry table, one directory and its sub-items (including sub-directory and entries) can co-exist;
In order to handle such a scenario, one hash is generated to show the hirarachy relationship

For example, one array with entry names is used as the input:
my @entries = (
    "imagename bind,persistent /var/",
    "imagename bind /var/tmp/",
    "imagename tmpfs,rw /root/",
    "imagename tmpfs,rw /root/.bashrc",
    "imagename tmpfs,rw /root/test/",
    "imagename bind /etc/resolv.conf",
    "imagename bind /var/run/"
);
Then, one hash will generated as:
%hashentries = {
          'bind,persistent /var/' => [
                                                 'bind /var/tmp/',
                                                 'bind /var/run/'
                                               ],
          'bind /etc/resolv.conf' => undef,
          'tmpfs,rw /root/' => [
                                           'tmpfs,rw /root/.bashrc',
                                           'tmpfs,rw /root/test/'
                                         ]
        };

Arguments:
    one array with entrynames,
    one hash to hold the entries parsed

Returns:
    0 if sucucess
    1 if fail

=cut



sub parseLiteFiles {
    my ($flref, $dhref) = @_;
    my @entries = @{$flref};


    foreach (@entries) {
        my $entry = $_;
        my @str = split /\s+/, $entry;
        shift @str;
        $entry = join "\t", @str;
        my $file = $str[1];
        chop $file if ($file =~ m{/$});
        unless (exists $dhref->{"$entry"}) {
            my $parent = dirname($file);
            # to see whether $parent exists in @entries or not
            unless ($parent =~ m/\/$/) {
                $parent .= "/";
            }
            my @res = grep {$_ =~ m/\Q$parent\E$/} @entries;
            my $found = scalar @res;

            if($found eq 1) { # $parent is found in @entries
		        # handle $res[0];
		        my @tmpresentry=split /\s+/, $res[0];
		        shift @tmpresentry;
		        $res[0] = join "\t", @tmpresentry;
                chop $parent;
                my @keys = keys %{$dhref};
                my $kfound = grep {$_ =~ m/\Q$res[0]\E$/} @keys;
                if($kfound eq 0) {
                    $dhref->{$res[0]} = [];
                }
                push @{$dhref->{"$res[0]"}}, $entry;
            }else {
                $dhref->{"$entry"} = ();
            }
        }
    }

    return 0;
}

1;
