# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::centos;
use Storable qw(dclone);
use Sys::Syslog;
use xCAT::Table;
use Cwd;
use File::Copy;
use xCAT::Template;
use xCAT::Postage;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;

my %distnames = (
  "1176234647.982657" => "centos5",
  "1156364963.862322" => "centos4.4",
  "1178480581.024704" => "centos4.5",
  "1195929648.203590" => "centos5.1"
  );
my %numdiscs = (
  "1156364963.862322" => 4,
  "1178480581.024704" => 3
  );

sub handled_commands {
  return {
    copycd => "centos",
    mknetboot => "nodetype:os=centos.*",
    mkinstall => "nodetype:os=centos.*",
  }
}
  
sub process_request {
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my $distname = undef;
  my $arch = undef;
  my $path = undef;
  if ($request->{command}->[0] eq 'copycd') { 
    return copycd($request,$callback,$doreq);
  } elsif ($request->{command}->[0] eq 'mkinstall') {
    return mkinstall($request,$callback,$doreq);
  } elsif ($request->{command}->[0] eq 'mknetboot') {
    return mknetboot($request,$callback,$doreq);
  }
}

sub mknetboot {
    my $req = shift;
    my $callback = shift;
    my $doreq = shift;
    my $tftpdir = "/tftpboot";
    my $nodes = @{$request->{node}};
    my @args=@{$req->{arg}};
    my @nodes = @{$req->{node}};
    my $ostab = xCAT::Table->new('nodetype');
    my $sitetab = xCAT::Table->new('site');
    my $installroot;
    if ($sitetab) { 
        (my $ref) = $sitetab->getAttribs({key=>installdir},value);
        print Dumper($ref);
        if ($ref and $ref->{value}) {
            $installroot = $ref->{value};
        }
    }
    foreach $node (@nodes) {
        my $ent = $ostab->getNodeAttribs($node,['os','arch','profile']);
        unless ($ent->{os} and $ent->{arch} and $ent->{profile}) {
            $callback->({error=>["Insufficient nodetype entry for $node"],errorcode=>[1]});
            next;
        }
        my $osver = $ent->{os};
        my $arch = $ent->{arch};
        my $profile = $ent->{profile};
        unless (-r "/$installroot/netboot/$osver/$arch/$profile/kernel" and -r "$installroot/netboot/$osver/$arch/$profile/rootimg.gz") {
            makenetboot($osver,$arch,$profile,$installroot,$callback);
            mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            copy("/$installroot/netboot/$osver/$arch/$profile/kernel","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            copy("/$installroot/netboot/$osver/$arch/$profile/rootimg.gz","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        }
        unless (-r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel" and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/rootimg.gz") {
            mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            copy("/$installroot/netboot/$osver/$arch/$profile/kernel","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            copy("/$installroot/netboot/$osver/$arch/$profile/rootimg.gz","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        }
        unless (-r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel" and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/rootimg.gz") {
            $callback->({error=>["Netboot image creation failed for $node"],errorcode=>[1]});
            next;
        }
        my $restab = xCAT::Table->new('noderes');
        my $hmtab = xCAT::Table->new('nodehm');
        my $ent = $restab->getNodeAttribs($node,['serialport','primarynic']);
        my $kcmdline;
        if (defined $ent->{serialport}) {
            my $sent = $hmtab->getNodeAttribs($node,['serialspeed','serialflow']);
            unless ($sent->{serialspeed}) {
                $callback->({error=>["serialport defined, but no serialspeed for $node in nodehm table"],errorcode=>[1]});
                next;
            }
            $kcmdline .= "console=ttyS".$ent->{serialport}.",".$sent->{serialspeed};
            if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/) {
                $kcmdline .= "n8r";
            }
        }
        $restab->setNodeAttribs($node,{
           kernel=>"xcat/netboot/$osver/$arch/$profile/kernel",
           initrd=>"xcat/netboot/$osver/$arch/$profile/rootimg.gz",
           kcmdline=>$kcmdline
        });
    }
}
sub makenetboot {
    my $osver = shift;
    my $arch = shift;
    my $profile = shift;
    my $installroot = shift;
    my $callback = shift;
    unless ($installroot) {
        $callback->({error=>["No installdir defined in site table"],errorcode=>[1]});
        return;
    }
    my $srcdir = "/$installroot/$osver/$arch";
    unless ( -d $srcdir."/repodata" ) {
        $callback->({error=>["copycds has not been run for $osver/$arch"],errorcode=>[1]});
        return;
    }
    my $yumconf;
    open($yumconf,">","/tmp/mknetboot.$$.yum.conf");
    print $yumconf "[$osver-$arch]\nname=$osver-$arch\nbaseurl=file:///$srcdir\ngpgcheck=0\n";
    close($yumconf);
    system("yum -y -c /tmp/mknetboot.$$.yum.conf --installroot=$installroot/netboot/$osver/$arch/$profile/rootimg/ --disablerepo=* --enablerepo=$osver-$arch install bash dhclient kernel openssh-server openssh-clients dhcpv6_client vim-minimal");
    my $cfgfile;
    open($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/fstab");
    print $cfgfile "devpts  /dev/pts    devpts  gid=5,mode=620 0 0\n";
    print $cfgfile "tmpfs   /dev/shm    tmpfs   defaults    0 0\n";
    print $cfgfile "proc    /proc   proc    defaults    0 0\n";
    print $cfgfile "sysfs   /sys    sysfs   defaults    0 0\n";
    close($cfgfile);
    open ($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network");
    print $cfgfile "NETWORKING=yes\n";
    close($cfgfile);
    open ($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network-scripts/ifcfg-eth0");
    print $cfgfile "ONBOOT=yes\nBOOTPROTO=dhcp\nDEVICE=eth0\n";
    close($cfgfile);
    open ($cfgfile,">","$installroot/netboot/$osver/$arch/$profile/rootimg/etc/sysconfig/network-scripts/ifcfg-eth1");
    print $cfgfile "ONBOOT=yes\nBOOTPROTO=dhcp\nDEVICE=eth1\n";
    close($cfgfile);
    link("$installroot/netboot/$osver/$arch/$profile/rootimg/sbin/init","$installroot/netboot/$osver/$arch/$profile/rootimg/init");
    rename(<$installroot/netboot/$osver/$arch/$profile/rootimg/boot/vmlinuz*>,"$installroot/netboot/$osver/$arch/$profile/kernel");
    if (-d "$installroot/postscripts/hostkeys") {
        for my $key (<$installroot/postscripts/hostkeys/*key>) {
            copy ($key,"$installroot/netboot/$osver/$arch/$profile/rootimg/etc/ssh/");
        }
        chmod 0600,</$installroot/netboot/$osver/$arch/$profile/rootimg/etc/ssh/*key>;
    }
    if (-d "/$installroot/postscripts/.ssh") {
        mkpath("/$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh");
        chmod(0700,"/$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh/");
        for my $file (</$installroot/postscripts/.ssh/*>) {
            copy ($file,"/$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh/");
        }
        chmod(0600,</$installroot/netboot/$osver/$arch/$profile/rootimg/root/.ssh/*>);
    }
    my $oldpath=cwd;
    chdir("$installroot/netboot/$osver/$arch/$profile/rootimg");
    system("find . '!' -wholename './usr/share/man*' -a '!' -wholename './usr/share/locale*' -a '!' -wholename './usr/share/i18n*' -a '!' -wholename './var/cache/yum*' -a '!' -wholename './usr/share/doc*' -a '!' -wholename './usr/lib/locale*' -a '!' -wholename './boot*' |cpio -H newc -o | gzip -c - > ../rootimg.gz");
    chdir($oldpath);
}

sub mkinstall {
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my @nodes = @{$request->{node}};
  my $node;
  my $ostab = xCAT::Table->new('nodetype');
  my %doneimgs;
  foreach $node (@nodes) {
    my $osinst;
    my $ent = $ostab->getNodeAttribs($node,['profile','os','arch']);
    unless ($ent->{os} and $ent->{arch} and $ent->{profile}) {
      $callback->({error=>["No profile defined in nodetype for $node"],errorcode=>[1]});
      next; #No profile
    }
    my $os = $ent->{os};
    my $arch = $ent->{arch};
    my $profile = $ent->{profile};
    unless (-r $::XCATROOT."/share/xcat/install/centos/".$ent->{profile}.".tmpl") {
      $callback->({error=>["No kickstart template exists for ".$ent->{profile}],errorcode=>[1]});
      next;
    }
    #Call the Template class to do substitution to produce a kickstart file in the autoinst dir
    xCAT::Template->subvars($::XCATROOT."/share/xcat/install/centos/".$ent->{profile}.".tmpl","/install/autoinst/".$node,$node);
    mkpath "/install/postscripts/";
    xCAT::Postage->writescript($node,"/install/postscripts/".$node);
    if (-r "/install/$os/$arch/images/pxeboot/vmlinuz" 
      and -r  "/install/$os/$arch/images/pxeboot/initrd.img") {
      #TODO: driver slipstream, targetted for network.
      unless ($doneimgs{"$os|$arch"}) {
        mkpath("/tftpboot/xcat/$os/$arch");
        copy("/install/$os/$arch/images/pxeboot/vmlinuz","/tftpboot/xcat/$os/$arch/");
        copy("/install/$os/$arch/images/pxeboot/initrd.img","/tftpboot/xcat/$os/$arch/");
        $doneimgs{"$os|$arch"}=1;
      }
      #We have a shot...
      my $restab = xCAT::Table->new('noderes');
      my $hmtab = xCAT::Table->new('nodehm');
      my $ent = $restab->getNodeAttribs($node,['nfsserver','serialport','primarynic','installnic']);
      my $sent = $hmtab->getNodeAttribs($node,['serialspeed','serialflow']);
      unless ($ent and $ent->{nfsserver}) {
        $callback->({error=>["No noderes.nfsserver defined for ".$node],errorcode=>[1]});
        next;
      }
      my $kcmdline="nofb utf8 ks=http://".$ent->{nfsserver}."/install/autoinst/".$node;
      if ($ent->{installnic}) {
        $kcmdline.=" ksdevice=".$ent->{installnic};
      } elsif ($ent->{primarynic}) { 
        $kcmdline.=" ksdevice=".$ent->{primarynic};
      } else {
        $kcmdline .= " ksdevice=eth0";
      }

      #TODO: dd=<url> for driver disks
      if (defined($ent->{serialport})) {
        unless ($sent->{serialspeed}) {
          $callback->({error=>["serialport defined, but no serialspeed for $node in nodehm table"],errorcode=>[1]});
          next;
        }
        $kcmdline.=" console=ttyS".$ent->{serialport}.",".$sent->{serialspeed};
        if ($sent->{serialflow} =~ /(hard|cts|ctsrts)/) {
          $kcmdline .= "n8r";
        }
      }
      $kcmdline .= " noipv6";
      
      $restab->setNodeAttribs($node,{
        kernel=>"xcat/$os/$arch/vmlinuz",
        initrd=>"xcat/$os/$arch/initrd.img",
        kcmdline=>$kcmdline
      });
    } else {
      $callback->({error=>["Unable to find kernel and initrd for $os and $arch in install source /install/$os/$arch"],errorcode=>[1]});
    }
  }
}

sub copycd {
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my $installroot;
  my $sitetab = xCAT::Table->new('site');
  if ($sitetab) { 
    (my $ref) = $sitetab->getAttribs({key=>installdir},value);
    print Dumper($ref);
    if ($ref and $ref->{value}) {
      $installroot = $ref->{value};
    }
  }

  @ARGV= @{$request->{arg}};
  GetOptions(
    'n=s' => \$distname,
    'a=s' => \$arch,
    'p=s' => \$path
  );
  unless ($path) {
    #this plugin needs $path...
    return;
  }
  if ($distname and $distname !~ /^centos/) {
    #If they say to call it something other than CentOS, give up?
    return;
  }
  unless (-r $path."/.discinfo") {
    return;
  }
  my $dinfo;
  open($dinfo,$path."/.discinfo");
  my $did = <$dinfo>;
  chomp($did);
  my $desc = <$dinfo>;
  chomp($desc);
  my $darch = <$dinfo>;
  chomp($darch);
  if ($darch and $darch =~ /i.86/) {
    $darch = "x86";
  }
  close($dinfo);
  if ($distnames{$did}) {
    unless ($distname) {
      $distname = $distnames{$did};
    }
  } elsif ($desc =~ /^Final$/) {
    unless ($distname) {
      $distname = "centos5";
    }
  } elsif ($desc =~ /^CentOS-4 .*/) {
    unless ($distname) {
      $distname = "centos4";
    }
  }

  unless ($distname) {
    return; #Do nothing, not ours..
  }
  if ($darch) {
    unless ($arch) { 
      $arch = $darch;
    }
    if ($arch and $arch ne $darch) {
      $callback->({error=>"Requested CentOS architecture $arch, but media is $darch"});
      return;
    }
  }
  %{$request} = (); #clear request we've got it.

  $callback->({data=>"Copying media to $installroot/$distname/$arch/"});
  my $omask=umask 0022;
  mkpath("$installroot/$distname/$arch");
  umask $omask;
  my $rc = system("cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch");
  chmod 0755,"$installroot/$distname/$arch";
  if ($rc != 0) {
    $callback->({error=>"Media copy operation failed, status $rc"});
  } else {
    $callback->({data=>"Media copy operation successful"});
  }
}

1;
