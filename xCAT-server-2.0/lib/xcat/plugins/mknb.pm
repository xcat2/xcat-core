package xCAT_plugin::mknb;
use File::Temp qw(tempdir);
use xCAT::Utils;
use File::Path;
use File::Copy;
use Data::Dumper;

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
      my $portent = $sitetab->getAttribs({key=>'defserialport'});
      if ($portent and defined($portent->{value})) {
         $serialport=$portent->{value};
      }
      $portent = $sitetab->getAttribs({key=>'defserialspeed'});
      if ($portent and defined($portent->{value})) {
         $serialspeed=$portent->{value};
      }
      $portent = $sitetab->getAttribs({key=>'defserialflow'});
      if ($portent and defined($portent->{value})) {
         $serialflow=$portent->{value};
      }
      $portent = $sitetab->getAttribs({key=>'xcatdport'});
      if ($portent and defined($portent->{value})) {
         $xcatdport=$portent->{value};
      }
      $sitetab->close;
   }

   my $installdir = "/install";
   my $tftpdir = "/tftpboot";
   if (scalar(@{$request->{arg}}) != 1) {
      $callback->({error=>Dumper($request)." Need to specifiy architecture (x86_64 or ppc64)"},{errorcode=>[1]});
      return;
   }
   my $arch = $request->{arg}->[0];
   unless (-d "$::XCATROOT/share/xcat/netboot/$arch") {
      $callback->({error=>"Unable to find directory $::XCATROOT/share/xcat/netboot/$arch",errorcode=>[1]});
      return;
   }
   unless ( -r "/root/.ssh/id_rsa.pub" ) {
      $callback->({data=>["Generating ssh private key for root"]});
      my $rc=system('ssh-keygen -t rsa -q -b 2048 -N "" -f  /root/.ssh/id_rsa');
      if ($rc) {
         $callback->({error=>["Failure executing ssh-keygen for root"],errorcode=>[1]});
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
   copy("/root/.ssh/id_rsa.pub","$tempdir/root/.ssh/authorized_keys");
   if (-r "$installdir/postscripts/hostkeys/ssh_host_key") {
      copy("$installdir/postscripts/hostkeys/ssh_host_key","$tempdir/etc/ssh_host_key");
      copy("$installdir/postscripts/hostkeys/ssh_host_rsa_key","$tempdir/etc/ssh_host_rsa_key");
      copy("$installdir/postscripts/hostkeys/ssh_host_dsa_key","$tempdir/etc/ssh_host_dsa_key");
   }
   unless (-r "$tempdir/etc/ssh_host_key") {
      system("ssh-keygen -t rsa1 -f $tempdir/etc/ssh_host_key -C '' -N ''");
      system("ssh-keygen -t rsa -f $tempdir/etc/ssh_host_rsa_key -C '' -N ''");
      system("ssh-keygen -t dsa -f $tempdir/etc/ssh_host_dsa_key -C '' -N ''");
   }
   $callback->({data=>["Creating nbfs.$arch.gz in $tftpdir/xcat"]});
   system("cd $tempdir; find . | cpio -o -H newc | gzip -9 > $tftpdir/xcat/nbfs.$arch.gz");
   system ("rm -rf $temdir");
   my $hexnets = xCAT::Utils->my_hexnets();
   my $consolecmdline;
   if ($serialport and $serialspeed) {
       $consolecmdline = "console=ttyS$serialport,$serialspeed";
      if ($serialflow =~ /cts/ or $serialflow =~ /hard/) {
         $consolecmdline .= "n8r";
      } 
   }
   my $cfgfile;
   foreach (keys %{$hexnets}) {
      if ($arch =~ /x86/) {
         open($cfgfile,">","$tftpdir/pxelinux.cfg/".uc($_));
         print $cfgfile "DEFAULT xCAT\n";
         print $cfgfile "  LABEL xCAT\n";
         print $cfgfile "  KERNEL xcat/nbk.$arch\n";
         print $cfgfile "  APPEND initrd=xcat/nbfs.$arch.gz xcatd=".$hexnets->{$_}.":$xcatdport $consolecmdline\n";
         close($cfgfile);
      } elsif ($arch =~ /ppc/) {
         open($cfgfile,">","$tftpdir/etc/".lc($_));
         print $cfgfile "timeout=5\n";
         print $cfgfile "label=xcat\n";
         print $cfgfile "image=xcat/nbk.$arch\n";
         print $cfgfile "initrd=xcat/nbfs.$arch.gz\n";
         print $cfgfile 'append="xcatd='.$hexnets->{$_}.":$xcatdport $consolecmdline\n";
         close($cfgfile);
      }
   }


   

}

1;
