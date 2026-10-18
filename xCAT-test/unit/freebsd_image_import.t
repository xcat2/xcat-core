#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_IMAGE_MODULE_DIR};
use Carp qw(croak);
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

sub read_file {
    my $path = shift;
    open(my $file, '<', $path) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$file>;
    close($file) or croak "$path: $!";
    return $bytes;
}

sub runtime_descriptor {
    my @extra = @_;
    my @paths = sort(@extra, qw(
        usr/local/sbin/xcat-install usr/local/libexec/xcat-install-lib.sh
        usr/local/share/xcat/installerconfig.tmpl usr/sbin/bsdinstall
        usr/libexec/bsdinstall/script usr/libexec/bsdinstall/pkgbase
        usr/libexec/bsdinstall/umount usr/libexec/flua usr/local/sbin/pkg-static
    ));
    return "format\txcat-freebsd-runtime-2\n"
      . "target\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000\n"
      . "pkg-version\t2.6.2\nbsdinstall-contract\txcat-freebsd-pkgbase-1\n"
      . join('', map { "file\t$_\t" . sha256_hex("runtime $_") . "\n" } @paths);
}

sub fixture {
    my $format = shift || 'xcat-mfsbsd-1';
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
    if ($format eq 'xcat-mfsbsd-2') {
        delete @payload{map { "usr/freebsd-dist/$_" } qw(MANIFEST base.txz kernel.txz)};
        $payload{'xcat/runtime.tsv'} = runtime_descriptor();
    }
    write_file("$root/$_", $payload{$_}) for keys %payload;
    my $manifest = {
        format => $format, release => '15.1-RELEASE', arch => 'amd64',
        mfsbsd_commit => 'a' x 40,
        files => { map { $_ => sha256_hex($payload{$_}) } keys %payload },
    };
    write_manifest($root, $manifest);
    return ($root, $manifest, \%payload);
}

sub rejected {
    my ($mutate, $pattern, $description, $format) = @_;
    my ($root, $manifest, $payload) = fixture($format);
    $mutate->($root, $manifest, $payload);
    eval { xCAT::FreeBSDImage::inspect_media($root); 1 };
    like($@, $pattern, $description);
}

sub replace_runtime {
    my ($root, $manifest, $content) = @_;
    write_file("$root/xcat/runtime.tsv", $content);
    $manifest->{files}{'xcat/runtime.tsv'} = sha256_hex($content);
    write_manifest($root, $manifest);
    return;
}

sub runtime_rejected {
    my ($mutate, $label) = @_;
    rejected(sub {
        my ($root, $manifest, $payload) = @_;
        replace_runtime($root, $manifest, $mutate->($payload->{'xcat/runtime.tsv'}));
    }, qr/runtime|descriptor/ix, $label, 'xcat-mfsbsd-2');
    return;
}

my ($source, $manifest) = fixture();
subtest 'boot postscript capability requires its complete runtime' => sub {
    my ($boot_source, $boot_manifest) = fixture('xcat-mfsbsd-2');
    my @workers = qw(usr/local/libexec/xcat-postscript usr/local/libexec/xcat-postscript-packages
        usr/local/libexec/freebsd-pkg-resolve usr/local/libexec/xcat-postboot);
    $boot_manifest->{postscript_contract} = 'xcat-freebsd-postscripts-1';
    replace_runtime($boot_source, $boot_manifest, runtime_descriptor(@workers));
    my $boot_media = eval { xCAT::FreeBSDImage::inspect_media($boot_source); };
    is($@, '', 'complete postscript runtime is accepted');
    is($boot_media && $boot_media->{postscript_contract}, 'xcat-freebsd-postscripts-1', 'verified capability reaches the caller');
    for my $missing (@workers) {
        replace_runtime($boot_source, $boot_manifest, runtime_descriptor(grep { $_ ne $missing } @workers));
        my $incomplete = eval { xCAT::FreeBSDImage::inspect_media($boot_source); };
        ok(!defined($incomplete), "missing $missing prevents capability acceptance");
        like($@, qr/Required[ ]runtime[ ]file/x, 'missing capability payload has an explicit diagnostic');
    }
    replace_runtime($boot_source, $boot_manifest, runtime_descriptor(@workers));
    for my $unsupported ('future', '', undef, []) {
        $boot_manifest->{postscript_contract} = $unsupported;
        write_manifest($boot_source, $boot_manifest);
        my $invalid = eval { xCAT::FreeBSDImage::inspect_media($boot_source); };
        ok(!defined($invalid), 'unknown or malformed capability is rejected');
        like($@, qr/boot[ ]postscript[ ]contract/x, 'capability validation reports its own boundary');
    }
    my ($legacy_source, $legacy_manifest) = fixture();
    $legacy_manifest->{postscript_contract} = 'xcat-freebsd-postscripts-1';
    write_manifest($legacy_source, $legacy_manifest);
    my $legacy_media = eval { xCAT::FreeBSDImage::inspect_media($legacy_source); };
    ok(!defined($legacy_media), 'distribution-set runtime cannot claim the pkgbase postscript capability');
    like($@, qr/boot[ ]postscript[ ]contract/x, 'legacy capability rejection is explicit');
    done_testing();
};

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
    ['format', 'xcat-mfsbsd-3', qr/format/, 'future format'],
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

sub boot_only_import {
    my ($root, $boot_manifest, $payload) = fixture('xcat-mfsbsd-2');
    my $boot_media = xCAT::FreeBSDImage::inspect_media($root);
    is($boot_media->{format}, 'xcat-mfsbsd-2', 'inspection preserves the boot format');
    is($boot_media->{digest}, sha256_hex(JSON->new->canonical->encode($boot_manifest)), 'the outer manifest identifies the boot bundle');
    is($boot_media->{files}{'xcat/runtime.tsv'}, sha256_hex($payload->{'xcat/runtime.tsv'}), 'the descriptor is pinned by the outer manifest');
    is_deeply([sort keys %$boot_media], [sort(keys %$boot_manifest, qw(distname media_arch digest))],
        'inspection adds identity fields, not a runtime acceptance claim');
    my $target = "$tmp/boot-install";
    make_path($target);
    my $boot_imported = xCAT::FreeBSDImage::import_media($root, $target);
    my $boot_destination = "$target/freebsd15.1/x86_64/boot/$boot_media->{digest}";
    is($boot_imported->{bootdir}, $boot_destination, 'boot media uses its own namespace');
    ok(!exists($boot_imported->{pkgdir}), 'boot media is not returned as a base repository');
    is($boot_imported->{reused}, 0, 'first import publishes the boot media');
    my $published = xCAT::FreeBSDImage::inspect_media($boot_destination);
    is($published && $published->{digest}, $boot_media->{digest}, 'published boot media validates');
    ok(!-e "$boot_destination/usr", 'published boot media contains no distribution tree');
    is((stat($boot_destination))[2] & oct('777'), oct('755'), 'boot root is traversable');
    is((stat("$boot_destination/xcat/runtime.tsv"))[2] & oct('777'), oct('644'), 'descriptor is readable without execute permission');
    is(xCAT::FreeBSDImage::import_media($root, $target)->{reused}, 1, 'repeat import verifies and reuses boot media');
    my $ok = eval { xCAT::FreeBSDImage::import_media($root, $target, nonoverwrite => 1); 1 };
    ok(!$ok, 'nonoverwrite rejects a repeated boot import');
    like($@, qr/already[ ]exists/x, 'nonoverwrite identifies the existing boot destination');
    write_file("$boot_destination/xcat/runtime.tsv", 'changed descriptor');
    $ok = eval { xCAT::FreeBSDImage::import_media($root, $target); 1 };
    ok(!$ok, 'reuse rejects a changed published descriptor');
    like($@, qr/SHA256[ ]mismatch/x, 'reuse reports descriptor corruption');
    $boot_manifest->{mfsbsd_commit} = 'c' x 40;
    write_manifest($root, $boot_manifest);
    my $replacement = xCAT::FreeBSDImage::import_media($root, $target);
    isnt($replacement->{bootdir}, $boot_destination, 'a changed source identity publishes a new boot generation');
    ok(-d $boot_destination, 'the previous generation remains in place');
    return;
}

subtest 'boot-only imports retain a separate content-addressed identity' => \&boot_only_import;

sub boot_only_payload {
    my ($legacy_root, $legacy_manifest) = fixture();
    delete $legacy_manifest->{mfsbsd_commit};
    write_manifest($legacy_root, $legacy_manifest);
    is(xCAT::FreeBSDImage::inspect_media($legacy_root)->{format}, 'xcat-mfsbsd-1',
        'legacy media still permits an absent mfsBSD source commit');
    rejected(sub { delete $_[1]->{mfsbsd_commit}; write_manifest($_[0], $_[1]); },
        qr/source[ ]commit/x, 'v2 requires the mfsBSD source commit', 'xcat-mfsbsd-2');
    rejected(sub { delete $_[1]->{files}{'xcat/runtime.tsv'}; write_manifest($_[0], $_[1]); },
        qr/not[ ]listed/x, 'v2 requires a listed runtime descriptor', 'xcat-mfsbsd-2');
    rejected(sub { unlink("$_[0]/xcat/runtime.tsv") or croak $!; },
        qr/not[ ]found|missing|non-regular/ix, 'v2 requires descriptor bytes', 'xcat-mfsbsd-2');
    rejected(sub { write_file("$_[0]/xcat/runtime.tsv", 'corrupted'); },
        qr/SHA256[ ]mismatch/x, 'descriptor bytes must match the outer pin', 'xcat-mfsbsd-2');
    rejected(sub { write_file("$_[0]/xcat/unlisted", 'unlisted'); },
        qr/not[ ]listed/x, 'v2 rejects unlisted descriptor-directory files', 'xcat-mfsbsd-2');
    rejected(sub {
        rename("$_[0]/xcat/runtime.tsv", "$_[0]/runtime.tsv") or croak $!;
        symlink('../runtime.tsv', "$_[0]/xcat/runtime.tsv") or croak $!;
    }, qr/symlink/x, 'v2 rejects a symlink descriptor', 'xcat-mfsbsd-2');
    for my $kind (qw(directory file symlink)) {
        rejected(sub {
            my $path = "$_[0]/usr/freebsd-dist";
            make_path(dirname($path));
            if ($kind eq 'directory') { make_path($path); }
            elsif ($kind eq 'file') { write_file($path, 'unexpected'); }
            else { symlink('absent', $path) or croak $!; }
        }, qr/distribution[ ]sets/x, "v2 rejects a distribution $kind", 'xcat-mfsbsd-2');
    }
    for my $path (qw(usr/freebsd-dist/base.txz usr/freebsd-dist/kernel.txz usr/freebsd-dist/MANIFEST packages/base.pkg xcat/other.tsv)) {
        rejected(sub {
            write_file("$_[0]/$path", 'unexpected payload');
            $_[1]->{files}{$path} = sha256_hex('unexpected payload');
            write_manifest($_[0], $_[1]);
        }, qr/payload[ ]path/x, "v2 rejects listed $path", 'xcat-mfsbsd-2');
    }
    return;
}

subtest 'boot-only payload and source identity are mandatory' => \&boot_only_payload;

subtest 'install capability is explicit and bound to media identity' => sub {
    my ($root, $capability_manifest) = fixture('xcat-mfsbsd-2');
    my $old = xCAT::FreeBSDImage::inspect_media($root);
    $capability_manifest->{install_contract} = 'xcat-freebsd-install-3';
    write_manifest($root, $capability_manifest);
    my $new = xCAT::FreeBSDImage::inspect_media($root);
    is($new->{install_contract}, 'xcat-freebsd-install-3', 'inspection exposes the declared install contract');
    isnt($new->{digest}, $old->{digest}, 'capability declaration changes immutable media identity');
    for my $value ('', 'xcat-freebsd-install-7', undef, ['xcat-freebsd-install-3']) {
        rejected(sub { $_[1]->{install_contract} = $value; write_manifest($_[0], $_[1]); },
            qr/installation[ ]contract/x, 'unsupported contract', 'xcat-mfsbsd-2');
    }
    rejected(sub { $_[1]->{install_contract} = 'xcat-freebsd-install-3'; write_manifest($_[0], $_[1]); },
        qr/installation[ ]contract/x, 'legacy distribution bundle cannot claim enhanced runtime');
};

subtest 'multi-disk capability requires its complete runtime roster' => sub {
    my $runtime = read_file("$FindBin::Bin/../fixtures/freebsd-storage-runtime.tsv");
    my ($root, $manifest) = fixture('xcat-mfsbsd-2');
    $manifest->{install_contract} = 'xcat-freebsd-install-4';
    replace_runtime($root, $manifest, $runtime);
    my $media = eval { xCAT::FreeBSDImage::inspect_media($root) };
    ok($media, 'complete storage runtime is admitted');
    diag($@) unless $media;
    is($media && $media->{install_contract}, 'xcat-freebsd-install-4', 'validated media advertises multi-disk installation');
    for my $record (grep { /^file\t/mx } split(/\n/x, $runtime)) {
        my (undef, $path) = split(/\t/x, $record);
        my $incomplete = $runtime;
        $incomplete =~ s/^\Q$record\E\n//mx;
        replace_runtime($root, $manifest, $incomplete);
        my $accepted = eval { xCAT::FreeBSDImage::inspect_media($root); 1 };
        ok(!$accepted, "missing $path prevents admission");
        like($@, qr/Required[ ]runtime[ ]file.*\Q$path\E/x, 'refusal identifies the absent dependency');
    }
    replace_runtime($root, $manifest, runtime_descriptor());
    my $accepted = eval { xCAT::FreeBSDImage::inspect_media($root); 1 };
    ok(!$accepted, 'legacy runtime cannot acquire multi-disk capability by changing the manifest');
};

sub runtime_framing {
    for my $case (
        ['xcat-freebsd-runtime-2', 'xcat-freebsd-runtime-3', 'format'],
        ['15.1-RELEASE', '15.0-RELEASE', 'release'],
        ['FreeBSD:15:amd64', 'FreeBSD:15:aarch64', 'ABI'],
        ['1501000', '1500000', 'OSVERSION'],
        ['2.6.2', '2.8.2', 'pkg version'],
        ['xcat-freebsd-pkgbase-1', 'xcat-freebsd-pkgbase-2', 'bsdinstall contract'],
    ) {
        runtime_rejected(sub { my $text = shift; $text =~ s/\Q$case->[0]\E/$case->[1]/x; return $text; },
            "rejects mismatched $case->[2]");
    }
    for my $case (
        ['missing final LF', sub { my $text = shift; chop $text; return $text; }],
        ['CRLF', sub { my $text = shift; $text =~ s/\n/\r\n/gx; return $text; }],
        ['blank record', sub { return "$_[0]\n"; }],
        ['NUL byte', sub { return "$_[0]\0"; }],
        ['duplicate singleton', sub { return "format\txcat-freebsd-runtime-2\n$_[0]"; }],
        ['missing singleton', sub { my $text = shift; $text =~ s/^pkg-version[^\n]*\n//mx; return $text; }],
        ['unknown record', sub { return "$_[0]extra\tvalue\n"; }],
        ['extra singleton field', sub { my $text = shift; $text =~ s/(pkg-version\t2\.6\.2)/$1\textra/x; return $text; }],
        ['trailing TAB', sub { my $text = shift; $text =~ s/\n\z/\t\n/x; return $text; }],
        ['empty field', sub { my $text = shift; $text =~ s/\t1501000\n/\t\n/x; return $text; }],
        ['reordered singleton', sub { my @lines = split /\n/x, $_[0]; @lines[1, 2] = @lines[2, 1]; return join("\n", @lines) . "\n"; }],
    ) {
        runtime_rejected($case->[1], "rejects $case->[0]");
    }
    return;
}

subtest 'runtime descriptor has exact singleton records and byte framing' => \&runtime_framing;

sub runtime_bounds {
    my @records = split /\n/x, runtime_descriptor();
    my @anchors = map { (split /\t/x, $_)[1] } @records[4 .. $#records];
    for my $anchor (@anchors) {
        runtime_rejected(sub { my $text = shift; $text =~ s/^file\t\Q$anchor\E\t[^\n]*\n//mx; return $text; },
            "requires runtime anchor $anchor");
    }
    runtime_rejected(sub { return $_[0] . "$records[-1]\n"; }, 'rejects a duplicate file record');
    runtime_rejected(sub { my @lines = split /\n/x, $_[0]; @lines[4, 5] = @lines[5, 4]; return join("\n", @lines) . "\n"; },
        'rejects unsorted file records');
    for my $path ('/usr/libexec/flua', 'usr//libexec/flua', 'usr/../libexec/flua', 'usr/./libexec/flua', 'usr/libexec/bad name') {
        runtime_rejected(sub { my $text = shift; $text =~ s{usr/libexec/flua}{$path}x; return $text; },
            "rejects runtime path $path");
    }
    for my $hash ('A' x 64, 'g' x 64, 'a' x 63) {
        runtime_rejected(sub { my $text = shift; $text =~ s/[a-f0-9]{64}/$hash/x; return $text; },
            "rejects runtime hash $hash");
    }
    runtime_rejected(sub { return 'x' x 65537; }, 'bounds descriptor bytes');
    runtime_rejected(sub { return runtime_descriptor(map { sprintf('usr/local/libexec/extra%03d', $_) } 1 .. 248); },
        'rejects 257 file records');
    my ($root, $bounded_manifest) = fixture('xcat-mfsbsd-2');
    replace_runtime($root, $bounded_manifest, runtime_descriptor(map { sprintf('usr/local/libexec/extra%03d', $_) } 1 .. 247));
    my $bounded_media = xCAT::FreeBSDImage::inspect_media($root);
    is($bounded_media->{format}, 'xcat-mfsbsd-2', '256 ordered file records are permitted');
    my @extra = map { sprintf('usr/local/libexec/extra%03d', $_) . ('x' x 150) } 1 .. 247;
    my $remaining = 65536 - length(runtime_descriptor(@extra));
    ok($remaining >= 0, 'the exact-size fixture has room for its final path suffix');
    $extra[-1] .= 'x' x $remaining;
    my $exact = runtime_descriptor(@extra);
    is(length($exact), 65536, 'the valid boundary fixture is exactly 65536 bytes');
    replace_runtime($root, $bounded_manifest, $exact);
    is(xCAT::FreeBSDImage::inspect_media($root)->{format}, 'xcat-mfsbsd-2',
        'the maximum descriptor byte length is permitted');
    $extra[-1] .= 'x';
    runtime_rejected(sub { return runtime_descriptor(@extra); },
        'one byte beyond the valid descriptor limit is rejected');
    return;
}

subtest 'runtime anchors are complete, ordered and bounded' => \&runtime_bounds;

sub boot_only_staging {
    my ($root, $staging_manifest) = fixture('xcat-mfsbsd-2');
    my $target = "$tmp/boot-failed";
    make_path($target);
    my $parent = "$target/freebsd15.1/x86_64/boot";
    my $digest = sha256_hex(JSON->new->canonical->encode($staging_manifest));
    for my $fail_at (1, 4, scalar(keys %{$staging_manifest->{files}}) + 1) {
        my $copied = 0;
        {
            no warnings 'redefine';
            local *xCAT::FreeBSDImage::copy = sub {
                if (++$copied == $fail_at) { local $! = 5; return 0; }
                return File::Copy::copy(@_);
            };
            my $ok = eval { xCAT::FreeBSDImage::import_media($root, $target); 1 };
            ok(!$ok, "copy failure at position $fail_at fails the import");
            like($@, qr/Cannot[ ]stage/x, 'the copy error is reported');
        }
        ok(!-e "$parent/$digest", 'no partial boot generation is published');
        my @remaining = glob("$parent/.mfsbsd-stage.*");
        is(scalar(@remaining), 0, 'the failed boot stage is removed');
    }
    {
        no warnings 'redefine';
        local *xCAT::FreeBSDImage::copy = sub {
            my ($from, $to) = @_;
            return 0 unless File::Copy::copy($from, $to);
            write_file($to, 'tampered staged runtime') if $to =~ m{/xcat/runtime\.tsv\z}x;
            return 1;
        };
        my $ok = eval { xCAT::FreeBSDImage::import_media($root, $target); 1 };
        ok(!$ok, 'staged descriptor corruption fails the import');
        like($@, qr/SHA256[ ]mismatch/x, 'staged descriptor bytes are checked');
    }
    ok(!-e "$parent/$digest", 'corrupt staging does not publish a boot generation');
    my @remaining = glob("$parent/.mfsbsd-stage.*");
    is(scalar(@remaining), 0, 'corrupt staging is removed');
    return;
}

subtest 'boot-only staging failures do not publish partial bundles' => \&boot_only_staging;

done_testing();
