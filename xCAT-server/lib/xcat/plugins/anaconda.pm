# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::anaconda;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Storable qw(dclone);
use Sys::Syslog;
use Thread qw(yield);
use POSIX qw(WNOHANG nice);
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
#use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;
use xCAT::Common;

#use strict;
my @cpiopid;

my %distnames = (
                 "1176234647.982657" => "centos5",
                 "1156364963.862322" => "centos4.4",
                 "1178480581.024704" => "centos4.5",
                 "1195929648.203590" => "centos5.1",
                 "1195929637.060433" => "centos5.1",
                 "1213888991.267240" => "centos5.2",
                 "1214240246.285059" => "centos5.2",
                 "1237641529.260981" => "centos5.3",
                 "1195488871.805863" => "centos4.6",
                 "1195487524.127458" => "centos4.6",
                 "1170973598.629055" => "rhelc5",
                 "1170978545.752040" => "rhels5",
                 "1192660014.052098" => "rhels5.1",
                 "1192663619.181374" => "rhels5.1",
                 "1209608466.515430" => "rhels5.2",
                 "1209603563.756628" => "rhels5.2",
                 "1209597827.293308" => "rhels5.2",
                 "1231287803.932941" => "rhels5.3", 
                 "1231285121.960246" => "rhels5.3",
                 "1250668122.507797" => "rhels5.4", #x86-64
                 "1250663123.136977" => "rhels5.4", #x86
                 "1250666120.105861" => "rhels5.4", #ppc
                 "1194015916.783841" => "fedora8",
                 "1194015385.299901" => "fedora8",
                 "1210112435.291709" => "fedora9",
                 "1210111941.792844" => "fedora9",
                 "1227147467.285093" => "fedora10",
                 "1227142402.812888" => "fedora10",
                 "1243981097.897160" => "fedora11", #x86_64 DVD ISO
                 "1257725234.740991" => "fedora12", #x86_64 DVD ISO
                 "1194512200.047708" => "rhas4.6",
                 "1194512327.501046" => "rhas4.6",
                 );
my %numdiscs = (
                "1156364963.862322" => 4,
                "1178480581.024704" => 3
                );

sub handled_commands
{
    return {
            copycd    => "anaconda",
            mknetboot => "nodetype:os=(centos.*)|(rh.*)|(fedora.*)",
            mkinstall => "nodetype:os=(esx[34].*)|(centos.*)|(rh.*)|(fedora.*)",
            };
}

sub preprocess_request
{
    my $req      = shift;
    my $callback = shift;
    return [$req]; #calls are only made from pre-farmed out scenarios
    if ($req->{command}->[0] eq 'copycd')
    {    #don't farm out copycd
        return [$req];
    }

    my $stab = xCAT::Table->new('site');
    my $sent;
    ($sent) = $stab->getAttribs({key => 'sharedtftp'}, 'value');
    unless (    $sent
            and defined($sent->{value})
            and ($sent->{value} =~ /no/i or $sent->{value} =~ /0/))
    {

        #unless requesting no sharedtftp, don't make hierarchical call
        return [$req];
    }

    my %localnodehash;
    my %dispatchhash;
    my $nrtab = xCAT::Table->new('noderes');
    my $nrents = $nrtab->getNodesAttribs($req->{node},[qw(tftpserver servicenode)]);
    foreach my $node (@{$req->{node}})
    {
        my $nodeserver;
        my $tent = $nrents->{$node}->[0]; #$nrtab->getNodeAttribs($node, ['tftpserver']);
        if ($tent) { $nodeserver = $tent->{tftpserver} }
        unless ($tent and $tent->{tftpserver})
        {
            $tent = $nrents->{$node}->[0]; #$nrtab->getNodeAttribs($node, ['servicenode']);
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

sub mknetboot
{
    my $xenstyle=0;
    my $req      = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $tftpdir  = "/tftpboot";
    my $nodes    = @{$req->{node}};
    my @args     = @{$req->{arg}};
    my @nodes    = @{$req->{node}};
    my $ostab    = xCAT::Table->new('nodetype');
    my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my %img_hash=();
    my $installroot;
    $installroot = "/install";

    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }
    my %donetftp=();
    my %oents = %{$ostab->getNodesAttribs(\@nodes,[qw(os arch profile provmethod)])};
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my $reshash    = $restab->getNodesAttribs(\@nodes, ['primarynic','tftpserver','xcatmaster']);
    my $hmhash =
          $hmtab->getNodesAttribs(\@nodes,
                                 ['serialport', 'serialspeed', 'serialflow']);
    #my $addkcmdhash =
    #    $bptab->getNodesAttribs(\@nodes, ['addkcmdline']);
    foreach my $node (@nodes)
    {
        my $osver;
        my $arch;
        my $profile;
	my $platform;
        my $rootimgdir;

        my $ent = $oents{$node}->[0]; #ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot')) {
	    my $imagename=$ent->{provmethod};
	    #print "imagename=$imagename\n";
	    if (!exists($img_hash{$imagename})) {
		if (!$osimagetab) {
		    $osimagetab=xCAT::Table->new('osimage', -create=>1);
		}
		(my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod');
		if ($ref) {
		    $img_hash{$imagename}->{osver}=$ref->{'osvers'};
		    $img_hash{$imagename}->{osarch}=$ref->{'osarch'};
		    $img_hash{$imagename}->{profile}=$ref->{'profile'};
		    $img_hash{$imagename}->{provmethod}=$ref->{'provmethod'};
		    if (!$linuximagetab) {
			$linuximagetab=xCAT::Table->new('linuximage', -create=>1);
		    }
		    (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'rootimgdir');
		    if (($ref1) && ($ref1->{'rootimgdir'})) {
			$img_hash{$imagename}->{rootimgdir}=$ref1->{'rootimgdir'};
		    }
		} else {
		    $callback->(
			{error     => ["The os image $imagename does not exists on the osimage table for $node"],
			 errorcode => [1]});
		    next;
		}
	    }
	    my $ph=$img_hash{$imagename};
	    $osver = $ph->{osver};
	    $arch  = $ph->{osarch};
	    $profile = $ph->{profile};
	
	    $rootimgdir=$ph->{rootimgdir};
	    if (!$rootimgdir) {
		$rootimgdir="$installroot/netboot/$osver/$arch/$profile";
	    }
	}
	else {
	    $osver = $ent->{os};
	    $arch    = $ent->{arch};
	    $profile = $ent->{profile};
	    $rootimgdir="$installroot/netboot/$osver/$arch/$profile";
	}

        #print"osvr=$osver, arch=$arch, profile=$profile, imgdir=$rootimgdir\n";
        unless ($osver and $arch and $profile)
        {
            $callback->(
                        {
                         error     => ["Insufficient nodetype entry or osimage entry for $node"],
                         errorcode => [1]
                        }
                        );
            next;
        }

        $platform=xCAT_plugin::anaconda::getplatform($osver);       
        my $suffix  = 'gz';
        if (-r "$rootimgdir/rootimg.sfs")
        {
            $suffix = 'sfs';
        }
        if (-r "$rootimgdir/rootimg.nfs")
        {
            $suffix = 'nfs';
        }
        unless (
                (
                    -r "$rootimgdir/rootimg.gz"
                 or -r "$rootimgdir/rootimg.sfs"
                 or -r "$rootimgdir/rootimg.nfs"
                )
                and -r "$rootimgdir/kernel"
                and -r "$rootimgdir/initrd.gz"
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

        # create the node-specific post scripts
        #mkpath "/install/postscripts/";
        #xCAT::Postage->writescript($node,"/install/postscripts/".$node, "netboot", $callback);

        mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");

        unless ($donetftp{$osver,$arch,$profile}) {
                eval {
                        if (-f "$rootimgdir/hypervisor") {
                                xCAT::Common::copy_if_newer("$rootimgdir/hypervisor",
                                "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
                                $xenstyle=1;
                        }
                        xCAT::Common::copy_if_newer("$rootimgdir/kernel",
                             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
                        xCAT::Common::copy_if_newer("$rootimgdir/initrd.gz",
                             "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
                            $donetftp{$osver,$arch,$profile} = 1;
                };
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
        my $ent    = $reshash->{$node}->[0];#$restab->getNodeAttribs($node, ['primarynic']);
        my $sent   = $hmhash->{$node}->[0];
#          $hmtab->getNodeAttribs($node,
#                                 ['serialport', 'serialspeed', 'serialflow']);

        # determine image server, if tftpserver use it, else use xcatmaster
        # last resort use self
        my $imgsrv;
        my $ient;
        $ient = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['tftpserver']);
        if ($ient and $ient->{tftpserver})
        {
            $imgsrv = $ient->{tftpserver};
        }
        else
        {
            $ient = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['xcatmaster']);
            if ($ient and $ient->{xcatmaster})
            {
                $imgsrv = $ient->{xcatmaster};
            }
            else
            {
                # master not correct for service node pools
                #$ient = $sitetab->getAttribs({key => master}, value);
                #if ($ient and $ient->{value})
                #{
                #    $imgsrv = $ient->{value};
                #}
                #else
                #{
                $imgsrv = '!myipfn!';
                #}
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
              "console=tty0 console=ttyS" . $sent->{serialport} . "," . $sent->{serialspeed};
            if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/)
            {
                $kcmdline .= "n8r";
            }
        }
        # add the addkcmdline attribute  to the end
        # of the command, if it exists
        #my $addkcmd   = $addkcmdhash->{$node}->[0];
        # add the extra addkcmd command info, if in the table
        #if ($addkcmd->{'addkcmdline'}) {
        #        $kcmdline .= " ";
        #        $kcmdline .= $addkcmd->{'addkcmdline'};
           
        #}
        
	my $kernstr="xcat/netboot/$osver/$arch/$profile/kernel";
	if ($xenstyle) {
	   $kernstr.= "!xcat/netboot/$osver/$arch/$profile/hypervisor";
	}
        $bptab->setNodeAttribs(
                      $node,
                      {
                       kernel => "$kernstr",
                       initrd => "xcat/netboot/$osver/$arch/$profile/initrd.gz",
                       kcmdline => $kcmdline
                      }
                      );
    }

    #my $rc = xCAT::Utils->create_postscripts_tar();
    #if ( $rc != 0 ) {
    #	xCAT::MsgUtils->message( "S", "Error creating postscripts tar file." );
    #}
}

sub mkinstall
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my @nodes    = @{$request->{node}};
    my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my %img_hash=();

    my $installroot;
    $installroot = "/install";
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }

    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my %doneimgs;
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my %osents = %{$ostab->getNodesAttribs(\@nodes, ['profile', 'os', 'arch', 'provmethod'])};
    my %rents =
              %{$restab->getNodesAttribs(\@nodes,
                                     ['nfsserver', 'primarynic', 'installnic'])};
    my %hents = 
              %{$hmtab->getNodesAttribs(\@nodes,
                                     ['serialport', 'serialspeed', 'serialflow'])};
    #my $addkcmdhash =
    #    $bptab->getNodesAttribs(\@nodes, ['addkcmdline']);
    require xCAT::Template;
    foreach $node (@nodes)
    {
        my $os;
        my $arch;
        my $profile;
        my $tmplfile;
        my $pkgdir;
	my $imagename;
	my $platform;

        my $osinst;
        my $ent = $osents{$node}->[0]; #$ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot')) {
	    $imagename=$ent->{provmethod};
	    #print "imagename=$imagename\n";
	    if (!exists($img_hash{$imagename})) {
		if (!$osimagetab) {
		    $osimagetab=xCAT::Table->new('osimage', -create=>1);
		}
		(my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod');
		if ($ref) {
		    $img_hash{$imagename}->{osver}=$ref->{'osvers'};
		    $img_hash{$imagename}->{osarch}=$ref->{'osarch'};
		    $img_hash{$imagename}->{profile}=$ref->{'profile'};
		    $img_hash{$imagename}->{provmethod}=$ref->{'provmethod'};
		    if (!$linuximagetab) {
			$linuximagetab=xCAT::Table->new('linuximage', -create=>1);
		    }
		    (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'template', 'pkgdir');
		    if ($ref1) {
			if ($ref1->{'template'}) {
			    $img_hash{$imagename}->{template}=$ref1->{'template'};
			}
			if ($ref1->{'pkgdir'}) {
			    $img_hash{$imagename}->{pkgdir}=$ref1->{'pkgdir'};
			}
		    }
		} else {
		    $callback->(
			{error     => ["The os image $imagename does not exists on the osimage table for $node"],
			 errorcode => [1]});
		    next;
		}
	    }
	    my $ph=$img_hash{$imagename};
	    $os = $ph->{osver};
	    $arch  = $ph->{osarch};
	    $profile = $ph->{profile};
	    $platform=xCAT_plugin::anaconda::getplatform($os);
	
	    $tmplfile=$ph->{template};
            $pkgdir=$ph->{pkgdir};
	    if (!$pkgdir) {
		$pkgdir="$installroot/$os/$arch";
	    }
	}
	else {
	    $os = $ent->{os};
	    $arch    = $ent->{arch};
	    $profile = $ent->{profile};
	    $platform=xCAT_plugin::anaconda::getplatform($os);
	    my $genos = $os;
	    $genos =~ s/\..*//;
	    if ($genos =~ /rh.*s(\d*)/)
	    {
		unless (-r "$installroot/custom/install/$platform/$profile.$genos.$arch.tmpl"
			or -r "/install/custom/install/$platform/$profile.$genos.tmpl"
			or -r "$::XCATROOT/share/xcat/install/$platform/$profile.$genos.$arch.tmpl"
			or -r "$::XCATROOT/share/xcat/install/$platform/$profile.$genos.tmpl")
		{
		    $genos = "rhel$1";
		}
	    }
	    
	    $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$platform", $profile, $os, $arch, $genos);
	    if (! $tmplfile) { $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$platform", $profile, $os, $arch, $genos); }

	    $pkgdir="$installroot/$os/$arch";
	}

        my @missingparms;
        unless ($os) {
	    if ($imagename) { push @missingparms,"osimage.osvers";  }
            else { push @missingparms,"nodetype.os";}
        }
        unless ($arch) {
	    if ($imagename) { push @missingparms,"osimage.osarch";  }
            else { push @missingparms,"nodetype.arch";}
        }
        unless ($profile) {
	    if ($imagename) { push @missingparms,"osimage.profile";  }
            else { push @missingparms,"nodetype.profile";}
        }
        unless ($os and $arch and $profile)
        {
            $callback->(
                        {
                         error => ["Missing ".join(',',@missingparms)." for $node"],
                         errorcode => [1]
                        }
                        );
            next;    #No profile
        }

        unless ( -r "$tmplfile")  
        {
            $callback->(
                        {
                         error => [
                                   "No $platform kickstart template exists for "
                                     . $profile
                         ],
                         errorcode => [1]
                        }
                        );
            next;
        }

        #Call the Template class to do substitution to produce a kickstart file in the autoinst dir
        my $tmperr;
	if ($imagename) {
	    $tmperr="Unable to find template file: $tmplfile";
	} else {
          $tmperr="Unable to find template in /install/custom/install/$platform or $::XCATROOT/share/xcat/install/$platform (for $profile/$os/$arch combination)";
	}
        if (-r "$tmplfile")
        {
            $tmperr =
              xCAT::Template->subvars(
                    $tmplfile,
                    "/$installroot/autoinst/" . $node,
                    $node
                    );
        }

        if ($tmperr)
        {
            $callback->(
                    {
                     node =>
                       [{name => [$node], error => [$tmperr], errorcode => [1]}]
                    }
                    );
            next;
        }
        #my $installdir="/install"; #TODO: not hardcode installdir
        my $tftpdir = "/tftpboot";

        # create the node-specific post scripts
        #mkpath "/install/postscripts/";
        #xCAT::Postage->writescript($node,"/install/postscripts/".$node, "install", $callback);
        my $kernpath;
        my $initrdpath;
        my $maxmem;

        if (
            (
                 $arch =~ /x86/ and 
                    (
                         -r "$pkgdir/images/pxeboot/vmlinuz"
                         and $kernpath = "$pkgdir/images/pxeboot/vmlinuz"
                         and -r "$pkgdir/images/pxeboot/initrd.img"
                         and $initrdpath = "$pkgdir/images/pxeboot/initrd.img"
                    ) or ( #Handle the case seen in VMWare 4.0 ESX media
                        #In VMWare 4.0 they dropped the pxe-optimized initrd
                        #leaving us no recourse but the rather large optical disk
                        #initrd, but perhaps we can mitigate with gPXE
                         -d "$pkgdir/VMware" 
                         and -r "$pkgdir/isolinux/vmlinuz"
                         and $kernpath ="$pkgdir/isolinux/vmlinuz"
                         and -r "$pkgdir/isolinux/initrd.img"
                         and $initrdpath = "$pkgdir/isolinux/initrd.img"
                         and $maxmem="512M" #Have to give up linux room to make room for vmware hypervisor evidently
                    )
            ) or (    $arch =~ /ppc/
                and -r "$pkgdir/ppc/ppc64/vmlinuz"
                and $kernpath = "$pkgdir/ppc/ppc64/vmlinuz"
                and -r "$pkgdir/ppc/ppc64/ramdisk.image.gz"
                and $initrdpath = "$pkgdir/ppc/ppc64/ramdisk.image.gz")
          )
        {

            #TODO: driver slipstream, targetted for network.
            unless ($doneimgs{"$os|$arch"})
            {
                mkpath("/tftpboot/xcat/$os/$arch");
                eval {
                        xCAT::Common::copy_if_newer($kernpath,"$tftpdir/xcat/$os/$arch");
                        xCAT::Common::copy_if_newer($initrdpath,"$tftpdir/xcat/$os/$arch/initrd.img");
                };

                if ($@) {
                        $callback->(
                                {
                                  error => ["copying pxe files failed: $@"],
                                  errorcode => [1],
                                }
                                );
                        next;
                }

                $doneimgs{"$os|$arch"} = 1;
            }

            #We have a shot...
            my $ent    = $rents{$node}->[0];
#              $restab->getNodeAttribs($node,
#                                     ['nfsserver', 'primarynic', 'installnic']);
            my $sent = $hents{$node}->[0];
#              $hmtab->getNodeAttribs(
#                                     $node,
#                                     [
#                                      'serialport', 'serialspeed', 'serialflow'
#                                     ]
#                                     );
            unless ($ent and $ent->{nfsserver})
            {
                $callback->(
                        {
                         error => ["No noderes.nfsserver defined for " . $node],
                         errorcode => [1]
                        }
                        );
                next;
            }
            my $kcmdline =
                "nofb utf8 ks=http://"
              . $ent->{nfsserver}
              . "/install/autoinst/"
              . $node;
            if ($maxmem) {
                $kcmdline.=" mem=$maxmem";
            }
            if ($ent->{installnic})
            {
                $kcmdline .= " ksdevice=" . $ent->{installnic};
            }
            elsif ($ent->{primarynic})
            {
                $kcmdline .= " ksdevice=" . $ent->{primarynic};
            }
            else
            {
                $kcmdline .= " ksdevice=eth0";
            }

            #TODO: dd=<url> for driver disks
            if (defined($sent->{serialport}))
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
                    " console=tty0 console=ttyS"
                  . $sent->{serialport} . ","
                  . $sent->{serialspeed};
                if ($sent->{serialflow} =~ /(hard|cts|ctsrts)/)
                {
                    $kcmdline .= "n8r";
                }
            }
            $kcmdline .= " noipv6";
            # add the addkcmdline attribute  to the end
            # of the command, if it exists
            #my $addkcmd   = $addkcmdhash->{$node}->[0];
            # add the extra addkcmd command info, if in the table
            #if ($addkcmd->{'addkcmdline'}) {
            #        $kcmdline .= " ";
            #        $kcmdline .= $addkcmd->{'addkcmdline'};
            #}

            $bptab->setNodeAttribs(
                                   $node,
                                   {
                                    kernel   => "xcat/$os/$arch/vmlinuz",
                                    initrd   => "xcat/$os/$arch/initrd.img",
                                    kcmdline => $kcmdline
                                   }
                                   );
        }
        else
        {
            $callback->(
                    {
                     error => ["Install image not found in /install/$os/$arch"],
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
    my $installroot;
    my $sitetab = xCAT::Table->new('site');
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        #print Dumper($ref);
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
    }

    my $distname;
    my $arch;
    my $path;

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
    if (    $distname
        and $distname !~ /^centos/
        and $distname !~ /^fedora/
        and $distname !~ /^rh/)
    {

        #If they say to call it something unidentifiable, give up?
        return;
    }
    unless (-r $path . "/.discinfo")
    {
        return;
    }
    my $dinfo;
    open($dinfo, $path . "/.discinfo");
    my $did = <$dinfo>;
    chomp($did);
    my $desc = <$dinfo>;
    chomp($desc);
    my $darch = <$dinfo>;
    chomp($darch);

    if ($darch and $darch =~ /i.86/)
    {
        $darch = "x86";
    }
    close($dinfo);
    if ($distnames{$did})
    {
        unless ($distname)
        {
            $distname = $distnames{$did};
        }
    }
    elsif ($desc =~ /^Final$/)
    {
        unless ($distname)
        {
            $distname = "centos5";
        }
    }
    elsif ($desc =~ /^Fedora 8$/)
    {
        unless ($distname)
        {
            $distname = "fedora8";
        }
    }
    elsif ($desc =~ /^CentOS-4 .*/)
    {
        unless ($distname)
        {
            $distname = "centos4";
        }
    }
    elsif ($desc =~ /^Red Hat Enterprise Linux Client 5$/)
    {
        unless ($distname)
        {
            $distname = "rhelc5";
        }
    }
    elsif ($desc =~ /^Red Hat Enterprise Linux Server 5$/)
    {
        unless ($distname)
        {
            $distname = "rhels5";
        }
    }
    elsif ($desc =~ /^Red Hat Enterprise Linux 6\.0$/)
    {
        unless ($distname)
        {
            $distname = "rhel6";
        }
    }

    unless ($distname)
    {
        return;    #Do nothing, not ours..
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
                   "Requested distribution architecture $arch, but media is $darch"
                }
                );
            return;
        }
        if ($arch =~ /ppc/) { $arch = "ppc64" }
    }
    %{$request} = ();    #clear request we've got it.

    $callback->({data => "Copying media to $installroot/$distname/$arch/"});
    my $omask = umask 0022;
    mkpath("$installroot/$distname/$arch");
    umask $omask;
    my $rc;
    my $reaped = 0;
    $SIG{INT} = $SIG{TERM} = sub {
        foreach(@cpiopid){
            kill 2, $_;
        }
        if ($::CDMOUNTPATH) {
            chdir("/");
            system("umount $::CDMOUNTPATH");
        }
    };
    my $KID;
    chdir $path;
    my $numFiles = `find . -print | wc -l`;
    my $child = open($KID, "|-");
    unless (defined $child)
    {
        $callback->({error => "Media copy operation fork failure"});
        return;
    }
    if ($child)
    {
        push @cpiopid, $child;
        my @finddata = `find .`;
        for (@finddata)
        {
            print $KID $_;
        }
        close($KID);
        $rc = $?;
    }
    else
    {
        nice 10;
        my $c = "nice -n 20 cpio -vdump $installroot/$distname/$arch";
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

    #my $rc = system("cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch");
    #my $rc = system("cd $path;rsync -a . $installroot/$distname/$arch/");
    chmod 0755, "$installroot/$distname/$arch";
    require xCAT::Yum;
    xCAT::Yum->localize_yumrepo($installroot, $distname, $arch);
    if ($rc != 0)
    {
        $callback->({error => "Media copy operation failed, status $rc"});
    }
    else
    {
        $callback->({data => "Media copy operation successful"});
	my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch);
        if ($ret[0] != 0) {
	    $callback->({data => "Error when updating the osimage tables: " . $ret[1]});
	}
    }
}


sub getplatform {
    my $os=shift;
    my $platform;
    if ($os =~ /rh.*/) 
    {
	$platform = "rh";
    }
    elsif ($os =~ /centos.*/)
    {
	$platform = "centos";
    }
    elsif ($os =~ /fedora.*/)
    {
	$platform = "fedora";
    }
    elsif ($os =~ /esx.*/)
    {
	$platform = "esx";
    }
    return $platform;
}

1;
