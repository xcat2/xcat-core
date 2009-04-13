# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::NodeRange;
use xCAT::Utils;
use xCAT::SvrUtils;
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
         } else {
	     $value=xCAT::Utils->getFacingIP($node); 
	 }
         push @scriptd, "$attribute=".$value."\n";
         push @scriptd, "export $attribute\n";
 
       } else {   # not Master attribute
           push @scriptd, "$attribute='".$value."'\n";
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

  my $noderesent = $noderestab->getNodeAttribs($node,['nfsserver']);
  if ($noderesent and defined($noderesent->{'nfsserver'})) {
    push @scriptd, "NFSSERVER=".$noderesent->{'nfsserver'}."\n";
    push @scriptd, "export NFSSERVER\n";
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

	# add the root passwd, if any, for AIX nodes
	# get it from the system/root entry in the passwd table
	# !!!!!  it must be an unencrypted value for AIX!!!!
	# - user will have to reset if this is a security issue
	$os =~ s/\s*$//;
	$os =~ tr/A-Z/a-z/;    # Convert to lowercase
	if ($os eq "aix") {
		my $passwdtab = xCAT::Table->new('passwd');
		unless ( $passwdtab) {
			my $rsp;
			push @{$rsp->{data}}, "Unable to open passwd table.";
			xCAT::MsgUtils->message("E", $rsp, $callback);
		}
                
                if ($passwdtab) {
		  my $et = $passwdtab->getAttribs({key => 'system', username => 'root'}, 'password');
		  if ($et and defined ($et->{'password'})) {
			push @scriptd, "ROOTPW=".$et->{'password'}."\n";
			push @scriptd, "export ROOTPW\n";
		  }
               }
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
  my $stat="install";
  if ($profile) {
    my $platform="rh";
    if ($os) {
      if ($os =~ /rh.*/)    { $platform = "rh"; }
      elsif ($os =~ /centos.*/) { $platform = "centos"; }
      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
      elsif ($os =~ /sles.*/) { $platform = "sles"; }
      elsif ($os =~ /aix.*/) { $platform = "aix"; }
    }
    if (($nodesetstate) && ($nodesetstate eq "netboot")) { $stat="netboot";}
    my $pkglist=get_otherpkg_file_name("/install/custom/$stat/$platform", $profile,  $os, $arch);
    if (!$pkglist) { $pkglist=get_otherpkg_file_name("$::XCATROOT/share/xcat/$stat/$platform", $profile, $os, $arch); }

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

        if (-r "/install/post/otherpkgs/$os/$arch/repodata/repomd.xml") {
          push @scriptd, "OTHERPKGS_HASREPO=1\n";
          push @scriptd, "export OTHERPKGS_HASREPO\n";
        }
      }    
    }
  }
  

  ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
  push @scriptd, "# postscripts-start-here\n";

  my %post_hash=();  #used to reduce duplicates
  # get the xcatdefaults entry in the postscripts table
  my $et = $posttab->getAttribs({node=>"xcatdefaults"},'postscripts');
  my $defscripts = $et->{'postscripts'};
  if ($defscripts) {
    foreach my $n (split(/,/, $defscripts)) {
      if (! exists($post_hash{$n})) {
	$post_hash{$n}=1;
        push @scriptd, $n."\n";
      }
    }
  }

  # get postscripts
  my $et = $posttab->getNodeAttribs($node, ['postscripts']);
  $ps = $et->{'postscripts'};
  if ($ps) {
    foreach my $n (split(/,/, $ps)) {
      if (! exists($post_hash{$n})) {
	$post_hash{$n}=1;
        push @scriptd, $n."\n";
      }
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
  return xCAT::SvrUtils->get_nodeset_state($node);
}

sub  get_otherpkg_file_name {
  my $pathtofiles=shift;
  my $profile=shift;
  my $os=shift;
  my $arch=shift;
  if (-r "$pathtofiles/$profile.$os.$arch.otherpkgs.pkglist") {
     return "$pathtofiles/$profile.$os.$arch.otherpkgs.pkglist";
   } elsif (-r "$pathtofiles/$profile.$arch.otherpkgs.pkglist") {
     return "$pathtofiles/$profile.$arch.otherpkgs.pkglist";
   } elsif (-r "$pathtofiles/$profile.$os.otherpkgs.pkglist") {
     return "$pathtofiles/$profile.$os.otherpkgs.pkglist";
   } elsif (-r "$pathtofiles/$profile.otherpkgs.pkglist") {
     return "$pathtofiles/$profile.otherpkgs.pkglist";
   }
   
   return "";
}

1;
