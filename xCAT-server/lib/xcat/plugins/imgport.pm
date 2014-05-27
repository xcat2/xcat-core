# Sumavi Inc (C) 2010

# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

#####################################################
# imgport will export and import xCAT stateless, statelite, and diskful templates.
# This will make it so that you can easily share your images with others.
# All your images are belong to us!
package xCAT_plugin::imgport;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings;
#use xCAT::Table;
#use xCAT::Schema;
#use xCAT::NodeRange qw/noderange abbreviate_noderange/;
#use xCAT::Utils;
use xCAT::TableUtils;
use Data::Dumper;
use XML::Simple;
use POSIX qw/strftime/;
use Getopt::Long;
use File::Temp;
use File::Copy;
use File::Path qw/mkpath/;
use File::Path qw/rmtree/;
use File::Basename;
use xCAT::NodeRange;
use xCAT::Schema;
use Cwd;
my $requestcommand;
$::VERBOSE = 0;
my $hasplugin=0;

1;

#some quick aliases to table/value
my %shortnames = (
                  groups => [qw(nodelist groups)],
                  tags   => [qw(nodelist groups)],
                  mgt    => [qw(nodehm mgt)],
                  #switch => [qw(switch switch)],
                  );

#####################################################
# Return list of commands handled by this plugin
#####################################################
sub handled_commands
{
    return {
        imgexport   => "imgport",
        imgimport   => "imgport",
    };
}

#####################################################
# Process the command
#####################################################
sub process_request
{
    #use Getopt::Long;
    Getopt::Long::Configure("bundling");
    #Getopt::Long::Configure("pass_through");
    Getopt::Long::Configure("no_pass_through");

    my $request  = shift;
    my $callback = shift;
    $requestcommand = shift;
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};

    if ($command eq "imgexport"){
        return xexport($request, $callback);
    }elsif ($command eq "imgimport"){
        return ximport($request, $callback);
    }else{
        print "Error: $command not found in export\n";
        $callback->({error=>["Error: $command not found in this module."],errorcode=>[1]});
        #return (1, "$command not found in sumavinode");
    }
}

# extract the bundle, then add it to the osimage table.  Basically the ying of the yang of the xexport
# function.
sub ximport {
    my $request = shift;
    my $callback = shift;
    my %rsp;    # response
    my $help;
    my $nodes;
    my $new_profile;
    my $remoteHost;

    my $xusage = sub {
        my $ec = shift;
        push@{ $rsp{data} }, "imgimport: Takes in an xCAT image bundle and defines it to xCAT so you can use it"; 
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\timgimport [-h|--help]";
        push@{ $rsp{data} }, "\timgimport <bundle_file_name> [-p|--postscripts <nodelist>] [-f|--profile <new_profile>] [-R|--remotehost <userid\@host>] [-v]";
        if($ec){ $rsp{errorcode} = $ec; }
        $callback->(\%rsp);
    };
    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{ $request->{arg}};
    if($#ARGV eq -1){
        $xusage->(1);
        return;
    }

    GetOptions(
        'h|?|help' => \$help,
        'v|verbose' => \$::VERBOSE,
        'R|remotehost=s' => \$remoteHost,
            'p|postscripts=s' => \$nodes,
            'f|profile=s' => \$new_profile,
    );

    if($help){
        $xusage->(0);
        return;
    }

    # first extract the bundle  
    extract_bundle( $request, $callback, $nodes, $new_profile, $remoteHost );
    
}


# function to export your image.  The image should already be in production, work well, and have 
# no bugs.  Lots of places will have problems because the image may not be in osimage table
# or they may have hardcoded things, or have post install scripts.
sub xexport { 
    my $request = shift;
    my $callback = shift;
    my %rsp;    # response
    my $help;
    my @extra;
    my $node;
    my $remoteHost;

    my $xusage = sub {
        my $ec = shift;
        push@{ $rsp{data} }, "imgexport: Creates a tarball (bundle) of an existing xCAT image";
        push@{ $rsp{data} }, "Usage: ";
        push@{ $rsp{data} }, "\timgexport [-h|--help]";
        push@{ $rsp{data} }, "\timgexport <image_name> [destination] [[-e|--extra <file:dir> ] ... ] [-p|--postscripts <node_name>] [-R|--remotehost <userid\@host>] [-v]";
        if($ec){ $rsp{errorcode} = $ec; }
        $callback->(\%rsp);
    };
    unless(defined($request->{arg})){ $xusage->(1); return; }
    @ARGV = @{ $request->{arg}};
    if($#ARGV eq -1){
        $xusage->(1);
        return;
    }

    GetOptions(
        'h|?|help' => \$help,
            'p|postscripts=s' => \$node,
        'e|extra=s' => \@extra,
        'R|remotehost=s' => \$remoteHost,
        'v|verbose' => \$::VERBOSE
    );

    if($help){
        $xusage->(0);
        return;
    }
    
    # ok, we're done with all that.  Now lets actually start doing some work.
    my $img_name = shift @ARGV; 
    my $dest = shift @ARGV;
    my $cwd = $request->{cwd}; #getcwd;
    $cwd = $cwd->[0];

    $callback->( {data => ["Exporting $img_name to $cwd..."]});
    # check if all files are in place
    my $attrs = get_image_info($img_name, $callback, $node, @extra);
    #print Dumper($attrs);

    unless($attrs){
        return 1;
    }   

    # make manifest and tar it up.
    make_bundle( $img_name, $dest, $remoteHost, $attrs, $callback, $cwd );
    
}





# verify the image and return the values
sub get_image_info {
    my $imagename = shift;
    my $callback = shift;
    my $node = shift;
    my @extra = @_;
    my $errors = 0;
    my $attrs;
    
    my $ostab = new xCAT::Table('osimage', -create=>1);
    unless($ostab){
        $callback->(
            {error => ["Unable to open table 'osimage'."],errorcode=>1}
        );
        return 0;
    }
    
    #(my $attrs) = $ostab->getAttribs({imagename => $imagename}, 'profile', 'imagetype', 'provmethod', 'osname', 'osvers', 'osdistro', 'osarch', 'synclists');
    (my $attrs0) = $ostab->getAttribs({imagename => $imagename},\@{$xCAT::Schema::tabspec{osimage}->{cols}});
    if (!$attrs0) {
        $callback->({error=>["Cannot find image \'$imagename\' from the osimage table."],errorcode=>[1]});
        return 0;
    }

    unless($attrs0->{provmethod}){
        $callback->({error=>["The 'provmethod' field is not set for \'$imagename\' in the osimage table."],errorcode=>[1]});
        $errors++;
    }

    unless($attrs0->{profile}){
        $callback->({error=>["The 'profile' field is not set for \'$imagename\' in the osimage table."],errorcode=>[1]});
        $errors++;
    }

    unless($attrs0->{osvers}){
        $callback->({error=>["The 'osvers' field is not set for \'$imagename\' in the osimage table."],errorcode=>[1]});
        $errors++;
    }

    unless($attrs0->{osarch}){
        $callback->({error=>["The 'osarch' field is not set for \'$imagename\' in the osimage table."],errorcode=>[1]});
        $errors++;
    }

    unless($attrs0->{provmethod} =~ /install|netboot|statelite|raw/){
        $callback->({error=>["Exporting images with 'provemethod' " . $attrs0->{provmethod} . " is not supported. Hint: install, netboot, statelite, or raw"], errorcode=>[1]});
        $errors++;
    }

    #$attrs->{imagename} = $imagename;

    if($errors){
        return 0;
    }
    
    $attrs->{osimage}=$attrs0;

    my $linuximagetab = new xCAT::Table('linuximage', -create=>1);
    unless($linuximagetab){
        $callback->(
            {error => ["Unable to open table 'linuximage'"],errorcode=>1}
        );
        return 0;
    }
    
    #from linuximage table
    #(my $attrs1) = $linuximagetab->getAttribs({imagename => $imagename}, 'template', 'pkglist', 'pkgdir', 'otherpkglist', 'otherpkgdir', 'exlist', 'postinstall', 'rootimgdir', 'nodebootif', 'otherifce', 'netdrivers', 'kernelver', 'permission');
    (my $attrs1) = $linuximagetab->getAttribs({imagename => $imagename},\@{$xCAT::Schema::tabspec{linuximage}->{cols}});
    if (!$attrs1) {
        $callback->({error=>["Cannot find image \'$imagename\' from the linuximage table."],errorcode=>[1]});
        return 0;
    }
    
	#merge attrs with attrs1    
    #foreach (keys %$attrs1) {
    #    $attrs->{$_} = $attrs1->{$_};
    #}
    $attrs->{linuximage}=$attrs1;


    # for kit staff

    if ($attrs0->{kitcomponents}) {
        my $kitcomponenttab = new xCAT::Table('kitcomponent', -create=>1);
        unless($kitcomponenttab){
            $callback->(
                {error => ["Unable to open table 'kitcomponent'"],errorcode=>1}
            );
            return 0;
        }

        my $kittab = new xCAT::Table('kit', -create=>1);
            unless($kittab){
            $callback->(
                {error => ["Unable to open table 'kit'"],errorcode=>1}
            );
            return 0;
        }

        my $kitrepotab = new xCAT::Table('kitrepo', -create=>1);
            unless($kitrepotab){
            $callback->(
                {error => ["Unable to open table 'kitrepo'"],errorcode=>1}
            );
            return 0;
        }

        my $kitlist;
        my $kitrepolist;
        my $kitcomplist;
        foreach my $kitcomponent (split ',', $attrs0->{kitcomponents}) {
            (my $kitcomphash) = $kitcomponenttab->getAttribs({kitcompname => $kitcomponent},'kitname');
            if (!$kitcomphash) {
                $callback->({error=>["Cannot find kitname of \'$kitcomponent\' from the kitcomponent table."],errorcode=>[1]});
                return 0;
            }
            
            if ($kitcomphash->{kitname}) {
                $kitlist->{$kitcomphash->{kitname}} = 1;

                my @kitrepohash = $kitrepotab->getAllAttribsWhere( "kitname = '$kitcomphash->{kitname}'", 'kitreponame');
                foreach my $kitrepo (@kitrepohash) {
                    if ($kitrepo->{kitreponame}) {
                        $kitrepolist->{$kitrepo->{kitreponame}} = 1;
                    }
                }

                my @kitcomponents = $kitcomponenttab->getAllAttribsWhere( "kitname = '$kitcomphash->{kitname}'", 'kitcompname');
                foreach my $kitcomp (@kitcomponents) {
                    if ($kitcomp->{kitcompname}) {
                        $kitcomplist->{$kitcomp->{kitcompname}} = 1;
                    }
                }
            }
        }


        foreach my $kitname (keys %$kitlist) {
            (my $kitattrs) = $kittab->getAttribs({kitname => $kitname},\@{$xCAT::Schema::tabspec{kit}->{cols}});
            if (!$kitattrs) {
                $callback->({error=>["Cannot find kit \'$kitname\' from the kit table."],errorcode=>[1]});
                return 0;
            }

            $attrs->{kit}->{$kitname}=$kitattrs;
        }

        foreach my $kitreponame (keys %$kitrepolist) {
            (my $kitrepoattrs) = $kitrepotab->getAttribs({kitreponame => $kitreponame},\@{$xCAT::Schema::tabspec{kitrepo}->{cols}});
            if (!$kitrepoattrs) {
                $callback->({error=>["Cannot find kitrepo \'$kitreponame\' from the kitrepo table."],errorcode=>[1]});
                return 0;
            }

            $attrs->{kitrepo}->{$kitreponame}=$kitrepoattrs;
        }

        foreach my $kitcompname (keys %$kitcomplist) {
            (my $kitcompattrs) = $kitcomponenttab->getAttribs({kitcompname => $kitcompname},\@{$xCAT::Schema::tabspec{kitcomponent}->{cols}});
            if (!$kitcompattrs) {
                $callback->({error=>["Cannot find kitcomp \'$kitcompname\' from the kitcomp table."],errorcode=>[1]});
                return 0;
            }

            $attrs->{kitcomp}->{$kitcompname}=$kitcompattrs;
        }

    }

    $attrs = get_files($imagename, $callback, $attrs);
    if($#extra > -1){
        my $ex = get_extra($callback, @extra);
        if($ex){ 
            $attrs->{extra} = $ex;
        }
    }

        #get postscripts
        if ($node) {
        $attrs = get_postscripts($node, $callback, $attrs)
    }

    # if we get nothing back, then we couldn't find the files.  How sad, return nuthin'
    return $attrs;  

}

sub get_postscripts {
    my $node = shift;
    my $errors = 0;
    my $callback = shift;
    my $attrs = shift; 
    my @nodes = noderange($node);
    if (@nodes > 0) { $node = $nodes[0]; }
    else {
    $callback->(
        {error => ["Unable to get postscripts, $node is not a valide node."],errorcode=>1}
        );
    return 0;
    }
    my $postscripts;
    my $postbootscripts;
    my $ptab = new xCAT::Table('postscripts', -create=>1);
    unless($ptab){
    $callback->(
        {error => ["Unable to open table 'postscripts'."],errorcode=>1}
        );
    return 0;
    }
    
    my $ent = $ptab->getNodeAttribs($node, ['postscripts', 'postbootscripts']);
    if ($ent)  
    {
        if ($ent->{postscripts}) { $postscripts = $ent->{postscripts}; }
        if ($ent->{postbootscripts}) { $postbootscripts = $ent->{postbootscripts}; }
    }
    
    (my $attrs1) = $ptab->getAttribs({node => "xcatdefaults"}, 'postscripts', 'postbootscripts');
    if ($attrs1) {
    if ($attrs1->{postscripts}) {
        if ($postscripts) {
        $postscripts = $attrs1->{postscripts} . ",$postscripts";
        } else {
        $postscripts = $attrs1->{postscripts};
        }
    }
    if ($attrs1->{postbootscripts}) {
        if ($postbootscripts) {
        $postbootscripts = $attrs1->{postbootscripts} . ",$postbootscripts";
        } else {
        $postbootscripts = $attrs1->{postbootscripts};
        }
    }
    
    }
    if ($postscripts) {
        $attrs->{postscripts} = $postscripts;
    }
    if ($postbootscripts) {
        $attrs->{postbootscripts} = $postbootscripts;
    }
    return $attrs;
}


# returns a hash of files
# extra {
#   file => dir
#   file => dir
# }

sub get_extra {
    my $callback = shift;
    my @extra = @_;
    my $extra;
    
    # make sure that the extra is formatted correctly:
    foreach my $e (@extra){
        my ($file , $to_dir) = split(/:/, $e);
        unless( -r $file){
            $callback->({error=>["Can not find Extra file $file.  Argument will be ignored"],errorcode=>[1]});
            next;
        }
        #print "$file => $to_dir";
        if (! $to_dir) {
            if (-d $file) {
                $to_dir=$file;
            } else {
                $to_dir=dirname($file);
            }
        }
        push @{ $extra}, { 'src' => $file, 'dest' => $to_dir };
    }   
    return $extra;
}



# well we check to make sure the files exist and then we return them.
sub get_files{
    my $imagename = shift;
    my $errors = 0;
    my $callback = shift;
    my $attrs = shift;  # we'll hopefully get a reference to it and modify this variable.
    my @arr;     # array of directory search paths
    my $template = '';

    # todo is XCATROOT not going to be /opt/xcat/  in normal situations?  We'll always
    # assume it is for now
    my $xcatroot = "/opt/xcat";

    # get the install root
    my $installroot = xCAT::TableUtils->getInstallDir();
    unless($installroot){
        $installroot = '/install';
    }

    my $provmethod = $attrs->{osimage}->{provmethod};
    my $osvers = $attrs->{osimage}->{osvers};
    my $arch = $attrs->{osimage}->{osarch};
    my $profile = $attrs->{osimage}->{profile};

    # here's the case for the install.  All we need at first is the 
    # template.  That should do it.
    if($provmethod =~ /install/){
        @arr = ("$installroot/custom/install", "$xcatroot/share/xcat/install");

        #get .tmpl file
        if (! $attrs->{linuximage}->{template}) {
        my $template = look_for_file('tmpl', $callback, $attrs, @arr);
        unless($template){
            $callback->({error=>["Couldn't find install template for $imagename"],errorcode=>[1]});
            $errors++;
        }else{
            $callback->( {data => ["$template"]});
            $attrs->{linuximage}->{template} = $template;
        }
        }
        $attrs->{media} = "required";
    }


    # for stateless I need to save the 
    # ramdisk
    # the kernel
    # the rootimg.gz
    if($osvers !~ /esx/){
        # don't do anything because these files don't exist for ESX stateless.
        if($provmethod =~ /netboot/){
            # For 's390x', we want all of the image files
            if ($arch =~ /s390x/) {
                my @files;
                my $dir = "$installroot/netboot/$osvers/s390x/$profile";
                opendir(DIR, $dir) or $callback->({error=>["Could not open image files in directory $dir"], errorcode=>[1]});
		
                while (my $file = readdir(DIR)) {
                    # We only want files in the directory that end with .img
                    next unless (-f "$dir/$file");
                    next unless ($file =~ m/\.img$/);
                    push(@files, "$dir/$file");
                }
                
                if (@files) {
                    $attrs->{rawimagefiles}->{files} = [@files];
                }
		
                closedir(DIR);
            }
            else {
                @arr = ("$installroot/custom/netboot", "$xcatroot/share/xcat/netboot");
                #get .pkglist file
                if (! $attrs->{linuximage}->{pkglist}) {
                    # we need to get the .pkglist for this one!
                    my $temp = look_for_file('pkglist', $callback, $attrs, @arr);
                    unless($temp){
                        $callback->({error=>["Couldn't find pkglist file for $imagename"], errorcode=>[1]});
                        $errors++;
                    }else{
                        $attrs->{linuximage}->{pkglist} = $temp;
                    }
                }
		
                @arr = ("$installroot/netboot");
		my $rootimgdir=$attrs->{linuximage}->{rootimgdir};
		my $ramdisk;
                my $kernel;
		my $rootimg;
                # look for ramdisk, kernel and rootimg.gz
		if($rootimgdir) {
	            if (-f "$rootimgdir/initrd-stateless.gz") {
			$ramdisk="$rootimgdir/initrd-stateless.gz";
		    } 
	            if (-f "$rootimgdir/kernel") {
			$kernel="$rootimgdir/kernel";
		    } 
	            if (-f "$rootimgdir/rootimg.gz") {
			$rootimg="$rootimgdir/rootimg.gz";
		    } 
                    	    
		} else {
		    $ramdisk = look_for_file('initrd-stateless.gz', $callback, $attrs, @arr);
		    $kernel = look_for_file('kernel', $callback, $attrs, @arr);
		    $rootimg = look_for_file('rootimg.gz', $callback, $attrs, @arr);
		}
		unless($ramdisk){
		    $callback->({error=>["Couldn't find ramdisk (initrd-stateless.gz) for  $imagename"],errorcode=>[1]});
		    $errors++;
		}else{
		    $attrs->{ramdisk} = $ramdisk;
		}
		    
		unless($kernel){
		    $callback->({error=>["Couldn't find kernel (kernel) for  $imagename"],errorcode=>[1]});
		    $errors++;
		}else{
		    $attrs->{kernel} = $kernel;
		}
		    
		unless($rootimg){
		    $callback->({error=>["Couldn't find rootimg (rootimg.gz) for  $imagename"],errorcode=>[1]});
		    $errors++;
		}else{
		    $attrs->{rootimg} = $rootimg;
		}
	    }
	} elsif ($provmethod =~ /statelite/) {
            @arr = ("$installroot/custom/netboot", "$xcatroot/share/xcat/netboot");
            #get .pkglist file
            if (! $attrs->{linuximage}->{pkglist})  {
                # we need to get the .pkglist for this one!
                my $temp = look_for_file('pkglist', $callback, $attrs, @arr);
                unless($temp){
                    $callback->({error=>["Couldn't find pkglist file for $imagename"],errorcode=>[1]});
                    $errors++;
                }else{
                    $attrs->{linuximage}->{pkglist} = $temp;
                }
            }
        
            @arr = ("$installroot/netboot");
	    my $rootimgdir=$attrs->{linuximage}->{rootimgdir};
	    my $kernel;
            my $ramdisk;
            #look for kernel and ramdisk
	    if($rootimgdir) {
		if (-f "$rootimgdir/kernel") {
		    $kernel="$rootimgdir/kernel";
		} 		
		if (-f "$rootimgdir/initrd-statelite.gz") {
		    $ramdisk="$rootimgdir/initrd-statelite.gz";
		} 
	    } else {
		$kernel = look_for_file('kernel', $callback, $attrs, @arr);
		$ramdisk = look_for_file('initrd-statelite.gz', $callback, $attrs, @arr);
	    }
	    
	    unless($kernel){
		$callback->({error=>["Couldn't find kernel (kernel) for  $imagename"],errorcode=>[1]});
		$errors++;
	    }else{
		$attrs->{kernel} = $kernel;
	    }

	    unless($ramdisk){
		$callback->({error=>["Couldn't find ramdisk (initrd-statelite.gz) for  $imagename"],errorcode=>[1]});
		$errors++;
	    }else{
		$attrs->{ramdisk} = $ramdisk;
	    }
	}
    }
    
    if (( $provmethod =~ /raw/ ) and ( $arch =~ /s390x/ )) {    
        my @files;
        my $dir = "$installroot/raw/$osvers/s390x/$profile";
        opendir(DIR, $dir) or $callback->({error=>["Could not open image files in directory $dir"], errorcode=>[1]});

        while (my $file = readdir(DIR)) {
            # We only want files in the directory that end with .img
            next unless (-f "$dir/$file");
            next unless ($file =~ m/\.img$/);
            push(@files, "$dir/$file");
        }

        if (@files) {
            $attrs->{rawimagefiles}->{files} = [@files];
        }

        closedir(DIR);
    }

    if($errors){
        $attrs = 0;
    }
    return $attrs;
}


# argument:
# type of file:  This is usually the suffix of the file, or the file name.
# attributes:  These are the paramaters you got from the osimage table in a hash.
# @dirs:  Some search paths where we'll start looking for them.
# then we just return a string of the full path to where the file is.
# mostly because we just ooze awesomeness.
sub look_for_file {
    my $file = shift;
    my $callback = shift;
    my $attrs = shift;
    my @dirs = @_;
    my $r_file = '';
    
    my $profile = $attrs->{osimage}->{profile};
    my $arch = $attrs->{osimage}->{osarch};
    my $distname = $attrs->{osimage}->{osvers};
    
    
    # go through the directories and look for the file.  We hopefully will find it...
    foreach my $d (@dirs){
    # widdle down rhel5.4, rhel5., rhel5, rhel, rhe, rh, r, 
    my $dd = $distname; # dd is distro directory, or disco dave, whichever you prefer.
    if($dd =~ /win/){ $dd = 'windows' };
    until(-r "$d/$dd" or not $dd){
        $callback->({data=>["not in  $d/$dd..."]}) if $::VERBOSE;
        chop($dd);  
    }
    if($distname && (($file eq 'tmpl') || ($file eq 'pkglist'))){       
        $callback->({data=>["looking in $d/$dd..."]}) if $::VERBOSE;
        # now look for the file name: foo.rhel5.x86_64.tmpl
        (-r "$d/$dd/$profile.$distname.$arch.$file") && (return "$d/$dd/$profile.$distname.$arch.$file");
        
        # now look for the file name: foo.rhel5.tmpl
        (-r "$d/$dd/$profile.$distname.$file") && (return "$d/$dd/$profile.$distname.$file");
        
        # now look for the file name: foo.x86_64.tmpl
        (-r "$d/$dd/$profile.$arch.$file") && (return "$d/$dd/$profile.$arch.$file");
        
        # finally, look for the file name: foo.tmpl
        (-r "$d/$dd/$profile.$file") && (return "$d/$dd/$profile.$file");
    }else{
        # this may find the ramdisk: /install/netboot/
        (-r "$d/$dd/$arch/$profile/$file") && (return "$d/$dd/$arch/$profile/$file");
    }
    }
    
    # I got nothing man.  Can't find it.  Sorry 'bout that.
    # returning nothing:
    return '';
}


# here's where we make the tarball
sub make_bundle {
    my $imagename = shift;
    my $dest = shift;
    my $remoteHost = shift;
    my $attribs = shift;
    my $callback = shift;
    
    # tar ball is made in local working directory.  Sometimes doing this in /tmp 
    # is bad.  In the case of my development machine, the / filesystem was nearly full.
    # so doing it in cwd is easy and predictable.
    my $dir = shift;
    #my $dir = getcwd;
    
    # get rid of spaces and put in underlines.  
    $imagename =~ s/\s+/_/g;    
    
    
    # we may find that cwd doesn't work, so we use the request cwd.
    my $ttpath = mkdtemp("$dir/imgexport.$$.XXXXXX");
    $callback->({data=>["Creating $ttpath..."]}) if $::VERBOSE;
    my $tpath = "$ttpath/$imagename";
    mkdir("$tpath");
    chmod 0755,$tpath;
    

    #for statelite
    if ($attribs->{osimage}->{provmethod} eq 'statelite') {
    #copy the rootimgdir over
    my $rootimgdir=$attribs->{linuximage}->{rootimgdir};
    if ($rootimgdir) {
        $callback->({data=>["Packing root image. It will take a while"]});
        system("cd $rootimgdir; find rootimg |cpio -H newc -o | gzip -c - > $tpath/rootimgtree.gz");
        $attribs->{'rootimgtree'} = "$rootimgdir/rootimgtree.gz";
    } else {
        $callback->({error=>["Couldn't locate the root image directory. "],errorcode=>[1]});
        return 0;
    }

    #get litefile table setting for the image
    my $lftab= xCAT::Table->new("litefile" ,-create=>1);
    if (!$lftab) {
        $callback->({error=>["Could not open the litefile table."],errorcode=>[1]});
        return 0;
    }

    $callback->({data=>["Getting litefile settings"]});
    my @imageInfo;
        my @imagegroupsattr = ('groups');
        # Check if this image contains osimage.groups attribute.
        # if so, means user wants to use specific directories to this image.
        my $osimagetab = xCAT::Table->new("osimage",-create=>1);
        my $imagegroups = $osimagetab->getAttribs({imagename => $imagename}, @imagegroupsattr);
        if ($imagegroups and $imagegroups->{groups}) {
            # get the directories with no names
            push @imageInfo, $lftab->getAttribs({image => ''}, ('file','options'));
            # get for the image groups specific directories
            push @imageInfo, $lftab->getAttribs({image => $imagegroups->{groups}}, ('file','options'));
            # get for the image specific directories
            push @imageInfo, $lftab->getAttribs({image => $imagename}, ('file','options'));
        } else {
            # get the directories with no names
            push @imageInfo, $lftab->getAttribs({image => ''}, ('file','options'));
            # get the ALL directories
            push @imageInfo, $lftab->getAttribs({image => 'ALL'}, ('file','options'));
            # get for the image specific directories
            push @imageInfo, $lftab->getAttribs({image => $imagename}, ('file','options'));
        }

    open(FILE,">$tpath/litefile.csv") or die "Could not open $tpath/litefile.csv";
    foreach(@imageInfo){
        my $file=$_->{file};
        if(!$file){ next; }
        my $o = $_->{options};
        if(!$o){
        $o = "tmpfs";
        }
        print FILE  "\"$imagename\",\"$file\",\"$o\",,\n";
    }
    close(FILE);
    $attribs->{'litefile'} = "$rootimgdir/litefile.csv";
   }

    #print Dumper($attribs);

    # make manifest.xml file.  So easy!  This is why we like XML.  I didn't like
    # the idea at first though.
    my $xml = new XML::Simple(RootName =>'xcatimage');  
    open(FILE,">$tpath/manifest.xml") or die "Could not open $tpath/manifest.xml";
    print FILE  $xml->XMLout($attribs, noattr => 1, xmldecl => '<?xml version="1.0"?>');
    #print $xml->XMLout($attribs, noattr => 1, xmldecl => '<?xml version="1.0">');
    close(FILE);
    
    
    # these are the only files we copy in.  (unless you have extras)
    for my $a ("kernel", "ramdisk", "rootimg"){
    my $filenames=$attribs->{$a};
    if($filenames) {
        my @file_array=split(',', $filenames);
        foreach my $fn (@file_array) {
            $callback->({data => ["$fn"]});
            if (-r $fn) {
                system("cp $fn $tpath");
            } else {
                $callback->({error=>["Couldn't find file $fn for $imagename. Skip."],errorcode=>[1]});
            }
        }
    }
    }

    for my $a ("template", "pkglist", "otherpkglist", "postinstall", "exlist"){
        my $filenames=$attribs->{linuximage}->{$a};
        if($filenames) {
            my @file_array=split(',', $filenames);
            foreach my $fn (@file_array) {
                $callback->({data => ["$fn"]});
                if (-r $fn) {
                    system("cp $fn $tpath");
                } else {
                    $callback->({error=>["Couldn't find file $fn for $imagename. Skip."],errorcode=>[1]});
                }
            }
        }
    }

    for my $a ("synclists"){
        my $filenames=$attribs->{osimage}->{$a};
        if($filenames) {
            my @file_array=split(',', $filenames);
            foreach my $fn (@file_array) {
                $callback->({data => ["$fn"]});
                if (-r $fn) {
                    system("cp $fn $tpath");
                } else {
                    $callback->({error=>["Couldn't find file $fn for $imagename. Skip."],errorcode=>[1]});
                }
            }
        }
    }
    
    # Copy kit 
    my @kits = keys %{$attribs->{kit}};
    foreach my $kit (@kits) {

        my $values = $attribs->{kit}->{$kit};
        if ( $values->{kitdir} ) {
            my $fn = $values->{kitdir};
            $callback->({data => ["$fn"]});
            if (-r $fn) {
                system("cp -dr $fn $tpath");
            } else {
                $callback->({error=>["Couldn't find file $fn for $imagename. Skip."],errorcode=>[1]});
            }
        }
    }


    # Copy any raw image files. Multiple files can exist (used by s390x)
    if ($attribs->{rawimagefiles}->{files}) {
        foreach my $fromf (@{$attribs->{rawimagefiles}->{files}}) {
            my $rc = system("cp $fromf $tpath");
            if ($rc != 0) {
                $callback->({error=>["Unable to copy the raw image file $fromf."], errorcode=>[1]});
                $rc = system("rm -rf $ttpath");
                if ($rc != 0) {
                    $callback->({error=>["Unable to remove $ttpath."], errorcode=>[1]});
                }
                return 0;
            }
        }
    }
    
    # extra files get copied in the extra directory.
    if($attribs->{extra}){
    mkdir("$tpath/extra");
    chmod 0755,"$tpath/extra";
    foreach(@{ $attribs->{extra} }){
        my $fromf = $_->{src};
        print " $fromf\n";
        if(-d $fromf ){
            print "fromf is a directory";
            mkpath("$tpath/extra/$fromf");
            `cp -a $fromf/* $tpath/extra/$fromf/`;
        }else{
            `cp $fromf $tpath/extra`;
        }
    }
    }
    
    # If this is an export to a remote host then split the destination into the 
    # remote directory portion and the name of the export bundle.
    my $remoteDest;
    if (defined $remoteHost) {
        $remoteDest = $dest;
        if (defined $dest) {
            $dest = (split( '/', $dest))[-1];
        }
    }
    
    # now get right below all this stuff and tar it up.
    chdir($ttpath);
    $callback->( {data => ["Inside $ttpath."]});
    unless($dest){ 
        $dest = "$dir/$imagename.tgz";
    }
    
    # if no absolute path specified put it in the cwd
    unless($dest =~ /^\//){
	    $dest = "$dir/$dest";			
    }
    
    $callback->( {data => ["Compressing $imagename bundle.  Please be patient."]});
    my $rc;
    if($::VERBOSE){
        $callback->({data => ["tar czvf $dest . "]});   
        $rc = system("tar czvf $dest . ");  
    }else{
        $rc = system("tar czf $dest . ");   
    }
    $callback->({data => ["Done!"]});
    
    if($rc) {
        # An error occurred during tar to create the image bundle.
        $callback->({error=>["Failed to compress archive!  (Maybe there was no space left?)"],errorcode=>[1]});
        if (-e $dest) {
            # Remove the partially created image bundle.
            $rc = system("rm $dest");
            if ($rc) {
                $callback->({error=>["Failed to clean up image bundle $dest"], errorcode=>[1]});
            }
        }
    } else {
        # The image bundle was created.
        # If remotehost was specified then move the image bundle off xCAT MN to the remote host.
        if (defined $remoteHost) {
            my $remoteFile = $remoteHost . ':' . $remoteDest;
            
            $callback->({data=>["Moving the image bundle to the remote system"]});
            $rc = system("/usr/bin/scp -B $dest $remoteFile");
            if ($rc) {
                $callback->({error=>["Unable to copy the image bundle to the remote host"], errorcode=>[1]});
            }
            
            # Remove the image bundle that was sent to the remote system.
            $rc = system("rm $dest");
            if ($rc) {
                $callback->({error=>["Failed to clean up image bundle $dest"], errorcode=>[1]});
            }
        }
    }
    
    chdir($dir);    
    $rc = system("rm -rf $ttpath");
    if ($rc) {
        $callback->({error=>["Failed to clean up temp space $ttpath"],errorcode=>[1]});
        return;
    }   
}

sub extract_bundle {
    my $request = shift;
    #print Dumper($request);
    my $callback = shift;
    my $nodes=shift;
    my $new_profile=shift;
    my $remoteHost = shift;
    
    @ARGV = @{ $request->{arg} };
    my $xml;
    my $data;
    my $datas;
    my $error = 0;
    
    my $bundle = shift @ARGV;
    
    # extract the image in temp path in cwd
    my $dir = $request->{cwd}; #getcwd;
    $dir = $dir->[0];
    #print Dumper($dir);
    
    # If we have a remote file then move it to the xCAT MN
    if (defined $remoteHost) {
        # Create unique directory for the bundle and copy the bundle to it
        my $remoteFile = "$remoteHost:$bundle";
        $dir = `/bin/mktemp -d /var/tmp/XXXXXX`;
        chomp($dir);
        $bundle = $dir . '/' . (split( '/', $bundle))[-1];
        $callback->({data=>["Obtaining the image bundle from the remote system"]});
        my $rc = system("/usr/bin/scp -v -B $remoteFile $dir");
        if ($rc != 0) {
            $callback->({error=>["Unable to copy the image bundle from the remote host"], errorcode=>[1]});
            $rc = rmtree $dir;
            if (! $rc) {
                $callback->({error=>["Failed to clean up directory containing the remote image bundle $bundle"], errorcode=>[1]});
            }
            return;
        }
    } else {
        # When we are not doing a remote copy, we need to verify the bundle exists and find its exact location
        unless(-r $bundle){
            $bundle = "$dir/$bundle";
        }
        
        unless(-r $bundle){
            $callback->({error => ["Cannot find $bundle"], errorcode=>[1]});
            return;
        }
    }
    
    if ($::VERBOSE) {
        if ($bundle =~ m/^\//) {
            # Bundle name began with a slash
            $callback->({data=>["Bundle file is located at $bundle"]});
        } else {
            my $pwd=cwd();
            $callback->({data=>["Bundle file is located at $pwd/$bundle"]});
        }
    }
    
    my $tpath = mkdtemp("$dir/imgimport.$$.XXXXXX");
    
    $callback->({data=>["Unbundling image..."]});
    my $rc;
    if ($::VERBOSE) {
        $callback->({data=>["tar zxvf $bundle -C $tpath"]});
        $rc = system("tar zxvf $bundle -C $tpath");
    } else {
        $rc = system("tar zxf $bundle -C $tpath");
    }
    
    if ($rc) {
        $callback->({error => ["Failed to extract bundle $bundle"],errorcode=>[1]});
    }
    
    # get all the files in the tpath.  These should be all the image names.
    my @files = < $tpath/* >;
    # go through each image directory.  Find the XML and put it into the array.  If there are any 
    # errors then the whole thing is over and we error and leave.
    foreach my $imgdir (@files){
    unless(-r "$imgdir/manifest.xml"){
        $callback->({error=>["Failed to find manifest.xml file in image bundle"],errorcode=>[1]});
        if (defined $remoteHost) {
            $rc = rmtree $dir;
            if ( ! $rc ) {
                $callback->({error=>["Failed to clean up directory containing the remote image bundle $bundle"], errorcode=>[1]});
            }
        }
        return;
    }
    $xml = new XML::Simple;
    # get the data!
    # put it in an eval string so that it 
    $data = eval { $xml->XMLin("$imgdir/manifest.xml") };
    if($@){
        $callback->({error=>["invalid manifest.xml file inside the bundle.  Please verify the XML"],errorcode=>[1]});
        #my $foo = $@;
        #$foo =~ s/\n//;
        #$callback->({error=>[$foo],errorcode=>[1]});
        #foreach($@){
        #   last;
        #}
        # If this was an import from a remote host then remove the directory created for the remote files.
        # We do not want to leave files hanging around that were brought from another system.
        if (defined $remoteHost) {
            $rc = rmtree $dir;
            if ( ! $rc ) {
                $callback->({error=>["Failed to clean up directory containing the remote image bundle $bundle"], errorcode=>[1]});
            }
        }
        return;
    }
    #print Dumper($data);
    #push @{$datas}, $data;


    #support imgimport osimage exported by xCAT 2.7
    manifest_adapter($data);

    
    # now we need to import the files...
    unless(verify_manifest($data, $callback)){
        $error++;
        next;       
    }
    
    # check media first
    unless(check_media($data, $callback)){
        $error++;
        next;       
    }

    #change profile name if needed
    if ($new_profile) {
        $data=change_profile($data, $callback, $new_profile, $imgdir);
    }
    
    #import manifest.xml into xCAT database
    unless(set_config($data, $callback)){
        $error++;
        next;
    }
    
    # now place files in appropriate directories.
    unless(make_files($data, $imgdir, $callback)){
        $error++;
        next;
    }

    #for kit stuff,create symlink between kitrepodir to otherpkgdir
    unless(create_symlink($data,$callback)){
        $error++;
        next;
    } 
    # put postscripts in the postsctipts table
    if ($nodes) {
        unless(set_postscripts($data, $callback, $nodes)){
        $error++;
        next;
        }
    }
        
    my $osimage = $data->{osimage}->{imagename};    
    $callback->({data=>["Successfully imported the image $osimage."]});
    }
    
    # remove temp file only if there were no problems.
    unless($error){
        $rc = system("rm -rf $tpath");
        if ($rc) {
            $callback->({error=>["Failed to clean up temp space $tpath"],errorcode=>[1]});
            return;
        }   
    }

    # If this was an import from a remote host then remove the directory created for the remote files.
    # We do not want to leave files hanging around that were brought from another system.
    if ( defined $remoteHost ) {
        $rc = rmtree $dir;
        if ( ! $rc ) {
            $callback->({error=>["Failed to clean up directory containing the remote image bundle $bundle"],errorcode=>[1]});
        }
    }
}

sub change_profile {
    my $data = shift;   
    my $callback = shift;
    my $new_profile=shift;
    my $srcdir=shift;

    my $old_profile= $data->{osimage}->{profile};
    if ($old_profile eq $new_profile) { 
        return $data; #do nothing if old profile is the same as the new one. 
    }

    $data->{osimage}->{profile}=$new_profile;
    my $installdir = xCAT::TableUtils->getInstallDir();
    unless($installdir){
    $installdir = '/install';
    }
    if ($data->{linuximage}->{rootimgdir}) {
        $data->{linuximage}->{rootimgdir}="$installdir/netboot/" . $data->{osimage}->{osvers} . "/" . $data->{osimage}->{osarch} . "/$new_profile";
    
        for my $a ("kernel", "ramdisk", "rootimg", "rootimgtree", "litefile") {
            if ($data->{$a}) {
                my $fn=basename($data->{$a});
                $data->{$a}=$data->{linuximage}->{rootimgdir} . "/$fn";
            }
        }
    }

    my $prov="netboot";
    if ($data->{osimage}->{provmethod} eq "install") { $prov = "install"; }
    my $platform;
    my $os=$data->{osimage}->{osvers};
    if ($os) {
      if ($os =~ /rh.*/)    { $platform = "rh"; }
      elsif ($os =~ /centos.*/) { $platform = "centos"; }
      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
      elsif ($os =~ /sles.*/) { $platform = "sles"; }
      elsif ($os =~ /SL.*/) { $platform = "SL"; }
      elsif ($os =~ /win/)  {$platform = "windows"; }
      elsif ($os =~ /ubuntu*/) {$platform = "ubuntu"; }
    }

    
    for my $a ("template", "pkglist", "synclists", "otherpkglist", "postinstall", "exlist")   {
        my $filenames=$data->{linuximage}->{$a};
        if ($a eq "synclists") { 
            $filenames=$data->{osimage}->{$a}; 
        }
        if($filenames) {
            my @file_array=split(',', $filenames);
            my @new_file_array=();
            foreach my $old (@file_array) {
            my $oldfn=basename($old);
            my $olddir=dirname($old);       
            my $newfn;
            my $newdir;
                    #if source file is from /opt/xcat/share..., 
            #then copy it to /install/custom... directory. 
                    #Otherwise, copy the file in the same directory
            if ($olddir =~ /$::XCATROOT\/share\/xcat/) {
                $newdir="$installdir/custom/$prov/$platform";
            } else {
                $newdir=$olddir;
            }
                    #if the file name contains the old profile name, 
                    #replace it with the new profile name.
                    #Otherwise prefix the old file name with the new profile name. 
            if ($oldfn =~ /$old_profile/) {
                $newfn=$oldfn;
                $newfn =~ s/$old_profile/$new_profile/;
            } else {
                $newfn="$new_profile.$oldfn";
            }
    
            move("$srcdir/$oldfn", "$srcdir/$newfn");
            push (@new_file_array, "$newdir/$newfn");
            }
            if ($a eq "synclists") {
                $data->{osimage}->{$a} = join(',', @new_file_array);
            } else {
                $data->{linuximage}->{$a} = join(',', @new_file_array);
            }
        }
    }

    #change the image name
    my $new_imgname=$data->{osimage}->{osvers} . "-" . $data->{osimage}->{osarch} . "-" . $data->{osimage}->{provmethod} . "-$new_profile";
    $data->{osimage}->{imagename}=$new_imgname;
    $data->{linuximage}->{imagename}=$new_imgname;

    return $data;
}

# return 1 for true 0 for false.
# need to make sure media is copied before importing image.
sub check_media {
    my $data = shift;   
    my $callback = shift;   
    my $rc = 0;
    unless( $data->{'media'}) {
        $rc = 1;
    }elsif($data->{media} eq 'required'){
        my $os = $data->{osimage}->{osvers};
        my $arch = $data->{osimage}->{osarch};
        my $installroot = xCAT::TableUtils->getInstallDir();
        unless($installroot){
            $installroot = '/install';
        }
        unless(-d "$installroot/$os/$arch"){
            $callback->({error=>["This image requires that you first copy media for $os-$arch"],errorcode=>[1]});
        }else{
            $rc = 1;
        }
    }
    return $rc;
}


sub set_postscripts {
    my $data = shift;
    my $callback = shift;
    my $nodes=shift;

    $callback->({data=>["Adding postscripts."]});

    my @good_nodes=noderange($nodes);

    if (@good_nodes > 0) {
        my @missed = nodesmissed();
        if (@missed > 0) {
            $callback->({warning => ["The following nodes will be skipped because they are not in the nodelist table.\n  " . join(',', @missed)],errorcode=>1});
        }
    } else {
        $callback->({error => ["The nodes $nodes are not defined in xCAT DB."],errorcode=>1});
        return 0;
    }

    my $ptab = xCAT::Table->new('postscripts',-create => 1,-autocommit => 0);
    unless($ptab){
        $callback->({error => ["Unable to open table 'postscripts'"],errorcode=>1});
        return 0;
    }


    # get xcatdefaults settings
    my @a1=();
    my @a2=();
    (my $attrs1) = $ptab->getAttribs({node => "xcatdefaults"}, 'postscripts', 'postbootscripts');
    if ($attrs1) {
        if ($attrs1->{postscripts}) {
            @a1=split(',', $attrs1->{postscripts});
        }
        if ($attrs1->{postbootscripts}) {
            @a2=split(',', $attrs1->{postbootscripts});
        }
    }    

    #remove the script if it is already in xcatdefaults
    my @a3=();
    my @a4=();
    my $postscripts = $data->{postscripts};
    my $postbootscripts = $data->{postbootscripts};
    if ($postscripts) { @a3 = split(',', $postscripts); }
    if ($postbootscripts) { @a4 = split(',', $postbootscripts); }

    my @a30;
    my @a40;
    if (@a1>0 && @a3>0) {
        foreach my $tmp1 (@a3) {
            if (! grep /^$tmp1$/, @a1) {
                push(@a30, $tmp1);
            }
        }
        $postscripts=join(',', @a30);
    }
    if (@a2>0 && @a4>0) {
        foreach my $tmp2 (@a4) {
            if (! grep /^$tmp2$/, @a2) {
                push(@a40, $tmp2);
            }
        }
        $postbootscripts=join(',', @a40);
    }
    
    #now save to the db
    my %keyhash;
    if ($postscripts || $postbootscripts) {
        $keyhash{postscripts} = $postscripts;
        $keyhash{postbootscripts} = $postbootscripts;
        $ptab->setNodesAttribs(\@good_nodes, \%keyhash );
        $ptab->commit;
    }

    return 1;
}


sub create_symlink {
    my $data = shift;
    my $callback = shift;
    my $otherpkgdir = $data->{linuximage}->{otherpkgdir};
    my @kitcomps=split(',',$data->{osimage}->{kitcomponents});

    my %tabs = ();
    my @tables = qw(kit kitrepo kitcomponent);
    foreach my $t ( @tables ) {
        $tabs{$t} = xCAT::Table->new($t,-create => 1,-autocommit => 1);

        if ( !exists( $tabs{$t} )) {
            my %rsp;
            push@{ $rsp{data} }, "Could not open xCAT table $t";
            xCAT::MsgUtils->message( "E", \%rsp, $callback );
            return 1;
        }
    }


    if ( defined($otherpkgdir) ) {

         # Create otherpkgdir if it doesn't exist
         unless ( -d "$otherpkgdir" ) {
         mkpath("$otherpkgdir");
         }

         if ( $data and $data->{osimage} and $data->{osimage}->{kitcomponents} ) {   
               foreach my $kitcomponent ( @kitcomps ){                           
                   (my $kitcomptable) = $tabs{kitcomponent}->getAttribs({kitcompname => $kitcomponent}, 'kitreponame');
                   if ( $kitcomptable and $kitcomptable->{'kitreponame'}){
                     
                           # Create symlink if doesn't exist
                           unless ( -d "$otherpkgdir/$kitcomptable->{'kitreponame'}" ) {
                           (my $kitrepotable) = $tabs{kitrepo}->getAttribs({kitreponame => $kitcomptable->{'kitreponame'}}, 'kitrepodir');
                           if ( $kitrepotable and $kitrepotable->{'kitrepodir'}){
                                  system("ln -sf $kitrepotable->{'kitrepodir'} $otherpkgdir/$kitcomptable->{'kitreponame'}");
                           } else {
                                  $callback->({error => ["Cannot open kitrepo table or kitrepodir do not exist"],errorcode=>[1]});
                                  next ;
                                              }
                           }
                    } else {
                           $callback->({error => ["Cannot open kitcomponent table or kitreponame do not exist"],errorcode=>[1]});
                           next;
                    }
              } 
          } else {
              $callback->({error => ["osimage table or kitcomponent do not exist"],errorcode=>[1]});
              return 1;
          }
     } 
     return 1;
            

}

sub set_config {
    my $data = shift;
    my $callback = shift;
    my $ostab = xCAT::Table->new('osimage',-create => 1,-autocommit => 0);
    my $linuxtab = xCAT::Table->new('linuximage',-create => 1,-autocommit => 0);
    my $kittab = xCAT::Table->new('kit',-create => 1,-autocommit => 0);
    my $kitrepotab = xCAT::Table->new('kitrepo',-create => 1,-autocommit => 0);
    my $kitcomptab = xCAT::Table->new('kitcomponent',-create => 1,-autocommit => 0);
    my %keyhash;
    my $osimage = $data->{osimage}->{imagename};

    unless($ostab){
        $callback->({error => ["Unable to open table 'osimage'"],errorcode=>1});
        return 0;
    }

	unless($linuxtab){
		$callback->({error => ["Unable to open table 'linuximage'"],errorcode=>1});
		return 0;
	}

    unless($kittab){
        $callback->({error => ["Unable to open table 'kit'"],errorcode=>1});
        return 0;
    }

    unless($kitrepotab){
        $callback->({error => ["Unable to open table 'kitrepo'"],errorcode=>1});
        return 0;
    }

    unless($kitcomptab){
        $callback->({error => ["Unable to open table 'kitcomponent'"],errorcode=>1});
        return 0;
    }

    $callback->({data=>["Adding $osimage"]}) if $::VERBOSE;

    # now we make a quick hash of what we want to put into this 
    my $hash_tmp=$data->{osimage};
    foreach my $key (keys %$hash_tmp) {
        $keyhash{$key}=$hash_tmp->{$key};
    }
        $ostab->setAttribs({imagename => $osimage }, \%keyhash );
        $ostab->commit;

    %keyhash=();
    my $hash_tmp1=$data->{linuximage};
    foreach my $key (keys %$hash_tmp1) {
        $keyhash{$key}=$hash_tmp1->{$key};
    }

    $linuxtab->setAttribs({imagename => $osimage }, \%keyhash );
    $linuxtab->commit;

    my $kit = $data->{kit};
    foreach my $k (keys %$kit) { 
        my $kithash = $kit->{$k};
        %keyhash=();
        foreach my $key (keys %$kithash){
            $keyhash{$key} = $kithash->{$key};
        }
        $kittab->setAttribs({kitname => $k }, \%keyhash );
        $kittab->commit;
    }

    my $kitrepo = $data->{kitrepo};
    foreach my $k (keys %$kitrepo) {
        my $kitrepohash = $kitrepo->{$k};
        %keyhash=();
        foreach my $key (keys %$kitrepohash){
            $keyhash{$key} = $kitrepohash->{$key};
        }
        $kitrepotab->setAttribs({kitreponame => $k }, \%keyhash );
        $kitrepotab->commit;
    } 

    my $kitcomp = $data->{kitcomp};
    foreach my $k (keys %$kitcomp) {
        my $kitcomphash = $kitcomp->{$k};
        %keyhash=();
        foreach my $key (keys %$kitcomphash){
            $keyhash{$key} = $kitcomphash->{$key};
        }
        $kitcomptab->setAttribs({kitcompname => $k }, \%keyhash );
        $kitcomptab->commit;
    }

    return 1;
}

#an adapter to convert the manifest structure from 2.7 to 2.8
sub manifest_adapter {
    my $data = shift;

    if(exists($data->{osimage}) or exists($data->{linuximage})){
       return 0;
    }

    my %colstodel;
    foreach my $col (@{$xCAT::Schema::tabspec{osimage}->{cols}}){
       if(defined($data->{$col})){
          $colstodel{$col}=1;
          $data->{osimage}->{$col}=$data->{$col};
       }
    }

    foreach my $col (@{$xCAT::Schema::tabspec{linuximage}->{cols}}){
       if(defined($data->{$col})){
          $colstodel{$col}=1;
          $data->{linuximage}->{$col}=$data->{$col};
       }
    }

    foreach my $col (keys %colstodel){
       delete($data->{$col});
    }

    return 1;
}


sub verify_manifest {
    my $data = shift;
    my $callback = shift;
    my $errors = 0;

    # first make sure that the stuff is defined!
    # For certain fields that are used in later construction of directory structure,
    # we trim whitespace which can occur in some versions of the xml processing. 
    unless($data->{osimage}->{imagename}){
        $callback->({error=>["The 'imagename' field is not defined in manifest.xml."],errorcode=>[1]});
        $errors++;
    }
    $data->{osimage}->{imagename} =~ s/^\s*(\S*)\s*$/$1/;
    
    unless($data->{osimage}->{provmethod}){
        $callback->({error=>["The 'provmethod' field is not defined in manifest.xml."],errorcode=>[1]});
        $errors++;
    }
    $data->{osimage}->{provmethod} =~ s/^\s*(\S*)\s*$/$1/;
    
    unless($data->{osimage}->{profile}){
        $callback->({error=>["The 'profile' field is not defined in manifest.xml."],errorcode=>[1]});
        $errors++;
    }
    $data->{osimage}->{profile} =~ s/^\s*(\S*)\s*$/$1/;
    
    unless($data->{osimage}->{osvers}){
        $callback->({error=>["The 'osvers' field is not defined in manifest.xml."],errorcode=>[1]});
        $errors++;
    }
    $data->{osimage}->{osvers} =~ s/^\s*(\S*)\s*$/$1/;
    
    unless($data->{osimage}->{osarch}){
        $callback->({error=>["The 'osarch' field is not defined in manifest.xml."],errorcode=>[1]});
        $errors++;
    }
    $data->{osimage}->{osarch} =~ s/^\s*(\S*)\s*$/$1/;
    
    unless($data->{osimage}->{provmethod} =~ /install|netboot|statelite|raw/){
        $callback->({error=>["Importing images with 'provemethod' " . $data->{osimage}->{provmethod} . " is not supported. Hint: install, netboot, statelite, or raw"],errorcode=>[1]});
        $errors++;
    }
    $data->{osimage}->{provmethod} =~ s/^\s*(\S*)\s*$/$1/;

    # if the install method is used, then we need to have certain files in place.
    if($data->{osimage}->{provmethod} =~ /install/){
        # we need to get the template for this one!
        unless($data->{linuximage}->{template}){
            $callback->({error=>["The 'osarch' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
        #$attrs->{media} = "required"; (need to do something to verify media!

    }elsif($data->{osimage}->{osvers} =~ /esx/){
        $callback->({info => ['this is an esx image']});
        # do nothing for ESX
        1;
    } elsif (($data->{osimage}->{provmethod} =~ /netboot/) and ($data->{osimage}->{osarch} !~ /s390x/)) {
        unless($data->{ramdisk}){
            $callback->({error=>["The 'ramdisk' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
        unless($data->{kernel}){
            $callback->({error=>["The 'kernel' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
        unless($data->{rootimg}){
            $callback->({error=>["The 'rootimg' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
    
    }elsif($data->{osimage}->{provmethod} =~ /statelite/){
        unless($data->{kernel}){
            $callback->({error=>["The 'kernel' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
        unless($data->{ramdisk}){
            $callback->({error=>["The 'ramdisk' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
        unless($data->{'rootimgtree'}){
            $callback->({error=>["The 'rootimgtree' field is not defined in manifest.xml."],errorcode=>[1]});
            $errors++;
        }
    
    }       
    
    if($errors){
        # we had problems, error and exit.
        return 0;
    }
    # returning 1 means everything went good!   
    return 1;
}

sub make_files {
    my $data = shift;
    my $imgdir = shift;
    my $callback = shift;
    my $os = $data->{osimage}->{osvers};
    my $arch = $data->{osimage}->{osarch};
    my $profile = $data->{osimage}->{profile};
    my $installroot = xCAT::TableUtils->getInstallDir();
    unless($installroot){
        $installroot = '/install';
    }
    
    # you'll get a hash like this for install:
    #$VAR1 = { 
    #          osimage=> {
    #              'imagename' => 'Default_Stateful',
    #              'provmethod' => 'install',
    #              'profile' => 'all',
    #              'osarch' => 'x86_64',
    #              'osvers' => 'centos5.4'
    #              'synclists' => '/opt/xcat/share/xcat/install/centos/all.othetpkgs.synclist',
    #          }
    #          linuxiage=> {
    #              'template' => '/opt/xcat/share/xcat/install/centos/all.tmpl',
    #              'pkglist' => '/opt/xcat/share/xcat/install/centos/all.pkglist',
    #              'otherpkglist' => '/opt/xcat/share/xcat/install/centos/all.othetpkgs.pkglist',
    #              'imagename' => 'Default_Stateful',
    #          }
    #          'media' => 'required',
    #        };
    
    # data will look something like this for netboot:
    #$VAR1 = { 
    #          'ramdisk' => '/install/netboot/centos5.4/x86_64/compute/initrd-stateless.gz',
    #          'rootimg' => '/install/netboot/centos5.4/x86_64/compute/rootimg.gz'
    #          'kernel' => '/install/netboot/centos5.4/x86_64/compute/kernel',
    #          osimage=> {
    #              'imagename' => 'Default_Stateless_1265981465',
    #              'osvers' => 'centos5.4',
    #              'osarch' => 'x86_64',
    #              'provmethod' => 'netboot',
    #              'profile' => 'compute',
    #              'synclists' => '/opt/xcat/share/xcat/install/centos/compute.othetpkgs.synclist',
    #          }
    #          linuximage=> {
    #              'imagename' => 'Default_Stateless_1265981465',
    #              'pkglist' => '/opt/xcat/share/xcat/install/centos/compute.pkglist',
    #              'otherpkglist' => '/opt/xcat/share/xcat/install/centos/compute.othetpkgs.pkglist',
    #              'exlist' => '/opt/xcat/share/xcat/install/centos/compute.exlist',
    #              'postinstall' => '/opt/xcat/share/xcat/install/centos/compute.postinstall',
    #          }
    #          'extra' => [
    #                     { 
    #                       'dest' => '/install/custom/netboot/centos',
    #                       'src' => '/opt/xcat/share/xcat/netboot/centos/compute.centos5.4.pkglist'
    #                     },
    #                     { 
    #                       'dest' => '/install/custom/netboot/centos',
    #                       'src' => '/opt/xcat/share/xcat/netboot/centos/compute.exlist'
    #                     }
    #                   ],
    #        };
    # data will look something like this for statelite:
    #$VAR1 = { 
    #          'ramdisk' => '/install/netboot/centos5.4/x86_64/compute/initrd-statelite.gz',
    #          'kernel' => '/install/netboot/centos5.4/x86_64/compute/kernel',
    #          'rootimgtree' => '/install/netboot/centos5.4/x86_64/compute/rootimg/rootimgtree.gz'
    #          osimage=> {
    #              'osvers' => 'centos5.4',
    #              'osarch' => 'x86_64',
    #              'imagename' => 'Default_Stateless_1265981465',
    #              'provmethod' => 'statelite',
    #              'profile' => 'compute',
    #               'synclists' => '/opt/xcat/share/xcat/install/centos/compute.othetpkgs.synclist',
    #          }
    #          linuximage=> {
    #              'imagename' => 'Default_Stateless_1265981465',
    #              'pkglist' => '/opt/xcat/share/xcat/install/centos/compute.pkglist',
    #              'otherpkglist' => '/opt/xcat/share/xcat/install/centos/compute.othetpkgs.pkglist',

    #              'exlist' => '/opt/xcat/share/xcat/install/centos/compute.exlist',
    #              'postinstall' => '/opt/xcat/share/xcat/install/centos/compute.postinstall',
    #          }
    #          'extra' => [
    #                     { 
    #                       'dest' => '/install/custom/netboot/centos',
    #                       'src' => '/opt/xcat/share/xcat/netboot/centos/compute.centos5.4.pkglist'
    #                     },
    #                     { 
    #                       'dest' => '/install/custom/netboot/centos',
    #                       'src' => '/opt/xcat/share/xcat/netboot/centos/compute.exlist'
    #                     }
    #                   ],
    #        };
    
    for my $a ("kernel", "ramdisk", "rootimg", "rootimgtree", "litefile") {
        my $filenames=$data->{$a};
        if($filenames) {
            my @file_array=split(',', $filenames);
            foreach my $fn (@file_array) {
            $callback->({data => ["$fn"]});
            my $basename=basename($fn);
            my $dirname=dirname($fn);
            if (! -r $dirname) {
                mkpath("$dirname", { verbose => 1, mode => 0755 });
            } 
            if (-r $fn) {
                $callback->( {data => ["  Moving old $fn to $fn.ORIG."]});
                move("$fn", "$fn.ORIG");
            }
            move("$imgdir/$basename",$fn);
            }
        }
    }

    for my $a ("template", "pkglist", "synclists", "otherpkglist", "postinstall", "exlist") {
        my $filenames;
        if ($a eq "synclists") {
             $filenames=$data->{osimage}->{$a};
        } else {
            $filenames=$data->{linuximage}->{$a};
        }
        if($filenames) {
            my @file_array=split(',', $filenames);
            foreach my $fn (@file_array) {
            $callback->({data => ["$fn"]});
            my $basename=basename($fn);
            my $dirname=dirname($fn);
            if (! -r $dirname) {
                mkpath("$dirname", { verbose => 1, mode => 0755 });
            } 
            if (-r $fn) {
                $callback->( {data => ["  Moving old $fn to $fn.ORIG."]});
                move("$fn", "$fn.ORIG");
            }
            move("$imgdir/$basename",$fn);
            }
        }
    }

    # unpack kit
    my $k = $data->{kit};
    foreach my $kit (keys %$k) {
        my $fn = $k->{$kit}->{kitdir};
        if ($fn) {
            my $dirname = dirname($fn);
            if (! -r $dirname) {
                mkpath("$dirname", { verbose => 1, mode => 0755 });
            }

            if (-r "$dirname/$kit") {
                $callback->( {data => ["  Moving old $fn to $fn.ORIG."]});
                move("$dirname/$kit", "$dirname/$kit.ORIG");
            
            }
            move("$imgdir/$kit","$dirname/$kit");
            #copy postscripts from kit dir to postscripts dir;
            copyPostscripts($dirname,$kit,$installroot,$callback);
            #copy plugin from kit to xCAT_plugin
            movePlugin($dirname,$kit,$callback);
        }
    }
    if ( $hasplugin ) {
    # Issue xcatd reload to load the new plugins
         system("/etc/init.d/xcatd restart");
         $hasplugin=0;
    }

    #unpack the rootimgtree.gz for statelite
    my $fn=$data->{'rootimgtree'};
    if($fn) {
        if (-r $fn) {
            my $basename=basename($fn);
            my $dirname=dirname($fn);
            #print "dirname=$dirname, basename=$basename\n";
            $callback->({data => ["Extracting rootimgtree.gz. It will take a while."]});
            system("mkdir -p $dirname; cd $dirname; zcat $basename |cpio -idum; rm $basename");
        }
    }
       
    if($data->{extra}){
        # have to copy extras
        print "copying extras\n" if $::VERBOSE;
        #if its just a hash then there is only one entry.
        if (ref($data->{extra}) eq 'HASH'){
            my $ex = $data->{extra};
            #my $f = basename($ex->{src});
            my $ff = $ex->{src};
            my $dest = $ex->{dest};
            unless(moveExtra($callback, $ff, $dest, $imgdir)){
                return 0;
            }
            # if its an array go through each item.
        }else{
            foreach(@{ $data->{extra} }) {
                #my $f = basename($_->{src});
                my $ff = $_->{src};
                my $dest = $_->{dest};
                unless(moveExtra($callback, $ff, $dest, $imgdir)){
                    return 0;
                }
            }
        }
    }

    
    #litefile table for statelite
    if ($data->{osimage}->{provmethod} eq 'statelite') {
        $callback->( {data => ["Updating the litefile table."]});
        my $fn=$data->{litefile};
        if (!$fn) {
            $callback->({error=>["Could not find liefile.csv."],errorcode=>[1]});
            return 1;
        } elsif (! -r $fn) {
            $callback->({error=>["Could not find $fn."],errorcode=>[1]});
            return 1;
        }
    
        my $lftab= xCAT::Table->new("litefile" ,-create=>1);
    	if (!$lftab) {
    	    $callback->({error=>["Could not open the litefile table."],errorcode=>[1]});
    	    return 0;
    	}
        open(FILE,"$fn") or die "Could not open $fn.";
    	foreach my $line (<FILE>) {
    	    chomp($line);
    	    print "$line\n";
    	    my @tmp=split('"', $line);
    	    my %keyhash;
    	    my %updates;
    	    $keyhash{image}=$data->{osimage}->{imagename};
    	    $keyhash{file}=$tmp[3];
    	    $updates{options}=$tmp[5];
    	    $lftab->setAttribs(\%keyhash, \%updates );
    	}
    	close(FILE);
        $lftab->commit;

    	$callback->( {data => ["The litetree and statelite talbes are untouched. You can update them if needed."]});
    } 
    
    # For s390x copy all image files from the root bundle directory to the repository location
    if (($data->{osimage}->{osarch} =~ /s390x/) && (($data->{osimage}->{provmethod} =~ /raw/) || ($data->{osimage}->{provmethod} =~ /netboot/))) {
        my $reposImgDir = "$installroot/$data->{osimage}->{provmethod}/$data->{osimage}->{osvers}/$data->{osimage}->{osarch}/$data->{osimage}->{profile}";
        mkpath($reposImgDir);
        
        if($data->{rawimagefiles}) {
            $callback->({data=>["Copying image files to $reposImgDir"]});
            
            my $rif = $data->{rawimagefiles};
            my $files = $rif->{files};
            if (ref($files) eq 'ARRAY') {
                foreach(@$files) {
                    my $old_file = basename($_);
                    my ($suffix) = $old_file =~ /(\.[^.]+)$/;
                    if ($suffix ne ".img") {
                        $suffix = ".img";
                    } else {
                        $suffix = "";
                    }
                    
                    $callback->({data=>["Moving $old_file to $reposImgDir as $old_file$suffix"]});
                    my $rc = move("$imgdir/$old_file", "$reposImgDir/$old_file$suffix");
                    if ($rc == 0) {
                        $callback->({error=>["Could not move $old_file to $reposImgDir: $!\n"], errorcode=>[1]});
                        return 0;
                    }
                }
            } else {
                my $old_file = basename($files);
                my ($suffix) = $old_file =~ /(\.[^.]+)$/;
                if ($suffix ne ".img") {
                    $suffix = ".img";
                } else {
                    $suffix = "";
                }
                
                $callback->({data=>["Moving $old_file to $reposImgDir as $old_file$suffix"]});
                my $rc = move( "$imgdir/$old_file", "$reposImgDir/$old_file$suffix" );
                if ($rc == 0) {
                     $callback->({error=>["Could not move $old_file to $reposImgDir: $!\n"], errorcode=>[1]});
                     return 0;
                }
            } 
        }
    }
    
    # return 1 meant everything was successful! 
    return 1;
}

sub copyPostscripts{
    my $dirname=shift;
    my $kit=shift;
    my $installdir = shift;
    my $callback = shift;
    my $fenv='\.env$';
    my $fexlist='\.exlist$';

    if ( -d "$dirname/$kit/other_files/") {
         opendir(DIRP,"$dirname/$kit/other_files/");
         foreach my $f (readdir(DIRP)) {
             if (($f=~m/^\./) || ($f =~ /$fexlist/i) || ($f =~ m/$fenv/i)) {
                  next;
             } else {
                  print "$f\n";
                  chmod(0755,"$dirname/$kit/other_files/$f");
                  system("cp -rfv $dirname/$kit/other_files/$f $installdir/postscripts/");
             }
         }

    closedir(DIRP);
    }
}

sub movePlugin {

    my $dirname=shift;
    my $kit=shift;
    my $callback=shift;

    if( -d "$dirname/$kit/plugins/") {
        chmod(644, "$dirname/$kit/plugins/*");
        opendir(DIR,"$dirname/$kit/plugins/");
        if ( grep { ($_ ne '.') && ($_ ne '..') } readdir(DIR) ) {
             system("cp -rfv $dirname/$kit/plugins/* $::XCATROOT/lib/perl/xCAT_plugin/");
             $hasplugin = 1;
         }
        closedir(DIR);
    } 

}

sub moveExtra {
    my $callback = shift;
    my $ff = shift;
    my $dest = shift;
    my $imgdir = shift; 
    my $f = basename($ff);
    
    if(-d "$imgdir/extra/$ff"){
        #print "This is a directory\n";
        # this extra file is a directory, so we are moving the directory over.
        $callback->( {data => ["$dest"]});
        unless(-d $dest){
            unless(mkpath($dest)){
                $callback->({error=>["Failed to create $dest"], errorcode => 1});
                return 0;
            }
        }
        # this could cause some problems.  This is one of the reasons we may not want to 
        # allow copying of directories.  
        `cp -a -f $imgdir/extra/$ff/* $dest`;
        if($?){
            $callback->({error=>["Failed to cp -a $imgdir/extra/$ff/* to $dest"], errorcode => 1});
            return 0;
        }    
    }else{
        #print "This is a file\n";
        # this extra file is a file and we can just copy to the destination.
        $callback->( {data => ["$dest/$f"]}) ;
        if(-r "$dest/$f"){
            $callback->({data => ["  Moving old $dest/$f to $dest/$f.ORIG."]}); 
            move("$dest/$f", "$dest/$f.ORIG");
        }
        `cp $imgdir/extra/$f $dest`;
        if ($?) {
            $callback->( {error=>["Failed to copy $imgdir/extra/$f to $dest"], errorcode => 1});
            return 0;
        }
    }
    return 1;
}

