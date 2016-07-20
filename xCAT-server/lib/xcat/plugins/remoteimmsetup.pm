package xCAT_plugin::remoteimmsetup;
use strict;
use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SLP;
use xCAT::NetworkUtils;
use xCAT::SSHInteract;
use xCAT::MacMap;
use xCAT_plugin::bmcconfig;
my $defaultbladeuser;
my $defaultbladepass;
my $currentbladepass;
my $currentbladeuser;
my $mpahash;

sub handled_commands {
    return {
        slpdiscover => "slpdiscover",
    };
}

my $callback;
my $docmd;
my %doneaddrs;
my %ip4neigh;
my %ip6neigh;
my %flexchassismap;
my %flexchassisuuid;
my %nodebymp;
my %passwordmap;
my %chassisbyuuid;
my %searchmacs;
my %researchmacs;
my $macmap;

sub get_mac_for_addr {
    my $neigh;
    my $addr = shift;
    if ($addr =~ /:/) {
        get_ipv6_neighbors();
        return $ip6neigh{$addr};
    } else {
        get_ipv4_neighbors();
        return $ip4neigh{$addr};
    }
}

sub get_ipv4_neighbors {

    #TODO: something less 'hacky'
    my @ipdata = `ip -4 neigh`;
    %ip6neigh = ();
    foreach (@ipdata) {
        if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
            $ip4neigh{$1} = $2;
        }
    }
}

sub get_ipv6_neighbors {

    #TODO: something less 'hacky'
    my @ipdata = `ip -6 neigh`;
    %ip6neigh = ();
    foreach (@ipdata) {
        if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
            $ip6neigh{$1} = $2;
        }
    }
}

sub process_request {
    my $request = shift;
    $callback = shift;
    $docmd    = shift;
    my $client;
    if ($request->{'_xcat_clienthost'}) {
        $client = $request->{'_xcat_clienthost'}->[0];
    }
    unless ($client) {
        return;
    }

}

sub setupIMM {
    my $node    = shift;
    my %args    = @_;
    my $slpdata = $args{slpdata};
    my $ipmitab = xCAT::Table->new('ipmi', -create => 1);
    my $ient = $ipmitab->getNodeAttribs($node, [qw/bmc bmcid/], prefetchcache => 1);
    my $newaddr;
    if ($ient) {
        my $bmcid = $ient->{bmcid};
        if ($bmcid and $slpdata->{macaddress} =~ /$bmcid/) {
            sendmsg("The IMM has been configured (ipmi.bmcid). Skipped.", $callback, $node);
            return;
        }    #skip configuration, we already know this one
        $newaddr = $ient->{bmc};
    }
    my @ips     = ();
    my $autolla = 0;
    if ($newaddr and not $newaddr =~ /^fe80:.*%.*/) {
        @ips = xCAT::NetworkUtils::getipaddr($newaddr, GetAllAddresses => 1);
    } else {
        if ($args{curraddr} =~ /^fe80:.*%.*/) { #if SLP were able to glean an LLA out of this, let's just roll with that result
            $ipmitab->setNodeAttribs($node, { bmc => $args{curraddr} });
            $autolla = 1;
        }
    }
    if (not scalar @ips and not $autolla) {
        sendmsg(":Cannot find the IP attribute for bmc", $callback, $node);
        return;
    }
    my $targips;
    if (scalar(@ips)) {
        $targips = join(',', @ips);
    } elsif ($autolla) {
        $targips = $args{curraddr};
    }
    sendmsg(":Configuration of " . $node . "[$targips] commencing, configuration may take a few minutes to take effect", $callback);
    my $child = fork();
    if     ($child)         { return; }
    unless (defined $child) { die "error spawining process" }

    #ok, with all ip addresses in hand, time to enable IPMI and set all the ip addresses (still static only, TODO: dhcp
    my $ssh = new xCAT::SSHInteract(-username => $args{username},
        -password                => $args{password},
        -host                    => $args{curraddr},
        -nokeycheck              => 1,
        -output_record_separator => "\r",
        Timeout                  => 15,
        Errmode                  => 'return',
        Prompt                   => '/> $/');
    if ($ssh and $ssh->atprompt) {    #we are in and good to issue commands
        $ssh->cmd("accseccfg -pe 0 -rc 0 -ci 0 -lf 0 -lp 0"); #disable the more insane password rules, this isn't by and large a human used interface
        $ssh->cmd("users -1 -n " . $args{username} . " -p " . $args{password} . " -a super"); #this gets ipmi going
        foreach my $ip (@ips) {
            if ($ip =~ /:/) {
                $ssh->cmd("ifconfig eth0 -ipv6static enable -i6 $ip");
            } else {
                (my $sip, my $mask, my $gw) = xCAT_plugin::bmcconfig::net_parms($ip);
                my $cmd = "ifconfig eth0 -c static -i $ip -s $mask";
                if ($gw) { $cmd .= " -g $gw"; }
                $ssh->cmd($cmd);
            }
        }
        $ssh->close();
        $ipmitab->setNodeAttribs($node, { bmcid => $slpdata->{macaddress} });
    }
    exit(0);
}

sub configure_hosted_elements {
    my $cmm  = shift;
    my $uuid = $flexchassisuuid{$cmm};
    my $node;
    my $immdata;
    my $slot;
    my $user = $passwordmap{$cmm}->{username};
    my $pass = $passwordmap{$cmm}->{password};
    foreach $immdata (values %{ $flexchassismap{$uuid} }) {
        $slot = $immdata->{attributes}->{slot}->[0];
        if ($node = $nodebymp{$cmm}->{$slot}) {
            my $addr = $immdata->{peername}; #todo, use sockaddr and remove the 427 port from it instead?
            if ($addr =~ /^fe80/) {    #Link local address requires scope index
                $addr .= "%" . $immdata->{scopeid};
            }
            if ($doneaddrs{$node}) { next; }
            $doneaddrs{$node} = 1;
            setupIMM($node, slpdata => $immdata, curraddr => $addr, username => $user, password => $pass);
        } else {
            sendmsg(": Ignoring target in bay $slot, no node found with mp.mpa/mp.id matching", $callback, $cmm);
        }

    }
    while (wait() > 0) { }
}

sub setup_cmm_pass {
    my $nodename  = shift;
    my $localuser = $defaultbladeuser;
    my $localpass = $defaultbladepass;
    if ($mpahash->{$nodename}) {
        if ($mpahash->{$nodename}->{username}) {
            $localuser = $mpahash->{$nodename}->{username};
        }
        if ($mpahash->{$nodename}->{password}) {
            $localpass = $mpahash->{$nodename}->{password};
        }
    }
    $passwordmap{$nodename}->{username} = $localuser;
    $passwordmap{$nodename}->{password} = $localpass;
}

sub do_blade_setup {
    my $data      = shift;
    my %args      = @_;
    my $addr      = $args{curraddr};
    my $nodename  = $data->{nodename};
    my $localuser = $passwordmap{$nodename}->{username};
    my $localpass = $passwordmap{$nodename}->{password};
    if (not $localpass or $localpass eq "PASSW0RD") {
        sendmsg([ 1, ":Password for blade must be specified in either mpa or passwd tables, and it must not be PASSW0RD" ], $callback, $nodename);
        return 0;
    }
    require xCAT_plugin::blade;
    my @cmds;
    my %exargs;
    if ($args{pass2}) {
        @cmds = qw/initnetwork=*/;
        %exargs = (nokeycheck => 1); #still not at the 'right' ip, so the known hosts shouldn't be bothered
    } else {
        @cmds = qw/snmpcfg=enable sshcfg=enable textid=*/; # initnetwork=*/; defer initnetwork until after chassis members have been configured
        %exargs = (curruser => $currentbladeuser, currpass => $currentbladepass);
    }
    my $result;
    $@ = "";
    my $rc = eval { $result = xCAT_plugin::blade::clicmds(
            $nodename,
            $localuser,
            $localpass,
            $nodename,
            0,
            curraddr => $addr,
            %exargs,
            cmds => \@cmds);
        1;
    };
    my $errmsg = $@;
    if ($errmsg) {
        if ($errmsg =~ /Incorrect Password/) {
            sendmsg([ 1, "Failed to set up Management module due to Incorrect Password (You may try the environment variables XCAT_CURRENTUSER and/or XCAT_CURRENTPASS to try a different value)" ], $callback, $nodename);
        } else {
            sendmsg([ 1, "Failed to set up Management module due to $errmsg" ], $callback, $nodename);
        }
        return 0;
    }
    if ($result) {
        if ($result->[0]) {
            if ($result->[2] =~ /Incorrect Password/) {
                sendmsg([ 1, "Failed to set up Management module due to Incorrect Password (You may try the environment variables XCAT_CURRENTUSER and/or XCAT_CURRENTPASS to try a different value)" ], $callback, $nodename);
                return 0;
            }
            my $errors = $result->[2];
            if (ref $errors) {
                foreach my $error (@$errors) {
                    sendmsg([ $result->[0], $error ], $callback, $nodename);
                }
            } else {
                sendmsg([ $result->[0], $result->[2] ], $callback, $nodename);
            }
            return 0;
        }
    }
    return $rc;
}
1;
