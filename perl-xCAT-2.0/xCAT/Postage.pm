# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;
use xCAT::Table;
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

    xCAT::Postage->writescript($node, "/install/postscripts/" . $node, $state);

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
	my %rsp;
	push @{$rsp->{data}}, "Unable to identify master for $node.\n";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return undef;
  }

  push @scriptd, "MASTER=".$master."\n";
  push @scriptd, "export MASTER\n";
  push @scriptd, "NODE=$node\n";
  push @scriptd, "export NODE\n";
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

  if ($nodesetstate) {
	push @scriptd, "NODESETSTATE=".$nodesetstate."\n";
	push @scriptd, "export NODESETSTATE\n";
  }

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

1;
