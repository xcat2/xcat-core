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
		$callback->({info=>["$cmdname -h # this help message\n$cmdname -v # version\n$cmdname -V # verbose\n$cmdname [-p profile] [-a architecture] [-o OS]\n$cmdname imagename"]});
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
	#	$callback->({info=>["packimage -h \npackimage -v \npackimage [-p profile] [-a architecture] [-o OS] \npackimage imagename"]});
		$callback->({info=>["imglite... prep an image to be lite"]});
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


	# now get the files for the node	
	my @synclist = xCAT::Utils->runcmd("ilitefile $imagename", 0, 1);
	if(!@synclist){
		$callback->({error=>["There are no files to sync for $imagename.  You have to have some files read/write filled out in the synclist table."],errorcode=>[1]});
		return;
	}

    my $listNew = $synclist[0]; 
    # verify the entries in litefile.save
    foreach my $line (@listSaved) {
        my @oldentry = split(/\s+/, $line);
        my $f = $oldentry[2];
        # if the file is not in the new synclist, or the option for the file has been changed, we need to recover the file back
        
        my @newentries = grep /\s+$f$/, @{$listNew}; # should only one entry in the array
        my @entry;

        if (scalar @newentries == 1) {
            @entry = split /\s+/, $newentries[0];
        }

        if($entry[1] eq $oldentry[1]) {
            #$callback->({info => ["$f is not changed..."]});
        } else {
            # have to consider both genimage and liteimg re-run
            $callback->({info => ["! $f may be removed or changed..."]});
            if ($oldentry[1] =~ m/bind/) {
                # shouldn't copy back from /.default, maybe the user has replaced the file/directory in .postinstall file
                my $default = $rootimg_dir . "/.default" . $f;
                xCAT::Utils->runcmd("rm -rf $default", 0, 1);   # not sure whether it's necessary right now
            } else {
                my $target = $rootimg_dir.$f;
                if (-l $target) {   #not one directory
                    my $location = readlink $target;
                    # if it is not linked from tmpfs, it should be modified by the .postinstall file
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
        }
    }
    # then store the @synclist to litefile.save
    #system("cp $rootimg_dir/.statelite/litefile.save $rootimg_dir/.statelite/litefile.save1");
    open SAVED, ">$rootimg_dir/.statelite/litefile.save";
    foreach my $line (@{$listNew}) {
        print SAVED "$line\n";
    }
    close SAVED;
    

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
        if ( !(-e "$rif") ) {
            my $rifstr = $rif;
            if($f =~ m{/$}) {
                $verbose && $callback->({info=>["mkdir -p $rif"]});
                system("mkdir -p $rif");
            } else {
                $verbose && $callback->({info=>["touch $rif"]});
                system("touch $rif");
            }
        }

        if( !(-e "$rootimg_dir/.default$d") ) {
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

1;
