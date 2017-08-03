# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# The last module to deal with hardware discovery request, write information that which module can deal with this request or no module can deal with it at all
package xCAT_plugin::zzzdiscovery;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

sub handled_commands {
    return {
        findme => 'zzzdiscovery',
    };
}

sub process_request {
    my $req   = shift;
    my $cb    = shift;
    my $doreq = shift;
    if ($req->{command}->[0] eq 'findme') {

        if (!defined($req->{discoverymethod}) or !defined($req->{discoverymethod}->[0]) or ($req->{discoverymethod}->[0] eq 'undef')) {
            my $rsp = {};
            $rsp->{error}->[0] = "The discovery request can not be processed";
            $cb->($rsp);
            xCAT::MsgUtils->message("S", "xcat.discovery.zzzdiscovery: ($req->{_xcat_clientmac}->[0]) Failed to discover the node.");

            #now, notify the node that its findme request has been processed
            my $client_ip = $req->{'_xcat_clientip'};
            xCAT::MsgUtils->message("S","Notify $client_ip that its findme request has been processed");
            my $sock = new IO::Socket::INET(
                PeerAddr => $client_ip,
                PeerPort => '3001',
                Timeout  => '1',
                Proto    => 'tcp'
            );
            if ($sock) { 
                print $sock "processed";
                close($sock);
            }else{
                xCAT::MsgUtils->message("S", "Failed to notify $client_ip that its findme request has been processed"); 
            }
        }else{
            xCAT::MsgUtils->message("S", "xcat.discovery.zzzdiscovery: ($req->{_xcat_clientmac}->[0]) Successfully discovered the node using $req->{discoverymethod}->[0] discovery method.");
        }

        return;
    }
}
1;
