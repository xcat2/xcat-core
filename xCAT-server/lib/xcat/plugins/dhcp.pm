# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::dhcp;
use strict;
use xCAT::Table;
use Data::Dumper;
use MIME::Base64;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use Socket;
use Sys::Syslog;
use IPC::Open2;
use xCAT::NetworkUtils;
use xCAT::Utils;
use xCAT::NodeRange;
use Fcntl ':flock';

my @dhcpconf; #Hold DHCP config file contents to be written back.
my @nrn;      # To hold output of networks table to be consulted throughout process
my $domain;
my $omshell;
my $statements;    #Hold custom statements to be slipped into host declarations
my $callback;
my $restartdhcp;
my $sitenameservers;
my $sitentpservers;
my $sitelogservers;
my $nrhash;
my $machash;
my $iscsients;
my $chainents;
my $tftpdir = xCAT::Utils->getTftpDir();
my $dhcpconffile = $^O eq 'aix' ? '/etc/dhcpsd.cnf' : '/etc/dhcpd.conf'; 

sub handled_commands
{
    return {makedhcp => "dhcp",};
}

sub delnode
{
    my $node  = shift;
    my $inetn = inet_aton($node);

    my $mactab = xCAT::Table->new('mac');
    my $ent;
    if ($machash) { $ent = $machash->{$node}->[0]; }
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
    my $nrent;
    my $chainent;
    my $ient;
    my $tftpserver;
    if ($chainents and $chainents->{$node}) {
        $chainent = $chainents->{$node}->[0];
    }
    if ($iscsients and $iscsients->{$node}) {
        $ient = $iscsients->{$node}->[0];
    }
    my $lstatements       = $statements;
    my $guess_next_server = 0;
    my $nxtsrv;
    if ($nrhash)
    {
        $nrent = $nrhash->{$node}->[0];
        if ($nrent and $nrent->{tftpserver})
        {
            #check the value of inet_ntoa(inet_aton("")),if the hostname cannot be resolved,
            #the value of inet_ntoa() will be "undef", which will cause fatal error
            my $tmp_name = inet_aton($nrent->{tftpserver});
            unless($tmp_name) {
                #tell the reason to the user
                $callback->(
                    { error => ["Unable to resolve the tftpserver for node"], errorcode => [1]}
                );
                return;
            }
            $tftpserver = inet_ntoa($tmp_name);
            $nxtsrv = $tftpserver;
            $lstatements =
                'next-server '
              . $tftpserver . ';'
              . $statements;
        }
        else
        {
            $guess_next_server = 1;
        }

        #else {
        # $nrent = $nrtab->getNodeAttribs($node,['servicenode']);
        # if ($nrent and $nrent->{servicenode}) {
        #  $statements = 'next-server  = \"'.inet_ntoa(inet_aton($nrent->{servicenode})).'\";'.$statements;
        # }
        #}
    }
    else
    {
        $guess_next_server = 1;
    }
    unless ($machash)
    {
        $callback->(
                   {
                    error => ["Unable to open mac table, it may not exist yet"],
                    errorcode => [1]
                   }
                   );
        return;
    }
    $ent = $machash->{$node}->[0]; #tab->getNodeAttribs($node, [qw(mac)]);
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
        my $ip = xCAT::Utils::getNodeIPaddress($hname);
        if ($hname eq '*NOIP*') {
            $hname = $node . "-noip".$mac;
            $hname =~ s/://g;
            $ip='DENIED';
#        } #if 'guess_next_server', inherit from the network provided value... see how this pans out
#       if ($guess_next_server and $ip and $ip ne "DENIED")
#       {
#           $nxtsrv = xCAT::Utils->my_ip_facing($hname);
#           if ($nxtsrv)
#           {
#               $tftpserver = $nxtsrv;
#               $lstatements = "next-server $nxtsrv;$statements";
#           } #of course, we set the xNBA variable to let that propogation carry forward into filename uri interpolation
        } elsif ($guess_next_server) {
            $nxtsrv='${next-server}'; #if floating IP support, cause gPXE command-line expansion patch to drive inheritence from network
        }
        my $doiscsi=0;
        if ($ient and $ient->{server} and $ient->{target}) {
            $doiscsi=1;
            unless (defined ($ient->{lun})) { #Some firmware fails to properly implement the spec, so we must explicitly say zero for such firmware
                $ient->{lun} = 0;
            }
            my $iscsirootpath ='iscsi:'.$ient->{server}.':6:3260:'.$ient->{lun}.':'.$ient->{target};
            if (defined ($ient->{iname})) { #Attempt to use gPXE or IBM iSCSI formats to specify the initiator
                #This all goes on one line, but will break it out to at least be readable in here
                $lstatements = 'if option vendor-class-identifier = \"ISAN\" { ' #This is declared by IBM iSCSI initiators, will call it 'ISAN' mode
                                   .'option isan.iqn \"'.$ient->{iname}.'\"; '  #Use vendor-spcefic option to declare the expected Initiator name
                                   .'option isan.root-path \"'.$iscsirootpath.'\"; ' #We must *not* use standard root-path if using ISAN style options
                              .'} else { '
                                   .'option root-path \"'.$iscsirootpath.'\"; ' #For everything but ISAN, use standard, RFC defined behavior for root
                                   .'if exists gpxe.bus-id { '  #Since our iscsi-initiator-iqn is in no way a standardized thing, only use it for gPXE
                                       . ' option iscsi-initiator-iqn \"'.$ient->{iname}.'\";' #gPXE will consider option 203 for initiator IQN
                                   . '}'
                             . '}'
                             .$lstatements;
                print $lstatements;
            } else { #We stick to the good old RFC defined behavior, ISAN, gPXE, everyone should be content with this so long as no initiator name need be specified
                $lstatements = 'option root-path \"'.$iscsirootpath.'\";'.$lstatements;
            }
        }
        if ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'xnba' and $lstatements !~ /filename/) {
            if (-f "$tftpdir/xcat/xnba.kpxe") {
                if ($doiscsi and $chainent and $chainent->{currstate} and ($chainent->{currstate} eq 'iscsiboot' or $chainent->{currstate} eq 'boot')) {
                    $lstatements = 'if exists gpxe.bus-id { filename = \"\"; } else if exists client-architecture { filename = \"xcat/xnba.kpxe\"; } '.$lstatements;
                } else {
                    $lstatements = 'if option user-class-identifier = \"xNBA\" { filename = \"http://'.$nxtsrv.'/tftpboot/xcat/xnba/nodes/'.$node.'\"; } else if exists client-architecture { filename = \"xcat/xnba.kpxe\"; } '.$lstatements; #Only PXE compliant clients should ever receive xNBA
                } 
            } #TODO: warn when windows
        } elsif ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'pxe' and $lstatements !~ /filename/) {
            if (-f "$tftpdir/xcat/xnba.kpxe") {
                if ($doiscsi and $chainent and $chainent->{currstate} and ($chainent->{currstate} eq 'iscsiboot' or $chainent->{currstate} eq 'boot')) {
                    $lstatements = 'if exists gpxe.bus-id { filename = \"\"; } else if exists client-architecture { filename = \"xcat/xnba.kpxe\"; } '.$lstatements;
                } else {
                    $lstatements = 'if option vendor-class-identifier = \"ScaleMP\" { filename = \"vsmp/pxelinux.0\"; } else { filename = \"pxelinux.0\"; }'.$lstatements;
                }
            }
        }


        if ( $^O eq 'aix')
        {
            addnode_aix( $ip, $mac, $hname, $tftpserver);
        }
        else
        {
            if ( !grep /:/,$mac ) {
                $mac = lc($mac);
                $mac =~ s/(\w{2})/$1:/g;
                $mac =~ s/:$//;
            }

            #syslog("local4|err", "Setting $node ($hname|$ip) to " . $mac);
            print $omshell "new host\n";
            print $omshell
                "set name = \"$hname\"\n";    #Find and destroy conflict name
                print $omshell "open\n";
            print $omshell "remove\n";
            print $omshell "close\n";
            if ($ip and $ip ne 'DENIED') {
                print $omshell "new host\n";
                print $omshell "set ip-address = $ip\n";   #find and destroy ip conflict
                    print $omshell "open\n";
                print $omshell "remove\n";
                print $omshell "close\n";
            }
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
                if ($ip) {
                    print $omshell "set ip-address = $ip\n";
                }
                if ($lstatements)
                {
                    $lstatements = 'ddns-hostname \"'.$node.'\"; send host-name \"'.$node.'\";'.$lstatements;

                } else {
                    $lstatements = 'ddns-hostname \"'.$node.'\"; send host-name \"'.$node.'\";';
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
}

######################################################
# Add nodes into dhcpsd.cnf. For AIX only
######################################################
sub addnode_aix
{
    my $ip          = shift;
    my $mac         = shift;
    my $hname       = shift;
    my $tftpserver  = shift;

    $restartdhcp = 1;

    # Format the mac address to aix
    $mac =~ s/://g;
    $mac = lc($mac);

    delnode_aix ( $hname);

#Find the location to insert node
    my $isSubnetFound = 0;
    my $i;
    my $netmask;
    for ($i = 0; $i < scalar(@dhcpconf); $i++)
    {
        if ( $dhcpconf[$i] =~ / ([\d\.]+)\/(\d+) ip configuration end/)
        {
            if (xCAT::Utils::isInSameSubnet( $ip, $1, $2, 1))
            {
                $isSubnetFound = 1;
                $netmask = $2;
                last;
            }
        }
    }

# Format the netmask from AIX format (24) to Linux format (255.255.255.0)
    my $netmask_linux = xCAT::Utils::formatNetmask( $netmask,1,0);

    # Create node section
    my @node_section = ();
    push @node_section, "        client 1 $mac $ip #node $hname start\n";
    push @node_section, "        {\n";
    push @node_section, "            option 1 $netmask_linux\n";
    push @node_section, "            option 12 $hname\n";
#    push @node_section, "            option sa $tftpserver\n";
#    push @node_section, "            option bf \"/tftpboot/$hname\"\n";
    push @node_section, "        } # node $hname end\n";
    

    if ( $isSubnetFound)
    {
        splice @dhcpconf, $i, 0, @node_section;
    }
}

###################################################
# Delete nodes in dhcpsd.cnf. For AIX only
###################################################
sub delnode_aix
{
    my $hname = shift;
    my $i;
    my $node_start = 0;
    my $node_end   = 0;
    for ($i = 0; $i < scalar(@dhcpconf); $i++)
    {
        if ( $dhcpconf[$i] =~ /node $hname start/)
        {
            $node_start = $i;
        }
        elsif ( $dhcpconf[$i] =~ /node $hname end/)
        {
            $node_end = $i;
            last;
        }
    }
    if ( $node_start && $node_end)
    {
        $restartdhcp = 1;
        splice @dhcpconf, $node_start, ($node_end - $node_start + 1);
        return 1;
    }
    else
    {
        return 0;
    }
}

sub preprocess_request
{
    my $req = shift;
    $callback = shift;
    my $localonly;
    if (ref $req->{arg}) {
        @ARGV       = @{$req->{arg}};
        GetOptions('l' => \$localonly);
    }
    #Exit if the packet has been preprocessed
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my @requests =
      ({%$req});    #Start with a straight copy to reflect local instance
    unless ($localonly) {
        my @sn = xCAT::Utils->getSNList('dhcpserver');
        foreach my $s (@sn)
        {
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $s;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;
        }
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
    my $oldmask = umask 0077;
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
           INTF: foreach $dhcpif (split /;/,$dhcpinterfaces) {
              my $host;
              my $savehost;
              my $foundself=1;
              if ($dhcpif =~ /\|/) {
                 $foundself=0;
                 
                 (my $ngroup,$dhcpif) = split /\|/,$dhcpif;
                 foreach $host (noderange($ngroup)) {
                    $savehost=$host;
                    unless (xCAT::Utils->thishostisnot($host)) {
                        $foundself=1;
                        last;
                    }
                 }
                 if (!defined($savehost)) { # host not defined in db,
                                 # probably management node
                    unless (xCAT::Utils->thishostisnot($ngroup)) {
                        $foundself=1;
                    }
                 }
              }
              unless ($foundself) {
                  next INTF;
              }
              foreach (split /[,\s]+/, $dhcpif)
              {
                 $activenics{$_} = 1;
                 $querynics = 0;
              }
           }
        }
        ($href) = $sitetab->getAttribs({key => 'nameservers'}, 'value');
        if ($href and $href->{value}) {
            $sitenameservers = $href->{value};
        }
        ($href) = $sitetab->getAttribs({key => 'ntpservers'}, 'value');
        if ($href and $href->{value}) {
            $sitentpservers = $href->{value};
        }
        ($href) = $sitetab->getAttribs({key => 'logservers'}, 'value');
        if ($href and $href->{value}) {
            $sitelogservers = $href->{value};
        }
        ($href) = $sitetab->getAttribs({key => 'domain'}, 'value');
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
    
   if(grep /-h/,@{$req->{arg}}) {
        my $usage="Usage: makedhcp -n\n\tmakedhcp -a\n\tmakedhcp -a -d\n\tmakedhcp -d noderange\n\tmakedhcp <noderange> [-s statements]\n\tmakedhcp [-h|--help]";
        $callback->({data => [$usage]});
        return;
    }

   my $dhcplockfd;
   open($dhcplockfd,">","/tmp/xcat/dhcplock");
   flock($dhcplockfd,LOCK_EX);
   if (grep /^-n$/, @{$req->{arg}})
    {
        if (-e $dhcpconffile)
        {
            my $bakname = "$dhcpconffile.xcatbak";
            rename("$dhcpconffile", $bakname);
        }
    }
    else
    {
        my $rconf;
        open($rconf, $dhcpconffile);    # Read file into memory
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
	my $nettab = xCAT::Table->new("networks");
	my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');
    if ($^O eq 'aix')
    {
        @nrn = xCAT::Utils::get_subnet_aix();
    }
    else
    {
        my @nsrnoutput = split /\n/,`/bin/netstat -rn`;
        splice @nsrnoutput, 0, 2;
        foreach (@nsrnoutput) { #scan netstat
            my @parts = split  /\s+/;
            push @nrn,$parts[0].":".$parts[7].":".$parts[2].":".$parts[3];
        }
    }

	foreach(@vnets){
		my $n = $_->{net};
		my $if = $_->{mgtifname};
		my $nm = $_->{mask};
		#$callback->({data => ["array of nets $n : $if : $nm"]});
        if ($if =~ /!remote!/) { #only take in networks with special interface
    		push @nrn, "$n:$if:$nm";
        }
	}
    if ($querynics)
    {    #Use netstat to determine activenics only when no site ent.
        foreach (@nrn)
        {
            my @ent = split /:/;
            my $firstoctet = $ent[0];
            $firstoctet =~ s/^(\d+)\..*/$1/;
            if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239) or $ent[0] eq "127.0.0.0" or $ent[0] eq '127')
            {
                next;
            }
            if ($ent[1] =~ m/(remote|ipoib|ib|vlan|bond|eth|myri|man|wlan|en\d+)/)
            {    #Mask out many types of interfaces, like xCAT 1.x
                $activenics{$ent[1]} = 1;
            }
        }
    }
    
    if ( $^O ne 'aix')
    {
#add the active nics to /etc/sysconfig/dhcpd
        if (-e "/etc/sysconfig/dhcpd") {
            open DHCPD_FD, "/etc/sysconfig/dhcpd";
            my $syscfg_dhcpd = "";
            my $found = 0;
            my $dhcpd_key = "DHCPDARGS";
            my $os = xCAT::Utils->osver();
            if ($os =~ /sles/i) {
                $dhcpd_key = "DHCPD_INTERFACE";
            }

            my $ifarg = "$dhcpd_key=\"";
            foreach (keys %activenics) {
                if (/!remote!/) { next; }
                $ifarg .= " $_";
            }
            $ifarg =~ s/^ //;
            $ifarg .= "\"\n";

            while (<DHCPD_FD>) {
                if ($_ =~ m/^$dhcpd_key/) {
                    $found = 1;
                    $syscfg_dhcpd .= $ifarg;
                }else {
                    $syscfg_dhcpd .= $_;
                }
            }

            if ( $found eq 0 ) {
                $syscfg_dhcpd .= $ifarg;
            }
            close DHCPD_FD; 

            open DBG_FD, '>', "/etc/sysconfig/dhcpd";
            print DBG_FD $syscfg_dhcpd;
            close DBG_FD;
        } else {
            $callback->({error=>"The file /etc/sysconfig/dhcpd doesn't exist, check the dhcp server"});
#        return;
        }
    }
    
    unless ($dhcpconf[0])
    {            #populate an empty config with some starter data...
        $restartdhcp=1;
        newconfig();
    }
    if ( $^O ne 'aix')
    {
        foreach (keys %activenics)
        {
            addnic($_);
        }
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

            my @entries=();
            if ($mactab) {
                @entries = ($mactab->getAllNodeAttribs([qw(mac)]));
            }
            foreach (@entries)
            {
                push @{$req->{node}}, $_->{node};
            }
        }
    }

    foreach (@nrn)
    {
        my @line = split /:/;
        my $firstoctet = $line[0];
        $firstoctet =~ s/^(\d+)\..*/$1/;
        if ($line[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239))
        {
            next;
        }
        if ($activenics{$line[1]} and $line[3] !~ /G/)
        {
            addnet($line[0], $line[2]);
        }
    }

    if ($req->{node})
    {
        my $ip_hash;
        foreach my $node ( @{$req->{node}} ) {
            my $hoststab  = xCAT::Table->new('hosts');
            my $ent = $hoststab->getNodeAttribs( $node, ['ip'] );
            if ( $ent->{ip} ) {
                if ( $ip_hash->{ $ent->{ip} } ) {
                    $callback->({error=>["Duplicated IP addresses in hosts table for following nodes: $node," . $ip_hash->{ $ent->{ip} }],errorcode=>[1]});
                    return;
                }
                $ip_hash->{ $ent->{ip} } = $node;
            }
        }

        @ARGV       = @{$req->{arg}};
        $statements = "";
        GetOptions('s|statements=s' => \$statements);

        if ($^O ne 'aix')
        {
            my $passtab = xCAT::Table->new('passwd');
            my $ent;
            ($ent) = $passtab->getAttribs({key => "omapi"}, qw(username password));
            unless ($ent->{username} and $ent->{password})
            {
                $callback->({error=>["Unable to access omapi key from passwd table, add the key from dhcpd.conf or makedhcp -n to create a new one"],errorcode=>[1]});
                syslog("local4|err","Unable to access omapi key from passwd table, unable to update DHCP configuration");
                return;
            }    # TODO sane err
#Have nodes to update
#open2($omshellout,$omshell,"/usr/bin/omshell");
            open($omshell, "|/usr/bin/omshell > /dev/null");

            print $omshell "key "
                . $ent->{username} . " \""
                . $ent->{password} . "\"\n";
            print $omshell "connect\n";
        }
        
        my $nrtab = xCAT::Table->new('noderes');
        my $chaintab = xCAT::Table->new('chain');
        if ($chaintab) {
            $chainents = $chaintab->getNodesAttribs($req->{node},['currstate']);
        } else {
            $chainents = undef;
        }
        $nrhash = $nrtab->getNodesAttribs($req->{node}, ['tftpserver','netboot']);
        my $iscsitab = xCAT::Table->new('iscsi');
        if ($iscsitab) {
            $iscsients = $iscsitab->getNodesAttribs($req->{node},[qw(server target lun iname)]);
        }
        my $mactab = xCAT::Table->new('mac');
        $machash = $mactab->getNodesAttribs($req->{node},['mac']);
        foreach (@{$req->{node}})
        {
            if (grep /^-d$/, @{$req->{arg}})
            {
                if ( $^O eq 'aix')
                {
                    delnode_aix $_;
                }
                else
                {
                    delnode $_;
                }
            }
            else
            {
                if  (xCAT::NetworkUtils->getipaddr($_) and not xCAT::Utils->nodeonmynet($_))
                {
                    next;
                }
                addnode $_;
            }
        }
        close($omshell) if ($^O ne 'aix');
    }
    writeout();
    if ($restartdhcp) {
        if ( $^O eq 'aix')
        {
            restart_dhcpd_aix();
        }
        else
        {
            system("/etc/init.d/dhcpd restart");
            system("chkconfig dhcpd on");
        }
    }
    flock($dhcplockfd,LOCK_UN);
    umask $oldmask;
}
# Restart dhcpd on aix
sub restart_dhcpd_aix
{
    #Check if dhcpd is running
    my @res = xCAT::Utils->runcmd('lssrc -s dhcpsd',0);
    if ( $::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("E", "Failed to check dhcpsd status\n");
    }
    if ( grep /\sactive/, @res)
    {
        xCAT::Utils->runcmd('refresh -s dhcpsd',0);
        xCAT::MsgUtils->message("E", "Failed to refresh dhcpsd configuration\n") if ( $::RUNCMD_RC);
    }
    else
    {
        xCAT::Utils->runcmd('startsrc -s dhcpsd',0);
        xCAT::MsgUtils->message("E", "Failed to start dhcpsd\n" ) if ( $::RUNCMD_RC);
    }
    return 1;
}


sub putmyselffirst {
    my $srvlist = shift;
            if ($srvlist =~ /,/) { #TODO: only reshuffle when requested, or allow opt out of reshuffle?
                my @dnsrvs = split /,/,$srvlist;
                my @reordered;
                foreach (@dnsrvs) {
                    if (xCAT::Utils->thishostisnot($_)) {
                        push @reordered,$_;
                    } else {
                        unshift @reordered,$_;
                    }
                }
                $srvlist = join(', ',@reordered);
            }
            return $srvlist;
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
            my @ent = split /:/;
            $firstoctet = $ent[0];
            $firstoctet =~ s/^(\d+)\..*/$1/;
            if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239))
            {
                next;
            }
            if ($ent[0] eq $net and $ent[2] eq $mask)
            {
                $nic = $ent[1];
            }
        }
        #print " add $net $mask under $nic\n";
        my $idx = 0;
        if ( $^O ne 'aix')
        {
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
        }

        # if here, means we found the idx before which to insert
        my $nettab = xCAT::Table->new("networks");
        my $nameservers;
        my $ntpservers;
        my $logservers;
        my $gateway;
        my $tftp;
        my $range;
        my $myip;
        $myip = xCAT::Utils->my_ip_facing($net);
        if ($nettab)
        {
            my $mask_formated = $mask;
            if ( $^O eq 'aix')
            {
                $mask_formated = inet_ntoa(pack("N", 2**$mask - 1 << (32 - $mask)));
            }
            my ($ent) =
              $nettab->getAttribs({net => $net, mask => $mask_formated},
                    qw(tftpserver nameservers ntpservers logservers gateway dynamicrange dhcpserver));
            if ($ent and $ent->{ntpservers}) {
                $ntpservers = $ent->{ntpservers};
            } elsif ($sitentpservers) {
                $ntpservers = $sitentpservers;
            }
            if ($ent and $ent->{logservers}) {
                $logservers = $ent->{logservers};
            } elsif ($sitelogservers) {
                $logservers = $sitelogservers;
            }
            if ($ent and $ent->{nameservers})
            {
                $nameservers = $ent->{nameservers};
            }
            else
            {
                if ($sitenameservers) {
                    $nameservers = $sitenameservers;
                } else {
                $callback->(
                    {
                     warning => [
                         "No $net specific entry for nameservers, and no nameservers defined in site table."
                     ]
                    }
                    );
                }
            }
            $nameservers=putmyselffirst($nameservers);
            $ntpservers=putmyselffirst($ntpservers);
            $logservers=putmyselffirst($logservers);


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
                         "No dynamic range specified for $net. If hardware discovery is being used, a dynamic range is required."
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

        if ( $^O eq 'aix')
        {
            return gen_aix_net( $myip, $net, $mask, $gateway, $tftp, 
                                $logservers, $ntpservers, $domain,
                                $nameservers, $range);
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
        if ($logservers) {
        	push @netent, "    option log-servers $logservers;\n";
        } elsif ($myip){
        	push @netent, "    option log-servers $myip;\n";
        }
        if ($ntpservers) {
        	push @netent, "    option ntp-servers $ntpservers;\n";
        } elsif ($myip){
        	push @netent, "    option ntp-servers $myip;\n";
        }
        push @netent, "    option domain-name \"$domain\";\n";
        if ($nameservers)
        {
            push @netent, "    option domain-name-servers  $nameservers;\n";
        }
        my $ddnserver = $nameservers;
        $ddnserver =~ s/,.*//;
        push @netent, "zone $domain. {\n";
        push @netent, "   primary $ddnserver; key xcat_key; \n";
        push @netent, " }\n";
        my $tmpmaskn = unpack("N", inet_aton($mask));
        my $maskbits = 32;
        while (not ($tmpmaskn & 1)) {
            $maskbits--;
            $tmpmaskn=$tmpmaskn>>1;
        }

                       # $lstatements = 'if exists gpxe.bus-id { filename = \"\"; } else if exists client-architecture { filename = \"xcat/xnba.kpxe\"; } '.$lstatements;
        push @netent, "    if option user-class-identifier = \"xNBA\" { #x86, xCAT Network Boot Agent\n";
        push @netent, "       filename = \"http://$tftp/tftpboot/xcat/xnba/nets/".$net."_".$maskbits."\";\n";
        push @netent, "    } else if option client-architecture = 00:00  { #x86\n";
        push @netent, "      filename \"xcat/xnba.kpxe\";\n";
        push @netent, "    } else if option vendor-class-identifier = \"Etherboot-5.4\"  { #x86\n";
        push @netent, "      filename \"xcat/xnba.kpxe\";\n";
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

######################################################
# Generate network configuration for aix
######################################################
sub gen_aix_net
{
    my $myip        = shift;
    my $net         = shift; 
    my $mask        = shift;
    my $gateway     = shift;
    my $tftp        = shift;
    my $logservers  = shift;
    my $ntpservers  = shift;
    my $domain      = shift;
    my $nameservers = shift;
    my $range       = shift;

    my $idx = 0;
    while ( $idx <= $#dhcpconf)
    {
        if ($dhcpconf[$idx] =~ /#Network configuration end\n/)
        {
            last;
        }
        $idx++;
    }
    
    unless ($dhcpconf[$idx] =~ /#Network configuration end\n/)
    {
        return 1;    #TODO: this is an error condition
    }

    $range =~ s/ /-/;
    my @netent = ( "network $net $mask\n{\n");
    if ( $gateway)
    {
        if (xCAT::Utils::isInSameSubnet($gateway,$net,$mask,1))
        {
            push @netent, "    option 3 $gateway\n";
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
#    if ($tftp)
#    {
#        push @netent, "    option 66 $tftp\n";
#    }
    if ($logservers) {
        $logservers =~ s/,/ /g;
        push @netent, "    option 7 $logservers\n";
    } elsif ($myip){
        push @netent, "    option 7 $myip\n";
    }
    if ($ntpservers) {
        $ntpservers =~ s/,/ /g;
        push @netent, "    option 42 $ntpservers\n";
    } elsif ($myip){
        push @netent, "    option 42 $myip\n";
    }
    push @netent, "    option 15 \"$domain\"\n";
    if ($nameservers)
    {
        $nameservers =~ s/,/ /g;
        push @netent, "    option 6 $nameservers\n";
    }
    push @netent, "    subnet $net $range\n    {\n";
    push @netent, "    } # $net/$mask ip configuration end\n";
    push @netent, "} # $net/$mask subnet_end\n\n";

    splice(@dhcpconf, $idx, 0, @netent);
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
        if ($nic =~ /!remote!/) {
            push @dhcpconf, "#shared-network $nic {\n";
            push @dhcpconf, "#\} # $nic nic_end\n";
        } else {
            push @dhcpconf, "shared-network $nic {\n";
            push @dhcpconf, "\} # $nic nic_end\n";
        }

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
    open($targ, '>', $dhcpconffile);
    foreach (@dhcpconf)
    {
        print $targ $_;
    }
    close($targ);
}

sub newconfig
{
    return newconfig_aix() if ( $^O eq 'aix');

    # This function puts a standard header in and enough to make omapi work.
    my $passtab = xCAT::Table->new('passwd', -create => 1);
    push @dhcpconf, "#xCAT generated dhcp configuration\n";
    push @dhcpconf, "\n";
    push @dhcpconf, "authoritative;\n";
    push @dhcpconf, "option space isan;\n";
    push @dhcpconf, "option isan-encap-opts code 43 = encapsulate isan;\n";
    push @dhcpconf, "option isan.iqn code 203 = string;\n";
    push @dhcpconf, "option isan.root-path code 201 = string;\n";
    push @dhcpconf, "option space gpxe;\n";
    push @dhcpconf, "option gpxe-encap-opts code 175 = encapsulate gpxe;\n";
    push @dhcpconf, "option gpxe.bus-id code 177 = string;\n";
    push @dhcpconf, "option user-class-identifier code 77 = string;\n";
    push @dhcpconf, "option gpxe.no-pxedhcp code 176 = unsigned integer 8;\n";
    push @dhcpconf, "option iscsi-initiator-iqn code 203 = string;\n"; #Only via gPXE, not a standard
    push @dhcpconf, "ddns-update-style interim;\n";
    push @dhcpconf, "update-static-leases on;\n"; #makedns rendered optional
    push @dhcpconf,
      "option client-architecture code 93 = unsigned integer 16;\n";
    push @dhcpconf, "option gpxe.no-pxedhcp 1;\n";
    push @dhcpconf, "\n";
    push @dhcpconf, "omapi-port 7911;\n";        #Enable omapi...
    push @dhcpconf, "key xcat_key {\n";
    push @dhcpconf, "  algorithm hmac-md5;\n";
    (my $passent) =
      $passtab->getAttribs({key => 'omapi', username => 'xcat_key'}, 'password');
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
        $passtab->setAttribs({key => 'omapi'},
                             {username => 'xcat_key', password => $secret});
    }

    push @dhcpconf, "  secret \"" . $secret . "\";\n";
    push @dhcpconf, "};\n";
    push @dhcpconf, "omapi-key xcat_key;\n";
    push @dhcpconf, ('class "pxe" {'."\n","   match if substring (option vendor-class-identifier, 0, 9) = \"PXEClient\";\n","   ddns-updates off;\n","    max-lease-time 600;\n","}\n");
}

sub newconfig_aix
{
    push @dhcpconf, "#xCAT generated dhcp configuration\n";
    push @dhcpconf, "\n";
#push @dhcpconf, "numLogFiles 4\n";
#push @dhcpconf, "logFileSize 100\n";
#push @dhcpconf, "logFileName /var/log/dhcpsd.log\n";
#push @dhcpconf, "logItem SYSERR\n";
#push @dhcpconf, "logItem OBJERR\n";
#push @dhcpconf, "logItem PROTERR\n";
#push @dhcpconf, "logItem WARNING\n";
#push @dhcpconf, "logItem EVENT\n";
#push @dhcpconf, "logItem ACTION\n";
#push @dhcpconf, "logItem INFO\n";
#push @dhcpconf, "logItem ACNTING\n";
#push @dhcpconf, "logItem TRACE\n";
    
    push @dhcpconf, "leaseTimeDefault 43200 seconds\n";
    push @dhcpconf, "#Network configuration begin\n";
    push @dhcpconf, "#Network configuration end\n";
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
