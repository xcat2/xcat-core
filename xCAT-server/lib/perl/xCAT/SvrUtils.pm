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
use Digest::SHA ();
use Errno qw(EEXIST);
use File::Basename;
use File::Copy ();
use File::Path;
use File::Temp;
use Scalar::Util ();
use Sys::Hostname ();
use strict;
use Exporter;
our @ISA       = qw/Exporter/;
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

        my @aixnodes       = ();
        my @pxenodes       = ();
        my @yabootnodes    = ();
        my @xnbanodes      = ();
        my @ipxenodes      = ();
        my @grub2nodes     = ();
        my @petitbootnodes = ();
        my $tabdata = $tab->getNodesAttribs(\@nodes, [ 'node', 'netboot' ]);
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
            elsif ($nb eq "ipxe")
            {
                push(@ipxenodes, $node);
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
            elsif ($nb eq "petitboot")
            {
                push(@petitbootnodes, $node);
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
        if (@ipxenodes > 0)
        {
            require xCAT_plugin::ipxe;
            @retarray =
              xCAT_plugin::ipxe::getNodesetStates(\@ipxenodes, $hashref);
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
        if (@petitbootnodes > 0)
        {
            require xCAT_plugin::petitboot;
            @retarray = xCAT_plugin::petitboot::getNodesetStates(\@petitbootnodes, $hashref);
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
    my %options = @_;
    my %gnopts;
    if ($options{prefetchcache}) { $gnopts{prefetchcache} = 1; }
    my $tab_hash;
    if ($options{global_tab_hash}) { $tab_hash = $options{global_tab_hash}; }

    my $state = "undefined";
    my $tftpdir;
    my $boottype;
    if (defined($tab_hash) && defined($tab_hash->{noderes}) && defined($tab_hash->{noderes}->{$node})) {
        $tftpdir  = $tab_hash->{noderes}->{$node}->{tftpdir};
        $boottype = $tab_hash->{noderes}->{$node}->{netboot};

    } else {

        #get boot type (pxe, yaboot or aixinstall)  for the node
        my $noderestab = xCAT::Table->new('noderes', -create => 0);
        my $ent = $noderestab->getNodeAttribs($node, [qw(netboot tftpdir)], %gnopts);

        #get tftpdir from the noderes table, if not defined get it from site talbe
        if ($ent && $ent->{tftpdir}) {
            $tftpdir = $ent->{tftpdir};
        }
        if (!$tftpdir) {
            if ($::XCATSITEVALS{tftpdir}) {
                $tftpdir = $::XCATSITEVALS{tftpdir};
            }
        }

        if ($ent && $ent->{netboot})
        {
            $boottype = $ent->{netboot};
        }


    }

    if (defined($boottype))
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
        elsif ($boottype eq "ipxe")
        {
            require xCAT_plugin::ipxe;
            my $tmp = xCAT_plugin::ipxe::getstate($node, $tftpdir);
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
        my $stref = $chaintab->getNodeAttribs($node, ['currstate'], %gnopts);
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
        my %node_syncfile    = ();
        my %osimage_syncfile = ();
        my @profiles         = ();

        if ($nodes) {

            # get the profile attributes for the nodes
            my $nodetype_t = xCAT::Table->new('nodetype');
            unless ($nodetype_t) {
                return;
            }
            my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, [ 'profile', 'provmethod' ]);

            # the vaule of profile for AIX node is the osimage name
            foreach my $node (@$nodes) {
                my $profile    = $nodetype_v->{$node}->[0]->{'profile'};
                my $provmethod = $nodetype_v->{$node}->[0]->{'provmethod'};
                if ($provmethod) {
                    $profile = $provmethod;
                }

                $node_syncfile{$node} = $profile;

                if (!grep /$profile/, @profiles) {
                    push @profiles, $profile;
                }
            }
        }

        # get the syncfiles base on the osimage
        my $osimage_t = xCAT::Table->new('osimage');
        unless ($osimage_t) {
            return;
        }
        foreach my $osimage (@profiles) {
            my $synclist = $osimage_t->getAttribs({ imagename => "$osimage" }, 'synclists');
            $osimage_syncfile{$osimage} = $synclist->{'synclists'};
        }

        # set the syncfiles to the nodes
        foreach my $node (@$nodes) {
            $node_syncfile{$node} = $osimage_syncfile{ $node_syncfile{$node} };
        }

        return \%node_syncfile;
    }    # end isAIX

    # if does not specify the $node param, default consider for genimage command
    if ($nodes) {
        my %node_syncfile = ();

        # get the os,arch,profile attributes for the nodes
        my $nodetype_t = xCAT::Table->new('nodetype');
        unless ($nodetype_t) {
            return;
        }
        my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, [ 'profile', 'os', 'arch', 'provmethod' ]);

        my $osimage_t = xCAT::Table->new('osimage');
        unless ($osimage_t) {
            return;
        }
        foreach my $node (@$nodes) {
            my $provmethod = $nodetype_v->{$node}->[0]->{'provmethod'};
            if (($provmethod) && ($provmethod ne "install") && ($provmethod ne "netboot") && ($provmethod ne "statelite")) {

                # get the syncfiles base on the osimage
                my $synclist = $osimage_t->getAttribs({ imagename => $provmethod }, 'synclists');
                if ($synclist && $synclist->{'synclists'}) {
                    $node_syncfile{$node} = $synclist->{'synclists'};
                }
            } else {
                $inst_type = "install";
                if ($provmethod eq "netboot" || $provmethod eq "diskless" || $provmethod eq "statelite") {
                    $inst_type = "netboot";
                }

                $profile = $nodetype_v->{$node}->[0]->{'profile'};
                $os      = $nodetype_v->{$node}->[0]->{'os'};
                $arch    = $nodetype_v->{$node}->[0]->{'arch'};
                my $platform = "";
                if ($os) {
                    if    ($os =~ /rh.*/)     { $platform = "rh"; }
                    elsif ($os =~ /centos.*/) { $platform = "centos"; }
		    elsif ($os =~ /alma.*/) { $platform = "alma"; }
                    elsif ($os =~ /rocky.*/) { $platform = "rocky"; }
                    elsif ($os =~ /^openeuler/) { $platform = "openeuler"; }
                    elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
                    elsif ($os =~ /sles.*/)   { $platform = "sles"; }
                    elsif ($os =~ /SL.*/)     { $platform = "SL"; }
                    elsif ($os =~ /ubuntu.*/) { $platform = "ubuntu"; }
                    elsif ($os =~ /debian.*/) { $platform = "debian"; }
                    elsif ($os =~ /AIX.*/)    { $platform = "AIX"; }
                }

                my $base = "$installdir/custom/$inst_type/$platform";
                $node_syncfile{$node} = xCAT::SvrUtils::get_file_name($base, "synclist", $profile, $os, $arch);
            }
        }

        return \%node_syncfile;
    } else {
        if ($imgname) {
            my $osimage_t = xCAT::Table->new('osimage');
            unless ($osimage_t) {
                return;
            }
            my $synclist = $osimage_t->getAttribs({ imagename => $imgname }, 'synclists');
            if ($synclist && $synclist->{'synclists'}) {
                return $synclist->{'synclists'};
            }
        }

        my $platform = "";
        if ($os) {
            if    ($os =~ /rh.*/)     { $platform = "rh"; }
            elsif ($os =~ /centos.*/) { $platform = "centos"; }
	    elsif ($os =~ /alma.*/) { $platform = "alma"; }
            elsif ($os =~ /rocky.*/) { $platform = "rocky"; }
            elsif ($os =~ /^openeuler/) { $platform = "openeuler"; }
            elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
            elsif ($os =~ /sles.*/)   { $platform = "sles"; }
            elsif ($os =~ /SL.*/)     { $platform = "SL"; }
            elsif ($os =~ /ubuntu.*/) { $platform = "ubuntu"; }
            elsif ($os =~ /debian.*/) { $platform = "debian"; }
            elsif ($os =~ /AIX.*/)    { $platform = "AIX"; }
            elsif ($os =~ /win/)      { $platform = "windows"; }
        }

        my $base = "$installdir/custom/$inst_type/$platform";
        return xCAT::SvrUtils::get_file_name($base, "synclist", $profile, $os, $arch);
    }

}

=head3 get_os_search_list
    Get the list of os names based on specified os name.
    This function is used to create a proper file search list for osimage
    template or pkglist

    Arguments:
      $os
    Returns:
      An array of the names of os
    Globals:
        none
    Error:
    Example:
         xCAT::SvrUtils->get_os_search_list("ubuntu24.04.1");
         Will return
         #   ubuntu24.04.1
         #   ubuntu24.04.0
         #   ubuntu24.04

         xCAT::SvrUtils->get_os_search_list("rocky9.6");
         Will return
         #   rocky9.6
         #   rocky9.5
         #   rocky9.4
         #   rocky9.3
         #   rocky9.2
         #   rocky9.1
         #   rocky9.0
         #   rocky9
    Comments:
        none

=cut

sub get_os_search_list {
    my $os = shift;
    if ($os =~ /^(openeuler(?:20|22|24)\.03)(sp[1-9][0-9]*)?$/) {
        return defined($2) ? ($os, $1, 'openeuler') : ($os, 'openeuler');
    }
    #example: for os=rhels7.6-alternate
    my ($baseos, $alter) = split(/\-/, $os);
    my @word = split(/\./, $baseos);
    my @list = ();

    while (@word && $word[-1] =~ /^[0-9]+$/) {
        my $last = pop(@word);
        if ($last =~ /^0[0-9]+$/) {
            push(@list, join('.', @word, $last));
            return @list;
        }
        while ($last >= 0) {
            push(@list, join('.', @word, $last));
            if ($last =~ /^0[0-9]/) {
                push(@list, join('.', @word, 0 + $last));
            }
            $last = sprintf("%0" . length($last) . "d", $last - 1);
        }
    }
    push(@list, join('.', @word));

    # openSUSE Leap 15.x uses the same AutoYaST asset layout as SLES 15.
    # Do not extend this to Leap 16 without validating its installer path.
    if ($baseos =~ /^(leap15)(?:\..*)?$/) {
        push(@list, "sle15");
    }

    return @list;
}

sub _profile_file_matches {
    my ($filename, $osver, $shortosver, $genos, $arch) = @_;

    my $stem = $filename;
    foreach my $extension (qw(otherpkgs.pkglist imgcapture.exlist pkglist tmpl exlist postinstall synclist repolist)) {
        if ($stem =~ s/\.\Q$extension\E$//) {
            last;
        }
    }
    $stem =~ s/\.[^.]+$// if $stem eq $filename;

    my @parts = split(/\./, $stem);

    # Not OS or architecture specific, for example compute.pkglist.
    if (scalar(@parts) <= 1) {
        return 1;
    }

    shift(@parts);    # profile

    my $suffix = join('.', @parts);
    if ($suffix eq $arch) {
        return 1;
    }

    my %valid_os_suffix = map { $_ => 1 } xCAT::SvrUtils::get_os_search_list($osver);
    $valid_os_suffix{$genos} = 1 if $genos && $osver !~ /^openeuler/;

    if ($valid_os_suffix{$suffix}) {
        return 1;
    }

    # OS and architecture specific, for example compute.ubuntu24.04.x86_64.pkglist.
    if (scalar(@parts) > 1 && $parts[-1] eq $arch) {
        pop(@parts);
        return $valid_os_suffix{join('.', @parts)} ? 1 : 0;
    }

    return 0;
}

sub get_file_name {
    my ($searchpath, $extension, $profile, $os, $arch, $genos) = @_;
    $genos = undef if $os =~ /^openeuler/;

    #usally there're only 4 arguments passed for this function
    #the $genos is only used for the Redhat family

    #handle the following ostypes: sles10.2, sles11.1, rhels5.3, rhels5.4, etc

    if (-r "$searchpath/$profile.$os.$arch.$extension") {
        return "$searchpath/$profile.$os.$arch.$extension";
    }
    if (-r "$searchpath/$profile.$os.$extension") {
        return "$searchpath/$profile.$os.$extension";
    }
    if (($genos) && (-r "$searchpath/$profile.$genos.$arch.$extension")) {
        return "$searchpath/$profile.$genos.$arch.$extension";
    }
    if (($genos) && (-r "$searchpath/$profile.$genos.$extension")) {
        return "$searchpath/$profile.$genos.$extension";
    }

    foreach my $osbase (xCAT::SvrUtils::get_os_search_list($os)) {
        if (-r "$searchpath/$profile.$osbase.$arch.$extension") {
            return "$searchpath/$profile.$osbase.$arch.$extension";
        }
        if (-r "$searchpath/$profile.$osbase.$extension") {
            return "$searchpath/$profile.$osbase.$extension";
        }
    }

    # No file matching OS name was found, next try just arch, if still nothing -> default to just profile
    if (-r "$searchpath/$profile.$arch.$extension") {
        return "$searchpath/$profile.$arch.$extension";
    }
    if (-r "$searchpath/$profile.$extension") {
        return "$searchpath/$profile.$extension";
    }

    return undef;
}

sub get_tmpl_file_name {
    my $searchpath = shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
        $searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "tmpl", @_);
}


sub get_pkglist_file_name {
    my $searchpath = shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
        $searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "pkglist", @_);
}

sub get_otherpkgs_pkglist_file_name {
    my $searchpath = shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
        $searchpath = shift;
    }
    return xCAT::SvrUtils::get_file_name($searchpath, "otherpkgs.pkglist", @_);
}


sub get_postinstall_file_name {
    my $searchpath = shift;
    if (($searchpath) && ($searchpath =~ /xCAT::SvrUtils/)) {
        $searchpath = shift;
    }
    my $profile   = shift;
    my $os        = shift;
    my $arch      = shift;
    my $genos     = shift;
    my $extension = "postinstall";
    if ($os =~ /^openeuler/) {
        my $file = get_file_name($searchpath, $extension, $profile, $os, $arch, undef);
        return defined($file) && -x $file ? $file : undef;
    }
    my $dotpos    = rindex($os, ".");
    my $osbase    = substr($os, 0, $dotpos);

    #handle the following ostypes: sles10.2, sles11.1, rhels5.3, rhels5.4, etc

    if (-x "$searchpath/$profile.$os.$arch.$extension") {
        return "$searchpath/$profile.$os.$arch.$extension";
    }
    if (-x "$searchpath/$profile.$osbase.$arch.$extension") {
        return "$searchpath/$profile.$osbase.$arch.$extension";
    }
    if (-x "$searchpath/$profile.$os.$extension") {
        return "$searchpath/$profile.$os.$extension";
    }
    if (-x "$searchpath/$profile.$osbase.$extension") {
        return "$searchpath/$profile.$osbase.$extension";
    }
    # If the osimge name was specified with -n, the name might contain multiple "."
    # Chop them off one at a time until filename match is found
    while ($dotpos > 0) {
        if (-x "$searchpath/$profile.$osbase.$arch.$extension") {
            return "$searchpath/$profile.$osbase.$arch.$extension";
        }
        if (-x "$searchpath/$profile.$osbase.$extension") {
            return "$searchpath/$profile.$osbase.$extension";
        }
        # Chop off "." from the end and try again
        $dotpos = rindex($osbase, ".");
        $osbase = substr($osbase, 0, $dotpos);
    }

    #if there are no '.', pick the two numbers follow by leading string, like sles11
    #then pick one number follow by leading string, like centos7, rhels7
    if ($os =~ m/([a-zA-Z]+\d\d)/)
    {
        $osbase=$1;
        if (-x "$searchpath/$profile.$osbase.$arch.$extension") {
            return "$searchpath/$profile.$osbase.$arch.$extension";
        }
        if (-x "$searchpath/$profile.$osbase.$extension") {
            return "$searchpath/$profile.$osbase.$extension";
        }
    }

    if ($os =~ m/([a-zA-Z]+\d)/)
    {
        $osbase = $1;
        if (-x "$searchpath/$profile.$osbase.$arch.$extension") {
            return "$searchpath/$profile.$osbase.$arch.$extension";
        }
        if (-x "$searchpath/$profile.$osbase.$extension") {
            return "$searchpath/$profile.$osbase.$extension";
        }
    }

    if (($genos) && (-x "$searchpath/$profile.$genos.$arch.$extension")) {
        return "$searchpath/$profile.$genos.$arch.$extension";
    }
    if (($genos) && (-x "$searchpath/$profile.$genos.$extension")) {
        return "$searchpath/$profile.$genos.$extension";
    }

    if (-x "$searchpath/$profile.$arch.$extension") {
        return "$searchpath/$profile.$arch.$extension";
    }
    if (-x "$searchpath/$profile.$extension") {
        return "$searchpath/$profile.$extension";
    }
    return undef;
}


sub get_exlist_file_name {
    my $searchpath = shift;
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

sub _apply_new_linuximage_defaults {
    my $linuximagetab = shift;
    my $imagename     = shift;
    my $attributes    = shift;

    my ($existing) = $linuximagetab->getAttribs(
        { imagename => $imagename }, 'pkgdir');
    unless ($existing) {
        $attributes->{addkcmdline} = "quiet";
    }
    return;
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
sub update_tables_with_templates
{
    my $osver = shift;    #like sle11, rhel5.3
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
        $osver = shift;
    }
    my $shortosver = $osver;
    $shortosver =~ s/\..*//; # for major-version assets, for example leap15.6 -> leap15
    my $arch         = shift;    #like ppc64, x86, x86_64
    my $ospkgdir     = shift;
    my $osdistroname = shift;
    my $legacyUB20   = shift;
    my %args         = @_;

    my $osname    = $osver;;     #like sles, rh, centos, windows
    my $ostype    = "Linux";     #like Linux, Windows
    my $imagetype = "linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
        $osname    = "windows";
        $ostype    = "Windows";
        $imagetype = "windows";
    } elsif ($osver =~ /^hyperv/) {
        $osname    = "hyperv";
        $ostype    = "Windows";
        $imagetype = "windows";
    } elsif ($osver =~ /^leap15/) {
        $osname = "sles";
    } else {
        until (-r "$::XCATROOT/share/xcat/install/$osname/" or not $osname) {
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
        $genos = "rhels$1";
    } elsif ($osver =~ /ubuntu/) {
        # for Focal and later Ubuntu we repurpose genos to indicate the use
        # of the subiquity installer
        if ($osver =~ /ubuntu(\d+\.\d+)/) {
            if (($1 >= 20.04) and ($legacyUB20 !~ /legacy/)) {
                $genos = "subiquity";
            }
        }
    } elsif ($osver =~ /^leap15/) {
        $genos = "sle15";
    }
    # For Leap, let get_os_search_list prefer leap15 assets before the sle15 fallback.
    my $file_lookup_genos = ($osver =~ /^leap15/) ? undef : $genos;

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
    my $tmp         = $installdirs[0];
    if (defined($tmp)) {
        $installroot = $tmp;
    }
    my $cuspath = "$installroot/custom/install/$osname";
    my $defpath = "$::XCATROOT/share/xcat/install/$osname";

    #now get all the profile names for full installation
    my %profiles  = ();
    my @tmplfiles = glob($cuspath . "/{compute,service}.*tmpl");
    foreach (@tmplfiles) {
        my $tmpf = basename($_);

        #skip template files for other OS or architecture suffixes
        next unless _profile_file_matches($tmpf, $osver, $shortosver, $genos, $arch);

        #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
        $tmpf =~ /^([^\.]*)\..*$/;
        $tmpf = $1;

        #print "$tmpf\n";
        $profiles{$tmpf} = 1;
    }
    @tmplfiles = glob($defpath . "/{compute,service}.*tmpl");
    foreach (@tmplfiles) {
        my $tmpf = basename($_);

        #skip template files for other OS or architecture suffixes
        next unless _profile_file_matches($tmpf, $osver, $shortosver, $genos, $arch);

        #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
        $tmpf =~ /^([^\.]*)\..*$/;
        $tmpf = $1;
        $profiles{$tmpf} = 1;
    }

    #update the osimage and linuximage table
    my $osimagetab;
    my $linuximagetab;
    my $winimagetab;
    if ($args{checkonly}) {
        if (keys %profiles) {
            return (0, "");
        } else {
            return (1, "Missing template files");
        }
    }
    foreach my $profile (keys %profiles) {

        #print "profile=$profile\n";
        #get template file
        my $tmplfile = get_tmpl_file_name($cuspath, $profile, $osver, $arch, $file_lookup_genos);
        if (!$tmplfile) { $tmplfile = get_tmpl_file_name($defpath, $profile, $osver, $arch, $file_lookup_genos); }
        if (!$tmplfile) { next; }

        #get otherpkgs.pkglist file
        my $otherpkgsfile = get_otherpkgs_pkglist_file_name($cuspath, $profile, $osver, $arch, $file_lookup_genos);
        if (!$otherpkgsfile) { $otherpkgsfile = get_otherpkgs_pkglist_file_name($defpath, $profile, $osver, $arch, $file_lookup_genos); }

        #get synclist file
        my $synclistfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");

        #get the pkglist file
        my $pkglistfile = get_pkglist_file_name($cuspath, $profile, $osver, $arch, $file_lookup_genos);
        if (!$pkglistfile) { $pkglistfile = get_pkglist_file_name($defpath, $profile, $osver, $arch, $file_lookup_genos); }

        #now update the db
        if (!$osimagetab) {
            $osimagetab = xCAT::Table->new('osimage', -create => 1);
        }

        if ($osimagetab) {

            #check if the image is already in the table
            if ($osimagetab) {
                my $found = 0;
                my $tmp1  = $osimagetab->getAllEntries();
                if (defined($tmp1) && (@$tmp1 > 0)) {
                    foreach my $rowdata (@$tmp1) {
                        if (($osver eq $rowdata->{osvers}) && ($arch eq $rowdata->{osarch}) && ($rowdata->{provmethod} eq "install") && ($profile eq $rowdata->{profile})) {
                            $found = 1;
                            last;
                        }
                    }
                }

                my $imagename = $osver . "-" . $arch . "-install-" . $profile;

                #TODO: check if there happen to be a row that has the same imagename but with different contents
                #now we can wirte the info into db
                my %key_col = (imagename => $imagename);
                my %tb_cols = (imagetype => $imagetype,
                    provmethod   => "install",
                    profile      => $profile,
                    osname       => $ostype,
                    osvers       => $osver,
                    osarch       => $arch,
                    synclists    => $synclistfile,
                    osdistroname => $osdistroname);

                #for service node osimage, add service node to the postscripts attributes
                if($profile eq "service"){
                    $tb_cols{postscripts}="servicenode";
                }


                if ($args{description}) {
                    $tb_cols{description} = $args{description};
                }
                $osimagetab->setAttribs(\%key_col, \%tb_cols)
                  unless $osver =~ /^openeuler/
                    && $osimagetab->getAttribs(\%key_col, 'imagename');

                if ($osname =~ /^win/) {
                    if (!$winimagetab) { $winimagetab = xCAT::Table->new('winimage', -create => 1); }
                    if ($winimagetab) {
                        my %key_col = (imagename => $imagename);
                        my %tb_cols = (template  => $tmplfile);
                        $winimagetab->setAttribs(\%key_col, \%tb_cols);
                    } else {
                        return (1, "Cannot open the winimage table.");
                    }
                } else {
                    if (!$linuximagetab) { $linuximagetab = xCAT::Table->new('linuximage', -create => 1); }
                    if ($linuximagetab) {
                        my %key_col = (imagename => $imagename);
                        my %tb_cols = (template => $tmplfile,
                            pkgdir       => $ospkgdir,
                            pkglist      => $pkglistfile,
                            otherpkglist => $otherpkgsfile,
                            otherpkgdir => "$installroot/post/otherpkgs/$osver/$arch");
                        _apply_new_linuximage_defaults(
                            $linuximagetab, $imagename, \%tb_cols);

                        $linuximagetab->setAttribs(\%key_col, \%tb_cols)
                          unless $osver =~ /^openeuler/
                            && $linuximagetab->getAttribs(\%key_col, 'imagename');

                    } else {
                        return (1, "Cannot open the linuximage table.");
                    }
                }
            } else {
                return (1, "Cannot open the osimage table.");
            }
        }
    }
    if ($osimagetab)    { $osimagetab->close(); }
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
sub update_tables_with_mgt_image
{
    my $osver = shift;    #like sle11, rhel5.3
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
        $osver = shift;
    }
    my $arch         = shift;    #like ppc64, x86, x86_64
    my $ospkgdir     = shift;
    my $osdistroname = shift;

    my $osname    = $osver;;     #like sles, rh, centos, windows
    my $ostype    = "Linux";     #like Linux, Windows
    my $imagetype = "linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
        $osname    = "windows";
        $ostype    = "Windows";
        $imagetype = "windows";
    } elsif ($osver =~ /^hyperv/) {
        $osname    = "hyperv";
        $ostype    = "Windows";
        $imagetype = "windows";
    } elsif ($osver =~ /^leap15/) {
        $osname = "sles";
    } else {
        until (-r "$::XCATROOT/share/xcat/install/$osname/" or not $osname) {
            chop($osname);
        }
        unless ($osname) {
            return (1, "Unable to find $::XCATROOT/share/xcat/install directory for $osver");
        }
    }

    #if the arch of osimage does not match the arch of MN,return
    my $myarch = qx(uname -i);
    chop $myarch;
    if ($arch ne $myarch) {
        return 0;
    }


    #for rhels5.1  genos=rhel5
    my $genos = $osver;
    $genos =~ s/\..*//;
    if ($genos =~ /rh.*s(\d*)/) {
        $genos = "rhels$1";
    }

    #if the osver does not match the osver of MN, return
    my $myosver = xCAT::Utils->osver("all");
    $myosver =~ s/,//;
    if (xCAT::Utils->version_cmp("$osver", "$myosver") != 0) {
        return 0;
    }

    my $installroot = xCAT::TableUtils->getInstallDir();
    my @installdirs = xCAT::TableUtils->get_site_attribute("installdir");
    my $tmp         = $installdirs[0];
    if (defined($tmp)) {
        $installroot = $tmp;
    }
    my $cuspath = "$installroot/custom/install/$osname";
    my $defpath = "$::XCATROOT/share/xcat/install/$osname";

    #now get all the profile names for full installation
    my %profiles  = ();
    my @tmplfiles = glob($cuspath . "/{compute,service}.*tmpl");
    foreach (@tmplfiles) {
        my $tmpf = basename($_);

        #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
        $tmpf =~ /^([^\.]*)\..*$/;
        $tmpf = $1;

        #print "$tmpf\n";
        $profiles{$tmpf} = 1;
    }
    @tmplfiles = glob($defpath . "/{compute,service}.*tmpl");
    foreach (@tmplfiles) {
        my $tmpf = basename($_);

        #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
        $tmpf =~ /^([^\.]*)\..*$/;
        $tmpf = $1;
        if ($tmpf eq "compute") {
            $profiles{$tmpf} = 1;
        }
    }

    #update the osimage and linuximage table
    my $osimagetab;
    my $linuximagetab;
    my $imagename = $osver . "-" . $arch . "-stateful" . "-mgmtnode";
    foreach my $profile (keys %profiles) {

        #print "profile=$profile\n";
        #get template file
        my $tmplfile = get_tmpl_file_name($cuspath, $profile, $osver, $arch, $genos);
        if (!$tmplfile) { $tmplfile = get_tmpl_file_name($defpath, $profile, $osver, $arch, $genos); }
        if (!$tmplfile) { next; }

        #get otherpkgs.pkglist file
        my $otherpkgsfile = get_otherpkgs_pkglist_file_name($cuspath, $profile, $osver, $arch);
        if (!$otherpkgsfile) { $otherpkgsfile = get_otherpkgs_pkglist_file_name($defpath, $profile, $osver, $arch); }

        #get synclist file
        my $synclistfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");

        #get the pkglist file
        my $pkglistfile = get_pkglist_file_name($cuspath, $profile, $osver, $arch);
        if (!$pkglistfile) { $pkglistfile = get_pkglist_file_name($defpath, $profile, $osver, $arch); }

        #now update the db
        if (!$osimagetab) {
            $osimagetab = xCAT::Table->new('osimage', -create => 1);
        }


        if ($osimagetab) {

            #check if the image is already in the table
            if ($osimagetab) {
                my $found = 0;
                my $tmp1  = $osimagetab->getAllEntries();
                if (defined($tmp1) && (@$tmp1 > 0)) {
                    foreach my $rowdata (@$tmp1) {
                        if (($osver eq $rowdata->{osvers}) && ($arch eq $rowdata->{osarch}) && ($rowdata->{provmethod} eq "install") && ($profile eq $rowdata->{profile})) {
                            $found = 1;
                            last;
                        }
                    }
                }

                #               if ($found) { next; }


                #TODO: check if there happen to be a row that has the same imagename but with different contents
                #now we can wirte the info into db
                my %key_col = (imagename => $imagename);
                my %tb_cols = (imagetype => $imagetype,
                    provmethod   => "install",
                    profile      => $profile,
                    osname       => $ostype,
                    osvers       => $osver,
                    osarch       => $arch,
                    synclists    => $synclistfile,
                    osdistroname => $osdistroname);
                $osimagetab->setAttribs(\%key_col, \%tb_cols);

                if ($osname !~ /^win/) {
                    if (!$linuximagetab) { $linuximagetab = xCAT::Table->new('linuximage', -create => 1); }
                    if ($linuximagetab) {
                        my %key_col = (imagename => $imagename);
                        my %tb_cols = (template => $tmplfile,
                            pkgdir       => $ospkgdir,
                            pkglist      => $pkglistfile,
                            otherpkglist => $otherpkgsfile,
                            otherpkgdir => "$installroot/post/otherpkgs/$osver/$arch");
                        _apply_new_linuximage_defaults(
                            $linuximagetab, $imagename, \%tb_cols);
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
    if ($osimagetab)    { $osimagetab->close(); }
    if ($linuximagetab) { $linuximagetab->close(); }

    #set nodetype.provmethod to the new created osimage if it is not set
    my @mgtnodes = xCAT::NodeRange::noderange('__mgmtnode');
    if (scalar @mgtnodes) {
        my $nttab = xCAT::Table->new('nodetype', -create => 1);
        unless ($nttab) {
            return (1, "Cannot open the nodetype table.");
        }

        my $ntents = $nttab->getNodesAttribs(\@mgtnodes, ['provmethod']);
        my %ent;
        foreach my $node (@mgtnodes) {
            print "$node\n";
            unless ($ntents->{$node} and $ntents->{$node}->['provmethod']) {
                $ent{$node}{'provmethod'} = $imagename;
            }
        }

        $nttab->setNodesAttribs(\%ent);


        if ($nttab) { $nttab->close(); }
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
sub update_tables_with_diskless_image
{
    my $osver = shift;    #like sle11, rhel5.3
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
        $osver = shift;
    }
    my $arch         = shift;    #like ppc64, x86, x86_64
    my $profile      = shift;
    my $mode         = shift;
    my $ospkgdir     = shift;
    my $osdistroname = shift;
    my $shortosver   = $osver;
    $shortosver =~ s/\..*//; # for major-version assets, for example leap15.6 -> leap15

    my $provm = "netboot";
    if ($mode) { $provm = $mode; }

    my $osname    = $osver;;     #like sles, rh, centos, windows
    my $ostype    = "Linux";     #like Linux, Windows
    my $imagetype = "linux";
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
        $osname    = "windows";
        $ostype    = "Windows";
        $imagetype = "windows";
    } elsif ($osver =~ /^leap15/) {
        $osname = "sles";
    } else {
        until (-r "$::XCATROOT/share/xcat/netboot/$osname/" or not $osname) {
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
        $genos = "rhels$1";
    } elsif ($osver =~ /^leap15/) {
        $genos = "sle15";
    }
    # For Leap, let get_os_search_list prefer leap15 assets before the sle15 fallback.
    my $file_lookup_genos = ($osver =~ /^leap15/) ? undef : $genos;

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
    my $tmp         = $installdirs[0];
    if (defined($tmp)) {
        $installroot = $tmp;
    }
    my $cuspath = "$installroot/custom/netboot/$osname";
    my $defpath = "$::XCATROOT/share/xcat/netboot/$osname";
    my $osimagetab;
    my $linuximagetab;

    my %profiles = ();
    if ($profile) {
        $profiles{$profile} = 1;
    } else {
        my @tmplfiles = glob($cuspath . "/compute.*pkglist");
        foreach (@tmplfiles) {
            my $tmpf = basename($_);

            #skip pkglist files for other OS or architecture suffixes
            next unless _profile_file_matches($tmpf, $osver, $shortosver, $genos, $arch);

            #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
            $tmpf =~ /^([^\.]*)\..*$/;
            $tmpf = $1;
            $profiles{$tmpf} = 1;
        }
        @tmplfiles = glob($defpath . "/compute.*pkglist");
        foreach (@tmplfiles) {
            my $tmpf = basename($_);

            #skip pkglist files for other OS or architecture suffixes
            next unless _profile_file_matches($tmpf, $osver, $shortosver, $genos, $arch);

            #get the profile name out of the file, TODO: this does not work if the profile name contains the '.'
            $tmpf =~ /^([^\.]*)\..*$/;
            $tmpf = $1;
            $profiles{$tmpf} = 1;
        }
    }
    foreach my $profile (keys %profiles) {

        #get the pkglist file
        my $pkglistfile = get_pkglist_file_name($cuspath, $profile, $osver, $arch, $file_lookup_genos);
        if (!$pkglistfile) { $pkglistfile = get_pkglist_file_name($defpath, $profile, $osver, $arch, $file_lookup_genos); }

        #print "pkglistfile=$pkglistfile\n";
        if (!$pkglistfile) { next; }

        #get otherpkgs.pkglist file
        my $otherpkgsfile = get_otherpkgs_pkglist_file_name($cuspath, $profile, $osver, $arch, $file_lookup_genos);
        if (!$otherpkgsfile) { $otherpkgsfile = get_otherpkgs_pkglist_file_name($defpath, $profile, $osver, $arch, $file_lookup_genos); }

        #get synclist file
        my $synclistfile = xCAT::SvrUtils->getsynclistfile(undef, $osver, $arch, $profile, "netboot");

        #get the exlist file
        my $exlistfile = get_exlist_file_name($cuspath, $profile, $osver, $arch, $file_lookup_genos);
        if (!$exlistfile) { $exlistfile = get_exlist_file_name($defpath, $profile, $osver, $arch, $file_lookup_genos); }

        #get postinstall script file name
        my $postfile = get_postinstall_file_name($cuspath, $profile, $osver, $arch, $genos);
        if (!$postfile) { $postfile = get_postinstall_file_name($defpath, $profile, $osver, $arch, $genos); }


        #now update the db
        if (!$osimagetab) {
            $osimagetab = xCAT::Table->new('osimage', -create => 1);
        }

        if ($osimagetab) {

            #check if the image is already in the table
            if ($osimagetab) {
                my $found = 0;
                my $tmp1  = $osimagetab->getAllEntries();
                if (defined($tmp1) && (@$tmp1 > 0)) {
                    foreach my $rowdata (@$tmp1) {
                        if (($osver eq $rowdata->{osvers}) && ($arch eq $rowdata->{osarch}) && ($rowdata->{provmethod} eq $provm) && ($profile eq $rowdata->{profile})) {
                            $found = 1;
                            last;
                        }
                    }
                }
                if ($found) {
                    print "The image is already in the db.\n";
                    #                         next;
                }

                my $imagename = $osver . "-" . $arch . "-$provm-" . $profile;

                #TODO: check if there happen to be a row that has the same imagename but with different contents
                #now we can wirte the info into db
                my %key_col = (imagename => $imagename);
                my %tb_cols = (imagetype => $imagetype,
                    provmethod   => $provm,
                    profile      => $profile,
                    osname       => $ostype,
                    osvers       => $osver,
                    osarch       => $arch,
                    synclists    => $synclistfile,
                    osdistroname => $osdistroname);
                $osimagetab->setAttribs(\%key_col, \%tb_cols)
                  unless $osver =~ /^openeuler/
                    && $osimagetab->getAttribs(\%key_col, 'imagename');

                if ($osname !~ /^win/) {
                    if (!$linuximagetab) { $linuximagetab = xCAT::Table->new('linuximage', -create => 1); }
                    if ($linuximagetab) {
                        my %key_col = (imagename => $imagename);
                        my %tb_cols = (pkglist => $pkglistfile,
                            pkgdir       => $ospkgdir,
                            otherpkglist => $otherpkgsfile,
                            otherpkgdir => "$installroot/post/otherpkgs/$osver/$arch",
                            exlist      => $exlistfile,
                            postinstall => $postfile,
                            rootimgdir => "$installroot/netboot/$osver/$arch/$profile");
                        _apply_new_linuximage_defaults(
                            $linuximagetab, $imagename, \%tb_cols);
                        $linuximagetab->setAttribs(\%key_col, \%tb_cols)
                          unless $osver =~ /^openeuler/
                            && $linuximagetab->getAttribs(\%key_col, 'imagename');

                    } else {
                        return (1, "Cannot open the linuximage table.");
                    }
                }
            } else {
                return (1, "Cannot open the osimage table.");
            }
        }
    }
    if ($osimagetab)    { $osimagetab->close(); }
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
        nopping:  will not call pping subroutine if it set as "nopping"
    Returns:
        Return a hash with node name as key
    Globals:
        none
    Error:
        none
    Example:
        xCAT::Utils->get_mac_by_arp($nodes, $display, $nopping);
    Comments:

=cut

#-------------------------------------------------------------------------------
sub get_mac_by_arp ()
{
    my ($class, $nodes, $display, $nopping) = @_;

    my $node;
    my $data;
    my %ret               = ();
    my $unreachable_nodes = "";
    my $noderange         = join(',', @$nodes);

    if ($nopping ne "nopping") {
        my @output = xCAT::Utils->runcmd("/opt/xcat/bin/pping $noderange", -1);
        foreach my $line (@output) {
            my ($hostname, $result) = split ':', $line;
            my ($token,    $status) = split ' ', $result;
            chomp($token);
            if ($token eq 'ping') {
                $node->{$hostname}->{reachable} = 1;
            }
        }
    }

    foreach my $n (@$nodes) {
        if (($node->{$n}->{reachable}) || ($nopping eq "nopping")) {
            my $output;
            my $IP = xCAT::NetworkUtils::toIP($n);
            if (xCAT::Utils->isAIX()) {
                $output = `/usr/sbin/arp -a`;
            } else {
                if (-x "/usr/sbin/arp") {
                    $output = `/usr/sbin/arp -n`;
                }
                else {
                    $output = `/sbin/arp -n`;
                }
            }

            my ($ip, $mac);
            my @lines = split /\n/, $output;
            foreach my $line (@lines) {
                if (xCAT::Utils->isAIX() && $line =~ /\((\S+)\)\s+at\s+(\S+)/) {
                    ($ip, $mac) = ($1, $2);
                    ######################################################
                    # Change mac format to be same as linux, but without ':'
                    # For example: '0:d:60:f4:f8:22' to '000d60f4f822'
                    ######################################################
                    if ($mac)
                    {
                        my @mac_sections = split /:/, $mac;
                        for my $m (@mac_sections)
                        {
                            $m = "0$m" if (length($m) == 1);
                        }
                        $mac = join '', @mac_sections;
                    }
                } elsif ($line =~ /^(\S+)+\s+\S+\s+(\S+)\s/) {
                    ($ip, $mac) = ($1, $2);
                } else {
                    ($ip, $mac) = (undef, undef);
                }
                if (@$IP[1] ne $ip) {
                    ($ip, $mac) = (undef, undef);
                } else {
                    last;
                }
            }
            if ($ip && $mac) {
                if ($display ne "yes") {
                    #####################################
                    # Write adapter mac to database
                    #####################################
                    my $mactab = xCAT::Table->new("mac", -create => 1, -autocommit => 1);
                    $mactab->setNodeAttribs($n, { mac => $mac });
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
    if ($request->{node}) {
        return $request->{node};
    } elsif ($request->{'_xcat_clienthost'}) {
        my @nodenames = noderange($request->{'_xcat_clienthost'}->[0] . "," . $request->{'_xcat_clientfqdn'}->[0]);
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

    my $node     = shift;
    my $type     = shift;
    my $callback = shift;

    # parse all the dollar signs...
    # if its a directory then it has a / in it, so you have to parse it.
    # if its a server, it won't have one so don't worry about it.
    my @arr = split("/", $dir);
    my $fdir = "";
    foreach my $p (@arr) {

        # have to make this geric so $ can be in the midle of the name: asdf$foobar.sitadsf
        if ($p =~ /\$/) {
            my $pre;
            my $suf;
            my @fParts;
            if ($p =~ /([^\$]*)([^# ]*)(.*)/) {
                $pre = $1;
                $p   = $2;
                $suf = $3;
            }

            # have to sub here:
            # get rid of the $ sign.
            foreach my $part (split('\$', $p)) {
                if ($part eq '') { next; }

                #$callback->({error=>["part is $part"],errorcode=>[1]});
                # check if p is just the node name:
                if ($part eq 'node') {

                    # it is so, just return the node.
                    #$fdir .= "/$pre$node$suf";
                    push @fParts, $node;
                } else {

                    # ask the xCAT DB what the attribute is.
                    my ($table, $col) = split('\.', $part);
                    unless ($col) { $col = 'UNDEFINED' }
                    my $tab = xCAT::Table->new($table);
                    unless ($tab) {
                        $callback->({ error => ["$table does not exist"], errorcode => [1] });
                        return;
                    }
                    my $ent;
                    my $val;
                    if ($table eq 'site') {

                        #$val = $tab->getAttribs( { key => "$col" }, 'value' );
                        #$val = $val->{'value'};
                        my @vals = xCAT::TableUtils->get_site_attribute($col);
                        $val = $vals[0];
                    } else {
                        $ent = $tab->getNodeAttribs($node, [$col]);
                        $val = $ent->{$col};
                    }
                    unless ($val) {

                        # couldn't find the value!!
                        $val = "UNDEFINED"
                    }
                    push @fParts, $val;
                }
            }
            my $val = join('.', @fParts);
            if ($type eq 'dir') {
                $fdir .= "/$pre$val$suf";
            } else {
                $fdir .= $pre . $val . $suf;
            }
        } else {

            # no substitution here
            $fdir .= "/$p";
        }
    }

    # now that we've processed variables, process commands
    # this isn't quite rock solid.  You can't name directories with #'s in them.
    if ($fdir =~ /#CMD=/) {
        my $dir;
        foreach my $p (split(/#/, $fdir)) {
            if ($p =~ /CMD=/) {
                $p =~ s/CMD=//;
                my $cmd = $p;

                #$callback->({info=>[$p]});
                $p = `$p 2>&1`;
                chomp($p);

                #$callback->({info=>[$p]});
                unless ($p) {
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

    my $sip      = shift;
    my $callback = shift;

    my $cmd = "XCATBYPASS=Y litetree $node";
    my @uris = xCAT::Utils->runcmd($cmd, 0);

    foreach my $uri (@uris) {

        # parse the result
        # the result looks like "nodename: nfsserver:directory";
        $uri =~ m/\Q$node\E:\s+(.+):(.+)$/;
        my $nfsserver    = $1;
        my $nfsdirectory = $2;

        if ($nfsserver eq $sip) {    # on the service node
            _ensure_nfs_exported($nfsserver, $nfsdirectory, $callback);
        }
    }
}

sub nfs_export_exists {
    my ( $dir, %opts ) = _nfs_method_args(@_);
    my @files = _nfs_export_files(%opts);
    for my $file (@files) {
        open(my $fh, '<', $file) or next;
        while (<$fh>) {
            next if /^\s*#/;
            return 1 if /^\s*\Q$dir\E\s/;
        }
        close $fh;
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3 nfs_export_line

    The /etc/exports line for a directory a service node serves to its nodes.

    Arguments:
        $dir        the directory to export
        reexport    true when $dir is itself an NFS mount

    Returns:
        one export line, with no trailing newline.

    exportfs refuses an NFS mount without an explicit fsid, and crossmnt lets a client cross into
    the mount below. The fsid is derived from the path, so a restart does not make client mounts
    stale.

=cut

#-----------------------------------------------------------------------------
sub nfs_export_line {
    my ( $dir, %opts ) = _nfs_method_args(@_);
    my $options = 'rw,no_root_squash,sync,no_subtree_check,insecure';
    if ( $opts{reexport} ) {
        $options .= ',crossmnt,fsid=' . _nfs_export_fsid($dir);
    }
    return "$dir *($options)";
}

# A stable, non-zero fsid for a path. 0 is reserved for the export root.
sub _nfs_export_fsid {
    my ($dir) = @_;
    my $sum = 0;
    $sum = ( $sum * 31 + ord($_) ) % 2147483647 for split //, $dir;
    return $sum || 1;
}

sub _ensure_nfs_exported {
    my ($nfsserver, $nfsdirectory, $callback, %opts) = @_;
    my $export_options = 'rw,no_root_squash,sync,no_subtree_check,insecure';

    unless (-d $nfsdirectory) {
        if (-e $nfsdirectory) {
            unlink $nfsdirectory;
        }
        mkpath $nfsdirectory;
    }

    my $cmd = "showmount -e $nfsserver";
    my @entries = xCAT::Utils->runcmd($cmd, 0);
    shift @entries;
    if (grep /\Q$nfsdirectory\E/, @entries) {
        $callback->({ data => ["$nfsdirectory has been exported already!"] });
    } else {
        $cmd = "/usr/sbin/exportfs :$nfsdirectory -o $export_options";
        xCAT::Utils->runcmd($cmd, 0);
        $callback->({ data => ["now $nfsdirectory is exported!"] });
    }

    if (ensure_nfs_export_option($nfsdirectory, 'insecure')) {
        xCAT::Utils->runcmd("/usr/sbin/exportfs -r", 0);
        $callback->({ data => ["added insecure to existing $nfsdirectory export"] });
    } elsif (!nfs_export_exists($nfsdirectory)) {
        my $append_separator = exists($opts{append_separator})
          ? $opts{append_separator}
          : ' ';
        $cmd = qq{echo "$nfsdirectory *($export_options)" >>$append_separator/etc/exports};
        xCAT::Utils->runcmd($cmd, 0);
        my $message = exists($opts{added_message})
          ? $opts{added_message}
          : "$nfsdirectory is added to /etc/exports with default option";
        $callback->({ data => [$message] });
    }
}

sub setupStatemnt {
    my $sip = shift;
    if (($sip) && ($sip =~ /xCAT::SvrUtils/))
    {
        $sip = shift;
    }

    my $statemnt = shift;
    my $callback = shift;

    $statemnt =~ m/^(.+):(.+)$/;
    my $nfsserver    = $1;
    my $nfsdirectory = $2;
    if ($sip eq xCAT::NetworkUtils->getipaddr($nfsserver)) {
        _ensure_nfs_exported(
            $nfsserver, $nfsdirectory, $callback,
            append_separator => '',
            added_message    => "$nfsdirectory is added into /etc/exports with default options",
        );
    }

}

sub ensure_nfs_export_option {
    my ( $dir, @args ) = _nfs_method_args(@_);
    local @_ = @args;
    my $option = shift || 'insecure';
    my %opts = @_;
    my @files = _nfs_export_files(%opts);
    my $changed = 0;
    for my $file (@files) {
        open(my $fh, '<', $file) or next;
        my @raw = <$fh>;
        close $fh;

        my @logical;
        my $buf = '';
        for my $r (@raw) {
            chomp $r;
            if ($r =~ s/\s*\\$//) {
                $buf .= "$r ";
                next;
            }
            $buf .= $r;
            push @logical, $buf;
            $buf = '';
        }
        push @logical, $buf if $buf ne '';

        my $file_changed = 0;
        for my $line (@logical) {
            next if $line =~ /^\s*#/;
            next unless $line =~ /^\s*\Q$dir\E\s/;
            my $line_changed = 0;
            my $comment = '';
            $comment = " $1" if $line =~ s/\s+(#.*)$//;
            my $tail = $line;
            $tail =~ s/^\s*\Q$dir\E\s+//;
            my @tokens;
            while ($tail =~ /(\S+(?:\([^)]*\))?)/g) {
                push @tokens, $1;
            }
            my @out;
            for my $tok (@tokens) {
                if ($tok =~ /^-(.+)/) {
                    my $opts = $1;
                    unless (xCAT::Utils->comma_list_contains($opts, $option)) {
                        $tok = "-$opts,$option";
                        $line_changed = 1;
                    }
                } elsif ($tok =~ /^([^(]+)\(([^)]*)\)$/) {
                    my ($client, $opts) = ($1, $2);
                    unless (xCAT::Utils->comma_list_contains($opts, $option)) {
                        $tok = "$client($opts,$option)";
                        $line_changed = 1;
                    }
                } else {
                    $tok = "$tok($option)";
                    $line_changed = 1;
                }
                push @out, $tok;
            }
            if ($line_changed) {
                $line = "$dir " . join(" ", @out) . "$comment";
                $file_changed = 1;
            }
        }
        if ($file_changed) {
            open(my $wfh, '>', $file) or next;
            print $wfh map { "$_\n" } @logical;
            close $wfh;
            $changed = 1;
        }
    }
    return $changed;
}

sub _nfs_method_args {
    my @args = @_;
    shift @args if @args && (ref($args[0]) || $args[0] eq __PACKAGE__);
    return @args;
}

sub _nfs_export_files {
    my %opts = @_;
    return @{ $opts{files} } if ref($opts{files}) eq 'ARRAY';

    my @files = ('/etc/exports');
    push @files, glob('/etc/exports.d/*.exports') if -d '/etc/exports.d';
    return @files;
}

#-------------------------------------------------------------------------------------------
# Common method to send info back to the client
# The last two args are optional, though $allerrornodes will unlikely be there without $node
# TODO: investigate possibly removing this and using MsgUtils instead
#
#--------------------------------------------------------------------------------------------
sub sendmsg {
    my $text          = shift;
    my $callback      = shift;
    my $node          = shift;
    my %allerrornodes = shift;
    my $descr;
    my $rc;
    if (ref $text eq 'HASH') {
        die "not right now";
    } elsif (ref $text eq 'ARRAY') {
        $rc   = $text->[0];
        $text = $text->[1];
    }
    my $text_origin = $text; # Save original text string
    if ($text =~ /:/) {
        ($descr, $text) = split /:/, $text, 2;
    }
    $text =~ s/^ *//;
    $text =~ s/ *$//;
    my $msg;
    my $curptr;
    if ($node) {
        $msg->{node} = [ { name => [$node] } ];
        $curptr = $msg->{node}->[0];
    } else {
        $msg    = {};
        $curptr = $msg;
    }
    if ($rc) {
        $curptr->{errorcode} = [$rc];
        $curptr->{error}     = [$text_origin];
        $curptr              = $curptr->{error}->[0];
        if (defined $node && %allerrornodes) {
            $allerrornodes{$node} = 1;
        }
    } else {
        $curptr->{data} = [ { contents => [$text] } ];
        $curptr = $curptr->{data}->[0];
        if ($descr) { $curptr->{desc} = [$descr]; }
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

    my $depstab = xCAT::Table->new('deps');
    if (!defined($depstab)) {
        return undef;
    }

    my $depset = $depstab->getNodesAttribs($nodes, [qw(nodedep msdelay cmd)]);
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
        foreach my $depent (@{ $depset->{$node} }) {
            my @depcmd = split(/,/, $depent->{'cmd'});

            #dependency match
            if (grep(/^$cmd$/, @depcmd)) {

                #expand the noderange
                my @nodedep = xCAT::NodeRange::noderange($depent->{'nodedep'}, 1);
                my $depsnode = join(',', @nodedep);
                if ($depsnode) {
                    $depent->{'nodedep'} = $depsnode;
                    push @{ $realdep->{$node} }, $depent;
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
        for ($i = 0 ; $i < scalar(@{ $dephash->{$node} }) ; $i++) {
            foreach my $attr (keys %{ $dephash->{$node}->[$i] }) {
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
    foreach my $node (keys %{$deps}) {
        my $keepnode = 0;
        foreach my $depent (@{ $deps->{$node} }) {

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
        $callback->(\%output);
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
            $output{errorcode} = 1;
            $output{data} = ["Loop dependency, check your deps table, may be related to the following nodes: $nodesinlist"];
            $callback->(\%output);
            return 1;
        }

        # update deps for the next loop
        # remove the node from the 'nodedep' attribute
        my $keepnode = 0;
        foreach my $nodeindeps (keys %{$deps}) {
            my $keepnode = 0;
            foreach my $depent (@{ $deps->{$nodeindeps} }) {

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
    my $osver = shift;

    if ($osver =~ /^(openeuler)(20|22|24)\.(03(?:sp[1-9][0-9]*)?)$/) {
        return ($1, $2, $3);
    }

    if ($osver =~ (/(\D+)(\d*)\.*(\d*)/))
    {
        return ($1, $2, $3);
    }

    return ();
}

#-------------------------------------------------------------------------------

=head3   is_el10_os

    Returns 1 when the xCAT OS version names an Enterprise Linux 10 family
    distribution, otherwise 0.

=cut

#-------------------------------------------------------------------------------

#-----------------------------------------------------------------------------

=head3   uses_static_ipv6_boot

    Description:
        Whether the installer of this OS takes a static IPv6 address from the kernel command
        line instead of asking DHCPv6 for one.

        The firmware and the install initrd of a node send different DHCPv6 identifiers, and a
        reservation matches one. An OS whose initrd honours "ip=<ip>::<gw>:<prefix>:<host>:<if>:none"
        is given the address of the node directly, so only the firmware stage speaks DHCPv6.

    Arguments:
        osver
    Returns:
        1 when the OS takes the static address, 0 otherwise.
    Example:
        if (xCAT::SvrUtils->uses_static_ipv6_boot($osver)) { ... }

=cut

#-----------------------------------------------------------------------------
sub uses_static_ipv6_boot
{
    my $osver = shift;
    if (defined($osver) && $osver eq __PACKAGE__)
    {
        $osver = shift;
    }

    return 0 unless defined($osver);
    my ($basename, $majorversion) = xCAT::SvrUtils::parseosver($osver);
    return 0 unless defined($basename) && defined($majorversion);

    # openEuler reaches the same kickstart and dracut code as EL through #KICKSTARTNET#.
    return 1 if $basename =~ /^openeuler$/i;
    # EL 10 is where the installer gained it. A later release keeps it, so this is not an
    # equality: is_el10_os tested for 10 exactly and left EL11 on the DHCPv6 path.
    return 1
      if $basename =~ /^(?:rh\w*|centos|alma|rocky|ol)$/i
      && $majorversion =~ /^\d+$/
      && $majorversion >= 10;
    return 0;
}

sub is_el10_os
{
    my $osver = shift;
    if (defined($osver) && $osver eq __PACKAGE__)
    {
        $osver = shift;
    }

    return 0 unless defined($osver);
    my ($basename, $majorversion) = xCAT::SvrUtils::parseosver($osver);
    return defined($basename)
      && defined($majorversion)
      && $majorversion eq '10'
      && $basename =~ /^(?:rh\w*|centos|alma|rocky|ol)$/i ? 1 : 0;
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
    my $osver = shift;    #like sle11, rhel5.3
    if (($osver) && ($osver =~ /xCAT::SvrUtils/)) {
        $osver = shift;
    }
    my $arch     = shift;    #like ppc64, x86, x86_64
    my $path     = shift;
    my $distname = shift;

    my $basename     = undef;
    my $majorversion = undef;
    my $minorversion = undef;

    my %keyhash = ();
    my %updates = ();

    my $ostype = "Linux";    #like Linux, Windows
    if (($osver =~ /^win/) || ($osver =~ /^imagex/)) {
        if ($osver =~ /^win\d/) {
            $osver =~ s/^win/windows/;
        } elsif ($osver =~ /^imagex/) {
            $osver = "windows";
        }
        $ostype = "Windows";
    }
    if ($osver =~ /hyperv/) {
        $ostype = "Windows";
    }


    unless ($distname) {
        $distname = $osver . "-" . $arch;
    }

    $keyhash{osdistroname} = $distname;

    $updates{type} = $ostype;
    if ($arch) {
        $updates{arch} = $arch;
    }

    #split $osver to basename,majorversion,minorversion
    if ($osver) {
        ($updates{basename}, $updates{majorversion}, $updates{minorversion}) = &parseosver($osver);
    }


    my $tab = xCAT::Table->new('osdistro', -create => 1);

    unless ($tab)
    {
        return (1, "failed to open table 'osdistro'!");
    }

    if ($path)
    {
        $path =~ s/\/+$//;
        (my $ref) = $tab->getAttribs(\%keyhash, 'dirpaths');
        if ($ref and $ref->{dirpaths})
        {
            #if $path does not exits in "dirpaths" of osdistro,append the $path delimited with a ",";otherwise keep the original value
            unless ($ref->{dirpaths} =~ /^($path)\/*,|,($path)\/*,|,($path)\/*$|^($path)\/*$/)
            {
                $updates{dirpaths} = $ref->{dirpaths} . ',' . $path;
            }
        } else
        {
            $updates{dirpaths} = $path;
        }
    }


    if (%updates)
    {
        $tab->setAttribs(\%keyhash, \%updates);
        $tab->commit;
    }
    $tab->close;

    return (0, "osdistro $distname update success");


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
    my %node_postbootscript    = ();
    my %osimage_postbootscript = ();



    # get the profile attributes for the nodes
    my $nodetype_t = xCAT::Table->new('nodetype');
    unless ($nodetype_t) {
        return;
    }
    my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['provmethod']);
    my @osimages;
    my $osimage_t = xCAT::Table->new('osimage');
    unless ($osimage_t) {
        return;
    }
    foreach my $node (@$nodes) {
        my $provmethod = $nodetype_v->{$node}->[0]->{'provmethod'};
        if (($provmethod) && ($provmethod ne "install") && ($provmethod ne "netboot") && ($provmethod ne "statelite")) {

            # then get the postbootscripts from the osimage
            my $postbootscripts = $osimage_t->getAttribs({ imagename => $provmethod }, 'postbootscripts');
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
    my $os = shift;    #like sles11.1, rhels6.3
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
    elsif ($os =~ /alma.*/)
    {
        $platform = "alma";
    }
    elsif ($os =~ /rocky.*/)
    {
        $platform = "rocky";
    }
    elsif ($os =~ /^openeuler/)
    {
        $platform = "openeuler";
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
    elsif ($os =~ /ubuntu.*/) {
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

# Parse statelite NFS root options once so command-time validation and the
# dracut root=nfs renderer enforce the same rules.
sub _parse_statelite_nfsroot_options {
    my ($additional_options) = @_;

    my @mount_options;
    if (defined($additional_options) && $additional_options ne '') {
        foreach my $option (split(/,/, $additional_options, -1)) {
            if ($option eq '' || $option =~ /\s/) {
                return (undef, 'nfsrootopts must be a comma-separated list without whitespace or empty options');
            }

            my ($name) = split(/=/, $option, 2);
            $name = lc($name);
            if ($name eq 'rw' || $name eq 'defaults') {
                return (undef, "nfsrootopts cannot contain '$name'; statelite NFS roots are always read-only");
            }
            next if lc($option) eq 'ro';
            push @mount_options, $option;
        }
    }

    return (\@mount_options, undef);
}

# Return an error message when statelite NFS root options violate the
# read-only root filesystem contract.
sub validate_statelite_nfsroot_options {
    shift if @_ && defined($_[0]) && $_[0] eq __PACKAGE__;
    my ($additional_options) = @_;

    my ($mount_options, $error) = _parse_statelite_nfsroot_options($additional_options);
    return $error;
}

# Build the dracut root=nfs parameter while preserving statelite's read-only
# root filesystem contract.
sub build_statelite_nfsroot_parameter {
    shift if @_ && defined($_[0]) && $_[0] eq __PACKAGE__;
    my ($server, $rootdir, $additional_options) = @_;

    my ($additional_mount_options, $error) = _parse_statelite_nfsroot_options($additional_options);
    return (undef, $error) if $error;

    my @mount_options = ('ro', @{$additional_mount_options});
    return ('root=nfs:' . $server . ':' . $rootdir . ':' . join(',', @mount_options), undef);
}

#--------------------------------------------------------------------------------------------------------
#searchcompressedrootimg:
#description: search the compressed rootimage for diskless or statelite osimage under specified directory
#argument:
#        $rootimgdir: the directory in which the compressed rootimage exist
#return:
#        on success: the basename of the compressed rootimage
#        on fail:    undef
#--------------------------------------------------------------------------------------------------------
sub searchcompressedrootimg{
    my $rootimgdir = shift;
    if (($rootimgdir) && ($rootimgdir =~ /xCAT::SvrUtils/)) {
        $rootimgdir = shift;
    }

    my $cpsdrootimg=undef;
    if (-f -r "$rootimgdir/rootimg.sfs"){
        $cpsdrootimg="rootimg.sfs";
    }elsif(-f -r "$rootimgdir/rootimg.gz"){
        $cpsdrootimg="rootimg.gz";
    }

    if(-f -r "$rootimgdir/rootimg.cpio.gz"){
        $cpsdrootimg = 'rootimg.cpio.gz';
    }elsif(-f -r "$rootimgdir/rootimg.cpio.xz"){
        $cpsdrootimg = 'rootimg.cpio.xz';
    }elsif(-f -r "$rootimgdir/rootimg.tar.gz"){
        $cpsdrootimg = 'rootimg.tar.gz';
    }elsif(-f -r "$rootimgdir/rootimg.tar.xz"){
        $cpsdrootimg = 'rootimg.tar.xz';
    }

    return $cpsdrootimg;
}

# Publication holds its lock briefly, so a writer that waits this long fails instead of taking the lock over.
my $publish_lock_wait = 60;

sub _rootimg_stage_prefix {
    (my $host = Sys::Hostname::hostname()) =~ s/[^A-Za-z0-9.-]/_/gx;
    return ".packimage-$host+";
}

#--------------------------------------------------------------------------------------------------------
#remove_abandoned_rootimg_stages:
#description: remove the private directories that writers on this host abandoned in an image directory.
#             A directory that keeps the previous files of a failed publication stays.
#             Hold the image lock while you call it.
#argument:
#        $dir: the image directory
#        $all: true to remove also the directories that keep previous files, as rmimage does
#--------------------------------------------------------------------------------------------------------
sub remove_abandoned_rootimg_stages {
    my (undef, $dir, $all) = @_;

    # The image lock is per host, so only this host's directories are known to be abandoned.
    my $prefix = _rootimg_stage_prefix();
    my @abandoned = grep { $all || !_holds_previous($_) } __PACKAGE__->image_dir_entries($dir, qr/\A\Q$prefix\E.{8}\z/sx);
    rmtree(\@abandoned) if @abandoned;
    return;
}

#--------------------------------------------------------------------------------------------------------
#image_dir_entries:
#description: list the entries of an image directory whose names match a pattern. Unlike glob, it takes the
#             directory literally, also when its path has a space or a wildcard character.
#arguments:
#        $dir:     the image directory
#        $pattern: a regular expression for the names of the entries
#return:
#        the paths of the matching entries, sorted
#--------------------------------------------------------------------------------------------------------
sub image_dir_entries {
    my (undef, $dir, $pattern) = @_;
    opendir(my $handle, $dir) or return;
    my @names = sort grep { $_ =~ $pattern } readdir($handle);
    closedir($handle);
    return map { "$dir/$_" } @names;
}

# Returns whether the staging directory $stage keeps previous files of a failed publication.
sub _holds_previous {
    my ($stage) = @_;
    return grep { -e "$stage/$_" || -l "$stage/$_" } qw(previous previous.metainfo);
}

# The staging directories that rootimg_stage created in this process, so that a publication can keep one.
my %rootimg_stages;

#--------------------------------------------------------------------------------------------------------
#rootimg_stage:
#description: create a private directory in an image directory for a new compressed rootimage, and remove
#             the directories that writers on this host abandoned. Hold the image lock while you call it.
#argument:
#        $dir: the image directory
#return:
#        on success: a File::Temp directory object, which removes the directory when it goes out of scope
#        on fail:    undef and the error message
#--------------------------------------------------------------------------------------------------------
sub rootimg_stage {
    my ($class, $dir) = @_;
    $class->remove_abandoned_rootimg_stages($dir);
    my $stage = eval { File::Temp->newdir(_rootimg_stage_prefix() . 'XXXXXXXX', DIR => $dir) };
    return (undef, "Cannot create a temporary directory in $dir: $@") if !$stage;
    $rootimg_stages{ $stage->dirname } = $stage;
    Scalar::Util::weaken($rootimg_stages{ $stage->dirname });
    return ($stage);
}

#--------------------------------------------------------------------------------------------------------
#write_rootimg_checksum:
#description: write the SHA-256 checksum of a compressed rootimage to <rootimage>.sha256 in sha256sum format
#argument:
#        $rootimg: the path of the compressed rootimage
#return:
#        on success: nothing
#        on fail:    the error message
#--------------------------------------------------------------------------------------------------------
sub write_rootimg_checksum {
    my (undef, $rootimg) = @_;
    my ($line, $error) = _rootimg_checksum_line($rootimg);
    return $error if $error;
    return _write_published_file("$rootimg.sha256", $line);
}

# Returns the sha256sum line of a compressed rootimage, or undef and the error message.
sub _rootimg_checksum_line {
    my ($rootimg) = @_;
    my $digest = eval { Digest::SHA->new(256)->addfile($rootimg)->hexdigest }
      or return (undef, "Cannot compute the SHA-256 checksum of $rootimg: $@");
    return ("$digest  " . basename($rootimg) . "\n");
}

#--------------------------------------------------------------------------------------------------------
#rootimg_checksum_enabled:
#description: tell whether nodes must check the compressed rootimage of an image against its checksum
#argument:
#        $value: the rootimgchecksum attribute of the image, or undef
#return:
#        false when the image, or site.rootimgchecksum if the image does not set it, is 'no' or '0'
#--------------------------------------------------------------------------------------------------------
sub rootimg_checksum_enabled {
    my (undef, $value) = @_;
    ($value) = xCAT::TableUtils->get_site_attribute('rootimgchecksum') if !defined($value) || $value eq '';
    return !(defined($value) && $value =~ /^\s*(?:no|0)\s*$/ix);
}

#--------------------------------------------------------------------------------------------------------
#rootimg_transport:
#description: tell how the nodes of an image get the compressed rootimage at boot
#argument:
#        $value: the rootimgtransport attribute of the image, or undef
#return:
#        'http' or 'uftp', from the image or, if the image does not set it, from site.rootimgtransport,
#        or undef and the error message for another value. Call it in list context.
#--------------------------------------------------------------------------------------------------------
sub rootimg_transport {
    my (undef, $value) = @_;
    my $source = 'The rootimgtransport attribute of the image';
    if (!defined($value) || $value !~ /\S/x) {
        ($value) = xCAT::TableUtils->get_site_attribute('rootimgtransport');
        $source = 'site.rootimgtransport';
    }
    return 'http' if !defined($value) || $value !~ /\S/x;
    my $transport = lc($value =~ s/^\s+|\s+$//grx);
    return $transport if $transport eq 'http' || $transport eq 'uftp';
    return (undef, "$source is '$value', but only http and uftp are supported.");
}

#--------------------------------------------------------------------------------------------------------
#upgrade_rootimg_checksum:
#description: on an upgrade from a release without the root image check, keep the stateless and statelite
#             ramdisk images of that release unchecked, and give new images the check. While
#             site.rootimgchecksum is not set, set the rootimgchecksum attribute to no for each such image
#             that does not set it, then set site.rootimgchecksum to yes. A later upgrade changes nothing.
#return:
#        nothing, or the error message
#--------------------------------------------------------------------------------------------------------
sub upgrade_rootimg_checksum {
    my ($class) = @_;
    my $sitetab = xCAT::Table->new('site', -create => 1) or return 'Cannot open the site table';
    my ($site) = $sitetab->getAttribs({ key => 'rootimgchecksum' }, 'value');
    return if $site && defined($site->{value}) && $site->{value} ne '';
    my $osimagetab    = xCAT::Table->new('osimage',    -create => 1) or return 'Cannot open the osimage table';
    my $linuximagetab = xCAT::Table->new('linuximage', -create => 1) or return 'Cannot open the linuximage table';
    my %decided = map { ($_->{imagename} => 1) } grep { defined($_->{rootimgchecksum}) && $_->{rootimgchecksum} ne '' }
      $linuximagetab->getAllAttribs('imagename', 'rootimgchecksum');
    foreach my $image ($osimagetab->getAllAttribs('imagename', 'provmethod')) {
        next if $decided{ $image->{imagename} } || ($image->{provmethod} // '') !~ /^(?:netboot|statelite)$/x;
        my (undef, $image_error) = $linuximagetab->setAttribs({ imagename => $image->{imagename} }, { rootimgchecksum => 'no' });
        return "Cannot turn the root image check off for $image->{imagename}: $image_error" if $image_error;
    }
    my (undef, $site_error) = $sitetab->setAttribs({ key => 'rootimgchecksum' }, { value => 'yes' });
    return $site_error ? "Cannot set site.rootimgchecksum: $site_error" : undef;
}

#--------------------------------------------------------------------------------------------------------
#write_initrd_check_marker:
#description: record that an initial ramdisk checks the compressed rootimage against its checksum.
#             The marker holds the SHA-256 of the initial ramdisk, so a replaced ramdisk does not match it.
#argument:
#        $initrd: the path of the initial ramdisk
#return:
#        on success: nothing
#        on fail:    the error message
#--------------------------------------------------------------------------------------------------------
sub write_initrd_check_marker {
    my (undef, $initrd) = @_;
    my $digest = eval { Digest::SHA->new(256)->addfile($initrd)->hexdigest }
      or return "Cannot compute the SHA-256 checksum of $initrd: $@";
    return _write_published_file("$initrd.rootimgcheck", "sha256=$digest\n");
}

#--------------------------------------------------------------------------------------------------------
#initrd_checks_rootimg:
#description: tell whether genimage built an initial ramdisk that checks the compressed rootimage
#arguments:
#        $initrd: the path of the initial ramdisk, or of a copy of it
#        $marker: the marker that genimage wrote, by default <initrd>.rootimgcheck
#return:
#        true when the marker holds the SHA-256 of the initial ramdisk
#--------------------------------------------------------------------------------------------------------
sub initrd_checks_rootimg {
    my (undef, $initrd, $marker_path) = @_;
    open(my $marker, '<', $marker_path // "$initrd.rootimgcheck") or return 0;
    my $line = <$marker> // '';
    close($marker);
    my ($recorded) = $line =~ /^sha256=([0-9a-f]{64})$/x or return 0;
    my $digest = eval { Digest::SHA->new(256)->addfile($initrd)->hexdigest } or return 0;
    return $digest eq $recorded;
}

#--------------------------------------------------------------------------------------------------------
#prepare_rootimg_checksum:
#description: write the missing checksums of an image before nodeset copies its boot files. With the check
#             turned off, a checksum that cannot be written is a warning instead of an error.
#arguments (by name):
#        value:      the rootimgchecksum attribute of the image, or undef
#        rootimgdir: the image directory
#        imagename:  the image name, for the messages
#        warned:     a hash of the image directories that already got a warning
#        callback:   the request callback
#return:
#        nothing, or the error that keeps nodeset from setting up the node
#--------------------------------------------------------------------------------------------------------
sub prepare_rootimg_checksum {
    my ($class, %args) = @_;
    my $rootimgdir = $args{rootimgdir};
    my $imagename  = $args{imagename} || $rootimgdir;

    # A node whose boot entry nodeset wrote while the check was on still checks, so every archive gets a checksum.
    my $error = $class->publish_missing_rootimg_checksums($rootimgdir) or return;
    $error =~ s/\.$//x;
    if (!$class->rootimg_checksum_enabled($args{value})) {
        $args{callback}->({ warning => [ "$error. Nodes of $imagename whose boot entries still ask for the check "
                  . "download the root image again until nodeset runs for them." ] }) unless $args{warned}{$rootimgdir}++;
        return;
    }
    return "The root image of $imagename has no checksum that its initial ramdisk can check: $error. "
      . "Run packimage for the image, then nodeset.";
}

#--------------------------------------------------------------------------------------------------------
#rootimg_checksum_boot:
#description: decide how a node checks the compressed rootimage that it downloads at boot, and warn once
#             for each image whose initial ramdisk has no matching marker
#arguments (by name):
#        value:      the rootimgchecksum attribute of the image, or undef
#        rootimgdir: the image directory
#        initrd:     the initial ramdisk that nodes boot, as nodeset left it in TFTP
#        imagename:  the image name, for the messages
#        warned:     a hash of the image directories that already got a warning
#        callback:   the request callback
#return:
#        the kernel argument that asks the node to check, or an empty string when the check is off
#--------------------------------------------------------------------------------------------------------
my %initrd_checks;
sub rootimg_checksum_boot {
    my ($class, %args) = @_;
    return '' unless $class->rootimg_checksum_enabled($args{value});
    my ($rootimgdir, $initrd) = @args{qw(rootimgdir initrd)};
    my $imagename = $args{imagename} || $rootimgdir;

    # The copy in TFTP checks only when it matches the marker that genimage wrote in the image directory.
    my $marker = "$rootimgdir/" . basename($initrd) . '.rootimgcheck';

    # nodeset runs this for every node, so each version of the initial ramdisk and its marker is hashed once.
    my @version = map { (stat($_))[ 0, 1, 7, 9 ] } ($initrd, $marker);
    my $key = join(':', $initrd, map { $_ // '' } @version);
    $initrd_checks{$key} //= $class->initrd_checks_rootimg($initrd, $marker) ? 1 : 0;
    $args{callback}->({ warning => [ "Cannot tell whether the initial ramdisk $initrd checks the root image checksum, so "
              . "nodes may boot the root image of $imagename unchecked. Run genimage for the image and then nodeset, or "
              . "set its rootimgchecksum attribute to no." ] }) unless $initrd_checks{$key} || $args{warned}{$rootimgdir}++;
    return 'rootimgchecksum=yes ';
}

# Returns the content of a file, or undef when it cannot be read.
sub _read_published_file {
    my ($path) = @_;
    open(my $file, '<', $path) or return;
    local $/ = undef;
    my $content = <$file>;
    close($file);
    return $content;
}

# A rename publishes the file, so no reader sees it partial.
sub _write_published_file {
    my ($path, $content) = @_;
    my $temp = "$path.$$";
    my $written;
    if (open(my $file, '>', $temp)) {
        $written = print($file $content) && close($file);
    }
    unless ($written && chmod(0644, $temp) && rename($temp, $path)) {
        my $error = $!;
        unlink($temp);
        return "Cannot write $path: $error";
    }
    return;
}

#--------------------------------------------------------------------------------------------------------
#publish_rootimg:
#description: replace a published compressed rootimage, its checksum and its metainfo with staged files.
#             Nodes keep downloading the previous rootimage until the rename replaces it. When the
#             publication fails, the previous files stay as they were.
#argument:
#        $staged:        the staged compressed rootimage, with <staged>.sha256 and <staged>.metainfo when they exist
#        $target:        the published path
#        $remove_others: true to remove the other rootimg.* files of the image directory
#        $held:          the publication lock from lock_rootimg_publication, when the caller holds it
#return:
#        on success: nothing
#        on fail:    the error message
#--------------------------------------------------------------------------------------------------------
sub publish_rootimg {
    my ($class, $staged, $target, $remove_others, $held) = @_;
    my $dir = dirname($target);
    my ($lock, $lock_error) = $held ? ($held) : _acquire_publish_lock($dir);
    return $lock_error unless $lock;
    my %state = (staged => $staged, target => $target, previous => dirname($staged) . '/previous',
        sums => _read_published_file("$target.sha256"));
    my $error = _replace_rootimg(\%state);
    if (defined($error)) {
        my $restore_error = _restore_rootimg(\%state);
        $error .= ", and $restore_error" if $restore_error;
    } else {
        # A checksum file that keeps the previous line still matches the new archive, so this rename may fail.
        rename("$staged.sha256", "$target.sha256") if -e "$staged.sha256";
        if ($remove_others) {
            # A node that already downloads another format checks it after the download, so the checksums stay.
            my %kept = map { ($_ => 1) } ($target, "$target.metainfo");
            unlink grep { !$kept{$_} && !/\.sha256$/x } $class->image_dir_entries($dir, qr/\Arootimg\./x);
        }
    }

    # Afterwards, only a staging directory that keeps previous files for a failed publication holds them.
    unlink(grep { -e $_ || -l $_ } map { "$state{previous}$_" } ('', '.metainfo', '.sha256')) if !$state{retained};
    _release_publish_lock($lock) if !$held;
    return if !defined($error);
    return "Cannot publish $target: $error";
}

#--------------------------------------------------------------------------------------------------------
#unpublish_rootimg:
#description: remove a published compressed rootimage with its checksum and metainfo
#arguments:
#        $target: the published path
#        $held:   the publication lock from lock_rootimg_publication, when the caller holds it
#return:
#        on success: nothing
#        on fail:    the error message
#--------------------------------------------------------------------------------------------------------
sub unpublish_rootimg {
    my ($class, $target, $held) = @_;
    my ($lock, $error) = $held ? ($held) : _acquire_publish_lock(dirname($target));
    return $error unless $lock;
    my @files = grep { -e $_ || -l $_ } ($target, "$target.sha256", "$target.metainfo");
    $error = "Cannot remove $target: $!" if unlink(@files) != @files;
    _release_publish_lock($lock) if !$held;
    return $error;
}

#--------------------------------------------------------------------------------------------------------
#lock_rootimg_publication:
#description: take the publication lock of an image directory. packimage and imgimport on every host take
#             it before they publish a compressed rootimage there.
#argument:
#        $dir: the image directory
#return:
#        on success: the lock, for publish_rootimg, unpublish_rootimg and unlock_rootimg_publication
#        on fail:    undef and the error message
#--------------------------------------------------------------------------------------------------------
sub lock_rootimg_publication {
    my (undef, $dir) = @_;
    return _acquire_publish_lock($dir);
}

sub unlock_rootimg_publication {
    my (undef, $lock) = @_;
    return _release_publish_lock($lock);
}

# Keeps $from at $to through a hard link, or through a copy with the mode of $from, which nodes need to read it.
sub _keep_copy {
    my ($from, $to) = @_;
    return 1 if link($from, $to);
    my $mode = (stat($from))[2];
    return File::Copy::copy($from, $to) && defined($mode) && chmod(Fcntl::S_IMODE($mode), $to);
}

# Replaces the published archive and its metainfo with the staged files, and records in $state what changed.
sub _replace_rootimg {
    my ($state) = @_;
    my ($staged, $target, $previous) = @$state{qw(staged target previous)};
    my @files = ($staged, grep { -e $_ } map { "$staged.$_" } qw(sha256 metainfo));
    $state->{first} = !-e $target && !-l $target;

    # A failed publication puts the previous archive back from a link, or from a copy without hard links.
    return "$!" if -e $target && !_keep_copy($target, $previous);
    return "$!" if !-s $staged || chmod(0644, @files) != @files;
    my $error = _replace_sums($state);
    return $error if $error;

    # The previous metainfo leaves first, so it never describes the new archive.
    if (-e "$target.metainfo") {
        $state->{metainfo_moved} = rename("$target.metainfo", "$previous.metainfo") or return "$!";
    }
    $state->{replaced} = rename($staged, $target) or return "$!";
    return "$!" if -e "$staged.metainfo" && !rename("$staged.metainfo", "$target.metainfo");
    return;
}

# Writes the checksum file of the publication in $state for the time that the archive is replaced, and returns
# why it cannot.
sub _replace_sums {
    my ($state) = @_;
    my ($staged, $target, $previous) = @$state{qw(staged target previous)};

    # A rollback renames the previous checksum entry back, so a symlink stays a symlink.
    $state->{sums_entry} = (-e "$target.sha256" || -l "$target.sha256") && link("$target.sha256", "$previous.sha256");

    # Until the archive is replaced, the checksum file lists the new and the previous archive, so the published
    # archive matches a line of it, also when the publisher is killed.
    if (-e "$staged.sha256") {
        # An archive packed without a checksum stays published until the rename, so the list needs its line too.
        my ($previous_line, $error) = ($state->{sums});
        ($previous_line, $error) = _rootimg_checksum_line($target) if !defined($previous_line) && -e $target;
        return $error if $error;
        $state->{sums_changed} = 1;
        return _write_published_file("$target.sha256", _read_published_file("$staged.sha256") . ($previous_line // ''));
    }
    if (defined($state->{sums})) {
        $state->{sums_changed} = 1;
        unlink("$target.sha256") or return "$!";
    }
    return;
}

# Moves the previous files that staging holds, the previous archive with each of @suffixes, to a new directory
# next to the target, because staging cleanup would delete them. Staging that keeps a file that cannot move
# stays. Returns the directories that keep the files.
sub _keep_previous {
    my ($state, @suffixes) = @_;
    my ($target, $previous) = @$state{qw(target previous)};
    my $kept = eval { File::Temp::tempdir('.rootimg-previous-XXXXXXXX', DIR => dirname($target)) };
    my $name = basename($target);
    my ($moved, $stuck) = (0, 0);
    foreach my $suffix (grep { -e "$previous$_" || -l "$previous$_" } @suffixes) {
        if ($kept && rename("$previous$suffix", "$kept/$name$suffix")) {
            $moved++;
        } else {
            $stuck++;
        }
    }
    rmdir($kept) if $kept && !$moved;
    return (($moved ? $kept : ()), ($stuck ? _retain_stage($state) : ()));
}

# Keeps the staging directory of the publication in $state, also when its owner drops it, and returns it.
sub _retain_stage {
    my ($state) = @_;
    my $stage = dirname($state->{previous});
    $rootimg_stages{$stage}->unlink_on_destroy(0) if $rootimg_stages{$stage};
    $state->{retained} = 1;
    return $stage;
}

# Puts back the previous files that _replace_rootimg changed, or returns why it cannot.
sub _restore_rootimg {
    my ($state) = @_;
    my ($target, $previous) = @$state{qw(target previous)};
    if ($state->{replaced} && $state->{first}) {

        # No archive was published before, so the new one leaves again.
        unlink($target) or return "the new archive cannot be removed: $!";
    } elsif ($state->{replaced} && !rename($previous, $target)) {
        my $error = "$!";
        my @kept  = _keep_previous($state, '', '.metainfo');
        return "the previous archive cannot be put back: $error, nor kept" if !@kept;
        my $archive = "$kept[0]/" . basename($target);
        _write_published_file("$archive.sha256", $state->{sums}) if defined($state->{sums}) && -e $archive;
        return "the previous archive cannot be put back: $error. It is kept in " . join(' and ', @kept);
    }
    my @errors;
    if ($state->{metainfo_moved} && !rename("$previous.metainfo", "$target.metainfo")) {
        my $error = "$!";
        my @kept  = _keep_previous($state, '.metainfo');
        push @errors, "the previous metainfo cannot be put back: $error" . (@kept ? '. It is kept in ' . join(' and ', @kept) : ', nor kept');
    }
    if ($state->{sums_changed}) {
        my $error = _restore_sums($state);
        push @errors, "the previous checksum cannot be put back: $error" if $error;
    }
    return @errors ? join(', and ', @errors) : undef;
}

# Puts back the previous checksum file of the publication in $state, or returns why it cannot. The kept entry goes
# back as it was, also a symlink. Otherwise the previous content goes back, so that nodes can check the archive.
sub _restore_sums {
    my ($state) = @_;
    my ($target, $previous) = @$state{qw(target previous)};
    return if $state->{sums_entry} && rename("$previous.sha256", "$target.sha256");
    my $entry_error = $state->{sums_entry} ? "$!" : undef;
    my $error = defined($state->{sums}) ? _write_published_file("$target.sha256", $state->{sums})
      : (-e "$target.sha256" && !unlink("$target.sha256")) ? "Cannot remove $target.sha256: $!" : undef;
    return $error if $error;
    return defined($entry_error) ? "$entry_error. Its previous content went back instead" : undef;
}

#--------------------------------------------------------------------------------------------------------
#publish_missing_rootimg_checksums:
#description: write the checksum of each published compressed rootimage of an image directory that has
#             none. An initial ramdisk that checks the rootimage refuses an image packed before the check.
#argument:
#        $dir: the image directory
#return:
#        on success: nothing
#        on fail:    the error message
#--------------------------------------------------------------------------------------------------------
sub publish_missing_rootimg_checksums {
    my ($class, $dir) = @_;
    my @formats = qw(rootimg.gz rootimg.cpio.gz rootimg.cpio.xz rootimg.tar.gz rootimg.tar.xz rootimg.sfs rootimg-statelite.gz);
    my $missing = sub { grep { -f "$dir/$_" && !-e "$dir/$_.sha256" } @formats };
    my @missing = $missing->();
    return if !@missing;

    # The lock keeps packimage from replacing an archive while this checksum is computed.
    my ($lock, $error) = _acquire_publish_lock($dir);
    return $error unless $lock;
    foreach my $file ($missing->()) {
        $error = $class->write_rootimg_checksum("$dir/$file");
        last if $error;
    }
    _release_publish_lock($lock);
    return $error;
}

# The image lock is per host, and mkdir is atomic for every host, also on NFS without locks.
sub _acquire_publish_lock {
    my ($dir) = @_;
    my $lock = "$dir/.packimage-publish";
    for (my $waited = 0; !mkdir($lock); $waited++) {
        return (undef, "Cannot create $lock: $!") unless $! == EEXIST;
        my $age = time() - ((stat($lock))[9] // time());
        if ($waited >= $publish_lock_wait || $age > $publish_lock_wait) {
            my $holder = '';
            if (open(my $owner, '<', "$lock/owner")) {
                $holder = <$owner> // '';
                close($owner);
                chomp($holder);
                $holder = " by $holder" if $holder;
            }
            return (undef, "$lock is held$holder. If no packimage or imgimport of this image runs on any host, "
                  . "remove it and run the command again.");
        }
        sleep 1;
    }
    if (open(my $owner, '>', "$lock/owner")) {
        print $owner Sys::Hostname::hostname() . " $$\n";
        close($owner);
    }
    return ($lock);
}

sub _release_publish_lock {
    my ($lock) = @_;
    unlink("$lock/owner");
    rmdir($lock);
    return;
}



#-----------------------------------------------------------------------------

=head3 named_service_action

    Which service action brings a freshly written named configuration into effect.

    Linux gets a restart. On Debian the package already runs named, so a start is a no-op and
    the daemon keeps serving the configuration it read at install time.

    Arguments: the platform, 'aix' or 'linux'
    Returns: 'start', 'restart', or '' for a platform with no action

=cut

#-----------------------------------------------------------------------------
sub named_service_action {
    my ($platform) = @_;
    $platform = '' unless defined $platform;
    return 'start'   if $platform eq 'aix';
    return 'restart' if $platform eq 'linux';
    return '';
}


1;
