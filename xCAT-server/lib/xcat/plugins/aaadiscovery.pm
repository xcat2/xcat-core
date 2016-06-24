# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::aaadiscovery;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::DiscoveryUtils;

sub handled_commands {
    return {
        findme => 'aaadiscovery',
    };
}

sub process_request {
    my $req = shift;
    my $cb = shift;
    my $doreq = shift;
    if ($req->{command}->[0] eq 'findme') {
        # The findme request is supposed to be dealt with in the first loop that cacheonly attribute is set for a request
        if (!($req->{cacheonly}) or !($req->{cacheonly}->[0])) {
            return;
        }
        if (defined($req->{discoverymethod}) and defined($req->{discoverymethod}->[0]))  {
            my $rsp = {};
            $rsp->{error}->[0] = "The findme request had been processed by ".$req->{discoverymethod}->[0] ." module";
            $cb->($rsp);
            return;
        }
        xCAT::MsgUtils->message("S", __PACKAGE__.": Processing findme request, writting it into 'discoverydata' table");
        $req->{discoverymethod}->[0] = 'undef';
        xCAT::DiscoveryUtils->update_discovery_data($req);
        return;
    }
}

1;
