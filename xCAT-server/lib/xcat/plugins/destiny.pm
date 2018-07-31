# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::destiny;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::NodeRange;
use Data::Dumper;
use xCAT::Utils;
use xCAT::TableUtils;
use Sys::Syslog;
use xCAT::GlobalDef;
use xCAT::Table;
use xCAT_monitoring::monitorctrl;
use Getopt::Long;
use strict;

my $request;
my $callback;
my $subreq;
my $errored = 0;

#DESTINY SCOPED GLOBALS
my $chaintab;
my $iscsitab;
my $typetab;
my $restab;

#my $sitetab;
my $hmtab;
my $tftpdir = "/tftpboot";


my $nonodestatus = 0;
my %failurenodes = ();

#my $sitetab = xCAT::Table->new('site');
#if ($sitetab) {
#(my $ref1) = $sitetab->getAttribs({key => 'nodestatus'}, 'value');
my @entries    = xCAT::TableUtils->get_site_attribute("nodestatus");
my $site_entry = $entries[0];
if (defined($site_entry)) {
    if ($site_entry =~ /0|n|N/) { $nonodestatus = 1; }
}

#}


sub handled_commands {
    return {
        setdestiny  => "destiny",
        getdestiny  => "destiny",
        nextdestiny => "destiny"
      }
}

sub process_request {
    $request  = shift;
    $callback = shift;
    $subreq   = shift;
    if (not $::XCATSITEVALS{disablecredfilecheck} and xCAT::Utils->isMN()) {
        my $result = xCAT::TableUtils->checkCredFiles($callback);
    }
    if ($request->{command}->[0] eq 'getdestiny') {
        xCAT::MsgUtils->trace(0, "d", "destiny->process_request: starting getdestiny...");
        my @nodes;
        if ($request->{node}) {
            if (ref($request->{node})) {
                @nodes = @{ $request->{node} };
            } else {
                @nodes = ($request->{node});
            }
        } else {    # a client asking for it's own destiny.
            unless ($request->{'_xcat_clienthost'}->[0]) {
                $callback->({ destiny => ['discover'] });
                return;
            }
            my ($node) = noderange($request->{'_xcat_clienthost'}->[0]);
            unless ($node) {    # it had a valid hostname, but isn't a node
                $callback->({ destiny => ['discover'] });
                return;
            }
            @nodes = ($node);
        }
        getdestiny(0, \@nodes);

    } elsif ($request->{command}->[0] eq 'nextdestiny') {
        xCAT::MsgUtils->trace(0, "d", "destiny->process_request: starting nextdestiny...");
        nextdestiny(0, 1);    #it is called within dodestiny

    } elsif ($request->{command}->[0] eq 'setdestiny') {
        xCAT::MsgUtils->trace(0, "d", "destiny->process_request: starting setdestiny...");
        setdestiny($request, 0);

    }
    xCAT::MsgUtils->trace(0, "d", "destiny->process_request: processing is finished for " . $request->{command}->[0]);
}

sub relay_response {
    my $resp = shift;
    return unless ($resp); 

    $callback->($resp);
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored = 1;
    }

    my $failure = 0;
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

sub setdestiny {
    my $req      = shift;
    my $flag     = shift;
    my $noupdate = shift;
    $chaintab = xCAT::Table->new('chain', -create => 1);
    my $bphash = $req->{bootparams};

    @ARGV = @{ $req->{arg} };
    my $noupdateinitrd;
    my $ignorekernelchk;

    #>>>>>>>used for trace log>>>>>>>
    my $verbose;
    GetOptions('noupdateinitrd' => \$noupdateinitrd,
        'ignorekernelchk' => \$ignorekernelchk,
        'V'               => \$verbose);       #>>>>>>>used for trace log>>>>>>>

    #>>>>>>>used for trace log start>>>>>>>
    my $verbose_on_off = 0;
    if ($verbose) { $verbose_on_off = 1; }

    #>>>>>>>used for trace log end>>>>>>>

    if (@{ $req->{node} } == 0) {
        xCAT::MsgUtils->trace($verbose, "d", "destiny->setdestiny: no nodes left to process, we are done");
        return; 
    }
    my @nodes = @{ $req->{node} };
    my $bptab = xCAT::Table->new('bootparams', -create => 1);
    my %tempbh = %{ $bptab->getNodesAttribs(\@nodes, [qw(addkcmdline)]) };
    while(my ($key, $value) = each(%tempbh)) {
        if ($value && $value->[0]->{"addkcmdline"}) {
            my $addkcmdline = $value->[0]->{"addkcmdline"};
            # $key is node name
            $bphash->{$key}->[0]->{"addkcmdline"} = $addkcmdline;
        }
    }
    $bptab->close();

    my $state = $ARGV[0];
    my $reststates;
    my %nstates;
    # to support the case that the state could be runimage=xxx,runimage=yyy,osimage=xxx
    ($state, $reststates) = split(/,/, $state, 2);
    chomp($state);

    if ($state eq "enact") {
        my $nodetypetab = xCAT::Table->new('nodetype', -create => 1);
        my %nodestates;
        my %stents = %{ $chaintab->getNodesAttribs($req->{node}, "currstate") };
        my %ntents = %{ $nodetypetab->getNodesAttribs($req->{node}, "provmethod") };
        my $state;
        my $sninit = 0;
        if (exists($req->{inittime})) {    # this is called in AAsn.pm
            $sninit = $req->{inittime}->[0];
        }

        foreach (@{ $req->{node} }) { #First, build a hash of all of the states to attempt to keep things as aggregated as possible
            if ($stents{$_}->[0]->{currstate}) {
                $state = $stents{$_}->[0]->{currstate};
                $state =~ s/ .*//;

                #skip the node if state=ondiscover
                if ($state eq 'ondiscover') {
                    next;
                }

                #get the osimagename if nodetype.provmethod has osimage specified
                #use it for both sninit and genesis operating
                if (($state eq 'install') || ($state eq 'netboot') || ($state eq 'statelite')) {
                    my $osimage = $ntents{$_}->[0]->{provmethod};
                    if (($osimage) && ($osimage ne 'install') && ($osimage ne 'netboot') && ($osimage ne 'statelite')) {
                        $state = "osimage=$osimage";
                    }
                }
                push @{ $nodestates{$state} }, $_;
            }
        }
        foreach (keys %nodestates) {
            $req->{arg}->[0] = $_;
            $req->{node} = $nodestates{$_};
            setdestiny($req, 30, 1); #ludicrous flag to denote no table updates can be inferred.
        }
        return;
    } elsif ($state eq "next") {
        return nextdestiny($flag + 1); #this is special case where updateflag is called
    } elsif ($state eq "iscsiboot") {
        my $iscsitab = xCAT::Table->new('iscsi');
        unless ($iscsitab) {
            $callback->({ error => "Unable to open iscsi table to get iscsiboot parameters", errorcode => [1], errorabort => [1] });
        }
        my $nodetype = xCAT::Table->new('nodetype');
        my $ntents = $nodetype->getNodesAttribs($req->{node}, [qw(os arch profile)]);
        my $ients = $iscsitab->getNodesAttribs($req->{node}, [qw(kernel kcmdline initrd)]);
        foreach (@{ $req->{node} }) {
            my $ient = $ients->{$_}->[0]; #$iscsitab->getNodeAttribs($_,[qw(kernel kcmdline initrd)]);
            my $ntent = $ntents->{$_}->[0];
            unless ($ient and $ient->{kernel}) {
                unless ($ntent and $ntent->{arch} =~ /x86/ and -f ("$tftpdir/undionly.kpxe" or -f "$tftpdir/xcat/xnba.kpxe")) {
                    $failurenodes{$_} = 1;
                    xCAT::MsgUtils->report_node_error($callback, $_, "No iscsi boot data available");
                } #If x86 node and undionly.kpxe exists, presume they know what they are doing
                next;
            }
            $bphash->{kernel} = $ient->{kernel};
            if ($ient->{initrd})   { $bphash->{initrd}   = $ient->{initrd} }
            if ($ient->{kcmdline}) { $bphash->{kcmdline} = $ient->{kcmdline} }
        }
    } elsif ($state =~ /ondiscover/) {
        my $target;
        if ($state =~ /=/) {
            ($state, $target) = split '=', $state, 2;
        }
        if(!$target){
            $callback->({ error => "invalid argument: \"$state\"", errorcode => [1] });
            return;
        }
        my @cmds = split '\|', $target;
        foreach my $tmpnode (@{ $req->{node} }) {
            foreach my $cmd (@cmds) {
                my $action;
               ($cmd, $action) = split ':', $cmd;
                my $runcmd = "$cmd $tmpnode $action";
                xCAT::Utils->runcmd($runcmd, 0);
                xCAT::MsgUtils->trace($verbose, "d", "run ondiscover command: $runcmd");
            }
        }
    } elsif ($state =~ /^install[=\$]/ or $state eq 'install' or $state =~ /^netboot[=\$]/ or $state eq 'netboot' or $state eq "image" or $state eq "winshell" or $state =~ /^osimage/ or $state =~ /^statelite/) {
        my $target;
        my $action;
        my $rawstate=$state;
        if ($state =~ /=/) {
            ($state, $target) = split '=', $state, 2;

            if(!$target){
                $callback->({ error => "invalid argument: \"$rawstate\"", errorcode => [1] });
                return;
            }
 
            if ($target =~ /:/) {
                ($target, $action) = split ':', $target, 2;
            }
        } else {
            if ($state =~ /:/) {
                ($state, $action) = split ':', $state, 2;
            }
        }
        xCAT::MsgUtils->trace($verbose, "d", "destiny->setdestiny: state=$state, target=$target, action=$action");
        my %state_hash;
        # 1, Set an initial state for all requested nodes
        foreach my $tmpnode (@{ $req->{node} }) {
            next if ($failurenodes{$tmpnode});
            $state_hash{$tmpnode} = $state;
        }

        # 2, Filter those unsuitable nodes in 'state_hash'
        my $nodetypetable = xCAT::Table->new('nodetype', -create => 1);
        my $noderestable  = xCAT::Table->new('noderes',  -create => 1);
        my $nbents = $noderestable->getNodeAttribs($req->{node}->[0], ["netboot"]); # It is assumed that all nodes has the same `netboot` attribute
        my $curnetboot = $nbents->{netboot};

        if ($state ne 'osimage') {
            $callback->({ error => "The options \"install\", \"netboot\", and \"statelite\" have been deprecated, use \"osimage=<osimage_name>\" instead.", errorcode => [1], errorabort => [1] });
            return;        

            my $updateattribs;
            if ($target) {
                my $archentries = $nodetypetable->getNodesAttribs($req->{node}, ['supportedarchs']);
                if ($target =~ /^([^-]*)-([^-]*)-(.*)/) {
                    $updateattribs->{os}      = $1;
                    $updateattribs->{arch}    = $2;
                    $updateattribs->{profile} = $3;
                    my $nodearch = $2;
                    foreach (@{ $req->{node} }) {
                        if ($archentries->{$_}->[0]->{supportedarchs} and $archentries->{$_}->[0]->{supportedarchs} !~ /(^|,)$nodearch(\z|,)/) {
                            xCAT::MsgUtils->report_node_error($callback, $_, 
                                "Requested architecture " . $nodearch . " is not one of the architectures supported by $_  (per nodetype.supportedarchs, it supports " . $archentries->{$_}->[0]->{supportedarchs} . ")"
                                );
                            $failurenodes{$_} = 1;
                            next;
                        }
                    }    #end foreach
                } else {
                    $updateattribs->{profile} = $target;
                }
            }    #end if($target)

            $updateattribs->{provmethod} = $state;
            my @tmpnodelist = ();
            foreach (@{ $req->{node} }) {
                if ($failurenodes{$_}) {
                    delete $state_hash{$_};
                    next;
                }
                push @tmpnodelist, $_;
            }
            $nodetypetable->setNodesAttribs(\@tmpnodelist, $updateattribs);

        } else {    #state is osimage
            if ($target) {
                if (@{ $req->{node} } == 0) { return; }
                my $osimagetable = xCAT::Table->new('osimage');
                (my $ref) = $osimagetable->getAttribs({ imagename => $target }, 'provmethod', 'osvers', 'profile', 'osarch', 'imagetype');
                if ($ref) {
                    if ($ref->{provmethod}) {
                        $state = $ref->{provmethod};

                    } else {
                        $callback->({ errorcode => [1], error => "osimage.provmethod for $target must be set.", errorabort => [1] });
                        return;
                    }
                } else {
                    $callback->({ errorcode => [1], error => "Cannot find the OS image $target in the osimage table.", errorabort => [1] });
                    return;
                }

                my $netbootval = xCAT::Utils->lookupNetboot($ref->{osvers}, $ref->{osarch}, $ref->{imagetype});
                unless ($netbootval =~ /$curnetboot/i) {

                    #$errored =1;
                    $callback->({ warning => [ join(",", @{ $req->{node} }) . ": $curnetboot might be invalid when provisioning $target,valid options: \"$netbootval\". \nFor more details see the 'netboot' description in the output of \"tabdump -d noderes\"." ] });

                    #return;
                }


                my $updateattribs;
                $updateattribs->{provmethod} = $target;
                $updateattribs->{profile}    = $ref->{profile};
                $updateattribs->{os}         = $ref->{osvers};
                $updateattribs->{arch}       = $ref->{osarch};
                my @tmpnodelist = ();
                foreach ( @nodes ) {
                    if (exists($failurenodes{$_})) {
                        delete $state_hash{$_};
                        next;
                    }
                    $state_hash{$_} = $state;
                    push @tmpnodelist, $_;
                }
                $nodetypetable->setNodesAttribs(\@tmpnodelist, $updateattribs);

            } else {
                my $invalidosimghash;
                my $updatestuff;
                my $nodetypetable = xCAT::Table->new('nodetype', -create => 1);
                my %ntents = %{ $nodetypetable->getNodesAttribs($req->{node}, "provmethod") };

                foreach my $tmpnode (@nodes) {
                    next if (exists($failurenodes{$tmpnode}));

                    my $osimage = $ntents{$tmpnode}->[0]->{provmethod};
                    if (($osimage) && ($osimage ne 'install') && ($osimage ne 'netboot') && ($osimage ne 'statelite')) {
                        if (exists($updatestuff->{$osimage})) { #valid osimage
                            my $vnodes = $updatestuff->{$osimage}->{nodes};
                            push(@$vnodes, $tmpnode);
                            $state_hash{$tmpnode} = $updatestuff->{$osimage}->{state};
                        } elsif (exists($invalidosimghash->{$osimage})) { #valid osimage
                            push(@{ $invalidosimghash->{$osimage}->{nodes} }, $tmpnode);
                            next;
                        }
                        else { #Get a new osimage, to valid it and put invalid osimage into `invalidosimghash`
                            my $osimagetable = xCAT::Table->new('osimage');
                            (my $ref) = $osimagetable->getAttribs({ imagename => $osimage }, 'provmethod', 'osvers', 'profile', 'osarch', 'imagetype');
                            if ($ref) {

                                #check whether the noderes.netboot is set appropriately
                                #if not,push the nodes into $invalidosimghash->{$osimage}->{netboot}
                                my $netbootval = xCAT::Utils->lookupNetboot($ref->{osvers}, $ref->{osarch}, $ref->{imagetype});
                                if ($netbootval =~ /$curnetboot/i) {
                                    1;
                                } else {
                                    push(@{ $invalidosimghash->{$osimage}->{nodes} }, $tmpnode);
                                    $invalidosimghash->{$osimage}->{netboot} = $netbootval;
                                    next;
                                }

                                if ($ref->{provmethod} && $ref->{profile} && $ref->{osvers} && $ref->{osarch}) {
                                    $state = $ref->{provmethod};
                                    $state_hash{$tmpnode} = $state;

                                    $updatestuff->{$osimage}->{state} = $state;
                                    $updatestuff->{$osimage}->{nodes} = [$tmpnode];
                                    $updatestuff->{$osimage}->{profile} = $ref->{profile};
                                    $updatestuff->{$osimage}->{os} = $ref->{osvers};
                                    $updatestuff->{$osimage}->{arch} = $ref->{osarch};
                                } else {
                                    push(@{ $invalidosimghash->{$osimage}->{nodes} }, $tmpnode);
                                    $invalidosimghash->{$osimage}->{error}->[0] = "osimage.provmethod, osimage.osvers, osimage.osarch and osimage.profile for $osimage must be set";
                                    next;
                                }
                            } else {
                                push(@{ $invalidosimghash->{$osimage}->{nodes} }, $tmpnode);
                                $invalidosimghash->{$osimage}->{error}->[0] = "Cannot find the OS image $osimage in the osimage table";
                                next;
                            }
                        }
                    } else {
                        # not supported legacy mode
                        push(@{ $invalidosimghash->{__xcat_legacy_provmethod_mode}->{nodes} }, $tmpnode);
                        $invalidosimghash->{__xcat_legacy_provmethod_mode}->{error}->[0] = "OS image name must be specified in nodetype.provmethod";
                        next;
                    }
                }

                #if any node with inappropriate noderes.netboot,report the warning
                foreach my $tmpimage (keys %$invalidosimghash) {
                    my @fnodes = @{ $invalidosimghash->{$tmpimage}->{nodes} };
                    for (@fnodes) {
                        $failurenodes{$_} = 1;
                        delete $state_hash{$_};
                        if ($invalidosimghash->{$tmpimage}->{error}) {
                            xCAT::MsgUtils->report_node_error($callback, $_, $invalidosimghash->{$tmpimage}->{error}->[0]);
                        }
                    }
                    my $netbootwarn = $invalidosimghash->{$tmpimage}->{netboot};
                    if ($netbootwarn) {
                        my $rsp;
                        $rsp->{warning}->[0] = join(",", @fnodes) . ": $curnetboot might be invalid when provisioning $tmpimage,valid options: \"$netbootwarn\". \nFor more details see the 'netboot' description in the output of \"tabdump -d noderes\".";
                        $callback->($rsp);
                    }
                }

                # upddate DB for the nodes which pass the checking
                foreach my $tmpimage (keys %$updatestuff) {
                    my $updateattribs = $updatestuff->{$tmpimage};
                    my @tmpnodelist   = @{ $updateattribs->{nodes} };

                    delete $updateattribs->{nodes}; #not needed for nodetype table
                    delete $updateattribs->{state}; #node needed for nodetype table
                    $nodetypetable->setNodesAttribs(\@tmpnodelist, $updateattribs);
                }
            }

            if (%state_hash) { # To valide mac here
                my @tempnodes = keys(%state_hash);
                my $mactab = xCAT::Table->new('mac', -create => 1);
                my $machash = $mactab->getNodesAttribs(\@tempnodes, ['mac']);

                foreach (@tempnodes) {
                    my $macs = $machash->{$_}->[0];
                    unless ($macs and $macs->{mac}) {
                        $failurenodes{$_} = 1;
                        xCAT::MsgUtils->report_node_error($callback, $_, "No MAC address available for this node");
                        delete $state_hash{$_};
                    }
                }
            }
        }

        #print Dumper(\%state_hash);
        my @validnodes = keys(%state_hash);
        unless (@validnodes) {
            # just return if no valid nodes left
            $callback->({ errorcode => [1]});
            return;
        }

        #if the postscripts directory exists then make sure it is
        # world readable and executable by root; otherwise wget fails
        my $installdir  = xCAT::TableUtils->getInstallDir();
        my $postscripts = "$installdir/postscripts";
        if (-e $postscripts) {
            my $cmd = "chmod -R a+r $postscripts";
            xCAT::Utils->runcmd($cmd, 0);
            my $rsp = {};
            if ($::RUNCMD_RC != 0)
            {
                $callback->({ info => "$cmd failed" });
            }
        }

        # 3, if precreatemypostscripts=1, create each mypostscript for each valid node
        # otherwise, create it during installation /updatenode
        my $notmpfiles = 0;    # create tmp files if precreate=0
        my $nofiles    = 0;    # create files, do not return array
        my $reqcopy = {%$req};
        $reqcopy->{node} = \@validnodes;
        require xCAT::Postage;
        xCAT::Postage::create_mypostscript_or_not($reqcopy, $callback, $subreq, $notmpfiles, $nofiles);

        # 4, Issue the sub-request for each state in 'state_hash'
        my %state_hash1;
        foreach my $tmpnode (keys(%state_hash)) {
            push @{ $state_hash1{ $state_hash{$tmpnode} } }, $tmpnode;
        }

        #print Dumper(\%state_hash1);
        foreach my $tempstate (keys %state_hash1) {
            my $samestatenodes = $state_hash1{$tempstate};

            #print "state=$tempstate nodes=@$samestatenodes\n";
            xCAT::MsgUtils->trace($verbose_on_off, "d", "destiny->setdestiny: issue mk$tempstate request");
            $errored = 0;
            $subreq->({ command => ["mk$tempstate"],
                    node            => $samestatenodes,
                    noupdateinitrd  => $noupdateinitrd,
                    ignorekernelchk => $ignorekernelchk,
                    bootparams => \$bphash}, \&relay_response);
            if ($errored) {
                # The error messeage for mkinstall/mknetboot/mkstatelite had been output within relay_response function above, don't need to output more
                xCAT::MsgUtils->trace($verbose_on_off, "d", "destiny->setdestiny: Failed in processing mk$tempstate.");
                next if ($errored > 1);
            }


            my $ntents = $nodetypetable->getNodesAttribs($samestatenodes, [qw(os arch profile)]);
            my $updates;
            foreach (@{$samestatenodes}) {
                next if (exists($failurenodes{$_})); #Filter the failure nodes

                $nstates{$_} = $tempstate; #local copy of state variable for mod
                my $ntent = $ntents->{$_}->[0]; #$nodetype->getNodeAttribs($_,[qw(os arch profile)]);
                if ($tempstate ne "winshell") {
                    if ($ntent and $ntent->{os}) {
                        $nstates{$_} .= " " . $ntent->{os};
                    } else {
                        xCAT::MsgUtils->report_node_error($callback, $_, "nodetype.os not defined for $_.");
                        $failurenodes{$_} = 1;
                        next;
                    }
                } else {
                    $nstates{$_} .= " winpe";
                }
                if ($ntent and $ntent->{arch}) {
                    $nstates{$_} .= "-" . $ntent->{arch};
                } else { 
                    xCAT::MsgUtils->report_node_error($callback, $_, "nodetype.arch not defined for $_.");
                    $failurenodes{$_} = 1;
                    next;
                }

                if (($tempstate ne "winshell") && ($tempstate ne "sysclone")) {
                    if ($ntent and $ntent->{profile}) {
                        $nstates{$_} .= "-" . $ntent->{profile};
                    } else {
                        xCAT::MsgUtils->report_node_error($callback, $_, "nodetype.profile not defined for $_.");
                        $failurenodes{$_} = 1;
                        next;
                    }
                }
                $updates->{$_}->{'currchain'} = "boot";
            }
            unless ($tempstate =~ /^netboot|^statelite/) {
                $chaintab->setNodesAttribs($updates);
            }

            if ($action eq "reboot4deploy") {

                # this action is used in the discovery process for deployment of the node
                # e.g. set chain.chain to 'osimage=rhels6.2-x86_64-netboot-compute:reboot4deploy'
                # Set the status of the node to be 'installing' or 'netbooting'
                my %newnodestatus;
                my $newstat = xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($tempstate, "rpower");
                $newnodestatus{$newstat} = $samestatenodes;
                xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
            }
        }
    } elsif ($state eq "shell" or $state eq "standby" or $state =~ /^runcmd/ or $state =~ /^runimage/) {

        if ($state =~ /^runimage/) {         # try to check the existence of the image for runimage

            my @runimgcmds;
            push @runimgcmds, $state;
            if ($reststates) {
                my @rstates = split(/,/, $reststates);
                foreach (@rstates) {
                    if (/^runimage/) {
                        push @runimgcmds, $_;
                    }
                }
            }

            foreach (@runimgcmds) {
                my (undef, $path) = split(/=/, $_);
                if ($path) {
                    if ($path =~ /\$/) { next; } # Ignore the path with including variable like $xcatmaster
                    my $cmd = "wget --spider --timeout 3 --tries=1 $path";
                    my @output = xCAT::Utils->runcmd("$cmd", -1);
                    unless (grep /^Remote file exists/, @output) {
                        $callback->({ error => ["Cannot wget $path. Verify it's downloadable."], errorcode => [1], errorabort => [1]});
                        return;
                    }
                } else {
                    $callback->({ error => "An image path should be specified to runimage.", errorcode => [1], errorabort => [1] });
                    return;
                }
            }
        }

        $restab = xCAT::Table->new('noderes', -create => 1);
        my $nodetype = xCAT::Table->new('nodetype');

        #my $sitetab = xCAT::Table->new('site');
        my $nodehm = xCAT::Table->new('nodehm');
        my $hments = $nodehm->getNodesAttribs(\@nodes, [ 'serialport', 'serialspeed', 'serialflow' ]);

        #(my $portent) = $sitetab->getAttribs({key=>'xcatdport'},'value');
        my @entries    = xCAT::TableUtils->get_site_attribute("xcatdport");
        my $port_entry = $entries[0];

        #(my $mastent) = $sitetab->getAttribs({key=>'master'},'value');
        my @entries      = xCAT::TableUtils->get_site_attribute("master");
        my $master_entry = $entries[0];
        my $enthash      = $nodetype->getNodesAttribs(\@nodes, [qw(arch)]);
        my $resents      = $restab->getNodesAttribs(\@nodes, [qw(xcatmaster)]);
        foreach (@nodes) {
            my $ent = $enthash->{$_}->[0]; #$nodetype->getNodeAttribs($_,[qw(arch)]);
            unless ($ent and $ent->{arch}) {
                $failurenodes{$_} = 1;
                xCAT::MsgUtils->report_node_error($callback, $_, "No archictecture defined in nodetype table for the node.");
                next;
            }
            my $arch = $ent->{arch};
            if ($arch eq "ppc64le" or $arch eq "ppc64el") {
                $arch = "ppc64";
            }
            my $ent = $resents->{$_}->[0]; #$restab->getNodeAttribs($_,[qw(xcatmaster)]);
            my $master;
            my $kcmdline = "quiet ";

            #the node.xcatmaster take precedence
            if ($ent and $ent->{xcatmaster}) {
                $master = $ent->{xcatmaster};
            }
    
            #if node.xcatmaster not specified, take the ip address facing the node
            unless($master){
                my @nxtsrvd = xCAT::NetworkUtils->my_ip_facing($_);
                unless ($nxtsrvd[0]) { 
                    $master = $nxtsrvd[1];                 
                }
            }
            
            #the site.master takes the last precedence
            unless($master){
                if (defined($master_entry)) {
                    $master = $master_entry;
                }
            }
            unless ($master) {
                xCAT::MsgUtils->report_node_error($callback, $_, "No master in site table nor noderes table for the node.");
                $failurenodes{$_} = 1;
                next;
            }

            $ent = $hments->{$_}->[0]; #$nodehm->getNodeAttribs($_,['serialport','serialspeed','serialflow']);
            if ($ent and defined($ent->{serialport})) {
                if ($arch eq "ppc64") {
                    $kcmdline .= "console=tty0 console=hvc" . $ent->{serialport};
                } else {
                    $kcmdline .= "console=tty0 console=ttyS" . $ent->{serialport};
                }

                #$ent = $nodehm->getNodeAttribs($_,['serialspeed']);
                unless ($ent and defined($ent->{serialspeed})) {
                    xCAT::MsgUtils->report_node_error($callback, $_, "serialport defined, but no serialspeed for this node in nodehm table");
                    $failurenodes{$_} = 1;
                    next;
                }
                $kcmdline .= "," . $ent->{serialspeed};

                #$ent = $nodehm->getNodeAttribs($_,['serialflow']);
                $kcmdline .= " ";
            }

            my $xcatdport = "3001";
            if (defined($port_entry)) {
                $xcatdport = $port_entry;
            }
            if (-r "$tftpdir/xcat/genesis.kernel.$arch") {
                my $bestsuffix  = "lzma";
                my $othersuffix = "gz";
                if (-r "$tftpdir/xcat/genesis.fs.$arch.lzma" and -r "$tftpdir/xcat/genesis.fs.$arch.gz") {
                    if (-C "$tftpdir/xcat/genesis.fs.$arch.lzma" > -C "$tftpdir/xcat/genesis.fs.$arch.gz") { #here, lzma is older for whatever reason
                        $bestsuffix  = "gz";
                        $othersuffix = "lzma";
                    }
                }
                if (-r "$tftpdir/xcat/genesis.fs.$arch.$bestsuffix") {
                    $bphash->{$_}->[0]->{kernel} = "xcat/genesis.kernel.$arch";
                    $bphash->{$_}->[0]->{initrd} = "xcat/genesis.fs.$arch.$bestsuffix";
                    $bphash->{$_}->[0]->{kcmdline} = $kcmdline . "xcatd=$master:$xcatdport destiny=$state";
                } else {
                    $bphash->{$_}->[0]->{kernel} = "xcat/genesis.kernel.$arch";
                    $bphash->{$_}->[0]->{initrd} = "xcat/genesis.fs.$arch.$othersuffix";
                    $bphash->{$_}->[0]->{kcmdline} = $kcmdline . "xcatd=$master:$xcatdport destiny=$state";
                }
            } else {    #'legacy' environment
                    $bphash->{$_}->[0]->{kernel} = "xcat/nbk.$arch";
                    $bphash->{$_}->[0]->{initrd} = "xcat/nkfs.$arch.gz";
                    $bphash->{$_}->[0]->{kcmdline} = $kcmdline . "xcatd=$master:$xcatdport";
            }
        }

    } elsif ($state eq "offline" || $state eq "shutdown") {
        1;
    } elsif (!($state eq "boot")) {
        $callback->({ error => ["Unknown state $state requested"], errorcode => [1] });
        exit(1);
    }

    #Exclude the failure nodes
    my @normalnodes = ();
    foreach (@nodes) {
        next if (exists($failurenodes{$_})); #Filter the failure nodes
        push @normalnodes, $_;
    }

    unless (@normalnodes) {
        return;
    }

    #blank out the nodetype.provmethod if the previous provisioning method is not 'install'
    if ($state eq "iscsiboot" or $state eq "boot") {
        my $nodetype   = xCAT::Table->new('nodetype', -create => 1);
        my $osimagetab = xCAT::Table->new('osimage',  -create => 1);
        my $ntents = $nodetype->getNodesAttribs(\@normalnodes, [qw(os arch profile provmethod)]);
        my @nodestoblank = ();
        my %osimage_hash = ();
        foreach (@normalnodes) {
            my $ntent = $ntents->{$_}->[0];

            #if the previous nodeset staute is not install, then blank nodetype.provmethod
            if ($ntent and $ntent->{provmethod}) {
                my $provmethod = $ntent->{provmethod};
                if (($provmethod ne 'install') && ($provmethod ne 'netboot') && ($provmethod ne 'statelite')) {
                    if (exists($osimage_hash{$provmethod})) {
                        $provmethod = $osimage_hash{$provmethod};
                    } else {
                        (my $ref) = $osimagetab->getAttribs({ imagename => $provmethod }, 'provmethod');
                        if (($ref) && $ref->{provmethod}) {
                            $osimage_hash{$provmethod} = $ref->{provmethod};
                            $provmethod = $ref->{provmethod};
                        }
                    }
                }

                #if ($provmethod ne 'install')
                #fix bug: in sysclone, provmethod attribute gets cleared
                if ($provmethod ne 'install' && $provmethod ne 'sysclone') {
                    push(@nodestoblank, $_);
                }
            }
        }    #end foreach

        #now blank out the nodetype.provmethod
        #print "nodestoblank=@nodestoblank\n";
        if (@nodestoblank > 0) {
            my $newhash;
            $newhash->{provmethod} = "";
            $nodetype->setNodesAttribs(\@nodestoblank, $newhash);
        }
    }

    if ($noupdate) { return; }    #skip table manipulation if just doing 'enact'
    my $updates;
    foreach (@normalnodes) {

        my $lstate = $state;
        if ($nstates{$_}) {
            $lstate = $nstates{$_};
        }
        $updates->{$_}->{'currstate'} = $lstate;

        # if there are multiple actions in the state argument, set the rest of states (shift out the first one)
        # to chain.currchain so that the rest ones could be used by nextdestiny command
        if ($reststates) {
            $updates->{$_}->{'currchain'} = $reststates;
        }
    }
    $chaintab->setNodesAttribs($updates);
    return getdestiny($flag + 1, \@normalnodes);
}


sub nextdestiny {
    my $flag        = shift;
    my $callnodeset = 0;
    if (scalar(@_)) {
        $callnodeset = 1;
    }
    my @nodes;
    if ($request and $request->{node}) {
        if (ref($request->{node})) {
            @nodes = @{ $request->{node} };
        } else {
            @nodes = ($request->{node});
        }

        #TODO: service third party getdestiny..
    } else {    #client asking to move along its own chain
         #TODO: SECURITY with this, any one on a node could advance the chain, for node, need to think of some strategy to deal with...
        my $node;
        if ($::XCATSITEVALS{nodeauthentication}) { #if requiring node authentication, this request will have a certificate associated with it, use it instead of name resolution
            unless (ref $request->{username}) { return; } #TODO: log an attempt without credentials?
            $node = $request->{username}->[0];
        } else {
            unless ($request->{'_xcat_clienthost'}->[0]) {
                #ERROR? malformed request
                xCAT::MsgUtils->trace(0, "d", "destiny->nextdestiny: Cannot determine the client from the received request");
                return;                                   #nothing to do here...
            }
            $node = $request->{'_xcat_clienthost'}->[0];
        }
        ($node) = noderange($node);
        unless ($node) {
            #not a node, don't trust it
            xCAT::MsgUtils->trace(0, "d", "destiny->nextdestiny: $node is not managed yet.");
            return;
        }
        @nodes = ($node);
    }

    my $node;
    my $noupdate_flag = 0;
    $chaintab = xCAT::Table->new('chain');
    my $chainents = $chaintab->getNodesAttribs(\@nodes, [qw(currstate currchain chain)]);
    foreach $node (@nodes) {
        unless ($chaintab) {
            syslog("local4|err", "ERROR: $node requested destiny update, no chain table");
            return;    #nothing to do...
        }
        my $ref = $chainents->{$node}->[0]; #$chaintab->getNodeAttribs($node,[qw(currstate currchain chain)]);
        unless ($ref->{chain} or $ref->{currchain}) {
            syslog("local4|err", "ERROR: node requested destiny update, no path in chain.currchain");
            return;    #Can't possibly do anything intelligent..
        }
        unless ($ref->{currchain}) {    #If no current chain, copy the default
            $ref->{currchain} = $ref->{chain};
        } elsif ($ref->{currchain} !~ /[,;]/){
            if ($ref->{currstate} and ($ref->{currchain} =~ /$ref->{currstate}/)) {
                $ref->{currchain} = 'standby';
                $callnodeset = 0;
            }
        }
        my @chain = split /[,;]/, $ref->{currchain};

        $ref->{currstate} = shift @chain;
        $ref->{currchain} = join(',', @chain);
        unless ($ref->{currchain}) { #If we've gone off the end of the chain, have currchain stick
            $ref->{currchain} = $ref->{currstate};
        }
        $chaintab->setNodeAttribs($node, $ref); #$ref is in a state to commit back to db

        my %requ;
        $requ{node} = [$node];
        $requ{arg}  = [ $ref->{currstate} ];
        if ($ref->{currstate} =~ /noupdateinitrd$/)
        {
            my @items = split /[:]/, $ref->{currstate};
            $requ{arg} = \@items;
            $noupdate_flag = 1;
        }
        setdestiny(\%requ, $flag + 1);
    }

    if ($callnodeset) {
        my $args;
        if ($noupdate_flag)
        {
            $args = [ 'enact', '--noupdateinitrd' ];
        }
        else
        {
            $args = ['enact'];
        }
        $subreq->({ command => ['nodeset'],
                node => \@nodes,
                arg  => $args });
    }

}


sub getdestiny {
    my $flag = shift;
    my $nodes = shift;

    # flag value:
    # 0--getdestiny is called by dodestiny
    # 1--called by nextdestiny in dodestiny. The node calls nextdestiny before boot and runcmd.
    # 2--called by nodeset command
    # 3--called by updateflag after the node finished installation and before booting

    my $node;
    xCAT::MsgUtils->trace(0, "d", "destiny->process_request: getdestiny...");
    $restab = xCAT::Table->new('noderes');
    my $chaintab = xCAT::Table->new('chain');
    my $chainents = $chaintab->getNodesAttribs($nodes, [qw(currstate chain)]);
    my $nrents = $restab->getNodesAttribs($nodes, [qw(tftpserver xcatmaster)]);
    my $bptab = xCAT::Table->new('bootparams', -create => 1);
    my $bpents = $bptab->getNodesAttribs($nodes, [qw(kernel initrd kcmdline xcatmaster)]);

    #my $sitetab= xCAT::Table->new('site');
    #(my $sent) = $sitetab->getAttribs({key=>'master'},'value');
    my @entries      = xCAT::TableUtils->get_site_attribute("master");
    my $master_value = $entries[0];

    my %node_status = ();
    foreach $node (@$nodes) {
        unless ($chaintab) { #Without destiny, have the node wait with ssh hopefully open at least
            my $stat = xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState("standby", "getdestiny");
            if ($stat) {
                if (exists($node_status{$stat})) {
                    push @{ $node_status{$stat} }, $node;
                } else { 
                    $node_status{$stat} = [$node];
                }
                xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1);
            }
            
            $callback->({ node => [ { name => [$node], data => ['standby'], destiny => ['standby'] } ] });
            return;
        }
        my $ref = $chainents->{$node}->[0]; #$chaintab->getNodeAttribs($node,[qw(currstate chain)]);
        unless ($ref) {

            #collect node status for certain states
            if (($nonodestatus == 0) && (($flag == 0) || ($flag == 3))) {
                my $stat = xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState("standby", "getdestiny");

                #print "node=$node, stat=$stat\n";
                if ($stat) {
                    if (exists($node_status{$stat})) {
                        push @{ $node_status{$stat} }, $node;
                    } else {
                        $node_status{$stat} = [$node];
                    }
                }
            }

            $callback->({ node => [ { name => [$node], data => ['standby'], destiny => ['standby'] } ] });
            next;
        }
        unless ($ref->{currstate}) {    #Has a record, but not yet in a state...
             # we set a 1 here so that it does the nodeset to create tftpboot files
            return nextdestiny(0, 1);    #Becomes a nextdestiny...

            #      my @chain = split /,/,$ref->{chain};
            #      $ref->{currstate} = shift @chain;
            #      $chaintab->setNodeAttribs($node,{currstate=>$ref->{currstate}});
        }
        my %response;
        $response{name}    = [$node];
        $response{data}    = [ $ref->{currstate} ];
        $response{destiny} = [ $ref->{currstate} ];
        my $nrent = $nrents->{$node}->[0]; #$noderestab->getNodeAttribs($node,[qw(tftpserver xcatmaster)]);
        my $bpent = $bpents->{$node}->[0]; #$bptab->getNodeAttribs($node,[qw(kernel initrd kcmdline xcatmaster)]);
        if (defined $bpent->{kernel}) {
            $response{kernel} = $bpent->{kernel};
        }
        if (defined $bpent->{initrd}) {
            $response{initrd} = $bpent->{initrd};
        }
        if (defined $bpent->{kcmdline}) {
            $response{kcmdline} = $bpent->{kcmdline};
        }
        if (defined $nrent->{tftpserver}) {
            $response{imgserver} = $nrent->{tftpserver};
        } elsif (defined $nrent->{xcatmaster}) {
            $response{imgserver} = $nrent->{xcatmaster};
        } elsif (defined($master_value)) {
            $response{imgserver} = $master_value;
        } else {
            my @resd = xCAT::NetworkUtils->my_ip_facing($node);
            unless ($resd[0]) { $response{imgserver} = $resd[1]; }
        }

        #collect node status for certain states
        if (($flag == 0) || ($flag == 3)) {
            my $stat = xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($response{destiny}->[0], "getdestiny");

            #print  "node=$node, stat=$stat\n";
            if ($stat) {
                if (exists($node_status{$stat})) {
                    push @{ $node_status{$stat} }, $node;
                } else {
                    $node_status{$stat} = [$node];
                }
            }
        }

        $callback->({ node => [ \%response ] });
    }

    #setup the nodelist.status
    if (($nonodestatus == 0) && (($flag == 0) || ($flag == 3))) {

        #print "save status\n";
        if (keys(%node_status) > 0) { xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1); }
    }
}


1;
