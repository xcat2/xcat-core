#!/usr/bin/env perl

# The Ubuntu counterpart of service_node_artifacts_el.t: render the artifacts an Ubuntu service
# node needs and assert each, so the fast oracle fails for any wrong artifact rather than only
# for the defects someone has already hit.
#
# It exists because the first Ubuntu oracle dropped two real fixes. The apt test measured apt's
# behaviour rather than the line the postscript writes, and nothing asserted the export line at
# all, although casper mounts the install tree over NFS from the service node.

use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

# get_file_name takes genos LAST, and update_tables_with_templates passes 'subiquity' for every
# Ubuntu 20.04 and later osimage. Passing the os version there resolves the preseed instead, which
# is the mistake this test would otherwise make about its own subject.
my %SN = (osver => 'ubuntu24.04', arch => 'x86_64', profile => 'service', genos => 'subiquity');
my $SHARE = "$FindBin::Bin/../../xCAT-server/share/xcat/install";

my $have = eval { require xCAT::SvrUtils; 1 } ? 1 : 0;
ok($have, 'xCAT::SvrUtils loads') or do { done_testing(); exit 1 };

# 1. The installer. Ubuntu 20.04 and later install with Subiquity, and xCAT decides that from the
#    NAME of the template it resolved. Without a service.subiquity.tmpl the service profile falls
#    back to the debian-installer preseed and the node boots the live image without casper.
my $tmpl = xCAT::SvrUtils::get_tmpl_file_name("$SHARE/ubuntu", $SN{profile}, $SN{osver},
                                              $SN{arch}, $SN{genos});
ok(defined $tmpl && length $tmpl, 'the Ubuntu service profile resolves a template');
like($tmpl, qr{subiquity}, '... and it is a Subiquity template, or the node never installs');
like($tmpl, qr{/service[^/]*\.tmpl$}, '... of the service profile, not compute');

# The compute profile must keep resolving too: an assertion that only ever looks at one profile
# cannot tell a profile fix from a lookup fix.
my $compute = xCAT::SvrUtils::get_tmpl_file_name("$SHARE/ubuntu", 'compute', $SN{osver},
                                                 $SN{arch}, $SN{genos});
like($compute, qr{subiquity}, 'the compute profile still resolves its own Subiquity template');

# 2. The NFS export. casper mounts the install tree from the service node, so a service node that
#    exports nothing stops the compute node at "Unable to find a live file system on the network".
my $can_export = xCAT::SvrUtils->can('nfs_export_line') ? 1 : 0;
ok($can_export, 'SvrUtils can render an export line, without which casper finds no filesystem');

SKIP: {
    skip 'nfs_export_line absent', 3 unless $can_export;
    my $re = xCAT::SvrUtils->nfs_export_line('/install', reexport => 1);
    like($re, qr{\bfsid=\d+},   're-exporting the mounted /install carries an fsid');
    like($re, qr{\bcrossmnt\b}, '... and crossmnt');
    like($re, qr{\bno_root_squash\b}, '... and no_root_squash, which the installer needs');
}

done_testing();
