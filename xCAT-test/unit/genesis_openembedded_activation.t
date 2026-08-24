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

done_testing();
