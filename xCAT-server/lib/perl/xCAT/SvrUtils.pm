#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::SvrUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
require xCAT::Utils;
use File::Basename;

use strict;


#-------------------------------------------------------------------------------

=head3   getNodesetStates
       get current nodeset stat for the given nodes 
    Arguments:
        nodes -- a pointer to an array of nodes
        hashref -- A pointer to a hash that contains the nodeset status.  
    Returns:
       (ret code, error message) 

=cut

#-------------------------------------------------------------------------------
sub getNodesetStates
{
    my $noderef = shift;
    if ($noderef =~ /xCAT::SvrUtils/)
    {
        $noderef = shift;
    }
    my @nodes   = @$noderef;
    my $hashref = shift;

    if (@nodes > 0)
    {
        my $tab = xCAT::Table->new('noderes');
        if (!$tab) { return (1, "Unable to open noderes table."); }

        my @aixnodes    = ();
        my @pxenodes    = ();
        my @yabootnodes = ();
        my $tabdata     = $tab->getNodesAttribs(\@nodes, ['node', 'netboot']);
        foreach my $node (@nodes)
        {
            my $nb   = "aixinstall";
            my $tmp1 = $tabdata->{$node}->[0];
            if (($tmp1) && ($tmp1->{netboot})) { $nb = $tmp1->{netboot}; }
            if ($nb eq "yaboot")
            {
                push(@yabootnodes, $node);
            }
            elsif ($nb eq "pxe")
            {
                push(@pxenodes, $node);
            }
            elsif ($nb eq "aixinstall")
            {
                push(@aixnodes, $node);
            }
        }

        my @retarray;
        my $retcode = 0;
        my $errormsg;

        # print "ya=@yabootnodes, pxe=@pxenodes, aix=@aixnodes\n";
        if (@yabootnodes > 0)
        {
            require xCAT_plugin::yaboot;
            @retarray =
              xCAT_plugin::yaboot::getNodesetStates(\@yabootnodes, $hashref);
            if ($retarray[0])
            {
                $retcode = $retarray[0];
                $errormsg .= $retarray[1];
                xCAT::MsgUtils->message('E', $retarray[1]);
            }
        }
        if (@pxenodes > 0)
        {
            require xCAT_plugin::pxe;
            @retarray =
              xCAT_plugin::pxe::getNodesetStates(\@pxenodes, $hashref);
            if ($retarray[0])
            {
                $retcode = $retarray[0];
                $errormsg .= $retarray[1];
                xCAT::MsgUtils->message('E', $retarray[1]);
            }
        }
        if (@aixnodes > 0)
        {
            require xCAT_plugin::aixinstall;
            @retarray =
              xCAT_plugin::aixinstall::getNodesetStates(\@aixnodes, $hashref);
            if ($retarray[0])
            {
                $retcode = $retarray[0];
                $errormsg .= $retarray[1];
                xCAT::MsgUtils->message('E', $retarray[1]);
            }
        }
    }
    return (0, "");
}

#-------------------------------------------------------------------------------

=head3   get_nodeset_state
       get current nodeset stat for the given node.
    Arguments:
        nodes -- node name.
    Returns:
       nodesetstate 

=cut

#-------------------------------------------------------------------------------
sub get_nodeset_state
{
    my $node = shift;
    if ($node =~ /xCAT::SvrUtils/)
    {
        $node = shift;
    }

    my $state = "undefined";

    #get boot type (pxe, yaboot or aixinstall)  for the node
    my $noderestab = xCAT::Table->new('noderes', -create => 0);
    my $ent = $noderestab->getNodeAttribs($node, [qw(netboot)]);
    if ($ent && $ent->{netboot})
    {
        my $boottype = $ent->{netboot};

        #get nodeset state from corresponding files
        if ($boottype eq "pxe")
        {
            require xCAT_plugin::pxe;
            my $tmp = xCAT_plugin::pxe::getstate($node);
            my @a = split(' ', $tmp);
            $state = $a[0];

        }
        elsif ($boottype eq "yaboot")
        {
            require xCAT_plugin::yaboot;
            my $tmp = xCAT_plugin::yaboot::getstate($node);
            my @a = split(' ', $tmp);
            $state = $a[0];
        }
        elsif ($boottype eq "aixinstall")
        {
            require xCAT_plugin::aixinstall;
            $state = xCAT_plugin::aixinstall::getNodesetState($node);
        }
    }
    else
    {    #default to AIX because AIX does not set noderes.netboot value
        require xCAT_plugin::aixinstall;
        $state = xCAT_plugin::aixinstall::getNodesetState($node);
    }

    #get the nodeset state from the chain table as a backup.
    if ($state eq "undefined")
    {
        my $chaintab = xCAT::Table->new('chain');
        my $stref = $chaintab->getNodeAttribs($node, ['currstate']);
        if ($stref and $stref->{currstate}) { $state = $stref->{currstate}; }
    }

    return $state;
}

#-----------------------------------------------------------------------------


=head3 getsynclistfile
    Get the synclist file for the nodes;
    The arguments $os,$arch,$profile,$insttype are only available when no $nodes is specified

    Arguments:
      $nodes
      $os
      $arch
      $profile
      $insttype  - installation type (can be install or netboot)
    Returns:
      When specified $nodes: reference of a hash of node=>synclist
      Otherwise: full path of the synclist file
    Globals:
        none
    Error:
    Example:
         my $node_syncfile=xCAT::SvrUtils->getsynclistfile($nodes);
         my $syncfile=xCAT::SvrUtils->getsynclistfile(undef, 'sles11', 'ppc64', 'compute', 'netboot');
    Comments:
        none

=cut

#-----------------------------------------------------------------------------


sub getsynclistfile()
{
  my $nodes = shift;
  if (($nodes) && ($nodes =~ /xCAT::SvrUtils/))
  {
    $nodes = shift;
  }

  my ($os, $arch, $profile, $inst_type) = @_;

  # for aix node, use the node figure out the profile, then use the value of
  # profile (osimage name) to get the synclist file path (osimage.synclists)
  if (xCAT::Utils->isAIX()) {
    my %node_syncfile = ();
    my %osimage_syncfile = ();
    my @profiles = ();

    # get the profile attributes for the nodes
    my $nodetype_t = xCAT::Table->new('nodetype');
    unless ($nodetype_t) {
      return ;
    }
    my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['profile', 'provmethod']);

    # the vaule of profile for AIX node is the osimage name
    foreach my $node (@$nodes) {
      my $profile = $nodetype_v->{$node}->[0]->{'profile'};
      my $provmethod=$nodetype_v->{$node}->[0]->{'provmethod'};
      if ($provmethod) {
	  $profile=$provmethod;
      }
	  
      $node_syncfile{$node} = $profile;
      
      if (! grep /$profile/, @profiles) {
        push @profiles, $profile;
      }
    }

    # get the syncfiles base on the osimage
    my $osimage_t = xCAT::Table->new('osimage');
    unless ($osimage_t) {
      return ;
    }
    foreach my $osimage (@profiles) {
      my $synclist = $osimage_t->getAttribs({imagename=>"$osimage"}, 'synclists');
      $osimage_syncfile{$osimage} = $synclist->{'synclists'};
    }

    # set the syncfiles to the nodes
    foreach my $node (@$nodes) {
      $node_syncfile{$node} = $osimage_syncfile{$node_syncfile{$node}};
    }

    return \%node_syncfile;
  }

  # if does not specify the $node param, default consider for genimage command
  if ($nodes) {
    my %node_syncfile = ();

    my %node_insttype = ();
    my %insttype_node = ();
    # get the nodes installation type
    xCAT::SvrUtils->getNodesetStates($nodes, \%insttype_node);
    # convert the hash to the node=>type
    foreach my $type (keys %insttype_node) {
      foreach my $node (@{$insttype_node{$type}}) {
        $node_insttype{$node} = $type;
      }
    }

    # get the os,arch,profile attributes for the nodes
    my $nodetype_t = xCAT::Table->new('nodetype');
    unless ($nodetype_t) {
      return ;
    }
    my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['profile','os','arch','provmethod']);

    foreach my $node (@$nodes) {
      my $provmethod=$nodetype_v->{$node}->[0]->{'provmethod'};
      if (($provmethod) && ( $provmethod ne "install") && ($provmethod ne "netboot")) {
	  # get the syncfiles base on the osimage
	  my $osimage_t = xCAT::Table->new('osimage');
	  unless ($osimage_t) {
	      return ;
	  }
	  my $synclist = $osimage_t->getAttribs({imagename=>$provmethod}, 'synclists');
	  if ($synclist && $synclist->{'synclists'}) {
	      $node_syncfile{$node} = $synclist->{'synclists'};
	  }  
      } else {
	  $inst_type = $node_insttype{$node};
	  if ($inst_type eq "netboot" || $inst_type eq "diskless") {
	      $inst_type = "netboot";
	  } else {
	      $inst_type = "install";
	  }
	  
	  $profile = $nodetype_v->{$node}->[0]->{'profile'};
	  $os = $nodetype_v->{$node}->[0]->{'os'};
	  $arch = $nodetype_v->{$node}->[0]->{'arch'};
	  my $platform = "";
	  if ($os) {
	      if ($os =~ /rh.*/)    { $platform = "rh"; }
	      elsif ($os =~ /centos.*/) { $platform = "centos"; }
	      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
	      elsif ($os =~ /sles.*/) { $platform = "sles"; }
	      elsif ($os =~ /AIX.*/) { $platform = "AIX"; }
	  }

	  my $base =  "/install/custom/$inst_type/$platform";
	  if (-r "$base/$profile.$os.$arch.synclist") {
	      $node_syncfile{$node} = "$base/$profile.$os.$arch.synclist";
	  } elsif (-r "$base/$profile.$arch.synclist") {
	      $node_syncfile{$node} = "$base/$profile.$arch.synclist";
	  } elsif (-r "$base/$profile.$os.synclist") {
	      $node_syncfile{$node} = "$base/$profile.$os.synclist";
	  } elsif (-r "$base/$profile.synclist") {
	      $node_syncfile{$node} = "$base/$profile.synclist";
	  }
      }
    }

    return \%node_syncfile;
  } else {
    my $platform = "";
    if ($os) {
      if ($os =~ /rh.*/)    { $platform = "rh"; }
      elsif ($os =~ /centos.*/) { $platform = "centos"; }
      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
      elsif ($os =~ /sles.*/) { $platform = "sles"; }
      elsif ($os =~ /AIX.*/) { $platform = "AIX"; }
      elsif ($os =~ /win/)  {$platform = "windows"; }
    }

    my $base = "/install/custom/$inst_type/$platform";
    if (-r "$base/$profile.$os.$arch.synclist") {
      return "$base/$profile.$os.$arch.synclist";
    } elsif (-r "$base/$profile.$arch.synclist") {
      return "$base/$profile.$arch.synclist";
    } elsif (-r "$base/$profile.$os.synclist") {
      return "$base/$profile.$os.synclist";
    } elsif (-r "$base/$profile.synclist") {
      return "$base/$profile.synclist";
    }

  }

}

sub get_file_name {
    my ($searchpath, $extension, $profile, $os, $arch, $genos) = @_;
    #usally there're only 4 arguments passed for this function
    #the $genos is only used for the Redhat family

    my $dotpos = rindex($os, ".");
    my $osbase = substr($os, 0, $dotpos);
    #handle the following ostypes: sles10.2, sles11.1, rhels5.3, rhels5.4, etc

    if (-r "$searchpath/$profile.$os.$arch.$extension") {
        return "$searchpath/$profile.$os.$arch.$extension";
    }
    elsif (-r "$searchpath/$profile.$osbase.$arch.$extension") {
        return "$searchpath/$profile.$osbase.$arch.$extension";
    }
    elsif (-r "$searchpath/$profile.$genos.$arch.$extension") {
        return "$searchpath/$profile.$genos.$arch.$extension";
    }
    elsif (-r "$searchpath/$profile.$os.$extension") {
        return "$searchpath/$profile.$os.$extension";
    }
    elsif (-r "$searchpath/$profile.$osbase.$extension") {
        return "$searchpath/$profile.$osbase.$extension";
    }
    elsif (-r "$searchpath/$profile.$genos.$extension") {
        return "$searchpath/$profile.$genos.$extension";
    }
    elsif (-r "$searchpath/$profile.$arch.$extension") {
        return "$searchpath/$profile.$arch.$extension";
    }
    elsif (-r "$searchpath/$profile.$extension") {
        return "$searchpath/$profile.$extension";
    }
    else {
        return undef;
    }
}

sub get_tmpl_file_name {
    my $searchpath=shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
	$searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "tmpl", @_);
}


sub get_pkglist_file_name {
    my $searchpath=shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
	$searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "pkglist", @_);
}

sub get_otherpkgs_pkglist_file_name {
    my $searchpath=shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
	$searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "otherpkgs.pkglist", @_);
}


sub get_postinstall_file_name {
    my $searchpath=shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
	$searchpath = shift;
    }
    my $profile=shift;
    my $os=shift;
    my $arch=shift;
    my $extension="postinstall";
    my $dotpos = rindex($os, ".");
    my $osbase = substr($os, 0, $dotpos);
    #handle the following ostypes: sles10.2, sles11.1, rhels5.3, rhels5.4, etc

    if (-x "$searchpath/$profile.$os.$arch.$extension") {
        return "$searchpath/$profile.$os.$arch.$extension";
    }
    elsif (-x "$searchpath/$profile.$osbase.$arch.$extension") {
        return "$searchpath/$profile.$osbase.$arch.$extension";
    }
    elsif (-x "$searchpath/$profile.$os.$extension") {
        return "$searchpath/$profile.$os.$extension";
    }
    elsif (-x "$searchpath/$profile.$osbase.$extension") {
        return "$searchpath/$profile.$osbase.$extension";
    }
    elsif (-x "$searchpath/$profile.$arch.$extension") {
        return "$searchpath/$profile.$arch.$extension";
    }
    elsif (-x "$searchpath/$profile.$extension") {
        return "$searchpath/$profile.$extension";
    }
    else {
        return undef;
    }
}


sub get_exlist_file_name {
    my $searchpath=shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
	$searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "exlist", @_);
}


#-------------------------------------------------------------------------------

=head3   update_tables_with_templates
       This function is called after copycds. Itwill get all the possible install templates
       from the default directories for the given osver and arch and update the osimage table.
    Arguments:
        osver
        arch
    Returns:
        an array (retcode, errmsg). The first one is the return code. If 0, it means succesful. 

=cut

#-------------------------------------------------------------------------------
sub  update_tables_with_templates
{
    my $osver = shift;  #like sle11, rhel5.3 
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
	$osver = shift;
    }
    my $arch = shift;  #like ppc64, x86, x86_64
    
    my $osname=$osver;;  #like sles, rh, centos, windows
    my $ostype="Linux";  #like Linux, Windows
    my $imagetype="linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
	$osname="windows";
	$ostype="Windows";
        $imagetype="windows";
    } else {
	until (-r  "$::XCATROOT/share/xcat/install/$osname/" or not $osname) {
	    chop($osname);
        }
        unless ($osname) {
	    return (1, "Unable to find $::XCATROOT/share/xcat/install directory for $osver");
	}  
    } 
      
    #for rhels5.1  genos=rhel5
    my $genos = $osver;
    $genos =~ s/\..*//;
    if ($genos =~ /rh.*s(\d*)/) {
	$genos = "rhel$1";
    }

  
    #print "osver=$osver, arch=$arch, osname=$osname, genos=$genos\n";
    my $installroot="/install";  
    my $sitetab = xCAT::Table->new('site');
    if ($sitetab) {
	(my $ref) = $sitetab->getAttribs({key => "installdir"}, "value");
	if ($ref and $ref->{value}) {
	    $installroot = $ref->{value};
	}
    }
    my $cuspath="$installroot/custom/install/$osname";
    my $defpath="$::XCATROOT/share/xcat/install/$osname"; 
    
    #now get all the profile names for full installation
    my %profiles=();
    my @tmplfiles=glob($cuspath."/*.tmpl");
    foreach (@tmplfiles) {
	my $tmpf=basename($_); 
	#get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
	$tmpf =~ /^([^\.]*)\..*$/;
	$tmpf = $1;
	#print "$tmpf\n";
	$profiles{$tmpf}=1;
    }
    @tmplfiles=glob($defpath."/*.tmpl");
    foreach (@tmplfiles) {
	my $tmpf=basename($_); 
	#get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
	$tmpf =~ /^([^\.]*)\..*$/;
	$tmpf = $1;
	$profiles{$tmpf}=1;
    }
    
    #update the osimage and linuximage table
    my $osimagetab;
    my $linuximagetab;
    foreach my $profile (keys %profiles) {
	#print "profile=$profile\n";
	#get template file
	my $tmplfile=get_tmpl_file_name ($cuspath, $profile, $osver, $arch, $genos);
	if (!$tmplfile) { $tmplfile=get_tmpl_file_name ($defpath, $profile, $osver, $arch, $genos);}
	if (!$tmplfile) { next; }
	
	#get otherpkgs.pkglist file
	my $otherpkgsfile=get_otherpkgs_pkglist_file_name($cuspath, $profile, $osver, $arch);
	if (!$otherpkgsfile) { $otherpkgsfile=get_otherpkgs_pkglist_file_name($defpath, $profile, $osver, $arch);}
	
	#get synclist file
	my $synclistfile=xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");
	
	#now update the db
	if (!$osimagetab) { 
	    $osimagetab=xCAT::Table->new('osimage',-create=>1); 
	}

	if ($osimagetab) {    
	    #check if the image is already in the table
	    if ($osimagetab) {
		my $found=0;
		my $tmp1=$osimagetab->getAllEntries();
		if (defined($tmp1) && (@$tmp1 > 0)) {
		    foreach my $rowdata(@$tmp1) {
			if (($osver eq $rowdata->{osvers}) && ($arch eq $rowdata->{osarch}) && ($rowdata->{provmethod} eq "install") && ($profile eq $rowdata->{profile})){
			    $found=1;
			    last;
			}
		    }
		}
		if ($found) { next; } 

		my $imagename=$osver . "-" . $arch . "-install-" . $profile;
                #TODO: check if there happen to be a row that has the same imagename but with different contents
                #now we can wirte the info into db
		my %key_col = (imagename=>$imagename);
		my %tb_cols=(imagetype=>$imagetype,
			     provmethod=>"install",
			     profile=>$profile, 
			     osname=>$ostype,
			     osvers=>$osver,
			     osarch=>$arch,
			     synclists=>$synclistfile);
		$osimagetab->setAttribs(\%key_col, \%tb_cols);
                
		if ($osname !~ /^win/) {
		    if (!$linuximagetab) { $linuximagetab=xCAT::Table->new('linuximage',-create=>1); }
		    if ($linuximagetab) {
			my %key_col = (imagename=>$imagename);
			my %tb_cols=(template=>$tmplfile, 
				     pkgdir=>"$installroot/$osver/$arch",
				     otherpkglist=>$otherpkgsfile,
				     otherpkgdir=>"$installroot/post/otherpkgs/$osver/$arch");
			$linuximagetab->setAttribs(\%key_col, \%tb_cols);
			
		    } else {
			return (1, "Cannot open the linuximage table.");
		    }
		}
	    } else {
		return (1, "Cannot open the osimage table."); 
	    }
	}  
    }
    if ($osimagetab) { $osimagetab->close(); }
    if ($linuximagetab) { $linuximagetab->close(); }
    return (0, "");
}

#-------------------------------------------------------------------------------

=head3   update_tables_with_diskless_image
       This function is called after a diskless image is created by packimage.
    It'll writes the newimage info into the osimage and the linuximage tables.
    Arguments:
        osver
        arch
        profile
    Returns:
        an array (retcode, errmsg). The first one is the return code. If 0, it means succesful. 

=cut

#-------------------------------------------------------------------------------
sub  update_tables_with_diskless_image
{
    my $osver = shift;  #like sle11, rhel5.3 
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
	$osver = shift;
    }
    my $arch = shift;  #like ppc64, x86, x86_64
    my $profile = shift;
    
    my $osname=$osver;;  #like sles, rh, centos, windows
    my $ostype="Linux";  #like Linux, Windows
    my $imagetype="linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
	$osname="windows";
	$ostype="Windows";
	$imagetype="windows";
    } else {
	until (-r  "$::XCATROOT/share/xcat/netboot/$osname/" or not $osname) {
	    chop($osname);
        }
        unless ($osname) {
	    return (1, "Unable to find $::XCATROOT/share/xcat/netboot directory for $osver");
	}  
    } 
      
    #for rhels5.1  genos=rhel5
    my $genos = $osver;
    $genos =~ s/\..*//;
    if ($genos =~ /rh.*s(\d*)/) {
	$genos = "rhel$1";
    }
  
    #print "osver=$osver, arch=$arch, osname=$osname, genos=$genos, profile=$profile\n";
    my $installroot="/install";  
    my $sitetab = xCAT::Table->new('site');
    if ($sitetab) {
	(my $ref) = $sitetab->getAttribs({key => "installdir"}, "value");
	if ($ref and $ref->{value}) {
	    $installroot = $ref->{value};
	}
    }
    my $cuspath="$installroot/custom/netboot/$osname";
    my $defpath="$::XCATROOT/share/xcat/netboot/$osname"; 
    my $osimagetab;
    my $linuximagetab;

    #get the pkglist file
    my $pkglistfile=get_pkglist_file_name($cuspath, $profile, $osver, $arch);
    if (!$pkglistfile) { $pkglistfile=get_pkglist_file_name($defpath, $profile, $osver, $arch);}
    #print "pkglistfile=$pkglistfile\n";
    if (!$pkglistfile) { return (0, "");}
    
    #get otherpkgs.pkglist file
    my $otherpkgsfile=get_otherpkgs_pkglist_file_name($cuspath, $profile, $osver, $arch);
    if (!$otherpkgsfile) { $otherpkgsfile=get_otherpkgs_pkglist_file_name($defpath, $profile, $osver, $arch);}
    
    #get synclist file
    my $synclistfile=xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");
    
    #get the exlist file
    my $exlistfile=get_exlist_file_name($cuspath, $profile, $osver, $arch);
    if (!$exlistfile) {  $exlistfile=get_exlist_file_name($defpath, $profile, $osver, $arch); }

    #get postinstall script file name
    my $postfile=get_postinstall_file_name($cuspath, $profile, $osver, $arch);
    if (!$postfile) {  $postfile=get_postinstall_file_name($defpath, $profile, $osver, $arch); }


    #now update the db
    if (!$osimagetab) { 
	$osimagetab=xCAT::Table->new('osimage',-create=>1); 
    }
    
    if ($osimagetab) {    
	#check if the image is already in the table
	if ($osimagetab) {
	    my $found=0;
	    my $tmp1=$osimagetab->getAllEntries();
	    if (defined($tmp1) && (@$tmp1 > 0)) {
		foreach my $rowdata(@$tmp1) {
		    if (($osver eq $rowdata->{osvers}) && ($arch eq $rowdata->{osarch}) && ($rowdata->{provmethod} eq "netboot") && ($profile eq $rowdata->{profile})){
			$found=1;
			last;
		    }
		}
	    }
	    if ($found) { print "The image is already in the db.\n"; return (0, ""); } 
	    
	    my $imagename=$osver . "-" . $arch . "-netboot-" . $profile;
	    #TODO: check if there happen to be a row that has the same imagename but with different contents
	    #now we can wirte the info into db
	    my %key_col = (imagename=>$imagename);
	    my %tb_cols=(imagetype=>$imagetype, 
			 provmethod=>"netboot",
			 profile=>$profile, 
			 osname=>$ostype,
			 osvers=>$osver,
			 osarch=>$arch,
			 synclists=>$synclistfile);
	    $osimagetab->setAttribs(\%key_col, \%tb_cols);
	    
	    if ($osname !~ /^win/) {
		if (!$linuximagetab) { $linuximagetab=xCAT::Table->new('linuximage',-create=>1); }
		if ($linuximagetab) {
		    my %key_col = (imagename=>$imagename);
		    my %tb_cols=(pkglist=>$pkglistfile, 
				 pkgdir=>"$installroot/$osver/$arch",
				 otherpkglist=>$otherpkgsfile,
				 otherpkgdir=>"$installroot/post/otherpkgs/$osver/$arch",
				 exlist=>$exlistfile,
				 postinstall=>$postfile,
				 rootimgdir=>"$installroot/netboot/$osver/$arch/$profile");
		    $linuximagetab->setAttribs(\%key_col, \%tb_cols);
		    
		} else {
		    return (1, "Cannot open the linuximage table.");
		}
	    }
	} else {
	    return (1, "Cannot open the osimage table."); 
	}
    }  
    if ($osimagetab) { $osimagetab->close(); }
    if ($linuximagetab) { $linuximagetab->close(); }
    return (0, "");
}



1;
