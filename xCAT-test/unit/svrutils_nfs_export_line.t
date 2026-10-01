#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# A service node with servicenode.nfsserver=1 is asked to "set up file services on this service
# node". When site.installloc is set it MOUNTS /install from the management node, and AAsn.pm
# then exported nothing at all, so the node served no NFS. An Ubuntu compute node boots the live
# installer with casper, which mounts the install tree over NFS from its own service node, and it
# stopped at "Unable to find a live file system on the network". Measured on xcat22-sn:
# showmount -e returned an empty list and /etc/exports was empty while nfs-kernel-server was
# active.
#
# Re-exporting an NFS mount is not the same as exporting a local directory. Linux requires an
# explicit fsid, because it cannot derive one from the underlying filesystem, and refuses the
# export without it.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::SvrUtils;

can_ok('xCAT::SvrUtils', 'nfs_export_line') or done_testing() && exit;

my $local = xCAT::SvrUtils->nfs_export_line('/install');
is($local, '/install *(rw,no_root_squash,sync,no_subtree_check,insecure)',
    'a local directory keeps the options xCAT has always written');

my $reexport = xCAT::SvrUtils->nfs_export_line('/install', reexport => 1);
like($reexport, qr{^/install \*\(},            're-export names the same directory and clients');
like($reexport, qr{\brw\b},                    '... stays read-write');
like($reexport, qr{\bno_root_squash\b},        '... keeps no_root_squash, which the installer needs');
like($reexport, qr{\binsecure\b},              '... keeps insecure, for clients on high ports');
like($reexport, qr{\bfsid=\d+},                '... carries an fsid, without which exportfs refuses an NFS mount');
like($reexport, qr{\bcrossmnt\b},              '... carries crossmnt, so the mount below it is followed');

# The fsid must be stable across runs, or every restart hands clients a new filesystem identity
# and their mounts go stale.
is(xCAT::SvrUtils->nfs_export_line('/install', reexport => 1), $reexport,
    'the same directory yields the same fsid every time');

my ($install_fsid) = $reexport      =~ /fsid=(\d+)/;
my ($tftp_fsid)    = xCAT::SvrUtils->nfs_export_line('/tftpboot', reexport => 1) =~ /fsid=(\d+)/;
isnt($tftp_fsid, $install_fsid, 'two directories do not share one fsid');
cmp_ok($install_fsid, '>', 0, 'the fsid is not 0, which Linux reserves for the export root');
# The guard that keeps it non-zero is only reachable when the checksum itself is 0, which an
# empty path produces. Drive it directly rather than claim a path that cannot reach it.
cmp_ok(xCAT::SvrUtils::_nfs_export_fsid(''), '>', 0,
    'a path whose checksum is 0 still yields a usable fsid');

done_testing();
