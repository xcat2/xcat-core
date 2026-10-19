#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Digest::SHA qw(sha256_hex);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Test::More;

my $fixture = tempdir(CLEANUP => 1);
$ENV{XCATCFG} = "SQLite:$fixture";
require xCAT::SvrUtils;

# The image value wins, and the site value applies only when the image does not set one.
for my $case ([ undef, undef, 1 ], [ '', undef, 1 ], [ undef, 'no', 0 ], [ undef, '0', 0 ], [ undef, 'yes', 1 ],
    [ 'no', undef, 0 ], [ 'NO', 'yes', 0 ], [ ' 0 ', 'yes', 0 ], [ 'yes', 'no', 1 ], [ '1', 'no', 1 ], [ '', 'no', 0 ]) {
    my ($image, $site, $enabled) = @$case;
    no warnings 'once';
    local %::XCATSITEVALS = (master => '192.0.2.1', defined $site ? (rootimgchecksum => $site) : ());
    is(xCAT::SvrUtils->rootimg_checksum_enabled($image) ? 1 : 0, $enabled,
        sprintf('image %s and site %s turn the check %s', map({ defined $_ ? "'$_'" : 'unset' } $image, $site), $enabled ? 'on' : 'off'));
}

my $initrd = "$fixture/initrd-stateless.gz";
write_text($initrd, "initial ramdisk\n");
ok(!xCAT::SvrUtils->initrd_checks_rootimg($initrd), 'an initial ramdisk without a marker cannot check');
is(xCAT::SvrUtils->write_initrd_check_marker($initrd), undef, 'the marker is written');
is(read_binary("$initrd.rootimgcheck"), 'sha256=' . sha256_hex("initial ramdisk\n") . "\n", 'the marker holds the checksum of the initial ramdisk');
is((stat("$initrd.rootimgcheck"))[2] & 07777, 0644, 'the marker is readable');
ok(xCAT::SvrUtils->initrd_checks_rootimg($initrd), 'a marked initial ramdisk can check');
write_text($initrd, "initial ramdisk from another genimage\n");
ok(!xCAT::SvrUtils->initrd_checks_rootimg($initrd), 'a replaced initial ramdisk does not match its old marker');

{
    no warnings 'once';
    local %::XCATSITEVALS = (master => '192.0.2.1');
    my (@warnings, %warned);
    my $callback = sub { push @warnings, @{ $_[0]{warning} || [] } };
    my %boot = (rootimgdir => $fixture, initrd => $initrd, imagename => 'img', warned => \%warned, callback => $callback);
    is(xCAT::SvrUtils->rootimg_checksum_boot(%boot), 'rootimgchecksum=yes ', 'a node is asked to check by default');
    like(join("\n", @warnings), qr/Cannot tell whether the initial ramdisk \Q$initrd\E checks the root image checksum, so nodes may boot the root image of img unchecked/,
        'an initial ramdisk without a matching marker is reported');
    xCAT::SvrUtils->rootimg_checksum_boot(%boot);
    is(scalar(@warnings), 1, 'the warning is given once for each image');
    xCAT::SvrUtils->write_initrd_check_marker($initrd);
    @warnings = ();
    %warned   = ();
    is(xCAT::SvrUtils->rootimg_checksum_boot(%boot), 'rootimgchecksum=yes ', 'a node with a marked initial ramdisk checks');
    is(scalar(@warnings), 0, 'a new marker is noticed although the initial ramdisk did not change');
    is(xCAT::SvrUtils->rootimg_checksum_boot(%boot, value => 'no'), '', 'a node is not asked to check when the check is turned off');

    # nodeset keeps a copy in TFTP, which checks only when it matches the marker in the image directory.
    mkdir("$fixture/tftp") or die $!;
    my $copy = "$fixture/tftp/initrd-stateless.gz";
    write_text($copy, read_binary($initrd));
    @warnings = ();
    %warned   = ();
    xCAT::SvrUtils->rootimg_checksum_boot(%boot, initrd => $copy);
    is(scalar(@warnings), 0, 'a copy of the marked initial ramdisk checks');
    write_text($copy, "initial ramdisk that an older genimage built\n");
    xCAT::SvrUtils->rootimg_checksum_boot(%boot, initrd => $copy);
    like(join("\n", @warnings), qr/initial ramdisk \Q$copy\E checks/, 'a copy that differs from the marked initial ramdisk is reported');
}

{
    my $dir = "$fixture/unwritable";
    mkdir($dir) or die $!;
    write_text("$dir/rootimg.cpio.gz", "packed before the check\n");
    my (@warnings, %warned);
    my $callback = sub { push @warnings, @{ $_[0]{warning} || [] } };
    no warnings 'redefine';
    local *xCAT::SvrUtils::publish_missing_rootimg_checksums = sub { return 'Cannot write the checksum.' };
    like(xCAT::SvrUtils->prepare_rootimg_checksum(rootimgdir => $dir, imagename => 'img', warned => \%warned, callback => $callback),
        qr/^The root image of img has no checksum that its initial ramdisk can check: Cannot write the checksum\. Run packimage/,
        'a checksum that cannot be written refuses a node that checks');
    is(xCAT::SvrUtils->prepare_rootimg_checksum(value => 'no', rootimgdir => $dir, imagename => 'img', warned => \%warned, callback => $callback),
        undef, 'a checksum that cannot be written does not refuse a node that skips the check');
    like(join("\n", @warnings), qr/Cannot write the checksum\. Nodes of img whose boot entries still ask for the check download the root image again/,
        'the nodes that still check are reported');

}

{
    my $dir = "$fixture/published";
    mkdir($dir) or die $!;
    write_text("$dir/rootimg.cpio.gz", "packed before the check\n");
    write_text("$dir/rootimg-statelite.gz", "statelite image\n");
    write_text("$dir/rootimg-statelite.gz.sha256", "checksum that liteimg wrote\n");
    is(xCAT::SvrUtils->publish_missing_rootimg_checksums($dir), undef, 'missing checksums are published');
    is(read_binary("$dir/rootimg.cpio.gz.sha256"), sha256_hex("packed before the check\n") . "  rootimg.cpio.gz\n",
        'an archive without a checksum gets one');
    is(read_binary("$dir/rootimg-statelite.gz.sha256"), "checksum that liteimg wrote\n", 'a published checksum is kept');
    ok(!-e "$dir/.packimage-publish", 'the publication lock is released');

    unlink("$dir/rootimg.cpio.gz.sha256") or die $!;
    mkdir("$dir/.packimage-publish") or die $!;
    write_text("$dir/.packimage-publish/owner", "other.host 4242\n");
    utime(time() - 120, time() - 120, "$dir/.packimage-publish") or die $!;
    like(xCAT::SvrUtils->publish_missing_rootimg_checksums($dir), qr/is held by other\.host 4242/,
        'a publication lock that another host holds is reported');
    ok(!-e "$dir/rootimg.cpio.gz.sha256", 'no checksum is computed while another host may replace the archive');
}

done_testing();
