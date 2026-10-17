#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(realpath);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Slurper qw(write_binary);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use xCAT::SvrUtils;
use xCAT::UFTP;

# The image checks refuse files that other users can write.
umask(022);
my $tmp = realpath(tempdir(CLEANUP => 1));

# packimage publishes the archive with its checksum, and the listener sends only such an archive.
sub publish {
    my ($dir, $name, $content) = @_;
    make_path($dir);
    chmod(0755, $dir);
    my ($stage, $error) = xCAT::SvrUtils->rootimg_stage($dir);
    die $error unless $stage;
    write_binary("$stage/$name", $content);
    $error = xCAT::SvrUtils->write_rootimg_checksum("$stage/$name") // xCAT::SvrUtils->publish_rootimg("$stage/$name", "$dir/$name");
    die $error if $error;
    return sha256_hex($content);
}

my $sha = sha256_hex('x');
my $request = xCAT::UFTP::parse_http_request(
    "GET /xcat-uftp/v1/transfer/$sha/install/netboot/img/rootimg.cpio.gz HTTP/1.1\r\n"
      . "Host: 192.0.2.1:1045\r\nUser-Agent: curl/8\r\n\r\n");
is_deeply($request, { method => 'GET', target => "/xcat-uftp/v1/transfer/$sha/install/netboot/img/rootimg.cpio.gz" },
    'the request target is parsed from the request line');
is_deeply(xCAT::UFTP::parse_http_request("GET /a HTTP/1.0\n\n"), { method => 'GET', target => '/a' },
    'bare line feeds are accepted');
ok(xCAT::UFTP::parse_http_request("GET /a HTTP/1.0\r\nHost: x\r\n")->{incomplete},
    'a request without the end of its headers is incomplete');
my $header_only = xCAT::UFTP::parse_http_request(
    "GET / HTTP/1.0\r\nX-Image: /install/netboot/img/rootimg.cpio.gz\r\n\r\n");
is($header_only->{target}, '/', 'an image path in a header is not the request target');
for my $case (
    [ "POST /a HTTP/1.0\r\n\r\n", 405 ],
    [ "GET /a HTTP/2.0\r\n\r\n", 400 ],
    [ "GET  /a HTTP/1.0\r\n\r\n", 400 ],
    [ "GET /a HTTP/1.0 extra\r\n\r\n", 400 ],
    [ "GET /install/%2e%2e/etc/rootimg.cpio.gz HTTP/1.0\r\n\r\n", 400 ],
    [ "GET /a?image=/install/x/rootimg.cpio.gz HTTP/1.0\r\n\r\n", 400 ],
    [ "GET /a#frag HTTP/1.0\r\n\r\n", 400 ],
    [ "GET /a\tb HTTP/1.0\r\n\r\n", 400 ],
    [ "GET /a HTTP/1.0\r\nno colon here\r\n\r\n", 400 ],
    [ "GET /a HTTP/1.0\r\n" . ("X: y\r\n" x 65) . "\r\n", 400 ],
) {
    (my $label = $case->[0]) =~ s/[\r\n].*//s;
    is(xCAT::UFTP::parse_http_request($case->[0])->{status}, $case->[1], "'$label' is answered with $case->[1]");
}

is(xCAT::UFTP::normalize_image_path('//install//netboot/rhels9/x86_64/compute/'),
    '/install/netboot/rhels9/x86_64/compute', 'repeated and trailing slashes are normalized');
for my $path ('install/x', '/install/../etc', '/install/./x', '/install/.hidden/x', '/a b',
    '/install/x%2e', '/install/x?y', '/' . ('a/' x 70), '/' . ('a' x 300)) {
    is(xCAT::UFTP::normalize_image_path($path), undef, "image path '$path' is refused");
}

my $prefix = "/xcat-uftp/v1/transfer/$sha";
my ($digest, $path, $error) = xCAT::UFTP::parse_transfer_target("$prefix/install/netboot/img/rootimg.tar.xz");
is_deeply([ $digest, $path, $error ], [ $sha, '/install/netboot/img/rootimg.tar.xz', undef ],
    'a transfer target yields the digest and the image path');
for my $target (
    "$prefix/install/netboot/img/../../../etc/rootimg.cpio.gz",
    "$prefix//install/netboot/img/rootimg.cpio.gz",
    "$prefix/install/netboot/img/rootimg.cpio.gz/",
    "$prefix/install/netboot/img/.hidden/rootimg.cpio.gz",
    "$prefix/etc/passwd",
    "$prefix/install/netboot/img/rootimg.gz",
    '/xcat-uftp/v1/transfer/' . ('A' x 64) . '/install/netboot/img/rootimg.cpio.gz',
    '/xcat-uftp/v1/transfer/' . ('a' x 63) . '/install/netboot/img/rootimg.cpio.gz',
    '/xcat-uftp/v2/transfer/' . $sha . '/install/netboot/img/rootimg.cpio.gz',
) {
    my (undef, undef, $target_error) = xCAT::UFTP::parse_transfer_target($target);
    ok($target_error, "transfer target '$target' is refused");
}
is_deeply([ xCAT::UFTP::parse_job_target('/xcat-uftp/v1/job/0123456789abcdef') ], [ '0123456789abcdef', undef ],
    'a job target yields the job identifier');
ok((xCAT::UFTP::parse_job_target('/xcat-uftp/v1/job/../../x'))[1], 'a malformed job target is refused');

my $root = "$tmp/install/netboot";
my $image_dir = "$root/rhels9/x86_64/compute";
my $digest_published = publish($image_dir, 'rootimg.cpio.gz', "published image\n");
my @roots = (realpath($root));

my ($image, $resolve_error) = xCAT::UFTP::resolve_artifact(\@roots, "$image_dir/rootimg.cpio.gz", $digest_published);
is($resolve_error, undef, 'a published image under an image root resolves');
is($image->{name}, 'rootimg.cpio.gz', 'the transfer keeps the archive name');
is($image->{size}, length("published image\n"), 'the resolved image has the published size');
my @published = stat("$image_dir/rootimg.cpio.gz");
is("$image->{dev}:$image->{ino}", "$published[0]:$published[1]", 'the job is keyed to the published inode');

# A batch keeps the bytes it opened when packimage publishes the next archive.
my $next = publish($image_dir, 'rootimg.cpio.gz', "next image\n");
my $bytes = do { local $/; my $fh = $image->{fh}; <$fh> };
is($bytes, "published image\n", 'the open handle reads the archive of its batch after a new publication');
close($image->{fh});

sub refused {
    my ($roots, $path, $digest, $pattern, $label) = @_;
    my ($resolved, $refusal) = xCAT::UFTP::resolve_artifact($roots, $path, $digest);
    close($resolved->{fh}) if $resolved;
    like($refusal // '', $pattern, $label);
}

refused(\@roots, "$image_dir/rootimg.cpio.gz", $digest_published,
    qr/not the published one/, 'the digest of a replaced archive is refused');
refused(\@roots, "$image_dir/rootimg.cpio.gz", sha256_hex('another generation'),
    qr/not the published one/, 'a digest that the checksum file does not list is refused');
write_binary("$image_dir/rootimg.cpio.gz.sha256", "$next  rootimg.cpio.gz\n$digest_published  rootimg.cpio.gz\n");
my ($during) = xCAT::UFTP::resolve_artifact(\@roots, "$image_dir/rootimg.cpio.gz", $digest_published);
ok($during, 'while packimage replaces the archive, the previous digest in the checksum file is accepted');
close($during->{fh}) if $during;
write_binary("$image_dir/rootimg.cpio.gz.sha256", "$next  rootimg.cpio.xz\n");
refused(\@roots, "$image_dir/rootimg.cpio.gz", $next, qr/not the published one/,
    'a checksum line for another archive name is refused');
write_binary("$image_dir/rootimg.cpio.gz.sha256", "$next  rootimg.cpio.gz\n");

write_binary("$image_dir/rootimg.cpio.xz", "unrelated existing file\n");
refused(\@roots, "$image_dir/rootimg.cpio.xz", sha256_hex("unrelated existing file\n"),
    qr/image is not published: .*rootimg\.cpio\.xz\.sha256 does not exist/, 'an archive without a checksum file is refused');

my $outside = "$tmp/srv/images/compute";
my $outside_digest = publish($outside, 'rootimg.cpio.gz', "outside image\n");
refused(\@roots, "$outside/rootimg.cpio.gz", $outside_digest,
    qr/outside the configured image roots/, 'a published image outside the image roots is refused');
my $sibling = "$tmp/install/netboot2/compute";
my $sibling_digest = publish($sibling, 'rootimg.cpio.gz', "sibling image\n");
refused(\@roots, "$sibling/rootimg.cpio.gz", $sibling_digest,
    qr/outside the configured image roots/, 'a directory sharing a name prefix with a root is refused');
my ($configured) = xCAT::UFTP::resolve_artifact([ @roots, realpath("$tmp/srv/images") ],
    "$outside/rootimg.cpio.gz", $outside_digest);
ok($configured, 'an explicitly configured image root outside /install is accepted');
close($configured->{fh}) if $configured;

symlink($outside, "$root/escape") or die $!;
refused(\@roots, "$root/escape/rootimg.cpio.gz", $outside_digest,
    qr/outside the configured image roots/, 'a symbolic link that escapes the image roots is refused');
symlink($image_dir, "$root/alias") or die $!;
my ($alias) = xCAT::UFTP::resolve_artifact(\@roots, "$root/alias/rootimg.cpio.gz", $next);
my @current = stat("$image_dir/rootimg.cpio.gz");
ok($alias && $alias->{ino} == $current[1], 'a symbolic link that stays inside an image root is resolved');
close($alias->{fh}) if $alias;

my $swapped = "$root/swapped";
my $swapped_digest = publish($swapped, 'rootimg.cpio.gz', "swapped archive\n");
write_binary("$tmp/secret", "secret readable by the service\n");
unlink("$swapped/rootimg.cpio.gz") or die $!;
symlink("$tmp/secret", "$swapped/rootimg.cpio.gz") or die $!;
refused(\@roots, "$swapped/rootimg.cpio.gz", $swapped_digest,
    qr/is a symbolic link/, 'an archive replaced by a symbolic link is refused');

my $linked_sums = "$root/linked-sums";
my $linked_digest = publish($linked_sums, 'rootimg.cpio.gz', "linked checksum\n");
rename("$linked_sums/rootimg.cpio.gz.sha256", "$tmp/moved.sha256") or die $!;
symlink("$tmp/moved.sha256", "$linked_sums/rootimg.cpio.gz.sha256") or die $!;
refused(\@roots, "$linked_sums/rootimg.cpio.gz", $linked_digest,
    qr/is a symbolic link/, 'a checksum file replaced by a symbolic link is refused');

my $writable = "$root/writable";
my $writable_digest = publish($writable, 'rootimg.cpio.gz', "writable\n");
chmod(0777, $writable) or die $!;
refused(\@roots, "$writable/rootimg.cpio.gz", $writable_digest,
    qr/writable by other users/, 'an image directory writable by others is refused');
chmod(0755, $writable) or die $!;
chmod(0666, "$writable/rootimg.cpio.gz") or die $!;
refused(\@roots, "$writable/rootimg.cpio.gz", $writable_digest,
    qr/writable by other users/, 'an archive writable by others is refused');

my $empty = "$root/empty";
make_path($empty);
chmod(0755, $empty) or die $!;
write_binary("$empty/rootimg.cpio.gz", '');
write_binary("$empty/rootimg.cpio.gz.sha256", sha256_hex('') . "  rootimg.cpio.gz\n");
refused(\@roots, "$empty/rootimg.cpio.gz", sha256_hex(''), qr/is empty/, 'an empty archive is refused');

refused(\@roots, "$root/missing/rootimg.cpio.gz", $next, qr/does not exist/,
    'a missing image directory is refused');

my $config_file = "$tmp/listener.conf";
sub config {
    my ($text) = @_;
    write_binary($config_file, $text);
    return xCAT::UFTP::load_listener_config($config_file);
}
my ($config, $config_error) = config("listen_address = 192.0.2.1\nimage_roots = $root\n");
is($config_error, undef, 'a minimal configuration loads');
is($config->{listen_port}, 1045, 'the listener port defaults to 1045');
is($config->{udp_port}, 1044, 'the UFTP port defaults to 1044');
is($config->{batch_delay}, 30, 'the batch delay defaults to 30 seconds');
is($config->{block_size}, 1300, 'the block size defaults to one that fits an MTU of 1500');
is($config->{multicast_interface}, '192.0.2.1', 'multicast is sent from the listen address by default');
is($config->{server_id}, '0xC0000201', 'the UFTP server ID is the sending address');
is_deeply($config->{image_roots}, \@roots, 'image roots are canonical paths');
($config) = config("listen_address = 192.0.2.1\nimage_roots = $root\nbatch_delay = 0\n");
is($config->{batch_delay}, 0, 'a zero batch delay is supported');
($config, $config_error) = config("listen_address = 192.0.2.1\nimage_roots = $root\nmax_transfers =\nblock_size =\n"
      . "uftp =\nallowed_networks =\nmulticast_interface =\n");
is($config_error, undef, 'a configuration with empty values loads');
is($config->{max_transfers}, 4, 'an empty max_transfers takes its default');
is($config->{block_size}, 1300, 'an empty block_size takes its default');
is($config->{uftp}, '/usr/bin/uftp', 'an empty uftp path takes its default');
ok(xCAT::UFTP::address_allowed($config->{allowed_networks}, '198.51.100.8'), 'empty allowed_networks allow any address');
is($config->{multicast_interface}, '192.0.2.1', 'an empty multicast_interface sends from the listen address');
for my $size (512, 8000, 8800) {
    my ($sized, $sized_error) = config("listen_address = 192.0.2.1\nimage_roots = $root\nblock_size = $size\n");
    is($sized_error, undef, "a block size of $size is accepted");
    is($sized->{block_size}, $size, "the block size of $size is kept");
}
($config) = config("listen_address = 192.0.2.1\nimage_roots = $root, $tmp/srv/images\n"
      . "allowed_networks = 192.0.2.0/24, 198.51.100.7/32\nmulticast_interface = 192.0.2.9\n");
ok(xCAT::UFTP::address_allowed($config->{allowed_networks}, '192.0.2.200'), 'an address inside allowed_networks is allowed');
ok(xCAT::UFTP::address_allowed($config->{allowed_networks}, '198.51.100.7'), 'a host network is allowed');
ok(!xCAT::UFTP::address_allowed($config->{allowed_networks}, '198.51.100.8'), 'other addresses are refused');
is($config->{server_id}, '0xC0000209', 'a separate multicast interface sets the server ID');
is(scalar(@{ $config->{image_roots} }), 2, 'several image roots are accepted');

for my $case (
    [ "image_roots = $root\n", qr/listen_address is required/ ],
    [ "listen_address =\nimage_roots = $root\n", qr/listen_address is required/ ],
    [ "listen_address = ::1\nimage_roots = $root\n", qr/listen_address must be an IPv4 address/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nlisten_port = 0\n", qr/between 1 and 65535/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nlisten_port = 65536\n", qr/between 1 and 65535/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nudp_port = 10a\n", qr/udp_port must be an integer/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nbatch_delay = -1\n", qr/batch_delay must be an integer/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nbatch_delay = 3601\n", qr/between 0 and 3600/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nbatch_delay = 030\n", qr/must be an integer/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\ntransfer_timeout = 0\n", qr/between 1 and 86400/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nblock_size = 511\n", qr/block_size must be between 512 and 8800/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nblock_size = 8801\n", qr/block_size must be between 512 and 8800/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\npublic_multicast = 10.0.0.1\n", qr/multicast address/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nencryption = none\n", qr/encryption must be one of/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nuftp = uftp\n", qr/uftp must be an absolute path/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = relative\n", qr/must be absolute paths/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $tmp/none\n", qr/is not a directory/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nallowed_networks = 192.0.2.0/33\n", qr/address\/prefix/ ],
    [ "listen_address = 192.0.2.1\nimage_roots = $root\nrate = 5\n", qr/unknown key 'rate'/ ],
    [ "listen_address = 192.0.2.1\nlisten_address = 192.0.2.2\nimage_roots = $root\n", qr/duplicate key/ ],
    [ "listen_address 192.0.2.1\n", qr/expected key = value/ ],
) {
    my (undef, $refusal) = config($case->[0]);
    like($refusal // '', $case->[1], "configuration is refused: $case->[1]");
}

is(xCAT::UFTP::parse_fingerprint("/etc/xcat/uftp/server.key: ECDSA, curve prime256v1, fingerprint: "
          . "31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2\n"),
    '31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2', 'uftp_keymgt output yields the fingerprint');
is(xCAT::UFTP::parse_fingerprint("31:94:09\n"), undef, 'a short fingerprint is refused');

($config) = config("listen_address = 192.0.2.1\nimage_roots = $root\nrate_kbps = 900000\n");
is_deeply([ xCAT::UFTP::uftp_command($config, 'rootimg.cpio.gz', '/run/x/job.hosts') ], [
        '/usr/bin/uftp', '-I', '192.0.2.1', '-U', '0xC0000201', '-p', 1044, '-M', '230.4.4.1',
        '-P', '230.5.5.x', '-t', 1, '-R', 900000, '-b', 1300, '-N', 98, '-Y', 'aes256-gcm',
        '-h', 'sha256', '-k', '/etc/xcat/uftp/server.key', '-H', '@/run/x/job.hosts', '-x', 2, '-l',
        '-D', 'rootimg.cpio.gz', '/dev/fd/3' ],
    'the sender argument vector holds only server-owned values and the inherited image descriptor');
($config) = config("listen_address = 192.0.2.1\nimage_roots = $root\nblock_size = 8000\n");
my @command = xCAT::UFTP::uftp_command($config, 'rootimg.cpio.gz', '/run/x/job.hosts');
my ($block_size) = map { $command[ $_ + 1 ] } grep { $command[$_] eq '-b' } 0 .. $#command - 1;
is($block_size, 8000, 'the configured block size reaches the sender');

done_testing();
