package xCAT::FreeBSDConfig;

use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK);
use MIME::Base64 qw(encode_base64);
use Digest::SHA qw(sha256_hex);

sub _fail { die "FreeBSD configuration: $_[0]\n"; }

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
