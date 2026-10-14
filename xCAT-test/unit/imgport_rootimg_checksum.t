#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Digest::SHA qw(sha256_hex);
use Errno qw(EIO);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use Sys::Hostname qw(hostname);
use Test::More;
use XCAT::Test::File qw(repo_path);

# The first rename into a path of %FAIL fails, as when the file system refuses it.
our %FAIL;
BEGIN {
    *CORE::GLOBAL::rename = sub {
        my ($from, $to) = @_;
        if ($FAIL{$to}) {
            delete $FAIL{$to};
            $! = EIO;
            return 0;
        }
        return CORE::rename($from, $to);
    };
}

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db", "$fixture/install");
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/imgport.pm'));
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'installdir' }, { value => "$fixture/install" });

# noderange keeps the node list for a few seconds, so the node is defined before the first import.
xCAT::Table->new('nodelist', -create => 1)->setAttribs({ node => 'psnode' }, { groups => 'compute' });

# The image lock lives in /var/lock/xcat, so the test records the request and decides whether another operation holds it.
our ($HELD, @LOCKED);
{
    no warnings qw(redefine once);
    *xCAT::Utils::acquire_lock_imageop = sub {
        my (undef, $dir) = @_;
        push @LOCKED, $dir;
        return $HELD ? (1, "failed to acquire lock, seems there is another genimage/packimage/rmimage process 4242 running on root image dir \"$dir\"") : (0, {});
    };
}

(my $host = hostname()) =~ s/[^A-Za-z0-9.-]/_/g;
my $published = "image that packimage published\n";
my $imported  = "image from the bundle\n";
my $sequence  = 0;

# imgimport places the files of an extracted bundle over an image that packimage published before.
sub import_image {
    my ($archive_name, $prepare, %manifest) = @_;
    my $dest   = "$fixture/install/netboot/import-" . ++$sequence;
    my $bundle = "$fixture/bundle-$sequence";
    make_path($dest, $bundle, "$dest/.packimage-$host+INTERRUP");
    write_text("$dest/$archive_name", $published);
    write_text("$dest/$archive_name.sha256", sha256_hex($published) . "  $archive_name\n");
    write_text("$dest/$archive_name.metainfo", "metainfo of the published image\n");
    write_text("$dest/rootimg.other", "another format\n");
    write_text("$dest/.packimage-other.host+ACTIVE00", "archive that another host is writing\n");
    write_text("$bundle/$archive_name", $imported);
    write_text("$dest/kernel", "published kernel\n");
    write_text("$dest/initrd-stateless.gz", "published ramdisk\n");
    write_text("$bundle/kernel", "kernel from the bundle\n");
    write_text("$bundle/initrd-stateless.gz", "ramdisk from the bundle\n");
    $prepare->($dest, $bundle) if $prepare;
    @LOCKED = ();
    my @errors;
    my $checksum = delete $manifest{rootimgchecksum};
    my $nodes    = delete $manifest{nodes};
    my $omit     = delete $manifest{omit} || [];
    my $name = "import-$sequence";
    xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => $name }, { osvers => 'rhels9.5', provmethod => 'netboot' });
    my $data = {
        rootimg => "$dest/$archive_name",
        kernel  => "$dest/kernel",
        ramdisk => "$dest/initrd-stateless.gz",
        (map { ($_ => ref($manifest{$_}) ? $manifest{$_} : $manifest{$_} =~ s/DEST/$dest/r) } keys %manifest),
        (defined $checksum ? (linuximage => { rootimgchecksum => $checksum }) : ()),
        osimage => { imagename => $name, osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute', provmethod => 'netboot' },
    };
    delete @{$data}{@$omit};
    my $placed = xCAT_plugin::imgport::place_image($data, $bundle, sub { push @errors, @{ $_[0]{error} || [] } }, $nodes);
    return ($placed, join("\n", @errors), $dest, "$dest/$archive_name");
}

# The osvers of the image definition, which a failed import must not change.
sub definition {
    my ($dest) = @_;
    my ($name) = $dest =~ m{/(import-\d+)$};
    my ($row) = xCAT::Table->new('osimage')->getAttribs({ imagename => $name }, 'osvers');
    return $row ? $row->{osvers} : undef;
}

for my $archive_name (qw(rootimg.cpio.gz rootimg.tar.xz rootimg.sfs)) {
    my ($placed, $errors, $dest, $archive) = import_image($archive_name);
    is_deeply(\@LOCKED, ["$dest/rootimg"], "$archive_name: the import holds the image lock that packimage takes");
    ok($placed, "$archive_name: the bundle is placed");
    is($errors, '', "$archive_name: no error is reported");
    is(read_binary($archive), $imported, "$archive_name: the imported image replaces the previous one");
    is(read_binary("$dest/kernel"), "kernel from the bundle\n", "$archive_name: the imported kernel is placed");
    is(read_binary("$dest/initrd-stateless.gz"), "ramdisk from the bundle\n", "$archive_name: the imported ramdisk is placed");
    is(read_binary("$archive.sha256"), sha256_hex($imported) . "  $archive_name\n", "$archive_name: the checksum describes the imported image");
    is((stat($archive))[2] & 07777, 0644, "$archive_name: nodes can read the image");
    is((stat("$archive.sha256"))[2] & 07777, 0644, "$archive_name: nodes can read the checksum");
    ok(!-e "$archive.metainfo", "$archive_name: the metainfo of the previous image is removed");
    is(read_binary("$archive.ORIG"), $published, "$archive_name: the previous image is kept as .ORIG");
    is(read_binary("$dest/rootimg.other"), "another format\n", "$archive_name: other formats stay");
    ok(!-e "$dest/.packimage-publish", "$archive_name: the publication lock is released");
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], "$archive_name: no temporary directory is left, including an abandoned one");
    ok(-e "$dest/.packimage-other.host+ACTIVE00", "$archive_name: the archive that another host is writing stays");
    is(definition($dest), 'rhels9.6', "$archive_name: the image definition of the bundle is imported");
}

{
    local $HELD = 1;
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz');
    ok(!$placed, 'an import fails while another image operation holds the image lock');
    like($errors, qr/failed to acquire lock/, 'the held image lock is reported');
    is(read_binary($archive), $published, 'the published image stays while the image lock is held');
    is(read_binary("$archive.sha256"), sha256_hex($published) . "  rootimg.cpio.gz\n", 'the published checksum stays while the image lock is held');
    is(read_binary("$dest/kernel"), "published kernel\n", 'the published kernel stays while the image lock is held');
    is(definition($dest), 'rhels9.5', 'the image definition stays while the image lock is held');
}

{
    # A statelite bundle has a rootimgtree and no rootimg, and its import needs the image lock too.
    local $HELD = 1;
    my $tree;
    my ($placed, $errors, $dest) = import_image('rootimg.cpio.gz', sub {
        my (undef, $bundle) = @_;
        $tree = "$bundle/rootimgtree.gz";
        write_text($tree, "tree from the bundle\n");
    }, rootimgtree => 'DEST/rootimgtree.gz', omit => [qw(rootimg kernel ramdisk)]);
    ok(!$placed, 'a statelite import fails while another command holds the image lock');
    like($errors, qr/failed to acquire lock/, 'the held image lock is reported for a statelite import');
    is_deeply(\@LOCKED, ["$dest/rootimg"], 'a statelite import asks for the lock of its image directory');
    ok(-e $tree, 'the tree stays in the bundle while the lock is held');
    is(definition($dest), 'rhels9.5', 'the image definition stays while the lock of a statelite image is held');
}

{
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', sub {
        my ($dest) = @_;
        mkdir("$dest/.packimage-publish") or die $!;
        write_text("$dest/.packimage-publish/owner", "other.host 4242\n");
        utime(time() - 120, time() - 120, "$dest/.packimage-publish") or die $!;
    });
    ok(!$placed, 'an import fails while another host holds the publication lock');
    like($errors, qr/\Q$dest\E\/\.packimage-publish is held by other\.host 4242\./, 'an import reports a publication lock that another host holds');
    is(read_binary("$dest/kernel"), "published kernel\n", 'the published kernel stays with the published image');
    is(read_binary("$dest/initrd-stateless.gz"), "published ramdisk\n", 'the published ramdisk stays with the published image');
    is(read_binary($archive), $published, 'the published image stays while another host publishes');
    is(read_binary("$archive.sha256"), sha256_hex($published) . "  rootimg.cpio.gz\n", 'the published checksum stays while another host publishes');
    ok(-d "$dest/.packimage-publish", 'the publication lock of the other host is not taken over');
    is(definition($dest), 'rhels9.5', 'the image definition stays while another host publishes');
    is_deeply([ glob("$dest/.packimage-$host+*") ], [], 'no temporary directory is left when the import cannot publish');
}

for my $failed (qw(rootimg.cpio.gz.sha256 rootimg.cpio.gz)) {
    local %FAIL;
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', sub {
        my ($dest) = @_;
        $FAIL{"$dest/$failed"} = 1;
    });
    ok(!$placed, "$failed: an import fails when the imported image cannot be published");
    like($errors, qr/Cannot publish \Q$archive\E: /, "$failed: the failed publication is reported");
    is(read_binary($archive), $published, "$failed: the published image stays");
    is(read_binary("$archive.sha256"), sha256_hex($published) . "  rootimg.cpio.gz\n", "$failed: the published checksum stays");
    is(read_binary("$archive.metainfo"), "metainfo of the published image\n", "$failed: the published metainfo stays");
    is(read_binary("$dest/kernel"), "published kernel\n", "$failed: the published kernel stays with the published image");
    is(read_binary("$dest/initrd-stateless.gz"), "published ramdisk\n", "$failed: the published ramdisk stays with the published image");
    is(definition($dest), 'rhels9.5', "$failed: the image definition stays with the published image");
}

{
    # A file is at the parent of the destination directory, so the extra file fails to copy after the boot files.
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', sub {
        make_path("$fixture/bundle-$sequence/extra");
        write_text("$fixture/bundle-$sequence/extra/late.conf", "extra file from the bundle\n");
        write_text("$fixture/a-file", "a file where a directory goes\n");
    }, extra => { src => '/etc/late.conf', dest => "$fixture/a-file/sub" });
    ok(!$placed, 'an import fails when an extra file cannot be copied');
    like($errors, qr{\Q$fixture/a-file/sub\E}, 'the destination of the failed extra file is reported');
    is(read_binary($archive), $imported, 'the imported image is published before the extra files');
    is(definition($dest), 'rhels9.6', 'the image definition matches the published image when a later step fails');
}

{
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', undef, rootimgchecksum => 'no');
    is($errors, '', 'an image with the check turned off is placed');
    is(read_binary($archive), $imported, 'the imported image replaces the previous one');
    is(read_binary("$archive.sha256"), sha256_hex($imported) . "  rootimg.cpio.gz\n", 'the checksum is written also when the check is turned off');
}

{
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', sub {
        write_text("$fixture/bundle-$sequence/initrd-stateless.gz.rootimgcheck", "sha256=marker of the bundled ramdisk\n");
    }, ramdiskcheck => 'DEST/initrd-stateless.gz.rootimgcheck');
    is($errors, '', 'a bundle with the initial ramdisk marker is placed');
    is(read_binary("$dest/initrd-stateless.gz.rootimgcheck"), "sha256=marker of the bundled ramdisk\n",
        'the marker of the bundled initial ramdisk is placed next to it');
}

for my $nodes (qw(psnode undefined-node)) {
    # The nodes that get the postscripts of the image exist, or not.
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', undef, nodes => $nodes);
    if ($nodes eq 'psnode') {
        is($errors, '', 'an import for a defined node is placed');
        is(read_binary($archive), $imported, 'the image of an import for a defined node is published');
        next;
    }
    ok(!$placed, 'an import for an undefined node fails');
    like($errors, qr/The nodes undefined-node are not defined in xCAT DB\./, 'the undefined node is reported');
    is(read_binary($archive), $published, 'the published image stays for an undefined node');
    is(read_binary("$dest/kernel"), "published kernel\n", 'the published kernel stays for an undefined node');
    is(definition($dest), 'rhels9.5', 'the image definition stays for an undefined node');
}

for my $case ([ kernel => 'kernel' ], [ 'extra/missing.conf' => extra => { src => '/etc/missing.conf', dest => "$fixture/extra" } ],
    [ missingkit => kit => { missingkit => { kitname => 'missingkit', kitdir => "$fixture/kits/missingkit" } } ])
{
    # The bundle lacks a file that its manifest names.
    my ($lacks, $key, $value) = @$case;
    my ($placed, $errors, $dest, $archive) = import_image('rootimg.cpio.gz', sub {
        unlink("$fixture/bundle-$sequence/kernel") or die $! if $key eq 'kernel';
    }, (defined $value ? ($key => $value) : ()));
    ok(!$placed, "an import fails when the bundle lacks $lacks");
    like($errors, qr/The image bundle lacks \Q$lacks\E\./, "the missing $lacks is reported");
    is(read_binary($archive), $published, "the published image stays when the bundle lacks $lacks");
    is(-e "$dest/kernel" ? read_binary("$dest/kernel") : undef, "published kernel\n", "the published kernel stays when the bundle lacks $lacks");
    is(definition($dest), 'rhels9.5', "the image definition stays when the bundle lacks $lacks");
}

done_testing();
