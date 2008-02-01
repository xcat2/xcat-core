# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::fedora;
use Storable qw(dclone);
use Sys::Syslog;
use DBI;
use xCAT::Table;
use xCAT::Template;
use xCAT::Postage;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;

my %discids = (
  "1194015916.783841" => "fedora8",
  );

sub handled_commands {
  return {
    copycd => "fedora",
    mkinstall => "nodetype:os=fedora.*",
    mknetboot => "nodetype:os=fedora.*"
  }
}
  
sub preprocess_request {
   my $req = shift;
   my $callback = shift;
  if ($req->{command}->[0] eq 'copycd') {  #don't farm out copycd
     return [$req];
  }
  my %localnodehash;
  my %dispatchhash;
  my $nrtab = xCAT::Table->new('noderes');
  foreach my $node (@{$req->{node}}) {
     my $nodeserver;
     my $tent = $nrtab->getNodeAttribs($node,['tftpserver']);
     if ($tent) { $nodeserver = $tent->{tftpserver} }
     unless ($tent and $tent->{tftpserver}) {
        $tent = $nrtab->getNodeAttribs($node,['servicenode']);
        if ($tent) { $nodeserver = $tent->{servicenode} }
     }
     if ($nodeserver) {
        $dispatchhash{$nodeserver}->{$node} = 1;
     } else {
        $localnodehash{$node} = 1;
     }
  }
  my @requests;
  my $reqc = {%$req};
  $reqc->{node} = [ keys %localnodehash ];
  if (scalar(@{$reqc->{node}})) { push @requests,$reqc }

  foreach my $dtarg (keys %dispatchhash) { #iterate dispatch targets
     my $reqcopy = {%$req}; #deep copy
     $reqcopy->{'_xcatdest'} = $dtarg;
     $reqcopy->{node} = [ keys %{$dispatchhash{$dtarg}}];
     push @requests,$reqcopy;
  }
  return \@requests;
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
  } elsif ($request->{command}->[0] eq 'packimage') {
         packimage($request,$callback,$doreq);
  } #$osver,$arch,$profile,$installroot,$callback);
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
    (my $sent) = $sitetab->getAttribs({key=>master},value);
    my $imgsrv;
    if ($sent and $sent->{value}) {
       $imgsrv = $sent->{value};
    }
    my $installroot;
    if ($sitetab) { 
        (my $ref) = $sitetab->getAttribs({key=>installdir},value);
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
         #packimage($osver,$arch,$profile,$installroot,$callback);
         unless (-r "/$installroot/netboot/$osver/$arch/$profile/rootimg.gz" and
         -r "/$installroot/netboot/$osver/$arch/$profile/kernel" and
         -r  "/$installroot/netboot/$osver/$arch/$profile/initrd.gz") {
            $callback->({error=>["No packed image for platform $osver, architecture $arch, profile $profile, please run packimage -o $osver -p $profile -a $arch"],errorcode=>[1]});
            next;
         }
         mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
         #TODO: only copy if newer..
         copy("/$installroot/netboot/$osver/$arch/$profile/kernel","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
         copy("/$installroot/netboot/$osver/$arch/$profile/initrd.gz","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
         #copy("/$installroot/netboot/$osver/$arch/$profile/rootimg.gz","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
         unless (-r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel" and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/initrd.gz") {
            $callback->({error=>["Copying to /$tftpdir/xcat/netboot/$osver/$arch/$profile failed"],errorcode=>[1]});
            next;
            #mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            #copy("/$installroot/netboot/$osver/$arch/$profile/kernel","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            #copy("/$installroot/netboot/$osver/$arch/$profile/rootimg.gz","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        }
        my $restab = xCAT::Table->new('noderes');
        my $hmtab = xCAT::Table->new('nodehm');
        my $ent = $restab->getNodeAttribs($node,['serialport','primarynic']);
        my $ient = $restab->getNodeAttribs($node,['servicenode']);
        if ($ient and $ient->{servicenode}) {
           $imgsrv = $ient->{servicenode};
        }
        unless ($imgsrv) {
           $callback->({error=>["Unable to determine image server for $node"]});
           next;
        }
        my $kcmdline = "imgurl=$imgsrv/install/netboot/$osver/$arch/$profile/rootimg.gz ";
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
           initrd=>"xcat/netboot/$osver/$arch/$profile/initrd.gz",
           kcmdline=>$kcmdline
        });
    }
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
    unless (-r $::XCATROOT."/share/xcat/install/fedora/".$ent->{profile}.".tmpl" or 
            -r $::XCATROOT."/share/xcat/install/fedora/$profile.$arch.tmpl" or
            -r $::XCATROOT."/share/xcat/install/fedora/$profile.$os.tmpl" or
            -r $::XCATROOT."/share/xcat/install/fedora/$profile.$os.$arch.tmpl") {
      $callback->({error=>["No kickstart template exists for ".$ent->{profile}],errorcode=>[1]});
      next;
    }
    #Call the Template class to do substitution to produce a kickstart file in the autoinst dir
    
    if ( -r $::XCATROOT."/share/xcat/install/fedora/$profile.$os.$arch.tmpl" ) { 
       xCAT::Template->subvars($::XCATROOT."/share/xcat/install/fedora/$profile.$os.$arch.tmpl","/install/autoinst/".$node,$node);
    } elsif ( -r $::XCATROOT."/share/xcat/install/fedora/$profile.$arch.tmpl" ) { 
       xCAT::Template->subvars($::XCATROOT."/share/xcat/install/fedora/$profile.$arch.tmpl","/install/autoinst/".$node,$node);
    } elsif ( -r $::XCATROOT."/share/xcat/install/fedora/$profile.$os.tmpl" ) { 
       xCAT::Template->subvars($::XCATROOT."/share/xcat/install/fedora/$profile.$os.tmpl","/install/autoinst/".$node,$node);
    } else {
       xCAT::Template->subvars($::XCATROOT."/share/xcat/install/fedora/".$ent->{profile}.".tmpl","/install/autoinst/".$node,$node);
    }
    mkpath "/install/postscripts/";
    xCAT::Postage->writescript($node,"/install/postscripts/".$node);
    if (($arch =~ /x86/ and 
      (-r "/install/$os/$arch/images/pxeboot/vmlinuz" and -r  "/install/$os/$arch/images/pxeboot/initrd.img")) 
      or $arch =~ /ppc/ and 
      (-r "/install/$os/$arch/ppc/ppc64/vmlinuz" and -r "/install/$os/$arch/ppc/ppc64/ramdisk.image.gz")) {
      unless ($doneimgs{"$os|$arch"}) {
      #TODO: driver slipstream, targetted for network.
        mkpath("/tftpboot/xcat/$os/$arch");
        if ($arch =~ /x86/) {
           copy("/install/$os/$arch/images/pxeboot/vmlinuz","/tftpboot/xcat/$os/$arch/");
           copy("/install/$os/$arch/images/pxeboot/initrd.img","/tftpboot/xcat/$os/$arch/");
        } elsif ($arch =~ /ppc/) {
           copy("/install/$os/$arch/ppc/ppc64/vmlinuz","/tftpboot/xcat/$os/$arch/");
           copy("/install/$os/$arch/ppc/ppc64/ramdisk.image.gz","/tftpboot/xcat/$os/$arch/initrd.img");
        } else {
            $callback->({error=>["Plugin doesn't know how to handle architecture $arch"],errorcode=>[1]});
            next;
        }
        $doneimgs{"$os|$arch"}=1;
      }
      #We have a shot...
      my $restab = xCAT::Table->new('noderes');
      my $ent = $restab->getNodeAttribs($node,['nfsserver','serialport','primarynic','installnic']);
      my $hmtab = xCAT::Table->new('nodehm');
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
      if (defined $ent->{serialport}) {
        unless ($sent->{serialspeed}) {
          $callback->({error=>["serialport defined, but no serialspeed for $node in nodehm table"],errorcode=>[1]});
          next;
        }
        $kcmdline.=" console=ttyS".$ent->{serialport}.",".$sent->{serialspeed};
        if ($sent->{serialflow} =~ /(ctsrts|cts|hard)/) {
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
      print "$arch is arch and /install/$os/$arch/images/pxeboot/vmlinuz and /install/$os/$arch/images/pxeboot/initrd.img\n";
        $callback->({error=>["Install image not found in /install/$os/$arch"],errorcode=>[1]});
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
  if ($distname and $distname !~ /^fedora/) {
    #If they say to call it something other than Fedora, give up?
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
  if ($discids{$did}) {
      unless ($distname) {
          $distname = $discids{$did};
      }
  }
  if ($desc =~ /^Fedora 8$/) {
    unless ($distname) {
      $distname = "fedora8";
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
      $callback->({error=>"Requested Fedora architecture $arch, but media is $darch"});
      return;
    }
    if ($arch =~ /ppc/) { $arch = "ppc64" };
  }
  %{$request} = (); #clear request we've got it.

  $callback->({data=>"Copying media to $installroot/$distname/$arch/"});
  my $omask=umask 0022;
  mkpath("$installroot/$distname/$arch");
  umask $omask;
  #my $rc = system("cd $path; find . | cpio -dump $installroot/$distname/$arch");
  my $rc = system("cd $path;rsync -a . $installroot/$distname/$arch/");
  chmod 0755,"$installroot/$distname/$arch";
  my $repomdfile;
  my $primaryxml;
  my @xmlines;
  my $oldsha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.xml.gz`;
  my $olddbsha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.sqlite.bz2`;
  $oldsha =~ s/\s.*//;
  chomp($oldsha);
  $olddbsha =~ s/\s.*//;
  chomp($olddbsha);
  unlink("$installroot/$distname/$arch/repodata/primary.sqlite");
  unlink("$installroot/$distname/$arch/repodata/primary.xml");
  system("/usr/bin/bunzip2  $installroot/$distname/$arch/repodata/primary.sqlite.bz2");
  system("/bin/gunzip  $installroot/$distname/$arch/repodata/primary.xml.gz");
  my $oldopensha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.xml`;
  $oldopensha =~ s/\s+.*//;
  chomp($oldopensha);
  my $olddbopensha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.sqlite`;
  $olddbopensha =~ s/\s+.*//;
  chomp($olddbopensha);
  my $pdbh = DBI->connect("dbi:SQLite:$installroot/$distname/$arch/repodata/primary.sqlite","","",{AutoCommit=>1});
  $pdbh->do('UPDATE "packages" SET "location_base" = NULL');
  $pdbh->disconnect;
  open($primaryxml,"+<$installroot/$distname/$arch/repodata/primary.xml");
  while (<$primaryxml>) {
     s!xml:base="media://[^"]*"!!g;
     push @xmlines,$_;
  }
  seek($primaryxml,0,0);
  print $primaryxml (@xmlines);
  truncate($primaryxml,tell($primaryxml));
  @xmlines=();
  close($primaryxml);
  my $newopensha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.xml`;
  my $newdbopensha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.sqlite`;
  system("/bin/gzip $installroot/$distname/$arch/repodata/primary.xml");
  system("/usr/bin/bzip2 $installroot/$distname/$arch/repodata/primary.sqlite");
  my $newsha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.xml.gz`;
  my $newdbsha=`/usr/bin/sha1sum $installroot/$distname/$arch/repodata/primary.sqlite.bz2`;
  $newopensha =~ s/\s.*//;
  $newdbopensha =~ s/\s.*//;
  $newsha =~ s/\s.*//;
  $newdbsha =~ s/\s.*//;
  chomp($newopensha);
  chomp($newdbopensha);
  chomp($newsha);
  chomp($newdbsha);
  open($primaryxml,"+<$installroot/$distname/$arch/repodata/repomd.xml");
  while (<$primaryxml>) { 
     s!xml:base="media://[^"]*"!!g;
     s!$oldsha!$newsha!g;
     s!$oldopensha!$newopensha!g;
     s!$olddbsha!$newdbsha!g;
     s!$olddbopensha!$newdbopensha!g;
     push @xmlines,$_;
  }
  seek($primaryxml,0,0);
  print $primaryxml (@xmlines);
  truncate($primaryxml,tell($primaryxml));
  close($primaryxml);
  if ($rc != 0) {
    $callback->({error=>"Media copy operation failed, status $rc"});
  } else {
    $callback->({data=>"Media copy operation successful"});
  }
}

1;
