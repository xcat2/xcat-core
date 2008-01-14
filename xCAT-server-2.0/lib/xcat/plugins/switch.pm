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
  };
}

sub process_request {
 my $req = shift;
 my $cb = shift;
 my $doreq = shift;
 my $ip = $req->{'!xcat_clientip'};
 my $mac = '';
 my $arptable = `/sbin/arp -n`;
 my @arpents = split /\n/,$arptable;
 foreach  (@arpents) {
   if (m/^($ip)\s+\S+\s+(\S+)\s/) {
     $mac=$2;
     last;
   }
 }
 unless ($mac) {
   return;
 }
 my $node = $macmap->find_mac($mac,$req->{cacheonly}->[0]);
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
