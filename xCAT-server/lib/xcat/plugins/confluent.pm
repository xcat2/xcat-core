# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
#TODO: delete entries not being refreshed if no noderange
package xCAT_plugin::confluent;
use strict;
use warnings;
use xCAT::PasswordUtils;
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use Getopt::Long;
use Sys::Hostname;
use xCAT::SvrUtils;
use Confluent::Client;

use strict;
my %termservers; #list of noted termservers

my $usage_string=
"  makeconfluentcfg [-d|--delete] noderange
  makeconfluentcf [-l|--local]
  makeconfluentcf [-c|--confluent]
  makeconfluentcf 
  makeconfluentcf -h|--help
  makeconfluentcf -v|--version
    -c|--confluent   Configure confluent only on the host.
                     The default goes down to all the confluent instances on
                     the server nodes and set them up
    -l|--local       Configure confluent only on the local system.
                     The default goes down to all the confluent instances on
                     the server nodes and set them up
    -d|--delete      Conserver has the relevant entries for the given noderange removed immediately from configuration
    -h|--help        Display this usage statement.
    -V|--verbose     Verbose mode.
    -v|--version     Display the version number.";

my $version_string=xCAT::Utils->Version(); 

sub handled_commands {
  return {
    makeconfluentcfg => "confluent"
  }
}

sub preprocess_request {
  my $request = shift;
  #if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
  if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
  my $callback=shift;
  my @requests;
  my $noderange = $request->{node}; #Should be arrayref 

  #display usage statement if -h
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }
  @ARGV=@exargs;

  my $isSN=xCAT::Utils->isServiceNode();
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) { $iphash{$_}=1;}

  $Getopt::Long::ignorecase=0;
  #$Getopt::Long::pass_through=1;
  if(!GetOptions(
      'c|confluent' => \$::CONSERVER,
      'l|local'     => \$::LOCAL,
      'h|help'     => \$::HELP,
      'D|debug'     => \$::DEBUG,
      'v|version'  => \$::VERSION,
      'V|verbose'  => \$::VERBOSE)) {
    $request = {};
    return;
  }
  if ($::HELP) {
    $callback->({data=>$usage_string});
    $request = {};
    return;
  }
  if ($::VERSION) {
    $callback->({data=>$version_string});
    $request = {};
    return;
  }
  if ($::LOCAL) {
    if ($noderange && @$noderange>0) {
      $callback->({data=>"Invalid option -l or --local when there are nodes specified."});
      $request = {};
      return;
    }
  }
  if ($::CONSERVER && $::LOCAL) {
      $callback->({data=>"Can not specify -l or --local together with -c or --confluent."});
      $request = {};
      return;
  }
  
  
  # get site master
  my $master=xCAT::TableUtils->get_site_Master();
  if (!$master) { $master=hostname(); }

  my %cons_hash=();
  my $hmtab = xCAT::Table->new('nodehm');
  my @items;
  my $allnodes=1;
  if ($noderange && @$noderange>0) {
    $allnodes=0;
    my $hmcache=$hmtab->getNodesAttribs($noderange,['node', 'serialport','cons', 'conserver']);
    foreach my $node (@$noderange) {
      my $ent=$hmcache->{$node}->[0]; #$hmtab->getNodeAttribs($node,['node', 'serialport','cons', 'conserver']);
      push @items,$ent;
    }
  } else {
    $allnodes=1;
    @items = $hmtab->getAllNodeAttribs(['node', 'serialport','cons', 'conserver']);
  }

  my @nodes=();
  foreach (@items) {
    if (((!defined($_->{cons})) || ($_->{cons} eq "")) and !defined($_->{serialport})) { next;} #skip if 'cons' is not defined for this node, unless serialport suggests otherwise
    if (defined($_->{conserver})) { push @{$cons_hash{$_->{conserver}}{nodes}}, $_->{node};}
    else { push @{$cons_hash{$master}{nodes}}, $_->{node};}
    push @nodes,$_->{node};
  }

  #send all nodes to the MN
  if (!$isSN && !$::CONSERVER) { #If -c flag is set, do not add the all nodes to the management node
    if ($::VERBOSE) {
        my $rsp;
        $rsp->{data}->[0] = "Configuring nodes in confluent on the management node";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    my $reqcopy = {%$request};
    $reqcopy->{'_xcatdest'} = $master;
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    $reqcopy->{'_allnodes'} = $allnodes; # the original command comes with nodes or not
    if ($allnodes==1) { @nodes=(); }
    $reqcopy->{node} = \@nodes;
    push @requests, $reqcopy;
    if ($::LOCAL) { return \@requests; }
  }

  # send to conserver hosts
  foreach my $cons (keys %cons_hash) {
    #print "cons=$cons\n";
    my $doit=0;
    if ($isSN) {
      if (exists($iphash{$cons})) { $doit=1; }
    } else {
      if (!exists($iphash{$cons}) || $::CONSERVER) { $doit=1; }
    }

    if ($doit) {
      my $reqcopy = {%$request};
      $reqcopy->{'_xcatdest'} = $cons;
      $reqcopy->{_xcatpreprocessed}->[0] = 1;
      $reqcopy->{'_allnodes'} = [$allnodes]; # the original command comes with nodes or not
      $reqcopy->{node} = $cons_hash{$cons}{nodes};
      my $no=$reqcopy->{node};
      #print "node=@$no\n";
      push @requests, $reqcopy;
    } #end if
  } #end foreach

  if ($::DEBUG) {
      my $rsp;
      $rsp->{data}->[0] = "In preprocess_request, request is " . Dumper(@requests);
      xCAT::MsgUtils->message("I", $rsp, $callback);
   }
  return \@requests;
}

sub process_request {
  my $req = shift;
  my $cb = shift;
  if ($req->{command}->[0] eq "makeconfluentcfg") {
    makeconfluentcfg($req,$cb);
  }
}

# Read the file, get db info, update the file contents, and then write the file
sub makeconfluentcfg {
  my $req = shift;
  %termservers = (); #clear hash of existing entries
  my $cb = shift;
  my $extrargs = $req->{arg};
  my @exargs=($req->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }
  @ARGV=@exargs;
  $Getopt::Long::ignorecase=0;
  #$Getopt::Long::pass_through=1;
  my $delmode;
  GetOptions('d|delete'  => \$delmode,
            );
  my $nodes = $req->{node};
  my $svboot=0;
  if (exists($req->{svboot})) { $svboot=1;}
  my $confluent = Confluent::Client->new();  # just the local form for now..

  my $isSN=xCAT::Utils->isServiceNode();
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}

  #print "process_request nodes=@$nodes\n";

  # Get db info for the nodes related to console
  my $hmtab = xCAT::Table->new('nodehm');
  my @cfgents1;# = $hmtab->getAllNodeAttribs(['cons','serialport','mgt','conserver','termserver','termport']);
  if (($nodes and @$nodes > 0) or $req->{noderange}->[0]) {
      @cfgents1 = $hmtab->getNodesAttribs($nodes,['node','cons','serialport','mgt','conserver','termserver','termport','consoleondemand']);
      # Adjust the data structure to make the result consistent with the getAllNodeAttribs() call we make if a noderange was not specified
      my @tmpcfgents1;
      foreach my $ent (@cfgents1)
      {
          foreach my $nodeent ( keys %$ent)
          {
              push @tmpcfgents1, $ent->{$nodeent}->[0] ;
          }
      }
      @cfgents1 = @tmpcfgents1

  } else {
    @cfgents1 = $hmtab->getAllNodeAttribs(['cons','serialport','mgt','conserver','termserver','termport','consoleondemand']);
  }


  #cfgents1 should now have all the nodes, so we can fill in the cfgents array and cfgenthash one at a time.
  # skip the nodes that do not have 'cons' defined, unless a serialport setting suggests otherwise
  my @cfgents=();
  my %cfgenthash;
  foreach (@cfgents1) {
    if ($_->{cons} or defined($_->{'serialport'})) {
      unless ($_->{cons}) {$_->{cons} = $_->{mgt};} #populate with fallback
      push @cfgents, $_;
      $cfgenthash{$_->{node}} = $_;     # also put the ref to the entry in a hash for quick look up
    }
  }

  if ($::DEBUG) {
      my $rsp;
      $rsp->{data}->[0] = "In makeconservercf, cfgents is " . Dumper(@cfgents);
      xCAT::MsgUtils->message("I", $rsp, $cb);
  }

  # if nodes defined, it is either on the service node or makeconserver was called with noderange on mn
  if (($nodes and @$nodes > 0) or $req->{noderange}->[0]) {
    # strip all xCAT configured nodes from config if the original command was for all nodes
    #if (($req->{_allnodes}) && ($req->{_allnodes}->[0]==1)) {} #TODO: identify nodes that will be removed 
    # call donodeent to add all node entries into the file.  It will return the 1st node in error.
    my $node;
    if ($node=donodeent(\%cfgenthash,$confluent,$delmode, $cb)) {
      #$cb->({node=>[{name=>$node,error=>"Bad configuration, check attributes under the nodehm category",errorcode=>1}]});
      xCAT::SvrUtils::sendmsg([1,"Bad configuration, check attributes under the nodehm category"],$cb,$node);
    }
  } else { #no nodes specified, do em all up
    #zapcfg(\@filecontent); # strip all xCAT configured nodes from config
    #TODO: identify nodes to be removed

    # get nodetype so we can filter out node types without console support
    my $typetab = xCAT::Table->new('nodetype');
    my %type;

    if ( defined($typetab)) {
      my @ents = $typetab->getAllNodeAttribs([qw(node nodetype)]);
      foreach (@ents) {
        $type{$_->{node}}=$_->{nodetype};
      }
    }
    # remove nodes that arent for this SN or type of node doesnt have console
    foreach (@cfgents) {
      my $keepdoing=0;
      if ($isSN && $_->{conserver} && exists($iphash{$_->{conserver}}))  {
        $keepdoing=1;  #only hanlde the nodes that use this SN as the conserver
      }
      if (!$isSN) { $keepdoing=1;} #handle all for MN
      if ($keepdoing) {
        if ($_->{termserver} and not $termservers{$_->{termserver}}) {
          die "confluent does not currently support termserver";
          $termservers{$_->{termserver}}=1; # dont add this one again
        }
        if ( $type{$_->{node}} =~ /fsp|bpa|hmc|ivm/ ) {
          $keepdoing=0;   # these types dont have consoles
        }
      }
      if (!$keepdoing) { delete $cfgenthash{$_->{node}}; }    # remove this node from the hash so we dont process it later
    }

    # Now add into the file all the node entries that we kept
    my $node;
    if ($node=donodeent(\%cfgenthash,$confluent, undef, $cb)) {
      # donodeent will return the 1st node in error
      #$cb->({node=>[{name=>$node,error=>"Bad configuration, check attributes under the nodehm category",errorcode=>1}]});
      xCAT::SvrUtils::sendmsg([1,"Bad configuration, check attributes under the nodehm category"],$cb,$node);
    }
  }
}


# Add entries in the file for each node.  This function used to do 1 node at a time, but was changed to do
# all nodes at once for performance reasons.  If there is a problem with a nodes config, this
# function will return that node name as the one in error.
sub donodeent {
  my $cfgenthash = shift;
  my $confluent = shift;
  my $delmode = shift;
  my $cb = shift;
  my $idx=0;
  my $toidx=-1;
  my $skip = 0;
  my $skipnext = 0;

  # Delete all the previous stanzas of the nodes specified
  my $isSN=xCAT::Utils->isServiceNode();
  my $curnode;
  # Loop till find the start of a node stanza and remove lines till get to the end of the stanza
  my %currnodes;
  $confluent->read('/nodes/');
  my $listitem = $confluent->next_result();
  while ($listitem) {
    if (exists $listitem->{item}) {
        my $name = $listitem->{item}->{href};
        $name =~ s/\/$//;
        $currnodes{$name} = 1;
    }
    $listitem = $confluent->next_result();
  }
  if ($delmode) {
      foreach my $confnode (keys %currnodes) {
        if ($cfgenthash->{$confnode}) {
            $confluent->delete('/nodes/' . $confnode);
        }
      return;
      }
  }
  my @toconfignodes = keys %{$cfgenthash};
  my $ipmitab = xCAT::Table->new('ipmi', -create=>0);
  my $ipmientries = {};
  if ($ipmitab) {
    $ipmientries = $ipmitab->getNodesAttribs(\@toconfignodes,
                                             [qw/bmc username password/]);
  }
  my $ipmiauthdata = xCAT::PasswordUtils::getIPMIAuth(
        noderange=>\@toconfignodes, ipmihash=>$ipmientries);

# Go thru all nodes specified to add them to the file
foreach my $node (sort keys %$cfgenthash) {
  my $cfgent = $cfgenthash->{$node};
  my $cmeth=$cfgent->{cons};
  if (not $cmeth) {
      return $node;
  }
  if ($cmeth ne 'ipmi') {
    die 'TODO: non ipmi consoles...'
  }
  my %parameters;
  $parameters{'console.method'} = $cmeth;
  if ($cmeth eq 'ipmi') {
    $parameters{'secret.hardwaremanagementuser'} =
            $ipmiauthdata->{$node}->{username};
      $parameters{'secret.hardwaremanagementpassphrase'} =
            $ipmiauthdata->{$node}->{password};
      my $bmc = $ipmientries->{$node}->[0]->{bmc};
      $bmc =~ s/,.*//;
      $parameters{'hardwaremanagement.manager'} = $bmc;
  }
  if (defined($cfgent->{consoleondemand})) {
    if ($cfgent->{consoleondemand}) {
        $parameters{'console.logging'} = 'none';
    }
    else {
        $parameters{'console.logging'} = 'full';
    }
  } elsif ($::XCATSITEVALS{'consoleondemand'} and $::XCATSITEVALS{'consoleondemand'} !~ m/^n/) {
    $parameters{'console.logging'} = 'none';
  }
  if (exists $currnodes{$node}) {
    $confluent->update('/nodes/'.$node.'/attributes/current', parameters=>\%parameters);
    my $rsp = $confluent->next_result();
    while ($rsp) {
        if (exists $rsp->{error}) {
            xCAT::SvrUtils::sendmsg([1,"Confluent error: " . $rsp->{error}],$cb,$node);
        }
        $rsp = $confluent->next_result();
    }
  } else {
    $parameters{name} = $node;
    $confluent->create('/nodes/', parameters=>\%parameters);
    my $rsp = $confluent->next_result();
    while ($rsp) {
        if (exists $rsp->{error}) {
            xCAT::SvrUtils::sendmsg([1,"Confluent error: " . $rsp->{error}],$cb,$node);
        }
        $rsp = $confluent->next_result();
    }
  }
}
return 0;
}

1;
