# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::switch;
use IO::Socket;
use Data::Dumper;
use xCAT::MacMap;
use Sys::Syslog;
use Storable;

my $macmap;
sub handled_commands {
  $macmap = xCAT::MacMap->new();
  return {
    findme => 'switch',
    findmac => 'switch',
  };
}

sub process_request {
 my $req = shift;
 my $cb = shift;
 my $doreq = shift;
 my $node;
 my $mac = '';
 if ($req->{command}->[0] eq 'findmac') {
     $mac = $req->{arg}->[0];
      $node = $macmap->find_mac($mac,0);
      $cb->({node=>[{name=>$node,data=>$mac}]});
    return;
 }
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
 my $arptable = `/sbin/arp -n`;
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
  $doreq->($req); 
  %{$req}=();#Clear req structure, it's done..
  undef $mactab;
 } else { 
    #Shouldn't complain, might be blade, but how to log total failures?
 }
}
1;
