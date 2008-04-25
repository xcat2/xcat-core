# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::anaconda;
use Storable qw(dclone);
use Sys::Syslog;
use Thread qw(yield);
use POSIX qw(WNOHANG nice);
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::Yum;
use xCAT::Template;
use xCAT::Postage;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;
my $cpiopid;

my %distnames = (
  "1176234647.982657" => "centos5",
  "1156364963.862322" => "centos4.4",
  "1178480581.024704" => "centos4.5",
  "1195929648.203590" => "centos5.1",
  "1195929637.060433" => "centos5.1",
  "1195488871.805863" => "centos4.6",
  "1195487524.127458" => "centos4.6",
  "1170973598.629055" => "rhelc5",
  "1170978545.752040" => "rhels5",
  "1192660014.052098" => "rhels5.1",
  "1192663619.181374" => "rhels5.1",
  "1194015916.783841" => "fedora8",
  );
my %numdiscs = (
  "1156364963.862322" => 4,
  "1178480581.024704" => 3
  );

sub handled_commands {
  return {
    copycd => "anaconda",
    mknetboot => "nodetype:os=(centos.*)|(rh.*)|(fedora.*)",
    mkinstall => "nodetype:os=(centos.*)|(rh.*)|(fedora.*)",
  };
}
  
sub preprocess_request
{
   my $req      = shift;
   my $callback = shift;
   if ($req->{command}->[0] eq 'copycd')
   {    #don't farm out copycd
      return [$req];
   }
   my %localnodehash;
   my %dispatchhash;
   my $nrtab = xCAT::Table->new('noderes');
   foreach my $node (@{$req->{node}})
   {
      my $nodeserver;
      my $tent = $nrtab->getNodeAttribs($node, ['tftpserver']);
      if ($tent) { $nodeserver = $tent->{tftpserver} }
      unless ($tent and $tent->{tftpserver})
      {
         $tent = $nrtab->getNodeAttribs($node, ['servicenode']);
         if ($tent) { $nodeserver = $tent->{servicenode} }
      }
      if ($nodeserver)
      {
         $dispatchhash{$nodeserver}->{$node} = 1;
      }
      else
      {
         $localnodehash{$node} = 1;
      }
   }
   my @requests;
   my $reqc = {%$req};
   $reqc->{node} = [keys %localnodehash];
   if (scalar(@{$reqc->{node}})) { push @requests, $reqc }

   foreach my $dtarg (keys %dispatchhash)
   {    #iterate dispatch targets
      my $reqcopy = {%$req};    #deep copy
         $reqcopy->{'_xcatdest'} = $dtarg;
      $reqcopy->{node} = [keys %{$dispatchhash{$dtarg}}];
      push @requests, $reqcopy;
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
    $installroot = "/install";

    (my $sent) = $sitetab->getAttribs({key=>master},value);
    my $imgsrv;
    if ($sent and $sent->{value}) {
       $imgsrv = $sent->{value};
    }
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
        my $platform;
        if ($osver =~ /rh.*/) {
           $platform = "rh";
        } elsif ($osver =~ /centos.*/) {
           $platform = "centos";
        } elsif ($osver =~ /fedora.*/) {
           $platform = "fedora";
        }
           
        my $arch = $ent->{arch};
        my $profile = $ent->{profile};
        my $suffix = 'gz';
        if (-r "/$installroot/netboot/$osver/$arch/$profile/rootimg.sfs") {
           $suffix = 'sfs';
        }
        if (-r "/$installroot/netboot/$osver/$arch/$profile/rootimg.nfs") {
           $suffix = 'nfs';
        }
        unless ((-r "/$installroot/netboot/$osver/$arch/$profile/rootimg.gz" or 
                -r "/$installroot/netboot/$osver/$arch/$profile/rootimg.sfs" or
                -r "/$installroot/netboot/$osver/$arch/$profile/rootimg.nfs") and
                -r "/$installroot/netboot/$osver/$arch/$profile/kernel" and
                -r "/$installroot/netboot/$osver/$arch/$profile/initrd.gz") {
               $callback->({error=>["No packed image for platform $osver, architecture $arch, and profile $profile, please run packimage (i.e.  packimage -o $osver -p $profile -a $arch"],errorcode=>[1]});
               next;
        }

		# create the node-specific post scripts
		mkpath "/install/postscripts/";
		xCAT::Postage->writescript($node,"/install/postscripts/".$node, "netboot", $callback);

        mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        #TODO: only copy if newer...
        copy("/$installroot/netboot/$osver/$arch/$profile/kernel","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        copy("/$installroot/netboot/$osver/$arch/$profile/initrd.gz","/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        unless (-r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel" and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/initrd.gz") {
           $callback->({error=>["Copying to /$tftpdir/xcat/netboot/$osver/$arch/$profile failed"],errorcode=>[1]});
           next;
        }
        my $restab = xCAT::Table->new('noderes');
        my $bptab = xCAT::Table->new('bootparams');
        my $hmtab = xCAT::Table->new('nodehm');
        my $ent = $restab->getNodeAttribs($node,['primarynic']);
        my $sent = $hmtab->getNodeAttribs($node,['serialport','serialspeed','serialflow']);
        my $ient = $restab->getNodeAttribs($node,['servicenode']);
        my $ipfn = xCAT::Utils->my_ip_facing($node);
        if ($ient and $ient->{servicenode}) { #Servicenode attribute overrides
           $imgsrv = $ient->{servicenode};
        } elsif ($ipfn) {
           $imgsrv = $ipfn; #guessing self is second best
        } # resort to master value in site table only if not local to node...
        unless ($imgsrv) {
           $callback->({error=>["Unable to determine or reasonably guess the image server for $node"],errorcode=>[1]});
           next;
        }
        my $kcmdline;
        if($suffix eq "nfs") {
          $kcmdline = "imgurl=nfs://$imgsrv/install/netboot/$osver/$arch/$profile/rootimg ";
        }
        else {
          $kcmdline = "imgurl=http://$imgsrv/install/netboot/$osver/$arch/$profile/rootimg.$suffix ";
        }
        if (defined $sent->{serialport}) {
         #my $sent = $hmtab->getNodeAttribs($node,['serialspeed','serialflow']);
         unless ($sent->{serialspeed}) {
            $callback->({error=>["serialport defined, but no serialspeed for $node in nodehm table"],errorcode=>[1]});
            next;
         }
         $kcmdline .= "console=ttyS".$sent->{serialport}.",".$sent->{serialspeed};
         if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/) {
            $kcmdline .= "n8r";
          }
        }
        $bptab->setNodeAttribs($node,{
           kernel=>"xcat/netboot/$osver/$arch/$profile/kernel",
           initrd=>"xcat/netboot/$osver/$arch/$profile/initrd.gz",
           kcmdline=>$kcmdline
        });
    }
	my $rc = xCAT::Utils->create_postscripts_tar();
	if ( $rc != 0 ) {
		xCAT::MsgUtils->message( "S", "Error creating postscripts tar file." );
	}
}

sub mkinstall {
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my @nodes = @{$request->{node}};
  my $installroot;
  $installroot = "/install";

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
    my $platform;
    if ($os =~ /rh.*/) {
       $platform = "rh";
    } elsif ($os =~ /centos.*/) {
      $platform = "centos";
    } elsif ($os =~ /fedora.*/) {
      $platform = "fedora";
    }
    unless (-r $::XCATROOT."/share/xcat/install/$platform/$profile.tmpl"
            or -r $::XCATROOT."/share/xcat/install/$platform/$profile.$arch.tmpl"
            or -r $::XCATROOT."/share/xcat/install/$platform/$profile.$os.tmpl"
            or -r $::XCATROOT."/share/xcat/install/$platform/$profile.$os.$arch.tmpl"
           ) {
      $callback->({error=>["No $platform kickstart template exists for ".$ent->{profile}],errorcode=>[1]});
      next;
    }
    #Call the Template class to do substitution to produce a kickstart file in the autoinst dir
    my $tmperr="Unable to find template in $::XCATROOT/share/xcat/install/$platform (for $profile/$os/$arc combination)";
    if (-r $::XCATROOT."/share/xcat/install/$platform/$profile.$os.$arch.tmpl") {
       $tmperr = xCAT::Template->subvars($::XCATROOT."/share/xcat/install/$platform/$profile.$os.$arch.tmpl","/$installroot/autoinst/".$node,$node);
    } elsif (-r $::XCATROOT."/share/xcat/install/$platform/$profile.$arch.tmpl") {
       $tmperr = xCAT::Template->subvars($::XCATROOT."/share/xcat/install/$platform/$profile.$arch.tmpl","/$installroot/autoinst/".$node,$node);
    } elsif (-r $::XCATROOT."/share/xcat/install/$platform/$profile.$os.tmpl") {
       $tmperr = xCAT::Template->subvars($::XCATROOT."/share/xcat/install/$platform/$profile.$os.tmpl","/$installroot/autoinst/".$node,$node);
    } elsif (-r $::XCATROOT."/share/xcat/install/$platform/$profile.tmpl") {
       $tmperr = xCAT::Template->subvars($::XCATROOT."/share/xcat/install/$platform/$profile.tmpl","/$installroot/autoinst/".$node,$node);
    }
    if ($tmperr) { 
       $callback->({node=>[{name=>[$node],error=>[$tmperr],errorcode=>[1]}]}); 
       next;
    }

	# create the node-specific post scripts
	mkpath "/install/postscripts/";
	xCAT::Postage->writescript($node,"/install/postscripts/".$node, "install", $callback);


    if (
      ($arch =~ /x86/ 
      and -r "/install/$os/$arch/images/pxeboot/vmlinuz" 
      and -r  "/install/$os/$arch/images/pxeboot/initrd.img"
      ) or ($arch =~ /ppc/ 
         and -r "/install/$os/$arch/ppc/ppc64/vmlinuz" 
         and -r "/install/$os/$arch/ppc/ppc64/ramdisk.image.gz"
      )) {
      #TODO: driver slipstream, targetted for network.
      unless ($doneimgs{"$os|$arch"}) {
        mkpath("/tftpboot/xcat/$os/$arch");
        if ($arch =~ /x86/) {
         copy("/install/$os/$arch/images/pxeboot/vmlinuz","/tftpboot/xcat/$os/$arch/");
         copy("/install/$os/$arch/images/pxeboot/initrd.img","/tftpboot/xcat/$os/$arch/");
        } elsif ( $arch =~ /ppc/ ) {
            copy( "/install/$os/$arch/ppc/ppc64/vmlinuz","/tftpboot/xcat/$os/$arch/" );
            copy("/install/$os/$arch/ppc/ppc64/ramdisk.image.gz","/tftpboot/xcat/$os/$arch/initrd.img");
        } else {
           $callback->({error=> ["Can not handle architecture $arch"], errorcode => [1]});
           next;
        }
        $doneimgs{"$os|$arch"}=1;
      }
      #We have a shot...
      my $restab = xCAT::Table->new('noderes');
      my $bptab = xCAT::Table->new('bootparams');
      my $hmtab = xCAT::Table->new('nodehm');
      my $ent = $restab->getNodeAttribs($node,['nfsserver','primarynic','installnic']);
      my $sent = $hmtab->getNodeAttribs($node,['serialport','serialspeed','serialflow']);
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
      if (defined($sent->{serialport})) {
        unless ($sent->{serialspeed}) {
          $callback->({error=>["serialport defined, but no serialspeed for $node in nodehm table"],errorcode=>[1]});
          next;
        }
        $kcmdline.=" console=ttyS".$sent->{serialport}.",".$sent->{serialspeed};
        if ($sent->{serialflow} =~ /(hard|cts|ctsrts)/) {
          $kcmdline .= "n8r";
        }
      }
      $kcmdline .= " noipv6";
      
      $bptab->setNodeAttribs($node,{
        kernel=>"xcat/$os/$arch/vmlinuz",
        initrd=>"xcat/$os/$arch/initrd.img",
        kcmdline=>$kcmdline
      });
    } else {
      $callback->({error=>["Install image not found in /install/$os/$arch"],errorcode=>[1]});
    }
  }
  my $rc = xCAT::Utils->create_postscripts_tar();
  if ( $rc != 0 ) {
     xCAT::MsgUtils->message( "S", "Error creating postscripts tar file." );
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
  if ($distname and $distname !~ /^centos/ and $distname !~ /^fedora/ and $distname !~ /^rh/) {
    #If they say to call it something unidentifiable, give up?
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
  } elsif ( $desc =~ /^Fedora 8$/ ) {
     unless ($distname) {
        $distname = "fedora8";
     }
  } elsif ($desc =~ /^CentOS-4 .*/) {
    unless ($distname) {
      $distname = "centos4";
    }
  } elsif ($desc =~ /^Red Hat Enterprise Linux Client 5$/ ) {
     unless ($distname) {
        $distname = "rhelc5";
     }
  } elsif ($desc =~ /^Red Hat Enterprise Linux Server 5$/ ) {
     unless ($distname) {
        $distname = "rhels5";
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
      $callback->({error=>"Requested distribution architecture $arch, but media is $darch"});
      return;
    }
    if ( $arch =~ /ppc/ ) { $arch = "ppc64" }
  }
  %{$request} = (); #clear request we've got it.

  $callback->({data=>"Copying media to $installroot/$distname/$arch/"});
  my $omask=umask 0022;
  mkpath("$installroot/$distname/$arch");
  umask $omask;
  my $rc;
  my $reaped=0;
  $SIG{INT} =  $SIG{TERM} = sub { if ($cpiopid) { kill 2, $cpiopid; exit 0; } };
  my $KID;
  chdir $path;
  my $child = open($KID,"|-");
  unless (defined $child) {
    $callback->({error=>"Media copy operation fork failure"});
    return;
  }
  if ($child) {
     $cpiopid = $child;
     my @finddata = `find .`;
     for (@finddata) {
        print $KID $_;
     }
     close($KID);
     $rc = $?;
  } else {
     nice 10;
     exec "nice -n 20 cpio -dump $installroot/$distname/$arch";
  }
  #my $rc = system("cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch");
  #my $rc = system("cd $path;rsync -a . $installroot/$distname/$arch/");
  chmod 0755,"$installroot/$distname/$arch";
  xCAT::Yum->localize_yumrepo($installroot,$distname,$arch);
  if ($rc != 0) {
    $callback->({error=>"Media copy operation failed, status $rc"});
  } else {
    $callback->({data=>"Media copy operation successful"});
  }
}

1;
