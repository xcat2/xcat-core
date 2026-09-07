#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_IMAGE_MODULE_DIR};
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Compress::Gzip qw(gzip);
use JSON;
use Test::More;
use xCAT::FreeBSDImage;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;

sub write_file {
    my ($path, $data) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or die "$path: $!";
    binmode($fh);
    print $fh $data;
    close($fh) or die "$path: $!";
}

sub write_manifest {
    my ($root, $manifest) = @_;
    write_file("$root/xcat/mfsbsd.json", JSON->new->canonical->encode($manifest));
}

sub fixture {
    my $root = "$tmp/media-" . ++$sequence;
    my $efi = "\0" x 512;
    substr($efi, 0, 2) = 'MZ';
    substr($efi, 60, 4) = pack('V', 128);
    substr($efi, 128, 4) = "PE\0\0";
    substr($efi, 132, 2) = pack('v', 0x8664);
    substr($efi, 152, 2) = pack('v', 0x20b);
    substr($efi, 220, 2) = pack('v', 10);
    my $elf = "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62);
    my ($kernel, $mfsroot);
    gzip(\$elf => \$kernel) or die $IO::Compress::Gzip::GzipError;
    my $ramdisk = 'installer fixture';
    gzip(\$ramdisk => \$mfsroot) or die $IO::Compress::Gzip::GzipError;
    my %payload = (
        'boot/pxeboot' => 'BIOS loader',
        'boot/loader.efi' => $efi,
        'boot/loader.conf' => "mfs_name=\"/mfsroot\"\n",
        'boot/defaults/loader.conf' => 'loader defaults',
        'boot/lua/loader.lua' => 'loader entry',
        'boot/lua/config.lua' => 'loader helper',
        'boot/kernel/kernel.gz' => $kernel,
        'mfsroot.gz' => $mfsroot,
        'usr/freebsd-dist/base.txz' => 'base set',
        'usr/freebsd-dist/kernel.txz' => 'kernel set',
    );
    $payload{'usr/freebsd-dist/MANIFEST'} = join('', map {
        "$_\t" . sha256_hex($payload{"usr/freebsd-dist/$_"}) . "\t1\tbase\t\"fixture\"\ton\n";
    } qw(base.txz kernel.txz));
    write_file("$root/$_", $payload{$_}) for keys %payload;
    my $manifest = {
        format => 'xcat-mfsbsd-1', release => '15.1-RELEASE', arch => 'amd64',
        mfsbsd_commit => 'a' x 40,
        files => { map { $_ => sha256_hex($payload{$_}) } keys %payload },
    };
    write_manifest($root, $manifest);
    return ($root, $manifest, \%payload);
}

sub rejected {
    my ($mutate, $pattern, $description) = @_;
    my ($root, $manifest, $payload) = fixture();
    $mutate->($root, $manifest, $payload);
    eval { xCAT::FreeBSDImage::inspect_media($root); 1 };
    like($@, $pattern, $description);
}

my ($source, $manifest) = fixture();
my $media = xCAT::FreeBSDImage::inspect_media($source);
is($media->{arch}, 'x86_64', 'FreeBSD amd64 uses the xCAT architecture name');
is($media->{media_arch}, 'amd64', 'media architecture remains explicit');
is($media->{distname}, 'freebsd15.1', 'release produces the xCAT distribution name');
is($media->{digest}, sha256_hex(JSON->new->canonical->encode($manifest)), 'exact manifest bytes identify the bundle');
is_deeply($media->{files}, $manifest->{files}, 'inspection returns the verified payload list');
is(xCAT::FreeBSDImage::inspect_media($tmp), undef, 'ordinary media is not claimed');

for my $case (
    ['release', '15.0-RELEASE', qr/15\.1-RELEASE/, 'other FreeBSD release'],
    ['arch', 'aarch64', qr/amd64/, 'other architecture'],
    ['format', 'xcat-mfsbsd-2', qr/format/, 'future format'],
    ['mfsbsd_commit', 'bad', qr/source commit/, 'invalid source commit'],
    ['extra', 'bad', qr/Unknown/, 'unrecognized manifest field'],
    ['release', [], qr/manifest release/, 'structured release value'],
) {
    rejected(sub {
        my ($root, $m) = @_;
        $m->{$case->[0]} = $case->[1];
        write_manifest($root, $m);
    }, $case->[2], "rejects $case->[3]");
}

rejected(sub { write_file("$_[0]/xcat/mfsbsd.json", '{broken'); }, qr/JSON/, 'rejects malformed JSON');
rejected(sub { write_file("$_[0]/xcat/mfsbsd.json", 'x' x 1048577); }, qr/exceeds/, 'bounds manifest size');
rejected(sub { unlink("$_[0]/boot/pxeboot") or die $!; }, qr/not found/, 'requires BIOS loader on disk');
rejected(sub {
    delete $_[1]->{files}{'boot/pxeboot'};
    write_manifest($_[0], $_[1]);
}, qr/not listed/, 'requires BIOS loader in manifest');
rejected(sub { write_file("$_[0]/boot/extra", 'unlisted'); }, qr/not listed/, 'rejects unlisted boot files');
rejected(sub { write_file("$_[0]/usr/freebsd-dist/base.txz", 'corrupted'); }, qr/SHA256 mismatch/, 'rejects distribution corruption');
rejected(sub { write_file("$_[0]/mfsroot.gz", 'corrupted'); }, qr/SHA256 mismatch/, 'rejects installer corruption');
for my $path ('../escape', '/boot/loader', 'boot/../escape', 'boot//escape', 'usr/freebsd-dist/extra.txz', 'boot/bad name') {
    rejected(sub {
        $_[1]->{files}{$path} = 'a' x 64;
        write_manifest($_[0], $_[1]);
    }, qr/payload path/, "rejects payload path $path");
}
rejected(sub {
    $_[1]->{files}{'boot/pxeboot'} = 'g' x 64;
    write_manifest($_[0], $_[1]);
}, qr/Invalid SHA256/, 'rejects malformed hash');
rejected(sub {
    my ($root) = @_;
    rename("$root/boot/pxeboot", "$root/pxeboot") or die $!;
    symlink('../pxeboot', "$root/boot/pxeboot") or die $!;
}, qr/symlink/, 'rejects payload symlinks');
rejected(sub {
    my ($root) = @_;
    rename("$root/boot/lua", "$root/lua") or die $!;
    symlink('../lua', "$root/boot/lua") or die $!;
}, qr/symlink/, 'rejects intermediate directory symlinks');
rejected(sub {
    my ($root, $m, $payload) = @_;
    my $content = $payload->{'usr/freebsd-dist/MANIFEST'};
    $content =~ s/[0-9a-f]{64}/'0' x 64/e;
    write_file("$root/usr/freebsd-dist/MANIFEST", $content);
    $m->{files}{'usr/freebsd-dist/MANIFEST'} = sha256_hex($content);
    write_manifest($root, $m);
}, qr/MANIFEST checksum differs/, 'cross-checks distribution MANIFEST against bundle hashes');
rejected(sub {
    my ($root, $m, $payload) = @_;
    my $content = $payload->{'boot/loader.efi'};
    substr($content, 132, 2) = pack('v', 0xaa64);
    write_file("$root/boot/loader.efi", $content);
    $m->{files}{'boot/loader.efi'} = sha256_hex($content);
    write_manifest($root, $m);
}, qr/amd64 EFI/, 'rejects an ARM EFI executable labeled amd64');
rejected(sub {
    my ($root, $m) = @_;
    my $content = 'not an ELF kernel';
    my $compressed;
    gzip(\$content => \$compressed) or die $IO::Compress::Gzip::GzipError;
    write_file("$root/boot/kernel/kernel.gz", $compressed);
    $m->{files}{'boot/kernel/kernel.gz'} = sha256_hex($compressed);
    write_manifest($root, $m);
}, qr/FreeBSD amd64 ELF/, 'rejects non-FreeBSD kernel');

my $installroot = "$tmp/install";
mkdir($installroot) or die $!;
my $imported = xCAT::FreeBSDImage::import_media($source, $installroot);
my $destination = "$installroot/freebsd15.1/x86_64/$media->{digest}";
is($imported->{pkgdir}, $destination, 'import uses a content-addressed directory');
is($imported->{reused}, 0, 'first import publishes a new bundle');
is(xCAT::FreeBSDImage::inspect_media($destination)->{digest}, $media->{digest}, 'published bundle passes full validation');
is((stat($destination))[2] & 0777, 0755, 'HTTP can traverse imported root');
is((stat("$destination/boot/pxeboot"))[2] & 0777, 0644, 'boot artifacts are world-readable and not executable');
is(xCAT::FreeBSDImage::import_media($source, $installroot)->{reused}, 1, 'repeated import verifies and reuses the same bundle');
eval { xCAT::FreeBSDImage::import_media($source, $installroot, nonoverwrite => 1); };
like($@, qr/already exists/, 'nonoverwrite rejects an existing bundle');
write_file("$destination/boot/pxeboot", 'damaged published file');
eval { xCAT::FreeBSDImage::import_media($source, $installroot); };
like($@, qr/SHA256 mismatch/, 'repeated import does not conceal damaged published media');

my ($other_source, $other_manifest, $other_payload) = fixture();
$other_manifest->{mfsbsd_commit} = 'b' x 40;
write_manifest($other_source, $other_manifest);
my $second = xCAT::FreeBSDImage::import_media($other_source, $installroot);
isnt($second->{pkgdir}, $destination, 'new bundle leaves the previous generation in place');
ok(-d $destination, 'prior bundle directory remains available');

my $failedroot = "$tmp/failed-import";
mkdir($failedroot) or die $!;
{
    no warnings 'redefine';
    local *xCAT::FreeBSDImage::copy = sub { $! = 5; return 0; };
    eval { xCAT::FreeBSDImage::import_media($source, $failedroot); };
    like($@, qr/Cannot stage/, 'copy failure is returned');
}
ok(!-e "$failedroot/freebsd15.1/x86_64/$media->{digest}", 'copy failure does not publish a partial bundle');
my @stages = glob("$failedroot/freebsd15.1/x86_64/.mfsbsd-stage.*");
is(scalar(@stages), 0, 'failed copy removes its staging tree');

for my $fail_at (3, scalar(keys %{$manifest->{files}}) + 1) {
    my $copied = 0;
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDImage::copy = sub {
            if (++$copied == $fail_at) { $! = 5; return 0; }
            return File::Copy::copy(@_);
        };
        eval { xCAT::FreeBSDImage::import_media($source, $failedroot); };
        like($@, qr/Cannot stage/, "copy failure at file $fail_at is returned");
    }
    ok(!-e "$failedroot/freebsd15.1/x86_64/$media->{digest}", 'partial copy is not published');
    my @remaining = glob("$failedroot/freebsd15.1/x86_64/.mfsbsd-stage.*");
    is(scalar(@remaining), 0, 'partial copy is removed');
}
{
    no warnings 'redefine';
    local *xCAT::FreeBSDImage::copy = sub {
        my ($from, $to) = @_;
        return 0 unless File::Copy::copy($from, $to);
        write_file($to, 'changed during copy') if $to =~ m{/boot/pxeboot\z};
        return 1;
    };
    eval { xCAT::FreeBSDImage::import_media($source, $failedroot); };
    like($@, qr/SHA256 mismatch/, 'staged content is verified after copying');
}
ok(!-e "$failedroot/freebsd15.1/x86_64/$media->{digest}", 'corrupt staging payload is not published');
@stages = glob("$failedroot/freebsd15.1/x86_64/.mfsbsd-stage.*");
is(scalar(@stages), 0, 'corrupt staging payload is removed');

my $symlinkroot = "$tmp/symlink-import";
mkdir($symlinkroot) or die $!;
symlink($installroot, "$symlinkroot/freebsd15.1") or die $!;
eval { xCAT::FreeBSDImage::import_media($source, $symlinkroot); };
like($@, qr/symlink/, 'does not import through a symlinked distribution directory');

done_testing();
