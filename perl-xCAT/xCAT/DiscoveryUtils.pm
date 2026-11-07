#!/usr/bin/env perl
# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::DiscoveryUtils;

use strict;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

use xCAT::MsgUtils;

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

1;
