# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Postage;

BEGIN
{
    $::XCATROOT =
        $ENV{'XCATROOT'} ? $ENV{'XCATROOT'}
      : -d '/opt/xcat'   ? '/opt/xcat'
      : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::NodeRange;
use xCAT::Utils;
use xCAT::SvrUtils;
use Data::Dumper;
use File::Basename;
use Socket;
use strict;

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

sub writescript
{
    if (scalar(@_) eq 5) { shift; }    #Discard self
    my $node         = shift;
    my $scriptfile   = shift;
    my $nodesetstate = shift;          # install or netboot
    my $callback     = shift;
    my $rsp;
    my $requires;
    my $script;
    open($script, ">", $scriptfile);

    unless ($scriptfile)
    {
        my %rsp;
        push @{$rsp->{data}}, "Could not open $scriptfile for writing.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #Some common variables...
    my @scriptcontents = makescript($node, $nodesetstate, $callback);
    if (!defined(@scriptcontents))
    {
        my %rsp;
        push @{$rsp->{data}},
          "Could not create node post script file for node \'$node\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    else
    {
        foreach (@scriptcontents)
        {
            print $script $_;
        }
    }
    close($script);
    chmod 0755, $scriptfile;
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
sub makescript
{
    my $node         = shift;
    my $nodesetstate = shift;    # install or netboot
    my $callback     = shift;

    my @scriptd;
    my ($master, $ps, $os, $arch, $profile);

    my $noderestab = xCAT::Table->new('noderes');
    my $typetab    = xCAT::Table->new('nodetype');
    my $posttab    = xCAT::Table->new('postscripts');
    my $sitetab    = xCAT::Table->new('site');
    my $ostab    = xCAT::Table->new('osimage');

    my %rsp;
    my $rsp;
    my $master;
    unless ($sitetab and $noderestab and $typetab and $posttab)
    {
        push @{$rsp->{data}},
          "Unable to open site or noderes or nodetype or postscripts table";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;

    }
    unless ($ostab){
        push @{$rsp->{data}},
          "Unable to open osimage table";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    # read all attributes for the site table and write an export
    # for them in the post install file
    my $recs = $sitetab->getAllEntries();
    my $attribute;
    my $value;
    my $masterset = 0;
    foreach (@$recs)    # export the attribute
    {
        $attribute = $_->{key};
        $attribute =~ tr/a-z/A-Z/;
        $value = $_->{value};
        if ($attribute eq "MASTER")
        {
            $masterset = 1;
            push @scriptd, "SITEMASTER=" . $value . "\n";
            push @scriptd, "export SITEMASTER\n";

            # if node has service node as master then override site master
            my $et = $noderestab->getNodeAttribs($node, ['xcatmaster']);
            if ($et and defined($et->{'xcatmaster'}))
            {
                $value = $et->{'xcatmaster'};
            }
            else
            {
                my $sitemaster_value = $value;
                $value = xCAT::Utils->my_ip_facing($node);
                if ($value eq "0")
                {
                    $value = $sitemaster_value;
                }
            }
            push @scriptd, "$attribute=" . $value . "\n";
            push @scriptd, "export $attribute\n";

        }
        else
        {    # not Master attribute
            push @scriptd, "$attribute='" . $value . "'\n";
            push @scriptd, "export $attribute\n";
        }
    }    # end site table attributes
         # read the sshbetweennodes attribute and process
    my $enablessh=xCAT::Utils->enablessh($node); 
    if ($enablessh == 1) {
        push @scriptd, "ENABLESSHBETWEENNODES=YES\n";
        push @scriptd, "export ENABLESSHBETWEENNODES\n";
    } else {
        push @scriptd, "ENABLESSHBETWEENNODES=NO\n";
        push @scriptd, "export ENABLESSHBETWEENNODES\n";
    }      

    if ($masterset == 0)
    {
        my %rsp;
        push @{$rsp->{data}}, "Unable to identify master for $node.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;

    }

    push @scriptd, "NODE=$node\n";
    push @scriptd, "export NODE\n";

    my $et =
      $typetab->getNodeAttribs($node, ['os', 'arch', 'profile', 'provmethod']);
    if ($^O =~ /^linux/i)
    {
        unless ($et and $et->{'os'} and $et->{'arch'})
        {
            my %rsp;
            push @{$rsp->{data}},
              "No os or arch setting in nodetype table for $node.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return undef;
        }
    }

    my $noderesent =
      $noderestab->getNodeAttribs($node,
                                  ['nfsserver', 'installnic', 'primarynic']);
    if ($noderesent and defined($noderesent->{'nfsserver'}))
    {
        push @scriptd, "NFSSERVER=" . $noderesent->{'nfsserver'} . "\n";
        push @scriptd, "export NFSSERVER\n";
    }
    if ($noderesent and defined($noderesent->{'installnic'}))
    {
        push @scriptd, "INSTALLNIC=" . $noderesent->{'installnic'} . "\n";
        push @scriptd, "export INSTALLNIC\n";
    }
    if ($noderesent and defined($noderesent->{'primarynic'}))
    {
        push @scriptd, "PRIMARYNIC=" . $noderesent->{'primarynic'} . "\n";
        push @scriptd, "export PRIMARYNIC\n";
    }

    my $os;
    my $profile;
    my $arch;
    my $provmethod = $et->{'provmethod'};
    if ($et->{'os'})
    {
        $os = $et->{'os'};
        push @scriptd, "OSVER=" . $et->{'os'} . "\n";
        push @scriptd, "export OSVER\n";
    }
    if ($et->{'arch'})
    {
        $arch = $et->{'arch'};
        push @scriptd, "ARCH=" . $et->{'arch'} . "\n";
        push @scriptd, "export ARCH\n";
    }
    if ($et->{'profile'})
    {
        $profile = $et->{'profile'};
        push @scriptd, "PROFILE=" . $et->{'profile'} . "\n";
        push @scriptd, "export PROFILE\n";
    }
    push @scriptd, 'PATH=`dirname $0`:$PATH' . "\n";
    push @scriptd, "export PATH\n";
    my $sent = $sitetab->getAttribs({key => 'svloglocal'}, 'value');
    if ($sent and defined($sent->{value}))
    {
        push @scriptd, "SVLOGLOCAL=" . $sent->{'value'} . "\n";
        push @scriptd, "export SVLOGLOCAL\n";
    }

    # add the root passwd, if any, for AIX nodes
    # get it from the system/root entry in the passwd table
    # !!!!!  it must be an unencrypted value for AIX!!!!
    # - user will have to reset if this is a security issue
    $os =~ s/\s*$//;
    $os =~ tr/A-Z/a-z/;    # Convert to lowercase
    if ($os eq "aix")
    {
        my $passwdtab = xCAT::Table->new('passwd');
        unless ($passwdtab)
        {
            my $rsp;
            push @{$rsp->{data}}, "Unable to open passwd table.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }

        if ($passwdtab)
        {
            my $et =
              $passwdtab->getAttribs({key => 'system', username => 'root'},
                                     'password', 'cryptmethod');
            if ($et and defined($et->{'password'}))
            {
                push @scriptd, "ROOTPW=" . $et->{'password'} . "\n";
                push @scriptd, "export ROOTPW\n";
            }
            if ($et and defined($et->{'cryptmethod'}))
            {
                push @scriptd, "CRYPTMETHOD=" . $et->{'cryptmethod'} . "\n";
                push @scriptd, "export CRYPTMETHOD\n";
            }
        }
    }

    if (!$nodesetstate) { $nodesetstate = getnodesetstate($node); }
    push @scriptd, "NODESETSTATE='" . $nodesetstate . "'\n";
    push @scriptd, "export NODESETSTATE\n";

    # set the UPDATENODE flag in the script, the default it 0, that means not in the updatenode process, xcatdsklspost and xcataixpost will set it to 1 in updatenode case
    push @scriptd, "UPDATENODE=0\n";
    push @scriptd, "export UPDATENODE\n";

    # see if this is a service or compute node?
    if (xCAT::Utils->isSN($node))
    {
        push @scriptd, "NTYPE=service\n";
    }
    else
    {
        push @scriptd, "NTYPE=compute\n";
    }
    push @scriptd, "export NTYPE\n";

    my $mactab = xCAT::Table->new("mac", -create => 0);
    my $tmp = $mactab->getNodeAttribs($node, ['mac']);
    if (defined($tmp) && ($tmp))
    {
        my $mac = $tmp->{mac};
        push @scriptd, "MACADDRESS='" . $mac . "'\n";
        push @scriptd, "export MACADDRESS\n";
    }

    #get vlan related items
    my $vlan;
    my $swtab = xCAT::Table->new("switch", -create => 0);
    if ($swtab) {
	my $tmp = $swtab->getNodeAttribs($node, ['vlan']);
	if (defined($tmp) && ($tmp) && $tmp->{vlan})
	{
	    $vlan = $tmp->{vlan};
	    push @scriptd, "VLANID='" . $vlan . "'\n";
	    push @scriptd, "export VLANID\n";
	} else {
	    my $vmtab = xCAT::Table->new("vm", -create => 0);
	    if ($vmtab) {
		my $tmp1 = $vmtab->getNodeAttribs($node, ['nics']);
		if (defined($tmp1) && ($tmp1) && $tmp1->{nics})
		{
		    push @scriptd, "VMNODE='YES'\n";
		    push @scriptd, "export VMNODE\n";
		    
		    my @nics=split(',', $tmp1->{nics});
		    foreach my $nic (@nics) {
			if ($nic =~ /^vl([\d]+)$/) {
			    $vlan = $1;
			    push @scriptd, "VLANID='" . $vlan . "'\n";
			    push @scriptd, "export VLANID\n";
			    last;
			}
		    }
		}
	    }
	}
	
	if ($vlan) {
	    my $nwtab=xCAT::Table->new("networks", -create =>0);
	    if ($nwtab) {
		my $sent = $nwtab->getAttribs({vlanid=>"$vlan"},'net','mask');
		my $subnet;
		my $netmask;
		if ($sent and ($sent->{net})) {
		    $subnet=$sent->{net};
		    $netmask=$sent->{mask};
		} 
		if (($subnet) && ($netmask)) {
		    my $hoststab = xCAT::Table->new("hosts", -create => 0);
		    if ($hoststab) {
			my $tmp = $hoststab->getNodeAttribs($node, ['otherinterfaces']);
			if (defined($tmp) && ($tmp) && $tmp->{otherinterfaces})
			{
			    my $otherinterfaces = $tmp->{otherinterfaces};
			    my @itf_pairs=split(/,/, $otherinterfaces);
			    foreach (@itf_pairs) {
				my ($name,$ip)=split(/:/, $_);
				if(xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet)) {
				    if ($name =~ /^-/ ) {
					$name = $node.$name;
				    }
				    push @scriptd, "VLANHOSTNAME='" . $name . "'\n";
				    push @scriptd, "export VLANHOSTNAME\n";
				    push @scriptd, "VLANIP='" . $ip . "'\n";
				    push @scriptd, "export VLANIP\n";
				    push @scriptd, "VLANSUBNET='" . $subnet . "'\n";
				    push @scriptd, "export VLANSUBNET\n";
				    push @scriptd, "VLANNETMASK='" . $netmask . "'\n";
				    push @scriptd, "export VLANNETMASK\n";
				    last;
				}
			    }	    
			}
		    }
		}
	    }
	}
    }


    #get monitoring server and other configuration data for monitoring setup on nodes
    my %mon_conf = xCAT_monitoring::monitorctrl->getNodeConfData($node);
    foreach (keys(%mon_conf))
    {
        push @scriptd, "$_=" . $mon_conf{$_} . "\n";
        push @scriptd, "export $_\n";
    }

    #get packge names for extra rpms
    my $pkglist;
    my $ospkglist;
    if (   ($^O =~ /^linux/i)
        && ($provmethod)
        && ($provmethod ne "install")
        && ($provmethod ne "netboot")
        && ($provmethod ne "statelite"))
    {

        #this is the case where image from the osimage table is used
        my $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
        (my $ref1) =
          $linuximagetab->getAttribs({imagename => $provmethod},
                                     'pkglist', 'pkgdir', 'otherpkglist',
                                     'otherpkgdir');
        if ($ref1)
        {
            if ($ref1->{'pkglist'})
            {
                $ospkglist = $ref1->{'pkglist'};
                if ($ref1->{'pkgdir'})
                {
                    push @scriptd, "OSPKGDIR=" . $ref1->{'pkgdir'} . "\n";
                    push @scriptd, "export OSPKGDIR\n";
                }
            }
            if ($ref1->{'otherpkglist'})
            {
                $pkglist = $ref1->{'otherpkglist'};
                if ($ref1->{'otherpkgdir'})
                {
                    push @scriptd,
                      "OTHERPKGDIR=" . $ref1->{'otherpkgdir'} . "\n";
                    push @scriptd, "export OTHERPKGDIR\n";
                }
            }
        }
    }
    else
    {
        my $stat        = "install";
        my $installroot = xCAT::Utils->getInstallDir();
        if ($profile)
        {
            my $platform = "rh";
            if ($os)
            {
                if    ($os =~ /rh.*/)     { $platform = "rh"; }
                elsif ($os =~ /centos.*/) { $platform = "centos"; }
                elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
                elsif ($os =~ /SL.*/)     { $platform = "SL"; }
                elsif ($os =~ /sles.*/)   { $platform = "sles"; }
                elsif ($os =~ /aix.*/)    { $platform = "aix"; }
            }
            if (($nodesetstate) && ($nodesetstate eq "netboot"))
            {
                $stat = "netboot";
            }

            $ospkglist =
              xCAT::SvrUtils->get_pkglist_file_name(
                                          "$installroot/custom/$stat/$platform",
                                          $profile, $os, $arch);
            if (!$ospkglist)
            {
                $ospkglist =
                  xCAT::SvrUtils->get_pkglist_file_name(
                                       "$::XCATROOT/share/xcat/$stat/$platform",
                                       $profile, $os, $arch);
            }

            $pkglist =
              xCAT::SvrUtils->get_otherpkgs_pkglist_file_name(
                                          "$installroot/custom/$stat/$platform",
                                          $profile, $os, $arch);
            if (!$pkglist)
            {
                $pkglist =
                  xCAT::SvrUtils->get_otherpkgs_pkglist_file_name(
                                       "$::XCATROOT/share/xcat/$stat/$platform",
                                       $profile, $os, $arch);
            }
        }
    }
    #print "pkglist=$pkglist\n";
    #print "ospkglist=$ospkglist\n";
    if ($ospkglist)
    {
        my $pkgtext = get_pkglist_tex($ospkglist);
        if ($pkgtext)
        {
            push @scriptd, "OSPKGS='".$pkgtext."'\n";
            push @scriptd, "export OSPKGS\n";
        }
    }

    if ($pkglist)
    {
        my $pkgtext = get_pkglist_tex($pkglist);
        if ($pkgtext)
        {
            my @sublists = split('#NEW_INSTALL_LIST#', $pkgtext);
            my $sl_index = 0;
            foreach (@sublists)
            {
                $sl_index++;
                push @scriptd, "OTHERPKGS$sl_index='".$_."'\n";
                push @scriptd, "export OTHERPKGS$sl_index\n";
            }
            if ($sl_index > 0)
            {
                push @scriptd, "OTHERPKGS_INDEX=$sl_index\n";
                push @scriptd, "export OTHERPKGS_INDEX\n";
            }
        }
    }

    # check if there are sync files to be handled
    my $syncfile;
    if (   ($provmethod)
        && ($provmethod ne "install")
        && ($provmethod ne "netboot")
        && ($provmethod ne "statelite"))
    {
        my $osimagetab = xCAT::Table->new('osimage', -create => 1);
        if ($osimagetab)
        {
            (my $ref) =
              $osimagetab->getAttribs(
                                      {imagename => $provmethod}, 'osvers',
                                      'osarch',     'profile',
                                      'provmethod', 'synclists'
                                      );
            if ($ref)
            {
                $syncfile = $ref->{'synclists'};
            }
        }
    }
    else
    {
        my $stat = "install";
        if (($nodesetstate) && ($nodesetstate eq "netboot")) {
            $stat = "netboot";
        }
        $syncfile =
          xCAT::SvrUtils->getsynclistfile(undef, $os, $arch, $profile, $stat);
    }
    if (!defined($syncfile))
    {
        push @scriptd, "NOSYNCFILES=1\n";
        push @scriptd, "export NOSYNCFILES\n";
    }

    my $isdiskless     = 0;
    my $setbootfromnet = 0;
    if (($arch eq "ppc64") || ($os =~ /aix.*/i))
    {

        # on Linux, the provmethod can be install,netboot or statelite,
        # on AIX, the provmethod can be null or image name
        #this is for Linux
        if (   ($provmethod)
            && (($provmethod eq "netboot") || ($provmethod eq "statelite")))
        {
            $isdiskless = 1;
        }
        if (   ($os =~ /aix.*/i)
            && ($provmethod)
            && ($provmethod ne "install")
            && ($provmethod ne "netboot")
            && ($provmethod ne "statelite"))
        {
            my $nimtype;
            my $nimimagetab = xCAT::Table->new('nimimage', -create => 1);
            if ($nimimagetab)
            {
                (my $ref) =
                  $nimimagetab->getAttribs({imagename => $provmethod},
                                           'nimtype');
                if ($ref)
                {
                    $nimtype = $ref->{'nimtype'};
                }
            }
            if ($nimtype eq 'diskless')
            {
                $isdiskless = 1;
            }
        }

        if ($isdiskless)
        {
            (my $ip, my $mask, my $gw) = net_parms($node);
            if (!$ip || !$mask || !$gw)
            {
                xCAT::MsgUtils->message(
                    'S',
                    "Unable to determine IP, netmask or gateway for $node, can not set the node to boot from network"
                    );
            }
            else
            {
                $setbootfromnet = 1;
                push @scriptd, "NETMASK=$mask\n";
                push @scriptd, "export NETMASK\n";
                push @scriptd, "GATEWAY=$gw\n";
                push @scriptd, "export GATEWAY\n";
            }
        }
    }

    # touch the /etc/xCATSN when it is a service node
    if (xCAT::Utils->isSN($node)) {
        push @scriptd, "touch /etc/xCATSN";
    }

    ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
    push @scriptd, "# postscripts-start-here\n";

    my %post_hash = ();    #used to reduce duplicates
    
    # get the xcatdefaults entry in the postscripts table
    my $et        =
      $posttab->getAttribs({node => "xcatdefaults"},
                           'postscripts', 'postbootscripts');
    my $defscripts = $et->{'postscripts'};
    if ($defscripts)
    {

        foreach my $n (split(/,/, $defscripts))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                push @scriptd, $n . "\n";
            }
        }
    }
    
    # get postscripts for images
    my $osimgname = $provmethod;

    if($osimgname =~ /install|netboot|statelite/){
        $osimgname = "$os-$arch-$provmethod-$profile";
    }
    my $et2 =
      $ostab->getAttribs({'imagename' => "$osimgname"}, ['postscripts', 'postbootscripts']);
    $ps = $et2->{'postscripts'};
    if ($ps)
    {
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                push @scriptd, $n . "\n";
            }
        }
    }

    # get postscripts for node specific
    my $et1 =
      $posttab->getNodeAttribs($node, ['postscripts', 'postbootscripts']);
    $ps = $et1->{'postscripts'};
    if ($ps)
    {
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($post_hash{$n}))
            {
                $post_hash{$n} = 1;
                push @scriptd, $n . "\n";
            }
        }
    }

    if ($setbootfromnet)
    {
        push @scriptd, "setbootfromnet\n";
    }

    # add setbootfromdisk if the nodesetstate is install and arch is ppc64
    if (($nodesetstate) && ($nodesetstate eq "install") && ($arch eq "ppc64"))
    {
        push @scriptd, "setbootfromdisk\n";
    }

    ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
    push @scriptd, "# postscripts-end-here\n";

    ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
    push @scriptd, "# postbootscripts-start-here\n";

    my %postboot_hash = ();                         #used to reduce duplicates
    my $defscripts    = $et->{'postbootscripts'};
    if ($defscripts)
    {
        foreach my $n (split(/,/, $defscripts))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                push @scriptd, $n . "\n";
            }
        }
    }

    # get postbootscripts for image
    my $ips = $et2->{'postbootscripts'};
    if ($ips)
    {
        foreach my $n (split(/,/, $ips))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                push @scriptd, $n . "\n";
            }
        }
    }


    # get postscripts
    $ps = $et1->{'postbootscripts'};
    if ($ps)
    {
        foreach my $n (split(/,/, $ps))
        {
            if (!exists($postboot_hash{$n}))
            {
                $postboot_hash{$n} = 1;
                push @scriptd, $n . "\n";
            }
        }
    }

    ###Please do not remove or modify this line of code!!! xcatdsklspost depends on it
    push @scriptd, "# postbootscripts-end-here\n";

    return @scriptd;
}

#----------------------------------------------------------------------------

=head3   get_pkglist_text

        read the pkglist file, expand it and return the content.
=cut

#-----------------------------------------------------------------------------
sub get_pkglist_tex
{
    my $pkglist   = shift;
    my @otherpkgs = ();
    my $pkgtext;
    if (open(FILE1, "<$pkglist"))
    {
        while (readline(FILE1))
        {
            chomp($_);    #remove newline
            s/\s+$//;     #remove trailing spaces
            s/^\s*//;     #remove leading blanks
            next if /^\s*$/;    #-- skip empty lines
            next
              if (   /^\s*#/
                  && !/^\s*#INCLUDE:[^#^\n]+#/
                  && !/^\s*#NEW_INSTALL_LIST#/);    #-- skip comments
            if (/^@(.*)/)
            {    #for groups that has space in name
                my $save = $1;
                if ($1 =~ / /) { $_ = "\@" . $save; }
            }
            push(@otherpkgs, $_);
        }
        close(FILE1);
    }
    if (@otherpkgs > 0)
    {
        $pkgtext = join(',', @otherpkgs);

        #handle the #INCLUDE# tag recursively
        my $idir         = dirname($pkglist);
        my $doneincludes = 0;
        while (not $doneincludes)
        {
            $doneincludes = 1;
            if ($pkgtext =~ /#INCLUDE:[^#^\n]+#/)
            {
                $doneincludes = 0;
                $pkgtext =~ s/#INCLUDE:([^#^\n]+)#/includefile($1,$idir)/eg;
            }
        }
    }
    return $pkgtext;
}

#----------------------------------------------------------------------------

=head3   includefile

        handles #INCLUDE# in otherpkg.pkglist file
=cut

#-----------------------------------------------------------------------------
sub includefile
{
    my $file = shift;
    my $idir = shift;
    my @text = ();
    unless ($file =~ /^\//)
    {
        $file = $idir . "/" . $file;
    }

    open(INCLUDE, $file) || \return "#INCLUDEBAD:cannot open $file#";

    while (<INCLUDE>)
    {
        chomp($_);    #remove newline
        s/\s+$//;     #remove trailing spaces
        next if /^\s*$/;    #-- skip empty lines
        next
          if (   /^\s*#/
              && !/^\s*#INCLUDE:[^#^\n]+#/
              && !/^\s*#NEW_INSTALL_LIST#/);    #-- skip comments
        push(@text, $_);
    }

    close(INCLUDE);

    return join(',', @text);
}

#----------------------------------------------------------------------------

=head3   getnodesetstate

        Determine the nodeset stat.
=cut

#-----------------------------------------------------------------------------
sub getnodesetstate
{
    my $node = shift;
    return xCAT::SvrUtils->get_nodeset_state($node);
}

sub net_parms
{
    my $ip = shift;
    $ip = xCAT::NetworkUtils->getipaddr($ip);
    if (!$ip)
    {
        xCAT::MsgUtils->message("S", "Unable to resolve $ip");
        return undef;
    }
    my $nettab = xCAT::Table->new('networks');
    unless ($nettab) { return undef }
    my @nets = $nettab->getAllAttribs('net', 'mask', 'gateway');
    foreach (@nets)
    {
        my $net  = $_->{'net'};
        my $mask = $_->{'mask'};
        my $gw   = $_->{'gateway'};
        if($gw eq '<myself>')
        {
             if(xCAT::NetworkUtils->ip_forwarding_enabled())
             {
                 $gw = xCAT::NetworkUtils->my_ip_in_subnet($net, $mask);
             }
             else
             {
                 $gw = '';
             }
        }
        if (xCAT::NetworkUtils->ishostinsubnet($ip, $mask, $net))
        {
            return ($ip, $mask, $gw);
        }
    }
    xCAT::MsgUtils->message(
        "S",
        "xCAT BMC configuration error, no appropriate network for $ip found in networks, unable to determine netmask"
        );
}

1;
