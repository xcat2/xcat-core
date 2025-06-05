package xCAT_plugin::mknb;
use strict;
use File::Temp qw(tempdir);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NodeRange;
use File::Path;
use File::Copy;

sub handled_commands {
    return {
        mknb => 'mknb',
    };
}

sub process_request {
    my $request  = shift;
    my $callback = shift;
    my $serialport;
    my $serialspeed;
    my $serialflow;
    my %nobootnicips = ();
    my $initrd_file = undef;
    my $xcatdport   = 3001;
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
    my $arch    = $request->{arg}->[0];
    if (!$arch) {
        $callback->({ error => "Need to specify architecture (x86, x86_64 or ppc64)" }, { errorcode => [1] });
        return;
    } elsif ($arch eq "ppc64le" or $arch eq "ppc64el") {
        $callback->({ data => "The arch:$arch is not supported, using \"ppc64\" instead" });
        $arch = 'ppc64';
        $request->{arg}->[0] = $arch;
    }

    unless (-d "$::XCATROOT/share/xcat/netboot/$arch" or -d "$::XCATROOT/share/xcat/netboot/genesis/$arch") {
        $callback->({ error => "Unable to find directory $::XCATROOT/share/xcat/netboot/$arch or $::XCATROOT/share/xcat/netboot/genesis/$arch", errorcode => [1] });
        return;
    }
    my $configfileonly = $request->{arg}->[1];
    if ($configfileonly and $configfileonly ne "-c" and $configfileonly ne "--configfileonly") {
        $callback->({ error => "The option $configfileonly is not supported", errorcode => [1] });
        return;
    } elsif ($configfileonly) {
        goto CREAT_CONF_FILE;
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
    my $invisibletouch = 0;
    if (-e "$::XCATROOT/share/xcat/netboot/genesis/$arch") {
        $rc = system("shopt -s dotglob; GLOBIGNORE=\".:..\" cp -a $::XCATROOT/share/xcat/netboot/genesis/$arch/fs/* $tempdir");
        $rc = system("cp -a $::XCATROOT/share/xcat/netboot/genesis/$arch/kernel $tftpdir/xcat/genesis.kernel.$arch");
        $invisibletouch = 1;
    } else {
        $rc = system("cp -a $::XCATROOT/share/xcat/netboot/$arch/nbroot/* $tempdir");
    }
    if ($rc) {
        system("rm -rf $tempdir");
        if ($invisibletouch) {
            $callback->({ error => ["Failed to copy  $::XCATROOT/share/xcat/netboot/genesis/$arch/fs contents"], errorcode => [1] });
        } else {
            $callback->({ error => ["Failed to copy  $::XCATROOT/share/xcat/netboot/$arch/nbroot/ contents"], errorcode => [1] });
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
        if (-x "/usr/bin/lzma") {    #let's reclaim some of that size...
            $callback->({ data => ["Creating genesis.fs.$arch.lzma in $tftpdir/xcat"] });
            system("cd $tempdir; find . | cpio -o -H newc | lzma -C crc32 -9 > $tftpdir/xcat/genesis.fs.$arch.lzma");
            $lzma_exit_value = $? >> 8;
            if ($lzma_exit_value) {
                $callback->({ data => ["Creating genesis.fs.$arch.lzma in $tftpdir/xcat failed, falling back to gzip"] });
                unlink("$tftpdir/xcat/genesis.fs.$arch.lzma");
            } else {
                $done        = 1;
                $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.lzma";
            }
        }

        if (not $done) {
            $callback->({ data => ["Creating genesis.fs.$arch.gz in $tftpdir/xcat"] });
            system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/genesis.fs.$arch.gz");
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

  CREAT_CONF_FILE:
    if ($configfileonly) {
        unless (-e "$tftpdir/xcat/genesis.kernel.$arch") {
            $callback->({ error => ["No kernel file found in $tftpdir/xcat, pls run \"mknb $arch\" instead."], errorcode => [1] });
            return;
        }
        if (-e "$tftpdir/xcat/genesis.fs.$arch.lzma") {
            $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.lzma";
        } elsif (-e "$tftpdir/xcat/genesis.fs.$arch.gz") {
            $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.gz";
        } elsif (-e "$tftpdir/xcat/nbfs.$arch.gz") {
            $initrd_file = "$tftpdir/xcat/nbfs.$arch.gz";
        } else {
            $callback->({ error => ["No filesystem file found in $tftpdir/xcat, pls run \"mknb $arch\" instead."], errorcode => [1] });
            return;
        }
    }
    my $hexnets  = xCAT::NetworkUtils->my_hexnets();
    my $normnets = xCAT::NetworkUtils->my_nets();
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
                print $cfg 'imgfetch -n kernel http://${next-server}:'.$httpport.'/tftpboot/xcat/genesis.kernel.' . "$arch quiet xcatd=" . $normnets->{$_} . ":$xcatdport $consolecmdline BOOTIF=01-" . '${netX/machyp}' . "\n";
                print $cfg 'imgfetch -n nbfs http://${next-server}:'.$httpport . "$initrd_file\n";
            } else {
                print $cfg 'imgfetch -n kernel http://${next-server}:'.$httpport.'/tftpboot/xcat/nbk.' . "$arch quiet xcatd=" . $normnets->{$_} . ":$xcatdport $consolecmdline\n";
                print $cfg 'imgfetch -n nbfs http://${next-server}:'.$httpport . "$initrd_file\n";
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
                print $cfg "   append=\"quiet xcatd=" . $normnets->{$_} . ":$xcatdport destiny=discover $consolecmdline BOOTIF=%B\"\n";
                close($cfg);
                open($cfg, ">", "$tftpdir/xcat/xnba/nets/$net.uefi");
                print $cfg "#!gpxe\n";
                print $cfg 'imgfetch -n kernel http://${next-server}:'.$httpport.'/tftpboot/xcat/genesis.kernel.' . "$arch\nimgload kernel\n";
                print $cfg "imgargs kernel quiet xcatd=" . $normnets->{$_} . ":$xcatdport $consolecmdline BOOTIF=01-" . '${netX/mac:hexhyp}' . " destiny=discover initrd=initrd\n";
                print $cfg 'imgfetch -n initrd http://${next-server}:'.$httpport . "$initrd_file\nimgexec kernel\n";
                close($cfg);
            }
        } elsif ($arch =~ /ppc/) {
            open($cfgfile, ">", "$tftpdir/pxelinux.cfg/p/$net");
            print $cfgfile "default \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   delay=10\n";
            print $cfgfile "   label \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   kernel http://" . $normnets->{$_} . ":$httpport/$tftpdir/xcat/genesis.kernel.$arch\n";
            print $cfgfile "   initrd http://" . $normnets->{$_} . ":$httpport/$initrd_file\n";
            print $cfgfile '   append "quiet xcatd=' . $normnets->{$_} . ":$xcatdport $consolecmdline\"\n";
            close($cfgfile);
        }
    }
    $dopxe = 0;
    foreach (keys %{$hexnets}) {
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
            my ($ignored, $tftp_initrd) = split /\/tftpboot\//, $initrd_file, 2;
            open($cfgfile, ">", "$tftpdir/pxelinux.cfg/" . uc($_));
            print $cfgfile "DEFAULT xCAT\n";
            print $cfgfile "  LABEL xCAT\n";
            print $cfgfile "  KERNEL xcat/nbk.$arch\n";
            print $cfgfile "  APPEND initrd=$tftp_initrd quiet xcatd=" . $hexnets->{$_} . ":$xcatdport $consolecmdline\n";
            close($cfgfile);
        } elsif ($arch =~ /ppc/) {
            open($cfgfile, ">", "$tftpdir/etc/" . lc($_));
            print $cfgfile "default \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   delay=10\n";
            print $cfgfile "   label \"xCAT Genesis (" . $normnets->{$_} . ")\"\n";
            print $cfgfile "   kernel http://" . $hexnets->{$_} . ":$httpport/$tftpdir/xcat/genesis.kernel.$arch\n";
            print $cfgfile "   initrd http://" . $hexnets->{$_} . ":$httpport/$initrd_file\n";
            print $cfgfile '   append "quiet xcatd=' . $hexnets->{$_} . ":$xcatdport $consolecmdline\"\n";
            close($cfgfile);
        }
    }
    if ($configfileonly) {
        $callback->({ data => ["Write netboot config file done"] });
    }
}

1;
