# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::petitboot;

use File::Path;
use Getopt::Long;
use xCAT::Table;
use Sys::Syslog;
use xCAT::Scope;
use xCAT::Usage;
my $globaltftpdir = xCAT::TableUtils->getTftpDir();

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> osimage[=<imagename>]",
);

my $httpmethod = "http";
my $httpport   = "80";

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
        if (-r $tftpdir . "/petitboot/" . $node) {
            my $fhand;
            open($fhand, $tftpdir . "/petitboot/" . $node);
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

  This function will manipulate the petitboot structure to match what the noderes/chain tables indicate the node should be booting.

=cut

    my $node         = shift;
    my %bphash       = %{ shift() };
    my %chainhash    = %{ shift() };
    my %machash      = %{ shift() };
    my $tftpdir      = shift;
    my %nrhash       = %{ shift() };
    my $linuximghash = shift();
    my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
      #my $nodereshash=$noderestab->getNodesAttribs(\@nodes,['tftpdir','xcatmaster','nfsserver', 'servicenode']);

    if ($kern->{kernel} !~ /^$tftpdir/) {
        my $nodereshash = $nrhash{$node}->[0];
        my $installsrv;
        if ($nodereshash and $nodereshash->{nfsserver}) {
            $installsrv = $nodereshash->{nfsserver};
        } elsif ($nodereshash->{xcatmaster}) {
            $installsrv = $nodereshash->{xcatmaster};
        } else {
            $installsrv = '!myipfn!';
        }
        $kern->{kernel} = "$httpmethod://$installsrv:$httpport$tftpdir/" . $kern->{kernel};
        $kern->{initrd} = "$httpmethod://$installsrv:$httpport$tftpdir/" . $kern->{initrd};
    }
    if ($kern->{kcmdline} =~ /!myipfn!/ or $kern->{kernel} =~ /!myipfn!/) {
        my $ipfn;
        my @ipfnd = xCAT::NetworkUtils->my_ip_facing($node);

        if ($ipfnd[0] == 1) {
            $::callback->(
                {
                    error     => [ $ipfnd[1] ],
                    errorcode => [1]
                });
            return;
        }
        elsif ($ipfnd[0] == 2) {
            my $servicenodes = $nrhash{$node}->[0];
            if ($servicenodes and $servicenodes->{servicenode}) {
                my @sns = split /,/, $servicenodes->{servicenode};
                foreach my $sn (@sns) {

                    # We are in the service node pools, print error if no facing ip.
                    if (xCAT::InstUtils->is_me($sn)) {
                        $::callback->(
                            {
                                error => [
                                    "$::myxcatname: $ipfnd[1] on service node $sn"
                                ],
                                errorcode => [1]
                            }
                        );
                        return;
                    }
                }
            } else {
                $::callback->(
                    {
                        error => [
                            "$::myxcatname: $ipfnd[1]"
                        ],
                        errorcode => [1]
                    }
                );
                return;
            }
        } else {
            $ipfn = $ipfnd[1];
            $kern->{kernel} =~ s/!myipfn!/$ipfn/g;
            $kern->{initrd} =~ s/!myipfn!/$ipfn/g;
            $kern->{kcmdline} =~ s/!myipfn!/$ipfn/g;
        }
    }


    if ($kern->{addkcmdline}) {
        $kern->{kcmdline} .= " " . $kern->{addkcmdline};
    }

    if ($linuximghash and $linuximghash->{'addkcmdline'})
    {
        unless ($linuximghash->{'boottarget'})
        {
            $kern->{kcmdline} .= " " . $linuximghash->{'addkcmdline'};
        }
    }

    my $bootloader_root = "$tftpdir/petitboot";
    unless (-d "$bootloader_root") {
        mkpath("$bootloader_root");
    }
    my $nodemac;

    my $cref = $chainhash{$node}->[0]; #$chaintab->getNodeAttribs($node,['currstate']);

    my $pcfg;
    # remove the old boot configuration file and create a new one, but only if not offline directive
    unlink("$bootloader_root/" . $node);
    if ($cref and $cref->{currstate} ne "offline") {
        open($pcfg, '>', "$bootloader_root/" . $node);
        print $pcfg "#" . $cref->{currstate} . "\n";
    }
    $normalnodes{$node} = 1;   #Assume a normal netboot (well, normal dhcp,
                               #which is normally with a valid 'filename' field,
      #but the typical ppc case will be 'special' makedhcp
      #to clear the filename field, so the logic is a little
      #opposite
      #  $sub_req->({command=>['makedhcp'], #This is currently batched elswhere
      #         node=>[$node]},$callback);  #It hopefully will perform correctly

    if ($cref and $cref->{currstate} eq "boot") {
        $breaknetbootnodes{$node} = 1;
        delete $normalnodes{$node}; #Signify to omit this from one makedhcp command
         #$sub_req->({command=>['makedhcp'], #batched elsewhere, this code is stale, hopefully
         #       node=>[$node],
         #        arg=>['-s','filename = \"xcat/nonexistant_file_to_intentionally_break_netboot_for_localboot_to_work\";']},$callback);
         #print $pcfg "bye\n";
        close($pcfg);
    } elsif ($kern and $kern->{kernel} and $cref and $cref->{currstate} ne "offline") {

        #It's time to set petitboot for this node to boot the kernel, but only if not offline directive
        my $label = "xCAT";
        if ($cref->{currstate} eq "shell") {
            $label = "xCAT Genesis shell";
        }
        print $pcfg "default $label\n";
        print $pcfg "label $label\n";
        print $pcfg "\tkernel $kern->{kernel}\n";
        if ($kern and $kern->{initrd}) {
            print $pcfg "\tinitrd " . $kern->{initrd} . "\n";
        }
        if ($kern and $kern->{kcmdline}) {
            print $pcfg "\tappend \"" . $kern->{kcmdline} . "\"\n";
        }
        close($pcfg);
    } else {    #TODO: actually, should possibly default to xCAT image?
                #print $pcfg "bye\n";
        close($pcfg);
    }
    my $ip = xCAT::NetworkUtils->getipaddr($node);
    unless ($ip) {
        syslog("local1|err", "xCAT unable to resolve IP for $node in petitboot plugin");
        return;
    }

    my @ipa = split(/\./, $ip);
    my $pname = sprintf("%02x%02x%02x%02x", @ipa);
    $pname = uc($pname);

    # remove the old boot configuration file and copy (link) a new one, but only if not offline directive
    unlink("$tftpdir/" . $pname);
    if ($cref and $cref->{currstate} ne "offline") {
        link("$bootloader_root/" . $node, "$tftpdir/" . $pname);
    }
    return;
}



my $errored = 0;

sub pass_along {
    my $resp = shift;

    #    print Dumper($resp);

    $callback->($resp);
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored = 1;
    }
    foreach (@{ $resp->{node} }) {
        if ($_->{error} or $_->{errorcode}) {
            $errored = 1;
        }
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

    if ($ARGV[0] ne "stat" && $ALLFLAG) {
        my %rsp;
        $rsp{error}->[0] = "'-a' could only be used with 'stat' subcommand.";
        $rsp{errorcode}->[0] = 1;
        $callback1->(\%rsp);
        return;
    }

    #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when
    #if they specify no sharedtftp in site table
    my @entries = xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $t_entry = $entries[0];
    xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: sharedtftp = $t_entry");
    if (defined($t_entry) and ($t_entry == 0 or $t_entry =~ /no/i)) {

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
        if ($req->{inittime}->[0]) {
            return [$req];
        }
        if (@CN > 0) {    # if compute nodes only, then broadcast to servic enodes

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
            xCAT::MsgUtils->trace(0, "d", "petitboot: disjointdhcps=$mynodeonly");

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
    $request    = shift;
    $callback   = shift;
    $::callback = $callback;
    $sub_req    = shift;
    my $command = $request->{command}->[0];
    %breaknetbootnodes = ();
    %normalnodes       = (); # It will be fill-up by method: setstate.

    #>>>>>>>used for trace log start>>>>>>>
    my @args = ();
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

    if ($::XCATSITEVALS{"httpmethod"}) { $httpmethod = $::XCATSITEVALS{"httpmethod"}; }
    if ($::XCATSITEVALS{"httpport"}) { $httpport = $::XCATSITEVALS{"httpport"}; }

    my @hostinfo = xCAT::NetworkUtils->determinehostname();
    $::myxcatname = $hostinfo[-1];
    xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: running on $::myxcatname");
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
    my %failurenodes = ();
    my %preparednodes = ();
    foreach (@rnodes) {
        my $ipret = xCAT::NetworkUtils->checkNodeIPaddress($_);
        my $errormsg = $ipret->{'error'};
        my $nodeip = $ipret->{'ip'};
        if ($errormsg) {# Add the node to failure set
            xCAT::MsgUtils->trace(0, "E", "petitboot: Defined IP address of $_ is $nodeip. $errormsg");
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
                xCAT::MsgUtils->trace(0, "W", "petitboot: configuration file was not created for [$_] because the node is not on the same network as this server");
                delete $preparednodes{$_};
            }
        }
    } else {
        @nodes = keys %preparednodes;
    }

    my $str_node = join(" ", @nodes);
    xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: nodes are $str_node") if ($str_node);

    # Return directly if no nodes in the same network, need to report error on console if its managed nodes are not handled.
    unless (@nodes) {
        xCAT::MsgUtils->message("S", "xCAT: petitboot netboot: no valid nodes. Stop the operation on this server.");

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
            if ($req2manage == 0) {
                #No nodes are required to be handled, quit without error.
                return;
            }
        }
        # Okay, now report error as no nodes are handled.
        my $rsp;
        $rsp->{errorcode}->[0] = 1;
        $rsp->{error}->[0]     = "Failed to generate petitboot configurations for some node(s) on $::myxcatname. Check xCAT log file for more details.";
        $callback->($rsp);
        return;
    }

    #now run the begin part of the prescripts
    unless ($args[0] eq '') {    # or $args[0] eq 'enact') {
        $errored = 0;
        if ($request->{'_disparatetftp'}->[0]) { #the call is distrubuted to the service node already, so only need to handle my own children
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: the call is distrubuted to the service node already, so only need to handle my own children");
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue runbeginpre request");
            $sub_req->({ command => ['runbeginpre'],
                    node => \@nodes,
                    arg => [ $args[0], '-l' ] }, \&pass_along);
        } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: nodeset did not distribute to the service node");
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue runbeginpre request");
            $sub_req->({ command => ['runbeginpre'],
                    node => \@nodes,
                    arg => [ $args[0] ] }, \&pass_along);
        }
        if ($errored) {
            my $rsp;
            $rsp->{errorcode}->[0] = 1;
            $rsp->{error}->[0]     = "Failed in running begin prescripts.\n";
            $callback->($rsp);
            return;
        }
    }

    #back to normal business
    my $inittime = 0;
    if (exists($request->{inittime})) { $inittime = $request->{inittime}->[0]; }
    if (!$inittime) { $inittime = 0; }

    my %bphash;
    unless ($args[0] eq '') {    # or $args[0] eq 'enact') {
        $errored = 0;
        xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue setdestiny request");
        $sub_req->({ command => ['setdestiny'],
                node     => \@nodes,
                inittime => [$inittime],
                arg      => \@args,
                bootparams => \%bphash},
                \&pass_along);
        if ($errored) { 
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: Failed in processing setdestiny.  Processing will not continue.");
            return; 
        }
    }

    # Fix the bug 4611: PowerNV stateful CN provision will hang at reboot stage#
    if ($args[0] eq 'next') {
        $sub_req->({ command => ['rsetboot'],
                node => \@nodes,
                arg  => ['default'],
                #todo: do not need to pass the XCAT_OPENBMC_DEVEL after the openbmc dev work finish
                #this does not hurt anything for other plugins
                environment => {XCAT_OPENBMC_DEVEL=>"YES"}
                });
        xCAT::MsgUtils->message("S", "xCAT: petitboot netboot: clear node(s): @nodes boot device setting.");
    }

    xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: starting to handle configuration...");
    my $chaintab = xCAT::Table->new('chain', -create => 1);
    my $chainhash = $chaintab->getNodesAttribs(\@nodes, ['currstate']);
    my $noderestab = xCAT::Table->new('noderes', -create => 1);
    my $nodereshash = $noderestab->getNodesAttribs(\@nodes, [ 'tftpdir', 'xcatmaster', 'nfsserver', 'servicenode' ]);
    my $mactab = xCAT::Table->new('mac', -create => 1);
    my $machash = $mactab->getNodesAttribs(\@nodes, ['mac']);
    my $typetab = xCAT::Table->new('nodetype', -create => 1);
    my $typehash = $typetab->getNodesAttribs(\@nodes, [ 'os', 'provmethod', 'arch', 'profile' ]);
    my $linuximgtab = xCAT::Table->new('linuximage', -create => 1);
    my $osimagetab  = xCAT::Table->new('osimage',    -create => 1);

    my $rc;
    my $errstr;

    my $tftpdir;
    foreach (@nodes) {
        my %response;
        if ($nodereshash->{$_} and $nodereshash->{$_}->[0] and $nodereshash->{$_}->[0]->{tftpdir}) {
            $tftpdir = $nodereshash->{$_}->[0]->{tftpdir};
        } else {
            $tftpdir = $globaltftpdir;
        }
        $response{node}->[0]->{name}->[0] = $_;
        if ($args[0]) { # send it on to the destiny plugin, then setstate
            my $ent       = $typehash->{$_}->[0];
            my $osimgname = $ent->{'provmethod'};
            my $linuximghash = $linuximgtab->getAttribs({ imagename => $osimgname }, 'boottarget', 'addkcmdline');


            ($rc, $errstr) = setstate($_, \%bphash, $chainhash, $machash, $tftpdir, $nodereshash, $linuximghash);
            if ($rc) {
                $response{node}->[0]->{errorcode}->[0] = $rc;
                $response{node}->[0]->{errorc}->[0]    = $errstr;
                $callback->(\%response);
            }
        }
    }    # end of foreach node
    xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: Finish to handle configurations");

    my @normalnodeset = keys %normalnodes;
    my @breaknetboot  = keys %breaknetbootnodes;
    my %osimagenodehash;
    for my $nn (@normalnodeset) {

        #record the os version for node
        my $ent     = $typehash->{$nn}->[0];
        my $osimage = $ent->{'provmethod'};
        push @{ $osimagenodehash{$osimage} }, $nn;
    }

    #Don't bother to try dhcp binding changes if sub_req not passed, i.e. service node build time
    unless (($inittime) || ($args[0] eq 'offline')) {

        #dhcp stuff
        my $do_dhcpsetup = 1;
        my @entries      = xCAT::TableUtils->get_site_attribute("dhcpsetup");
        my $t_entry      = $entries[0];
        if (defined($t_entry)) {
            if ($t_entry =~ /0|n|N/) { $do_dhcpsetup = 0; }
        }
        if ($do_dhcpsetup) {
            my @parameter;
            push @parameter, '-l' if ($request->{'_disparatetftp'}->[0]);
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue makedhcp request");

            $sub_req->({ command => ['makedhcp'],
                         arg => \@parameter,
                         node => \@normalnodeset }, $callback);
        } else {
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: dhcpsetup=$do_dhcpsetup");
        }

    }

    if ($args[0] eq 'offline') {

        # If nodeset directive was offline we need to remove dhcp entries
        $sub_req->({ command => ['makedhcp'], arg => ['-d'], node => \@normalnodeset }, $callback);
    }

    #now run the end part of the prescripts
    unless ($args[0] eq '') {    # or $args[0] eq 'enact')
        $errored = 0;
        if ($request->{'_disparatetftp'}->[0]) { #the call is distrubuted to the service node already, so only need to handles my own children
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue runendpre request");
            $sub_req->({ command => ['runendpre'],
                    node => \@nodes,
                    arg => [ $args[0], '-l' ] }, \&pass_along);
        } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off, "d", "petitboot: issue runendpre request");
            $sub_req->({ command => ['runendpre'],
                    node => \@nodes,
                    arg => [ $args[0] ] }, \&pass_along);
        }
        if ($errored) {
            my $rsp;
            $rsp->{errorcode}->[0] = 1;
            $rsp->{error}->[0]     = "Failed in running end prescripts\n";
            $callback->($rsp);
            return;
        }
    }

    # Return error codes if there are failed nodes
    if (%failurenodes) {
        my $rsp;
        $rsp->{errorcode}->[0] = 1;
        $rsp->{error}->[0]     = "Failed to generate petitboot configurations for some node(s) on $::myxcatname. Check xCAT log file for more details.";
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
    if ($noderef =~ /xCAT_plugin::petitboot/) {
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
