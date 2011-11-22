# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::sles;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Storable qw(dclone);
use Sys::Syslog;
use File::Temp qw/tempdir/;
use xCAT::Table;
use xCAT::Utils;
use xCAT::NetworkUtils;
use xCAT::SvrUtils;
use xCAT::MsgUtils;
use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;
use File::Temp qw/mkdtemp/;

use Socket;

#use strict;
my @cpiopid;

sub handled_commands
{
    return {
            copycd    => "sles",
            mknetboot => "nodetype:os=(sles.*)|(suse.*)",
            mkinstall => "nodetype:os=(sles.*)|(suse.*)",
            mkstatelite => "nodetype:os=(sles.*)"
            };
}

sub mknetboot
{
    my $req      = shift;
    my $callback = shift;
    my $doreq    = shift;

    my $statelite = 0;
    if($req->{command}->[0] =~ 'mkstatelite') {
        $statelite = "true";
    }

    my $tftpdir  = "/tftpboot";
    my $nodes    = @{$req->{node}};
    my @nodes    = @{$req->{node}};
    my $ostab    = xCAT::Table->new('nodetype');
    my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $pkgdir;
    my $osimagetab;
    my $installroot;
    $installroot = "/install";

    my $xcatdport = "3001";

    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        if ($ref and $ref->{value})
        {
            $installroot = $ref->{value};
        }
        ($ref) = $sitetab->getAttribs({key => 'xcatdport'}, 'value');
        if ($ref and $ref->{value}) 
        {
            $xcatdport = $ref->{value};
        }
    }

    my $ntents = $ostab->getNodesAttribs($req->{node}, ['os', 'arch', 'profile', 'provmethod']);
    my %img_hash=();

    my $statetab;
    my $stateHash;
    if ($statelite) {
        $statetab = xCAT::Table->new('statelite', -create=>1);
        $stateHash = $statetab->getNodesAttribs(\@nodes, ['statemnt']);
    }

    # TODO: following the redhat change, get the necessary attributes before the next foreach
    # get the mac addresses for all the nodes
    my $mactab = xCAT::Table->new('mac');
    my $machash = $mactab->getNodesAttribs(\@nodes, ['interface', 'mac']);

    my $restab = xCAT::Table->new('noderes');
    my $reshash = $restab->getNodesAttribs(\@nodes, ['primarynic', 'tftpserver', 'xcatmaster', 'nfsserver', 'nfsdir', 'installnic']);

    my %donetftp=();
    foreach my $node (@nodes)
    {
        my $osver;
        my $arch;
        my $profile;
        my $rootimgdir;
        my $nodebootif; # nodebootif will be used if noderes.installnic is not set
        my $rootfstype;
	
	    my $ent= $ntents->{$node}->[0];
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
	        my $imagename=$ent->{provmethod};
	        #print "imagename=$imagename\n";
	        if (!exists($img_hash{$imagename})) {
		        if (!$osimagetab) {
		            $osimagetab=xCAT::Table->new('osimage', -create=>1);
		        }
		        (my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'rootfstype', 'provmethod');
		        if ($ref) {
		            $img_hash{$imagename}->{osver}=$ref->{'osvers'};
		            $img_hash{$imagename}->{osarch}=$ref->{'osarch'};
		            $img_hash{$imagename}->{profile}=$ref->{'profile'};
                    $img_hash{$imagename}->{rootfstype}=$ref->{'rootfstype'};
		            $img_hash{$imagename}->{provmethod}=$ref->{'provmethod'};
		            if (!$linuximagetab) {
			            $linuximagetab=xCAT::Table->new('linuximage', -create=>1);
		            }
		            (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'rootimgdir', 'nodebootif');
		            if (($ref1) && ($ref1->{'rootimgdir'})) {
			            $img_hash{$imagename}->{rootimgdir}=$ref1->{'rootimgdir'};
		            }
                    if (($ref1) && ($ref1->{'nodebootif'})) {
                        $img_hash{$imagename}->{nodebootif} = $ref1->{'nodebootif'};
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
            $rootfstype = $ph->{rootfstype};
            $nodebootif = $ph->{nodebootif};
	
	        $rootimgdir = $ph->{rootimgdir};
	        unless ($rootimgdir) {
		        $rootimgdir = "$installroot/netboot/$osver/$arch/$profile";
	        }
	    }
	    else {
	        $osver = $ent->{os};
	        $arch    = $ent->{arch};
	        $profile = $ent->{profile};
            $rootfstype = "nfs";    # TODO: try to get it from the option or table
            my $imgname;
            if ($statelite) {
                $imgname = "$osver-$arch-statelite-$profile";
            } else {
                $imgname = "$osver-$arch-netboot-$profile";
            }

            if (! $osimagetab) {
                $osimagetab = xCAT::Table->new('osimage');
            }

            if ($osimagetab) {
                my ($ref1) = $osimagetab->getAttribs({imagename => $imgname}, 'rootfstype');
                if (($ref1) && ($ref1->{'rootfstype'})) {
                    $rootfstype = $ref1->{'rootfstype'};
                }
            } else {
                $callback->(
                    { error => [ qq{Cannot find the linux image called "$osver-$arch-$provmethod-$profile", maybe you need to use the "nodeset <nr> osimage=<osimage name>" command to set the boot state} ],
                    errorcode => [1]}
                );
            }

	        $rootimgdir="$installroot/netboot/$osver/$arch/$profile";
	    }

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

        #print"osvr=$osver, arch=$arch, profile=$profile, imgdir=$rootimgdir\n";
	    my $platform;
        if ($osver =~ /sles.*/)
        {
            $platform = "sles";
            # TODO: should get the $pkgdir value from the linuximage table
            $pkgdir = "$installroot/$osver/$arch";
        }elsif($osver =~ /suse.*/){
            $platform = "sles";
	    }

        my $suffix  = 'gz';       
        if (-r "$rootimgdir/rootimg.sfs")
        {
            $suffix = 'sfs';
        }

        if ($statelite) {
            unless ( -r "$rootimgdir/kernel") {
                $callback->({
                    error=>[qq{Did you run "genimage" before running "liteimg"? kernel cannot be found}],
                    errorcode => [1]
                });
                next;
            } 
            if ( $rootfstype eq "ramdisk" and ! -r "$rootimgdir/rootimg-statelite.gz" ) {
                $callback->({
                    error=>[qq{No packed rootimage for the platform $osver, arch $arch and profile $profile, please run liteimg to create it}],
                    errorcode=>[1]
                });
                next;
            }

	    if (!-r "$rootimgdir/initrd-statelite.gz") {
                if (! -r "$rootimgdir/initrd.gz") {
                    $callback->({
                        error=>[qq{Did you run "genimage" before running "liteimg"? initrd.gz or initrd-statelite.gz cannot be found}],
                        errorcode=>[1]
				});
                    next;
                }
		else {
		    copy("$rootimgdir/initrd.gz", "$rootimgdir/initrd-statelite.gz");
                }
	    }
	    
        } else {
            unless ( -r "$rootimgdir/kernel") {
                $callback->({
                    error=>[qq{Did you run "genimage" before running "packimage"? kernel cannot be found}],
                    errorcode=>[1]
			    });
                next;
	    }
	    if (!-r "$rootimgdir/initrd-stateless.gz") {
                if (! -r "$rootimgdir/initrd.gz") {
                    $callback->({
                        error=>[qq{Did you run "genimage" before running "packimage"? initrd.gz or initrd-stateless.gz cannot be found}],
                        errorcode=>[1]
				});
                    next;
                }
		else {
		    copy("$rootimgdir/initrd.gz", "$rootimgdir/initrd-stateless.gz");
                }
            }
	    
            unless ( -r "$rootimgdir/rootimg.gz" or -r "$rootimgdir/rootimg.sfs" ) {
                $callback->({
                    error=>[qq{No packed image for platform $osver, architecture $arch, and profile $profile, please run packimage before nodeset}],
                    errorcode=>[1]
                });
                next;
            }
        }

        mkpath("/$tftpdir/xcat/netboot/$osver/$arch/$profile/");

        #TODO: only copy if newer...
        unless ($donetftp{$osver,$arch,$profile}) {
            copy("$rootimgdir/kernel", "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            if ($statelite) {
                copy("$rootimgdir/initrd-statelite.gz", "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            } else {
                copy("$rootimgdir/initrd-stateless.gz", "/$tftpdir/xcat/netboot/$osver/$arch/$profile/");
            }
            $donetftp{$osver,$arch,$profile} = 1;
        }

        if ($statelite) {
            unless ( -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel" 
                    and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/initrd-statelite.gz") {
                $callback->({
                    error=>[qq{copying to /$tftpdir/xcat/netboot/$osver/$arch/$profile failed}],
                    errorcode=>[1]
                });
                next;
            }
        } else {
            unless ( -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/kernel" 
                    and -r "/$tftpdir/xcat/netboot/$osver/$arch/$profile/initrd-stateless.gz") {
                $callback->({
                    error=>[qq{copying to /$tftpdir/xcat/netboot/$osver/$arch/$profile failed}],
                    errorcode=>[1]
                });
                next;
            }
        }

        # TODO: move the table operations out of the foreach loop
        my $bptab  = xCAT::Table->new('bootparams',-create=>1);
        my $hmtab  = xCAT::Table->new('nodehm');
        my $sent   =
          $hmtab->getNodeAttribs($node,
                                 ['serialport', 'serialspeed', 'serialflow']);

        # determine image server, if tftpserver use it, else use xcatmaster
        # last resort use self
        my $imgsrv;
        my $ient;
        my $xcatmaster;

        $ient = $restab->getNodeAttribs($node, ['xcatmaster']);
        if ($ient and $ient->{xcatmaster})
        {
            $xcatmaster = $ient->{xcatmaster};
        } else {
            $xcatmaster = '!myipfn!'; #allow service nodes to dynamically nominate themselves as a good contact point, this is of limited use in the event that xcat is not the dhcp/tftp server
        }

        $ient = $restab->getNodeAttribs($node, ['tftpserver']);
        if ($ient and $ient->{tftpserver})
        {
            $imgsrv = $ient->{tftpserver};
        }
        else
        {
        #    $ient = $restab->getNodeAttribs($node, ['xcatmaster']);
        #    if ($ient and $ient->{xcatmaster})
        #    {
        #        $imgsrv = $ient->{xcatmaster};
        #    }
        #    else
        #    {
        #        # master removed, does not work for servicenode pools
        #        #$ient = $sitetab->getAttribs({key => master}, value);
        #        #if ($ient and $ient->{value})
        #        #{
        #         #   $imgsrv = $ient->{value};
        #        #}
        #        #else
        #        #{
        #        $imgsrv = '!myipfn!';
        #        #}
        #    }
            $imgsrv = $xcatmaster;
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
        if ($statelite) 
        {
            if($rootfstype ne "ramdisk") {
                # get entry for nfs root if it exists;
                # have to get nfssvr, nfsdir and xcatmaster from noderes table
                my $nfssrv = $imgsrv;
                my $nfsdir = $rootimgdir;
                
                if ($restab) {
                    my $resHash = $restab->getNodeAttribs($node, ['nfsserver', 'nfsdir']);
                    if($resHash and $resHash->{nfsserver}) {
                        $nfssrv = $resHash->{nfsserver};
                    }
                    if($resHash and $resHash->{nfsdir} ne '') {
                        $nfsdir = $resHash->{nfsdir} . "/netboot/$osver/$arch/$profile";
                    }
                }
                $kcmdline = 
                    "NFSROOT=$nfssrv:$nfsdir STATEMNT=";
            } else {
                $kcmdline =
                    "imgurl=http://$imgsrv/$rootimgdir/rootimg-statelite.gz STATEMNT=";
            }
            # add support for subVars in the value of "statemnt"
            my $statemnt="";
            if (exists($stateHash->{$node})) {
                $statemnt = $stateHash->{$node}->[0]->{statemnt};
                if (grep /\$/, $statemnt) {
                    my ($server, $dir) = split(/:/, $statemnt);
                    
                    #if server is blank, then its the directory
                    unless($dir) {
                        $dir = $server;
                        $server = '';
                    }
                    if(grep /\$|#CMD/, $dir) {
                        $dir = xCAT::SvrUtils->subVars($dir, $node, 'dir', $callback);
                        $dir =~ s/\/\//\//g;
                    }
                    if($server) {
                        $server = xCAT::SvrUtils->subVars($server, $node, 'server', $callback);
                    }
                    $statemnt = $server . ":" . $dir;
                }
            }
            $kcmdline .= $statemnt . " ";
            # get "xcatmaster" value from the "noderes" table
            
            if($rootfstype ne "ramdisk") {
                #BEGIN service node 
                my $isSV = xCAT::Utils->isServiceNode();
                my $res = xCAT::Utils->runcmd("hostname", 0);
                my $sip = xCAT::NetworkUtils->getipaddr($res);  # this is the IP of service node
                if($isSV and (($xcatmaster eq $sip) or ($xcatmaster eq $res))) {
                    # if the NFS directory in litetree is on the service node, 
                    # and it is not exported, then it will be mounted automatically 
                    xCAT::SvrUtils->setupNFSTree($node, $sip, $callback);
                    # then, export the statemnt directory if it is on the service node
                    if($statemnt) {
                        xCAT::SvrUtils->setupStatemnt($sip, $statemnt, $callback);
                    }
                }
                #END sevice node 
            }
        }
        else
        {
            $kcmdline =
              "imgurl=http://$imgsrv/$rootimgdir/rootimg.$suffix ";
        }
        $kcmdline .= "XCAT=$xcatmaster:$xcatdport quiet ";

        # add the kernel-booting parameter: netdev=<eth0>, or BOOTIF=<mac>
        my $netdev = "";
        my $mac = $machash->{$node}->[0]->{mac};

        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{installnic}) {
            if ($reshash->{$node}->[0]->{installnic} ne "mac") {
                $kcmdline .= "netdev=" . $reshash->{$node}->[0]->{installnic} . " ";
            }
        } elsif ($nodebootif) {
            $kcmdline .=  "netdev=" . $nodebootif . " ";
        } elsif ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{primarynic}) {
            $kcmdline .= "netdev=" . $reshash->{$node}->[0]->{primarynic} . " ";
        } else {
            if ($arch =~ /x86/) {
                #do nothing, we'll let pxe/xnba work their magic
            } elsif ($mac) {
                $kcmdline .=  "BOOTIF=" . $mac . " ";
            } else {
                $callback->({
                    error=>[qq{"cannot get the mac address for $node in mac table"}],
                    errorcode=>[1]
                });
            }
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

        my $initrdstr = "xcat/netboot/$osver/$arch/$profile/initrd-stateless.gz";
        $initrdstr = "xcat/netboot/$osver/$arch/$profile/initrd-statelite.gz" if ($statelite);

		if($statelite)
		{
		    my $statelitetb = xCAT::Table->new('statelite');
                    my $mntopts = $statelitetb->getNodeAttribs($node, ['mntopts']);
		    
		    my $mntoptions = $mntopts->{'mntopts'};
		    if(defined($mntoptions))
		    {
				$kcmdline .= "MNTOPTS=\'$mntoptions\'";
		    }			
		}
        $bptab->setNodeAttribs(
                      $node,
                      {
                       kernel => "xcat/netboot/$osver/$arch/$profile/kernel",
                       initrd => $initrdstr,
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
    elsif ($request->{command}->[0] eq 'mknetboot' or
    $request->{command}->[0] eq 'mkstatelite')
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
    my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;

    my $ntents = $ostab->getNodesAttribs($request->{node}, ['os', 'arch', 'profile', 'provmethod']);
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

    my %doneimgs;
    require xCAT::Template; #only used here, load so memory can be COWed
    foreach $node (@nodes)
    {
        my $os;
        my $arch;
        my $profile;
        my $tmplfile;
        my $pkgdir;
	my $pkglistfile;
        my $osinst;
        my $ent = $ntents->{$node}->[0];
	my $plat = "";

        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
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
		    (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'template', 'pkgdir', 'pkglist');
		    if ($ref1) {
			if ($ref1->{'template'}) {
			    $img_hash{$imagename}->{template}=$ref1->{'template'};
			}
			if ($ref1->{'pkgdir'}) {
			    $img_hash{$imagename}->{pkgdir}=$ref1->{'pkgdir'};
			}
			if ($ref1->{'pkglist'}) {
			    $img_hash{$imagename}->{pkglist}=$ref1->{'pkglist'};
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
	
	    $tmplfile=$ph->{template};
            $pkgdir=$ph->{pkgdir};
	    if (!$pkgdir) {
		$pkgdir="$installroot/$os/$arch";
	    }
	    $pkglistfile=$ph->{pkglist};
	}
	else {
	    $os = $ent->{os};
	    $arch    = $ent->{arch};
	    $profile = $ent->{profile};
	    if($os =~/sles.*/){
		$plat = "sles";
	    }elsif($os =~/suse.*/){
		$plat = "suse";
	    }else{
		$plat = "foobar";
		print "You should never get here!  Programmer error!";
		return;
	    }

		$tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$plat", $profile, $os, $arch);
		if (! $tmplfile) { $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$plat", $profile, $os, $arch); }

	    $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$plat", $profile, $os, $arch);
	    if (! $pkglistfile) { $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$plat", $profile, $os, $arch); }

	    $pkgdir="$installroot/$os/$arch";
	}
	

	unless ($os and $arch and $profile)
	{
	    $callback->(
		{
		    error     => ["No profile defined in nodetype or osimage table for $node"],
		    errorcode => [1]
		}
		);
	    next;
	}

        
	unless ( -r "$tmplfile")     
        {
            $callback->(
                      {
                       error =>
                         ["No AutoYaST template exists for " . $ent->{profile} . " in directory $installroot/custom/install/$plat or $::XCATROOT/share/xcat/install/$plat"],
                       errorcode => [1]
                      }
                      );
            next;
        }

        #Call the Template class to do substitution to produce a kickstart file in the autoinst dir
        my $tmperr;
        if (-r "$tmplfile")
        {
            $tmperr =
              xCAT::Template->subvars(
                         $tmplfile,
                         "$installroot/autoinst/$node",
                         $node,
		         $pkglistfile,
		         $pkgdir
                         );
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
             and -r "$pkgdir/1/boot/$arch/loader/linux"
             and -r "$pkgdir/1/boot/$arch/loader/initrd"
            )
            or
            (
             $arch =~ /x86$/
             and -r "$pkgdir/1/boot/i386/loader/linux"
             and -r "$pkgdir/1/boot/i386/loader/initrd"
            )
            or ($arch =~ /ppc/ and -r "$pkgdir/1/suseboot/inst64")
          )
        {

            # Define a variable for driver update list
            my @dd_drivers;

            #TODO: driver slipstream, targetted for network.
            unless ($doneimgs{"$os|$arch"})
            {
                mkpath("/tftpboot/xcat/$os/$arch");
                if ($arch =~ /x86_64/)
                {
                    copy("$pkgdir/1/boot/$arch/loader/linux",
                         "/tftpboot/xcat/$os/$arch/");
                    copy("$pkgdir/1/boot/$arch/loader/initrd",
                         "/tftpboot/xcat/$os/$arch/");
                    @dd_drivers = &insert_dd($callback, $os, $arch, "/tftpboot/xcat/$os/$arch/initrd");
                } elsif ($arch =~ /x86/) {
                    copy("$pkgdir/1/boot/i386/loader/linux",
                         "/tftpboot/xcat/$os/$arch/");
                    copy("$pkgdir/1/boot/i386/loader/initrd",
                         "/tftpboot/xcat/$os/$arch/");
                    @dd_drivers = &insert_dd($callback, $os, $arch, "/tftpboot/xcat/$os/$arch/initrd");
                }
                elsif ($arch =~ /ppc/)
                {
                    copy("$pkgdir/1/suseboot/inst64",
                         "/tftpboot/xcat/$os/$arch");
                    @dd_drivers = &insert_dd($callback, $os, $arch, "/tftpboot/xcat/$os/$arch/inst64");
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
	    my $netserver = '!myipfn!';
            if ($ent and $ent->{nfsserver})
            {
		$netserver = $ent->{nfsserver};
            }
            my $kcmdline =
                "quiet autoyast=http://"
              . $netserver
              . "$installroot/autoinst/"
              . $node
              . " install=http://"
              . $netserver
              . "$pkgdir/1";

            my $netdev = "";
            if ($ent->{installnic})
            {
                if ($ent->{installnic} eq "mac")
                {
                    my $mactab = xCAT::Table->new("mac");
                    my $macref = $mactab->getNodeAttribs($node, ['mac']);
                    $netdev = $macref->{mac};
                 }
                else
                {
                    $netdev = $ent->{installnic};
                }
            }
            elsif ($ent->{primarynic})
            {
                if ($ent->{primarynic} eq "mac")
                {
                    my $mactab = xCAT::Table->new("mac");
                    my $macref = $mactab->getNodeAttribs($node, ['mac']);
                    $netdev = $macref->{mac};
                }
                else
                {
                    $netdev = $ent->{primarynic};
                }
            }
            else
            {
                $netdev = "bootif";
            }
            if ($netdev eq "") #why it is blank, no mac defined?
            {
                $callback->(
                    {
                        error => ["No mac.mac for $node defined"],
                        errorcode => [1]
                    }
                );
            }
            unless ($netdev eq "bootif") { #if going by bootif, BOOTIF will suffice
                $kcmdline .= " netdevice=" . $netdev;
            }

            # Add the kernel paramets for driver update disk loading
            foreach (@dd_drivers) {
                $kcmdline .= " dud=file:/cus_driverdisk/$_";
            }

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
                    " console=tty0 console=ttyS"
                  . $sent->{serialport} . ","
                  . $sent->{serialspeed};
                if ($sent and ($sent->{serialflow} =~ /(ctsrts|cts|hard)/))
                {
                    $kcmdline .= "n8r";
                }
            }
            # for pSLES installation, the dhcp request may timeout
            # due to spanning tree settings or multiple network adapters.
            # use dhcptimeout=150 to avoid dhcp timeout
            if ($arch =~ /ppc/)
            {
                $kcmdline .= " dhcptimeout=150";
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
    my $arch;
    my $path;
    $installroot = "/install";
    my $sitetab = xCAT::Table->new('site');
    if ($sitetab)
    {
        (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
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
    if ($distname and $distname !~ /^sles|^suse/)
    {

        #If they say to call it something other than SLES or SUSE, give up?
        return;
    }
    unless (-r $path . "/content")
    {
        return;
    }
    my $dinfo;
    open($dinfo, $path . "/content");
    my $darch;
    while (<$dinfo>)
    {
        if (m/^DEFAULTBASE\s+(\S+)/)
        {
            $darch = $1;
            chomp($darch);
            last;
        }
        if (not $darch and m/^BASEARCHS\s+(\S+)/) {
            $darch = $1;
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

            if ($prod =~ m/SUSE-Linux-Enterprise-Server/ || $prod =~ m/SUSE-Linux-Enterprise-Software-Development-Kit/)
            {
                if (-f "$path/content") {
                    my $content;
                    open($content,"<","$path/content");
                    my @contents = <$content>;
                    close($content);
                    foreach (@contents) {
                        if (/^VERSION/) {
                            my @verpair = split;
                            $detdistname = "sles".$verpair[1];
                            unless ($distname) { $distname = $detdistname; }
                        }
                    }
                } else {
                    my @parts    = split /\s+/, $prod;
                    my @subparts = split /-/,   $parts[2];
                    $detdistname = "sles" . $subparts[0];
                    unless ($distname) { $distname = "sles" . $subparts[0] };
                }
                if($prod =~ m/Software-Development-Kit/) {
                    $discnumber = 'sdk' . $discnumber;
                }
		# check media.1/products for text.  
		# the cselx is a special GE built version.
		# openSUSE is the normal one.
            }elsif($prod =~ m/cselx 1.0-0|openSUSE 11.1-0/){
			$distname = "suse11";
                	$detdistname = "suse11";
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
	my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch);
        if ($ret[0] != 0) {
	    $callback->({data => "Error when updating the osimage tables: " . $ret[1]});
	}
        my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "netboot");
        if ($ret[0] != 0) {
            $callback->({data => "Error when updating the osimage tables for stateless: " . $ret[1]});
        }
        my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "statelite");
        if ($ret[0] != 0) {
            $callback->({data => "Error when updating the osimage tables for statelite: " . $ret[1]});
        }
    }
}

# Get the driver update disk from /install/driverdisk/<os>/<arch>
# Take out the drivers from driver update disk and insert them
# into the initrd

sub insert_dd {
    my $callback = shift;
    my $os = shift;
    my $arch = shift;
    my $img = shift;

    my $install_dir = xCAT::Utils->getInstallDir();

    # Find out the dirver disk which need to be insert into initrd
    if (! -d "$install_dir/driverdisk/$os/$arch") {
	return ();
    }
    my $cmd = "find $install_dir/driverdisk/$os/$arch -type f";
    my @dd_list = xCAT::Utils->runcmd($cmd, -1);
    chomp(@dd_list);
    if (!@dd_list) {
        return undef;
    }

    # Create the tmp dir for dd hack
    my $dd_dir = mkdtemp("/tmp/ddtmpXXXXXXX");
    mkpath "$dd_dir/initrd_img";

    
    my $pkgdir="$install_dir/$os/$arch";
    # Unzip the original initrd
    if ($arch =~ /x86/) {
        $cmd = "gunzip --quiet -c $img > $dd_dir/initrd";
    } elsif ($arch =~/ppc/) {
        $cmd = "gunzip --quiet -c $pkgdir/1/suseboot/initrd64 > $dd_dir/initrd";
    }
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Handle the driver update disk failed. Could not gunzip the initial initrd.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return ();
    }
    
    # Unpack the initrd
    $cmd = "cd $dd_dir/initrd_img; cpio -id --quiet < $dd_dir/initrd";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Handle the driver update disk failed. Could not extract files from the initial initrd.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return ();
    }
    
    # Create the dir for driver update disk
    $cmd = "mkdir -p $dd_dir/initrd_img/cus_driverdisk";
    xCAT::Utils->runcmd($cmd, -1);

    # insert the driver update disk into the cus_driverdisk dir
    foreach my $dd (@dd_list) {
        copy($dd, "$dd_dir/initrd_img/cus_driverdisk");
    }
    
    # Repack the initrd
    # In order to avoid the runcmd add the '2>&1' at end of the cpio
    # cmd, the echo cmd is added at the end
    $cmd = "cd $dd_dir/initrd_img; find . -print | cpio -H newc -o > $dd_dir/initrd | echo";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Handle the driver update disk failed. Could not pack the hacked initrd.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return ();
    }
    
    # zip the initrd
    #move ("$dd_dir/initrd.new", "$dd_dir/initrd");
    $cmd = "gzip -f $dd_dir/initrd";
    xCAT::Utils->runcmd($cmd, -1);

    if ($arch =~ /x86/) {
        copy ("$dd_dir/initrd.gz", "$img");
    } elsif ($arch =~/ppc/) {
        # make sure the src kernel existed
        $cmd = "gunzip -c $pkgdir/1/suseboot/linux64.gz > $dd_dir/kernel";
        xCAT::Utils->runcmd($cmd, -1);
        
        # create the zimage
        $cmd = "env -u POSIXLY_CORRECT /lib/lilo/scripts/make_zimage_chrp.sh --vmlinux $dd_dir/kernel --initrd $dd_dir/initrd.gz --output $img";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp;
            push @{$rsp->{data}}, "Handle the driver update disk failed. Could not pack the hacked initrd.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        }
    }

    my $rsp;
    push @{$rsp->{data}}, "Inserted the driver update disk:".join(',', sort(@dd_list)).".";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    my @dd_files = ();
    foreach my $dd (sort(@dd_list)) {
        chomp($dd);
	$dd =~ s/^.*\///;
	push @dd_files, $dd;
    }

    return sort(@dd_files);    
}

#sub get_tmpl_file_name {
#  my $base=shift;
#  my $profile=shift;
#  my $os=shift;
#  my $arch=shift;
#  if (-r   "$base/$profile.$os.$arch.tmpl") {
#    return "$base/$profile.$os.$arch.tmpl";
#  }
#  elsif (-r "$base/$profile.$os.tmpl") {
#    return  "$base/$profile.$os.tmpl";
#  }
#  elsif (-r "$base/$profile.$arch.tmpl") {
#    return  "$base/$profile.$arch.tmpl";
#  }
#  elsif (-r "$base/$profile.tmpl") {
#    return  "$base/$profile.tmpl";
#  }
#
#  return "";
#}

1;
