package xCAT::FreeBSDConfig;

use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NOFOLLOW O_NONBLOCK);
use MIME::Base64 qw(encode_base64 decode_base64);
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
        kern.geom.label.gpt.enable
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

sub _decoded_boot_options {
    my $encoded = shift;
    _fail('Invalid encoded boot options') if !defined($encoded) || ref($encoded) ||
        length($encoded) > 21848 || $encoded !~ /\A[A-Za-z0-9+\/=]*\z/x;
    my $text = decode_base64($encoded);
    _fail('Noncanonical encoded boot options') unless encode_base64($text, '') eq $encoded;
    my %options;
    for my $line (split(/\n/x, $text)) {
        my ($key, $value) = $line =~ /\A([^=]+)="([^"]*)"\z/x;
        _fail('Invalid native boot assignment') if !defined($key) || exists($options{$key});
        $options{$key} = $value;
    }
    _fail('Noncanonical native boot options') unless render_boot_options(\%options) eq $text;
    return $text;
}

sub _boot_settings {
    my $settings = shift;
    for my $key (qw(bootstrap console_port console_speed console_flow)) {
        _fail("Missing or invalid $key") if !defined($settings->{$key}) || ref($settings->{$key});
    }
    _fail('Invalid bootstrap mode') unless $settings->{bootstrap} =~ /\A(?:dhcp|static)\z/x;
    _fail('Invalid console flow control') unless $settings->{console_flow} =~ /\A(?:none|hard)\z/x;
    if ($settings->{console_port} eq 'none') {
        _fail('Console speed or flow without a serial port') unless $settings->{console_speed} eq '0' &&
            $settings->{console_flow} eq 'none';
    } else {
        _fail('Invalid serial console port') unless $settings->{console_port} =~ /\A[0-3]\z/x;
        _fail('Invalid serial console speed') unless $settings->{console_speed} =~ /\A(?:9600|19200|38400|57600|115200)\z/x;
    }
    return map { _decoded_boot_options($settings->{$_}) }
        qw(install_boot_options_base64 target_boot_options_base64);
}

sub _serial_settings {
    my $console = shift;
    my %boot = (console_port => 'none', console_speed => '0', console_flow => 'none');
    for my $key (qw(serialport serialspeed serialflow)) {
        _fail("Invalid nodehm.$key") if defined($console->{$key}) && ref($console->{$key});
    }
    if (defined($console->{serialport}) && length($console->{serialport})) {
        $boot{console_port} = $console->{serialport};
        $boot{console_speed} = $console->{serialspeed};
        $boot{console_flow} = $console->{serialflow} if length($console->{serialflow} || '');
    } else {
        _fail('Console speed or flow without a serial port') if
            length($console->{serialspeed} || '') || length($console->{serialflow} || '');
    }
    return %boot;
}

sub boot_settings {
    my ($settings, $commandline, $console, $media) = @_;
    _fail('Invalid boot settings inputs') unless ref($settings) eq 'HASH' &&
        ref($console) eq 'HASH' && ref($media) eq 'HASH';
    my $options = parse_boot_options($commandline);
    my %boot = (bootstrap => (defined($settings->{bootstrap}) ? $settings->{bootstrap} : 'dhcp'),
        _serial_settings($console),
        install_boot_options_base64 => encode_base64(render_boot_options($options->{volatile}), ''),
        target_boot_options_base64 => encode_base64(render_boot_options($options->{persistent}), ''));
    _boot_settings(\%boot);
    my %result = %$settings;
    delete $result{bootstrap};
    if (exists($settings->{bootstrap_network_base64})) {
        require xCAT::FreeBSDNetwork;
        xCAT::FreeBSDNetwork::decode($settings->{bootstrap_network_base64});
        _fail('Early virtual networking requires xcat-freebsd-bootstrap-1 media') unless
            ($media->{network_contract} || '') eq 'xcat-freebsd-bootstrap-1';
    }
    if (($media->{install_contract} || '') =~ /\Axcat-freebsd-install-[3456]\z/x) {
        return { %result, %boot };
    }
    _fail('Boot settings require a runtime with xcat-freebsd-install-3') if
        $boot{bootstrap} ne 'dhcp' || $boot{console_port} ne 'none' ||
        length($boot{install_boot_options_base64}) || length($boot{target_boot_options_base64});
    return \%result;
}

sub render_loader_settings {
    my ($settings, $network) = @_;
    _fail('Invalid loader settings') unless ref($settings) eq 'HASH' && ref($network) eq 'HASH';
    return '' unless exists($settings->{bootstrap});
    my ($text) = _boot_settings($settings);
    $text .= "xcat_bootstrap=\"$settings->{bootstrap}\"\n";
    if (exists($settings->{bootstrap_network_base64})) {
        require xCAT::FreeBSDNetwork;
        $text .= xCAT::FreeBSDNetwork::loader($settings->{bootstrap_network_base64});
    }
    if ($settings->{bootstrap} eq 'static') {
        for my $key (qw(ipv4 netmask gateway)) {
            my $value = $network->{$key};
            $value = '' if $key eq 'gateway' && !defined($value);
            _fail("Invalid bootstrap $key") unless ($key eq 'gateway' && $value eq '') || _ipv4($value);
            $text .= "xcat_bootstrap_$key=\"$value\"\n";
        }
    }
    if ($settings->{console_port} ne 'none') {
        my @ports = qw(0x3f8 0x2f8 0x3e8 0x2e8);
        my $port = $ports[$settings->{console_port}];
        my $speed = $settings->{console_speed};
        $text .= "comconsole_port=\"$port\"\ncomconsole_speed=\"$speed\"\n"
          . "console=\"comconsole,\${console}\"\nboot_serial=\"YES\"\nboot_multicons=\"YES\"\n"
          . "hw.uart.console=\"io:$port,br:$speed\"\n"
          . "hint.uart.$settings->{console_port}.at=\"acpi\"\n"
          . "hint.uart.$settings->{console_port}.port=\"$port\"\n";
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
    return _policy_values($text, @keys);
}

sub _policy_values {
    my ($text, @keys) = @_;
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

sub _disk_member {
    my $member = shift;
    my $device = qr/(?:ada|da|nda|nvd|vtbd)(?:0|[1-9][0-9]{0,4})/x;
    return $member =~ /\A($device)@([A-Za-z0-9_.:+-]{1,128})\z/x;
}

sub _zfs_storage {
    my $settings = shift;
    return 0 unless grep { exists($settings->{$_}) } qw(zfs_topology zfs_vdevs swap_mode);
    _fail('Scalar and multi-disk policies cannot be combined') if
        exists($settings->{target_disk}) || exists($settings->{target_disk_ident});
    for my $key (qw(filesystem swap_size zfs_topology zfs_vdevs swap_mode)) {
        _fail("Missing or invalid storage setting $key") unless
            defined($settings->{$key}) && !ref($settings->{$key});
    }
    _fail('Multi-disk storage requires ZFS') unless $settings->{filesystem} eq 'zfs';
    _fail('Redundant storage requires swap_size=0 and swap_mode=none') unless
        $settings->{swap_size} eq '0' && $settings->{swap_mode} eq 'none';
    my %minimum = (stripe => 1, mirror => 2, raid10 => 4, raidz1 => 3, raidz2 => 4, raidz3 => 5);
    my $topology = $settings->{zfs_topology};
    _fail('Unsupported ZFS topology') unless exists($minimum{$topology});
    _fail('ZFS membership exceeds its size limit') if length($settings->{zfs_vdevs}) > 4096;
    my @groups = split(/;/x, $settings->{zfs_vdevs}, -1);
    my (%devices, %serials, @sizes);
    my $count = 0;
    for my $group (@groups) {
        my @members = split(/,/x, $group, -1);
        _fail('Empty ZFS member group') unless length($group) && @members;
        push @sizes, scalar(@members);
        for my $member (@members) {
            my ($device, $serial) = _disk_member($member);
            _fail('Invalid ZFS device and serial pair') unless defined($device);
            _fail('Duplicate ZFS device or serial') if $devices{$device}++ || $serials{$serial}++;
            _fail('ZFS policy exceeds 16 members') if ++$count > 16;
        }
    }
    _fail('Insufficient ZFS members') if $count < $minimum{$topology};
    _fail('The OS stripe policy requires one disk') if $topology eq 'stripe' && $count != 1;
    if ($topology eq 'raid10') {
        _fail('Striped mirrors require at least two pairs') if @groups < 2 || grep { $_ != 2 } @sizes;
    } else {
        _fail('ZFS topology requires one member group') unless @groups == 1;
    }
    return 1;
}

sub _zfs_disk_policy {
    my $settings = shift;
    my $extended = ($settings->{zfs_topology} || '') eq 'stripe' ||
        grep { exists($settings->{$_}) } qw(zfs_compression zfs_ashift disk_action preserve_disks
        zfs_log_vdevs zfs_cache_vdevs zfs_special_vdevs zfs_special_small_blocks);
    return 0 unless $extended;
    _fail('Disk properties require an explicit ZFS member policy') unless _zfs_storage($settings);
    $settings->{zfs_compression} //= 'lz4';
    $settings->{zfs_ashift} //= '12';
    $settings->{disk_action} //= 'empty';
    $settings->{preserve_disks} //= '-';
    _fail('Unsupported OS compression') unless $settings->{zfs_compression} =~ /\A(?:off|lz4|gzip(?:-[1-9])?|zstd(?:-(?:[1-9]|1[0-9]))?)\z/x;
    $settings->{zfs_compression} = 'gzip' if $settings->{zfs_compression} eq 'gzip-6';
    _fail('Invalid ZFS ashift') unless $settings->{zfs_ashift} =~ /\A(?:9|1[0-6])\z/x;
    _fail('Disk action must be empty or erase') unless $settings->{disk_action} =~ /\A(?:empty|erase)\z/x;
    _fail('Preserved disk policy exceeds its size limit') if length($settings->{preserve_disks}) > 32768;
    my (%devices, %serials);
    for my $member (split(/[,;]/x, $settings->{zfs_vdevs})) {
        my ($device, $serial) = split(/@/x, $member);
        $devices{$device} = $serials{$serial} = 1;
    }
    _zfs_auxiliary($settings, \%devices, \%serials);
    if ($settings->{preserve_disks} ne '-') {
        my @members = split(/,/x, $settings->{preserve_disks}, -1);
        _fail('A preserved disk identity or dash is required') unless @members;
        _fail('Too many preserved disks') if @members > 128;
        for my $preserved_member (@members) {
            my ($device, $serial) = _disk_member($preserved_member);
            _fail('Invalid preserved disk identity') unless defined($device);
            _fail('OS and preserved disk identities overlap or repeat') if $devices{$device}++ || $serials{$serial}++;
        }
    }
    return 1;
}

sub _zfs_auxiliary {
    my ($settings, $devices, $serials) = @_;
    return unless grep { exists($settings->{$_}) }
        qw(zfs_log_vdevs zfs_cache_vdevs zfs_special_vdevs zfs_special_small_blocks);
    my $topology = $settings->{zfs_topology};
    my $special_width = $topology eq 'mirror' ? scalar(split(/,/x, $settings->{zfs_vdevs})) :
        $topology eq 'raidz2' ? 3 : $topology eq 'raidz3' ? 4 : 2;
    for my $role (qw(special log cache)) {
        my $key = "zfs_${role}_vdevs";
        $settings->{$key} //= '-';
        my $value = $settings->{$key};
        _fail("Invalid $role device policy") if ref($value) || !length($value) || length($value) > 16384;
        next if $value eq '-';
        _fail('An OS stripe cannot use mirrored special devices') if $role eq 'special' && $topology eq 'stripe';
        my @groups = split(/;/x, $value, -1);
        _fail('Cache devices require one flat list') if $role eq 'cache' && @groups != 1;
        for my $group (@groups) {
            my @members = split(/,/x, $group, -1);
            _fail("Empty $role device group") unless length($group) && @members;
            _fail('Special devices must match the OS replication level') if
                $role eq 'special' && @members != $special_width;
            for my $member (@members) {
                my ($device, $serial) = _disk_member($member);
                _fail("Invalid $role device identity") unless defined($device);
                _fail('OS device identities overlap or repeat') if $devices->{$device}++ || $serials->{$serial}++;
                _fail('OS policy exceeds 128 disks') if keys(%$devices) > 128;
            }
        }
    }
    $settings->{zfs_special_small_blocks} //= '0';
    my $size = $settings->{zfs_special_small_blocks};
    _fail('Invalid OS special_small_blocks size') if ref($size) || $size !~ /\A(?:0|[1-9][0-9]{0,7})\z/x ||
        $size > 16777216 || ($size && ($size < 512 || ($size & ($size - 1))));
    _fail('Small blocks require a redundant special vdev') if $size && $settings->{zfs_special_vdevs} eq '-';
    return;
}

sub load_settings {
    my ($node, $template, $partitionfile, $planner) = @_;
    my $settings = _policy($template, $node, qw(authorized_keys_file bootstrap bootstrap_interface));
    my ($text) = _read_file($partitionfile, $node, 65536);
    require xCAT::FreeBSDStorage;
    my ($os, $pools, $datasets) = xCAT::FreeBSDStorage::sections($text);
    my $disk = _policy_values($os,
        qw(target_disk target_disk_ident filesystem swap_size zfs_topology zfs_vdevs swap_mode
        zfs_compression zfs_ashift disk_action preserve_disks
        zfs_log_vdevs zfs_cache_vdevs zfs_special_vdevs zfs_special_small_blocks));
    $disk->{swap_size} = '0' unless defined($disk->{swap_size});
    _zfs_storage($disk);
    _zfs_disk_policy($disk);
    my $storage;
    if (keys %$pools) {
        _read_file($planner, $node, 262144);
        $storage = xCAT::FreeBSDStorage::compile($node, $disk, $pools, $planner);
        _zfs_disk_policy($disk);
    }
    if (keys %$datasets) {
        _fail('A shared dataset planner is required') unless defined($planner) && !ref($planner);
        my $dataset_planner = $planner;
        $dataset_planner =~ s{[^/]+\z}{configzfs-datasets.awk}x;
        _read_file($dataset_planner, $node, 262144);
        xCAT::FreeBSDStorage::datasets($disk, $storage, $datasets, $dataset_planner);
    }
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
    return { %$disk, (defined($storage) ? (data_storage => $storage) : ()),
        (map { exists($settings->{$_}) ? ($_ => $settings->{$_}) : () } qw(bootstrap bootstrap_interface)),
        swap_size => (defined($disk->{swap_size}) ? $disk->{swap_size} : '0'),
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
    return _render_config(\%config, \@order, [qw(generation base_sha256 kernel_sha256)],
        'dist_url', 'distribution');
}

sub render_pkgbase {
    my ($node, $settings, $network, $install, $generation) = @_;
    _fail('Pkgbase rendering requires five arguments') unless @_ == 5;
    _node($node);
    _fail('Invalid pkgbase install inputs') unless ref($install) eq 'HASH' && keys(%$install) == 2
      && exists($install->{media}) && exists($install->{package_plan_sha256});
    my $media = $install->{media};
    _fail('Invalid settings or media') unless ref($settings) eq 'HASH' && ref($network) eq 'HASH' &&
        ref($media) eq 'HASH' && ref($media->{files}) eq 'HASH';
    _fail('Unsupported pkgbase boot media') unless ($media->{format} || '') eq 'xcat-mfsbsd-2' &&
        ($media->{release} || '') eq '15.1-RELEASE' && ($media->{arch} || '') eq 'x86_64';
    my %config = (%$settings, %$network, format => 'xcat-freebsd-install-2', release => $media->{release},
        node => $node, generation => $generation, package_plan_sha256 => $install->{package_plan_sha256},
        boot_media_sha256 => $media->{digest}, runtime_sha256 => $media->{files}{'xcat/runtime.tsv'});
    my $multi_disk = _zfs_storage(\%config);
    my $disk_policy = _zfs_disk_policy(\%config);
    my $install_contract = $media->{install_contract} || '';
    my @storage = $multi_disk ? qw(zfs_topology zfs_vdevs swap_mode) : qw(target_disk target_disk_ident);
    my @order = (qw(format release node generation master port mac ipv4 netmask gateway hostname),
        @storage, qw(filesystem swap_size install_url package_plan_sha256
        boot_media_sha256 runtime_sha256 authorized_key_base64 nameservers));
    if ($multi_disk) {
        _fail('Multi-disk storage requires a runtime with xcat-freebsd-install-4') unless
            $install_contract =~ /\Axcat-freebsd-install-[456]\z/x;
    }
    if ($install_contract =~ /\Axcat-freebsd-install-[3456]\z/x) {
        $config{format} = $multi_disk ? 'xcat-freebsd-install-4' : 'xcat-freebsd-install-3';
        push @order, qw(bootstrap console_port console_speed console_flow
            install_boot_options_base64 target_boot_options_base64);
        _boot_settings(\%config);
    }
    if ($disk_policy) {
        _fail('Disk properties and reinstall require xcat-freebsd-install-5') unless
            $install_contract =~ /\Axcat-freebsd-install-[56]\z/x;
        $config{format} = 'xcat-freebsd-install-5';
        push @order, qw(zfs_compression zfs_ashift disk_action preserve_disks);
    }
    if (exists($config{zfs_log_vdevs})) {
        _fail('OS auxiliary devices require xcat-freebsd-install-6') unless
            $install_contract eq 'xcat-freebsd-install-6';
        $config{format} = 'xcat-freebsd-install-6';
        push @order, qw(zfs_log_vdevs zfs_cache_vdevs zfs_special_vdevs zfs_special_small_blocks);
    }
    if (exists($config{bootstrap_network_base64})) {
        require xCAT::FreeBSDNetwork;
        _fail('Early virtual networking requires xcat-freebsd-bootstrap-1 media') unless
            ($media->{network_contract} || '') eq 'xcat-freebsd-bootstrap-1';
        my $bootstrap = xCAT::FreeBSDNetwork::decode($config{bootstrap_network_base64});
        _fail('Bootstrap network belongs to another provisioning MAC') unless $bootstrap->{mac} eq $config{mac};
        push @order, 'bootstrap_network_base64';
    }
    if (exists($config{zfs_datasets_base64})) {
        _fail('OS datasets require xcat-freebsd-datasets-1 media and explicit ZFS disks') unless
            $multi_disk && ($media->{dataset_contract} || '') eq 'xcat-freebsd-datasets-1';
        _fail('Invalid encoded OS datasets') unless $config{zfs_datasets_base64} =~ /\A[A-Za-z0-9+\/=]+\z/x
            && length($config{zfs_datasets_base64}) <= 16384;
        push @order, 'zfs_datasets_base64';
    }
    return _render_config(\%config, \@order,
        [qw(generation package_plan_sha256 boot_media_sha256 runtime_sha256)], 'install_url', 'installation');
}

sub _render_config {
    my ($values, $order, $digests, $url_key, $url_description) = @_;
    my %config = %$values;
    my @order = @$order;
    my %allowed = map { $_ => 1 } @order;
    _fail('Unsupported generated setting') if grep { !$allowed{$_} } keys %config;
    for my $key (qw(gateway nameservers)) { $config{$key} = '' unless defined($config{$key}); }
    for my $key (@order) {
        _fail("Missing or invalid $key") unless defined($config{$key}) && !ref($config{$key}) &&
            $config{$key} !~ /[^\x20-\x7e]/;
    }
    for my $key (@$digests) {
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
    if ($config{format} =~ /\Axcat-freebsd-install-[456]\z/x) {
        _fail('Missing multi-disk policy') unless _zfs_storage(\%config);
    } else {
        _fail('Invalid target disk') unless $config{target_disk} =~ /\A(?:ada|da|nda|nvd|vtbd)[0-9]+\z/;
        _fail('A disk serial is required') unless $config{target_disk_ident} =~ /\A[A-Za-z0-9_.:+-]+\z/;
    }
    _fail('Unsupported filesystem') unless $config{filesystem} =~ /\A(?:zfs|ufs)\z/;
    _fail('Invalid swap size') unless $config{swap_size} =~ /\A(?:0|[1-9][0-9]*[mMgG])\z/ && length($config{swap_size}) <= 6;
    _fail("Invalid $url_description URL") unless $config{$url_key} =~ m{\Ahttps?://[A-Za-z0-9.-]+(?::[0-9]+)?/[A-Za-z0-9_.+/\-]+\z} &&
        $config{$url_key} !~ m{/\.\.?(?:/|\z)};
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

sub fingerprint_pkgbase {
    my ($node, $settings, $network, $install) = @_;
    _fail('Pkgbase fingerprinting requires four arguments') unless @_ == 4;
    return sha256_hex(render_pkgbase($node, $settings, $network, $install, '0' x 32));
}

1;
