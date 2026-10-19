package xCAT::FreeBSDImage;

use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use IO::Uncompress::Gunzip;
use JSON;

my $MARKER = 'xcat/mfsbsd.json';
my @BOOT_FILES = qw(
  boot/pxeboot boot/loader.efi boot/loader.conf boot/defaults/loader.conf
  boot/lua/loader.lua boot/kernel/kernel.gz mfsroot.gz
);
my @DIST_FILES = qw(
  usr/freebsd-dist/MANIFEST usr/freebsd-dist/base.txz usr/freebsd-dist/kernel.txz
);
my @RUNTIME_FILES = qw(
  usr/local/sbin/xcat-install usr/local/libexec/xcat-install-lib.sh
  usr/local/share/xcat/installerconfig.tmpl usr/sbin/bsdinstall
  usr/libexec/bsdinstall/script usr/libexec/bsdinstall/pkgbase
  usr/libexec/bsdinstall/umount usr/libexec/flua usr/local/sbin/pkg-static
);
my @STORAGE_FILES = qw(
  bin/rmdir boot/gptzfsboot boot/loader.efi boot/pmbr
  sbin/mount_msdosfs sbin/newfs_msdos sbin/zfs usr/bin/basename usr/bin/cut usr/bin/od
  usr/libexec/bsdconfig/040.password/include/messages.subr
  usr/libexec/bsdconfig/include/messages.subr usr/libexec/bsdinstall/bootconfig
  usr/libexec/bsdinstall/config usr/libexec/bsdinstall/entropy
  usr/libexec/bsdinstall/mount usr/libexec/bsdinstall/mount_aux usr/libexec/bsdinstall/zfsboot
  usr/local/libexec/xcat-storage usr/local/libexec/xcat-storage-efi.sh
  usr/share/bsdconfig/common.subr usr/share/bsdconfig/device.subr usr/share/bsdconfig/dialog.subr
  usr/share/bsdconfig/geom.subr usr/share/bsdconfig/password/password.subr
  usr/share/bsdconfig/strings.subr usr/share/bsdconfig/struct.subr usr/share/bsdconfig/variable.subr
  usr/sbin/chroot usr/sbin/efibootmgr usr/sbin/efivar usr/sbin/fstyp
);

sub _fail { die "$_[0]\n"; }

sub _regular_file {
    my $path = shift;
    _fail("Missing, empty, or non-regular bundle file $path")
      unless lstat($path) && -f _ && !-l _ && -s _;
}

sub _read_file {
    my ($path, $limit) = @_;
    _regular_file($path);
    _fail("Bundle file exceeds $limit bytes: $path") if -s $path > $limit;
    open(my $fh, '<', $path) or _fail("Cannot open $path: $!");
    local $/;
    my $data = <$fh>;
    close($fh) or _fail("Cannot close $path: $!");
    _fail("Cannot read $path") unless defined($data);
    return $data;
}

sub _digest {
    my $path = shift;
    _regular_file($path);
    open(my $fh, '<', $path) or _fail("Cannot open $path: $!");
    binmode($fh);
    my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
    close($fh) or _fail("Cannot close $path: $!");
    return $digest;
}

sub _prefix {
    my ($path, $length) = @_;
    open(my $fh, '<', $path) or _fail("Cannot open $path: $!");
    binmode($fh);
    my $bytes = '';
    my $read = read($fh, $bytes, $length);
    close($fh) or _fail("Cannot close $path: $!");
    _fail("Cannot read $length bytes from $path") unless defined($read) && $read == $length;
    return $bytes;
}

sub _validate_boot_arch {
    my $root = shift;
    my $loader = _prefix("$root/boot/loader.efi", 512);
    my $offset = unpack('V', substr($loader, 60, 4));
    _fail('The bundle EFI loader is not an amd64 EFI application')
      unless substr($loader, 0, 2) eq 'MZ' && $offset <= 416
      && substr($loader, $offset, 4) eq "PE\0\0"
      && unpack('v', substr($loader, $offset + 4, 2)) == 0x8664
      && unpack('v', substr($loader, $offset + 24, 2)) == 0x20b
      && unpack('v', substr($loader, $offset + 92, 2)) == 10;
    my $kernel = IO::Uncompress::Gunzip->new("$root/boot/kernel/kernel.gz", Transparent => 0)
      or _fail('Cannot decompress the bundle kernel');
    my $header = '';
    my $read = $kernel->read($header, 20);
    $kernel->close();
    _fail('The bundle kernel is not a FreeBSD amd64 ELF image')
      unless $read == 20 && substr($header, 0, 8) eq "\x7fELF\x02\x01\x01\x09"
      && unpack('v', substr($header, 18, 2)) == 62;
    _fail('The mfsBSD root image is not gzip compressed')
      unless _prefix("$root/mfsroot.gz", 2) eq "\x1f\x8b";
}

sub _directory {
    my $path = shift;
    _fail("Bundle directory is missing or is a symlink: $path")
      unless lstat($path) && -d _ && !-l _;
}

sub _relative_path {
    my $path = shift;
    return 0 unless defined($path) && $path =~ m{\A[A-Za-z0-9_.+-]+(?:/[A-Za-z0-9_.+-]+)*\z};
    return 0 if grep { $_ eq '.' || $_ eq '..' } split(m{/}, $path);
    return 1;
}

sub _payload_path {
    my ($path, $boot_only) = @_;
    return 0 unless _relative_path($path);
    return 1 if $path eq 'mfsroot.gz' || $path =~ m{\Aboot/};
    return $boot_only ? $path eq 'xcat/runtime.tsv'
      : $path =~ m{\Ausr/freebsd-dist/(?:MANIFEST|base\.txz|kernel\.txz)\z};
}

sub _validate_runtime {
    my ($root, $postscripts, $storage, $network, $datasets) = @_;
    my @records = split(/\n/x, _read_file("$root/xcat/runtime.tsv", 65536), -1);
    _fail('Runtime descriptor must end with one LF') unless pop(@records) eq '';
    my @prefix = (
        "format\txcat-freebsd-runtime-2",
        "target\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000",
        "pkg-version\t2.6.2",
        "bsdinstall-contract\txcat-freebsd-pkgbase-1",
    );
    for my $expected (@prefix) {
        _fail('Unsupported runtime descriptor contract') unless @records && shift(@records) eq $expected;
    }
    _fail('Runtime descriptor must contain 1 to 256 file records') if !@records || @records > 256;
    my %files;
    my $previous = '';
    for my $line (@records) {
        my @fields = split(/\t/x, $line, -1);
        _fail('Invalid runtime file record') unless @fields == 3 && $fields[0] eq 'file';
        my ($path, $digest) = @fields[1, 2];
        _fail("Invalid runtime file path: $path") unless _relative_path($path);
        _fail("Invalid runtime SHA256 for $path") unless $digest =~ /\A[0-9a-f]{64}\z/x;
        _fail('Runtime file records must be unique and path-sorted') if $path le $previous;
        $previous = $path;
        $files{$path} = 1;
    }
    my @required = @RUNTIME_FILES;
    push @required, qw(usr/local/libexec/xcat-postscript usr/local/libexec/xcat-postscript-packages
        usr/local/libexec/freebsd-pkg-resolve usr/local/libexec/xcat-postboot) if $postscripts;
    push @required, @STORAGE_FILES if $storage;
    push @required, 'usr/local/libexec/configzfs-datasets.awk' if $datasets;
    push @required, qw(usr/local/libexec/xcat-network.sh usr/local/libexec/confignetwork-freebsd.awk
        boot/modules/if_infiniband.ko boot/modules/if_lagg.ko boot/modules/bridgestp.ko
        boot/modules/if_bridge.ko boot/modules/if_vlan.ko) if $network;
    for my $path (@required) {
        _fail("Required runtime file is not listed: $path") unless $files{$path};
    }
    return;
}

sub _validate_payload {
    my ($root, $files, @trees) = @_;
    my %found;
    File::Find::find({
        no_chdir => 1,
        wanted => sub {
            my $entry_path = $File::Find::name;
            _fail("Cannot inspect bundle path $entry_path: $!") unless lstat($entry_path);
            _fail("Unsupported bundle symlink or special file: $entry_path") if -l _ || !(-f _ || -d _);
            return if -d _;
            my $relative = substr($entry_path, length($root) + 1);
            return if $relative eq $MARKER;
            _fail("Bundle file is not listed in the manifest: $relative") unless exists($files->{$relative});
            $found{$relative} = 1;
        },
    }, @trees);
    $found{'mfsroot.gz'} = 1;
    for my $path (sort keys %$files) {
        _fail("Bundle file was not found: $path") unless $found{$path};
        _fail("Bundle SHA256 mismatch: $path") unless _digest("$root/$path") eq $files->{$path};
    }
    return;
}

sub _validate_distributions {
    my ($root, $files) = @_;
    my $dist_manifest = _read_file("$root/usr/freebsd-dist/MANIFEST", 1048576);
    for my $set (qw(base.txz kernel.txz)) {
        my @entries = grep { /^\Q$set\E\t/ } split(/\n/, $dist_manifest);
        _fail("Distribution MANIFEST must contain one $set entry") unless @entries == 1;
        my @fields = split(/\t/, $entries[0]);
        _fail("Distribution MANIFEST checksum differs for $set")
          unless @fields >= 2 && $fields[1] eq $files->{"usr/freebsd-dist/$set"};
    }
    return;
}

sub inspect_media {
    my $root = shift;
    _fail('A bundle directory is required') unless defined($root) && length($root);
    return undef unless -e "$root/$MARKER" || -l "$root/$MARKER";
    _directory($root);
    _directory("$root/xcat");
    my $raw = _read_file("$root/$MARKER", 1048576);
    my $manifest = eval { JSON->new->utf8->decode($raw) };
    _fail('Invalid xCAT mfsBSD JSON manifest') unless ref($manifest) eq 'HASH';
    my %allowed = map { $_ => 1 } qw(format release arch files mfsbsd_commit postscript_contract
        install_contract network_contract dataset_contract disk_selection_contract);
    _fail('Unknown xCAT mfsBSD manifest field') if grep { !$allowed{$_} } keys %$manifest;
    for my $key (qw(format release arch)) {
        _fail("Missing or invalid mfsBSD manifest $key")
          unless defined($manifest->{$key}) && !ref($manifest->{$key});
    }
    _fail('Unsupported mfsBSD bundle format')
      unless $manifest->{format} eq 'xcat-mfsbsd-1' || $manifest->{format} eq 'xcat-mfsbsd-2';
    my $boot_only = $manifest->{format} eq 'xcat-mfsbsd-2';
    _fail('Unsupported installation contract') if exists($manifest->{install_contract}) &&
        (!$boot_only || !defined($manifest->{install_contract}) || ref($manifest->{install_contract}) ||
         $manifest->{install_contract} !~ /\Axcat-freebsd-install-[3456]\z/x);
    if (exists($manifest->{postscript_contract})) {
        _fail('Unsupported boot postscript contract') unless $boot_only
          && defined($manifest->{postscript_contract}) && ref($manifest->{postscript_contract}) eq ''
          && $manifest->{postscript_contract} eq 'xcat-freebsd-postscripts-1';
    }
    if (exists($manifest->{network_contract})) {
        _fail('Unsupported bootstrap network contract') unless $boot_only &&
            ($manifest->{install_contract} || '') =~ /\Axcat-freebsd-install-[3456]\z/x &&
            defined($manifest->{network_contract}) && !ref($manifest->{network_contract}) &&
            $manifest->{network_contract} eq 'xcat-freebsd-bootstrap-1';
    }
    if (exists($manifest->{dataset_contract})) {
        _fail('Unsupported dataset contract') unless $boot_only &&
            ($manifest->{install_contract} || '') =~ /\Axcat-freebsd-install-[456]\z/x &&
            defined($manifest->{dataset_contract}) && !ref($manifest->{dataset_contract}) &&
            $manifest->{dataset_contract} eq 'xcat-freebsd-datasets-1';
    }
    if (exists($manifest->{disk_selection_contract})) {
        _fail('Unsupported disk selection contract') unless $boot_only &&
            ($manifest->{install_contract} || '') =~ /\Axcat-freebsd-install-[3456]\z/x &&
            defined($manifest->{disk_selection_contract}) && !ref($manifest->{disk_selection_contract}) &&
            $manifest->{disk_selection_contract} eq 'xcat-freebsd-disk-selection-1';
    }
    _fail('Only FreeBSD 15.1-RELEASE bundles are supported') unless $manifest->{release} eq '15.1-RELEASE';
    _fail('Only FreeBSD amd64 bundles are supported') unless $manifest->{arch} eq 'amd64';
    _fail('A v2 bundle requires its mfsBSD source commit') if $boot_only && !exists($manifest->{mfsbsd_commit});
    _fail('Invalid mfsBSD source commit')
      if exists($manifest->{mfsbsd_commit})
      && (!defined($manifest->{mfsbsd_commit}) || ref($manifest->{mfsbsd_commit})
          || $manifest->{mfsbsd_commit} !~ /\A[0-9a-f]{40}\z/);
    my $files = $manifest->{files};
    _fail('The bundle manifest must list its payload checksums')
      unless ref($files) eq 'HASH' && keys(%$files) && keys(%$files) <= 8192;
    for my $path (keys %$files) {
        _fail("Invalid bundle payload path: $path") unless _payload_path($path, $boot_only);
        _fail("Invalid SHA256 for $path") unless defined($files->{$path})
          && !ref($files->{$path}) && $files->{$path} =~ /\A[0-9a-f]{64}\z/;
    }
    for my $path (@BOOT_FILES, $boot_only ? 'xcat/runtime.tsv' : @DIST_FILES) {
        _fail("Required bundle file is not listed: $path") unless exists($files->{$path});
    }
    _directory("$root/boot");
    my @trees = ("$root/boot");
    if ($boot_only) {
        _fail('A v2 boot bundle must not contain distribution sets')
          if -e "$root/usr/freebsd-dist" || -l "$root/usr/freebsd-dist";
        push @trees, "$root/xcat";
    } else {
        _directory("$root/usr");
        _directory("$root/usr/freebsd-dist");
        push @trees, "$root/usr/freebsd-dist";
    }
    _validate_payload($root, $files, @trees);
    if ($boot_only) {
        _validate_runtime($root, exists($manifest->{postscript_contract}),
            scalar(($manifest->{install_contract} || '') =~ /\Axcat-freebsd-install-[456]\z/x),
            exists($manifest->{network_contract}), exists($manifest->{dataset_contract}));
    } else {
        _validate_distributions($root, $files);
    }
    _validate_boot_arch($root);
    return {
        %$manifest,
        arch => 'x86_64',
        media_arch => 'amd64',
        distname => 'freebsd15.1',
        digest => sha256_hex($raw),
    };
}

sub _remove_stage {
    my $stage = shift;
    my $errors;
    remove_tree($stage, { error => \$errors });
    _fail('Cannot remove import staging directory: ' . join('; ', map {
        my ($path, $message) = %$_;
        "$path: $message";
    } @$errors)) if $errors && @$errors;
}

sub import_media {
    my ($source, $installroot, %options) = @_;
    my $media = inspect_media($source);
    _fail('The media is not an xCAT mfsBSD bundle') unless $media;
    _fail('The installation root must be an existing absolute directory')
      unless defined($installroot) && $installroot =~ m{\A/[^\x00\r\n]+\z} && -d $installroot;
    $installroot = abs_path($installroot);
    _fail('The installation root cannot be /') unless defined($installroot) && $installroot ne '/';
    my $boot_only = $media->{format} eq 'xcat-mfsbsd-2';
    my $archdir = "$installroot/$media->{distname}/$media->{arch}";
    my @directories = ("$installroot/$media->{distname}", $archdir,
        $boot_only ? "$archdir/boot" : ());
    for my $dir (@directories) {
        mkdir($dir, 0755) or _fail("Cannot create $dir: $!") unless -e $dir || -l $dir;
        _directory($dir);
    }
    my $parent = $directories[-1];
    my $role = $boot_only ? 'bootdir' : 'pkgdir';
    my $lockpath = "$parent/.mfsbsd-import.lock";
    sysopen(my $lock, $lockpath, O_CREAT | O_RDWR | O_NOFOLLOW, 0600)
      or _fail("Cannot open import lock $lockpath: $!");
    flock($lock, LOCK_EX) or _fail("Cannot acquire import lock: $!");
    my $destination = "$parent/$media->{digest}";
    if (-e $destination || -l $destination) {
        _fail("Bundle destination already exists: $destination") if $options{nonoverwrite};
        _directory($destination);
        my $existing = inspect_media($destination);
        _fail("Existing bundle differs from its directory digest: $destination")
          unless $existing && $existing->{digest} eq $media->{digest};
        return { %$media, $role => $destination, reused => 1 };
    }
    my $stage = tempdir('.mfsbsd-stage.XXXXXXXX', DIR => $parent, CLEANUP => 0);
    my $ok = eval {
        chmod(0755, $stage) or _fail("Cannot set staging directory permissions: $!");
        for my $relative (sort(keys %{ $media->{files} }), $MARKER) {
            my $target = "$stage/$relative";
            make_path(dirname($target), { mode => 0755 });
            copy("$source/$relative", $target) or _fail("Cannot stage $relative: $!");
            chmod(0644, $target) or _fail("Cannot set permissions on $target: $!");
        }
        my $staged = inspect_media($stage);
        _fail('Bundle manifest changed while copying') unless $staged->{digest} eq $media->{digest};
        rename($stage, $destination) or _fail("Cannot publish bundle $destination: $!");
        1;
    };
    unless ($ok) {
        my $error = $@ || 'Unknown mfsBSD import error';
        eval { _remove_stage($stage); 1 } or $error .= $@;
        die $error;
    }
    return { %$media, $role => $destination, reused => 0 };
}

1;
