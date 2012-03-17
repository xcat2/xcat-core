package xCAT::SLP;
use Carp;
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
	unless ($args{SrvTypes}) { croak "SrvTypes argument is required for xCAT::SLP::Dodiscover"; }
   my @srvtypes;
	if (ref $args{SrvTypes}) {
		@srvtypes = @{$args{SrvTypes}};
	} else {
		@srvtypes = split /,/,$args{SrvTypes};
	}
	foreach my $srvtype (@srvtypes) {
		dodiscover_single(%args,SrvType=>$srvtype);
	}
}
sub dodiscover_single {
	my %args = @_;
	my $packet = gendiscover(%args);
	my @interfaces = get_interfaces(%args);
	my $socket;
	if ($args{'socket'}) {
		$socket = $args{'socket'};
	} elsif ($ip6support) {
		$socket = IO::Socket::INET6->new(Proto => 'udp');
	} else {
		die "TODO: SLP without ipv6";
	}
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
		
