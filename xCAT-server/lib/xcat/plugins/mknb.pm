package xCAT_plugin::mknb;
use strict;
use File::Temp qw(tempdir);
use xCAT::Utils;
use xCAT::TableUtils;
use File::Path;
use File::Copy;

sub handled_commands {
   return { 
      mknb => 'mknb',
   };
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   #my $sitetab = xCAT::Table->new('site');
   my $serialport;
   my $serialspeed;
   my $serialflow;
   my $xcatdport = 3001;
   #if ($sitetab) {
      #my $portent = $sitetab->getAttribs({key=>'defserialport'},'value');
      my @entries =  xCAT::TableUtils->get_site_attribute("defserialport");
      my $t_entry = $entries[0];
      if ( defined($t_entry) ) {
         $serialport=$t_entry;
      }
      #$portent = $sitetab->getAttribs({key=>'defserialspeed'},'value');
      @entries =  xCAT::TableUtils->get_site_attribute("defserialspeed");
      $t_entry = $entries[0];
      if ( defined($t_entry) ) {
         $serialspeed=$t_entry;
      }
      #$portent = $sitetab->getAttribs({key=>'defserialflow'},'value');
      @entries =  xCAT::TableUtils->get_site_attribute("defserialflow");
      $t_entry = $entries[0];
      if ( defined($t_entry) ) {
         $serialflow=$t_entry;
      }
      #$portent = $sitetab->getAttribs({key=>'xcatdport'},'value');
      @entries =  xCAT::TableUtils->get_site_attribute("xcatdport");
      $t_entry = $entries[0];
      if ( defined($t_entry) ) {
         $xcatdport=$t_entry;
      }
      #$sitetab->close;
   #}

   my $tftpdir = xCAT::TableUtils->getTftpDir();
   my $arch = $request->{arg}->[0];
   if (! $arch) {
      $callback->({error=>"Need to specify architecture (x86, x86_64 or ppc64)"},{errorcode=>[1]});
      return;
   } elsif ( $arch eq "ppc64le" or $arch eq "ppc64el" ) {
       $callback->({data=>"The arch:$arch is not supported at present, pls use \"ppc64\" instead"});
       return;
   }
   unless (-d "$::XCATROOT/share/xcat/netboot/$arch" or -d "$::XCATROOT/share/xcat/netboot/genesis/$arch") {
      $callback->({error=>"Unable to find directory $::XCATROOT/share/xcat/netboot/$arch or $::XCATROOT/share/xcat/netboot/genesis/$arch",errorcode=>[1]});
      return;
   }
   unless ( -r "/root/.ssh/id_rsa.pub" ) {
      if (-r "/root/.ssh/id_rsa") {
         $callback->({data=>["Extracting ssh public key from private key"]});
         my $rc = system('ssh-keygen -y -f /root/.ssh/id_rsa > /root/.ssh/id_rsa.pub');
         if ($rc) {
            $callback->({error=>["Failure executing ssh-keygen for root"],errorcode=>[1]});
         }
      } else {
        $callback->({data=>["Generating ssh private key for root"]});
        my $rc=system('ssh-keygen -t rsa -q -b 2048 -N "" -f  /root/.ssh/id_rsa');
        if ($rc) {
           $callback->({error=>["Failure executing ssh-keygen for root"],errorcode=>[1]});
        }
      }
   }
   my $tempdir = tempdir("mknb.$$.XXXXXX",TMPDIR=>1);
   unless ($tempdir) {
      $callback->({error=>["Failed to create a temporary directory"],errorcode=>[1]});
      return;
   }
   unless (-e "$tftpdir/xcat") {
       mkpath("$tftpdir/xcat");
   }
   my $rc;
   my $invisibletouch=0;
   if (-e  "$::XCATROOT/share/xcat/netboot/genesis/$arch") {
      $rc = system("cp -a $::XCATROOT/share/xcat/netboot/genesis/$arch/fs/* $tempdir");
      $rc = system("cp -a $::XCATROOT/share/xcat/netboot/genesis/$arch/kernel $tftpdir/xcat/genesis.kernel.$arch");
      $invisibletouch=1;
   } else {
      $rc = system("cp -a $::XCATROOT/share/xcat/netboot/$arch/nbroot/* $tempdir");
   }
   if ($rc) {
      system("rm -rf $tempdir");
      if ($invisibletouch) {
          $callback->({error=>["Failed to copy  $::XCATROOT/share/xcat/netboot/genesis/$arch/fs contents"],errorcode=>[1]});
      } else {
          $callback->({error=>["Failed to copy  $::XCATROOT/share/xcat/netboot/$arch/nbroot/ contents"],errorcode=>[1]});
      }
      return;
   }
   my $sshdir;
   if ($invisibletouch) {
	$sshdir="/.ssh";
   } else {
        $sshdir="/root/.ssh";
   }
   mkpath($tempdir."$sshdir");
   chmod(0700,$tempdir."$sshdir");
   copy("/root/.ssh/id_rsa.pub","$tempdir$sshdir/authorized_keys");
   chmod(0600,"$tempdir$sshdir/authorized_keys");
   if (not $invisibletouch and -r "/etc/xcat/hostkeys/ssh_host_key") {
    copy("/etc/xcat/hostkeys/ssh_host_key","$tempdir/etc/ssh_host_key");
    copy("/etc/xcat/hostkeys/ssh_host_rsa_key","$tempdir/etc/ssh_host_rsa_key");
    copy("/etc/xcat/hostkeys/ssh_host_dsa_key","$tempdir/etc/ssh_host_dsa_key");
      chmod(0600,<$tempdir/etc/ssh_*>);
   }
   unless ($invisibletouch or -r "$tempdir/etc/ssh_host_key") {
      system("ssh-keygen -t rsa1 -f $tempdir/etc/ssh_host_key -C '' -N ''");
      system("ssh-keygen -t rsa -f $tempdir/etc/ssh_host_rsa_key -C '' -N ''");
      system("ssh-keygen -t dsa -f $tempdir/etc/ssh_host_dsa_key -C '' -N ''");
   }
   my $initrd_file = undef;
   my $lzma_exit_value=1;
   if ($invisibletouch) {
       my $done=0;
       if (-x "/usr/bin/lzma") { #let's reclaim some of that size...
       $callback->({data=>["Creating genesis.fs.$arch.lzma in $tftpdir/xcat"]});
       system("cd $tempdir; find . | cpio -o -H newc | lzma -C crc32 -9 > $tftpdir/xcat/genesis.fs.$arch.lzma");
	$lzma_exit_value=$? >> 8;
	if ($lzma_exit_value) {
		$callback->({data=>["Creating genesis.fs.$arch.lzma in $tftpdir/xcat failed, falling back to gzip"]});
		unlink ("$tftpdir/xcat/genesis.fs.$arch.lzma");
	} else {
		$done = 1;
                $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.lzma";
	}
	}
		
       if (not $done) {
       $callback->({data=>["Creating genesis.fs.$arch.gz in $tftpdir/xcat"]});
       system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/genesis.fs.$arch.gz");
       $initrd_file = "$tftpdir/xcat/genesis.fs.$arch.gz";
	}
   } else {
   	$callback->({data=>["Creating nbfs.$arch.gz in $tftpdir/xcat"]});
       system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/nbfs.$arch.gz");
       $initrd_file = "$tftpdir/xcat/nbfs.$arch.gz";
   }
   system ("rm -rf $tempdir");
   unless ($initrd_file) {
       $callback->({data=>["Creating filesystem file in $tftpdir/xcat failed"]});
       return;
   }
   my $hexnets = xCAT::NetworkUtils->my_hexnets();
   my $normnets = xCAT::NetworkUtils->my_nets();
   my $consolecmdline;
   if (defined($serialport) and $serialspeed) {
       $consolecmdline = "console=tty0 console=ttyS$serialport,$serialspeed";
      if ($serialflow =~ /cts/ or $serialflow =~ /hard/) {
         $consolecmdline .= "n8r";
      } 
   }
   my $cfgfile;
   if ($arch =~ /x86/) {
      mkpath("$tftpdir/xcat/xnba/nets");
      chmod(0755,"$tftpdir/xcat/xnba");
      chmod(0755,"$tftpdir/xcat/xnba/nets");
      mkpath("$tftpdir/pxelinux.cfg");
      chmod(0755,"$tftpdir/pxelinux.cfg");
      if (! -r "$tftpdir/pxelinux.0") {
         unless (-r "/usr/lib/syslinux/pxelinux.0" or -r "/usr/share/syslinux/pxelinux.0") {
            $callback->({error=>["Unable to find pxelinux.0 "],errorcode=>[1]});
            return;
         }
         if (-r "/usr/lib/syslinux/pxelinux.0") {
            copy("/usr/lib/syslinux/pxelinux.0","$tftpdir/pxelinux.0");
         } else {
            copy("/usr/share/syslinux/pxelinux.0","$tftpdir/pxelinux.0");
         }
         chmod(0644,"$tftpdir/pxelinux.0");
      }
   } elsif ($arch =~ /ppc/) {
      mkpath("$tftpdir/pxelinux.cfg/p/");
   }
   my $dopxe=0;
   foreach (keys %{$normnets}) {
      my $net = $_;
      $net =~s/\//_/;
      $dopxe=0;
      if ($arch =~ /x86/) { #only do pxe if just x86 or x86_64 and no x86
          if ($arch =~ /x86_64/ and not $invisibletouch) {
              if (-r "$tftpdir/xcat/xnba/nets/$net") {
                  my $cfg;
                  my @contents;
                  open($cfg,"<","$tftpdir/xcat/xnba/nets/$net");
                  @contents = <$cfg>;
                  close($cfg);
                   if (grep (/x86_64/,@contents)) {
                      $dopxe=1;
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
         open($cfg,">","$tftpdir/xcat/xnba/nets/$net");
         print $cfg "#!gpxe\n";
	 if ($invisibletouch) {
         print $cfg 'imgfetch -n kernel http://${next-server}/tftpboot/xcat/genesis.kernel.'."$arch quiet xcatd=".$normnets->{$_}.":$xcatdport $consolecmdline BOOTIF=01-".'${netX/machyp}'."\n";
	if ($lzma_exit_value) {
         print $cfg 'imgfetch -n nbfs http://${next-server}/tftpboot/xcat/genesis.fs.'."$arch.gz\n";
	} else {
         print $cfg 'imgfetch -n nbfs http://${next-server}/tftpboot/xcat/genesis.fs.'."$arch.lzma\n";
	}
         } else {
         print $cfg 'imgfetch -n kernel http://${next-server}/tftpboot/xcat/nbk.'."$arch quiet xcatd=".$normnets->{$_}.":$xcatdport $consolecmdline\n";
         print $cfg 'imgfetch -n nbfs http://${next-server}/tftpboot/xcat/nbfs.'."$arch.gz\n";
	 }
         print $cfg "imgload kernel\n";
         print $cfg "imgexec kernel\n";
         close($cfg);
	if ($invisibletouch and $arch =~ /x86_64/) { #UEFI time
         open($cfg,">","$tftpdir/xcat/xnba/nets/$net.elilo");
         print $cfg "default=\"xCAT Genesis\"\ndelay=5\n\n";
         print $cfg 'image=/tftpboot/xcat/genesis.kernel.'."$arch\n";
	 print $cfg "   label=\"xCAT Genesis\"\n";
	if ($lzma_exit_value) {
	 print $cfg "   initrd=/tftpboot/xcat/genesis.fs.$arch.gz\n";
	} else {
	 print $cfg "   initrd=/tftpboot/xcat/genesis.fs.$arch.lzma\n";
	}
	 print $cfg "   append=\"quiet xcatd=".$normnets->{$_}.":$xcatdport destiny=discover $consolecmdline BOOTIF=%B\"\n";
	 close($cfg);
         open($cfg,">","$tftpdir/xcat/xnba/nets/$net.uefi");
         print $cfg "#!gpxe\n";
	 print $cfg 'chain http://${next-server}/tftpboot/xcat/elilo-x64.efi -C /tftpboot/xcat/xnba/nets/'."$net.elilo\n";
	 close($cfg);
	}
	
      } elsif ($arch =~ /ppc/) {
         open($cfgfile,">", "$tftpdir/pxelinux.cfg/p/$net");
         print $cfgfile "default xCAT\n";
         print $cfgfile "   label xCAT\n";
         print $cfgfile "   kernel http://".$normnets->{$_}.":80/$tftpdir/xcat/genesis.kernel.$arch\n";
         print $cfgfile "   initrd http://".$normnets->{$_}.":80/$initrd_file\n";
         print $cfgfile '   append "quiet xcatd='.$normnets->{$_}.":$xcatdport $consolecmdline\"\n";
         close($cfgfile);
      }
   }
   $dopxe=0;
   foreach (keys %{$hexnets}) {
      $dopxe=0;
      if ($arch =~ /x86/) { #only do pxe if just x86 or x86_64 and no x86
         if ($arch =~ /x86_64/) {
            if (-r "$tftpdir/pxelinux.cfg/".uc($_)) {
               my $pcfg;
               open($pcfg,"<","$tftpdir/pxelinux.cfg/".uc($_));
               my @pcfgcontents = <$pcfg>;
               close($pcfg);
               if (grep (/x86_64/,@pcfgcontents)) {
                  $dopxe=1;
               }
            } else {
               $dopxe=1;
            }
         } else {
            $dopxe=1;
         }
      }
      if ($dopxe) {
         open($cfgfile,">","$tftpdir/pxelinux.cfg/".uc($_));
         print $cfgfile "DEFAULT xCAT\n";
         print $cfgfile "  LABEL xCAT\n";
         print $cfgfile "  KERNEL xcat/nbk.$arch\n";
         print $cfgfile "  APPEND initrd=xcat/nbfs.$arch.gz quiet xcatd=".$hexnets->{$_}.":$xcatdport $consolecmdline\n";
         close($cfgfile);
      } elsif ($arch =~ /ppc/) {
         open($cfgfile,">","$tftpdir/etc/".lc($_));
         print $cfgfile "default xCAT\n";
         print $cfgfile "   label xCAT\n";
         print $cfgfile "   kernel http://".$hexnets->{$_}.":80/$tftpdir/xcat/genesis.kernel.$arch\n";
         print $cfgfile "   initrd http://".$hexnets->{$_}.":80/$initrd_file\n";
         print $cfgfile '   append "quiet xcatd='.$hexnets->{$_}.":$xcatdport $consolecmdline\"\n";
         close($cfgfile);
      }
   }


   

}

1;
