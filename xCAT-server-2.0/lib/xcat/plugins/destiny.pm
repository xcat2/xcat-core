# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::destiny;
use xCAT::NodeRange;
use Data::Dumper;
use Sys::Syslog;
use strict;

my $request;
my $callback;
my $subreq;
my $errored = 0;

sub handled_commands {
  return {
    setdestiny => "destiny",
    getdestiny => "destiny",
    nextdestiny => "destiny"
  }
}
sub process_request {
  $request = shift;
  $callback = shift;
  $subreq = shift;
  if ($request->{command}->[0] eq 'getdestiny') {
    getdestiny();
  }
  if ($request->{command}->[0] eq 'nextdestiny') {
    nextdestiny($request);
  }
  if ($request->{command}->[0] eq 'setdestiny') {
    setdestiny($request);
  }
}

sub relay_response {
    my $resp = shift;
    $callback->($resp);
    if ($resp and $resp->{errorcode} and $resp->{errorcode}->[0]) {
        $errored = 1;
    }
}

sub setdestiny {
  my $req=shift;
  my $chaintab = xCAT::Table->new('chain');
  my @nodes=@{$req->{node}};
  my $state = $req->{arg}->[0];
  my %nstates;
  if ($state eq "next") {
    return nextdestiny();
  } elsif ($state =~ /^install$/ or $state eq "install" or $state eq "netboot") {
    chomp($state);
    $subreq->({command=>["mk$state"],
              node=>$req->{node}}, \&relay_response);
    if ($errored) { return; }
    my $nodetype = xCAT::Table->new('nodetype');
    foreach (@{$req->{node}}) {
      $nstates{$_} = $state; #local copy of state variable for mod
      my $ntent = $nodetype->getNodeAttribs($_,[qw(os arch profile)]);
      if ($ntent and $ntent->{os}) {
        $nstates{$_} .= " ".$ntent->{os};
      } else { $errored =1; $callback->({error=>"nodetype.os not defined for $_"}); }
      if ($ntent and $ntent->{arch}) {
        $nstates{$_} .= "-".$ntent->{arch};
      } else { $errored =1; $callback->({error=>"nodetype.arch not defined for $_"}); }
      if ($ntent and $ntent->{profile}) {
        $nstates{$_} .= "-".$ntent->{profile};
      } else { $errored =1; $callback->({error=>"nodetype.profile not defined for $_"}); }
      if ($errored) {return;}
      unless ($state =~ /^netboot/) { $chaintab->setNodeAttribs($_,{currchain=>"boot"}); };
    }
  } elsif ($state eq "shell" or $state eq "standby" or $state =~ /^runcmd/) {
    my $noderes=xCAT::Table->new('noderes');
    my $nodetype = xCAT::Table->new('nodetype');
    my $sitetab = xCAT::Table->new('site');
    (my $portent) = $sitetab->getAttribs({key=>'xcatdport'},'value');
    (my $mastent) = $sitetab->getAttribs({key=>'master'},'value');
    foreach (@nodes) {
      my $ent = $nodetype->getNodeAttribs($_,[qw(arch)]);
      unless ($ent and $ent->{arch}) {
        $callback->({error=>["No archictecture defined in nodetype table for $_"],errorcode=>[1]});
        return;
      }
      my $arch = $ent->{arch};
      my $ent = $noderes->getNodeAttribs($_,[qw(xcatmaster)]);
      my $master;
      if ($mastent and $mastent->{value}) {
          $master = $mastent->{value};
      }
      if ($ent and $ent->{xcatmaster}) {
          $master = $ent->{xcatmaster};
      }
      unless ($master) {
          $callback->({error=>["No master in site table nor noderes table for $_"],errorcode=>[1]});
          return;
      }
      my $xcatdport="3001";
      if ($portent and $portent->{value}) {
          $xcatdport = $portent->{value};
      }
      $noderes->setNodeAttribs($_,{kernel => "xcat/nbk.$arch",
                                   initrd => "xcat/nbfs.$arch.gz",
                                   kcmdline => "xcatd=$master:$xcatdport"});
    }
    $nodetype->close;
  } elsif (!($state eq "boot")) { 
      $callback->({error=>["Unknown state $state requested"],errorcode=>[1]});
      return;
  }
  foreach (@nodes) {
    my $lstate = $state;
    if ($nstates{$_}) {
        $lstate = $nstates{$_};
    } 
    $chaintab->setNodeAttribs($_,{currstate=>$lstate});
  }
  return getdestiny();
}


sub nextdestiny {
  my @nodes;
  if ($request and $request->{node}) {
    if (ref($request->{node})) {
      @nodes = @{$request->{node}};
    } else {
      @nodes = ($request->{node});
    }
    #TODO: service third party getdestiny..
  } else { #client asking to move along its own chain
    #TODO: SECURITY with this, any one on a node could advance the chain, for node, need to think of some strategy to deal with...
    unless ($request->{'_xcat_clienthost'}->[0]) {
      #ERROR? malformed request
      return; #nothing to do here...
    }
    my $node = $request->{'_xcat_clienthost'}->[0];
    ($node) = noderange($node);
    unless ($node) {
      #not a node, don't trust it
      return;
    }
    @nodes=($node);
  }

  my $node;
  foreach $node (@nodes) {
    my $chaintab = xCAT::Table->new('chain');
    unless($chaintab) {
      syslog("local1|err","ERROR: $node requested destiny update, no chain table");
      return; #nothing to do...
    }
    my $ref =  $chaintab->getNodeAttribs($node,[qw(currstate currchain chain)]);
    unless ($ref->{chain} or $ref->{currchain}) {
      syslog ("local1|err","ERROR: node requested destiny update, no path in chain.currchain");
      $chaintab->close;
      return; #Can't possibly do anything intelligent..
    }
    unless ($ref->{currchain}) { #If no current chain, copy the default
      $ref->{currchain} = $ref->{chain};
    }
    my @chain = split /[,:;]/,$ref->{currchain};

    $ref->{currstate} = shift @chain;
    $ref->{currchain}=join(',',@chain);
    unless ($ref->{currchain}) { #If we've gone off the end of the chain, have currchain stick
      $ref->{currchain} = $ref->{currstate};
    }
    $chaintab->setNodeAttribs($node,$ref); #$ref is in a state to commit back to db
    $chaintab->close;
    my %requ;
    $requ{node}=[$node];
    $requ{arg}=[$ref->{currstate}];
    setdestiny(\%requ);
    getdestiny();
  }
}


sub getdestiny {
  my @args;
  my @nodes;
  if ($request->{node}) {
    if (ref($request->{node})) {
      @nodes = @{$request->{node}};
    } else {
      @nodes = ($request->{node});
    }
  } else { # a client asking for it's own destiny.
    unless ($request->{'_xcat_clienthost'}->[0]) {
      $callback->({destiny=>[ 'discover' ]});
      return;
    }
    my ($node) = noderange($request->{'_xcat_clienthost'}->[0]);
    unless ($node) { # it had a valid hostname, but isn't a node
      $callback->({destiny=>[ 'discover' ]}); 
      return;
    }
    @nodes=($node);
  }
  my $node;
  foreach $node (@nodes) {
    my $chaintab = xCAT::Table->new('chain');
    unless ($chaintab) { #Without destiny, have the node wait with ssh hopefully open at least
      $callback->({node=>[{name=>[$node],data=>['standby'],destiny=>[ 'standby' ]}]});
      return;
    }
    my $ref = $chaintab->getNodeAttribs($node,[qw(currstate chain)]);
    unless ($ref) {
      $callback->({node=>[{name=>[$node],data=>['standby'],destiny=>[ 'standby' ]}]});
      return;
    }
    unless ($ref->{currstate}) { #Has a record, but not yet in a state...
      my @chain = split /,/,$ref->{chain};
      $ref->{currstate} = shift @chain;
      $chaintab->setNodeAttribs($node,{currstate=>$ref->{currstate}});
    }
    my $noderestab = xCAT::Table->new('noderes'); #In case client decides to download images, get data out to it
    my %response;
    $response{name}=[$node];
    $response{data}=[$ref->{currstate}];
    $response{destiny}=[$ref->{currstate}];
    my $sitetab= xCAT::Table->new('site');
    my $nrent = $noderestab->getNodeAttribs($node,[qw(tftpserver kernel initrd kcmdline xcatmaster)]);
    (my $sent) = $sitetab->getAttribs({key=>'master'},'value');
    if (defined $nrent->{kernel}) {
        $response{kernel}=$nrent->{kernel};
    }
    if (defined $nrent->{initrd}) {
        $response{initrd}=$nrent->{initrd};
    }
    if (defined $nrent->{kcmdline}) {
        $response{kcmdline}=$nrent->{kcmdline};
    }
    if (defined $nrent->{tftpserver}) {
        $response{imgserver}=$nrent->{tftpserver};
    } elsif (defined $nrent->{xcatmaster}) {
        $response{imgserver}=$nrent->{xcatmaster};
    } elsif (defined($sent->{value})) {
        $response{imgserver}=$sent->{value};
    }
    
    $callback->({node=>[\%response]});
  }  
}


1;
