package xCAT_plugin::mknb;
use strict;
use File::Temp qw(tempdir);
use xCAT::Utils;
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
   my $sitetab = xCAT::Table->new('site');
   my $serialport;
   my $serialspeed;
   my $serialflow;
   my $xcatdport = 3001;
   if ($sitetab) {
      my $portent = $sitetab->getAttribs({key=>'defserialport'},'value');
      if ($portent and defined($portent->{value})) {
         $serialport=$portent->{value};
      }
      $portent = $sitetab->getAttribs({key=>'defserialspeed'},'value');
      if ($portent and defined($portent->{value})) {
         $serialspeed=$portent->{value};
      }
      $portent = $sitetab->getAttribs({key=>'defserialflow'},'value');
      if ($portent and defined($portent->{value})) {
         $serialflow=$portent->{value};
      }
      $portent = $sitetab->getAttribs({key=>'xcatdport'},'value');
      if ($portent and defined($portent->{value})) {
         $xcatdport=$portent->{value};
      }
      $sitetab->close;
   }

   my $installdir = "/install";
   my $tftpdir = "/tftpboot";
   if (scalar(@{$request->{arg}}) != 1) {
      $callback->({error=>"Need to specifiy architecture (x86, x86_64 or ppc64)"},{errorcode=>[1]});
      return;
   }
   my $arch = $request->{arg}->[0];
   unless (-d "$::XCATROOT/share/xcat/netboot/$arch") {
      $callback->({error=>"Unable to find directory $::XCATROOT/share/xcat/netboot/$arch",errorcode=>[1]});
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
   my $rc = system("cp -a $::XCATROOT/share/xcat/netboot/$arch/nbroot/* $tempdir");
   if ($rc) {
      system("rm -rf $tempdir");
      $callback->({error=>["Failed to copy  $::XCATROOT/share/xcat/netboot/$arch/nbroot/ contents"],errorcode=>[1]});
      return;
   }
   mkpath($tempdir."/root/.ssh");
   chmod(0700,$tempdir."/root/.ssh");
   copy("/root/.ssh/id_rsa.pub","$tempdir/root/.ssh/authorized_keys");
   chmod(0600,"$tempdir/root/.ssh/authorized_keys");
   if (-r "/etc/xcat/hostkeys/ssh_host_key") {
    copy("/etc/xcat/hostkeys/ssh_host_key","$tempdir/etc/ssh_host_key");
    copy("/etc/xcat/hostkeys/ssh_host_rsa_key","$tempdir/etc/ssh_host_rsa_key");
    copy("/etc/xcat/hostkeys/ssh_host_dsa_key","$tempdir/etc/ssh_host_dsa_key");
      chmod(0600,<$tempdir/etc/ssh_*>);
   }
   unless (-r "$tempdir/etc/ssh_host_key") {
      system("ssh-keygen -t rsa1 -f $tempdir/etc/ssh_host_key -C '' -N ''");
      system("ssh-keygen -t rsa -f $tempdir/etc/ssh_host_rsa_key -C '' -N ''");
      system("ssh-keygen -t dsa -f $tempdir/etc/ssh_host_dsa_key -C '' -N ''");
   }
   $callback->({data=>["Creating nbfs.$arch.gz in $tftpdir/xcat"]});
   system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/nbfs.$arch.gz");
   system ("rm -rf $tempdir");
   my $hexnets = xCAT::Utils->my_hexnets();
   my $normnets = xCAT::Utils->my_nets();
   my $consolecmdline;
   if (defined($serialport) and $serialspeed) {
       $consolecmdline = "console=ttyS$serialport,$serialspeed";
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
      mkpath("$tftpdir/etc");
      if (! -r "$tftpdir/yaboot") {
          $callback->({error=>["Unable to locate yaboot to boot ppc clients, install yaboot-xcat"],errorcode=>[1]});
      }
   }
   my $dopxe=0;
   foreach (keys %{$normnets}) {
      my $net = $_;
      $net =~s/\//_/;
      $dopxe=0;
      if ($arch =~ /x86/) { #only do pxe if just x86 or x86_64 and no x86
          if ($arch =~ /x86_64/) {
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
         print $cfg 'imgfetch -n kernel http://${next-server}/tftpboot/xcat/nbk.'."$arch quiet xcatd=".$normnets->{$_}.":$xcatdport $consolecmdline\n";
         print $cfg 'imgfetch -n nbfs http://${next-server}/tftpboot/xcat/nbfs.'."$arch.gz\n";
         print $cfg "imgload kernel\n";
         print $cfg "imgexec kernel\n";
         close($cfg);
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
         print $cfgfile "timeout=5\n";
         print $cfgfile "   label=xcat\n";
         print $cfgfile "   image=xcat/nbk.$arch\n";
         print $cfgfile "   initrd=xcat/nbfs.$arch.gz\n";
         print $cfgfile '   append="quiet xcatd='.$hexnets->{$_}.":$xcatdport $consolecmdline\"\n";
         close($cfgfile);
      }
   }


   

}

1;
