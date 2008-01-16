# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;
use xCAT::Table;
use xCAT::NodeRange;
use Data::Dumper;
my $depsfile = "/etc/xcat/postscripts.dep";
my $rulesfile = "/etc/xcat/postscripts.rules";
my $rules;
my $deps;
my $rulec;
my $node;

sub writescript {
  if (scalar(@_) eq 3) { shift; } #Discard self 
  $node = shift;
  my $scriptfile = shift;
  my $script;
  open($rules,"<",$rulesfile);
  open($deps,"<",$depsfile);
  unless($rules) {
    return undef;
  }
  open($script,">",$scriptfile);
  unless ($scriptfile) {
    return undef;
  }
  #Some common variables...
  my $noderestab=xCAT::Table->new('noderes');
  my $typetab=xCAT::Table->new('nodetype');
  unless ($noderestab and $typetab) {
    die "Unable to open noderes or nodetype table";
  }
  my $master;
  my $sitetab = xCAT::Table->new('site');
  (my $et) = $sitetab->getAttribs({key=>"master"},'value');
  if ($et and $et->{value}) {
      $master = $et->{value};
  }
  $et = $noderestab->getNodeAttribs($node,['xcatmaster']);
  if ($et and $et->{'xcatmaster'}) { 
    $master = $et->{'xcatmaster'};
  }
  unless ($master) {
      die "Unable to identify master for $node";
  }
  print $script "MASTER=".$master."\n";
  print $script "export MASTER\n";
  print $script "NODE=$node\n";
  print $script "export NODE\n";
  my $et = $typetab->getNodeAttribs($node,['os','arch']);
  unless ($et and $et->{'os'} and $et->{'arch'}) {
    die "No os/arch setting in nodetype table for $node";
  }
  print $script "OSVER=".$et->{'os'}."\n";
  print $script "ARCH=".$et->{'arch'}."\n";
  print $script "export OSVER ARCH\n";
  print $script 'PATH=`dirname $0`:$PATH'."\n";
  print $script "export PATH\n";
  $rulec="";
  my @scripts;
  my $inlist = 0;
  my $pushmode = 0;
  my $critline="";
  while (<$rules>) {
    my $line = $_;
    $line =~ s/^\s*//;
    $line =~ s/\s*$//;
    $line =~ s/#.*//;
    if ($line =~ /^$/) {
      next;
    }
    # we are left with content lines..
    my $donewithline=0;
    while (not $donewithline) {
      if ($line =~ /^\s*$/) {
        $donewithline=1;
        next;
      }
      if ($inlist) {
        if ($line =~/^[^\}]*\{/) {
          #TODO: error unbalanced {} in postscripts.rules
          die "Unbalanced {}";
          return undef; 
        }
        if ($pushmode) {
          my $toadd;
          ($toadd) = $line =~ /(^[^\}]*)/;
          $line =~ s/(^[^\}]*)//;
          unless ($toadd =~ /^\s*$/) {
            push @scripts,$toadd;
          }
        } else { #strip non } characters leading
          $line =~ s/^[^\}]*//;
        }
        if ($line =~ /\}/) {
          $line =~ s/\}//;
          $inlist=0;
        }
      } else {
        if ($line =~/^[^\{]*\}/) {
          #TODO: error unbalanced {} in postscripts.rules
          return undef; 
        }
        (my $tcritline) = $line =~ /^([^\{]*)/;
        $critline .= $tcritline . " ";
        if ($line =~ /\{/) {
          if (criteriamatches($critline)) {
            $pushmode=1;
          } else {
            $pushmode=0;
          }
          $critline = "";
          $inlist = 1;
          $line =~ s/[^\{]*\{//;
        } else {
          $donewithline=1;
        }
      }
    }
  }
  foreach (@scripts) {
    print $script $_."\n";
  }
  close($script);
  chmod 0755,$scriptfile;
}

#shamelessly brought forth from postrules.pl in xCAT 1.3
sub criteriamatches {
  my $cline = shift;
  my $level=0;
  my $pline;
  my @opstack;
  my @expstack;
  my $r;
  $cline =~ s/\{//g;
  $cline =~ s/(\(|\))/ $1 /g;
  $cline =~ s/\s*=\s*/=/g;
  $cline =~ s/^\s*//;
  $cline =~ s/\s*$//;
  $cline =~ s/\s+/ /;
  if ($cline =~ /^ALL$/) {
    return 1;
  }
  my @tokens = split('\s+',$cline);
  my $token;
  foreach $token (@tokens) {
    if ($token eq ')') {
      $level--;
      if ($level == 0) {
        push @expstack,criteriamatches($pline);
        $pline="";
        next;
      } elsif ($level < 0) {
        die "Unbalanecd () in postrules";
      }
    }
    if ($level) {
      $pline .= " $token";
    }
    if ($token eq '(') {
      $level++;
      next;
    }
    if ($level) {
      next;
    }
    if ($token =~ /=/) {
      push(@expstack,$token);
      next;
    }
    if ($token =~ /^(and|or|not)$/i) {
      push (@opstack,$token);
      next;
    }
    die "Syntax error in postscripts rules, bad token $token";
  }
  if ($level) {
    die "Unbalanced () in postscripts rules";
  }

  while (@opstack) {
    my $op;
    my $r1 = 0;
    my $r2 = 0;

    $op = pop(@opstack);
    unless (defined $op) {
      die "Stack underflow in postscripts rules";
    }
    if ($op =~ /and/i) {
      $r1 = popeval(\@expstack);
      $r2 = popeval(\@expstack);

      if ($r1 && $r2) {
        push(@expstack,1);
      } else {
        push(@expstack,0);
      }
    } elsif ($op =~ /or/i) {
      $r1 = popeval(\@expstack);
      $r2 = popeval(\@expstack);
      if ($r1 || $r2) {
        push(@expstack,1);
      } else {
        push(@expstack,0);
      }
    } elsif ($op =~ /not/i) {
      $r1 = popeval(\@expstack);
      if ($r1==0) {
        push(@expstack,1);
      } else {
        push (@expstack,0);
      }
    }
  }
  if (@expstack == 1) {
    $r = popeval(\@expstack);
    push(@expstack,$r);
  }

  $r = pop(@expstack);
  unless (defined $r) {
    die "Stack underflow in postscripts processing";
  }
  if (@expstack != 0 || @opstack != 0) {
    die "Stack underflow in postscripts processing";
  }
  return $r;
}


sub popeval {
  my ($expstack) = @_;
  my $exp;
  my $v;
  my $r;
  $exp = pop(@$expstack);
  if (defined ($exp)) {
    if ($exp =~ /=/) {
      my @eqarr = split(/=/,$exp);
      $r = $eqarr[$#eqarr];
      $v = join('=',@eqarr[0..($#eqarr-1)]);
      #($v,$r) = split(/=/,$exp);
      if ($v =~ /^OSVER$/) { #OSVER is redundant, but a convenient shortcut
        $v = 'TABLE:nodetype:$NODE:os';
      }
      if ($v =~ /^NODERANGE$/i) {
        my @nr = noderange $r;
        foreach (@nr) {
          if ($node eq $_) {
            return 1;
          }
        }
        return 0;
      }
      if ($v =~ /^TABLE:/) {
        my $table;
        my $key;
        my $field;
        ($table,$key,$field) = $v =~ m/TABLE:([^:]+):([^:]+):(.*)/;
        my $tabref = xCAT::Table->new($table);
        unless ($tabref) { return 0; }
        my $ent;
        if ($key =~ /^\$NODE/) {
          $ent = $tabref->getNodeAttribs($node,[$field]);
        } else {
          my @keys = split /,/,$key;
          my %keyh;
          foreach (@keys) {
            my $keycol;
            my $keyval;
            ($keycol,$keyvol)=split /=/,$_;
            $keyh{$keycol}=$keyvol;
          }
          ($ent)=$tabref->getAttribs(\%keyh,$field);
        }

        unless ($ent and $ent->{$field}) { return 0; }
        if ($ent->{$field} =~ /^$r$/) {
          return 1;
        } else {
          return 0;
        }
      }
      #TODO? support for env vars?  Don't see much of a point now, but need input
    } elsif ($exp == 0 || $exp == 1) { 
      return ($exp);
    } else {
      die "Invalid expression $exp in postcripts rules";
    }
  } else {
    die "Stack underflow in postscripts rules...";
  }
}



1;
