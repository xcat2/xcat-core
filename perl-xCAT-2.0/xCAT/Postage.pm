# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;
use xCAT::Table;
use xCAT::NodeRange;
use xCAT::MsgUtils;
use Data::Dumper;

#-------------------------------------------------------------------------------

=head1    Postage

=head2    xCAT post script support.

This program module file is a set of utilities to support xCAT post scripts.

=cut

#-------------------------------------------------------------------------------

#----------------------------------------------------------------------------

=head3   writescript

        Create a node-specific post script for an xCAT node

        Arguments:
        Returns:
				0 - All was successful.
                1 - An error occured.
        Globals:
        Error:
        Example:

	xCAT::Postage->writescript($node, "/install/postscripts/" . $node, $state);

		Comments:

=cut

#-----------------------------------------------------------------------------

sub writescript {

	if (scalar(@_) eq 4) { shift; } #Discard self 
	my $node = shift;
	my $scriptfile = shift;
	my $nodesetstate = shift;  # install or netboot

	my ($master, $ps, $os, $arch, $profile); 

	unless (open(SCRIPT,">",$scriptfile)){
		my $rsp;
        push @{$rsp->{data}}, "Could not open $scriptfile for writing.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	#
	# get attribute values from DB...
	#
	# get noderes, nodetype, & site tables
	my $noderestab=xCAT::Table->new('noderes');
	my $typetab=xCAT::Table->new('nodetype');
	my $sitetab = xCAT::Table->new('site');
	my $posttab = xCAT::Table->new('postscripts');

	unless ($noderestab and $typetab and $sitetab) {
		my $rsp;
        push @{$rsp->{data}}, "Unable to open noderes or nodetype or site table.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
	}

	# the master is either the site "master" or the noderes "servicenode"
	#	or the  xcatmaster - in that order
	(my $et) = $sitetab->getAttribs({key=>"master"},'value');
	if ($et and $et->{value}) {
		$master = $et->{value};
	}

	# get servicenode
	$et = $noderestab->getNodeAttribs($node,['servicenode']);
	if ($et and $et->{'servicenode'}) { 
		$master = $et->{'servicenode'};
	}

	# get xcatmaster
	$et = $noderestab->getNodeAttribs($node,['xcatmaster']);
	if ($et and $et->{'xcatmaster'}) { 
		$master = $et->{'xcatmaster'};
	}

	unless ($master) {
        my $rsp;
        push @{$rsp->{data}}, "Unable to identify master for $node.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# get os & arch
	my $et = $typetab->getNodeAttribs($node,['os','arch','profile']);
	$os = $et->{'os'};
	$arch = $et->{'arch'};
	$profile = $et->{'profile'};

	# get postscripts 
	my $et = $posttab->getNodeAttribs($node, ['postscripts']);	
	$ps = $et->{'postscripts'};

	# get the xcatdefaults entry in the postscripts table
	my $et = $posttab->getAttribs({node=>"xcatdefaults"},'postscripts');
	$defscripts = $et->{'postscripts'};

	#
	# build the node-specific script
	#

#print "master=$master, node=$node, os = $os, postscripts= $ps\n";

	print SCRIPT "MASTER=".$master."\n";
	print SCRIPT "export MASTER\n";
	print SCRIPT "NODE=$node\n";
	print SCRIPT "export NODE\n";

	if ($os) {
		print SCRIPT "OSVER=".$os ."\n";
		print SCRIPT "export OSVER\n";
	}
	if ($arch) {
		print SCRIPT "ARCH=".$arch."\n";
		print SCRIPT "export ARCH\n";
	}
	if ($profile) {
		print SCRIPT "PROFILE=".$profile."\n";
        print SCRIPT "export PROFILE\n";
	}
	if ($nodesetstate) {
        print SCRIPT "NODESETSTATE=".$nodesetstate."\n";
        print SCRIPT "export NODESETSTATE\n";
    }
	print SCRIPT 'PATH=`dirname $0`:$PATH'."\n";
	print SCRIPT "export PATH\n";

	if ($defscripts) {
		foreach my $n (split(/,/, $defscripts)) {
            print SCRIPT $n."\n";
        }
	}

	if ($ps) {
        foreach my $n (split(/,/, $ps)) {
            print SCRIPT $n."\n";
        }
    }

  	close(SCRIPT);
	
	my $cmd = "chmod 0755 $scriptfile";
	my @result = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not run the chmod command.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	return 0;
}


##########################
#  old code
#############################


sub old_writescript {
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
  $et = $noderestab->getNodeAttribs($node,['servicenode']);
  if ($et and $et->{'servicenode'}) { 
    $master = $et->{'servicenode'};
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
