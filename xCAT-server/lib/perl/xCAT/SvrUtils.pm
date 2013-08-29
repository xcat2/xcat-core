#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::SvrUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
require xCAT::NodeRange;
require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::NetworkUtils;
use File::Basename;
use File::Path;

use strict;
use Exporter;
our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/sendmsg/;

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
        my @xnbanodes= ();
        my @grub2nodes = ();
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
            elsif ($nb eq "xnba")
            {
                push(@xnbanodes, $node);
            }
            elsif ($nb eq "pxe")
            {
                push(@pxenodes, $node);
            }
            elsif ($nb eq "aixinstall")
            {
                push(@aixnodes, $node);
            }
            elsif ($nb eq "grub2")
            {
                push(@grub2nodes, $node);
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
        if (@xnbanodes > 0)
        {
            require xCAT_plugin::xnba;
            @retarray =
              xCAT_plugin::xnba::getNodesetStates(\@xnbanodes, $hashref);
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
        if (@grub2nodes > 0)
        {
            require xCAT_plugin::grub2;
            @retarray =
              xCAT_plugin::grub2::getNodesetStates(\@grub2nodes, $hashref);
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
    my %options=@_;
    my %gnopts;
    if ($options{prefetchcache}) { $gnopts{prefetchcache}=1; }
    my $tab_hash; 
    if ($options{global_tab_hash}) { $tab_hash = $options{global_tab_hash}; }
 
    my $state = "undefined";
    my $tftpdir;
    my $boottype;
    if( defined($tab_hash) && defined($tab_hash->{noderes}) && defined($tab_hash->{noderes}->{$node}) ) {
        $tftpdir = $tab_hash->{noderes}->{$node}->{tftpdir};
        $boottype = $tab_hash->{noderes}->{$node}->{netboot};

    } else {
        #get boot type (pxe, yaboot or aixinstall)  for the node
        my $noderestab = xCAT::Table->new('noderes', -create => 0);
        my $ent = $noderestab->getNodeAttribs($node, [qw(netboot tftpdir)],%gnopts);

        #get tftpdir from the noderes table, if not defined get it from site talbe
        if ($ent && $ent->{tftpdir}) {
	    $tftpdir=$ent->{tftpdir};
        }
        if (!$tftpdir) {
	    if ($::XCATSITEVALS{tftpdir}) { 
	        $tftpdir=$::XCATSITEVALS{tftpdir};
	    }
        }

        if ($ent && $ent->{netboot})
        {
            $boottype = $ent->{netboot};
        }


    }

    if ( defined($boottype) )
    {
        #my $boottype = $ent->{netboot};

        #get nodeset state from corresponding files
        if ($boottype eq "pxe")
        {
            require xCAT_plugin::pxe;
            my $tmp = xCAT_plugin::pxe::getstate($node, $tftpdir);
            my @a = split(' ', $tmp);
            $state = $a[0];
        }
        elsif ($boottype eq "xnba")
        {
            require xCAT_plugin::xnba;
            my $tmp = xCAT_plugin::xnba::getstate($node, $tftpdir);
            my @a = split(' ', $tmp);
            $state = $a[0];
        }
        elsif ($boottype eq "yaboot")
        {
            require xCAT_plugin::yaboot;
            my $tmp = xCAT_plugin::yaboot::getstate($node, $tftpdir);
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
        my $stref = $chaintab->getNodeAttribs($node, ['currstate'],%gnopts);
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

  my ($os, $arch, $profile, $inst_type, $imgname) = @_;

  my $installdir = xCAT::TableUtils->getInstallDir();

  # for aix node, use the node figure out the profile, then use the value of
  # profile (osimage name) to get the synclist file path (osimage.synclists)
  if (xCAT::Utils->isAIX()) {
    my %node_syncfile = ();
    my %osimage_syncfile = ();
    my @profiles = ();

    if ($nodes) {
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
  } # end isAIX

  # if does not specify the $node param, default consider for genimage command
  if ($nodes) {
    my %node_syncfile = ();

    # get the os,arch,profile attributes for the nodes
    my $nodetype_t = xCAT::Table->new('nodetype');
    unless ($nodetype_t) {
      return ;
    }
    my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['profile','os','arch','provmethod']);

	  my $osimage_t = xCAT::Table->new('osimage');
	  unless ($osimage_t) {
	      return ;
	  }
    foreach my $node (@$nodes) {
      my $provmethod=$nodetype_v->{$node}->[0]->{'provmethod'};
      if (($provmethod) && ( $provmethod ne "install") && ($provmethod ne "netboot") && ($provmethod ne "statelite")) {
	  # get the syncfiles base on the osimage
	  my $synclist = $osimage_t->getAttribs({imagename=>$provmethod}, 'synclists');
	  if ($synclist && $synclist->{'synclists'}) {
	      $node_syncfile{$node} = $synclist->{'synclists'};
	  }  
      } else {
	  $inst_type = "install";
	  if ($provmethod eq "netboot" || $provmethod eq "diskless" || $provmethod eq "statelite") {
	      $inst_type = "netboot";
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
	      elsif ($os =~ /SL.*/) { $platform = "SL"; }
	      elsif ($os =~ /ubuntu.*/) { $platform = "ubuntu"; }
	      elsif ($os =~ /debian.*/) { $platform = "debian"; }
	      elsif ($os =~ /AIX.*/) { $platform = "AIX"; }
	  }

	  my $base =  "$installdir/custom/$inst_type/$platform";
	  $node_syncfile{$node} = xCAT::SvrUtils::get_file_name($base, "synclist", $profile, $os, $arch);	 
      }
    }

    return \%node_syncfile;
  } else {
    if ($imgname) {
        my $osimage_t = xCAT::Table->new('osimage');
        unless ($osimage_t) {
            return ;
        }
        my $synclist = $osimage_t->getAttribs({imagename=>$imgname}, 'synclists');
        if ($synclist && $synclist->{'synclists'}) {
            return $synclist->{'synclists'};
        }
    }

    my $platform = "";
    if ($os) {
      if ($os =~ /rh.*/)    { $platform = "rh"; }
      elsif ($os =~ /centos.*/) { $platform = "centos"; }
      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
      elsif ($os =~ /sles.*/) { $platform = "sles"; }
      elsif ($os =~ /SL.*/) { $platform = "SL"; }
      elsif ($os =~ /ubuntu.*/) { $platform = "ubuntu"; }
      elsif ($os =~ /debian.*/) { $platform = "debian"; }
      elsif ($os =~ /AIX.*/) { $platform = "AIX"; }
      elsif ($os =~ /win/)  {$platform = "windows"; }
    }

    my $base = "$installdir/custom/$inst_type/$platform";
    return xCAT::SvrUtils::get_file_name($base, "synclist", $profile, $os, $arch);
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

# for the "imgcapture" command

sub get_imgcapture_exlist_file_name {
    my $searchpath = shift;
    if ($searchpath and $searchpath =~ m/xCAT::SvrUtils/) {
        $searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "imgcapture.exlist", @_);
}


#-------------------------------------------------------------------------------

=head3   update_tables_with_templates
       This function is called after copycds. Itwill get all the possible install templates
       from the default directories for the given osver and arch and update the osimage table.
    Arguments:
        osver
        arch
	ospkgdir
	osdistroname
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
    my $shortosver = $osver;
    $shortosver =~ s/\..*//;
    my $arch = shift;  #like ppc64, x86, x86_64
    my $ospkgdir=shift;      
    my $osdistroname=shift;
    my %args = @_;

    my $osname=$osver;;  #like sles, rh, centos, windows
    my $ostype="Linux";  #like Linux, Windows
    my $imagetype="linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
	$osname="windows";
	$ostype="Windows";
        $imagetype="windows";
    } elsif ($osver =~ /^hyperv/) {
	$osname="hyperv";
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
    my $installroot = xCAT::TableUtils->getInstallDir();
    #my $sitetab = xCAT::Table->new('site');
    #if ($sitetab) {
    #	(my $ref) = $sitetab->getAttribs({key => "installdir"}, "value");
    #	if ($ref and $ref->{value}) {
    #       $installroot = $ref->{value};
    #	}
    #}
    my @installdirs = xCAT::TableUtils->get_site_attribute("installdir");
    my $tmp = $installdirs[0];
    if ( defined($tmp)) {
       $installroot = $tmp; 
    }
    my $cuspath="$installroot/custom/install/$osname";
    my $defpath="$::XCATROOT/share/xcat/install/$osname"; 
    
    #now get all the profile names for full installation
    my %profiles=();
    my @tmplfiles=glob($cuspath."/*.tmpl");
    foreach (@tmplfiles) {
	my $tmpf=basename($_); 
	#get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
	if ($tmpf =~ /[^\.]*\.([^\.]*)\.([^\.]*)\./) { # osver *and* arch specific, make sure they match
		unless (($1 eq $osver or $1 eq $shortosver) and $2 eq $arch) { next; }
	} elsif ($tmpf =~  /[^\.]*\.([^\.]*)\./) { #osver *or* arch specific, make sure one matches
		unless ($1 eq $osver or $1 eq $shortosver or $2 eq $arch) { next; }
	}
	$tmpf =~ /^([^\.]*)\..*$/;
	$tmpf = $1;
	#print "$tmpf\n";
	$profiles{$tmpf}=1;
    }
    @tmplfiles=glob($defpath."/*.tmpl");
    foreach (@tmplfiles) {
	my $tmpf=basename($_); 
	#get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
	if ($tmpf =~ /[^\.]*\.([^\.]*)\.([^\.]*)\./) { # osver *and* arch specific, make sure they match
		unless (($1 eq $osver or $1 eq $shortosver) and $2 eq $arch) { next; }
	} elsif ($tmpf =~  /[^\.]*\.([^\.]*)\./) { #osver *or* arch specific, make sure one matches
		unless ($1 eq $osver or $1 eq $shortosver or $1 eq $arch) { next; }
	}
	$tmpf =~ /^([^\.]*)\..*$/;
	$tmpf = $1;
	$profiles{$tmpf}=1;
    }
    
    #update the osimage and linuximage table
    my $osimagetab;
    my $linuximagetab;
    my $winimagetab;
    if ($args{checkonly}) {
    	if (keys %profiles) {
		return (0,"");
	} else {
		return (1,"Missing template files");
	}
    }
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
	
	#get the pkglist file
	my $pkglistfile=get_pkglist_file_name($cuspath, $profile, $osver, $arch);
	if (!$pkglistfile) { $pkglistfile=get_pkglist_file_name($defpath, $profile, $osver, $arch,$genos);}

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
#		if ($found) { next; } 

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
			     synclists=>$synclistfile,
			     osdistroname=>$osdistroname);
		$osimagetab->setAttribs(\%key_col, \%tb_cols);
                
		if ($osname =~ /^win/) {
		    if (!$winimagetab) { $winimagetab=xCAT::Table->new('winimage',-create=>1); }
		    if ($winimagetab) {
		        my %key_col = (imagename=>$imagename);
			    my %tb_cols=(template=>$tmplfile);
			    $winimagetab->setAttribs(\%key_col, \%tb_cols);
		    } else {
			    return (1, "Cannot open the winimage table.");
		    }
		} else {
		    if (!$linuximagetab) { $linuximagetab=xCAT::Table->new('linuximage',-create=>1); }
		    if ($linuximagetab) {
			my %key_col = (imagename=>$imagename);
			my %tb_cols=(template=>$tmplfile, 
				     pkgdir=>$ospkgdir,
				     pkglist=>$pkglistfile,
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

=head3   update_tables_with_mgt_image
       This function is called after copycds to generate a default osimage for management node
         It will get all the possible templates from the default directories for the
         management node's osver and osarch, and update the osimage table
    Arguments:

    Returns:
        an array (retcode, errmsg). The first one is the return code. If 0, it means succesful.

=cut

#-------------------------------------------------------------------------------
sub  update_tables_with_mgt_image
{
    my $osver = shift;  #like sle11, rhel5.3
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
        $osver = shift;
    }
    my $arch = shift;  #like ppc64, x86, x86_64
    my $ospkgdir=shift;
    my $osdistroname=shift;

    my $osname=$osver;;  #like sles, rh, centos, windows
    my $ostype="Linux";  #like Linux, Windows
    my $imagetype="linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
        $osname="windows";
        $ostype="Windows";
        $imagetype="windows";
    } elsif ($osver =~ /^hyperv/) {
        $osname="hyperv";
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
   
    #if the arch of osimage does not match the arch of MN,return
    my $myarch=qx(uname -i);
    chop $myarch;
    if($arch ne $myarch){
       return 0;
    }


    #for rhels5.1  genos=rhel5
    my $genos = $osver;
    $genos =~ s/\..*//;
    if ($genos =~ /rh.*s(\d*)/) {
        $genos = "rhel$1";
    }

    #if the osver does not match the osver of MN, return
    my $myosver = xCAT::Utils->osver("all");
    $myosver =~ s/,//;
    if ( $osver ne $myosver ) {
        return 0;
    }

    my $installroot = xCAT::TableUtils->getInstallDir();
    my @installdirs = xCAT::TableUtils->get_site_attribute("installdir");
    my $tmp = $installdirs[0];
    if ( defined($tmp)) {
       $installroot = $tmp;
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
        if ( $tmpf eq "compute" ) {
            $profiles{$tmpf}=1;
        }
    }
    #update the osimage and linuximage table
    my $osimagetab;
    my $linuximagetab;
    my $imagename=$osver . "-" . $arch . "-stateful" . "-mgmtnode";
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

        #get the pkglist file
        my $pkglistfile=get_pkglist_file_name($cuspath, $profile, $osver, $arch);
        if (!$pkglistfile) { $pkglistfile=get_pkglist_file_name($defpath, $profile, $osver, $arch);}

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
#               if ($found) { next; }


                #TODO: check if there happen to be a row that has the same imagename but with different contents
                #now we can wirte the info into db
                my %key_col = (imagename=>$imagename);
                my %tb_cols=(imagetype=>$imagetype,
                             provmethod=>"install",
                             profile=>$profile,
                             osname=>$ostype,
                             osvers=>$osver,
                             osarch=>$arch,
                             synclists=>$synclistfile,
                             osdistroname=>$osdistroname);
                $osimagetab->setAttribs(\%key_col, \%tb_cols);

                if ($osname !~ /^win/) {
                    if (!$linuximagetab) { $linuximagetab=xCAT::Table->new('linuximage',-create=>1); }
                    if ($linuximagetab) {
                        my %key_col = (imagename=>$imagename);
                        my %tb_cols=(template=>$tmplfile,
                                     pkgdir=>$ospkgdir,
                                     pkglist=>$pkglistfile,
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
 
    #set nodetype.provmethod to the new created osimage if it is not set
    my @mgtnodes=xCAT::NodeRange::noderange('__mgmtnode');
    if(scalar @mgtnodes){
        my $nttab=xCAT::Table->new('nodetype', -create=>1);
        unless($nttab){
           return(1, "Cannot open the nodetype table.");
        }

        my $ntents=$nttab->getNodesAttribs(\@mgtnodes, ['provmethod']);
        my %ent;
        foreach my $node (@mgtnodes){
           print "$node\n";
           unless($ntents->{$node} and $ntents->{$node}->['provmethod']){
                 $ent{$node}{'provmethod'}=$imagename;
           }
        }
        
        $nttab->setNodesAttribs(\%ent);  

               
        if($nttab){ $nttab->close(); }
    }


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
        mode
        ospkgdir
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
    my $mode=shift;
    my $ospkgdir=shift;
    my $osdistroname=shift; 

    my $provm="netboot";
    if ($mode) { $provm = $mode; } 
    
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
    my $installroot = xCAT::TableUtils->getInstallDir();
    #my $sitetab = xCAT::Table->new('site');
    #if ($sitetab) {
    #	(my $ref) = $sitetab->getAttribs({key => "installdir"}, "value");
    #	if ($ref and $ref->{value}) {
    #	    $installroot = $ref->{value};
    #	}
    #}
    my @installdirs = xCAT::TableUtils->get_site_attribute("installdir");
    my $tmp = $installdirs[0];
    if ( defined($tmp)) {
       $installroot = $tmp; 
    }
    my $cuspath="$installroot/custom/netboot/$osname";
    my $defpath="$::XCATROOT/share/xcat/netboot/$osname"; 
    my $osimagetab;
    my $linuximagetab;

    my %profiles=();
    if ($profile) {
        $profiles{$profile} = 1;
    } else {
        my @tmplfiles=glob($cuspath."/*.pkglist");
        foreach (@tmplfiles) {
            my $tmpf=basename($_); 
            #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
            $tmpf =~ /^([^\.]*)\..*$/;
            $tmpf = $1;
            $profiles{$tmpf}=1;
        }
        @tmplfiles=glob($defpath."/*.pkglist");
        foreach (@tmplfiles) {
            my $tmpf=basename($_); 
            #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
            $tmpf =~ /^([^\.]*)\..*$/;
            $tmpf = $1;
            $profiles{$tmpf}=1;
        }
    }
    foreach my $profile (keys %profiles) {
        #get the pkglist file
        my $pkglistfile=get_pkglist_file_name($cuspath, $profile, $osver, $arch);
        if (!$pkglistfile) { $pkglistfile=get_pkglist_file_name($defpath, $profile, $osver, $arch);}
        #print "pkglistfile=$pkglistfile\n";
        if (!$pkglistfile) { next;}
        
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
    		    if (($osver eq $rowdata->{osvers}) && ($arch eq $rowdata->{osarch}) && ($rowdata->{provmethod} eq $provm) && ($profile eq $rowdata->{profile})){
    			$found=1;
    			last;
    		    }
    		}
    	    }
           if ($found) { 
                           print "The image is already in the db.\n"; 
 #                         next; 
                         } 
    	    
    	    my $imagename=$osver . "-" . $arch . "-$provm-" . $profile;
    	    #TODO: check if there happen to be a row that has the same imagename but with different contents
    	    #now we can wirte the info into db
    	    my %key_col = (imagename=>$imagename);
    	    my %tb_cols=(imagetype=>$imagetype, 
    			 provmethod=>$provm,
    			 profile=>$profile, 
    			 osname=>$ostype,
    			 osvers=>$osver,
    			 osarch=>$arch,
    			 synclists=>$synclistfile,
			 osdistroname=>$osdistroname);
    	    $osimagetab->setAttribs(\%key_col, \%tb_cols);
    	    
    	    if ($osname !~ /^win/) {
    		if (!$linuximagetab) { $linuximagetab=xCAT::Table->new('linuximage',-create=>1); }
    		if ($linuximagetab) {
    		    my %key_col = (imagename=>$imagename);
    		    my %tb_cols=(pkglist=>$pkglistfile, 
				 pkgdir=>$ospkgdir,    				 
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
    }
    if ($osimagetab) { $osimagetab->close(); }
    if ($linuximagetab) { $linuximagetab->close(); }
    return (0, "");
}


#-------------------------------------------------------------------------------

=head3  get_mac_by_arp
    Description:
        Get the MAC address by arp protocol

    Arguments:
        nodes: a reference to nodes array
        display: whether just display the result, if not 'yes', the result will
                 be written to the mac table.
    Returns:
        Return a hash with node name as key
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->get_mac_by_arp($nodes, $display);
    Comments:

=cut

#-------------------------------------------------------------------------------
sub get_mac_by_arp ()
{
    my ($class, $nodes, $display) = @_;

    my $node;
    my $data;
    my %ret = ();
    my $unreachable_nodes = "";
    my $noderange = join (',', @$nodes);
    my @output = xCAT::Utils->runcmd("/opt/xcat/bin/pping $noderange", -1);

    foreach my $line (@output) {
        my ($hostname, $result) = split ':', $line;
        my ($token,    $status) = split ' ', $result;
        chomp($token);
        if ($token eq 'ping') {
            $node->{$hostname}->{reachable} = 1;
        }
    }

    foreach my $n ( @$nodes ) {
        if ( $node->{$n}->{reachable} ) {
            my $output;
            my $IP = xCAT::NetworkUtils::toIP( $n );
            if ( xCAT::Utils->isAIX() ) {
                $output = `/usr/sbin/arp -a`;
            } else {
                if ( -x "/usr/sbin/arp" ) {
                    $output = `/usr/sbin/arp -n`;
                }
                else {
                    $output = `/sbin/arp -n`;
                }
            }

            my ($ip, $mac);
            my @lines = split /\n/, $output;
            foreach my $line ( @lines ) {
                if ( xCAT::Utils->isAIX() && $line =~ /\((\S+)\)\s+at\s+(\S+)/ ) {
                    ($ip, $mac) = ($1,$2);
                    ######################################################
                    # Change mac format to be same as linux, but without ':'
                    # For example: '0:d:60:f4:f8:22' to '000d60f4f822'
                    ######################################################
                    if ( $mac)
                    {
                        my @mac_sections = split /:/, $mac;
                        for my $m (@mac_sections)
                        {
                            $m = "0$m" if ( length($m) == 1);
                        }
                        $mac = join '', @mac_sections;
                    }
                } elsif ( $line =~ /^(\S+)+\s+\S+\s+(\S+)\s/ ) {
                    ($ip, $mac) = ($1,$2);
                } else {
                    ($ip, $mac) = (undef,undef);
                }
                if ( @$IP[1] !~ $ip ) {
                    ($ip, $mac) = (undef,undef);
                } else {
                    last;
                }
            }
            if ( $ip && $mac ) {
                if ( $display ne "yes" ) {
                    #####################################
                    # Write adapter mac to database
                    #####################################
                    my $mactab = xCAT::Table->new( "mac", -create=>1, -autocommit=>1 );
                    $mactab->setNodeAttribs( $n,{mac=>$mac} );
                    $mactab->close();
                }
                $ret{$n} = "MAC Address: $mac";
            } else {
                $ret{$n} = "Cannot find MAC Address in arp table, please make sure target node and management node are in same network.";
            }
        } else {
                $ret{$n} = "Unreachable.";
        }
    }

    return \%ret;
}

#-------------------------------------------------------------------------------

=head3  get_nodename_from_request
    Description:
        Determine whether _xcat_clienthost or _xcat_fqdn is the correct
        nodename and return it.

    Arguments:
        request: node request to look at
    Returns:
        The name of the node.
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->get_nodenane_from_request($request);
    Comments:

=cut

#-------------------------------------------------------------------------------
sub get_nodename_from_request()
{
    my $request = shift;
    if($request->{node}){
        return $request->{node};
    }elsif($request->{'_xcat_clienthost'}){
         my @nodenames = noderange($request->{'_xcat_clienthost'}->[0].",".$request->{'_xcat_clientfqdn'}->[0]);
         return \@nodenames;
    }

    return undef;
}

# some directories will have xCAT database values, like:
# $nodetype.os.  If that is the case we need to open up
# the database and look at them.  We need to make sure
# we do this sparingly...  We don't like tons of hits
# to the database.
sub subVars {
  my $dir = shift;
  if (($dir) && ($dir =~ /xCAT::SvrUtils/))
  {
    $dir = shift;
  }

        my $node = shift;
        my $type = shift;
        my $callback = shift;
        # parse all the dollar signs...
        # if its a directory then it has a / in it, so you have to parse it.
        # if its a server, it won't have one so don't worry about it.
        my @arr = split("/", $dir);
        my $fdir = "";
        foreach my $p (@arr){
                # have to make this geric so $ can be in the midle of the name: asdf$foobar.sitadsf
                if($p =~ /\$/){
                        my $pre;
                        my $suf;
                        my @fParts;
                        if($p =~ /([^\$]*)([^# ]*)(.*)/){
                                $pre= $1;
                                $p = $2;
                                $suf = $3;
                        }
                        # have to sub here:
                        # get rid of the $ sign.
                        foreach my $part (split('\$',$p)){
                                if($part eq ''){ next; }
                                #$callback->({error=>["part is $part"],errorcode=>[1]});
                                # check if p is just the node name:
                                if($part eq 'node'){
                                        # it is so, just return the node.
                                        #$fdir .= "/$pre$node$suf";
                                        push @fParts, $node;
                                }else{
                                        # ask the xCAT DB what the attribute is.
                                        my ($table, $col) = split('\.', $part);
                                        unless($col){ $col = 'UNDEFINED' };
                                        my $tab = xCAT::Table->new($table);
                                        unless($tab){
                                                $callback->({error=>["$table does not exist"],errorcode=>[1]});
                                                return;
                                        }
                                        my $ent;
                                        my $val;
                                        if($table eq 'site'){
                                                #$val = $tab->getAttribs( { key => "$col" }, 'value' );
                                                #$val = $val->{'value'};
                                                my @vals = xCAT::TableUtils->get_site_attribute($col);
                                                $val = $vals[0];
                                        }else{
                                                $ent = $tab->getNodeAttribs($node,[$col]);
                                                $val = $ent->{$col};
                                        }
                                        unless($val){
                                                # couldn't find the value!!
                                                $val = "UNDEFINED"
                                        }
                                        push @fParts, $val;
                                }
                        }
                        my $val = join('.', @fParts);
                        if($type eq 'dir'){
                                        $fdir .= "/$pre$val$suf";
                        }else{
                                        $fdir .= $pre . $val . $suf;
                        }
                }else{
                        # no substitution here
                        $fdir .= "/$p";
                }
        }
        # now that we've processed variables, process commands
        # this isn't quite rock solid.  You can't name directories with #'s in them.
        if($fdir =~ /#CMD=/){
                my $dir;
                foreach my $p (split(/#/,$fdir)){
                        if($p =~ /CMD=/){
                                $p =~ s/CMD=//;
                                my $cmd = $p;
                                #$callback->({info=>[$p]});
                                $p = `$p 2>&1`;
                                chomp($p);
                                #$callback->({info=>[$p]});
                                unless($p){
                                        $p = "#CMD=$p did not return output#";
                                }
                        }
                        $dir .= $p;
                }
                $fdir = $dir;
        }

        return $fdir;
}

sub setupNFSTree {
  my $node = shift;
  if (($node) && ($node =~ /xCAT::SvrUtils/))
  {
    $node = shift;
  }

    my $sip = shift;
    my $callback = shift;

    my $cmd = "XCATBYPASS=Y litetree $node";
    my @uris = xCAT::Utils->runcmd($cmd, 0);

    foreach my $uri (@uris) {
        # parse the result
        # the result looks like "nodename: nfsserver:directory";
        $uri =~ m/\Q$node\E:\s+(.+):(.+)$/;
        my $nfsserver = $1;
        my $nfsdirectory = $2;

        if($nfsserver eq $sip) { # on the service node

            unless (-d $nfsdirectory) {
                if (-e $nfsdirectory) {
                    unlink $nfsdirectory;
                }
                mkpath $nfsdirectory;
            }
        
            $cmd = "showmount -e $nfsserver";
            my @entries = xCAT::Utils->runcmd($cmd, 0);
            shift @entries;
            if(grep /\Q$nfsdirectory\E/, @entries) {
                $callback->({data=>["$nfsdirectory has been exported already!"]});
                # nothing to do
            }else {
                $cmd = "/usr/sbin/exportfs :$nfsdirectory";
                xCAT::Utils->runcmd($cmd, 0);
                # exportfs can export this directory immediately
                $callback->({data=>["now $nfsdirectory is exported!"]});
                $cmd = "cat /etc/exports";
                @entries = xCAT::Utils->runcmd($cmd, 0);
                unless (my $entry = grep /\Q$nfsdirectory\E/, @entries) {
                    #if there's no entry in /etc/exports, one with default options will be added
                    $cmd = qq{echo "$nfsdirectory *(rw,no_root_squash,sync,no_subtree_check)" >> /etc/exports};
                    xCAT::Utils->runcmd($cmd, 0);
                    $callback->({data=>["$nfsdirectory is added to /etc/exports with default option"]});
                }
            }
        }
    }
}

sub setupStatemnt {
    my $sip = shift;
    if (($sip) && ($sip=~ /xCAT::SvrUtils/))
    {
      $sip = shift;
    }

    my $statemnt = shift;
    my $callback = shift;

    $statemnt =~ m/^(.+):(.+)$/;
    my $nfsserver = $1;
    my $nfsdirectory = $2;
    if($sip eq xCAT::NetworkUtils->getipaddr($nfsserver)) {
        unless (-d $nfsdirectory) {
            if (-e $nfsdirectory) {
                unlink $nfsdirectory;
            } 
            mkpath $nfsdirectory;
        }

        my $cmd = "showmount -e $nfsserver";
        my @entries = xCAT::Utils->runcmd($cmd, 0);
        shift @entries;
        if(grep /\Q$nfsdirectory\E/, @entries) {
            $callback->({data=>["$nfsdirectory has been exported already!"]});
        } else {
            $cmd = "/usr/sbin/exportfs :$nfsdirectory -o rw,no_root_squash,sync,no_subtree_check";
            xCAT::Utils->runcmd($cmd, 0);
            $callback->({data=>["now $nfsdirectory is exported!"]});
            # add the directory into /etc/exports if not exist
            $cmd = "cat /etc/exports";
            @entries = xCAT::Utils->runcmd($cmd, 0);
            if(my $entry = grep /\Q$nfsdirectory\E/, @entries) {
                unless ($entry =~ m/rw/) {
                    $callback->({data=>["The $nfsdirectory should be with rw option in /etc/exports"]});
                }
            }else {
                xCAT::Utils->runcmd(qq{echo "$nfsdirectory *(rw,no_root_squash,sync,no_subtree_check)" >>/etc/exports}, 0);
                $callback->({data => ["$nfsdirectory is added into /etc/exports with default options"]});
            }
        }
    }
    
}

#-------------------------------------------------------------------------------------------
# Common method to send info back to the client
# The last two args are optional, though $allerrornodes will unlikely be there without $node
# TODO: investigate possibly removing this and using MsgUtils instead
#
#--------------------------------------------------------------------------------------------
sub sendmsg {
    my $text = shift;
    my $callback = shift;
    my $node = shift;
    my %allerrornodes = shift;
    my $descr;
    my $rc;
    if (ref $text eq 'HASH') {
        die "not right now";
    } elsif (ref $text eq 'ARRAY') {
        $rc = $text->[0];
        $text = $text->[1];
    }
    if ($text =~ /:/) {
        ($descr,$text) = split /:/,$text,2;
    }
    $text =~ s/^ *//;
    $text =~ s/ *$//;
    my $msg;
    my $curptr;
    if ($node) {
        $msg->{node}=[{name => [$node]}];
        $curptr=$msg->{node}->[0];
    } else {
        $msg = {};
        $curptr = $msg;
    }
    if ($rc) {
        $curptr->{errorcode}=[$rc];
        $curptr->{error}=[$text];
        $curptr=$curptr->{error}->[0];
        if (defined $node && %allerrornodes) {
            $allerrornodes{$node}=1;
        }
    } else {
        $curptr->{data}=[{contents=>[$text]}];
        $curptr=$curptr->{data}->[0];
        if ($descr) { $curptr->{desc}=[$descr]; }
    }
#        print $outfd freeze([$msg]);
#        print $outfd "\nENDOFFREEZE6sK4ci\n";
#        yield;
#        waitforack($outfd);
    $callback->($msg);
}

#-------------------------------------------------------------------------------
=head3  build_deps
    Look up the "deps" table to generate the dependencies for the nodes
    Arguments:
        nodes: The nodes list in an array reference
    Returns:
        depset: dependencies hash reference 
    Globals:
        none
    Error:
        none
    Example:
        my $deps = xCAT::SvrUtils->build_deps($req->{node});
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub build_deps()
{
    my ($class, $nodes, $cmd) = @_;
    my %depshash = ();

    my $depstab  = xCAT::Table->new('deps');
    if (!defined($depstab)) {
        return undef;
    }

    my $depset = $depstab->getNodesAttribs($nodes,[qw(nodedep msdelay cmd)]);
    if (!defined($depset))
    {
        return undef;
    }
    foreach my $node (@$nodes) {
        # Delete the nodes without dependencies from the hash
        if (!defined($depset->{$node}[0])) {
            delete($depset->{$node});
        } 
    }

    # the deps hash does not check the 'cmd',
    # use the realdeps to reflect the 'cmd' also
    my $realdep;
    foreach my $node (@$nodes) {
            foreach my $depent (@{$depset->{$node}}){
                my @depcmd = split(/,/, $depent->{'cmd'});
                #dependency match
                if (grep(/^$cmd$/, @depcmd)) {
                    #expand the noderange
                    my @nodedep = xCAT::NodeRange::noderange($depent->{'nodedep'},1);
                    my $depsnode = join(',', @nodedep);
                    if ($depsnode) {
                        $depent->{'nodedep'} = $depsnode;
                        push @{$realdep->{$node}}, $depent;
                    }
                }
            }
        }
    return $realdep;
}


#-------------------------------------------------------------------------------

=head3  handle_deps
    Group the nodes according to the deps hash returned from build_deps
    Arguments:
        deps: the dependencies hash reference
        nodes: The nodes list in an array reference
        $callback: sub request callback
    Returns:
        nodeseq: the nodes categorized based on dependencies
                 returns 1 if runs into problem
    Globals:
        none
    Error:
        none
    Example:
        my $deps = xCAT::SvrUtils->handle_deps($deps, $req->{node});
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub handle_deps()
{
    my ($class, $dephash, $nodes, $callback) = @_;

    # a small subroutine to remove some specific node from a comma separated list
    sub remove_node_from_list()
    {
        my ($string, $nodetoremove) = @_;
        my @arr = split(',', $string);
        my @newarr = ();
        foreach my $tmp (@arr) {
            if ($tmp ne $nodetoremove) {
                push @newarr, $tmp;
            }
        }
        return join(',', @newarr);
    }

    # This is an example of the deps hash ref
    #  DB<3> x $deps
    #0  HASH(0x239db47c)
    #   'aixcn1' => ARRAY(0x23a26be0)
    #      0  HASH(0x23a21968) 
    #         'cmd' => 'off' 
    #         'msdelay' => 10000 
    #         'node' => 'aixcn1' 
    #         'nodedep' => 'aixmn2' 
    #   'aixsn1' => ARRAY(0x23a2219c)
    #      0  HASH(0x23a21728) 
    #         'cmd' => 'off' 
    #         'msdelay' => 10000 
    #         'node' => 'aixsn1' 
    #         'nodedep' => 'aixcn1' 

    #copy the dephash, do not manipulate the subroutine argument $dephash
    my $deps;
    foreach my $node (keys %{$dephash}) {
        my $i = 0;
        for ($i = 0; $i < scalar(@{$dephash->{$node}}); $i++) {
            foreach my $attr (keys %{$dephash->{$node}->[$i]}) {
                $deps->{$node}->[$i]->{$attr} = $dephash->{$node}->[$i]->{$attr};
            }
        }
    }

    #needs to search the nodes list a lot of times
    #using hash will be more effective
    my %nodelist;
    foreach my $node (@{$nodes}) {
        $nodelist{$node} = 1;
    }


    # check if any depnode is not in the nodelist,
    # print warning message
    my $depsnotinargs;
    foreach my $node (keys %{$deps}){
        my $keepnode = 0;
        foreach my $depent (@{$deps->{$node}}){
            # an autonomy dependency group?
            foreach my $dep (split(/,/, $depent->{'nodedep'})) {
                if (!defined($nodelist{$dep})) {
                   $depsnotinargs->{$dep} = 1; 
                   $depent->{'nodedep'} = &remove_node_from_list($depent->{'nodedep'}, $dep);
                }       
            }       
            if ($depent->{'nodedep'}) {
                $keepnode = 1;
            }
        }
        if (!$keepnode) {
            delete($deps->{$node});
        }
    }
    if (scalar(keys %{$depsnotinargs}) > 0) {
        my $n = join(',', keys %{$depsnotinargs});
  
        my %output;
        $output{data} = ["The following nodes are dependencies for some nodes passed in through arguments, but not in the command arguments: $n, make sure these nodes are in correct state"]; 
        $callback->( \%output );
    }                                                            
                                                                             


    my $arrayindex = 0;                                                      
    my $nodeseq;                                                             
    #handle all the nodes
    while (keys %nodelist) {                                                 

       my @curnodes;
       foreach my $node (keys %nodelist) {                                  
            #no dependency                                                  
           if (!defined($deps->{$node})) {                                  
               $nodeseq->[$arrayindex]->{$node} = 1;                        
               delete($nodelist{$node});                                    
               push @curnodes, $node;
           }                                                                
       }                                                                    
                                                                             
       if (scalar(@curnodes) == 0) {
           # no nodes in this loop at all,
           # means infinite loop???
           my %output;
           my $nodesinlist = join(',', keys %nodelist);
           $output{errorcode}=1;
           $output{data} = ["Loop dependency, check your deps table, may be related to the following nodes: $nodesinlist"];
           $callback->( \%output );
           return 1;
       }

       # update deps for the next loop                              
       # remove the node from the 'nodedep' attribute               
       my $keepnode = 0;                                            
       foreach my $nodeindeps (keys %{$deps}) {
           my $keepnode = 0;
           foreach my $depent (@{$deps->{$nodeindeps}}){                      
                 #remove the curnodes from the 'nodedep'
                 foreach my $nodetoremove (@curnodes) {
                     $depent->{'nodedep'} = &remove_node_from_list($depent->{'nodedep'}, $nodetoremove);
                 }
                 if ($depent->{'nodedep'}) {
                     $keepnode = 1;
                 }
            }
            if (!$keepnode) {
                delete($deps->{$nodeindeps});
            }
        }

        # the round is over, jump to the next arrary entry
        $arrayindex++;  
    }                                                                  
    return $nodeseq; 
}


#-------------------------------------------------------------------------------

=head3   parseosver 
    parse osver to osdistribution base name,majorversion,minorversion
    Returns:
       list (osdistribution base name, majorversion,minorversion)
    Globals:
        none
    Error:
        none
    Input:
        osver
    Example:
    ($basename,$majorversion,$minorversion)=xCAT::Utils->parseosver($osver);
    Comments:
=cut

#-------------------------------------------------------------------------------
sub parseosver
{
  my $osver=shift;

  if($osver =~ (/(\D+)(\d*)\.*(\d*)/))
  {
        return ($1,$2,$3);
  }

  return ();
}

#-------------------------------------------------------------------------------

=head3 update_osdistro_table
       This function is called after copycds. It will update the osdistro table with
       given osver and arch 
    Arguments:
        osver
        arch
        ospkgdir
    Returns:
        an array (retcode, errmsg). The first one is the return code. If 0, it means succesful. 

=cut

#-------------------------------------------------------------------------------

sub update_osdistro_table
{ 
    my $osver = shift;  #like sle11, rhel5.3 
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
        $osver = shift;
    }
    my $arch = shift;  #like ppc64, x86, x86_64
    my $path=shift;
    my $distname=shift;
 
    my $basename=undef;
    my $majorversion=undef;
    my $minorversion=undef;
	
    my %keyhash=();
    my %updates=();

    my $ostype="Linux";  #like Linux, Windows
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
	if ($osver =~ /^win\d/) {
		$osver =~ s/^win/windows/;
	} elsif ($osver =~ /^imagex/) {
        	$osver="windows";
	}
        $ostype="Windows";
    }
    if ($osver =~ /hyperv/) {
	$ostype = "Windows";
    }


   unless($distname){
	$distname=$osver."-".$arch;
   }
     
    $keyhash{osdistroname}    = $distname;

    $updates{type}=$ostype;
    if($arch){
             $updates{arch}    = $arch;
    }
#split $osver to basename,majorversion,minorversion 
    if($osver){
              ($updates{basename},$updates{majorversion},$updates{minorversion}) = &parseosver($osver);
    }


    my $tab = xCAT::Table->new('osdistro',-create=>1);

    unless($tab)
    {
          return(1,"failed to open table 'osdistro'!");
    }

    if($path)
        {
              $path =~ s/\/+$//;
              (my $ref) = $tab->getAttribs(\%keyhash, 'dirpaths');
              if ($ref and $ref->{dirpaths} )
               {
#if $path does not exits in "dirpaths" of osdistro,append the $path delimited with a ",";otherwise keep the original value
                    unless($ref->{dirpaths} =~ /^($path)\/*,|,($path)\/*,|,($path)\/*$|^($path)\/*$/)
                    {
                           $updates{dirpaths}=$ref->{dirpaths}.','.$path;
                    }
                }else
                {
                        $updates{dirpaths}   = $path;
                }
        }


        if(%updates)
        {
                $tab->setAttribs( \%keyhash,\%updates );
                $tab->commit;
        }
        $tab->close;

        return(0,"osdistro $distname update success");


}

#-----------------------------------------------------------------------------


=head3 getpostbootscripts
    Get the  the postbootscript list for the Linux nodes as defined in
    the osimage table postbootscripts attribute 

    Arguments:
      $nodes - array of nodes
    Returns:
      reference of a hash of node=>postbootscripts comma separated list
    Globals:
        none
    Error:
    Example:
         my $node_postbootscripts=xCAT::SvrUtils->getpostbootscripts($nodes);
    Comments:
        none

=cut

#-----------------------------------------------------------------------------


sub getpostbootscripts()
{
  my $nodes = shift;
  if (($nodes) && ($nodes =~ /xCAT::SvrUtils/))
  {
    $nodes = shift;
  }
  my %node_postbootscript = ();
  my %osimage_postbootscript = ();



	# get the profile attributes for the nodes
	my $nodetype_t = xCAT::Table->new('nodetype');
	unless ($nodetype_t) {
	    return ;
   }
	my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['provmethod']);
   my @osimages;	
   my $osimage_t = xCAT::Table->new('osimage');
   unless ($osimage_t) {
      return ;
   }
	foreach my $node (@$nodes) {
	    my $provmethod=$nodetype_v->{$node}->[0]->{'provmethod'};
	    if (($provmethod) && ( $provmethod ne "install") && ($provmethod ne "netboot") && ($provmethod ne "statelite")) {
       # then get the postbootscripts from the osimage
          my $postbootscripts = $osimage_t->getAttribs({imagename=>$provmethod}, 'postbootscripts');
          if ($postbootscripts && $postbootscripts->{'postbootscripts'}) {
           $node_postbootscript{$node} = $postbootscripts->{'postbootscripts'};
          }
        }

	    
   }
   return \%node_postbootscript;
  }

#-------------------------------------------------------------------------------

=head3   getplatform
       Translate the os to platform name.
       Use this subroutine to replace the getplatform subroutines in different plugins.
    Arguments:
        os: like rhels6.3 or sles11.2
    Returns:
        platform: like rh and sles
    Example:
         my $platform = xCAT::SvrUtils->getplatform($os);

=cut

#-------------------------------------------------------------------------------

sub getplatform {
    my $os = shift;  #like sles11.1, rhels6.3
    if (($os) && ($os =~ /xCAT::SvrUtils/)) {
        $os = shift;
    }

    my $platform;
    if ($os =~ /rh.*/) 
    {
	$platform = "rh";
    }
    elsif ($os =~ /sles.*/) 
    {
	$platform = "sles";
    }
    elsif ($os =~ /suse.*/) 
    {
	$platform = "suse";
    }
    elsif ($os =~ /centos.*/)
    {
	$platform = "centos";
    }
    elsif ($os =~ /fedora.*/)
    {
	$platform = "fedora";
    }
    elsif ($os =~ /esxi.*/)
    {
	$platform = "esxi";
    }
    elsif ($os =~ /esx.*/)
    {
	$platform = "esx";
    }
    elsif ($os =~ /SL.*/)
    {
        $platform = "SL";
    }
    elsif ($os =~ /ol.*/)
    {
        $platform = "ol";
    }
    elsif ($os =~ /debian.*/) {
        $platform = "debian";
    }
    elsif ($os =~ /ubuntu.*/){
        $platform = "ubuntu";
    }
    elsif ($os =~ /AIX.*/)
    {
        $platform = "AIX";
    }
    elsif ($os =~ /win.*/)
    {
        $platform = "windows";
    }

    return $platform;
}
1;
