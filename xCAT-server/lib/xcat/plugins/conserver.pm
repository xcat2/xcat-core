# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#TODO: delete entries not being refreshed if no noderange
package xCAT_plugin::conserver;
use strict;
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use Getopt::Long;
use Sys::Hostname;
use xCAT::SvrUtils;

use strict;
use Data::Dumper;
my @cservers = qw(mrv cyclades);
my %termservers; #list of noted termservers
my $siteondemand; # The site value for consoleondemand

my $usage_string=
"  makeconservercf [-d|--delete] noderange
  makeconservercf [-l|--local]
  makeconservercf [-c|--conserver]
  makeconservercf 
  makeconservercf -h|--help
  makeconservercf -v|--version
    -c|--conserver   The conserver gets set up only on the conserver host.
                     The default goes down to all the conservers on
                     the server nodes and set them up
    -l|--local       The conserver gets set up only on the local host.
                     The default goes down to all the conservers on
                     the server nodes and set them up
    -d|--delete      Conserver has the relevant entries for the given noderange removed immediately from configuration
    -h|--help        Display this usage statement.
    -V|--verbose     Verbose mode.
    -v|--version     Display the version number.";

my $version_string=xCAT::Utils->Version(); 

sub handled_commands {
  return {
    makeconservercf => "conserver"
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
      'c|conserver' => \$::CONSERVER,
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
      $callback->({data=>"Can not specify -l or --local together with -c or --conserver."});
      $request = {};
      return;
  }
  
  
  # get site master
  my $master=xCAT::TableUtils->get_site_Master();
  if (!$master) { $master=hostname(); }

  # get conserver for each node
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
        $rsp->{data}->[0] = "Setting the nodes into /etc/conserver.cf on the management node";
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
  if ($req->{command}->[0] eq "makeconservercf") {
    makeconservercf($req,$cb);
  }
}

# Add the initial/global entries to the beginning of the file
sub docfheaders {
# Put in standard headers common to all conserver.cf files
  my $content = shift;
  my @newheaders=();
  my $numlines = @$content;
  my $idx = 0;
  my $skip = 0;
  my @meat = grep(!/^#/,@$content);
  unless (grep(/^config \* {/,@meat)) {
    # do not add the ssl configurations 
    # if conserver is not compiled with ssl support
    my $cmd = "console -h 2>&1";
    my $output = xCAT::Utils->runcmd($cmd, -1);
    if ($output !~ "encryption not compiled")
    {
        push @newheaders,"config * {\n";
        push @newheaders,"  sslrequired yes;\n";
        push @newheaders,"  sslauthority /etc/xcat/cert/ca.pem;\n";
        push @newheaders,"  sslcredentials /etc/xcat/cert/server-cred.pem;\n";
        push @newheaders,"}\n";
    }
  }
  unless (grep(/^default cyclades/,@meat)) {
    push @newheaders,"default cyclades { type host; portbase 7000; portinc 1; }\n"
  }
  unless (grep(/^default mrv/,@meat)) {
    push @newheaders,"default mrv { type host; portbase 2000; portinc 100; }\n"
  }
  #Go through and delete that which would match access and default
  while($idx < @$content){
    if (($content->[$idx] =~ /^access \*/)
      ||($content->[$idx] =~ /^default \*/)) {
      $skip = 1;
    }
    if ($skip == 1){
      splice(@$content, $idx, 1);
    } else {
      $idx++;
    }
    if($skip and $content->[$idx] =~ /\}/){
      splice(@$content, $idx, 1);
      $skip = 0;
    }
  }
  #push @$content,"#xCAT BEGIN ACCESS\n";
  push @newheaders,"access * {\n";
  push @newheaders,"  trusted 127.0.0.1;\n";
  my $master=xCAT::TableUtils->get_site_Master();
  push @newheaders, "  trusted $master;\n";
  # trust all the ip addresses configured on this node
  my @allips = xCAT::NetworkUtils->gethost_ips();
  my @ips = ();
  #remove $xcatmaster and duplicate entries
  foreach my $ip (@allips) {
      if (($ip eq "127.0.0.1") || ($ip eq $master)) {
          next;
      }
      if(!grep(/^$ip$/, @ips)) {
          push @ips,$ip;
      }
  }
  if ($::TRUSTED_HOST)
  {
      my @trusted_host = (split /,/, $::TRUSTED_HOST);
      foreach my $tip (@trusted_host)
      {
          if(!grep(/^$tip$/, @ips)) {
              push @ips,$tip;
          }
      }
  }
  if(scalar(@ips) > 0) {
      my $ipstr = join(',', @ips);
      push @newheaders, "  trusted $ipstr;\n";
  }

  push @newheaders,"}\n";
  #push @$content,"#xCAT END ACCESS\n";

  push @newheaders,"default * {\n";
  push @newheaders,"  logfile /var/log/consoles/&;\n";
  push @newheaders,"  timestamp 1hab;\n";
  push @newheaders,"  rw *;\n";
  push @newheaders,"  master localhost;\n";

  #-- if option "conserverondemand" in site table is set to yes
  #-- then start all consoles on demand
  #-- this helps eliminate many ssh connections to blade AMM
  #-- which seems to kill AMMs occasionally
  #my $sitetab  = xCAT::Table->new('site');
  #my $vcon = $sitetab->getAttribs({key => "consoleondemand"}, 'value');
  my @entries =  xCAT::TableUtils->get_site_attribute("consoleondemand");
  my $site_entry = $entries[0];
  if ( defined($site_entry) and $site_entry eq "yes" ) {
    push @newheaders,"  options ondemand;\n";
    $siteondemand=1;
  }
  else {
    $siteondemand=0;
  }

  push @newheaders,"}\n";
  unshift @$content,@newheaders;
}

# Read the file, get db info, update the file contents, and then write the file
sub makeconservercf {
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
             't|trust=s' => \$::TRUSTED_HOST
            );
  my $nodes = $req->{node};
  my $svboot=0;
  if (exists($req->{svboot})) { $svboot=1;}
  my $cfile;
  my @filecontent;
  open $cfile,'/etc/conserver.cf';
  while (<$cfile>) {
    push @filecontent,$_;
  }
  close $cfile;
  docfheaders(\@filecontent);

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
    if (($req->{_allnodes}) && ($req->{_allnodes}->[0]==1)) {zapcfg(\@filecontent);}
    # call donodeent to add all node entries into the file.  It will return the 1st node in error.
    my $node;
    if ($node=donodeent(\%cfgenthash,\@filecontent,$delmode)) {
      #$cb->({node=>[{name=>$node,error=>"Bad configuration, check attributes under the nodehm category",errorcode=>1}]});
      xCAT::SvrUtils::sendmsg([1,"Bad configuration, check attributes under the nodehm category"],$cb,$node);
    }
  } else { #no nodes specified, do em all up
    zapcfg(\@filecontent); # strip all xCAT configured nodes from config

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
          # add a terminal server entry to file
          dotsent($_,\@filecontent);
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
    if ($node=donodeent(\%cfgenthash,\@filecontent)) {
      # donodeent will return the 1st node in error
      #$cb->({node=>[{name=>$node,error=>"Bad configuration, check attributes under the nodehm category",errorcode=>1}]});
      xCAT::SvrUtils::sendmsg([1,"Bad configuration, check attributes under the nodehm category"],$cb,$node);
    }
  }

  # Write out the file contents
  open $cfile,'>','/etc/conserver.cf';
  if ($::VERBOSE) {
      my $rsp;
      $rsp->{data}->[0] = "Setting the following lines into /etc/conserver.cf:\n @filecontent";
      xCAT::MsgUtils->message("I", $rsp, $cb);
  }
  foreach (@filecontent) {
    print $cfile $_;
  }
  close $cfile;

  # restart conserver
  if (!$svboot) {
    #restart conserver daemon
    my $cmd;
    if(xCAT::Utils->isAIX()){
        $cmd = "stopsrc -s conserver";
        xCAT::Utils->runcmd($cmd, 0);
        $cmd = "startsrc -s conserver";
        xCAT::Utils->runcmd($cmd, 0);
    } else {
        $cmd = "/etc/init.d/conserver stop";
        xCAT::Utils->runcmd($cmd, 0);
        $cmd = "/etc/init.d/conserver start";
        xCAT::Utils->runcmd($cmd, 0);
    }
  }
}

# Put a terminal server entry in the file - not used much any more
sub dotsent {
  my $cfgent = shift;
  my $tserv = $cfgent->{termserver};
  my $content = shift;
  my $idx = 0;
  my $toidx = -1;
  my $skip = 0;
  my $skipnext = 0;

  while ($idx < $#$content) { # Go through and delete that which would match my entry
    if ($content->[$idx] =~ /^#xCAT BEGIN $tserv TS/) {
      $toidx=$idx; #TODO put it back right where I found it
      $skip = 1;
      $skipnext=1;
    } elsif ($content->[$idx] =~ /^#xCAT END $tserv TS/) {
      $skipnext = 0;
    }
    if ($skip) {
      splice (@$content,$idx,1);
    } else {
      $idx++;
    }
    $skip = $skipnext;
  }
  push @$content,"#xCAT BEGIN $tserv TS\n";
  push @$content,"default $tserv {\n";
  push @$content,"  include ".$cfgent->{cons}.";\n";
  push @$content,"  host $tserv;\n";
  push @$content,"}\n";
  push @$content,"#xCAT END $tserv TS\n";

}

# Add entries in the file for each node.  This function used to do 1 node at a time, but was changed to do
# all nodes at once for performance reasons.  If there is a problem with a nodes config, this
# function will return that node name as the one in error.
sub donodeent {
  my $cfgenthash = shift;
  my $content = shift;
  my $delmode = shift;
  my $idx=0;
  my $toidx=-1;
  my $skip = 0;
  my $skipnext = 0;

  # Delete all the previous stanzas of the nodes specified
  my $isSN=xCAT::Utils->isServiceNode();
  my $curnode;
  # Loop till find the start of a node stanza and remove lines till get to the end of the stanza
  while ($idx <= $#$content) { # Go through and delete that which would match my entry
    my ($begorend, $node) = $content->[$idx] =~ /^#xCAT (\S+) (\S+) CONS/;
    if ($begorend eq 'BEGIN') {
      if ($cfgenthash->{$node}) {
        $toidx=$idx; #TODO put it back right where I found it
        $skip = 1;    # delete this line
        $skipnext=1;  # put us in skip mode until we find the end of the stanza
        $curnode = $node;
      }
    } elsif ($begorend eq 'END' && $node eq $curnode) {
      $skipnext = 0;
    }
    if ($skip) {
      splice (@$content,$idx,1);
    } else {
      $idx++;
    }
    $skip = $skipnext;
  }
if ($delmode) {
      # dont need to add node entries, so we are done
      return;
  }

# Go thru all nodes specified to add them to the file
foreach my $node (sort keys %$cfgenthash) {
  my $cfgent = $cfgenthash->{$node};
  my $cmeth=$cfgent->{cons};
  if (not $cmeth or (grep(/^$cmeth$/,@cservers) and (not $cfgent->{termserver} or not $cfgent->{termport}))) {
      # either there is no console method (shouldnt happen) or not one of the supported terminal servers
      return $node;
  }
  push @$content,"#xCAT BEGIN $node CONS\n";
  push @$content,"console $node {\n";
  if (grep(/^$cmeth$/,@cservers)) {
    push @$content," include ".$cfgent->{termserver}.";\n";
    push @$content," port ".$cfgent->{termport}.";\n";
    if ((!$isSN) && ($cfgent->{conserver}) && xCAT::NetworkUtils->thishostisnot($cfgent->{conserver})) { # let the master handle it
      push @$content,"  master ".$cfgent->{conserver}.";\n";
    }
  } else { #a script method...
    push @$content,"  type exec;\n";
    if ((!$isSN) && ($cfgent->{conserver}) && xCAT::NetworkUtils->thishostisnot($cfgent->{conserver})) { # let the master handle it
      push @$content,"  master ".$cfgent->{conserver}.";\n";
    } else { # handle it here
      my $locerror = $isSN ? "PERL_BADLANG=0 " : '';    # on service nodes, often LC_ALL is not set and perl complains
      push @$content,"  exec $locerror".$::XCATROOT."/share/xcat/cons/".$cmeth." ".$node.";\n"
    }
  }
  if (defined($cfgent->{consoleondemand})) {
    if ($cfgent->{consoleondemand} && !$siteondemand ) {
      push @$content,"  options ondemand;\n";
    }
    elsif (!$cfgent->{consoleondemand} && $siteondemand ) {
      push @$content,"  options !ondemand;\n";
    }
  }
  push @$content,"}\n";
  push @$content,"#xCAT END $node CONS\n";
}
return 0;
}

# Delete any xcat added node entries from the file
sub zapcfg {
  my $content = shift;
  my $idx=0;
  my $toidx=-1;
  my $skip = 0;
  my $skipnext = 0;
  while ($idx <= $#$content) { # Go through and delete that which would match my entry
    if ($content->[$idx] =~ /^#xCAT BEGIN/) {
      $toidx=$idx; #TODO put it back right where I found it
      $skip = 1;
      $skipnext=1;
    } elsif ($content->[$idx] =~ /^#xCAT END/) {
      $skipnext = 0;
    }
    if ($skip) {
      splice (@$content,$idx,1);
    } else {
      $idx++;
    }
    $skip = $skipnext;
  }
}


1;
