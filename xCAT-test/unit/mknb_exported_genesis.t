#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

BEGIN {
    package xCAT::Utils;
    sub genpassword { return 'test-token'; }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    our ($tftpdir, $site_master);
    sub getTftpDir { return $tftpdir; }
    sub get_site_attribute {
        my $attribute = $_[-1];
        return ($site_master) if $attribute eq 'master' && defined($site_master);
        return;
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    our ($normnet_addresses, $hexnet_addresses, @master_addresses);
    sub my_nets    { return $normnet_addresses; }
    sub my_hexnets { return $hexnet_addresses; }
    sub getipaddr  { return @master_addresses; }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::noderange"} = sub { return; };
    }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

my $source_mknb_plugin =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/mknb.pm";
if (-f $source_mknb_plugin) {
    require $source_mknb_plugin;
} else {
    require xCAT_plugin::mknb;
}

sub write_file {
    my ($filename, $content) = @_;
    open(my $fh, '>:raw', $filename) or die "Unable to write $filename: $!";
    print {$fh} $content;
    close($fh) or die "Unable to close $filename: $!";
}

sub read_file {
    my ($filename) = @_;
    open(my $fh, '<:raw', $filename) or die "Unable to read $filename: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

sub export_manifest {
    my ($architecture) = @_;
    return "format=xcat-genesis\n"
      . "version=1\n"
      . "architecture=$architecture\n";
}

sub prepare_export {
    my ($directory, $kernel, $initramfs, $architecture) = @_;
    $architecture //= 'x86_64';
    make_path($directory);
    write_file("$directory/kernel", $kernel);
    write_file("$directory/initramfs.cpio.gz", $initramfs);
    my $manifest = export_manifest($architecture);
    write_file("$directory/xcat-genesis.manifest", $manifest);
    write_file(
        "$directory/SHA256SUMS",
        sha256_hex($initramfs) . "  initramfs.cpio.gz\n"
          . sha256_hex($kernel) . "  kernel\n"
          . sha256_hex($manifest) . "  xcat-genesis.manifest\n",
    );
}

sub published_files {
    my ($tftpdir, $arch) = @_;
    return (
        "$tftpdir/xcat/genesis.kernel.$arch",
        "$tftpdir/xcat/genesis.fs.$arch.gz",
    );
}

sub temporary_files {
    my ($directory) = @_;
    opendir(my $dir_fh, $directory) or return;
    my @files = grep { /\.test-token\.(?:new|old)$/ } readdir($dir_fh);
    closedir($dir_fh);
    return @files;
}

my $tmpdir = tempdir(CLEANUP => 1);
my $export = "$tmpdir/export";
my $tftpdir = "$tmpdir/tftpboot";
prepare_export($export, 'new kernel', 'new initramfs');

ok(
    xCAT_plugin::mknb::_prebuilt_genesis_requested($export),
    'an export manifest selects the prebuilt path',
);

my ($installed_initrd, $install_error) =
  xCAT_plugin::mknb::_install_prebuilt_genesis($export, $tftpdir, 'x86_64');
is($install_error, undef, 'a valid export installs without an error');
is(
    $installed_initrd,
    "$tftpdir/xcat/genesis.fs.x86_64.gz",
    'the installer returns the published initramfs path',
);
my ($published_kernel, $published_initramfs) =
  published_files($tftpdir, 'x86_64');
is(read_file($published_kernel), 'new kernel', 'the kernel is published');
is(read_file($published_initramfs), 'new initramfs', 'the initramfs is published');
is(sprintf('%04o', (stat($published_kernel))[2] & oct('7777')), '0644', 'the kernel is readable by TFTP');
is(sprintf('%04o', (stat($published_initramfs))[2] & oct('7777')), '0644', 'the initramfs is readable by TFTP');
is_deeply([temporary_files("$tftpdir/xcat")], [], 'staging files are removed');

write_file($published_kernel, 'current kernel');
write_file($published_initramfs, 'current initramfs');
write_file("$export/kernel", 'corrupt kernel');
($installed_initrd, $install_error) =
  xCAT_plugin::mknb::_install_prebuilt_genesis($export, $tftpdir, 'x86_64');
like($install_error, qr/Genesis checksum mismatch/, 'a checksum mismatch is rejected');
is(read_file($published_kernel), 'current kernel', 'a bad export keeps the current kernel');
is(read_file($published_initramfs), 'current initramfs', 'a bad export keeps the current initramfs');
is_deeply([temporary_files("$tftpdir/xcat")], [], 'a failed install removes staging files');

my $unmarked_export = "$tmpdir/unmarked";
prepare_export($unmarked_export, 'kernel', 'initramfs');
unlink("$unmarked_export/xcat-genesis.manifest");
ok(
    !xCAT_plugin::mknb::_prebuilt_genesis_requested($unmarked_export),
    'boot artifacts without an export manifest do not select the prebuilt path',
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $unmarked_export, $tftpdir, 'x86_64'
);
like($install_error, qr/Missing Genesis export manifest/, 'the installer requires the export manifest');

my $partial_export = "$tmpdir/partial";
make_path($partial_export);
write_file("$partial_export/initramfs.cpio.gz", 'partial initramfs');
write_file(
    "$partial_export/xcat-genesis.manifest",
    export_manifest('x86_64'),
);
ok(
    !xCAT_plugin::mknb::_prebuilt_genesis_requested($partial_export),
    'a partial export does not satisfy the prebuilt layout',
);
ok(
    xCAT_plugin::mknb::_genesis_export_manifest_present($partial_export),
    'a partial export still declares the new format',
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $partial_export, $tftpdir, 'x86_64'
);
like($install_error, qr/Missing Genesis checksum file/, 'a partial export fails closed');

my $missing_manifest_checksum = "$tmpdir/missing-manifest-checksum";
prepare_export($missing_manifest_checksum, 'kernel', 'initramfs');
write_file(
    "$missing_manifest_checksum/SHA256SUMS",
    sha256_hex('kernel') . "  kernel\n"
      . sha256_hex('initramfs') . "  initramfs.cpio.gz\n",
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $missing_manifest_checksum, $tftpdir, 'x86_64'
);
like($install_error, qr/Missing Genesis checksum entry: xcat-genesis\.manifest/, 'the export manifest needs a checksum');

my $bad_manifest_checksum = "$tmpdir/bad-manifest-checksum";
prepare_export($bad_manifest_checksum, 'kernel', 'initramfs');
write_file(
    "$bad_manifest_checksum/xcat-genesis.manifest",
    "architecture=x86_64\nversion=1\nformat=xcat-genesis\n",
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $bad_manifest_checksum, $tftpdir, 'x86_64'
);
like($install_error, qr/Genesis checksum mismatch: .*xcat-genesis\.manifest/, 'the export manifest checksum is verified');

my @invalid_manifests = (
    [ malformed => "not a manifest\n", qr/Invalid Genesis export manifest entry/ ],
    [ unknown => export_manifest('x86_64') . "label=test\n", qr/Unknown Genesis export manifest entry: label/ ],
    [ duplicate => export_manifest('x86_64') . "version=1\n", qr/Duplicate Genesis export manifest entry: version/ ],
    [ missing => "format=xcat-genesis\nversion=1\n", qr/Missing Genesis export manifest entry: architecture/ ],
    [ version => "format=xcat-genesis\nversion=2\narchitecture=x86_64\n", qr/Unsupported Genesis export version: 2/ ],
    [ architecture => export_manifest('ppc64le'), qr/Unsupported Genesis export architecture: ppc64le/ ],
);
foreach my $case (@invalid_manifests) {
    my ($name, $content, $error_pattern) = @{$case};
    my $invalid_export = "$tmpdir/manifest-$name";
    prepare_export($invalid_export, 'kernel', 'initramfs');
    write_file("$invalid_export/xcat-genesis.manifest", $content);
    (undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
        $invalid_export, $tftpdir, 'x86_64'
    );
    like($install_error, $error_pattern, "$name export manifests are rejected");
}

my $symlink_manifest = "$tmpdir/symlink-manifest";
prepare_export($symlink_manifest, 'kernel', 'initramfs');
unlink("$symlink_manifest/xcat-genesis.manifest");
symlink("$symlink_manifest/kernel", "$symlink_manifest/xcat-genesis.manifest")
  or die "Unable to create manifest symlink: $!";
ok(
    xCAT_plugin::mknb::_prebuilt_genesis_requested($symlink_manifest),
    'a manifest symlink still selects the prebuilt path',
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $symlink_manifest, $tftpdir, 'x86_64'
);
like($install_error, qr/Missing Genesis export manifest/, 'export manifest symlinks fail closed');

my $missing_entry = "$tmpdir/missing-entry";
prepare_export($missing_entry, 'kernel', 'initramfs');
write_file(
    "$missing_entry/SHA256SUMS",
    sha256_hex('kernel') . "  kernel\n"
      . sha256_hex(export_manifest('x86_64'))
      . "  xcat-genesis.manifest\n",
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $missing_entry, $tftpdir, 'x86_64'
);
like($install_error, qr/Missing Genesis checksum entry: initramfs\.cpio\.gz/, 'each published file needs a checksum');

my $duplicate_entry = "$tmpdir/duplicate-entry";
prepare_export($duplicate_entry, 'kernel', 'initramfs');
write_file(
    "$duplicate_entry/SHA256SUMS",
    sha256_hex('kernel') . "  kernel\n"
      . sha256_hex('kernel') . "  kernel\n",
);
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $duplicate_entry, $tftpdir, 'x86_64'
);
like($install_error, qr/Duplicate Genesis checksum entry: kernel/, 'duplicate checksum entries are rejected');

my $malformed_entry = "$tmpdir/malformed-entry";
prepare_export($malformed_entry, 'kernel', 'initramfs');
write_file("$malformed_entry/SHA256SUMS", "not a checksum\n");
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $malformed_entry, $tftpdir, 'x86_64'
);
like($install_error, qr/Invalid Genesis checksum entry/, 'malformed checksum entries are rejected');

my $symlink_export = "$tmpdir/symlink-export";
prepare_export($symlink_export, 'kernel', 'initramfs');
unlink("$symlink_export/kernel");
symlink("$symlink_export/initramfs.cpio.gz", "$symlink_export/kernel")
  or die "Unable to create test symlink: $!";
(undef, $install_error) = xCAT_plugin::mknb::_install_prebuilt_genesis(
    $symlink_export, $tftpdir, 'x86_64'
);
like($install_error, qr/Missing Genesis artifact: .*\/kernel/, 'artifact symlinks are rejected');

my $legacy_directory = "$tmpdir/legacy";
make_path("$legacy_directory/fs");
write_file("$legacy_directory/kernel", 'legacy kernel');
ok(
    !xCAT_plugin::mknb::_prebuilt_genesis_requested($legacy_directory),
    'the legacy fs layout does not select the prebuilt path',
);

$::XCATROOT = "$tmpdir/xcatroot";
my $process_export =
  "$::XCATROOT/share/xcat/netboot/genesis/ppc64";
prepare_export($process_export, 'process kernel', 'process initramfs', 'ppc64');
$xCAT::TableUtils::tftpdir = "$tmpdir/custom-tftpboot";
$xCAT::NetworkUtils::normnet_addresses = {
    '192.0.2.0/24' => ['192.0.2.1'],
};
$xCAT::NetworkUtils::hexnet_addresses = {};
$xCAT::TableUtils::site_master = undef;
@xCAT::NetworkUtils::master_addresses = ();

my @responses;
xCAT_plugin::mknb::process_request(
    { arg => ['ppc64'] },
    sub { push(@responses, @_); },
);
ok(
    !grep({ ref($_) eq 'HASH' && $_->{error} } @responses),
    'mknb accepts the exported layout',
);
my ($process_kernel, $process_initramfs) =
  published_files($xCAT::TableUtils::tftpdir, 'ppc64');
is(read_file($process_kernel), 'process kernel', 'mknb publishes the exported kernel');
is(read_file($process_initramfs), 'process initramfs', 'mknb publishes the exported initramfs');
ok(
    -f "$xCAT::TableUtils::tftpdir/pxelinux.cfg/p/192.0.2.0_24",
    'mknb writes boot configuration after publishing the export',
);

unlink("$process_export/SHA256SUMS");
@responses = ();
xCAT_plugin::mknb::process_request(
    { arg => ['ppc64'] },
    sub { push(@responses, @_); },
);
ok(
    grep(
        { ref($_) eq 'HASH' && $_->{error}
              && $_->{error}->[0] =~ /Incomplete Genesis export/ }
          @responses
    ),
    'mknb rejects an incomplete marked export',
);
is(
    read_file($process_kernel),
    'process kernel',
    'an incomplete marked export keeps the published kernel',
);
is(
    read_file($process_initramfs),
    'process initramfs',
    'an incomplete marked export keeps the published initramfs',
);

done_testing();
