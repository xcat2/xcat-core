# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::dhcp;
use xCAT::Table;
use Data::Dumper;
use MIME::Base64;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use Socket;
use Sys::Syslog;
use IPC::Open2;
use xCAT::Utils;

my @dhcpconf; #Hold DHCP config file contents to be written back.
my @nrn;      # To hold output of netstat -rn to be consulted throughout process
my $domain;
my $omshell;
my $statements;    #Hold custom statements to be slipped into host declarations
my $callback;
my $restartdhcp;

sub handled_commands
{
    return {makedhcp => "dhcp",};
}

sub delnode
{
    my $node  = shift;
    my $inetn = inet_aton($node);

    my $mactab = xCAT::Table->new('mac');
    if ($mactab) { $ent = $mactab->getNodeAttribs($node, [qw(mac)]); }
    if ($ent and $ent->{mac})
    {
        my @macs = split(/\|/, $ent->{mac});
        my $mace;
        foreach $mace (@macs)
        {
            my $mac;
            my $hname;
            ($mac, $hname) = split(/!/, $mace);
            unless ($hname) { $hname = $node; }
            print $omshell "new host\n";
            print $omshell
              "set name = \"$hname\"\n";    #Find and destroy conflict name
            print $omshell "open\n";
            print $omshell "remove\n";
            print $omshell "close\n";

            if ($mac)
            {
                print $omshell "new host\n";
                print $omshell "set hardware-address = " . $mac
                  . "\n";                   #find and destroy mac conflict
                print $omshell "open\n";
                print $omshell "remove\n";
                print $omshell "close\n";
            }
            if ($inetn)
            {
                my $ip;
                if (inet_aton($hname))
                {
                    $ip = inet_ntoa(inet_aton($hname));
                }
                if ($ip)
                {
                    print $omshell "new host\n";
                    print $omshell
                      "set ip-address = $ip\n";    #find and destroy ip conflict
                    print $omshell "open\n";
                    print $omshell "remove\n";
                    print $omshell "close\n";
                }
            }
        }
    }
    print $omshell "new host\n";
    print $omshell "set name = \"$node\"\n";    #Find and destroy conflict name
    print $omshell "open\n";
    print $omshell "remove\n";
    print $omshell "close\n";
    if ($inetn)
    {
        my $ip = inet_ntoa(inet_aton($node));
        unless ($ip) { return; }
        print $omshell "new host\n";
        print $omshell "set ip-address = $ip\n";   #find and destroy ip conflict
        print $omshell "open\n";
        print $omshell "remove\n";
        print $omshell "close\n";
    }
}

sub addnode
{

    #Use omshell to add the node.
    #the process used is blind typing commands that should work
    #it tries to delet any conflicting entries matched by name and
    #hardware address and ip address before creating a brand now one
    #unfortunate side effect: dhcpd.leases can look ugly over time, when
    #doing updates would keep it cleaner, good news, dhcpd restart cleans
    #up the lease file the way we would want anyway.
    my $node = shift;
    my $ent;
    my $nrtab             = xCAT::Table->new('noderes');
    my $lstatements       = $statements;
    my $guess_next_server = 0;
    if ($nrtab)
    {
        my $ent;
        $ent = $nrtab->getNodeAttribs($node, ['tftpserver']);
        if ($ent and $ent->{tftpserver})
        {
            $lstatements =
                'next-server '
              . inet_ntoa(inet_aton($ent->{tftpserver})) . ';'
              . $statements;
        }
        else
        {
            $guess_next_server = 1;
        }

        #else {
        # $ent = $nrtab->getNodeAttribs($node,['servicenode']);
        # if ($ent and $ent->{servicenode}) {
        #  $statements = 'next-server  = \"'.inet_ntoa(inet_aton($ent->{servicenode})).'\";'.$statements;
        # }
        #}
    }
    else
    {
        $guess_next_server = 1;
    }
    my $mactab = xCAT::Table->new('mac');
    unless ($mactab)
    {
        $callback->(
                   {
                    error => ["Unable to open mac table, it may not exist yet"],
                    errorcode => [1]
                   }
                   );
        return;
    }
    $ent = $mactab->getNodeAttribs($node, [qw(mac)]);
    unless ($ent and $ent->{mac})
    {
        $callback->(
                    {
                     error     => ["Unable to find mac address for $node"],
                     errorcode => [1]
                    }
                    );
        return;
    }
    my @macs = split(/\|/, $ent->{mac});
    my $mace;
    foreach $mace (@macs)
    {
        my $mac;
        my $hname;
        $hname = "";
        ($mac, $hname) = split(/!/, $mace);
        unless ($hname)
        {
            $hname = $node;
        }    #Default to hostname equal to nodename
        unless ($mac) { next; }    #Skip corrupt format
        my $inetn;
        $inetn = "";
        if ($hname eq '*NOIP*')
        {
            $inetn = "DENIED";
            $hname = $node . "-noip" . $mac;
            $hname =~ s/://g;
        }
        else
        {
            $inetn = inet_aton($hname);
        }
        unless ($inetn)
        {
            syslog(
                  "local1|err",
                  "xCAT DHCP plugin unable to resolve IP for $hname (for $node)"
                  );
            return;
        }
        my $ip;
        $ip = "";
        if ($inetn eq "DENIED")
        {
            $ip = "DENIED";
        }
        else
        {
            $ip = inet_ntoa(inet_aton($hname));
        }
        if ($guess_next_server and $ip ne "DENIED")
        {
            my $nxtsrv = xCAT::Utils->my_ip_facing($hname);
            if ($nxtsrv)
            {
                $lstatements = "next-server $nxtsrv;$statements";
            }
        }
        #syslog("local4|err", "Setting $node ($hname|$ip) to " . $mac);
        print $omshell "new host\n";
        print $omshell
          "set name = \"$hname\"\n";    #Find and destroy conflict name
        print $omshell "open\n";
        print $omshell "remove\n";
        print $omshell "close\n";
        print $omshell "new host\n";
        print $omshell "set ip-address = $ip\n";   #find and destroy ip conflict
        print $omshell "open\n";
        print $omshell "remove\n";
        print $omshell "close\n";
        print $omshell "new host\n";
        print $omshell "set hardware-address = " . $mac
          . "\n";    #find and destroy mac conflict
        print $omshell "open\n";
        print $omshell "remove\n";
        print $omshell "close\n";
        print $omshell "new host\n";
        print $omshell "set name = \"$hname\"\n";
        print $omshell "set hardware-address = " . $mac . "\n";
        print $omshell "set hardware-type = 1\n";

        if ($ip eq "DENIED")
        { #Blacklist this mac to preclude confusion, give best shot at things working
            print $omshell "set statements = \"deny booting;\"\n";
        }
        else
        {
            print $omshell "set ip-address = $ip\n";
            if ($lstatements)
            {
                $lstatements = 'send host-name \"'.$node.'\";'.$lstatements;

            } else {
                $lstatements = 'send host-name \"'.$node.'\";';
            }
            print $omshell "set statements = \"$lstatements\"\n";
        }

        print $omshell "create\n";
        print $omshell "close\n";
        unless (grep /#definition for host $node aka host $hname/, @dhcpconf)
        {
            push @dhcpconf,
              "#definition for host $node aka host $hname can be found in the dhcpd.leases file\n";
        }
    }
}

sub preprocess_request
{
    my $req = shift;
    $callback = shift;
    if ($req->{_xcatdest})
    {
        return [$req];
    }    #Exit if the packet has been preprocessed in its history
    my @requests =
      ({%$req});    #Start with a straight copy to reflect local instance
    my @sn = xCAT::Utils->getSNList(dhcpserver);
    foreach my $s (@sn)
    {
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $s;
        push @requests, $reqcopy;
    }
    if (scalar(@requests) > 1)
    {               #hierarchy detected, enforce more rigorous sanity
        my $ntab = xCAT::Table->new('networks');
        if ($ntab)
        {
            foreach (@{$ntab->getAllEntries()})
            {
                if ($_->{dynamicrange} and not $_->{dhcpserver})
                {
                    $callback->({error=>["Hierarchy requested, therefore networks.dhcpserver must be set for net=".$_->{net}.""],errorcode=>[1]});
                    return [];
                }
            }
        }
    }

    return \@requests;
}

sub process_request
{
    $restartdhcp=0;
    my $req = shift;
    $callback = shift;
    my $sitetab = xCAT::Table->new('site');
    my %activenics;
    my $querynics = 1;
    if ($sitetab)
    {
        my $href;
        ($href) = $sitetab->getAttribs({key => 'dhcpinterfaces'}, 'value');
        unless ($href and $href->{value})
        {    #LEGACY: singular keyname for old style site value
            ($href) = $sitetab->getAttribs({key => 'dhcpinterface'}, 'value');
        }
        if ($href and $href->{value})
        #syntax should be like host|ifname1,ifname2;host2|ifname3,ifname2 etc or simply ifname,ifname2
        #depending on complexity of network wished to be described
        {
           my $dhcpinterfaces = $href->{value};
           my $dhcpif;
           foreach $dhcpif (split /;/,$dhcpinterfaces) {
              if ($dhcpif =~ /\|/) {
                 (my $host,$dhcpif) = split /\|/,$dhcpif;
                 if (xCAT::Utils->thishostisnot($host)) {
                    next;
                 }
              }
              foreach (split /[,\s]+/, $dhcpif)
              {
                 $activenics{$_} = 1;
                 $querynics = 0;
              }
           }
        }
        ($href) = $sitetab->getAttribs({key => 'domain'}, 'value');
        unless ($href and $href->{value})
        {
            $callback->(
                 {error => ["No domain defined in site tabe"], errorcode => [1]}
                 );
            return;
        }
        $domain = $href->{value};
    }

    @dhcpconf = ();
    unless ($req->{arg} or $req->{node})
    {
        $callback->({data => ["Usage: makedhcp <-n> <noderange>"]});
        return;
    }
    if (grep /^-n$/, @{$req->{arg}})
    {
        if (-e "/etc/dhcpd.conf")
        {
            my $bakname = "/etc/dhcpd.conf.xcatbak";
            rename("/etc/dhcpd.conf", $bakname);
        }
    }
    else
    {
        open($rconf, "/etc/dhcpd.conf");    # Read file into memory
        if ($rconf)
        {
            while (<$rconf>)
            {
                push @dhcpconf, $_;
            }
            close($rconf);
        }
        unless ($dhcpconf[0] =~ /^#xCAT/)
        {    #Discard file if not xCAT originated, like 1.x did
            $restartdhcp=1;
            @dhcpconf = ();
        }
    }
    @nrn = split /\n/, `/bin/netstat -rn`;
    splice @nrn, 0, 2;    #get rid of header
    if ($querynics)
    {    #Use netstat to determine activenics only when no site ent.
        foreach (@nrn)
        {
            my @ent = split /\s+/;
            my $firstoctet = $ent[0];
            $firstoctet =~ s/^(\d+)\..*/$1/;
            if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239))
            {
                next;
            }
            if ($ent[7] =~ m/(ipoib|ib|vlan|bond|eth|myri|man|wlan)/)
            {    #Mask out many types of interfaces, like xCAT 1.x
                $activenics{$ent[7]} = 1;
            }
        }
    }
    unless ($dhcpconf[0])
    {            #populate an empty config with some starter data...
        $restartdhcp=1;
        newconfig();
    }
    foreach (keys %activenics)
    {
        addnic($_);
    }
    if (grep /^-a$/, @{$req->{arg}})
    {
        if (grep /-d$/, @{$req->{arg}})
        {
            $req->{node} = [];
            my $nodelist = xCAT::Table->new('nodelist');
            my @entries  = ($nodelist->getAllNodeAttribs([qw(node)]));
            foreach (@entries)
            {
                push @{$req->{node}}, $_->{node};
            }
        }
        else
        {
            $req->{node} = [];
            my $mactab  = xCAT::Table->new('mac');
            my @entries = ($mactab->getAllNodeAttribs([qw(mac)]));
            foreach (@entries)
            {
                push @{$req->{node}}, $_->{node};
            }
        }
    }

    if ($req->{node})
    {
        @ARGV       = @{$req->{arg}};
        $statements = "";
        GetOptions('s|statements=s' => \$statements);

        my $passtab = xCAT::Table->new('passwd');
        my $ent;
        ($ent) = $passtab->getAttribs({key => "omapi"}, qw(username password));
        unless ($ent->{username} and $ent->{password})
        {
            return;
        }    # TODO sane err
             #Have nodes to update
             #open2($omshellout,$omshell,"/usr/bin/omshell");
        open($omshell, "|/usr/bin/omshell > /dev/null");

        print $omshell "key "
          . $ent->{username} . " \""
          . $ent->{password} . "\"\n";
        print $omshell "connect\n";
        foreach (@{$req->{node}})
        {
            if (grep /^-d$/, @{$req->{arg}})
            {
                delnode $_;
            }
            else
            {
                unless (xCAT::Utils->nodeonmynet($_))
                {
                    next;
                }
                addnode $_;
            }
        }
        close($omshell);
    }
    foreach (@nrn)
    {
        my @line = split /\s+/;
        my $firstoctet = $line[0]; 
        $firstoctet =~ s/^(\d+)\..*/$1/;
        if ($line[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239))
        {
            next;
        }
        if ($activenics{$line[7]} and $line[3] !~ /G/)
        {
            addnet($line[0], $line[2]);
        }
    }
    writeout();
    if ($restartdhcp) {
        system("/etc/init.d/dhcpd restart");
        system("chkconfig dhcpd on");
    }
}

sub addnet
{
    my $net  = shift;
    my $mask = shift;
    my $nic;
    my $firstoctet = $net;
    $firstoctet =~ s/^(\d+)\..*/$1/;
    if ($net eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239)) {
        return;
    }
    unless (grep /\} # $net\/$mask subnet_end/, @dhcpconf)
    {
        $restartdhcp=1;
        foreach (@nrn)
        {    # search for relevant NIC
            my @ent = split /\s+/;
            $firstoctet = $ent[0];
            $firstoctet =~ s/^(\d+)\..*/$1/;
            if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239))
            {
                next;
            }
            if ($ent[0] eq $net and $ent[2] eq $mask)
            {
                $nic = $ent[7];
            }
        }
        #print " add $net $mask under $nic\n";
        my $idx = 0;
        while ($idx <= $#dhcpconf)
        {
            if ($dhcpconf[$idx] =~ /\} # $nic nic_end\n/)
            {
                last;
            }
            $idx++;
        }
        unless ($dhcpconf[$idx] =~ /\} # $nic nic_end\n/)
        {
            return 1;    #TODO: this is an error condition
        }

        # if here, means we found the idx before which to insert
        my $nettab = xCAT::Table->new("networks");
        my $nameservers;
        my $gateway;
        my $tftp;
        my $range;
        my $myip;
        $myip = xCAT::Utils->my_ip_facing($net);
        if ($nettab)
        {
            my ($ent) =
              $nettab->getAttribs({net => $net, mask => $mask},
                    qw(tftpserver nameservers gateway dynamicrange dhcpserver));
            if ($ent and $ent->{nameservers})
            {
                $nameservers = $ent->{nameservers};
            }
            else
            {
                $callback->(
                    {
                     warning => [
                         "No $net specific entry for nameservers, and dhcp plugin not sourcing from site yet (TODO)"
                     ]
                    }
                    );
            }
            if ($ent and $ent->{tftpserver})
            {
                $tftp = $ent->{tftpserver};
            }
            else
            {    #presume myself to be it, dhcp no longer does this for us
                $tftp = $myip;
            }
            if ($ent and $ent->{gateway})
            {
                $gateway = $ent->{gateway};
            }
            if ($ent and $ent->{dynamicrange})
            {
                unless ($ent->{dhcpserver}
                        and xCAT::Utils->thishostisnot($ent->{dhcpserver}))
                {    #If specific, only one dhcp server gets a dynamic range
                    $range = $ent->{dynamicrange};
                    $range =~ s/[,-]/ /g;
                }
            }
            else
            {
                $callback->(
                    {
                     warning => [
                         "No dynamic range specified for $net, unknown systems on this network will not receive an address"
                     ]
                    }
                    );
            }
        }
        else
        {
            $callback->(
                  {
                   error =>
                     ["Unable to open networks table, please run makenetworks"],
                   errorcode => [1]
                  }
                  );
            return 1;
        }

        my @netent;
        my $maskn = unpack("N", inet_aton($mask));
        my $netn  = unpack("N", inet_aton($net));
        @netent = (
                   "  subnet $net netmask $mask {\n",
                   "    max-lease-time 43200;\n",
                   "    min-lease-time 43200;\n",
                   "    default-lease-time 43200;\n"
                   );
        if ($gateway)
        {
            my $gaten = unpack("N", inet_aton($gateway));
            if (($gaten & $maskn) == ($maskn & $netn))
            {
                push @netent, "    option routers  $gateway;\n";
            }
            else
            {
                $callback->(
                    {
                     error => [
                         "Specified gateway $gateway is not valid for $net/$mask, must be on same network"
                     ],
                     errorcode => [1]
                    }
                    );
            }
        }
        if ($tftp)
        {
            push @netent, "    next-server  $tftp;\n";
        }
        push @netent, "    option log-servers $myip;\n";
        push @netent, "    option ntp-servers $myip;\n";
        push @netent, "    option domain-name \"$domain\";\n";
        if ($nameservers)
        {
            push @netent, "    option domain-name-servers  $nameservers;\n";
        }
        push @netent, "    if option client-architecture = 00:00  { #x86\n";
        push @netent, "      filename \"pxelinux.0\";\n";
        push @netent,
          "    } else if option client-architecture = 00:02 { #ia64\n ";
        push @netent, "      filename \"elilo.efi\";\n";
        push @netent,
          "    } else if substring(filename,0,1) = null { #otherwise, provide yaboot if the client isn't specific\n ";
        push @netent, "      filename \"/yaboot\";\n";
        push @netent, "    }\n";
        if ($range) { push @netent, "    range dynamic-bootp $range;\n" }
        push @netent, "  } # $net\/$mask subnet_end\n";
        splice(@dhcpconf, $idx, 0, @netent);
    }
}

sub addnic
{
    my $nic        = shift;
    my $firstindex = 0;
    my $lastindex  = 0;
    unless (grep /} # $nic nic_end/, @dhcpconf)
    {    #add a section if not there
        $restartdhcp=1;
        print "Adding NIC $nic\n";
        push @dhcpconf, "shared-network $nic {\n";
        push @dhcpconf, "\} # $nic nic_end\n";
    }

    #return; #Don't touch it, it should already be fine..
    #my $idx=0;
    #while ($idx <= $#dhcpconf) {
    #  if ($dhcpconf[$idx] =~ /^shared-network $nic {/) {
    #    $firstindex = $idx; # found the first place to chop...
    #  } elsif ($dhcpconf[$idx] =~ /} # $nic network_end/) {
    #    $lastindex=$idx;
    #  }
    #  $idx++;
    #}
    #print Dumper(\@dhcpconf);
    #if ($firstindex and $lastindex) {
    #  splice @dhcpconf,$firstindex,($lastindex-$firstindex+1);
    #}
    #print Dumper(\@dhcpconf);
}

sub writeout
{
    my $targ;
    open($targ, '>', "/etc/dhcpd.conf");
    foreach (@dhcpconf)
    {
        print $targ $_;
    }
    close($targ);
}

sub newconfig
{

    # This function puts a standard header in and enough to make omapi work.
    my $passtab = xCAT::Table->new('passwd', -create => 1);
    push @dhcpconf, "#xCAT generated dhcp configuration\n";
    push @dhcpconf, "\n";
    push @dhcpconf, "authoritative;\n";
    push @dhcpconf, "ddns-update-style none;\n";
    push @dhcpconf,
      "option client-architecture code 93 = unsigned integer 16;\n";
    push @dhcpconf, "\n";
    push @dhcpconf, "omapi-port 7911;\n";        #Enable omapi...
    push @dhcpconf, "key xcat_key {\n";
    push @dhcpconf, "  algorithm hmac-md5;\n";
    (my $passent) =
      $passtab->getAttribs({key => omapi, username => 'xcat_key'}, 'password');
    my $secret = encode_base64(genpassword(32));    #Random from set of  62^32
    chomp $secret;
    if ($passent->{password}) { $secret = $passent->{password}; }
    else
    {
        $callback->(
             {
              data =>
                ["The dhcp server must be restarted for OMAPI function to work"]
             }
             );
        $passtab->setAttribs({key => omapi},
                             {username => 'xcat_key', password => $secret});
    }

    push @dhcpconf, "  secret \"" . $secret . "\";\n";
    push @dhcpconf, "};\n";
    push @dhcpconf, "omapi-key xcat_key;\n";
}

sub genpassword
{

    #Generate a pseudo-random password of specified length
    my $length     = shift;
    my $password   = '';
    my $characters =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890';
    srand;    #have to reseed, rand is not rand otherwise
    while (length($password) < $length)
    {
        $password .= substr($characters, int(rand 63), 1);
    }
    return $password;
}

1;
