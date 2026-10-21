#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use Errno ();
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

our $fail_write;
BEGIN {
    *CORE::GLOBAL::syswrite = sub {
        if ($fail_write) {
            $! = Errno::ENOSPC();
            return undef;
        }
        return CORE::syswrite($_[0], $_[1], $_[2] // length($_[1]), $_[3] // 0);
    };
}
use xCAT::UFTP;

my $tmp = tempdir(CLEANUP => 1);

sub entries {
    my ($dir) = @_;
    opendir(my $dh, $dir) or return ();
    my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir($dh);
    return @names;
}

# genimage records the initial ramdisk it built with the receiver, and nodeset checks the copy that nodes boot.
my $initrd = "$tmp/initrd-stateless.gz";
write_binary($initrd, 'initramfs with receiver');
is(xCAT::UFTP::verify_initrd_marker($initrd) // '',
    "$initrd was not built with the UFTP receiver; install the uftp package in the image and run genimage again",
    'an initial ramdisk without a marker cannot receive over UFTP');
is(xCAT::UFTP::write_initrd_marker($initrd), undef, 'genimage records a ramdisk with the receiver');
is(scalar(read_binary("$initrd.uftp")), 'sha256=' . sha256_hex('initramfs with receiver') . "\n",
    'the marker holds the SHA-256 of the ramdisk');
is((stat("$initrd.uftp"))[2] & 07777, 0644, 'the marker is readable');
is(xCAT::UFTP::verify_initrd_marker($initrd), undef, 'the recorded ramdisk is accepted');
write_binary("$tmp/tftp-copy.gz", 'initramfs with receiver');
is(xCAT::UFTP::verify_initrd_marker("$tmp/tftp-copy.gz", "$initrd.uftp"), undef,
    'an identical copy of the ramdisk is accepted under the marker of the original');
write_binary("$tmp/other-initrd.gz", 'initramfs regenerated without uftp');
like(xCAT::UFTP::verify_initrd_marker("$tmp/other-initrd.gz", "$initrd.uftp"),
    qr/is not the initial ramdisk that genimage built with the UFTP receiver/,
    'another ramdisk is not accepted under an old marker');
write_binary("$tmp/broken.uftp", "format=1\n");
like(xCAT::UFTP::verify_initrd_marker($initrd, "$tmp/broken.uftp"), qr/is not a UFTP receiver marker/,
    'a marker in another format is refused');
is(xCAT::UFTP::remove_initrd_marker($initrd), undef, 'the marker is removed');
is(xCAT::UFTP::remove_initrd_marker($initrd), undef, 'removing a missing marker succeeds');
like(xCAT::UFTP::verify_initrd_marker($initrd), qr/was not built with the UFTP receiver/,
    'a ramdisk rebuilt without the receiver loses the marker');

my $atomic = "$tmp/atomic";
make_path($atomic);
write_binary("$atomic/server.fingerprint", "old fingerprint\n");
{
    local $fail_write = 1;
    like(xCAT::UFTP::write_file_atomic("$atomic/server.fingerprint", "new fingerprint\n", 0644),
        qr/Cannot write/, 'a failed write is reported');
}
is(scalar(read_binary("$atomic/server.fingerprint")), "old fingerprint\n", 'a failed write keeps the existing file');
{
    no warnings qw(redefine once);
    local *IO::Handle::sync = sub { $! = Errno::EIO(); return 0 };
    like(xCAT::UFTP::write_file_atomic("$atomic/server.fingerprint", "new fingerprint\n", 0644),
        qr/Cannot flush/, 'a failed flush is reported');
}
is(scalar(read_binary("$atomic/server.fingerprint")), "old fingerprint\n", 'a failed flush keeps the existing file');
is_deeply([ entries($atomic) ], ['server.fingerprint'], 'failed writes leave no temporary file');
is(xCAT::UFTP::write_file_atomic("$atomic/server.fingerprint", "new fingerprint\n", 0644), undef,
    'a complete write replaces the file');
is(scalar(read_binary("$atomic/server.fingerprint")), "new fingerprint\n", 'the replacement has the new content');
is((stat("$atomic/server.fingerprint"))[2] & 07777, 0644, 'the replacement has the requested mode');

sub elf {
    my ($path, $class, $data, $machine) = @_;
    my $ident = "\x7fELF" . chr($class) . chr($data) . "\x01" . ("\0" x 9);
    my $type = $data == 2 ? pack('n', 2) : pack('v', 2);
    my $mach = $data == 2 ? pack('n', $machine) : pack('v', $machine);
    write_binary($path, $ident . $type . $mach . ("\0" x 44));
    chmod(0755, $path);
}

elf("$tmp/x86_64", 2, 1, 62);
elf("$tmp/ppc64le", 2, 1, 21);
elf("$tmp/ppc64", 2, 2, 21);
elf("$tmp/aarch64", 2, 1, 183);
elf("$tmp/riscv64", 2, 1, 243);
is(xCAT::UFTP::elf_arch_error("$tmp/$_", $_), undef, "a $_ receiver matches a $_ image")
  for qw(x86_64 ppc64le ppc64 aarch64 riscv64);
like(xCAT::UFTP::elf_arch_error("$tmp/x86_64", 'ppc64le'), qr/built for another architecture than ppc64le/,
    'a management node binary is refused for another image architecture');
like(xCAT::UFTP::elf_arch_error("$tmp/ppc64le", 'ppc64'), qr/another architecture/,
    'byte order distinguishes ppc64le from ppc64');
is(xCAT::UFTP::elf_arch_error("$tmp/ppc64le", 'ppc64el'), undef, 'a ppc64le receiver matches an Ubuntu ppc64el image');
like(xCAT::UFTP::elf_arch_error("$tmp/ppc64", 'ppc64el'), qr/another architecture/,
    'a big-endian receiver is refused for an Ubuntu ppc64el image');
like(xCAT::UFTP::elf_arch_error("$tmp/aarch64", 'x86_64'), qr/another architecture/,
    'an aarch64 receiver is refused for an x86_64 image');
write_binary("$tmp/script", "#!/bin/sh\n");
chmod(0755, "$tmp/script");
like(xCAT::UFTP::elf_arch_error("$tmp/script", 'x86_64'), qr/not an ELF executable/,
    'a script is not accepted as a receiver');
like(xCAT::UFTP::elf_arch_error("$tmp/x86_64", 'sparc'), qr/not supported for architecture sparc/,
    'unknown architectures are refused');

sub receiver_image {
    my ($name, $class, $data, $machine, $version) = @_;
    my $root = "$tmp/receiver-$name";
    make_path("$root/usr/bin");
    elf("$root/usr/bin/uftpd", $class, $data, $machine);
    open(my $fh, '>>:raw', "$root/usr/bin/uftpd") or die $!;
    print {$fh} "\0UFTP version $version  Copyright\0";
    close($fh);
    return $root;
}
is_deeply([ xCAT::UFTP::usable_receiver(receiver_image('ok', 2, 1, 62, '5.0.3 (xCAT build 1)'), 'x86_64') ],
    [ '/usr/bin/uftpd', undef ], 'a UFTP 5 receiver of xcat-dep for the image architecture is used');
my ($stock_receiver, $stock_warning) = xCAT::UFTP::usable_receiver(receiver_image('stock', 2, 1, 62, '5.0.3'), 'x86_64');
ok(!defined($stock_receiver), 'a UFTP 5 receiver without the xCAT build mark is left out');
like($stock_warning, qr/UFTP 5\.0\.3 without the xCAT fixes; use the uftp package of xcat-dep; the initial ramdisk will not/,
    'a UFTP 5 receiver without the xCAT build mark gets a warning');
my ($none_receiver, $none_warning) = xCAT::UFTP::usable_receiver("$tmp/receiver-absent", 'x86_64');
ok(!defined($none_receiver) && !defined($none_warning), 'an image without uftpd gets no receiver and no warning');
my ($old_receiver, $old_warning) = xCAT::UFTP::usable_receiver(receiver_image('old', 2, 1, 62, '4.10.2'), 'x86_64');
ok(!defined($old_receiver), 'a UFTP 4 receiver is left out');
like($old_warning, qr/UFTP 5\.x is required; the initial ramdisk will not receive the root image over UFTP/,
    'a UFTP 4 receiver gets a warning instead of failing the image build');
is_deeply([ xCAT::UFTP::usable_receiver(receiver_image('ppc64el', 2, 1, 21, '5.0.3 (xCAT build 1)'), 'ppc64el') ],
    [ '/usr/bin/uftpd', undef ], 'a ppc64le receiver of xcat-dep is used for an Ubuntu ppc64el image');
my ($foreign_receiver, $foreign_warning) = xCAT::UFTP::usable_receiver(receiver_image('foreign', 2, 1, 183, '5.0.3 (xCAT build 1)'), 'x86_64');
ok(!defined($foreign_receiver), 'a receiver for another architecture is left out');
like($foreign_warning, qr/another architecture than x86_64/, 'a foreign receiver gets a warning');

write_binary("$tmp/uftp5", ("\0" x 70000) . "UFTP version 5.0.3 (xCAT build 1)  Copyright (C) 2001-2023\0");
chmod(0755, "$tmp/uftp5");
write_binary("$tmp/uftp5-stock", "\0UFTP version 5.0.3  Copyright (C) 2001-2023\0");
chmod(0755, "$tmp/uftp5-stock");
write_binary("$tmp/uftp4", "\0UFTP version 4.10.2  Copyright\0");
chmod(0755, "$tmp/uftp4");
write_binary("$tmp/uftp-none", "\0no version here\0");
chmod(0755, "$tmp/uftp-none");
is(xCAT::UFTP::uftp_version_error("$tmp/uftp5"), undef, 'UFTP 5 binaries with the xCAT build mark are accepted');
like(xCAT::UFTP::uftp_version_error("$tmp/uftp5-stock"), qr/is UFTP 5\.0\.3 without the xCAT fixes/,
    'UFTP 5 binaries without the xCAT build mark are refused');
like(xCAT::UFTP::uftp_version_error("$tmp/uftp4"), qr/is UFTP 4\.10\.2; UFTP 5\.x is required/,
    'UFTP 4 binaries are refused');
like(xCAT::UFTP::uftp_version_error("$tmp/uftp-none"), qr/Cannot find the UFTP version/,
    'binaries without a version string are refused');

my @listing = (
    'drwxr-xr-x   2 root root        0 Jan  1 00:00 usr/bin',
    '-rwxr-xr-x   1 root root   180000 Jan  1 00:00 usr/bin/uftpd',
    '-rwxr-xr-x   1 root root    40000 Jan  1 00:00 usr/bin/sha256sum',
    '-rw-r--r--   1 root root    12000 Jan  1 00:00 lib/xcat-rootimg-fetch.sh',
);
is_deeply([ xCAT::UFTP::initrd_missing_files(\@listing) ], [], 'a complete initramfs listing passes');
my @sbin = @listing;
$sbin[1] =~ s{usr/bin/uftpd}{usr/sbin/uftpd};
is_deeply([ xCAT::UFTP::initrd_missing_files(\@sbin) ], [], 'a receiver in usr/sbin is accepted');
my @usrmerge = @listing;
$usrmerge[3] =~ s{lib/xcat-rootimg-fetch\.sh}{usr/lib/xcat-rootimg-fetch.sh};
push @usrmerge, 'lrwxrwxrwx   1 root root        7 Jan  1 00:00 lib -> usr/lib';
is_deeply([ xCAT::UFTP::initrd_missing_files(\@usrmerge) ], [], 'a helper under usr/lib in a usrmerged initramfs is accepted');
is_deeply([ xCAT::UFTP::initrd_missing_files([ @listing[0, 2, 3] ]) ], ['uftpd'],
    'a missing receiver is reported');
is_deeply([ xCAT::UFTP::initrd_missing_files([ @listing[0, 1] ]) ],
    [ 'sha256sum', 'xcat-rootimg-fetch.sh' ], 'missing verification files are reported');

done_testing();
