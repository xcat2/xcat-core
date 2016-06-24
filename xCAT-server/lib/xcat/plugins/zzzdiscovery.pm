# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
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
    my $req = shift;
    my $cb = shift;
    my $doreq = shift;
    if ($req->{command}->[0] eq 'findme') {
        # The findme request is supposed to be dealt with in the first loop that cacheonly attribute is set for a request
        if (!($req->{cacheonly}) or !($req->{cacheonly}->[0])) {
            return;
        }
        xCAT::MsgUtils->message("S", __PACKAGE__.": Processing findme request");
        if (!defined($req->{discoverymethod}) or !defined($req->{discoverymethod}->[0]))  {
            my $rsp = {};
            $rsp->{error}->[0] = "The findme request can not be processed";
            $cb->($rsp);
            return;
        }
        xCAT::MsgUtils->message("S", __PACKAGE__.": This findme request had been processed by $req->{discoverymethod}->[0] module");
        return;
    }
}
1;
