package xCAT_plugin::mknb;
use strict;
use Digest::SHA ();
use File::Temp qw(tempdir);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NodeRange;
use File::Path;
use File::Copy;

my $GENESIS_EXPORT_MANIFEST = 'xcat-genesis.manifest';
my %GENESIS_ARCHITECTURES = map { $_ => 1 }
  qw(x86 x86_64 ppc64 ppc64le armv7hf aarch64 riscv64);

sub handled_commands {
    return {
        mknb => 'mknb',
    };
}

sub _select_network_addresses {
    my ($network_addresses, $preferred_addresses) = @_;
    my %preferred = map { $_ => 1 } grep { defined($_) } @{$preferred_addresses};
    my %legacy;
    my %selected;

    foreach my $network (keys %{$network_addresses}) {
        my $addresses = $network_addresses->{$network};
        next unless @{$addresses};
        $legacy{$network}   = $addresses->[-1];
        $selected{$network} = $addresses->[0];
        foreach my $address (@{$addresses}) {
            if (defined($address) && $preferred{$address}) {
                $selected{$network} = $address;
                last;
            }
        }
    }

    return (\%legacy, \%selected);
}

sub _select_genesis_source {
    my ($xcatroot, $requested_arch) = @_;
    return unless defined($requested_arch);

    my $arch = $requested_arch eq 'ppc64el' ? 'ppc64le' : $requested_arch;
    return unless $GENESIS_ARCHITECTURES{$arch};

    my $netboot = "$xcatroot/share/xcat/netboot";
    my $openembedded = "$netboot/genesis-openembedded/$arch";
    return ($openembedded, $arch, 'openembedded')
      if -d $openembedded;

    my $legacy_arch = $arch eq 'ppc64le' ? 'ppc64' : $arch;
    my $legacy = "$netboot/genesis/$legacy_arch";
    return ($legacy, $legacy_arch, 'legacy') if -d $legacy;

    my $classic = "$netboot/$legacy_arch";
    return ($classic, $legacy_arch, 'classic') if -d $classic;

    return;
}

sub _genesis_export_manifest_present {
    my ($directory) = @_;
    my $manifest = "$directory/$GENESIS_EXPORT_MANIFEST";
    return -e $manifest || -l $manifest;
}

sub _prebuilt_genesis_requested {
    my ($directory) = @_;
    foreach my $name (
        $GENESIS_EXPORT_MANIFEST,
        'kernel',
        'initramfs.cpio.gz',
        'SHA256SUMS'
      )
    {
        my $path = "$directory/$name";
        return 0 unless -e $path || -l $path;
    }
    return 1;
}

sub _validate_prebuilt_genesis_manifest {
    my ($directory, $arch) = @_;
    my $manifest = "$directory/$GENESIS_EXPORT_MANIFEST";
    return "Missing Genesis export manifest: $manifest"
      unless -f $manifest && !-l $manifest;

    open(my $manifest_fh, '<:raw', $manifest)
      or return "Unable to read Genesis export manifest: $manifest";

    my %expected = (
        format       => 'xcat-genesis',
        version      => '1',
        architecture => $arch,
    );
    my %values;
    while (my $line = <$manifest_fh>) {
        chomp($line);
        unless ($line =~ /^([a-z][a-z0-9_-]*)=([A-Za-z0-9][A-Za-z0-9._+-]*)$/) {
            close($manifest_fh);
            return "Invalid Genesis export manifest entry: $line";
        }
        my ($name, $value) = ($1, $2);
        unless (exists($expected{$name})) {
            close($manifest_fh);
            return "Unknown Genesis export manifest entry: $name";
        }
        if (exists($values{$name})) {
            close($manifest_fh);
            return "Duplicate Genesis export manifest entry: $name";
        }
        $values{$name} = $value;
    }
    close($manifest_fh);

    foreach my $name (qw(format version architecture)) {
        return "Missing Genesis export manifest entry: $name"
          unless exists($values{$name});
        return "Unsupported Genesis export $name: $values{$name}"
          unless $values{$name} eq $expected{$name};
    }

    return;
}

sub _read_prebuilt_genesis_checksums {
    my ($directory) = @_;
    my $checksum_file = "$directory/SHA256SUMS";
    return (undef, "Missing Genesis checksum file: $checksum_file")
      unless -f $checksum_file && !-l $checksum_file;

    open(my $checksum_fh, '<:raw', $checksum_file)
      or return (undef, "Unable to read Genesis checksum file: $checksum_file");

    my %expected;
    while (my $line = <$checksum_fh>) {
        chomp($line);
        unless ($line =~ /^([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)$/) {
            close($checksum_fh);
            return (undef, "Invalid Genesis checksum entry: $line");
        }
        my ($digest, $name) = ($1, $2);
        if (exists($expected{$name})) {
            close($checksum_fh);
            return (undef, "Duplicate Genesis checksum entry: $name");
        }
        $expected{$name} = $digest;
    }
    close($checksum_fh);

    return (\%expected, undef);
}

sub _sha256_file {
    my ($path) = @_;
    open(my $artifact_fh, '<:raw', $path)
      or return (undef, "Unable to read Genesis artifact: $path");
    my $digest = Digest::SHA->new(256)->addfile($artifact_fh)->hexdigest;
    close($artifact_fh);
    return ($digest, undef);
}

sub _install_prebuilt_genesis {
    my ($source, $tftpdir, $arch) = @_;
    return (undef, "Invalid Genesis export directory: $source")
      unless -d $source && !-l $source;

    my $manifest_error =
      _validate_prebuilt_genesis_manifest($source, $arch);
    return (undef, $manifest_error) if $manifest_error;

    my ($expected, $checksum_error) =
      _read_prebuilt_genesis_checksums($source);
    return (undef, $checksum_error) if $checksum_error;

    unless (exists($expected->{$GENESIS_EXPORT_MANIFEST})) {
        return (undef,
            "Missing Genesis checksum entry: $GENESIS_EXPORT_MANIFEST");
    }
    my ($manifest_digest, $manifest_digest_error) =
      _sha256_file("$source/$GENESIS_EXPORT_MANIFEST");
    return (undef, $manifest_digest_error) if $manifest_digest_error;
    unless ($manifest_digest eq $expected->{$GENESIS_EXPORT_MANIFEST}) {
        return (undef,
            "Genesis checksum mismatch: $source/$GENESIS_EXPORT_MANIFEST");
    }

    my $destination_dir = "$tftpdir/xcat";
    eval { mkpath($destination_dir) unless -d $destination_dir; };
    return (undef, "Unable to create Genesis destination: $destination_dir")
      unless -d $destination_dir;

    my $suffix = xCAT::Utils::genpassword(24);
    my @artifacts = (
        [ 'kernel',             "$destination_dir/genesis.kernel.$arch" ],
        [ 'initramfs.cpio.gz', "$destination_dir/genesis.fs.$arch.gz" ],
        [ $GENESIS_EXPORT_MANIFEST,
          "$destination_dir/genesis.exact-arch.$arch" ],
    );
    my @staged;

    foreach my $artifact (@artifacts) {
        my ($name, $destination) = @{$artifact};
        my $source_path = "$source/$name";
        unless (-f $source_path && !-l $source_path) {
            unlink(@staged);
            return (undef, "Missing Genesis artifact: $source_path");
        }
        unless (exists($expected->{$name})) {
            unlink(@staged);
            return (undef, "Missing Genesis checksum entry: $name");
        }

        my $temporary = "$destination.$suffix.new";
        unless (copy($source_path, $temporary) && chmod(0644, $temporary)) {
            unlink(@staged, $temporary);
            return (undef, "Unable to stage Genesis artifact: $source_path");
        }
        push(@staged, $temporary);

        my ($digest, $digest_error) = _sha256_file($temporary);
        if ($digest_error || $digest ne $expected->{$name}) {
            unlink(@staged);
            return (undef, $digest_error || "Genesis checksum mismatch: $source_path");
        }
    }

    my %backups;
    foreach my $artifact (@artifacts) {
        my $destination = $artifact->[1];
        next unless -e $destination || -l $destination;
        unless (-f $destination && !-l $destination) {
            unlink(@staged, values(%backups));
            return (undef, "Invalid Genesis destination: $destination");
        }

        my $backup = "$destination.$suffix.old";
        unless (copy($destination, $backup)) {
            unlink(@staged, values(%backups));
            return (undef, "Unable to preserve Genesis artifact: $destination");
        }
        $backups{$destination} = $backup;
    }

    my @installed;
    foreach my $index (0 .. $#artifacts) {
        my $destination = $artifacts[$index]->[1];
        unless (rename($staged[$index], $destination)) {
            my @rollback_errors;
            foreach my $installed (reverse(@installed)) {
                if ($backups{$installed}) {
                    push(@rollback_errors, $installed)
                      unless rename($backups{$installed}, $installed);
                } else {
                    push(@rollback_errors, $installed) unless unlink($installed);
                }
            }
            unlink(@staged[$index .. $#staged], values(%backups));
            my $error = "Unable to install Genesis artifact: $destination";
            $error .= "; unable to restore: " . join(', ', @rollback_errors)
              if @rollback_errors;
            return (undef, $error);
        }
        push(@installed, $destination);
    }

    unlink(values(%backups));
    return ("$destination_dir/genesis.fs.$arch.gz", undef);
}

sub _remove_openembedded_genesis {
    my ($tftpdir, $requested_arch) = @_;
    return (0, 'Missing Genesis architecture') unless defined($requested_arch);
    my $arch = $requested_arch eq 'ppc64el' ? 'ppc64le' : $requested_arch;
    return (0, "Unsupported Genesis architecture: $requested_arch")
      unless $GENESIS_ARCHITECTURES{$arch};

    my $directory = "$tftpdir/xcat";
    my @artifacts = (
        "$directory/genesis.kernel.$arch",
        "$directory/genesis.fs.$arch.gz",
        "$directory/genesis.fs.$arch.lzma",
        "$directory/genesis.exact-arch.$arch",
    );
    my $removed = 0;
    foreach my $artifact (@artifacts) {
        next unless -e $artifact || -l $artifact;
        return ($removed, "Unable to remove Genesis artifact: $artifact")
          unless unlink($artifact);
        $removed++;
    }
    return ($removed, undef);
}

sub genesis_lzma_command {
    my ($have_lzma, $have_xz) = @_;
    return 'lzma -C crc32 -9'             if $have_lzma;
    return 'xz --format=lzma -C crc32 -9' if $have_xz;
    return;
}

sub process_request {
    my $request  = shift;
    my $callback = shift;
    my $serialport;
    my $serialspeed;
    my $serialflow;
    my %nobootnicips = ();
    my $initrd_file    = undef;
    my $invisibletouch = 0;
    my $xcatdport      = 3001;
    my @entries     = xCAT::TableUtils->get_site_attribute("defserialport");
    my $t_entry     = $entries[0];
    if (defined($t_entry)) {
        $serialport = $t_entry;
    }

    @entries = xCAT::TableUtils->get_site_attribute("defserialspeed");
    $t_entry = $entries[0];
    if (defined($t_entry)) {
        $serialspeed = $t_entry;
    }

    @entries = xCAT::TableUtils->get_site_attribute("defserialflow");
    $t_entry = $entries[0];
    if (defined($t_entry)) {
        $serialflow = $t_entry;
    }

    @entries = xCAT::TableUtils->get_site_attribute("xcatdport");
    $t_entry = $entries[0];
    if (defined($t_entry)) {
        $xcatdport = $t_entry;
    }

    my $httpport="80";
    my @hports=xCAT::TableUtils->get_site_attribute("httpport");
    if ($hports[0]){
        $httpport=$hports[0];
    }
    my $portsuffix = ( $httpport eq "80" ) ? "" : ":$httpport";

    @entries = xCAT::TableUtils->get_site_attribute("dhcpinterfaces");
    $t_entry = $entries[0];
    if (defined($t_entry)) {
        my %nobootnics = ();
        foreach my $dhcpif (split /;/, $t_entry) {
            if ($dhcpif =~ /\|/) {
                my $isself = 0;
                (my $ngroup, $dhcpif) = split /\|/, $dhcpif;
                foreach my $host (noderange($ngroup)) {
                    unless(xCAT::NetworkUtils->thishostisnot($host)) {
                        $isself = 1;
                    }
                }
                unless(xCAT::NetworkUtils->thishostisnot($ngroup)) {
                    $isself = 1;
                }
                unless ($isself) {
                    next;
                }
            }
            foreach (split /[,\s]+/, $dhcpif) {
                my ($nicname, $flag) = split /:/;
                if ($flag and $flag =~ /noboot/i) {
                    $nobootnics{$nicname} = 1;
                }
            }
        }
        my $nicips = xCAT::NetworkUtils->get_nic_ip();
        foreach (keys %$nicips) {
            # To support tagged vlan, create entries in the hash for the
            # interface name removing the physical interface ending:
            # 'enP1p12s0f0.2@enP1p12s0f0' => 'enP1p12s0f0.2'
            if ($_ =~ "@") {
                my $newkey = $_;
                $newkey =~ s/\@.*//g;
                $$nicips{$newkey} = ${nicips}->{$_};
            }
        }

        foreach (keys %nobootnics)  {
            if (defined($nicips->{$_})) {
                $nobootnicips{$nicips->{$_}} = 1;
            }
        }
    }

    my $tftpdir = xCAT::TableUtils->getTftpDir();
    my $requested_arch = $request->{arg}->[0];
    if (!$requested_arch) {
        $callback->({ error => "Need to specify architecture (x86, x86_64, ppc64, ppc64le, armv7hf, aarch64 or riscv64)" }, { errorcode => [1] });
        return;
    }

    my $canonical_arch = $requested_arch eq 'ppc64el'
      ? 'ppc64le'
      : $requested_arch;
    if (($request->{arg}->[1] // '') eq '--remove-openembedded') {
        unless ($GENESIS_ARCHITECTURES{$canonical_arch}) {
            $callback->({ error => "Unsupported Genesis architecture: $requested_arch", errorcode => [1] });
            return;
        }
        my $source = "$::XCATROOT/share/xcat/netboot/genesis-openembedded/$canonical_arch";
        if (-d $source || -l $source) {
            $callback->({ error => "Cannot remove boot artifacts while OpenEmbedded Genesis $canonical_arch is installed", errorcode => [1] });
            return;
        }
        my ($removed, $remove_error) =
          _remove_openembedded_genesis($tftpdir, $canonical_arch);
        if ($remove_error) {
            $callback->({ error => $remove_error, errorcode => [1] });
            return;
        }
        $callback->({ data => "Removed $removed OpenEmbedded Genesis artifacts for $canonical_arch" });
        return;
    }

    my ($genesis_dir, $arch, $genesis_type) =
      _select_genesis_source($::XCATROOT, $requested_arch);
    unless (defined($genesis_dir) && -d $genesis_dir) {
        $callback->({ error => "Unable to find a Genesis image for architecture $requested_arch", errorcode => [1] });
        return;
    }
    if ($canonical_arch eq 'ppc64le' && $arch eq 'ppc64') {
        my $marker = "$tftpdir/xcat/genesis.exact-arch.ppc64";
        if (-e $marker || -l $marker) {
            $callback->({
                error => 'Cannot use the legacy ppc64le fallback while a canonical ppc64 image is published',
                errorcode => [1],
            });
            return;
        }
    }
    if ($requested_arch eq 'ppc64el') {
        $callback->({ data => 'Using the canonical architecture name ppc64le' });
    }
    if (($requested_arch eq 'ppc64le' || $requested_arch eq 'ppc64el')
        && $arch eq 'ppc64') {
        $callback->({ data => 'OpenEmbedded ppc64le is not installed, using the legacy ppc64 image' });
    }
    $request->{arg}->[0] = $arch;

    my $configfileonly = $request->{arg}->[1];
    if ($configfileonly and $configfileonly ne "-c" and $configfileonly ne "--configfileonly") {
        $callback->({ error => "The option $configfileonly is not supported", errorcode => [1] });
        return;
    } elsif ($configfileonly) {
        goto CREAT_CONF_FILE;
    }
    if (_prebuilt_genesis_requested($genesis_dir)) {
        my $image_name = $genesis_type eq 'openembedded'
          ? 'OpenEmbedded Genesis'
          : 'exported Genesis';
        $callback->({ data => ["Installing $image_name image for $arch"] });
        my ($installed_initrd, $install_error) =
          _install_prebuilt_genesis($genesis_dir, $tftpdir, $arch);
        if ($install_error) {
            $callback->({ error => [$install_error], errorcode => [1] });
            return;
        }
        $initrd_file    = $installed_initrd;
        $invisibletouch = 1;
        goto CREAT_CONF_FILE;
    }
    if ($genesis_type eq 'openembedded'
        || _genesis_export_manifest_present($genesis_dir)) {
        $callback->({
            error => ["Incomplete Genesis export: $genesis_dir"],
            errorcode => [1],
        });
        return;
    }
    # Grab all the standard ssh public keys we can
    my @ssh_pub_keys = ();
    if (-r "/root/.ssh/id_rsa.pub") {
        push(@ssh_pub_keys, 'id_rsa.pub');
    }
    if (-r "/root/.ssh/id_ed25519.pub") {
        push(@ssh_pub_keys, 'id_ed25519.pub');
    }
    if (-r "/root/.ssh/id_ecdsa.pub") {
        push(@ssh_pub_keys, 'id_ecdsa.pub');
    }
    if (scalar @ssh_pub_keys == 0) {
        # We have no public keys.
        # See if we have any private keys we can extract pubkeys from
        if (-r "/root/.ssh/id_rsa") {
            $callback->({ data => ["Extracting rsa ssh public key from private key"] });
            my $rc = system('ssh-keygen -y -f /root/.ssh/id_rsa > /root/.ssh/id_rsa.pub');
            if ($rc) {
                $callback->({ error => ["Failure executing ssh-keygen for root when extracting rsa ssh public key from private key"], errorcode => [1] });
            } else {
                push(@ssh_pub_keys, 'id_rsa.pub');
            }
        } elsif (-r "/root/.ssh/id_ed25519") {
            $callback->({ data => ["Extracting ed25519 ssh public key from private key"] });
            my $rc = system('ssh-keygen -y -f /root/.ssh/id_ed25519 > /root/.ssh/id_ed25519.pub');
            if ($rc) {
                $callback->({ error => ["Failure executing ssh-keygen for root when extracting ed25519 ssh public key from private key"], errorcode => [1] });
            } else {
                push(@ssh_pub_keys, 'id_ed25519.pub');
            }
        } elsif (-r "/root/.ssh/id_ecdsa") {
            $callback->({ data => ["Extracting ecdsa ssh public key from private key"] });
            my $rc = system('ssh-keygen -y -f /root/.ssh/id_ecdsa > /root/.ssh/id_ecdsa.pub');
            if ($rc) {
                $callback->({ error => ["Failure executing ssh-keygen for root when extracting ecdsa ssh public key from private key"], errorcode => [1] });
            } else {
                push(@ssh_pub_keys, 'id_ecdsa.pub');
            }
        }
    }
    if (scalar @ssh_pub_keys == 0) {
        # Looks like we didn't have any private keys either, so generate one
        $callback->({ data => ["Generating rsa ssh private key for root"] });
        my $rc = system('ssh-keygen -t rsa -q -b 2048 -N "" -f  /root/.ssh/id_rsa');
        if ($rc) {
            $callback->({ error => ["Failure executing ssh-keygen for root when generating rsa ssh private key"], errorcode => [1] });
        } else {
            push(@ssh_pub_keys, 'id_rsa.pub');
        }
    }
    my $tempdir = tempdir("mknb.$$.XXXXXX", TMPDIR => 1);
    unless ($tempdir) {
        $callback->({ error => ["Failed to create a temporary directory"], errorcode => [1] });
        return;
    }
    unless (-e "$tftpdir/xcat") {
        mkpath("$tftpdir/xcat");
    }
    my $rc;
    if ($genesis_type eq 'legacy') {
        $rc = system("shopt -s dotglob; GLOBIGNORE=\".:..\" cp -a $genesis_dir/fs/* $tempdir");
        $rc = system("cp -a $genesis_dir/kernel $tftpdir/xcat/genesis.kernel.$arch");
        $invisibletouch = 1;
    } else {
        $rc = system("cp -a $genesis_dir/nbroot/* $tempdir");
    }
    if ($rc) {
        system("rm -rf $tempdir");
        if ($invisibletouch) {
            $callback->({ error => ["Failed to copy $genesis_dir/fs contents"], errorcode => [1] });
        } else {
            $callback->({ error => ["Failed to copy $genesis_dir/nbroot contents"], errorcode => [1] });
        }
        return;
    }
    my $sshdir;
    if ($invisibletouch) {
        $sshdir = "/.ssh";
    } else {
        $sshdir = "/root/.ssh";
    }
    mkpath($tempdir . "$sshdir");
    chmod(0700, $tempdir . "$sshdir");
    open(my $authkeys_fh, '>:raw', "$tempdir$sshdir/authorized_keys");
    foreach my $keyfile (@ssh_pub_keys) {
        open(my $pubkey_fh, '<:raw', "/root/.ssh/$keyfile");
	while(my $line = <$pubkey_fh>) {
	    print($authkeys_fh $line);
	}
        close($pubkey_fh);
    }
    close($authkeys_fh);
    chmod(0600, "$tempdir$sshdir/authorized_keys");
    if (not $invisibletouch and -r "/etc/xcat/hostkeys/ssh_host_rsa_key") {
        copy("/etc/xcat/hostkeys/ssh_host_rsa_key", "$tempdir/etc/ssh_host_rsa_key");
        copy("/etc/xcat/hostkeys/ssh_host_dsa_key", "$tempdir/etc/ssh_host_dsa_key");
        chmod(0600, <$tempdir/etc/ssh_*>);
    }
    unless ($invisibletouch or -r "$tempdir/etc/ssh_host_rsa_key") {
        system("ssh-keygen -t rsa -f $tempdir/etc/ssh_host_rsa_key -C '' -N ''");
        system("ssh-keygen -t dsa -f $tempdir/etc/ssh_host_dsa_key -C '' -N ''");
    }
    my $lzma_exit_value = 1;
    if ($invisibletouch) {
        my $done = 0;
        # Build each image under a unique suffix and atomically rename it into
        # place, so concurrent mknb runs sharing $tftpdir cannot read or clobber
        # a half-written genesis.fs.
        my $suffix = xCAT::Utils::genpassword(24);
        my $lzma_command = genesis_lzma_command(-x "/usr/bin/lzma", -x "/usr/bin/xz");
        if ($lzma_command) {    #let's reclaim some of that size...
            $callback->({ data => ["Creating genesis.fs.$arch.lzma in $tftpdir/xcat"] });
            system("cd $tempdir; find . | cpio -o -H newc | $lzma_command > $tftpdir/xcat/genesis.fs.$arch.lzma.$suffix");
            $lzma_exit_value = $? >> 8;
            if ($lzma_exit_value) {
                $callback->({ data => ["Creating genesis.fs.$arch.lzma in $tftpdir/xcat failed, falling back to gzip"] });
                unlink("$tftpdir/xcat/genesis.fs.$arch.lzma.$suffix");
            } else {
                move("$tftpdir/xcat/genesis.fs.$arch.lzma.$suffix", "$tftpdir/xcat/genesis.fs.$arch.lzma");
                $done        = 1;
                $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.lzma";
            }
        }

        if (not $done) {
            $callback->({ data => ["Creating genesis.fs.$arch.gz in $tftpdir/xcat"] });
            system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/genesis.fs.$arch.gz.$suffix");
            move("$tftpdir/xcat/genesis.fs.$arch.gz.$suffix", "$tftpdir/xcat/genesis.fs.$arch.gz");
            $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.gz";
        }
    } else {
        $callback->({ data => ["Creating nbfs.$arch.gz in $tftpdir/xcat"] });
        system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/nbfs.$arch.gz");
        $initrd_file = "$tftpdir/xcat/nbfs.$arch.gz";
    }
    system("rm -rf $tempdir");
    unless ($initrd_file) {
        $callback->({ data => ["Creating filesystem file in $tftpdir/xcat failed"] });
        return;
    }
    my $exact_arch_marker = "$tftpdir/xcat/genesis.exact-arch.$arch";
    if (($genesis_type eq 'legacy' || $genesis_type eq 'classic')
        && (-e $exact_arch_marker || -l $exact_arch_marker)
        && !unlink($exact_arch_marker)) {
        $callback->({ error => ["Unable to remove Genesis architecture marker: $exact_arch_marker"], errorcode => [1] });
        return;
    }

  CREAT_CONF_FILE:
    if ($configfileonly) {
        unless (-e "$tftpdir/xcat/genesis.kernel.$arch") {
            $callback->({ error => ["No kernel file found in $tftpdir/xcat, pls run \"mknb $arch\" instead."], errorcode => [1] });
            return;
        }
        if (-e "$tftpdir/xcat/genesis.fs.$arch.lzma") {
            $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.lzma";
            $invisibletouch = 1;
        } elsif (-e "$tftpdir/xcat/genesis.fs.$arch.gz") {
            $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.gz";
            $invisibletouch = 1;
        } elsif (-e "$tftpdir/xcat/nbfs.$arch.gz") {
            $initrd_file = "$tftpdir/xcat/nbfs.$arch.gz";
        } else {
            $callback->({ error => ["No filesystem file found in $tftpdir/xcat, pls run \"mknb $arch\" instead."], errorcode => [1] });
            return;
        }
    }
    my $hexnet_addresses  = xCAT::NetworkUtils->my_hexnets('all');
    my $normnet_addresses = xCAT::NetworkUtils->my_nets('all');
    my @masters = xCAT::TableUtils->get_site_attribute("master");
    my @master_addresses;
    if ($masters[0]) {
        @master_addresses = xCAT::NetworkUtils->getipaddr(
            $masters[0], OnlyV4 => 1, GetAllAddresses => 1
        );
    }
    my ($hexnets, $xcatdhexnets) = _select_network_addresses(
        $hexnet_addresses, \@master_addresses
    );
    my ($normnets, $xcatdnormnets) = _select_network_addresses(
        $normnet_addresses, \@master_addresses
    );
    my $consolecmdline;
    if (defined($serialport) and $serialspeed) {
        if ($arch =~ /ppc/) {
            $consolecmdline = "console=tty0 console=hvc$serialport,$serialspeed";
        } else {
            $consolecmdline = "console=tty0 console=ttyS$serialport,$serialspeed";
        }
        if ($serialflow =~ /cts/ or $serialflow =~ /hard/) {
            $consolecmdline .= "n8r";
        }
    }
    my $cfgfile;
    if ($arch =~ /x86/) {
        mkpath("$tftpdir/xcat/xnba/nets");
        chmod(0755, "$tftpdir/xcat/xnba");
        chmod(0755, "$tftpdir/xcat/xnba/nets");
        mkpath("$tftpdir/pxelinux.cfg");
        chmod(0755, "$tftpdir/pxelinux.cfg");
        if (-r "/usr/lib/syslinux/pxelinux.0") {
            copy("/usr/lib/syslinux/pxelinux.0", "$tftpdir/pxelinux.0");
        } elsif (-r "/usr/share/syslinux/pxelinux.0") {
            copy("/usr/share/syslinux/pxelinux.0", "$tftpdir/pxelinux.0");
        } elsif ("/usr/lib/PXELINUX/pxelinux.0") {
            copy("/usr/lib/PXELINUX/pxelinux.0", "$tftpdir/pxelinux.0");
        } else {
            copy("/opt/xcat/share/xcat/netboot/syslinux/pxelinux.0", "$tftpdir/pxelinux.0");
        }
        if (-r "$tftpdir/pxelinux.0") {
            chmod(0644, "$tftpdir/pxelinux.0");
        }
    } elsif ($arch =~ /ppc/) {
        mkpath("$tftpdir/pxelinux.cfg/p/");
    }
    my $dopxe = 0;
    foreach (keys %{$normnets}) {
        my $net = $_;
        my $nicip = $normnets->{$net};
        my $xcatd_address = defined($xcatdnormnets->{$net}) ? $xcatdnormnets->{$net} : $nicip;
        $net =~ s/\//_/;
        if (defined($nobootnicips{$nicip})) {
            if ($arch =~ /ppc/ and -r "$tftpdir/pxelinux.cfg/p/$net") {
                unlink("$tftpdir/pxelinux.cfg/p/$net");
            }
            next;
        }
        $dopxe = 0;
        if ($arch =~ /x86/) {    #only do pxe if just x86 or x86_64 and no x86
            if ($arch =~ /x86_64/ and not $invisibletouch) {
                if (-r "$tftpdir/xcat/xnba/nets/$net") {
                    my $cfg;
                    my @contents;
                    open($cfg, "<", "$tftpdir/xcat/xnba/nets/$net");
                    @contents = <$cfg>;
                    close($cfg);
                    if (grep (/x86_64/, @contents)) {
                        $dopxe = 1;
                    }
                } else {
                    $dopxe = 1;
                }
            } else {
                $dopxe = 1;
            }
        }
        if ($dopxe) {
            my $cfg;
            open($cfg, ">", "$tftpdir/xcat/xnba/nets/$net");
            print $cfg "#!gpxe\n";
            if ($invisibletouch) {
                print $cfg 'imgfetch -n kernel http://${next-server}'.$portsuffix.'/tftpboot/xcat/genesis.kernel.' . "$arch xcatd=" . $xcatd_address . ":$xcatdport $consolecmdline BOOTIF=01-" . '${netX/machyp}' . "\n";
                print $cfg 'imgfetch -n nbfs http://${next-server}'.$portsuffix . "$initrd_file\n";
            } else {
                print $cfg 'imgfetch -n kernel http://${next-server}'.$portsuffix.'/tftpboot/xcat/nbk.' . "$arch xcatd=" . $xcatd_address . ":$xcatdport $consolecmdline\n";
                print $cfg 'imgfetch -n nbfs http://${next-server}'.$portsuffix . "$initrd_file\n";
            }
            print $cfg "imgload kernel\n";
            print $cfg "imgexec kernel\n";
            close($cfg);
            if ($invisibletouch and $arch =~ /x86_64/) {    #UEFI time
                open($cfg, ">", "$tftpdir/xcat/xnba/nets/$net.elilo");
                print $cfg "default=\"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
                print $cfg "   delay=5\n";
                print $cfg '   image=/tftpboot/xcat/genesis.kernel.' . "$arch\n";
                print $cfg "   label=\"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
                print $cfg "   initrd=$initrd_file\n";
                print $cfg "   append=\"xcatd=" . $xcatd_address . ":$xcatdport destiny=discover $consolecmdline BOOTIF=%B\"\n";
                close($cfg);
                open($cfg, ">", "$tftpdir/xcat/xnba/nets/$net.uefi");
                print $cfg "#!gpxe\n";
                print $cfg 'imgfetch -n kernel http://${next-server}'.$portsuffix.'/tftpboot/xcat/genesis.kernel.' . "$arch\nimgload kernel\n";
                print $cfg "imgargs kernel xcatd=" . $xcatd_address . ":$xcatdport $consolecmdline BOOTIF=01-" . '${netX/mac:hexhyp}' . " destiny=discover initrd=initrd\n";
                print $cfg 'imgfetch -n initrd http://${next-server}'.$portsuffix . "$initrd_file\nimgexec kernel\n";
                close($cfg);
            }
        } elsif ($arch =~ /ppc/) {
            open($cfgfile, ">", "$tftpdir/pxelinux.cfg/p/$net");
            print $cfgfile "default \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   delay=10\n";
            print $cfgfile "   label \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   kernel http://" . $xcatd_address . "$portsuffix/$tftpdir/xcat/genesis.kernel.$arch\n";
            print $cfgfile "   initrd http://" . $xcatd_address . "$portsuffix/$initrd_file\n";
            print $cfgfile '   append "xcatd=' . $xcatd_address . ":$xcatdport $consolecmdline\"\n";
            close($cfgfile);
        }
    }
    $dopxe = 0;
    foreach (keys %{$hexnets}) {
        my $xcatd_address = defined($xcatdhexnets->{$_}) ? $xcatdhexnets->{$_} : $hexnets->{$_};
        $dopxe = 0;
        if ($arch =~ /x86/) {    #only do pxe if just x86 or x86_64 and no x86
            if ($arch =~ /x86_64/) {
                if (-r "$tftpdir/pxelinux.cfg/" . uc($_)) {
                    my $pcfg;
                    open($pcfg, "<", "$tftpdir/pxelinux.cfg/" . uc($_));
                    my @pcfgcontents = <$pcfg>;
                    close($pcfg);
                    if (grep (/x86_64/, @pcfgcontents)) {
                        $dopxe = 1;
                    }
                } else {
                    $dopxe = 1;
                }
            } else {
                $dopxe = 1;
            }
        }
        if ($dopxe) {
            my $tftp_initrd = $initrd_file;
            $tftp_initrd =~ s{^\Q$tftpdir\E/?}{};
            my $kernel_file = $invisibletouch ? "genesis.kernel.$arch" : "nbk.$arch";
            open($cfgfile, ">", "$tftpdir/pxelinux.cfg/" . uc($_));
            print $cfgfile "DEFAULT xCAT\n";
            print $cfgfile "  LABEL xCAT\n";
            print $cfgfile "  KERNEL xcat/$kernel_file\n";
            print $cfgfile "  APPEND initrd=$tftp_initrd xcatd=" . $xcatd_address . ":$xcatdport $consolecmdline\n";
            close($cfgfile);
        } elsif ($arch =~ /ppc/) {
            open($cfgfile, ">", "$tftpdir/etc/" . lc($_));
            print $cfgfile "default \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   delay=10\n";
            print $cfgfile "   label \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   kernel http://" . $xcatd_address . "$portsuffix/$tftpdir/xcat/genesis.kernel.$arch\n";
            print $cfgfile "   initrd http://" . $xcatd_address . "$portsuffix/$initrd_file\n";
            print $cfgfile '   append "xcatd=' . $xcatd_address . ":$xcatdport $consolecmdline\"\n";
            close($cfgfile);
        }
    }
    if ($configfileonly) {
        $callback->({ data => ["Write netboot config file done"] });
    }
}

1;
