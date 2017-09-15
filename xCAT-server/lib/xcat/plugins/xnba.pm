# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::xnba;
use strict;
use Sys::Syslog;
use Socket;
use File::Copy;
use File::Path;
use xCAT::Scope;
use xCAT::MsgUtils;
use Getopt::Long;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::Usage;

my $dhcpconf = "/etc/dhcpd.conf";

#my $tftpdir = "/tftpboot";
my $globaltftpdir = xCAT::TableUtils->getTftpDir();

#my $dhcpver = 3;

my %usage = (
"nodeset" => "Usage: nodeset <noderange> [shell|boot|runcmd=bmcsetup|osimage[=<imagename>]|offline]",
);

sub handled_commands {
    return {
        nodeset => "noderes:netboot"
      }
}

sub check_dhcp {
    return 1;

    #TODO: omapi magic to do things right
    my $node = shift;
    my $dhcpfile;
    open($dhcpfile, $dhcpconf);
    while (<$dhcpfile>) {
        if (/host $node\b/) {
            close $dhcpfile;
            return 1;
        }
    }
    close $dhcpfile;
    return 0;
}

sub _slow_get_tftpdir {    #make up for paths where tftpdir is not passed in
    my $node = shift;
    my $nrtab = xCAT::Table->new('noderes', -create => 0); #in order to detect per-node tftp directories
    unless ($nrtab) { return $globaltftpdir; }
    my $ent = $nrtab->getNodeAttribs($node, ["tftpdir"]);
    if ($ent and $ent->{tftpdir}) {
        return $ent->{tftpdir};
    } else {
        return $globaltftpdir;
    }
}

sub getstate {
    my $node    = shift;
    my $tftpdir = shift;
    unless ($tftpdir) { $tftpdir = _slow_get_tftpdir($node); }
    if (check_dhcp($node)) {
        if (-r $tftpdir . "/xcat/xnba/nodes/" . $node) {
            my $fhand;
            open($fhand, $tftpdir . "/xcat/xnba/nodes/" . $node);
            my $headline = <$fhand>;
            $headline = <$fhand>;    #second line is the comment now...
            close $fhand;
            $headline =~ s/^#//;
            chomp($headline);
            return $headline;
        } elsif (-r $tftpdir . "/pxelinux.cfg/" . $node) {
            my $fhand;
            open($fhand, $tftpdir . "/pxelinux.cfg/" . $node);
            my $headline = <$fhand>;
            close $fhand;
            $headline =~ s/^#//;
            chomp($headline);
            return $headline;
        } else {

            # There is no boot configuration file, node must be offline
            return "offline";
        }
    } else {
        return "discover";
    }
}

sub setstate {

=pod

  This function will manipulate the pxelinux.cfg structure to match what the noderes/chain tables indicate the node should be booting.

=cut

    my $node            = shift;
    my %bphash          = %{ shift() };
    my %chainhash       = %{ shift() };
    my %machash         = %{ shift() };
    my %iscsihash       = %{ shift() };
    my $tftpdir         = shift;
    my %linuximghash    = ();
    my $linuximghashref = shift;
    if (ref $linuximghashref) { %linuximghash = %{$linuximghashref}; }
    my $imgaddkcmdline = ($linuximghash{'boottarget'}) ? undef : $linuximghash{'addkcmdline'};
    my $kern = $bphash{$node}->[0];

    unless ($::XNBA_addkcmdlinehandled->{$node}) { #Tag to let us know the plugin had a special syntax implemented for addkcmdline
        if ($kern->{addkcmdline} or ($imgaddkcmdline)) {

            #Implement the kcmdline append here for
            #most generic, least code duplication

        ###hack start
            # This is my comment. There are many others like it, but this one is mine.
            # My comment is my best friend. It is my life. I must master it as I must master my life.
            # Without me, my comment is useless. Without my comment, I am useless.

            # Jarrod to clean up.  It really should be in Table.pm and support
            # the new statelite $table notation.

            #I dislike spaces, tabs are cleaner, I'm too tired to change all the xCAT code.
            #I give in.

            my $kcmdlinehack = ($imgaddkcmdline) ? $kern->{addkcmdline} . " " . $imgaddkcmdline : $kern->{addkcmdline};

            my $cmdhashref;
            if ($kcmdlinehack) {
                $cmdhashref = xCAT::Utils->splitkcmdline($kcmdlinehack);
            }

            if ($cmdhashref and $cmdhashref->{volatile})
            {
                $kcmdlinehack = $cmdhashref->{volatile};
            }


            while ($kcmdlinehack =~ /#NODEATTRIB:([^:#]+):([^:#]+)#/) {
                my $natab = xCAT::Table->new($1);
                my $naent = $natab->getNodeAttribs($node, [$2]);
                my $naval = $naent->{$2};
                $kcmdlinehack =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#/$naval/;
            }
            while ($kcmdlinehack =~ /#TABLE:([^:#]+):([^:#]+):([^:#]+)#/) {
                my $tabname = $1;
                my $keyname = $2;
                my $colname = $3;
                if ($2 =~ /THISNODE/ or $2 =~ /\$NODE/) {
                    my $natab = xCAT::Table->new($tabname);
                    my $naent = $natab->getNodeAttribs($node, [$colname]);
                    my $naval = $naent->{$colname};
                    $kcmdlinehack =~ s/#TABLE:([^:#]+):([^:#]+):([^:#]+)#/$naval/;
                } else {
                    my $msg = "Table key of $2 not yet supported by boottarget mini-template";
                    $::XNBA_callback->({
                            error     => ["$msg"],
                            errorcode => [1]
                    });
                }
            }

            #$kern->{kcmdline} .= " ".$kern->{addkcmdline};
            $kern->{kcmdline} .= " " . $kcmdlinehack;
        ###hack end

        }
    }
    my $elilokcmdline = $kern->{kcmdline}; #track it separate, since vars differ
    my $pxelinuxkcmdline = $kern->{kcmdline}; #track it separate, since vars differ
    if ($kern->{kcmdline} =~ /!myipfn!/) {
        my $ipfn = '${next-server}';          #xCAT::Utils->my_ip_facing($node);
        $kern->{kcmdline} =~ s/!myipfn!/$ipfn/g;
        $elilokcmdline =~ s/!myipfn!/%N/g;
        my @ipfnd = xCAT::NetworkUtils->my_ip_facing($node);
        unless ($ipfnd[0]) { $ipfn = $ipfnd[1]; }
        else               { $ipfn = undef; }
        unless ($ipfn) { $ipfn = $::XCATSITEVALS{master}; }
        if ($ipfn) {
            $pxelinuxkcmdline =~ s/!myipfn!/$ipfn/g;
        }
    }
    my $pcfg;
    unlink($tftpdir . "/xcat/xnba/nodes/" . $node . ".pxelinux");
    open($pcfg, '>', $tftpdir . "/xcat/xnba/nodes/" . $node);
    my $cref = $chainhash{$node}->[0]; #$chaintab->getNodeAttribs($node,['currstate']);
    print $pcfg "#!gpxe\n";
    if ($cref->{currstate}) {
        print $pcfg "#" . $cref->{currstate} . "\n";
    }
    if ($cref and $cref->{currstate} eq "boot") {
        my $ient = $iscsihash{$node}->[0];
        if ($ient and $ient->{server} and $ient->{target}) {
            print $pcfg "hdboot\n";
        } else {
            print $pcfg "exit\n";
        }
        close($pcfg);
    } elsif ($kern and $kern->{kernel}) {
        if ($kern->{kernel} =~ /!/) { #TODO: deprecate this, do stateless Xen like stateless ESXi
            my $hypervisor;
            my $kernel;
            ($kernel, $hypervisor) = split /!/, $kern->{kernel};
            print $pcfg " set 209:string xcat/xnba/nodes/$node.pxelinux\n";
            print $pcfg " set 210:string http://" . '${next-server}' . "/tftpboot/\n";
            print $pcfg " imgfetch -n pxelinux.0 http://" . '${next-server}' . "/tftpboot/xcat/pxelinux.0\n";
            print $pcfg " imgload pxelinux.0\n";
            print $pcfg " imgexec pxelinux.0\n";
            close($pcfg);
            open($pcfg, '>', $tftpdir . "/xcat/xnba/nodes/" . $node . ".pxelinux");
            print $pcfg "DEFAULT xCAT\nLABEL xCAT\n   KERNEL mboot.c32\n";
            print $pcfg " APPEND $hypervisor --- $kernel " . $pxelinuxkcmdline . " --- " . $kern->{initrd} . "\n";
        } else {
            if ($kern->{kernel} =~ /\.c32\z/ or $kern->{kernel} =~ /memdisk\z/) { #gPXE comboot support seems insufficient, chain pxelinux instead
                print $pcfg " set 209:string xcat/xnba/nodes/$node.pxelinux\n";
                print $pcfg " set 210:string http://" . '${next-server}' . "/tftpboot/\n";
                print $pcfg " imgfetch -n pxelinux.0 http://" . '${next-server}' . "/tftpboot/xcat/pxelinux.0\n";
                print $pcfg " imgload pxelinux.0\n";
                print $pcfg " imgexec pxelinux.0\n";
                close($pcfg);
                open($pcfg, '>', $tftpdir . "/xcat/xnba/nodes/" . $node . ".pxelinux");

                #It's time to set pxelinux for this node to boot the kernel..
                print $pcfg "DEFAULT xCAT\nLABEL xCAT\n";
                print $pcfg " KERNEL " . $kern->{kernel} . "\n";
                if ($kern->{initrd} or $kern->{kcmdline}) {
                    print $pcfg " APPEND ";
                }
                if ($kern and $kern->{initrd}) {
                    print $pcfg "initrd=" . $kern->{initrd} . " ";
                }
                if ($kern and $kern->{kcmdline}) {
                    print $pcfg $pxelinuxkcmdline . "\n";
                } else {
                    print $pcfg "\n";
                }
                print $pcfg "IPAPPEND 2\n";
                if ($kern->{kernel} =~ /esxi[56]/) {  #Make uefi boot provisions
                    my $ucfg;
                    open($ucfg, '>', $tftpdir . "/xcat/xnba/nodes/" . $node . ".uefi");
                    if ($kern->{kcmdline} =~ /xcat\/netboot/) {
                        $kern->{kcmdline} =~ s/xcat\/netboot/\/tftpboot\/xcat\/netboot/;
                    }
                    print $ucfg "#!gpxe\n";
                    print $ucfg 'chain http://${next-server}/tftpboot/xcat/esxboot-x64.efi ' . $kern->{kcmdline} . "\n";
                    close($ucfg);
                }
            } else { #other than comboot/multiboot, we won't have need of pxelinux
                print $pcfg "imgfetch -n kernel http://" . '${next-server}/tftpboot/' . $kern->{kernel} . "\n";
                print $pcfg "imgload kernel\n";
                if ($kern->{kcmdline}) {
                    print $pcfg "imgargs kernel " . $kern->{kcmdline} . ' BOOTIF=01-${netX/machyp}' . "\n";
                } else {
                    print $pcfg "imgargs kernel BOOTIF=" . '${netX/mac}' . "\n";
                }
                if ($kern->{initrd}) {
                    print $pcfg "imgfetch http://" . '${next-server}' . "/tftpboot/" . $kern->{initrd} . "\n";
                }
                print $pcfg "imgexec kernel\n";
                if ($kern->{kcmdline} and $kern->{initrd}) { #only a linux kernel/initrd pair should land here, write elilo config and uefi variant of xnba config file
                    my $ucfg;
                    open($ucfg, '>', $tftpdir . "/xcat/xnba/nodes/" . $node . ".uefi");
                    print $ucfg "#!gpxe\n";
                    print $ucfg 'chain http://${next-server}/tftpboot/xcat/elilo-x64.efi -C /tftpboot/xcat/xnba/nodes/' . $node . ".elilo\n";
                    close($ucfg);
                    open($ucfg, '>', $tftpdir . "/xcat/xnba/nodes/" . $node . ".elilo");
                    print $ucfg 'default="xCAT"' . "\n";
                    print $ucfg "delay=0\n\n";
                    print $ucfg "image=/tftpboot/" . $kern->{kernel} . "\n";
                    print $ucfg "   label=\"xCAT\"\n";
                    print $ucfg "   initrd=/tftpboot/" . $kern->{initrd} . "\n";
                    print $ucfg "   append=\"" . $elilokcmdline . ' BOOTIF=%B"' . "\n";
                    close($ucfg);
                }
            }
        }
        close($pcfg);
    } else {    #TODO: actually, should possibly default to xCAT image?
        print $pcfg "LOCALBOOT 0\n";
        close($pcfg);
    }
}



my $errored = 0;

sub pass_along {
    my $resp = shift;
    if ($resp->{error} and not ref $resp->{error}) {
        $resp->{error} = [ $resp->{error} ];
    }
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored = 1;
    }
    foreach (@{ $resp->{node} }) {
        if ($_->{error} or $_->{errorcode}) {
            $errored = 1;
        }
        if ($_->{_addkcmdlinehandled}) {
            $::XNBA_addkcmdlinehandled->{ $_->{name}->[0] } = 1;
            return;    #Don't send back to client this internal hint
        }
    }
    $::XNBA_callback->($resp);
}


sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $callback1 = shift;
    my $command   = $req->{command}->[0];
    my $sub_req   = shift;
    my $nodes     = $req->{node};
    my @args      = ();
    if (ref($req->{arg})) {
        @args = @{ $req->{arg} };
    } else {
        @args = ($req->{arg});
    }
    @ARGV = @args;

    #use Getopt::Long;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    my $HELP;
    my $ALLFLAG;
    my $VERSION;
    my $VERBOSE;
    if (!GetOptions('h|?|help' => \$HELP,
            'v|version' => \$VERSION,
            'a'           =>\$ALLFLAG,
            'V'         => \$VERBOSE    #>>>>>>>used for trace log>>>>>>>
        )) {
        if ($usage{$command}) {
            my %rsp;
            $rsp{data}->[0] = $usage{$command};
            $callback1->(\%rsp);
        }
        return;
    }

    #>>>>>>>used for trace log start>>>>>>
    my $verbose_on_off = 0;
    if ($VERBOSE) { $verbose_on_off = 1; }

    #>>>>>>>used for trace log end>>>>>>>

    if ($HELP) {
        if ($usage{$command}) {
            my %rsp;
            $rsp{data}->[0] = $usage{$command};
            $callback1->(\%rsp);
        }
        return;
    }

    if ($VERSION) {
        my $ver = xCAT::Utils->Version();
        my %rsp;
        $rsp{data}->[0] = "$ver";
        $callback1->(\%rsp);
        return;
    }

    my $ret=xCAT::Usage->validateArgs($command,@ARGV);
    if ($ret->[0]!=0) {
         if ($usage{$command}) {
             my %rsp;
             $rsp{error}->[0] = $ret->[1];
             $rsp{data}->[1] = $usage{$command};
             $rsp{errorcode}->[0] = $ret->[0];
             $callback1->(\%rsp);
        }
        return;
    }

    if ($ARGV[0] ne "stat" && $ALLFLAG) {
        my %rsp;
        $rsp{error}->[0] = "'-a' could only be used with 'stat' subcommand.";
        $rsp{errorcode}->[0] = 1;
        $callback1->(\%rsp);
        return;
    }

    #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when
    #they specify no sharedtftp in site table
    my @entries = xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $t_entry = $entries[0];
    xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: sharedtftp=$t_entry");
    if (defined($t_entry) and ($t_entry eq "0" or $t_entry eq "no" or $t_entry eq "NO")) {

        # check for  computenodes and servicenodes from the noderange, if so error out
        my @SN;
        my @CN;
        xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
        unless (($args[0] eq 'stat') or ($args[0] eq 'enact')) { # mix is ok for these options
            if ((@SN > 0) && (@CN > 0)) {    # there are both SN and CN
                my %rsp;
                $rsp{errorcode}->[0] = 1;
                $rsp{error}->[0] =
"Nodeset was run with a noderange containing both service nodes and compute nodes. This is not valid. You must submit with either compute nodes in the noderange or service nodes. \n";
                $callback1->(\%rsp);
                return;
            }
        }

        $req->{'_disparatetftp'} = [1];
        if ($req->{inittime}->[0]) {
            return [$req];
        }
        if (@CN > 0) {    # if compute nodes broadcast to all servicenodes

            my @sn = xCAT::ServiceNodeUtils->getSNList();
            unless ( @sn > 0 ) {
                return xCAT::Scope->get_parallel_scope($req)
            }

            my $mynodeonly  = 0;
            my @entries = xCAT::TableUtils->get_site_attribute("disjointdhcps");
            my $t_entry = $entries[0];
            if (defined($t_entry)) {
                $mynodeonly = $t_entry;
            }
            $req->{'_disjointmode'} = [$mynodeonly];
            xCAT::MsgUtils->trace(0, "d", "xnba: disjointdhcps=$mynodeonly");

            if ($mynodeonly == 0 || $ALLFLAG) { # broadcast to all service nodes
                return xCAT::Scope->get_broadcast_scope_with_parallel($req, \@sn);
            }

            my $sn_hash = xCAT::ServiceNodeUtils->getSNformattedhash(\@CN, "xcat", "MN");
            my @dhcpsvrs = ();
            my $ntab = xCAT::Table->new('networks');
            if ($ntab) {
                foreach (@{ $ntab->getAllEntries() }) {
                    next unless ($_->{dynamicrange});
                    # if dynamicrange specified but dhcpserver was not - issue error message
                    push @dhcpsvrs, $_->{dhcpserver} if ($_->{dhcpserver})
                }
            }
            return xCAT::Scope->get_broadcast_disjoint_scope_with_parallel($req, $sn_hash, \@dhcpsvrs);
        }
    }
    # Do not dispatch to service nodes if non-sharedtftp or the node range contains only SNs.
    return xCAT::Scope->get_parallel_scope($req);
}

sub process_request {
    $::XNBA_request  = shift;
    $::XNBA_callback = shift;
    my $sub_req = shift;
    undef $::XNBA_addkcmdlinehandled;    # clear out any previous value
    my @args;
    my @nodes;
    my @rnodes;

    #>>>>>>>used for trace log start>>>>>>>
    my %opt;
    my $verbose_on_off = 0;
    if (ref($::XNBA_request->{arg})) {
        @args = @{ $::XNBA_request->{arg} };
    } else {
        @args = ($::XNBA_request->{arg});
    }
    @ARGV = @args;
    GetOptions('V' => \$opt{V});
    if ($opt{V}) { $verbose_on_off = 1; }

    #>>>>>>>used for trace log end>>>>>>>

    my @hostinfo = xCAT::NetworkUtils->determinehostname();
    $::myxcatname = $hostinfo[-1];
    xCAT::MsgUtils->trace(0, "d", "xnba: running on $::myxcatname");
    if (ref($::XNBA_request->{node})) {
        @rnodes = @{ $::XNBA_request->{node} };
    } else {
        if ($::XNBA_request->{node}) { @rnodes = ($::XNBA_request->{node}); }
    }
    unless (@rnodes) {
        if ($usage{ $::XNBA_request->{command}->[0] }) {
            $::XNBA_callback->({ data => $usage{ $::XNBA_request->{command}->[0] } });
        }
        return;
    }

    if ($args[0] eq 'stat') {
        my $noderestab = xCAT::Table->new('noderes'); #in order to detect per-node tftp directories
        my %nrhash = %{ $noderestab->getNodesAttribs(\@rnodes, [qw(tftpdir)]) };
        foreach my $node (@rnodes) {
            my %response;
            my $tftpdir;
            if ($nrhash{$node}->[0] and $nrhash{$node}->[0]->{tftpdir}) {
                $tftpdir = $nrhash{$node}->[0]->{tftpdir};
            } else {
                $tftpdir = $globaltftpdir;
            }
            $response{node}->[0]->{name}->[0] = $node;
            $response{node}->[0]->{data}->[0] = getstate($node, $tftpdir);
            $::XNBA_callback->(\%response);
        }
        return;
    }

    my @nodes = ();
    # Filter those nodes which have bad DNS: not resolvable or inconsistent IP
    my %failurenodes = ();
    my %preparednodes = ();
    foreach (@rnodes) {
        my $ipret = xCAT::NetworkUtils->checkNodeIPaddress($_);
        my $errormsg = $ipret->{'error'};
        my $nodeip = $ipret->{'ip'};
        if ($errormsg) {# Add the node to failure set
            xCAT::MsgUtils->trace(0, "E", "xnba: Defined IP address of $_ is $nodeip. $errormsg");
            unless ($nodeip) {
                $failurenodes{$_} = 1;
            }
        }
        if ($nodeip) {
            $preparednodes{$_} = $nodeip;
        }
    }

    #if not shared tftpdir, then filter, otherwise, set up everything
    if ($::XNBA_request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
        # Filter those nodes not in the same subnet, and print error message in log file.
        foreach (keys %preparednodes) {
            # Only handle its boot configuration files if the node in same subnet
            if (xCAT::NetworkUtils->nodeonmynet($preparednodes{$_})) {
                push @nodes, $_;
            } else {
                xCAT::MsgUtils->trace(0, "W", "xnba: configuration file was not created for [$_] because the node is not on the same network as this server");
                delete $preparednodes{$_};
            }
        }
    } else {
        @nodes = keys %preparednodes;
    }

    my $str_node = join(" ", @nodes);
    xCAT::MsgUtils->trace(0, "d", "xnba: nodes are $str_node") if ($str_node);

    # Return directly if no nodes in the same network, need to report error on console if its managed nodes are not handled.
    unless (@nodes) {
        xCAT::MsgUtils->message("S", "xCAT: xnba netboot: no valid nodes. Stop the operation on this server.");

        # If non-shared tftproot and non disjoint mode, need to figure out if no nodes here is a normal case.
        if ($::XNBA_request->{'_disparatetftp'}->[0] && $::XNBA_request->{'_disjointmode'}->[0] != 1) {
            # Find out which nodes are really mine only when not sharedtftp and not disjoint mode.
            my %iphash   = ();
            # flag the IPs or names in iphash
            foreach (@hostinfo) { $iphash{$_} = 1; }

            # Get managed node list under current server
            # The node will be under under 'site.master' if no 'noderes.servicenode' is defined
            my $sn_hash = xCAT::ServiceNodeUtils->getSNformattedhash(\@rnodes, "xcat", "MN");
            my $req2manage = 0;
            foreach (keys %$sn_hash) {
                if (exists($iphash{$_})) {
                    $req2manage = 1;
                    last;
                }
            }
            if ($req2manage == 0) {
                #No nodes are required to be handled, quit without error.
                return;
            }
        }
        # Okay, now report error as no nodes are handled.
        my $rsp;
        $rsp->{errorcode}->[0] = 1;
        $rsp->{error}->[0]     = "Failed to generate xnba configurations for some node(s) on $::myxcatname. Check xCAT log file for more details.";
        $::XNBA_callback->($rsp);
        return;
    }

    #now run the begin part of the prescripts
    unless ($args[0] eq '') {    # or $args[0] eq 'enact') {
        $errored = 0;
        if ($::XNBA_request->{'_disparatetftp'}->[0]) { #the call is distrubuted to the service node already, so only need to handles my own children
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: the call is distrubuted to the service node already, so only need to handles my own children");
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: issue runbeginpre request");
            $sub_req->({ command => ['runbeginpre'],
                    node => \@nodes,
                    arg => [ $args[0], '-l' ] }, \&pass_along);
        } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: nodeset did not distribute to the service node");
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: issue runbeginpre request");
            $sub_req->({ command => ['runbeginpre'],
                    node => \@nodes,
                    arg => [ $args[0] ] }, \&pass_along);
        }
        if ($errored) {
            my $rsp;
            $rsp->{errorcode}->[0] = 1;
            $rsp->{error}->[0] = "Failed in running begin prescripts.  Processing will still continue.\n";
            $::XNBA_callback->($rsp);
        }
    }

    #back to normal business
    if (!-r "$globaltftpdir/xcat/pxelinux.0") {
        unless (-r $::XCATROOT . "/share/xcat/netboot/syslinux/pxelinux.0") {
            $::XNBA_callback->({ error => [ "Unable to find pxelinux.0 at " . $::XCATROOT . "/share/xcat/netboot/syslinux/pxelinux.0" ], errorcode => [1] });
            return;
        }
        copy($::XCATROOT . "/share/xcat/netboot/syslinux/pxelinux.0", "$globaltftpdir/xcat/pxelinux.0");
        chmod(0644, "$globaltftpdir/xcat/pxelinux.0");
    }
    unless (-r "$globaltftpdir/xcat/pxelinux.0") {
        $::XNBA_callback->({ error => ["Unable to find pxelinux.0 from syslinux"], errorcode => [1] });
        return;
    }



    my $inittime = 0;
    if (exists($::XNBA_request->{inittime})) { $inittime = $::XNBA_request->{inittime}->[0]; }
    if (!$inittime) { $inittime = 0; }

    my %bphash;
    unless ($args[0] eq '') {    # or $args[0] eq 'enact') {
        $errored = 0;
        xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: issue setdestiny request");
        $sub_req->({ command => ['setdestiny'],
                node     => \@nodes,
                inittime => [$inittime],
                arg      => \@args ,
                bootparams => \%bphash},
                \&pass_along);
        if ($errored) { 
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: Failed in processing setdestiny.  Processing will not continue.");
            return; 
        }
    }

    xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: starting to handle configuration...");
    #Time to actually configure the nodes, first extract database data with the scalable calls
    my $chaintab = xCAT::Table->new('chain');
    my $noderestab = xCAT::Table->new('noderes'); #in order to detect per-node tftp directories
    my $mactab     = xCAT::Table->new('mac');     #to get all the hostnames
    my %nrhash = %{ $noderestab->getNodesAttribs(\@nodes, [qw(tftpdir)]) };
    my %chainhash = %{ $chaintab->getNodesAttribs(\@nodes, [qw(currstate)]) };
    my %iscsihash;
    my $iscsitab = xCAT::Table->new('iscsi');

    if ($iscsitab) {
        %iscsihash = %{ $iscsitab->getNodesAttribs(\@nodes, [qw(server target)]) };
    }
    my $typetab = xCAT::Table->new('nodetype', -create => 1);
    my $typehash = $typetab->getNodesAttribs(\@nodes, ['provmethod']);
    my $linuximgtab = xCAT::Table->new('linuximage', -create => 1);

    my %machash = %{ $mactab->getNodesAttribs(\@nodes, [qw(mac)]) };
    foreach (@nodes) {
        my $tftpdir;
        if ($nrhash{$_}->[0] and $nrhash{$_}->[0]->{tftpdir}) {
            $tftpdir = $nrhash{$_}->[0]->{tftpdir};
        } else {
            $tftpdir = $globaltftpdir;
        }
        mkpath($tftpdir . "/xcat/xnba/nodes/");
        my %response;
        $response{node}->[0]->{name}->[0] = $_;
        if ($args[0]) { # Send it on to the destiny plugin, then setstate
            my $rc;
            my $errstr;
            my $ent          = $typehash->{$_}->[0];
            my $osimgname    = $ent->{'provmethod'};
            my $linuximghash = undef;
            unless ($osimgname =~ /^(install|netboot|statelite)$/) {
                $linuximghash = $linuximgtab->getAttribs({ imagename => $osimgname }, 'boottarget', 'addkcmdline');
            }
            ($rc, $errstr) = setstate($_, \%bphash, \%chainhash, \%machash, \%iscsihash, $tftpdir, $linuximghash);

            #currently, it seems setstate doesn't return error codes...
            #if ($rc) {
            #  $response{node}->[0]->{errorcode}->[0]= $rc;
            #  $response{node}->[0]->{errorc}->[0]= $errstr;
            #  $::XNBA_callback->(\%response);
            #}
            if ($args[0] eq 'offline') {
                unlink($tftpdir . "/xcat/xnba/nodes/" . $_);
                unlink($tftpdir . "/xcat/xnba/nodes/" . $_ . ".pxelinux");
                unlink($tftpdir . "/xcat/xnba/nodes/" . $_ . ".uefi");
                unlink($tftpdir . "/xcat/xnba/nodes/" . $_ . ".elilo");
            }
        }
    }
    xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: Finish to handle configurations");

    # for offline operation, remove the dhcp entries
    if ($args[0] eq 'offline') {
        $sub_req->({ command => ['makedhcp'], arg => ['-d'], node => \@nodes }, $::XNBA_callback);
    }

    #dhcp stuff -- inittime is set when xcatd on sn is started
    unless (($inittime) || ($args[0] eq 'offline')) {
        my $do_dhcpsetup = 1;
        my @entries = xCAT::TableUtils->get_site_attribute("dhcpsetup");
        my $t_entry = $entries[0];
        if (defined($t_entry)) {
            if ($t_entry =~ /0|n|N/) { $do_dhcpsetup = 0; }
        }
        if ($do_dhcpsetup) {
            my @parameter;
            push @parameter, '-l' if ($::XNBA_request->{'_disparatetftp'}->[0]);
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: issue makedhcp request");

            $sub_req->({ command => ['makedhcp'],
                         arg => \@parameter,
                         node => \@nodes }, $::XNBA_callback);
        } else {
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: dhcpsetup=$do_dhcpsetup");
        }
    }

    #now run the end part of the prescripts
    unless ($args[0] eq '') {    # or $args[0] eq 'enact')
        $errored = 0;
        if ($::XNBA_request->{'_disparatetftp'}->[0]) { #the call is distrubuted to the service node already, so only need to handle my own children
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: issue runendpre request");
            $sub_req->({ command => ['runendpre'],
                    node => \@nodes,
                    arg => [ $args[0], '-l' ] }, \&pass_along);
        } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off, "d", "xnba: issue runendpre request");
            $sub_req->({ command => ['runendpre'],
                    node => \@nodes,
                    arg => [ $args[0] ] }, \&pass_along);
        }
        if ($errored) {
            my $rsp;
            $rsp->{errorcode}->[0] = 1;
            $rsp->{error}->[0] = "Failed in running end prescripts.  Processing will still continue.\n";
            $::XNBA_callback->($rsp);
        }
    }

    # Return error codes if there are failed nodes
    if (%failurenodes) {
        my $rsp;
        $rsp->{errorcode}->[0] = 1;
        $rsp->{error}->[0]     = "Failed to generate xnba configurations for some node(s) on $::myxcatname. Check xCAT log file for more details.";
        $::XNBA_callback->($rsp);
        return;
    }

}


#----------------------------------------------------------------------------

=head3  getNodesetStates
       returns the nodeset state for the given nodes. The possible nodeset
           states are: netboot, install, boot and discover.
    Arguments:
        nodes  --- a pointer to an array of nodes
        states -- a pointer to a hash table. This hash will be filled by this
             function. The key is the nodeset status and the value is a pointer
             to an array of nodes. 
    Returns:
       (return code, error message)
=cut

#-----------------------------------------------------------------------------
sub getNodesetStates {
    my $noderef = shift;
    if ($noderef =~ /xCAT_plugin::pxe/) {
        $noderef = shift;
    }
    my @nodes   = @$noderef;
    my $hashref = shift;
    my $noderestab = xCAT::Table->new('noderes'); #in order to detect per-node tftp directories
    my %nrhash = %{ $noderestab->getNodesAttribs(\@nodes, [qw(tftpdir)]) };
    if (@nodes > 0) {
        foreach my $node (@nodes) {
            my $tftpdir;
            if ($nrhash{$node}->[0] and $nrhash{$node}->[0]->{tftpdir}) {
                $tftpdir = $nrhash{$node}->[0]->{tftpdir};
            } else {
                $tftpdir = $globaltftpdir;
            }
            my $tmp = getstate($node, $tftpdir);
            my @a = split(' ', $tmp);
            my $stat = $a[0];
            if (exists($hashref->{$stat})) {
                my $pa = $hashref->{$stat};
                push(@$pa, $node);
            }
            else {
                $hashref->{$stat} = [$node];
            }
        }
    }
    return (0, "");
}

1;
