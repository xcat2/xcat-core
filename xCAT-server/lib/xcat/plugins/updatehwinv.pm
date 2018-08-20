#!/usr/bin/perl
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::updatehwinv;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";
use xCAT::Table;
use xCAT::Utils;
use xCAT::NodeRange;

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return {
        updatehwinv => 'updatehwinv',
    };
}

sub process_request {
    my $req      = shift;
    my $callback = shift;

    if ($req->{command}->[0] eq "updatehwinv") {
        update_hw_inv($req);
    }
}

sub update_hw_inv {
    my $request    = shift;
    my $tmp_node   = $request->{'_xcat_clienthost'}->[0];
    my @valid_node = xCAT::NodeRange::noderange($tmp_node);

    unless (@valid_node) {
        xCAT::MsgUtils->message("S", "xcat.hwinv: Received invalid node $tmp_node hwinv info, ignore...");
        return;
    }

    my $node = $valid_node[0];

    my @nodefs;
    my $basicdata;

    my @hwinv_info = ("cpucount", "cputype", "memory", "disksize");

    foreach my $hwinv_type (@hwinv_info) {
        if (defined($request->{$hwinv_type}) and $request->{$hwinv_type}->[0]) {
            $basicdata->{$hwinv_type} = $request->{$hwinv_type}->[0];
        } else {
            push @nodefs, $hwinv_type;
        }
    }

    if ($basicdata) {
        my $hwinv_tab = xCAT::Table->new("hwinv", -create => 1);
        xCAT::MsgUtils->message("S", "xcat.hwinv: Update hwinv for $node");
        $hwinv_tab->setNodeAttribs($node, $basicdata);
    }
    if (@nodefs) {
        my $nodef = join(",", @nodefs);
        xCAT::MsgUtils->message("E", "xcat.hwinv: No valid hwinv info $nodef received from $node");
    }
}

1;
