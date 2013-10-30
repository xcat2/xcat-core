package xCAT_plugin::ddns;
use strict;
use Getopt::Long;
use Net::DNS;
use File::Path;
use xCAT::Table;
use Sys::Hostname;
use xCAT::TableUtils;
use xCAT::NetworkUtils qw/getipaddr/;
use Math::BigInt;
use MIME::Base64;
use xCAT::SvrUtils;
use Socket;
use Fcntl qw/:flock/;

# This is a rewrite of DNS management using nsupdate rather than 
#	direct zone mangling

my $callback;
my $distro = xCAT::Utils->osver();

my $service="named";

# is this ubuntu ?
if ( $distro =~ /ubuntu.*/i || $distro =~ /debian.*/i ){
    $service = "bind9";	
}

sub handled_commands
{
    my @entries =  xCAT::TableUtils->get_site_attribute("dnshandler");
    my $site_entry = $entries[0];
    unless ( defined($site_entry)) {
        return {"makedns" => "ddns"};
    }

    return {"makedns" => "site:dnshandler"};
}
sub getzonesfornet {
    my $netent = shift;
    my $net = $netent->{net};
    my $mask = $netent->{mask};
    my @zones = ();
    if ($netent->{ddnsdomain}) {
        push @zones,$netent->{ddnsdomain};
    }
    if ($net =~ /:/) {#ipv6, for now do the simple stuff under the assumption we won't have a mask indivisible by 4
        $net =~ s/\/(.*)//;
        my $maskbits=$1;
        if ($maskbits%4) {
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
        push @zones,$rev;
        return @zones;
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
    } elsif ($masknum > 0xffff0000) { #(/17) to /23
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
    } elsif ($masknum > 0xff000000) { # (/9) to class b /16, could have made it more flexible, for for only two cases, not worth in
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
sub get_reverse_zones_for_entity {
    my $ctx = shift;
    my $node = shift;
    my $net;
    if (($node =~ /loopback/) || ($node =~ /localhost/))
    {
        # do not use DNS to resolve localhsot
        return;
    }

    if ($ctx->{hoststab} and $ctx->{hoststab}->{$node} and $ctx->{hoststab}->{$node}->[0]->{ip}) {
        $node = $ctx->{hoststab}->{$node}->[0]->{ip};
    }
    my @tvars=getipaddr($node,GetNumber=>1,GetAllAddresses=>1);
    my $tvar;
    my @revs;
    foreach $tvar (@tvars) {
        foreach my $net (keys %{$ctx->{nets}}) {
            if ($ctx->{nets}->{$net}->{netn} == ($tvar & $ctx->{nets}->{$net}->{mask})) {
                if ($net =~ /\./) { #IPv4/IN-ADDR.ARPA case.
                    my $maskstr = unpack("B32",pack("N",$ctx->{nets}->{$net}->{mask}));
                    my $maskcount = ($maskstr =~ tr/1//);
                    if ($maskcount >= 24)
                    {
                        $maskcount-=($maskcount%8);  #e.g. treat the 27bit netmask as 24bit
                    }
                    else
                    {
                        $maskcount+=((8-($maskcount%8))%8); #round to the next octet
                    }
                    my $newmask = 2**$maskcount -1 << (32 - $maskcount);
                    my $rev = inet_ntoa(pack("N",($tvar & $newmask)));
                    my @zone;
                    my @orig=split /\./,$rev;
                    while ($maskcount) {
                        $maskcount-=8;
                        unshift(@zone,(shift @orig));
                    }
                    $rev = join('.',@zone);
                    $rev .= '.IN-ADDR.ARPA.';
                    push @revs,$rev;
                } elsif ($net =~ /:/) {#v6/ip6.arpa case
                    $net =~ /\/(.*)/;
                    my $maskbits = $1;
                    unless ($maskbits and (($maskbits%4)==0)) {
                        die "Never expected this, $net should have had CIDR / notation... and the mask should be a factor of 4, if not, need work..."
                    }
                    my $netnum = Math::BigInt->new($ctx->{nets}->{$net}->{netn});
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
                    push @revs,$rev;
                }
            }
        }
    }
    return @revs;
}

sub process_request {
    my $request = shift;
    $callback = shift;
    my $oldmask = umask(0007);
    my $ctx = {};
    my @nodes=();
    my $hadargs=0;
    my $allnodes;
    my $zapfiles;
    my $help;
    my $deletemode=0;
    my $external=0;
    if ($request->{arg}) {
        $hadargs=1;
        @ARGV=@{$request->{arg}};

        Getopt::Long::Configure("no_pass_through");
        Getopt::Long::Configure("bundling");
        if (!GetOptions(
            'a|all' => \$allnodes,
            'n|new' => \$zapfiles,
            'd|delete' => \$deletemode,
            'e|external' => \$external,
            'h|help' => \$help,
            )) {
            #xCAT::SvrUtils::sendmsg([1,"TODO: makedns Usage message"], $callback);
            makedns_usage($callback);
            umask($oldmask);
            return;
        }
    }
    if ($::XCATSITEVALS{externaldns}) {
    	$external=1;
    }

    if ($help)
    {
        makedns_usage($callback);
        umask($oldmask);
        return;
    }

    if ($deletemode && (!$request->{node}->[0]))
    {
        makedns_usage($callback);
        umask($oldmask);
        return;
    }
    
    $ctx->{deletemode}=$deletemode;

    # check for site.domain     
    my @entries =  xCAT::TableUtils->get_site_attribute("domain");
    my $site_entry = $entries[0];
    unless ( defined($site_entry)) {
        xCAT::SvrUtils::sendmsg([1,"domain not defined in site table"], $callback);
        umask($oldmask);
        return;
    }
    $ctx->{domain} = $site_entry;

    if($external) #need to check if /etc/resolv.conf existing
    {
        my $resolv = "/etc/resolv.conf";
        my $cmd = "egrep '^nameserver|^search' $resolv";
        my $acmd = "egrep '^nameserver|^domain' $resolv";

        if (xCAT::Utils->isAIX())
        {
            $cmd = $acmd;
        }
        
        my @output=xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::SvrUtils::sendmsg([1,"You are using -e flag to update DNS records to an external DNS server, please ensure /etc/resolv.conf existing and pointed to this external DNS server."], $callback);
            umask($oldmask);
            return;
        }
   }
   
   # check for selinux disabled
    my $rc=xCAT::Utils->isSELINUX();
    if ($rc == 0)
    {
        xCAT::SvrUtils::sendmsg([0,"Warning:SELINUX is not disabled. The makedns command will not be able to generate a complete DNS setup. Disable SELINUX and run the command again."], $callback);

    }
    my @entries =  xCAT::TableUtils->get_site_attribute("nameservers");
    my $sitens = $entries[0];
    unless ( defined($site_entry)) {
        xCAT::SvrUtils::sendmsg([1,"nameservers not defined in site table"], $callback);
        umask($oldmask);
        return;
    }
     
    my $networkstab = xCAT::Table->new('networks',-create=>0);
    unless ($networkstab) { xCAT::SvrUtils::sendmsg([1,'Unable to enumerate networks, try to run makenetworks'], $callback); }

    my @networks = $networkstab->getAllAttribs('net','mask','ddnsdomain','domain','nameservers');
    # exclude the net if it is using an external dns server.
    foreach my $net (@networks)
    {
        if ($net and $net->{nameservers})
        {
            my $valid = 0;
            my $myip = xCAT::NetworkUtils->my_ip_facing($net->{net});
            foreach (split /,/, $net->{nameservers})
            {
                chomp $_;
                if (($_ eq $myip) || ($_ eq '<xcatmaster>') || ($_ eq $sitens))
                {
                    $valid += 1;
                }
            }
            unless ($valid > 0)
            {
                $net = undef;
            }
        }
    }

#    if ($request->{node}) { #we have a noderange to process
#        @nodes = @{$request->{node}};
    #} elsif ($allnodes) {
    if ($allnodes) {
        #read all nodelist specified nodes
    } else { 
	if (not $request->{node} and $deletemode) {
		#when this was permitted, it really ruined peoples' days
		xCAT::SvrUtils::sendmsg([1,"makedns -d without noderange or -a is not supported"],$callback); 
        umask($oldmask);
		return;
	}
	my @contents;
		my $domain;
	if ($request->{node}) { #leverage makehosts code to flesh out the options
		require xCAT_plugin::hosts;
                my @content1;
                my @content2;
		xCAT_plugin::hosts::add_hosts_content(nodelist=>$request->{node},callback=>$callback,hostsref=>\@content1);
		xCAT_plugin::hosts::donics(nodes=>$request->{node},callback=>$callback,hostsref=>\@content2);
                @contents = (@content1, @content2);
	} else {
	        #legacy behavior, read from /etc/hosts
	        my $hostsfile;
	        open($hostsfile,"<","/etc/hosts");
	        flock($hostsfile,LOCK_SH);
	        @contents = <$hostsfile>;
	        flock($hostsfile,LOCK_UN);
	        close($hostsfile);
	}
        my $addr;
        my $name;
        my $canonical;
        my $aliasstr;
        my @aliases;
        my $names;
		my @hosts;
		my %nodehash;

        foreach (@contents) {
            chomp; #no newline
            s/#.*//; #strip comments;
            s/^[ \t\n]*//; #remove leading whitespace
            next unless ($_); #skip empty lines
            ($addr,$names) = split /[ \t]+/,$_,2;

            if ($addr !~ /^\d+\.\d+\.\d+\.\d+$/ and $addr !~ /^[abcdef0123456789:]+$/) {
                xCAT::SvrUtils::sendmsg(":Ignoring line $_ in /etc/hosts, address seems malformed.", $callback);
                next;
            }
            unless ($names =~ /^[a-z0-9\. \t\n-]+$/i) {
                xCAT::SvrUtils::sendmsg(":Ignoring line $_ in /etc/hosts, names  $names contain invalid characters (valid characters include a through z, numbers and the '-', but not '_'", $callback);
                next;
            }

			my ($host, $ip) = xCAT::NetworkUtils->gethostnameandip($addr);
			push @hosts, $host;
			$nodehash{$addr}{names}=$names;
			$nodehash{$addr}{host}=$host;
		}

		# get the domains for each node - one call for all nodes in hosts file
		my $nd = xCAT::NetworkUtils->getNodeDomains(\@hosts);
		my %nodedomains = %$nd;

		foreach my $n (keys %nodehash) {
			$addr=$n;
			$names=$nodehash{$n}{names};
			# - need domain for this node
			my $host = $nodehash{$n}{host};
			$domain=$nodedomains{$host};
			unless ($domain =~ /^\./) { $domain = '.'.$domain; }

            ($canonical,$aliasstr)  = split /[ \t]+/,$names,2;
            if ($aliasstr) {
                @aliases= split /[ \t]+/,$aliasstr;
            } else {
                @aliases = ();
            }
            my %names = ();
            my $node = $canonical;

            xCAT::SvrUtils::sendmsg(":Handling $node in /etc/hosts.", $callback);
            
            unless ($canonical =~ /$domain/) {
                $canonical.=$domain;
            }
			# for only the sake of comparison, ensure consistant dot suffix
            unless ($canonical =~ /\.\z/) { $canonical .= '.' }
            foreach my $alias (@aliases) {
                unless ($alias =~ /$domain/) {
                    $alias .= $domain;
                }
                unless ($alias =~ /\.\z/) {
                    $alias .= '.';
                }
                if ($alias eq $canonical) {
                    next;
                }
				# remember alias for CNAM records later
                $ctx->{aliases}->{$node}->{$alias}=1;
            }

            # exclude the nodes not belong to any nets defined in networks table
            # 	because only the nets defined in networks table will be add 
			#	zones later.
            my $found = 0;
            foreach (@networks)
            {
                if(xCAT::NetworkUtils->ishostinsubnet($addr, $_->{mask}, $_->{net}))
                {
                    $found = 1;
                }
            }

            if ($found)
            {
                push @nodes,$node;
                $ctx->{nodeips}->{$node}->{$addr}=1;
            }
            else
            {
                unless ($node =~ /localhost/)
                {
                    xCAT::SvrUtils::sendmsg(":Ignoring host $node, it does not belong to any nets defined in networks table or the net it belongs to is configured to use an external nameserver.", $callback);
                }    
            }
        }
    }

    my $hoststab = xCAT::Table->new('hosts',-create=>0);
    if ($hoststab) {
        $ctx->{hoststab} = $hoststab->getNodesAttribs(\@nodes,['ip']);
    }
    $ctx->{nodes} = \@nodes;

    foreach (@networks) {
        my $maskn;
        if ($_->{mask}) { #better be IPv4, we only do CIDR for v6, use the v4/v6 agnostic just in case
            $maskn = getipaddr($_->{mask},GetNumber=>1); #pack("N",inet_aton($_->{mask}));
        } elsif ($_->{net} =~ /\/(.*)/) { #CIDR
            my $maskbits=$1;
            my $numbits;
            if ($_->{net} =~ /:/) { #v6
                $numbits=128;
            } elsif ($_->{net} =~ /\./) {
                $numbits=32;
            } else {
                umask($oldmask);
                die "Network ".$_->{net}." appears to be malformed in networks table";
            }
            $maskn = Math::BigInt->new("0b".("1"x$maskbits).("0"x($numbits-$maskbits)));
        }
        $ctx->{nets}->{$_->{net}}->{mask} = $maskn;

        my $net = $_->{net};
        $net =~ s/\/.*//;
        $ctx->{nets}->{$_->{net}}->{netn} = getipaddr($net,GetNumber=>1);
        my $currzone;
        foreach $currzone (getzonesfornet($_)) {
            $ctx->{zonestotouch}->{$currzone} = 1;
        }
    }
    my $passtab = xCAT::Table->new('passwd');
    my $pent = $passtab->getAttribs({key=>'omapi',username=>'xcat_key'},['password']);
    if ($pent and $pent->{password}) { 
        $ctx->{privkey} = $pent->{password};
    } #do not warn/error here yet, if we can't generate or extract, we'll know later

    my @entries =  xCAT::TableUtils->get_site_attribute("forwarders");
    my $site_entry = $entries[0];
    if ( defined($site_entry)) {
        my @forwarders = split /[ ,]/,$site_entry;
        $ctx->{forwarders}=\@forwarders;
    }

    $ctx->{zonestotouch}->{$ctx->{domain}}=1;
	foreach (@networks) {
		if ($_->{domain}) {
			$ctx->{zonestotouch}->{$_->{domain}}=1;
		}
	}
	
    xCAT::SvrUtils::sendmsg("Getting reverse zones, this may take several minutes for a large cluster.", $callback);
    
    foreach (@nodes) {
        my @revzones =  get_reverse_zones_for_entity($ctx,$_);;
        unless (@revzones) { next; }
        $ctx->{revzones}->{$_} = \@revzones;
        foreach (@revzones) {
            $ctx->{zonestotouch}->{$_}=1;
        }
    }
    xCAT::SvrUtils::sendmsg("Completed getting reverse zones.", $callback);
    
    if (1) { 
		#TODO: function to detect and return 1 if the master server is 
		#	DNS SOA for all the zones we care about here, we are examining 
        #   files to assure that our key is in named.conf, the zones we 
		#	care about are there, and that if active directory is in use,
        #  	 allow the domain controllers to update specific zones
        @entries =  xCAT::TableUtils->get_site_attribute("directoryprovider");
        $site_entry = $entries[0];
        if ( defined($site_entry) and $site_entry eq 'activedirectory') {
            @entries =  xCAT::TableUtils->get_site_attribute("directoryservers");
            $site_entry = $entries[0];
            if ( defined($site_entry)) {
                my @dservers = split /[ ,]/,$site_entry;
                $ctx->{adservers} = \@dservers;

				############################
				# - should this include all domains?
				# - multi-domains not supported with activedirectory
				#  	- TODO in future release
				###################

                $ctx->{adzones} = {
                    "_msdcs.". $ctx->{domain} => 1,
                    "_sites.". $ctx->{domain} => 1,
                    "_tcp.". $ctx->{domain} => 1,
                    "_udp.". $ctx->{domain} => 1,
                };
            }
        }

        @entries =  xCAT::TableUtils->get_site_attribute("dnsupdaters");
        $site_entry = $entries[0];
        if ( defined($site_entry) ) {
                my @nservers = split /[ ,]/,$site_entry;
                $ctx->{dnsupdaters} = \@nservers;
        }
	unless ($external) {
	        if ($zapfiles) { #here, we unlink all the existing files to start fresh
	            if (xCAT::Utils->isAIX())
	            {
	                system("/usr/bin/stopsrc -s $service");
	            }
	            else
	            {
	                system("service $service stop"); #named may otherwise hold on to stale journal filehandles
	            }
	            my $conf = get_conf();
	            unlink $conf;
	            my $DBDir = get_dbdir();
	            foreach (<$DBDir/db.*>) {
	                unlink $_;
	            }
	        }
	        #We manipulate local namedconf
	        $ctx->{dbdir} = get_dbdir();
	        $ctx->{zonesdir} = get_zonesdir();
	        chmod 0775, $ctx->{dbdir}; # assure dynamic dns can actually execute against the directory

	        update_namedconf($ctx); 
	        update_zones($ctx);
        
	        if ($ctx->{restartneeded}) {
	            xCAT::SvrUtils::sendmsg("Restarting $service", $callback);

                    if (xCAT::Utils->isAIX())
                    {
                        my $cmd = "/usr/bin/stopsrc -s $service";
                        my @output=xCAT::Utils->runcmd($cmd, 0);
                        my $outp = join('', @output);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Command failed: $cmd. Error message: $outp.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return;
                        }

                        $cmd = "/usr/bin/startsrc -s $service";
                        @output=xCAT::Utils->runcmd($cmd, 0);
                        $outp = join('', @output);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Command failed: $cmd. Error message: $outp.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return;
                        }
                    }
                    else
                    {
                        my $cmd = "service $service stop";
                        my @output=xCAT::Utils->runcmd($cmd, 0);
                        my $outp = join('', @output);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Command failed: $cmd. Error message: $outp.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return;
                        }

                        $cmd = "service $service start";
                        @output=xCAT::Utils->runcmd($cmd, 0);
                        $outp = join('', @output);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Command failed: $cmd. Error message: $outp.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return;
                        }
                    }

	            xCAT::SvrUtils::sendmsg("Restarting named complete", $callback);
		}
	        
	}
    } else {
        unless ($ctx->{privkey}) {
            xCAT::SvrUtils::sendmsg([1,"Unable to update DNS due to lack of credentials in passwd to communicate with remote server"], $callback);
        }
    }

    # check if named is active before update dns records.
    if (xCAT::Utils->isAIX())
    {
        my $cmd = "/usr/bin/lssrc -s $service |grep active";
        my @output=xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            $cmd = "/usr/bin/startsrc -s $service";
            @output=xCAT::Utils->runcmd($cmd, 0);
            my $outp = join('', @output);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Command failed: $cmd. Error message: $outp.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return;
            }
        }
    }
    else
    {
        my $cmd = "service $service status|grep running";
        my @output=xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            $cmd = "service $service start";
            @output=xCAT::Utils->runcmd($cmd, 0);
            my $outp = join('', @output);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Command failed: $cmd. Error message: $outp.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return;
            }
        }
    }
        
    #now we stick to Net::DNS style updates, with TSIG if possible.  TODO: kerberized (i.e. Windows) DNS server support, maybe needing to use nsupdate -g....
    if ($external)
    {
		# based on /etc/resolv.conf
        $ctx->{resolver} = Net::DNS::Resolver->new(); 
    }
    else
    {
		# default to localhost
        $ctx->{resolver} = Net::DNS::Resolver->new(nameservers=>['127.0.0.1']); 
    }

    my $ret = add_or_delete_records($ctx);
    unless($ret) {
        xCAT::SvrUtils::sendmsg("DNS setup is completed", $callback);
    }

    umask($oldmask);
}

sub get_zonesdir {
    my $ZonesDir = get_dbdir();

    my @entries =  xCAT::TableUtils->get_site_attribute("bindzones");
    my $site_entry = $entries[0];

	if ( defined($site_entry) ) {
		$ZonesDir= $site_entry;
	}

    return "$ZonesDir";
}

sub get_conf {
    my $conf="/etc/named.conf";

    # is this ubuntu ?
	if ( $distro =~ /ubuntu.*/i || $distro =~ /debian.*/i ){
        $conf="/etc/bind/named.conf";
    }

    my @entries =  xCAT::TableUtils->get_site_attribute("bindconf");
    my $site_entry = $entries[0];

	if ( defined($site_entry) ) {
		$conf= $site_entry;
	}

    return "$conf";
}

sub get_dbdir {
    my $DBDir;

    my @entries =  xCAT::TableUtils->get_site_attribute("binddir");
    my $site_entry = $entries[0];
	if ( defined($site_entry) ) {
		$DBDir = $site_entry;
	}

    if ( -d "$DBDir" ) {
        return "$DBDir"
    } elsif (-d "/var/named") {
        return "/var/named/";
    } elsif (-d "/var/lib/named") {
        # Temp fix for bugzilla 73119
        chown(scalar(getpwnam('root')),scalar(getgrnam('named')),"/var/lib/named");
        return "/var/lib/named/";
    } 
    elsif (-d "/var/lib/bind") {
        return "/var/lib/bind/";
    } 
    else {
        mkpath "/var/named/";
        chown(scalar(getpwnam('named')),scalar(getgrnam('named')),"/var/named");
        return "/var/named/";
    }
}

sub isvalidip {
    #inet_pton/ntop good for ensuring an ip looks like an ip? or do string compare manually?
    #for now, do string analysis, one problem with pton/ntop is that 010.1.1.1 would look diff from 10.1.1.1)
    my $candidate = shift;
    if ($candidate =~ /^(\d+)\.(\d+)\.(\d+).(\d+)\z/) {
        return (
            $1 >= 0 and $1 <= 255 and
            $2 >= 0 and $2 <= 255 and
            $3 >= 0 and $3 <= 255 and
            $4 >= 0 and $4 <= 255
            );
    }
}
sub update_zones {
    my $ctx = shift;
    my $currzone;
    my $dbdir = $ctx->{dbdir};
    my $name = hostname;
    my $node = $name;

	# get the domain for the node - which is the local hostname
	my ($host, $nip) = xCAT::NetworkUtils->gethostnameandip($node);
	my @hosts;
	push (@hosts, $host);
	my $nd = xCAT::NetworkUtils->getNodeDomains(\@hosts);
	my %nodedomains = %$nd;
	my $domain = $nodedomains{$host};

    xCAT::SvrUtils::sendmsg("Updating zones.", $callback);

    unless ($domain =~ /^\./) {
        $domain = '.'.$domain;
    }
    unless ($name =~ /\./) {
        $name .= $domain;
    }
    unless ($name =~ /\.\z/) {
        $name .= '.';
    }
    my $ip=$node;
    if ($ctx->{hoststab} and $ctx->{hoststab}->{$node} and $ctx->{hoststab}->{$node}->[0]->{ip}) {
        $ip = $ctx->{hoststab}->{$node}->[0]->{ip};
        unless (isvalidip($ip)) {
            xCAT::SvrUtils::sendmsg([1,"The hosts table entry for $node indicates $ip as an ip address, which is not a valid address"], $callback);
            next;
        }
    } else {
        unless ($ip = inet_aton($ip)) {
            print "Unable to find an IP for $node in hosts table or via system lookup (i.e. /etc/hosts";
            xCAT::SvrUtils::sendmsg([1,"Unable to find an IP for $node in hosts table or via system lookup (i.e. /etc/hosts"], $callback);
            next;
        }
        $ip = inet_ntoa($ip);
    }
    my @neededzones = keys %{$ctx->{zonestotouch}};
    push @neededzones,keys %{$ctx->{adzones}};
    my ($sec, $min, $hour, $mday, $mon, $year, $rest) = localtime(time);
    my $serial = ($mday * 100) + (($mon + 1) * 10000) + (($year + 1900) * 1000000);

    foreach $currzone (@neededzones) {
		my $zonefilename = $currzone;
        if ($currzone =~ /IN-ADDR\.ARPA/) {
            $currzone =~ s/\.IN-ADDR\.ARPA.*//;
            my @octets = split/\./,$currzone;
            $currzone = join('.',reverse(@octets));
            $zonefilename = $currzone;
        #If needed, the below, but it was a fairly painfully restricted paradigm for zonefile names...
        #} elsif (not $zonefilename =~ /_/) {
        #    $zonefilename =~ s/\..*//; #compatible with bind.pm
        }
        unless (-f $dbdir."/db.$zonefilename") {
            my $zonehdl;
            open($zonehdl,">>",$dbdir."/db.$zonefilename");
            flock($zonehdl,LOCK_EX);
            seek($zonehdl,0,0);
            truncate($zonehdl,0);
            print $zonehdl '$TTL 86400'."\n";
            print $zonehdl '@ IN SOA '.$name." root.$name ( $serial 10800 3600 604800 86400 )\n";
            print $zonehdl "  IN NS  $name\n";
            if ($name =~ /$currzone/) { #Must guarantee an A record for the DNS server
                print $zonehdl "$name  IN A  $ip\n";
            }
            flock($zonehdl,LOCK_UN);
            close($zonehdl);
			if ( $distro =~ /ubuntu.*/i || $distro =~ /debian.*/i ){
                chown(scalar(getpwnam('root')),scalar(getgrnam('bind')),$dbdir."/db.$zonefilename");
            }
            else{
                chown(scalar(getpwnam('named')),scalar(getgrnam('named')),$dbdir."/db.$zonefilename");
            }
            $ctx->{restartneeded}=1;
        }
    }
    xCAT::SvrUtils::sendmsg("Completed updating zones.", $callback);
}

sub update_namedconf {
    my $ctx = shift;
    my $namedlocation = get_conf();
    my $nameconf;
    my @newnamed;
    my $gotoptions=0;
    my $gotkey=0;
    my %didzones;

    if (-r $namedlocation) {
        my @currnamed=();
        open($nameconf,"<",$namedlocation);
        flock($nameconf,LOCK_SH);
        @currnamed=<$nameconf>;
        flock($nameconf,LOCK_UN);
        close($nameconf);
        my $i = 0;
        for ($i=0;$i<scalar(@currnamed);$i++) {
            my $line = $currnamed[$i];
            if ($line =~ /^options +\{/) {
                $gotoptions=1;
                my $skip=0;
                do {
		    #push @newnamed,"\t\t//listen-on-v6 { any; };\n";
                    if ($ctx->{forwarders} and $line =~ /forwarders {/) {
                        push @newnamed,"\tforwarders \{\n";
                        $skip=1;
                        foreach (@{$ctx->{forwarders}}) {
                            push  @newnamed,"\t\t".$_.";\n";
                        }
                        push @newnamed,"\t};\n";
                    } elsif ($skip) {
                        if ($line =~ /};/) {
                            $skip = 0;
                        }
                    } else {
                        push @newnamed,$line;
                    }
                    $i++;
                    $line = $currnamed[$i];
                } while ($line !~ /^\};/);
                push @newnamed,$line;
            } elsif ($line =~ /^zone "([^"]*)" in \{/) {
                my $currzone = $1;
                if ($ctx->{zonestotouch}->{$currzone} or $ctx->{adzones}->{$currzone}) {
                    $didzones{$currzone}=1;
                    my @candidate = ($line);
                    my $needreplace=1;
                    do {
                        $i++;
                        $line =  $currnamed[$i];
                        push @candidate,$line;
                        if ($line =~ /key xcat_key/) {
                            $needreplace=0;
                        }
                    } while ($line !~ /^\};/); #skip the old file zone
                    unless ($needreplace) {
                        push @newnamed,@candidate;
                        next;
                    }
                    $ctx->{restartneeded}=1;
                    push @newnamed,"zone \"$currzone\" in {\n","\ttype master;\n","\tallow-update {\n","\t\tkey xcat_key;\n";
                    my @list;
                    if (not $ctx->{adzones}->{$currzone}) {
                        if ($ctx->{dnsupdaters}) {
                            @list = @{$ctx->{dnsupdaters}};
                        }
                    } else {
                        if ($ctx->{adservers}) {
                            @list = @{$ctx->{adservers}};
                        }
                    }
                    foreach (@list) {
                        push @newnamed,"\t\t$_;\n";
                    }
                    if ($currzone =~ /IN-ADDR\.ARPA/) {
                        my $net = $currzone;
                        $net =~ s/.IN-ADDR\.ARPA.*//;
                        my @octets = split/\./,$net;
                        $net = join('.',reverse(@octets));
                        push @newnamed,"\t};\n","\tfile \"db.$net\";\n","};\n";

                    } else {
                        my $zfilename = $currzone;
                        #$zfilename =~ s/\..*//;
                        push @newnamed,"\t};\n","\tfile \"db.$zfilename\";\n","};\n";
                    }
                } else {
                    push @newnamed,$line;
                    do {
                        $i++;
                        $line =  $currnamed[$i];
                        push @newnamed,$line;
                    } while ($line !~ /^\};/);
                }

            } elsif ($line =~ /^key xcat_key/) {
                $gotkey=1;
                if ($ctx->{privkey}) {
                    #for now, assume the field is correct
                    #push @newnamed,"key xcat_key {\n","\talgorithm hmac-md5;\n","\tsecret \"".$ctx->{privkey}."\";\n","};\n\n";
                    push @newnamed,$line;
                    do {
                        $i++;
                        $line =  $currnamed[$i];
                        push @newnamed,$line;
                    } while ($line !~ /^\};/);
                } else {
                    push @newnamed,$line;
                    while ($line !~ /^\};/) { #skip the old file zone
                        if ($line =~ /secret \"([^"]*)\"/) {
                            my $passtab = xCAT::Table->new("passwd",-create=>1);
                            $passtab->setAttribs({key=>"omapi",username=>"xcat_key"},{password=>$1});
                        }
                        $i++;
                        $line =  $currnamed[$i];
                        push @newnamed,$line;
                    }
                }
            } else {
                push @newnamed,$line;
            }
        }
    }
    unless ($gotoptions) {
        push @newnamed,"options {\n","\tdirectory \"".$ctx->{zonesdir}."\";\n";
	push @newnamed,"\t\t//listen-on-v6 { any; };\n";
        if ($ctx->{forwarders}) {
            push @newnamed,"\tforwarders {\n";
            foreach (@{$ctx->{forwarders}}) {
                push @newnamed,"\t\t$_;\n";
            }
            push @newnamed,"\t};\n";
        }
        push @newnamed,"};\n\n";
    }
    unless ($gotkey) {
        unless ($ctx->{privkey}) { #need to generate one
            $ctx->{privkey} = encode_base64(genpassword(32));
            chomp($ctx->{privkey});
        }
        push @newnamed,"key xcat_key {\n","\talgorithm hmac-md5;\n","\tsecret \"".$ctx->{privkey}."\";\n","};\n\n";
        $ctx->{restartneeded}=1;
    }
    my $zone;
    foreach $zone (keys %{$ctx->{zonestotouch}}) {
        if ($didzones{$zone}) { next; }
        $ctx->{restartneeded}=1; #have to add a zone, a restart will be needed
        push @newnamed,"zone \"$zone\" in {\n","\ttype master;\n","\tallow-update {\n","\t\tkey xcat_key;\n";
        foreach (@{$ctx->{dnsupdaters}}) {
            push @newnamed,"\t\t$_;\n";
        }
        if ($zone =~ /IN-ADDR\.ARPA/) {
            my $net = $zone;
            $net =~ s/.IN-ADDR\.ARPA.*//;
            my @octets = split/\./,$net;
            $net = join('.',reverse(@octets));
            push @newnamed,"\t};\n","\tfile \"db.$net\";\n","};\n";

        } else {
            my $zfilename = $zone;
            #$zfilename =~ s/\..*//;
            push @newnamed,"\t};\n","\tfile \"db.$zfilename\";\n","};\n";
        }
    }
    foreach $zone (keys %{$ctx->{adzones}}) {
        if ($didzones{$zone}) { next; }
        $ctx->{restartneeded}=1; #have to add a zone, a restart will be needed
        push @newnamed,"zone \"$zone\" in {\n","\ttype master;\n","\tallow-update {\n","\t\tkey xcat_key;\n";
        foreach (@{$ctx->{adservers}}) {
            push @newnamed,"\t\t$_;\n";
        }
        my $zfilename = $zone;
        #$zfilename =~ s/\..*//;
        push @newnamed,"\t};\n","\tfile \"db.$zfilename\";\n","};\n\n";
    }

    # For AIX, add a hint zone
    if (xCAT::Utils->isAIX())
    {
        unless (grep(/hint/, @newnamed))
        {
            push @newnamed,"zone \"\.\" in {\n","\ttype hint;\n","\tfile \"db\.cache\";\n","};\n\n";
            # Toutch the stub zone file
            system("/usr/bin/touch $ctx->{dbdir}.'/db.cache'");
            $ctx->{restartneeded}=1;
            if($ctx->{forwarders})
            {
                my $dbcachefile = $ctx->{dbdir}.'/db.cache';
                my $cmd = qq~dig @"$ctx->{forwarders}[0]" . ns >> $dbcachefile~;
                my $outref = xCAT::Utils->runcmd("$cmd", 0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Failed to run command: $cmd.\n";
                    xCAT::MsgUtils->message("W", $rsp, $callback, 1);
                }
            }
        }
    }

    my $newnameconf;
    open($newnameconf,">>",$namedlocation);
    flock($newnameconf,LOCK_EX);
    seek($newnameconf,0,0);
    truncate($newnameconf,0);
    for my $l  (@newnamed) { print $newnameconf $l; }
    flock($newnameconf,LOCK_UN);
    close($newnameconf);
	if ( $distro =~ /ubuntu.*/i || $distro =~ /debian.*/i ){
        chown (scalar(getpwnam('root')),scalar(getgrnam('bind')),$namedlocation);
    }
    else{
        chown (scalar(getpwnam('root')),scalar(getgrnam('named')),$namedlocation);
    }
}

sub add_or_delete_records {
    my $ctx = shift;

    xCAT::SvrUtils::sendmsg("Updating DNS records, this may take several minutes for a large cluster.", $callback);
    
    unless ($ctx->{privkey}) {
        my $passtab = xCAT::Table->new('passwd');
        my $pent = $passtab->getAttribs({key=>'omapi',username=>'xcat_key'},['password']);
        if ($pent and $pent->{password}) { 
            $ctx->{privkey} = $pent->{password};
        } else {
            xCAT::SvrUtils::sendmsg([1,"Unable to find omapi key in passwd table"], $callback);
        }
    }
    my $node;
    my @ips;

    $ctx->{nsmap} = {}; #will store a map to known NS records to avoid needless redundant queries to sort nodes into domains
    $ctx->{updatesbyzone}={}; #sort all updates into their respective zones for bulk update for fewer DNS transactions

	# get node domains
	my $nd = xCAT::NetworkUtils->getNodeDomains(\@{$ctx->{nodes}});
	my %nodedomains = %{$nd};

    foreach $node (@{$ctx->{nodes}}) {
        my $name = $node;

        if (($name =~ /loopback/) || ($name =~ /localhost/))
        {
            next;
        }

		my $domain = $nodedomains{$node};
		unless ($domain =~ /^\./) { $domain = '.'.$domain; }

        unless ($name =~ /$domain/) { $name .= $domain } # $name needs to represent fqdn, but must preserve $node as a nodename for cfg lookup

        if ($ctx->{hoststab} and $ctx->{hoststab}->{$node} and $ctx->{hoststab}->{$node}->[0]->{ip}) {
            @ips = ($ctx->{hoststab}->{$node}->[0]->{ip});
        } else {
            @ips = getipaddr($node,GetAllAddresses=>1);
	    if (not @ips and keys %{$ctx->{nodeips}->{$node}}) {
	    	@ips = keys %{$ctx->{nodeips}->{$node}};
	    }
            if (!defined($ips[0])) {
                xCAT::SvrUtils::sendmsg([1,"Unable to find an IP for $node in hosts table or via system lookup (i.e. /etc/hosts)"], $callback);
                next;
            }
        }
        foreach my $ip (@ips) {
            $ctx->{currip}=$ip;
            #time to update, A and PTR records, IPv6 still TODO
            if ($ip =~ /\./) { #v4
                $ip = join('.',reverse(split(/\./,$ip)));
                $ip .= '.IN-ADDR.ARPA.';
            } elsif ($ip =~ /:/) { #v6
                $ip=getipaddr($ip,GetNumber=>1);
                $ip=$ip->as_hex();
                $ip =~ s/^0x//;
                $ip = join('.',reverse(split(//,$ip)));
                $ip .= '.ip6.arpa.';
            } else {
                die "ddns did not understand $ip result of lookup";
            }
            #ok, now it is time to identify which zones should actually hold the forward (A) and reverse (PTR) records and a nameserver to handle the request
            my $revzone = $ip;
            $ctx->{currnode}=$node;
            $ctx->{currname}=$name;
            $ctx->{currrevname}=$ip;
            my $tmpdm;
            unless ($domain =~ /\.$/) { $tmpdm = $domain.'.'; } #example.com becomes example.com.

            find_nameserver_for_dns($ctx,$revzone);
            find_nameserver_for_dns($ctx,$tmpdm);
        }
    }
    my $zone;
    foreach $zone (keys %{$ctx->{updatesbyzone}}) {
	my $ip = xCAT::NetworkUtils->getipaddr($ctx->{nsmap}->{$zone});
        if( !defined $ip) {
            xCAT::SvrUtils::sendmsg([1,"Please make sure $ctx->{nsmap}->{$zone} exist either in /etc/hosts or DNS."], $callback);
            return 1;
        }

        my $resolver = Net::DNS::Resolver->new(nameservers=>[$ip]);
        my $entry;
        my $numreqs = 300; # limit to 300 updates in a payload, something broke at 644 on a certain sample, choosing 300 for now
        my $update = Net::DNS::Update->new($zone);
        foreach $entry (@{$ctx->{updatesbyzone}->{$zone}}) {
            if ($ctx->{deletemode}) {
                $update->push(update=>rr_del($entry));
            } else {
                $update->push(update=>rr_add($entry));
            }
            $numreqs -= 1;
            if ($numreqs == 0) {
                $update->sign_tsig("xcat_key",$ctx->{privkey});
                $numreqs=300;
                my $reply = $resolver->send($update);
                if ($reply)
                {
                    if ($reply->header->rcode ne 'NOERROR')
                    {
                        xCAT::SvrUtils::sendmsg([1,"Failure encountered updating $zone, error was ".$reply->header->rcode.". See more details in system log."], $callback);
                    }
                }
                else
                {
                    xCAT::SvrUtils::sendmsg([1,"No reply received when sending DNS update to zone $zone"], $callback);
                }
                
                $update =  Net::DNS::Update->new($zone); #new empty request
            }
        }
        if ($numreqs != 300) { #either no entries at all to begin with or a perfect multiple of 300
            $update->sign_tsig("xcat_key",$ctx->{privkey});
            my $reply = $resolver->send($update);
                if ($reply)
                {
                    if ($reply->header->rcode ne 'NOERROR')
                    {
                        xCAT::SvrUtils::sendmsg([1,"Failure encountered updating $zone, error was ".$reply->header->rcode.". See more details in system log."], $callback);
                    }
                }
                else
                {
                    xCAT::SvrUtils::sendmsg([1,"No reply received when sending DNS update to zone $zone"], $callback);
                }
            
            # sometimes resolver does not work if the update zone request sent so quick
            sleep 1;
        }
    }
    xCAT::SvrUtils::sendmsg("Completed updating DNS records.", $callback);
}
sub find_nameserver_for_dns {
    my $ctx = shift;
    my $zone = shift;
    my $node = $ctx->{currnode};
    my $ip = $ctx->{currip};
    my $rname = $ctx->{currrevname};
    my $name = $ctx->{currname};
    unless ($name =~ /\.\z/) { $name .= '.' }
    my @rrcontent;
    if ($ip =~ /:/) {
        @rrcontent = ( "$name IN AAAA $ip" );
    } else {
        @rrcontent = ( "$name IN A $ip" );
    }
    foreach (keys %{$ctx->{nodeips}->{$node}}) {
        unless ($_ eq $ip) {
            if ($_ =~ /:/) {
                push @rrcontent,"$name IN AAAA $_";
            } else {
                push @rrcontent,"$name IN A $_";
            }
        }
    }

    if (defined $ctx->{aliases}->{$node}) {
    	foreach (keys %{$ctx->{aliases}->{$node}}) {
    		push @rrcontent, "$_ IN CNAME $name";
    	}
    }
    if ($ctx->{deletemode}) {
        push @rrcontent,"$name TXT";
        push @rrcontent,"$name A";
    }
    if ($zone =~ /IN-ADDR.ARPA/ or $zone =~ /ip6.arpa/) { #reverse style
        @rrcontent = ("$rname IN PTR $name");
    }
    while ($zone) {
       unless (defined $ctx->{nsmap}->{$zone}) { #ok, we already thought about this zone and made a decision
           if ($zone =~ /^\.*192.IN-ADDR.ARPA\.*/ or $zone =~ /^\.*172.IN-ADDR.ARPA\.*/ or $zone =~ /127.IN-ADDR.ARPA\.*/ or $zone =~ /^\.*IN-ADDR.ARPA\.*/ or $zone =~ /^\.*ARPA\.*/) {
                $ctx->{nsmap}->{$zone} = 0; #ignore zones that are likely to appear, but probably not ours
	   } elsif ($::XCATSITEVALS{ddnsserver}) {
                $ctx->{nsmap}->{$zone} = $::XCATSITEVALS{ddnsserver};
           } else {
               my $reply = $ctx->{resolver}->query($zone,'NS');
               if ($reply)  {
                   if ($reply->header->rcode ne 'NOERROR') {
                      xCAT::SvrUtils::sendmsg([1,"Failure encountered querying $zone, error was ".$reply->header->rcode], $callback);
                    }
                    foreach my $record ($reply->answer) {
                        if ( $record->nsdname =~ /blackhole.*\.iana\.org/) {
                            $ctx->{nsmap}->{$zone} = 0; 
                        } else {
                            $ctx->{nsmap}->{$zone} = $record->nsdname;
                        }
                    }
               } else { 
                   $ctx->{nsmap}->{$zone} = 0; 
               }
           }
       }

       if ($ctx->{nsmap}->{$zone}) {  #we have a nameserver for this zone, therefore this zone is one to update
           push @{$ctx->{updatesbyzone}->{$zone}},@rrcontent;
           last;
       } else { #we have it defined, but zero, means search higher domains.  Possible to shortcut further by pointing to the right domain, maybe later
            if ($zone !~ /\./) {
               xCAT::SvrUtils::sendmsg([1,"Unable to find reverse zone to hold $node"], $callback,$node);
               last;
            }

           $zone =~ s/^[^\.]*\.//; #strip all up to and including first dot
           unless ($zone) {
               xCAT::SvrUtils::sendmsg([1,"Unable to find zone to hold $node"], $callback,$node);
               last;
           }
       }
    }
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

sub makedns_usage
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}},
      "\n  makedns - sets up domain name services (DNS).";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tmakedns [-h|--help ]";
    push @{$rsp->{data}}, "\tmakedns [-e|--external] [-n|--new ] [noderange]";
    push @{$rsp->{data}}, "\tmakedns [-e|--external] [-d|--delete noderange]";
    push @{$rsp->{data}}, "\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

1;
