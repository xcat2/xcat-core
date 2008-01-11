#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::nodediscover;
#use Net::SNMP qw(:snmp INTEGER);
use xCAT::Table;
use IO::Socket;
use SNMP;
use strict;

use XML::Simple;
use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use IO::Select;
use IO::Handle;
use Sys::Syslog;


sub handled_commands {
  return {
    discovered => 'chain:ondiscover',
  };
}
sub process_request {
  my $request = shift;
  my $callback = shift;
  my $node = $request->{node}->[0];
  my $ip = $request->{'!xcat_clientip'};
  openlog("xCAT node discovery",'','local0');
  #First, fill in tables with data fields..
  if (defined($request->{mtm}) or defined($request->{serial})) {
    my $vpdtab = xCAT::Table->new("vpd",-create=>1);
    if ($request->{mtm}->[0]) {
      $vpdtab->setNodeAttribs($node,{mtm=>$request->{mtm}->[0]});
    }
    if ($request->{serial}) {
      $vpdtab->setNodeAttribs($node,{serial=>$request->{serial}->[0]});
    }
  }
  if (defined($request->{arch})) {
    my $typetab=xCAT::Table->new("nodetype",-create=>1);
    $typetab->setNodeAttribs($node,{arch=>$request->{arch}->[0]});
  }
  #TODO: mac table?  on the one hand, 'the' definitive interface was determined earlier...
  #Delete the state it was in to make it traverse destiny once agoin
  my $chaintab = xCAT::Table->new('chain');
  if ($chaintab) {
    $chaintab->setNodeAttribs($node,{currstate=>'',currchain=>''});
    $chaintab->close();
  }


  #now, notify the node to continue life
  my $sock = new IO::Socket::INET (
          PeerAddr => $ip,
          PeerPort => '3001',
          Timeout => '1',
          Proto => 'tcp'
    );
    unless ($sock) { syslog("err","Failed to notify $ip that it's actually $node."); return; } #Give up if the node won't hear of it.
    print $sock "restart";
    close($sock);
    syslog("info","$node has been discovered");
}

1;
