# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::bmcconfig;
use Data::Dumper;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::PasswordUtils;
use xCAT::IMMUtils;
use xCAT::TableUtils;
use IO::Select;
use Socket;

sub handled_commands {
    return {
        getbmcconfig   => 'bmcconfig',
        remoteimmsetup => 'bmcconfig',
    };
}

sub genpassword {
    my $length   = shift;
    my $password = '';
    my $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890';
    srand;    #have to reseed, rand is not rand otherwise
    while (length($password) < $length) {
        $password .= substr($characters, int(rand 63), 1);
    }
    return $password;
}

sub net_parms {
    my $ip = shift;
    if (inet_aton($ip)) {
        $ip = inet_ntoa(inet_aton($ip));
    } else {
        xCAT::MsgUtils->message("S", "Unable to resolve $ip");
        return undef;
    }
    my $nettab = xCAT::Table->new('networks');
    unless ($nettab) { return undef }
    my @nets = $nettab->getAllAttribs('net', 'mask', 'gateway');
    foreach (@nets) {
        my $net  = $_->{'net'};
        my $mask = $_->{'mask'};
        my $gw   = $_->{'gateway'};
        $ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
        my $ipnum = ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
        $mask =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
        my $masknum = ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;
        $net =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ or next; #next if ipv6, TODO: IPv6 support
        my $netnum = ($1 << 24) + ($2 << 16) + ($3 << 8) + $4;

        if ($gw eq '<xcatmaster>') {
            my @gwd = xCAT::NetworkUtils->my_ip_facing($ip);
            unless ($gwd[0]) { $gw = $gwd[1]; }
        }
        if (($ipnum & $masknum) == $netnum) {
            return ($ip, $mask, $gw);
        }
    }
    xCAT::MsgUtils->message("S", "xCAT BMC configuration error, no appropriate network for $ip found in networks, unable to determine netmask");
}


sub ok_with_node {
    my $node = shift;

    #Here we connect to the node on a privileged port (in the clear) and ask the
    #node if it just asked us for credential.  It's convoluted, but it is
    #a convenient way to see if root on the ip has approved requests for
    #credential retrieval.  Given the nature of the situation, it is only ok
    #to assent to such requests before users can log in.  During postscripts
    #stage in stateful nodes and during the rc scripts of stateless boot
    my $select = new IO::Select;

    #sleep 0.5; # gawk script race condition might exist, try to lose just in case
    my $sock = new IO::Socket::INET(PeerAddr => $node,
        Proto    => "tcp",
        PeerPort => shift);
    my $rsp;
    unless ($sock) { return 0 }
    $select->add($sock);
    print $sock "CREDOKBYYOU?\n";
    unless ($select->can_read(5)) {    #wait for data for up to five seconds
        return 0;
    }
    my $response = <$sock>;
    chomp($response);
    if ($response eq "CREDOKBYME") {
        return 1;
    }
    return 0;
}

sub process_request {
    my $request  = shift;
    my $callback = shift;
    my $node     = $request->{'_xcat_clienthost'}->[0];
    my $bmc_mgmt_type = "ipmi";
    if ($request->{isopenbmc}->[0]) {
        $bmc_mgmt_type = "openbmc";
    }
    unless (ok_with_node($node, 300)) {
        $callback->({ error => ["Unable to prove root on your IP approves of this request"], errorcode => [1] });
        return;
    }

    my $ipmitable = xCAT::Table->new("$bmc_mgmt_type");
    my $tmphash;
    my $username;
    my $gennedpassword = 0;
    my $bmc;
    my $password;
    $tmphash = $ipmitable->getNodesAttribs([$node], [ 'bmc', 'username', 'bmcport', 'password', 'taggedvlan' ]);
    my $authmap = xCAT::PasswordUtils::getIPMIAuth(noderange => [$node], ipmihash => $tmphash, keytype => $bmc_mgmt_type);

    if ($::XCATSITEVALS{genpasswords} eq "1" or $::XCATSITEVALS{genpasswords} =~ /y(es)?/i) {
        $password       = genpassword(10) . "1cA!";
        $gennedpassword = 1;
    } else {
        $password = $authmap->{$node}->{password};
    }
    my $bmcport;
    if (defined $tmphash->{$node}->[0]->{bmcport}) {
        $bmcport = $tmphash->{$node}->[0]->{bmcport};
    }
    if ($tmphash->{$node}->[0]->{bmc}) {
        $bmc = $tmphash->{$node}->[0]->{bmc};
    }
    $username = $authmap->{$node}->{username};
    my $cliusername;
    if ($authmap->{$node}->{cliusername}) {
        $cliusername = $authmap->{$node}->{cliusername};
    } else {
        $cliusername = $username;
    }
    my $clipassword;
    if ($authmap->{$node}->{clipassword}) {
        $clipassword = $authmap->{$node}->{clipassword};
    } else {
        $clipassword = $password;
    }
    unless (defined $bmc) {
        xCAT::MsgUtils->message('S', "Received request from host=$node but unable to determine the $bmc_mgmt_type.bmc value for the node. Verify the node.mgt attribute is configured and the node.bmc is defined.");
        $callback->({ error => ["No value specified for '$node.bmc'. Unable to configure the BMC, check the node definition."], errorcode => [1] });
        return 1;
    }
    my $bmcport_counter = 0;
    foreach my $sbmc (split /,/, $bmc) {
        (my $ip, my $mask, my $gw) = net_parms($sbmc);
        unless ($ip and $mask and $username and $password) {
            xCAT::MsgUtils->message('S', "Unable to determine IP, Netmask, Username, or Password for $sbmc. Ensure that hostname resolution is working. [IP=$ip Netmask=$mask User=$username Pass=$password]",);
            $callback->({ error => ["Invalid/Missing BMC related attributes in the node defintion (IP=$ip Netmask=$mask User=$username Pass=$password). Unable to configure the BMC, check the node definition."], errorcode => [1] });
            return 1;
        }
        if ($request->{command}->[0] eq 'remoteimmsetup') {
            xCAT::IMMUtils::setupIMM($node, cliusername => $cliusername, clipassword => $clipassword, username => $username, password => $password, callback => $callback);
            return;
        }
        my $response = { bmcip => $ip, netmask => $mask, gateway => $gw, username => $username, password => $password };
        if (defined $bmcport) {
            if ($bmcport =~ /,/) {
                my @sbmcport = (split /,/, $bmcport);
                $response->{bmcport} = $sbmcport[$bmcport_counter];
            } else {
                $response->{bmcport} = $bmcport;
            }
        }
        if (defined $tmphash->{$node}->[0]->{taggedvlan}) {
            if ($tmphash->{$node}->[0]->{taggedvlan} =~ /,/) {
                my @staggedvlan = (split /,/, $tmphash->{$node}->[0]->{taggedvlan});
                $response->{taggedvlan} = $staggedvlan[$bmcport_counter];
            } else {
                $response->{taggedvlan} = $tmphash->{$node}->[0]->{taggedvlan};
            }
        }
        $callback->($response);
        $bmcport_counter += 1;
    }
    if ($gennedpassword) {    # save generated password
        $ipmitable->setNodeAttribs($node, { password => $password });
    }

    return 1;
}



1;

