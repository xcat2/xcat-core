# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# Used to deal with MTMS(machine-type/model and serial) based hardware discovery
package xCAT_plugin::typemtms;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

sub handled_commands {
    return {
        findme => 'typemtms',
    };
}

sub findme {
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    if (!defined $request->{'mtm'} or !defined $request->{'serial'}) {
        xCAT::MsgUtils->message("S", "Discovery Error: 'mtm' or 'serial' not found.");
        return;
    }
    my @attr_array = ();
    my $mtms       = $request->{'mtm'}->[0] . "*" . $request->{'serial'}->[0];
    my $tmp_nodes  = $::XCATVPDHASH{$mtms};
    my @nodes      = ();
    my $bmc_node;
    foreach (@$tmp_nodes) {
        if ($::XCATMPHASH{$_}) {
            $bmc_node = $_;
        } else {
            push @nodes, $_;
        }
    }
    my $nodenum = $#nodes;
    if ($nodenum < 0) {
        xCAT::MsgUtils->message("S", "xcat.discovery.mtms: ($request->{_xcat_clientmac}->[0]) Warning: Could not find any node for $mtms matching using mtms-based discovery");
        return;
    } elsif ($nodenum > 0) {
        xCAT::MsgUtils->message("S", "xcat.discovery.mtms: ($request->{_xcat_clientmac}->[0]) Error: More than one node for $mtms was found");
        return;
    }
    {
        xCAT::MsgUtils->message("S", "xcat.discovery.mtms: ($request->{_xcat_clientmac}->[0]) Found node: $nodes[0]");
        $request->{discoverymethod}->[0] = 'mtms';
        my $req = {%$request};
        $req->{command}   = ['discovered'];
        $req->{noderange} = [ $nodes[0] ];
        $req->{bmc_node}  = [$bmc_node];
        $subreq->($req);
        %{$req} = ();
    }
}

sub process_request {
    my $req   = shift;
    my $cb    = shift;
    my $doreq = shift;
    if ($req->{command}->[0] eq 'findme') {
        if (defined($req->{discoverymethod}) and defined($req->{discoverymethod}->[0]) and ($req->{discoverymethod}->[0] ne 'undef')) {

            # The findme request had been processed by other module, just return
            return;
        }
        &findme($req, $callback, $doreq);
        return;
    }
}
1;
