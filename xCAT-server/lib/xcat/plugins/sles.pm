# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::sles;
use Storable qw(dclone);
use Sys::Syslog;
use File::Temp qw/tempdir/;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::Template;
use xCAT::Postage;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;

my @cpiopid;

sub handled_commands
{
    return {
            copycd    => "sles",
            mknetboot => "nodetype:os=sles.*",
            mkinstall => "nodetype:os=sles.*"
            };
}

sub mknetboot
{
    my $req      = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $tftpdir  = "/tftpboot";
    my $nodes    = @{$request->{node}};
    my @args     = @{$req->{arg}};
    my @nodes    = @{$req->{node}};
    my $ostab    = xCAT::Table->new('nodetype');
    my $sitetab  = xCAT::Table->new('site');
    my $installroot;
    $installroot = "/install";

    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => installdir}, value);
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }
    my %donetftp=();
    foreach $node (@nodes)
    {
        my $ent = $ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
        unless ($ent->{os} and $ent->{arch} and $ent->{profile})
        {
            $callback->(
                        {
                         error     => ["Insufficient nodetype entry for $node"],
                         errorcode => [1]
                        }
                        );
            next;
        }

        my $osver = $ent->{os};
        my $platform;
        if ($osver =~ /sles.*/)
        {
            $platform = "sles";
        }

        my $arch    = $ent->{arch};
        my $profile = $ent->{profile};
        my $suffix  = 'gz';
        if (-r "/$installroot/netboot/$osver/$arch/$profile/rootimg.sfs")
        {
            $suffix = 'sfs';
        }
        if (-r "/$installroot/netboot/$osver/$arch/$profile/rootimg.nfs")
        {
            $suffix = 'nfs';
        }
        unless (
                (
                    -r "/$installroot/netboot/$osver/$arch/$profile/rootimg.gz"
                 or -r "/$installroot/netboot/$osver/$arch/$profile/rootimg.sfs"
                 or -r "/$installroot/netboot/$osver/$arch/$profile/rootimg.nfs"
                )
                and -r "/$installroot/netboot/$osver/$arch/$profile/kernel"
                and -r "/$installroot/netboot/$osver/$arch/$profile/initrd.gz"
          )
        {
            $callback->(
                {
                 error => [
                     "No packed image for platform $osver, architecture $arch, and profile $profile, please run packimage (i.e.  packimage -o $osver -p $profile -a $arch"
                 ],
                 errorcode => [1]
                }
                );
            next;
        }

        mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");

        #TODO: only copy if newer...
        unless ($donetftp{$osver,$arch,$profile}) {
        copy("/$installroot/netboot/$osver/$arch/$profile/kernel",
             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
        copy("/$installroot/netboot/$osver/$arch/$profile/initrd.gz",
             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            $donetftp{$osver,$arch,$profile} = 1;
        }
        unless (    -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel"
                and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/initrd.gz")
        {
            $callback->(
                {
                 error => [
                     "Copying to /$tftpdir/xcat/netboot/$osver/$arch/$profile failed"
                 ],
                 errorcode => [1]
                }
                );
            next;
        }
        my $restab = xCAT::Table->new('noderes');
        my $bptab  = xCAT::Table->new('bootparams',-create=>1);
        my $hmtab  = xCAT::Table->new('nodehm');
        my $ent    = $restab->getNodeAttribs($node, ['primarynic']);
        my $sent   =
          $hmtab->getNodeAttribs($node,
                                 ['serialport', 'serialspeed', 'serialflow']);

        # determine image server, if tftpserver use it, else use xcatmaster
        # else use site.Master, last resort use self
        my $imgsrv;
        my $ient;
        $ient = $restab->getNodeAttribs($node, ['tftpserver']);
        if ($ient and $ient->{tftpserver})
        {
            $imgsrv = $ient->{tftpserver};
        }
        else
        {
            $ient = $restab->getNodeAttribs($node, ['xcatmaster']);
            if ($ient and $ient->{xcatmaster})
            {
                $imgsrv = $ient->{xcatmaster};
            }
            else
            {
                $ient = $sitetab->getAttribs({key => master}, value);
                if ($ient and $ient->{value})
                {
                    $imgsrv = $ient->{value};
                }
                else
                {
                    my $ipfn = xCAT::Utils->my_ip_facing($node);
                    if ($ipfn)
                    {
                        $imgsrv = $ipfn;    #guessing self is second best

                    }
                }
            }
        }
        unless ($imgsrv)
        {
            $callback->(
                {
                 error => [
                     "Unable to determine or reasonably guess the image server for $node"
                 ],
                 errorcode => [1]
                }
                );
            next;
        }
        my $kcmdline;
        if ($suffix eq "nfs")
        {
            $kcmdline =
              "imgurl=nfs://$imgsrv/install/netboot/$osver/$arch/$profile/rootimg ";
        }
        else
        {
            $kcmdline =
              "imgurl=http://$imgsrv/install/netboot/$osver/$arch/$profile/rootimg.$suffix ";
        }
        if (defined $sent->{serialport})
        {

            #my $sent = $hmtab->getNodeAttribs($node,['serialspeed','serialflow']);
            unless ($sent->{serialspeed})
            {
                $callback->(
                    {
                     error => [
                         "serialport defined, but no serialspeed for $node in nodehm table"
                     ],
                     errorcode => [1]
                    }
                    );
                next;
            }
            $kcmdline .=
              "console=ttyS" . $sent->{serialport} . "," . $sent->{serialspeed};
            if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/)
            {
                $kcmdline .= "n8r";
            }
        }
        $bptab->setNodeAttribs(
                      $node,
                      {
                       kernel => "xcat/netboot/$osver/$arch/$profile/kernel",
                       initrd => "xcat/netboot/$osver/$arch/$profile/initrd.gz",
                       kcmdline => $kcmdline
                      }
                      );
    }
}

sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $distname = undef;
    my $arch     = undef;
    my $path     = undef;
    if ($request->{command}->[0] eq 'copycd')
    {
        return copycd($request, $callback, $doreq);
    }
    elsif ($request->{command}->[0] eq 'mkinstall')
    {
        return mkinstall($request, $callback, $doreq);
    }
    elsif ($request->{command}->[0] eq 'mknetboot')
    {
        return mknetboot($request, $callback, $doreq);
    }
}

sub mkinstall
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my @nodes    = @{$request->{node}};
    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my %doneimgs;
    foreach $node (@nodes)
    {
        my $osinst;
        my $ent = $ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
        unless ($ent->{os} and $ent->{arch} and $ent->{profile})
        {
            $callback->(
                        {
                         error => ["No profile defined in nodetype for $node"],
                         errorcode => [1]
                        }
                        );
            next;    #No profile
        }
        my $os      = $ent->{os};
        my $arch    = $ent->{arch};
        my $profile = $ent->{profile};
        unless ( -r $::XCATROOT . "/share/xcat/install/sles/$profile.tmpl"
              or -r $::XCATROOT . "/share/xcat/install/sles/$profile.$arch.tmpl"
              or -r $::XCATROOT . "/share/xcat/install/sles/$profile.$os.tmpl"
              or -r $::XCATROOT
              . "/share/xcat/install/sles/$profile.$os.$arch.tmpl")
        {
            $callback->(
                      {
                       error =>
                         ["No AutoYaST template exists for " . $ent->{profile}],
                       errorcode => [1]
                      }
                      );
            next;
        }

        #Call the Template class to do substitution to produce a kickstart file in the autoinst dir
        my $tmperr;
        if (-r $::XCATROOT . "/share/xcat/install/sles/$profile.$os.$arch.tmpl")
        {
            $tmperr =
              xCAT::Template->subvars(
                         $::XCATROOT
                           . "/share/xcat/install/sles/$profile.$os.$arch.tmpl",
                         "/install/autoinst/$node",
                         $node
                         );
        }
        elsif (-r $::XCATROOT . "/share/xcat/install/sles/$profile.$arch.tmpl")
        {
            $tmperr =
              xCAT::Template->subvars(
                   $::XCATROOT . "/share/xcat/install/sles/$profile.$arch.tmpl",
                   "/install/autoinst/$node", $node);
        }
        elsif (-r $::XCATROOT . "/share/xcat/install/sles/$profile.$os.tmpl")
        {
            $tmperr =
              xCAT::Template->subvars(
                     $::XCATROOT . "/share/xcat/install/sles/$profile.$os.tmpl",
                     "/install/autoinst/$node", $node);
        }
        elsif (-r $::XCATROOT . "/share/xcat/install/sles/$profile.tmpl")
        {
            $tmperr =
              xCAT::Template->subvars(
                         $::XCATROOT . "/share/xcat/install/sles/$profile.tmpl",
                         "/install/autoinst/$node", $node);
        }
        if ($tmperr)
        {
            $callback->(
                        {
                         node => [
                                  {
                                   name      => [$node],
                                   error     => [$tmperr],
                                   errorcode => [1]
                                  }
                         ]
                        }
                        );
            next;
        }
	
		# create the node-specific post script DEPRECATED, don't do
		#mkpath "/install/postscripts/";
		#xCAT::Postage->writescript($node, "/install/postscripts/".$node, "install", $callback);

        if (
            (
             $arch =~ /x86_64/
             and -r "/install/$os/$arch/1/boot/$arch/loader/linux"
             and -r "/install/$os/$arch/1/boot/$arch/loader/initrd"
            )
            or
            (
             $arch =~ /x86$/
             and -r "/install/$os/$arch/1/boot/i386/loader/linux"
             and -r "/install/$os/$arch/1/boot/i386/loader/initrd"
            )
            or ($arch =~ /ppc/ and -r "/install/$os/$arch/1/suseboot/inst64")
          )
        {

            #TODO: driver slipstream, targetted for network.
            unless ($doneimgs{"$os|$arch"})
            {
                mkpath("/tftpboot/xcat/$os/$arch");
                if ($arch =~ /x86_64/)
                {
                    copy("/install/$os/$arch/1/boot/$arch/loader/linux",
                         "/tftpboot/xcat/$os/$arch/");
                    copy("/install/$os/$arch/1/boot/$arch/loader/initrd",
                         "/tftpboot/xcat/$os/$arch/");
                } elsif ($arch =~ /x86/) {
                    copy("/install/$os/$arch/1/boot/i386/loader/linux",
                         "/tftpboot/xcat/$os/$arch/");
                    copy("/install/$os/$arch/1/boot/i386/loader/initrd",
                         "/tftpboot/xcat/$os/$arch/");
                }
                elsif ($arch =~ /ppc/)
                {
                    copy("/install/$os/$arch/1/suseboot/inst64",
                         "/tftpboot/xcat/$os/$arch");
                }
                $doneimgs{"$os|$arch"} = 1;
            }

            #We have a shot...
            my $restab = xCAT::Table->new('noderes');
            my $bptab = xCAT::Table->new('bootparams',-create=>1);
            my $hmtab  = xCAT::Table->new('nodehm');
            my $ent    =
              $restab->getNodeAttribs(
                                      $node,
                                      [
                                       'nfsserver', 
                                       'primarynic', 'installnic'
                                      ]
                                      );
            my $sent =
              $hmtab->getNodeAttribs($node, ['serialport', 'serialspeed', 'serialflow']);
            unless ($ent and $ent->{nfsserver})
            {
                $callback->(
                           {
                            error => ["No noderes.nfsserver for $node defined"],
                            errorcode => [1]
                           }
                           );
                next;
            }
            my $kcmdline =
                "autoyast=http://"
              . $ent->{nfsserver}
              . "/install/autoinst/"
              . $node
              . " install=http://"
              . $ent->{nfsserver}
              . "/install/$os/$arch/1";
            if ($ent->{installnic})
            {
                $kcmdline .= " netdevice=" . $ent->{installnic};
            }
            elsif ($ent->{primarynic})
            {
                $kcmdline .= " netdevice=" . $ent->{primarynic};
            }
            else
            {
                $kcmdline .= " netdevice=eth0";
            }

            #TODO: driver disk handling should in SLES case be a mod of the install source, nothing to see here
            if (defined $sent->{serialport})
            {
                unless ($sent->{serialspeed})
                {
                    $callback->(
                        {
                         error => [
                             "serialport defined, but no serialspeed for $node in nodehm table"
                         ],
                         errorcode => [1]
                        }
                        );
                    next;
                }
                $kcmdline .=
                    " console=ttyS"
                  . $sent->{serialport} . ","
                  . $sent->{serialspeed};
                if ($sent and ($sent->{serialflow} =~ /(ctsrts|cts|hard)/))
                {
                    $kcmdline .= "n8r";
                }
            }

            if ($arch =~ /x86/)
            {
                $bptab->setNodeAttribs(
                                        $node,
                                        {
                                         kernel   => "xcat/$os/$arch/linux",
                                         initrd   => "xcat/$os/$arch/initrd",
                                         kcmdline => $kcmdline
                                        }
                                        );
            }
            elsif ($arch =~ /ppc/)
            {
                $bptab->setNodeAttribs(
                                        $node,
                                        {
                                         kernel   => "xcat/$os/$arch/inst64",
                                         initrd   => "",
                                         kcmdline => $kcmdline
                                        }
                                        );
            }

        }
        else
        {
            $callback->(
                {
                 error => [
                     "Failed to detect copycd configured install source at /install/$os/$arch"
                 ],
                 errorcode => [1]
                }
                );
        }
    }
    #my $rc = xCAT::Utils->create_postscripts_tar();
    #if ($rc != 0)
    #{
    #    xCAT::MsgUtils->message("S", "Error creating postscripts tar file.");
    #}
}

sub copycd
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $distname = "";
    my $detdistname = "";
    my $installroot;
    $installroot = "/install";
    my $sitetab = xCAT::Table->new('site');
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => installdir}, value);
        print Dumper($ref);
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }

    @ARGV = @{$request->{arg}};
    GetOptions(
               'n=s' => \$distname,
               'a=s' => \$arch,
               'p=s' => \$path
               );
    unless ($path)
    {

        #this plugin needs $path...
        return;
    }
    if ($distname and $distname !~ /^sles/)
    {

        #If they say to call it something other than SLES, give up?
        return;
    }
    unless (-r $path . "/content")
    {
        return;
    }
    my $dinfo;
    open($dinfo, $path . "/content");
    while (<$dinfo>)
    {
        if (m/^DEFAULTBASE\s+(\S+)/)
        {
            $darch = $1;
            chomp($darch);
            last;
        }
    }
    close($dinfo);
    unless ($darch)
    {
        return;
    }
    my $dirh;
    opendir($dirh, $path);
    my $discnumber;
    my $totaldiscnumber;
    while (my $pname = readdir($dirh))
    {
        if ($pname =~ /media.(\d+)/)
        {
            $discnumber = $1;
            chomp($discnumber);
            my $mfile;
            open($mfile, $path . "/" . $pname . "/media");
            <$mfile>;
            <$mfile>;
            $totaldiscnumber = <$mfile>;
            chomp($totaldiscnumber);
            close($mfile);
            open($mfile, $path . "/" . $pname . "/products");
            my $prod = <$mfile>;
            close($mfile);

            if ($prod =~ m/SUSE-Linux-Enterprise-Server/)
            {
                my @parts    = split /\s+/, $prod;
                my @subparts = split /-/,   $parts[2];
                $detdistname = "sles" . $subparts[0];
                unless ($distname) { $distname = "sles" . $subparts[0] };
            }
        }
    }
    unless ($distname and $discnumber)
    {
        return;
    }
    if ($darch and $darch =~ /i.86/)
    {
        $darch = "x86";
    }
    elsif ($darch and $darch =~ /ppc/)
    {
        $darch = "ppc64";
    }
    if ($darch)
    {
        unless ($arch)
        {
            $arch = $darch;
        }
        if ($arch and $arch ne $darch)
        {
            $callback->(
                     {
                      error =>
                        ["Requested SLES architecture $arch, but media is $darch"],
                        errorcode => [1]
                     }
                     );
            return;
        }
    }
    %{$request} = ();    #clear request we've got it.

    $callback->(
         {data => "Copying media to $installroot/$distname/$arch/$discnumber"});
    my $omask = umask 0022;
    mkpath("$installroot/$distname/$arch/$discnumber");
    umask $omask;
    my $rc;
    $SIG{INT} =  $SIG{TERM} = sub { 
       foreach(@cpiopid){
          kill 2, $_; 
       }
       if ($::CDMOUNTPATH) {
            chdir("/");
            system("umount $::CDMOUNTPATH");
       }
    };
    my $kid;
    chdir $path;
    my $numFiles = `find . -print | wc -l`;
    my $child = open($kid,"|-");
    unless (defined $child) {
      $callback->({error=>"Media copy operation fork failure"});
      return;
    }
    if ($child) {
       push @cpiopid,$child;
       my @finddata = `find .`;
       for (@finddata) {
          print $kid $_;
       }
       close($kid);
       $rc = $?;
    } else {
        my $c = "nice -n 20 cpio -vdump $installroot/$distname/$arch/$discnumber";
        my $k2 = open(PIPE, "$c 2>&1 |") ||
           $callback->({error => "Media copy operation fork failure"});
	push @cpiopid, $k2;
        my $copied = 0;
        my ($percent, $fout);
        while(<PIPE>){
          next if /^cpio:/;
          $percent = $copied / $numFiles;
          $fout = sprintf "%0.2f%%", $percent * 100;
          $callback->({sinfo => "$fout"});
          ++$copied;
        }
        exit;
    }
    #  system(
    #    "cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch/$discnumber/"
    #    );
    chmod 0755, "$installroot/$distname/$arch";
    chmod 0755, "$installroot/$distname/$arch/$discnumber";
    if ($detdistname eq "sles10.2" and $discnumber eq "1") { #Go and correct inst_startup.ycp in the install root
        my $tmnt = tempdir("xcat-sles.$$.XXXXXX",TMPDIR=>1);
        my $tdir = tempdir("xcat-slesd.$$.XXXXXX",TMPDIR=>1);
        my $startupfile;
        my $ycparch = $arch;
        if ($arch eq "x86") { 
            $ycparch = "i386";
        }
        system("mount -o loop $installroot/$distname/$arch/$discnumber/boot/$ycparch/root $tmnt");
        system("cd $tmnt;find . |cpio -dump $tdir");
        system("umount $tmnt;rm $installroot/$distname/$arch/$discnumber/boot/$ycparch/root");
        open($startupfile,"<","$tdir/usr/share/YaST2/clients/inst_startup.ycp");
        my @ycpcontents = <$startupfile>;
        my @newcontents;
        my $writecont=1;
        close($startupfile);
        foreach (@ycpcontents) {
            if (/No hard disks/) {
                $writecont=0;
            } elsif (/\}/) {
                $writecont=1;
            }
            s/cancel/next/;
            if ($writecont) {
                push @newcontents, $_;
            } 
        }
        open($startupfile,">","$tdir/usr/share/YaST2/clients/inst_startup.ycp");
        foreach (@newcontents) {
            print $startupfile $_;
        }
        close($startupfile);
        system("cd $tdir;mkfs.cramfs . $installroot/$distname/$arch/$discnumber/boot/$ycparch/root");
        system("rm -rf $tmnt $tdir");
    }

    if ($rc != 0)
    {
        $callback->({error => "Media copy operation failed, status $rc"});
    }
    else
    {
        $callback->({data => "Media copy operation successful"});
    }
}

1;
