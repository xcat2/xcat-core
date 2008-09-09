# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::NodeRange;
use Data::Dumper;
use strict;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

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
  my $rsp;
  my $requires;
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
  my $typetab = xCAT::Table->new('nodetype');
  my $posttab = xCAT::Table->new('postscripts');
  my $sitetab = xCAT::Table->new('site');

  my %rsp;
  my $rsp;
  my $master;
  unless ( $sitetab and $noderestab and $typetab and $posttab) {
	push @{$rsp->{data}}, "Unable to open site or noderes or nodetype or postscripts table";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return undef;
  
  }
  # read all attributes for the site table and write an export
  # for them in the post install file
   my $recs        = $sitetab->getAllEntries();
   my $attribute;
   my $value;
   my $masterset =0 ;
   foreach (@$recs)  # export the attribute
   {
       $attribute =  $_->{key};
       $attribute =~ tr/a-z/A-Z/;
       $value =  $_->{value};
       if ($attribute eq "MASTER" ) {
         $masterset=1;
         push @scriptd, "SITEMASTER=".$value."\n";
         push @scriptd, "export SITEMASTER\n";
         # if node has service node as master then override site master
         my $et = $noderestab->getNodeAttribs($node,['xcatmaster']);
         if ($et and defined($et->{'xcatmaster'})) { 
           $value = $et->{'xcatmaster'};
         }
         push @scriptd, "$attribute=".$value."\n";
         push @scriptd, "export $attribute\n";
 
       } else {   # not Master attribute
           push @scriptd, "$attribute=".$value."\n";
           push @scriptd, "export $attribute\n";
       }
  }
  if ($masterset == 0) {
	my %rsp;
	push @{$rsp->{data}}, "Unable to identify master for $node.\n";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return undef;
       
   }

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

  my $os;
  my $profile;
  my $arch;
  if ($et->{'os'}) {
        $os=$et->{'os'};
  	push @scriptd, "OSVER=".$et->{'os'}."\n";
	push @scriptd, "export OSVER\n";
  }
  if ($et->{'arch'}) {
        $arch=$et->{'arch'};
	push @scriptd, "ARCH=".$et->{'arch'}."\n";
	push @scriptd, "export ARCH\n";
  }
  if ($et->{'profile'}) {
        $profile=$et->{'profile'};
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

  #get monitoring server and other configuration data for monitoring setup on nodes
  my %mon_conf=xCAT_monitoring::monitorctrl->getNodeConfData($node);
  foreach (keys(%mon_conf)) {
    push @scriptd, "$_=" . $mon_conf{$_}. "\n";
    push @scriptd, "export $_\n";
  }

  #get packge names for extra rpms
  if ($profile) {
    my $platform="rh";
    if ($os) {
      if ($os =~ /rh.*/)    { $platform = "rh"; }
      elsif ($os =~ /centos.*/) { $platform = "centos"; }
      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
      elsif ($os =~ /sles.*/) { $platform = "sles"; }
      elsif ($os =~ /aix.*/) { $platform = "aix"; }
    }
    my $stat="install";
    if (($nodesetstate) && ($nodesetstate eq "netboot")) { $stat="netboot";}
    my $pathtofiles="$::XCATROOT/share/xcat/$stat/$platform";
    my $pkglist;
    if (-r "$pathtofiles/$profile.$os.$arch.otherpkgs.pkglist") {
      $pkglist = "$pathtofiles/$profile.$os.$arch.otherpkgs.pkglist";
    } elsif (-r "$pathtofiles/$profile.$arch.otherpkgs.pkglist") {
      $pkglist = "$pathtofiles/$profile.$arch.otherpkgs.pkglist";
    } elsif (-r "$pathtofiles/$profile.$os.otherpkgs.pkglist") {
      $pkglist = "$pathtofiles/$profile.$os.otherpkgs.pkglist";
    } elsif (-r "$pathtofiles/$profile.otherpkgs.pkglist") {
      $pkglist = "$pathtofiles/$profile.otherpkgs.pkglist";
    }

    if ($pkglist) {
      my @otherpkgs=();
      if (open(FILE1, "<$pkglist")) {
        while (readline(FILE1)) {
	  chomp($_);
          push(@otherpkgs,$_);
        }
        close(FILE1);
      } 
      if ( @otherpkgs > 0) { 
        push @scriptd, "OTHERPKGS=". join(',',@otherpkgs) . " \n";
        push @scriptd, "export OTHERPKGS\n";
     }    
    }
  }
  

  ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
  push @scriptd, "# postscripts-start-here\n";

  # get the xcatdefaults entry in the postscripts table
  my $et = $posttab->getAttribs({node=>"xcatdefaults"},'postscripts');
  my $defscripts = $et->{'postscripts'};
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

 
  ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
  push @scriptd, "# postscripts-end-here\n";

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
      my @a=split(' ', $headline);
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
