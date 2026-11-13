#!/usr/bin/env perl
# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::DiscoveryUtils;

use strict;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

use xCAT::MsgUtils;
use xCAT::NetworkUtils;
use Socket qw(AF_INET6 inet_aton inet_ntoa inet_pton inet_ntop);

sub is_findme_request {
    my ($request) = @_;

    return 0 unless ref $request eq 'HASH';
    return 0 unless ref $request->{command} eq 'ARRAY';
    return 0 unless defined $request->{command}->[0];
    return $request->{command}->[0] eq 'findme';
}

sub findme_request_for_handler {
    my ($request) = @_;

    return unless is_findme_request($request);
    return [$request];
}

sub findme_request_is_claimed {
    my ($request) = @_;

    return 0 unless is_findme_request($request);
    return 0 unless ref $request->{discoverymethod} eq 'ARRAY';
    return 0 unless defined $request->{discoverymethod}->[0];
    return $request->{discoverymethod}->[0] ne 'undef';
}

=head3 update_discovery_data
 Update the discovery data from the xcat request to discoverydata table to indicate the discovery events
 arg1 - the request

=cut

sub update_discovery_data {
    my $class   = shift;
    my $request = shift;

    my %disdata;
    my %otherdata;

    unless ($request->{'uuid'}->[0]) {
        xCAT::MsgUtils->message("S", "Discovery Error: Found a node without uuid");
    }

    if ($request->{'discoverymethod'}->[0]) {
        $disdata{'method'} = $request->{'discoverymethod'}->[0];
    } else {
        $disdata{'method'} = "undef";
    }

    #discoverytime
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
        $mon + 1, $mday, $year + 1900, $hour, $min, $sec);
    $disdata{'discoverytime'} = $currtime;

    foreach my $attr (keys %$request) {
        if ($attr =~ /^(command|discoverymethod|_xcat|cacheonly|noderange|environment|method|discoverytime|updateswitch)/) {
            next;
        } elsif ($attr =~ /^(node|uuid|arch|cpucount|cputype|memory|mtm|serial)$/) {
            $disdata{$attr} = $request->{$attr}->[0];
        } elsif ($attr eq 'nic') {

            # Set the nics attributes
            foreach my $nic (@{ $request->{nic} }) {
                my $nicname = $nic->{'devname'}->[0];
                foreach my $nicattr (keys %$nic) {
                    my $tbattr;
                    if ($nicattr eq 'driver') {
                        $tbattr = "nicdriver";
                    } elsif ($nicattr eq 'ip4address') {
                        $tbattr = "nicipv4";
                    } elsif ($nicattr eq 'hwaddr') {
                        $tbattr = "nichwaddr";
                    } elsif ($nicattr eq 'pcidev') {
                        $tbattr = "nicpci";
                    } elsif ($nicattr eq 'location') {
                        $tbattr = "nicloc";
                    } elsif ($nicattr eq 'onboardeth') {
                        $tbattr = "niconboard";
                    } elsif ($nicattr eq 'firmdesc') {
                        $tbattr = "nicfirm";
                    } elsif ($nicattr =~ /^(switchname|switchaddr|switchdesc|switchport)$/) {
                        $tbattr = $nicattr;
                    }

                    if ($tbattr) {
                        if ($disdata{$tbattr}) {
                            $disdata{$tbattr} .= ',' . $nicname . '!' . $nic->{$nicattr}->[0];
                        } else {
                            $disdata{$tbattr} = $nicname . '!' . $nic->{$nicattr}->[0];
                        }
                    }
                }
            }
        } else {

            # store to otherdata for the not parsed attributes
            $otherdata{$attr} = $request->{$attr};
        }
    }

    if (keys %otherdata) {
        $disdata{'otherdata'} = XMLout(\%otherdata, RootName => 'discoveryotherdata', NoAttr => 1);
    }

    my $distab = xCAT::Table->new('discoverydata');
    if ($distab) {
        $distab->setAttribs({ uuid => $request->{'uuid'}->[0] }, \%disdata);
        $distab->close();
    }
}

#-------------------------------------------------------------------------------

=head3 client_certificate_name

    Descriptions: The name xcatd may record as the verified client certificate of a request.
                  becomeuser and tokens replace the authenticated name with an account name.
                  A name that differs from the certificate CN is therefore not a certificate name.

    Arguments   : $cert_cn  - the CN of the client certificate, undef when there is none
                  $authname - the authenticated name xcatd uses for the request
    Returns     : $cert_cn when the request is still authenticated by that certificate, else undef

=cut

#-------------------------------------------------------------------------------
sub client_certificate_name {
    my ($cert_cn, $authname) = @_;
    return undef unless defined $cert_cn && $cert_cn ne '';
    return undef unless defined $authname && $authname eq $cert_cn;
    return $cert_cn;
}

#-------------------------------------------------------------------------------

=head3 request_client_names

    Descriptions: The names a node-initiated request offers for correlating it to a node, most
                  trustworthy first.

                  xcatd fills _xcat_clienthost and _xcat_clientfqdn from a reverse lookup of the
                  peer socket, so both are empty when that lookup fails.
                  _xcat_certname is the CN of the validated client certificate.
                  _xcat_authname is not a candidate: a password or a token can set it.
                  The request's own node attribute is not a candidate: the client sends it.

    Arguments   : $request - the request hash xcatd built
    Returns     : the candidate names, without duplicates; an empty list when there are none

=cut

#-------------------------------------------------------------------------------
sub request_client_names {
    my ($request) = @_;
    return () unless ref($request) eq 'HASH';
    my @names;
    foreach my $key (qw(_xcat_clienthost _xcat_clientfqdn _xcat_certname)) {
        my $name = _first_value($request, $key);
        next unless defined $name;
        push @names, $name unless grep { $_ eq $name } @names;
    }
    return @names;
}

#-------------------------------------------------------------------------------

=head3 request_client_node

    Descriptions: The node a node-initiated request comes from.
                  A peer name is expanded as before, and the first node it gives is used.
                  The certificate name must name exactly one node, with no group or range
                  expansion, because xCAT signs user and node certificates with one CA.

    Arguments   : $request - the request hash xcatd built
                  $expand  - code ref that expands a noderange to a node list (noderange)
    Returns     : the node name, or undef when no candidate names a node

=cut

#-------------------------------------------------------------------------------
sub request_client_node {
    my ($request, $expand) = @_;
    return undef unless ref($request) eq 'HASH' && ref($expand) eq 'CODE';
    foreach my $key (qw(_xcat_clienthost _xcat_clientfqdn)) {
        my $name = _first_value($request, $key);
        next unless defined $name;
        my ($node) = $expand->($name);
        return $node if $node;
    }
    my $cert = _first_value($request, '_xcat_certname');
    return undef unless defined $cert;
    my @nodes = $expand->($cert);
    return $cert if @nodes == 1 && defined $nodes[0] && $nodes[0] eq $cert;
    return undef;
}

sub _first_value {
    my ($request, $key) = @_;
    my $value = $request->{$key};
    return undef unless ref($value) eq 'ARRAY';
    my $name = $value->[0];
    return undef unless defined $name && $name ne '';
    return $name;
}

#--------------------------------------------------------------------------------

=head3  vpd_attribs_from_findme

      The vpd attributes a findme request carries for the node it discovers.

    Arguments:
      the findme request
    Returns:
      a hash reference of vpd attributes, empty when the request carries none

=cut

#--------------------------------------------------------------------------------
sub vpd_attribs_from_findme
{
    my $request = shift;
    if ( defined($request) && !ref($request) && $request eq __PACKAGE__ )
    {
        $request = shift;
    }
    return {} unless ref($request) eq 'HASH';

    my $uuid = $request->{uuid};
    $uuid = $uuid->[0] if ref($uuid) eq 'ARRAY';
    return {} unless defined($uuid);

    # The OpenEmbedded image synthesises "<machine type>-<serial>-<first mac>" when the firmware
    # reports no product_uuid. dhcp6_client_duids builds a DUID-UUID from this value, and a DUID
    # built from that string matches no client, so only the SMBIOS form is recorded.
    return {} unless $uuid =~ /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

    return { uuid => lc($uuid) };
}

#--------------------------------------------------------------------------------

=head3  discovery_address_usable

      Can discovery record a node whose address is this?

    Arguments:
      the address a node resolved to
    Returns:
      1 when the address names a node, 0 when it does not

=cut

#--------------------------------------------------------------------------------
sub discovery_address_usable
{
    my $address = shift;
    $address = shift if defined($address) && !ref($address) && $address eq __PACKAGE__;
    return 0 unless defined($address) && length($address);

    # A scoped link-local names an interface, not a node on the provisioning network.
    return 0 if index( $address, '%' ) >= 0;
    return 1 if xCAT::NetworkUtils->isIpaddr($address);
    return 1 if xCAT::NetworkUtils->isIpv6addr($address);
    return 0;
}

#--------------------------------------------------------------------------------

=head3  nic_network_key

      The network a discovered NIC is on, as a string two NICs on one network share.

    Arguments:
      the address of the NIC, and the prefix length
    Returns:
      the network address, or undef when the value is no address

=cut

#--------------------------------------------------------------------------------
sub nic_network_key
{
    my $address = shift;
    $address = shift if defined($address) && !ref($address) && $address eq __PACKAGE__;
    my ($netbits) = @_;

    return undef unless defined($address) && length($address);
    $netbits = 0 unless defined($netbits) && $netbits =~ /\A\d+\z/;

    if ( xCAT::NetworkUtils->isIpaddr($address) ) {

        # The arithmetic the caller used before, kept so an IPv4 key does not move.
        my $ipn  = unpack( "N", inet_aton($address) );
        my $mask = $netbits ? ( 2**$netbits - 1 << ( 32 - $netbits ) ) : 0;
        return inet_ntoa( pack( "N", $ipn & $mask ) );
    }

    return undef if index( $address, '%' ) >= 0;
    return undef unless xCAT::NetworkUtils->isIpv6addr($address);

    my $packed = inet_pton( AF_INET6, $address );
    return undef unless defined($packed) && length($packed) == 16;

    # Mask bits, not bytes: a /60 keeps half of the fourth group.
    my @byte = unpack( "C16", $packed );
    foreach my $i ( 0 .. 15 ) {
        my $bits = $netbits - $i * 8;
        if    ( $bits <= 0 ) { $byte[$i] = 0; }
        elsif ( $bits < 8 )  { $byte[$i] &= ( 0xFF << ( 8 - $bits ) ) & 0xFF; }
    }
    return inet_ntop( AF_INET6, pack( "C16", @byte ) );
}

#--------------------------------------------------------------------------------

=head3  ipv6_networks

      The IPv6 networks of networks table rows, as [network, prefix length] pairs.

    Arguments:
      the rows, each a hash with net and mask. An IPv6 net may carry its own /len, and an
      IPv6 mask is written /len.
    Returns:
      an arrayref of pairs

=cut

#--------------------------------------------------------------------------------
sub ipv6_networks
{
    my $rows = shift;
    $rows = shift if defined($rows) && !ref($rows) && $rows eq __PACKAGE__;

    my @networks;
    foreach my $row ( @{ $rows || [] } ) {
        my ( $net, $bits ) = split m{/}, ( $row->{net} || '' ), 2;
        next unless defined($net) && xCAT::NetworkUtils->isIpv6addr($net);
        ($bits) = ( $row->{mask} || '' ) =~ m{\A/?(\d+)\z} unless defined($bits) && length($bits);
        next unless defined($bits) && $bits =~ /\A\d+\z/ && $bits <= 128;
        push @networks, [ $net, $bits ];
    }
    return \@networks;
}

#--------------------------------------------------------------------------------

=head3  hosttag_for_ipv6_nic

      The hostname tag a discovered IPv6 NIC takes.

      gethosttag reads an A record and my_if_netmap, which prints IPv4 routes only, so the
      decision for an IPv6 NIC is made from the addresses: a NIC on the network of the node is
      the node, and that is what marks the node reachable on the provisioning network.

    Arguments:
      the node, its address, the interface name, the address of the NIC, the prefix length,
      the names already taken, and the IPv6 networks of the networks table as
      [network, prefix length] pairs
    Returns:
      the node, an interface-qualified name, or undef when the NIC is on another network

=cut

#--------------------------------------------------------------------------------
sub hosttag_for_ipv6_nic
{
    my $node = shift;
    $node = shift if defined($node) && !ref($node) && $node eq __PACKAGE__;
    my ( $nodeaddr, $ifname, $nicaddr, $netbits, $usednames, $networks ) = @_;

    return undef unless defined($node) && length($node);
    return undef unless defined($nicaddr) && length($nicaddr);

    # The IPv4 path owns an IPv4 NIC, and its hostname rules are not reproduced here.
    return undef if xCAT::NetworkUtils->isIpaddr($nicaddr);
    return undef unless discovery_address_usable($nodeaddr);
    return undef if xCAT::NetworkUtils->isIpaddr($nodeaddr);

    my $nicnet  = nic_network_key( $nicaddr,  $netbits );
    my $nodenet = nic_network_key( $nodeaddr, $netbits );
    my $same = defined($nicnet) && defined($nodenet) && $nicnet eq $nodenet;

    # NetworkManager installs a DHCPv6 lease as a /128. That prefix names one address and no
    # network, so take the network from the networks table instead.
    if ( !$same && defined($netbits) && $netbits eq '128' ) {
        foreach my $network ( @{ $networks || [] } ) {
            my ( $net, $bits ) = @$network;
            my $key = nic_network_key( $net, $bits );
            next unless defined($key);
            my $nic  = nic_network_key( $nicaddr,  $bits );
            my $node = nic_network_key( $nodeaddr, $bits );
            if ( defined($nic) && defined($node) && $nic eq $key && $node eq $key ) {
                $same = 1;
                last;
            }
        }
    }
    return undef unless $same;

    return $node unless $usednames && $usednames->{$node};
    return "$node-$ifname" if defined($ifname) && length($ifname);
    return undef;
}

1;
