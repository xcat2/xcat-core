# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::dhcp;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use IPC::Open2;
use xCAT::Table;
#use Data::Dumper;
use MIME::Base64;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use Socket;
my $candoipv6 = eval {
    require Socket6;
    1;
};
use Sys::Syslog;
use IPC::Open2;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils qw/getipaddr/;
use xCAT::ServiceNodeUtils;
use xCAT::NodeRange;
use Fcntl ':flock';

my @aixcfg;  # hold AIX entries created by NIM
my @dhcpconf; #Hold DHCP config file contents to be written back.
my @dhcp6conf; #ipv6 equivalent
my @nrn;      # To hold output of networks table to be consulted throughout process
my @nrn6; #holds ip -6 route output on Linux, yeah, name doesn't make much sense now..
my $site_domain;
my @alldomains;
my $omshell;
my $omshell6; #separate session to DHCPv6 instance of dhcp
my $statements;    #Hold custom statements to be slipped into host declarations
my $localonly;     # flag for running only on local server - needs to be global
my $callback;
my $restartdhcp;
my $restartdhcp6;
my $sitenameservers;
my $sitentpservers;
my $sitelogservers;
my $nrhash;
my $machash;
my $vpdhash;
my $iscsients;
my $nodetypeents;
my $chainents;
my $tftpdir = xCAT::TableUtils->getTftpDir();
use Math::BigInt;
my $dhcpconffile = $^O eq 'aix' ? '/etc/dhcpsd.cnf' : '/etc/dhcpd.conf'; 
my %dynamicranges; #track dynamic ranges defined to see if a host that resolves is actually a dynamic address
my %netcfgs;
my $distro = xCAT::Utils->osver();

# dhcp 4.x will use /etc/dhcp/dhcpd.conf as the config file
my $dhcp6conffile;
if ( $^O ne 'aix' and -d "/etc/dhcp" ) {
    $dhcpconffile = '/etc/dhcp/dhcpd.conf';
    $dhcp6conffile = '/etc/dhcp/dhcpd6.conf'; 
}
my $usingipv6;

# define usage statement
my $usage="Usage: makedhcp -n\n\tmakedhcp -a\n\tmakedhcp -a -d\n\tmakedhcp -d noderange\n\tmakedhcp <noderange> [-s statements]\n\tmakedhcp -q\n\tmakedhcp [-h|--help]";


# is this ubuntu ?
if ( $distro =~ /ubuntu.*/ ){
    if (-e '/etc/dhcp/') {
        $dhcpconffile = '/etc/dhcp/dhcpd.conf';
    }
    else {
        $dhcpconffile = '/etc/dhcp3/dhcpd.conf';	
    }
}

sub check_uefi_support {
	my $ntent = shift;
	my %blacklist = (
		"win2k3.*" => 1,
		"winxp.*" => 1,
		"SL5.*" => 1,
		"rhels5.*" => 1,
		"centos5.*" => 1,
		"sl5.*" => 1,
		"sles10.*" => 1,
		"esxi4.*" => 1);
	if ($ntent and $ntent->{os}) {
		 foreach (keys %blacklist) {
			if ($ntent->{os} =~ /$_/) {
				return 0;
			}
		}
	}
	if ($ntent->{os} =~ /^win/ or $ntent->{os} =~ /^hyperv/) { #UEFI support is a tad different, need to punt..
		return 2;
	}
	return 1;
}

# check whether the proxydhcp has been enabled.
sub proxydhcp {
    my $nrent = shift;

    if ($nrent && defined $nrent->{'proxydhcp'} && $nrent->{'proxydhcp'} =~ /0|no|n/i) {
        return 0;
    }
    my @output = xCAT::Utils->runcmd("ps -C proxydhcp-xcat", -1);
    if (@output) {
        if (grep /proxydhcp-xcat/, @output) {
            return 1;
        }
    }

    return 0;
}

sub ipIsDynamic { 
	#meant to be v4/v6 agnostic.  DHCPv6 however takes some care to allow a dynamic range to overlap static reservations
    #xCAT will for now continue to advise people to keep their nodes out of the dynamic range
    my $ip = shift;
    my $number = getipaddr($ip,GetNumber=>1);
    unless ($number) { # shouldn't be possible, but pessimistically presume it dynamically if so
        return 1;
    }
    foreach (values %dynamicranges) {
        if ($_->[0] <= $number and $_->[1] >= $number) {
            return 1;
        } 
    }
    return 0; #it isn't in any of the dynamic ranges we are aware of
}

sub handled_commands
{
    return {makedhcp => "dhcp",};
}

######################################################
# List nodes in DHCP for both IPv4 and IPv6
######################################################
sub listnode
{
    my $node  = shift;
    my $callback  = shift;
    my $lines;
    my $ipaddr = "";
    my $hwaddr;
    my $nname;
    my $rsp;
    my ($OMOUT,$OMIN,$OMOUT6,$OMIN6);

    my $usingipv6;
    my $omapiuser;
    my $omapikey;
    # Collect the omapi user and key from the passwd table
    my $pwtab = xCAT::Table->new("passwd");
    my @pws = $pwtab->getAllAttribs('key','username','password','cryptmethod','authdomain','comments','disable');
    foreach (@pws) {
        # Look for the opapi entry in the passwd table
        if ($_->{key} =~ "omapi") { #omapi key
            # save username and password for omapi connection
            $omapiuser = $_->{username};
            $omapikey = $_->{password};
        }
     }
    # Look through the networks table for networks with IPv6 format for address 
    my $nettab = xCAT::Table->new("networks");
    my @vnets = $nettab->getAllAttribs('net','mgtifname','mask','dynamicrange','nameservers','ddnsdomain', 'domain');
    foreach (@vnets) {
        if ($_->{net} =~ /:/) { #IPv6 detected
            $usingipv6=1;
        }
     }

    # open ipv4 omshell file handles - $OMOUT will contain the response
    open2($OMOUT,$OMIN,"/usr/bin/omshell ");

    # setup omapi for the connection and check for the node requested
    print $OMIN "key "
     . $omapiuser . " \""
     . $omapikey . "\"\n";
    print $OMIN "connect\n";
    print $OMIN "new host\n";
    # specify which node we are looking up
    print $OMIN "set name = \"$node\"\n";
    print $OMIN "open\n";
    # the close will put the data into $OMOUT
    print $OMIN "close\n";
    close ($OMIN);
    my $name = 0;

    # Process the output 
    while (<$OMOUT>) {     # now read the output of sort(1)
        chomp $_;
        # if this line contains the node name
        if ($_ =~ $node) {
            # save the name returned 
            if ($name) {
                $nname = $_;
                $nname =~ s/name = //;
                $nname =~ s/"//g;
            }
            $name =1;
        }
        # if this line is the hardware-address line
        if ($_ =~ 'hardware-address') {
            # save the hardware address as it is with the hardware-address label
            $hwaddr = $_;
        }
        # if this line is the ip-address line
        elsif ($_ =~ 'ip-address') {
            # convert the hex IP address to a dotted decimal address for readability
            my ($ipname,$ip) = split /= /,$_;
            chomp($ip);
            my ($p1, $p2, $p3, $p4) = split(/\:/, $ip);
            my $dp1 = hex($p1);
            my $dp2 = hex($p2);
            my $dp3 = hex($p3);
            my $dp4 = hex($p4);
            $ipaddr = "ip-address = $dp1.$dp2.$dp3.$dp4";
        }
    }
    # if we collected the ip address then print out the information for this node
    if ($ipaddr) { 
	push @{$rsp->{data}}, "$nname: $ipaddr, $hwaddr";
	xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    close ($OMOUT);

    # if using IPv6 addresses check using omshell IPv6 port
    if ($usingipv6) {
         open2($OMOUT6,$OMIN6,"/usr/bin/omshell ");
         print $OMOUT6 "port 7912\n";
         print $OMOUT6 "connect\n";
         print $OMIN6 "key "
          . $omapiuser . " \""
          . $omapikey . "\"\n";
         print $OMIN6 "connect\n";
         print $OMIN6 "new host\n";
         # check for the node specified
         print $OMIN6 "set name = \"$node\"\n";
         print $OMIN6 "open\n";
         print $OMIN6 "close\n";
         close ($OMIN6);
         $name = 0;
         $ipaddr = "";
         while (<$OMOUT6>) {     # now read the output 
	     chomp $_;
             if ($_ =~ $node) {
                # save the name
                if ($name) {
			$nname = $_;
			$nname =~ s/name = //;
			$nname =~ s/"//g;
                }
                $name =1;
                }
             if ($_ =~ 'hardware-address') {
             # save the hardware-address   
		$hwaddr = $_;
             }
             elsif ($_ =~ 'ip-address') {
                #save the ip address
                my ($ipname,$ipaddr) = split /= /,$_;
                chomp($ipaddr);
             }
         }
         # print the information if the ip address is found
         if ($ipaddr) { 
	     push @{$rsp->{data}}, "$nname: $ipaddr, $hwaddr";
	     xCAT::MsgUtils->message("I", $rsp, $callback);
         }
         # close the IPv6 output file handle
     close ($OMOUT6);
     }
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
        my $count = 0;
        foreach $mace (@macs)
        {
            my $mac;
            my $hname;
            ($mac, $hname) = split(/!/, $mace);

            unless ($hname)
            {
                $hname = $node;
            }    #Default to hostname equal to nodename
            unless ($mac) { next; }    #Skip corrupt format

            if ( !grep /:/,$mac ) {
                $mac = lc($mac);
                $mac =~ s/(\w{2})/$1:/g;
                $mac =~ s/:$//;
            }
            my $hostname = $hname;
            my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
            if ( $client_nethash{$node}{mgtifname} =~ /hf/ )
            {
                if ( scalar(@macs) > 1 ) {
                    if ( $hname !~ /^(.*)-hf(.*)$/ ) {
                        $hostname = $hname . "-hf" . $count;
                    } else {
                        $hostname = $1 . "-hf" . $count;
                    }
                }
            }
            $count = $count + 2;

            unless ($hostname) { $hostname = $node; }
            print $omshell "new host\n";
            print $omshell
              "set name = \"$hostname\"\n";    #Find and destroy conflict name
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
                if (inet_aton($hostname))
                {
                    $ip = inet_ntoa(inet_aton($hostname));
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

sub addnode6 {
    #omshell to add host dynamically
    my $node = shift;
    unless ($vpdhash) { 
        $callback->({node=>[{name=>[$node],warning => ["Skipping DHCPv6 setup due to missing vpd.uuid information."]}]});
        return;
    }
    my $ent = $vpdhash->{$node}->[0]; #tab->getNodeAttribs($node, [qw(mac)]);
    unless ($ent and $ent->{uuid})
    {
        $callback->({node=>[{name=>[$node],warning => ["Skipping DHCPv6 setup due to missing vpd.uuid information."]}]});
        return;
    }
    #phase 1, dynamic and static addresses, hopefully ddns-hostname works, may be tricky to do 'send hostname'
    #since FQDN is the only thing to be sent down, and that RFC clearly suggests that the client
    #assembles that data, not host
    #tricky for us since the client wouldn't know it's hostname/fqdn in advance
    #unless acquired via IPv4 first
    #don't think dhclient is smart enough to assemble advertised domain with it's own name and then
    #request FQDN update
    #goal is simple enough, we want `hostname` to look sane *and* we want DNS to look right
    my $uuid = $ent->{uuid};
    $uuid =~ s/-//g;
    $uuid =~ s/(..)/$1:/g;
    $uuid =~ s/:\z//;
    $uuid =~ s/^/00:04:/;
    my $ip = getipaddr($node);
    if ($ip and $ip =~ /:/ and not ipIsDynamic($ip)) {
        $ip = getipaddr($ip,GetNumber=>1);
        $ip = $ip->as_hex;
        $ip =~ s/^0x//;
        $ip =~ s/(..)/$1:/g;
        $ip =~ s/:\z//;
        print $omshell6 "set ip-address = $ip\n";
    } else {
        $ip=0;
    }
    print $omshell6 "new host\n";
    print $omshell6 "set name = \"$node\"\n";    #Find and destroy conflict name
    print $omshell6 "open\n";
    print $omshell6 "remove\n";
    print $omshell6 "close\n";
    if ($ip) {
        print $omshell6 "new host\n";
        print $omshell6 "set ip-address = $ip\n";   #find and destroy ip conflict
        print $omshell6 "open\n";
        print $omshell6 "remove\n";
        print $omshell6 "close\n";
    }
    print $omshell6 "new host\n";
    print $omshell6 "set dhcp-client-identifier = " . $uuid . "\n";    #find and destroy DUID-UUID conflict
    print $omshell6 "open\n";
    print $omshell6 "remove\n";
    print $omshell6 "close\n";
    print $omshell6 "new host\n";
    print $omshell6 "set name = \"$node\"\n";
    print $omshell6 "set dhcp-client-identifier = $uuid\n";
    print $omshell6 'set statements = "ddns-hostname \"'.$node.'\";";'."\n";
    if ($ip) {
        print $omshell6 "set ip-address = $ip\n";
    }
    print $omshell6 "create\n";
    print $omshell6 "close\n";

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
    my $ntent;
    my $tftpserver;
    if ($chainents and $chainents->{$node}) {
        $chainent = $chainents->{$node}->[0];
    }
    if ($iscsients and $iscsients->{$node}) {
        $ient = $iscsients->{$node}->[0];
    }
    if ($nodetypeents and $nodetypeents->{$node}) {
	$ntent = $nodetypeents->{$node}->[0];
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
                    warning => ["Unable to open mac table, it may not exist yet"]
                   }
                   );
        return;
    }
    $ent = $machash->{$node}->[0]; #tab->getNodeAttribs($node, [qw(mac)]);
    unless ($ent and $ent->{mac})
    {
        $callback->(
                    {
                     warning => ["Unable to find mac address for $node"]
                    }
                    );
        return;
    }
    my @macs = split(/\|/, $ent->{mac});
    my $mace;
    my $deflstaments=$lstatements;
    my $count = 0;
    foreach $mace (@macs)
    {
        $lstatements=$deflstaments; #force recalc on every entry
        my $mac;
        my $hname;
        $hname = "";
        ($mac, $hname) = split(/!/, $mace);
        unless ($hname)
        {
            $hname = $node;
        }    #Default to hostname equal to nodename
        unless ($mac) { next; }    #Skip corrupt format
        my $ip = getipaddr($hname,OnlyV4=>1);
        if ($hname eq '*NOIP*') {
            $hname = $node . "-noip".$mac;
            $hname =~ s/://g;
            $ip='DENIED';
#        } #if 'guess_next_server', inherit from the network provided value... see how this pans out
#       if ($guess_next_server and $ip and $ip ne "DENIED")
#       {
#           $nxtsrv = xCAT::NetworkUtils->my_ip_facing($hname);
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
        my $douefi=check_uefi_support($ntent);
        if ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'xnba' and $lstatements !~ /filename/) {
            if (-f "$tftpdir/xcat/xnba.kpxe") {
                if ($doiscsi and $chainent and $chainent->{currstate} and ($chainent->{currstate} eq 'iscsiboot' or $chainent->{currstate} eq 'boot')) {
                    $lstatements = 'if option client-architecture = 00:00 and not exists gpxe.bus-id { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; } '.$lstatements;
                } else {
                    # If proxydhcp daemon is enabled for windows deployment, do vendor-class-identifier of "PXEClient" to bump it over to proxydhcp.c
                    if (($douefi == 2 and $chainent->{currstate} =~ /^install/) or $chainent->{currstate} =~ /^winshell/) { 
                        if (proxydhcp($nrent)){ #proxy dhcp required in uefi invocation
                            $lstatements = 'if option client-architecture = 00:00 or option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else { filename = \"\"; }'.$lstatements; #If proxydhcp daemon is enable, use it.
                        } else {
                            $lstatements = 'if option user-class-identifier = \"xNBA\" and option client-architecture = 00:00 { always-broadcast on; filename = \"http://'.$nxtsrv.'/tftpboot/xcat/xnba/nodes/'.$node.'\"; } else if option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }'.$lstatements; #Only PXE compliant clients should ever receive xNBA
                        }
                    } elsif ($douefi and $chainent->{currstate} ne "boot" and $chainent->{currstate} ne "iscsiboot") {
                        $lstatements = 'if option user-class-identifier = \"xNBA\" and option client-architecture = 00:00 { always-broadcast on; filename = \"http://'.$nxtsrv.'/tftpboot/xcat/xnba/nodes/'.$node.'\"; } else if option user-class-identifier = \"xNBA\" and option client-architecture = 00:09 { filename = \"http://'.$nxtsrv.'/tftpboot/xcat/xnba/nodes/'.$node.'.uefi\"; } else if option client-architecture = 00:07 { filename = \"xcat/xnba.efi\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }'.$lstatements; #Only PXE compliant clients should ever receive xNBA
                    } else {
                        $lstatements = 'if option user-class-identifier = \"xNBA\" and option client-architecture = 00:00 { filename = \"http://'.$nxtsrv.'/tftpboot/xcat/xnba/nodes/'.$node.'\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }'.$lstatements; #Only PXE compliant clients should ever receive xNBA
                    }
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
        } elsif ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'yaboot') {
            $lstatements = 'filename = \"/yb/node/yaboot-'.$node.'\";'.$lstatements;
        } elsif ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'grub2') {
            $lstatements = 'filename = \"/boot/grub2/grub2-'.$node.'\";'.$lstatements;
        } elsif ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'petitboot') {
            $lstatements = 'option conf-file \"http://'.$nxtsrv.'/tftpboot/petitboot/'.$node.'\";'.$lstatements;
        } elsif ($nrent and $nrent->{netboot} and $nrent->{netboot} eq 'nimol') {
            $lstatements = 'supersede server.filename=\"/vios/nodes/'.$node.'\"'.$lstatements;
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
            my $hostname = $hname;
            my $hardwaretype = 1;
            my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
            if ( $client_nethash{$node}{mgtifname} =~ /hf/ )
            {
                $hardwaretype = 37;
                if ( scalar(@macs) > 1 ) {
                    if ( $hname !~ /^(.*)-hf(.*)$/ ) {
                        $hostname = $hname . "-hf" . $count;
                    } else {
                        $hostname = $1 . "-hf" . $count;
                    }
                }
            }

            #syslog("local4|err", "Setting $node ($hname|$ip) to " . $mac);
            print $omshell "new host\n";
            print $omshell
                "set name = \"$hostname\"\n";    #Find and destroy conflict name
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
            print $omshell "set name = \"$hostname\"\n";
            print $omshell "set hardware-address = " . $mac . "\n";
            print $omshell "set hardware-type = $hardwaretype\n";

            if ($ip eq "DENIED")
            { #Blacklist this mac to preclude confusion, give best shot at things working
                print $omshell "set statements = \"deny booting;\"\n";
            }
            else
            {
                if ($ip and not ipIsDynamic($ip)) {
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
    	    unless ($::XCATSITEVALS{externaldhcpservers}) { 
	            unless (grep /#definition for host $node aka host $hostname/, @dhcpconf)
	            {
	                push @dhcpconf,
	                     "#definition for host $node aka host $hostname can be found in the dhcpd.leases file (typically /var/lib/dhcpd/dhcpd.leases)\n";
            	}
	    }
        }
        $count = $count + 2;
    }
}

sub addrangedetection {
    my $net = shift;
    my $tranges = $net->{dynamicrange}; #temp range, the dollar sign makes it look strange
    my $trange;
    my $begin;
    my $end;
    my $myip;
    $myip = xCAT::NetworkUtils->my_ip_facing($net->{net});
    
    # convert <xcatmaster> to nameserver IP
    if ($net->{nameservers} eq '<xcatmaster>')
    {
        $netcfgs{$net->{net}}->{nameservers} = $myip;
    }
    else
    {
        $netcfgs{$net->{net}}->{nameservers} = $net->{nameservers};
    }
    $netcfgs{$net->{net}}->{ddnsdomain} = $net->{ddnsdomain};
	$netcfgs{$net->{net}}->{domain} = $net->{domain};

    unless ($netcfgs{$net->{net}}->{nameservers}) {
        # convert <xcatmaster> to nameserver IP
        if ($::XCATSITEVALS{nameservers} eq '<xcatmaster>')
        {
            $netcfgs{$net->{net}}->{nameservers} = $myip;
        }
        else
        {
            $netcfgs{$net->{net}}->{nameservers} = $::XCATSITEVALS{nameservers};
        }
    }
    foreach $trange (split /;/,$tranges) {
        if ($trange =~ /[ ,-]/) { #a range of one number to another..
           $trange =~ s/[,-]/ /g;
           $netcfgs{$net->{net}}->{range}=$trange; 
           ($begin,$end) = split / /,$trange;
           $dynamicranges{$trange}=[getipaddr($begin,GetNumber=>1),getipaddr($end,GetNumber=>1)];
        } elsif ($trange =~ /\//) { #a CIDR style specification for a range that could be described in subnet rules
            #we are going to assume that this is a subset of the network (it really ought to be) and therefore all zeroes or all ones is good to include
            my $prefix;
            my $suffix;
            ($prefix,$suffix) = split /\//,$trange;
            my $numbits;
            if ($prefix =~ /:/) { #ipv6
                $netcfgs{$net->{net}}->{range}=$trange; #we can put in dhcpv6 ranges verbatim as CIDR
                $numbits=128;
            } else {
                $numbits=32;
            }
            my $number = getipaddr($prefix,GetNumber=>1);
            my $highmask=Math::BigInt->new("0b".("1"x$suffix).("0"x($numbits-$suffix)));
            my $lowmask=Math::BigInt->new("0b".("1"x($numbits-$suffix)));
            $number &= $highmask; #remove any errant high bits beyond the mask.
            $begin = $number->copy();
            $number |= $lowmask; #get the highest number in the range, 
            $end=$number->copy();
            $dynamicranges{$trange}=[$begin,$end];
            if ($prefix !~ /:/) { #ipv4, must convert CIDR subset to range
                my $lowip = inet_ntoa(pack("N*",$begin));
                my $highip = inet_ntoa(pack("N*",$end));
                $netcfgs{$net->{net}}->{range} = "$lowip $highip";
    
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
            if (xCAT::NetworkUtils::isInSameSubnet( $ip, $1, $2, 1))
            {
                $isSubnetFound = 1;
                $netmask = $2;
                last;
            }
        }
    }

# Format the netmask from AIX format (24) to Linux format (255.255.255.0)
    my $netmask_linux = xCAT::NetworkUtils::formatNetmask( $netmask,1,0);

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

############################################################
# check_options will process the options for makedhcp and 
# give a usage error for any invalid options 
############################################################
sub check_options
{
    my $req = shift;
    my $opt = shift;
    my $callback = shift;
    my $rc       = 0;
    
    # Exit if the packet has been preprocessed
    # Comment this line to make sure check_options can be processed on service node.
    if ($req->{_xcatpreprocessed}->[0] == 1) { return 0; }

    # display the usage if -h
    if ($opt->{h})
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("I", $rsp, $callback, 0);
        return 0;
    }
    # if not help and not -n,  dhcpd needs to be running
    if (!($opt->{h})&& (!($opt->{n}))) {
     if (xCAT::Utils->isLinux()) {
       #my $DHCPSERVER="dhcpd";
       #if( -e "/etc/init.d/isc-dhcp-server" ){
       #       $DHCPSERVER="isc-dhcp-server";
       #} 

       #my @output = xCAT::Utils->runcmd("service $DHCPSERVER status", -1);
       #if ($::RUNCMD_RC != 0)  { # not running
       my $ret=0;
       $ret=xCAT::Utils->checkservicestatus("dhcp");
       if($ret!=0)
       {
          my $rsp = {};
          $rsp->{data}->[0] = "dhcp server is not running.  please start the dhcp server.";
          xCAT::MsgUtils->message("E", $rsp, $callback, 1);
          return 1;
       }
      } else {   # AIX
          my @output = xCAT::Utils->runcmd("lssrc -s dhcpsd ", -1);
          if ($::RUNCMD_RC != 0)  { # not running
             my $rsp = {};
             $rsp->{data}->[0] = "dhcpsd is not running. Run startsrc -s dhcpsd  and rerun your command.";
             xCAT::MsgUtils->message("E", $rsp, $callback, 1);
             return 1;
          } else {  # check the status
              # the return output varies, sometime status is the third sometimes the 4th col 
              if (grep /inoperative/, @output) 
              {
                 my $rsp = {};
                 $rsp->{data}->[0] = "dhcpsd is not running. Run startsrc -s dhcpsd and rerun your command.";
                 xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                 return 1;

              }
          }
       }
    }
     

    # check to see if -q is listed with any other options which is not allowed
    if ($opt->{q} and ($opt->{a} || $opt->{d} || $opt->{n} || $opt->{r} || $opt->{l} || $statements)) {
        my $rsp = {};
        $rsp->{data}->[0] = "The -q option cannot be used with other options.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
     }

    # check to see if -n is listed with any other options which is not allowed
    if ($opt->{n} and ($opt->{a} || $opt->{d} || $opt->{q} || $opt->{r} || $opt->{l} || $statements)) {
        my $rsp = {};
        $rsp->{data}->[0] = "The -n option cannot be used with other options.";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
     }


    unless (($req->{arg} and (@{$req->{arg}}>0)) or $req->{node})
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("I", $rsp, $callback, 1);
        return;
    }

    return 0;
}

############################################################
# preprocess_request will perform syntax checking and do basic precess checking
############################################################
sub preprocess_request
{
    my $req = shift;
    my $callback = shift;
    my $rc       = 0;
   

    Getopt::Long::Configure("bundling");
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("no_pass_through");

    # Exit if the packet has been preprocessed
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    # Save the arguements in ARGV for GetOptions
    if ($req && $req->{arg}) { @ARGV = @{$req->{arg}}; }
    else { @ARGV = (); }

    my %opt;
    # Parse the options for makedhcp
    if (!GetOptions(
                     'h|help'    => \$opt{h},
                     'a'  => \$opt{a},
                     'd'  => \$opt{d},
                     'l|localonly'  => \$localonly,
                     'n'  => \$opt{n},
                     'r'  => \$opt{r},
                     's=s'  => \$statements,  # $statements is declared globally
                     'q'  => \$opt{q}
                   ))
    {
        # If the arguements do not pass GetOptions then issue error message and return
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
    }

    # check the syntax
    $rc = check_options($req, \%opt,$callback);
    if ( $rc ) {
        return [];
    }
    
    my $snonly=0;
    my @entries =  xCAT::TableUtils->get_site_attribute("disjointdhcps");
    my $t_entry = $entries[0];
    if (defined($t_entry)) {
	$snonly=$t_entry;
    }
    my @requests=();
    my $hasHierarchy=0;

    my @nodes=();
    # if the new option is not specified
    if (!$opt{n}) {
	# save the node names specified    
	if ($req->{node}) {
	    @nodes=@{$req->{node}};
	}
	# if option all 
        elsif($opt{a}) {
	    # if option delete - Delete all node entries, that were added by xCAT, from the DHCP server configuration.
            if ($opt{d})
	    {
			my $nodelist = xCAT::Table->new('nodelist');
			my @entries  = ($nodelist->getAllNodeAttribs([qw(node)]));
			foreach (@entries)
			{
		    	push @nodes, $_->{node};
			}
	    }
	    # Delete not specified so only add - Define all nodes to the DHCP server
	    else
	    {
			my $mactab  = xCAT::Table->new('mac');
			my @entries=();
			if ($mactab) {
		    	@entries = ($mactab->getAllNodeAttribs([qw(mac)]));
			}
			foreach (@entries)
			{
		    	push @nodes, $_->{node};
			}
	    }	    
	} # end - if -a

	# don't put compute node entries in for AIX nodes
	# this is handled by NIM - duplicate entires will cause
	# an error
	if ($^O eq 'aix') {
		my @tmplist;
		my $Imsg;
		foreach my $n (@nodes)
		{
			# get the nodetype for each node
            my $ntable = xCAT::Table->new('nodetype');
            if ($ntable) {
                my $mytype = $ntable->getNodeAttribs($n,['nodetype']);
			    if ($mytype->{nodetype} =~ /osi/) {
				$Imsg++;
			    }
			    # if its aix and not "osi" then add it to the list of nodes
			    unless ($mytype->{nodetype} =~ /osi/) {
				    push @tmplist, $n;
			    }
            }
		}
		# replace nodes with the tmplist of nodes that are not osi nodetype
		@nodes = @tmplist;

		# if any nodes were found with a ndoetype of osi - issue message that they are handled by NIM
		if ($Imsg) {
			my $rsp;
			push @{$rsp->{data}}, "AIX nodes with a nodetype of \'osi\' will not be added to the dhcp configuration file.  This is handled by NIM.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		}
	}
	}

    # If service node and not -n option
    if (($snonly == 1) && (!$opt{n})) {
	# if a list of nodes are specified
        if (@nodes > 0) {
	    # get the hash of service nodes
	    my $sn_hash =xCAT::ServiceNodeUtils->getSNformattedhash(\@nodes,"xcat","MN"); 
	    # if processing only on the local host
	    if ($localonly) {
		#check if this node is the service node for any input node
		my @hostinfo=xCAT::NetworkUtils->determinehostname();
		my %iphash=();
		# flag the hostnames in iphash
		foreach(@hostinfo) {$iphash{$_}=1;}
		# compare the service node hash with the iphash - a match adds this service node 
		foreach(keys %$sn_hash) {
		    if (exists($iphash{$_})) {
			my $reqcopy = {%$req};
			$reqcopy->{'node'}=$sn_hash->{$_};
			$reqcopy->{'_xcatdest'} = $_;
			$reqcopy->{_xcatpreprocessed}->[0] = 1;
			push @requests, $reqcopy;
		    }
		}
	    } else {
		# check to see if dhcp is running on service nodes
		my @sn = xCAT::ServiceNodeUtils->getSNList('dhcpserver');
		if (@sn > 0) { $hasHierarchy=1;}
		# create a request for each service node
		foreach(keys %$sn_hash) {
		    my $reqcopy = {%$req};
		    $reqcopy->{'node'}=$sn_hash->{$_};
		    $reqcopy->{'_xcatdest'} = $_;
		    $reqcopy->{_xcatpreprocessed}->[0] = 1;
		    push @requests, $reqcopy;
		}
	    }
	}   # list of nodes specified
    # if new specified or there are nodes
    } # end if service node only and NOT -n option
    # if -n option or nodes were specified
    elsif (@nodes > 0 or $opt{n}) { #send the request to every dhservers
        $req->{'node'}=\@nodes;
       	@requests = ({%$req});    #Start with a straight copy to reflect local instance
	# if not localonly - get list of service nodes and create requests
	unless ($localonly) {
	    my @sn = xCAT::ServiceNodeUtils->getSNList('dhcpserver');
	    if (@sn > 0) { $hasHierarchy=1; }

	    foreach my $s (@sn)
	    {
	        if (scalar @nodes == 1 and $nodes[0] eq $s) { next; }
	        my $reqcopy = {%$req};
	        $reqcopy->{'_xcatdest'} = $s;
	        $reqcopy->{_xcatpreprocessed}->[0] = 1;
	        push @requests, $reqcopy;
	    }
	}
    }

    if ( $hasHierarchy)
    {  
        #hierarchy detected, enforce more rigorous sanity
	my $ntab = xCAT::Table->new('networks');
	if ($ntab)
	{
	    foreach (@{$ntab->getAllEntries()})
	    {
		# if dynamicrange specified but dhcpserver was not - issue error message
		if ($_->{dynamicrange} and not $_->{dhcpserver})
		{
		    $callback->({error=>["Hierarchy requested, therefore networks.dhcpserver must be set for net=".$_->{net}.""],errorcode=>[1]});
		    return [];
		}
	    }
	}
    }
    #print Dumper(@requests);
    return \@requests;

}
 
#############################################################################
# process_request will perform syntax checking and do basic process checkingi
# and call other functions to complete the request to add or delete entries
#############################################################################
sub process_request
{
    my $req = shift;
    $callback = shift;
    my $oldmask = umask 0077;
    $restartdhcp=0;
    my $rsp;
    #print Dumper($req);

    Getopt::Long::Configure("bundling");
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("no_pass_through");

    # Save the arguements in ARGV for GetOptions
    if ($req && $req->{arg}) { @ARGV = @{$req->{arg}}; }
    else { @ARGV = (); }

    my %opt;

    # Parse the options for makedhcp
    if (!GetOptions(
                     'h|help'    => \$opt{h},
                     'a'  => \$opt{a},
                     'd'  => \$opt{d},
                     'l|localonly'  => \$localonly,
                     'n'  => \$opt{n},
                     'r'  => \$opt{r},
                     's=s'  => \$statements,  # $statements is declared globally
                     'q'  => \$opt{q}
                   ))
    {
        # If the arguements do not pass GetOptions then issue error message and return
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return 1;
     }


    # Check options again in case we are called from plugin and options have not been processed
    my $rc       = 0;
    $rc = check_options($req, \%opt,$callback);

    if ( $rc ) {
        return [];
    }


    # if option is query then call listnode for each node and return 
    if ($opt{q})
    {
	# call listnode for each node requested
        foreach my $node ( @{$req->{node}} ) {
                listnode($node,$callback);
         }
        return;
    }

    # if current node is a servicenode, make sure that it is also a dhcpserver
    my $isok=1;
    if (xCAT::Utils->isServiceNode()) {
        $isok=0;
        my @hostinfo=xCAT::NetworkUtils->determinehostname();
        my %iphash=();
        foreach(@hostinfo) {$iphash{$_}=1;}
        my @sn = xCAT::ServiceNodeUtils->getSNList('dhcpserver');
        foreach my $s (@sn) {
            if (exists($iphash{$s})) {
                $isok=1;
            }
        }
    }
    
    if($isok == 0) { #do nothing if it is a service node, but not dhcpserver
	print "Do nothing\n";
	return;  
    }

    my $servicenodetab = xCAT::Table->new('servicenode');
    my @nodeinfo   = xCAT::NetworkUtils->determinehostname;
    my $nodename   = pop @nodeinfo;                    # get hostname
    my $dhcpinterfaces = $servicenodetab->getNodeAttribs($nodename, ['dhcpinterfaces']);

    my %activenics;
    my $querynics = 1;

    if ( xCAT::Utils->isServiceNode() and $dhcpinterfaces and $dhcpinterfaces->{dhcpinterfaces} ) {
        my @dhcpifs = split ',', $dhcpinterfaces->{dhcpinterfaces};
        foreach my $nic ( @dhcpifs ) {
             $activenics{$nic} = 1;
             $querynics = 0;
        }
    }
    else
    {
        my @entries =  xCAT::TableUtils->get_site_attribute("dhcpinterfaces");
        my $t_entry = $entries[0];
        unless ( defined($t_entry) )
        {    #LEGACY: singular keyname for old style site value
            @entries =  xCAT::TableUtils->get_site_attribute("dhcpinterface");
            $t_entry = $entries[0];
        }
        if ( defined($t_entry) )
        #syntax should be like host|ifname1,ifname2;host2|ifname3,ifname2 etc or simply ifname,ifname2
        #depending on complexity of network wished to be described
        {
           my $dhcpinterfaces = $t_entry;
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
                    unless (xCAT::NetworkUtils->thishostisnot($host)) {
                        $foundself=1;
                        last;
                    }
                 }
                 if (!defined($savehost)) { # host not defined in db,
                                 # probably management node
                    unless (xCAT::NetworkUtils->thishostisnot($ngroup)) {
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
        @entries =  xCAT::TableUtils->get_site_attribute("nameservers");
        $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $sitenameservers = $t_entry;
        }
        @entries =  xCAT::TableUtils->get_site_attribute("ntpservers");
        $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $sitentpservers = $t_entry;
        }
        @entries =  xCAT::TableUtils->get_site_attribute("logservers");
        $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $sitelogservers = $t_entry;
        }
        @entries =  xCAT::TableUtils->get_site_attribute("domain");
        $t_entry = $entries[0];

        unless ( defined($t_entry) )
        {
		# this may not be an error
        #    $callback->(
        #         {error => ["No domain defined in site tabe"], errorcode => [1]}
        #         );
        #    return;
        } else {
			$site_domain = $t_entry;
		}
    }

    @dhcpconf = ();
    @dhcp6conf = ();
    
    my $dhcplockfd;
    open($dhcplockfd,">","/tmp/xcat/dhcplock");
    flock($dhcplockfd,LOCK_EX);
    if ($::XCATSITEVALS{externaldhcpservers}) { 
        # do nothing if remote dhcpservers at this point
    } elsif ($opt{n}) {
        if (-e $dhcpconffile) {
            if ($^O eq 'aix') {
                # save NIM aix entries - to be restored later
                my $aixconf;
                open($aixconf, $dhcpconffile); 
                if ($aixconf) {
                    my $save=0;
                    while (<$aixconf>) {
                        if ($save) {	
                            push @aixcfg, $_;
                        }

                        if ($_ =~ /#Network configuration end\n/) {
                            $save++;
                        }
                    }
                    close($aixconf);
                }
                $restartdhcp=1;  
                @dhcpconf = ();
            }

            my $rsp;
            push @{$rsp->{data}}, "Renamed existing dhcp configuration file to  $dhcpconffile.xcatbak\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);

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
        if ($dhcp6conffile and -e $dhcp6conffile) {
            open($rconf, $dhcp6conffile);
            while (<$rconf>) { push @dhcp6conf, $_; }
            close($rconf);
        }
        unless ($dhcp6conf[0] =~ /^#xCAT/)
        {    #Discard file if not xCAT originated
            $restartdhcp6=1;
            @dhcp6conf = ();
        }
    }
    my $nettab = xCAT::Table->new("networks");
    my @vnets = $nettab->getAllAttribs('net','mgtifname','mask','dynamicrange','nameservers','ddnsdomain', 'domain');

    # get a list of all domains listed in xCAT network defs
    #       - include the site domain - if any
    my $nettab = xCAT::Table->new("networks");
    my @doms = $nettab->getAllAttribs('domain');
    foreach(@doms){
        if ($_->{domain}) {
            push (@alldomains, $_->{domain});
        }
    }
    $nettab->close;

    # add the site domain
    if ($site_domain) {
        if (!grep(/^$site_domain$/, @alldomains)) {
            push (@alldomains, $site_domain);
        }
    }

    foreach (@vnets) {
        if ($_->{net} =~ /:/) { #IPv6 detected
            $usingipv6=1;
        }
        addrangedetection($_); #add to hash for remembering whether a node has a static address or just happens to live dynamically
    }
    if ($^O eq 'aix')
    {
        @nrn = xCAT::NetworkUtils::get_subnet_aix();
    }
    else
    {
        my @nsrnoutput = split /\n/,`/bin/netstat -rn`;
        splice @nsrnoutput, 0, 2;
        foreach (@nsrnoutput) { #scan netstat
            my @parts = split  /\s+/;
            push @nrn,$parts[0].":".$parts[7].":".$parts[2].":".$parts[3];
        }
        my @ip6routes = `ip -6 route`;
        foreach (@ip6routes) {
            #TODO: filter out multicast?  Don't know if multicast groups *can* appear in ip -6 route...
            if (/^default/ or /^fe80::\/64/ or /^unreachable/ or /^[^ ]+ via/) { #ignore link-local, junk, and routed networks
                next;
            }
            my @parts = split /\s+/;
            push @nrn6,{net=>$parts[0],iface=>$parts[2]};
        }
    }

    foreach(@vnets){
        #TODO: v6 relayed networks?
        my $n = $_->{net};
        my $if = $_->{mgtifname};
        my $nm = $_->{mask};
        if ($if =~ /!remote!/ and $n !~ /:/) { #only take in networks with special interface, but only v4 for now
            push @nrn, "$n:$if:$nm";
        }
    }
    if ($querynics)
    {   
        # Use netstat to determine activenics only when no site ent.
        # TODO: IPv6 auto-detect, or just really really insist people define dhcpinterfaces or suffer doom?
        foreach (@nrn)
        {
            my @ent = split /:/;
            my $firstoctet = $ent[0];
            $firstoctet =~ s/^(\d+)\..*/$1/;
            if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239) or $ent[0] eq "127.0.0.0" or $ent[0] eq '127')
            {
                next;
            }
            my $netif = $ent[1];
            if ($netif =~ /!remote!\S+/) {
                $netif =~ s/!remote!\s*(.*)$/$1/;
            }
            # Bridge nics
            if ((-f "/usr/sbin/brctl") || (-f "/sbin/brctl"))
            {
                #system "brctl showmacs $ent[1] 2>&1 1>/dev/null";
                system "brctl showmacs $netif 2>&1 1>/dev/null";
                if ($? == 0)
                {
                    #$activenics{$ent[1]} = 1;
                    $activenics{$netif} = 1;
                    next;
                }
            }
            #if ($ent[1] =~ m/(remote|ipoib|ib|vlan|bond|eth|myri|man|wlan|en\S*\d+|em\S*\d+)/)
            if ($netif =~ m/(remote|ipoib|ib|vlan|bond|eth|myri|man|wlan|en\S*\d+|em\S*\d+)/)
            {    #Mask out many types of interfaces, like xCAT 1.x
                #$activenics{$ent[1]} = 1;
                $activenics{$netif} = 1;
            }
        }
    }
    
    if ( $^O ne 'aix')
    {
        my $os = xCAT::Utils->osver();
        #add the active nics to /etc/sysconfig/dhcpd or /etc/default/dhcp3-server(ubuntu)
        my $dhcpver;
        my %missingfiles = ( "dhcpd"=>1, "dhcpd6"=>1, "dhcp3-server"=>1 );
        foreach $dhcpver ("dhcpd", "dhcpd6", "dhcp3-server", "isc-dhcp-server") {

            # if ipv6 is not present, no need to look at dhcpd6 files
            if (!$usingipv6 and $dhcpver eq "dhcpd6") {
                delete($missingfiles{"dhcpd6"});
                next;
            }

            # check the possible system config paths for the various Linux O/S
            my $syspath;
            foreach $syspath ("/etc/sysconfig", "/etc/default") {

                my $generatedpath = "$syspath/$dhcpver";
                my $dhcpd_key = "DHCPDARGS";

                if ($os =~ /sles/i) {
                    $dhcpd_key = "DHCPD_INTERFACE";
                    if ($usingipv6 and $dhcpver eq "dhcpd6") {
                        # For SLES, the dhcpd6 "dhcpver" is going to modify the dhcpd conf file with key=DHCPD6_INTERFACE
                        $dhcpd_key = "DHCPD6_INTERFACE";
                        $generatedpath = "$syspath/dhcpd";
                    }
                }

                if ($generatedpath and -e "$generatedpath") {
                    # remove the file from the hash because it will be processed
                    if ($dhcpver eq "dhcpd") {
                        # If dhcpd is found, then not necessary to find dhcp3-server
                        delete($missingfiles{"dhcp3-server"});
                    }

                    # UBUNTU/DEBIAN specific
                    if ($dhcpver eq "isc-dhcp-server") {
                        # UBUNTU/DEBIAN configuration ipv6 & ipv4 uses the isc-dhcp-server
                        # remove all other from the missingfiles hash
                        delete($missingfiles{"dhcpd"});
                        delete($missingfiles{"dhcpd6"});
                        delete($missingfiles{"dhcp3-server"});

                        $dhcpd_key = "INTERFACES";
                    }
                    delete($missingfiles{$dhcpver});

                    open DHCPD_FD, "$generatedpath";
                    my $syscfg_dhcpd = "";
                    my $found = 0;

                    my $ifarg = "$dhcpd_key=\"";
                    foreach (keys %activenics) {
                        if (/!remote!/) { next; }
                        $ifarg .= " $_";
                    }
                    $ifarg =~ s/\=\" /\=\"/;
                    $ifarg .= "\"\n";

                    while (<DHCPD_FD>) {
                        if ($_ =~ m/^$dhcpd_key/) {
                            $found = 1;
                            $syscfg_dhcpd .= $ifarg;
                        } else {
                            $syscfg_dhcpd .= $_;
                        }
                    }

                    if ( $found eq 0 ) {
                        $syscfg_dhcpd .= $ifarg;
                    }
                    close DHCPD_FD;

                    # write out the new file with the interfaces defined
                    open DBG_FD, '>', "$generatedpath";
                    print DBG_FD $syscfg_dhcpd;
                    close DBG_FD;
                }
            }
        }

        if ($usingipv6) {
            # sles had dhcpd and dhcpd6 config in the dhcp file
            if ($os =~ /sles/i) {
                if ($missingfiles{dhcpd}) {
                    $callback->({error=>["The file /etc/sysconfig/dhcpd doesn't exist, check the dhcp server"]});
                }
            } else {
                if ($missingfiles{dhcpd6}) {
                    $callback->({error=>["The file /etc/sysconfig/dhcpd6 doesn't exist, check the dhcp server"]});
                }
            }
        }
	if ($missingfiles{dhcpd}) {
            $callback->({error=>["The file /etc/sysconfig/dhcpd doesn't exist, check the dhcp server"]});
	}
    }
    
    unless ($dhcpconf[0])
    {            #populate an empty config with some starter data...
        $restartdhcp=1;
        newconfig();
    }
    if ($usingipv6 and not $dhcp6conf[0]) {
        $restartdhcp6=1;
        newconfig6();
    }
    if ( $^O ne 'aix')
    {
        foreach (keys %activenics)
        {
            addnic($_,\@dhcpconf);
            if ($usingipv6) {
                addnic($_,\@dhcp6conf);
            }
        }
    }
    #need to transfer CEC/Frame to FSPs/BPAs
    my @inodes = ();
    my @validnodes = ();
    my $pnode;
    my $cnode;
    if ($req->{node})
    {
        #@inodes = split /,/,${$req->{noderange}};
        my $typehash = xCAT::DBobjUtils->getnodetype(\@{$req->{node}});
        foreach $pnode(@{$req->{node}})
        {
            my $ntype = $$typehash{$pnode};
                if ($ntype =~ /^(cec|frame)$/)
                {
                    $cnode = xCAT::DBobjUtils->getchildren($pnode);
                    foreach (@$cnode)
                    {
                        push @validnodes, $_;
                    }
                } else
                {
                    push @validnodes, $pnode;
                }
        }
        $req->{node} = \@validnodes;
    }
	
    if ((!$req->{node}) && ($opt{a}))
    {
        if ($opt{d}) #delete all entries
        {
            $req->{node} = [];
            my $nodelist = xCAT::Table->new('nodelist');
            my @entries  = ($nodelist->getAllNodeAttribs([qw(node)]));
            my @nodeentries;
            foreach (@entries) {
                push @nodeentries, $_->{node};
            }                
            my $typehash = xCAT::DBobjUtils->getnodetype(\@nodeentries);
            foreach (@entries)
            {
                #delete the CEC and Frame node
                my $ntype = $$typehash{$_->{node}};
                unless ($ntype =~ /^(cec|frame)$/)
                {
                    push @{$req->{node}}, $_->{node};
                }
            }
        }
        else #add all entries
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

			# don't put compute node entries in for AIX nodes
			# this is handled by NIM - duplicate entires will cause
			# an error
			if ($^O eq 'aix') {
				my @tmplist;
				foreach my $n (@{$req->{node}})
				{
					# get the nodetype for each node
                    my $ntable = xCAT::Table->new('nodetype');
                    if ($ntable) {
                        my $ntype = $ntable->getNodeAttribs($n,['nodetype']);

					    # don't add if it is type "osi"
					    unless ($ntype->{nodetype} =~ /osi/) {
						push @tmplist, $n;
					    }
                    }    
				}
				@{$req->{node}} = @tmplist;
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
        my $netif = $line[1];
        if ($netif =~ /!remote!\S+/) {
            $netif =~ s/!remote!\s*(.*)$/$1/;
            if (!defined($activenics{"!remote!"})) {
                next;
            } elsif (!defined($activenics{$netif})) {
                addnic($netif,\@dhcpconf);
                $activenics{$netif} = 1; 
            }
        }
        #if ($activenics{$line[1]} and $line[3] !~ /G/)
        if ($activenics{$netif} and $line[3] !~ /G/)
        {
            addnet($line[0], $line[2]);
        }
    }
    foreach (@nrn6) { #do the ipv6 networks
        addnet6($_); #already did all the filtering before putting into nrn6
    }

    if ($req->{node})
    {
        my $ip_hash;
        foreach my $node ( @{$req->{node}} ) {
            #need to change the way of finding IP for nodes
            my $ifip = xCAT::NetworkUtils->isIpaddr($node);
            if ($ifip)
            {
                $ip_hash->{ $node} = $node;
            }
            else
            {
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
        }

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
	    if ($::XCATSITEVALS{externaldhcpservers}) {
	    	print $omshell "server $::XCATSITEVALS{externaldhcpservers}\n";
	    }
            print $omshell "connect\n";
            if ($usingipv6) {
                open($omshell6, "|/usr/bin/omshell > /dev/null");
	    	if ($::XCATSITEVALS{externaldhcpservers}) {
		    	print $omshell "server $::XCATSITEVALS{externaldhcpservers}\n";
		    }
                print $omshell6 "port 7912\n";
                print $omshell6 "key "
                    . $ent->{username} . " \""
                    . $ent->{password} . "\"\n";
                print $omshell6 "connect\n";
            }
        }
        
        my $nrtab = xCAT::Table->new('noderes');
        my $chaintab = xCAT::Table->new('chain');
        if ($chaintab) {
            $chainents = $chaintab->getNodesAttribs($req->{node},['currstate']);
        } else {
            $chainents = undef;
        }
        $nrhash = $nrtab->getNodesAttribs($req->{node}, ['tftpserver','netboot','proxydhcp']);
        my $nodetypetab;
	$nodetypetab = xCAT::Table->new('nodetype',-create=>0);
	if ($nodetypetab) {
            $nodetypeents = $nodetypetab->getNodesAttribs($req->{node},[qw(os)]);
	}
        my $iscsitab = xCAT::Table->new('iscsi',-create=>0);
        if ($iscsitab) {
            $iscsients = $iscsitab->getNodesAttribs($req->{node},[qw(server target lun iname)]);
        }
        my $mactab = xCAT::Table->new('mac');
        $machash = $mactab->getNodesAttribs($req->{node},['mac']);
        my $vpdtab = xCAT::Table->new('vpd');
        $vpdhash = $vpdtab->getNodesAttribs($req->{node},['uuid']);
        foreach (@{$req->{node}})
        {
            if ($opt{d})
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
                if  (xCAT::NetworkUtils->getipaddr($_) and not xCAT::NetworkUtils->nodeonmynet($_))
                {
                    next;
                }
                addnode $_;
                if ($usingipv6) {
                    addnode6 $_;
                }
            }
        }
        close($omshell) if ($^O ne 'aix');
        close($omshell6) if ($omshell6 and $^O ne 'aix');
        foreach my $node (@{$req->{node}})
        {
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
            my $ent = $machash->{$node}->[0]; #tab->getNodeAttribs($node, [qw(mac)]);
            unless ($ent and $ent->{mac})
            {
                $callback->(
                        {
                         warning     => ["Unable to find mac address for $node"]
                        }
                        );
                next;
            }
        }
    }
    writeout();
    if (not $::XCATSITEVALS{externaldhcpservers} and $restartdhcp) {
        if ( $^O eq 'aix')
        {
            restart_dhcpd_aix();
        }
        else {
            if ( $distro =~ /ubuntu.*/ || $distro =~ /debian.*/i)
		{
		    if (-e '/etc/dhcp/dhcpd.conf') {
			system("chmod a+r /etc/dhcp/dhcpd.conf");
			#system("/etc/init.d/isc-dhcp-server restart");
		    }
		    else {
			#ubuntu config
			system("chmod a+r /etc/dhcp3/dhcpd.conf");
			#system("/etc/init.d/dhcp3-server restart");
		    }
		}
		#else
		#{
		#    system("/etc/init.d/dhcpd restart");
		#    # should not chkconfig dhcpd on every makedhcp invoation
		#    # it is not appropriate and will cause problem for HAMN
		#    # do it in xcatconfig instead
		#    #system("chkconfig dhcpd on");
		#}
            xCAT::Utils->restartservice("dhcp");
        print "xx";
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

sub getzonesfornet {
    my $net = shift;
    my $mask = shift;
    my @zones = ();
    if ($net =~ /:/) {#ipv6, for now do the simple stuff under the assumption we won't have a mask indivisible by 4
        $net =~ s/\/(.*)//;
        my $maskbits=$1;
        if ($mask) {
            die "Not supporting having a mask like $mask on an ipv6 network like $net";
        }
        my $netnum= getipaddr($net,GetNumber=>1);
        unless ($netnum) { return (); }
        $netnum->brsft(128-$maskbits);
        my $prefix=$netnum->as_hex();
        my $nibbs=$maskbits/4;
        $prefix =~ s/^0x//;
        my $rev;
        foreach (reverse(split //,$prefix)) {
            $rev .= $_.".";
            $nibbs--;
        }
        while ($nibbs) { 
            $rev .= "0.";
            $nibbs--;
        }
        $rev.="ip6.arpa.";
        return ($rev);
    }
    #return all in-addr reverse zones for a given mask and net
    #for class a,b,c, the answer is easy
    #for classless, identify the partial byte, do $netbyte | (0xff&~$maskbyte) to get the highest value
    #return sequence from $net to value calculated above
    #since old bind.pm only went as far as class c, we will carry that over for now (more people with smaller than class c complained
    #and none hit the theoretical conflict.  FYI, the 'official' method in RFC 2317 seems cumbersome, but maybe one day it makes sense
    #since this is dhcpv4 for now, we'll use the inet_aton, ntop functions to generate the answers (dhcpv6 omapi would be nice...)
    my $netn = inet_aton($net);
    my $maskn = inet_aton($mask);
    unless ($netn and $mask) { return (); }
    my $netnum = unpack('N',$netn);
    my $masknum = unpack('N',$maskn);
    if ($masknum >= 0xffffff00) { #treat all netmasks higher than 255.255.255.0 as class C
        $netnum = $netnum & 0xffffff00;
        $netn = pack('N',$netnum);
        $net = inet_ntoa($netn);
        $net =~ s/\.[^\.]*$//;
        return (join('.',reverse(split('\.',$net))).'.IN-ADDR.ARPA.');
    } elsif ($masknum > 0xffff0000) { #class b (/16) to /23
        my $tempnumber = ($netnum >> 8);
        $masknum = $masknum >> 8;
        my $highnet = $tempnumber | (0xffffff & ~$masknum);
        foreach ($tempnumber..$highnet) {
            $netnum = $_ << 8;
            $net = inet_ntoa(pack('N',$netnum));
            $net =~ s/\.[^\.]*$//;
            push @zones,join('.',reverse(split('\.',$net))).'.IN-ADDR.ARPA.';
        }
        return @zones;
    } elsif ($masknum > 0xff000000) { #class a (/8) to /15, could have made it more flexible, for for only two cases, not worth in
        my $tempnumber = ($netnum >> 16); #the last two bytes are insignificant, shift them off to make math easier
        $masknum = $masknum >> 16;
        my $highnet = $tempnumber | (0xffff & ~$masknum);
        foreach ($tempnumber..$highnet) {
            $netnum = $_ << 16; #convert back to the real network value
            $net = inet_ntoa(pack('N',$netnum));
            $net =~ s/\.[^\.]*$//;
            $net =~ s/\.[^\.]*$//;
            push @zones,join('.',reverse(split('\.',$net))).'.IN-ADDR.ARPA.';
        }
        return @zones;
    } else { #class a (theoretically larger, but those shouldn't exist)
        my $tempnumber = ($netnum >> 24); #the last two bytes are insignificant, shift them off to make math easier
        $masknum = $masknum >> 24;
        my $highnet = $tempnumber | (0xff & ~$masknum);
        foreach ($tempnumber..$highnet) {
            $netnum = $_ << 24; #convert back to the real network value
            $net = inet_ntoa(pack('N',$netnum));
            $net =~ s/\.[^\.]*$//;
            $net =~ s/\.[^\.]*$//;
            $net =~ s/\.[^\.]*$//;
            push @zones,join('.',reverse(split('\.',$net))).'.IN-ADDR.ARPA.';
        }
        return @zones;
    }
}

sub putmyselffirst {
    my $srvlist = shift;
            if ($srvlist =~ /,/) { #TODO: only reshuffle when requested, or allow opt out of reshuffle?
                my @dnsrvs = split /,/,$srvlist;
                my @reordered;
                foreach (@dnsrvs) {
                    if (xCAT::NetworkUtils->thishostisnot($_)) {
                        push @reordered,$_;
                    } else {
                        unshift @reordered,$_;
                    }
                }
                $srvlist = join(', ',@reordered);
            }
            return $srvlist;
}
sub addnet6
{
    if ($::XCATSITEVALS{externaldhcpservers}) { return; }
    my $netentry = shift;
    my $net = $netentry->{net};
    my $iface = $netentry->{iface};
    my $idx = 0;
    if (grep /\} # $net subnet_end/,@dhcp6conf) { #need to add to dhcp6conf
        return;
    } else { #need to add to dhcp6conf
	$restartdhcp6=1;
        while ($idx <= $#dhcp6conf)
        {
            if ($dhcp6conf[$idx] =~ /\} # $iface nic_end/) {
                last;
            }
            $idx++;
        }
        unless ($dhcp6conf[$idx] =~ /\} # $iface nic_end\n/) {
                $callback->(
	            {
                        error =>
                            ["Could not add the subnet $net for interface $iface into $dhcpconffile.\nPlease verify the xCAT database matches networks defined on this system."],
                            errorcode => [1]
                    }
                );
                return 1;
        }

    }

    my $dhcplease = 43200;
    if (defined $::XCATSITEVALS{'dhcplease'} && $::XCATSITEVALS{'dhcplease'} ne "") {
         $dhcplease = $::XCATSITEVALS{'dhcplease'};
    }

    my @netent = (
                   "  subnet6 $net {\n",
                   "    authoritative;\n",
                   "    max-lease-time $dhcplease;\n",
                   "    min-lease-time $dhcplease;\n",
                   "    default-lease-time $dhcplease;\n",
                   );
    #for now, just do address allocatios (phase 1)
    #phase 2 (by 2.6 presumably) will include the various things like DNS server and other options allowed by dhcpv6
    #gateway is *not* currently allowed to be DHCP designated, router advertises its own self indpendent of dhcp.  We'll just keep it that way
    #domain search list is allowed (rfc 3646)
        #nis domain is also an alloed option (rfc 3898)
    #sntp server list (rfc 4075)
    #ntp server rfc 5908
    #fqdn rfc 4704
    #posix timezone rfc 4833/tzdb timezone
    #phase 3 will include whatever is required to do Netboot6.  That might be in the october timeframe for lack of implementations to test
    #boot url/param (rfc 59070)
    my $netdomain = $netcfgs{$net}->{domain};
    unless ($netdomain) { $netdomain = $site_domain; }
    push @netent, "    option domain-name \"".$netdomain."\";\n";

	#  add domain-search if not sles10 or rh5
    my $osv = xCAT::Utils->osver();
    unless ( ($osv =~ /^sle[sc]10/) || ($osv =~ /^rh.*5$/) ) {
	    # We want something like "option domain-search "foo.com", "bar.com";"
	    my $domainstring = qq~"$netcfgs{$net}->{domain}"~;
	    foreach my $dom (@alldomains) {
		    chomp $dom;
		    if ($dom ne $netcfgs{$net}->{domain}){
			    $domainstring .= qq~, "$dom"~;
		    }
	    }

	    if ($netcfgs{$net}->{domain}) {
		    push @netent, "    option domain-search  $domainstring;\n";
	    }
    }

    my $nameservers = $netcfgs{$net}->{nameservers};
    if ($nameservers and $nameservers =~ /:/) {
        push @netent,"    nameservers ".$netcfgs{$net}->{nameservers}.";\n";
    }
    my $ddnserver = $nameservers;
    $ddnserver =~ s/,.*//;
    my $ddnsdomain;
    if ($netcfgs{$net}->{ddnsdomain}) {
        $ddnsdomain = $netcfgs{$net}->{ddnsdomain};
    }
    if ($::XCATSITEVALS{dnshandler} =~ /ddns/) {
        if ($ddnsdomain) {
            push @netent, "    ddns-domainname \"".$ddnsdomain."\";\n";
            push @netent, "    zone $ddnsdomain. {\n";
        } else {
			push @netent, "    zone $netdomain. {\n";
        }
    push @netent, "       primary $ddnserver; key xcat_key; \n";
    push @netent, "    }\n";
    foreach (getzonesfornet($net)) {
       push @netent, "    zone $_ {\n";
       push @netent, "       primary $ddnserver; key xcat_key; \n";
       push @netent, "    }\n";
    }
    }
    if ($netcfgs{$net}->{range}) {
        push @netent,"    range6 ".$netcfgs{$net}->{range}.";\n";
    } else {
        $callback->({warning => ["No dynamic range specified for $net. Hosts with no static address will receive no addresses on this subnet."]});
    }
    push @netent, "  } # $net subnet_end\n";
    splice(@dhcp6conf, $idx, 0, @netent);
}
sub addnet
{
    if ($::XCATSITEVALS{externaldhcpservers}) { return; }
    my $net  = shift;
    my $mask = shift;
    my $nic;
	my $domain;
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
                if ($nic =~ /!remote!\S+/) {
                    $nic =~ s/!remote!\s*(.*)$/$1/;
                }
                # The first nic that matches the network,
                # what will happen if there are more than one nics in the same subnet,
                # and we want to use the second nic as the dhcp interfaces?
                # this is a TODO
                last;
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
                $callback->(
	            {
                        error =>
                            ["Could not add the subnet $net for interface $nic into $dhcpconffile.\nPlease verify the xCAT database matches networks defined on this system."],
                            errorcode => [1]
                    }
                );
                return 1;
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
        $myip = xCAT::NetworkUtils->my_ip_facing($net);
        if ($nettab)
        {
            my $mask_formated = $mask;
            if ( $^O eq 'aix')
            {
                my $mask_shift = 32 - $mask;
                $mask_formated = inet_ntoa(pack("N", 2**$mask - 1 << $mask_shift));
             #  $mask_formated = inet_ntoa(pack("N", 2**$mask - 1 << (32 - $mask)));
            }

            my ($ent) =
              $nettab->getAttribs({net => $net, mask => $mask_formated},
                    qw(tftpserver nameservers ntpservers logservers gateway dynamicrange dhcpserver domain));
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
			if ($ent and $ent->{domain}) {
				$domain = $ent->{domain};
			} elsif ($site_domain)  {
				$domain = $site_domain;
			} else {
				$callback->(
					{
					warning => [
						"No $net specific entry for domain, and no domain defined in site table."
					]
					});
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

            # convert <xcatmaster> to nameserver IP
            $nameservers =~ s/<xcatmaster>/$myip/g;

            if (!$ntpservers || ($ntpservers eq '<xcatmaster>'))
            {
                $ntpservers = $myip;
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

                if ($gateway eq '<xcatmaster>')
                {
                    if(xCAT::NetworkUtils->ip_forwarding_enabled())
                    {
                        $gateway = $myip;
                    }
                    else
                    {
                        $gateway = '';
                    }
                }
            }
            if ($ent and $ent->{dynamicrange})
            {
                unless ($ent->{dhcpserver}
                        and xCAT::NetworkUtils->thishostisnot($ent->{dhcpserver}))
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
        my $dhcplease = 43200;
        if (defined $::XCATSITEVALS{'dhcplease'} && $::XCATSITEVALS{'dhcplease'} ne "") {
             $dhcplease = $::XCATSITEVALS{'dhcplease'};
        }
        @netent = (
                   "  subnet $net netmask $mask {\n",
                   "    authoritative;\n",
                   "    max-lease-time $dhcplease;\n",
                   "    min-lease-time $dhcplease;\n",
                   "    default-lease-time $dhcplease;\n"
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
        }
        if ($nameservers)
        {
            push @netent, "    option domain-name \"$domain\";\n";
            push @netent, "    option domain-name-servers  $nameservers;\n";
        }

        #  add domain-search if not sles10 or rh5
        my $osv = xCAT::Utils->osver();
        unless ( ($osv =~ /^sle[sc]10/) || ($osv =~ /^rh.*5$/) ) {
		    # want something like "option domain-search "foo.com", "bar.com";"
		    my $domainstring = qq~"$domain"~;
		    foreach my $dom (@alldomains) {
			    chomp $dom;
			    if ($dom ne $domain){
				    $domainstring .= qq~, "$dom"~;
			   }
		    }

		    if ($domain) {
			    push @netent, "    option domain-search  $domainstring;\n";
            }
		}

        my $ddnserver = $nameservers;
        $ddnserver =~ s/,.*//;
        my $ddnsdomain;
        if ($netcfgs{$net}->{ddnsdomain}) {
            $ddnsdomain = $netcfgs{$net}->{ddnsdomain};
        }
    if ($::XCATSITEVALS{dnshandler} =~ /ddns/) {
        if ($ddnsdomain) {
            push @netent, "    ddns-domainname \"".$ddnsdomain."\";\n";
            push @netent, "    zone $ddnsdomain. {\n";
        } else {
            push @netent, "    zone $domain. {\n";
        }
        if ($ddnserver)
        {
            push @netent, "   primary $ddnserver; key xcat_key; \n";
        }
        push @netent, " }\n";
        foreach (getzonesfornet($net,$mask)) {
            push @netent, "zone $_ {\n";
            if ($ddnserver)
            {
                push @netent, "   primary $ddnserver; key xcat_key; \n";
            }
            push @netent, " }\n";
        }
        }

        my $tmpmaskn = unpack("N", inet_aton($mask));
        my $maskbits = 32;
        while (not ($tmpmaskn & 1)) {
            $maskbits--;
            $tmpmaskn=$tmpmaskn>>1;
        }

                       # $lstatements = 'if exists gpxe.bus-id { filename = \"\"; } else if exists client-architecture { filename = \"xcat/xnba.kpxe\"; } '.$lstatements;
        push @netent, "    if option user-class-identifier = \"xNBA\" and option client-architecture = 00:00 { #x86, xCAT Network Boot Agent\n";
        push @netent, "       always-broadcast on;\n";
        push @netent, "       filename = \"http://$tftp/tftpboot/xcat/xnba/nets/".$net."_".$maskbits."\";\n";
        push @netent, "    } else if option user-class-identifier = \"xNBA\" and option client-architecture = 00:09 { #x86, xCAT Network Boot Agent\n";
        push @netent, "       filename = \"http://$tftp/tftpboot/xcat/xnba/nets/".$net."_".$maskbits.".uefi\";\n";
        push @netent, "    } else if option client-architecture = 00:00  { #x86\n";
        push @netent, "      filename \"xcat/xnba.kpxe\";\n";
        push @netent, "    } else if option vendor-class-identifier = \"Etherboot-5.4\"  { #x86\n";
        push @netent, "      filename \"xcat/xnba.kpxe\";\n";
        push @netent,
          "    } else if option client-architecture = 00:07 { #x86_64 uefi\n ";
        push @netent, "      filename \"xcat/xnba.efi\";\n";
        push @netent,
          "    } else if option client-architecture = 00:09 { #x86_64 uefi alternative id\n ";
        push @netent, "      filename \"xcat/xnba.efi\";\n";
        push @netent,
          "    } else if option client-architecture = 00:02 { #ia64\n ";
        push @netent, "      filename \"elilo.efi\";\n";
        push @netent,
          "    } else if option client-architecture = 00:0e { #OPAL-v3\n ";
        push @netent, "      option conf-file = \"http://$tftp/tftpboot/pxelinux.cfg/p/".$net."_".$maskbits."\";\n";
        push @netent,
          "    } else if substring(filename,0,1) = null { #otherwise, provide yaboot if the client isn't specific\n ";
        push @netent, "      filename \"/yaboot\";\n";
        push @netent, "    }\n";
        if ($range) { 
            foreach  my $singlerange (split /;/,$range) {
                push @netent, "    range dynamic-bootp $singlerange;\n" 
            }
        }
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
        if ($gateway eq '<xcatmaster>')
        {
            if(xCAT::NetworkUtils->ip_forwarding_enabled())
            {
                $gateway = $myip;
            }
            else
            {
                $gateway = '';
            }
        }
        if (xCAT::NetworkUtils::isInSameSubnet($gateway,$net,$mask,1))
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
    if ($::XCATSITEVALS{externaldhcpservers}) { return; }
    my $nic        = shift;
    my $conf       = shift;
    my $firstindex = 0;
    my $lastindex  = 0;
    unless (grep /} # $nic nic_end/, @$conf)
    {    #add a section if not there
        #$restartdhcp=1;
        #print "Adding NIC $nic\n";
        if ($nic eq '!remote!') {
            push @$conf, "#shared-network $nic {\n";
            push @$conf, "#\} # $nic nic_end\n";
        } else {
            push @$conf, "shared-network $nic {\n";
            push @$conf, "\} # $nic nic_end\n";
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
    if ($::XCATSITEVALS{externaldhcpservers}) { return; }

	# add the new entries to the dhcp config file
    my $targ;
    open($targ, '>', $dhcpconffile);
    my $idx;
    my $skipone;
    foreach $idx (0..$#dhcpconf)
    {
        #avoid writing out empty shared network declarations
        if ($dhcpconf[$idx] =~ /^shared-network/ and $dhcpconf[$idx+1] =~ /^} .* nic_end/) {
            $skipone=1;
            next;
        } elsif ($skipone) {
            $skipone=0;
            next;
        }
        print $targ $dhcpconf[$idx];
    }

	if ($^O eq 'aix')
	{
		# add back any NIM entries that were saved earlier
		if (@aixcfg) {
			foreach $idx (0..$#aixcfg)
			{
				print $targ $aixcfg[$idx];
			}
		}
	}
    close($targ);
    @dhcpconf=(); #dispose of the file contents in memory, no longer needed
    @aixcfg=();


    if (@dhcp6conf) {
    open($targ, '>', $dhcp6conffile);
    foreach $idx (0..$#dhcp6conf)
    {
        if ($dhcp6conf[$idx] =~ /^shared-network/ and $dhcp6conf[$idx+1] =~ /^} .* nic_end/) {
            $skipone=1;
            next;
        } elsif ($skipone) {
            $skipone=0;
            next;
        }
        print $targ $dhcp6conf[$idx];
    }
    close($targ);
    @dhcp6conf=();
    }
}

sub newconfig6 {
    if ($::XCATSITEVALS{externaldhcpservers}) { return; }
    #phase 1, basic working
    #phase 2, ddns too, evaluate other stuff from dhcpv4 as applicable
    push @dhcp6conf, "#xCAT generated dhcp configuration\n";
    push @dhcp6conf, "\n";
    push @dhcp6conf, "ddns-update-style interim;\n";
    push @dhcp6conf, "ignore client-updates;\n";
#    push @dhcp6conf, "update-static-leases on;\n";
    push @dhcp6conf, "omapi-port 7912;\n";        #Enable omapi...
    push @dhcp6conf, "key xcat_key {\n";
    push @dhcp6conf, "  algorithm hmac-md5;\n";
    my $passtab = xCAT::Table->new('passwd', -create => 1);
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

    push @dhcp6conf, "  secret \"" . $secret . "\";\n";
    push @dhcp6conf, "};\n";
    push @dhcp6conf, "omapi-key xcat_key;\n";
    #that is all for pristine ipv6 config
}

sub newconfig
{
    if ($::XCATSITEVALS{externaldhcpservers}) { return; }
    return newconfig_aix() if ( $^O eq 'aix');

    # This function puts a standard header in and enough to make omapi work.
    my $passtab = xCAT::Table->new('passwd', -create => 1);
    push @dhcpconf, "#xCAT generated dhcp configuration\n";
    push @dhcpconf, "\n";
    push @dhcpconf, "option conf-file code 209 = text;\n";
    push @dhcpconf, "option space isan;\n";
    push @dhcpconf, "option isan-encap-opts code 43 = encapsulate isan;\n";
    push @dhcpconf, "option isan.iqn code 203 = string;\n";
    push @dhcpconf, "option isan.root-path code 201 = string;\n";
    push @dhcpconf, "option space gpxe;\n";
    push @dhcpconf, "option gpxe-encap-opts code 175 = encapsulate gpxe;\n";
    push @dhcpconf, "option gpxe.bus-id code 177 = string;\n";
    push @dhcpconf, "option user-class-identifier code 77 = string;\n";
    push @dhcpconf, "option gpxe.no-pxedhcp code 176 = unsigned integer 8;\n";
    push @dhcpconf, "option tcode code 101 = text;\n";
	
    push @dhcpconf, "option iscsi-initiator-iqn code 203 = string;\n"; #Only via gPXE, not a standard
    push @dhcpconf, "ddns-update-style interim;\n";
    push @dhcpconf, "ignore client-updates;\n"; #Windows clients like to do all caps, very un xCAT-like
#    push @dhcpconf, "update-static-leases on;\n"; #makedns rendered optional
    push @dhcpconf,
      "option client-architecture code 93 = unsigned integer 16;\n";
    if ($::XCATSITEVALS{timezone}) {
    push @dhcpconf, "option tcode \"".$::XCATSITEVALS{timezone}."\";\n";
    }
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
