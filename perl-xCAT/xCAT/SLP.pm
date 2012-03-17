package xCAT::SLP;
use Carp;
use IO::Select;
use strict;
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
	unless ($args{'socket'}) {
		if ($ip6support) {
			$args{'socket'} = IO::Socket::INET6->new(Proto => 'udp');
		} else {
			croak "TODO: SLP without ipv6";
		}
	}
	unless ($args{SrvTypes}) { croak "SrvTypes argument is required for xCAT::SLP::Dodiscover"; }
   my @srvtypes;
	if (ref $args{SrvTypes}) {
		@srvtypes = @{$args{SrvTypes}};
	} else {
		@srvtypes = split /,/,$args{SrvTypes};
	}
	foreach my $srvtype (@srvtypes) {
		send_discover_single(%args,SrvType=>$srvtype);
	}
	unless ($args{NoWait}) { #in nowait, caller owns the responsibility..
		#by default, report all respondants within 3 seconds:
		my %rethash;
		my $waitforsocket = IO::Select->new();
		$waitforsocket->add($args{'socket'});
		my $deadline=time()+3;
		while ($deadline > time()) {
			while ($waitforsocket->can_read(1)) {
				my $slppacket;
				my $peer = $args{'socket'}->recv($slppacket,1400);
				my( $port,$flow,$ip6n,$scope) = Socket6::unpack_sockaddr_in6_all($peer);
				my $peername = Socket6::inet_ntop(Socket6::AF_INET6(),$ip6n);
				if ($rethash{$peername}) {
					next; #got a dupe, discard
				}
				my $result = process_slp_packet(packet=>$slppacket,sockaddr=>$peer,'socket'=>$args{'socket'});
				if ($result) {
					$result->{peername} = $peername;
					$result->{scopeid} = $scope;
					$result->{sockaddr} = $peer;
					$rethash{$peername.'%'.$scope} = $result;
					if ($args{Callback}) {
						$args{Callback}->($result);
					}
				}
			}
		}
		return \%rethash;
	}
}

sub process_slp_packet {
	my %args = @_;
	my $sockaddy = $args{sockaddr};
	my $socket = $args{'socket'};
	my $packet = $args{packet};
	my $parsedpacket = removeslpheader($packet);
	if ($parsedpacket->{FunctionId} == 2) {#Service Reply
		$parsedpacket->{service_urls} = parse_service_reply($parsedpacket->{payload});
		unless (scalar @{$parsedpacket->{service_urls}}) { return undef; }
		send_attribute_request('socket'=>$socket,url=>$parsedpacket->{service_urls}->[0],sockaddr=>$sockaddy);
		return undef;
	} elsif ($parsedpacket->{FunctionId} == 7) { #attribute reply
		$parsedpacket->{attributes} = parse_attribute_reply($parsedpacket->{payload});
		delete $parsedpacket->{payload};
		return $parsedpacket;
	} else {
		return undef;
	}
}

sub parse_attribute_reply {
	my $contents = shift;
	my @payload = unpack("C*",$contents);
	if ($payload[0] != 0 or $payload[1] != 0) {
		return [];
	}
	my $attrlength = ($payload[2]<<8)+$payload[3];
	splice(@payload,0,4);
	my @attributes = splice(@payload,0,$attrlength);
	my $attrstring = pack("C*",@attributes);
	my %attribs;
	#now we have a string...
	while ($attrstring) {
		if ($attrstring =~ /^\(/) {
			$attrstring =~ s/([^)]*\)),?//;
			my $attrib = $1;
			$attrib =~ s/^\(//;
			$attrib =~ s/\),?$//;
			$attrib =~ s/=(.*)$//;
			$attribs{$attrib}=[];
			if ($1) {
				my $valstring = $1;
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
sub send_attribute_request {
	my %args = @_;
	my $packet  = pack("C*",0,0); #no prlist
	my $service = $args{url};
	$service =~ s!://.*!!;
	my $length = length($service);
	$packet .= pack("C*",($length>>8),($length&0xff));
	$packet .= $service.pack("C*",0,7).'DEFAULT'.pack("C*",0,0,0,0);
	my $header = genslpheader($packet,FunctionId=>6);
	$args{'socket'}->send($header.$packet,0,$args{sockaddry});
}
	

sub parse_service_reply {
	my $packet = shift;
	my @reply = unpack("C*",$packet);
	if ($reply[0] != 0 or $reply[1] != 0) {
		return ();
	}
	my @urls;
	my $numurls = ($reply[2]<<8)+$reply[3];
	splice (@reply,0,4);
	while ($numurls--) {
		push @urls,extract_next_url(\@reply);
	}
	return \@urls;
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
		
sub send_discover_single {
	my %args = @_;
	my $packet = gendiscover(%args);
	my @interfaces = get_interfaces(%args);
	my $socket = $args{'socket'};
	my $v6addr;
	if ($ip6support) {
		my $hash=getmulticasthash($args{SrvType});
		my $target = "ff02::1:$hash";
		my ($fam, $type, $proto, $name);
		($fam, $type, $proto, $v6addr, $name) = 
		   Socket6::getaddrinfo($target,"svrloc",Socket6::AF_INET6(),SOCK_DGRAM,0);
	}
	foreach my $iface (@interfaces) {
		if ($ip6support) {
			setsockopt($socket,Socket6::IPPROTO_IPV6(),IPV6_MULTICAST_IF,pack("I",$iface));
			$socket->send($packet,0,$v6addr);
		}
		#TODO: IPv4 support
#		setsockopt($socket,IPPROTO_IP,IP_MULTICAST_IF,
	}
}

sub get_interfaces {
	#TODO: AIX tolerance, no subprocess, include/exclude interface(s)
	my @ipoutput = `ip link`;
	my @ifaceoutput = grep(/MULTICAST/,@ipoutput);
	my @interfaces;
	foreach (@ifaceoutput) {
		chomp;
		s/:.*//;
		push @interfaces,$_;
	}
	return @interfaces;
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
sub gendiscover {
	my %args = @_;
	my $srvtype = $args{SrvType};
	my $scope = "DEFAULT";
	if ($args{Scopes}) { $scope = $args{Scopes}; }
	my $packet = pack("C*",0,0); #start with PRList, we have no prlist so zero
	#TODO: actually accumulate PRList, particularly between IPv4 and IPv6 runs
	my $length = length($srvtype);
	$packet .= pack("C*",($length>>8),($length&0xff));
	$packet .= $srvtype;
	$length = length($scope);
	$packet .= pack("C*",($length>>8),($length&0xff));
	$packet .= $scope;
	#no ldap predicates, and no auth, so zeroes..
	$packet .= pack("C*",0,0,0,0);
	my $header = genslpheader($packet,Multicast=>1,FunctionId=>1);
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
	splice(@payload,0,3); #ignore next ext offset for now
	$parsedheader{Xid} = ((shift @payload)<<8)+(shift @payload);
	my $langlen = ((shift @payload)<<8)+(shift @payload);
	$parsedheader{lang} = pack("C*",splice(@payload,0,$langlen)); 
	$parsedheader{payload} = pack("C*",@payload);
	return \%parsedheader;
}
	
	
	
sub genslpheader {
	my $packet = shift;
	my %args = @_;
	my $xid = rand(65535);
	my $flaghigh=0;
	my $flaglow=0; #this will probably never ever ever change
	if ($args{Multicast}) { $flaghigh |= 0x20; }
	my $length = length($packet)+16; #our header is 16 bytes due to lang tag invariance
	if ($length > 1400) { die "Overflow not supported in xCAT SLP"; }
	return pack("C*",2, $args{FunctionId}, ($length >> 16), ($length >> 8)&0xff, $length&0xff, $flaghigh, $flaglow,0,0,0,$xid>>8,$xid&0xff,0,2)."en";
}
		
unless (caller) { 
	#time to provide unit testing/example usage
	#somewhat fancy invocation with multiple services and callback for
	#results on-the-fly
	require Data::Dumper;
	Data::Dumper->import();
	my $srvtypes = ["service:management-hardware.IBM:chassis-management-module","service:management-hardware.IBM:management-module"];
	xCAT::SLP::dodiscover(SrvTypes=>$srvtypes,Callback=>sub { print Dumper(@_) });
	#example 2: simple invocation of a single service type
	$srvtypes = "service:management-hardware.IBM:chassis-management-module";
	print Dumper(xCAT::SLP::dodiscover(SrvTypes=>$srvtypes));
	#TODO: pass-in socket and not wait inside SLP.pm example
}
1;
