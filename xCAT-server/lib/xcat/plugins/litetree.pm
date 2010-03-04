package xCAT_plugin::litetree;
use xCAT::NodeRange;
use Data::Dumper;
use xCAT::Utils;
use Sys::Syslog;
use xCAT::GlobalDef;
use xCAT::Table;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

use strict;
# synchonize files and directories from mulitple sources. 

# object is to return a list of files to be syncronized.
# requesting them.  By default we will do read-write files.


my $syncdirTab = "litetree";
my $syncfileTab = "litefile";
my $errored = 0;


sub handled_commands {
	# command is syncmount, syncdir is the perl module to use.
	return {
		litetree => "litetree",
		litefile => "litetree",
		ilitefile => "litetree"
	}
}

sub usage {
	my $command = shift;
	my $callback = shift;
	my $error = shift;
	my $msg;	
	if($command eq "ilitefile"){
		$msg = "ilitefile <imagename>
\texample:\n\tilitefile centos5.3-x86_64-compute"
	}	else{
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
		$noderange = noderange($request->{'_xcat_clienthost'}.",".$request->{'_xcat_clientfqdn'});
	}else{
		$callback->({error=>["Well Kemosabi, I can't figure out who you are."],errorcode=>[1]});
		return;
	}

	if(!$noderange){
		my $usage_string="Missing Noderange\n";
		$callback->({error=>[$usage_string],errorcode=>[1]});
		$request = {};
		return;
	}

	my $command = $request->{command}->[0];
	if($command eq "litetree"){
		return syncmount("dir",$request,$callback,$noderange);
	}elsif($command eq "litefile"){
		return syncmount("file",$request, $callback,$noderange);
	}elsif($command eq "ilitefile"){
			#print Dumper($request);
			unless($request->{arg}){
				usage($command, $callback,1);
				return 1;
			}
			return syncmount("image",$request, $callback,$request->{arg});
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
				$dir = subVar($dir,$node,'dir',$callback);
				$dir =~ s/\/\//\//g;
			}
			$first = $dir;
			$first =~ s!\/([^/]*)\/.*!$1!;

			if($server){
				if(grep /\$/, $server){
					$server = subVar($server,$node,'server',$callback);
				}
		
				$mntpnt = $server . ":";
				# we have a server and need to make sure we can mount them under unique names
				if($mnts->{$first} eq '' ){  # if the first mount point doesn't have a server then leave it.
					$mnts->{$first} = $server;
				}else{
					# they may just have the name in twice:
					unless($server eq $mnts->{$first}){ 
						my $msg = "# " . $mnts->{$first} . " and $server both mount /$first.  This not supported.";
						$callback->({info => $msg});
						return;	
					}else{
						$mntpnt = "";  # only mount it once, so get rid of the directory
					}
				}
			}	
			$mntpnt .= $dir;
			# ok, now we have all the mount points.  Let's go through them all?
			$callback->({info => "$node: $mntpnt"});
		}

	}elsif($syncType =~ /file|image/){
		foreach my $file (sort keys %$dirs){
			my $options	= $dirs->{$file};
			# persistent,rw
			my $out = sprintf("%s: %-13s %s", $node, $options, $file);
			$callback->({info => $out});
		}
	}

}

# some directories will have xCAT database values, like:
# $nodetype.os.  If that is the case we need to open up
# the database and look at them.  We need to make sure
# we do this sparingly...  We don't like tons of hits
# to the database.
sub subVar {
	my $dir = shift;
	my $node = shift;
	my $type = shift;
	my $callback = shift;
	# parse all the dollar signs...	
	# if its a directory then it has a / in it, so you have to parse it.
	# if its a server, it won't have one so don't worry about it.
	my @arr = split("/", $dir);
	my $fdir = "";
	foreach my $p (@arr){
		# have to make this geric so $ can be in the midle of the name: asdf$foobar.sitadsf
		if($p =~ /\$/){
			my $pre;
			my $suf;
			my @fParts;
			if($p =~ /([^\$]*)([^# ]*)(.*)/){
				$pre= $1;
				$p = $2;
				$suf = $3;
			}
			# have to sub here:
			# get rid of the $ sign.
			foreach my $part (split('\$',$p)){
				if($part eq ''){ next; }
				#$callback->({error=>["part is $part"],errorcode=>[1]});
				# check if p is just the node name:
				if($part eq 'node'){
					# it is so, just return the node.
					#$fdir .= "/$pre$node$suf";
					push @fParts, $node;
				}else{
					# ask the xCAT DB what the attribute is.
					my ($table, $col) = split('\.', $part);
					unless($col){ $col = 'UNDEFINED' };
					my $tab = xCAT::Table->new($table);
					unless($tab){
						$callback->({error=>["$table does not exist"],errorcode=>[1]});
						return;
					}
					my $ent;
					my $val;
					if($table eq 'site'){
						$val = $tab->getAttribs( { key => "$col" }, 'value' );
 						$val = $val->{'value'};
					}else{
						$ent = $tab->getNodeAttribs($node,[$col]);		
						$val = $ent->{$col};
					}
					unless($val){
						# couldn't find the value!!
						$val = "UNDEFINED"
					}
					push @fParts, $val;
				}	
			}
			my $val = join('.', @fParts);
			if($type eq 'dir'){
					$fdir .= "/$pre$val$suf";
			}else{
					$fdir .= $pre . $val . $suf;
			}
		}else{
			# no substitution here
			$fdir .= "/$p";
		}
	}	
	# now that we've processed variables, process commands
	# this isn't quite rock solid.  You can't name directories with #'s in them.
	if($fdir =~ /#CMD=/){	
		my $dir;
		foreach my $p (split(/#/,$fdir)){
			if($p =~ /CMD=/){
				$p =~ s/CMD=//;
				my $cmd = $p;
				#$callback->({info=>[$p]});
				$p = `$p 2>&1`;
				chomp($p);
				#$callback->({info=>[$p]});
				unless($p){
					$p = "#CMD=$p did not return output#";
				}
			}
			$dir .= $p;
		}
		$fdir = $dir;	
	}

	return $fdir;
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
		@attrs = ['priority', 'directory'];
	}elsif($type =~ /file|image/){
		@attrs = ['file','options'];
	}else{
		print "Yikes! error in the code litefile;getNodeData!";
		exit 1;
	}
	# get the directories with no names
	push @imageInfo, $tab->getAttribs({image => ''}, @attrs);
	# get the ALL directories
	push @imageInfo, $tab->getAttribs({image => 'ALL'}, @attrs);
	# get for the image specific directories
	push @imageInfo, $tab->getAttribs({image => $image}, @attrs);
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
			if($_->{file} eq ''){ next; }
			my $o = $_->{options};
			if(!$o){
				$o = "tmpfs,rw";
			}
			# TODO: put some logic in here to make sure that ro is alone.
			# if type is ro and con, then this is wrong silly!
			#if($p eq "ro" and $t eq "con"){
			#	my $f = $_->{file};
			#	$cb->({info => "#skipping: $f.  not allowed to be ro and con"});
			#	next;
			#}
			$attrs->{$_->{file}} = $o;
		}
	}else{
		print "Yikes!  Error in the code in mergeArrays!\n";
		exit 1;
	}
	#print "mergeArrays...\n";
	#print Dumper($attrs);
	return $attrs;
}

1;
#vim: set ts=2

