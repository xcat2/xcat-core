#!/usr/bin/env perl

# The artifacts an EL service node needs, rendered from one fixture and asserted: the builder
# repository per release and vendor, the install template the service profile resolves, and the
# NFS export line for a local directory and for a re-exported mount.
#
# The boot itself is not here. Whether the compute node takes its lease from the service node,
# and whether the installer mounts what was exported, are end-to-end questions.

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
    skip 'ELBuilderRepo absent', 16 unless $have_builder_repo;

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

my $rhel_repo = 'codeready-builder-for-rhel-9-x86_64-rpms';
is_deeply([ELBuilderRepo::enable_repo_commands($rhel_repo, 1)],
    [ "subscription-manager repos --enable=$rhel_repo",
      "dnf config-manager --set-enabled $rhel_repo" ],
    'a registered node asks subscription-manager first, because it rewrites redhat.repo');
is_deeply([ELBuilderRepo::enable_repo_commands($rhel_repo, 0)],
    [ "dnf config-manager --set-enabled $rhel_repo" ],
    'an unregistered node runs config-manager alone');
unlike(join(' ', ELBuilderRepo::enable_repo_commands($rhel_repo, 0)), qr/subscription-manager/,
    '... and never runs subscription-manager, whose failure names the registration');
is_deeply([ELBuilderRepo::enable_repo_commands('crb', 1)],
    [ 'subscription-manager repos --enable=crb',
      'dnf config-manager --set-enabled crb' ],
    'a registered AlmaLinux or Rocky node takes the same path, which is the Katello case');
is_deeply([ELBuilderRepo::enable_repo_commands('', 1)], [],
    'no repository id means no command to run');

# The registration probe. `subscription-manager identity` is the question, and its answer decides
# which of the commands above runs. The registered and the unregistered form below are the wording
# of subscription-manager 1.30.12, which is what EL10 ships.
ok(ELBuilderRepo::registered_with_subscription_manager(0,
        "system identity: 7a6bd2ee-1f43-4b0c-9d61-6c0e4f2a55b8\nname: sn\norg ID: 1234567\n"),
    'an identity and an exit status of 0 report a registered node');
ok(!ELBuilderRepo::registered_with_subscription_manager(1,
        "This system is not yet registered."
      . " Try 'subscription-manager register --help' for more information.\n"),
    'the unregistered message reports no registration');
ok(!ELBuilderRepo::registered_with_subscription_manager(127, ''),
    'a missing subscription-manager reports no registration');
ok(!ELBuilderRepo::registered_with_subscription_manager(8,
        "Error: this command requires root access to execute\n"),
    'a call without root privilege reports no registration');
ok(!ELBuilderRepo::registered_with_subscription_manager(0, "Unable to read consumer identity\n"),
    'an exit status of 0 without an identity line reports no registration');
ok(!ELBuilderRepo::registered_with_subscription_manager(1,
        "system identity: 7a6bd2ee-1f43-4b0c-9d61-6c0e4f2a55b8\n"),
    'an identity line with a non-zero exit status reports no registration');
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
