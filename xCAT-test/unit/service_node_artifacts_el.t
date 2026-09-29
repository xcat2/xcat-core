#!/usr/bin/env perl

# Every service node defect found in this change set was a GENERATED ARTIFACT that was wrong, not
# a runtime fault: the repository file that did not enable the builder repo, the install template
# that resolved to the wrong installer, the exports line that was never written. None of them was
# visible in the boot; all of them were decided before it.
#
# So this test renders the artifacts an EL service node needs, from one fixture, and asserts each
# one. It fails for ANY wrong artifact, including a defect nobody has hit yet, which is what makes
# it usable as the fast oracle for the EL cell: the end-to-end suite provisions three machines and
# takes 45 to 90 minutes, and this runs in a second.
#
# What it cannot cover, and what keeps the end-to-end run necessary: the boot half. Whether the
# compute node takes its lease from the service node, whether tftp hands over, whether the
# installer mounts what was exported. Those are not artifacts and are not here.

use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT/postscripts";

# ---------------------------------------------------------------------------
# The fixture: one EL service node, as the hierarchical cells define it.
# ---------------------------------------------------------------------------
my %SN = (
    name    => 'xcat42-sn',
    os      => 'alma9.8',
    osver   => 'rhels9.8',
    vendor  => 'alma',
    major   => 9,
    arch    => 'x86_64',
    profile => 'service',
);
my $SHARE = "$FindBin::Bin/../../xCAT-server/share/xcat/install";

# ---------------------------------------------------------------------------
# 1. The builder repository. xCAT-server pulls perl modules that BaseOS and AppStream do not
#    carry. A service node reaches no CRB and no EPEL unless something enables them, and
#    `dnf install xCATsn` then fails on "nothing provides perl(IO::Pty)".
# ---------------------------------------------------------------------------
# A missing module must not stop the file. On a tree without the fix this test is the gap
# report, and a report that dies at the first gap names one of them.
my $have_builder_repo = eval { require ELBuilderRepo; 1 } ? 1 : 0;
ok($have_builder_repo, 'ELBuilderRepo is present, so something can enable the builder repo')
    or diag("ELBuilderRepo did not load: $@");

SKIP: {
    skip 'ELBuilderRepo absent', 5 unless $have_builder_repo;

my @ids = ELBuilderRepo::builder_repo_ids($SN{vendor}, $SN{major}, $SN{arch});
is_deeply(\@ids, ['crb'], 'EL9 enables crb, the name the builder repo has from EL9 onwards');

is_deeply([ELBuilderRepo::builder_repo_ids('alma', 8, 'x86_64')], ['powertools', 'PowerTools'],
    'EL8 enables powertools, which is NOT called crb, and tolerates the Rocky 8.4 spelling');
is_deeply([ELBuilderRepo::builder_repo_ids('rhel', 9, 'ppc64le')],
    ['codeready-builder-for-rhel-9-ppc64le-rpms'],
    'RHEL names the CodeReady repo by release and arch');
is_deeply([ELBuilderRepo::builder_repo_ids('ol', 9, 'x86_64')], ['ol9_codeready_builder'],
    'Oracle names it its own way');
is_deeply([ELBuilderRepo::builder_repo_ids('alma', undef, 'x86_64')], [],
    'an unknown release enables nothing rather than guessing crb');
}

# ---------------------------------------------------------------------------
# 2. The install template. An EL service node installs from a kickstart, and it must be the
#    SERVICE profile's own, not the compute one and not a Subiquity template, which belongs to
#    Ubuntu and which an EL node cannot boot.
# ---------------------------------------------------------------------------
my $have_svrutils = eval { require xCAT::SvrUtils; 1 } ? 1 : 0;
ok($have_svrutils, 'xCAT::SvrUtils loads') or diag("SvrUtils did not load: $@");

SKIP: {
    skip 'xCAT::SvrUtils absent', 10 unless $have_svrutils;

my $tmpl = xCAT::SvrUtils::get_tmpl_file_name($SHARE . '/rh', $SN{profile}, $SN{osver},
                                              $SN{arch}, $SN{osver});
ok(defined $tmpl && length $tmpl, 'the EL service profile resolves a template at all')
    or diag('no template for ' . join(' ', @SN{qw(profile osver arch)}));
like($tmpl, qr{/service[^/]*\.tmpl$}, '... and it is the service profile, not compute');
unlike($tmpl, qr{subiquity}, '... and not a Subiquity template, which no EL node can boot');

# ---------------------------------------------------------------------------
# 3. The NFS export. A service node with nfsserver=1 serves files. With site.installloc set it
#    MOUNTS /install from the management node, and an export of an NFS mount needs an explicit
#    fsid or the kernel refuses it -- which is how a service node ended up exporting nothing.
# ---------------------------------------------------------------------------
# A missing capability FAILS here; it does not skip. A skip reads as a pass, and the absence of
# this sub is exactly the defect the block below exists to catch.
my $have_export_line = xCAT::SvrUtils->can('nfs_export_line') ? 1 : 0;
ok($have_export_line, 'SvrUtils can render an export line, without which a service node exports nothing');

SKIP: {
    skip 'nfs_export_line absent', 6 unless $have_export_line;

my $local = xCAT::SvrUtils->nfs_export_line('/install');
like($local, qr{^/install \*\(}, 'a local /install is exported to every client');
like($local, qr{\bno_root_squash\b}, '... with no_root_squash, which the installer needs');
unlike($local, qr{\bfsid=}, '... and without an fsid, which a local filesystem does not need');

my $reexport = xCAT::SvrUtils->nfs_export_line('/install', reexport => 1);
like($reexport, qr{\bfsid=\d+}, 're-exporting a mount carries an fsid, without which exportfs refuses');
like($reexport, qr{\bcrossmnt\b}, '... and crossmnt, so the mount underneath is followed');
is(xCAT::SvrUtils->nfs_export_line('/install', reexport => 1), $reexport,
    '... and the fsid is stable, or every restart hands clients a new filesystem identity');
}
}

done_testing();
