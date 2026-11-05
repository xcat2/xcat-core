# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# The first module to deal with hardware discovery request, write the request into "discoverydata" table only
package xCAT_plugin::aaadiscovery;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::DiscoveryUtils;
use xCAT::NetworkUtils;

sub handled_commands {
    return {
        findme => 'aaadiscovery',
    };
}

sub process_request {
    my $req   = shift;
    my $cb    = shift;
    my $doreq = shift;
    if ($req->{command}->[0] eq 'findme') {
        if (defined($req->{discoverymethod}) and defined($req->{discoverymethod}->[0])) {
            my $rsp = {};
            $rsp->{error}->[0] = "The findme request had been processed by " . $req->{discoverymethod}->[0] . " module";
            $cb->($rsp);
            return;
        }
        my $client_ip = $req->{'_xcat_clientip'};

        # arp(8) prints the IPv4 table only, and the address used to be interpolated
        # into a regular expression, where every dot matched any character.
        my $mac;
        $mac = xCAT::NetworkUtils->mac_of_neighbour($client_ip);
        unless ($mac) {
            xCAT::MsgUtils->message("S", "xcat.discovery.aaadiscovery: Failed to get MAC address for $client_ip in arp cache.");
            $mac = "$req->{mtm}->[0]*$req->{serial}->[0]";
        }

        xCAT::MsgUtils->message("S", "xcat.discovery.aaadiscovery: ($mac) Got a discovery request, attempting to discover the node...");
        $req->{discoverymethod}->[0] = 'undef';
        $req->{_xcat_clientmac}->[0] = $mac;
        #Workaround (#4890) for IP changed cases.
        xCAT::NetworkUtils->clearcache();
        xCAT::DiscoveryUtils->update_discovery_data($req);
        return;
    }
}

1;
