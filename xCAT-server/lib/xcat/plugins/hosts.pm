# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::hosts;
use strict;
use warnings;
use xCAT::Table;
use xCAT::NetworkUtils;
use Data::Dumper;
use File::Copy;
use Getopt::Long;
use Fcntl ':flock';


my @hosts; #Hold /etc/hosts data to be written back
my $LONGNAME;
my $OTHERNAMESFIRST;
my $ADDNAMES;
my $MACTOLINKLOCAL;


my %usage=(
    makehosts => "Usage: makehosts <noderange> [-d] [-n] [-l] [-a] [-o] [-m]\n       makehosts -h",
);
sub handled_commands {
  return {
    makehosts => "hosts",
  }
}
  

sub delnode {
  my $node = shift;
  my $ip = shift;
  unless ($node and $ip) { return; } #bail if requested to do something that could zap /etc/hosts badly
  my $othernames = shift;
  my $domain = shift;
  my $idx=0;
  
  while ($idx <= $#hosts) {
    if (($ip and $hosts[$idx] =~ /^${ip}\s/) or $hosts[$idx] =~ /^\d+\.\d+\.\d+\.\d+\s+${node}[\s\.r]/) {
        $hosts[$idx]=""; 
    }
    $idx++;
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
    if ($hosts[$idx] =~ /^${ip}\s/ or $hosts[$idx] =~ /^\d+\.\d+\.\d+\.\d+\s+${node}[\s\.r]/) {
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
    my @n_names=();
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
	} elsif ($ADDNAMES) {
        unshift(@n_names,"$_.$domain");
    } 
    }
    unshift(@o_names,@n_names);

    if ($node =~ m/\.$domain$/i) {
        $longname = $node;
        $node =~ s/\.$domain$//;
    } elsif ($domain && !$longname) {
	    $longname="$node.$domain";
    } 

    $othernames=join(' ', @o_names);
    if ($LONGNAME) { return "$ip $longname $node $othernames\n"; } 
    elsif ($OTHERNAMESFIRST) { return "$ip $othernames $longname $node\n"; }
    else { return "$ip $node $longname $othernames\n"; }
}


sub addotherinterfaces {
  my $node = shift;
  my $otherinterfaces = shift;
  my $domain = shift;

    my @itf_pairs=split(/,/, $otherinterfaces);
    foreach (@itf_pairs) {
      my ($itf,$ip)=split(/:/, $_);
      if ($itf =~ /^-/ ) {
          $itf = $node.$itf };
      addnode $itf,$ip,'',$domain;
    }
}


sub process_request {
  Getopt::Long::Configure("bundling") ;
  $Getopt::Long::ignorecase=0;
  Getopt::Long::Configure("no_pass_through");

  my $req = shift;
  my $callback = shift;
  my $HELP;
  my $REMOVE;
  my $DELNODE;

  # parse the options
  if ($req && $req->{arg}) {@ARGV = @{$req->{arg}};}
  else {  @ARGV = (); }

# print "argv=@ARGV\n";
  if(!GetOptions(
      'h|help'  => \$HELP,
      'n'  => \$REMOVE,
      'd'  => \$DELNODE,
      'o|othernamesfirst'  => \$OTHERNAMESFIRST,
      'a|adddomaintohostnames'  => \$ADDNAMES,
      'm|mactolinklocal'  => \$MACTOLINKLOCAL,
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
  my $lockh;
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
      
      # add the localhost entry if trying to create the /etc/hosts from scratch
      if ($^O =~ /^aix/i) {
        push @hosts, "127.0.0.1 loopback localhost\n";
      } else {
        push @hosts, "127.0.0.1 localhost\n";
      }
    }
  } else {
    if (-e "/etc/hosts") {
      my $bakname = "/etc/hosts.xcatbak";
      copy("/etc/hosts",$bakname);
    }
    open($lockh,">","/tmp/xcat/hostsfile.lock");
    flock($lockh,LOCK_EX);
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
    if ($MACTOLINKLOCAL) {
        my $mactab = xCAT::Table->new("mac");
        my $machash = $mactab->getNodesAttribs($req->{node},['mac']);
        foreach my $node (keys %{$machash})
        {
            my $mac = $machash->{$node}->[0]->{mac};
            if (!$mac) {
                next;
            }
            my $linklocal = xCAT::NetworkUtils->linklocaladdr($mac);
            if ($DELNODE) {
              delnode $node,$linklocal,$node,$domain;
            } else {
              addnode $node,$linklocal,$node,$domain;
            }
        }
    } else {
        my $hostscache = $hoststab->getNodesAttribs($req->{node},[qw(ip node hostnames otherinterfaces)]);
        foreach(@{$req->{node}}) {
          my $ref = $hostscache->{$_}->[0]; #$hoststab->getNodeAttribs($_,[qw(ip node hostnames otherinterfaces)]);
          if ($DELNODE) {
              delnode $ref->{node},$ref->{ip},$ref->{hostnames},$domain;
          } else {
              addnode $ref->{node},$ref->{ip},$ref->{hostnames},$domain;
              if (defined($ref->{otherinterfaces})){
                 addotherinterfaces $ref->{node},$ref->{otherinterfaces},$domain;
            }
          }
        } #end foreach
    } # end else
  } else {
      if ($DELNODE) {
          return;
      }
    my @hostents = $hoststab->getAllNodeAttribs(['ip','node','hostnames','otherinterfaces']);
    foreach (@hostents) {
      addnode $_->{node},$_->{ip},$_->{hostnames},$domain;
      if (defined($_->{otherinterfaces})){
         addotherinterfaces $_->{node},$_->{otherinterfaces},$domain;
      }
    }
  }
  writeout();
  
  if ($lockh) {
    flock($lockh,LOCK_UN);
  }
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
