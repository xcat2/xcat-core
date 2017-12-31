#!/usr/bin/env perl
# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::DiscoveryUtils;

use strict;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

use xCAT::MsgUtils;

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

1;
