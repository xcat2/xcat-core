package xCAT::SLP;
use Carp;
use IO::Select;
use strict;
use xCAT::Utils;
my $ip6support = eval {
    require IO::Socket::INET6;
    require Socket6;
    1;
};
use Socket;
unless ($ip6support) {
    require IO::Socket::INET;
}

#TODO: somehow get at system headers to get the value, put in linux's for now
use constant IPV6_MULTICAST_IF => 17;
use constant IP_MULTICAST_IF => 32;
use constant REQ_INTERVAL => 1;
my %xid_to_srvtype_map;
my $xid;
my $gprlist;
my %searchmacs;
my %ip4neigh;
my %ip6neigh;
my %servicehash;
my %sendhash;
my $attrpy = 0;
my $serrpy = 0;
sub getmulticasthash {
    my $hash=0;
    my @nums = unpack("C*",shift);
    foreach my $num (@nums) {
        $hash *= 33;
        $hash += $num;
        $hash &= 0xffff;
    }
    $hash &= 0x3ff;
    $hash |= 0x1000;
    return sprintf("%04x",$hash);
}


sub dodiscover {
    my %args = @_;
    my $unicast = $args{unicast}; #should be used with -s !
    my $ipranges = $args{range};
    my $rspcount = 0;
    my $rspcount1 = 0;
    my $sendcount = 1;
    $xid = int(rand(16384))+1;
    my %rethash;
    unless ($args{'socket'}) {
        if ($ip6support) {
                $args{'socket'} = IO::Socket::INET6->new(Proto => 'udp');
        } else {
                $args{'socket'} = IO::Socket::INET->new(Proto => 'udp');
        }
         #make an extra effort to request biggest receive buffer OS is willing to give us
        if (-r "/proc/sys/net/core/rmem_max") { # we can detect the maximum allowed socket, read it.
            my $sysctl;
            open ($sysctl,"<","/proc/sys/net/core/rmem_max");
            my $maxrcvbuf=<$sysctl>;
            my $rcvbuf = $args{'socket'}->sockopt(SO_RCVBUF);
            if ($maxrcvbuf > $rcvbuf) {
                $args{'socket'}->sockopt(SO_RCVBUF,$maxrcvbuf/2);
            }
        }
    } #end of unless socket
    unless ($args{SrvTypes}) { croak "SrvTypes argument is required for xCAT::SLP::Dodiscover"; }
    unless (xCAT::Utils->isAIX()) { # AIX bug, can't set socket with SO_BROADCAST, otherwise multicast can't work.
        setsockopt($args{'socket'},SOL_SOCKET,SO_BROADCAST,1); #allow for broadcasts to be sent, we know what we are doing
    }
    my @srvtypes;
    if (ref $args{SrvTypes}) {
        @srvtypes = @{$args{SrvTypes}};
    } else {
        @srvtypes = split /,/,$args{SrvTypes};
    }

    my $interfaces = get_interfaces(%args);
    if ($args{Ip}) {
        foreach my $nic (keys %$interfaces) {
            if (${${$interfaces->{$nic}}{ipv4addrs}}[0] =~ /(\d+\.\d+\.\d+\.\d+)/) {
                unless ($args{Ip} =~ $1) {
                    delete $interfaces->{$nic};
                }
            }
        }
    }
    my @printip;
    foreach my $iface (keys %{$interfaces}) {
        foreach my $sip (@{$interfaces->{$iface}->{ipv4addrs}}) {
            my $ip = $sip;
            $ip =~ s/\/(.*)//;
            push @printip, $ip;
        }
    }
    my $printinfo = join(",", @printip);
    
    if ($unicast) {
        if (xCAT::Utils->isAIX()){
            send_message($args{reqcallback}, 1, "lsslp unicast is not supported on AIX");
            exit 1;
        }
        if (! -f "/usr/bin/nmap"){
            send_message($args{reqcallback}, 1, "nmap does not exist, lsslp unicast is not possible");
            exit 1;
        }
        my @servernodes;
        my @iprange = split /,/, $ipranges;
        foreach my $range (@iprange) {
            send_message($args{reqcallback}, 0, "Processing range $range...");
            if ($range =~/\/(\d+)/){
               if ($1 < 16) {
                   send_message($args{reqcallback}, 0, "The rarge is too large and may be time consuming. Broadcast is recommended.");
               }
            }

            #no need to check site.nmapoptions because it specifilly 
			# uses T5 for certain performance requirement.
            `/usr/bin/nmap $range -sn -PE -n --send-ip -T5 `;
            my $nmapres = `/usr/bin/nmap $range -PE -p 427 -n --send-ip -T5 `;
            foreach my $line (split(/\n\n/,$nmapres)) {
                my $server;
                foreach my $sline (split(/\n/, $line)) {
                    if ($sline =~ /Nmap scan report for (\d+\.\d+\.\d+\.\d+)/) {
                       $server = $1;
                    }
                    if ($sline =~ /427/ and ($sline =~ /open/ or $sline =~ /filtered/)){
                        push @servernodes, $server;
                    }
                } # end of foreach line
            } # end of foreach line
        } # end of foreach pi-range
        unless (@servernodes){
            send_message($args{reqcallback}, 0, "Nmap returns nothing");
            return undef;
        }  
        my $number = scalar (@servernodes);
        send_message($args{reqcallback}, 0, "Begin to do unicast to $number nodes...");
        my %rechash;
        pipe CREAD,PWRITE;
        my $pid = xCAT::Utils->xfork();
        if ( !defined($pid) ) {
            send_message($args{reqcallback}, 1, "Fork error: $!" );
            return undef;
        } elsif ( $pid == 0 ) {
            close PWRITE; 
            foreach my $srvtype (@srvtypes) {
                my $packet = generate_attribute_request(%args, SrvType=>$srvtype);
                foreach my $destserver (@servernodes) {
                    my $destip = inet_aton($destserver);
                    my $destaddr = sockaddr_in(427,$destip);
                    my $res =  $args{'socket'}->send($packet,0,$destaddr);
                } # end of foreach destserver    
            }# end of foreach services
            while(<CREAD>){ 
                chomp; 
                my $destserver = $_;
                if ($destserver =~ /NowYouNeedToDie/){
                    close CREAD;
                    exit 0;
                }   
                foreach my $srvtype (@srvtypes) {
                    my $packet = generate_attribute_request(%args, SrvType=>$srvtype);
                    my $destip = inet_aton($destserver);
                    my $destaddr = sockaddr_in(427,$destip);
                    for( my $j = 0; $j < 1; $j++) {
                        my $res =  $args{'socket'}->send($packet,0,$destaddr);
                    } # end of foreach j++
                }# end of foreach services
            } # end of while (cread)
        } else {
            close CREAD;
            $rspcount = 0;
            my $waittime = ($args{Time}>0)?$args{Time}:300;
            my $deadline = time()+ $waittime;
            my $waitforsocket = IO::Select->new();
            $waitforsocket->add($args{'socket'});
            my $rectime = time() + 5;
            my $recvzero = 0;
            while ($deadline > time()) {
                $rspcount1 = 0;
                while ($rectime > time()) {
                    while ($waitforsocket->can_read(0)) {
                        my $slppacket;
                        my $peer = $args{'socket'}->recv($slppacket,3000,0);
                        $rechash{$peer} = $slppacket;
                    }  #end of can_read
                } # end of receiving
                # now begin to parse the packets
                for my $tp (keys %rechash) {
                    my @restserver ;
                    my $pkg = $tp;
                    my $slpkg = $rechash{$tp};          
                    my( $port,$flow,$ip6n,$ip4n,$scope);
                    my $peername;
                    if ($ip6support) {
                        ( $port,$flow,$ip6n,$scope) = Socket6::unpack_sockaddr_in6_all($pkg);
                        $peername = Socket6::inet_ntop(Socket6::AF_INET6(),$ip6n);
                    } else {
                        ($port,$ip4n) = sockaddr_in($pkg);
                        $peername = inet_ntoa($ip4n);
                    }
                    if ($peername =~ /\./) { #ipv4
                        $peername =~ s/::ffff://;
                    }
                    if ($rethash{$peername}) {
                        next; #got a dupe, discard
                    }
                    my $result = process_slp_packet(packet=>$slpkg,sockaddr=>$pkg,'socket'=>$args{'socket'}, peername=>$peername, callback=>$args{reqcallback});
                    if ($result) {
                        $rspcount++;
                        $rspcount1++;
                        $result->{peername} = $peername;
                        $result->{scopeid} = $scope;
                        $result->{sockaddr} = $pkg;
                        my $hashkey;
                        if ($peername =~ /fe80/) {
                            $peername .= '%'.$scope;
                        }
                        $rethash{$peername} = $result;
                        if ($args{Callback}) {
                            $args{Callback}->($result);
                        }
                        foreach my $mynode (@servernodes) {
                            unless ($mynode =~ $peername) {
                                push @restserver, $mynode;
                            }#end of mynode=~peername
                        } # end of foreach
                        @servernodes = @restserver;
                    } # end of if result
                } # end of foreach processing
                foreach my $node (@servernodes) {
                    syswrite PWRITE,"$node\n";
                } # end of foreach servernodes
                $recvzero++ unless ($rspcount1);
                last if ($recvzero > 2);    
            } # end of while(deadline) 
            syswrite PWRITE,"NowYouNeedToDie\n";
            close PWRITE;             
            if (@servernodes) {
                my $miss = join(",", @servernodes);
                send_message($args{reqcallback}, 0, "Warning: can't get attributes from these nodes' replies: $miss. Please re-send unicast to these nodes.") if ($args{reqcallback});
            }
        }# end of parent process 
    }  else {
    send_message($args{reqcallback}, 0, "Sending SLP request on interfaces: $printinfo ...") if ($args{reqcallback} and !$args{nomsg} );
        foreach my $srvtype (@srvtypes) {
            send_service_request_single(%args,ifacemap=>$interfaces,SrvType=>$srvtype);
        }
        unless ($args{NoWait}) { #in nowait, caller owns the responsibility..
            #by default, report all respondants within 3 seconds:
            my $waitforsocket = IO::Select->new();
            $waitforsocket->add($args{'socket'});
            my $retrytime = ($args{Retry}>0)?$args{Retry}+1:3;
            my $retryinterval = ($args{Retry}>0)?$args{Retry}:REQ_INTERVAL;
            my $waittime = ($args{Time}>0)?$args{Time}:20;
            my @peerarray;
            my @pkgarray;
            my $startinterval = time();
            my $interval;
            my $deadline=time()+$waittime;
            my( $port,$flow,$ip6n,$ip4n,$scope);
            my $slppacket;
            my $peername;
            while ($deadline > time()) {
                ########################################
                # receive untill there is none
                ########################################
                while ($waitforsocket->can_read(0)) {
                    my $peer = $args{'socket'}->recv($slppacket,3000,0);
                    push @peerarray, $peer;
                    push @pkgarray, $slppacket;
                }
                #######################################
                # process the packets
                #######################################
                for(my $j = 0; $j< scalar(@peerarray); $j++) {
                    my $pkg = $peerarray[$j];
                    my $slpkg = $pkgarray[$j];
                    if ($ip6support) {
                        ( $port,$flow,$ip6n,$scope) = Socket6::unpack_sockaddr_in6_all($pkg);
                         $peername = Socket6::inet_ntop(Socket6::AF_INET6(),$ip6n);
                    } else {
                        ($port,$ip4n) = sockaddr_in($pkg);
                        $peername = inet_ntoa($ip4n);
                    }
                    if ($rethash{$peername}) {
                            next; #got a dupe, discard
                    }
                    my $result = process_slp_packet(packet=>$slpkg,sockaddr=>$pkg,'socket'=>$args{'socket'}, peername=>$peername, callback=>$args{reqcallback});
                    if ($result) {
                        if ($peername =~ /\./) { #ipv4
                            $peername =~ s/::ffff://;
                        }
                        $result->{peername} = $peername;
                        if ($gprlist) {
                            $gprlist .= ','.$peername if(length($gprlist) < 1250);
                        } else {
                            $gprlist = $peername;
                        }
                        $result->{scopeid} = $scope;
                        $result->{sockaddr} = $pkg;
                        my $hashkey;
                        if ($peername =~ /fe80/) {
                            $peername .= '%'.$scope;
                        }
                        $rspcount++;
                        $rspcount1++;
                        $rethash{$peername} = $result;
                        if ($args{Callback}) {
                            $args{Callback}->($result);
                        }
                    }
                }
                #############################
                # check if need to return
                #############################
                @peerarray = ();
                @pkgarray = ();
                $interval = time() -  $startinterval;
                if ($args{Time} and $args{Count}) {
                    if ($rspcount >= $args{Count} or $interval >= $args{Time}) {
                        send_message($args{reqcallback}, 0, "Received $rspcount1 responses.") if ($args{reqcallback}  and !$args{nomsg});
                        last;
                    }
                }
                if ($sendcount > $retrytime and $rspcount1 == 0) {
                    send_message($args{reqcallback}, 0, "Received $rspcount1 responses.") if ($args{reqcallback} and !$args{nomsg});
                    last;
                }
                #########################
                # send request again
                #########################
                if ( $interval > $retryinterval){#* (2**$sendcount))) { #double time
                    $sendcount++;
                    $startinterval = time();
                    send_message($args{reqcallback}, 0, "Received $rspcount1 responses.") if ($args{reqcallback} and !$args{nomsg});  
                    send_message($args{reqcallback}, 0, "Sending SLP request on interfaces: $printinfo ...") if ($args{reqcallback} and !$args{nomsg});
                    foreach my $srvtype (@srvtypes) {
                        send_service_request_single(%args,ifacemap=>$interfaces,SrvType=>$srvtype);
                    }
                    $rspcount1 = 0;
                }    
            }
        } #end nowait
    } #end of if( unicast )

    foreach my $entry (keys %rethash) {
        handle_new_slp_entity($rethash{$entry});
    }
    if (xCAT::Utils->isAIX()) {
        foreach my $iface (keys %{$interfaces}) {
            foreach my $sip (@{$interfaces->{$iface}->{ipv4addrs}}) {
                my $ip = $sip;
                $ip =~ s/\/(.*)//;
                my $maskbits = $1;
                my $runcmd = `route delete 239.255.255.253 $ip`;
            }
        }
    }
    return (\%searchmacs, $sendcount, $rspcount);
}

sub process_slp_packet {
        my %args = @_;
        my $sockaddy = $args{sockaddr};
        my $socket = $args{'socket'};
        my $packet = $args{packet};
        my $parsedpacket = removeslpheader($packet);

        if ($parsedpacket->{FunctionId} == 2) {#Service Reply
            parse_service_reply($parsedpacket->{payload},$parsedpacket);
            unless (ref $parsedpacket->{service_urls} and scalar @{$parsedpacket->{service_urls}}) { return undef; }
            if ($parsedpacket->{attributes} && get_mac_for_addr($args{peername})) {
                #service reply had ext. Stop here if has gotten attributes and got mac. 
                #continue the unicast request for service attributes if cannot find mac for peernode
                return $parsedpacket; #don't bother sending attrrequest, already got it in first packet
            }
            my $srvtype = $xid_to_srvtype_map{$parsedpacket->{Xid}};
            my $packet = generate_attribute_request(%args,SrvType=>$srvtype);
            $sendhash{$args{peername}}->{package} = $packet;
            $sendhash{$args{peername}}->{sockaddy} = $sockaddy;
            $serrpy++;
            $socket->send($packet,0,$sockaddy);
            return undef;
        } elsif ($parsedpacket->{FunctionId} == 7) { #attribute reply
            $attrpy++;
            $parsedpacket->{SrvType} = $xid_to_srvtype_map{$parsedpacket->{Xid}};
            $parsedpacket->{attributes} = parse_attribute_reply($parsedpacket->{payload});
            my $attributes = $parsedpacket->{attributes};
            my $type = ${$attributes->{'type'}}[0] ;
            return undef unless ($type) ;
            #delete $parsedpacket->{payload};
            return $parsedpacket;
        } else {
            return undef;
        }
}

sub parse_attribute_reply {
    my $contents = shift;
    my @payload = unpack("C*",$contents);

    if ($payload[0] != 0 or $payload[1] != 0) {
        return {};
    }
    splice (@payload,0,2);
    return parse_attribute_list(\@payload);
}
sub parse_attribute_list {
    my $payload = shift;
    my $attrlength = ($payload->[0]<<8)+$payload->[1];
    splice(@$payload,0,2);
    my @attributes = splice(@$payload,0,$attrlength);
    my $attrstring = pack("C*",@attributes);
    my %attribs;
    #now we have a string...
    my $lastattrstring;
    while ($attrstring) {
        if ($lastattrstring eq $attrstring) { #infinite loop
            $attribs{unparsed_attribdata}=$attrstring;
            last;
        }
        $lastattrstring=$attrstring;
        if ($attrstring =~ /^\(/) {
            $attrstring =~ s/([^)]*\)),?//;
            my $attrib = $1;
            $attrib =~ s/^\(//;
            $attrib =~ s/\),?$//;
            $attrib =~ s/=(.*)$//;
            $attribs{$attrib}=[];
            my $valstring = $1;
            if (defined $valstring) {
                foreach(split /,/,$valstring) {
                    push @{$attribs{$attrib}},$_;
                }
            }
        } else {
            $attrstring =~ s/([^,]*),?//;
            $attribs{$1}=[];
        }
    }
    return \%attribs;
}
sub generate_attribute_request {
    my %args = @_;
    my $srvtype = $args{SrvType};
    my $scope = "DEFAULT";
    if ($args{Scopes}) { $scope = $args{Scopes}; }
    my $packet  = pack("C*",0,0); #no prlist
    my $service = $srvtype;
    $service =~ s!://.*!!;
    my $length = length($service);
    $packet .= pack("C*",($length>>8),($length&0xff));
    $length = length($scope);
    $packet .= $service.pack("C*",($length>>8),($length&0xff)).$scope;
    $packet .= pack("C*",0,0,0,0);
    my $header = genslpheader($packet,FunctionId=>6);
    $xid_to_srvtype_map{$xid++}=$srvtype;
    return $header.$packet;
    #$args{'socket'}->send($header.$packet,0,$args{sockaddry});
}


sub parse_service_reply {
    my $packet = shift;
    my $parsedpacket = shift;
    my @reply = unpack("C*",$packet);
    if ($reply[0] != 0 or $reply[1] != 0) {
        return ();
    }
    if ($parsedpacket->{extoffset}) {
        my @extdata = splice(@reply,$parsedpacket->{extoffset}-$parsedpacket->{currentoffset});
        $parsedpacket->{currentoffset} = $parsedpacket->{extoffset};
        parse_extension(\@extdata,$parsedpacket);
    }
    my $numurls = ($reply[2]<<8)+$reply[3];
    splice (@reply,0,4);
    while ($numurls--) {
        push @{$parsedpacket->{service_urls}},extract_next_url(\@reply);
    }
    return;
}

sub parse_extension {
    my $extdata = shift;
    my $parsedpacket = shift;
    my $extid = ($extdata->[0]<<8)+$extdata->[1];
    my $nextext = (($extdata->[2])<<16)+(($extdata->[3])<<8)+$extdata->[4];
    if ($nextext) {
        my @nextext = splice(@$extdata,$nextext-$parsedpacket->{currentoffset});
        $parsedpacket->{currentoffset} = $nextext;
        parse_extension(\@nextext,$parsedpacket);
    }
    splice(@$extdata,0,5);
    if ($extid == 2) {
        #this is defined in RFC 3059, attribute list extension
        #employed by AMM for one...
        my $urllen = ((shift @$extdata)<<8)+(shift @$extdata);
        splice @$extdata,0,$urllen; #throw this out for now..
        $parsedpacket->{attributes} = parse_attribute_list($extdata);
    }
}


sub extract_next_url { #section 4.3 url entries
    my $payload = shift;
    splice (@$payload,0,3); # discard reserved and lifetime which we will not bother using
    my $urllength = ((shift @$payload)<<8)+(shift @$payload);
    my @url = splice(@$payload,0,$urllength);
    my $authblocks = shift @$payload;
    unless ($authblocks == 0) {
        $payload = []; #TODO: skip/use auth blocks if needed to get at more URLs
    }
    return pack("C*",@url);
}

sub send_service_request_single {
    my %args = @_;
    my $packet = generate_service_request(%args);
    my $interfaces = $args{ifacemap}; #get_interfaces(%args);
    my $socket = $args{'socket'};
    my @v6addrs;
    my $v6addr;
    if ($ip6support) {
        my $hash=getmulticasthash($args{SrvType});
        my $target = "ff02::1:$hash";
        my ($fam, $type, $proto, $name);
        ($fam, $type, $proto, $v6addr, $name) =
           Socket6::getaddrinfo($target,"svrloc",Socket6::AF_INET6(),SOCK_DGRAM,0);
        push @v6addrs,$v6addr;
        ($fam, $type, $proto, $v6addr, $name) =
           Socket6::getaddrinfo("ff01::1:$hash","svrloc",Socket6::AF_INET6(),SOCK_DGRAM,0);
        push @v6addrs,$v6addr;
    }
    my $ipv4mcastaddr = inet_aton("239.255.255.253"); #per rfc 2608
    my $ipv4sockaddr  = sockaddr_in(427,$ipv4mcastaddr);
    foreach my $iface (keys %{$interfaces}) {
        if ($ip6support) {
            setsockopt($socket,Socket6::IPPROTO_IPV6(),IPV6_MULTICAST_IF,pack("I",$interfaces->{$iface}->{scopeidx}));
            foreach $v6addr (@v6addrs) {
                $socket->send($packet,0,$v6addr);
            }
        }
        foreach my $sip (@{$interfaces->{$iface}->{ipv4addrs}}) {
            my $ip = $sip;
            $ip =~ s/\/(.*)//;
            my $maskbits = $1;
            if (xCAT::Utils->isAIX()) {
                my $runcmd = `route add 239.255.255.253 $ip`;
            }
            my $ipn = inet_aton($ip); #we are ipv4 only, this is ok
            my $ipnum=unpack("N",$ipn);
            $ipnum= $ipnum | (2**(32-$maskbits))-1;
            my $bcastn = pack("N",$ipnum);
            my $bcastaddr = sockaddr_in(427,$bcastn);
            setsockopt($socket,0,IP_MULTICAST_IF,$ipn);
            $socket->send($packet,0,$ipv4sockaddr);
            $socket->send($packet,0,$bcastaddr);
        }
    }
}

sub get_interfaces {
        #TODO: AIX tolerance, no subprocess, include/exclude interface(s)
        my %ifacemap;
        my $payingattention=0;
        my $interface;
        my $keepcurrentiface;
        # AIX part
    if (xCAT::Utils->isAIX()) {
        $ip6support = 0;
        my $result = `ifconfig -a`;
        my @nics = $result =~ /(\w+\d+)\: flags=/g;
        my @adapter = split /\w+\d+:\s+flags=/, $result;
        for (my $i=0; $i<scalar(@adapter); $i++) {
            $_ = $adapter[$i+1];
            if ( !($_ =~ /LOOPBACK/ ) and
                   $_ =~ /UP(,|>)/ and
                   $_ =~ /BROADCAST/ ) {
                my @ip = split /\n/;
                for my$entry  ( @ip ) {
                    if ( $entry =~ /broadcast\s+/ and $entry =~ /^\s*inet\s+(\d+\.\d+\.\d+\.\d+)/) {
                        my $tmpip = $1;
                        if($entry =~ /netmask\s+(0x\w+)/) {
                            my $mask = hex($1);
                            my $co = 31;
                            my $count = 0;
                            while ($co+1) {
                                if((($mask&(2**$co))>>$co) == 1) {
                                    $count++;
                                }
                                $co--;
                            }
                            $tmpip = $tmpip.'/'.$count;
                        }
                        push @{$ifacemap{$nics[$i]}->{ipv4addrs}},$tmpip;
                        if( $nics[$i]=~ /\w+(\d+)/){
                        $ifacemap{$nics[$i]}->{scopeidx} = $1+2;
                       }
                    }
                }
            }
        }
    } else {
        my @ipoutput = `ip addr`;
        foreach my $line (@ipoutput) {
            if ($line =~ /^\d/) { # new interface, new context..
                if ($interface and not $keepcurrentiface) {
                    #don't bother reporting unusable nics
                    delete $ifacemap{$interface};
                }
                $keepcurrentiface=0;
                unless ($line =~ /MULTICAST/) { #don't care if it isn't multicast capable
                    $payingattention=0;
                    next;
                }
                $payingattention=1;
                $line =~ /^([^:]*): ([^:]*):/;
                $interface=$2;
                $ifacemap{$interface}->{scopeidx}=$1;
            }
            unless ($payingattention) { next; } #don't think about lines unless in context of paying attention.
            if ($line =~ /inet/) {
                $keepcurrentiface=1;
            }
            if ($line =~ /\s+inet\s+(\S+)\s/) { #got an ipv4 address, store it
                push @{$ifacemap{$interface}->{ipv4addrs}},$1;
            }
        }
    }
    return \%ifacemap;
}
# discovery is "service request", rfc 2608
#     0                   1                   2                   3
#     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |       Service Location header (function = SrvRqst = 1)        |
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |      length of <PRList>       |        <PRList> String        \
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |   length of <service-type>    |    <service-type> String      \
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |    length of <scope-list>     |     <scope-list> String       \
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |  length of predicate string   |  Service Request <predicate>  \
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |  length of <SLP SPI> string   |       <SLP SPI> String        \
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
sub generate_service_request {
    my %args = @_;
    my $srvtype = $args{SrvType};
    my $scope = "DEFAULT";
    if ($args{Scopes}) { $scope = $args{Scopes}; }
    my $prlist = $gprlist;
    my $prlength = length($prlist);
    my $packet = pack("C*",($prlength>>8),($prlength&0xff));
    $packet .= $prlist;
    my $length = length($srvtype);
    $packet .= pack("C*",($length>>8),($length&0xff));
    $packet .= $srvtype;
    $length = length($scope);
    $packet .= pack("C*",($length>>8),($length&0xff));
    $packet .= $scope;
    #no ldap predicates, and no auth, so zeroes..
    $packet .= pack("C*",0,0,0,0);
    $packet .= pack("C*",0,2,0,0,0,0,0,0,0,0);
    my $extoffset = length($srvtype)+length($scope)+length($prlist)+10;
    my $header = genslpheader($packet,Multicast=>1,FunctionId=>1,ExtOffset=>$extoffset);
    $xid_to_srvtype_map{$xid++}=$srvtype;
    return $packet = $header.$packet;
}
# SLP header from RFC 2608
#     0                   1                   2                   3
#     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |    Version    |  Function-ID  |            Length             |
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    | Length, contd.|O|F|R|       reserved          |Next Ext Offset|
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |  Next Extension Offset, contd.|              XID              |
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#    |      Language Tag Length      |         Language Tag          \
#    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
sub removeslpheader {
    my $packet = shift;
    my %parsedheader;
    my @payload = unpack("C*",$packet);
    $parsedheader{Version} = shift @payload;
    $parsedheader{FunctionId} = shift @payload;
    splice(@payload,0,3); #remove length
    splice(@payload,0,2); #TODO: parse flags
    my $nextoffset = ((shift @payload)<<16)+((shift @payload)<<8)+(shift @payload);
    $parsedheader{Xid} = ((shift @payload)<<8)+(shift @payload);
    my $langlen = ((shift @payload)<<8)+(shift @payload);
    $parsedheader{lang} = pack("C*",splice(@payload,0,$langlen));
    $parsedheader{payload} = pack("C*",@payload);
    if ($nextoffset != 0) {
            #correct offset since header will be removed
            $parsedheader{currentoffset} = 14+$langlen;
            $parsedheader{extoffset}=$nextoffset;
    }
    return \%parsedheader;
}



sub genslpheader {
    my $packet = shift;
    my %args = @_;
    my $flaghigh=0;
    my $flaglow=0; #this will probably never ever ever change
    if ($args{Multicast}) { $flaghigh |= 0x20; }
    my $extoffset=0;
    if ($args{ExtOffset}) {
            $extoffset = $args{ExtOffset}+16;
    }
    my @extoffset=(($extoffset>>16),(($extoffset>>8)&0xff),($extoffset&0xff));
    my $length = length($packet)+16; #our header is 16 bytes due to lang tag invariance
    if ($length > 1400) { die "Overflow not supported in xCAT SLP"; }
    return pack("C*",2, $args{FunctionId}, ($length >> 16), ($length >> 8)&0xff, $length&0xff, $flaghigh, $flaglow,@extoffset,$xid>>8,$xid&0xff,0,2)."en";
}

unless (caller) {
    #time to provide unit testing/example usage
    #somewhat fancy invocation with multiple services and callback for
    #results on-the-fly
    require Data::Dumper;
    Data::Dumper->import();
    my $srvtypes = ["service:management-hardware.IBM:chassis-management-module","service:management-hardware.IBM:integrated-management-module2","service:management-hardware.IBM:management-module","service:management-hardware.IBM:cec-service-processor"];
    xCAT::SLP::dodiscover(SrvTypes=>$srvtypes,Callback=>sub { print Dumper(@_) });
    #example 2: simple invocation of a single service type
    $srvtypes = "service:management-hardware.IBM:chassis-management-module";
    print Dumper(xCAT::SLP::dodiscover(SrvTypes=>$srvtypes));
    #TODO: pass-in socket and not wait inside SLP.pm example
}
###########################################
# Parse the slp resulte data
###########################################
sub handle_new_slp_entity {
    my $data = shift;
    delete $data->{sockaddr}; #won't need it
    my $mac = get_mac_for_addr($data->{peername});
    unless ($mac) { return; }
    $searchmacs{$mac} = $data;
}
###########################################
# Get mac addresses
###########################################
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

###########################################
# Get ipv4 mac addresses
###########################################
sub get_ipv4_neighbors {
    if (xCAT::Utils->isAIX()) {
        my @ipdata = `arp -a`;
        %ip6neigh=();
        for my $entry (@ipdata) {
            if ($entry =~ /(\d+\.\d+\.\d+\.\d+)/) {
                my $ip = $1;
                #if ($entry =~ /at (\w+\:\w+\:\w+\:\w+\:\w+\:\w+)/) {
                #    $ip4neigh{$ip}=$1;
                if ($entry =~ /at (\w+)\:(\w+)\:(\w+)\:(\w+)\:(\w+)\:(\w+)/) {
                     #$ip4neigh{$ip}=$1.$2.$3.$4.$5.$6;
                    $ip4neigh{$ip}=sprintf("%02s%02s%02s%02s%02s%02s",$1,$2,$3,$4,$5,$6);
                }
            }
        }
    } else {
        #TODO: something less 'hacky'
        my @ipdata = `ip -4 neigh`;
        %ip6neigh=();
        foreach (@ipdata) {
            if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
                $ip4neigh{$1}=$2;
            }
        }
    }
}



###########################################
# Get ipv6 mac addresses
###########################################
sub get_ipv6_neighbors {
    #TODO: something less 'hacky'
    my @ipdata = `ip -6 neigh`;
    %ip6neigh=();
    foreach (@ipdata) {
        if (/^(\S*)\s.*lladdr\s*(\S*)\s/) {
            $ip6neigh{$1}=$2;
        }
    }
}

sub send_message {
    my $callback = shift;
    my $ecode   = shift;
    my $msg     = shift;
    my %output;
    $output{errorcode} = $ecode;
    $output{data} = $msg;
    $callback->( \%output );
}
1;


