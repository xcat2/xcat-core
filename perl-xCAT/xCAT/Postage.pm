# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::NodeRange;
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
        Globals:
        Error:
        Example:

    xCAT::Postage->writescript($node, "/install/postscripts/" . $node, $state,$callback);

        Comments:

=cut

#-----------------------------------------------------------------------------

sub writescript {
  if (scalar(@_) eq 5) { shift; } #Discard self 
  my $node = shift;
  my $scriptfile = shift;
  my $nodesetstate = shift;  # install or netboot
  my $callback = shift;

  my $script;
  open($script,">",$scriptfile);
  unless ($scriptfile) {
	my %rsp;
	push @{$rsp->{data}}, "Could not open $scriptfile for writing.\n";
	xCAT::MsgUtils->message("E", $rsp, $callback);
    return 1;
  }
  #Some common variables...
  my @scriptcontents = makescript($node, $nodesetstate, $callback);
  if (!defined(@scriptcontents)) {
	my %rsp;
	push @{$rsp->{data}}, "Could not create node post script file for node \'$node\'.\n";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return 1;
  } else {	
  	foreach (@scriptcontents) {
     	print $script $_;
	}
  }
  close($script);
  chmod 0755,$scriptfile;
}

#----------------------------------------------------------------------------

=head3   makescript

        Determine the contents of a node-specific post script for an xCAT node

        Arguments:
        Returns:
        Globals:
        Error:
        Example:

    xCAT::Postage->makescript($node, $nodesetstate, $callback);

        Comments:

=cut

#-----------------------------------------------------------------------------
sub makescript {
  my $node = shift;
  my $nodesetstate = shift;  # install or netboot
  my $callback = shift;

  my @scriptd;
  my ($master, $ps, $os, $arch, $profile);

  my $noderestab=xCAT::Table->new('noderes');
  my $typetab=xCAT::Table->new('nodetype');
  my $posttab = xCAT::Table->new('postscripts');

  unless ($noderestab and $typetab and $posttab) {
	my %rsp;
	push @{$rsp->{data}}, "Unable to open noderes or nodetype or postscripts table";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return undef;
  }
  # read the master node from the site table for the node  
  my $master;   # may be the Management Node or Service Node
  my $sitemaster; # Always the Management Node
  my $sitetab = xCAT::Table->new('site');
  (my $et) = $sitetab->getAttribs({key=>"master"},'value');
  if ($et and defined($et->{value})) {
      $master = $et->{value};
      $sitemaster = $et->{value};

  }
  # if node has service node as master then override site master
  $et = $noderestab->getNodeAttribs($node,['xcatmaster']);
  if ($et and defined($et->{'xcatmaster'})) { 
    $master = $et->{'xcatmaster'};
  }
  unless ($master) {
	my %rsp;
	push @{$rsp->{data}}, "Unable to identify master for $node.\n";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return undef;
  }

  # read the ntpservers 
  my $ntpservers;
  (my $et) = $sitetab->getAttribs({key=>"ntpservers"},'value');
  if ($et and defined($et->{value})) {
      $ntpservers = $et->{value};

  }

  # read the remoteshell attributes, if they exist 
  # default to rsh on AIX and ssh on Linux
  my $rsh;
  my $rcp;
  if (xCAT::Utils->isLinux()) {
     $rsh = "/usr/bin/ssh";
     $rcp = "/usr/bin/scp";
  } else { #AIX
     $rsh = "/bin/rsh";
     $rcp = "/bin/rcp";
  }
  # check for admin input
  (my $et) = $sitetab->getAttribs({key=>"rsh"},'value');
  if ($et and defined($et->{value})) {
      $rsh = $et->{value};

  }
  (my $et) = $sitetab->getAttribs({key=>"rcp"},'value');
  if ($et and defined($et->{value})) {
      $rcp = $et->{value};

  }
  # set env variable $SITEMASTER for Management Node 
  push @scriptd, "SITEMASTER=".$sitemaster."\n";
  push @scriptd, "export SITEMASTER\n";

  # set env variable $MASTER for master of node (MN or SN)
  push @scriptd, "MASTER=".$master."\n";
  push @scriptd, "export MASTER\n";
  push @scriptd, "NODE=$node\n";
  push @scriptd, "export NODE\n";

  # if ntpservers exist, export $NTPSERVERS
  if (defined($ntpservers)) {
    push @scriptd, "NTPSERVERS=".$ntpservers."\n";
    push @scriptd, "export NTPSERVERS\n";
  }

  # export remote shell 
  push @scriptd, "RSH=".$rsh."\n";
  push @scriptd, "export RSH\n";
  push @scriptd, "RCP=".$rcp."\n";
  push @scriptd, "export RCP\n";

  my $et = $typetab->getNodeAttribs($node,['os','arch','profile']);
  if ($^O =~ /^linux/i) {
	unless ($et and $et->{'os'} and $et->{'arch'}) {
		my %rsp;
		push @{$rsp->{data}}, "No os or arch setting in nodetype table for $node.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return undef;
	}
  }
  if ($et->{'os'}) {
  	push @scriptd, "OSVER=".$et->{'os'}."\n";
	push @scriptd, "export OSVER\n";
  }
  if ($et->{'arch'}) {
	push @scriptd, "ARCH=".$et->{'arch'}."\n";
	push @scriptd, "export ARCH\n";
  }
  if ($et->{'profile'}) {
  	push @scriptd, "PROFILE=".$et->{'profile'}."\n";
  	push @scriptd, "export PROFILE\n";
  }
  push @scriptd, 'PATH=`dirname $0`:$PATH'."\n";
  push @scriptd, "export PATH\n";
  my $sent = $sitetab->getAttribs({key=>'svloglocal'},'value');
  if ($sent and defined($sent->{value})) {
    push @scriptd, "SVLOGLOCAL=".$sent->{'value'}."\n";
    push @scriptd, "export SVLOGLOCAL\n"; 
  } 

  if (!$nodesetstate) { $nodesetstate=getnodesetstate($node);}
  push @scriptd, "NODESETSTATE=".$nodesetstate."\n";
  push @scriptd, "export NODESETSTATE\n";


  # see if this is a service or compute node?         
  if (xCAT::Utils->isSN($node) ) {
	push @scriptd, "NTYPE=service\n";
  } else {
  	push @scriptd, "NTYPE=compute\n";
  }
  push @scriptd, "export NTYPE\n";

  # get the xcatdefaults entry in the postscripts table
  my $et = $posttab->getAttribs({node=>"xcatdefaults"},'postscripts');
  $defscripts = $et->{'postscripts'};
  if ($defscripts) {
  	foreach my $n (split(/,/, $defscripts)) {
		push @scriptd, $n."\n";
 	}
  }

  # get postscripts
  my $et = $posttab->getNodeAttribs($node, ['postscripts']);
  $ps = $et->{'postscripts'};
  if ($ps) {
	foreach my $n (split(/,/, $ps)) {
		push @scriptd, $n."\n";
	}
  }

  return @scriptd;
}

#----------------------------------------------------------------------------

=head3   getnodesetstate

        Determine the nodeset stat.
=cut

#-----------------------------------------------------------------------------
sub getnodesetstate {
  my $node=shift;
  my $state="undefined";

  #get boot type (pxe or yaboot)  for the node
  my $noderestab=xCAT::Table->new('noderes',-create=>0);
  my $ent=$noderestab->getNodeAttribs($node,[qw(netboot)]);
  if ($ent->{netboot})  {
    my $boottype=$ent->{netboot};

    #get nodeset state from corresponding files
    my $bootfilename;
    if ($boottype eq "pxe") { $bootfilename="/tftpboot/pxelinux.cfg/$node";}
    elsif ($boottype eq "yaboot") { $bootfilename="/tftpboot/etc/$node";}
    else { $bootfilename="/tftpboot/pxelinux.cfg/$node"; }

    if (-r $bootfilename) {
      my $fhand;
      open ($fhand, $bootfilename);
      my $headline = <$fhand>;
      close $fhand;
      $headline =~ s/^#//;
      chomp($headline);
      @a=split(' ', $headline);
      $state = $a[0];
    } else {
      xCAT::MsgUtils->message('S', "getpostscripts: file $bootfilename cannot be accessed.");
    }
  } else {
    xCAT::MsgUtils->message('S', "getpostscripts: noderes.netboot for node $node not defined.");
  }

  #get the nodeset state from the chain table as a backup.
  if ($state eq "undefined") {
    my $chaintab = xCAT::Table->new('chain');
    my $stref = $chaintab->getNodeAttribs($node,['currstate']);
    if ($stref and $stref->{currstate}) { $state=$stref->{currstate}; }
  }

  return $state;
}

1;
