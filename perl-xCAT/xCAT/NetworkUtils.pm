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
#use Data::Dumper;
use strict;
use warnings "all";
my $socket6support = eval { require Socket6 };

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(getipaddr);

my $utildata; #data to persist locally
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
        my $class    = shift;
	my $nodes  = shift;

	my @nodelist = @$nodes;
	my %nodedomains;

	# Get the network info for each node
        my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodelist);

	# get the site domain value
	my @domains = xCAT::TableUtils->get_site_attribute("domain");
	my $sitedomain = $domains[0];

	# for each node - set hash value to network domain or default 
	#		to site domain 
	foreach my $node (@nodelist) {
            unless (defined($node)) {next;}
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

    if (($iporhost =~ /\d+\.\d+\.\d+\.\d+/) || ($iporhost =~ /:/)) #ip address
    {
        return (xCAT::NetworkUtils->gethostname($iporhost), $iporhost);
    }
    else #hostname
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
           return undef;
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
            my ($family, $socket, $protocol, $ip, $name) = Socket6::getaddrinfo($iporhost,0,AF_UNSPEC,SOCK_STREAM,6); #specifically ask for TCP capable records, maximizing chance of no more than one return per v4/v6
            my $host = (Socket6::getnameinfo($ip))[0];
            if ($host eq $iporhost) # can not resolve
            {
                return undef;
            }
            if ($host)
            {
                $host =~ s/\..*//; #short hostname
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
            if ( $hostname ) {            
                $hostname =~ s/\..*//; #short hostname
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
    if ($iporhost eq 'xCAT::NetworkUtils') { #was called with -> syntax
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

    #cache, do not lookup DNS each time
    if ($::hostiphash and defined($::hostiphash{$iporhost}) && $::hostiphash{$iporhost})
    {
        return $::hostiphash{$iporhost};
    }
    else
    {
        if ($socket6support) # the getaddrinfo and getnameinfo supports both IPv4 and IPv6
        {
            my @returns;
            my $reqfamily=AF_UNSPEC;
            if ($extraarguments{OnlyV6}) {
                $reqfamily=AF_INET6;
            } elsif ($extraarguments{OnlyV4}) {
                $reqfamily=AF_INET;
            }
            my @addrinfo = Socket6::getaddrinfo($iporhost,0,$reqfamily,SOCK_STREAM,6);
            my ($family, $socket, $protocol, $ip, $name) = splice(@addrinfo,0,5);
            while ($ip)
            {
                if ($extraarguments{GetNumber}) { #return a BigInt for compare, e.g. for comparing ip addresses for determining if they are in a common network or range
                    my $ip = (Socket6::getnameinfo($ip, Socket6::NI_NUMERICHOST()))[0];
                    my $bignumber = Math::BigInt->new(0);
                    foreach (unpack("N*",Socket6::inet_pton($family,$ip))) { #if ipv4, loop will iterate once, for v6, will go 4 times
                        $bignumber->blsft(32);
                        $bignumber->badd($_);
                    }
                    push(@returns,$bignumber);
                } else {
                    push @returns,(Socket6::getnameinfo($ip, Socket6::NI_NUMERICHOST()))[0];
                }
                if (scalar @addrinfo and $extraarguments{GetAllAddresses}) {
                    ($family, $socket, $protocol, $ip, $name) = splice(@addrinfo,0,5);
                } else {
                    $ip=0;
                }
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
	     if ($iporhost =~ /:/) { #ipv6
		return undef;
		#die "Attempt to process IPv6 address, but system does not have requisite IPv6 perl support";
	     }
	     my $packed_ip;
             $iporhost and $packed_ip = inet_aton($iporhost);
             if (!$packed_ip)
             {
                return undef;
             }
             if ($extraarguments{GetNumber}) { #only 32 bits, no for loop needed.
                 return Math::BigInt->new(unpack("N*",$packed_ip));
             }
             return inet_ntoa($packed_ip);
        }
    }
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
    if($mac =~ /^([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2}).*?([0-9A-Fa-f]{2})$/)
    {
        ($m1, $m2, $m3, $m6, $m7, $m8) = ($1, $2, $3, $4, $5, $6);
    }
    else
    {
        #not a valid mac address
        return undef;
    }
    my ($m4, $m5)  = ("ff","fe");

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
sub ishostinsubnet {
    my ($class, $ip, $mask, $subnet) = @_;

    #safe guard
    if (!defined($ip) || !defined($mask) || !defined($subnet))
    {
        return 0;
    }
    my $numbits=32;
    if ($ip =~ /:/) {#ipv6
        $numbits=128;
    }
    if ($mask) {
	if ($mask =~ /\//) {
	    $mask =~ s/^\///;
            $mask=Math::BigInt->new("0b".("1"x$mask).("0"x($numbits-$mask)));
	} else {
	        $mask=getipaddr($mask,GetNumber=>1);
	}
    } else {  #CIDR notation supported
        if ($subnet && ($subnet =~ /\//)) { 
            ($subnet,$mask) = split /\//,$subnet,2;
            $mask=Math::BigInt->new("0b".("1"x$mask).("0"x($numbits-$mask)));
        } else {
            die "ishostinsubnet must either be called with a netmask or CIDR /bits notation";
        }
    }
    if ($subnet && ($subnet =~ /\//)) #remove CIDR suffix from subnet
    {
        $subnet =~ s/\/.*$//;
    }
    $ip = getipaddr($ip,GetNumber=>1);
    $subnet = getipaddr($subnet,GetNumber=>1);
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
    my ($class, $enable)=@_;  
    if (xCAT::Utils->isLinux()) {
	my $conf_file="/etc/sysctl.conf";
	`grep "net.ipv4.ip_forward" $conf_file`;
        if ($? == 0) {
	    `sed -i "s/^net.ipv4.ip_forward = .*/net.ipv4.ip_forward = $enable/" $conf_file`;
            `sed -i "s/^#net.ipv4.ip_forward *= *.*/net.ipv4.ip_forward = $enable/" $conf_file`; #debian/ubuntu have different default format
 	} else {
	    `echo "net.ipv4.ip_forward = $enable" >> $conf_file`;
	}
	`sysctl -e -p $conf_file`; # workaround for redhat bug 639821
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
    my ($class, $enable)=@_;
    if (xCAT::Utils->isLinux()) {
        my $conf_file="/etc/sysctl.conf";
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
    
    my $number=Math::BigInt->new("0b".("1"x$prefixlength).("0"x(128-$prefixlength)));
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
    my $mode    = "MULTICAST";
        my $payingattention=0;
        my $interface;
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
        my $cmd     = "ifconfig -a";
        my $result  = `$cmd`;
        #############################################
        # Error running command
        #############################################
        if ( !$result ) {
          return undef;
        }
        my @adapter = split /(\w+\d+):\s+flags=/, $result;
        foreach ( @adapter ) {
            if ($_ =~ /^(en\d)/) {
               $nic = $1;
               next;
            }
            if ( !($_ =~ /LOOPBACK/ ) and
                   $_ =~ /UP(,|>)/ and
                   $_ =~ /$mode/ ) {
                my @ip = split /\n/;
                for my $ent ( @ip ) {
                    if ( $ent =~ /^\s*inet\s+(\d+\.\d+\.\d+\.\d+)/  ) {
                        $iphash{$nic} = $1; 
                        next;
                    }
                }
            }
        }
    }
    else {   # linux
        my @ipoutput = `ip addr`;
        #############################################
        # Error running command
        #############################################
        if ( !@ipoutput ) {
          return undef;
        }
        foreach my $line (@ipoutput) {
            if ($line =~ /^\d/) { # new interface, new context..
                if ($interface and not $keepcurrentiface) {
                    #don't bother reporting unusable nics
                    delete $iphash{$interface};
                }
                $keepcurrentiface=0;
                if ( !($line =~ /LOOPBACK/ ) and
                   $line =~ /UP( |,|>)/ and 
                   $line =~ /$mode/ ) {
                
                    $payingattention=1;
                    $line =~ /^([^:]*): ([^:]*):/;
                    $interface=$2;
               } else {
                    $payingattention=0;
                    next;
               }
            }
            unless ($payingattention) { next; } 
            if ($line =~ /inet/) {
                $keepcurrentiface=1;
            }
            if ( $line =~ /^\s*inet \s*(\d+\.\d+\.\d+\.\d+)/ ) {
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
    if ($bitstoeven eq 8) { $bitstoeven = 0; }
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


#-------------------------------------------------------------------------------

=head3   my_hexnets

    Arguments:
        none
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
        if ($bitstoeven eq 4) { $bitstoeven = 0; }
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
            $rethash->{substr($nowhex, 0, $numchars)} = $curnet;
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
    if ( exists $PING_CACHE{ $ip})
    {
         $rc = $PING_CACHE{ $ip};
    }
    else
    {
        my $res = `LANG=C ping -c 1 -w 5 $ip 2>&1`;
        if ( $res =~ /100% packet loss/g)
        { 
            $rc = 1;
        }
        else
        {
            $rc = 0;
        }
        $PING_CACHE{ $ip} = $rc;
    }

    return ! $rc;    
}
 
#-------------------------------------------------------------------------------

=head3 my_nets
    Description:
        Return a hash ref that contains all subnet and netmask on the mn (or sn). This subroutine can be invoked on both Linux and AIX.
        
    Arguments:
        none.
        
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
    require xCAT::Table;
    my $rethash;
    my @nets;
    my $v6net;
    my $v6ip;
    if ( $^O eq 'aix')
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
        if ( $^O eq 'aix')
        {
            if ($elems[1] eq 'inet6')
            {
                $v6net=$elems[2];
                $v6ip=$elems[2];
                $v6ip =~ s/\/.*//; # ipv6 address 4000::99/64
                $v6ip =~ s/\%.*//; # ipv6 address ::1%1/128
            }
            else
            {
                $curnet = $elems[2];
                $maskbits = formatNetmask( $elems[4], 2, 1);
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
            my $curmask  = 2**$maskbits - 1 << (32 - $maskbits);
            my $nown     = unpack("N", inet_aton($curnet));
            $nown = $nown & $curmask;
            my $textnet=inet_ntoa(pack("N",$nown));
            $textnet.="/$maskbits";
            $rethash->{$textnet} = $curnet;
         }
         else
         {
             $rethash->{$v6net} = $v6ip;
         }
    }


  # now get remote nets
    my $nettab = xCAT::Table->new("networks");
    #my $sitetab = xCAT::Table->new("site");
    #my $master = $sitetab->getAttribs({key=>'master'},'value');
    #$master = $master->{value};
    my @masters = xCAT::TableUtils->get_site_attribute("master"); 
    my $master = $masters[0];
    my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');

    foreach(@vnets){
      my $n = $_->{net};
      my $if = $_->{mgtifname};
      my $nm = $_->{mask};
      if (!$n || !$if || !$nm)
      {
          next; #incomplete network
      }
      if ($if =~ /!remote!/) { #only take in networks with special interface
        $nm = formatNetmask($nm, 0 , 1);
        $n .="/$nm";
        #$rethash->{$n} = $if;
        $rethash->{$n} = $master;
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
        if (/^\D/) { next; }    #skip headers
        if (/^\S+\s+\S+\s+\S+\s+\S*G/)
        {
            next;
        }                       #Skip networks that require gateways to get to
        /^(\S+)\s.*\s(\S+)$/;
        $retmap{$1} = $2;
    }
    return \%retmap;
}

#-------------------------------------------------------------------------------

=head3   my_ip_facing
         Returns my ip address  
         Linux only
    Arguments:
        nodename 
    Returns:
    Globals:
        none
    Error:
        none
    Example:
        xCAT::NetworkUtils->my_ip_facing
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
    return my_ip_facing_aix( $peer) if ( $^O eq 'aix');
    my $peernumber = inet_aton($peer); #TODO: IPv6 support
    unless ($peernumber) { return undef; }
    my $noden = unpack("N", inet_aton($peer));
    my @nets = split /\n/, `/sbin/ip addr`;
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
            return $curnet;
        }
    }
    return undef;
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
    foreach my $net (@nets)
    {
        my ($curnet,$netmask);
        if ( $net =~ /^\s*inet\s+([\d\.]+)\s+netmask\s+(\w+)\s+broadcast/)
        {
            ($curnet,$netmask) = ($1,$2);
        }
        elsif ($net =~ /^\s*inet6\s+(.*)$/)
        {
            ($curnet,$netmask) = split('/', $1);
        }
        else
        {
            next;
        }
        if (isInSameSubnet($peer, $curnet, $netmask, 2))
        {
            return $curnet;
        }
    }
    return undef;
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
    my $mask = shift;
    my $origType = shift;
    my $newType = shift;
    my $maskn;
    if ( $origType == 0)
    {
        $maskn = unpack("N", inet_aton($mask));
    }
    elsif ( $origType == 1)
    {
        $maskn = 2**$mask - 1 << (32 - $mask);
    }
    elsif( $origType == 2)
    {
        $maskn = hex $mask;
    }
    else
    {
        return undef;
    }

    if ( $newType == 0)
    {
        return inet_ntoa( pack('N', $maskn));
    }
    if ( $newType == 1)
    {
        my $bin = unpack ("B32", pack("N", $maskn));
        my @dup = ( $bin =~ /(1{1})0*/g);
        return scalar ( @dup);
    }
    if ( $newType == 2)
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
        2: not in same subnet
        
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
    my $ip1 = shift;
    my $ip2 = shift;
    my $mask = shift;
    my $maskType = shift;

    $ip1 = xCAT::NetworkUtils->getipaddr($ip1);
    $ip2 = xCAT::NetworkUtils->getipaddr($ip2);

    if (!defined($ip1) || !defined($ip2))
    {
        return undef;
    }

    if ((($ip1 =~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 !~ /\d+\.\d+\.\d+\.\d+/))
      ||(($ip1 !~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 =~ /\d+\.\d+\.\d+\.\d+/)))
    {
        #ipv4 and ipv6 can not be in the same subnet
        return undef;
    }

    if (($ip1 =~ /\d+\.\d+\.\d+\.\d+/) && ($ip2 =~ /\d+\.\d+\.\d+\.\d+/))
    {
        my $maskn;
        if ( $maskType == 0)
        {
            $maskn = unpack("N", inet_aton($mask));
        }
        elsif ( $maskType == 1)
        {
            $maskn = 2**$mask - 1 << (32 - $mask);
        }
        elsif( $maskType == 2)
        {
            $maskn = hex $mask;
        }
        else
        {
            return undef;
        }

        my $ip1n = unpack("N", inet_aton($ip1));
        my $ip2n = unpack("N", inet_aton($ip2));

        return ( ( $ip1n & $maskn) == ( $ip2n & $maskn) );
    }
    else
    {
        #ipv6
        if (($ip1 =~ /\%/) || ($ip2 =~ /\%/))
        {
            return undef;
        }
        my $netipmodule = eval {require Net::IP;};
        if ($netipmodule) {
           my $eip1 = Net::IP::ip_expand_address ($ip1,6);
           my $eip2 = Net::IP::ip_expand_address ($ip2,6);
           my $bmask = Net::IP::ip_get_mask($mask,6);
           my $bip1 = Net::IP::ip_iptobin($eip1,6);
           my $bip2 = Net::IP::ip_iptobin($eip2,6);
           if (($bip1 & $bmask) == ($bip2 & $bmask)) {
               return 1;
           }
       } # else, can not check without Net::IP module
       return undef;
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

    my $nodeip = getNodeIPaddress( $nodetocheck );
    if (!$nodeip)
    {
        return 0;
    }
    unless ($nodeip =~ /\d+\.\d+\.\d+\.\d+/)
    {
        #IPv6
        if ( $^O eq 'aix')
        {
            my @subnets = get_subnet_aix();
            for my $net_ent (@subnets)
            {
                if ($net_ent !~ /-/)
                {
                    #ipv4
                    next;
                }
                my ($net, $interface, $mask, $flag) = split/-/ , $net_ent;
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip, $mask, $net))
                {
                    return 1;
                }
            }

        } else {
            my @v6routes = split /\n/,`ip -6 route`;
            foreach (@v6routes) {
                if (/via/ or /^unreachable/ or /^fe80::\/64/) {
                  #only count local ones, remote ones can be caught in next loop
                   #also, link-local would be a pitfall, 
                    #since more context than address is
                     #needed to determine locality
                    next;
                }
                s/ .*//; #remove all after the space
                if (xCAT::NetworkUtils->ishostinsubnet($nodeip,'',$_)) { #bank on CIDR support
                    return 1;
                }
            }
        }
        my $nettab=xCAT::Table->new("networks");
        my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');
        foreach (@vnets) {
            if ((defined $_->{mgtifname}) && ($_->{mgtifname} eq '!remote!'))
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
        @nets = @{$utildata->{nodeonmynetdata}->{nets}};
    } else {
        if ( $^O eq 'aix')
        {
            my @subnets = get_subnet_aix();
            for my $net_ent (@subnets)
            {
                if ($net_ent =~ /-/) 
                {
                    #ipv6
                    next;
                }
                my @ents = split /:/ , $net_ent;
                push @nets, $ents[0] . '/' . $ents[2] . ' dev ' . $ents[1];
            }

        }
        else
        {
            @nets = split /\n/, `/sbin/ip route`;
        }
        my $nettab=xCAT::Table->new("networks");
        my @vnets = $nettab->getAllAttribs('net','mgtifname','mask');
        foreach (@vnets) {
            if ((defined $_->{mgtifname}) && ($_->{mgtifname} eq '!remote!'))
            { #global scoped network
                my $curm = unpack("N", inet_aton($_->{mask}));
                my $bits=32;
                until ($curm & 1)  {
                    $bits--;
                    $curm=$curm>>1;
                }
                push @nets,$_->{'net'}."/".$bits." dev remote";
            }
        }
        $utildata->{nodeonmynetdata}->{pid}=$$;
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
    my $port        = shift;
    my $nodeip;

    $nodeip = xCAT::NetworkUtils->getipaddr($nodetocheck);
    if (!$nodeip)
    {
        my $hoststab = xCAT::Table->new( 'hosts');
        my $ent = $hoststab->getNodeAttribs( $nodetocheck, ['ip'] );
        if ( $ent->{'ip'} ) {
            $nodeip = $ent->{'ip'};
        }
    }
            
    if ( $nodeip ) {
        return $nodeip;
    } else {
        return undef;
    }
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
    if ( $^O eq 'aix')
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
       $cmd="ip -4 --oneline addr show |awk -F ' ' '{print \$4}'|awk -F '/' '{print \$1}'";
       my @result =xCAT::Utils->runcmd($cmd);
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
             my $v6ip = $1;
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
    for my $entry ( @netstat_res)
    {
#We need to find entries like:
#Destination        Gateway           Flags   Refs     Use  If   Exp  Groups
#9.114.47.192/27    9.114.47.205      U         1         1 en0
#4000::/64          link#4            UCX       1         0 en2      -      - 
        my ( $net, $netmask, $flag, $nic);
        if ( $entry =~ /^\s*([\d\.]+)\/(\d+)\s+[\d\.]+\s+(\w+)\s+\d+\s+\d+\s(\w+)/)
        {
            ( $net, $netmask, $flag, $nic) = ($1,$2,$3,$4);
            my @dotsec = split /\./, $net;
            for ( my $i = 4; $i > scalar(@dotsec); $i--)
            {
                $net .= '.0';
            }
            push @aix_nrn, "$net:$nic:$netmask:$flag" if ($net ne '127.0.0.0');
        }
        elsif ($entry =~ /^\s*([\dA-Fa-f\:]+)\/(\d+)\s+.*?\s+(\w+)\s+\d+\s+\d+\s(\w+)/)
        {
            #print "=====$entry====\n";
            ( $net, $netmask, $flag, $nic) = ($1,$2,$3,$4);
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
    my $hostnamecmd = "/bin/hostname";
    my @thostname = xCAT::Utils->runcmd($hostnamecmd, 0);
    if ($::RUNCMD_RC != 0)
    {    # could not get hostname
        xCAT::MsgUtils->message("S",
                              "Error $::RUNCMD_RC from $hostnamecmd command\n");
        exit $::RUNCMD_RC;
    }
    $hostname = $thostname[0];

    #get all potentially valid abbreviations, and pick the one that is ok
    #by 'noderange'
    my @hostnamecandidates;
    my $nodename;
    while ($hostname =~ /\./) {
        push @hostnamecandidates,$hostname;
        $hostname =~ s/\.[^\.]*//;
    }
    push @hostnamecandidates,$hostname;
    my $checkhostnames = join(',',@hostnamecandidates);
    my @validnodenames = xCAT::NodeRange::noderange($checkhostnames);
    unless (scalar @validnodenames) { #If the node in question is not in table, take output literrally.
        push @validnodenames,$hostnamecandidates[0];
    }
    #now, noderange doesn't guarantee the order, so we search the preference order, most to least specific.
    foreach my $host (@hostnamecandidates) {
        if (grep /^$host$/,@validnodenames) {
            $nodename = $host;
            last;
        }
    }
    my @ips       = xCAT::NetworkUtils->gethost_ips;
    my @hostinfo  = (@ips, $nodename);

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
        return ([0, $_[0]]);
    }
    my $ip = xCAT::NetworkUtils->getipaddr($_[0]);
    if (!$ip)
    {
        return ([1, "Cannot Resolve: $_[0]\n"]);
    }
    return ([0, $ip]);
}

#-------------------------------------------------------------------------------

=head3    validate_ip
    Validate list of IPs
    Arguments:
        List of IPs
    Returns:
        1 - Invalid IP address in the list
        0 - IP addresses are all valid
    Globals:
        none
    Error:
        none
    Example:
        if (xCAT::NetworkUtils->validate_ip($IP)) {}
    Comments:
        none
=cut

#-------------------------------------------------------------------------------
sub validate_ip
{
    my ($class, @IPs) = @_;
    foreach (@IPs) {
        my $ip = $_;
        #TODO need more check for IPv6 address
        if ($ip =~ /:/)
        {
            return([0]);
        }
        ###################################
        # Length is 4 for IPv4 addresses
        ###################################
        my (@octets) = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
        if ( scalar(@octets) != 4 ) {
            return( [1,"Invalid IP address1: $ip"] );
        }
        foreach my $octet ( @octets ) {
            if (( $octet < 0 ) or ( $octet > 255 )) {
                return( [1,"Invalid IP address2: $ip"] );
            }
        }
    }
    return([0]);
}
#-------------------------------------------------------------------------------

=head3    isIpaddr

    returns 1 if parameter is has a valid IP address form.

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
sub isIpaddr
{
    my $addr = shift;
    if (($addr) && ($addr =~ /xCAT::NetworkUtils/))
    {
        $addr = shift;
    }

    unless ( $addr )
    {
        return 0;
    }
    #print "addr=$addr\n";
    if ($addr !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
    {
        return 0;
    }

    if ($1 > 255 || $1 == 0 || $2 > 255 || $3 > 255 || $4 > 255)
    {
        return 0;
    }
    else
    {
        return 1;
    }
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
sub getNodeNameservers{
    my $nodes=shift;
    if( $nodes =~ /xCAT::NetworkUtils/)
    {
      $nodes=shift;
    }
    my @nodelist = @$nodes;
    my %nodenameservers;
    my $nrtab = xCAT::Table->new('noderes',-create=>0);
    my %nrhash = %{$nrtab->getNodesAttribs(\@nodelist,['nameservers'])};
    
    my $nettab = xCAT::Table->new("networks");
    my %nethash = xCAT::DBobjUtils->getNetwkInfo( \@nodelist );

    my @nameservers = xCAT::TableUtils->get_site_attribute("nameservers");
    my $sitenameservers=$nameservers[0];


    foreach my $node (@nodelist){
       if ($nrhash{$node} and $nrhash{$node}->[0] and $nrhash{$node}->[0]->{nameservers})
       {
           $nodenameservers{$node}=$nrhash{$node}->[0]->{nameservers};
       }elsif($nethash{$node}{nameservers})
       {
           $nodenameservers{$node}=$nethash{$node}{nameservers};
       }elsif($sitenameservers)
       {
           $nodenameservers{$node}=$sitenameservers;
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
    if( $node =~ /xCAT::NetworkUtils/)
    {
       $node =shift;
    }

    my $ip   = xCAT::NetworkUtils->getipaddr($node);
    my $mask = undef;
    my $gateway = undef;

    my $nettab = xCAT::Table->new("networks");
    if ($nettab) {
	   my @nets = $nettab->getAllAttribs('net','mask','gateway');
	   foreach my $net (@nets) {
	      if (xCAT::NetworkUtils::isInSameSubnet( $net->{'net'}, $ip, $net->{'mask'}, 0)) {
	          $gateway=$net->{'gateway'};
	          $mask=$net->{'mask'};
	       }
	   }
    }
 
    return ($ip, $node, $gateway, xCAT::NetworkUtils::formatNetmask($mask,0,0));
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

    my $ip_tmp_res  = xCAT::NetworkUtils::toIP($node);
    ($Rc, $ip) = @$ip_tmp_res;
    if ( $Rc ) {
        my $hosttab  = xCAT::Table->new( 'hosts' );
        if ( $hosttab) {
            my $node_ip_hash = $hosttab->getNodeAttribs( $node,[qw(ip)]);
            $ip = $node_ip_hash->{ip};
        }
	
    }
     
    if (!$ip) {
        return undef;
    }

    return $ip;
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
    my ($class, @mon_nodes)=@_;
    my %status=();
    my @active_nodes=();
    my @inactive_nodes=();
    #print "NetworkUtils->pingNodeStatus called, nodes=@mon_nodes\n";
    if ((@mon_nodes)&& (@mon_nodes > 0)) {
	#get all the active nodes
	my $nodes= join(' ', @mon_nodes);
	if (-x '/usr/bin/nmap' or -x '/usr/local/bin/nmap') { #use nmap
	    #print "use nmap\n";
	    my %deadnodes;
	    foreach (@mon_nodes) {
		$deadnodes{$_}=1;
	    }	 

		# get additional options from site table
		my @nmap_options = xCAT::TableUtils->get_site_attribute("nmapoptions"); 
		my $more_options = $nmap_options[0];

        #call namp
	    open (NMAP, "nmap -PE --system-dns --send-ip -sP $more_options ". $nodes . " 2> /dev/null|") or die("Cannot open nmap pipe: $!");
	    my $node;
	    while (<NMAP>) {
		if (/Host (.*) \(.*\) appears to be up/) {
		    $node=$1;
		    unless ($deadnodes{$node}) {
			foreach (keys %deadnodes) {
			    if ($node =~ /^$_\./) {
				$node = $_;
				last;
			    }
			}
		    }
		    delete $deadnodes{$node};
		    push(@active_nodes, $node);
		} elsif (/Nmap scan report for ([^ ]*) /) {
		    $node=$1;
		} elsif (/Host is up./) {
		    unless ($deadnodes{$node}) {
			foreach (keys %deadnodes) {
			    if ($node =~ /^$_\./) {
				$node = $_;
			      last;
			    }
			}
		    }
		    delete $deadnodes{$node};
		    push(@active_nodes, $node);
		}
	    }
	    foreach (sort keys %deadnodes) {
	      push(@inactive_nodes, $_);
	    }
	} else { #use fping
	    #print "use fping\n";

	    my $temp=`fping -a $nodes 2> /dev/null`;
	    chomp($temp);
	    @active_nodes=split(/\n/, $temp);
	    
	    #get all the inactive nodes by substracting the active nodes from all.
	    my %temp2;
	    if ((@active_nodes) && ( @active_nodes > 0)) {
		foreach(@active_nodes) { $temp2{$_}=1};
		foreach(@mon_nodes) {
		    if (!$temp2{$_}) { push(@inactive_nodes, $_);}
		}
	    }
	    else {@inactive_nodes=@mon_nodes;}
	}     
    }
    
    $status{$::STATUS_ACTIVE}=\@active_nodes;
    $status{$::STATUS_INACTIVE}=\@inactive_nodes;
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
    if ($macstr =~ /^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$/){
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
    if ($hostname =~ /^[a-z0-9]/){
        if ($hostname =~ /[a-z0-9]$/){
            if ($hostname =~ /^[\-a-z0-9]+$/){
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
    if ($hostname =~ /^[a-z0-9][\.\-a-z0-9]+[a-z0-9]$/){
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
    my $ipint = xCAT::NetworkUtils->ip_to_int($ipstr);
    my $maskint = xCAT::NetworkUtils->ip_to_int($netmask);
    my $tmp = sprintf("%d", ~$maskint);
    my $bcnum = sprintf("%d", ($ipint | $tmp) & hex('0x00000000FFFFFFFF'));
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
    my $class = shift;
    my $startip = shift;
    my $endip = shift;
    my $increment = shift;
    my @iplist = ();
    my $tmpip;

    my $startipnum = xCAT::NetworkUtils->ip_to_int($startip);
    my $endipnum = xCAT::NetworkUtils->ip_to_int($endip);

    if ($increment > 0){
        while ($startipnum <= $endipnum){
            $tmpip = xCAT::NetworkUtils->int_to_ip($startipnum);
            $startipnum += $increment;
            push (@iplist, $tmpip);
        }
    }elsif($increment < 0){
        while ($endipnum >= $startipnum){
            $tmpip = xCAT::NetworkUtils->int_to_ip($endipnum);
            $endipnum += $increment;
            push (@iplist, $tmpip);
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
sub get_all_nicips{
    my ($class, $hashref) = @_;
    my %allipshash;
    my @allipslist;

    my $table = xCAT::Table->new('nics');
    my @entries = $table->getAllNodeAttribs(['nicips']);
    foreach (@entries){
        # $_->{nicips} looks like "eth0:ip1,eth1:ip2,bmc:ip3..."
        if($_->{nicips}){
            my @nicandiplist = split(',', $_->{nicips});
            # Each record in @nicandiplist looks like "eth0:ip1"
			# delimiter has been changed to use "!"  in xCAT 2.8
            foreach (@nicandiplist){
				my @nicandip;
				if ($_  =~ /!/) {
					@nicandip = split('!', $_);
				} else {
					@nicandip = split(':', $_);
				}
                if ($hashref){
                    $allipshash{$nicandip[1]} = 0;
                } else{
                    push (@allipslist, $nicandip[1]);
                }
            }
        }
    }
    if ($hashref){
        return \%allipshash;
    } else{
        return \@allipslist;
    }
}



1;
