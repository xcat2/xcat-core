package xCAT::FreeBSDConfig;

use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK);
use MIME::Base64 qw(encode_base64);
use Digest::SHA qw(sha256_hex);

sub _fail { die "FreeBSD configuration: $_[0]\n"; }

sub _boot_option {
    my ($key, $value) = @_;
    _fail('Invalid boot option name') if !defined($key) || ref($key);
    _fail('Invalid boot option name') unless $key =~ /\A[A-Za-z][A-Za-z0-9_.-]{0,127}\z/x;
    _fail("Invalid boot option value for $key") if !defined($value) || ref($value);
    _fail("Invalid boot option value for $key") if length($value) > 128 ||
        $value !~ m{\A[A-Za-z0-9_.,:+/@%=\-]*\z}x;
    my %reserved = map { $_ => 1 } qw(
        exec loader_conf_files loader_conf_dirs local_loader_conf_files product_vars
        nextboot_conf nextboot_enable kernel kernels kernels_autodetect kernel_options
        kernel_path kernelname xen_kernel bootfile module_path module_blacklist lua_path loader_path efi-version
        currdev loaddev root rootdev rootpath root_path rootflags rootfstype root_disk_unit num_ide_disks
        init initrd rdinit console boot_serial boot_multicons boot_multiple boot_mute
        boot_mutemsgs boot_askname boot_cdrom boot_dfltroot autoboot_delay beastie_disable
        hostname hostid hostuuid ip bootif netmask gateway nameserver nameservers
        kern.hostname kern.hostid kern.hostuuid kern.domainname kern.bootfile kern.maxphys
    );
    my $name = lc($key);
    _fail("Reserved boot option $key") if $reserved{$name} ||
        $name =~ /\A(?:xcat[_.]|mdroot[_.]|kernel_)/x ||
        $name =~ /\Amfs(?:bsd|root)?(?:[_.]|\z)/x ||
        $name =~ /\A(?:boot\.|dhcp\.|init_|hostuuid_|bootenv|zfs_be_)/x ||
        $name =~ /\A(?:vfs\.root[._]|vfs\.zfs\.(?:boot|root))/x ||
        $name =~ /\A(?:comconsole_|hw\.uart\.console(?:\.|\z))/x ||
        $name =~ /\Ahint\.(?:uart|sio)\./x ||
        $name =~ /_(?:before|after|error|name|type)\z/x;
    if ($key =~ /_load\z/x || $key =~ /\Aboot_(?:ddb|gdb|pause|single|verbose|safe)\z/x) {
        _fail("Expected YES or NO for $key") unless $value =~ /\A(?:YES|NO)\z/ix;
        return uc($value);
    }
    return $value;
}

sub parse_boot_options {
    my $text = shift;
    $text = '' unless defined($text);
    _fail('Invalid boot options') if ref($text) || length($text) > 16384 || $text =~ /[^\x20-\x7e]/x;
    my %options = (volatile => {}, persistent => {});
    return \%options unless $text =~ /[^ ]/x;
    _fail('Expected a native boot option key=value') if grep {
        length($_) && $_ !~ /\A(?:R::)?[^= ]+=/x;
    } split(/[ ]+/x, $text);
    require xCAT::Utils;
    my $phases = xCAT::Utils->splitkcmdline($text);
    for my $phase (qw(volatile persistent)) {
        my $count = 0;
        my $size = 0;
        for my $token (split(/[ ]+/x, $phases->{$phase} || '')) {
            next unless length($token);
            _fail('Too many boot options') if ++$count > 128;
            my ($key, $value) = $token =~ /\A([^=]+)=(.*)\z/x;
            _fail('Expected a native boot option key=value') unless defined($key);
            _fail("Duplicate $phase boot option $key") if exists($options{$phase}{$key});
            $value = _boot_option($key, $value);
            $size += length($key) + length($value) + 4;
            _fail('Rendered boot options are too large') if $size > 16384;
            $options{$phase}{$key} = $value;
        }
    }
    return \%options;
}

sub render_boot_options {
    my $options = shift;
    _fail('Invalid boot options map') unless ref($options) eq 'HASH';
    _fail('Too many boot options') if keys(%$options) > 128;
    my $text = '';
    for my $key (sort keys %$options) {
        my $value = _boot_option($key, $options->{$key});
        $text .= "$key=\"$value\"\n";
        _fail('Rendered boot options are too large') if length($text) > 16384;
    }
    return $text;
}

sub _node {
    my $node = shift;
    _fail('Invalid node name') unless defined($node) && !ref($node) &&
        $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,246}\z/;
}

sub _read_file {
    my ($path, $node, $limit) = @_;
    _node($node);
    _fail('An absolute configuration path is required') unless defined($path) && !ref($path) &&
        $path =~ m{\A/[^\x00\r\n]+\z};
    $path =~ s/#NODE#/$node/g;
    my @parts = split(m{/}, substr($path, 1), -1);
    _fail('Configuration path traversal is not permitted') if grep { $_ eq '' || $_ eq '.' || $_ eq '..' } @parts;
    pop @parts;
    my $parent = '/';
    for my $part ('', @parts) {
        $parent .= "$part/" if length($part);
        my $directory = $parent eq '/' ? '/' : substr($parent, 0, -1);
        my @stat = lstat($directory);
        _fail("Unsafe configuration parent: $directory") unless @stat && -d _ && !-l _ &&
            ($stat[4] == 0 || $stat[4] == $>) && (!($stat[2] & 0022) || ($stat[2] & 01000));
    }
    sysopen(my $handle, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or _fail("Cannot open $path: $!");
    my @stat = stat($handle);
    _fail('Configuration must be a bounded regular file') unless -f $handle && $stat[7] <= $limit;
    _fail('Unsafe configuration file permissions') unless ($stat[4] == 0 || $stat[4] == $>) && !($stat[2] & 0022);
    my $text = '';
    while (1) {
        my $count = sysread($handle, my $chunk, 4096);
        _fail("Cannot read configuration: $!") unless defined($count);
        last unless $count;
        $text .= $chunk;
        _fail('Configuration file is too large') if length($text) > $limit;
    }
    close($handle) or _fail("Cannot close configuration: $!");
    return ($text, $path);
}

sub _policy {
    my ($path, $node, @keys) = @_;
    my ($text) = _read_file($path, $node, 65536);
    _fail('Configuration contains control characters') if $text =~ /[^\x09\x0a\x20-\x7e]/;
    my %allowed = map { $_ => 1 } @keys;
    my %values;
    for my $line (split(/\n/, $text)) {
        next if $line =~ /\A\s*(?:#.*)?\z/;
        _fail('Expected a key=value setting') unless $line =~ /\A([a-z_]+)=(.*)\z/;
        my ($key, $value) = ($1, $2);
        _fail("Unsupported setting $key") unless $allowed{$key};
        _fail("Duplicate setting $key") if exists($values{$key});
        $values{$key} = $value;
    }
    return \%values;
}

sub load_settings {
    my ($node, $template, $partitionfile) = @_;
    my $settings = _policy($template, $node, 'authorized_keys_file');
    my $disk = _policy($partitionfile, $node, qw(target_disk target_disk_ident filesystem swap_size));
    my ($keys, $keyfile) = _read_file($settings->{authorized_keys_file}, $node, 16384);
    my @keys = grep { /\S/ } split(/\n/, $keys);
    _fail('A plain SSH public key is required') unless @keys && !grep {
        !/\A(?:ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)) [A-Za-z0-9+\/=]+(?: [\x20-\x7e]*)?\z/;
    } @keys;
    {
        local $SIG{CHLD} = 'DEFAULT';
        open(my $check, '-|', 'ssh-keygen', '-l', '-f', $keyfile) or _fail("Cannot verify SSH keys: $!");
        while (<$check>) { }
        close($check) or _fail('SSH public key verification failed');
    }
    return { %$disk, swap_size => (defined($disk->{swap_size}) ? $disk->{swap_size} : '0'),
        authorized_key_base64 => encode_base64(join("\n", @keys) . "\n", '') };
}

sub _ipv4 {
    my $value = shift;
    return 0 unless defined($value) && !ref($value) && $value =~ /\A(?:[0-9]+\.){3}[0-9]+\z/;
    return !grep { $_ > 255 || length($_) > 3 || (length($_) > 1 && /^0/) } split(/\./, $value);
}

sub render {
    my ($node, $settings, $network, $media, $generation) = @_;
    _node($node);
    _fail('Invalid settings or media') unless ref($settings) eq 'HASH' && ref($network) eq 'HASH' &&
        ref($media) eq 'HASH' && ref($media->{files}) eq 'HASH';
    _fail('Unsupported media') unless ($media->{release} || '') eq '15.1-RELEASE' &&
        ($media->{arch} || '') eq 'x86_64';
    my %config = (%$settings, %$network, format => 'xcat-freebsd-install-1', release => $media->{release},
        node => $node, generation => $generation,
        base_sha256 => $media->{files}{'usr/freebsd-dist/base.txz'},
        kernel_sha256 => $media->{files}{'usr/freebsd-dist/kernel.txz'});
    my @order = qw(format release node generation master port mac ipv4 netmask gateway hostname
        target_disk target_disk_ident filesystem swap_size dist_url base_sha256 kernel_sha256
        authorized_key_base64 nameservers);
    my %allowed = map { $_ => 1 } @order;
    _fail('Unsupported generated setting') if grep { !$allowed{$_} } keys %config;
    for my $key (qw(gateway nameservers)) { $config{$key} = '' unless defined($config{$key}); }
    for my $key (@order) {
        _fail("Missing or invalid $key") unless defined($config{$key}) && !ref($config{$key}) &&
            $config{$key} !~ /[^\x20-\x7e]/;
    }
    for my $key (qw(generation base_sha256 kernel_sha256)) {
        my $length = $key eq 'generation' ? 32 : 64;
        _fail("Invalid $key") unless $config{$key} =~ /\A[0-9a-f]{$length}\z/;
    }
    for my $key (qw(master ipv4 netmask)) { _fail("Invalid $key") unless _ipv4($config{$key}); }
    _fail('Invalid gateway') if $config{gateway} ne '' && !_ipv4($config{gateway});
    my $inverse = 0xffffffff ^ unpack('N', pack('C4', split(/\./, $config{netmask})));
    _fail('Noncontiguous netmask') if $inverse & ($inverse + 1);
    _fail('Invalid status port') unless $config{port} =~ /\A[1-9][0-9]{0,4}\z/ && $config{port} <= 65535;
    _fail('Invalid provisioning MAC') unless $config{mac} =~ /\A(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\z/;
    _node($config{hostname});
    _fail('Invalid target disk') unless $config{target_disk} =~ /\A(?:ada|da|nda|nvd|vtbd)[0-9]+\z/;
    _fail('A disk serial is required') unless $config{target_disk_ident} =~ /\A[A-Za-z0-9_.:+-]+\z/;
    _fail('Unsupported filesystem') unless $config{filesystem} =~ /\A(?:zfs|ufs)\z/;
    _fail('Invalid swap size') unless $config{swap_size} =~ /\A(?:0|[1-9][0-9]*[mMgG])\z/ && length($config{swap_size}) <= 6;
    _fail('Invalid distribution URL') unless $config{dist_url} =~ m{\Ahttps?://[A-Za-z0-9.-]+(?::[0-9]+)?/[A-Za-z0-9_.+/\-]+\z} &&
        $config{dist_url} !~ m{/\.\.?(?:/|\z)};
    _fail('Invalid encoded SSH keys') unless $config{authorized_key_base64} =~ /\A[A-Za-z0-9+\/=]+\z/;
    if (length($config{nameservers})) {
        _fail('Invalid name server') if grep { !_ipv4($_) } split(/,/, $config{nameservers}, -1);
    }
    my $text = join('', map { "$_=$config{$_}\n" } @order);
    _fail('Generated configuration is too large') if length($text) > 32768;
    return $text;
}

sub fingerprint {
    my ($node, $settings, $network, $media) = @_;
    _fail('Invalid media digest') unless ref($media) eq 'HASH' && defined($media->{digest}) &&
        !ref($media->{digest}) && $media->{digest} =~ /\A[0-9a-f]{64}\z/;
    return sha256_hex($media->{digest} . "\n" . render($node, $settings, $network, $media, '0' x 32));
}

1;
