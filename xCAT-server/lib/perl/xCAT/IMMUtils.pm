package xCAT::IMMUtils;
use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SSHInteract;
use xCAT_plugin::bmcconfig;

#For IMMs, there are a few contexts where setup is most sensibly done remotely via CLI automation, or must be done remotely.
#If slp driven discovery, this is the sensible path pretty much in all scenarios (rack and flex)
#for bmcsetup, it still makes sense for IBM Flex system servers where the server is forbidden from manipulation local authentication
#data

#setupIMM
#Arguments:
#    first argument: the nodename to be managed (*NOT* the IMM, the node managed by the IMM)
#    named arguments:
#       nodedata - structure containing miscellaneous information about the target IMM.  Currently, macaddress is the only member of interest
#       skipbmcidcheck - if true will do the ssh in even if the bmcid indicates otherwis.  remoteimmsetup context, for example, is better served with this strategy
#	skipnetconfig - if true, will not issue ifconfig type commands.  In remoteimmsetup, this is handled in the typical bmcsetup way
#	callback - function to handle getting output back to client
#	cliusername - username to use for ssh (might not match ipmi)
#	clipassword - password for cli
#	curraddr - current address (in case current address does not match intended address
# example invocation:
# xCAT::IMMUtils::setupIMM($node,nodedata=>$immdata,curraddr=>$addr,cliusername=>$user,clipassword=>$pass,callback=>$callback);

sub setupIMM {
    my $node     = shift;
    my %args     = @_;
    my $nodedata = $args{nodedata};
    my $callback = $args{callback};
    my $ipmitab  = xCAT::Table->new('ipmi', -create => 1);

    # collect the bmc and bmcid attributes from the ipmi table for this bmc
    my $ient = $ipmitab->getNodeAttribs($node, [qw/bmc bmcid/], prefetchcache => 1);

    # get the ipmi userid and password from the pmi, mp, or passwd table
    my $ipmiauthmap = xCAT::PasswordUtils::getIPMIAuth(noderange => [$node]);
    my $newaddr;

    # if the bmc and bmcid were found
    if ($ient) {
        my $bmcid = $ient->{bmcid};

        # if not skip and bmcid was found and its the same as the node's macaddress - then msg and skip
        if (not $args{skipbmcidcheck} and $bmcid and $nodedata->{macaddress} =~ /$bmcid/) {
            sendmsg("The IMM has been configured (ipmi.bmcid). Skipped.", $callback, $node);
            return;
        }   #skip configuration, we already know this one
            # not skipping so save the bmc address from the ipmi table for later
        $newaddr = $ient->{bmc};
    }
    my @ips     = ();
    my $autolla = 0;

    # if the bmc address was found in the ipmi table and its NOT an IPv6 IP
    if ($newaddr and not $newaddr =~ /^fe80:.*%.*/) {

        # get the ip addresses associated with the bmc ip address in the ipmi table
        @ips = xCAT::NetworkUtils::getipaddr($newaddr, GetAllAddresses => 1);
    } else {

        # otherwise check if the curraddr passed in is IPv6 LLA then use it
        if ($args{curraddr} =~ /^fe80:.*%.*/) { #if SLP were able to glean an LLA out of this, let's just roll with that result
                # set the node bmc attribute to the LLA found and passed in
            $ipmitab->setNodeAttribs($node, { bmc => $args{curraddr} });
            $autolla = 1;
        }
    }

    # if there is not are not ip addresses resolved from the IP in the ipmi bmc ip or there is not a LLA then error and exit
    if (not scalar @ips and not $autolla) {
        sendmsg(":Cannot find the IP attribute for bmc", $callback, $node);
        return;
    }
    my $targips;
    my $sship = $args{curraddr};

    # if the ips resloved from the bmc ip in the ipmi table
    if (scalar(@ips)) {
        $targips = join(',', @ips);
        unless ($sship) { $sship = $ips[0]; }

        # else if its the LLA ip address passed in
    } elsif ($autolla) {
        $targips = $args{curraddr};
    }

    # Tell admin that configuration is about to begin
    sendmsg(":Configuration of " . $node . "[$targips] commencing, configuration may take a few minutes to take effect", $callback);
    my $child = fork();
    if     ($child)         { return; }
    unless (defined $child) { die "error spawining process" }

    #ok, with all ip addresses in hand, time to enable IPMI and set all the ip addresses (still static only, TODO: dhcp
    my $ssh;

    # setup ssh parameters and make initial ssh connection
    eval { $ssh = new xCAT::SSHInteract(-username => $args{cliusername},
            -password                => $args{clipassword},
            -host                    => $sship,
            -nokeycheck              => 1,
            -output_record_separator => "\r",
            Timeout                  => 15,
            Errmode                  => 'return',
            Prompt                   => '/> $/'); };
    my $errmsg = $@;

    # error message and exit on any error on ssh connection
    if ($errmsg) {
        if ($errmsg =~ /Login Failed/) {
            $errmsg = "Login failed";
        } elsif ($errmsg =~ /Incorrect Password/) {
            $errmsg = "Incorrect Password";
        } else {
            $errmsg = "Failed";
        }
        sendmsg(":$errmsg", $callback, $node);
        exit(0);
    }

    # if ssh connection was good and we have a valid prompt
    if ($ssh and $ssh->atprompt) {    #we are in and good to issue commands
          # set access configiuration options to allow bmc to be managed by xcat
        $ssh->cmd("accseccfg -pe 0 -rc 0 -ci 0 -lf 0 -lp 0"); #disable the more insane password rules, this isn't by and large a human used interface
                                                              # enable ipmi
        $ssh->cmd("users -1 -n " . $ipmiauthmap->{$node}->{username} . " -p " . $ipmiauthmap->{$node}->{password} . " -a super"); #this gets ipmi going
            # if we do not have to skip network configuration
        unless ($args{skipnetconfig}) {

            # process all the IP addresses
            foreach my $ip (@ips) {

                # if address is IPv6
                if ($ip =~ /:/) {
                    $ssh->cmd("ifconfig eth0 -ipv6static enable -i6 $ip");
                } else {

                    # resolve the IP network parms
                    (my $sip, my $mask, my $gw) = xCAT_plugin::bmcconfig::net_parms($ip);
                    my $cmd = "ifconfig eth0 -c static -i $ip -s $mask";
                    if ($gw) { $cmd .= " -g $gw"; }
                    $ssh->cmd($cmd);
                }
            }
        }

        # close the ssh session
        $ssh->close();

        # update the ipmi table bmc attribute for this node
        $ipmitab->setNodeAttribs($node, { bmcid => $nodedata->{macaddress} });
    }
    sendmsg(":Succeeded", $callback, $node);
    exit(0);
}

1;
