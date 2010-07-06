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

	my $sitetab = xCAT::Table->new('site');
	my $ent = $sitetab->getAttribs({key=>'installdir'},['value']);
	my $installroot = "/install";

	# get /install directory
	if ($ent and $ent->{value}) {
		$installroot = $ent->{value};
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

	my $osver;
	my $arch;
	my $profile;
	my $rootimg_dir;
	my $destdir;
	my $imagename;

	GetOptions(
		"profile|p=s" => \$profile,
		"arch|a=s" => \$arch,
		"osver|o=s" => \$osver,
		"help|h" => \$help,
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
		(my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile');
		if (!$ref) {
			$callback->({error=>["Cannot find image \'$imagename\' from the osimage table."],errorcode=>[1]});
			return;
		}

		$osver=$ref->{'osvers'};
		$arch=$ref->{'osarch'};
		$profile=$ref->{'profile'};
	} # end of case where they give us osimage.

	unless ($osver and $arch and $profile ) {
		$callback->({error=>["osimage.osvers, osimage.osarch, and osimage.profile and must be specified for the image $imagename in the database, or you must specify -o os -p profile -a arch."],errorcode=>[1]});
		return;
	}

	$destdir="$installroot/netboot/$osver/$arch/$profile";
	$rootimg_dir="$destdir/rootimg";
	my $oldpath=cwd();
	
	# now we have all the info we need:
	# - rootimg_dir
	# - osver
	# - arch
	# - profile
	$callback->({info=>["going to modify $rootimg_dir"]});

        #get the root password for the node 
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
	#if (!$imagename) {
	#    $syncfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");
	#    if (defined ($syncfile) && -f $syncfile
	#	&& -d $rootimg_dir) {
	#	print "sync files from $syncfile to the $rootimg_dir\n";
	#	`$::XCATROOT/bin/xdcp -i $rootimg_dir -F $syncfile`;
	#    }
	#}

        #store the image in the DB
	if (!$imagename) {
	    my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($osver, $arch, $profile, 'statelite');
	    if ($ret[0] != 0) {
		$callback->({error=>["Error when updating the osimage tables: " . $ret[1]]});
	    }
            $imagename="$osver-$arch-statelite-$profile"
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

    my %hashNew = ();
    if ( parseLiteFiles($listNew, \%hashNew) ) {
        $callback->({error=>["parseLiteFiles failed for listNew!"]});
        return;
    }

    foreach my $entry (keys %hashNew) {
        my @tmp = split (/\s+/, $entry);
        if ($hashNew{$entry}) {
            foreach my $child ( @{$hashNew{$entry}} ) {
                my @tmpc = split (/\s+/, $child);
                my $f = $tmp[2];
                my $fc = $tmpc[2];
                if ($tmp[1] =~ m/bind/ && $tmpc[1] !~ m/bind/) {
                    $callback->({error=>["$fc should have bind options like $f "], errorcode=> [ 1]});
                    return;
                }
                if ($tmp[1] =~ m/tmpfs/ && $tmpc[1] =~ m/bind/) {
                    $callback->({error=>["$fc shouldnot use bind options "], errorcode=> [ 1]});
                    return;
                }
                if ($tmp[1] =~ m/persistent/ && $tmpc[1] !~ m/persistent/) {
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
        my $f = $oldentry[2];

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
                my $name = $rootimg_dir . $tmpc[2];

                if (-e $name) {
                    $verbose && $callback->({info=>["cp -a $name $rootimg_dir.statebackup$f"]});
                    xCAT::Utils->runcmd("cp -a $name $rootimg_dir.statebackup$f");
                }
            }
        }

        unless ($entry[1] eq $oldentry[1]) {
            recoverFiles($rootimg_dir, \@oldentry, $callback);
            if ($hashSaved{$line}) {
                $verbose && $callback->({info=>["$f has sub items in the litefile table."]});
                my $childrenRef = $hashSaved{$line};
                foreach my $child (@{$childrenRef}) {
                    # recover them from .statebackup to $rootimg_dir
                    my @tmpc = split (/\s+/, $child);
                    my $name = $tmpc[2];
                    my @newentries = grep /\s+$name$/, @{listNew};
                    my @entry;

                    my $destf = $rootimg_dir . $name;
                    my $srcf = $rootimg_dir . ".statebackup" . $name;
                    if ( -e $destf ) {
                        $verbose && $callback->({info => ["rm -rf $destf"]});
                        xCAT::Utils->runcmd("rm -rf $destf", 0, 1);
                    }

                    if ( -e $srcf ) {
                        $verbose && $callback->({info=>["recovering from $srcf to $destf"]});
                        xCAT::Utils->runcmd("cp -a $destf $srcf", 0, 1);
                    }

                }
            }
        }

        # recover the children
        if ($hashSaved{$line}) {
            $verbose && $callback->({info=>["$f has sub items in the litefile table."]});
            my $childrenRef = $hashSaved{$line};
            foreach my $child (@{$childrenRef}) {
                my @tmpc = split (/\s+/, $child);
                my $name = $tmpc[2];
                my @newentries = grep /\s+$name$/, @{listNew};
                my @entry;
                
                if (scalar @newentries == 1) {
                    @entry = split(/\s+/, $newentries[0]);
                }
                unless($tmpc[1] eq $entry[1]) {
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
    
=head3
    # then the @synclist
    # We need to consider the characteristics of the file if the option is "persistent,bind" or "bind"
	my @files;
    my @bindedFiles;
	foreach my $line (@synclist){
		foreach (@{$line}){
            my @entry = split(/\s+/, $_);
            # $entry[0] => imgname or nodename
            # $entry[1] => option value
            # $entry[2] => file/directory name
            my $f = $entry[2];
            if($entry[1] =~ m/bind/) {
                if($f =~ /^\//) {
                    push @bindedFiles, $f;
                }else {
                    # make sure each file begins with "/"
                    $callback->({error=>["$f in litefile does not begin with absolute path!  Need a '/' in the beginning"],errorcode=>[1]});
                    return;
                }
            } else {
			    if($f =~ /^\//){
				    push @files, $f;
			    }else{
				    # make sure each file begins with "/"
				    $callback->({error=>["$f in litefile does not begin with absolute path!  Need a '/' in the beginning"],errorcode=>[1]});
				    return;
			    }
            }
		}
	}
	
	liteMe($rootimg_dir,\@files, \@bindedFiles, $callback);
=cut

    liteMeNew($rootimg_dir, \%hashNew, $callback);

    # now stick the rc file in:
    # this is actually a pre-rc file because it gets run before the node boots up all the way.
    $verbose && $callback->({info => ["put the statelite rc file to $rootimg_dir/etc/init.d/"]});
    if ($osver =~ m/^rh/ and $arch eq "ppc64") {
        system("cp -a $::XCATROOT/share/xcat/netboot/add-on/statelite/rc.statelite.ppc.redhat $rootimg_dir/etc/init.d/statelite");
    }else {
        system("cp -a $::XCATROOT/share/xcat/netboot/add-on/statelite/rc.statelite $rootimg_dir/etc/init.d/statelite");
    }

}

sub liteMeNew {
    my $rootimg_dir = shift;
    my $hashNewRef = shift;
    my $callback = shift;

    unless (-d $rootimg_dir) {
        $callback->({error=>["no rootimage dir"],errorcode=>[1]});
        return;
    }

    # snapshot directory for tmpfs and persistent data.
    $callback->({info=>["creating $rootimg_dir/$statedir"]});
    unless ( -d "$rootimg_dir/$statedir/tmpfs" ) {
        xCAT::Utils->runcmd("mkdir -p $rootimg_dir/$statedir/tmpfs", 0, 1);
    }

    foreach my $line (keys %{$hashNewRef}) {
        liteItem($rootimg_dir, $line, 0, $callback);
        if($hashNewRef->{$line}) { # there're children 
            my $childrenRef = $hashNewRef->{$line};
            print Dumper($childrenRef);
            foreach my $child (@{$childrenRef}) {
                liteItem($rootimg_dir, $child, 1, $callback);
            }
        }
    }

    # end loop, synclist should now all be in place.
}


sub liteMe {
	# Arg 1:  root image dir: /install/netboot/centos5.3/x86_64/compute/rootimg
	my $rootimg_dir = shift; 
	my $files = shift;
    my $bindedFiles = shift;
	# Arg 2: callback ref to make comments...
	my $callback = shift;	
	unless(-d $rootimg_dir){
		$callback->({error=>["no rootimage dir"],errorcode=>[1]});
		return;
	}
	# snapshot directory for tmpfs and persistent data.	
	$callback->({info=>["creating $rootimg_dir/$statedir"]});
	mkpath("$rootimg_dir/$statedir/tmpfs");
	# now make a place for all the files.	

    # this loop uses "mount --bind" to mount files instead of creating symbolic links for 
    # each of the files in the @$bindedFiles sync list;
    # 1.  copy original contents if they exist to .default directory
    foreach my $f (@$bindedFiles) {
        # copy the file to /.defaults
        my $rif = $rootimg_dir . $f;
        my $d = dirname($f);

        # if no such file like $rif, create one
        unless ( -e "$rif" ) {
            if($f =~ m{/$}) {
                $verbose && $callback->({info=>["mkdir -p $rif"]});
                system("mkdir -p $rif");
            } else {
                # check whether its directory exists or not
                my $rifdir = dirname($rif);
                unless( -e $rifdir ) {
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
        
        # copy the file in place.
        $verbose && $callback->({info=>["cp -a $rif $rootimg_dir/.default$d"]});
        system("cp -a $rif $rootimg_dir/.default$d");
    }

	# this loop creates symbolic links for each of the files in the sync list.
	# 1.  copy original contents if they exist to .default directory
	# 2.  remove file 
	# 3.  create symbolic link to .statelite

	my $sym = "1"; # sym = 0 means no symlinks, just bindmount
	if($sym){
		foreach my $f (@$files){
            #check if the file has been moved to .default by its parent or by last liteimg, if yes, then do nothing
            my $ret=`readlink -m $rootimg_dir$f`;
            if ($? == 0) {
                if ($ret =~ /$rootimg_dir\/.default/)
                {
                    $verbose && $callback->({info=>["do nothing for file $f"]});
                    next;
                }
            }


			# copy the file to /.defaults
			my $rif = $rootimg_dir . $f;
			my $d = dirname($f);
			if( -f "$rif" or -d "$rif"){
				# if its already a link then leave it alone.
				unless(-l $rif){
					# mk the directory if it doesn't exist:
					$verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$d"]});
					system("mkdir -p $rootimg_dir/.default$d");

					# copy the file in place.
					$verbose && $callback->({info=>["cp -a $rif $rootimg_dir/.default$d"]});
					system("cp -a $rif $rootimg_dir/.default$d");

					# remove the real file
					$verbose && $callback->({info=>["rm -rf $rif"]});
					system("rm -rf $rif");

				}
	
			}else{
			
				# in this case the file doesn't exist in the image so we create something to it.
				# here we're modifying the read/only image
				unless(-d "$rootimg_dir$d"){
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
				}else{
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
				
		}	
	}else{
		# if we go the bindmount method, create some files
		foreach my $f (@$files){
			my $rif = $rootimg_dir . $f;
			my $d = dirname($rif);
			unless(-e "$rif"){
				# if it doesn't exist, create it on base image:
				unless(-d $d){
					#$callback->({info=>["mkdir -p $d"]});
					system("mkdir -p $d");
				}
				if($rif =~ /\/$/){
					#$callback->({info=>["mkdir -p $rif"]});
					system("mkdir -p $rif");
				}else{
					#$callback->({info=>["touch $rif"]});
					system("touch $rif");
				}
			}	
			else {
					#$callback->({info=>["$rif exists"]});
			}
				
		}

	}
		
	# end loop, synclist should now all be in place.

	# now stick the rc files in:
	# this is actually a pre-rc file because it gets run before the node boots up all the way.
	system("cp -a $::XCATROOT/share/xcat/netboot/add-on/statelite/rc.statelite $rootimg_dir/etc/init.d/statelite");
	
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
          'imagename bind,persistent /var/' => [
                                                 'imagename bind /var/tmp/',
                                                 'imagename bind /var/run/'
                                               ],
          'imagename bind /etc/resolv.conf' => undef,
          'imagename tmpfs,rw /root/' => [
                                           'imagename tmpfs,rw /root/.bashrc',
                                           'imagename tmpfs,rw /root/test/'
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
        my $file = $str[2];
        chop $file if ($file =~ m{/$});
        unless (exists $dhref->{"$entry"}) {
            my $parent = dirname($file);
            # to see whether $parent exists in @entries or not
            unless ($parent =~ m/\/$/) {
                $parent .= "/";
            }
            #$verbose && print "+++$parent+++\n";
            #my $found = grep $_ =~ m/\Q$parent\E$/, @entries;
            my @res = grep {$_ =~ m/\Q$parent\E$/} @entries;
            my $found = scalar @res;
            #$verbose && print "+++found = $found+++\n";

            if($found eq 1) { # $parent is found in @entries
                #$verbose && print "+++$parent is found+++\n";
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
    $f = $oldentry->[2];
    
    #$callback->({info => ["! updating $f ..."]});

    if ($oldentry->[1] =~ m/bind/) {
        # shouldn't copy back from /.default, maybe the user has replaced the file/directory in .postinstall file
        my $default = $rootimg_dir . $f;
        xCAT::Utils->runcmd("rm -rf $default", 0, 1);   # not sure whether it's necessary right now
    } else {
        my $target = $rootimg_dir . $f;
        if (-l $target) {   #not one directory
            my $location = readlink $target;
            # if it is not linked from tmpfs, it should have been modified by the .postinstall file
            if ($location =~ /\.statelite\/tmpfs/) {
                xCAT::Utils->runcmd("rm -rf $target", 0, 1);
                my $default = $rootimg_dir . "/.default" . $f;
                if( -e $default) {
                    xCAT::Utils->runcmd("cp -a $default $target", 0, 1);
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
                        xCAT::Utils->runcmd("cp -a $default $target", 0, 1);
                    } else {
                        xCAT::Utils->runcmd("mkdir $target", 0, 1);
                    }
                }
            }
        }
        $target = $rootimg_dir . "/.statelite/tmpfs" . $f;
        xCAT::Utils->runcmd("rm -rf $target", 0, 1);
    }

    return 0;
}

=head3
    liteItem
=cut

sub liteItem {
    my $rootimg_dir = shift;
    my $item = shift;
    my $isChild = shift;
    my $callback = shift;

    my @entry = split (/\s+/, $item);
    my $f = $entry[2];

    my $rif = $rootimg_dir . $f;
    my $d = dirname($f);

    if($entry[1] =~ m/bind/) {

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
        $verbose && $callback->({info=>["cp -a $rif $rootimg_dir/.default$d"]});
        system("cp -a $rif $rootimg_dir/.default$d");

    }else {
        # 1.  copy original contents if they exist to .default directory
        # 2.  remove file
        # 3.  create symbolic link to .statelite

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
                    $verbose && $callback->({info=>["mkdir -p $rootimg_dir/.default$d"]});
                    system("mkdir -p $rootimg_dir/.default$d");
                
                    # copy the file in place.
                    $verbose && $callback->({info=>["cp -a $rif $rootimg_dir/.default$d"]});
                    system("cp -a $rif $rootimg_dir/.default$d");

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
            # what we only to do is to check it exists in .default directory
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
                    xCAT::Utils->runcmd("mkdir -p $rootimg_dir/.default$fdir", 0, 1);
                }
                $verbose && $callback->({info=>["touch $rootimg_dir/.default$f"]});
                xCAT::Utils->runcmd("touch $rootimg_dir/.default$f", 0, 1);
            }
        }
    }

}


1;
