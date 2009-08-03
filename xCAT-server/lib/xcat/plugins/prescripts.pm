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
require xCAT::MsgUtils;
use Getopt::Long;
use Sys::Hostname;
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

    my $nodes   = $req->{node};
    if (!$nodes) { return;}

    my $service = "xcat";
    my @args=();
    if (ref($req->{arg})) {
	@args=@{$req->{arg}};
    } else {
	@args=($req->{arg});
    }
    @ARGV = @args;

    print "prepscripts: preprocess_request get called, args=@args, nodes=@$nodes\n";
    
    #use Getopt::Long;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    GetOptions('l'  => \$::LOCAL);
    my $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");
    my @requests;
    if ($::LOCAL) { #only handle the local nodes
        print "process local nodes: @$nodes\n";
        #get its own children only
	my @hostinfo=xCAT::Utils->determinehostname();
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
        print "dispatch to sn\n";
	# find service nodes for requested nodes
	# build an individual request for each service node
	# find out the names for the Management Node
	foreach my $snkey (keys %$sn)
	{
	    print "sn=$snkey\n";
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
    my $installdir = "/install";    # default
    my @installdir1 = xCAT::Utils->get_site_attribute("installdir");
    if ($installdir1[0])
    {
	$installdir = $installdir1[0];    
    }
 
    my %script_hash=getprescripts($nodes, $action, "begin");
    foreach my $scripts (keys %script_hash) {
	my $runnodes=$script_hash{$scripts};
        if ($runnodes && (@$runnodes>0)) {
	    my $runnodes_s=join(',', @$runnodes);
	    my $rsp = {};
	    $rsp->{data}->[0]="$localhostname: Running $scripts for nodes $runnodes_s.";
	    $callback->($rsp);

	    #now run the scripts 
	    undef $SIG{CHLD};
	    my @script_array=split(',', $scripts);
            foreach my $s (@script_array) {
		my $ret=`NODES=$runnodes_s ACTION=$action $installdir/prescripts/$s 2>&1`;
		my $err_code=$?;
		if ($err_code != 0) {
		    my $rsp = {};
		    $rsp->{data}->[0]="$localhostname: $err_code: $ret";
		    $callback->($rsp);
		    last;
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
    my $installdir = "/install";    # default
    my @installdir1 = xCAT::Utils->get_site_attribute("installdir");
    if ($installdir1[0])
    {
	$installdir = $installdir1[0];    
    }
    my $inittime=0;
    if (exists($request->{inittime})) { $inittime=$request->{inittime}->[0];}
    if (!$inittime) { $inittime=0; };
    
    #normalnodeset and breaknetboot are used by setupdhcp
    #yaboo sets up normalnodeset and breaknetboot; pxe does not, so we use $nodes for pxe
    my $normalnodeset=[];
    if (exists($request->{normalnodeset})) { $normalnodeset=$request->{normalnodeset};}
    my $breaknetboot=[];
    if (exists($request->{breaknetboot})) { $breaknetboot=$request->{breaknetboot};}
    if ((!$normalnodeset) && (!$breaknetboot)) { $normalnodeset=$nodes;}
    
    print "prescripts:inittime=$inittime; normalnodeset=@$normalnodeset; breaknetboot=@$breaknetboot\n"; 

    my %script_hash=getprescripts($nodes, $action, "end");
    foreach my $scripts (keys %script_hash) {
	my $runnodes=$script_hash{$scripts};
        if ($runnodes && (@$runnodes>0)) {
	    my $runnodes_s=join(',', @$runnodes);
            my %runnodes_hash=();
            foreach (@$runnodes) { $runnodes_hash{$_}=1; }

	    my $rsp = {};
	    $rsp->{data}->[0]="$localhostname: Running $scripts for nodes $runnodes_s.";
	    $callback->($rsp);

	    #now run the scripts 
	    undef $SIG{CHLD};
	    my @script_array=split(',', $scripts);
            foreach my $s (@script_array) {
		my $ret;
                print "script name=$s\n";
		if ($s eq "setupdhcp") { #special case for setupdhcp                    
                    #remove the nodes from normalnodeset and breaknetboot that are not in runnodes
                    my @new_normalnodeset=();
                    my @new_breaknetboot=();
                    foreach (@$normalnodeset) {
			if ($runnodes_hash{$_}) { push(@new_normalnodeset, $_); }
		    }
                    foreach (@$breaknetboot) {
			if ($runnodes_hash{$_}) { push(@new_breaknetboot, $_); }
		    }
		    my $normalnodeset_s=join(',', @new_normalnodeset);
		    my $breaknetboot_s=join(',',  @new_breaknetboot);
                    if (!$normalnodeset_s) { $normalnodeset_s="NONE"; }
                    if (!$breaknetboot_s) { $breaknetboot_s="NONE";}
                    
		    print "prescripts:inittime=$inittime; normalnodeset=$normalnodeset_s; breaknetboot=$breaknetboot_s\n";
		    $ret=`NODES=$runnodes_s ACTION=$action $installdir/prescripts/$s $inittime $normalnodeset_s $breaknetboot_s 2>&1`;
		} else {
		    $ret=`NODES=$runnodes_s ACTION=$action $installdir/prescripts/$s 2>&1`;
		}
		my $rsp = {};
		$rsp->{data}->[0]="$localhostname: $s: $ret";
		$callback->($rsp);
		my $err_code=$?;
		if ($err_code != 0) {
		    $rsp = {};
		    $rsp->{data}->[0]="$localhostname: $s: error code=$err_code.";
		    $callback->($rsp);
		    last;
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
    my ($nodes, $action, $colname) = @_;
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
	    if ($scripts =~ /$action:([^|]*)/) {
		$ret=$1;
	    }
	} else {
	    $ret=$scripts;
	}
    }
    return $ret;
}
