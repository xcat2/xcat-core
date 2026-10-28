#!/usr/bin/env perl
# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::NetworkUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
    unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";
use POSIX qw(ceil);
use File::Path;
use Math::BigInt;
use Socket;
use xCAT::GlobalDef;
use Sys::Hostname;
use strict;
use warnings "all";
my $socket6support = eval { require Socket6 };
my $core_socket_resolver = defined(&Socket::getaddrinfo)
  && defined(&Socket::getnameinfo)
  && defined(&Socket::inet_pton)
  && eval {
    my @required_constants = (
        Socket::AF_INET6(),
        Socket::AI_NUMERICHOST(),
        Socket::NI_NUMERICHOST(),
    );
    scalar(@required_constants) == 3;
  };

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  format_host_port
  format_uri_host
  getipaddr
  my_ip_facing_family
  parse_host_port
);

my $utildata;    #data to persist locally

#--------------------------------------------------------------------------------

=head1    xCAT::NetworkUtils

=head2    Package Description

This program module file, is a set of network utilities used by xCAT commands.

=cut

#-------------------------------------------------------------

#-------------------------------------------------------------------------------

=head3  getNodeDomains

		Gets the network domain for a list of nodes

		The domain value comes from the network definition
		associated with the node ip address.

		If the network domain is not set then the default is to
		use the site.domain value

    Arguments:
       list of nodes
    Returns:
		error - undef
		success - hash ref of domains for each node
    Globals:
		$::VERBOSE
    Error:
    Example:
     my $nodedomains = xCAT::NetworkUtils->getNodeDomains(\@nodes, $callback);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub getNodeDomains()
{
    my $class = shift;
    my $nodes = shift;

    my @nodelist = @$nodes;
    my %nodedomains;

    # Get the network info for each node
    my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodelist);

    # get the site domain value
    my @domains    = xCAT::TableUtils->get_site_attribute("domain");
    my $sitedomain = $domains[0];

    # for each node - set hash value to network domain or default
    #		to site domain
    foreach my $node (@nodelist) {
        unless (defined($node)) { next; }
        if (defined($nethash{$node}) && $nethash{$node}{domain}) {
            $nodedomains{$node} = $nethash{$node}{domain};
        } else {
            $nodedomains{$node} = $sitedomain;
        }
    }

    return \%nodedomains;
}

#-------------------------------------------------------------------------------

=head3  gethostnameandip
    Works for both IPv4 and IPv6.
    Takes either a host name or an IP address string
    and performs a lookup on that name,
    returns an array with two elements: the hostname, the ip address
    if the host name or ip address can not be resolved,
    the corresponding element in the array will be undef
    Arguments:
       hostname or ip address
    Returns: the hostname and the ip address
    Globals:

    Error:
        none
    Example:
        my ($host, $ip) = xCAT::NetworkUtils->gethostnameandip($iporhost);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub gethostnameandip()
{
    my ($class, $iporhost) = @_;

    if (($iporhost =~ /\d+\.\d+\.\d+\.\d+/) || ($iporhost =~ /:/))   #ip address
    {
        return (xCAT::NetworkUtils->gethostname($iporhost), $iporhost);
    }
    else                                                             #hostname
    {
        return ($iporhost, xCAT::NetworkUtils->getipaddr($iporhost));
    }
}

#-------------------------------------------------------------------------------

=head3  gethostname
    Works for both IPv4 and IPv6.
    Takes an IP address string and performs a lookup on that name,
    returns the hostname of the ip address
    if the ip address can not be resolved, returns undef
    Arguments:
       ip address
    Returns: the hostname
    Globals:
        cache: %::iphosthash
    Error:
        none
    Example:
        my $host = xCAT::NetworkUtils->gethostname($ip);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub gethostname()
{
    my ($class, $iporhost) = @_;

    if (!defined($iporhost))
    {
        return undef;
    }

    if (ref($iporhost) eq 'ARRAY')
    {
        $iporhost = @{$iporhost}[0];
        if (!$iporhost)
        {
            return;
        }
    }

    if (($iporhost !~ /\d+\.\d+\.\d+\.\d+/) && ($iporhost !~ /:/))
    {
        #why you do so? pass in a hostname and only want a hostname??
        return $iporhost;
    }

    #cache, do not lookup DNS each time
    if (defined($::iphosthash{$iporhost}) && $::iphosthash{$iporhost})
    {
        return $::iphosthash{$iporhost};
    }
    else
    {
        if ($socket6support) # the getaddrinfo and getnameinfo supports both IPv4 and IPv6
        {
            my ($family, $socket, $protocol, $ip, $name) = Socket6::getaddrinfo($iporhost, 0, AF_UNSPEC, SOCK_STREAM, 6); #specifically ask for TCP capable records, maximizing chance of no more than one return per v4/v6
            my $host = (Socket6::getnameinfo($ip))[0];
            if ($host eq $iporhost)    # can not resolve
            {
                return undef;
            }
            if ($host)
            {
                $host =~ s/\..*//;     #short hostname
            }
            return $host;
        }
        else
        {
            #it is possible that no Socket6 available,
            #but passing in IPv6 address, such as ::1 on loopback
            if ($iporhost =~ /:/)
            {
                return undef;
            }
            my $hostname = gethostbyaddr(inet_aton($iporhost), AF_INET);
            if ($hostname) {
                $hostname =~ s/\..*//;    #short hostname
            }
            return $hostname;
        }
    }
}

#-------------------------------------------------------------------------------

=head3  getipaddr
    Works for both IPv4 and IPv6.
    Takes a hostname string and performs a lookup on that name,
    returns the the ip address of the hostname
    if the hostname can not be resolved, returns undef
    Arguments:
       hostname
       Optional:
        GetNumber=>1 (return the address as a BigInt instead of readable string)
        GetAllAddresses=>1 (return the )
        OnlyV6=>1 ()
        OnlyV4=> ()
    Returns: ip address
    Globals:
        cache: %::hostiphash
    Error:
        none
    Example:
        my $ip = xCAT::NetworkUtils->getipaddr($hostname);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub getipaddr
{
    my $iporhost = shift;
    if ($iporhost eq 'xCAT::NetworkUtils') {    #was called with -> syntax
        $iporhost = shift;
    }
    my %extraarguments = @_;

    if (!defined($iporhost))
    {
        return undef;
    }

    if (ref($iporhost) eq 'ARRAY')
    {
        $iporhost = @{$iporhost}[0];
        if (!$iporhost)
        {
            return undef;
        }
    }

    #go ahead and do the reverse lookup on ip, useful to 'frontend' aton/pton and also to
    #spit out a common abbreviation if leading zeroes or using different ipv6 presentation rules
    #if ($iporhost and ($iporhost =~ /\d+\.\d+\.\d+\.\d+/) || ($iporhost =~ /:/))
    #{
    #    #pass in an ip and only want an ip??
    #    return $iporhost;
    #}
    my $isip=0;
    if ($iporhost and ($iporhost =~ /\d+\.\d+\.\d+\.\d+/) || ($iporhost =~ /:/)){
        $isip=1;
    }


#print "============================\n";
#print Dumper(\%::hostiphash);
#print "\n";
#print Dumper(\%extraarguments);
#print "\n";
#print "iporhost=$iporhost";
#print "\n";
#print "============================\n";

    # Keep family-specific lookups out of the legacy cache.  Otherwise an
    # OnlyV6 lookup can make a later OnlyV4 lookup return an IPv6 address (and
    # vice versa).
    my $cache_suffix = $extraarguments{OnlyV6} ? '_v6'
      : $extraarguments{OnlyV4}                ? '_v4'
      :                                          '';
    my $host_cache_key   = 'hostip' . $cache_suffix;
    my $number_cache_key = 'Number' . $cache_suffix;

    #cache, do not lookup DNS each time
    #
    # An unrestricted lookup asks for AF_UNSPEC and caches whatever came back, which
    # on a dual-stack host is the AAAA record. Serving that to an OnlyV4 caller gives
    # it an IPv6 address it cannot use: debian.pm renders nfsroot=<address>:<path>,
    # and nfsroot=2001:db8::1:/install does not parse.
    my $cached_v6 =
      defined($::hostiphash{$iporhost})
      && $::hostiphash{$iporhost}
      && $::hostiphash{$iporhost}{hostip}
      && $::hostiphash{$iporhost}{hostip} =~ /:/;
    if (
        ((not $extraarguments{OnlyV6}) and (not $extraarguments{GetAllAddresses}))
        and (not($extraarguments{OnlyV4} and $cached_v6))
        and defined($::hostiphash{$iporhost}) and $::hostiphash{$iporhost})
    {

        if($extraarguments{GetNumber} ) {
            if(defined($::hostiphash{$iporhost}{$number_cache_key})){
        #print "YYYYYYYYYY GetNumber Cache Hit!!!YYYYYYYYY\n";
                return $::hostiphash{$iporhost}{$number_cache_key};
            }
        } elsif(defined($::hostiphash{$iporhost}{$host_cache_key})) {
        #print "YYYYYYYYYY dns  Cache Hit!!!YYYYYYYYY\n";
            return $::hostiphash{$iporhost}{$host_cache_key};
        } elsif($cache_suffix && defined($::hostiphash{$iporhost}{hostip})) {
            my $cached_ip = $::hostiphash{$iporhost}{hostip};
            if (($extraarguments{OnlyV4} && xCAT::NetworkUtils->isIpaddr($cached_ip))
                || ($extraarguments{OnlyV6}
                    && $cached_ip =~ /:/
                    && xCAT::NetworkUtils->isValidIp($cached_ip)))
            {
                $::hostiphash{$iporhost}{$host_cache_key} = $cached_ip;
                return $cached_ip;
            }
        }
    }

    if ($socket6support) # the getaddrinfo and getnameinfo supports both IPv4 and IPv6
    {
        my @returns;
        my $reqfamily = AF_UNSPEC;
        if ($extraarguments{OnlyV6}) {
            $reqfamily = AF_INET6;
        } elsif ($extraarguments{OnlyV4}) {
            $reqfamily = AF_INET;
        }
        my @addrinfo;
        if($isip) {
            @addrinfo=Socket6::getaddrinfo($iporhost, 0, $reqfamily, SOCK_STREAM, 6,Socket6::AI_NUMERICHOST());
        }else{
            @addrinfo=Socket6::getaddrinfo($iporhost, 0, $reqfamily, SOCK_STREAM, 6);
        }
        # The resolver lists every address of the host, link-local included,
        # and the first one is what a caller that asked for no family gets.
        @addrinfo = _socket6_addrinfo_routable_first(@addrinfo);
        my ($family, $socket, $protocol, $ip, $name) = splice(@addrinfo, 0, 5);
        unless($reqfamily == AF_INET6){
            if($isip){
               if($name){
                   $::hostiphash{$iporhost}{$host_cache_key}=$name;
               }
            }elsif($ip){
                $::hostiphash{$iporhost}{$host_cache_key}=$ip;
            }
        }
        while ($ip)
        {
            if ($extraarguments{GetNumber}) { #return a BigInt for compare, e.g. for comparing ip addresses for determining if they are in a common network or range
                my $ip = (Socket6::getnameinfo($ip, Socket6::NI_NUMERICHOST()))[0];
                my $bignumber = Math::BigInt->new(0);
                foreach (unpack("N*", Socket6::inet_pton($family, $ip))) { #if ipv4, loop will iterate once, for v6, will go 4 times
                    $bignumber->blsft(32);
                    $bignumber->badd($_);
                }
                push(@returns, $bignumber);
                $::hostiphash{$iporhost}{$number_cache_key}=$returns[0];
                unless ($cache_suffix)
                {
                    my $family_key = $family == AF_INET6 ? 'Number_v6' : 'Number_v4';
                    $::hostiphash{$iporhost}{$family_key} = $bignumber
                      unless defined($::hostiphash{$iporhost}{$family_key});
                }
            } else {
                my $numeric_ip = (Socket6::getnameinfo($ip, Socket6::NI_NUMERICHOST()))[0];
                push @returns, $numeric_ip;
                $::hostiphash{$iporhost}{$host_cache_key}=$returns[0];
                unless ($cache_suffix)
                {
                    my $family_key = $family == AF_INET6 ? 'hostip_v6' : 'hostip_v4';
                    $::hostiphash{$iporhost}{$family_key} = $numeric_ip
                      unless defined($::hostiphash{$iporhost}{$family_key});
                }
            }
            if (scalar @addrinfo and $extraarguments{GetAllAddresses}) {
                ($family, $socket, $protocol, $ip, $name) = splice(@addrinfo, 0, 5);
            } else {
                $ip = 0;
            }
        }
        unless ($extraarguments{GetAllAddresses}) {
            return $returns[0];
        }
        return @returns;
    }
    elsif ($core_socket_resolver)
    {
        my $reqfamily = Socket::AF_UNSPEC();
        if ($extraarguments{OnlyV6}) {
            $reqfamily = Socket::AF_INET6();
        } elsif ($extraarguments{OnlyV4}) {
            $reqfamily = Socket::AF_INET();
        }

        my %hints = (
            family   => $reqfamily,
            socktype => Socket::SOCK_STREAM(),
            protocol => 6,
        );
        $hints{flags} = Socket::AI_NUMERICHOST() if $isip;

        my ($error, @addrinfo) = Socket::getaddrinfo($iporhost, 0, \%hints);
        if ($error)
        {
            return () if $extraarguments{GetAllAddresses};
            return;
        }

        # getaddrinfo returns every address of the host, link-local included,
        # and a caller that asked for no family takes the first one. Order the
        # entries the way prefer_routable_addresses orders their literals.
        @addrinfo = _addrinfo_routable_first(@addrinfo);

        my @returns;
        foreach my $address (@addrinfo)
        {
            my ($name_error, $numeric_ip) = Socket::getnameinfo(
                $address->{addr}, Socket::NI_NUMERICHOST()
            );
            next if $name_error || !defined($numeric_ip);

            if ($extraarguments{GetNumber})
            {
                my $packed = Socket::inet_pton($address->{family}, $numeric_ip);
                next unless defined($packed);
                my $bignumber = Math::BigInt->new(0);
                foreach (unpack("N*", $packed))
                {
                    $bignumber->blsft(32);
                    $bignumber->badd($_);
                }
                push @returns, $bignumber;
                $::hostiphash{$iporhost}{$number_cache_key} = $returns[0];
                unless ($cache_suffix)
                {
                    my $family_key = $address->{family} == Socket::AF_INET6()
                      ? 'Number_v6' : 'Number_v4';
                    $::hostiphash{$iporhost}{$family_key} = $bignumber
                      unless defined($::hostiphash{$iporhost}{$family_key});
                }
            }
            else
            {
                push @returns, $numeric_ip;
                $::hostiphash{$iporhost}{$host_cache_key} = $returns[0];
                unless ($cache_suffix)
                {
                    my $family_key = $address->{family} == Socket::AF_INET6()
                      ? 'hostip_v6' : 'hostip_v4';
                    $::hostiphash{$iporhost}{$family_key} = $numeric_ip
                      unless defined($::hostiphash{$iporhost}{$family_key});
                }
            }
            last unless $extraarguments{GetAllAddresses};
        }

        unless ($extraarguments{GetAllAddresses}) {
            return $returns[0];
        }
        return @returns;
    }
    else
    {
        #return inet_ntoa(inet_aton($iporhost))
        #TODO, what if no scoket6 support, but passing in a IPv6 hostname?
        if ($extraarguments{OnlyV6} || $iporhost =~ /:/) {    #ipv6
            return undef;

            #die "Attempt to process IPv6 address, but system does not have requisite IPv6 perl support";
        }
        my $packed_ip;
        $iporhost and $packed_ip = inet_aton($iporhost);
        if (!$packed_ip)
        {
            return undef;
        }

        my $myip=inet_ntoa($packed_ip);

        unless($isip) {
            $::hostiphash{$iporhost}{$host_cache_key}=$myip;
            unless ($cache_suffix)
            {
                $::hostiphash{$iporhost}{hostip_v4}=$myip
                  unless defined($::hostiphash{$iporhost}{hostip_v4});
            }
        }

        if ($extraarguments{GetNumber}) { #only 32 bits, no for loop needed.
            my $number=Math::BigInt->new(unpack("N*", $packed_ip));
            $::hostiphash{$iporhost}{$number_cache_key}=$number;
            unless ($cache_suffix)
            {
                $::hostiphash{$iporhost}{Number_v4}=$number
                  unless defined($::hostiphash{$iporhost}{Number_v4});
            }
            return $number;
        }

        return $myip;
    }
}

#-------------------------------------------------------------------------------

=head3  clearcache
    Workaround: Clear the IP address cache in case that the long running process
    (discovery/install monitor) could work as normal when the node's IP address
    is changed.
    Globals:
        cache: %::hostiphash
    Error:
        none
    Example:
        xCAT::NetworkUtils->clearcache();
=cut

#-------------------------------------------------------------------------------
sub clearcache
{
    undef %::hostiphash;
}

#-------------------------------------------------------------------------------

=head3  unmap_v4mapped_addr
    Reduce a packed IPv4-mapped IPv6 address to its 4 IPv4 bytes, so a caller
    can ask gethostbyaddr for AF_INET.
    Arguments:
       a packed address, as IO::Socket peeraddr returns
    Returns:
       the 4-byte IPv4 address when the argument is a 16-byte ::ffff:a.b.c.d,
       otherwise the argument unchanged
    Globals:
    Error:
        none
    Example:
        my $addr = xCAT::NetworkUtils::unmap_v4mapped_addr($conn->peeraddr);
    Comments:
        A real IPv6 address keeps all 16 bytes. Truncating one would offer
        gethostbyaddr its last 4 bytes as an IPv4 address.
=cut

#-------------------------------------------------------------------------------
sub unmap_v4mapped_addr {
    my ($addr) = @_;
    return $addr unless (defined($addr) and length($addr) == 16);
    return $addr unless (substr($addr, 0, 12) eq ("\0" x 10) . "\xff\xff");
    return substr($addr, 12, 4);
}

#-------------------------------------------------------------------------------

=head3  linklocaladdr
    Only for IPv6.
    Takes a mac address, calculate the IPv6 link local address
    Arguments:
       mac address
    Returns:
       ipv6 link local address. returns undef if passed in a invalid mac address
    Globals:
    Error:
        none
    Example:
        my $linklocaladdr = xCAT::NetworkUtils->linklocaladdr($mac);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub linklocaladdr {
    my ($class, $mac) = @_;
    $mac = lc($mac);
    my $localprefix = "fe80";

    my ($m1, $m2, $m3, $m6, $m7, $m8);

    # mac address can be 00215EA376B0 or 00:21:5E:A3:76:B0
    if ($mac =~ /^([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2})$/)
    {
        ($m1, $m2, $m3, $m6, $m7, $m8) = ($1, $2, $3, $4, $5, $6);
    }
    else
    {
        #not a valid mac address
        return undef;
    }
    my ($m4, $m5) = ("ff", "fe");

    #my $bit = (int $m1) & 2;
    #if ($bit) {
    #   $m1 = $m1 - 2;
    #} else {
    #   $m1 = $m1 + 2;
    #}
    $m1 = hex($m1);
    $m1 = $m1 ^ 2;
    $m1 = sprintf("%x", $m1);

    $m1 = $m1 . $m2;
    $m3 = $m3 . $m4;
    $m5 = $m5 . $m6;
    $m7 = $m7 . $m8;

    my $laddr = join ":", $m1, $m3, $m5, $m7;
    $laddr = join "::", $localprefix, $laddr;

    return $laddr;
}


#-------------------------------------------------------------------------------

=head3  ishostinsubnet
    Works for both IPv4 and IPv6.
    Takes an ip address, the netmask and a subnet,
    chcek if the ip address is in the subnet
    Arguments:
       ip address, netmask, subnet
    Returns:
       1 - if the ip address is in the subnet
       0 - if the ip address is NOT in the subnet
    Globals:
    Error:
        none
    Example:
        if(xCAT::NetworkUtils->ishostinsubnet($ip, $netmask, $subnet);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub ishostinsubnet{
    my ($class, $ip, $mask, $subnet) = @_;

    #safe guard
    if (!defined($ip) || !defined($mask) || !defined($subnet))
    {
        return 0;
    }

    my $maskType=0;

    #CIDR notation supported
    if ($subnet && ($subnet =~ /\//)) {
        ($subnet, $mask) = split /\//, $subnet, 2;
        $subnet =~ s/\/.*$//;
        $maskType=1;
    }elsif ($mask) {
        if ($mask =~ /\//) {
            $mask =~ s/^\///;
            $maskType=1;
        } elsif($mask =~ /^0x/i ) {
            $maskType=2;
        }
    }

    my $ret=xCAT::NetworkUtils::isInSameSubnet( $ip, $subnet, $mask, $maskType);
    if(defined $ret and $ret==1){
        return 1;
    }else{
        return 0;
    }
}

sub ishostinsubnet_orig {
    my ($class, $ip, $mask, $subnet) = @_;

    #safe guard
    if (!defined($ip) || !defined($mask) || !defined($subnet))
    {
        return 0;
    }

    my $numbits = 32;
    if ($ip =~ /:/) {    #ipv6
        $numbits = 128;
    }
    if ($mask) {
        if ($mask =~ /\//) {
            $mask =~ s/^\///;
            $mask = Math::BigInt->new("0b" . ("1" x $mask) . ("0" x ($numbits - $mask)));
        } else {
            $mask = getipaddr($mask, GetNumber => 1);
        }
    } else {             #CIDR notation supported
        if ($subnet && ($subnet =~ /\//)) {
            ($subnet, $mask) = split /\//, $subnet, 2;
            $mask = Math::BigInt->new("0b" . ("1" x $mask) . ("0" x ($numbits - $mask)));
        } else {
            die "ishostinsubnet must either be called with a netmask or CIDR /bits notation";
        }
    }
    if ($subnet && ($subnet =~ /\//))    #remove CIDR suffix from subnet
    {
        $subnet =~ s/\/.*$//;
    }
    $ip     = getipaddr($ip,     GetNumber => 1);
    $subnet = getipaddr($subnet, GetNumber => 1);
    $ip &= $mask;
    if ($ip && $subnet && ($ip == $subnet)) {
        return 1;
    } else {
        return 0;
    }
}

#-----------------------------------------------------------------------------

=head3 setup_ip_forwarding

    Sets up ip forwarding on localhost

=cut

#-----------------------------------------------------------------------------
sub setup_ip_forwarding
{
    my ($class, $enable) = @_;
    if (xCAT::Utils->isLinux()) {
        my $conf_file = "/etc/sysctl.conf";
        `grep "net.ipv4.ip_forward" $conf_file`;
        if ($? == 0) {
`sed -i "s/^[[:space:]]*net[.]ipv4[.]ip_forward[[:space:]]*=[[:space:]]*.*/net.ipv4.ip_forward = $enable/" $conf_file`;
`sed -i "s/^#net.ipv4.ip_forward *= *.*/net.ipv4.ip_forward = $enable/" $conf_file`; #debian/ubuntu have different default format
        } else {
            `echo "net.ipv4.ip_forward = $enable" >> $conf_file`;
        }
        `sysctl -e -p $conf_file`;    # workaround for redhat bug 639821
    }
    else
    {
        `no -o ipforwarding=$enable`;
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3 setup_ipv6_forwarding

    Sets up ipv6 forwarding on localhost

=cut

#-----------------------------------------------------------------------------
sub setup_ipv6_forwarding
{
    my ($class, $enable) = @_;
    if (xCAT::Utils->isLinux()) {
        my $conf_file = "/etc/sysctl.conf";
        `grep "net.ipv6.conf.all.forwarding" $conf_file`;
        if ($? == 0) {
`sed -i "s/^net.ipv6.conf.all.forwarding = .*/net.ipv6.conf.all.forwarding = $enable/" $conf_file`;
        } else {
            `echo "net.ipv6.conf.all.forwarding = $enable" >> $conf_file`;
        }
        `sysctl -e -p $conf_file`;
    }
    else
    {
        `no -o ip6forwarding=$enable`;
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3  prefixtomask
    Convert the IPv6 prefix length(e.g. 64) to the netmask(e.g. ffff:ffff:ffff:ffff:0000:0000:0000:0000).
    Till now, the netmask format ffff:ffff:ffff:: only works for AIX NIM

    Arguments:
       prefix length
    Returns:
       netmask - netmask like ffff:ffff:ffff:ffff:0000:0000:0000:0000
       0 - if the prefix length is not correct
    Globals:
    Error:
        none
    Example:
        my #netmask = xCAT::NetworkUtils->prefixtomask($prefixlength);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub prefixtomask {
    my ($class, $prefixlength) = @_;

    if (($prefixlength < 1) || ($prefixlength > 128))
    {
        return 0;
    }

    my $number = Math::BigInt->new("0b" . ("1" x $prefixlength) . ("0" x (128 - $prefixlength)));
    my $mask = $number->as_hex();
    $mask =~ s/^0x//;
    $mask =~ s/(....)/$1/g;
    return $mask;
}

#-------------------------------------------------------------------------------

=head3  my_ip_in_subnet
    Get the facing ip for some specific network

    Arguments:
       net - subnet, such as 192.168.0.01
       mask - netmask, such as 255.255.255.0
    Returns:
       facing_ip - The local ip address in the subnet,
                   returns undef if no local ip address is in the subnet
    Globals:
    Error:
        none
    Example:
        my $facingip = xCAT::NetworkUtils->my_ip_in_subnet($net, $mask);
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub my_ip_in_subnet
{
    my ($class, $net, $mask) = @_;

    if (!$net || !$mask)
    {
        return undef;
    }

    my $fmask = xCAT::NetworkUtils::formatNetmask($mask, 0, 1);

    my $localnets = xCAT::NetworkUtils->my_nets();

    return $localnets->{"$net\/$fmask"};
}

#-------------------------------------------------------------------------------

=head3  ip_forwarding_enabled
    Check if the ip_forward enabled on the system

    Arguments:
    Returns:
       1 - The ip_forwarding is eanbled
       0 - The ip_forwarding is not eanbled
    Globals:
    Error:
        none
    Example:
        if(xCAT::NetworkUtils->ip_forwarding_enabled())
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub ip_forwarding_enabled
{

    my $enabled;
    if (xCAT::Utils->isLinux())
    {
        $enabled = `sysctl -n net.ipv4.ip_forward`;
        chomp($enabled);
    }
    else
    {
        $enabled = `no -o ipforwarding`;
        chomp($enabled);
        $enabled =~ s/ipforwarding\s+=\s+//;
    }
    return $enabled;
}

#-------------------------------------------------------------------------------

=head3  get_nic_ip
    Get the ip address for the node nics

    Arguments:
    Returns:
        Hash of the mapping of the nic and the ip addresses
    Globals:
    Error:
        none
    Example:
        xCAT::NetworkUtils->get_nic_ip()
    Comments:
        none
=cut

#-------------------------------------------------------------------------------

sub get_nic_ip
{
    my $nic;
    my %iphash;
    my $mode            = "MULTICAST";
    my $payingattention = 0;
    my $interface       = "";
    my $keepcurrentiface;


    if (xCAT::Utils->isAIX()) {
        ##############################################################
        # Should look like this for AIX:
        # en0: flags=4e080863,80<UP,BROADCAST,NOTRAILERS,RUNNING,
        #      SIMPLEX,MULTICAST,GROUPRT,64BIT,PSEG,CHAIN>
        #      inet 30.0.0.1    netmask 0xffffff00 broadcast 30.0.0.255
        #      inet 192.168.2.1 netmask 0xffffff00 broadcast 192.168.2.255
        # en1: ...
        #
        ##############################################################
        my $cmd    = "ifconfig -a";
        my $result = `$cmd`;
        #############################################
        # Error running command
        #############################################
        if (!$result) {
            return undef;
        }
        my @adapter = split /(\w+\d+):\s+flags=/, $result;
        foreach (@adapter) {
            if ($_ =~ /^(en\d)/) {
                $nic = $1;
                next;
            }
            if (!($_ =~ /LOOPBACK/) and
                $_ =~ /UP(,|>)/ and
                $_ =~ /$mode/) {
                my @ip = split /\n/;
                for my $ent (@ip) {
                    if ($ent =~ /^\s*inet\s+(\d+\.\d+\.\d+\.\d+)/) {
                        $iphash{$nic} = $1;
                        next;
                    }
                }
            }
        }
    }
    else {    # linux
        my @ipoutput = `ip addr`;
        #############################################
        # Error running command
        #############################################
        if (!@ipoutput) {
            return undef;
        }
        foreach my $line (@ipoutput) {
            if ($line =~ /^\d/) {    # new interface, new context..
                if ($interface and not $keepcurrentiface) {

                    #don't bother reporting unusable nics
                    delete $iphash{$interface};
                }
                $keepcurrentiface = 0;
                $interface = "";
                if (!($line =~ /LOOPBACK/) and
                    $line =~ /UP( |,|>)/ and
                    $line =~ /$mode/) {

                    $payingattention = 1;
                    $line =~ /^([^:]*): ([^:]*):/;
                    $interface = $2;
                } else {
                    $payingattention = 0;
                    next;
                }
            }
            unless ($payingattention) { next; }
            if ($line =~ /inet/) {
                $keepcurrentiface = 1;
            }
            if ($line =~ /^\s*inet \s*(\d+\.\d+\.\d+\.\d+)/) {
                $iphash{$interface} = $1;
            }
        }
    }
    return \%iphash;
}

#-------------------------------------------------------------------------------

=head3   classful_networks_for_net_and_mask

    Arguments:
        network and mask
    Returns:
        a list of classful subnets that constitute the entire potentially classless arguments
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub classful_networks_for_net_and_mask
{
    my $network    = shift;
    my $mask       = shift;
    my $given_mask = 0;
    if ($mask =~ /\./)
    {
        $given_mask = 1;
        my $masknumber = unpack("N", inet_aton($mask));
        $mask = 32;
        until ($masknumber % 2)
        {
            $masknumber = $masknumber >> 1;
            $mask--;
        }
    }

    my @results;
    my $bitstoeven = (8 - ($mask % 8));
    if ($bitstoeven == 8) { $bitstoeven = 0; }
    my $resultmask = $mask + $bitstoeven;
    if ($given_mask)
    {
        $resultmask =
          inet_ntoa(pack("N", (2**$resultmask - 1) << (32 - $resultmask)));
    }
    push @results, $resultmask;

    my $padbits  = (32 - ($bitstoeven + $mask));
    my $numchars = int(($mask + $bitstoeven) / 4);
    my $curmask  = 2**$mask - 1 << (32 - $mask);
    my $nown     = unpack("N", inet_aton($network));
    $nown = $nown & $curmask;
    my $highn = $nown + ((2**$bitstoeven - 1) << (32 - $mask - $bitstoeven));

    while ($nown <= $highn)
    {
        push @results, inet_ntoa(pack("N", $nown));

        #$rethash->{substr($nowhex, 0, $numchars)} = $network;
        $nown += 1 << (32 - $mask - $bitstoeven);
    }
    return @results;
}

# Record an address while preserving the caller's undefined map until needed.
sub _record_network_address
{
    my ($mapref, $key, $address, $returnall) = @_;

    if ($returnall) {
        push @{ ${$mapref}->{$key} }, $address;
    } else {
        ${$mapref}->{$key} = $address;
    }
}

#-------------------------------------------------------------------------------

=head3   my_hexnets

    Arguments:
        Optional: 'all' returns every IPv4 address found for each network in order.
        The default behavior returns the last address found.
    Returns:
    Globals:
        none
    Error:
        none
    Example:
        xCAT::NetworkUtils->my_hexnets
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub my_hexnets
{
    my $returnall = @_ && $_[-1] eq 'all';
    my $rethash;
    my @nets = split /\n/, `/sbin/ip addr`;
    foreach (@nets)
    {
        my @elems = split /\s+/;
        unless (/^\s*inet\s/)
        {
            next;
        }
        (my $curnet, my $maskbits) = split /\//, $elems[2];
        my $bitstoeven = (4 - ($maskbits % 4));
        if ($bitstoeven == 4) { $bitstoeven = 0; }
        my $padbits  = (32 - ($bitstoeven + $maskbits));
        my $numchars = int(($maskbits + $bitstoeven) / 4);
        my $curmask  = 2**$maskbits - 1 << (32 - $maskbits);
        my $nown     = unpack("N", inet_aton($curnet));
        $nown = $nown & $curmask;
        my $highn =
          $nown + ((2**$bitstoeven - 1) << (32 - $maskbits - $bitstoeven));

        while ($nown <= $highn)
        {
            my $nowhex = sprintf("%08x", $nown);
            my $hexnet = substr($nowhex, 0, $numchars);
            _record_network_address(\$rethash, $hexnet, $curnet, $returnall);
            $nown += 1 << (32 - $maskbits - $bitstoeven);
        }
    }
    return $rethash;
}

#-------------------------------------------------------------------------------

=head3 get_host_from_ip
    Description:
        Get the hostname of an IP addresses. First from hosts table, and then try system resultion.
        If there is a shortname, it will be returned. Otherwise it will return long name. If the IP cannot be resolved, return undef;

    Arguments:
        $ip: the IP to get;

    Returns:
        Return: the hostname.
For an example

    Globals:
        none

    Error:
        none

    Example:
        xCAT::NetworkUtils::get_host_from_ip('192.168.200.1')

    Comments:
=cut

#-----------------------------------------------------------------------
sub get_host_from_ip
{
    my $ip = shift;
}

#-------------------------------------------------------------------------------

=head3 isPingable
    Description:
        Check if an IP address can be pinged

    Arguments:
        $ip: the IP to ping;

    Returns:
        Return: 1 indicates yes; 0 indicates no.
For an example

    Globals:
        none

    Error:
        none

    Example:
        xCAT::NetworkUtils::isPingable('192.168.200.1')

    Comments:
        none
=cut

#-----------------------------------------------------------------------
my %PING_CACHE;

sub isPingable
{
    my $ip = shift;

    my $rc;
    if (exists $PING_CACHE{$ip})
    {
        $rc = $PING_CACHE{$ip};
    }
    else
    {
        my $res = `LANG=C ping -c 1 -w 5 $ip 2>&1`;
        if ($res =~ /100% packet loss/g)
        {
            $rc = 1;
        }
        else
        {
            $rc = 0;
        }
        $PING_CACHE{$ip} = $rc;
    }

    return !$rc;
}

#-------------------------------------------------------------------------------

=head3 my_nets
    Description:
        Return a hash ref that contains all subnet and netmask on the mn (or sn). This subroutine can be invoked on both Linux and AIX.

    Arguments:
        Optional: 'all' returns every address found for each network in order.
        The default behavior returns the last address found.

    Returns:
        Return a hash ref. Each entry will be: <subnet/mask>=><existing ip>;
        For an example:
            '192.168.200.0/255.255.255.0' => '192.168.200.246';
For an example

    Globals:
        none

    Error:
        none

    Example:
        xCAT::NetworkUtils::my_nets().

    Comments:
        none
=cut

#-----------------------------------------------------------------------
sub my_nets
{
    my $returnall = @_ && $_[-1] eq 'all';
    require xCAT::Table;
    my $rethash;
    my @nets;
    my $v6net;
    my $v6ip;
    if ($^O eq 'aix')
    {
        @nets = split /\n/, `/usr/sbin/ifconfig -a`;
    }
    else
    {
        @nets = split /\n/, `/sbin/ip addr`; #could use ip route, but to match hexnets...
    }
    foreach (@nets)
    {
        $v6net = '';
        my @elems = split /\s+/;
        unless (/^\s*inet/)
        {
            next;
        }
        my $curnet; my $maskbits;
        if ($^O eq 'aix')
        {
            if ($elems[1] eq 'inet6')
            {
                $v6net = $elems[2];
                $v6ip  = $elems[2];
                $v6ip =~ s/\/.*//;    # ipv6 address 4000::99/64
                $v6ip =~ s/\%.*//;    # ipv6 address ::1%1/128
            }
            else
            {
                $curnet = $elems[2];
                $maskbits = formatNetmask($elems[4], 2, 1);
            }
        }
        else
        {
            if ($elems[1] eq 'inet6')
            {
                next; #Linux IPv6 TODO, do not return IPv6 networks on Linux for now
            }
            ($curnet, $maskbits) = split /\//, $elems[2];
        }
        if (!$v6net)
        {
            my $curmask = 2**$maskbits - 1 << (32 - $maskbits);
            my $nown = unpack("N", inet_aton($curnet));
            $nown = $nown & $curmask;
            my $textnet = inet_ntoa(pack("N", $nown));
            $textnet .= "/$maskbits";
            _record_network_address(\$rethash, $textnet, $curnet, $returnall);
        }
        else
        {
            _record_network_address(\$rethash, $v6net, $v6ip, $returnall);
        }
    }


    # now get remote nets
    my $nettab = xCAT::Table->new("networks");

    #my $sitetab = xCAT::Table->new("site");
    #my $master = $sitetab->getAttribs({key=>'master'},'value');
    #$master = $master->{value};
    my @masters = xCAT::TableUtils->get_site_attribute("master");
    my $master  = $masters[0];
    my @vnets   = $nettab->getAllAttribs('net', 'mgtifname', 'mask');

    foreach (@vnets) {
        my $n  = $_->{net};
        my $if = $_->{mgtifname};
        my $nm = $_->{mask};
        if (!$n || !$if || !$nm)
        {
            next;    #incomplete network
        }
        if ($if =~ /!remote!/) {   #only take in networks with special interface
            $nm = formatNetmask($nm, 0, 1);
            $n .= "/$nm";

            #$rethash->{$n} = $if;
            _record_network_address(\$rethash, $n, $master, $returnall);
        }
    }
    return $rethash;
}

#-------------------------------------------------------------------------------

=head3   my_if_netmap
   Arguments:
      none
   Returns:
      hash of networks to interface names
   Globals:
      none
   Error:
      none
   Comments:
      none
=cut

#-------------------------------------------------------------------------------
sub my_if_netmap
{
    my $net;
    if (scalar(@_))
    {    #called with the other syntax
        $net = shift;
    }
    my @rtable = split /\n/, `netstat -rn`;
    if ($?)
    {
        return "Unable to run netstat, $?";
    }
    my %retmap;
    foreach (@rtable)
    {
        if (/^\D/) { next; }             #skip headers
        if (/^\S+\s+\S+\s+\S+\s+\S*G/)
        {
            next;
        }    #Skip networks that require gateways to get to
        /^(\S+)\s.*\s(\S+)$/;
        $retmap{$1} = $2;
    }
    return \%retmap;
}

#-------------------------------------------------------------------------------

=head3   my_ip_facing
         Returns my ip address in the same network with the specified node
         Linux only
    Arguments:
        nodename
    Returns:
	result and error message or my ip address
	1. If node can not be resolved, the return info will be like this:
	[1, "The $node can not be resolved"].
	2. If no IP found that matching the giving node, the return info will be:
	[2, "The IP address of node $node is in an undefined subnet"].
	3. If IP found:
	[0,ip1,ip2,...]
    Globals:
        none
    Error:
        none
    Example:
        my @ip = xCAT::NetworkUtils->my_ip_facing($peerip)  # return multiple
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub my_ip_facing
{
    my $peer = shift;
    if (@_)
    {
        $peer = shift;
    }

    return my_ip_facing_aix($peer) if ($^O eq 'aix');
    my @rst;
    my $peernumber = inet_aton($peer);    #TODO: IPv6 support
    unless ($peernumber) {
        $rst[0] = 1;
        $rst[1] = "The $peer can not be resolved";
        return @rst; }
    my $noden = unpack("N", $peernumber);
    my @nets = split /\n/, `/sbin/ip addr`;

    my @ips;
    foreach (@nets)
    {
        my @elems = split /\s+/;
        unless (/^\s*inet\s/)
        {
            next;
        }
        (my $curnet, my $maskbits) = split /\//, $elems[2];
        my $curmask = 2**$maskbits - 1 << (32 - $maskbits);
        my $curn = unpack("N", inet_aton($curnet));
        if (($noden & $curmask) == ($curn & $curmask))
        {
            push @ips, $curnet;
        }
    }

    if (@ips) {
        $rst[0] = 0;
        push @rst, @ips;
    } else {
        $rst[0] = 2;
        $rst[1] = "The IP address of node $peer is in an undefined subnet";
    }
    return @rst;
}

#-------------------------------------------------------------------------------

=head3   my_ip_facing_family

         Returns local addresses in the same subnet as the specified peer,
         restricted to the requested address family. Linux only.
    Arguments:
        peer hostname or address
        address family (4 or 6)
    Returns:
        [0, ip1, ip2, ...] when matching local addresses are found
        [1, error] when the peer cannot be resolved in the requested family
        [2, error] when no local address shares the peer's subnet
    Example:
        my @ip = xCAT::NetworkUtils->my_ip_facing_family($peer, 6)

=cut

#-------------------------------------------------------------------------------

sub _local_ip_prefixes
{
    my $family = shift;
    return unless defined($family) && ($family == 4 || $family == 6);
    return if $^O eq 'aix';

    my $ipcmd = -x '/sbin/ip' ? '/sbin/ip'
      : -x '/usr/sbin/ip'     ? '/usr/sbin/ip'
      :                         undef;
    return unless $ipcmd;

    my $address_type = $family == 6 ? 'inet6' : 'inet';
    my @addresses;
    if (open(my $ipout, '-|', $ipcmd, '-o', "-$family", 'addr', 'show', 'scope', 'global'))
    {
        while (my $line = <$ipout>)
        {
            if ($line =~ /\s\Q$address_type\E\s+([^\s\/]+)\/(\d+)/)
            {
                push @addresses, [ $1, $2 ];
            }
        }
        close($ipout);
    }
    return @addresses;
}

sub _pack_ip_address
{
    my ($address, $family) = @_;
    return unless defined($address);

    if ($family == 4)
    {
        return inet_aton($address);
    }

    my $packed;
    if (defined(&Socket::inet_pton))
    {
        $packed = eval { Socket::inet_pton(Socket::AF_INET6(), $address) };
    }
    if (!defined($packed) && $socket6support)
    {
        $packed = eval { Socket6::inet_pton(Socket6::AF_INET6(), $address) };
    }
    return $packed;
}

# Turns a packed address back into a literal. Core Socket has carried
# inet_ntop since 5.14; Socket6 is the fallback for an older perl, and it is
# optional, so a host can have neither.
sub _unpack_ip_address
{
    my ($packed, $family) = @_;
    return unless defined($packed);
    return inet_ntoa($packed) if $family == 4;

    my $address;
    if (defined(&Socket::inet_ntop))
    {
        $address = eval { Socket::inet_ntop(Socket::AF_INET6(), $packed) };
    }
    if (!defined($address) && $socket6support)
    {
        $address = eval { Socket6::inet_ntop(Socket6::AF_INET6(), $packed) };
    }
    return $address;
}

#-------------------------------------------------------------------------------

=head3    canonical_ip_address

    Returns the one spelling of an address that every other spelling of it
    shares, for use as a hash key.

    Arguments:
        IPv4 address or IPv6 address, with an optional zone identifier
    Returns:
        the canonical literal, or undef when the value is not an address or
        this host has no parser for its family
    Comments:
        2001:db8::10 and 2001:0db8:0000:0000:0000:0000:0000:0010 are the same
        address and have to reach the same key. A caller that keys on the
        literal holds two entries for one host.

=cut

#-------------------------------------------------------------------------------
sub canonical_ip_address
{
    my $address = shift;
    if (defined($address) && $address eq __PACKAGE__)
    {
        $address = shift;
    }
    return unless defined($address) && length($address);

    $address =~ s/%.*$//;
    return unless length($address);
    return unless xCAT::NetworkUtils->isValidIp($address);

    my $family = $address =~ /:/ ? 6 : 4;
    my $packed = _pack_ip_address($address, $family);
    return unless defined($packed);
    return _unpack_ip_address($packed, $family);
}

#-------------------------------------------------------------------------------

=head3    getIPv6PrefixLength

    Returns the numeric prefix length from an IPv6 network and optional mask.

    Arguments:
        IPv6 network, optionally with a CIDR suffix
        Optional numeric prefix mask
    Returns:
        Prefix length from 0 through 128, or undef

=cut

#-------------------------------------------------------------------------------

sub getIPv6PrefixLength
{
    my $network = shift;
    if (defined($network) && $network eq __PACKAGE__)
    {
        $network = shift;
    }
    my $mask = shift;

    return unless defined($network) && $network =~ /:/;

    my $prefix;
    if ($network =~ m{/([0-9]+)$})
    {
        $prefix = $1;
    }
    elsif (defined($mask) && $mask =~ m{^/?([0-9]+)$})
    {
        $prefix = $1;
    }

    return unless defined($prefix) && $prefix <= 128;
    return $prefix;
}

#-------------------------------------------------------------------------------

=head3    getIPv6ReverseZone

    Formats the nibble-aligned ip6.arpa zone for an IPv6 network.

    Arguments:
        IPv6 network, optionally with a CIDR suffix
        Optional numeric prefix mask
    Returns:
        Reverse zone name, or undef for invalid or non-nibble-aligned input

=cut

#-------------------------------------------------------------------------------

#-------------------------------------------------------

=head3    getIPv6ReverseZones

    Description: The reverse zones that cover an IPv6 network.

    Arguments:
        network: the network, with or without a prefix length
        mask:    the prefix length, used when the network carries none

    Returns:
        The nibble-aligned zones that cover the network, as a list. A reverse zone is delegated
        on a nibble, so a prefix that is not a multiple of 4 is covered by several zones of the
        next nibble: a /62 by four /64 zones. This is what the IPv4 side does with a /22.
        An empty list when the network does not parse.

    Example:
        my @zones = xCAT::NetworkUtils->getIPv6ReverseZones('2001:db8::/62');

=cut

#-------------------------------------------------------
sub getIPv6ReverseZones
{
    my $network = shift;
    if (defined($network) && $network eq __PACKAGE__)
    {
        $network = shift;
    }
    my $mask = shift;

    my $prefix = xCAT::NetworkUtils->getIPv6PrefixLength($network, $mask);
    return () unless defined($prefix);

    # The address is taken without the prefix, because getIPv6PrefixLength prefers an embedded
    # one and a rounded value passed beside it would be ignored.
    my $address = $network;
    $address =~ s{/.*$}{};
    my $packed = _pack_ip_address($address, 6);
    return () unless defined($packed);
    return ('ip6.arpa.') if $prefix == 0;

    my $remainder = $prefix % 4;
    my $zonebits  = $remainder ? $prefix + ( 4 - $remainder ) : $prefix;
    return () if $zonebits > 128;

    my $nibbles = $zonebits / 4;
    my $hex     = substr( unpack('H*', $packed), 0, $nibbles );
    my $count   = $remainder ? ( 1 << ( 4 - $remainder ) ) : 1;
    my $base    = hex( substr( $hex, $nibbles - 1, 1 ) );
    my $head    = substr( $hex, 0, $nibbles - 1 );

    my @zones;
    foreach my $step ( 0 .. $count - 1 ) {
        my $last = $base + $step;
        last if $last > 0xf;
        my $zone = $head . sprintf( '%x', $last );
        push @zones, join( '.', reverse( split( //, $zone ) ) ) . '.ip6.arpa.';
    }
    return @zones;
}

sub getIPv6ReverseZone
{
    my $network = shift;
    if (defined($network) && $network eq __PACKAGE__)
    {
        $network = shift;
    }
    my $mask = shift;

    my $prefix = xCAT::NetworkUtils->getIPv6PrefixLength($network, $mask);
    return unless defined($prefix) && $prefix % 4 == 0;

    my $address = $network;
    $address =~ s{/.*$}{};
    my $packed = _pack_ip_address($address, 6);
    return unless defined($packed);
    return 'ip6.arpa.' if $prefix == 0;

    my $hex = substr(unpack('H*', $packed), 0, $prefix / 4);
    return join('.', reverse(split(//, $hex))) . '.ip6.arpa.';
}

#-------------------------------------------------------------------------------

=head3    getIPv6ReverseName

    Formats the complete 32-nibble ip6.arpa owner name for an IPv6 literal.

=cut

#-------------------------------------------------------------------------------

sub getIPv6ReverseName
{
    my $address = shift;
    if (defined($address) && $address eq __PACKAGE__)
    {
        $address = shift;
    }

    return xCAT::NetworkUtils->getIPv6ReverseZone($address, 128);
}

#-------------------------------------------------------------------------------

=head3    isSameIPAddress

    Compares two IPv4 or IPv6 literals by their packed address value.

    Arguments:
        Two IPv4 or IPv6 address literals
    Returns:
        1 - equivalent addresses
        0 - different or invalid addresses

=cut

#-------------------------------------------------------------------------------

sub isSameIPAddress
{
    my $first = shift;
    if (defined($first) && $first eq __PACKAGE__)
    {
        $first = shift;
    }
    my $second = shift;

    return 0 unless xCAT::NetworkUtils->isValidIp($first)
      && xCAT::NetworkUtils->isValidIp($second);
    my $family = $first =~ /:/ ? 6 : 4;
    return 0 if ($second =~ /:/ ? 6 : 4) != $family;

    my $first_packed  = _pack_ip_address($first, $family);
    my $second_packed = _pack_ip_address($second, $family);
    return defined($first_packed)
      && defined($second_packed)
      && $first_packed eq $second_packed ? 1 : 0;
}

sub _addresses_share_prefix
{
    my ($first, $second, $prefix, $family) = @_;
    my $max_prefix = $family == 6 ? 128 : 32;
    return 0 unless defined($prefix)
      && $prefix =~ /^\d+$/
      && $prefix >= 0
      && $prefix <= $max_prefix;

    my $first_packed  = _pack_ip_address($first, $family);
    my $second_packed = _pack_ip_address($second, $family);
    return 0 unless defined($first_packed) && defined($second_packed);

    my $whole_bytes = int($prefix / 8);
    return 0
      if substr($first_packed, 0, $whole_bytes)
      ne substr($second_packed, 0, $whole_bytes);

    my $remaining_bits = $prefix % 8;
    if ($remaining_bits)
    {
        my $mask = (0xff << (8 - $remaining_bits)) & 0xff;
        return 0
          if (ord(substr($first_packed, $whole_bytes, 1)) & $mask)
          != (ord(substr($second_packed, $whole_bytes, 1)) & $mask);
    }
    return 1;
}

#-------------------------------------------------------------------------------

=head3    node_address_family

    Returns the preferred address family for a node. IPv4 remains preferred
    for dual-stack nodes to preserve existing xCAT behavior.

=cut

#-------------------------------------------------------------------------------

sub node_address_family
{
    my $node = shift;
    if (defined($node) && $node eq __PACKAGE__)
    {
        $node = shift;
    }

    return 4 if xCAT::NetworkUtils->getipaddr($node, OnlyV4 => 1);
    return 6 if xCAT::NetworkUtils->getipaddr($node, OnlyV6 => 1);
    return;
}

sub node_is_ipv6_only
{
    my $node = shift;
    if (defined($node) && $node eq __PACKAGE__)
    {
        $node = shift;
    }

    my $family = xCAT::NetworkUtils->node_address_family($node);
    return defined($family) && $family == 6 ? 1 : 0;
}

sub my_ip_facing_family
{
    my $peer = shift;
    if (defined($peer) && $peer eq __PACKAGE__)
    {
        $peer = shift;
    }
    my $family = shift;

    unless (defined($family) && ($family == 4 || $family == 6))
    {
        return (1, 'Address family must be 4 or 6');
    }

    my $peerip = $family == 6
      ? xCAT::NetworkUtils->getipaddr($peer, OnlyV6 => 1)
      : xCAT::NetworkUtils->getipaddr($peer, OnlyV4 => 1);
    unless ($peerip)
    {
        return (1, "The $peer can not be resolved as IPv$family");
    }

    my @ips;
    foreach my $local (_local_ip_prefixes($family))
    {
        my ($address, $prefix) = @{$local};
        if (_addresses_share_prefix($peerip, $address, $prefix, $family))
        {
            push @ips, $address;
        }
    }

    if (@ips)
    {
        return (0, @ips);
    }
    return (2, "The IPv$family address of node $peer is in an undefined subnet");
}

sub ipv6_server_for_node
{
    my $node = shift;
    if (defined($node) && $node eq __PACKAGE__)
    {
        $node = shift;
    }
    my $server = shift;

    if (!defined($server) || $server eq '!myipfn!' || $server eq '<xcatmaster>')
    {
        my @facing = xCAT::NetworkUtils->my_ip_facing_family($node, 6);
        return unless @facing && !$facing[0];
        return $facing[1];
    }

    return $server
      if $server =~ /:/ && xCAT::NetworkUtils->isValidIp($server);
    return xCAT::NetworkUtils->getipaddr($server, OnlyV6 => 1);
}

#-------------------------------------------------------------------------------

=head3   my_ip_facing_aix
         Returns my ip address
         AIX only
    Arguments:
        nodename
    Returns:
    Globals:
        none
    Error:
        none
    Example:
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub my_ip_facing_aix
{
    my $peer = shift;
    my @nets = `ifconfig -a`;
    chomp @nets;
    my @ips;
    my @rst;
    foreach my $net (@nets)
    {
        my ($curnet, $netmask);
        if ($net =~ /^\s*inet\s+([\d\.]+)\s+netmask\s+(\w+)\s+broadcast/)
        {
            ($curnet, $netmask) = ($1, $2);
        }
        elsif ($net =~ /^\s*inet6\s+(.*)$/)
        {
            ($curnet, $netmask) = split('/', $1);
        }
        else
        {
            next;
        }
        if (isInSameSubnet($peer, $curnet, $netmask, 2))
        {
            push @ips, $curnet;
        }
    }
    if (@ips)
    {
        $rst[0] = 0;
        push @rst, @ips;
    }
    else
    {
        $rst[0] = 2;
        $rst[1] = "The IP address of node $peer is in an undefined subnet";
    }
    return @rst;
}

#-------------------------------------------------------------------------------

=head3 formatNetmask
    Description:
        Transform netmask to one of 3 formats (255.255.255.0, 24, 0xffffff00).

    Arguments:
        $netmask: the original netmask
        $origType: the original netmask type. The valid value can be 0, 1, 2:
            Type 0: 255.255.255.0
            Type 1: 24
            Type 2: 0xffffff00
        $newType: the new netmask type, valid values can be 0,1,2, as above.

    Returns:
        Return undef if any error. Otherwise return the netmask in new format.

    Globals:
        none

    Error:
        none

    Example:
        xCAT::NetworkUtils::formatNetmask( '24', 1, 0); #return '255.255.255.0'.

    Comments:
        none
=cut

#-----------------------------------------------------------------------
sub formatNetmask
{
    my $mask     = shift;
    my $origType = shift;
    my $newType  = shift;
    my $maskn;
    if (not defined $mask) { return undef; }
    if ($origType == 0)
    {
        $maskn = unpack("N", inet_aton($mask));
    }
    elsif ($origType == 1)
    {
        $maskn = 2**$mask - 1 << (32 - $mask);
    }
    elsif ($origType == 2)
    {
        $maskn = hex $mask;
    }
    else
    {
        return undef;
    }

    if ($newType == 0)
    {
        return inet_ntoa(pack('N', $maskn));
    }
    if ($newType == 1)
    {
        my $bin = unpack("B32", pack("N", $maskn));
        my @dup = ($bin =~ /(1{1})0*/g);
        return scalar(@dup);
    }
    if ($newType == 2)
    {
        return sprintf "0x%1x", $maskn;
    }
    return undef;
}

#-------------------------------------------------------------------------------

=head3 isInSameSubnet
    Description:
        Check if 2 given IP addresses are in same subnet

    Arguments:
        $ip1: the first IP
        $ip2: the second IP
        $mask: the netmask, here are 3 possible netmask types, following are examples for these 3 types:
            Type 0: 255.255.255.0
            Type 1: 24
            Type 2: 0xffffff00
        $masktype: the netmask type, 3 possible values: 0,1,2, as indicated above

    Returns:
        1: they are in same subnet
        undef: not in same subnet

    Globals:
        none

    Error:
        none

    Example:
        xCAT::NetworkUtils::isInSameSubnet( '192.168.10.1', '192.168.10.2', '255.255.255.0', 0);

    Comments:
        none
=cut

#-----------------------------------------------------------------------
sub isInSameSubnet
{
    my $ip1      = shift;
    my $ip2      = shift;
    my $mask     = shift;
    my $maskType = shift;

    $ip1 = xCAT::NetworkUtils->getipaddr($ip1);
    $ip2 = xCAT::NetworkUtils->getipaddr($ip2);

    if (!defined($ip1) || !defined($ip2))
    {
        return undef;
    }

    if ((($ip1 =~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 !~ /\d+\.\d+\.\d+\.\d+/))
        || (($ip1 !~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 =~ /\d+\.\d+\.\d+\.\d+/)))
    {
        #ipv4 and ipv6 can not be in the same subnet
        return undef;
    }

    if (($ip1 =~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 =~ /\d+\.\d+\.\d+\.\d+/))
    {
        my $maskn;
        if ($maskType == 0)
        {
            $maskn = unpack("N", inet_aton($mask));
        }
        elsif ($maskType == 1)
        {
            $maskn = 2**$mask - 1 << (32 - $mask);
        }
        elsif ($maskType == 2)
        {
            $maskn = hex $mask;
        }
        else
        {
            return undef;
        }

        my $ip1n = unpack("N", inet_aton($ip1));
        my $ip2n = unpack("N", inet_aton($ip2));

        return (($ip1n & $maskn) == ($ip2n & $maskn));
    }
    else
    {
        #ipv6
        if (($ip1 =~ /\%/) || ($ip2 =~ /\%/))
        {
            return undef;
        }
        $mask =~ s{^/}{} if defined($mask);
        return _addresses_share_prefix($ip1, $ip2, $mask, 6) ? 1 : undef;
    }
}

#-------------------------------------------------------------------------------

=head3 nodeonmynet - checks to see if node is on any network this server is attached to or remote network potentially managed by this system
    Arguments:
       Node name
    Returns:  1 if node is on the network
    Globals:
        none
    Error:
        none
    Example:
        xCAT::NetworkUtils->nodeonmynet
    Comments:
        none
=cut

#-------------------------------------------------------------------------------

sub nodeonmynet
{
    require xCAT::Table;
    my $nodetocheck = shift;
    if (scalar(@_))
    {
        $nodetocheck = shift;
    }

    my $nodeip = getNodeIPaddress($nodetocheck);
    if (!$nodeip)
    {
        return 0;
    }
    unless ($nodeip =~ /\d+\.\d+\.\d+\.\d+/)
    {
        #IPv6
        if ($^O eq 'aix')
        {
            my @subnets = get_subnet_aix();
            for my $net_ent (@subnets)
            {
                if ($net_ent !~ /-/)
                {
                    #ipv4
                    next;
                }
                my ($net, $interface, $mask, $flag) = split /-/, $net_ent;
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip, $mask, $net))
                {
                    return 1;
                }
            }

        } else {
            my @v6routes = split /\n/, `ip -6 route`;
            foreach (@v6routes) {
                if (/via/ or /^unreachable/ or /^fe80::\/64/) {

                    #only count local ones, remote ones can be caught in next loop
                    #also, link-local would be a pitfall,
                    #since more context than address is
                    #needed to determine locality
                    next;
                }
                s/ .*//;    #remove all after the space
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip, '', $_)) { #bank on CIDR support
                    return 1;
                }
            }
        }
        my $nettab = xCAT::Table->new("networks");
        my @vnets = $nettab->getAllAttribs('net', 'mgtifname', 'mask');
        foreach (@vnets) {
            if ((defined $_->{mgtifname}) && ($_->{mgtifname} =~ /!remote!/))
            {
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip, $_->{mask}, $_->{net}))
                {
                    return 1;
                }
            }
        }
        return 0;
    }
    my $noden = unpack("N", inet_aton($nodeip));
    my @nets;
    if ($utildata->{nodeonmynetdata} and $utildata->{nodeonmynetdata}->{pid} == $$) {
        @nets = @{ $utildata->{nodeonmynetdata}->{nets} };
    } else {
        if ($^O eq 'aix')
        {
            my @subnets = get_subnet_aix();
            for my $net_ent (@subnets)
            {
                if ($net_ent =~ /-/)
                {
                    #ipv6
                    next;
                }
                my @ents = split /:/, $net_ent;
                push @nets, $ents[0] . '/' . $ents[2] . ' dev ' . $ents[1];
            }

        }
        else
        {
            @nets = split /\n/, `/sbin/ip route`;
        }
        my $nettab = xCAT::Table->new("networks");
        my @vnets = $nettab->getAllAttribs('net', 'mgtifname', 'mask');
        foreach (@vnets) {
            if ((defined $_->{mgtifname}) && ($_->{mgtifname} =~ /!remote!/))
            {    #global scoped network
                my $curm = unpack("N", inet_aton($_->{mask}));
                my $bits = 32;
                until ($curm & 1) {
                    $bits--;
                    $curm = $curm >> 1;
                }
                push @nets, $_->{'net'} . "/" . $bits . " dev remote";
            }
        }
        $utildata->{nodeonmynetdata}->{pid}  = $$;
        $utildata->{nodeonmynetdata}->{nets} = \@nets;
    }
    foreach (@nets)
    {
        my @elems = split /\s+/;
        unless ($elems[1] =~ /dev/)
        {
            next;
        }
        (my $curnet, my $maskbits) = split /\//, $elems[0];
        my $curmask = 2**$maskbits - 1 << (32 - $maskbits);
        my $curn = unpack("N", inet_aton($curnet));
        if (($noden & $curmask) == $curn)
        {
            return 1;
        }
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3   getNodeIPaddress
    Arguments:
       Node name  only one at a time
    Returns: ip address(s)
    Globals:
        none
    Error:
        none
    Example:   my $c1 = xCAT::NetworkUtils::getNodeIPaddress($nodetocheck);

=cut

#-------------------------------------------------------------------------------

sub getNodeIPaddress
{
    require xCAT::Table;
    my $nodetocheck = shift;
    if ($nodetocheck eq 'xCAT::NetworkUtils') {    #was called with -> syntax
        $nodetocheck = shift;
    }

    # Quick return if pass in an IP
    return $nodetocheck if (xCAT::NetworkUtils->isIpv4addr($nodetocheck));

    my $nodeip = xCAT::NetworkUtils->getipaddr($nodetocheck);
    if (!$nodeip)
    {
        my $hoststab = xCAT::Table->new('hosts');
        my $ent = $hoststab->getNodeAttribs($nodetocheck, ['ip']);
        if ($ent->{'ip'}) {
            $nodeip = $ent->{'ip'};
        }
    }

    if ($nodeip) {
        return $nodeip;
    } else {
        return undef;
    }
}


#-------------------------------------------------------------------------------

=head3   checkNodeIPaddress
    Arguments:
       Node name  only one at a time
    Returns: a hash object contains IP or Error
    Globals:
        none
    Example:   my $ipresult = xCAT::NetworkUtils::checkNodeIPaddress($nodetocheck);

=cut

#-------------------------------------------------------------------------------

sub checkNodeIPaddress
{
    require xCAT::Table;
    my $nodetocheck = shift;
    if ($nodetocheck eq 'xCAT::NetworkUtils') {    #was called with -> syntax
        $nodetocheck = shift;
    }
    my $ret;

    my $nodeip;
    my $hoststab = xCAT::Table->new('hosts');
    my $ent = $hoststab->getNodeAttribs($nodetocheck, ['ip']);
    if ($ent->{'ip'}) {
        $nodeip = $ent->{'ip'};
    }

    # Get the IP from DNS
    my $dnsip = xCAT::NetworkUtils->getipaddr($nodetocheck);
    if (!$dnsip)
    {
        $ret->{'error'} = "The $nodetocheck can not be resolved.";
        $ret->{'ip'} = $nodeip if ($nodeip);
    } elsif (!$nodeip) {
        $ret->{'ip'} = $dnsip;
    } else {
        $ret->{'ip'} = $nodeip;
        $ret->{'error'} = "Defined IP address of $nodetocheck is inconsistent with DNS." if ($nodeip ne $dnsip);
    }
    return $ret;
}


#-------------------------------------------------------------------------------

=head3   thishostisnot
    returns  0 if host is not the same
    Arguments:
       hostname
    Returns:
    Globals:
        none
    Error:
        none
    Example:
        xCAT::NetworkUtils->thishostisnot
    Comments:
        none
=cut

#-------------------------------------------------------------------------------

sub thishostisnot
{
    my $comparison = shift;
    if (scalar(@_))
    {
        $comparison = shift;
    }

    my @ips;
    if ($^O eq 'aix')
    {
        @ips = split /\n/, `/usr/sbin/ifconfig -a`;
    }
    else
    {
        @ips = split /\n/, `/sbin/ip addr`;
    }
    my $comp = xCAT::NetworkUtils->getipaddr($comparison);
    if ($comp)
    {
        foreach (@ips)
        {
            if (/^\s*inet.?\s+/)
            {
                my @ents = split(/\s+/);
                my $ip   = $ents[2];
                $ip =~ s/\/.*//;
                $ip =~ s/\%.*//;
                if ($ip eq $comp)
                {
                    return 0;
                }
            }
        }
    }
    return 1;
}

#-----------------------------------------------------------------------------

=head3 gethost_ips  (AIX and Linux)
     Will use ifconfig to determine all possible ip addresses for the
	 host it is running on and then gethostbyaddr to get all possible hostnames

     input:
	 output: array of ipaddress(s)  and hostnames
	 example:  @ips=xCAT::NetworkUtils->gethost_ips();

=cut

#-----------------------------------------------------------------------------
#sub gethost_ips1
#{
#    my ($class) = @_;
#    my $cmd;
#    my @ipaddress;
#    $cmd = "ifconfig" . " -a";
#    $cmd = $cmd . "| grep \"inet\"";
#    my @result = xCAT::Utils->runcmd($cmd, 0);
#    if ($::RUNCMD_RC != 0)
#    {
#        xCAT::MsgUtils->message("S", "Error from $cmd\n");
#        exit $::RUNCMD_RC;
#    }
#    foreach my $addr (@result)
#    {
#        my @ip;
#        if (xCAT::Utils->isLinux())
#        {
#            if ($addr =~ /inet6/)
#            {
#               #TODO, Linux ipv6
#            }
#            else
#            {
#                my ($inet, $addr1, $Bcast, $Mask) = split(" ", $addr);
#                #@ip = split(":", $addr1);
#                #push @ipaddress, $ip[1];
#                $addr1 =~ s/.*://;
#                push @ipaddress, $addr1;
#            }
#        }
#        else
#        {    #AIX
#            if ($addr =~ /inet6/)
#            {
#               $addr =~ /\s*inet6\s+([\da-fA-F:]+).*\/(\d+)/;
#               my $v6ip = $1;
#               my $v6mask = $2;
#               if ($v6ip)
#               {
#                   push @ipaddress, $v6ip;
#               }
#            }
#            else
#            {
#                my ($inet, $addr1, $netmask, $mask1, $Bcast, $bcastaddr) =
#                  split(" ", $addr);
#                push @ipaddress, $addr1;
#            }
#
#        }
#    }
#    my @names = @ipaddress;
#    foreach my $ipaddr (@names)
#    {
#        my $hostname = xCAT::NetworkUtils->gethostname($ipaddr);
#        if ($hostname)
#        {
#            my @shorthost = split(/\./, $hostname);
#            push @ipaddress, $shorthost[0];
#        }
#    }
#
#    return @ipaddress;
#}


sub gethost_ips
{
    my ($class) = @_;
    my $cmd;
    my @ipaddress;
    if (xCAT::Utils->isLinux())
    {
        $cmd = "ip -4 --oneline addr show |awk -F ' ' '{print \$4}'|awk -F '/' '{print \$1}'";
        my @result = xCAT::Utils->runcmd($cmd);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("S", "Error from $cmd\n");
            exit $::RUNCMD_RC;
        }

        push @ipaddress, @result;
    }
    else
    {    #AIX

        $cmd = "ifconfig" . " -a";
        $cmd = $cmd . "| grep \"inet\"";
        my @result = xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("S", "Error from $cmd\n");
            exit $::RUNCMD_RC;
        }

        foreach my $addr (@result)
        {
            if ($addr =~ /inet6/)
            {
                $addr =~ /\s*inet6\s+([\da-fA-F:]+).*\/(\d+)/;
                my $v6ip   = $1;
                my $v6mask = $2;
                if ($v6ip)
                {
                    push @ipaddress, $v6ip;
                }
            }
            else
            {
                my ($inet, $addr1, $netmask, $mask1, $Bcast, $bcastaddr) =
                  split(" ", $addr);
                push @ipaddress, $addr1;
            }

        }
    }

    my @names = @ipaddress;
    foreach my $ipaddr (@names)
    {
        my $hostname = xCAT::NetworkUtils->gethostname($ipaddr);
        if ($hostname)
        {
            my @shorthost = split(/\./, $hostname);
            push @ipaddress, $shorthost[0];
        }
    }
    return @ipaddress;
}

#-------------------------------------------------------------------------------

=head3 get_subnet_aix
    Description:
        To get present subnet configuration by parsing the output of 'netstat'. Only designed for AIX.
    Arguments:
        None
    Returns:
        @aix_nrn : An array with entries in format "net:nic:netmask:flag". Following is an example entry:
            9.114.47.224:en0:27:U
    Globals:
        none
    Error:
        none
    Example:
         my @nrn =xCAT::NetworkUtils::get_subnet_aix
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub get_subnet_aix
{
    my @netstat_res = `/usr/bin/netstat -rn`;
    chomp @netstat_res;
    my @aix_nrn;
    for my $entry (@netstat_res)
    {
        #We need to find entries like:
        #Destination        Gateway           Flags   Refs     Use  If   Exp  Groups
        #9.114.47.192/27    9.114.47.205      U         1         1 en0
        #4000::/64          link#4            UCX       1         0 en2      -      -
        my ($net, $netmask, $flag, $nic);
        if ($entry =~ /^\s*([\d\.]+)\/(\d+)\s+[\d\.]+\s+(\w+)\s+\d+\s+\d+\s(\w+)/)
        {
            ($net, $netmask, $flag, $nic) = ($1, $2, $3, $4);
            my @dotsec = split /\./, $net;
            for (my $i = 4 ; $i > scalar(@dotsec) ; $i--)
            {
                $net .= '.0';
            }
            push @aix_nrn, "$net:$nic:$netmask:$flag" if ($net ne '127.0.0.0');
        }
        elsif ($entry =~ /^\s*([\dA-Fa-f\:]+)\/(\d+)\s+.*?\s+(\w+)\s+\d+\s+\d+\s(\w+)/)
        {
            #print "=====$entry====\n";
            ($net, $netmask, $flag, $nic) = ($1, $2, $3, $4);

            # for ipv6, can not use : as the delimiter
            push @aix_nrn, "$net-$nic-$netmask-$flag" if ($net ne '::')
        }
    }
    return @aix_nrn;
}

#-----------------------------------------------------------------------------

=head3 determinehostname  and ip address(s)

  Used on the service node to figure out what hostname and ip address(s)
  are valid names and addresses
  Input: None
  Output: ipaddress(s),nodename
=cut

#-----------------------------------------------------------------------------
sub determinehostname
{
    my $hostname;
    eval {
        $hostname = hostname;
    };
    if($@){
        xCAT::MsgUtils->message("S","Fail to get hostname: $@\n");
        exit -1;
    }
    #get all potentially valid abbreviations, and pick the one that is ok
    #by 'noderange'
    my @hostnamecandidates;
    my $nodename;
    while ($hostname =~ /\./) {
        push @hostnamecandidates, $hostname;
        $hostname =~ s/\.[^\.]*//;
    }
    push @hostnamecandidates, $hostname;
    my $checkhostnames = join(',', @hostnamecandidates);
    my @validnodenames = xCAT::NodeRange::noderange($checkhostnames);
    unless (scalar @validnodenames) { #If the node in question is not in table, take output literrally.
        push @validnodenames, $hostnamecandidates[0];
    }

    #now, noderange doesn't guarantee the order, so we search the preference order, most to least specific.
    foreach my $host (@hostnamecandidates) {
        if (grep /^$host$/, @validnodenames) {
            $nodename = $host;
            last;
        }
    }
    my @ips = xCAT::NetworkUtils->gethost_ips;
    my @hostinfo = (@ips, $nodename);

    return @hostinfo;
}

#-----------------------------------------------------------------------------

=head3 toIP

 IPv4 function to convert hostname to IP address

=cut

#-----------------------------------------------------------------------------
sub toIP
{

    if (($_[0] =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/) || ($_[0] =~ /:/))
    {
        return ([ 0, $_[0] ]);
    }
    my $ip = xCAT::NetworkUtils->getipaddr($_[0]);
    if (!$ip)
    {
        return ([ 1, "Cannot Resolve: $_[0]\n" ]);
    }
    return ([ 0, $ip ]);
}

#-------------------------------------------------------------------------------

=head3    isIpv4addr

    returns 1 if parameter has a valid IPv4 address form.

    Arguments:
        dot qulaified IP address: e.g. 1.2.3.4
    Returns:
        1 - if legal IP address
        0 - if not legal IP address.
    Globals:
        none
    Error:
        none
    Example:
         if ($ipAddr) { blah; }
    Comments:
        Doesn't test if the IP address is on the network,
        just tests its form.

=cut

#-------------------------------------------------------------------------------
sub isIpv4addr
{
    my $addr = shift;
    if (($addr) && ($addr =~ /xCAT::NetworkUtils/))
    {
        $addr = shift;
    }

    unless ($addr)
    {
        return 0;
    }

    #print "addr=$addr\n";
    if ($addr !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
    {
        return 0;
    }

    if ($1 > 255 || $1 =~ /^0/ || $2 > 255 || $2 =~ /^0\d/ || $3 > 255 || $3 =~ /^0\d/ || $4 > 255 || $4 =~ /^0\d/)
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

#-------------------------------------------------------------------------------

=head3    isIpaddr

    Deprecated alias for isIpv4addr, kept for external callers.

=cut

#-------------------------------------------------------------------------------
sub isIpaddr
{
    return isIpv4addr(@_);
}

#-------------------------------------------------------------------------------

=head3    isIpv6addr

    returns 1 if the value is a valid IPv6 address.

    Arguments:
        IPv6 address string
    Returns:
        1 - valid IPv6 address
        0 - not a valid IPv6 address
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::NetworkUtils->isIpv6addr($ip)) { blah; }
    Comments:
        Zone identifiers such as fe80::1%eth0 are not accepted.

=cut

#-------------------------------------------------------------------------------
sub isIpv6addr
{
    my $value = shift;
    if (($value) && ($value =~ /xCAT::NetworkUtils/))
    {
        $value = shift;
    }

    unless (defined($value) and length($value))
    {
        return 0;
    }

    # inet_pton handling of zone identifiers is platform-dependent
    if ($value =~ /%/)
    {
        return 0;
    }

    my $packed_address;
    if (defined &Socket::inet_pton)
    {
        $packed_address = eval { Socket::inet_pton(Socket::AF_INET6(), $value) };
    }
    elsif (defined &Socket6::inet_pton)
    {
        # Perl 5.8 core Socket has no inet_pton; Socket6 provides it
        $packed_address = eval { Socket6::inet_pton(Socket6::AF_INET6(), $value) };
    }
    return defined($packed_address) ? 1 : 0;
}

#-------------------------------------------------------------------------------
# A link-local address reaches one link only, so it cannot serve as a cluster
# address: fe80::/10 for IPv6, 169.254.0.0/16 for IPv4.
sub _is_link_local
{
    my $address = shift;
    return 0 unless defined($address) && length($address);
    return 1 if $address =~ /^fe[89ab][0-9a-f]:/i;
    return 1 if $address =~ /^169\.254\./;
    return 0;
}

#-------------------------------------------------------------------------------
# Socket6::getaddrinfo answers a flat list of five-element records. Reorder the
# records, not the elements, by the rule prefer_routable_addresses applies.
sub _socket6_addrinfo_routable_first
{
    my @addrinfo = @_;
    return @addrinfo if scalar(@addrinfo) % 5;

    my (@routable, @linklocal, @unreadable);
    while (my @record = splice(@addrinfo, 0, 5))
    {
        my $numeric_ip = (Socket6::getnameinfo($record[3], Socket6::NI_NUMERICHOST()))[0];
        if (!defined($numeric_ip))
        {
            push @unreadable, @record;
        }
        elsif (_is_link_local($numeric_ip))
        {
            push @linklocal, @record;
        }
        else
        {
            push @routable, @record;
        }
    }
    return (@routable, @linklocal, @unreadable);
}

#-------------------------------------------------------------------------------
# Order getaddrinfo entries by the same rule prefer_routable_addresses applies
# to literals. An entry whose address cannot be read keeps its place at the end.
sub _addrinfo_routable_first
{
    my @addrinfo = @_;
    my (@routable, @linklocal, @unreadable);
    foreach my $address (@addrinfo)
    {
        my ($name_error, $numeric_ip) =
          Socket::getnameinfo($address->{addr}, Socket::NI_NUMERICHOST());
        if ($name_error || !defined($numeric_ip))
        {
            push @unreadable, $address;
        }
        elsif (_is_link_local($numeric_ip))
        {
            push @linklocal, $address;
        }
        else
        {
            push @routable, $address;
        }
    }
    return (@routable, @linklocal, @unreadable);
}

#-------------------------------------------------------------------------------

=head3    prefer_routable_addresses

    Orders resolved addresses so a routable one comes before a link-local one,
    and removes the IPv6 zone identifier.

    Arguments:
        list of address literals, in resolver order
    Returns:
        the same addresses, routable ones first, order kept inside each group
    Comments:
        A host resolves its own name to every address on it, and a link-local
        address is often first. site.master takes that answer and reaches every
        node, which cannot use fe80::/10 across a link or parse the %zone form.

=cut

#-------------------------------------------------------------------------------
sub prefer_routable_addresses
{
    my @addresses = @_;
    shift @addresses
      if @addresses && defined($addresses[0]) && $addresses[0] eq __PACKAGE__;

    my (@routable, @linklocal);
    foreach my $address (@addresses)
    {
        next unless defined($address) && length($address);
        $address =~ s/%.*$//;
        next unless length($address);
        if (_is_link_local($address))
        {
            push @linklocal, $address;
        }
        else
        {
            push @routable, $address;
        }
    }
    return (@routable, @linklocal);
}

#-------------------------------------------------------------------------------

=head3    isValidIp

    returns 1 if the value is a valid IPv4 or IPv6 address.

    Arguments:
        IP address string
    Returns:
        1 - valid IP address
        0 - not a valid IP address
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::NetworkUtils->isValidIp($ip)) { blah; }
    Comments:
        IPv4 values follow the isIpv4addr rules.

=cut

#-------------------------------------------------------------------------------
sub isValidIp
{
    my $value = shift;
    if (($value) && ($value =~ /xCAT::NetworkUtils/))
    {
        $value = shift;
    }

    return (isIpv4addr($value) or isIpv6addr($value)) ? 1 : 0;
}



#-------------------------------------------------------------------------------

=head3    format_uri_host

    Formats a host for use in a URI authority. IPv6 literals are enclosed in
    square brackets; IPv4 literals and hostnames are returned unchanged.

    Arguments:
        IPv4 address, IPv6 address, or hostname
    Returns:
        Formatted host, or undef for malformed input

=cut

#-------------------------------------------------------------------------------

sub _endpoint_hostname_is_valid
{
    my $host = shift;
    return 0 unless defined($host) && length($host);

    # The endpoint grammar intentionally accepts uppercase and underscore
    # labels used by xCAT; the legacy hostname validators do not accept both.
    my $name = $host;
    $name =~ s/\.$//;
    return 0 unless length($name) && length($name) <= 253;
    if ($name =~ /^(?:\d+\.){3}\d+$/)
    {
        return xCAT::NetworkUtils->isIpaddr($name);
    }

    foreach my $label (split(/\./, $name, -1))
    {
        return 0 unless length($label) <= 63
          && $label =~ /^[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?$/;
    }
    return 1;
}

sub format_uri_host
{
    my $host = shift;
    if (defined($host) && $host eq __PACKAGE__)
    {
        $host = shift;
    }

    return unless defined($host) && length($host);
    if ($host =~ /^\[([^\]]+)\]$/)
    {
        my $address = $1;
        return unless xCAT::NetworkUtils->isValidIp($address) && $address =~ /:/;
        return $host;
    }

    if ($host =~ /:/)
    {
        return unless xCAT::NetworkUtils->isValidIp($host);
        return "[$host]";
    }

    return _endpoint_hostname_is_valid($host) ? $host : undef;
}

#-------------------------------------------------------------------------------

=head3    format_host_port

    Formats a host and TCP/UDP port. IPv6 literals use the standard bracketed
    form so the result can be used as either a URI authority or endpoint.

    Arguments:
        IPv4 address, IPv6 address, or hostname
        Port number (1-65535)
    Returns:
        host:port, [IPv6-address]:port, or undef for malformed input

=cut

#-------------------------------------------------------------------------------

sub _endpoint_port_is_valid
{
    my $port = shift;
    return defined($port)
      && $port =~ /^\d+$/
      && $port > 0
      && $port <= 65535;
}

sub format_host_port
{
    my $host = shift;
    if (defined($host) && $host eq __PACKAGE__)
    {
        $host = shift;
    }
    my $port = shift;

    return unless _endpoint_port_is_valid($port);
    my $formatted_host = xCAT::NetworkUtils->format_uri_host($host);
    return unless defined($formatted_host);
    return "$formatted_host:$port";
}

#-------------------------------------------------------------------------------

=head3    parse_host_port

    Parses a hostname or address with an optional port. An IPv6 address with
    an explicit port must use [address]:port syntax; an unbracketed IPv6
    literal is treated only as a host.

    Arguments:
        Host or endpoint
        Optional default port (1-65535)
    Returns:
        (host, port), or an empty list for malformed input

=cut

#-------------------------------------------------------------------------------

sub parse_host_port
{
    my $endpoint = shift;
    if (defined($endpoint) && $endpoint eq __PACKAGE__)
    {
        $endpoint = shift;
    }
    my $default_port = shift;

    return unless defined($endpoint) && length($endpoint);
    return if defined($default_port) && !_endpoint_port_is_valid($default_port);

    my ($host, $port);
    if ($endpoint =~ /^\[([^\]]+)\](?::(\d+))?$/)
    {
        $host = $1;
        $port = defined($2) ? $2 : $default_port;
        return unless xCAT::NetworkUtils->isValidIp($host) && $host =~ /:/;
    }
    elsif (xCAT::NetworkUtils->isValidIp($endpoint) && $endpoint =~ /:/)
    {
        $host = $endpoint;
        $port = $default_port;
    }
    elsif ($endpoint =~ /^([^:]+):(\d+)$/)
    {
        ($host, $port) = ($1, $2);
    }
    elsif ($endpoint !~ /:/)
    {
        $host = $endpoint;
        $port = $default_port;
    }
    else
    {
        return;
    }

    return unless defined(xCAT::NetworkUtils->format_uri_host($host));
    return if defined($port) && !_endpoint_port_is_valid($port);
    return ($host, $port);
}




#-------------------------------------------------------------------------------

=head3  getNodeNameservers
    Description:
        Get nameservers of  specified nodes.
        The priority: noderes.nameservers > networks.nameservers > site.nameservers
    Arguments:
        node: node name list
    Returns:
        Return a hash ref, of the $nameservers{$node}
        undef - Failed to get the nameservers
    Globals:
        none
    Error:
        none
    Example:
        my $nameservers = xCAT::NetworkUtils::getNodeNameservers(\@node);
    Comments:
        none

=cut

#-------------------------------------------------------------------------------
sub getNodeNameservers {
    my $nodes = shift;
    if ($nodes =~ /xCAT::NetworkUtils/)
    {
        $nodes = shift;
    }
    my @nodelist = @$nodes;
    my %nodenameservers;
    my $nrtab = xCAT::Table->new('noderes', -create => 0);
    my %nrhash = %{ $nrtab->getNodesAttribs(\@nodelist, ['nameservers']) };

    my $nettab  = xCAT::Table->new("networks");
    my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodelist);

    my @nameservers     = xCAT::TableUtils->get_site_attribute("nameservers");
    my $sitenameservers = $nameservers[0];


    foreach my $node (@nodelist) {
        if ($nrhash{$node} and $nrhash{$node}->[0] and $nrhash{$node}->[0]->{nameservers})
        {
            $nodenameservers{$node} = $nrhash{$node}->[0]->{nameservers};
        } elsif ($nethash{$node}{nameservers})
        {
            $nodenameservers{$node} = $nethash{$node}{nameservers};
        } elsif ($sitenameservers)
        {
            $nodenameservers{$node} = $sitenameservers;
        }
    }

    return \%nodenameservers;
}


#-------------------------------------------------------------------------------

=head3   getNodeNetworkCfg
    Description:
        Get node network configuration, including "IP, hostname(the nodename),and netmask" by this node's name.

    Arguments:
        node: the nodename
    Returns:
        Return an array, which contains (IP,hostname,gateway,netmask').
        undef - Failed to get the network configuration info
    Globals:
        none
    Error:
        none
    Example:
        my ($ip,$host,undef,$mask) = xCAT::NetworkUtils::getNodeNetworkCfg('node1');
    Comments:
        Presently gateway is always blank. Need to be improved.

=cut

#-------------------------------------------------------------------------------
sub getNodeNetworkCfg
{
    my $node = shift;
    if ($node =~ /xCAT::NetworkUtils/)
    {
        $node = shift;
    }

    my $ip      = xCAT::NetworkUtils->getipaddr($node);
    my $mask    = undef;
    my $gateway = undef;

    my $nettab = xCAT::Table->new("networks");
    if ($nettab) {
        my @nets = $nettab->getAllAttribs('net', 'mask', 'gateway');
        foreach my $net (@nets) {
            if (xCAT::NetworkUtils::isInSameSubnet($net->{'net'}, $ip, $net->{'mask'}, 0)) {
                $gateway = $net->{'gateway'};
                $mask    = $net->{'mask'};
            }
        }
    }

    return ($ip, $node, $gateway, xCAT::NetworkUtils::formatNetmask($mask, 0, 0));
}

#-------------------------------------------------------------------------------

=head3   getNodeNetworkCfg6
    Description:
        Get the configured IPv6 address, hostname, gateway, and prefix length
        for a node.

    Arguments:
        node: the nodename
    Returns:
        An array containing (IPv6 address, hostname, gateway, prefix length).
        The address is undefined when the node has no IPv6 address.  Gateway
        and prefix are undefined when no matching networks row exists.

=cut

#-------------------------------------------------------------------------------
sub getNodeNetworkCfg6
{
    my $node = shift;
    if (defined($node) && $node =~ /xCAT::NetworkUtils/)
    {
        $node = shift;
    }

    my $ip = xCAT::NetworkUtils->getipaddr($node, OnlyV6 => 1);
    return (undef, $node, undef, undef) unless $ip;

    my ($gateway, $prefix);
    my $nettab = xCAT::Table->new("networks");
    if ($nettab) {
        my @nets = $nettab->getAllAttribs('net', 'mask', 'gateway');
        foreach my $net (@nets) {
            my $network = $net->{'net'};
            my $candidate_prefix = $net->{'mask'};
            next unless defined($network);

            if ($network =~ s{/([0-9]+)$}{}) {
                $candidate_prefix = $1 unless defined($candidate_prefix) && length($candidate_prefix);
            }
            next unless defined($candidate_prefix);
            $candidate_prefix =~ s{^/}{};
            next unless $candidate_prefix =~ /^\d+$/ && $candidate_prefix <= 128;

            if (xCAT::NetworkUtils::_addresses_share_prefix($network, $ip, $candidate_prefix, 6)) {
                $gateway = $net->{'gateway'};
                $prefix  = $candidate_prefix;
                last;
            }
        }
        $nettab->close();
    }

    return ($ip, $node, $gateway, $prefix);
}

#-------------------------------------------------------------------------------

=head3   getNodesNetworkCfg
    Description:
        Get network configuration (ip,netmask,gateway) for a group of nodes

    Arguments:
        nodes: the group of nodes
    Returns:
        If failed: (1, error_msg)
        If success: (0, the hash variable store network configuration info for nodes that get matching network entry)
    Error:
        none
    Example:
        my ($ret, $hash) = xCAT::NetworkUtils::getNodesNetworkCfg($noderange);
    Comments:

=cut

#-------------------------------------------------------------------------------

sub getNodesNetworkCfg
{
    my $nodes = shift;
    if ($nodes =~ /xCAT::NetworkUtils/) {
        $nodes = shift;
    }
    my @nets   = ();
    my $nettab = xCAT::Table->new("networks");
    if ($nettab) {
        my @error_net = ();
        my @all_nets = $nettab->getAllAttribs('net', 'mask', 'gateway');
        foreach my $net (@all_nets) {
            my $gateway = $net->{gateway};
            if (defined($gateway) and ($gateway eq '<xcatmaster>')) {
                my @gatewayd = xCAT::NetworkUtils->my_ip_facing($net->{'net'});
                unless ($gatewayd[0]) {
                    $gateway = $gatewayd[1];
                }
            }
            push @nets, { net => $net->{net}, mask => $net->{mask}, gateway => $gateway };
        }
        $nettab->close;
    }
    else {
        return (1, "Open \"networks\" table failed");
    }
    if (!scalar(@nets)) {
        return (1, "No entry find in \"networks\" table");
    }
    my %rethash = ();
    foreach my $node (@$nodes) {
        my $ip = xCAT::NetworkUtils->getipaddr($node);
        foreach my $net (@nets) {
            if (xCAT::NetworkUtils::isInSameSubnet($net->{'net'}, $ip, $net->{'mask'}, 0)) {
                $rethash{$node}->{ip}      = $ip;
                $rethash{$node}->{mask}    = $net->{'mask'};
                $rethash{$node}->{gateway} = $net->{'gateway'};
                last;
            }
        }
    }
    return (0, \%rethash);
}

#-------------------------------------------------------------------------------

=head3   get_hdwr_ip
    Description:
        Get hardware(CEC, BPA) IP from the hosts table, and then /etc/hosts.

    Arguments:
        node: the nodename(cec, or bpa)
    Returns:
        Return the node IP
        -1  - Failed to get the IP.
    Globals:
        none
    Error:
        none
    Example:
        my $ip = xCAT::NetworkUtils::get_hdwr_ip('node1');
    Comments:
        Used in FSPpower FSPflash, FSPinv.

=cut

#-------------------------------------------------------------------------------
sub get_hdwr_ip
{
    require xCAT::Table;
    my $node = shift;
    my $ip   = undef;
    my $Rc   = undef;

    my $ip_tmp_res = xCAT::NetworkUtils::toIP($node);
    ($Rc, $ip) = @$ip_tmp_res;
    if ($Rc) {
        my $hosttab = xCAT::Table->new('hosts');
        if ($hosttab) {
            my $node_ip_hash = $hosttab->getNodeAttribs($node, [qw(ip)]);
            $ip = $node_ip_hash->{ip};
        }

    }

    if (!$ip) {
        return undef;
    }

    return $ip;
}

#--------------------------------------------------------------------------------

=head3    match_ping_target

      Maps a name or numeric address reported by a ping backend to the
      original target supplied by xCAT.

=cut

#--------------------------------------------------------------------------------

sub match_ping_target
{
    my ($class, $candidate, $targets) = @_;
    return unless defined($candidate) && ref($targets) eq 'ARRAY';

    my @matches = $class->match_ping_targets([$candidate], $targets);
    return $matches[0];
}

#--------------------------------------------------------------------------------

=head3    match_ping_targets

      Maps a batch of names or numeric addresses reported by a ping backend to
      the original xCAT targets, reusing one address-resolution index.

=cut

#--------------------------------------------------------------------------------

sub match_ping_targets
{
    my ($class, $candidates, $targets) = @_;
    return unless ref($candidates) eq 'ARRAY' && ref($targets) eq 'ARRAY';

    my %state;
    my @matches;
    foreach my $candidate (@{$candidates})
    {
        my $target = _match_ping_target($candidate, $targets, \%state);
        push @matches, $target if defined($target);
    }
    return @matches;
}

sub _ping_address_key
{
    my ($address) = @_;
    return unless xCAT::NetworkUtils->isValidIp($address);

    my $family = $address =~ /:/ ? 6 : 4;
    my $packed = _pack_ip_address($address, $family);
    return defined($packed) ? "$family:" . unpack('H*', $packed) : undef;
}

sub _ping_address_targets
{
    my ($targets) = @_;
    my %addresses;

    foreach my $target (@{$targets})
    {
        next unless defined($target);
        my $literal_key = _ping_address_key($target);
        if (defined($literal_key))
        {
            $addresses{$literal_key} = $target
              unless exists($addresses{$literal_key});
            next;
        }

        foreach my $family (qw(OnlyV4 OnlyV6))
        {
            my $address = xCAT::NetworkUtils->getipaddr(
                $target, $family => 1
            );
            my $key = _ping_address_key($address);
            next unless defined($key);
            $addresses{$key} = $target unless exists($addresses{$key});
        }
    }

    return \%addresses;
}

sub _match_ping_target
{
    my ($candidate, $targets, $state) = @_;
    return unless defined($candidate);

    $candidate =~ s/^\s+|\s+$//g;
    foreach my $target (@{$targets})
    {
        return $target if lc($candidate) eq lc($target);
        return $target if $candidate =~ /^\Q$target\E\./i;
    }

    my $key = _ping_address_key($candidate);
    return unless defined($key);
    $state->{addresses} = _ping_address_targets($targets)
      unless exists($state->{addresses});
    return $state->{addresses}{$key};
}


#--------------------------------------------------------------------------------

=head3    nmap_alive_targets

      Parses old and current nmap ping-scan output and returns the original
      xCAT targets that nmap reported as reachable.

=cut

#--------------------------------------------------------------------------------

sub nmap_alive_targets
{
    my ($class, $targets, $output) = @_;
    return unless ref($targets) eq 'ARRAY' && ref($output) eq 'ARRAY';

    my %match_state;
    my (%alive, @alive);
    my $current_target;
    foreach my $line (@{$output})
    {
        if ($line =~ /^Host\s+(.+?)(?:\s+\(([^)]*)\))?\s+appears to be up\b/)
        {
            my $target = _match_ping_target($1, $targets, \%match_state);
            if (!defined($target) && defined($2))
            {
                $target = _match_ping_target($2, $targets, \%match_state);
            }
            if (defined($target) && !$alive{$target}++)
            {
                push @alive, $target;
            }
            next;
        }

        if ($line =~ /^Nmap scan report for\s+(.+?)\s*$/)
        {
            my $reported = $1;
            my $reported_address;
            if ($reported =~ s/\s+\(([^()]*)\)\s*$//)
            {
                $reported_address = $1;
            }
            $current_target = _match_ping_target(
                $reported, $targets, \%match_state
            );
            if (!defined($current_target) && defined($reported_address))
            {
                $current_target = _match_ping_target(
                    $reported_address, $targets, \%match_state
                );
            }
            next;
        }

        if ($line =~ /^Host is up\b/ && defined($current_target))
        {
            if (!$alive{$current_target}++)
            {
                push @alive, $current_target;
            }
        }
    }

    return @alive;
}


sub _nmap_ping_available
{
    return -x '/usr/bin/nmap' || -x '/usr/local/bin/nmap';
}

sub _nmap_ping_output
{
    my ($class, $nodes, $more_options) = @_;
    my $targets = join(' ', @{$nodes});
    $more_options ||= '';
    open(my $nmap, "nmap -PE --system-dns --send-ip -sP $more_options $targets 2> /dev/null|") ## no critic (InputOutput::ProhibitTwoArgOpen)
      or die("Cannot open nmap pipe: $!");
    my @output = <$nmap>;
    close($nmap);
    return @output;
}


#--------------------------------------------------------------------------------

=head3    pingNodeStatus
      This function takes an array of nodes and returns their status using nmap or fping.
    Arguments:
       nodes-- an array of nodes.
    Returns:
       a hash that has the node status. The format is:
          {alive=>[node1, node3,...], unreachable=>[node4, node2...]}
=cut

#--------------------------------------------------------------------------------
sub pingNodeStatus {
    my ($class, @mon_nodes) = @_;
    my %status         = ();
    my @active_nodes   = ();
    my @inactive_nodes = ();

    #print "NetworkUtils->pingNodeStatus called, nodes=@mon_nodes\n";
    if ((@mon_nodes) && (@mon_nodes > 0)) {

        #get all the active nodes
        my $nodes = join(' ', @mon_nodes);
        if ($class->_nmap_ping_available()) {    #use nmap
                #print "use nmap\n";
            # get additional options from site table
            my @nmap_options = xCAT::TableUtils->get_site_attribute("nmapoptions");
            my $more_options = $nmap_options[0];

            #call nmap
            my @nmap_output = $class->_nmap_ping_output(
                \@mon_nodes, $more_options
            );

            @active_nodes = xCAT::NetworkUtils->nmap_alive_targets(
                \@mon_nodes, \@nmap_output
            );
            my %active_nodes = map { $_ => 1 } @active_nodes;
            @inactive_nodes = sort grep { !$active_nodes{$_} } @mon_nodes;
        } else {    #use fping
                    #print "use fping\n";

            my $temp = `fping -a $nodes 2> /dev/null`;
            chomp($temp);
            @active_nodes = split(/\n/, $temp);

            #get all the inactive nodes by substracting the active nodes from all.
            my %temp2;
            if ((@active_nodes) && (@active_nodes > 0)) {
                foreach (@active_nodes) { $temp2{$_} = 1 }
                foreach (@mon_nodes) {
                    if (!$temp2{$_}) { push(@inactive_nodes, $_); }
                }
            }
            else { @inactive_nodes = @mon_nodes; }
        }
    }

    $status{$::STATUS_ACTIVE}   = \@active_nodes;
    $status{$::STATUS_INACTIVE} = \@inactive_nodes;

    #use Data::Dumper;
    #print Dumper(%status);

    return %status;
}

#-------------------------------------------------------------------------------

=head3 isValidMAC
      Description : Validate whether specified string is a MAC string.
      Arguments   : macstr - the string to be validated.
      Returns     : 1 - valid MAC String.
                    0 - invalid MAC String.
=cut

#-------------------------------------------------------------------------------
sub isValidMAC
{
    my ($class, $macstr) = @_;
    if ($macstr =~ /^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$/) {
        return 1;
    }
    return 0;
}

#-------------------------------------------------------------------------------

=head3 isValidHostname
      Description : Validate whether specified string is a valid hostname.
      Arguments   : hostname - the string to be validated.
      Returns     : 1 - valid hostname String.
                    0 - invalid hostname String.
=cut

#-------------------------------------------------------------------------------
sub isValidHostname
{
    my ($class, $hostname) = @_;
    if ($hostname =~ /^[a-z0-9]/) {
        if ($hostname =~ /[a-z0-9]$/) {
            if ($hostname =~ /^[\-a-z0-9]+$/) {
                return 1;
            }
        }
    }
    return 0;
}


#-------------------------------------------------------------------------------

=head3 isValidFQDN
      Description : Validate whether specified string is a valid FQDN.
      Arguments   : hostname - the string to be validated.
      Returns     : 1 - valid hostname FQDN.
                    0 - invalid hostname FQDN.
=cut

#-------------------------------------------------------------------------------
sub isValidFQDN
{
    my ($class, $hostname) = @_;
    if ($hostname =~ /^[a-z0-9][\.\-a-z0-9]+[a-z0-9]$/) {
        return 1;
    }
    return 0;
}


#-------------------------------------------------------------------------------

=head3 ip_to_int
      Description : convert an IPv4 string into int.
      Arguments   : ipstr - the IPv4 string.
      Returns     : ipint - int number
=cut

#-------------------------------------------------------------------------------
sub ip_to_int
{
    my ($class, $ipstr) = @_;
    my $ipint = 0;
    my @ipnums = split('\.', $ipstr);
    $ipint += $ipnums[0] << 24;
    $ipint += $ipnums[1] << 16;
    $ipint += $ipnums[2] << 8;
    $ipint += $ipnums[3];
    return $ipint;
}

#-------------------------------------------------------------------------------

=head3 int_to_ip
      Description : convert an int into IPv4 String.
      Arguments   : ipnit - the input int number.
      Returns     : ipstr - IPv4 String.
=cut

#-------------------------------------------------------------------------------
sub int_to_ip
{
    my ($class, $ipint) = @_;
    return inet_ntoa(inet_aton($ipint));
}

#-------------------------------------------------------------------------------

=head3 getBroadcast
      Description : Get the broadcast ips
      Arguments   : ipstr - the IPv4 string ip.
                    netmask - the subnet mask of network
      Returns     : bcipint - the IPv4 string of broadcast ip.
=cut

#-------------------------------------------------------------------------------
sub getBroadcast
{
    my ($class, $ipstr, $netmask) = @_;
    my $ipint   = xCAT::NetworkUtils->ip_to_int($ipstr);
    my $maskint = xCAT::NetworkUtils->ip_to_int($netmask);
    my $tmp     = sprintf("%d", ~$maskint);
    my $bcnum   = sprintf("%d", ($ipint | $tmp) & hex('0x00000000FFFFFFFF'));
    return xCAT::NetworkUtils->int_to_ip($bcnum);
}

#-------------------------------------------------------------------------------

=head3 get_allips_in_range
      Description : Get all IPs in a IP range, return in a list.
      Arguments   : $startip - start IP address
                    $endip - end IP address
                    $increment - increment factor
      Returns     : IP list in this range.
      Example     :
                    my $startip = "192.168.0.1";
                    my $endip = "192.168.0.100";
                    xCAT::NetworkUtils->get_allips_in_range($startip, $endip, 1);
=cut

#-------------------------------------------------------------------------------
sub get_allips_in_range
{
    my $class     = shift;
    my $startip   = shift;
    my $endip     = shift;
    my $increment = shift;
    my @iplist    = ();
    my $tmpip;

    my $startipnum = xCAT::NetworkUtils->ip_to_int($startip);
    my $endipnum   = xCAT::NetworkUtils->ip_to_int($endip);

    if ($increment > 0) {
        while ($startipnum <= $endipnum) {
            $tmpip = xCAT::NetworkUtils->int_to_ip($startipnum);
            $startipnum += $increment;
            push(@iplist, $tmpip);
        }
    } elsif ($increment < 0) {
        while ($endipnum >= $startipnum) {
            $tmpip = xCAT::NetworkUtils->int_to_ip($endipnum);
            $endipnum += $increment;
            push(@iplist, $tmpip);
        }
    }
    return \@iplist;
}

#-------------------------------------------------------------------------------

=head3 get_all_ips
      Description : Get all IP addresses from table nics, column nicips.
      Arguments   : hashref - if not set, will return a reference of list,
                              if set, will return a reference of hash.
      Returns     : All IPs reference.
=cut

#-------------------------------------------------------------------------------
sub get_all_nicips {
    my ($class, $hashref) = @_;
    my %allipshash;
    my @allipslist;

    my $table   = xCAT::Table->new('nics');
    my @entries = $table->getAllNodeAttribs(['nicips']);
    foreach (@entries) {

        # $_->{nicips} looks like "eth0:ip1,eth1:ip2,bmc:ip3..."
        if ($_->{nicips}) {
            my @nicandiplist = split(',', $_->{nicips});

            # Each record in @nicandiplist looks like "eth0:ip1"
            # delimiter has been changed to use "!"  in xCAT 2.8
            foreach (@nicandiplist) {
                my @nicandip;
                if ($_ =~ /!/) {
                    @nicandip = split('!', $_);
                } else {
                    @nicandip = split(':', $_);
                }
                if ($hashref) {
                    $allipshash{ $nicandip[1] } = 0;
                } else {
                    push(@allipslist, $nicandip[1]);
                }
            }
        }
    }
    if ($hashref) {
        return \%allipshash;
    } else {
        return \@allipslist;
    }
}

#-------------------------------------------------------------------------------

=head3  gen_net_boot_params

    Description:
        This subroutine is used to generate all possible kernel parameters for network boot (rh/sles/ubuntu + diskfull/diskless)
        The supported network boot parameters:
            ksdevice - Specify network device for Anaconda. For rh6 and earlier. Format: 'ksdevice={$mac|$nicname}'
            BOOTIF - Specify network device for Anaconda. The boot device which set by pxe. xCAT also set it if the bootload is not pxe. Format 'BOOTIF={$mac}'
            ifname - Specify a interfacename<->mac pair, it will set the interfacename to the interface which has the <mac>. Format 'ifname=$ifname:$mac'
               # This will only be generated when linuximage.nodebootif is set.
            bootdev - Specify the boot device. Mostly it's used with <ip> parameter and when there are multiple <ip> params. Format 'bootdev={$mac|$ifname}
            ip - Specify the network configuration for an interface. Format: 'ip=dhcp', 'ip=$ifname:dhcp'

            netdevice - Specify network device for Linuxrc (Suse bootloader). Format: 'netdevice={$mac|$nicname}'

            netdev - Specify the interfacename which is used by xCAT diskless boot script to select the network interface. Format: 'netdev=$nicname'

        Reference:
            Redhat anaconda doc: https://github.com/rhinstaller/anaconda/blob/master/docs/boot-options.txt
            Suse Linuxrc do: https://en.opensuse.org/SDB:Linuxrc

    Arguments:
        $installnic   <- node.installnic
        $primarynic <- node.primarynic
        $macmac    <- node.mac
        $nodebootif <- linuximage.nodebootif

    Returns:
        $net_params - The key will be the parameter name, the value for the key will be the parameter value.
        Valid Parameter Name:
            ksdevice
            netdev
            netdevice
            ip
            ifname
            BOOTIF

        And following two keys also will be returned for reference
            mac
            nicname

    Example:
        my $netparams = xCAT::NetworkUtils->gen_net_boot_params($installnic, $primmarynic, $macmac, $nodebootif);

=cut

#-------------------------------------------------------------------------------

sub gen_net_boot_params
{
    my $class      = shift;
    my $installnic = shift;
    my $primarynic = shift;
    my $macmac     = shift;
    my $nodebootif = shift;

    my $net_params;

    # arbitrary use primarynic if installnic is not set
    unless ($installnic) {
        $installnic = $primarynic;
    }

    # just use the installnic to generate the nic related kernel parameters
    my $mac;
    my $nicname;

    # set the default nicname to nodebootif from image definition
    if ($nodebootif) {
        $nicname = $nodebootif;
    }

    if ((!defined($installnic)) || ($installnic eq "") || ($installnic =~ /^mac$/i)) {
        $mac = $macmac;
        $net_params->{mac} = $mac;
    } elsif ($installnic =~ /^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$/) {
        $mac                  = $installnic;
        $net_params->{mac}    = $mac;
        $net_params->{setmac} = $mac;
    } else {
        $mac                   = $macmac;
        $nicname               = $installnic;
        $net_params->{nicname} = $nicname;
        $net_params->{mac}     = $mac;
    }

    # if nicname is set and mac.mac is NOT set to <mac address>, use nicname in the boot parameters
    if ($nicname && !defined($net_params->{setmac})) {
        $net_params->{ksdevice}  = "ksdevice=$nicname";
        $net_params->{ip}        = "ip=$nicname:dhcp";
        $net_params->{netdev}    = "netdev=$nicname";
        $net_params->{netdevice} = "netdevice=$nicname";
        $net_params->{bootdev}   = "bootdev=$nicname";
    } elsif ($mac) {
        $net_params->{ksdevice}  = "ksdevice=$mac";
        $net_params->{BOOTIF}    = "BOOTIF=$mac";
        $net_params->{ip}        = "ip=dhcp";
        $net_params->{netdevice} = "netdevice=$mac";
    }

    return $net_params;
}

#--------------------------------------------------------------------------------
=head3  send_tcp_msg
      establish a tcp socket to the specified IP address and port, then send the specifid message via the socket
      Arguments:
         $destip  : the destination IP address
         $destport: the destination TCP port
         $msg     : the message to send
      Returns:
         0  on success, 1 on fail
=cut
#--------------------------------------------------------------------------------
sub send_tcp_msg {
    my $self=shift;
    my $destip=shift;
    my $destport=shift;
    my $msg=shift;

    my $sock = new IO::Socket::INET(
                PeerAddr => $destip,
                PeerPort => $destport,
                Timeout  => '1',
                Proto    => 'tcp'
            );
    if ($sock) {
        print $sock $msg;
        close($sock);
        return 0;
    }else{
        return 1;
    }
}

#-----------------------------------------------------------------------------

=head3 uri_authority

    Format an address and port as a URI authority, for a kernel argument or a URL.

    Arguments:
        $address - an address, IPv4 or IPv6
        $port    - the port
    Returns:
        "<address>:<port>", with the address bracketed when it is IPv6.

    An IPv6 address contains colons, so an unbracketed "<v6>:<port>" cannot be
    split on the colon. RFC 3986 brackets the host for exactly this reason.

=cut

#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------

=head3 substitute_facing_address

    Replaces every !myipfn! in a kernel command line with the facing address of
    the management node.

    Arguments:
        $cmdline - the kernel command line
        $address - the facing address, IPv4 or IPv6
    Returns:
        the command line, with the placeholder replaced.

    A placeholder that a port follows is bracketed when the address is IPv6,
    because "http://2001:db8::1:80/" cannot be split into a host and a port.
    Every other placeholder takes the bare address: xcatd=!myipfn! names a host
    with no port, and the postscripts read that value as it stands.

=cut

#-----------------------------------------------------------------------------
sub substitute_facing_address {
    my ($cmdline, $address) = @_;

    return $cmdline unless defined($cmdline) && defined($address) && length($address);
    if (index($address, ':') >= 0) {
        $cmdline =~ s/!myipfn!(?=:\d)/[$address]/g;
    }
    $cmdline =~ s/!myipfn!/$address/g;
    return $cmdline;
}

#-----------------------------------------------------------------------------

sub uri_authority {
    my ($address, $port) = @_;

    return unless defined($address) && length($address);
    return "[$address]:$port" if index($address, ':') >= 0;
    return "$address:$port";
}

#-----------------------------------------------------------------------------

=head3 xcatd_cmdline_address

    The authority of the xcatd= kernel argument. See uri_authority.

=cut

#-----------------------------------------------------------------------------
sub xcatd_cmdline_address {
    my ($address, $port) = @_;

    return uri_authority($address, $port);
}

1;
