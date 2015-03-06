
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xdsh

   Supported command:
         nodenetconn
         ipforward (internal command)

=cut

#-------------------------------------------------------
package xCAT_plugin::vlan;
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
use Text::Balanced qw(extract_bracketed);
use xCAT::SwitchHandler;
use Safe;
my $evalcpt = new Safe;
$evalcpt->share('&mknum');
$evalcpt->permit('require');

my %Switches=();
  
1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            mkvlan => "vlan",
            chvlan => "vlan",
            rmvlan => "vlan",
            lsvlan => "vlan",
            chvlanports => "vlan",
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
    $::CALLBACK = $callback;

    #if already preprocessed, go straight to request
    if ((defined($request->{_xcatpreprocessed}))
        && ($request->{_xcatpreprocessed}->[0] == 1))
    {
        return [$request];
    }

    if ($command eq "mkvlan") {
	return preprocess_mkvlan($request,$callback,$sub_req);
    } elsif($command eq "chvlanports"){
        return preprocess_chvlanports($request,$callback,$sub_req);
    } elsif ($command eq "chvlan") {
	return preprocess_chvlan($request,$callback,$sub_req);
    } elsif ($command eq "rmvlan") {
	return preprocess_rmvlan($request,$callback,$sub_req);
    } elsif ($command eq "lsvlan") {
	return preprocess_lsvlan($request,$callback,$sub_req);
    } else {
	my $rsp={};
	$rsp->{error}->[0]= "$command: unsupported command.";
	$callback->($rsp);
	return 1;
    }
}

sub preprocess_mkvlan {
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

    my $nr;
    my $net;
    my $netmask;
    my $prefix;
    my $nic;
    if(!GetOptions(
	    'h|help'      => \$::HELP,
	    'v|version'   => \$::VERSION,
	    'n|nodes=s'   => \$nr,
	    't|net=s'   => \$net,
	    'm|mask=s'   => \$netmask,
	    'p|prefix=s'   => \$prefix,
            'i|interface=s' => \$nic,
       ))
    {
	&mkvlan_usage($callback);
	return 1;
    }
    # display the usage if -h or --help is specified
    if ($::HELP) {
	&mkvlan_usage($callback);
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

    my $vlan_id=0;
    if (@ARGV>0) {
	$vlan_id=$ARGV[0];   
    }

    my @nodes=();
    if ($nr) {
	#get nodes
	@nodes = noderange($nr);
	if (nodesmissed) {
	    my $rsp={};
	    $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
	    $callback->($rsp);
	    return 1;
	}
    } else {
	my $rsp={};
	$rsp->{data}->[0]= "Please specify a list of nodes to be added to the new vlan.";
	$callback->($rsp);
	return 1;
    }

    
    if ($net && (!$netmask)) {
	my $rsp={};
	$rsp->{data}->[0]= "Please specify a netmask for the vlan.";
	$callback->($rsp);
	return 1;
    }
    if ($netmask && (!$net)) {
	my $rsp={};
	$rsp->{data}->[0]= "Please specify a network address for the vlan.";
	$callback->($rsp);
	return 1;
    }

    #let process _request to handle it
    my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    $reqcopy->{vlanid}->[0] = $vlan_id; 
    $reqcopy->{node} = \@nodes;
    if ($net) { $reqcopy->{net}->[0]=$net; }
    if ($netmask) { $reqcopy->{netmask}->[0]=$netmask; }
    if ($prefix) { $reqcopy->{prefix}->[0]=$prefix; }
    if ($nic) { $reqcopy->{nic}->[0]=$nic; }
    return [$reqcopy];
}
# TODO: finish this
sub preprocess_chvlanports {
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

    my $nr;
    my $delete;
    my $nic;
    if(!GetOptions(
        'h|help'      => \$::HELP,
        'v|version'   => \$::VERSION,
        'n|nodes=s'   => \$nr,
        'd|delete'    => \$delete,
        'i|interface=s' => \$nic,
    ))
    {
        &chvlanports_usage($callback);
        return 1;
    }
    # display the usage if -h or --help is specified
    if ($::HELP) {
        &chvlanports_usage($callback);
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
    if (@ARGV==0) {
        my $rsp={};
        $rsp->{data}->[0]= "Please specify a vlan id.";
        $callback->($rsp);
        return 1;
    }

    my $vlan_id=$ARGV[0];   

    my @nodes=();
    if (!$nr) {
        my $rsp={};
        $rsp->{data}->[0]= "Please specify a range of nodes to be added to vlan $vlan_id.";
        $callback->($rsp);
        return 1;
    } else {
        #get nodes
        @nodes = noderange($nr);
        if (nodesmissed) {
            my $rsp={};
            $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
            $callback->($rsp);
            return 1;
        }
    }
    
    if (!$nic) {
        my $rsp={};
        $rsp->{data}->[0]= "Please specify a network interface for nodes";
        $callback->($rsp);
        return 1;
    }

    #let process _request to handle it
    my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    $reqcopy->{vlanid}->[0]=$vlan_id;
    $reqcopy->{node} = \@nodes;
    $reqcopy->{delete}->[0] = $delete;
    $reqcopy->{nic}->[0]=$nic;
    return [$reqcopy];
}

sub preprocess_chvlan {
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

    my $nr;
    my $delete;
    my $nic;
    if(!GetOptions(
	    'h|help'      => \$::HELP,
	    'v|version'   => \$::VERSION,
	    'n|nodes=s'   => \$nr,
	    'd|delete'    => \$delete,
            'i|interface=s' => \$nic,
       ))
    {
	&chvlan_usage($callback);
	return 1;
    }
    # display the usage if -h or --help is specified
    if ($::HELP) {
	&chvlan_usage($callback);
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
    if (@ARGV==0) {
	my $rsp={};
	$rsp->{data}->[0]= "Please specify a vlan id.";
	$callback->($rsp);
	return 1;
    }

    my $vlan_id=$ARGV[0];   

    my @nodes=();
    if (!$nr) {
	my $rsp={};
	$rsp->{data}->[0]= "Please specify a range of nodes to be added to vlan $vlan_id.";
	$callback->($rsp);
	return 1;
    } else {
	#get nodes
	@nodes = noderange($nr);
	if (nodesmissed) {
	    my $rsp={};
	    $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
	    $callback->($rsp);
	    return 1;
	}
    }

    #let process _request to handle it
   my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    $reqcopy->{vlanid}->[0]=$vlan_id;
    $reqcopy->{node} = \@nodes;
    $reqcopy->{delete}->[0] = $delete;
    if ($nic) { $reqcopy->{nic}->[0]=$nic; }
    return [$reqcopy];
}

sub preprocess_rmvlan {
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

    my $nodes;
    if(!GetOptions(
	    'h|help'      => \$::HELP,
	    'v|version'   => \$::VERSION,
       ))
    {
	&rmvlan_usage($callback);
	return 1;
    }
    # display the usage if -h or --help is specified
    if ($::HELP) {
	&rmvlan_usage($callback);
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

    if (@ARGV==0) {
	my $rsp={};
	$rsp->{data}->[0]= "Please specify a vlan id.";
	$callback->($rsp);
	return 1;
    }

    my $vlan_id=$ARGV[0];   

    #let process _request to handle it
    my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    $reqcopy->{vlanid}->[0]=$vlan_id;
    return [$reqcopy];
}

sub preprocess_lsvlan {
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

    my $nodes;
    if(!GetOptions(
	    'h|help'      => \$::HELP,
	    'v|version'   => \$::VERSION,
       ))
    {
	&lsvlan_usage($callback);
	return 1;
    }
    # display the usage if -h or --help is specified
    if ($::HELP) {
	&lsvlan_usage($callback);
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

    my $vlan_id=0;
    if (@ARGV>0) {
	$vlan_id=$ARGV[0];   
    }

    #let process _request to handle it
    my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    $reqcopy->{vlanid}->[0]=$vlan_id;
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
    $::CALLBACK = $callback;

    if ($command eq "mkvlan") {
	return process_mkvlan($request,$callback,$sub_req);
    } elsif ($command eq "chvlanports"){
        return process_chvlanports($request,$callback,$sub_req);
    } elsif ($command eq "chvlan") {
	return process_chvlan($request,$callback,$sub_req);
    } elsif ($command eq "rmvlan") {
	return process_rmvlan($request,$callback,$sub_req);
    } elsif ($command eq "lsvlan") {
	return process_lsvlan($request,$callback,$sub_req);
    } else {
	my $rsp={};
	$rsp->{error}->[0]= "$command: unsupported command.";
	$callback->($rsp);
	return 1;
    }



    return 0;
}


sub process_mkvlan {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    
    my $vlan_id=0;
    if (exists($request->{vlanid})) {
	$vlan_id=$request->{vlanid}->[0];
    }
    my @nodes=();
    if (exists($request->{node})) {
	@nodes=@{$request->{node}};
    }

    my $net;
    if (exists($request->{net})) {
	$net=$request->{net}->[0];
    }
    my $netmask;
    if (exists($request->{netmask})) {
	$netmask=$request->{netmask}->[0];
    }
    my $prefix;
    if (exists($request->{prefix})) {
	$prefix=$request->{prefix}->[0];
    } 

    my $nic;
    if (exists($request->{nic})) {
	$nic=$request->{nic}->[0];
    } 

    #check if the vlan is already defined on the table 
    my $nwtab=xCAT::Table->new("networks", -create =>1);
    if ($vlan_id > 0) {
	if ($nwtab) {
	    my @tmp1=$nwtab->getAllAttribs(('vlanid', 'net', 'mask'));
	    if ((@tmp1) && (@tmp1 > 0)) {
		foreach(@tmp1) {
		    if ($vlan_id eq $_->{vlanid}) {
			my $rsp={};
			$rsp->{error}->[0]= "The vlan $vlan_id is already used. Please choose another vlan id.";
			$callback->($rsp);
			return 1;
		    }
		}
	    }
	}
    }

    #make sure the vlan id is not currently used by another vlan
    #if no vlan id is supplied, automatically generate a new vlan id
    if ($vlan_id > 0) {
	if (!verify_vlanid($vlan_id, $callback)) { return 1; }
    } else {
	$vlan_id=get_next_vlanid($callback);
	if (!$vlan_id) { return 1;}
    }

    if (!$prefix) {
	$prefix="v". $vlan_id . "n"; #default
    }
    

    ####now get the switch ports for the nodes
    my %swinfo=();  # example: %swinfo=( switch1=>{ 23=>{ nodes: [node1]
                         #                                interface: eth0
                         #                               },
                         #                          24=>{ nodes: [node2,node3], 
                         #                                vmhost: kvm1
                         #                                interface: eth1
                         #                              }
                         #                         },
                         #               switch12=>{ 3=>{ nodes: [node4]},
                         #                           7=>{ nodes: [node4]
                         #                                interface: eth0 }, 
                         #                           9=>{ nodes: [node6]}
                         #                        }
                         #             )

    my %vminfo=();       # example: %vminfo=( kvm1=>{clients:[node1,node2...]},
                         #                    kvm2=>{clients:[node2,node3...]},
                         #                   )
                         #                  
    my @vmnodes=();      # vm clients
    my @snodes=();       # stand alone nodes

    
    #get the vm hosts  
    my $vmtab=xCAT::Table->new("vm", -create =>1);
    my $vmtmphash = $vmtab->getNodesAttribs(\@nodes, ['host', 'nics']) ;
    foreach my $node (@nodes) {
	my $host;
	my $ent=$vmtmphash->{$node}->[0];
	if (ref($ent) and defined $ent->{host}) { 
	    $host = $ent->{host}; 
	    if (exists($vminfo{$host})) {
		my $pa=$vminfo{$host}->{clients};
		push(@$pa, $node);
	    } else {
		$vminfo{$host}->{clients}=[$node];
	    }

	    push(@vmnodes, $node);
	}
    }

   
    if (@vmnodes > 0) {
	foreach my $node (@nodes) {
	    if (! grep /^$node$/, @vmnodes) {
		push(@snodes, $node);
	    }
	}
    } else {
	@snodes=@nodes;
    }
 
    #get the switch and port numbers for each node
    my @vmhosts=keys(%vminfo);
    my @anodes=(@snodes, @vmhosts); #nodes that connects to the switch
    my %swsetup=();
    my $swtab=xCAT::Table->new("switch", -create =>1);
    my $swtmphash = $swtab->getNodesAttribs(\@anodes, ['switch', 'port', 'vlan', 'interface']) ;
    my @missed_nodes=();
    foreach my $node (@anodes) {
	my $node_enties=$swtmphash->{$node}; 
	if ($node_enties) {
	    my $i=-1;
            my $use_this=0;
	    foreach my $ent (@$node_enties) {
		$i++;
		if (ref($ent) and defined $ent->{switch} and defined $ent->{port}) { 
		    my $switch;
		    my $port;
		    $switch = $ent->{switch};
		    $port = $ent->{port};
		    my $interface="primary";		    
		    if (defined $ent->{interface}) { $interface=$ent->{interface};}
                    # for primary nic, the interface can be empty, "primary" or "primary:eth0"
		    #print "***nic=$nic, interface=$interface\n";
		    if ($nic) {
			if ($interface =~ /primary/) {
			    $interface =~ s/primary(:)?//g;
			}
			if ($interface && ($interface eq $nic)) { $use_this=1; }
		    } else {
			if ($interface =~ /primary/) {  $use_this=1; }
		    } 

		    if (! $use_this) { 
			next; 
		    }
		    else { 
			$swsetup{$node}->{port}=$port;
			$swsetup{$node}->{switch}=$switch;
			if (defined $ent->{vlan}) { 
			    $swsetup{$node}->{vlan}=$ent->{vlan};
			} else {
			    $swsetup{$node}->{vlan}="";
			}
		    }

		    if ($interface) { 			
			$swinfo{$switch}->{$port}->{interface}=$interface;
		    }
		    
		    if (exists($vminfo{$node})) {
			$swinfo{$switch}->{$port}->{vmhost}=$node;
			$swinfo{$switch}->{$port}->{nodes}=$vminfo{$node}->{clients};
		    } else {
			$swinfo{$switch}->{$port}->{nodes}=[$node];
		    }
		    last;
		    
		} 
	    }
            if ( $use_this != 1 ) {
                push (@missed_nodes, $node);
            }
	}
    }

    if (@missed_nodes > 0) {
	my $rsp={};
	$rsp->{error}->[0]= "Cannot proceed, please define switch and port info on the switch table for the following nodes:\n  @missed_nodes\n";
	$callback->($rsp);
	return 1;
    }
    
    #print "vminfo=" . Dumper(%vminfo) . "\n";
    #print "swinfo=" . Dumper(%swinfo) . "\n";
    #print "snodes=" . Dumper(@snodes) . "\n";
    #print "anodes=" . Dumper(@anodes) . "\n";
    #print "vmnodes=" . Dumper(@vmnodes) . "\n";
    #print "swtmphash" . Dumper($swtmphash). "\n";

    ### verify the ports are not used by other vlans
    #if (!verify_switch_ports($vlan_id, \%swinfo, $callback)) { return 1;}
    
    ### now pick a network address for the vlan
    if (!$net) {
	($net, $netmask)=get_subnet($vlan_id, $callback);
    }


    ### save the vlan on the networks table
    my %key_col = (netname=>"vlan$vlan_id");
    my %tb_cols=(vlanid=>$vlan_id, net=>$net, mask=>$netmask);
    $nwtab->setAttribs(\%key_col, \%tb_cols);


    ### configure vlan on the switch
    if (!create_vlan($vlan_id, \%swinfo, $callback)) { return 1;}
    if (!add_ports($vlan_id, \%swinfo, $callback)) { return 1;}
    my @sws=keys(%swinfo);
    if (!add_crossover_ports($vlan_id, \@sws, $callback)) { return 1;}

    ### add the vlanid for the standalone nodes on the switch table
    ### append the vlan id for the vmhosts on the switch table
    add_vlan_to_switch_table(\%swsetup, $vlan_id);

    ### get node ip and vlan hostname from the hosts table. 
    #If it is not defined, put the default into the host table
    my @allnodes=(@anodes, @vmnodes);
    if (!add_vlan_ip_host($net, $netmask, $prefix, 1, \@allnodes, $callback)) { return 1;}

    ### for vm nodes, add an additional nic on the vm.nics
    if (@vmnodes > 0) {
	my %setupnics=();
	my $new_nic="vl$vlan_id";
	foreach my $node (@vmnodes) {
	    my $ent=$vmtmphash->{$node}->[0];
	    my $nics;
	    if (ref($ent) and defined $ent->{nics}) { 
		$nics=$ent->{nics};
		my @a=split(",", $nics);
		if (!grep(/^$new_nic$/, @a)) { $nics="$nics,$new_nic"; }
	    } else {
		$nics=$new_nic;
	    }
	    $setupnics{$node}={nics=>"$nics"};
	}
	$vmtab->setNodesAttribs(\%setupnics);
    }

    ### populate the /etc/hosts and make the DNS server on the mn aware this change
    $::CALLBACK = $callback;
    my $res = xCAT::Utils->runxcmd(  {
            command => ['makehosts'],
            }, $sub_req, 0, 1);
    my $rsp = {};
    $rsp->{data}->[0] = "Running makehosts...";
    $callback->($rsp);
    if ($res && (@$res > 0)) {
	$rsp = {};
	$rsp->{data} = $res;
	$callback->($rsp);
    }

    $::CALLBACK = $callback;
    my $res = xCAT::Utils->runxcmd(  {
            command => ['makedns'],
            }, $sub_req, 0, 1);
    my $rsp = {};
    $rsp->{data}->[0] = "Running makedns...";
    $callback->($rsp);
    if ($res && (@$res > 0)) {
	$rsp->{data} = $res;
	$callback->($rsp);
    }

    my $cmd = "service named restart";
    my $rc=system $cmd;

    ### now go to the nodes to configure the vlan interface
    $::CALLBACK = $callback;
    my $args = ["-P", "configvlan $vlan_id --keephostname"];
    my $res = xCAT::Utils->runxcmd(  {
            command => ['updatenode'],
	    node    => \@snodes,
	    arg     => $args
            }, $sub_req, 0, 1);
    my $rsp = {};
    $rsp->{data}->[0] = "Running updatenode...";
    $callback->($rsp);
    if ($res && (@$res > 0)) {
	$rsp->{data} = $res;
	$callback->($rsp);
    }

    ### add configvlan postscripts to the postscripts table for the node
    #   so that next time the node bootup, the vlan can get configured
    my @pnodes=(@snodes, @vmnodes);
    add_postscript($callback, \@pnodes);

    my $rsp={};
    $rsp->{data}->[0]= "The vlan is successfully configured. ";
    $rsp->{data}->[1]= "  vlan id: $vlan_id";
    $rsp->{data}->[2]= "  vlan subnet: $net";
    $rsp->{data}->[3]= "  vlan netmask: $netmask";
    #$rsp->{data}->[4]= "  vlan dhcp server:";
    #$rsp->{data}->[5]= "  vlan dns server:";
    #$rsp->{data}->[6]= "  vlan gateway:";
    $callback->($rsp);


    return 0;
}

#-------------------------------------------------------
=head3  add_vlan_to_switch_table

  It adds the vlan id to the switch.vlan for the given nodes.

=cut
#-------------------------------------------------------
sub add_vlan_to_switch_table {
    my $swsetup=shift;
    my $vlan_id=shift;

    my $swtab1 = xCAT::Table->new( 'switch', -create=>1, -autocommit=>0 );
    foreach my $node (keys(%$swsetup)) {
	my %keyhash=();
	my %updates=();
	$keyhash{'node'} = $node;
	$keyhash{'switch'}= $swsetup->{$node}->{switch};
	$keyhash{'port'} = $swsetup->{$node}->{port};
	$updates{'vlan'}=$vlan_id;
	my $vlan;
	if($swsetup->{$node}->{vlan}) { 
	    $vlan=$swsetup->{$node}->{vlan};
	    my @a=split(",", $vlan);
	    if (!grep(/^$vlan_id$/, @a)) { $vlan="$vlan,$vlan_id";}
	    $updates{'vlan'}=$vlan;
	}
	  
	$swtab1->setAttribs( \%keyhash,\%updates );
    }
    $swtab1->commit;
}

sub remove_vlan_from_switch_table {
    my $swsetup=shift;
    my $vlan_id=shift;
    #remove the vlan id from the switch table for standalone nodes 
    my $swtab1 = xCAT::Table->new('switch', -create=>1, -autocommit=>0 );
    foreach my $node (keys(%$swsetup)) {
	my %keyhash=();
	my %updates=();
	$keyhash{'node'} = $node;
	$keyhash{'switch'}= $swsetup->{$node}->{switch};
	$keyhash{'port'} = $swsetup->{$node}->{port};
	$updates{'vlan'} = "";
	if($swsetup->{$node}->{vlan}) {
	    my @a=split(',', $swsetup->{$node}->{vlan});
	    my @b=grep(!/^$vlan_id$/,@a);
	    if (@b>0) {
		$updates{'vlan'}=join(',', @b);
	    }
	}
	$swtab1->setAttribs( \%keyhash,\%updates );
    }
    $swtab1->commit;
}


#-------------------------------------------------------
=head3  add_postscript

  It adds the 'configvlan' postscript to the postscript table
  for the given nodes.

=cut
#-------------------------------------------------------
sub  add_postscript {
    my $callback=shift;
    my $anodes=shift;

    my $posttab=xCAT::Table->new("postscripts", -create =>1);
    if ($posttab) {
	(my $ref1) = $posttab->getAttribs({node => 'xcatdefaults'}, ('postscripts', 'postbootscripts'));
        #if configvlan is in xcadefaults, then do nothing
	if ($ref1) {
	    if ($ref1->{postscripts}) {
		my @a = split(/,/, $ref1->{postscripts});
		if (grep(/^configvlan$/, @a)) { next; }
	    }
	    if ($ref1->{postbootscripts}) {
		my @a = split(/,/, $ref1->{postbootscripts});
		if (grep(/^configvlan$/, @a)) { next; }
	    }
	}

	#now check for each node
	my %setup_hash;
	my $postcache = $posttab->getNodesAttribs($anodes,[qw(postscripts postbootscripts)]);
	foreach my $node (@$anodes) {
	    my $ref = $postcache->{$node}->[0]; 
	    if ($ref) {
		if (exists($ref->{postscripts})) {
		    my @a = split(/,/, $ref->{postscripts});
		    if (grep(/^configvlan$/, @a)) { next; }
		}

		if (exists($ref->{postbootscripts})) {
		    my $post=$ref->{postbootscripts};
		    my @old_a=split(',', $post);
		    if (grep(/^configvlan$/, @old_a)) {
			next;
		    } else {
			$setup_hash{$node}={postbootscripts=>"$post,configvlan"};
		    }
		} else {
		    $setup_hash{$node}={postbootscripts=>"configvlan"};
		}
	    } else {
		$setup_hash{$node}={postbootscripts=>"configvlan"};
	    }
	}
	if (keys(%setup_hash) > 0) {
	    $posttab->setNodesAttribs(\%setup_hash);
	}
    }   

    return 0;
}



#-------------------------------------------------------
=head3  add_vlan_ip_host

  It goes to the hosts.otherinterfaces to see if the vlan ip and hostname
  is defined. If not, it will add the default in the table. 
  The default is v<vlanid>n<node#>

=cut
#-------------------------------------------------------
sub  add_vlan_ip_host {
    my $subnet=shift;
    my $netmask=shift;
    my $prefix=shift;
    my $node_number=shift;
    my $nodes=shift;
    my $callback=shift;

    my $hoststab = xCAT::Table->new('hosts');
    my $hostscache = $hoststab->getNodesAttribs($nodes,[qw(node otherinterfaces)]);
    my %setup_hash;
    foreach my $node (@$nodes) {
	my $ref = $hostscache->{$node}->[0]; 
	my $found=0;
	my $otherinterfaces;
	if ($ref && exists($ref->{otherinterfaces})){
	    $otherinterfaces = $ref->{otherinterfaces};
	    my @itf_pairs=split(/,/, $otherinterfaces);
	    foreach (@itf_pairs) {
            	my ($name,$ip)=split(/:/, $_);
	    	if ($name =~ /^-/ ) {
	    	    $name = $node.$name;
	    	}
	    	if(xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet)) {
	    	    $found=1;
	    	}
	    }	    
	}
	if (!$found) {
	    my $hostname=$prefix . "$node_number"; 
	    my $ip="";
	    if ($subnet =~ /\d+\.\d+\.\d+\.\d+/) {# ipv4 address
		$subnet =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
		my $netnum = ($1<<24)+($2<<16)+($3<<8)+$4;
		my $ipnum=$netnum + $node_number;
		my @a=();
		for (my $i=3; $i>-1; $i--) {
		    $a[$i]=$ipnum % 256;
		    $ipnum = int($ipnum / 256);
		}
		$ip= "$a[0].$a[1].$a[2].$a[3]";
		#print "ip=$ip\n";
	    } else {
		my $rsp={};
		$rsp->{error}->[0]= "Does not support IPV6 address yet.";
		$callback->($rsp);
		return 0; 
	    }
	    $node_number++;

	    if ($otherinterfaces) {
		$setup_hash{$node}={otherinterfaces=>"$hostname:$ip,$otherinterfaces"};
	    } else {
		$setup_hash{$node}={otherinterfaces=>"$hostname:$ip"};
	    }
	}
    } #foreach node

    if (keys(%setup_hash) > 0) {
	$hoststab->setNodesAttribs(\%setup_hash);
    }

    return 1;
}


#-------------------------------------------------------
=head3 get_prefix_and_nodenumber

  It gets the prefix and max node number from the current nodes
  in the given vlan. 

=cut
#-------------------------------------------------------
sub get_prefix_and_nodenumber {
    my $vlan_id = shift;
    my $subnet = shift;
    my $netmask = shift;

    #get all the nodes that are in the vlan
    my $swtab=xCAT::Table->new("switch", -create =>0);
    my @nodes=();
    my @tmp1=$swtab->getAllAttribs(('node', 'vlan'));
    if ((@tmp1) && (@tmp1 > 0)) {
	foreach my $ent (@tmp1) {
	    my @nodes_tmp=noderange($ent->{node});
	    foreach my $node (@nodes_tmp) {
		if ($ent->{vlan}) {
		    my @a=split(",", $ent->{vlan});
		    if (grep(/^$vlan_id$/,@a)) {
			push(@nodes, $node);
		    }
		}
	    }
	}
    }


    #get all the vm clients if the node is a vm host
    my $vmtab=xCAT::Table->new("vm", -create =>0);
    my @vmnodes=();
    if ($vmtab) {
	my @tmp1=$vmtab->getAllAttribs('node', 'host');
	if ((@tmp1) && (@tmp1 > 0)) {
	    foreach(@tmp1) {
		my $host = $_->{host};
		if (grep(/^$host$/, @nodes)) {
		    my @nodes_tmp=noderange($_->{node});
		    foreach my $node (@nodes_tmp) {
			push(@vmnodes, $node);
		    }
		}
	    }
	}
    }
    
    @nodes=(@nodes, @vmnodes);
    #print "nodes=@nodes\n";	

    #now go to hosts table to get the prefix and max node number
    my $hoststab = xCAT::Table->new('hosts');
    my $hostscache = $hoststab->getNodesAttribs(\@nodes,[qw(node otherinterfaces)]);
    my $max=0;
    my $prefix;
    foreach my $node (@nodes) {
	my $ref = $hostscache->{$node}->[0]; 
	my $otherinterfaces;
	if ($ref && exists($ref->{otherinterfaces})){
	    $otherinterfaces = $ref->{otherinterfaces};
	    my @itf_pairs=split(/,/, $otherinterfaces);
	    my @itf_pairs2=();
	    foreach (@itf_pairs) {
            	my ($name,$ip)=split(/:/, $_);
	    	if(xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet)) {
		   $name =~ /^(.*)([\d]+)$/;
                   if ($2 > $max) { $max=$2;}
		   if (!$prefix) { $prefix=$1;}
		   #print "name=$name\n, 1=$1, 2=$2\n";
	    	}
	    }
	}
    } #foreach node

    return ($prefix, $max);
}



#-------------------------------------------------------
=head3  remove_vlan_ip_host

  It goes to the hosts.otherinterfaces to see if the vlan ip and hostname
  is defined. If it is, it will remove it. It also remove the entried in 
  the /etc/hosts file

=cut
#-------------------------------------------------------
sub  remove_vlan_ip_host {
    my $subnet=shift;
    my $netmask=shift;
    my $nodes=shift;
    my $callback=shift;

    my $hoststab = xCAT::Table->new('hosts');
    my $hostscache = $hoststab->getNodesAttribs($nodes,[qw(node otherinterfaces)]);
    my %setup_hash;
    foreach my $node (@$nodes) {
	my $ref = $hostscache->{$node}->[0]; 
	my $otherinterfaces;
	if ($ref && exists($ref->{otherinterfaces})){
	    $otherinterfaces = $ref->{otherinterfaces};
	    my @itf_pairs=split(/,/, $otherinterfaces);
	    my @itf_pairs2=();
	    my $index=0;
	    foreach (@itf_pairs) {
            	my ($name,$ip)=split(/:/, $_);
	    	if(!xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet)) {
	    	    $itf_pairs2[$index]=$_;
		    $index++;
	    	} else {
		    my $cmd="sed -i /$ip/d /etc/hosts";
		    my $rc=system $cmd;
		}
	    }
	    if (@itf_pairs2 > 0) {
		my $new_intf=join(",", @itf_pairs2);
		$setup_hash{$node}={otherinterfaces=>$new_intf}
	    } else {
		$setup_hash{$node}={otherinterfaces=>""};
	    }
	}
    } #foreach node

    if (keys(%setup_hash) > 0) {
	$hoststab->setNodesAttribs(\%setup_hash);
    }

    return 1;
}

#-------------------------------------------------------
=head3  verify_vlanid

  It goes to all the switches to make sure that the vlan 
  id is not used by other vlans.
=cut
#-------------------------------------------------------
sub verify_vlanid {
    my $vlan_id=shift;
    my $callback=shift;

    my $switchestab=xCAT::Table->new('switches',-create=>0);
    my @tmp1=$switchestab->getAllAttribs(('switch'));
    if ((@tmp1) && (@tmp1 > 0)) {
	foreach(@tmp1) {
	    my @switches_tmp=noderange($_->{switch});
	    if (@switches_tmp==0) { push @switches_tmp, $_->{switch}; } #sometimes the switch name is not on the node list table.  
	    foreach my $switch (@switches_tmp) {
		my $swh;
		if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
		else {
		    $swh=new xCAT::SwitchHandler->new($switch);
		    $Switches{$switch}=$swh;
		}
		my @ids=$swh->get_vlan_ids();
		print "ids=@ids\n";
		foreach my $id (@ids) {
		    if ($id == $vlan_id) {
			my $rsp={};
			$rsp->{error}->[0]= "The vlan id $vlan_id already exists on switch $switch. Please choose another vlan id.\n";
			$callback->($rsp);
			return 0; 
		    }
		}
	    }
	}
    }
    return 1;
}

#-------------------------------------------------------
=head3  get_next_vlanid

  It automatically generates the vlan ID. It goes to all the
  switches, get the smallest common integer that is not used
  by any existing vlans. 
=cut
#-------------------------------------------------------
sub get_next_vlanid {
    my $callback=shift;
    my $switchestab=xCAT::Table->new('switches',-create=>0);
    my @tmp1=$switchestab->getAllAttribs(('switch'));
    my %vlanids=();
    if ((@tmp1) && (@tmp1 > 0)) {
	foreach(@tmp1) {
	    my @switches_tmp=noderange($_->{switch});
	    if (@switches_tmp==0) { push @switches_tmp, $_->{switch}; } #sometimes the switch name is not on the node list table.  
	    foreach my $switch (@switches_tmp) {
		my $swh;
		if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
		else {
		    $swh=new xCAT::SwitchHandler->new($switch);
		    $Switches{$switch}=$swh;
		}
		my @ids=$swh->get_vlan_ids();
		foreach my $id (@ids) {
		    $vlanids{$id}=1;
		}
	    }
	}
    }
    
    for (my $index=2; $index<255; $index++) {
	if (! exists($vlanids{$index})) { return $index; }
    }

    my $rsp={};
    $rsp->{data}->[0]= "No valid vlan ID can be used any more, Please remove unused vlans.\n";
    $callback->($rsp);
    
    return 0;
}

#-------------------------------------------------------
=head3  verify_switch_ports

  It checks if the switch ports to be configured are used by other vlans.

=cut
#-------------------------------------------------------
sub verify_switch_ports {
    my $vlan_id=shift;
    my $swinfo=shift;
    my $callback=shift;

    my $ret=1;
    foreach my $switch (keys %$swinfo) {
	my $porthash=$swinfo->{$switch};
	my $swh;
	if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
	else {
	    $swh=new xCAT::SwitchHandler->new($switch);
	    $Switches{$switch}=$swh;
	}
 	my $port_vlan_hash=$swh->get_vlanids_for_ports(keys(%$porthash));
	print "port_vlan_hash=" . Dumper($port_vlan_hash) . "\n";
	my @error_ports=();
	foreach my $port (keys(%$port_vlan_hash)) {
	    my $val=$port_vlan_hash->{$port};
	    foreach my $tmp_vid (@$val) {
		if (($tmp_vid != $vlan_id) && ($tmp_vid != 1) && ($tmp_vid ne 'NA')) {
        if (exists($porthash->{$port}->{vmhost})) { next; } #skip the vmhost, vmhost can have more than one vlans
		    push(@error_ports, $port);
		    last;
		}
	    }
	}
	if (@error_ports >0) {
	    $ret=0;
	    my $error_str;
	    foreach(@error_ports) {
		my @tmp=@{$porthash->{$_}->{nodes}};
		my $ids_tmp=$port_vlan_hash->{$_};
		$error_str .= "$_: vlan-ids=@$ids_tmp  nodes=@tmp\n";
	    }
	    my $rsp={};
	    $rsp->{error}->[0]= "The following ports on switch $switch are used by other vlans.\n$error_str";
	    $callback->($rsp);
	}
    }

    return $ret;
}

#-------------------------------------------------------
=head3  create_vlan

  It goes to the switches and create a new vlan. 
  Returns:  1 -- suggessful
            0 -- fail 
=cut
#-------------------------------------------------------
sub create_vlan {
    my $vlan_id=shift;
    my $swinfo=shift;
    my $callback=shift;
    my $ret=1;
    foreach my $switch (keys %$swinfo) {
	my $swh;
	if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
	else {
	    $swh=new xCAT::SwitchHandler->new($switch);
	    $Switches{$switch}=$swh;
	}
	#check if the vlan already exists on the switch
	my @ids=$swh->get_vlan_ids(); 
        my $vlan_exists=0;
	foreach my $id (@ids) {
	    if ($id == $vlan_id) { 
		$vlan_exists=1;
		last;
	    }
	}

	if (!$vlan_exists) {
	    #create the vlan
            print "create vlan $vlan_id on switch $switch\n";
	    my @ret=$swh->create_vlan($vlan_id);
	    if ($ret[0] != 0) {
		my $rsp={};
		$rsp->{error}->[0]= "create_vlan: $ret[1]";
		$callback->($rsp);
	    }
	}
    }


    return 1;
}


#-------------------------------------------------------
=head3  add_ports

  It adds the ports to the vlan.
  Returns:  1 -- suggessful
            0 -- fail 
=cut
#-------------------------------------------------------
sub add_ports {
    my $vlan_id=shift;
    my $swinfo=shift;
    my $callback=shift;
    my $portmode=shift;
    my $ret=1;
    foreach my $switch (keys %$swinfo) {
	my $porthash=$swinfo->{$switch};
	my $swh;
	if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
	else {
	    $swh=new xCAT::SwitchHandler->new($switch);
	    $Switches{$switch}=$swh;
	}

 	my @ret=$swh->add_ports_to_vlan($vlan_id, $portmode, keys(%$porthash));
	if ($ret[0] != 0) {
	    my $rsp={};
	    $rsp->{error}->[0]= "add_ports_to_vlan: $ret[1]";
	    $callback->($rsp);
	}
    }

    return 1;
}

#-------------------------------------------------------
=head3  add_crossover_ports

  It enables the vlan on the cross-over links.
  Returns:  1 -- suggessful
            0 -- fail 
=cut
#-------------------------------------------------------
sub add_crossover_ports {
    my $vlan_id=shift;
    my $psws=shift;
    my $callback=shift;    

    #now make sure the links between the switches allows this vlan to go through
    my @sws=@$psws;
    print "sws=@sws\n";
    if (@sws > 1) {
	foreach my $switch (@sws) {
	    my $swh;
	    if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
	    else {
		$swh=new xCAT::SwitchHandler->new($switch);
		$Switches{$switch}=$swh;
	    }

	    my @sws_b=grep(!/^$switch$/, @sws);
	    my @ret=$swh->add_crossover_ports_to_vlan($vlan_id, @sws_b);
	    if ($ret[0] != 0) {
		my $rsp={};
		$rsp->{error}->[0]= "add_crossover_ports: $ret[1]";
		$callback->($rsp);
	    } else {
		if ($ret[1]) {
		    my $rsp={};
		    $rsp->{data}->[0]= "add_crossover_ports: $ret[1]";
		    $callback->($rsp);
		}
	    }
	}
    }

    return 1;
}

#-------------------------------------------------------
=head3  remove_ports

  It goes to the switches and create a new vlan.
  Returns:  1 -- suggessful
            0 -- fail 
=cut
#-------------------------------------------------------
sub remove_ports {
    my $vlan_id=shift;
    my $swinfo=shift;
    my $callback=shift;
    my $novmhost=shift;
    my $ret=1;
    foreach my $switch (keys %$swinfo) {
	my $porthash=$swinfo->{$switch};
	my $swh;
	if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
	else {
	    $swh=new xCAT::SwitchHandler->new($switch);
	    $Switches{$switch}=$swh;
	}

	my @ports=();
	if ($novmhost) {  #skip the vm hosts for chvlan
	    foreach my $port (keys(%$porthash)) {
		if (!exists($porthash->{$port}->{vmhost})) {
		    push(@ports, $port);
		}
	    } 
	}else {
	    @ports=keys(%$porthash);
	}
 	my @ret=$swh->remove_ports_from_vlan($vlan_id, @ports);
	if ($ret[0] != 0) {
	    my $rsp={};
	    $rsp->{error}->[0]= "remove_ports_from_vlan: $ret[1]";
	    $callback->($rsp);
	}
    }

    return 1;
}


#-------------------------------------------------------
=head3   get_subnet

  It gets the subnet address and netmask for the given 
  vlan ID. The pattern is defined by "vlannets" and "vlanmask"
  on the site table.  The default is "10.<$vlanid>.0.0"/"255.255.0.0". 
=cut
#-------------------------------------------------------
sub get_subnet {
    my $vlan_id=shift;
    my $callback = shift;
    my $net;
    my $mask;

    #get vlannets and vlanidmask from the site table 
    my $vlannets="|(\\d+)|10.(\$1+0).0.0|";
    my $vlanmask="255.255.0.0";
    my $sitetab = xCAT::Table->new('site');
    my $sent = $sitetab->getAttribs({key=>'vlannets'},'value');
    if ($sent and ($sent->{value})) {
	$vlannets=$sent->{value};
    } 
    $sent = $sitetab->getAttribs({key=>'vlanmask'},'value');
    if ($sent and ($sent->{value})) {
	$vlanmask=$sent->{value};
    } 
    $mask = $vlanmask;

    if ($vlannets =~ /^\/[^\/]*\/[^\/]*\/$/)
    {
	my $exp = substr($vlannets, 1);
	chop $exp;
	my @parts = split('/', $exp, 2);
	$net=$vlan_id;
	$net =~ s/$parts[0]/$parts[1]/;
    }
    elsif ($vlannets =~ /^\|.*\|.*\|$/)
    {
	
	my $exp = substr($vlannets, 1);
	chop $exp;
	my @parts = split('\|', $exp, 2);
	my $curr;
	my $next;
	my $prev;
	my $retval = $parts[1];
	($curr, $next, $prev) =
	    extract_bracketed($retval, '()', qr/[^()]*/);
	
	unless($curr) { #If there were no paramaters to save, treat this one like a plain regex
	    undef $@; #extract_bracketed would have set $@ if it didn't return, undef $@
	    $retval = $vlan_id;
	    $retval =~ s/$parts[0]/$parts[1]/;
	}
	while ($curr)
	{
	    my $value = $vlan_id;
	    $value =~ s/$parts[0]/$curr/;
	    $value = $evalcpt->reval('use integer;'.$value);
	    $retval = $prev . $value . $next;
	    ($curr, $next, $prev) =
		extract_bracketed($retval, '()', qr/[^()]*/);
	}
	undef $@;
	$net = $vlan_id;
	$net =~ s/$parts[0]/$retval/;
    }
    return ($net, $mask);
}


# process_chvlanports only support physical nodes
# bond not supported and multi nics are not supported
sub process_chvlanports {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
	
	my $vlan_id=0;
    my $nic = "";
    my @nodes=();
    my $delete=0;
    
    # validate vlan id value.
    $vlan_id=$request->{vlanid}->[0];
    #debug message.
    xCAT::MsgUtils->message('S',"vlanid: $vlan_id");
    if ($vlan_id <= 0) {
        my $rsp={};
        $rsp->{error}->[0]= "Invalid vlan id: $vlan_id";
        $callback->($rsp);
        return;
    }
    #Check if the vlan is defined in networks table.
    my $net="";
    my $netmask="";
    my $nwtab=xCAT::Table->new("networks", -create =>1);
    if ($nwtab) {
        my @nwentires=$nwtab->getAllAttribs(('vlanid', 'net', 'mask'));
        foreach(@nwentires) {
            if ($vlan_id eq $_->{vlanid}) {
                $net=$_->{net};
                $netmask=$_->{mask};
            }
        }
    }
    if ((!$net) || (!$netmask)) {
        my $rsp = {};
        $rsp->{data}->[0] = "Can not find valid network/netmask definition from table networks for vlan $vlan_id.";
        $callback->($rsp);
        return 1;
    }
	
    $nic=$request->{nic}->[0];
    #debug message.
    xCAT::MsgUtils->message('S',"nic is: $nic");

    @nodes=@{$request->{node}};
    #debug message.
    my $nodesstr = Dumper(@nodes);
    xCAT::MsgUtils->message('S',"nodes are: $nodesstr");

    $delete=$request->{delete}->[0];
    #debug message.
    xCAT::MsgUtils->message('S',"delete flag: $delete");
	

	####now get the switch ports for the nodes
    my %swinfo=();  # example: %swinfo=( switch1=>{ 23=>{ nodes: [node1]},
                         #                          24=>{ nodes: [node2]},
                         #                         },
                         #               switch12=>{ 3=>{ nodes: [node4],
                         #                         }
                         #             )
    my %nodeswinfo=(); # example: %nodeswinfo=(
                         #               node1=>{eth0=>{switch => swith1,
                         #                              port => 1,
                         #                              vlanids => [2,3]},
                         #                       eth1=>{switch => switch1,
                         #                              port => 2,
                         #                              vlanids => [5]}}
                         #                   )
    my %swsetup=();

    #get the switch and port numbers for each node
    my $swtab=xCAT::Table->new("switch", -create =>1);
    my $swtmphash = $swtab->getNodesAttribs(\@nodes, ['switch', 'port', 'vlan', 'interface']);
    foreach my $node (keys (%$swtmphash)) {
        my $node_enties=$swtmphash->{$node}; 
        foreach my $ent (@$node_enties) {
            if (ref($ent) and defined $ent->{switch} and defined $ent->{port}){ 
                my $switch = $ent->{switch};
                my $port = $ent->{port};
                my $interface = "";
                if( defined $ent->{interface} ){ $interface = $ent->{interface}};
                my $vlan = "";
                if( defined $ent->{vlan}) {$vlan = $ent->{vlan}};
                
                if ($interface){
                    $nodeswinfo{$node}->{$interface}->{switch}=$switch;
                    $nodeswinfo{$node}->{$interface}->{port}=$port;
                    $nodeswinfo{$node}->{$interface}->{vlan} = $vlan;
                }
            }
        }
    }
    #debug message.
    my $nodesinfostr = Dumper(%nodeswinfo);
    xCAT::MsgUtils->message('S',"nodeswinfo: $nodesinfostr");

    # Validate node's switch info %nodeswinfo and build up %swinfo, %swsetup.
    my @missed_switch_nodes = ();
    my @missed_vlanid_nodes = ();
    foreach my $node (@nodes){
        # Check whether the switch, port and interface info defined for all nodes.
        if(defined $nodeswinfo{$node} && defined $nodeswinfo{$node}->{$nic}){
        } else{
            push(@missed_switch_nodes, $node);
            next;
        }
    
        if ($delete){
            # For delete mode, must make sure all node's has such a vlan ID defined for the interface.
            my @vlanids = split(",",$nodeswinfo{$node}->{$nic}->{vlan});
            if (@vlanids && (grep /^$vlan_id$/, @vlanids)){
                my $switch = $nodeswinfo{$node}->{$nic}->{switch};
                my $port = $nodeswinfo{$node}->{$nic}->{port};

                #setup swinfo and swsetup .
                $swinfo{$switch}->{$port}->{hosts} = [$node];
                $swsetup{$node}->{switch} = $switch;
                $swsetup{$node}->{port} = $port;
                $swsetup{$node}->{vlan} = $nodeswinfo{$node}->{$nic}->{vlan};
            }else{
                push(@missed_vlanid_nodes, $node);
                next;
            }
        } else{
            # non-delete mode, just setup swinfo directly.
            my $switch = $nodeswinfo{$node}->{$nic}->{switch};
            my $port = $nodeswinfo{$node}->{$nic}->{port};

            #setup swinfo and swsetup for add_ports, add_crossover_ports and add_vlan_to_switch_table call later.
            $swinfo{$switch}->{$port}->{hosts} = [$node];
            $swsetup{$node}->{switch} = $switch;
            $swsetup{$node}->{port} = $port;
            $swsetup{$node}->{vlan} = $nodeswinfo{$node}->{$nic}->{vlan};
        }
    }
    if (@missed_switch_nodes > 0) {
        my $rsp={};
        $rsp->{error}->[0]= "Cannot proceed, please define switch, port and interface info on the switch table for the following nodes:\n  @missed_switch_nodes\n";
        $callback->($rsp);
        return 1;
    }
    if (@missed_vlanid_nodes > 0) {
        my $rsp={};
        $rsp->{error}->[0]= "Cannot proceed, no such vlan ID $vlan_id defined for following nodes:\n @missed_vlanid_nodes\n";
        $callback->($rsp);
        return 1;
    }
    #debug message.
    my $swinfostr = Dumper(%swinfo);
    xCAT::MsgUtils->message('S',"swinfo: $swinfostr");
    my $swsetupstr = Dumper(%swsetup);
    xCAT::MsgUtils->message('S',"swsetup: $swsetupstr");
    
    # Do actual configurations on switches
    if (!$delete) {
        ### add ports to the vlan
        if (!add_ports($vlan_id, \%swinfo, $callback, 1)) { return 1;}
        xCAT::MsgUtils->message('S',"Adding ports to switch success!");

        ### add the cross-over ports to the vlan
        my @sws=keys(%swinfo);;
        #get all the switches  that are in the vlan
        my $swtab=xCAT::Table->new("switch", -create =>0);
        if ($swtab) {
            my @tmp1=$swtab->getAllAttribs('switch', 'vlan');
            if ((@tmp1) && (@tmp1 > 0)) {
                foreach my $item (@tmp1) {
                    my $vlan=$item->{vlan};
                    my $sw=$item->{switch};
                    if ($vlan) {
                        my @a=split(",",$vlan);
                        if (grep(/^$vlan_id$/, @a)) {
                            if (!grep(/^$sw$/, @sws)) {
                                push(@sws, $sw);
                            }
                        }
                    }
                }
            }
        }
        if (!add_crossover_ports($vlan_id, \@sws, $callback)) { return 1;}
        xCAT::MsgUtils->message('S',"Configuring cross over ports success!");
	
        #add the vlanid for the standalone nodes on the switch table
        #append the vlan id for the vmhosts on the switch table
        add_vlan_to_switch_table(\%swsetup, $vlan_id); 
        xCAT::MsgUtils->message('S',"Adding vlan to switch table success!");
        
        # done
        my $rsp={};
        $rsp->{data}->[0]= "The interface $nic of following nodes are added to the vlan $vlan_id:\n@nodes";
        $callback->($rsp);
        
    } else{
        ### remove ports from the vlan
        my $novmhost=1;
        if (!remove_ports($vlan_id, \%swinfo, $callback, $novmhost)) { return 1;}
        xCAT::MsgUtils->message('S',"Removing ports from vlan success!");
 
        #remove the vlan id from the switch table.
        remove_vlan_from_switch_table(\%swsetup,$vlan_id);
        xCAT::MsgUtils->message('S',"Removing ports from switch table success!");
        
        # done
        my $rsp={};
        $rsp->{data}->[0]= "The interface $nic of following nodes are removed from the vlan $vlan_id:\n@nodes";
        $callback->($rsp);
    }
    return 0;
}

sub process_chvlan {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;

    my $vlan_id=0;
    if (exists($request->{vlanid})) {
        $vlan_id=$request->{vlanid}->[0];
    }
    if ($vlan_id == 0) {
        my $rsp={};
        $rsp->{error}->[0]= "Invalid vlan id: $vlan_id";
        $callback->($rsp);
        return;
    }
    
    my $nic;
    if (exists($request->{nic})) {
        $nic=$request->{nic}->[0];
    } 

    my @nodes=();
    if (exists($request->{node})) {
        @nodes=@{$request->{node}};
    }

    my $delete=0;
    if (exists($request->{delete})) {
        $delete=$request->{delete}->[0];
    }
    my $net;
    my $netmask;
    #check if the vlan is already defined on the table 
    my $found=0;
    my $nwtab=xCAT::Table->new("networks", -create =>1);
    if ($vlan_id > 0) {
        if ($nwtab) {
            my @tmp1=$nwtab->getAllAttribs(('vlanid', 'net', 'mask'));
            if ((@tmp1) && (@tmp1 > 0)) {
                foreach(@tmp1) {
                    if ($vlan_id eq $_->{vlanid}) {
                        $found=1;
                        $net=$_->{net};
                        $netmask=$_->{mask};
                    }
                }
	        }
        }
    }
    if (!$found) {
        my $rsp = {};
        $rsp->{data}->[0] = "The vlan $vlan_id does not exist.";
        $callback->($rsp);
        return 1;
    }

    if ((!$net) || (!$netmask)) {
        my $rsp = {};
        $rsp->{data}->[0] = "Please make sure subnet and netmask are specified on the networks table for vlan $vlan_id.";
        $callback->($rsp);
        return 1;
    }

    ####now get the switch ports for the nodes
    my %swinfo=();  # example: %swinfo=( switch1=>{ 23=>{ nodes: [node1]},
                         #                          24=>{ nodes: [node2,node3], 
                         #                                        vmhost: kvm1
                         #                              }
                         #                         },
                         #               switch12=>{ 3=>{ nodes: [node4]},
                         #                           7=>{ nodes: [node5]}, 
                         #                           9=>{ nodes: [node6]}
                         #                        }
                         #             )

    my %vminfo=();       # example: %vminfo=( kvm1=>{clients:[node1,node2...]},
                         #                    kvm2=>{clients:[node2,node3...]},
                         #                   )
                         #                  
    my @vmnodes=();      # vm clients
    my @snodes=();       # stand alone nodes

    
    #get the vm hosts  
    my $vmtab=xCAT::Table->new("vm", -create =>1);
    my $vmtmphash = $vmtab->getNodesAttribs(\@nodes, ['host','nics']) ;
    foreach(@nodes) {
        my $node=$_;
        my $host;
        my $ent=$vmtmphash->{$node}->[0];
        if (ref($ent) and defined $ent->{host}) { 
            $host = $ent->{host}; 
            if (exists($vminfo{$host})) {
                my $pa=$vminfo{$host}->{clients};
                push(@$pa, $node);
            } else {
                $vminfo{$host}->{clients}=[$node];
            }
	        push(@vmnodes, $node);
	    }
    }
   
    if (@vmnodes > 0) {
        foreach my $node (@nodes) {
            if (! grep /^$node$/, @vmnodes) {
                push(@snodes, $node);
            }
        }
    } else {
        @snodes=@nodes;
    }
 
    #get the switch and port numbers for each node
    my @vmhosts=keys(%vminfo);
    my @anodes=(@snodes, @vmhosts); #nodes that connects to the switch
    my %swsetup=();
    my $swtab=xCAT::Table->new("switch", -create =>1);
    my $swtmphash = $swtab->getNodesAttribs(\@anodes, ['switch', 'port', 'vlan', 'interface']) ;
    my @missed_nodes=();
    foreach my $node (@anodes) {
        my $switch;
        my $port;
        my $node_enties=$swtmphash->{$node}; 
        if ($node_enties) {
            my $i=-1;
            my $use_this=0;
            foreach my $ent (@$node_enties) {
                $i++;
                if (ref($ent) and defined $ent->{switch} and defined $ent->{port}) { 
                    $switch = $ent->{switch};
                    $port = $ent->{port};
                    my $interface="primary";		    
                    if (defined $ent->{interface}) { $interface=$ent->{interface};}
                    # for primary nic, the interface can be empty, "primary" or "primary:eth0"		   
                    if ($delete) {
                        if (defined($ent->{vlan})) {
                            my @a=split(',', $ent->{vlan});
                            if (grep(/^$vlan_id$/, @a)) {  $use_this=1; }
                        }			
                    } else {
                        if ($nic) {
                            if ($interface =~ /primary/) {
                                $interface =~ s/primary(:)?//g;
                            }
                            if ($interface && ($interface eq $nic)) { $use_this=1; }
                        } else {
                            if ($interface =~ /primary/) {  $use_this=1; }
                        } 
                    }
		    
                    if (! $use_this) { 
                        next; 
                    } else { 
                        $swsetup{$node}->{port}=$port;
                        $swsetup{$node}->{switch}=$switch;
                        if (defined $ent->{vlan}) { 
                            $swsetup{$node}->{vlan}=$ent->{vlan};
                        } else {
                            $swsetup{$node}->{vlan}="";
                        }
                    }

                    if ($interface) { 			
                        $swinfo{$switch}->{$port}->{interface}=$interface;
                    }
		    
                    if (exists($vminfo{$node})) {
                        $swinfo{$switch}->{$port}->{vmhost}=$node;
                        $swinfo{$switch}->{$port}->{nodes}=$vminfo{$node}->{clients};
                    } else {
                        $swinfo{$switch}->{$port}->{nodes}=[$node];
                    }
                    last;
                } 
            }
            if ( $use_this != 1 ) {
                push (@missed_nodes, $node);
            }
        }
    }

    if (@missed_nodes > 0) {
        my $rsp={};
        $rsp->{error}->[0]= "Cannot proceed, please define switch and port info on the switch table for the following nodes:\n  @missed_nodes\n";
        $callback->($rsp);
        return 1;
    }
    
    #print "vminfo=" . Dumper(%vminfo) . "\n";
    #print "swinfo=" . Dumper(%swinfo) . "\n";
    #print "anodes=" . Dumper(@anodes) . "\n";
    #print "vmnodes=" . Dumper(@vmnodes) . "\n";

    if (!$delete) {
        ### verify the ports are not used by other vlans
        #if (!verify_switch_ports($vlan_id, \%swinfo, $callback)) { return 1;}
	
        ###create the vlan if it does not exist 
         if (!create_vlan($vlan_id, \%swinfo, $callback)) { return 1;}

        ### add ports to the vlan
        if (!add_ports($vlan_id, \%swinfo, $callback)) { return 1;}

        ### add the cross-over ports to the vlan
        my @sws=keys(%swinfo);;
        #get all the switches  that are in the vlan
        my $swtab=xCAT::Table->new("switch", -create =>0);
        if ($swtab) {
            my @tmp1=$swtab->getAllAttribs('switch', 'vlan');
            if ((@tmp1) && (@tmp1 > 0)) {
                foreach my $item (@tmp1) {
                    my $vlan=$item->{vlan};
                    my $sw=$item->{switch};
                    if ($vlan) {
                        my @a=split(",",$vlan);
                        if (grep(/^$vlan_id$/, @a)) {
                            if (!grep(/^$sw$/, @sws)) {
                                push(@sws, $sw);
                            }
                        }
                    }
                }
            }
        }
        if (!add_crossover_ports($vlan_id, \@sws, $callback)) { return 1;}
	
        #add the vlanid for the standalone nodes on the switch table
        #append the vlan id for the vmhosts on the switch table
        add_vlan_to_switch_table(\%swsetup, $vlan_id);   
	
        #we'll derive the prefix and the node numbers from the existing
        #nodes on the vlan
        my ($prefix, $start_number)=get_prefix_and_nodenumber($vlan_id, $net, $netmask);
 
        ### get node ip and vlan hostname from the hosts table. 
        #If it is not defined, put the default into the host table
        my @allnodes=(@anodes, @vmnodes);
        if (!add_vlan_ip_host($net, $netmask, $prefix, $start_number+1, \@allnodes, $callback)) { return 1;}

        ### for vm nodes, add an additional nic on the vm.nics
        if (@vmnodes > 0) {
            my %setupnics=();
            my $new_nic="vl$vlan_id";
            foreach my $node (@vmnodes) {
                my $ent=$vmtmphash->{$node}->[0];
                my $nics;
                if (ref($ent) and defined $ent->{nics}) { 
                    $nics=$ent->{nics};
                    my @a=split(",", $nics);
                    if (!grep(/^$new_nic$/, @a)) { $nics="$nics,$new_nic"; }
                } else {
                    $nics=$new_nic;
                }
                $setupnics{$node}={nics=>"$nics"};
            }
            $vmtab->setNodesAttribs(\%setupnics);
        }

        ### populate the /etc/hosts and make the DNS server on the mn aware this change
        $::CALLBACK = $callback;
        my $res = xCAT::Utils->runxcmd({
                                        command => ['makehosts'],
                                       }, $sub_req, 0, 1);
        my $rsp = {};
        $rsp->{data}->[0] = "Running makehosts...";
        $callback->($rsp);
        if ($res && (@$res > 0)) {
            $rsp = {};
            $rsp->{data} = $res;
            $callback->($rsp);
        }
        $callback->($rsp);
	
        $::CALLBACK = $callback;
        my $res = xCAT::Utils->runxcmd({
                                        command => ['makedns'],
                                       }, $sub_req, 0, 1);
	
        my $rsp = {};
        $rsp->{data}->[0] = "Running makedns...";
        if ($res && (@$res > 0)) {
            $callback->($rsp);
            $rsp->{data} = $res;
            $callback->($rsp);
        }
	
        my $cmd = "service named restart";
        my $rc=system $cmd;
	
        ### now go to the nodes to configure the vlan interface
        $::CALLBACK = $callback;
        my $args = ["-P", "configvlan $vlan_id --keephostname"]; 
        my $res = xCAT::Utils->runxcmd( {
                                          command => ['updatenode'],
                                          node    => \@snodes,
                                          arg     => $args
                                        }, $sub_req, 0, 1);
        my $rsp = {};
        $rsp->{data}->[0] = "Running updatenode...";
        if ($res && (@$res > 0)) {
            $callback->($rsp);
            $rsp->{data} = $res;
            $callback->($rsp);
        }
	
        ### add configvlan postscripts to the postscripts table for the node
        my @pnodes=(@snodes, @vmnodes);
        add_postscript($callback, \@pnodes);
	
        # done
        my $rsp={};
        $rsp->{data}->[0]= "The following nodes are added to the vlan $vlan_id:\n@nodes";
        $callback->($rsp);
    } else {
        ### go to the nodes to de-configure the vlan interface
        if (@snodes > 0) {
            my $args = ["-P", "deconfigvlan $vlan_id"];
            my $res = xCAT::Utils->runxcmd(  {
                                              command => ['updatenode'],
                                              node    => \@snodes,
                                              arg     => $args
                                             }, $sub_req, 0, 1);
            my $rsp = {};
            $rsp->{data}->[0] = "Running updatenode...";
            if ($res && (@$res > 0)) {
                $callback->($rsp);
                $rsp->{data} = $res;
                $callback->($rsp);
            }
        }

        ### remove ports from the vlan
        my $novmhost=1;
        if (!remove_ports($vlan_id, \%swinfo, $callback, $novmhost)) { return 1;}
 
        #remove the vlan id from the switch table for standalone nodes
        #cannot call this function because %swsetup contains vmhosts
        #remove_vlan_from_switch_table(\%swsetup,$vlan_id); 
        #print "swsetup=". Dumper(%swsetup);
        my $swtab1 = xCAT::Table->new('switch', -create=>1, -autocommit=>0 );
        foreach my $node (@snodes) {
            if (exists($swsetup{$node})) {
                my %keyhash=();
                my %updates=();
                $keyhash{'node'} = $node;
                $keyhash{'switch'}= $swsetup{$node}->{switch};
                $keyhash{'port'} = $swsetup{$node}->{port};
                $updates{'vlan'} = "";
                if($swsetup{$node}->{vlan}) {
                    my @a=split(',', $swsetup{$node}->{vlan});
                    my @b=grep(!/^$vlan_id$/,@a);
                    if (@b>0) {
                        $updates{'vlan'}=join(',', @b);
                    }
                }
                $swtab1->setAttribs( \%keyhash,\%updates );
            }
        }
        $swtab1->commit;

        #remove the vlan from the vm.nic for vm clients
        if (@vmnodes > 0) {
            my %setupnics=();
            my $new_nic="vl$vlan_id";
            foreach my $node (@vmnodes) {
                my $ent=$vmtmphash->{$node}->[0];
                my $nics='';
                if (ref($ent) and defined $ent->{nics}) { 
                    $nics=$ent->{nics};
                    my @a=split(",", $nics);
                    my @b=grep(!/^$new_nic$/, @a);
                    if (@b>0) { $nics=join(',', @b); }
                }
                $setupnics{$node}={nics=>"$nics"};
            }
            $vmtab->setNodesAttribs(\%setupnics);
        }
	
        #remove the node's vlan hostname and the ip from the host table and /etc/hosts
        my @pnodes=(@snodes, @vmnodes);
        if (!remove_vlan_ip_host($net, $netmask, \@pnodes, $callback)) { return 1;}

        #refresh the DNS server
        my $res = xCAT::Utils->runxcmd(  {
                                           command => ['makedns'],
                                         }, $sub_req, 0, 1);
        my $rsp = {};
        $rsp->{data}->[0] = "Running makedns...";
        if ($res && (@$res > 0)) {
            $callback->($rsp);
            $rsp->{data} = $res;
            $callback->($rsp);
        }
        my $cmd = "service named restart";
        my $rc=system $cmd;
	
        # remove configvlan postscripts from the postscripts table for the node
        remove_postscript($callback, \@pnodes);	

        # done
        my $rsp={};
        $rsp->{data}->[0]= "The following nodes are removed from the vlan $vlan_id:\n@nodes";
        $callback->($rsp);
    }
    return 0;
}



sub process_rmvlan {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    
    my $vlan_id=0;
    if (exists($request->{vlanid})) {
	$vlan_id=$request->{vlanid}->[0];
    }

    my @anodes=();
    my %swportinfo=();
    my %swsetup=();
    my $swtab=xCAT::Table->new("switch", -create =>0);
    if ($swtab) {
	my @tmp1=$swtab->getAllAttribs(('node', 'switch', 'port', 'vlan'));
	if ((@tmp1) && (@tmp1 > 0)) {
	    foreach my $ent (@tmp1) {
		my @nodes_tmp=noderange($ent->{node});
		foreach my $node (@nodes_tmp) {
		    my $switch=$ent->{switch};
		    my $port=$ent->{port};
		    if ($ent->{vlan}) {
			my @a=split(",", $ent->{vlan});
			if (grep(/^$vlan_id$/,@a)) {
			    push(@anodes, $node);
			    if (exists($swportinfo{$switch})) {
				my $pa=$swportinfo{$switch};
				push(@$pa, $port);
			    } else {
				$swportinfo{$switch}=[$port];
			    }
			    $swsetup{$node}->{port}=$port;
			    $swsetup{$node}->{switch}=$switch;
			    $swsetup{$node}->{vlan}=$ent->{vlan};
			}
		    }
		}
	    }
	}
    }

    my $switchestab=xCAT::Table->new('switches',-create=>0);
    if ($switchestab) {
	my @tmp1=$switchestab->getAllAttribs(('switch'));
	if ((@tmp1) && (@tmp1 > 0)) {
	    foreach(@tmp1) {
		my @switches_tmp=noderange($_->{switch});
		if (@switches_tmp==0) { push @switches_tmp, $_->{switch}; } #sometimes the switch name is not on the node list table.  
		foreach my $switch (@switches_tmp) {
		    my $ports=[];
		    if (exists($swportinfo{$switch})) {
			$ports = $swportinfo{$switch};
		    }
		    
		    my $swh;
		    if (exists($Switches{$switch})) { $swh=$Switches{$switch};}
		    else {
			$swh=new xCAT::SwitchHandler->new($switch);
			$Switches{$switch}=$swh;
		    }
		
		    print "switch=$switch, ports=@$ports\n";
		    if (@$ports > 0) {
			my @ret=$swh->remove_ports_from_vlan($vlan_id, @$ports);
			if ($ret[0] != 0) {
			    my $rsp={};
			    $rsp->{error}->[0]= "remove_ports_from_vlan: $ret[1]";
			    $callback->($rsp);
			}
		    
			my @ret=$swh->remove_vlan($vlan_id);
			if ($ret[0] != 0) {
			    my $rsp={};
			    $rsp->{error}->[0]= "remove_vlan: $ret[1]";
			    $callback->($rsp);
			}
		    } else { 
			#check if the vlan exists on the switch
			my @ids=$swh->get_vlan_ids(); 
			foreach my $id (@ids) {
			    if ($id == $vlan_id) { 
				#remove it if exists
				my @ret=$swh->remove_vlan($vlan_id);
				if ($ret[0] != 0) {
				    my $rsp={};
				    $rsp->{error}->[0]= "remove_vlan: $ret[1]";
				    $callback->($rsp);
				}
				last; 
			    }
			}
		    }
		}
	    }
	}
    }

    ### now go to the nodes to de-configure the vlan interface
    my $args = ["-P", "deconfigvlan $vlan_id"];
    my $res = xCAT::Utils->runxcmd(  {
            command => ['updatenode'],
	    node    => \@anodes,
	    arg     => $args
            }, $sub_req, 0, 1);
    my $rsp = {};
    $rsp->{data}->[0] = "Running updatenode...";
    if ($res && (@$res > 0)) {
	$callback->($rsp);
	$rsp->{data} = $res;
	$callback->($rsp);
    }

    #remove the vlan from the networks table
    my $nwtab=xCAT::Table->new("networks", -create =>1);
    my $sent = $nwtab->getAttribs({vlanid=>"$vlan_id"},'net','mask');
    my $net;
    my $netmask;
    if ($sent and ($sent->{net})) {
	$net=$sent->{net};
	$netmask=$sent->{mask};
    } 
    
    my %key_col = (vlanid=>$vlan_id);
    $nwtab->delEntries(\%key_col);
 
    #remove the vlan from the switch table for standalone nodes and vm hosts
    remove_vlan_from_switch_table(\%swsetup,$vlan_id);   

    #remove the vlan nic from vm.nics for the vm clients
    my @vmnodes=();
    my %vmsetup=();
    my $vmtab=xCAT::Table->new("vm", -create =>0);
    if ($vmtab) {
	my @tmp1=$vmtab->getAllAttribs(('node','host', 'nics'));
	if ((@tmp1) && (@tmp1 > 0)) {
	    foreach(@tmp1) {
		my @nodes_tmp=noderange($_->{node});
		my $nics=$_->{nics};
		my $new_nic="vl$vlan_id";
		if ($nics) {
		    foreach my $node (@nodes_tmp) {
			my @a=split(",", $nics);
			if (grep(/^$new_nic$/,@a)) {
			    push(@vmnodes, $node);
			    my @b=grep(!/^$new_nic$/,@a);
			    if (@b>0) {
				$vmsetup{$node}={nics=>join(',', @b)};
			    } else {
				$vmsetup{$node}={nics=>''};
			    }
			}
		    }
		}
	    }
	}
	if (keys(%vmsetup) > 0) {
	    $vmtab->setNodesAttribs(\%vmsetup);
	}
    }
    
 

    #remove the node's vlan hostname and the ip from the host table and /etc/hosts
    my @allnodes=(@anodes, @vmnodes);
    if (!remove_vlan_ip_host($net, $netmask, \@allnodes, $callback)) { return 1;}

    #refresh the DNS server
    my $res = xCAT::Utils->runxcmd(  {
            command => ['makedns'],
            }, $sub_req, 0, 1);
    my $rsp = {};
    $rsp->{data}->[0] = "Running makedns...";
    if ($res && (@$res > 0)) {
	$callback->($rsp);
	$rsp->{data} = $res;
	$callback->($rsp);
    }
    my $cmd = "service named restart";
    my $rc=system $cmd;

    ### remove configvlan postscripts from the postscripts table for the node
    #   note: if configvlan is in xcatdefaults, it will not get removed becase 
    #   it may affect other vlans
    #remove_postscript($callback, \@allnodes);  --- will not remove for multi-vlan support
}

#-------------------------------------------------------
=head3  remove_postscript

    It removes configvlan postscripts from the postscripts table for the node
    Note: if configvlan is in xcatdefaults, it will not get removed becase 
       it may affect other vlans

=cut
#-------------------------------------------------------
sub  remove_postscript {
    my $callback=shift;
    my $anodes=shift;
    my $posttab=xCAT::Table->new("postscripts", -create =>0);
    if ($posttab) {
	my %setup_hash;
	my $postcache = $posttab->getNodesAttribs($anodes,[qw(postscripts postbootscripts)]);
	foreach my $node (@$anodes) {
	    my $ref = $postcache->{$node}->[0]; 
	    if ($ref) {
		if (exists($ref->{postbootscripts})) {
		    my $post=$ref->{postbootscripts};
		    my @old_a=split(',', $post);
		    my @new_a = grep (!/^configvlan$/, @old_a);
		    if (scalar(@new_a) != scalar(@old_a)) {
			#print "newa =@new_a\n";
			$setup_hash{$node}={postbootscripts=>join(',', @new_a)};
		    }
		}
		if (exists($ref->{postscripts})) {
		    my $post=$ref->{postscripts};
		    my @old_a=split(',', $post);
		    my @new_a = grep (!/^configvlan$/, @old_a);
		    if (scalar(@new_a) != scalar(@old_a)) {
			$setup_hash{$node}={postscripts=>join(',', @new_a)};
		    }
		}
	    }
	}
	if (keys(%setup_hash) > 0) {
	    $posttab->setNodesAttribs(\%setup_hash);
	}
    }   
}

sub process_lsvlan {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    
    my $vlan_id=0;
    if (exists($request->{vlanid})) {
	$vlan_id=$request->{vlanid}->[0];
    }
   
    my %vlans=();
    #get all the vm clients if the node is a vm host
    my $nwtab=xCAT::Table->new("networks", -create =>0);
    if ($nwtab) {
	my @tmp1=$nwtab->getAllAttribs('net', 'mask', 'vlanid');
	if ((@tmp1) && (@tmp1 > 0)) {
	    foreach(@tmp1) {
		if (exists($_->{vlanid})) {
		    $vlans{$_->{vlanid}}->{net}=$_->{net};
	            $vlans{$_->{vlanid}}->{mask}=$_->{mask};
		}
	    }
	}
    }
   
    if($vlan_id !=0 && !exists($vlans{$vlan_id})) {
	my $rsp={};
        $rsp->{data}->[0] = "the vlan $vlan_id is not defined for the cluster nodes.";
        $rsp->{errorcode} = -1;
	$callback->($rsp);
        return;
    }
	
    if ($vlan_id == 0) { #just show the existing vlan ids
	my $rsp={};
	my $index=0;
	if (keys(%vlans) > 0) {
	    foreach my $id (sort keys(%vlans)) {
		$rsp->{data}->[$index] = "vlan $id:\n    subnet " . $vlans{$id}->{net}. "\n    netmask " . $vlans{$id}->{mask} . "\n";
		$index++;
	    }
	} else {
	    $rsp->{data}->[0] = "No vlans defined for the cluster nodes."
	}
	$callback->($rsp);

    } else { #shows the details
	#get all the nodes that are in the vlan
	my $swtab=xCAT::Table->new("switch", -create =>0);
	my @nodes=();
	if ($swtab) {
	    my @tmp1=$swtab->getAllAttribs('node', 'vlan', 'interface');
	    if ((@tmp1) && (@tmp1 > 0)) {
		foreach my $grp (@tmp1) {
		    my $vlan=$grp->{vlan};
		    my $nic="primary";
		    if ($grp->{interface}) { $nic=$grp->{interface};}

		    my @nodes_tmp=noderange($grp->{node});
		    if ($vlan) {
			my @a=split(",",$vlan);
			if (grep(/^$vlan_id$/, @a)) {
			    foreach my $node (@nodes_tmp) {
				push(@nodes, $node);
				$vlans{$vlan_id}->{node}->{$node}->{name} = $node;
				$vlans{$vlan_id}->{node}->{$node}->{interface} = $nic;
			    }
			}
		    }
		}
	    }
	}

	
	#get all the vm clients if the node is a vm host
	my $vmtab=xCAT::Table->new("vm", -create =>0);
	my @vmnodes=();
	if ($vmtab) {
	    my @tmp1=$vmtab->getAllAttribs('node', 'host', 'nics');
	    if ((@tmp1) && (@tmp1 > 0)) {
		my $new_nic="vl$vlan_id";
		foreach(@tmp1) {
		    my $host = $_->{host};
		    my $nics = $_->{nics};
		    if ($nics) {
			my @a=split(",", $nics);
			if (grep(/^$new_nic$/, @a)) {
			    my @nodes_tmp=noderange($_->{node});
			    foreach my $node (@nodes_tmp) {
				push(@vmnodes, $node);
				$vlans{$vlan_id}->{node}->{$node}->{name} = $node;
				$vlans{$vlan_id}->{node}->{$node}->{vmhost} = $host;
			    }
			}
		    }
		}
	    }
	}
	
	@nodes=(@nodes, @vmnodes);
	
	#now go to hosts table to get the host name and ip on the vlan
	my $hoststab = xCAT::Table->new('hosts');
	my $hostscache = $hoststab->getNodesAttribs(\@nodes,[qw(node otherinterfaces)]);
	my $max=0;
	my $prefix;
	foreach my $node (@nodes) {
	    my $ref = $hostscache->{$node}->[0]; 
	    my $otherinterfaces;
	    if ($ref && exists($ref->{otherinterfaces})){
		$otherinterfaces = $ref->{otherinterfaces};
		my @itf_pairs=split(/,/, $otherinterfaces);
		my @itf_pairs2=();
		foreach (@itf_pairs) {
		    my ($name,$ip)=split(/:/, $_);
		    if(xCAT::NetworkUtils->ishostinsubnet($ip, $vlans{$vlan_id}->{mask}, $vlans{$vlan_id}->{net})) {
			$vlans{$vlan_id}->{node}->{$node}->{ip}=$ip;
			$vlans{$vlan_id}->{node}->{$node}->{vname}=$name;
		    }
		}
	    }
	} #foreach node

	my $rsp={};
	$rsp->{data}->[0]="vlan $vlan_id";
        $rsp->{data}->[1]="    subnet " . $vlans{$vlan_id}->{net};
        $rsp->{data}->[2]="    netmask " . $vlans{$vlan_id}->{mask} . "\n";
	my $node_hash=$vlans{$vlan_id}->{node};
	#print Dumper($node_hash);
	if ($node_hash && keys(%$node_hash) > 0) {
	    $rsp->{data}->[3]="    hostname\tip address\tnode    \tvm host \tinterface";
	    my $index=4;
	    foreach (sort keys(%$node_hash)) {
		my $vname=$node_hash->{$_}->{vname};
		if (!$vname) { $vname="      ";}
		my $ip=$node_hash->{$_}->{ip};
		if (!$ip) { $ip="               "; }
		my $name=$node_hash->{$_}->{name};
		if (!$name) { $name="      ";}	   
		my $host=$node_hash->{$_}->{vmhost};
		if (!$host) { $host="        ";}	  
		my $nic=$node_hash->{$_}->{interface};
		$rsp->{data}->[$index] = "    $vname\t$ip\t$name\t$host\t$nic";
		$index++;
	    }
	}
	$callback->($rsp);
    } 
}

sub mkvlan_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: mkvlan -h";
    $rsp->{data}->[1]= "       mkvlan -v";
    $rsp->{data}->[2]= "       mkvlan [vlanid] -n noderange [-t net -m mask] [-p node_prefix] [-i nic]";

    $cb->($rsp);
}

sub rmvlan_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: rmvlan -h";
    $rsp->{data}->[1]= "       rmvlan -v";
    $rsp->{data}->[2]= "       rmvlan vlanid";

    $cb->($rsp);
}

sub chvlanports_usage{
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: chvlanports -h";
    $rsp->{data}->[1]= "       chvlanports -v";
    $rsp->{data}->[2]= "       chvlanports vlanid -n noderange -i nic";
    $rsp->{data}->[3]= "       chvlanports vlanid -n noderange -i nic -d";
    $cb->($rsp);
}
sub chvlan_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: chvlan -h";
    $rsp->{data}->[1]= "       chvlan -v";
    $rsp->{data}->[2]= "       chvlan vlanid -n noderange [-i nic]";
    $rsp->{data}->[3]= "       chvlan vlanid -n noderange -d";
    $cb->($rsp);
}

sub lsvlan_usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: lsvlan -h";
    $rsp->{data}->[1]= "       lsvlan -v";
    $rsp->{data}->[2]= "       lsvlan";
    $rsp->{data}->[3]= "       lsvlan vlanid";

    $cb->($rsp);
}

#-------------------------------------------------------
=head3  getNodeVlanConfData
   This function is called by Postage.pm to collect all the 
   environmental variables for setting up a vlan for a given 
   node.  
=cut
#-------------------------------------------------------
sub getNodeVlanConfData {
    my $node=shift;
    if ($node =~ /xCAT_plugin::vlan/) {
	$node=shift;
    }

    my @scriptd=();
    my $swtab = xCAT::Table->new("switch", -create => 0);
    if ($swtab) {
	my $tmp_switch = $swtab->getNodesAttribs([$node], ['vlan','interface'],prefetchcache=>1);
        #print Dumper($tmp_switch);
	if (defined($tmp_switch) && (exists($tmp_switch->{$node})) && (defined($tmp_switch->{$node}->[0]))) { 
	    my $tmp_node_array=$tmp_switch->{$node};
	    my $index=0;
	    foreach my $tmp (@$tmp_node_array) {
		if (exists($tmp->{vlan})) {
		    my $nic="primary";
		    if (exists($tmp->{interface})) { $nic=$tmp->{interface};}
		    my @vlanid_array = split(',', $tmp->{vlan});
		    foreach my $vlan (@vlanid_array) {
			$index++;
			push @scriptd, "VLANID_$index='" . $vlan . "'\n";
			push @scriptd, "export VLANID_$index\n";
			push @scriptd, "VLANNIC_$index='" . $nic . "'\n";
			push @scriptd, "export VLANNIC_$index\n";
			my @temp_data=getNodeVlanOtherConfData($node, $vlan, $index);
			@scriptd = (@scriptd,@temp_data);
		    } 
		}
	    }
	    if ($index > 0) { 
		push @scriptd, "VLANMAXINDEX='" . $index . "'\n";
		push @scriptd, "export VLANMAXINDEX\n";
	    }   
	} else {
	    my $vmtab = xCAT::Table->new("vm", -create => 0);
	    if ($vmtab) {
		my $tmp1 = $vmtab->getNodeAttribs($node, ['nics','host'],prefetchcache=>1);
		
		my $vlan;
		my $index=0;
		if (defined($tmp1) && ($tmp1) && $tmp1->{nics})
		{
		    push @scriptd, "VMNODE='YES'\n";
		    push @scriptd, "export VMNODE\n";
		    push @scriptd, "VMNICS='" . $tmp1->{nics} . "'\n";
		    push @scriptd, "export VMNICS\n";
		    
		    my @nics=split(',', $tmp1->{nics});

		    #get the vlan id and interface from the host
		    my $host=$tmp1->{host};
		    #my $host_vlan_info=get_vm_host_vlan_info($host);
                    my $nic_position=0;
		    foreach my $nic (@nics) {
			$nic_position++;
			if ($nic =~ /^vl([\d]+)$/) {
			    $vlan = $1;
			    $index++;
			    push @scriptd, "VLANID_$index='" . $vlan . "'\n";
			    push @scriptd, "export VLANID_$index\n";
			    push @scriptd, "VLAN_VMNICPOS_$index='" . $nic_position . "'\n";
			    push @scriptd, "export VLAN_VMNICPOS_$index\n";
			    #if ($host_vlan_info && (exists($host_vlan_info->{$vlan}))) {
			    #	push @scriptd, "HOST_VLANNIC_$index='" . $host_vlan_info->{$vlan} . "'\n";
			    #	push @scriptd, "export HOST_VLANNIC_$index\n";
			    #}
			    my @temp_data=getNodeVlanOtherConfData($node, $vlan, $index);
			    @scriptd = (@scriptd,@temp_data); 
			}
   		    } #end foreach
		}
		if ($index > 0) { 
		    push @scriptd, "VLANMAXINDEX='" . $index . "'\n";
		    push @scriptd, "export VLANMAXINDEX\n";
		}		
	    }
	}
    }
    
    return @scriptd;
}

sub getNodeVlanOtherConfData {
    my $node=shift;
    if ($node =~ /xCAT_plugin::vlan/) {
	$node=shift;
    }
    my $vlan=shift;
    my $index=shift;

    my @scriptd=();
    my $nwtab=xCAT::Table->new("networks", -create =>0);
    if ($nwtab) {
	my $sent = $nwtab->getAttribs({vlanid=>"$vlan"},'net','mask');
	my $subnet;
	my $netmask;
	if ($sent and ($sent->{net})) {
	    $subnet=$sent->{net};
	    $netmask=$sent->{mask};
	} 
	if (($subnet) && ($netmask)) {
	    my $hoststab = xCAT::Table->new("hosts", -create => 0);
	    if ($hoststab) {
		my $tmp = $hoststab->getNodeAttribs($node, ['otherinterfaces'],prefetchcache=>1);
		if (defined($tmp) && ($tmp) && $tmp->{otherinterfaces})
		{
		    my $otherinterfaces = $tmp->{otherinterfaces};
		    my @itf_pairs=split(/,/, $otherinterfaces);
		    foreach (@itf_pairs) {
			my ($name,$ip)=split(/:/, $_);
			if(xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet)) {
			    if ($name =~ /^-/ ) {
				$name = $node.$name;
			    }
			    push @scriptd, "VLANHOSTNAME_$index='" . $name . "'\n";
			    push @scriptd, "export VLANHOSTNAME_$index\n";
			    push @scriptd, "VLANIP_$index='" . $ip . "'\n";
			    push @scriptd, "export VLANIP_$index\n";
			    push @scriptd, "VLANSUBNET_$index='" . $subnet . "'\n";
			    push @scriptd, "export VLANSUBNET_$index\n";
			    push @scriptd, "VLANNETMASK_$index='" . $netmask . "'\n";
			    push @scriptd, "export VLANNETMASK_$index\n";
			    last;
			}
		    }	    
		}
	    }
	}
    }
    
    return @scriptd;
}

#-------------------------------------------------------
=head3  get_vm_host_vlan_info
   This function returns a hash pointer that has the vlan id
   and the interface info for the given KVM host. A host can
   support more than one vlans for a interface. For example:
   {1=>"eth0", 2=>"eth0", 3=>"eth1" ...}
=cut
#-------------------------------------------------------
sub get_vm_host_vlan_info {
    my $host=shift;
    my $host_vlan_info={};
    my $swtab = xCAT::Table->new("switch", -create => 0);
    if ($swtab) {
	my $tmp_switch = $swtab->getNodesAttribs([$host], ['vlan','interface'],prefetchcache=>1);
	if (defined($tmp_switch) && (exists($tmp_switch->{$host}))) { 
	    my $tmp_node_array=$tmp_switch->{$host};
	    foreach my $tmp (@$tmp_node_array) {
		if (exists($tmp->{vlan})) {
		    my $vlans = $tmp->{vlan};
		    my $nic="primary";
		    if (exists($tmp->{interface})) {
			$nic=$tmp->{interface};
		    }
		    foreach my $vlan (split(',',$vlans)) {
			$host_vlan_info->{$vlan}=$nic;
		    }
		}
	    }
	}
	return $host_vlan_info;  
    }
}
