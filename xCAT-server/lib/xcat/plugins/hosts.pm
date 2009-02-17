# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::hosts;
use strict;
use warnings;
use xCAT::Table;
use Data::Dumper;
use File::Copy;

my @hosts; #Hold /etc/hosts data to be written back


my %usage=(
    makehosts => "Usage: makehosts [-n] <noderange>",
);
sub handled_commands {
  return {
    makehosts => "hosts",
  }
}
  

sub addnode {
  my $node = shift;
  my $ip = shift;
  unless ($node and $ip) { return; } #bail if requested to do something that could zap /etc/hosts badly
  my $othernames = shift;
  my $idx=0;
  my $foundone=0;
  
  while ($idx <= $#hosts) {
    if ($hosts[$idx] =~ /^${ip}\s/ or $hosts[$idx] =~ /^\d+\.\d+\.\d+\.\d+\s+${node}\s/) {
      #TODO: if foundone, delete a dupe
      $hosts[$idx] = "$ip $node $othernames\n";
      $foundone=1;
    }
    $idx++;
  }
  if ($foundone) { return;}
  push @hosts,"$ip $node $othernames\n";
}
sub process_request {
  my $req = shift;
  my $callback = shift;
  my $hoststab = xCAT::Table->new('hosts');
  @hosts = ();
  if (grep /-h/,@{$req->{arg}}) {
      $callback->({data=>$usage{makehosts}});
      return;
  }
  if (grep /-n/,@{$req->{arg}}) {
    if (-e "/etc/hosts") {
      my $bakname = "/etc/hosts.xcatbak";
      rename("/etc/hosts",$bakname);
    }
  } else {
    if (-e "/etc/hosts") {
      my $bakname = "/etc/hosts.xcatbak";
      copy("/etc/hosts",$bakname);
    }
    my $rconf;
    open($rconf,"/etc/hosts"); # Read file into memory
    if ($rconf) {
      while (<$rconf>) {
        push @hosts,$_;
      }
      close($rconf);
    }
  }

  if ($req->{node}) {
    my $hostscache = $hoststab->getNodesAttribs($req->{node},[qw(ip node hostnames)]);
    foreach(@{$req->{node}}) {
      my $ref = $hostscache->{$_}->[0]; #$hoststab->getNodeAttribs($_,[qw(ip node hostnames)]);
      addnode $ref->{node},$ref->{ip},$ref->{hostnames};
    }
  } else {
    my @hostents = $hoststab->getAllNodeAttribs(['ip','node','hostnames']);
    foreach (@hostents) {
      addnode $_->{node},$_->{ip},$_->{hostnames};
    }
  }
  writeout();
}


sub writeout {
  my $targ;
  open($targ,'>',"/etc/hosts");
  foreach (@hosts) {
    print $targ $_;
  }
  close($targ)
}

1;
