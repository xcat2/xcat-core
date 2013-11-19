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
use xCAT::TableUtils;
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
my $httpmethod = "http";
my $httpport = "80";
use File::Find;
use File::Basename;
use Digest::MD5 qw(md5_hex);
use Socket;

use strict;
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

    my $globaltftpdir  = "/tftpboot";
    my $nodes    = @{$req->{node}};
    my @nodes    = @{$req->{node}};
    my $noupdateinitrd = $req->{'noupdateinitrd'};
    my $ignorekernelchk = $req->{'ignorekernelchk'};
    my $ostab    = xCAT::Table->new('nodetype');
    #my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $pkgdir;
    my $osimagetab;
    my $installroot;
    $installroot = "/install";

    my $xcatdport = "3001";
    my $xcatiport = "3002";
    my $nodestatus = "y";
    #if ($sitetab)
    #{
        #(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
        my $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $installroot = $t_entry;
        }
        #($ref) = $sitetab->getAttribs({key => 'xcatdport'}, 'value');
        @entries =  xCAT::TableUtils->get_site_attribute("xcatdport");
        $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $xcatdport = $t_entry;
        }
        @entries =  xCAT::TableUtils->get_site_attribute("xcatiport");
        $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $xcatiport = $t_entry;
        }
        @entries =  xCAT::TableUtils->get_site_attribute("nodestatus");
        $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $nodestatus = $t_entry;
        }

    #}

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
    my $reshash = $restab->getNodesAttribs(\@nodes, ['primarynic', 'tftpserver', 'tftpdir', 'xcatmaster', 'nfsserver', 'nfsdir', 'installnic']);

    my %donetftp=();
    # Warning message for nodeset <noderange> install/netboot/statelite
    foreach my $knode (keys %{$ntents})
    {
        my $ent = $ntents->{$knode}->[0];
        if ($ent && $ent->{provmethod}
            && (($ent->{provmethod} eq 'install') || ($ent->{provmethod} eq 'netboot') || ($ent->{provmethod} eq 'statelite')))
        {
            my @ents = xCAT::TableUtils->get_site_attribute("disablenodesetwarning");
            my $site_ent = $ents[0];
            if (!defined($site_ent) || ($site_ent =~ /no/i) || ($site_ent =~ /0/))
            {
                $callback->(
                            {
                             warning => ["The options \"install\", \"netboot\", and \"statelite\" have been deprecated. They should continue to work in this release, but have not been tested as carefully, and some new functions are not available with these options.  For full function and support, use \"nodeset <noderange> osimage=<osimage_name>\" instead."],
                           }
                            );
                # Do not print this warning message multiple times
                last;
            }
        }
    }
    foreach my $node (@nodes)
    {
        my $osver;
        my $arch;
        my $profile;
        my $provmethod;
        my $rootimgdir;
        my $nodebootif; # nodebootif will be used if noderes.installnic is not set
        my $dump;  #for kdump
        my $crashkernelsize;
        my $rootfstype;
        my $cfgpart;
        my $imagename; # set it if running of 'nodeset osimage=xxx'
	
        my $ent= $ntents->{$node}->[0];
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
            $imagename=$ent->{provmethod};
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
                    (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'rootimgdir', 'nodebootif', 'dump', 'crashkernelsize', 'partitionfile');
                    if (($ref1) && ($ref1->{'rootimgdir'})) {
                        $img_hash{$imagename}->{rootimgdir}=$ref1->{'rootimgdir'};
                    }
                    if (($ref1) && ($ref1->{'nodebootif'})) {
                        $img_hash{$imagename}->{nodebootif} = $ref1->{'nodebootif'};
                    }
                    if (($ref1) && ($ref1->{'dump'})){
                        $img_hash{$imagename}->{dump} = $ref1->{'dump'};
                    }
                    if (($ref1) && ($ref1->{'crashkernelsize'})) {
                        $img_hash{$imagename}->{crashkernelsize} = $ref1->{'crashkernelsize'};
                    }
                    if ($ref1 && $ref1->{'partitionfile'}) {
                        # check the validity of the partition configuration file
                        if ($ref1->{'partitionfile'} =~ /^s:(.*)/) {
                            # the configuration file is a script
                            if (-r $1) {
                                $img_hash{$imagename}->{'cfgpart'} = "yes";
                            }
                        } else {
                            if (open (FILE, "<$ref1->{'partitionfile'}")) {
                                while (<FILE>) {
                                    if (/enable=yes/) {
                                        $img_hash{$imagename}->{'cfgpart'} = "yes";
                                        last;
                                    }
                                }
                            }
                            close (FILE);
                        }
            
                        $img_hash{$imagename}->{'partfile'} = $ref1->{'partitionfile'};
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
            $provmethod = $ph->{provmethod};
            $dump = $ph->{dump};
            $crashkernelsize = $ph->{crashkernelsize};
            $cfgpart = $ph->{'cfgpart'};
            
            $rootimgdir = $ph->{rootimgdir};
            unless ($rootimgdir) {
                $rootimgdir = "$installroot/netboot/$osver/$arch/$profile";
            }
        }else {
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

            #get the dump path and kernel crash memory side for kdump on sles
            if (!$linuximagetab){
                $linuximagetab = xCAT::Table->new('linuximage');
            }
            if ($linuximagetab){
                 (my $ref1) = $linuximagetab->getAttribs({imagename => $imgname}, 'dump', 'crashkernelsize', 'partitionfile');
                 if ($ref1 && $ref1->{'dump'}){
                 $dump = $ref1->{'dump'};
                 }
                 if ($ref1 and $ref1->{'crashkernelsize'}){
                 $crashkernelsize = $ref1->{'crashkernelsize'};
                 }
                 if($ref1 and $ref1->{'partitionfile'})  {
                     # check the validity of the partition configuration file
                     if ($ref1->{'partitionfile'} =~ /^s:(.*)/) {
                         # the configuration file is a script
                         if (-r $1) {
                             $cfgpart = "yes";
                         }
                     } else {
                         if (-r $ref1->{'partitionfile'} && open (FILE, "<$ref1->{'partitionfile'}")) {
                             while (<FILE>) {
                                 if (/enable=yes/) {
                                     $cfgpart = "yes";
                                     last;
                                 }
                             }
                         }
                         close (FILE);
                     }
                 }
            }
            else{
                $callback->(
                { error => [qq{ Cannot find the linux image called "$osver-$arch-$imgname-$profile", maybe you need to use the "nodeset <nr> osimage=<your_image_name>" command to set the boot state}],
                errorcode => [1] }
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
        my $tftpdir;
 	if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{tftpdir}) {
	   $tftpdir = $reshash->{$node}->[0]->{tftpdir};
        } else {
	   $tftpdir = $globaltftpdir;
        }


        # Copy the boot resource to /tftpboot and check to only copy once
        my $docopy = 0;
        my $tftppath;
        my $rtftppath; # the relative tftp path without /tftpboot/
        if ($imagename) {
            $tftppath = "$tftpdir/xcat/osimage/$imagename";
            $rtftppath = "xcat/osimage/$imagename";
            unless ($donetftp{$imagename}) {
                $docopy = 1;
                $donetftp{$imagename} = 1;
            }
        } else {
            $tftppath = "/$tftpdir/xcat/netboot/$osver/$arch/$profile/";
            $rtftppath = "xcat/netboot/$osver/$arch/$profile/";
            unless ($donetftp{$osver,$arch,$profile,$tftpdir}) {
                $docopy = 1;
                $donetftp{$osver,$arch,$profile,$tftpdir} = 1;
            }
        }

        if ($docopy && !$noupdateinitrd) {
            mkpath("$tftppath");
            copy("$rootimgdir/kernel", "$tftppath");
            if ($statelite) {
                copy("$rootimgdir/initrd-statelite.gz", "$tftppath");
            } else {
                copy("$rootimgdir/initrd-stateless.gz", "$tftppath");
            }
        }

        if ($statelite) {
            unless ( -r "$tftppath/kernel" and -r "$tftppath/initrd-statelite.gz" ) {
                $callback->({
                    error=>[qq{copying to $tftppath failed}],
                    errorcode=>[1]
                });
                next;
            }
        } else {
            unless ( -r "$tftppath/kernel" 
                    and -r "$tftppath/initrd-stateless.gz") {
                $callback->({
                    error=>[qq{copying to $tftppath failed}],
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
                    "imgurl=$httpmethod://$imgsrv/$rootimgdir/rootimg-statelite.gz STATEMNT=";
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
              "imgurl=$httpmethod://$imgsrv/$rootimgdir/rootimg.$suffix ";
        }
        $kcmdline .= "XCAT=$xcatmaster:$xcatdport quiet ";
        
        #if site.nodestatus="n", append "nonodestatus" to kcmdline 
        #to inform the statelite/stateless node not to update the nodestatus during provision
        if(($nodestatus eq "n") or ($nodestatus eq "N") or ($nodestatus eq "0")){
           $kcmdline .= " nonodestatus ";
        }

        $kcmdline .= "NODE=$node ";

        # add the kernel-booting parameter: netdev=<eth0>, or BOOTIF=<mac>
        my $netdev = "";
        my $mac = $machash->{$node}->[0]->{mac};

        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{installnic} and ($reshash->{$node}->[0]->{installnic} ne "mac")) {
                $kcmdline .= "netdev=" . $reshash->{$node}->[0]->{installnic} . " ";
        } elsif ($nodebootif) {
            $kcmdline .=  "netdev=" . $nodebootif . " ";
        } elsif ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{primarynic} and ($reshash->{$node}->[0]->{primarynic} ne "mac")) {
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


         if (defined $sent->{serialport}) {
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

        #create the kcmd for node to support kdump
        if ($dump){
            if ($crashkernelsize){
                $kcmdline .= " crashkernel=$crashkernelsize dump=$dump ";
            }
            else{
                # for ppc64, the crashkernel paramter should be "128M@32M", otherwise, some kernel crashes will be met
                if ($arch eq "ppc64"){
                	$kcmdline .= " crashkernel=256M\@64M dump=$dump ";
                }
                if ($arch =~ /86/){
                	$kcmdline .= " crashkernel=128M dump=$dump ";
                }
            }
        }
        # add the cmdline parameters for handling the local disk for stateless
        if ($cfgpart eq "yes") {
            if ($statelite) {
                $kcmdline .= " PARTITION_SLES";
            } else {
                $kcmdline .= " PARTITION_DOMOUNT_SLES";
            }
        }

        my $initrdstr = "$rtftppath/initrd-stateless.gz";
        $initrdstr = "$rtftppath/initrd-statelite.gz" if ($statelite);

        if($statelite)
        {
            my $statelitetb = xCAT::Table->new('statelite');
            my $mntopts = $statelitetb->getNodeAttribs($node, ['mntopts']);
            
            my $mntoptions = $mntopts->{'mntopts'};
            if(defined($mntoptions)) {
                $kcmdline .= "MNTOPTS=\'$mntoptions\'";
            }			
        }
        $bptab->setNodeAttribs(
            $node,
            {
            kernel => "$rtftppath/kernel",
            initrd => $initrdstr,
            kcmdline => $kcmdline
            });
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
    if ($::XCATSITEVALS{"httpmethod"}) { $httpmethod = $::XCATSITEVALS{"httpmethod"}; }
    if ($::XCATSITEVALS{"httpport"}) { $httpport = $::XCATSITEVALS{"httpport"}; }
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
    my $globaltftpdir = xCAT::TableUtils->getTftpDir();

    my $noupdateinitrd = $request->{'noupdateinitrd'};
    my $ignorekernelchk = $request->{'ignorekernelchk'};
    my @nodes    = @{$request->{node}};
    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    #my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my $osdistrouptab;

    my $ntents = $ostab->getNodesAttribs($request->{node}, ['os', 'arch', 'profile', 'provmethod']);
    my %img_hash=();
    my $installroot;
    $installroot = "/install";
            my $restab = xCAT::Table->new('noderes');
            my $bptab = xCAT::Table->new('bootparams',-create=>1);
            my $hmtab  = xCAT::Table->new('nodehm');
            my $resents    = 
              $restab->getNodesAttribs(
                                      \@nodes,
                                      [
                                       'nfsserver', 'tftpdir','xcatmaster',
                                       'primarynic', 'installnic'
                                      ]
                                      );
            my $hments =
              $hmtab->getNodesAttribs(\@nodes, ['serialport', 'serialspeed', 'serialflow']);

    #if ($sitetab)
    #{
        #(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
        my $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $installroot = $t_entry;
        }
    #}

    my %donetftp;
    require xCAT::Template; #only used here, load so memory can be COWed
    # Define a variable for driver update list
    my @dd_drivers;

    # Warning message for nodeset <noderange> install/netboot/statelite
    foreach my $knode (keys %{$ntents})
    {
        my $ent = $ntents->{$knode}->[0];
        if ($ent && $ent->{provmethod}
            && (($ent->{provmethod} eq 'install') || ($ent->{provmethod} eq 'netboot') || ($ent->{provmethod} eq 'statelite')))
        {
            my @ents = xCAT::TableUtils->get_site_attribute("disablenodesetwarning");
            my $site_ent = $ents[0];
            if (!defined($site_ent) || ($site_ent =~ /no/i) || ($site_ent =~ /0/))
            {
                $callback->(
                           { 
                             warning => ["The options \"install\", \"netboot\", and \"statelite\" have been deprecated. They should continue to work in this release, but have not been tested as carefully, and some new functions are not available with these options.  For full function and support, use \"nodeset <noderange> osimage=<osimage_name>\" instead."],
                           }
                           );
                # Do not print this warning message multiple times
                last;
            }
        }
    }

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
        my $tftpdir;
        my $partfile;
        my $netdrivers;
        my $driverupdatesrc;
        my $osupdir;
        my $imagename; # set it if running of 'nodeset osimage=xxx'
        if ($resents->{$node} and $resents->{$node}->[0]->{tftpdir}) {
	   $tftpdir = $resents->{$node}->[0]->{tftpdir};
        } else {
	   $tftpdir = $globaltftpdir;
        }

        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
	    $imagename=$ent->{provmethod};
	    if (!exists($img_hash{$imagename})) {
		if (!$osimagetab) {
		    $osimagetab=xCAT::Table->new('osimage', -create=>1);
		}
		(my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod', 'osupdatename');
		if ($ref) {
		    $img_hash{$imagename}->{osver}=$ref->{'osvers'};
		    $img_hash{$imagename}->{osarch}=$ref->{'osarch'};
		    $img_hash{$imagename}->{profile}=$ref->{'profile'};
		    $img_hash{$imagename}->{provmethod}=$ref->{'provmethod'};
		    if (!$linuximagetab) {
			$linuximagetab=xCAT::Table->new('linuximage', -create=>1);
		    }
		    (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'template', 'pkgdir', 'pkglist', 'partitionfile', 'driverupdatesrc', 'netdrivers');
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
            if ($ref1->{'partitionfile'}) {
                $img_hash{$imagename}->{partitionfile}=$ref1->{'partitionfile'};
            }
			if ($ref1->{'driverupdatesrc'}) {
			    $img_hash{$imagename}->{driverupdatesrc}=$ref1->{'driverupdatesrc'};
			}
			if ($ref1->{'netdrivers'}) {
			    $img_hash{$imagename}->{netdrivers}=$ref1->{'netdrivers'};
			}
		    }
		} else {
		    $callback->(
			{error     => ["The os image $imagename does not exists on the osimage table for $node"],
			 errorcode => [1]});
		    next;
		}

		   # get the path list of the osdistroupdate
                if ($ref->{'osupdatename'}) {
                    my $osdisupdir;
                    my @osupdatenames = split (/,/, $ref->{'osupdatename'});
                    
                    unless ($osdistrouptab) {
                        $osdistrouptab=xCAT::Table->new('osdistroupdate', -create=>1);
                        unless ($osdistrouptab) {
                            $callback->({ error => ["Cannot open the table osdistroupdate."], errorcode => [1] });
                            next;
                        }
                    }
                    my @osdup = $osdistrouptab->getAllAttribs("osupdatename", "dirpath");
                    foreach my $upname (@osupdatenames) {
                        foreach my $upref (@osdup) {
                            if ($upref->{'osupdatename'} eq $upname) {
                                $osdisupdir .= ",$upref->{'dirpath'}";
                                last;
                            }
                        }
                    }

                    $osdisupdir =~ s/^,//;
                    $img_hash{$imagename}->{'osupdir'} = $osdisupdir;
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
        $partfile=$ph->{partitionfile};
	    $netdrivers = $ph->{netdrivers};
	    $driverupdatesrc = $ph->{driverupdatesrc};
	    $osupdir = $ph->{'osupdir'};
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

        #get the partition file from the linuximage table
        my $imgname = "$os-$arch-install-$profile";

        if (! $linuximagetab) {
            $linuximagetab = xCAT::Table->new('linuximage');
        }

        if ( $linuximagetab ) {
            (my $ref1) = $linuximagetab->getAttribs({imagename => $imgname}, 'partitionfile');
            if ( $ref1 and $ref1->{'partitionfile'}){
                $partfile = $ref1->{'partitionfile'};
            }
        }
        else {
            $callback->(
                { error => [qq{ Cannot find the linux image called "$imgname", maybe you need to use the "nodeset <nr> osimage=<your_image_name>" command to set the boot state}], errorcode => [1] }
            );
        }
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
      
        
        #To support multiple paths for osimage.pkgdir. We require the first value of osimage.pkgdir
        # should be the os base pkgdir.
        my $tmppkgdir=$pkgdir;
        my @srcdirs = split(",", $pkgdir);
        $pkgdir = $srcdirs[0];
        if( $pkgdir =~/^($installroot\/$os\/$arch)$/) {
            $srcdirs[0]="$pkgdir/1";
            $tmppkgdir=join(",", @srcdirs);
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
		         $tmppkgdir,
                 $os,
                 $partfile
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
            #TODO: driver slipstream, targetted for network.
            
            # Copy the install resource to /tftpboot and check to only copy once
            my $docopy = 0;
            my $tftppath;
            my $rtftppath; # the relative tftp path without /tftpboot/
            if ($imagename) {
                $tftppath = "/$tftpdir/xcat/osimage/$imagename";
                $rtftppath = "xcat/osimage/$imagename";
                unless ($donetftp{$imagename}) {
                    $docopy = 1;
                    $donetftp{$imagename} = 1;
                }
            } else {
                $tftppath = "/$tftpdir/xcat/$os/$arch/$profile";
                $rtftppath = "xcat/$os/$arch/$profile";
                unless ($donetftp{"$os|$arch|$profile|$tftpdir"}) {
                    $docopy = 1;
                    $donetftp{"$os|$arch|$profile|$tftpdir"} = 1;
                }
            }
            
            if ($docopy) {
                mkpath("$tftppath");
                if ($arch =~ /x86_64/)
                {
                    unless ($noupdateinitrd) {
                        copy("$pkgdir/1/boot/$arch/loader/linux", "$tftppath");
                        copy("$pkgdir/1/boot/$arch/loader/initrd", "$tftppath");
                        @dd_drivers = &insert_dd($callback, $os, $arch, "$tftppath/initrd", "$tftppath/linux", $driverupdatesrc, $netdrivers, $osupdir, $ignorekernelchk);
                    }
                } elsif ($arch =~ /x86/) {
                    unless ($noupdateinitrd) {
                        copy("$pkgdir/1/boot/i386/loader/linux", "$tftppath");
                        copy("$pkgdir/1/boot/i386/loader/initrd", "$tftppath");
                        @dd_drivers = &insert_dd($callback, $os, $arch, "$tftppath/initrd", "$tftppath/linux", $driverupdatesrc, $netdrivers, $osupdir, $ignorekernelchk);
                    }
                }
                elsif ($arch =~ /ppc/)
                {
                    unless ($noupdateinitrd) {
                        copy("$pkgdir/1/suseboot/inst64", "$tftppath");
                        @dd_drivers = &insert_dd($callback, $os, $arch, "$tftppath/inst64", undef, $driverupdatesrc, $netdrivers, $osupdir, $ignorekernelchk);
                    }
                }
            }

            #We have a shot...
            my $ent    = $resents->{$node}->[0]; 
            my $sent = $hments->{$node}->[0]; #hmtab->getNodeAttribs($node, ['serialport', 'serialspeed', 'serialflow']);

            my $netserver;
            if ($ent and $ent->{xcatmaster}) {
                $netserver = $ent->{xcatmaster};
            } else {
                $netserver = '!myipfn!';
            }
            if ($ent and $ent->{nfsserver})
            {
		$netserver = $ent->{nfsserver};
            }
            my $httpprefix = $pkgdir;
	    if ($installroot =~ /\/$/) { #must prepend /install/
		$httpprefix =~ s/^$installroot/\/install\//;
	    } else {
		$httpprefix =~ s/^$installroot/\/install/;
            }
            my $kcmdline =
                "quiet autoyast=$httpmethod://"
              . $netserver . ":" . $httpport
              . "/install/autoinst/"
              . $node
              . " install=$httpmethod://"
              . $netserver . ":" . $httpport
              . "$httpprefix/1";

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

            my $kernelpath;
            my $initrdpath;
            
            if ($arch =~ /x86/)
            {
                $kernelpath = "$rtftppath/linux";
                $initrdpath = "$rtftppath/initrd";
                $bptab->setNodeAttribs(
                                        $node,
                                        {
                                         kernel   => $kernelpath,
                                         initrd   => $initrdpath,
                                         kcmdline => $kcmdline
                                        }
                                        );
            }
            elsif ($arch =~ /ppc/)
            {
                $kernelpath = "$rtftppath/inst64";
                $bptab->setNodeAttribs(
                                        $node,
                                        {
                                         kernel   => $kernelpath,
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
    #my $rc = xCAT::TableUtils->create_postscripts_tar();
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
    my $mntpath=undef;
    my $inspection=undef;
    my $noosimage=undef;
    my $nonoverwrite=undef;

    $installroot = "/install";
    #my $sitetab = xCAT::Table->new('site');
    #if ($sitetab)
    #{
        #(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
        #print Dumper($ref);
        my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
        my $t_entry = $entries[0];
        if ( defined($t_entry) ) {
            $installroot = $t_entry;
        }
    #}

    @ARGV = @{$request->{arg}};
    GetOptions(
               'n=s' => \$distname,
               'a=s' => \$arch,
               'm=s' => \$mntpath,
	       'i'   => \$inspection,
               'p=s' => \$path,
	       'o'   => \$noosimage,
               'w'   => \$nonoverwrite,
	       );
    unless ($mntpath)
    {

        #this plugin needs $mntpath...
        return;
    }
    if ($distname and $distname !~ /^sles|^suse/)
    {

        #If they say to call it something other than SLES or SUSE, give up?
        return;
    }

    #parse the disc info of the os media to get the distribution, arch of the os
    unless (-r $mntpath . "/content")
    {
        return;
    }
    my $dinfo;
    open($dinfo, $mntpath . "/content");
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
    opendir($dirh, $mntpath);
    my $discnumber;
    my $totaldiscnumber;
    while (my $pname = readdir($dirh))
    {
        if ($pname =~ /media.(\d+)/)
        {
            $discnumber = $1;
            chomp($discnumber);
            my $mfile;
            open($mfile, $mntpath . "/" . $pname . "/media");
            <$mfile>;
            <$mfile>;
            $totaldiscnumber = <$mfile>;
            chomp($totaldiscnumber);
            close($mfile);
            open($mfile, $mntpath . "/" . $pname . "/products");
            my $prod = <$mfile>;
            close($mfile);

            if ($prod =~ m/SUSE-Linux-Enterprise-Server/ || $prod =~ m/SUSE-Linux-Enterprise-Software-Development-Kit/)
            {
                if (-f "$mntpath/content") {
                    my $content;
                    open($content,"<","$mntpath/content");
                    my @contents = <$content>;
                    close($content);
                    foreach (@contents) {
                        if (/^VERSION/) {
                            my @verpair = split /\s+|-/;
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
  
    closedir($dirh);

    unless ($distname and $discnumber)
    {
            #failed to parse the disc info    
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

    if($inspection)
    {
            $callback->(
                {
                 info =>
                   "DISTNAME:$distname\n"."ARCH:$arch\n"."DISCNO:$discnumber\n"
                }
                );
            return;
    }

    %{$request} = ();    #clear request we've got it.
    my $defaultpath="$installroot/$distname/$arch";
    unless($path)
    {
        $path=$defaultpath;
    }
    my $osdistroname=$distname."-".$arch;
    if ($::XCATSITEVALS{osimagerequired}){
	   my ($nohaveimages,$errstr) = xCAT::SvrUtils->update_tables_with_templates($distname, $arch,$path,$osdistroname,checkonly=>1);
	   if ($nohaveimages) { 
        	$callback->({error => "No Templates found to support $distname($arch)",errorcode=>2});
		return;
	   }
    }

    my $ospkgpath= "$path/$discnumber";
  
    #tranverse the directory structure of the os media and get the fingerprint     
    my @filelist=();
    find(
         {
          "wanted"   => sub{s/$mntpath/\./;push(@filelist,$_);},
          "no_chdir" => 1,
          "follow"   => 0,
         },
         $mntpath
        );
    my @sortedfilelist=sort @filelist;
    my $fingerprint=md5_hex(join("",@sortedfilelist));
    
    #check whether the os media has already been copied in
    my $disccopiedin=0;
    my $tabosdistro=xCAT::Table->new('osdistro',-create=>1);
    if($tabosdistro)
    {
       my %keyhash=();
       $keyhash{osdistroname} = $osdistroname;
       my $ref = undef;
       $ref=$tabosdistro->getAttribs(\%keyhash, 'dirpaths');
       if ($ref and $ref->{dirpaths} )
       {
          my @dirpaths=split(',',$ref->{dirpaths});
          foreach(@dirpaths)
          {
             if(0 == system("grep -E "."\"\\<$fingerprint\\>\""."  $_"."/.fingerprint"))
             {
	       $disccopiedin=1;
               if($nonoverwrite)
               {
                  $callback->(
                              {
                               info =>
                 	              ["The disc iso has already been copied in!"]
			      }	       
		             );
                  $tabosdistro->close();
	          return;
	       }
	       last;
             }
         }
      }
     }
    $tabosdistro->close();

    #create the destination directory of the os media copying    
    if(-l $ospkgpath)
    {
        unlink($ospkgpath);
    }elsif(-d $ospkgpath)
    {
	rmtree($ospkgpath);	
    }
    mkpath("$ospkgpath");

    my $omask = umask 0022;
    umask $omask;

    $callback->(
         {data => "Copying media to $ospkgpath"});

    my $rc;

    #the intrupt handler of SIGINT and SIGTERM    
    $SIG{INT} =  $SIG{TERM} = sub {
       foreach(@cpiopid){
          kill 15, $_;
          use POSIX ":sys_wait_h";
          my $kid=0;
          do {
                $kid = waitpid($_, WNOHANG);
          } while $kid != $_;
      }
      if ($mntpath) {
            chdir("/");
            system("umount $mntpath");
            system("rm -rf $mntpath");
      }
       exit;
    };

    #media copy process    
    my $kid;
    chdir $mntpath;
    my $numFiles = scalar(@sortedfilelist);
    my $child = open($kid,"|-");
    unless (defined $child) {
      $callback->({error=>"Media copy operation fork failure"});
      return;
    }
    if ($child) {
       push @cpiopid,$child;
       chdir("/");
       for (@sortedfilelist) {
          print $kid $_."\n";
       }
       close($kid);
       $rc = $?;
    } else {
        my $c = "nice -n 20 cpio -vdump $ospkgpath";
        my $k2 = open(PIPE, "$c 2>&1 |") || exit(1);
        chdir("/");
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
        if($copied == $numFiles)
        {
                #media copy success		
		exit(0);
	}
	else
        {
                #media copy failed		
                exit(1);
        }
    }
    #  system(
    #    "cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch/$discnumber/"
    #    );
    chmod 0755, "$path";
    chmod 0755, "$ospkgpath"; 


    #append the fingerprint to the .fingerprint file to indicate that the os media has been copied in    
    unless($disccopiedin)
    {
	my $ret=open(my $fpd,">>","$path/.fingerprint");
	if($ret){
        	print $fpd "$fingerprint,";
        	close($fpd);
	}
    }

    #if the destination path is not the default, create a symlink named by the default path to the specified path   
    unless($path =~ /^($defaultpath)/)
    {
	mkpath("$defaultpath/$discnumber");
        if(-d "$defaultpath/$discnumber")
        {
                rmtree("$defaultpath/$discnumber");
        }
        else
        {
                unlink("$defaultpath/$discnumber");
        }

        my $hassymlink = eval { symlink("",""); 1 };
        if ($hassymlink) {
                symlink($ospkgpath,"$defaultpath/$discnumber");
        }else
        {
                link($ospkgpath,"$defaultpath/$discnumber");
        }

    }

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

	my @ret=xCAT::SvrUtils->update_osdistro_table($distname,$arch,$path,$osdistroname);
        if ($ret[0] != 0) {
            $callback->({data => "Error when updating the osdistro tables: " . $ret[1]});
        }

	#if --noosimage option is not specified, create the relevant osimage and linuximage entris	
	unless($noosimage){
   	   my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch,$path,$osdistroname);
	   if ($ret[0] != 0) {
	       $callback->({data => "Error when updating the osimage tables: " . $ret[1]});
	   }

           my @ret=xCAT::SvrUtils->update_tables_with_mgt_image($distname, $arch, $path,$osdistroname);
           if ($ret[0] != 0) {
               $callback->({data => "Error when updating the osimage tables for management node " . $ret[1]});
           }
           
	   my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "netboot",$path,$osdistroname);
	   if ($ret[0] != 0) {
	       $callback->({data => "Error when updating the osimage tables for stateless: " . $ret[1]});
	   }

           my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "statelite",$path,$osdistroname);
	   if ($ret[0] != 0) {
	       $callback->({data => "Error when updating the osimage tables for statelite: " . $ret[1]});
	   }
	}
    }
}

# callback subroutine for 'find' command to return the path
my $driver_name;
my $real_path;
sub get_path ()
{
    if ($File::Find::name =~ /\/$driver_name/) {
        $real_path = $File::Find::name;
    }
}

# callback subroutine for 'find' command to return the path for all the matches
my @all_real_path;
sub get_all_path ()
{
    if ($File::Find::name =~ /\/$driver_name/) {
        push @all_real_path, $File::Find::name;
    }
}

# Get the driver disk or driver rpm from the osimage.driverupdatesrc
# The valid value: dud:/install/dud/dd.img,rpm:/install/rpm/d.rpm, if missing the tag: 'dud'/'rpm'
# the 'rpm' is default.
#
# If cannot find the driver disk from osimage.driverupdatesrc, will try to search driver disk 
# from /install/driverdisk/<os>/<arch>
#
# For driver rpm, the driver list will be gotten from osimage.netdrivers. If not set, copy all the drivers from driver 
# rpm to the initrd.
#

sub insert_dd () {
    my $callback = shift;
    if ($callback eq "xCAT_plugin::sles") {
        $callback = shift;
    }
    my $os = shift;
    my $arch = shift;
    my $img = shift;
    my $kernelpath = shift;
    my $driverupdatesrc = shift;
    my $drivers = shift;
    my $osupdirlist = shift;
    my $ignorekernelchk = shift;

    my $install_dir = xCAT::TableUtils->getInstallDir();

    my $cmd;
    
    my @dd_list;
    my @rpm_list;
    my @vendor_rpm; # the rpms from driverupdatesrc attribute
    my @driver_list;
    my $Injectalldriver;
    my $updatealldriver;

    my @rpm_drivers;

    # since the all rpms for drivers searching will be extracted to one dir, the newer rpm should be
    # extracted later so that the newer drivers will overwirte the older one if certain drvier is included 
    # in multiple rpms
    # 
    # The order of rpm list in the @rpm_list should be: osdistroupdate1, osdistroupdate2, driverupdatesrc
    #
    # get the kernel-*.rpm from the dirpath of osdistroupdate
    if ($osupdirlist) {
        my @osupdirs = split (/,/, $osupdirlist);
        foreach my $osupdir (@osupdirs) {
            # find all the rpms start with kernel.*
            my @kernel_rpms = `find $osupdir -name kernel-*.rpm`;
            push @rpm_list, @kernel_rpms;
        }
    }
    
    # Parse the parameters to the the source of Driver update disk and Driver rpm, and driver list as well
    if ($driverupdatesrc) {
        my @srcs = split(',', $driverupdatesrc);
        foreach my $src (@srcs) {
            if ($src =~ /dud:(.*)/i) {
                push @dd_list, $1;
            } elsif ($src =~ /rpm:(.*)/i) {
                push @rpm_list, $1;
                push @vendor_rpm, $1;
            } else {
                push @rpm_list, $src;
                push @vendor_rpm, $src;
            }
        }
    }
    if (! @dd_list) {
        # get Driver update disk from the default path if not specified in osimage
        # check the Driver Update Disk images, it can be .img or .iso
        if (-d "$install_dir/driverdisk/$os/$arch") {
            $cmd = "find $install_dir/driverdisk/$os/$arch -type f";
            @dd_list = xCAT::Utils->runcmd($cmd, -1);
        }
    }

    foreach (split /,/,$drivers) {
        if (/^allupdate$/) {
            $Injectalldriver = 1;
            next;
        } elsif (/^updateonly$/) {
            $updatealldriver = 1;
            next;
        }
        unless (/\.ko$/) {
            s/$/.ko/;
        }
        push @driver_list, $_;
    }

    chomp(@dd_list);
    chomp(@rpm_list);
    chomp(@vendor_rpm);
    
    unless (@dd_list || (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list))) {
        return ();
    }

    # Create the tmp dir for dd hack
    my $dd_dir = mkdtemp("/tmp/ddtmpXXXXXXX");
    mkpath "$dd_dir/initrd_img";

    
    my $pkgdir="$install_dir/$os/$arch";
    # Unzip the original initrd
    # This only needs to be done for ppc or handling the driver rpm
    # For the driver disk against x86, append the driver disk to initrd directly
    if ($arch =~/ppc/ || (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list))) {
        if ($arch =~ /ppc/) {
            $cmd = "gunzip --quiet -c $pkgdir/1/suseboot/initrd64 > $dd_dir/initrd";
        } elsif ($arch =~ /x86/) {
            $cmd = "gunzip --quiet -c $img > $dd_dir/initrd";
        }
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp;
            push @{$rsp->{data}}, "Handle the driver update failed. Could not gunzip the initial initrd.";
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

        # Start to load the drivers from rpm packages
        if (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list)) {
            # Extract the files from rpm to the tmp dir
            mkpath "$dd_dir/rpm";
            my $new_kernel_ver;
            foreach my $rpm (@rpm_list) {
                if (-r $rpm) {
                    $cmd = "cd $dd_dir/rpm; rpm2cpio $rpm | cpio -idum";
                    xCAT::Utils->runcmd($cmd, -1);
                    if ($::RUNCMD_RC != 0) {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not extract files from the rpm $rpm.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not read the rpm $rpm.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                # get the new kernel if it exists in the update distro
                my @new_kernels = <$dd_dir/rpm/boot/vmlinu*>;
                foreach my $new_kernel (@new_kernels) {
                    if (-r $new_kernel && $new_kernel =~ /\/vmlinu[zx]-(.*(x86_64|ppc64|default))$/) {
                        $new_kernel_ver = $1;
                        $cmd = "/bin/mv -f $new_kernel $dd_dir/rpm/newkernel";
                        xCAT::Utils->runcmd($cmd, -1);
                        if ($::RUNCMD_RC != 0) {
                            my $rsp;
                            push @{$rsp->{data}}, "Handle the driver update failed. Could not move $new_kernel to $dd_dir/rpm/newkernel.";
                            xCAT::MsgUtils->message("I", $rsp, $callback);
                        }
                    }
                } 
            }

            # Extract files from vendor rpm when $ignorekernelchk is specified
            if ($ignorekernelchk) {
                mkpath "$dd_dir/vendor_rpm";
                foreach my $rpm (@vendor_rpm) {
                    if (-r $rpm) {
                        $cmd = "cd $dd_dir/vendor_rpm; rpm2cpio $rpm | cpio -idum";
                        xCAT::Utils->runcmd($cmd, -1);
                        if ($::RUNCMD_RC != 0) {
                            my $rsp;
                            push @{$rsp->{data}}, "Handle the driver update failed. Could not extract files from the rpm $rpm.";
                            xCAT::MsgUtils->message("I", $rsp, $callback);
                        }
                    } else {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not read the rpm $rpm.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }
            }

            # To skip the conflict of files that some rpm uses the xxx.ko.new as the name of the driver
            # Change it back to xxx.ko here
            $driver_name = "\*ko.new";
            @all_real_path = ();
            my @rpmfiles = <$dd_dir/rpm/*>;
            if ($ignorekernelchk) {
                push @rpmfiles, <$dd_dir/vendor_rpm/*>;
            }
            find(\&get_all_path, @rpmfiles);
            foreach my $file (@all_real_path) {
                my $newname = $file;
                $newname =~ s/\.new$//;
                $cmd = "mv -f $file $newname";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not rename $file.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }

            # Copy the firmware to the rootimage
            if (-d "$dd_dir/rpm/lib/firmware") {
                if (! -d "$dd_dir/initrd_img/lib") {
                    mkpath "$dd_dir/initrd_img/lib";
                }
                $cmd = "/bin/cp -rf $dd_dir/rpm/lib/firmware $dd_dir/initrd_img/lib";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not copy firmware to the initrd.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }

            # if the new kernel from update distro is not existed in initrd, create the path for it
            if (! -r "$dd_dir/initrd_img/lib/modules/$new_kernel_ver/") {
                mkpath ("$dd_dir/initrd_img/lib/modules/$new_kernel_ver/");
                # link the /modules to this new kernel dir
                unlink "$dd_dir/initrd_img/modules";
                $cmd = "/bin/ln -sf lib/modules/$new_kernel_ver/initrd $dd_dir/initrd_img/modules";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not create link to the new kernel dir.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }

            # get the name list for all drivers in the original initrd if 'netdrivers=updateonly'
            # then only the drivers in this list will be updated from the drvier rpms
            if ($updatealldriver) {
                $driver_name = "\*\.ko";
                @all_real_path = ();
                find(\&get_all_path, <$dd_dir/initrd_img/lib/modules/*>);
                foreach my $real_path (@all_real_path) {
                    my $driver = basename($real_path);
                    push @driver_list, $driver;
                }
            }
            
            # Copy the drivers to the rootimage
            # Figure out the kernel version
            my @kernelpaths = <$dd_dir/initrd_img/lib/modules/*>;
            my @kernelvers;
            if ($new_kernel_ver) {
                push @kernelvers, $new_kernel_ver;
            }
            foreach (@kernelpaths) {
                my $kernelv = basename($_);
                if ($kernelv =~ /^[\d\.]+/) {
                    if ($new_kernel_ver) {
                        rmtree ("$dd_dir/initrd_img/lib/modules/$kernelv");
                    } else {
                        push @kernelvers, $kernelv;
                    }
                }
            }
                    
            foreach my $kernelver (@kernelvers) {
              # if $ignorekernelchk is specified, copy all files from vendor_rpm dir to target kernel dir
              if ($ignorekernelchk) {
                  my @kernelpath4vrpm = <$dd_dir/vendor_rpm/lib/modules/*>;
                  foreach my $path (@kernelpath4vrpm) {
                      unless (-d "$dd_dir/rpm/lib/modules/$kernelver") {
                          mkpath "$dd_dir/rpm/lib/modules/$kernelver";
                      }
                      $cmd = "/bin/cp -rf $path/* $dd_dir/rpm/lib/modules/$kernelver";
                      xCAT::Utils->runcmd($cmd, -1);
                      if ($::RUNCMD_RC != 0) {
                          my $rsp;
                          push @{$rsp->{data}}, "Handle the driver update failed. Could not copy driver $path from vendor rpm.";
                          xCAT::MsgUtils->message("I", $rsp, $callback);
                      }
                  }
              }

              unless (-d "$dd_dir/rpm/lib/modules/$kernelver") {
                  next;
              }

              if (@driver_list) {
                # copy the specific drivers to initrd
                foreach my $driver (@driver_list) {
                  $driver_name = $driver;
                  @all_real_path = ();
                  find(\&get_all_path, <$dd_dir/rpm/lib/modules/$kernelver/*>);
                  # NOTE: for the initrd of sles that the drivers are put in the /lib/modules/$kernelver/initrd/
                  foreach my $real_path (@all_real_path) { 
                      if ($real_path && $real_path =~ m!$dd_dir/rpm/lib/modules/$kernelver/!) {
                          if (! -d "$dd_dir/initrd_img/lib/modules/$kernelver/initrd") {
                              mkpath "$dd_dir/initrd_img/lib/modules/$kernelver/initrd";
                          }
                          $cmd = "/bin/cp -rf $real_path $dd_dir/initrd_img/lib/modules/$kernelver/initrd";
                          xCAT::Utils->runcmd($cmd, -1);
                          if ($::RUNCMD_RC != 0) {
                              my $rsp;
                              push @{$rsp->{data}}, "Handle the driver update failed. Could not copy driver $driver to the initrd.";
                              xCAT::MsgUtils->message("I", $rsp, $callback);
                          } else {
                              push @rpm_drivers, $driver;
                          }
                      }
                  }
                }
              } elsif ($Injectalldriver) {
                # copy all the drviers to the initrd
                $driver_name = "\*\.ko";
                @all_real_path = ();
                find(\&get_all_path, <$dd_dir/rpm/lib/modules/$kernelver/*>);
                foreach my $real_path (@all_real_path) {
                  # NOTE: for the initrd of sles that the drivers are put in the /lib/modules/$kernelver/initrd/
                  if ($real_path && $real_path =~ m!$dd_dir/rpm/lib/modules/$kernelver/!) {
                      if (! -d "$dd_dir/initrd_img/lib/modules/$kernelver/initrd") {
                          mkpath "$dd_dir/initrd_img/lib/modules/$kernelver/initrd";
                      }
                      $cmd = "/bin/cp -rf $real_path $dd_dir/initrd_img/lib/modules/$kernelver/initrd";
                      my $driver = basename($real_path);
                      xCAT::Utils->runcmd($cmd, -1);
                      if ($::RUNCMD_RC != 0) {
                          my $rsp;
                          push @{$rsp->{data}}, "Handle the driver update failed. Could not copy driver $driver to the initrd.";
                          xCAT::MsgUtils->message("I", $rsp, $callback);
                      } else {
                          push @rpm_drivers, $driver;
                      }
                  }
                }
            }
    
            # regenerate the modules dependency
            foreach my $kernelver (@kernelvers) {
                $cmd = "cd $dd_dir/initrd_img; depmod -b . $kernelver";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not generate the depdency for the drivers in the initrd.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }
          }
        } # end of loading drivers from rpm packages 
    
        # Create the dir for driver update disk
        mkpath("$dd_dir/initrd_img/cus_driverdisk");

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

        if ($arch =~/ppc/) {
            if (-r "$dd_dir/rpm/newkernel") {
                # if there's new kernel from update distro, then use it
                copy ("$dd_dir/rpm/newkernel", "$dd_dir/kernel");
            } else {
                # make sure the src kernel existed
                $cmd = "gunzip -c $pkgdir/1/suseboot/linux64.gz > $dd_dir/kernel";
                xCAT::Utils->runcmd($cmd, -1);
            }
            
            # create the zimage
            $cmd = "env -u POSIXLY_CORRECT /lib/lilo/scripts/make_zimage_chrp.sh --vmlinux $dd_dir/kernel --initrd $dd_dir/initrd.gz --output $img";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Handle the driver update disk failed. Could not pack the hacked initrd.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return ();
            }
        } elsif ($arch =~/x86/) {
            if (-r "$dd_dir/rpm/newkernel") {
                # if there's new kernel from update distro, then use it
                copy ("$dd_dir/rpm/newkernel", $kernelpath);
            }
            copy ("$dd_dir/initrd.gz", "$img");
        }
    } elsif ($arch =~ /x86/) {
        my $rdhandle;
        my $ddhandle;
        open($rdhandle,">>",$img);
        open ($ddhandle,"<","$dd_dir/initrd.gz");
        binmode($rdhandle);
        binmode($ddhandle);
        { local $/ = 32768; my $block; while ($block = <$ddhandle>) { print $rdhandle $block; } }
        close($rdhandle);
        close($ddhandle);
    }
    
    # clean the env
    system("rm -rf $dd_dir");

    my $rsp;
    if (@dd_list) {
        push @{$rsp->{data}}, "The driver update disk:".join(',',@dd_list)." have been injected to initrd.";
    }
    # remove the duplicated names
    my %dnhash;
    foreach (@rpm_drivers) {
        $dnhash{$_} = 1;
    }
    @rpm_drivers = keys %dnhash;

    if (@rpm_list) {
        if (@rpm_drivers) {
            push @{$rsp->{data}}, "The drivers:".join(',', sort(@rpm_drivers))." from ".join(',', sort(@rpm_list))." have been injected to initrd.";
        } else {
            push @{$rsp->{data}}, "No driver was injected to initrd.";
        }
    }
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
