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
  if (scalar(@_) eq 4) { shift; } #Discard self 
  my $node = shift;
  my $scriptfile = shift;
  my $nodesetstate = shift;  # install or netboot

  my $script;
  open($script,">",$scriptfile);
  unless ($scriptfile) {
    return undef;
  }
  #Some common variables...
  my @scriptcontents = makescript($node);
  foreach (@scriptcontents) {
     print $script $_;
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

    xCAT::Postage->writescript($node, "/install/postscripts/" . $node, $state);

        Comments:

=cut

#-----------------------------------------------------------------------------
sub makescript {
  $node = shift;
  my @scriptd;

  my ($master, $ps, $os, $arch, $profile);

  my $noderestab=xCAT::Table->new('noderes');
  my $typetab=xCAT::Table->new('nodetype');
  my $posttab = xCAT::Table->new('postscripts');

  unless ($noderestab and $typetab and $posttab) {
    die "Unable to open noderes or nodetype or site or postscripts table";
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

  push @scriptd, "MASTER=".$master."\n";
  push @scriptd, "export MASTER\n";
  push @scriptd, "NODE=$node\n";
  push @scriptd, "export NODE\n";
  my $et = $typetab->getNodeAttribs($node,['os','arch','profile']);
  unless ($et and $et->{'os'} and $et->{'arch'} and $et->{'profile'}) {
    die "No os or arch or profile setting in nodetype table for $node";
  }
  push @scriptd, "OSVER=".$et->{'os'}."\n";
  push @scriptd, "ARCH=".$et->{'arch'}."\n";
  push @scriptd, "PROFILE=".$et->{'profile'}."\n";
  push @scriptd, "export OSVER ARCH PROFILE\n";
  push @scriptd, 'PATH=`dirname $0`:$PATH'."\n";
  push @scriptd, "export PATH\n";
  if ($nodesetstate) {
	push @scriptd, "NODESETSTATE=".$nodesetstate."\n";
	push @scriptd, "export NODESETSTATE\n";
  }

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
