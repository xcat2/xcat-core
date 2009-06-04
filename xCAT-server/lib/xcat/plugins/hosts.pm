# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::hosts;
use strict;
use warnings;
use xCAT::Table;
use Data::Dumper;
use File::Copy;
use Getopt::Long;


my @hosts; #Hold /etc/hosts data to be written back
my $LONGNAME;


my %usage=(
    makehosts => "Usage: makehosts <noderange> [-n] [-l]\n       makehosts -h",
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
  my $domain = shift;
  my $idx=0;
  my $foundone=0;
  
  while ($idx <= $#hosts) {
    if ($hosts[$idx] =~ /^${ip}\s/ or $hosts[$idx] =~ /^\d+\.\d+\.\d+\.\d+\s+${node}[\s\.r/) {
      if ($foundone) {
        $hosts[$idx]=""; 
      } else {
        $hosts[$idx]=build_line($ip, $node, $domain, $othernames); 
      }
      $foundone=1;
    }
    $idx++;
  }
  if ($foundone) { return;}

  my $line=build_line($ip, $node, $domain, $othernames); 
  push @hosts, $line;
}

sub build_line {
    my $ip=shift; 
    my $node=shift;
    my $domain=shift;
    my $othernames=shift;
    my @o_names=();
    if (defined $othernames) {
         @o_names=split(/,| /, $othernames);
    }
    my $longname;
    foreach (@o_names) {
	if (($_ eq $node) || ( $domain && ($_ eq "$node.$domain"))) {
            $longname="$node.$domain";
	    $_="";
	} elsif ( $_ =~ /\./) {
            if (!$longname) { 
		$longname=$_;
		$_="";
	    }
	}
    } 

    if ($domain && !$longname) {
	$longname="$node.$domain";
    } 

    $othernames=join(' ', @o_names);
    if ($LONGNAME) { return "$ip $longname $node $othernames\n"; } 
    else { return "$ip $node $longname $othernames\n"; }
}


sub process_request {
  Getopt::Long::Configure("bundling") ;
  $Getopt::Long::ignorecase=0;
  Getopt::Long::Configure("no_pass_through");

  my $req = shift;
  my $callback = shift;
  my $HELP;
  my $REMOVE;

  # parse the options
  if ($req && $req->{arg}) {@ARGV = @{$req->{arg}};}
  else {  @ARGV = (); }

# print "argv=@ARGV\n";
  if(!GetOptions(
      'h|help'  => \$HELP,
      'n'  => \$REMOVE,
      'l|longnamefirst'  => \$LONGNAME,))
  {
    $callback->({data=>$usage{makehosts}});
    return;
  }

  # display the usage if -h
  if ($HELP) { 
    $callback->({data=>$usage{makehosts}});
    return;
  }


  my $hoststab = xCAT::Table->new('hosts');
  my $sitetab = xCAT::Table->new('site');
  my $domain;
  if ($sitetab) {
    my $dent = $sitetab->getAttribs({key=>'domain'},'value');
    if ($dent and $dent->{value}) {
        $domain=$dent->{value};
    }
  }

  @hosts = ();
  if ($REMOVE) {
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
      addnode $ref->{node},$ref->{ip},$ref->{hostnames},$domain;
    }
  } else {
    my @hostents = $hoststab->getAllNodeAttribs(['ip','node','hostnames']);
    foreach (@hostents) {
      addnode $_->{node},$_->{ip},$_->{hostnames},$domain;
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
