# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::prescripts;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
require xCAT::Table;
require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::ServiceNodeUtils;
require xCAT::MsgUtils;
use Getopt::Long;
use Sys::Hostname;
use Time::HiRes qw(gettimeofday sleep);
use POSIX "WNOHANG";


1;

#-------------------------------------------------------
=head3  handled_commands
Return list of commands handled by this plugin
=cut
#-------------------------------------------------------

sub handled_commands
{
    return {
	runbeginpre => "prescripts",
	runendpre => "prescripts"
    };
}

#-------------------------------------------------------
=head3  preprocess_request
  Check and setup for hierarchy 
=cut
#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $cb  = shift;

    #if already preprocessed, go straight to request
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $req_nodes   = $req->{node};
    if (!$req_nodes) { return;}

    my @nodes;
    my $command  = $req->{command}->[0];
    my $column;
    if    ($command eq 'runbeginpre') { $column = 'begin'; }
    elsif ($command eq 'runendpre')   { $column = 'end'; }
    else  { $column = ''; }

    # See if anything in the prescripts table for the nodes.  If not, skip. 
    #   Nothing to do.
    my $tab = xCAT::Table->new('prescripts');
    #first check if xcatdefaults entry
    if ( $tab->getAttribs({node=>"xcatdefaults"},$column) ) {
        # yes - process all nodes
        @nodes = @$req_nodes;
    } else {
        # no xcatdefaults, check for node entries
        my $tabdata=$tab->getNodesAttribs($req_nodes,['node', $column]);
        if ($tabdata) {
            foreach my $node (@$req_nodes) {
                if (($tabdata->{$node}) &&
                    ($tabdata->{$node}->[0]) &&
                    ($tabdata->{$node}->[0]->{$column}) )  {
                    push (@nodes,$node);
                }
            }
        }
    }
    
    # if no nodes left to process, we are done
    if (! @nodes) { return; }

    my $service = "xcat";
    my @args=();
    if (ref($req->{arg})) {
	@args=@{$req->{arg}};
    } else {
	@args=($req->{arg});
    }
    @ARGV = @args;

    #print "prepscripts: preprocess_request get called, args=@args, nodes=@$nodes\n";
    
    #use Getopt::Long;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    GetOptions('l'  => \$::LOCAL);
    my $sn = xCAT::ServiceNodeUtils->getSNformattedhash(\@nodes, $service, "MN");
    my @requests;
    if ($::LOCAL) { #only handle the local nodes
        #print "process local nodes: @$nodes\n";
        #get its own children only
	my @hostinfo=xCAT::NetworkUtils->determinehostname();
	my %iphash=();
	foreach(@hostinfo) {$iphash{$_}=1;}

        my @children=();
        foreach my $snkey (keys %$sn)  {
	    if (exists($iphash{$snkey})) {
                my $tmp=$sn->{$snkey};
		@children=(@children,@$tmp); 
	    }
	}
        if (@children > 0) {
	    my $reqcopy = {%$req};
	    $reqcopy->{node} = \@children;
	    $reqcopy->{'_xcatdest'} = $hostinfo[0];
	    $reqcopy->{_xcatpreprocessed}->[0] = 1;
	    push @requests, $reqcopy;
	    return \@requests;
	}
    } else { #run on mn and need to dispatch the requests to the service nodes
        #print "dispatch to sn\n";
	# find service nodes for requested nodes
	# build an individual request for each service node
	# find out the names for the Management Node
	foreach my $snkey (keys %$sn)
	{
	    my $reqcopy = {%$req};
	    $reqcopy->{node} = $sn->{$snkey};
	    $reqcopy->{'_xcatdest'} = $snkey;
	    $reqcopy->{_xcatpreprocessed}->[0] = 1;
	    push @requests, $reqcopy;
	    
	}   # end foreach
	return \@requests;
    }
    return; 
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $rsp      = {};

    if ($command eq "runbeginpre")
    {
        runbeginpre($nodes, $request, $callback);
    }
    else
    {
        if ($command eq "runendpre")
        {
            runendpre($nodes, $request, $callback)
        }
        else
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "Unknown command $command.  Cannot process the command.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return;
        }
    }
}

#-------------------------------------------------------
=head3  runbeginpre
   Runs all the begin scripts defined in prescripts.begin column for the give nodes.
=cut
#-------------------------------------------------------
sub runbeginpre
{
    my ($nodes, $request, $callback) = @_;
    my $args     = $request->{arg};
    my $action=$args->[0];
    my $localhostname=hostname();
    my $installdir = xCAT::TableUtils->getInstallDir();
 
    my %script_hash=getprescripts($nodes, $action, "begin");
    foreach my $scripts (keys %script_hash) {
	my $runnodes=$script_hash{$scripts};
        if ($runnodes && (@$runnodes>0)) {
	    my $runnodes_s=join(',', @$runnodes);

	    #now run the scripts 
	    my @script_array=split(',', $scripts);
            foreach my $s (@script_array) {
		my $rsp = {};
		$rsp->{data}->[0]="$localhostname: Running begin script $s for nodes $runnodes_s.";
		$callback->($rsp);

                #check if the script need to be invoked for each node in parallel. 
                #script must contian a line like this in order to be run this way: #xCAT setting: MAX_INSTANCE=4
                #where 4 is the maximum instance at a time
                my $max_instance=0; 
                my $ret=`grep -E '#+xCAT setting: *MAX_INSTANCE=' $installdir/prescripts/$s`;
                if ($? == 0) {
		   $max_instance=`echo "$ret" | cut -d= -f2`; 
                   chomp($max_instance);
		}
                
                if ($max_instance > 0) {
		    #run the script for each node in paralell, no more than max_instance at a time
		    run_script_single_node($installdir, $s,$action,$max_instance,$runnodes,$callback);
		} else { 
		    undef $SIG{CHLD};
                    #pass all the nodes to the script, only invoke the script once
		    my $ret=`NODES=$runnodes_s ACTION=$action $installdir/prescripts/$s 2>&1`;
		    my $err_code=$?/256;
		    if ($err_code != 0) {
			my $rsp = {};
			$rsp->{error}->[0]="$localhostname: $s: return code=$err_code. Error message=$ret";
			$callback->($rsp);
                        if ($err_code > 1) { return $err_code; }
		    } else {
			if ($ret) {
			    my $rsp = {};
			    $rsp->{data}->[0]="$localhostname: $s: $ret";
			    $callback->($rsp);
			}
		    }
		}
	    }
	}
    } 
    return; 
}

#-------------------------------------------------------
=head3  runendpre
   Runs all the begin scripts defined in prescripts.begin column for the give nodes.
=cut
#-------------------------------------------------------
sub runendpre
{
    my ($nodes, $request, $callback) = @_;

    my $args= $request->{arg};
    my $action=$args->[0];
    my $localhostname=hostname();
    my $installdir = xCAT::TableUtils->getInstallDir();

    my %script_hash=getprescripts($nodes, $action, "end");
    foreach my $scripts (keys %script_hash) {
	my $runnodes=$script_hash{$scripts};
        if ($runnodes && (@$runnodes>0)) {
	    my $runnodes_s=join(',', @$runnodes);
            my %runnodes_hash=();

	    #now run the scripts 
	    my @script_array=split(',', $scripts);
            foreach my $s (@script_array) {
		my $rsp = {};
		$rsp->{data}->[0]="$localhostname: Running end script $s for nodes $runnodes_s.";
		$callback->($rsp);

                #check if the script need to be invoked for each node in parallel. 
                #script must contian a line like this in order to be run this way: #xCAT setting: MAX_INSTANCE=4
                #where 4 is the maximum instance at a time
                my $max_instance=0; 
                my $ret=`grep -E '#+xCAT setting: *MAX_INSTANCE=' $installdir/prescripts/$s`;
                if ($? == 0) {
		   $max_instance=`echo "$ret" | cut -d= -f2`; 
                   chomp($max_instance);
		}
                
                if ($max_instance > 0) {
		    #run the script for each node in paralell, no more than max_instance at a time
		    run_script_single_node($installdir, $s,$action,$max_instance,$runnodes,$callback);
		} else { 
		    undef $SIG{CHLD};
		    my $ret=`NODES=$runnodes_s ACTION=$action $installdir/prescripts/$s 2>&1`;
		    my $err_code=$?/256;
		    if ($err_code != 0) {
			my $rsp = {};
			$rsp->{error}->[0]="$localhostname: $s: return code=$err_code. Error message=$ret";
			$callback->($rsp);
                        if ($err_code > 1) { return $err_code; }
		    } else {
			if ($ret) {
			    my $rsp = {};
			    $rsp->{data}->[0]="$localhostname: $s: $ret";
			    $callback->($rsp);
			}
		    }
		}
	    }
	}
    }

    return;
}

#-------------------------------------------------------
=head3  getprescripts
   get the prescripts for the given nodes and actions
=cut
#-------------------------------------------------------
sub getprescripts
{
    my ($nodes, $tmp_action, $colname) = @_;
    my @action_a=split('=',$tmp_action);
    my $action=$action_a[0]; 

    my %ret=();
    if ($nodes && (@$nodes>0)) {
	my $tab = xCAT::Table->new('prescripts',-create=>1);  
        #first get xcatdefault column
	my $et = $tab->getAttribs({node=>"xcatdefaults"},$colname);
	my $tmp_def = $et->{$colname};
	my $defscripts;
	if ($tmp_def) {
	    $defscripts=parseprescripts($tmp_def, $action);
	}

        #get scripts for the given nodes and 
	#add the scripts from xcatdefault in front of the other scripts
	my $tabdata=$tab->getNodesAttribs($nodes,['node', $colname]); 
	foreach my $node (@$nodes) {
	    my $scripts_to_save=$defscripts;
            my %lookup=(); #so that we do not have to parse the same scripts more than once
	    if ($tabdata && exists($tabdata->{$node}))  {
		my $tmp=$tabdata->{$node}->[0];
		my $scripts=$tmp->{$colname};
		if ($scripts) {
		    #parse the script. it is in the format of netboot:s1,s2|install:s3,s4 or just s1,s2
		    if (!exists($lookup{$scripts})) {
			my $tmp_s=parseprescripts($scripts, $action);
			$lookup{$scripts}=$tmp_s;
			$scripts=$tmp_s;
		    } else {
			$scripts=$lookup{$scripts};
		    }
		    #add the xcatdefaults
		    if ($scripts_to_save && $scripts) {
			$scripts_to_save .= ",$scripts"; 
		    } else {
			if ($scripts) { $scripts_to_save=$scripts; }
		    }
		}
	    }
	    
            #save to the hash
	    if ($scripts_to_save) {
		if (exists($ret{$scripts_to_save})) {
		    my $pa=$ret{$scripts_to_save};
		    push(@$pa, $node);
		}
		else {
		    $ret{$scripts_to_save}=[$node];
		}
	    }
	}
    }
    return %ret;
}

#-------------------------------------------------------
=head3  parseprescripts
   Parse the prescript string and get the scripts for the given action out
=cut
#-------------------------------------------------------
sub  parseprescripts
{
    my $scripts=shift;
    my $action=shift;
    my $ret;
    if ($scripts) {
	if ($scripts =~ /:/) {
            my @a=split(/\|/,$scripts);
            foreach my $token (@a) {
                #print "token=$token, action=$action\n";
	        if ($token =~ /^$action:(.*)/) {
		    $ret=$1;
                    last;
	        }
            }   
	} else {
	    $ret=$scripts;
	}
    }
    return $ret;
}


#-------------------------------------------------------
=head3  run_script_single_node
   
=cut
#-------------------------------------------------------
sub  run_script_single_node
{
    my $installdir=shift; #/install
    my $s=shift;  #script name
    my $action=shift;
    my $max=shift;  #max number of instances to be run at a time
    my $nodes=shift; #nodes to be run
    my $callback=shift; #callback
    
    my $children=0;
    my $localhostname=hostname();
    
    foreach my $node ( @$nodes ) {
	$SIG{CHLD} = sub { my $pid = 0; while (($pid = waitpid(-1, WNOHANG)) > 0) {  $children--; } };
	
	while ( $children >= $max ) {
	    Time::HiRes::sleep(0.5);
	    next;
	}
	
	my $pid = xCAT::Utils->xfork;
	if ( !defined($pid) ) {
	    # Fork error
	    my $rsp = {};
	    $rsp->{data}->[0]="$localhostname: Fork error before running script $s for node $node";
	    $callback->($rsp);
	    return 1;
	}
	elsif ( $pid == 0 ) {
	    # Child process
	    undef $SIG{CHLD};
	    my $ret=`NODES=$node ACTION=$action $installdir/prescripts/$s 2>&1`;
	    my $err_code=$?;
	    my $rsp = {};
	    if ($err_code != 0) {
		$rsp = {};
		$rsp->{error}->[0]="$localhostname: $s: node=$node. return code=$err_code. Error message=$ret";
		$callback->($rsp);
	    } else {
		if ($ret) {
		    $rsp->{data}->[0]="$localhostname: $s: node=$node. $ret";
		    $callback->($rsp);
		}
	    }    
	    exit $err_code;
	}
	else {
	    # Parent process
	    $children++;
	}
    }
    
    #drain one more time
    while ($children > 0) {
	Time::HiRes::sleep(0.5);
	
	$SIG{CHLD} = sub { my $pid = 0; while (($pid = waitpid(-1, WNOHANG)) > 0) { $children--; } };
    }
    return 0;
}
