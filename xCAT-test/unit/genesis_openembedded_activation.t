#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));

sub read_file {
    my ($relative) = @_;
    my $path = File::Spec->catfile($root, split m{/}, $relative);
    open(my $fh, '<', $path) or die "open $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $content;
}

my $rpm_spec = read_file('xCAT/xCAT.spec');
like(
    $rpm_spec,
    qr/^%if 0%\{\?fedora\} \|\| 0%\{\?rhel\} >= 8 \|\| 0%\{\?suse_version\} >= 1500$/m,
    'RPM weak dependencies are limited to package managers that support them',
);
like(
    $rpm_spec,
    qr/^Recommends:\s+xCAT-genesis-openembedded-x86_64$/m,
    'RPM installations recommend the first-class x86_64 image',
);
like(
    $rpm_spec,
    qr/^Recommends:\s+xCAT-genesis-openembedded-ppc64le$/m,
    'RPM installations recommend the first-class ppc64le image',
);
unlike(
    $rpm_spec,
    qr/^Requires:\s+xCAT-genesis-openembedded-/m,
    'missing OpenEmbedded images do not block an RPM upgrade',
);

my $deb_control = read_file('xCAT/debian/control');
like(
    $deb_control,
    qr/^Recommends:.*\bxcat-genesis-openembedded-x86-64\b/m,
    'DEB installations recommend the first-class x86_64 image',
);
like(
    $deb_control,
    qr/^Recommends:.*\bxcat-genesis-openembedded-ppc64le\b/m,
    'DEB installations recommend the first-class ppc64le image',
);
unlike(
    $deb_control,
    qr/^Depends:.*\bxcat-genesis-openembedded-/m,
    'missing OpenEmbedded images do not block a DEB upgrade',
);

my $sn_rpm_spec = read_file('xCATsn/xCATsn.spec');
like(
    $sn_rpm_spec,
    qr/^%if 0%\{\?fedora\} \|\| 0%\{\?rhel\} >= 8 \|\| 0%\{\?suse_version\} >= 1500$/m,
    'service-node weak dependencies use the same compatibility guard',
);
like(
    $sn_rpm_spec,
    qr/^Recommends:\s+xCAT-genesis-openembedded-x86_64$/m,
    'RPM service nodes recommend the first-class x86_64 image',
);
like(
    $sn_rpm_spec,
    qr/^Recommends:\s+xCAT-genesis-openembedded-ppc64le$/m,
    'RPM service nodes recommend the first-class ppc64le image',
);

my $sn_deb_control = read_file('xCATsn/debian/control');
like(
    $sn_deb_control,
    qr/^Recommends:.*\bxcat-genesis-openembedded-x86-64\b/m,
    'DEB service nodes recommend the first-class x86_64 image',
);
like(
    $sn_deb_control,
    qr/^Recommends:.*\bxcat-genesis-openembedded-ppc64le\b/m,
    'DEB service nodes recommend the first-class ppc64le image',
);

my $go_xcat = read_file('xCAT-server/share/xcat/tools/go-xcat');
unlike(
    $go_xcat,
    qr/GO_XCAT_LIBRARY_ONLY/,
    'go-xcat cannot be disabled by an inherited test environment variable',
);
for my $architecture (qw(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64)) {
    like(
        $go_xcat,
        qr/\bxCAT-genesis-openembedded-\Q$architecture\E\b/,
        "go-xcat removes the $architecture RPM image",
    );
    (my $deb_architecture = $architecture) =~ tr/_/-/;
    like(
        $go_xcat,
        qr/\bxcat-genesis-openembedded-\Q$deb_architecture\E\b/,
        "go-xcat removes the $architecture DEB image",
    );
}

my $mknb_pod = read_file('xCAT-client/pods/man8/mknb.8.pod');
like(
    $mknb_pod,
    qr{/opt/xcat/share/xcat/netboot/genesis-openembedded/ARCH},
    'the mknb man page documents the OpenEmbedded install namespace',
);
like(
    $mknb_pod,
    qr/x86.*x86_64.*ppc64.*ppc64le.*armv7hf.*aarch64.*riscv64/s,
    'the mknb man page lists every exact OpenEmbedded architecture',
);
unlike(
    $mknb_pod,
    qr/For ppc64le, use the ppc64 architecture/,
    'the mknb man page no longer presents ppc64 as the ppc64le name',
);

my $offline_guide = read_file('docs/source/guides/install-guides/common_sections.rst');
like(
    $offline_guide,
    qr/reposync.*--repofrompath=xcat-dep-common,https:\/\/xcat\.org\/.*\/xcat-dep\/common.*--repoid=xcat-dep-common.*--download-metadata/s,
    'the offline mirror command defines the common repository itself',
);
like(
    $offline_guide,
    qr{repodata/repomd\.xml\.asc}s,
    'the offline mirror includes the repository metadata signature',
);
like(
    $offline_guide,
    qr{repodata/repomd\.xml\.key}s,
    'the offline mirror includes its signing key',
);
like(
    $offline_guide,
    qr{baseurl=file://.*xcat-dep/common}s,
    'the offline guide points a repository file at the mirror',
);
like(
    $offline_guide,
    qr/dnf makecache.*--enablerepo=xcat-dep-common/s,
    'the offline guide verifies the mirrored common repository',
);
unlike(
    $offline_guide,
    qr/install .*xCAT-release.*local xcat-core/is,
    'the offline guide does not assume xCAT-release is in the core tarball',
);
unlike(
    $offline_guide,
    qr/Run .*mklocalrepo\.sh.*mirrored directory/is,
    'the offline guide does not depend on files reposync cannot download',
);

my $yum_guide = read_file(
    'docs/source/guides/install-guides/yum/configure_xcat.rst'
);
like(
    $yum_guide,
    qr/start-after: BEGIN_configure_xcat_local_repo_xcat-dep_DNF/,
    'the DNF guide includes the DNF common repository steps',
);

my $zypper_guide = read_file(
    'docs/source/guides/install-guides/zypper/configure_xcat.rst'
);
like(
    $zypper_guide,
    qr/start-after: BEGIN_configure_xcat_local_repo_xcat-dep_ZYPPER/,
    'the zypper guide includes its own common repository steps',
);
unlike(
    $zypper_guide,
    qr/start-after: BEGIN_configure_xcat_local_repo_xcat-dep_DNF/,
    'the zypper guide does not include DNF-only setup',
);

done_testing();
