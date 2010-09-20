package xCAT_plugin::litetree;
use xCAT::NodeRange;
use Data::Dumper;
use xCAT::Utils;
use Sys::Syslog;
use xCAT::GlobalDef;
use xCAT::Table;
use Getopt::Long;
use xCAT::SvrUtils;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

use strict;
# synchonize files and directories from mulitple sources. 

# object is to return a list of files to be syncronized.
# requesting them.  By default we will do read-write files.


my $syncdirTab = "litetree";
my $syncfileTab = "litefile";
my $synclocTab = "statelite";
my $errored = 0;


sub handled_commands {
	# command is syncmount, syncdir is the perl module to use.
	return {
		litetree => "litetree",
		litefile => "litetree",
		ilitefile => "litetree",
		lslite => "litetree"
	}
}

sub usage {
	my $command = shift;
	my $callback = shift;
	my $error = shift;
	my $msg;	
	if($command eq "ilitefile"){
		$msg = "Usage: ilitefile <imagename>
\texample:\n\tilitefile centos5.3-x86_64-statelite-compute"
	} elsif($command eq "litefile") {
        $msg = "Usage: litefile <noderange>\nexample:\n\tlitefile node1";
   	} elsif($command eq "litetree") {
        $msg = "Usage: litetree <noderange>\nexample:\n\tlitetree node1";
    } else{
		$msg = "some general usage string";
	}

	if($error){
		$callback->({error=>[$msg],errorcode=>[$error]});
	}else{
		$callback->({info=>[$msg]});
	}
}

sub process_request {
	my $request = shift;
	my $callback = shift;
	my $noderange;
	my $image;
	# the request can come from node or some one running command
	# on xCAT mgmt server
	# argument could also be image...

	# if request comes from user:
	if($request->{node}){
		$noderange = $request->{node};
		
	# if request comes from node post script .awk file.
	}elsif($request->{'_xcat_clienthost'}){
		my @nodenames = noderange($request->{'_xcat_clienthost'}->[0].",".$request->{'_xcat_clientfqdn'}->[0]);
        if (@nodenames) {
    		$noderange = \@nodenames;
            $request->{node} = $noderange;
        }
	}else{
		$callback->({error=>["Well Kemosabi, I can't figure out who you are."],errorcode=>[1]});
		return;
	}

	my $command = $request->{command}->[0];
	if($command eq "litetree"){
        unless($request->{node}) {
            usage($command, $callback, 0);
            return 1;
        }
		return syncmount("dir",$request,$callback,$noderange);
	}elsif($command eq "litefile"){
		unless($request->{node}) {
            usage($command, $callback, 0);
            return 1;
        }
        return syncmount("file",$request, $callback,$noderange);
	}elsif($command eq "ilitefile"){
			#print Dumper($request);
			unless($request->{arg}){
				usage($command, $callback, 0);
				return 1;
			}
			return syncmount("image",$request, $callback,$request->{arg});
	}elsif($command eq "lslite"){
	    if (defined $noderange)
	    {
	        &lslite($request, $callback, $noderange);
	    }
	    else
	    {
	        &lslite($request, $callback, undef);
	    }
	    return;
	}else{
		$callback->({error=>["error in code..."], errorcode=>[127]});
		$request = {};
		return;
	}
	
}


sub syncmount {	
	my $syncType = shift;
	my $request = shift;
	my $callback = shift;
	# deterimine which node is calling this 
	# then find out what directories to use.
	my $noderange = shift;
	my @nodes = @{$noderange};
	my $tab;
	if($syncType eq 'dir'){
		$tab = xCAT::Table->new($syncdirTab,-create=>1);
	}elsif($syncType =~ /file|image/ ){
		$tab = xCAT::Table->new($syncfileTab,-create=>1);
	}elsif($syncType =~ /location/){
	    $tab = xCAT::Table->new($synclocTab,-create=>1);
	}else{
		$callback->({error=>["error in code..."], errorcode=>[127]});
		$request = {};
		return;
	}
	my $ostab;
	my %osents;
	unless($syncType =~ /image/){
		$ostab = xCAT::Table->new('nodetype');
		%osents = %{$ostab->getNodesAttribs(\@nodes,['profile','os','arch','provmethod'])};
	}
	foreach my $node (@nodes){
	    # node may be an image...
	    my $image;
	    my $ent;
	    if($syncType !~ /image/){
			$ent = $osents{$node}->[0];

			if (xCAT::Utils->isAIX()) {
				$image=$ent->{provmethod};
			} else {
		
				unless($ent->{os} && $ent->{arch} && $ent->{profile}){
					$callback->({error=>["$node does not have os, arch, or profile defined in nodetype table"],errorcode=>[1]});
					$request = {};
					next;
				}

                if ((!$ent->{provmethod}) ||  ($ent->{provmethod} eq 'statelite') || ($ent->{provmethod} eq 'netboot') || ($ent->{provmethod} eq 'install')) {
					$image = $ent->{os} . "-" . $ent->{arch} . "-statelite-" . $ent->{profile};
				} elsif (($ent->{provmethod} ne 'netboot') && ($ent->{provmethod} ne 'install')) {
					$image=$ent->{provmethod};
				}
			}
		} else {
			$image=$node;
		}
    	my $fData = getNodeData($syncType,$node,$image,$tab,$callback);	
    	# now we go through each directory and search for the file.
    	showSync($syncType,$callback, $node, $fData);	
	}	
}

# In most cases the syncdir will be on the management node so 
# want to make sure its not us before we mount things.
sub showSync {
	my $syncType = shift; # dir or file	
	my $callback = shift;
	my $node = shift;
	my $dirs = shift;
	my $mnts;
	my $first;
	#print Dumper($dirs);
	# go through each directory in priority order
	#mkdir "/mnt/xcat";
	if($syncType eq "dir"){

		foreach my $priority (sort {$a <=> $b} keys %$dirs){
			# split the nfs server up from the directory:
			my $mntpnt;
			my ($server, $dir) = split(/:/,$dirs->{$priority});

			# if server is blank then its the directory:
			unless($dir){
				$dir = $server;
				$server = '';	
			}

			if(grep /\$|#CMD/, $dir){
				$dir = xCAT::SvrUtils->subVars($dir,$node,'dir',$callback);
				$dir =~ s/\/\//\//g;
			}
			$first = $dir;
			$first =~ s!\/([^/]*)\/.*!$1!;

			if($server){
				if(grep /\$/, $server){
					$server = xCAT::SvrUtils->subVars($server,$node,'server',$callback);
				}
		
				$mntpnt = $server . ":";
				# we have a server and need to make sure we can mount them under unique names
				if($mnts->{$first} eq '' ){  # if the first mount point doesn't have a server then leave it.
					$mnts->{$first} = $server;
				}
			}	
			$mntpnt .= $dir;
			# ok, now we have all the mount points.  Let's go through them all?
			if ($::from_lslite == 1)
			{
			    $callback->({info => "        $priority, $mntpnt"});
			}
			else
			{
    			    $callback->({info => "$node: $mntpnt"});
			}
		}

	}elsif($syncType =~ /file|image/){
		foreach my $file (sort keys %$dirs){
			my $options	= $dirs->{$file};
			# persistent,rw
			my $out;
			if ($::from_lslite == 1)
			{
    			    $out = sprintf("        %-13s %s", $options, $file);
			}
			else
			{
    			    $out = sprintf("%s: %-13s %s", $node, $options, $file);
			}
			
			$callback->({info => $out});
		}
	}elsif($syncType =~ /location/){
	    foreach my $node (sort keys %$dirs){
            my $location = $dirs->{$node};

            my ($server, $dir) = split(/:/, $location);

            if(grep /\$|#CMD/, $dir)
            {
                $dir = xCAT::SvrUtils->subVars($dir,$node,'dir',$callback);
                $dir =~ s/\/\//\//g;
            }

            if(grep /\$/, $server)
            {
                $server = xCAT::SvrUtils->subVars($server,$node,'server',$callback);
            }

            $location = $server . ":" . $dir;
            	
            if ($::from_lslite == 1)
            {
                $callback->({info => "        $location"});
            }
            else
            {
                $callback->({info => "$node: $location"});
            }
        }
    }

}

# get all the directories or files for given image related to this node.
sub getNodeData {
	my $type = shift;
	my $node = shift;
	my $image = shift;
	my $tab = shift;	
	my $cb = shift;  # callback to print messages!!
	# the image name will be something like rhels5.4-x86_64-nfsroot
	#my $image;
	#unless($type =~ /image/){
	#	$image = $ent->{os} . "-" . $ent->{arch} . "-statelite-" . $ent->{profile};
	#}else{
	#	$image = $node;
	#}

	my @imageInfo;
	my @attrs;
	if($type eq "dir"){
		@attrs = ('priority', 'directory');
	}elsif($type =~ /file|image/){
		@attrs = ('file','options');
	}elsif($type =~ /location/){
	    @attrs = ('node','statemnt');
	}else{
		print "Yikes! error in the code litefile;getNodeData!";
		exit 1;
	}

	if ($type eq "location")
	{
	    # get locations with specific nodes
	    push @imageInfo, $tab->getAttribs({node => $node}, @attrs);

	    if (!defined $imageInfo[0])
	    {
	        # maybe node belongs to nodegroup
	        # try to find it in groups
	        my @tmpnodes = join(',', $node);

	        # group info in nodelist tab
	        my $nltab  = xCAT::Table->new('nodelist');
            my $nltabdata = $nltab->getNodesAttribs(\@tmpnodes, ['node', 'groups']);

            my $data = $nltabdata->{$node}->[0];
	        my @grps = split(',', $data->{groups});
	        foreach my $g (@grps)
	        {
	            chomp $g;
	            my $info = $tab->getAttribs({node => $g}, @attrs);
	            if(defined $info)
	            {
    	            push @imageInfo, $info; 
	            }

	            # return once get one record
	            last if (defined $imageInfo[1]);
	        }	        
	    }
	}
	else
	{
        # get the directories with no names
        push @imageInfo, $tab->getAttribs({image => ''}, @attrs);
        # get the ALL directories
        push @imageInfo, $tab->getAttribs({image => 'ALL'}, @attrs);
        # get for the image specific directories
        push @imageInfo, $tab->getAttribs({image => $image}, @attrs);
	}
	# pass back a reference to the directory

	# now we need to sort them
	return mergeArrays($type,\@imageInfo,$cb);
}

sub mergeArrays {
	my $type = shift; # file or dir?
	my $arr = shift; # array of info from the tables.
	my $cb = shift;  # callback routine
	my $attrs;
	if($type eq "dir"){
		foreach(@$arr){
			if($_->{directory} eq ''){ next; }
			$attrs->{$_->{priority}} = $_->{directory};
		}
	}elsif($type =~ /file|image/){
		foreach(@$arr){
			next if($_->{file} eq '');
			my $o = $_->{options};
            $o = "tempfs" unless ($o);
			# TODO: put some logic in here to make sure that ro is alone.
			# if type is ro and con, then this is wrong silly!
			#if($p eq "ro" and $t eq "con"){
			#	my $f = $_->{file};
			#	$cb->({info => "#skipping: $f.  not allowed to be ro and con"});
			#	next;
			#}
			$attrs->{$_->{file}} = $o;
		}
	}elsif($type =~ /location/){
	    foreach(@$arr)
	    {
	        if($_->{statemnt} eq '') {next;}
	        $attrs->{$_->{node}} = $_->{statemnt};
	    }
	
	}else{
		print "Yikes!  Error in the code in mergeArrays!\n";
		exit 1;
	}
	#print "mergeArrays...\n";
	#print Dumper($attrs);
	return $attrs;
}

#----------------------------------------------------------------------------

=head3  lslite_usage

=cut

#-----------------------------------------------------------------------------

sub lslite_usage
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}},
      "\n  lslite - Display a summary of the statelite information \n\t\tthat has been defined for a noderange or an image.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tlslite [-h | --help]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}}, "\tlslite [-V | --verbose] [-i imagename] | [noderange]";
    
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

sub lslite {
    my $request = shift;
    my $callback = shift;
    my $noderange = shift;
    my @image;
    $::from_lslite = 1; # to control the output format

    unless($request->{arg} || defined $noderange)
    {
        &lslite_usage($callback);
        return 1;
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    Getopt::Long::Configure("bundling");
    
    if ($request->{arg})
    {
        @ARGV = @{$request->{arg}};
        
        if (
            !GetOptions(
                        'h|help'    => \$::HELP,
                        'i=s'       => \$::OSIMAGE,
                        'V|verbose' => \$::VERBOSE,
            )
          )
        {
            &lslite_usage($callback);
            return 1;
        }
    }

    if ($::HELP)
    {
        &lslite_usage($callback);
        return 0;
    }
    
    # handle "lslite -i image1"
    # use the logic for ilitefile
    if ($::OSIMAGE)
    {
        # make sure the osimage is defined
        my @imglist = xCAT::DBobjUtils->getObjectsOfType('osimage');
        if (!grep(/^$::OSIMAGE$/, @imglist))
        {
            $callback->({error=>["The osimage named \'$::OSIMAGE\' is not defined."],errorcode=>[1]});
            return 1;
        }
        
        @image = join(',', $::OSIMAGE);
        syncmount("image", $request, $callback, \@image);
        return 0;
    }

    # handle "lslite node1"
    my @nodes;
    if (defined $noderange)
    {
        @nodes = @{$noderange};
        
        if (scalar @nodes)
        {
            # get node's osimage/profile
            my $nttab  = xCAT::Table->new('nodetype');
            my $nttabdata = $nttab->getNodesAttribs(\@nodes, ['node', 'profile', 'os', 'arch', 'provmethod']);
        
            foreach my $node (@nodes)
            {
                my $image;
                my $data = $nttabdata->{$node}->[0];

                if (xCAT::Utils->isAIX())
                {
                    if (defined ($data->{provmethod}))
                    {
                        $image = $data->{provmethod};
                    }
                    else
                    {
                        $callback->({error=>["no provmethod defined for node $node."],errorcode=>[1]});
                    }
                }
                else
                {
                    if ((!$data->{provmethod}) ||  ($data->{provmethod} eq 'statelite') || ($data->{provmethod} eq 'netboot') || ($data->{provmethod} eq 'install')) 
                    {
                        $image = $data->{os} . "-" . $data->{arch} . "-statelite-" . $data->{profile};
                    }
                    else
                    {
                        $image = $data->{provmethod};
                    }                
                }

                $callback->({info => ">>>Node: $node\n"});
                $callback->({info => "Osimage: $image\n"});

                # structure node as ARRAY
                my @tmpnode = join(',', $node);

                my @types = ("location", "file", "dir");
                foreach my $type (@types)
                {
                    if($type eq "location")
                    {
                        # show statelite table
                        $callback->({info => "Persistent directory (statelite table):"});                    }
                    elsif($type eq "file")
                    {
                        # show litefile table
                        $callback->({info => "Litefiles (litefile table):"});
                    }
                    elsif($type eq "dir")
                    {
                        # show litetree table
                        $callback->({info => "Litetree path (litetree table):"});
                    }
                    else
                    {
                        $callback->({error=>["Invalid type."],errorcode=>[1]});
                        return 1;
                    }

                    syncmount($type, $request, $callback, \@tmpnode);  
                    $callback->({info => "\n"});
                }
            }
        }
    }

return;

}

1;
#vim: set ts=2

