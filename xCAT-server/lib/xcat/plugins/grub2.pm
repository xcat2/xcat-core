# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::grub2;

use Sys::Syslog;
use xCAT::Scope;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use File::Path;
use Socket;
use Getopt::Long;
use xCAT::Table;
use xCAT::Usage;
my $request;
my %tftpserverip;
my $callback;
my $sub_req;
my $globaltftpdir = xCAT::TableUtils->getTftpDir();


my %usage = (
"nodeset" => "Usage: nodeset <noderange> [shell|boot|runcmd=bmcsetup|osimage[=<imagename>]|offline|shutdown|stat]",
);

sub handled_commands {

    # process noderes:netboot like "grub2-<transfer protocol>"
    # such as grub2-http and grub2-tftp
    return {
        nodeset => "noderes:netboot=(grub2[-]?.*)"
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
        if (-r $tftpdir . "/boot/grub2/" . $node) {
            my $fhand;
            open($fhand, $tftpdir . "/boot/grub2/" . $node);
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

  This function will manipulate the grub structure to match what the noderes/chain tables indicate the node should be booting.

=cut

    my $node         = shift;
    my %bphash       = %{ shift() };
    my %chainhash    = %{ shift() };
    my %machash      = %{ shift() };
    my $tftpdir      = shift;
    my %nrhash       = %{ shift() };
    my $linuximghash = shift();
    my $nodearch     = shift;
    my $nodeos       = shift;
    my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
    if ($kern->{kcmdline} =~ /!myipfn!/) {
        my $ipfn;
        my @ipfnd = xCAT::NetworkUtils->my_ip_facing($node);

        if ($ipfnd[0] ==  1) {
            return (1, $ipfnd[1]);
        }
        elsif ($ipfnd[0] == 2) {
            my $servicenodes = $nrhash{$node}->[0];
            if ($servicenodes and $servicenodes->{servicenode}) {
                my @sns = split /,/, $servicenodes->{servicenode};
                foreach my $sn (@sns) {

                    # We are in the service node pools, print error if no facing ip.
                    if (xCAT::InstUtils->is_me($sn)) {
                        return (1, "$::myxcatname: $ipfnd[1] on service node $sn");
                    }
                }
            } else {
                return (1, "$::myxcatname: $ipfnd[1]");
            }
        } else {
            $ipfn = $ipfnd[1];
            $kern->{kcmdline} =~ s/!myipfn!/$ipfn/g;
        }
    }

    my $addkcmdline;
    if ($kern->{addkcmdline}) {
        $addkcmdline .= $kern->{addkcmdline} . " ";
    }

    if ($linuximghash and $linuximghash->{'addkcmdline'})
    {
        unless ($linuximghash->{'boottarget'})
        {
            $addkcmdline .= $linuximghash->{'addkcmdline'} . " ";
        }
    }

    my $cmdhashref;
    if ($addkcmdline) {
        $cmdhashref = xCAT::Utils->splitkcmdline($addkcmdline);
    }

    if ($cmdhashref and $cmdhashref->{volatile})
    {
        $kern->{kcmdline} .= " " . $cmdhashref->{volatile};
    }

    my $bootloader_root = "$tftpdir/boot/grub2";
    unless (-d "$bootloader_root") {
        mkpath("$bootloader_root");
    }

    my $cref = $chainhash{$node}->[0];
    unless ($cref->{currstate}) { # the currstate should be set during 'setdestiny'
        return (1, "Cannot determine current state for this node");
    }

    # remove the old boot configuration files and create a new one, but only if not offline directive
    system("find $bootloader_root/ -inum \$(stat --printf \%i $bootloader_root/$node 2>/dev/null) -exec rm -f {} \\; 2>/dev/null");

    my $pcfg;
    if ($cref->{currstate} ne "offline") {
        open($pcfg, '>', "$bootloader_root/" . $node);
        print $pcfg "#" . $cref->{currstate} . "\n";

        if (($::XCATSITEVALS{xcatdebugmode} eq "1") or ($::XCATSITEVALS{xcatdebugmode} eq "2")) {
            print $pcfg "set debug=all\n";
        }

        print $pcfg "set timeout=5\n";
    }

    if ($cref->{currstate} eq "boot") {
        close($pcfg);
    } elsif ($kern and $kern->{kernel}) {

        #It's time to set grub configuration for this node to boot the kernel..
        #get tftpserver
        my $tftpserver;
        if (defined($nrhash{$node}->[0]) && $nrhash{$node}->[0]->{'tftpserver'}) {
            $tftpserver = $nrhash{$node}->[0]->{'tftpserver'};
        } elsif (defined($nrhash{$node}->[0]) && $nrhash{$node}->[0]->{'xcatmaster'}) {
            $tftpserver = $nrhash{$node}->[0]->{'xcatmaster'};
        } else {
            $tftpserver = "<xcatmaster>";
        }

        my $serverip;

        if($tftpserver eq "<xcatmaster>"){
            my @nxtsrvd = xCAT::NetworkUtils->my_ip_facing($node);
            unless ($nxtsrvd[0]) {
                $serverip = $nxtsrvd[1];
            } else {
                return (1, $nxtsrvd[1]);
            }
        } else {
            if (defined($tftpserverip{$tftpserver})) {
                $serverip = $tftpserverip{$tftpserver};
            } else {
                $serverip = xCAT::NetworkUtils->getipaddr($tftpserver);
                unless ($serverip) {
                    return (1, "xCAT unable to resolve $tftpserver");
                }
                $tftpserverip{$tftpserver} = $serverip;
            }
        }

        unless($serverip){
            close($pcfg);
            return (1, "Unable to determine the tftpserver for $node");
        }
        my $grub2protocol = "tftp";
        if (defined($nrhash{$node}->[0]) && $nrhash{$node}->[0]->{'netboot'}
            && ($nrhash{$node}->[0]->{'netboot'} =~ /grub2-(.*)/)) {
            $grub2protocol = $1;
        }

        unless ($grub2protocol =~ /^http|tftp$/) {
            close($pcfg);
            return (1, "Invalid netboot method, please check noderes.netboot for $node");
        }

        # write entries to boot config file, but only if not offline directive
        if ($cref and $cref->{currstate} ne "offline") {
            my $httpport = "80";
            my @hports = xCAT::TableUtils->get_site_attribute("httpport");
            if ($hports[0]) {
                $httpport = $hports[0];
            }

            print $pcfg "set default=\"xCAT OS Deployment\"\n";
            print $pcfg "menuentry \"xCAT OS Deployment\" {\n";
            print $pcfg "    insmod http\n";
            print $pcfg "    insmod tftp\n";
            if ($grub2protocol eq "http" && $httpport ne "80") {
                print $pcfg "    set root=http,$serverip:$httpport\n";
            } else {
                print $pcfg "    set root=$grub2protocol,$serverip\n";
            }
            print $pcfg "    echo Loading Install kernel ...\n";

            my $protocolrootdir = "";
            if ($grub2protocol =~ /^http$/)
            {
                $protocolrootdir = $tftpdir;
            }

            if ($kern and $kern->{kcmdline}) {
                print $pcfg "    linux $protocolrootdir/$kern->{kernel} $kern->{kcmdline}\n";
            } else {
                print $pcfg "    linux $protocolrootdir/$kern->{kernel}\n";
            }
            print $pcfg "    echo Loading initial ramdisk ...\n";
            if ($kern and $kern->{initrd}) {
                print $pcfg "    initrd $protocolrootdir/$kern->{initrd}\n";
            }

            print $pcfg "}";
            close($pcfg);
        }
    } else {
        close($pcfg);
    }

    unless ($nodearch) {
        return (1, "No archictecture defined in nodetype table for the node.");
    }
    if ($nodearch =~ /ppc64/i) {
        $nodearch = "ppc"
    }
    my $grub2bin    = "$bootloader_root/grub2." . $nodearch;
    unless (-e "$grub2bin") {
        return (1, "Stop grub2 configuration for this node, \"$grub2bin\" does not exits.");
    }

    chdir("$bootloader_root");
    if ($cref->{currstate} eq "offline" or $cref->{currstate} eq "boot") {
        unlink("grub2-$node");
    } elsif ($cref->{currstate} eq "standby" and $nodeos =~ /^sle/i) {
        my $os_version = $nodeos;
        $os_version =~ s/sles//i; # Strip sles if there
        $os_version =~ s/sle//i; # String sle if there
        if ($os_version >= "15") {
            # Make sure for SLES15 or higher can still boot 
            # from disk in "standby" state
            unlink("grub2-$node");
        }
    } elsif (! -e "grub2-$node") {
        symlink("grub2." . $nodearch, "grub2-$node");
    }

    my $ip = xCAT::NetworkUtils->getipaddr($node);
    unless ($ip) {
        return (1, "xCAT unable to resolve IP in grub2 plugin");
    }
    #my $mactab = xCAT::Table->new('mac');
    my %ipaddrs;
    my $macstring;
    $ipaddrs{$ip} = 1;

    my $ment = $machash{$node}->[0];
    if ($ment and $ment->{mac}) {
        $macstring = $ment->{mac};
        my @macs = split(/\|/, $ment->{mac});
        foreach (@macs) {
            if (/!(.*)/) {
                my $ipaddr = xCAT::NetworkUtils->getipaddr($1);
                if ($ipaddr) {
                    $ipaddrs{$ipaddr} = 1;
                }
            }
        }
    }

    # Do not use symbolic link, p5 does not support symbolic link in /tftpboot
    #  my $hassymlink = eval { symlink("",""); 1 };
    foreach $ip (keys %ipaddrs) {
        my @ipa = split(/\./, $ip);
        my $pname = "grub.cfg-" . sprintf("%02X%02X%02X%02X", @ipa);

        # remove the old boot configuration file and copy (link) a new one, but only if not offline directive
        unlink("$bootloader_root/" . $pname);
        link("$bootloader_root/" . $node, "$bootloader_root/" . $pname) if ($cref->{currstate} ne "offline");
    }

    my $nodemac;
    my $nrent=$nrhash{$node}->[0];
    if($nrent and $nrent->{installnic}){
        my $myinstallnic=$nrent->{installnic};
        if(xCAT::NetworkUtils->isValidMAC($myinstallnic)){
            $nodemac=$myinstallnic;
        }
    }
    if (! $nodemac and $macstring) {
        $nodemac = xCAT::Utils->parseMacTabEntry($macstring, $node);
    }

    if ($nodemac =~ /:/) {
        my $tmp = lc($nodemac);
        $tmp =~ s/(..):(..):(..):(..):(..):(..)/$1-$2-$3-$4-$5-$6/g;
        my $pname = "grub.cfg-01-" . $tmp;

        # remove the old boot configuration file and copy (link) a new one, but only if not offline directive
        unlink("$bootloader_root/" . $pname);
        link("$bootloader_root/" . $node, "$bootloader_root/" . $pname) if ($cref->{currstate} ne "offline");
    }
    return (0, "");
}

my $errored = 0;

sub pass_along {
    my $resp = shift;
    return unless ($resp);

    my $failure = 0;
    if ($resp->{errorabort}) { # Global error, it normally means to stop the parent execution. For example, DB operation error.
        $failure = 2;
        delete $resp->{errorabort};
    } elsif (($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $failure = 1;
    }
    $callback->($resp);

    if ($failure > 1) { # quick abort
        $errored = $failure;
        return;
    }

    # Partial error on nodes, it allows to continue the rest of business on the sucessful nodes.
    foreach (@{ $resp->{node} }) {
        if ($_->{error} or $_->{errorcode}) {
            $failure = 1;
            if ($_->{name}) {
                $failurenodes{$_->{name}->[0]} = 2;
            }
        }
    }
    if ( $failure ) {
        $errored = $failure;
    }
}


sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $callback1 = shift;
    my $command   = $req->{command}->[0];
    my $sub_req   = shift;
    my @args      = ();
    if (ref($req->{arg})) {
        @args = @{ $req->{arg} };
    } else {
        @args = ($req->{arg});
    }
    @ARGV = @args;
    my $nodes = $req->{node};

    #use Getopt::Long;
    my $HELP;
    my $ALLFLAG;
    my $VERSION;
    my $VERBOSE;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
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

    # inittime flag in request will only be set in AAsn.pm (it is only used when xcatd starting on service node)
    # There is special requirement to not run in parallel on one SN to avoid DB CPU 100% when all service nodes booting in the same time.
    my $inittime = 0;
    if (exists($req->{inittime})) { $inittime = $req->{inittime}->[0]; }
    if (!$inittime) { $inittime = 0; }

    #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when
    #if they specify no sharedtftp in site table
    my @entries = xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $t_entry = $entries[0];

    xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: sharedtftp=$t_entry");

    if (defined($t_entry) and ($t_entry eq "0" or $t_entry eq "no" or $t_entry eq "NO")) {

        # check for  computenodes and servicenodes from the noderange, if so error out
        my @SN;
        my @CN;
        xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
        unless (($args[0] eq 'stat') or ($args[0] eq 'enact')) {
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
        if (@CN > 0) {    # if compute nodes only, then broadcast to servic enodes

            # 1, Non-hierarchy, run on locally with parallel
            my @sn = xCAT::ServiceNodeUtils->getSNList();
            unless ( @sn > 0 ) {
                return if (xCAT::Utils->isServiceNode()); # in case the wrong configuration
                return xCAT::Scope->get_parallel_scope($req);
            }

            # To check site table to see if disjoint mode
            my $mynodeonly  = 0;
            my @entries = xCAT::TableUtils->get_site_attribute("disjointdhcps");
            my $t_entry = $entries[0];
            if (defined($t_entry)) {
                $mynodeonly = $t_entry;
            }
            $req->{'_disjointmode'} = [$mynodeonly];
            xCAT::MsgUtils->trace(0, "d", "grub2: disjointdhcps=$mynodeonly");

            # 2, Non-disjoint mode, broadcast to all service nodes,
            #    but for SN init time (AAsn.pm), only run locally without parallel.
            if ($mynodeonly == 0 || $ALLFLAG) {
                if ($inittime) {
                    $req->{_xcatpreprocessed}->[0] = 1;
                    return [$req];
                }
                return xCAT::Scope->get_broadcast_scope_with_parallel($req, \@sn);
            }

            # 3, Disjoint mode, run on local for owned CNs only and
            # dispatch to parent SNs of the requesting nodes and `dhcpserver` which serving dynamic range in `networks` table.
            #    but for SN init time (AAsn.pm), only run locally without parallel.
            my $sn_hash = xCAT::ServiceNodeUtils->getSNformattedhash(\@CN, "xcat", "MN");
            if ($inittime) {
                foreach my $sn ( keys %$sn_hash ) {
                    unless (xCAT::NetworkUtils->thishostisnot($sn)) {
                        $req->{node} = $sn_hash->{$sn};
                        $req->{_xcatpreprocessed}->[0] = 1;
                        return [$req];
                    }
                }
            }
            my @dhcpsvrs = ();
            my $ntab = xCAT::Table->new('networks');
            if ($ntab) {
                foreach (@{ $ntab->getAllEntries() }) {
                    next unless ($_->{dynamicrange});
                    push @dhcpsvrs, $_->{dhcpserver} if ($_->{dhcpserver} && xCAT::NetworkUtils->nodeonmynet($_->{dhcpserver}));
                }
            }
            return xCAT::Scope->get_broadcast_disjoint_scope_with_parallel($req, $sn_hash, \@dhcpsvrs);
        }
    } elsif ($inittime) {
        # Shared TFTP, no need to run on service node booting (AAsn.pm)
        return;
    }
    # Do not dispatch to service nodes if non-sharedtftp or the node range contains only SNs.
    return xCAT::Scope->get_parallel_scope($req);
}

sub process_request {
    $request    = shift;
    $callback   = shift;
    $sub_req    = shift;
    my $command = $request->{command}->[0];

    undef %failurenodes;

    my @args;
    #>>>>>>>used for trace log start>>>>>>>
    my %opt;
    my $verbose_on_off = 0;
    if (ref($request->{arg})) {
        @args = @{ $request->{arg} };
    } else {
        @args = ($request->{arg});
    }
    @ARGV = @args;
    GetOptions('V' => \$opt{V});
    if ($opt{V}) { $verbose_on_off = 1; }

    #>>>>>>>used for trace log end>>>>>>>

    my @hostinfo = xCAT::NetworkUtils->determinehostname();
    $::myxcatname = $hostinfo[-1];
    xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: running on $::myxcatname");
    my @rnodes;
    if (ref($request->{node})) {
        @rnodes = @{ $request->{node} };
    } else {
        if ($request->{node}) { @rnodes = ($request->{node}); }
    }
    unless (@rnodes) {
        if ($usage{ $request->{command}->[0] }) {
            $callback->({ data => $usage{ $request->{command}->[0] } });
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
            $callback->(\%response);
        }
        return;
    }

    my @nodes = ();
    # Filter those nodes which have bad DNS: not resolvable or inconsistent IP
    my %preparednodes = ();
    foreach (@rnodes) {
        my $ipret = xCAT::NetworkUtils->checkNodeIPaddress($_);
        my $errormsg = $ipret->{'error'};
        my $nodeip = $ipret->{'ip'};
        if ($errormsg) {# Add the node to failure set
            xCAT::MsgUtils->trace(0, "E", "grub2: Defined IP address of $_ is $nodeip. $errormsg");
            unless ($nodeip) {
                $failurenodes{$_} = 1;
            }
        }
        if ($nodeip) {
            $preparednodes{$_} = $nodeip;
        }
    }

    #if not shared tftpdir, then filter, otherwise, set up everything
    if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
        # Filter those nodes not in the same subnet, and print error message in log file.
        foreach (keys %preparednodes) {
            # Only handle its boot configuration files if the node in same subnet
            if (xCAT::NetworkUtils->nodeonmynet($preparednodes{$_})) {
                push @nodes, $_;
            } else {
                xCAT::MsgUtils->trace(0, "W", "grub2: configuration file was not created for [$_] because the node is not on the same network as this server");
                delete $preparednodes{$_};
            }
        }
    } else {
        @nodes = keys %preparednodes;
    }

    my $str_node = '';
    my $total = $#nodes;
    if ($total > 20) {
        $str_node = join(" ", @nodes[0..19]) . " ...";
    } else {
        $str_node = join(" ", @nodes);
    }
    xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: [total=$total] nodes are $str_node");

    # Return directly if no nodes in the same network, need to report error on console if its managed nodes are not handled.
    unless (@nodes) {
        xCAT::MsgUtils->message("S", "xCAT: grub2 netboot: no valid nodes. Stop the operation on this server.");

        # If non-shared tftproot and non disjoint mode, need to figure out if no nodes here is a normal case.
        if ($request->{'_disparatetftp'}->[0] && $request->{'_disjointmode'}->[0] != 1) {
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
            # Okay, now report error as no nodes are handled.
            if ($req2manage == 0) {
                xCAT::MsgUtils->trace(0, "d", "grub2: No nodes are required to be managed on this server");
                return;
            }
        }
        my $rsp;
        $rsp->{errorcode}->[0] = 1;
        $rsp->{error}->[0]     = "Failed to generate grub2 configurations for some node(s) on $::myxcatname. Check xCAT log file for more details.";
        $callback->($rsp);
        return;
    }

    #now run the begin part of the prescripts
    unless ($args[0] eq '') {    # or $args[0] eq 'enact') {
        $errored = 0;
        if ($request->{'_disparatetftp'}->[0]) { #the call is distrubuted to the service node already, so only need to handle my own children
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: the call is distrubuted to the service node already, so only need to handle my own children");
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: issue runbeginpre request");
            $sub_req->({ command => ['runbeginpre'],
                    node => \@nodes,
                    arg => [ $args[0], '-l' ] }, \&pass_along);
        } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: nodeset did not distribute to the service node");
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: issue runbeginpre request");
            $sub_req->({ command => ['runbeginpre'],
                    node => \@rnodes,
                    arg => [ $args[0] ] }, \&pass_along);
        }
        if ($errored) {
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: Failed in running begin prescripts.");
            return if ($errored > 1);
        }
    }

    #back to normal business
    my $inittime = 0;
    if (exists($request->{inittime})) { $inittime = $request->{inittime}->[0]; }
    if (!$inittime) { $inittime = 0; }

    my %bphash;
    unless ($args[0] eq '') {    # or $args[0] eq 'enact') {
        $errored = 0;
        xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: issue setdestiny request");
        $sub_req->({ command => ['setdestiny'],
                node     => \@nodes,
                inittime => [$inittime],
                arg      => \@args,
                bootparams => \%bphash
                }, \&pass_along);
        if ($errored) {
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: Failed in processing setdestiny.");
            return if ($errored > 1);
        }
    }

    xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: starting to handle configuration...");
    my $chaintab = xCAT::Table->new('chain', -create => 1);
    my $chainhash = $chaintab->getNodesAttribs(\@nodes, ['currstate']);
    my $noderestab = xCAT::Table->new('noderes', -create => 1);
    my $nodereshash = $noderestab->getNodesAttribs(\@nodes, ['tftpdir']);
    my $mactab = xCAT::Table->new('mac', -create => 1);
    my $machash = $mactab->getNodesAttribs(\@nodes, ['mac']);
    my $nrtab = xCAT::Table->new('noderes', -create => 1);
    my $nrhash = $nrtab->getNodesAttribs(\@nodes, [ 'servicenode', 'tftpserver', 'xcatmaster', 'netboot' , 'installnic']);
    my $typetab = xCAT::Table->new('nodetype', -create => 1);
    my $typehash = $typetab->getNodesAttribs(\@nodes, [ 'os', 'provmethod', 'arch', 'profile' ]);
    my $linuximgtab = xCAT::Table->new('linuximage', -create => 1);
    my $osimagetab  = xCAT::Table->new('osimage',    -create => 1);

    my $rc;
    my $errstr;

    my @normalnodeset = ();
    foreach (@nodes) {
        next if (exists($failurenodes{$_}));

        my $tftpdir = $globaltftpdir;
        if ($nodereshash->{$_} and $nodereshash->{$_}->[0] and $nodereshash->{$_}->[0]->{tftpdir}) {
            $tftpdir = $nodereshash->{$_}->[0]->{tftpdir};
        }

        my %response;
        $response{node}->[0]->{name}->[0] = $_;
        if ($args[0]) { # Send it on to the destiny plugin, then setstate
            my $ent          = $typehash->{$_}->[0];
            my $nodearch     = $ent->{'arch'};
            my $nodeos       = $ent->{'os'};
            my $osimgname    = $ent->{'provmethod'};
            my $linuximghash = undef;
            unless ($osimgname =~ /^(install|netboot|statelite)$/) {
                $linuximghash = $linuximgtab->getAttribs({ imagename => $osimgname }, 'boottarget', 'addkcmdline');
            }

            ($rc, $errstr) = setstate($_, \%bphash, $chainhash, $machash, $tftpdir, $nrhash, $linuximghash, $nodearch, $nodeos);
            if ($rc) {
                $response{node}->[0]->{errorcode}->[0] = $rc;
                $response{node}->[0]->{error}->[0]    = $errstr;
                $failurenodes{$_} = 1;
                $callback->(\%response);
            } else {
                push @normalnodeset, $_;
            }

        }
    }    # end of foreach node
    xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: Finish to handle configurations");

    #Don't bother to try dhcp binding changes if sub_req not passed, i.e. service node build time
    unless ($inittime) {

        #dhcp stuff
        my $do_dhcpsetup = 1;
        my @entries      = xCAT::TableUtils->get_site_attribute("dhcpsetup");
        my $t_entry      = $entries[0];
        if (defined($t_entry)) {
            if ($t_entry =~ /0|n|N/) { $do_dhcpsetup = 0; }
        }
        # For offline operation, remove the dhcp entries whatever dhcpset is disabled in site ( existing code logic, just keep it as is)
        if ($do_dhcpsetup || $args[0] eq 'offline') {
            my @parameter;
            push @parameter, '-l' if ($request->{'_disparatetftp'}->[0]);
            push @parameter, '-d' if ($args[0] eq 'offline');
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue makedhcp request");

            $sub_req->({ command => ['makedhcp'],
                         arg => \@parameter,
                         node => \@normalnodeset }, $callback);
        } else {
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: dhcpsetup=$do_dhcpsetup");
        }
    }

    #now run the end part of the prescripts
    unless ($args[0] eq '') {    # or $args[0] eq 'enact')
        $errored = 0;
        if ($request->{'_disparatetftp'}->[0]) { #the call is distrubuted to the service node already, so only need to handles my own children
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: issue runendpre request");
            $sub_req->({ command => ['runendpre'],
                    node => \@normalnodeset,
                    arg => [ $args[0], '-l' ] }, \&pass_along);
        } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: issue runendpre request");
            $sub_req->({ command => ['runendpre'],
                    node => \@normalnodeset,
                    arg => [ $args[0] ] }, \&pass_along);
        }
        if ($errored) {
            xCAT::MsgUtils->trace($verbose_on_off, "d", "grub2: Failed in running end prescripts.");
        }
    }

    # Return error codes if there are failed nodes
    if (%failurenodes) {
        my $rsp;
        $rsp->{errorcode}->[0] = 1;
        $rsp->{error}->[0]     = "Failed to generate grub2 configurations for some node(s) on $::myxcatname. Check xCAT log file for more details.";
        $callback->($rsp);
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
             function.The key is the nodeset status and the value is a pointer
             to an array of nodes.
    Returns:
       (return code, error message)
=cut

#-----------------------------------------------------------------------------
sub getNodesetStates {
    my $noderef = shift;
    if ($noderef =~ /xCAT_plugin::grub2/) {
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
            $stat = $a[0];
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
