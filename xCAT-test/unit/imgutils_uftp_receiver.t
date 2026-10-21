#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use imgutils;
use xCAT::UFTP;

my $tmp    = realpath(tempdir(CLEANUP => 1));
my $helper = realpath("$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-fetch.sh");

# Returns what the code printed and what it returned or died with.
sub output_of {
    my ($code) = @_;
    my $out = '';
    open(my $capture, '>', \$out) or die $!;
    my $previous = select($capture);
    my @result = eval { $code->() };
    my $error = $@;
    select($previous);
    close($capture);
    return ($out, $error, @result);
}

# An image root with an x86_64 uftpd of the UFTP version $version.
sub image_root {
    my ($name, $version) = @_;
    my $root = "$tmp/image-$name";
    make_path("$root/usr/bin");
    my $elf = "\x7fELF\x02\x01\x01" . ("\0" x 9) . pack('v', 2) . pack('v', 62) . ("\0" x 44);
    if ($version) {
        write_binary("$root/usr/bin/uftpd", $elf . "\0UFTP version $version  Copyright\0");
        chmod(0755, "$root/usr/bin/uftpd");
    }
    return $root;
}

my $module = "$tmp/98xcat";
my $copy   = "$module/xcat-rootimg-fetch.sh";
make_path($module);

my ($out, $error, $receiver) = output_of(sub { imgutils::add_uftp_receiver(image_root('uftp5', '5.0.3 (xCAT build 1)'), 'x86_64', $module, 1) });
is($error, '', 'a stateless image with a UFTP 5 receiver is accepted');
is($receiver, '/usr/bin/uftpd', 'the receiver of the image is returned');
is(scalar(read_binary($copy)), scalar(read_binary($helper)), 'the dracut module gets the UFTP fetch helper');
is((stat($copy))[2] & 07777, 0644, 'the dracut module installs the helper itself, so the copy is not executable');
like($out, qr{Adding the UFTP receiver /usr/bin/uftpd to the initial ramdisk}, 'genimage reports the receiver');

($out, $error, $receiver) = output_of(sub { imgutils::add_uftp_receiver(image_root('uftp5', '5.0.3 (xCAT build 1)'), 'x86_64', $module, 0) });
ok(!defined($receiver) && $error eq '', 'an initial ramdisk that must not receive over UFTP gets no receiver');
ok(!-e $copy, 'the helper that an earlier stateless build left in the module is removed');

write_binary($copy, "older helper\n");
($out, $error, $receiver) = output_of(sub { imgutils::add_uftp_receiver(image_root('none'), 'x86_64', $module, 1) });
ok(!defined($receiver) && $error eq '', 'an image without uftpd gets no receiver');
is($out, '', 'an image without uftpd gets no warning');
ok(!-e $copy, 'the helper is removed when the image no longer has uftpd');

symlink("$tmp/missing", $copy) or die $!;
($out, $error, $receiver) = output_of(sub { imgutils::add_uftp_receiver(image_root('uftp4', '4.10.2'), 'x86_64', $module, 1) });
ok(!defined($receiver) && $error eq '', 'a UFTP 4 receiver is left out without failing the image build');
like($out, qr/Warning: .*UFTP 5\.x is required/, 'a UFTP 4 receiver gets a warning');
ok(!-e $copy && !-l $copy, 'a dangling helper link is removed');

($out, $error, $receiver) = output_of(sub { imgutils::add_uftp_receiver(image_root('stock', '5.0.3'), 'x86_64', $module, 1) });
ok(!defined($receiver) && $error eq '', 'a UFTP 5 receiver without the xCAT build mark is left out');
like($out, qr/Warning: .*UFTP 5\.0\.3 without the xCAT fixes/, 'a UFTP 5 receiver without the xCAT build mark gets a warning');

($out, $error, $receiver) = output_of(sub { imgutils::add_uftp_receiver(image_root('uftp5', '5.0.3 (xCAT build 1)'), 'ppc64le', $module, 1) });
ok(!defined($receiver), 'a receiver for another architecture than the image is left out');
like($out, qr/Warning: .*another architecture than ppc64le/, 'a foreign receiver gets a warning');
ok(!-e $copy, 'no helper is added without a usable receiver');

# unlink and copy fail on these paths for root too.
make_path("$copy/older");
(undef, $error) = output_of(sub { imgutils::add_uftp_receiver(image_root('none'), 'x86_64', $module, 1) });
like($error, qr/^Error: cannot remove \Q$copy\E/, 'an older helper that cannot be removed fails the image build');
rmdir("$copy/older") && rmdir($copy) or die $!;
my $missing_module = "$tmp/missing/98xcat";
(undef, $error) = output_of(sub { imgutils::add_uftp_receiver(image_root('uftp5', '5.0.3 (xCAT build 1)'), 'x86_64', $missing_module, 1) });
like($error, qr{^Error: cannot copy \S+/imgutils/xcat-rootimg-fetch\.sh to \Q$missing_module/xcat-rootimg-fetch.sh\E},
    'a helper that cannot be added fails the image build');

# lsinitrd runs in the image, so the test replaces the listing that it returns.
my (@listed, $listing);
{
    no warnings 'redefine';
    *imgutils::initrd_listing = sub { push @listed, [@_]; return $listing };
}
$listing = [
    "-rwxr-xr-x   1 root root   180000 Jan  1 00:00 usr/bin/uftpd\n",
    "-rwxr-xr-x   1 root root    40000 Jan  1 00:00 usr/bin/sha256sum\n",
    "-rw-r--r--   1 root root    12000 Jan  1 00:00 usr/lib/xcat-rootimg-fetch.sh\n",
];
my $root = image_root('uftp5', '5.0.3 (xCAT build 1)');
(undef, $error, my $checked) = output_of(sub { imgutils::check_uftp_initrd($root, '/tmp/initrd.1.gz', 'stateless') });
ok($checked && $error eq '', 'an initial ramdisk with the receiver files passes');
is_deeply(\@listed, [ [ $root, '/tmp/initrd.1.gz' ] ], 'the initial ramdisk is listed in the image');
$listing = [ @$listing[ 1, 2 ] ];
(undef, $error) = output_of(sub { imgutils::check_uftp_initrd($root, '/tmp/initrd.1.gz', 'stateless') });
like($error, qr/^Error: the initial ramdisk for stateless lacks the UFTP receiver files: uftpd$/m,
    'an initial ramdisk without uftpd fails the image build');
$listing = undef;
(undef, $error) = output_of(sub { imgutils::check_uftp_initrd($root, '/tmp/initrd.1.gz', 'stateless') });
like($error, qr/lacks the UFTP receiver files: a readable file list/, 'an initial ramdisk that cannot be listed fails the image build');

my $initrd = "$tmp/initrd-stateless.gz";
write_binary($initrd, "initial ramdisk with the receiver\n");
($out, $error, my $marked) = output_of(sub { imgutils::mark_uftp_receiver($initrd, '/usr/bin/uftpd') });
ok($marked && $error eq '', 'an initial ramdisk with the receiver is marked');
is(xCAT::UFTP::verify_initrd_marker($initrd), undef, 'nodeset accepts the marked initial ramdisk');
like($out, qr/\Q$initrd\E can receive the root image over UFTP/, 'genimage reports the UFTP receiver');

write_binary($initrd, "initial ramdisk without the receiver\n");
($out, $error, $marked) = output_of(sub { imgutils::mark_uftp_receiver($initrd, undef) });
ok($marked && $error eq '' && $out eq '', 'an initial ramdisk without the receiver is not marked');
ok(!-e "$initrd.uftp", 'the marker of the previous initial ramdisk is removed');
like(xCAT::UFTP::verify_initrd_marker($initrd), qr/was not built with the UFTP receiver/, 'nodeset refuses UFTP for it');

# A file cannot replace a directory, for root too.
make_path("$initrd.uftp/older");
($out, $error, $marked) = output_of(sub { imgutils::mark_uftp_receiver($initrd, '/usr/bin/uftpd') });
is($error, '', 'a marker that cannot be written does not fail the image build');
ok(!$marked, 'a marker that cannot be written is reported to the caller');
like($out, qr/^Warning: Cannot publish \Q$initrd\E\.uftp: /, 'a marker that cannot be written gets a warning');
is(scalar(() = glob("$tmp/.initrd-stateless.gz.uftp.tmp*")), 0, 'a marker that cannot be written leaves no temporary file');

done_testing();
