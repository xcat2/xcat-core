package xCAT_plugin::statelite;
BEGIN
{
	$::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use Getopt::Long;
use File::Basename;
use File::Path;
use File::Copy;
use File::Find;
use Cwd;
use File::Temp;
use xCAT::Utils qw(genpassword);
use xCAT::TableUtils qw(get_site_attribute);
use xCAT::SvrUtils;
use Data::Dumper;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $cmdname = "liteimg";
my $statedir = ".statelite";
my $verbose = "0";
sub handled_commands {
	return {
		$cmdname => "statelite"
	}
}

# function to handle request.  Basically, get the information
# about the image and then do the action on it.  Is that vague enough?
sub process_request {
	my $request = shift;
	my $callback = shift;
	my $doreq = shift;

	#my $sitetab = xCAT::Table->new('site');
	#my $ent = $sitetab->getAttribs({key=>'installdir'},['value']);
        my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
        my $t_entry = $entries[0];
	my $installroot = "/install";

	# get /install directory
	if ( defined($t_entry) ) {
		$installroot = $t_entry;
	}
	# if not defined, error out... or should we set it as default?
	unless ($installroot) {
		$callback->({error=>["No installdir defined in site table"],errorcode=>[1]});
		return;
	}

	@ARGV = @{$request->{arg}};
	my $argc = scalar @ARGV;
	if ($argc == 0) {
		$callback->({info=>["$cmdname -h # this help message\n$cmdname -v # version\n$cmdname -V # verbose\n$cmdname -p <profile> -a <architecture> -o <OS>\n$cmdname imagename"]});
		return;
	}

    my $rootfstype;
    my $exlistloc; # borrowed from packimage.pm
	my $osver;
	my $arch;
	my $profile;
	my $rootimg_dir;
    my $exlist; # it is used when rootfstype = ramdisk
	my $destdir;
	my $imagename;
    my $dotorrent;

	GetOptions(
        "rootfstype|t=s" => \$rootfstype,
		"profile|p=s" => \$profile,
		"arch|a=s" => \$arch,
		"osver|o=s" => \$osver,
		"help|h" => \$help,
        "tracker" => \$dotorrent,
		"version|v" => \$version,
		"verbose|V" => \$verbose
	);

	if ($version) {
		my $version = xCAT::Utils->Version();
		$callback->({info=>[$version]});
		return;
	}
	if ($help) {
		$callback->({info=>["$cmdname -h # this help message\n$cmdname -v # version\n$cmdname -V # verbose\n$cmdname [-p profile] [-a architecture] [-o OS]\n$cmdname imagename"]});
		return;
	}

	# if they only gave us the image name:
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
			# os image doesn't exist in table.
			$callback->({error=>["The osimage table cannot be opened."],errorcode=>[1]});
			return;
		}

		# open the linux image table to get more attributes... for later.
		my $linuximagetab=xCAT::Table->new('linuximage', -create=>1);
		if (!$linuximagetab) {
			$callback->({error=>["The linuximage table cannot be opened."],errorcode=>[1]});
			return;
		}
		# get the os, arch, and profile from the image name table.
		(my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'rootfstype', 'osvers', 'osarch', 'profile','provmethod');
		if (!$ref) {
			$callback->({error=>["Cannot find image \'$imagename\' from the osimage table."],errorcode=>[1]});
			return;
		}

		my $provmethod=$ref->{'provmethod'}; 
		if ($provmethod !~ /statelite/) {
		    $callback->({error=>["Please make sure that osimage.provmethod is set to statelite before calling this command."],errorcode=>[1]});
			return;
		}

                $rootfstype = $ref->{'rootfstype'};
		$osver=$ref->{'osvers'};
		$arch=$ref->{'osarch'};
		$profile=$ref->{'profile'};

        # get the exlist and rootimgdir attributes
        (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'exlist', 'rootimgdir');
        unless($ref1) {
            $callback->({error=>[qq{Cannot find image '$imagename' from the osimage table.}], errorcode => [1]});
        }
        $destdir = $ref1->{'rootimgdir'};
        $exlistloc = $ref1->{'exlist'};
        $rootimg_dir = "$destdir/rootimg";

	} # end of case where they give us osimage.

	unless ($osver and $arch and $profile ) {
		$callback->({error=>["osimage.osvers, osimage.osarch, and osimage.profile and must be specified for the image $imagename in the database, or you must specify -o os -p profile -a arch."],errorcode=>[1]});
		return;
	}

    unless ($destdir) {
	    $destdir="$installroot/netboot/$osver/$arch/$profile";
	    $rootimg_dir="$destdir/rootimg";
    }
	my $oldpath=cwd();
	
	# now we have all the info we need:
	# - rootimg_dir
	# - osver
	# - arch
	# - profile
	$callback->({info=>["going to modify $rootimg_dir"]});

        #copy $installroot/postscripts into the image at /xcatpost
        if( -e "$rootimg_dir/xcatpost" ) {
            system("rm -rf $rootimg_dir/xcatpost");
        }

        system("mkdir -p $rootimg_dir/xcatpost");
        system("cp -r $installroot/postscripts/* $rootimg_dir/xcatpost/");
 

        #get the root password for the node 
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
		    $pass = crypt($pass,'$1$'.genpassword(8));
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

    my $distname = $osver;
    unless ( -r "$::XCATROOT/share/xcat/netboot/$distname/" or not $distname) {
        chop($distname);
    }

    unless($distname) {
        $callback->({error=>["Unable to find $::XCATROOT/share/xcat/netboot directory for $osver"], errorcode=>[1]});
        return;
    }

	unless ($imagename) {
        #store the image in the DB
	    my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($osver, $arch, $profile, 'statelite');
	    if ($ret[0]) {
		    $callback->({error=>["Error when updating the osimage tables: " . $ret[1]]});
	    }
        $imagename="$osver-$arch-statelite-$profile";

        $exlistloc = xCAT::SvrUtils->get_exlist_file_name("$installroot/custom/netboot/$distname", $profile, $osver, $arch); 
        unless ($exlistloc) { 
            $exlistloc = xCAT::SvrUtils->get_exlist_file_name("$::XCATROOT/share/xcat/netboot/$distname", $profile, $osver, $arch); 
        }
	}

        #sync fils configured in the synclist to the rootimage
        $syncfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot", $imagename);
        if (defined ($syncfile) && -f $syncfile
                && -d $rootimg_dir) {
                print "sync files from $syncfile to the $rootimg_dir\n";
                `$::XCATROOT/bin/xdcp -i $rootimg_dir -F $syncfile`;
        }

    # check if the file "litefile.save" exists or not
    # if it doesn't exist, then we get the synclist, and run liteMe
    # if it exists, it means "liteimg" has run more than one time, we need to compare with the synclist

    my @listSaved;
    if ( -e "$rootimg_dir/.statelite/litefile.save") {
        open SAVED, "$rootimg_dir/.statelite/litefile.save";
        # store all its contents to @listSaved;
        while(<SAVED>) {
            chomp $_;
            push @listSaved, $_;
        }
        close SAVED;
    }

    my %hashSaved = ();
    if ( parseLiteFiles(\@listSaved, \%hashSaved) ) {
        $callback->({error=>["parseLiteFiles failed for listSaved!"]});
        return ;
    }


	# now get the files for the node	
	my @synclist = xCAT::Utils->runcmd("ilitefile $imagename", 0, 1);
	unless (@synclist) {
		$callback->({error=>["There are no files to sync for $imagename.  You have to have some files read/write filled out in the synclist table."],errorcode=>[1]});
		return;
	}

    my $listNew = $synclist[0]; 
    # for compatible reason, replace "tmpfs,rw" with "link" option in xCAT 2.5 or higher
    for (@{$listNew}) {
        s/tmpfs,rw/link/;
    }

    # the directory/file in litefile table must be the absolute path ("/***")
    foreach my $entry (@$listNew) {
        my @tmp = split (/\s+/, $entry);

        # check the validity of the option
        if ($tmp[1] !~ /^(tmpfs|persistent|localdisk|rw|ro|con|link|tmpfs,rw|link,ro|link,persistent|link,con)$/) {
            $callback->({error=>[qq{ $tmp[2] has invalid option. The valid options: tmpfs persistent localdisk rw ro con link tmpfs,rw link,ro link,persistent link,con}], errorcode=>[1]});
            return;
        }

        unless ($tmp[2] =~ m{^/}) {
            $callback->({error=>[qq{ $tmp[2] is not one absolute path. }], errorcode=>[1]});
            return;
        }
        if ($tmp[1] =~ m{con} and $tmp[2] =~ m{/$}) {
            $callback->({error=>[qq{ $tmp[2] is directory, don't use "con" as its option }], errorcode=>[1]});
            return;
        }
    }

    my %hashNew = ();
    if ( parseLiteFiles($listNew, \%hashNew) ) {
        $callback->({error=>["parseLiteFiles failed for listNew!"]});
        return;
    }

    # validate the options for all litefile entries
    # if there is any scenario not supported, the command  exits
    foreach my $entry (keys %hashNew) {
        my @tmp = split (/\s+/, $entry);
        my $f = $tmp[1];

        if ($hashNew{$entry}) {
            if ( $tmp[0] =~ m/ro$/  or $tmp[0] =~ m/con$/) {
                $callback->({error=>[qq{the directory "$f" should not be with "ro" or "con" as its option}], errorcode=>[1]});
                return;
            }
            foreach my $child ( @{$hashNew{$entry}} ) {
                my @tmpc = split (/\s+/, $child);
                my $fc = $tmpc[1];
                if ($tmp[0] =~ m/link/) {
                    if ($tmpc[0] eq "link,ro") {
                        $callback->({error=>[qq{Based on the option of $f, $fc should not use "link,ro" as its option}], errorcode=> [1]});
                        return;
                    }
                    if ($tmpc[0] !~ m/link/) {
                        $callback->({error=>[qq{Based on the option of $f, $fc can only use "link"-based options}], errorcode=> [1]});
                        return;
                    }
                } else {
                    if ($tmpc[0] =~ m/link/) {
                        # The /etc/mtab is a specific file which can only be handled by link option.
                        # It need to be existed in rootimage and during the runing of statelite, 
                        # and after running of statelite, it need to be linked to /proc/mount
                        if ($tmpc[1] != "/etc/mtab") {
                            $callback->({error=>[qq{Based on the option of $f, $fc should not use "link"-based options}], errorcode=>[1]});
                            return;
                        }
                    }
                }
                if ( ($tmp[0] =~ m{persistent}) and ($tmpc[0] !~ m{persistent}) ) {
                    # TODO: if the parent is "persistent", the child can be ro/persistent/rw/con
                    $callback->({error=>["$fc should have persistent option like $f "], errorcode=> [ 1]});
                    return;
                }
            }
        }

    }

    # backup the file/directory before recovering the files in litefile.save
    unless ( -d "$rootimg_dir/.statebackup") {
        if (-e "$rootimg_dir/.statebackup") {
            xCAT::Utils->runcmd("rm $rootimg_dir/.statebackup", 0, 1);
        }
        $verbose && $callback->({info=>["mkdir $rootimg_dir/.statebackup"]});
        xCAT::Utils->runcmd("mkdir $rootimg_dir/.statebackup", 0, 1);
    }

    # recovery the files in litefile.save if necessary
    foreach my $line (keys %hashSaved) {
        my @oldentry = split(/\s+/, $line);
        my $f = $oldentry[1];

        my @newentries = grep /\s+$f$/, @{$listNew};
        my @entry;
        if(scalar @newentries == 1) {
            @entry = split(/\s+/, $newentries[0]);
        }

        # backup the children to .statebackup
        if ($hashSaved{$line}) {
            my $childrenRef = $hashSaved{$line};

            unless ( -d "$rootimg_dir/.statebackup$f" ) {
                xCAT::Utils->runcmd("rm -rf $rootimg_dir/.statebackup$f", 0, 1) if (-e "$rootimg_dir/.statebackup$f");
                $verbose && $callback->({info=>["mkdir $rootimg_dir/.statebackup$f"]});
                xCAT::Utils->runcmd("mkdir -p $rootimg_dir/.statebackup$f");
            }
            foreach my $child (@{$childrenRef}) {
                my @tmpc = split(/\s+/, $child);
                my $name = $rootimg_dir . $tmpc[1];

                if (-e $name) {
                    $verbose && $callback->({info=>["cp -r -a $name $rootimg_dir/.statebackup$f"]});
                    xCAT::Utils->runcmd("cp -r -a $name $rootimg_dir/.statebackup$f");
                }
            }
        }

        # there's one parent directory, whose option is different from the old one
        unless ($entry[1] eq $oldentry[0]) {
            recoverFiles($rootimg_dir, \@oldentry, $callback);
            # if its children items exist, we need to copy the backup files from .statebackup to the rootfs, 
            if ($hashSaved{$line}) {
                $verbose && $callback->({info=>["$f has child file/directory in the litefile table."]});
                my $childrenRef = $hashSaved{$line};
                foreach my $child (@{$childrenRef}) {
                    # recover them from .statebackup to $rootimg_dir
                    my @tmpc = split (/\s+/, $child);
                    my $name = $tmpc[1];
                    my @newentries = grep /\s+$name$/, @{listNew};

                    my $destf = $rootimg_dir . $name;
                    my $srcf = $rootimg_dir . "/.statebackup" . $name;
                    if ( -e $destf ) {
                        $verbose && $callback->({info => ["rm -rf $destf"]});
                        xCAT::Utils->runcmd("rm -rf $destf", 0, 1);
                    }

                    # maybe the dir of $destf doesn't exist, so we will create one
                    my $dirDestf = dirname $destf;
                    unless ( -d $dirDestf ) {
                        $verbose && $callback->({info=>["mkdir -p $dirDestf"]});
                        xCAT::Utils->runcmd("mkdir -p $dirDestf", 0, 1);
                    }

                    if ( -e $srcf ) {
                        $verbose && $callback->({info=>["recovering from $srcf to $destf"]});
                        xCAT::Utils->runcmd("cp -r -a $srcf $destf", 0, 1);
                    }

                }
            }
        }

        # recover the children
        if ($hashSaved{$line}) {
            $verbose && $callback->({info=>["$f has child file/directory in the litefile table."]});
            my $childrenRef = $hashSaved{$line};
            foreach my $child (@{$childrenRef}) {
                my @tmpc = split (/\s+/, $child);
                my $name = $tmpc[1];
                my @newentries = grep /\s+$name$/, @{$listNew};
                my @entry;
                
                if (scalar @newentries == 1) {
                    @entry = split(/\s+/, $newentries[0]);
                }
                unless($tmpc[0] eq $entry[1]) {
                    recoverFiles($rootimg_dir, \@tmpc, $callback);
                }
            }
        }

    }

    # remove  .statebackup
    $verbose && $callback->({info=>["remove .statebackup"]});
    xCAT::Utils->runcmd("rm -rf $rootimg_dir/.statebackup", 0, 1);
    
    # then store the @synclist to litefile.save
    #system("cp $rootimg_dir/.statelite/litefile.save $rootimg_dir/.statelite/litefile.save1");
    open SAVED, ">$rootimg_dir/.statelite/litefile.save";
    foreach my $line (@{$listNew}) {
        print SAVED "$line\n";
    }
    close SAVED;

    liteMe($rootimg_dir, \%hashNew, $callback);

    # now stick the rc file in:
    # this is actually a pre-rc file because it gets run before the node boots up all the way.
    $verbose && $callback->({info => ["put the statelite rc file to $rootimg_dir/etc/init.d/"]});
    # rh5,rh6.1 to rh6.4 use rc.statelite.ppc.redhat, otherwise use rc.statelite 
    if (($osver =~ m/^rh[a-zA-Z]*5/) or ($osver =~ m/^rh[a-zA-Z]*6(\.)?[1-4]/) and $arch eq "ppc64") { # special case for redhat5/6.x on PPC64
        system("cp -a $::XCATROOT/share/xcat/netboot/add-on/statelite/rc.statelite.ppc.redhat $rootimg_dir/etc/init.d/statelite");
    }else {
        system("cp -a $::XCATROOT/share/xcat/netboot/add-on/statelite/rc.statelite $rootimg_dir/etc/init.d/statelite");
    }

    # newly-introduced code for the rootfs with "ramdisk" as its type
    if( $rootfstype eq "ramdisk" ) {
        my $xcat_packimg_tmpfile = "/tmp/xcat_packimg.$$";
        my $excludestr = "find . ";
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

        $excludestr =~ s/-a $//;
        if ($includestr) {
            $includestr =~ s/-o $//;
            $includestr = "find . " .  $includestr;
        }

        print "\nexcludestr=$excludestr\n\n includestr=$includestr\n\n"; # debug
        
        # some rpms like atftp mount the rootimg/proc to /proc, we need to make sure rootimg/proc is free of junk 
        # before packaging the image
        system("umount $rootimg_dir/proc");

        my $verb = "Packing";

        my $temppath;
        my $oldmask;
        $callback->({data=>["$verb contents of $rootimg_dir"]});
        unlink("$destdir/rootimg-statelite.gz");
        if ($exlistloc) {
            chdir("$rootimg_dir");
            system("$excludestr >> $xcat_packimg_tmpfile");
            if ( $includestr) {
                system("$includestr >> $xcat_packimg_tmpfile");
            }
            $excludestr = "cat $xcat_packimg_tmpfile |cpio -H newc -o | gzip -c - > ../rootimg-statelite.gz";
        } else {
            $excludestr = "find . |cpio -H newc -o | gzip -c - > ../rootimg-statelite.gz";
        }
        $oldmask = umask 0077;
        chdir("$rootimg_dir");
        xCAT::Utils->runcmd("$excludestr");
        chmod 0644, "$destdir/rootimg-statelite.gz";
        if ($dotorrent) {
            my $currdir = getcwd;
            chdir($destdir);
            unlink("rootimg-statelite.gz.metainfo");
            system("ctorrent -t -u $dotorrent -l 1048576 -s rootimg-statelite.gz.metainfo rootimg.gz");
            chmod 0644, "rootimg-statelite.gz.metainfo";
            chdir($currdir);
        }
        umask $oldmask;
        
        system("rm -f $xcat_packimg_tmpfile");
    }
    chdir($oldpath);
}

sub liteMe {
    my $rootimg_dir = shift;
    my $hashNewRef = shift;
    my $callback = shift;

    unless (-d $rootimg_dir) {
        $callback->({error=>["no rootimage dir"],errorcode=>[1]});
        return;
    }

    unless ( -d "$rootimg_dir/$statedir" ) {
        # snapshot directory for tmpfs and persistent data.
        if ( -e "$rootimg_dir/$statedir" ) {
            xCAT::Utils->runcmd("rm -rf $rootimg_dir/$statedir", 0, 1);
        }
        $callback->({info=>["creating $rootimg_dir/$statedir"]});
        xCAT::Utils->runcmd("mkdir -p $rootimg_dir/$statedir", 0, 1);
    }
    unless ( -d "$rootimg_dir/$statedir/tmpfs" ) {
        xCAT::Utils->runcmd("mkdir -p $rootimg_dir/$statedir/tmpfs", 0, 1);
    }

    foreach my $line (keys %{$hashNewRef}) {
        liteItem($rootimg_dir, $line, 0, $callback);
        if($hashNewRef->{$line}) { # there're children 
            my $childrenRef = $hashNewRef->{$line};
            foreach my $child (@{$childrenRef}) {
                liteItem($rootimg_dir, $child, 1, $callback);
            }
        }
    }

    $callback->({info=>["done."]});
    # end loop, synclist should now all be in place.
}

sub getRelDir {
	my $f = shift;
	$f = dirname($f);
	if($f eq "/"){
		return ".";
	}
	my $l = "";
	
	my @arr = split("/", $f);
	foreach (1 .. $#arr){
		$l .= "../";
	}

	chop($l); # get rid of last /
	return $l
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
    "imagename persistent /var/",
    "imagename tempfs /var/tmp/",
    "imagename link /root/",
    "imagename link /root/.bashrc",
    "imagename link /root/test/",
    "imagename link /root/second/third",
    "imagename tempfs /etc/resolv.conf",
    "imagename tempfs /var/run/"
);
Then, one hash will generated as:
%hashentries = {
    'persistent /var/' => [
        'tempfs /var/tmp/',
        'tempfs /var/run/'
    ],
    'tempfs /etc/resolv.conf' => undef,
    'link /root/' => [
        'link /root/.bashrc',
        'link /root/test/',
        'link /root/second/third"
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
        shift @str; # remove the imgname in @entries
        $entry = join "\t", @str;
        my $file = $str[1];
        chop $file if ($file =~ m{/$});
        unless (exists $dhref->{"$entry"}) {
            my $parent = dirname $file;
            my @res;
            my $found = 0;
            while($parent ne "/") {
                # to see whether $parent exists in @entries or not
                $parent .= "/" unless ($parent =~ m/\/$/);
                @res = grep {$_ =~ m/\Q$parent\E$/} @entries;
                $found = scalar @res;
                last if ($found eq 1);
                $parent = dirname $parent;
            }

            if($found eq 1) { # $parent is found in @entries
		        # handle $res[0];
		        my @tmpresentry=split /\s+/, $res[0];
		        shift @tmpresentry; # remove the imgname in @tmpresentry
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


=head3
    recoverFiles 
=cut

sub recoverFiles {
    my ($rootimg_dir, $oldentry, $callback) = @_;
    $f = $oldentry->[1];
    
    #$callback->({info => ["! updating $f ..."]});

    if ($oldentry->[0] =~ m{^link}) {
        my $target = $rootimg_dir . $f;
        if (-l $target) {   #not one directory
            my $location = readlink $target;
            # if it is not linked from tmpfs, it should have been modified by the .postinstall file
            if ($location =~ /\.statelite\/tmpfs/) {
                xCAT::Utils->runcmd("rm -rf $target", 0, 1);
                my $default = $rootimg_dir . "/.default" . $f;
                if( -e $default) {
                    xCAT::Utils->runcmd("cp -r -a $default $target", 0, 1);
                }else { # maybe someone deletes the copy in .default directory
                    xCAT::Utils->runcmd("touch $target", 0, 1);
                }
            }
        } else {
            chop $target;
            if( -l $target ) {
                my $location = readlink $target;
                if ($location =~ /\.statelite\/tmpfs/) {
                    xCAT::Utils->runcmd("rm -rf $target", 0, 1);
                    my $default = $rootimg_dir . "/.default" . $f;
                    if( -e $default) {
                        xCAT::Utils->runcmd("cp -r -a $default $target", 0, 1);
                    } else {
                        xCAT::Utils->runcmd("mkdir $target", 0, 1);
                    }
                }
            }
        }
        $target = $rootimg_dir . "/.statelite/tmpfs" . $f;
        xCAT::Utils->runcmd("rm -rf $target", 0, 1);
    } else {
        # shouldn't copy back from /.default, maybe the user has replaced the file/directory in .postinstall file
        my $default = $rootimg_dir . $f;
        xCAT::Utils->runcmd("rm -rf $default", 0, 1);   # TODO: not sure whether it's necessary right now
    }

    return 0;
}

=head3
    liteItem
=cut

sub liteItem {
    my ($rootimg_dir, $item, $isChild, $callback) = @_;

    my @entry = split (/\s+/, $item);

    my $f = $entry[1]; # file name

    my $rif = $rootimg_dir . $f; # the file's location in rootimg_dir
    my $d = dirname($f);

    if ($entry[0] =~ m/link/) {
        # 1.  copy original contents if they exist to .default directory
        # 2.  remove file
        # 3.  create symbolic link to .statelite

        # the /etc/mtab should be handled every time even the parent /etc/ has been handled.
        # if adding /etc/ to litefile, only tmpfs should be used. 
        if ($entry[1] eq "/etc/mtab") {
            $isChild = 0;
        }

        if ($isChild == 0) {
            #check if the file has been moved to .default by its parent or by last liteimg, if yes, then do nothing
            my $ret=`readlink -m $rootimg_dir$f`;
            if ($? == 0) {
                if ($ret =~ /$rootimg_dir\/.default/) {
                    $verbose && $callback->({info=>["do nothing for file $f"]});
                    next;
                }
            }

            # copy the file to /.defaults
            if( -f "$rif" or -d "$rif"){
                # if its already a link then leave it alone.
                unless(-l $rif){
                    # mk the directory if it doesn't exist:
                    unless ( -d "$rootimg_dir/.default$d" ) {
                        $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$d"]});
                        system("mkdir -p $rootimg_dir/.default$d");
                    }
                
                    # copy the file in place.
                    $verbose && $callback->({info=>["cp -r -a $rif $rootimg_dir/.default$d"]});
                    system("cp -r -a $rif $rootimg_dir/.default$d");

                    # remove the real file
                    $verbose && $callback->({info=>["rm -rf $rif"]});
                    system("rm -rf $rif");
                }
            } else {
                # in this case the file doesn't exist in the image so we create something to it.
                # here we're modifying the read/only image

                unless (-d "$rootimg_dir$d") {
                    $verbose && $callback->({info=>["mkdir -p $rootimg_dir$d"]});
                    system("mkdir -p $rootimg_dir$d");
                }

                unless(-d "$rootimg_dir/.default$d"){
                    $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$d"]});
                    system("mkdir -p $rootimg_dir/.default$d");
                }

                # now make touch the file:
                if($f =~ /\/$/){
                    # if its a directory, make the directory in .default
                    $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$f"]});
                    system("mkdir -p $rootimg_dir/.default$f");
                } else {
                    # if its just a file then link it.
                    $verbose && $callback->({info=>["touch $rootimg_dir/.default$f"]});
                    system("touch $rootimg_dir/.default$f");
                }
            }

            # now create the spot in tmpfs
            $verbose && $callback->({info=>["mkdir -p $rootimg_dir/$statedir/tmpfs$d"]});
            system("mkdir -p $rootimg_dir/$statedir/tmpfs$d");

            # now for each file, create a symbollic link to /.statelite/tmpfs/
            # strip the last / if its a directory for linking, but be careful!
            # doing ln -sf ../../tmp <blah>../tmp when tmp is a directory creates 50 levels of links.
            # have to do:
            # ln -sf ../../tmp <blah>../../tmp/ <- note the / on the end!
            if($f =~ /\/$/){
                $f =~ s/\/$//g;
            }
            # now do the links.
            # link the .default file to the .statelite file and the real file to the .statelite file.
            # ../ for tmpfs
            # ../ for .statelite
            # the rest are for the paths in the file.
            my $l = getRelDir($f);
            $verbose && $callback->({info=>["ln -sf ../../$l/.default$f $rootimg_dir/$statedir/tmpfs$f"]});
            system("ln -sfn ../../$l/.default$f $rootimg_dir/$statedir/tmpfs/$f");

            $verbose && $callback->({info=>["ln -sf $l/$statedir/tmpfs$f $rootimg_dir$f"]});
            system("ln -sfn $l/$statedir/tmpfs$f $rootimg_dir$f");

        } else {
            # since its parent directory has been linked to .default and .statelite/tmpfs/, 
            # what we need to do is only to check whether it exists in .default directory
            if($f =~ m{/$}) { # one directory
                unless ( -d "$rootimg_dir/.default$f" ) {
                    if (-e "$rootimg_dir/.default$f") {
                        xCAT::Utils->runcmd("rm -rf $rootimg_dir/.default$f", 0, 1);
                    }
                    $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$f"]});
                    xCAT::Utils->runcmd("mkdir -p $rootimg_dir/.default$f", 0, 1);
                }
            }else { # only one file
                my $fdir = dirname($f);
                unless ( -d "$rootimg_dir/.default$fdir") {
                    $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$fdir"]});
                    xCAT::Utils->runcmd("mkdir -p $rootimg_dir/.default$fdir", 0, 1);
                }
                unless( -e "$rootimg_dir/.default$f") {
                    $verbose && $callback->({info=>["touch $rootimg_dir/.default$f"]});
                    xCAT::Utils->runcmd("touch $rootimg_dir/.default$f", 0, 1);
                }
            }
        }
    } else {
        # if no such file like $rif, create one
        unless ( -e "$rif" ) {
            if ($f =~ m{/$}) {
                $verbose && $callback->({info=>["mkdir -p $rif"]});
                system("mkdir -p $rif");
            } else {
                # check whether its directory exists or not
                my $rifdir = $rootimg_dir . $d;
                unless (-e $rifdir) {
                    $verbose && $callback->({info => ["mkdir $rifdir"]});
                    mkdir($rifdir);
                }
                $verbose && $callback->({info=>["touch $rif"]});
                system("touch $rif");
            }
        }

        unless ( -e "$rootimg_dir/.default$d" ) {
            $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$d"]});
            system("mkdir -p $rootimg_dir/.default$d");
        }
        
        # copy the file to /.defaults
        $verbose && $callback->({info=>["cp -r -a $rif $rootimg_dir/.default$d"]});
        system("cp -r -a $rif $rootimg_dir/.default$d");
    }
}


1;
