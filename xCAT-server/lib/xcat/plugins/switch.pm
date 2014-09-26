# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::switch;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";


use IO::Socket;
use Data::Dumper;
use xCAT::MacMap;
use xCAT::NodeRange;
use Sys::Syslog;
use xCAT::Usage;
use Storable;
use xCAT::MellanoxIB;
require xCAT::TableUtils;
require xCAT::ServiceNodeUtils;

my $macmap;
sub handled_commands {
    return {
	findme => 'switch',
	findmac => 'switch',
	rspconfig => 'nodehm:mgt',
    };
}

sub preprocess_request { 
  my $request = shift;
  if (defined $request->{_xcatpreprocessed}->[0] and $request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }

  my $callback=shift;
  my @requests;

  my $noderange = $request->{node}; 
  my $command = $request->{command}->[0];
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }

  if ($command eq "rspconfig") {
      my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
      if ($usage_string) {
	  $callback->({data=>$usage_string});
	  $request = {};
	  return;
      }
      if (!$noderange) {
	  $usage_string=xCAT::Usage->getUsage($command);
	  $callback->({data=>$usage_string});
	  $request = {};
	  return;
      }   

      #make sure all the nodes are switches
      my $switchestab=xCAT::Table->new('switches',-create=>0);
      my @all_switches;
      my @tmp=$switchestab->getAllAttribs(('switch'));
      if (@tmp && (@tmp > 0)) {
	  foreach(@tmp) {
	      my @switches_tmp=noderange($_->{switch});
	      if (@switches_tmp==0) { push @switches_tmp, $_->{switch}; }
	      foreach my $switch (@switches_tmp) {
		 push @all_switches, $switch; 
	      }
	  }
      }
      #print "all switches=@all_switches\n";
      my @wrong_nodes;
      foreach my $node (@$noderange) {
	  if (! grep /^$node$/, @all_switches) {
	      push @wrong_nodes, $node;
	  }
      }
      if (@wrong_nodes > 0) {
	  my $rsp = {};
	  $rsp->{error}->[0] = "The following nodes are not defined in the switches table:\n  @wrong_nodes.";
	  $callback->($rsp);
	  return;
      }

      # find service nodes for requested switch
      # build an individual request for each service node
      my $service  = "xcat";
      my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, $service, "MN");
      
      # build each request for each service node
      foreach my $snkey (keys %$sn)
      {
	  #print "snkey=$snkey\n";
	  my $reqcopy = {%$request};
	  $reqcopy->{node} = $sn->{$snkey};
	  $reqcopy->{'_xcatdest'} = $snkey;
	  $reqcopy->{_xcatpreprocessed}->[0] = 1;
	  push @requests, $reqcopy;
      }
      return \@requests;  
  }
  return [$request];
}

sub process_request {
    my $req = shift;
    my $cb = shift;
    my $doreq = shift;
    unless ($macmap) {
	$macmap = xCAT::MacMap->new();
    }
    my $node;
    my $mac = '';
    if ($req->{command}->[0] eq 'findmac') {
	$mac = $req->{arg}->[0];
	$node = $macmap->find_mac($mac,0);
	$cb->({node=>[{name=>$node,data=>$mac}]});
	return;
    }  elsif ($req->{command}->[0] eq 'rspconfig') {
	return process_switch_config($req, $cb, $doreq);
    } elsif ($req->{command}->[0] eq 'findme') {
	my $ip = $req->{'_xcat_clientip'};
	if (defined $req->{nodetype} and $req->{nodetype}->[0] eq 'virtual') {
	    #Don't attempt switch discovery of a  VM Guest
	    #TODO: in this case, we could/should find the host system 
	    #and then ask it what node is associated with the mac
	    #Either way, it would be kinda weird since xCAT probably made up the mac addy
	    #anyway, however, complex network topology function may be aided by
	    #discovery working.  Food for thought.
	    return;
	}
	my $arptable;
        if ( -x "/usr/sbin/arp") {
            $arptable = `/usr/sbin/arp -n`;
        }
        else{
            $arptable = `/sbin/arp -n`;
        }
	my @arpents = split /\n/,$arptable;
	foreach  (@arpents) {
	    if (m/^($ip)\s+\S+\s+(\S+)\s/) {
		$mac=$2;
		last;
	    }
	}
	my $firstpass=1;
	if ($mac) {
	    $node = $macmap->find_mac($mac,$req->{cacheonly}->[0]);
	    $firstpass=0;
	}
	if (not $node) { # and $req->{checkallmacs}->[0]) {
	    foreach (@{$req->{mac}}) {
		/.*\|.*\|([\dABCDEFabcdef:]+)(\||$)/;
		$node = $macmap->find_mac($1,$firstpass);
		$firstpass=0;
		if ($node) { last; }
	    }
	}
        my $pbmc_node = undef;
        if ($req->{'mtm'}->[0] and $req->{'serial'}->[0]) {
            my $mtms = $req->{'mtm'}->[0]."*".$req->{'serial'}->[0];
            my $tmp_nodes = $::XCATVPDHASH{$mtms};
            foreach (@$tmp_nodes) {
                if ($::XCATPPCHASH{$_}) {
                    $pbmc_node = $_;
                }
            } 
        }
	 
	if ($node) {
	    my $mactab = xCAT::Table->new('mac',-create=>1);
	    $mactab->setNodeAttribs($node,{mac=>$mac});
	    $mactab->close();
	    #my %request = (
	    #  command => ['makedhcp'],
	    #  node => [$node]
	    #);
	    #$doreq->(\%request);
	    $req->{command}=['discovered'];
	    $req->{noderange} = [$node];
            if ($pbmc_node) {
                $req->{pbmc_node} = [$pbmc_node];
            }
	    $req->{discoverymethod} = ['switch'];
	    $doreq->($req); 
	    %{$req}=();#Clear req structure, it's done..
	    undef $mactab;
	} else { 
	    #Shouldn't complain, might be blade, but how to log total failures?
	}
    }
}

sub process_switch_config { 
    my $request = shift;
    my $callback=shift;
    my $subreq=shift;
    my $noderange = $request->{node}; 
    my $command = $request->{command}->[0];
    my $extrargs = $request->{arg};
    my @exargs=($request->{arg});
    if (ref($extrargs)) {
	@exargs=@$extrargs;
    }

    my $subcommand=join(' ', @exargs);
    my $argument;
    ($subcommand,$argument) = split(/=/,$subcommand);
    if (!$subcommand) {
	my $rsp = {};
	$rsp->{error}->[0] = "No subcommand specified.";
	$callback->($rsp);
	return;
    }


    #decide what kind of swith it is
    my $sw_types=getSwitchType($noderange); #hash {type=>[node1,node1...]}
    foreach my $t (keys(%$sw_types)) {
	my $nodes=$sw_types->{$t};
	if (@$nodes>0) {
	    if ($t =~ /Mellanox/i) {
		if (!$argument) {
		    xCAT::MellanoxIB::getConfig($nodes, $callback, $subreq, $subcommand);
		} else {
		    xCAT::MellanoxIB::setConfig($nodes, $callback, $subreq, $subcommand, $argument);
		}
	    } else {
		my $rsp = {};
		$rsp->{error}->[0] = "The following '$t' switches are unsuppored:\n@$nodes";
		$callback->($rsp);
	    }
	}
    }
}

#--------------------------------------------------------------------------------
=head3    getSwitchType
      It determins the swtich vendor and model for the given swith.      
    Arguments:
        noderange-- an array ref to switches.
    Returns:
        a hash ref. the key is the switch type string and the value is an array ref to the swithces t
=cut
#--------------------------------------------------------------------------------
sub getSwitchType {
    my $noderange=shift;
    if ($noderange =~ /xCAT_plugin::switch/) {
	$noderange=shift;
    }

    my $ret={};
    my $switchestab =  xCAT::Table->new('switches',-create=>1);
    my $switches_hash = $switchestab->getNodesAttribs($noderange,['switchtype']);
    foreach my $node (@$noderange) {
	my $type="EtherNet";
	if ($switches_hash) {
	    if ($switches_hash->{$node}-[0]) {
		$type = $switches_hash->{$node}->[0]->{switchtype};
	    }
	}
	if (exists($ret->{$type})) {
	    $pa=$ret->{$type};
	    push @$pa, $node;
	} else {
	    $ret->{$type}=[$node];
	}
    }

    return $ret;
}

1;
