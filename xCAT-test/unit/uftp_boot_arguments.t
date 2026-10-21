#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(write_binary);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use xCAT::UFTP;

my $tmp = realpath(tempdir(CLEANUP => 1));
my $fp = '31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2';

# genimage marks the ramdisk in the image directory, and nodes boot its copy in TFTP.
my $root = "$tmp/install/netboot";
my $image = "$root/rhels9/x86_64/compute";
my $tftp = "$tmp/tftpboot/xcat/osimage/compute";
make_path($image, $tftp, "$tmp/etc");
write_binary("$image/initrd-stateless.gz", 'initramfs with receiver');
write_binary("$tftp/initrd-stateless.gz", 'initramfs with receiver');
write_binary("$image/rootimg.cpio.gz", "root image\n");
is(xCAT::UFTP::write_initrd_marker("$image/initrd-stateless.gz"), undef, 'the ramdisk with the receiver is marked');
write_binary("$tmp/etc/server.fingerprint", "$fp\n");
write_binary("$tmp/etc/listener.conf",
    "listen_address = 192.0.2.1\nlisten_port = 2045\nimage_roots = $root\n"
      . "fingerprint_file = $tmp/etc/server.fingerprint\n");

my %base = (
    rootimgdir => $image,
    artifact   => 'rootimg.cpio.gz',
    initrd     => "$tftp/initrd-stateless.gz",
    marker     => "$image/initrd-stateless.gz.uftp",
    httpmethod => 'http',
    checksum   => 1,
    config     => "$tmp/etc/listener.conf",
);

sub arguments {
    my (%override) = @_;
    return xCAT::UFTP::boot_arguments(%base, %override);
}

my $args = "xcat.uftp=2045 xcat.uftpfp=$fp ";
is_deeply([ arguments() ], [ $args, undef ], 'nodeset passes the listener port and the server key fingerprint');
is_deeply([ arguments(addkcmdline => 'console=ttyS0,115200 xcat.uftpx=1 uftp=true xcat.imgsha256=abc') ],
    [ $args, undef ], 'other addkcmdline tokens are left to the bootloader');
for my $token ('xcat.uftp=1', 'xcat.uftpfp=AA') {
    my (undef, $refusal) = arguments(addkcmdline => "quiet $token");
    like($refusal, qr/linuximage\.addkcmdline must not set/, "a managed token in addkcmdline is refused: $token");
    (undef, $refusal) = arguments(node_addkcmdline => "quiet $token");
    like($refusal, qr/^bootparams\.addkcmdline must not set/, "a managed token in the addkcmdline of a node is refused: $token");
}
is_deeply([ arguments(node_addkcmdline => 'console=ttyS1,115200 xcat.uftpx=1') ], [ $args, undef ],
    'other tokens in the addkcmdline of a node are left to the bootloader');

my (undef, $unchecked) = arguments(checksum => 0);
like($unchecked, qr/UFTP needs the root image checksum/, 'UFTP is refused for an image whose checksum is turned off');
my (undef, $statelite) = arguments(statelite => 1);
like($statelite, qr/only the compressed root image of a stateless image/, 'UFTP is refused for a statelite image');
my (undef, $https) = arguments(httpmethod => 'https');
like($https, qr/requires site\.httpmethod=http, not https/, 'UFTP is refused for an HTTPS image URL');
for my $artifact (undef, 'rootimg.gz') {
    my (undef, $unknown) = arguments(artifact => $artifact);
    like($unknown, qr/has no root image that UFTP can send; run packimage/,
        sprintf('an image whose archive is %s is refused', $artifact // 'missing'));
}

write_binary("$image/rootimg.cpio.gz.metainfo", 'torrent');
my (undef, $torrent) = arguments();
like($torrent, qr/cannot be combined with packimage --tracker/, 'UFTP is refused for a BitTorrent image');
unlink("$image/rootimg.cpio.gz.metainfo");

write_binary("$tftp/initrd-stateless.gz", 'initramfs rebuilt without receiver');
my (undef, $stale_initrd) = arguments();
like($stale_initrd, qr/is not the initial ramdisk that genimage built with the UFTP receiver/,
    'a TFTP ramdisk that differs from the marked one is refused');
write_binary("$tftp/initrd-stateless.gz", 'initramfs with receiver');
xCAT::UFTP::remove_initrd_marker("$image/initrd-stateless.gz");
my (undef, $no_marker) = arguments();
like($no_marker, qr/was not built with the UFTP receiver/, 'a ramdisk without the receiver is refused');
xCAT::UFTP::write_initrd_marker("$image/initrd-stateless.gz");

my $outside = "$tmp/images/rhels9/x86_64/compute";
make_path($outside);
my (undef, $foreign) = arguments(rootimgdir => $outside);
like($foreign, qr/^\Q$outside\E is outside the image_roots of the UFTP listener in \Q$tmp\E\/etc\/listener\.conf$/,
    'an image that the listener does not serve is refused');
my $spaced = "$root/rhels9/x86_64/compute two";
make_path($spaced);
my (undef, $unsendable) = arguments(rootimgdir => $spaced);
like($unsendable, qr/has a character that a UFTP request cannot carry/, 'an image path that a request cannot name is refused');

my (undef, $no_config) = arguments(config => "$tmp/etc/missing.conf");
like($no_config, qr/UFTP listener configuration: Cannot read/, 'a missing listener configuration is refused');
write_binary("$tmp/etc/server.fingerprint", "not a fingerprint\n");
my (undef, $bad_fp) = arguments();
like($bad_fp, qr/does not hold a UFTP key fingerprint/, 'a malformed server fingerprint is refused');
unlink("$tmp/etc/server.fingerprint");
my (undef, $no_fp) = arguments();
like($no_fp, qr/Cannot read UFTP server fingerprint/, 'a missing server fingerprint is refused');

done_testing();
