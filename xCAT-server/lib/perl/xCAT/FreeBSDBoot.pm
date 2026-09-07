package xCAT::FreeBSDBoot;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Errno qw(EEXIST);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find;
use File::Path qw(remove_tree);
use File::Temp qw(tempdir tempfile);
use IO::Handle;

sub _fail { die "FreeBSD boot publication: $_[0]\n"; }

sub _identity {
    my ($node, $generation) = @_;
    _fail('Invalid node name') unless defined($node) && !ref($node) &&
      $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/;
    _fail('Invalid generation') unless defined($generation) && !ref($generation) && $generation =~ /\A[0-9a-f]{32}\z/;
}

sub _directory {
    my ($path, $create) = @_;
    if ($create && !(-e $path || -l $path)) {
        _fail("Cannot create $path: $!") if !mkdir($path, 0755) && $! != EEXIST;
    }
    my @stat = lstat($path);
    _fail("Not a plain directory: $path") unless @stat && -d _ && !-l _;
    _fail("Unsafe directory permissions: $path") unless ($stat[4] == 0 || $stat[4] == $>) &&
      (!(($stat[2] & 0022)) || ($stat[2] & 01000));
}

sub _absolute_directory {
    my $path = shift;
    _fail('An existing absolute directory is required') unless defined($path) && !ref($path) &&
      $path =~ m{\A/(?:[A-Za-z0-9_.+-]+/)*[A-Za-z0-9_.+-]+/?\z};
    $path =~ s{/$}{};
    my $current = '';
    for my $part (split(m{/}, substr($path, 1))) {
        _fail('Directory traversal is not permitted') if $part eq '.' || $part eq '..';
        $current .= "/$part";
        _directory($current);
    }
    return $path;
}

sub _parents {
    my ($root, $relative) = @_;
    my @parts = split(m{/}, $relative);
    pop @parts;
    my $current = $root;
    for my $part (@parts) {
        $current .= "/$part";
        _directory($current, 1);
    }
}

sub _file_hash {
    my $path = shift;
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW) or _fail("Cannot open $path: $!");
    _fail("Not a regular file: $path") unless -f $file;
    my @stat = stat($file);
    binmode($file);
    my $hash = Digest::SHA->new(256)->addfile($file)->hexdigest;
    close($file) or _fail("Cannot close $path: $!");
    return ($hash, [@stat[0, 1]]);
}

sub _verify_tree {
    my ($root, $expected, $shared) = @_;
    _directory($root);
    my %directories = ('' => 1);
    for my $expected_path (keys %$expected) {
        my $parent = dirname($expected_path);
        while ($parent ne '.') {
            $directories{$parent} = 1;
            $parent = dirname($parent);
        }
    }
    my %found;
    File::Find::find({ no_chdir => 1, wanted => sub {
        my $path = $File::Find::name;
        my $relative = $path eq $root ? '' : substr($path, length($root) + 1);
        _fail("Cannot inspect $path: $!") unless lstat($path);
        _fail("Unexpected boot tree entry: $path") if -l _ || !(-f _ || -d _);
        if (-d _) {
            _fail("Unexpected boot directory: $path") unless $directories{$relative};
            _directory($path);
            return;
        }
        _fail("Unexpected boot file: $path") unless exists($expected->{$relative});
        my @stat = lstat($path);
        _fail("Unsafe boot file permissions: $path") unless ($stat[4] == 0 || $stat[4] == $>) && !($stat[2] & 0022);
        if ($shared && $relative ne 'boot/loader.conf') {
            my $source = $shared->{$relative};
            _fail("Boot payload is not linked to its shared image: $path")
              unless $source && $stat[0] == $source->[0] && $stat[1] == $source->[1];
            $found{$relative} = [@stat[0, 1]];
        } else {
            my ($hash, $identity) = _file_hash($path);
            _fail("Boot checksum mismatch: $path") unless $hash eq $expected->{$relative};
            $found{$relative} = $identity;
        }
    } }, $root);
    _fail("Missing boot file: $_") for grep { !$found{$_} } keys %$expected;
    return \%found;
}

sub _stage {
    my ($parent, $destination, $writer, $verifier) = @_;
    if (-e $destination || -l $destination) {
        return $verifier->($destination);
    }
    my $stage = tempdir('.publish-stage.XXXXXXXX', DIR => $parent, CLEANUP => 0);
    my $verified;
    my $ok = eval {
        chmod(0755, $stage) or _fail("Cannot set directory permissions: $!");
        $writer->($stage);
        $verified = $verifier->($stage);
        rename($stage, $destination) or _fail("Cannot publish $destination: $!");
        1;
    };
    unless ($ok) {
        my $error = $@;
        my $errors;
        remove_tree($stage, { error => \$errors });
        $error .= "Cannot remove failed publication stage $stage\n" if $errors && @$errors;
        die $error;
    }
    return $verified;
}

sub _stable_target {
    my ($root, $node) = @_;
    my $stable = "$root/$node";
    return undef unless -e $stable || -l $stable;
    _fail("Refusing to replace an unrelated node path: $stable") unless -l $stable;
    my $target = readlink($stable);
    _fail("Refusing to replace an unrelated node link: $stable") unless defined($target) &&
      $target =~ m{\A\.nodes/\Q$node\E/[0-9a-f]{32}\z};
    _directory("$root/$target");
    return $target;
}

sub _verify_config {
    my ($path, $content) = @_;
    sysopen(my $file, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or _fail("Cannot open configuration $path: $!");
    my @stat = stat($file);
    _fail("Unsafe configuration file: $path") unless -f $file && ($stat[4] == 0 || $stat[4] == $>) &&
      ($stat[2] & 07777) == 0644 && $stat[7] <= 32768;
    binmode($file);
    my $actual = do { local $/; <$file> };
    close($file) or _fail("Cannot close configuration $path: $!");
    _fail("Configuration generation contents differ: $path") unless defined($actual) && $actual eq $content;
}

sub publish_config {
    my ($node, %options) = @_;
    my %allowed = map { $_ => 1 } qw(generation installroot content);
    _fail('Unknown configuration publication option') if grep { !$allowed{$_} } keys %options;
    my $generation = $options{generation};
    _identity($node, $generation);
    my $content = $options{content};
    _fail('Configuration must contain 1 to 32768 bytes') unless defined($content) && !ref($content) &&
      utf8::downgrade($content, 1) && length($content) && length($content) <= 32768;
    my $root = _absolute_directory($options{installroot});
    my $relative = "autoinst/freebsd/$node/$generation.conf";
    _parents($root, $relative);
    my $destination = "$root/$relative";
    if (-e $destination || -l $destination) {
        _verify_config($destination, $content);
        return $relative;
    }
    my ($file, $temporary) = tempfile('.config-stage.XXXXXXXX', DIR => dirname($destination), UNLINK => 0);
    eval {
        binmode($file);
        print {$file} $content or _fail("Cannot write configuration: $!");
        $file->flush or _fail("Cannot flush configuration: $!");
        chmod(0644, $file) or _fail("Cannot protect configuration: $!");
        $file->sync or _fail("Cannot sync configuration: $!");
        close($file) or _fail("Cannot close configuration: $!");
        _verify_config($temporary, $content);
        if (!link($temporary, $destination)) {
            _fail("Cannot publish configuration: $!") unless $! == EEXIST;
        }
        _verify_config($destination, $content);
        1;
    };
    my $error = $@;
    close($file) if defined(fileno($file));
    $error .= "Cannot remove temporary configuration $temporary: $!\n" unless unlink($temporary);
    die $error if length($error);
    return $relative;
}

sub publish {
    my ($node, %options) = @_;
    my %allowed = map { $_ => 1 } qw(generation pkgdir media tftpdir config_url config_sha256 mac);
    _fail('Unknown publication option') if grep { !$allowed{$_} } keys %options;
    my $generation = $options{generation};
    _identity($node, $generation);
    _fail('Invalid configuration checksum') unless defined($options{config_sha256}) &&
      !ref($options{config_sha256}) && $options{config_sha256} =~ /\A[0-9a-f]{64}\z/;
    _fail('Invalid provisioning MAC') unless defined($options{mac}) && !ref($options{mac}) &&
      $options{mac} =~ /\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/;
    my $url = $options{config_url};
    _fail('Invalid configuration URL') unless defined($url) && !ref($url) &&
      $url =~ m{\Ahttps?://[A-Za-z0-9.-]+(?::[0-9]{1,5})?/[A-Za-z0-9_.+/-]+\z} &&
      $url !~ m{/\.\.?(?:/|\z)};
    my $media = $options{media};
    _fail('Validated FreeBSD 15.1 media is required') unless ref($media) eq 'HASH' &&
      ($media->{format} || '') eq 'xcat-mfsbsd-1' && ($media->{release} || '') eq '15.1-RELEASE' &&
      ($media->{arch} || '') eq 'x86_64' && ($media->{distname} || '') eq 'freebsd15.1' &&
      defined($media->{digest}) && !ref($media->{digest}) && $media->{digest} =~ /\A[0-9a-f]{64}\z/ &&
      ref($media->{files}) eq 'HASH' && keys(%{$media->{files}}) <= 8192;
    my %payload;
    for my $payload_path (keys %{$media->{files}}) {
        next if $payload_path =~ m{\Ausr/freebsd-dist/(?:MANIFEST|base\.txz|kernel\.txz)\z};
        _fail("Invalid boot payload path: $payload_path") unless
          $payload_path =~ m{\A(?:boot/[A-Za-z0-9_.+/-]+|mfsroot\.gz)\z} &&
          $payload_path !~ m{(?:\A|/)\.\.?(?:/|\z)|//|/\z};
        my $hash = $media->{files}{$payload_path};
        _fail("Invalid boot checksum: $payload_path") unless defined($hash) && !ref($hash) && $hash =~ /\A[0-9a-f]{64}\z/;
        $payload{$payload_path} = $hash;
    }
    _fail("Missing required boot payload: $_") for grep { !exists($payload{$_}) }
      qw(boot/pxeboot boot/loader.efi boot/loader.conf boot/defaults/loader.conf boot/lua/loader.lua boot/kernel/kernel.gz mfsroot.gz);
    my $source = _absolute_directory($options{pkgdir});
    my $tftp = _absolute_directory($options{tftpdir});
    _directory("$tftp/xcat", 1);
    my $root = "$tftp/xcat/freebsd";
    _directory($root, 1);
    sysopen(my $lock, "$root/.publish.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0600)
      or _fail("Cannot open publication lock: $!");
    _fail('Unsafe publication lock') unless -f $lock && (stat($lock))[4] == $> && !((stat($lock))[2] & 0077);
    flock($lock, LOCK_EX) or _fail("Cannot lock publication: $!");
    _directory("$root/.images", 1);
    _directory("$root/.nodes", 1);
    _directory("$root/.nodes/$node", 1);
    my $old_target = _stable_target($root, $node);
    my $shared = "$root/.images/$media->{digest}";
    my $verified = _stage("$root/.images", $shared, sub {
        my $stage = shift;
        for my $relative (sort keys %payload) {
            my $parent = dirname($relative);
            _absolute_directory("$source/$parent") unless $parent eq '.';
            sysopen(my $input, "$source/$relative", O_RDONLY | O_NOFOLLOW)
              or _fail("Cannot open source boot payload $relative: $!");
            _fail("Source boot payload is not regular: $relative") unless -f $input;
            _parents($stage, $relative);
            copy($input, "$stage/$relative") or _fail("Cannot copy $relative: $!");
            close($input) or _fail("Cannot close source boot payload $relative: $!");
            chmod(0444, "$stage/$relative") or _fail("Cannot protect $relative: $!");
        }
    }, sub { _verify_tree($_[0], \%payload); });
    sysopen(my $loader, "$shared/boot/loader.conf", O_RDONLY | O_NOFOLLOW) or _fail("Cannot read loader configuration: $!");
    _fail('Loader configuration exceeds 1 MiB') if (stat($loader))[7] > 1048576;
    my $loader_text = do { local $/; <$loader> };
    close($loader) or _fail("Cannot close loader configuration: $!");
    $loader_text .= "\nxcat_config_url=\"$url\"\nxcat_config_sha256=\"$options{config_sha256}\"\nboot.netif.hwaddr=\"$options{mac}\"\n";
    my %node_payload = (%payload, 'boot/loader.conf' => sha256_hex($loader_text));
    my $destination = "$root/.nodes/$node/$generation";
    _stage("$root/.nodes/$node", $destination, sub {
        my $stage = shift;
        for my $relative (sort keys %payload) {
            _parents($stage, $relative);
            if ($relative eq 'boot/loader.conf') {
                sysopen(my $file, "$stage/$relative", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0444)
                  or _fail("Cannot create loader configuration: $!");
                print {$file} $loader_text or _fail("Cannot write loader configuration: $!");
                close($file) or _fail("Cannot close loader configuration: $!");
            } else {
                link("$shared/$relative", "$stage/$relative") or _fail("Cannot link $relative: $!");
            }
        }
    }, sub { _verify_tree($_[0], \%node_payload, $verified); });
    my $target = ".nodes/$node/$generation";
    if (!defined($old_target) || $old_target ne $target) {
        my $stage = tempdir('.link-stage.XXXXXXXX', DIR => $root, CLEANUP => 0);
        my $ok = eval {
            _stable_target($root, $node);
            symlink($target, "$stage/node") or _fail("Cannot stage node link: $!");
            rename("$stage/node", "$root/$node") or _fail("Cannot publish node link: $!");
            1;
        };
        my $error = $@;
        my $errors;
        remove_tree($stage, { error => \$errors });
        _fail("Cannot remove link stage $stage") if $errors && @$errors;
        die $error unless $ok;
    }
    close($lock) or _fail("Cannot close publication lock: $!");
    return { kernel => "xcat/freebsd/$node/boot/pxeboot", initrd => '', kcmdline => '', addkcmdline => '' };
}

1;
