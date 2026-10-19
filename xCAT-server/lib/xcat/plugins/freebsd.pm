package xCAT_plugin::freebsd;

use strict;
use warnings;
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use Getopt::Long ();
use xCAT::FreeBSDImage;
use xCAT::Table;
use xCAT::TableUtils;

sub handled_commands {
    return { copycd => 'freebsd', mkinstall => 'nodetype:os=(freebsd.*)' };
}

sub process_request {
    my ($request, $callback, $doreq) = @_;
    return copycd($request, $callback, $doreq)
      if $request->{command}->[0] eq 'copycd';
    return mkinstall($request, $callback)
      if $request->{command}->[0] eq 'mkinstall';
    return;
}

sub _read_media_row {
    my ($table, $key, $name, $create) = @_;
    my $tab = xCAT::Table->new($table, -create => (defined($create) ? $create : 1), -autocommit => 1)
      or die "Cannot open $table\n";
    my $rows = eval { $tab->getAllEntries(1) };
    my $error = $@;
    $tab->close();
    die $error if $error;
    die "Cannot read $table\n" unless ref($rows) eq 'ARRAY';
    my @found = grep { defined($_->{$key}) && $_->{$key} eq $name } @$rows;
    die "Duplicate $table entry $name\n" if @found > 1;
    return $found[0];
}

sub _matching_media_row {
    my ($row, $expected, $exact) = @_;
    return 0 unless $row;
    for my $key (keys %$expected) {
        return 0 unless defined($row->{$key}) && $row->{$key} eq $expected->{$key};
    }
    if ($exact) {
        return 0 if grep {
            !exists($expected->{$_}) && defined($row->{$_}) && length($row->{$_})
        } keys %$row;
    }
    return 1;
}

sub _validate_registered_media {
    my ($table, $name, $row, $expected, $repositories) = @_;
    die "The $table entry $name is disabled\n"
      if defined($row->{disable}) && length($row->{disable})
      && $row->{disable} !~ /\A(?:0|no)\z/i;
    my %identity = %$expected;
    delete $identity{profile};
    delete $identity{otherpkgdir} if $repositories;
    die "The $table entry $name does not match the imported media\n"
      unless _matching_media_row($row, \%identity);
    if ($repositories && $table eq 'freebsdimage') {
        my $error = xCAT::Utils->freebsd_image_definition_error({ %$row, imagetype => 'freebsd' });
        die "$name: $error\n" if defined($error) && length($error);
    }
    return;
}

sub _rollback_registered_media {
    my $created = shift;
    my $error = '';
    for my $added (reverse @$created) {
        my ($table, $key, $name, $expected) = @$added;
        my $cleaned = eval {
            my $row = _read_media_row($table, $key, $name);
            if ($row) {
                die "The entry changed during registration\n"
                  unless _matching_media_row($row, $expected, 1);
                my $tab = xCAT::Table->new($table, -create => 1, -autocommit => 1)
                  or die "Cannot open $table\n";
                my $deleted = eval { $tab->delEntries({ $key => $name }); 1 };
                my $delete_error = $@;
                $tab->close();
                die $delete_error unless $deleted;
                die "The entry still exists\n" if _read_media_row($table, $key, $name);
            }
            1;
        };
        $error .= "Cleanup failed for $table $name: $@" unless $cleaned;
    }
    return $error;
}

sub _register_media {
    my ($media, $noosimage) = @_;
    my $repositories = ($media->{imageversion} || '') eq '2';
    my $suffix = substr($media->{digest}, 0, 12);
    my $distro = "$media->{distname}-$media->{arch}-$suffix";
    my $image = "$media->{distname}-$media->{arch}-install-compute-$suffix";
    my @records = (
        ['osdistro', 'osdistroname', $distro, {
            osdistroname => $distro, basename => 'freebsd', majorversion => '15',
            minorversion => '1', arch => $media->{arch}, type => 'FreeBSD',
            dirpaths => $repositories ? dirname($media->{pkgdir}) : $media->{pkgdir},
        }],
    );
    unless ($noosimage) {
        my %settings = (imagename => $image, pkgdir => $media->{pkgdir});
        if ($repositories) {
            $settings{imageversion} = '2';
            $settings{otherpkgdir} = $media->{otherpkgdir} if defined($media->{otherpkgdir});
        }
        push @records,
          ['freebsdimage', 'imagename', $image, \%settings],
          ['osimage', 'imagename', $image, {
              imagename => $image, imagetype => 'freebsd', osname => 'FreeBSD',
              osvers => $media->{distname}, osarch => $media->{arch},
              provmethod => 'install', profile => 'compute', osdistroname => $distro,
          }];
    }
    my $lock;
    if ($repositories) {
        $lock = xCAT::FreeBSDRepoImport::registration_lock(dirname(dirname($media->{pkgdir})));
    } else {
        my $lockpath = dirname($media->{pkgdir}) . '/.mfsbsd-register.lock';
        sysopen($lock, $lockpath, O_CREAT | O_RDWR | O_NOFOLLOW, 0600)
          or die "Cannot open media registration lock: $!\n";
        flock($lock, LOCK_EX) or die "Cannot lock media registration: $!\n";
    }
    my @missing;
    for my $record (@records) {
        my ($table, $key, $name, $expected) = @$record;
        my $row = _read_media_row($table, $key, $name);
        unless ($row) {
            push @missing, $record;
            next;
        }
        _validate_registered_media($table, $name, $row, $expected, $repositories);
    }
    my @created;
    my $ok = eval {
        for my $pending (@missing) {
            my ($table, $key, $name, $expected) = @$pending;
            my $tab = xCAT::Table->new($table, -create => 1, -autocommit => 1)
              or die "Cannot open $table\n";
            push @created, $pending;
            my ($rc, $message);
            my $written = eval {
                ($rc, $message) = $tab->setAttribs({ $key => $name }, $expected);
                1;
            };
            my $error = $@;
            $tab->close();
            die $error unless $written;
            die "Cannot register $table $name: " . ($message || 'database write failed') . "\n"
              unless defined($rc) && $rc == 0;
            die "Cannot verify $table $name after registration\n"
              unless _matching_media_row(_read_media_row($table, $key, $name), $expected);
        }
        1;
    };
    unless ($ok) {
        my $error = $@ || "Media registration failed\n";
        $error .= _rollback_registered_media(\@created);
        die $error . "Imported media retained at $media->{pkgdir}\n";
    }
    return $noosimage ? undef : $image;
}

sub _copy_release {
    my ($mount, $inspect, $noosimage, $nonoverwrite, $callback) = @_;
    require xCAT::FreeBSDRepoImport;
    my $tree = xCAT::FreeBSDRepo::inspect_release_tree($mount);
    die "The source is not supported FreeBSD release media\n" unless $tree;
    if ($inspect) {
        my $roles = join(',', sort keys %{$tree->{repositories}});
        $callback->({ info => ["DISTNAME:$tree->{distname}\nARCH:$tree->{arch}\nTREE_DIGEST:$tree->{digest}\nREPOSITORIES:$roles\n"] });
        return;
    }
    my $policy = xCAT::FreeBSDRepoImport::load_import_policy(_site('freebsdimportpolicy', ''));
    my $options = xCAT::FreeBSDRepoImport::release_import_options($policy, $tree->{digest});
    my $publication = xCAT::FreeBSDRepoImport::import_release($mount,
        xCAT::TableUtils->getInstallDir(), %$options, nonoverwrite => $nonoverwrite);
    my $media = { distname => $tree->{distname}, arch => $tree->{arch},
        digest => $publication->{digest}, imageversion => '2', pkgdir => "$publication->{path}/base" };
    $media->{otherpkgdir} = "$publication->{path}/applications"
      if exists($publication->{repositories}{applications});
    my $image = _register_media($media, $noosimage);
    $callback->({ data => ["Imported FreeBSD repositories to $publication->{path}"] });
    $callback->({ data => ["Approved selected release tree $tree->{digest}; operator-recorded ISO SHA256 $policy->{releases}{$tree->{digest}}{iso_sha256}"] });
    $callback->({ data => ["Base repository: $media->{pkgdir}"] });
    $callback->({ data => ["Application repository: $media->{otherpkgdir}"] }) if defined($media->{otherpkgdir});
    $callback->({ data => ["Created or verified osimage $image"] }) if defined($image);
    return;
}

sub _copy_bundle {
    my ($mount, $inspect, $noosimage, $nonoverwrite, $callback) = @_;
    if ($inspect) {
        my $media = xCAT::FreeBSDImage::inspect_media($mount);
        $callback->({ info => ["DISTNAME:$media->{distname}\nARCH:$media->{arch}\nDIGEST:$media->{digest}\n"] });
        return;
    }
    my $media = xCAT::FreeBSDImage::import_media($mount,
        xCAT::TableUtils->getInstallDir(), nonoverwrite => $nonoverwrite);
    if ($media->{format} eq 'xcat-mfsbsd-2') {
        $callback->({ data => ["Imported FreeBSD boot media to $media->{bootdir}"] });
    } else {
        my $image = _register_media($media, $noosimage);
        $callback->({ data => ["Imported FreeBSD media to $media->{pkgdir}"] });
        $callback->({ data => ["Created or verified osimage $image"] }) if defined($image);
    }
    return;
}

sub copycd {
    my ($request, $callback, $doreq) = @_;
    my @args = @{ $request->{arg} || [] };
    my ($mount, $source, $inspect, $noosimage, $nonoverwrite, $name, $arch, $path, $specific);
    my @parse_errors;
    my $parser = Getopt::Long::Parser->new(config => [qw(no_auto_abbrev no_ignore_case)]);
    my $parsed;
    {
        local $SIG{__WARN__} = sub { push @parse_errors, @_ };
        $parsed = $parser->getoptionsfromarray(\@args,
            'm=s' => \$mount, 'f=s' => \$source, 'i' => \$inspect,
            'o' => \$noosimage, 'w' => \$nonoverwrite, 'n=s' => \$name,
            'a=s' => \$arch, 'p=s' => \$path, 's' => \$specific);
    }
    return unless defined($mount);
    my $legacy = -e "$mount/xcat/mfsbsd.json" || -l "$mount/xcat/mfsbsd.json";
    return unless $legacy || -e "$mount/bin/freebsd-version" || -l "$mount/bin/freebsd-version";
    %$request = ();
    my $ok = eval {
        die "Invalid FreeBSD copycd arguments: @parse_errors\n" unless $parsed && !@args;
        die "FreeBSD copycds does not support -n, -a, -p, or -s\n"
          if defined($name) || defined($arch) || defined($path) || $specific;
        if (!$legacy) {
            _copy_release($mount, $inspect, $noosimage, $nonoverwrite, $callback);
        } else {
            _copy_bundle($mount, $inspect, $noosimage, $nonoverwrite, $callback);
        }
        1;
    };
    $callback->({ error => [$@ || 'FreeBSD media import failed'], errorcode => [1] }) unless $ok;
    return;
}

sub _site {
    my ($key, $default) = @_;
    my ($value) = xCAT::TableUtils->get_site_attribute($key);
    return defined($value) && length($value) ? $value : $default;
}

sub _node_row {
    my ($table, $node, $create, @attributes) = @_;
    my $tab = xCAT::Table->new($table, -create => $create)
      or die "Cannot open $table\n";
    my $row = eval { $tab->getNodeAttribs($node, \@attributes) };
    my $error = $@;
    $tab->close();
    die $error if $error;
    die "Cannot read $table for $node\n" if defined($row) && ref($row) ne 'HASH';
    return $row || {};
}

sub _ipv4 {
    my ($name, $label) = @_;
    die "A single $label hostname or IPv4 address is required\n"
      unless defined($name) && !ref($name) && $name =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/;
    my $ip = xCAT::NetworkUtils->getipaddr($name, OnlyV4 => 1);
    die "Cannot resolve $label to IPv4\n" unless defined($ip) &&
      $ip =~ /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/ &&
      !grep { $_ > 255 || (length($_) > 1 && /^0/) } split(/\./, $ip);
    return $ip;
}

sub _local_server {
    my ($value, $master, $label) = @_;
    $value = $master if !defined($value) || !length($value) ||
      $value eq '<xcatmaster>' || $value eq '!myipfn!';
    my $ip = _ipv4($value, $label);
    die "Remote $label is not supported for FreeBSD installation\n"
      if xCAT::NetworkUtils->thishostisnot($ip);
    return $ip;
}

sub _provision_network {
    my ($node, $resources) = @_;
    die "FreeBSD installation requires netboot=xnba\n" unless ($resources->{netboot} || '') eq 'xnba';
    die "A node assigned to a service node requires one explicit xcatmaster\n"
      if length($resources->{servicenode} || '') && !length($resources->{xcatmaster} || '');
    my $owner = $resources->{xcatmaster} || _site('master', '');
    if (length($owner)) {
        $owner = _ipv4($owner, 'installation owner');
        die "FreeBSD installation must run on its selected xcatmaster\n"
          if xCAT::NetworkUtils->thishostisnot($owner);
    }
    my $master = $owner;
    unless (length($resources->{xcatmaster} || '')) {
        my ($rc, @facing) = xCAT::NetworkUtils->my_ip_facing($node);
        die "Cannot select one node-facing controller address\n" if $rc || @facing != 1;
        $master = _local_server($facing[0], $owner, 'controller');
    }
    my $ip = _ipv4($node, 'node');
    my $tab = xCAT::Table->new('networks', -create => 0) or die "Cannot open networks\n";
    my @networks = eval { $tab->getAllAttribs(qw(netname net mask gateway nameservers domain tftpserver mtu)) };
    my $error = $@;
    $tab->close();
    die $error if $error;
    my @matching;
    for my $network (@networks) {
        next unless ref($network) eq 'HASH' && defined($network->{net});
        next if $network->{net} =~ /:/;
        my $mask = $network->{mask};
        my $identity = $network->{netname} || $network->{net};
        die "Invalid IPv4 mask for network $identity\n"
          unless defined($mask) && !ref($mask) && $mask =~ /\A[0-9.]+\z/ &&
            ($mask eq '0.0.0.0' || xCAT::NetworkUtils::isIpv4addr($mask)) &&
            xCAT::NetworkUtils::formatNetmask(xCAT::NetworkUtils::formatNetmask($mask, 0, 1), 1, 0) eq $mask;
        push @matching, $network if xCAT::NetworkUtils::isInSameSubnet($network->{net}, $ip, $mask, 0);
    }
    die "FreeBSD installation requires exactly one matching networks entry\n" unless @matching == 1;
    my $network = $matching[0];
    my $tftpserver = _local_server($resources->{tftpserver} || $network->{tftpserver}, $master, 'TFTP server');
    my $httpserver = _local_server($resources->{nfsserver}, $master, 'HTTP server');
    my $gateway = $network->{gateway} || '';
    if ($gateway eq '<xcatmaster>') {
        $gateway = xCAT::NetworkUtils->ip_forwarding_enabled() ? $master : '';
    } elsif (length($gateway)) {
        $gateway = _ipv4($gateway, 'gateway');
    }
    die "The FreeBSD gateway must be in the node subnet\n" if length($gateway) &&
      !xCAT::NetworkUtils::isInSameSubnet($gateway, $ip, $network->{mask}, 0);
    for my $endpoint ($master, $httpserver, $tftpserver) {
        die "An off-subnet installation endpoint requires a gateway\n" unless length($gateway) ||
          xCAT::NetworkUtils::isInSameSubnet($endpoint, $ip, $network->{mask}, 0);
    }
    my $macrow = _node_row('mac', $node, 0, 'mac');
    my @eligible;
    for my $entry (split(/\|/, $macrow->{mac} || '', -1)) {
        my ($address, $alias, @extra) = split(/!/, $entry, -1);
        die "Invalid mac table entry\n" if @extra;
        next if defined($alias) && $alias ne $node;
        die "Invalid provisioning MAC\n" unless defined($address) &&
          $address =~ /\A(?:[0-9A-Fa-f]{12}|(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})\z/;
        push @eligible, lc(xCAT::Utils::parseMacTabEntry($address, $node));
    }
    my $selector = $resources->{installnic} || $resources->{primarynic} || 'mac';
    my $mac;
    if ($selector eq 'mac') {
        die "FreeBSD installation requires one unambiguous provisioning MAC\n" unless @eligible == 1;
        $mac = $eligible[0];
    } else {
        die "FreeBSD installnic must be mac or an explicit MAC address\n"
          unless $selector =~ /\A(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\z/;
        $mac = lc($selector);
        die "The installation MAC must belong to this node in the mac table\n" unless grep { $_ eq $mac } @eligible;
    }
    my $nameservers = $resources->{nameservers} || $network->{nameservers} || _site('nameservers', '');
    my @nameservers = map { _ipv4(($_ eq '<xcatmaster>' || $_ eq '!myipfn!') ? $master : $_, 'name server') }
      length($nameservers) ? split(/,/, $nameservers, -1) : ();
    my $domain = $network->{domain} || _site('domain', '');
    my $hostname = $node;
    $hostname .= ".$domain" if length($domain) && $node !~ /\./;
    die "FreeBSD installation requires HTTP distribution service\n" unless _site('httpmethod', 'http') eq 'http';
    my $httpport = _site('httpport', '80');
    die "Invalid HTTP port\n" unless $httpport =~ /\A[1-9][0-9]{0,4}\z/ && $httpport <= 65535;
    return ({ master => $master, port => _site('xcatiport', '3002'), mac => $mac, ipv4 => $ip,
        netmask => xCAT::NetworkUtils::formatNetmask($network->{mask}, 0, 0), gateway => $gateway,
        hostname => $hostname, nameservers => join(',', @nameservers) }, "http://$httpserver:$httpport/install", $network->{mtu} || 1500);
}

sub _install_image {
    my ($name, $installroot) = @_;
    my $image = _read_media_row('osimage', 'imagename', $name, 0)
      or die "An explicit FreeBSD osimage is required\n";
    my $error = xCAT::Utils->freebsd_image_error($image, 'xnba');
    die "Not a supported FreeBSD installation image\n" unless defined($error);
    die "$error\n" if length($error);
    my $settings = _read_media_row('freebsdimage', 'imagename', $name, 0)
      or die "Missing freebsdimage entry for $name\n";
    for my $row ($image, $settings) {
        die "The FreeBSD image is disabled\n" if length($row->{disable} || '') && $row->{disable} !~ /\A(?:0|no)\z/i;
    }
    my $merged = { %$image, %$settings };
    $error = xCAT::Utils->freebsd_image_definition_error($merged);
    die "Not a supported FreeBSD installation image\n" unless defined($error);
    die "$error\n" if length($error);
    my $pkgbase = ($merged->{imageversion} || '') eq '2';
    my $role = $pkgbase ? 'bootdir' : 'pkgdir';
    my $pkgdir = defined($settings->{$role}) ? abs_path($settings->{$role}) : undef;
    die "FreeBSD $role must be an imported directory below installdir\n" unless defined($pkgdir) &&
      -d $pkgdir && index($pkgdir, "$installroot/") == 0;
    my $media = xCAT::FreeBSDImage::inspect_media($pkgdir)
      or die "FreeBSD $role has no xCAT mfsBSD manifest\n";
    my $format = $pkgbase ? 'xcat-mfsbsd-2' : 'xcat-mfsbsd-1';
    die "FreeBSD $role requires an $format bundle\n" unless $media->{format} eq $format;
    my $parent = "$installroot/freebsd15.1/x86_64" . ($pkgbase ? '/boot' : '');
    die "FreeBSD $role does not match the imported media identity\n"
      unless $pkgdir eq "$parent/$media->{digest}";
    my $result = { settings => $settings, pkgdir => $pkgdir, media => $media };
    if ($pkgbase) {
        require xCAT::FreeBSDRepoImport;
        require xCAT::FreeBSDPackagePlan;
        my ($policy_path) = xCAT::TableUtils->get_site_attribute('freebsdimportpolicy');
        my $policy = xCAT::FreeBSDRepoImport::load_import_policy($policy_path);
        my $options = xCAT::FreeBSDRepoImport::package_plan_options($policy);
        my $plan = xCAT::FreeBSDPackagePlan::publish_image(installroot => $installroot,
            image => $merged, %$options);
        $result->{install} = { media => $media, package_plan_sha256 => $plan->{digest} };
        $result->{package_plan} = $plan->{path};
    }
    return $result;
}

sub mkinstall {
    my ($request, $callback) = @_;
    require xCAT::FreeBSDBoot;
    require xCAT::FreeBSDConfig;
    require xCAT::FreeBSDInstall;
    require xCAT::NetworkUtils;
    require xCAT::Utils;
    my $bootparams = ${ $request->{bootparams} };
    my %images;
    for my $node (@{ $request->{node} || [] }) {
        my $ok = eval {
            die "Invalid FreeBSD node name\n" unless $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,246}\z/;
            my $prior = $bootparams->{$node};
            my $commandline = $prior && @$prior ? $prior->[0]{addkcmdline} : undef;
            my $installroot = abs_path(xCAT::TableUtils->getInstallDir());
            die "An existing installation directory is required\n" unless defined($installroot) && -d $installroot;
            my $type = _node_row('nodetype', $node, 0, qw(os arch provmethod profile));
            die "FreeBSD 15.1 x86_64 installation is required\n"
              unless ($type->{os} || '') eq 'freebsd15.1' && ($type->{arch} || '') eq 'x86_64';
            die "A valid FreeBSD installation profile is required\n" unless
              ($type->{profile} || '') =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/;
            my $name = $type->{provmethod} || '';
            $images{$name} ||= _install_image($name, $installroot);
            my $image = $images{$name};
            my $resources = _node_row('noderes', $node, 0,
                qw(netboot xcatmaster servicenode tftpserver tftpdir nfsserver installnic primarynic nameservers));
            my $iscsi = _node_row('iscsi', $node, 1, qw(server target));
            die "An explicit iSCSI root conflicts with scripted FreeBSD installation\n"
              if length($iscsi->{server} || '') && length($iscsi->{target} || '');
            my ($network, $url, $bootstrap_mtu) = _provision_network($node, $resources);
            my $tftpdir = abs_path($resources->{tftpdir} || xCAT::TableUtils->getTftpDir());
            die "An existing TFTP directory is required\n" unless defined($tftpdir) && -d $tftpdir;
            if ($image->{install}) {
                $network->{install_url} = $url;
            } else {
                $network->{dist_url} = $url . substr($image->{pkgdir}, length($installroot)) . '/usr/freebsd-dist';
            }
            my $settings = xCAT::FreeBSDConfig::load_settings($node,
                $image->{settings}{template}, $image->{settings}{partitionfile},
                "$installroot/postscripts/configzfs-freebsd.awk");
            my $storage = delete $settings->{data_storage};
            die "Data pool provisioning requires pkgbase media with native postscripts\n"
              if defined($storage) && (!$image->{install} || !$image->{media}{postscript_contract}
                || ($image->{media}{install_contract} || '') !~ /\Axcat-freebsd-install-[56]\z/x);
            if (exists($settings->{bootstrap_interface})) {
                require xCAT::FreeBSDNetwork;
                my $interface = delete $settings->{bootstrap_interface};
                my $nics = _node_row('nics', $node, 0, qw(nictypes nicdevices nicextraparams nicsadapter));
                $settings->{bootstrap_network_base64} = xCAT::FreeBSDNetwork::encode(
                    $interface, $network->{mac}, $nics, "$installroot/postscripts/confignetwork-freebsd.awk", $bootstrap_mtu);
            }
            my $console = _node_row('nodehm', $node, 0, qw(serialport serialspeed serialflow));
            $settings = xCAT::FreeBSDConfig::boot_settings($settings, $commandline, $console, $image->{media});
            my @postscript_options;
            if ($image->{media}{postscript_contract}) {
                require xCAT::FreeBSDPostscript;
                my $prepared = xCAT::FreeBSDPostscript::prepare_boot($node, $image->{package_plan},
                    defined($storage) ? (data_storage => $storage) : ());
                @postscript_options = (postscript_preparations => $prepared);
            }
            my $fingerprint = $image->{install}
              ? xCAT::FreeBSDConfig::fingerprint_pkgbase($node, $settings, $network, $image->{install})
              : xCAT::FreeBSDConfig::fingerprint($node, $settings, $network, $image->{media});
            my $params;
            xCAT::FreeBSDInstall::prepare($node, $fingerprint, @postscript_options, publish => sub {
                my $generation = shift;
                my $content = $image->{install}
                  ? xCAT::FreeBSDConfig::render_pkgbase($node, $settings, $network, $image->{install}, $generation)
                  : xCAT::FreeBSDConfig::render($node, $settings, $network, $image->{media}, $generation);
                my $relative = xCAT::FreeBSDBoot::publish_config($node, generation => $generation,
                    installroot => $installroot, content => $content);
                $params = xCAT::FreeBSDBoot::publish($node, generation => $generation,
                    pkgdir => $image->{pkgdir}, media => $image->{media}, tftpdir => $tftpdir,
                    settings => $settings, network => $network,
                    config_url => "$url/$relative", config_sha256 => sha256_hex($content), mac => $network->{mac});
            });
            $bootparams->{$node} = [$params];
            1;
        };
        unless ($ok) {
            delete $bootparams->{$node};
            $callback->({ node => [{ name => [$node], error => [$@ || 'FreeBSD installation preparation failed'], errorcode => [1] }] });
        }
    }
    return;
}

1;
