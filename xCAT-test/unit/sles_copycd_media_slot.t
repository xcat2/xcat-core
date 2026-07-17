#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins";

require sles;

sub write_file
{
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "Cannot write $path: $!";
    print {$fh} $contents;
    close($fh);
}

sub inspect_media
{
    my $mountpoint = shift;
    my @responses;
    my $request = {
        arg => [ '-m', $mountpoint, '-i' ],
    };

    {
        no warnings qw(once redefine);
        local *xCAT::TableUtils::get_site_attribute = sub { return; };
        xCAT_plugin::sles::copycd(
            $request,
            sub { push @responses, shift; },
            undef,
        );
    }

    my ($info) = map { $_->{info} } grep { defined($_->{info}) } @responses;
    return $info || '';
}

my $sles12 = tempdir(CLEANUP => 1);
make_path("$sles12/media.1");
write_file("$sles12/content", "DEFAULTBASE ppc64le\nVERSION 12.4-0\n");
write_file("$sles12/media.1/media", "SUSE Linux Enterprise Server 12 SP4\nppc64le\n1\n");
write_file("$sles12/media.1/products", "SUSE-Linux-Enterprise-Server 12.4-0 ppc64le\n");

like(
    inspect_media($sles12),
    qr/^DISTNAME:sles12\.4\nARCH:ppc64le\nDISCNO:1\n$/,
    'SLES 12 primary server media keeps slot 1',
);

my $sles12_source = tempdir(CLEANUP => 1);
make_path("$sles12_source/media.2");
write_file("$sles12_source/content", "DEFAULTBASE ppc64le\nVERSION 12.4-0\n");
write_file("$sles12_source/media.2/media", "SUSE\n20181107140652\n");
write_file("$sles12_source/media.2/products", "/ SLES12-SP4 12.4-0\n");
like(
    inspect_media($sles12_source),
    qr/^DISTNAME:sles12\.4\nARCH:ppc64le\nDISCNO:2\n$/,
    'SLES 12 source media uses its embedded media.2 sequence',
);

write_file("$sles12/media.1/products", "SUSE-Linux-Enterprise-Software-Development-Kit 12.4-0 ppc64le\n");
like(
    inspect_media($sles12),
    qr/^DISTNAME:sles12\.4\nARCH:ppc64le\nDISCNO:sdk3\n$/,
    'SLES 12 SDK workaround remains based on embedded metadata',
);

my $sle15 = tempdir(CLEANUP => 1);
make_path("$sle15/media.1");
write_file("$sle15/media.1/products", "SLES 15 ppc64le\n");

write_file("$sle15/media.1/media", "SUSE - SLE-15-Installer-DVD-ppc64le-Build668.1-Media\n");
like(
    inspect_media($sle15),
    qr/^DISTNAME:sle15\nARCH:ppc64le\nDISCNO:1\n$/,
    'SLE 15 primary Installer media keeps slot 1',
);

write_file("$sle15/media.1/media", "SUSE - SLE-15-Installer-DVD-ppc64le-Build668.1-Media-SOURCE\n");
like(
    inspect_media($sle15),
    qr/^DISTNAME:sle15\nARCH:ppc64le\nDISCNO:installer2\n$/,
    'SLE 15 Installer source media uses its embedded SOURCE marker',
);

write_file("$sle15/media.1/media", "SUSE - SLE-15-Packages-ppc64le-Build668.1-Media1.iso\n");
like(
    inspect_media($sle15),
    qr/^DISTNAME:sle15\nARCH:ppc64le\nDISCNO:2\n$/,
    'SLE 15 primary Packages media keeps slot 2',
);

write_file("$sle15/media.1/media", "SUSE - SLE-15-Packages-ppc64le-Build668.1-Media2.iso\n");
like(
    inspect_media($sle15),
    qr/^DISTNAME:sle15\nARCH:ppc64le\nDISCNO:packages2\n$/,
    'SLE 15 Packages source media uses its embedded Media2 marker',
);

write_file("$sle15/media.1/media", "SLE-15 SOURCE ppc64le\n");
like(
    inspect_media($sle15),
    qr/^DISTNAME:sle15\nARCH:ppc64le\nDISCNO:2\n$/,
    'SLE 15 SOURCE Media2 keeps the existing packages-compatible slot',
);

write_file("$sle15/media.1/media", "SLE-15 Full ppc64le\n");
like(
    inspect_media($sle15),
    qr/^DISTNAME:sle15\nARCH:ppc64le\nDISCNO:1\n$/,
    'SLE 15 Full media keeps the existing primary slot',
);

done_testing();
