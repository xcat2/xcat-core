# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xdsh

   Supported command:
         nodenetconn
         ipforward (internal command)

=cut

#-------------------------------------------------------
package xCAT_plugin::snmove;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::Table;
use xCAT::Utils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use Getopt::Long;
use xCAT::NodeRange;
use Data::Dumper;


1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            snmove => "snmove",
           };
}


#-------------------------------------------------------

=head3  preprocess_request

  Preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request
{

    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $command = $request->{command}->[0];
    my $args    = $request->{arg};

    #if already preprocessed, go straight to request
    if ((defined($request->{_xcatpreprocessed}))
        && ($request->{_xcatpreprocessed}->[0] == 1))
    {
        return [$request];
    }

    #let process _request to handle it
    my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    return [$reqcopy];
 

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
    my $sub_req  = shift;

    my $command = $request->{command}->[0];
    my $args    = $request->{arg};
    # parse the options
    @ARGV=();
    if ($args) {
	@ARGV=@{$args};
    }
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");

    my $SN1;
    my $SN1N;
    my $SN2;
    my $SN2N;
    if(!GetOptions(
	    'h|help'      => \$::HELP,
	    'v|version'   => \$::VERSION,
	    's|source=s'  => \$SN1,
	    'S|sourcen=s'  => \$SN1N,
	    'd|dest=s'    => \$SN2,
	    'D|destn=s'    => \$SN2N,
	    'i|ignorenodes'    => \$::IGNORE,
       ))
    {
	&usage($callback);
	return 1;
    }
    
    # display the usage if -h or --help is specified
    if ($::HELP) {
	&usage($callback);
	return 0;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
	my $rsp={};
	$rsp->{data}->[0]= xCAT::Utils->Version();
	$callback->($rsp);
	return 0;
    }

    #-d must be specified
    if ((!$SN2) || (!$SN2N)) {
	my $rsp={};
	$rsp->{data}->[0]="The destination service node must be specified using -d and -D flags.\n";
	$callback->($rsp);
	&usage($callback);
	return 1;
    }

    if (@ARGV > 1) {
	my $rsp={};
	$rsp->{data}->[0]="Too manay paramters.\n";
	$callback->($rsp);
	&usage($callback);
	return 1;
    }

    if ((@ARGV == 0) && (!$SN1)) {
	my $rsp={};
	$rsp->{data}->[0]="A node range or the source service node must be specified.\n";
	$callback->($rsp);
	&usage($callback);
	return 1;	
    }

    my @nodes=();
    if (@ARGV == 1) {
	my $nr=$ARGV[0];
	@nodes = noderange($nr);
	if (nodesmissed) {
	    my $rsp={};
	    $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
	    $callback->($rsp);
	    return 1;
	}
    } else {
	#get all the nodes that uses SN1 as the primary service nodes
	my $pn_hash= xCAT::Utils->getSNandNodes();
	foreach my $snlist (keys %$pn_hash) {
	    if (($snlist =~ /^$SN1$/) || ($snlist =~ /^$SN1\,/)) {
		push(@nodes,  @{$pn_hash->{$snlist}});
	    }
	}
    }

    #now do some database changes
    my $rsp={};
    $rsp->{data}->[0]= "Changing database setting for nodes: @nodes";
    $callback->($rsp);  
  
    my $nrtab=xCAT::Table->new('noderes',-create=>1);
    my $nodehash={};
    if ($nrtab) {
	$nodehash = $nrtab->getNodesAttribs(\@nodes, ['servicenode', 'tftpserver', 'nfsserver', 'monserver', 'xcatmaster']);
    } else {
	my $rsp={};
	$rsp->{data}->[0]= "Cannot open noderes table\n";
	$callback->($rsp);
	return 1;
    }
    my $sn_hash={};
    my $old_node_hash={};
    if ($nodehash) {
	#print Dumper($nodehash);
	foreach my $node (@nodes) {
	    foreach my $rec (@{$nodehash->{$node}})	{
	        if (!$rec) { next; }
		my $sn1;
		my $sn1n;
		if ($SN1N) { $sn1n=$SN1N; }
		elsif ($rec->{'xcatmaster'}) { $sn1n=$rec->{'xcatmaster'};}
		else { 
		    my $rsp={};
		    $rsp->{error}->[0]= "xcatmaster is not set for some nodes.";
		    $callback->($rsp);
		    return;
		}
		
		my $snlist=$rec->{'servicenode'};
		my @sn_a=split(',', $snlist);
		if ($SN1) { $sn1=$SN1; }
		else { $sn1=$sn_a[0];}
		my @sn_temp=grep(!/^$SN2$/, @sn_a);
		unshift(@sn_temp,$SN2);
		my $t=join(',', @sn_temp);
		
		$sn_hash->{$node}->{'servicenode'}=$t;
		$sn_hash->{$node}->{'xcatmaster'}=$SN2N;
		$old_node_hash->{$node}->{'oldsn'}=$sn1;
		$old_node_hash->{$node}->{'oldmaster'}=$sn1n;
		
		if ($rec->{'tftpserver'} && ($rec->{'tftpserver'} eq $sn1n)) {
		    $sn_hash->{$node}->{'tftpserver'}=$SN2N;
		}
		if ($rec->{'nfsserver'}  && ($rec->{'nfsserver'} eq $sn1n)) {
		    $sn_hash->{$node}->{'nfsserver'}=$SN2N;
		}
		if ($rec->{'monserver'}) {
		    my @tmp_a=split(',', $rec->{'monserver'});
		    if ((@tmp_a > 1) && ($tmp_a[1] eq $sn1n)) {
			$sn_hash->{$node}->{'monserver'}="$SN2,$SN2N";
		    }
		}
	    }
	}

	if (keys(%$sn_hash) > 0) {
	    $nrtab->setNodesAttribs($sn_hash);
	}
	#print "noderes=" . Dumper($old_node_hash);
    }


    #handle conserver
    my $nhtab=xCAT::Table->new('nodehm',-create=>1);
    my $nodehmhash={};
    if ($nhtab) {
	$nodehmhash = $nhtab->getNodesAttribs(\@nodes, ['conserver']);
    } else {
	my $rsp={};
	$rsp->{data}->[0]= "Cannot open nodehm table\n";
	$callback->($rsp);
	return 1;
    }
   # print Dumper($nodehmhash);
    my $sn_hash1={};
    if ($nodehmhash) {
	foreach my $node (@nodes) {
	    foreach my $rec (@{$nodehmhash->{$node}})	{
		if ($rec and $rec->{'conserver'} and ($rec->{'conserver'} eq $old_node_hash->{$node}->{'oldsn'})) {
		    $sn_hash1->{$node}->{'conserver'}=$SN2;
		}
	    }
	}

	if (keys(%$sn_hash1) > 0) {
	    $nhtab->setNodesAttribs($sn_hash1);
	}
	#print "nodehm=" . Dumper($sn_hash1);
    }

    #change the services
    #conserver
    my @nodes_con=keys(%$sn_hash1);
    if (@nodes_con > 0) {
	my $rsp={};
	$rsp->{data}->[0]= "Running makeconservercf " . join(',', @nodes_con);
	$callback->($rsp);    
	my $ret = xCAT::Utils->runxcmd({  command => ['makeconservercf'],
					  node    => \@nodes_con,
				       }, 
				       $sub_req, 0, 1);
	$callback->({data=>$ret});
    }

    if (xCAT::Utils->isLinux()) {
	#tftp, dhcp and nfs (site.disjointdhcps should be set to 1)
	my $nttab=xCAT::Table->new('nodetype',-create=>1);
	my $nodetypehash={};
	if ($nttab) {
	    $nodetypehash = $nttab->getNodesAttribs(\@nodes, ['provmethod']);
	} else {
	    my $rsp={};
	    $rsp->{error}->[0]= "Cannot open nodetype table\n";
	    $callback->($rsp);
	    return 1;
	}
	my $nodeset_hash = {};
	foreach my $node (@nodes) {
	    foreach my $rec (@{$nodetypehash->{$node}})	{
		if ($rec && $rec->{'provmethod'}) {
		    if (exists($nodeset_hash->{$rec->{'provmethod'}})) {
			my $pa=$nodeset_hash->{$rec->{'provmethod'}};
			push (@$pa, $node);
		    } else {
			$nodeset_hash->{$rec->{'provmethod'}}=[$node];
		    }
		}
	    }		
	}
	
	foreach my $provmethod (keys(%$nodeset_hash)) {
	    my $nodeset_nodes=$nodeset_hash->{$provmethod};
	    if (($provmethod eq 'netboot') || ($provmethod eq 'netboot') || ($provmethod eq 'netboot')) {
		my $rsp={};
		$rsp->{data}->[0]= "Running nodeset " .  join(',', @$nodeset_nodes) . " $provmethod";
		$callback->($rsp);    
		my $ret = xCAT::Utils->runxcmd({  command => ['nodeset'],
						  node    => $nodeset_nodes,
						  arg     => [$provmethod],
					       }, 
					       $sub_req, 0, 1);
		$callback->({data=>$ret});
	    } else {
		my $rsp={};
		$rsp->{data}->[0]= "Running nodeset " .  join(',', @$nodeset_nodes) . " osimage=$provmethod";
		$callback->($rsp);    
		my $ret = xCAT::Utils->runxcmd({  command => ['nodeset'],
						  node    => $nodeset_nodes,
						  arg     => ["osimage=$provmethod"],
					       }, 
					       $sub_req, 0, 1);
		$callback->({data=>$ret});
	    }
	}
	
	#postscripts to takecare of syslog server, ntp server, it will run syslog and setupntp scripts if they are in the postscripts table for the nodes
	if (!$::IGNORE) {
	    my $pstab=xCAT::Table->new('postscripts',-create=>1);
	    my $nodeposhash={};
	    if ($pstab) {
		$nodeposhash = $pstab->getNodesAttribs(\@nodes, ['postscripts', 'postbootscripts']);
	    } else {
		my $rsp={};
		$rsp->{error}->[0]= "Cannot open postsripts table\n";
		$callback->($rsp);
		return 1;
	    }
	    my $et = $pstab->getAttribs({node=>"xcatdefaults"},'postscripts','postbootscripts');
	    my $defscripts="";
	    my $defbootscripts="";
	    if ($et) {
		$defscripts = $et->{'postscripts'};
		$defbootscripts = $et->{'postbootscripts'};
	    }
	    #print "defscripts=$defscripts; defbootscripts=$defbootscripts\n";
	    #print "nodeposhash=" . Dumper($nodeposhash). "\n";
	    
	    my $pos_hash = {};
	    foreach my $node (@nodes) {
		foreach my $rec (@{$nodeposhash->{$node}})	{
		    my $scripts;
		    if ($rec) {
			$scripts=join(',', $defscripts, $defbootscripts, $rec->{'postscripts'}, $rec->{'postsbootcripts'} );
		    } else {
			$scripts=join(',', $defscripts, $defbootscripts);
		    }
		    my @tmp_a=split(',', $scripts);
		    my $scripts1;
		    if (grep (/^syslog$/, @tmp_a)) {
			$scripts1="syslog";
		    }
		    if (grep (/^setupntp$/, @tmp_a)) {
			if ($scripts1) { $scripts1= "$scripts1,setupntp"; }
			else { $scripts1="setupntp"; }
		    }
		    if ($scripts1) {
			if (exists($pos_hash->{$scripts1})) {
			    my $pa=$pos_hash->{$scripts1};
			    push (@$pa, $node);
			}  else {
			    $pos_hash->{$scripts1}=[$node];
			}
		    }
		}
	    }
	    #print "postscripts=" . Dumper($pos_hash);
	    foreach my $scripts (keys(%$pos_hash)) {
		my $pos_nodes=$pos_hash->{$scripts};
		my $rsp={};
		$rsp->{data}->[0]= "Running updatenode " . join(',', @$pos_nodes) . " -P $scripts -s";
		$callback->($rsp);    
		my $ret = xCAT::Utils->runxcmd({  command => ['updatenode'],
						  node    => $pos_nodes,
						  arg     => ["-P", $scripts, "-s"],
					       }, 
					       $sub_req, 0, 1);
		$callback->({data=>$ret});
	    }
	}
    }
}
    



sub usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: snmove -h";
    $rsp->{data}->[1]= "       snmove -v";
    $rsp->{data}->[2]= "       snmove noderange -d sn2 -D sn2n [-i]";
    $rsp->{data}->[3]= "       snmove -s sn1 [-S sn1n] -d sn2 -D sn2n [-i]";
    $rsp->{data}->[4]= "           where sn1 is the hostname of the source service node adapter facing the mn.";
    $rsp->{data}->[5]= "                 sn1n is the hostname of the source service node adapter facing the nodes.";
    $rsp->{data}->[6]= "                 sn2 is the hostname of the destination service node adapter facing the mn.";
    $rsp->{data}->[7]= "                 sn2n is the hostname of the destination service node adapter facing the nodes.";
    $cb->($rsp);
}


