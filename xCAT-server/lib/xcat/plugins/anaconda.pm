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
use xCAT::TableUtils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
#use Data::Dumper;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
use File::Path;
use File::Copy;
use File::Temp qw/mkdtemp/;
use File::Find;
use File::Basename;
use Digest::MD5 qw(md5_hex);
use Socket;

use strict;
my @cpiopid;
my $httpmethod="http";
my $httpport="80";
my $useflowcontrol="0";



sub handled_commands
{
    return {
            copycd    => "anaconda",
            mknetboot => "nodetype:os=(^ol[0-9].*)|(centos.*)|(rh.*)|(fedora.*)|(SL.*)",
            mkinstall => "nodetype:os=(pkvm.*)|(esxi4.1)|(esx[34].*)|(^ol[0-9].*)|(centos.*)|(rh(?!evh).*)|(fedora.*)|(SL.*)",
            mksysclone => "nodetype:os=(esxi4.1)|(esx[34].*)|(^ol[0-9].*)|(centos.*)|(rh(?!evh).*)|(fedora.*)|(SL.*)",
            mkstatelite => "nodetype:os=(esx[34].*)|(^ol[0-9].*)|(centos.*)|(rh.*)|(fedora.*)|(SL.*)",
	
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

    #my $stab = xCAT::Table->new('site');
    #my $sent;
    #($sent) = $stab->getAttribs({key => 'sharedtftp'}, 'value');
    my @ents = xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $site_ent = $ents[0];
    unless (  defined($site_ent)
            and ($site_ent eq "no" or $site_ent eq "NO"  or $site_ent eq "0"))
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
    if ($::XCATSITEVALS{"httpmethod"}) { $httpmethod = $::XCATSITEVALS{"httpmethod"}; }
    if ($::XCATSITEVALS{"httpport"}) { $httpport = $::XCATSITEVALS{"httpport"}; }
    if ($::XCATSITEVALS{"useflowcontrol"}) { $useflowcontrol = $::XCATSITEVALS{"useflowcontrol"}; }

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
    elsif ($request->{command}->[0] eq 'mksysclone')
    {
        return mksysclone($request, $callback, $doreq);
    }
}

# Check whether the dracut is supported by this os 
sub using_dracut
{
    my $os = shift;
    if ($os =~ /(rhels|rhel|centos)(\d+)/) {
        if ($2 >= 6) {
          return 1;
        }
    } elsif ($os =~ /fedora(\d+)/) {
        if ($1 >= 12) {
          return 1;
        }
    } elsif ($os =~ /SL(\d+)/) {
        if ($1 >= 6) {
          return 1;
        }
    }

    return 0;
}

sub mknetboot
{
    my $xenstyle=0;
    my $req      = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $statelite = 0;
    if($req->{command}->[0] =~ 'mkstatelite'){
        $statelite = "true";
    }
    my $globaltftpdir  = "/tftpboot";
    my $nodes    = @{$req->{node}};
    my @args     = @{$req->{arg}} if(exists($req->{arg}));
    my @nodes    = @{$req->{node}};
    my $noupdateinitrd = $req->{'noupdateinitrd'};
    my $ignorekernelchk = $req->{'ignorekernelchk'};
    my $ostab    = xCAT::Table->new('nodetype');
    #my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my %img_hash=();
    my $installroot;
    $installroot = "/install";
    my $xcatdport = "3001";
    my $xcatiport = "3002";
    my $nodestatus = "y"; 
    my @myself = xCAT::NetworkUtils->determinehostname();
    my $myname = $myself[(scalar @myself)-1];

    #if ($sitetab)
    #{
    #    (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
    my @ents = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if ( defined($site_ent) )
    {
        $installroot = $site_ent;
    }
    @ents = xCAT::TableUtils->get_site_attribute("nodestatus");
    $site_ent = $ents[0];
    if ( defined($site_ent) )
    {
        $nodestatus = $site_ent;
    }
    #    ($ref) = $sitetab->getAttribs({key => 'xcatdport'}, 'value');
    @ents = xCAT::TableUtils->get_site_attribute("xcatdport");
    $site_ent = $ents[0];
    if ( defined($site_ent) )
    {
        $xcatdport = $site_ent;
    }
    @ents = xCAT::TableUtils->get_site_attribute("xcatiport");
    $site_ent = $ents[0];
    if ( defined($site_ent) )
    {
        $xcatiport = $site_ent;
    }
    #    ($ref) = $sitetab->getAttribs({key => 'tftpdir'}, 'value');
    @ents = xCAT::TableUtils->get_site_attribute("tftpdir");
    $site_ent = $ents[0];
    if ( defined($site_ent) )
    {
        $globaltftpdir = $site_ent;
    }
    my %donetftp=();
    my %oents = %{$ostab->getNodesAttribs(\@nodes,[qw(os arch profile provmethod)])};
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my $mactab = xCAT::Table->new('mac');

    my $machash = $mactab->getNodesAttribs(\@nodes, ['interface','mac']);

    my $reshash    = $restab->getNodesAttribs(\@nodes, ['primarynic','tftpserver','tftpdir','xcatmaster','nfsserver','nfsdir', 'installnic']);
    my $hmhash =
          $hmtab->getNodesAttribs(\@nodes,
                                 ['serialport', 'serialspeed', 'serialflow']);
    my $statetab;
    my $stateHash;
    if($statelite){
        $statetab = xCAT::Table->new('statelite',-create=>1);
        $stateHash = $statetab->getNodesAttribs(\@nodes, ['statemnt']);
    }
    #my $addkcmdhash =
    #    $bptab->getNodesAttribs(\@nodes, ['addkcmdline']);

    # Warning message for nodeset <noderange> install/netboot/statelite
    foreach my $knode (keys %oents)
    {
        my $ent = $oents{$knode}->[0];
        if ($ent && $ent->{provmethod}
            && (($ent->{provmethod} eq 'install') || ($ent->{provmethod} eq 'netboot') || ($ent->{provmethod} eq 'statelite')))
        {
            my @ents = xCAT::TableUtils->get_site_attribute("disablenodesetwarning");
            my $site_ent = $ents[0];
            if (!defined($site_ent) || ($site_ent =~ /no/i) || ($site_ent =~ /0/))
            {
               if (!defined($::DISABLENODESETWARNING)) {  # set by AAsn.pm
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
    }
    foreach my $node (@nodes)
    {
        my $osver;
        my $arch;
        my $profile;
        my $platform;
        my $rootimgdir;
        my $nodebootif; # nodebootif will be used if noderes.installnic is not set
        my $dump; # for kdump, its format is "nfs://<nfs_server_ip>/<kdump_path>"
        my $crashkernelsize;
        my $rootfstype; 
        my $tftpdir;
        my $cfgpart;
        my $imagename; # set it if running of 'nodeset osimage=xxx'
        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{tftpdir}) {
		$tftpdir = $reshash->{$node}->[0]->{tftpdir};
        } else {
		$tftpdir = $globaltftpdir;
        }
           

        my $ent = $oents{$node}->[0]; #ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
	        $imagename=$ent->{provmethod};
	        #print "imagename=$imagename\n";
	        if (!exists($img_hash{$imagename})) {
        	    if (!$osimagetab) {
        	        $osimagetab=xCAT::Table->new('osimage', -create=>1);
        	    }
        	    (my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod', 'rootfstype');
        	    if ($ref) {
                    $img_hash{$imagename}->{osver}=$ref->{'osvers'};
                    $img_hash{$imagename}->{osarch}=$ref->{'osarch'};
                    $img_hash{$imagename}->{profile}=$ref->{'profile'};
                    $img_hash{$imagename}->{provmethod}=$ref->{'provmethod'};
                    $img_hash{$imagename}->{rootfstype} = $ref->{rootfstype};
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
                    if ( $ref1 ) {
                        if ($ref1->{'dump'}) {
                            $img_hash{$imagename}->{dump} = $ref1->{'dump'};
                        }
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
            $rootimgdir=$ph->{rootimgdir};
            unless ($rootimgdir) {
                $rootimgdir="$installroot/netboot/$osver/$arch/$profile";
            }
            
            $nodebootif = $ph->{nodebootif};
            $crashkernelsize = $ph->{crashkernelsize};
            $dump = $ph->{dump};
            $cfgpart = $ph->{'cfgpart'};
	  }
        else {
            $osver = $ent->{os};
            $arch    = $ent->{arch};
            $profile = $ent->{profile};
            $rootimgdir="$installroot/netboot/$osver/$arch/$profile";
            
            $rootfstype = "nfs"; # TODO: try to get it from the option or table
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
                    { error => [ qq{Cannot find the linux image called "$osver-$arch-$imgname-$profile", maybe you need to use the "nodeset <nr> osimage=<osimage name>" command to set the boot state} ],
                    errorcode => [1]}
                );
            }

            if ( ! $linuximagetab ) {
                $linuximagetab = xCAT::Table->new('linuximage');
            }
            if ( $linuximagetab ) {
                (my $ref1) = $linuximagetab->getAttribs({imagename => $imgname}, 'dump', 'crashkernelsize', 'partitionfile');
                if($ref1 and $ref1->{'dump'})  {
                    $dump = $ref1->{'dump'};
                }
                if($ref1 and $ref1->{'crashkernelsize'})  {
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
            } else {
                $callback->(
                    { error => [qq{ Cannot find the linux image called "$osver-$arch-$imgname-$profile", maybe you need to use the "nodeset <nr> osimage=<your_image_name>" command to set the boot state}],
                    errorcode => [1] }
                );
            }
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
        $suffix = 'sfs' if (-r "$rootimgdir/rootimg.sfs");
	    # statelite images are not packed.  
        if ($statelite) {
            unless ( -r "$rootimgdir/kernel") {
                $callback->({
                    error=>[qq{Did you run "genimage" before running "liteimg"? kernel cannot be found at $rootimgdir/kernel on $myname}], 
                    errorcode=>[1]
                });
                next;
            }
            if (!-r "$rootimgdir/initrd-statelite.gz") {
                if (! -r "$rootimgdir/initrd.gz") {
                    $callback->({
                        error=>[qq{Did you run "genimage" before running "liteimg"? initrd.gz or initrd-statelite.gz cannot be found at $rootimgdir/initrd.gz on $myname}],
                        errorcode=>[1]
            	    });
                    next;
                }
                else {
                    copy("$rootimgdir/initrd.gz", "$rootimgdir/initrd-statelite.gz");
                }
            } 
            if ( $rootfstype eq "ramdisk" and ! -r "$rootimgdir/rootimg-statelite.gz") {
                $callback->({
                    error=>[qq{No packed image for platform $osver, architecture $arch and profile $profile, please run "liteimg" to create it.}],
                    errorcode => [1]
                });
                next;
            }
        } else {
            unless ( -r "$rootimgdir/kernel") {
                $callback->({
                    error=>[qq{Did you run "genimage" before running "packimage"? kernel cannot be found at $rootimgdir/kernel on $myname}],
                    errorcode=>[1]
			    });
                next;
	        }
	        if (!-r "$rootimgdir/initrd-stateless.gz") {
                  if (! -r "$rootimgdir/initrd.gz") {
                      $callback->({
                          error=>[qq{Did you run "genimage" before running "packimage"? initrd.gz or initrd-stateless.gz cannot be found at $rootimgdir/initrd.gz on $myname}],
                          errorcode=>[1]
  				    });
                      next;
                  } else {
                      copy("$rootimgdir/initrd.gz", "$rootimgdir/initrd-stateless.gz");
                  }
              }
	        unless ( -r "$rootimgdir/rootimg.gz" or -r "$rootimgdir/rootimg.sfs" ) {
                $callback->({
                    error=>["No packed image for platform $osver, architecture $arch, and profile $profile found at $rootimgdir/rootimg.gz or $rootimgdir/rootimg.sfs on $myname, please run packimage (e.g.  packimage -o $osver -p $profile -a $arch"],
                    errorcode => [1]});
                next;
            }
        }

        # create the node-specific post scripts
        #mkpath "/install/postscripts/";

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
            unless ($donetftp{$osver,$arch,$profile}) {
                $docopy = 1;
                $donetftp{$osver,$arch,$profile} = 1;
            }
        }
        
        if ($docopy && !$noupdateinitrd) {
            mkpath("$tftppath");
            if (-f "$rootimgdir/hypervisor") {
                copy("$rootimgdir/hypervisor", "$tftppath");
                $xenstyle=1;
            }
            copy("$rootimgdir/kernel", "$tftppath");
            if ($statelite) {
                if($rootfstype eq "ramdisk") {
                    copy("$rootimgdir/initrd-stateless.gz", "$tftppath");
                } else {
                    copy("$rootimgdir/initrd-statelite.gz", "$tftppath");
                }
            } else {
                copy("$rootimgdir/initrd-stateless.gz", "$tftppath");
            }
        }

        if ($statelite) {
            my $initrdloc = "$tftppath";
            if ($rootfstype eq "ramdisk") {
                $initrdloc .= "/initrd-stateless.gz";
            } else {
                $initrdloc .= "/initrd-statelite.gz";
            }
            unless ( -r "$tftppath/kernel"
                    and -r $initrdloc ) {
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

        $ent    = $reshash->{$node}->[0];#$restab->getNodeAttribs($node, ['primarynic']);
        my $sent   = $hmhash->{$node}->[0];
#          $hmtab->getNodeAttribs($node,
#                                 ['serialport', 'serialspeed', 'serialflow']);

        # determine image server, if tftpserver use it, else use xcatmaster
        # last resort use self
        my $imgsrv;
        my $ient;
        my $xcatmaster;

        $ient = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['tftpserver']);

        if ($ient and $ient->{xcatmaster})
        {
            $xcatmaster = $ient->{xcatmaster};
        } else {
            $xcatmaster = '!myipfn!'; #allow service nodes to dynamically nominate themselves as a good contact point, this is of limited use in the event that xcat is not the dhcp/tftp server
        }

        if ($ient and $ient->{tftpserver})
        {
            $imgsrv = $ient->{tftpserver};
        }
        else
        {
            $ient = $reshash->{$node}->[0]; #$restab->getNodeAttribs($node, ['xcatmaster']);
            #if ($ient and $ient->{xcatmaster})
            #{
            #    $imgsrv = $ient->{xcatmaster};
            #}
            #else
            #{
                # master not correct for service node pools
                #$ient = $sitetab->getAttribs({key => master}, value);
                #if ($ient and $ient->{value})
                #{
                #    $imgsrv = $ient->{value};
                #}
                #else
                #{
            #   $imgsrv = '!myipfn!';
                #}
            #}
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
        # add  more arguments: XCAT=xcatmaster:xcatport NODE=<nodename> 
        #and ifname=<eth0>:<mac address>
	    if($statelite){
            if ($rootfstype ne "ramdisk") {
		        # get entry for nfs root if it exists:
		        # have to get nfssvr and nfsdir from noderes table
		        my $nfssrv = $imgsrv;
		        my $nfsdir = $rootimgdir;
		        if($ient->{nfsserver} ){
			        $nfssrv = $ient->{nfsserver};
		        }
		        if($ient->{nfsdir} ne ''){	
			        $nfsdir = $ient->{nfsdir} . "/netboot/$osver/$arch/$profile";
                        #this code sez, "if nfsdir starts with //, then
                        #use a absolute path, i.e. do not append xCATisms"
                        #this is required for some statelite envs.
                        #still open for debate.

			        if($ient->{nfsdir} =~ m!^//!) {
				        $nfsdir = $ient->{nfsdir};
				        $nfsdir =~ s!^/!!;
			        }
		        }

                # special case for redhat6, fedora12/13/14
                if (&using_dracut($osver)) {
                    $kcmdline = "root=nfs:$nfssrv:$nfsdir/rootimg:ro STATEMNT=";
                } else {
                    $kcmdline = "NFSROOT=$nfssrv:$nfsdir STATEMNT=";	
                }
            } else {
                if (-r "$rootimgdir/rootimg-statelite.gz.metainfo") {
                    $kcmdline =  "imgurl=$httpmethod://$imgsrv:$httpport/$rootimgdir/rootimg-statelite.gz.metainfo STATEMNT=";
                } else {
                    $kcmdline =  "imgurl=$httpmethod://$imgsrv:$httpport/$rootimgdir/rootimg-statelite.gz STATEMNT=";
                }
            }

            # add support for subVars in the value of "statemnt"
            my $statemnt = "";
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
		    $kcmdline .= $statemnt ." ";
                    my $xcatmasterip;
                    # if xcatmaster is hostname, convert it to ip address
                    if (xCAT::NetworkUtils->validate_ip($xcatmaster)) {
                        # Using XCAT=<hostname> will cause problems rc.statelite.ppc.redhat
                        # when trying to run chroot command
                        $xcatmasterip = xCAT::NetworkUtils->getipaddr($xcatmaster);
                        if (!$xcatmasterip)
                        {
                            $xcatmasterip = $xcatmaster;
                        }
                    } else {
                        $xcatmasterip = $xcatmaster;
                    }

                    $kcmdline .= "XCAT=$xcatmasterip:$xcatdport ";


            if ($rootfstype ne "ramdisk") {
                # BEGIN service node
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
                # END service node
            }
            $kcmdline .= "NODE=$node ";
        }
        else {
            if (-r "$rootimgdir/rootimg.$suffix.metainfo") {
                $kcmdline =
                  "imgurl=$httpmethod://$imgsrv:$httpport/$rootimgdir/rootimg.$suffix.metainfo ";
            } else {
                $kcmdline =
                  "imgurl=$httpmethod://$imgsrv:$httpport/$rootimgdir/rootimg.$suffix ";
            }
              $kcmdline .= "XCAT=$xcatmaster:$xcatdport ";
            $kcmdline .= "NODE=$node ";
            # add flow control setting
            $kcmdline .= "FC=$useflowcontrol ";
        }
        #inform statelite/stateless node not to  update the nodestatus during provision 
        if(($nodestatus eq "n") or ($nodestatus eq "N") or ($nodestatus eq "0")){
           $kcmdline .= " nonodestatus ";
        }


        # add one parameter: ifname=<eth0>:<mac address>
        # which is used for dracut
        # the redhat5.x os will ignore it
        my $useifname=0;
        #for rhels5.x-ppc64, if installnic="mac", BOOTIF=<mac> should be appended 
        my $usemac=0;
        my $nicname="";
        if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{installnic} and $reshash->{$node}->[0]->{installnic} ne "mac") {
            $useifname=1;
            #$kcmdline .= "ifname=".$reshash->{$node}->[0]->{installnic} . ":";
            $nicname=$reshash->{$node}->[0]->{installnic};
        } elsif ($nodebootif) {
            $useifname=1;
            #$kcmdline .= "ifname=$nodebootif:";
            $nicname=$nodebootif;
        } elsif ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{primarynic} and $reshash->{$node}->[0]->{primarynic} ne "mac") {
            $useifname=1;
            #$kcmdline .= "ifname=".$reshash->{$node}->[0]->{primarynic}.":";
            $nicname=$reshash->{$node}->[0]->{primarynic};
        }else{
	    if($arch=~ /ppc/)
	    {
     		$usemac=1;	
	    }
	}
        #else { #no, we autodetect and don't presume anything
        #    $kcmdline .="eth0:";
        #    print "eth0 is used as the default booting network devices...\n";
        #}
        # append the mac address
        my $mac;
	
        if( ($usemac ||  $useifname) && $machash->{$node}->[0] && $machash->{$node}->[0]->{'mac'}) {
            # TODO: currently, only "mac" attribute with classic style is used, the "|" delimited string of "macaddress!hostname" format is not used
            $mac = $machash->{$node}->[0]->{'mac'};
#            if ( (index($mac, "|") eq -1) and (index($mac, "!") eq -1) ) {
               #convert to linux format
                if ($mac !~ /:/) {
                   $mac =~s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
                }
		$mac =~ s/!.*//; #remove multi-interface mac information
		$mac =~ s/\|.*//;
#            } else {
#                $callback->({ error=>[ qq{In the "mac" table, the "|" delimited string of "macaddress!hostname" format is not supported by "nodeset <nr> netboot|statelite if installnic/primarynic is set".}], errorcode=>[1]});
#                return;
#            }
        }

        if( ($nicname ne "") and  (not xCAT::NetworkUtils->isValidMAC($nicname) )){
		if ($useifname && $mac) {
		    $kcmdline .= "ifname=$nicname:$mac ";
		}
                $kcmdline .= "netdev=$nicname ";
        }else {
               if($mac){
                    $kcmdline .= "BOOTIF=$mac "; 
               }
        }

       
        # add "netdev=<eth0>" or "BOOTIF=<mac>" 
        # which are used for other scenarios
        #my $netdev = "";
        #if ($reshash->{$node}->[0] and $reshash->{$node}->[0]->{installnic} and $reshash->{$node}->[0]->{installnic} ne "mac") {
        #    $kcmdline .= "netdev=" . $reshash->{$node}->[0]->{installnic} . " ";
        #} elsif ($nodebootif) {
        #    $kcmdline .= "netdev=" . $nodebootif . " ";
        #} elsif ( $reshash->{$node}->[0] and $reshash->{$node}->[0]->{primarynic} and $reshash->{$node}->[0]->{primarynic} ne "mac") {
        #    $kcmdline .= "netdev=" . $reshash->{$node}->[0]->{primarynic} . " ";
        #} else {
        #    if ( ($usemac || $useifname) && $mac) {
        #        $kcmdline .= "BOOTIF=" . $mac . " ";
        #    }
        #}

        my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
        if ( $client_nethash{$node}{mgtifname} =~ /hf/ )
        {
            $kcmdline .= "rdloaddriver=hf_if ";
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
              " console=tty0 console=ttyS" . $sent->{serialport} . "," . $sent->{serialspeed};
            if ($sent->{serialflow} =~ /(hard|tcs|ctsrts)/)
            {
                $kcmdline .= "n8r";
            }
        }

        # turn off the selinux
        if ($osver =~ m/fedora12/ || $osver =~ m/fedora13/) {
            $kcmdline .= " selinux=0 ";
        }

        # if kdump service is enbaled, add "crashkernel=" and "kdtarget="
        if ($dump) {
            my $fadumpFlag = 0;
            my $fadump = '';
            my $kdump = '';
            if ($dump =~ /^fadump.*/){
                $dump =~ s/fadump://g;
                $fadumpFlag = 1;
                $fadump = $dump;
                $kdump = $dump;
                if ($dump =~ /^nfs:\/\/\/.*/){
                    $fadump =~ s/(nfs:\/\/)(\/.*)/net,${xcatmaster}:${2}/;
                    $kdump =~ s/(nfs:\/\/)(\/.*)/${1}${xcatmaster}${2}/;
                }
            }
            if ($crashkernelsize){
                if ($fadumpFlag && $arch eq "ppc64"){
                    $kcmdline .= " fadump=on fadump_reserve_mem=$crashkernelsize fadump_target=$fadump fadump_default=noreboot dump=$kdump ";
                }
                else{
                    $kcmdline .= " crashkernel=$crashkernelsize dump=$dump ";
                }
            }
            else{
                if ($arch eq "ppc64"){
                    if ($fadumpFlag){
                        $kcmdline .= " fadump=on fadump_reserve_mem=512M fadump_target=$fadump fadump_default=noreboot dump=$kdump ";
                    }
                    else{
                        $kcmdline .= " crashkernel=256M\@64M dump=$dump ";
                    }
                }
                if ($arch =~ /86/){
                    $kcmdline .= " crashkernel=128M dump=$dump ";
                }
            }
        }

        # add the cmdline parameters for handling the local disk for stateless
        if ($cfgpart eq "yes") {
            if ($statelite) {
                $kcmdline .= " PARTITION_RH"
            } else {
                $kcmdline .= " PARTITION_DOMOUNT_RH"
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
        
	    my $kernstr="$rtftppath/kernel";
	    if ($xenstyle) {
	        $kernstr.= "!$rtftppath/hypervisor";
	    }
        my $initrdstr = "$rtftppath/initrd-stateless.gz";
        $initrdstr = "$rtftppath/initrd-statelite.gz" if ($statelite);
        # special case for the dracut-enabled OSes
        if (&using_dracut($osver)) {
            if($statelite and $rootfstype eq "ramdisk") {
                $initrdstr = "$rtftppath/initrd-stateless.gz";
            }
        }

        if($statelite)
        {
            my $statelitetb = xCAT::Table->new('statelite');
            my $mntopts = $statelitetb->getNodeAttribs($node, ['mntopts']);

            my $mntoptions = $mntopts->{'mntopts'};
            unless (defined($mntoptions))
            {
                $kcmdline .= " MNTOPTS=";
            }
            else
            {
                $kcmdline .= " MNTOPTS=$mntoptions";
            }
        }

        $bptab->setNodeAttribs(
            $node,
            {
                kernel => $kernstr,
                initrd => $initrdstr,
                kcmdline => $kcmdline
            }
        );
    }

}

sub mkinstall
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my @nodes    = @{$request->{node}};
    my $noupdateinitrd = $request->{'noupdateinitrd'};
    my $ignorekernelchk = $request->{'ignorekernelchk'};
    #my $sitetab  = xCAT::Table->new('site');
    my $linuximagetab;
    my $osimagetab;
    my $osdistrouptab;
    my %img_hash=();

    my $installroot;
    my $globaltftpdir;
    $installroot = "/install";
    $globaltftpdir = "/tftpboot";

    #if ($sitetab)
    #{
    #    (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
    my @ents = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if( defined($site_ent) )    
    {
        $installroot = $site_ent;
    }
    #( $ref) = $sitetab->getAttribs({key => 'tftpdir'}, 'value');
    @ents = xCAT::TableUtils->get_site_attribute("tftpdir");
    $site_ent = $ents[0];
    if( defined($site_ent) )    
    {
        $globaltftpdir = $site_ent;
    }
    #}

    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my %donetftp;
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my %osents = %{$ostab->getNodesAttribs(\@nodes, ['profile', 'os', 'arch', 'provmethod'])};
    my %rents =
              %{$restab->getNodesAttribs(\@nodes,
                                     ['xcatmaster', 'nfsserver', 'tftpdir', 'primarynic', 'installnic'])};
    my %hents = 
              %{$hmtab->getNodesAttribs(\@nodes,
                                     ['serialport', 'serialspeed', 'serialflow'])};
    #my $addkcmdhash =
    #    $bptab->getNodesAttribs(\@nodes, ['addkcmdline']);
    require xCAT::Template;

    # Warning message for nodeset <noderange> install/netboot/statelite
    foreach my $knode (keys %osents)
    {
        my $ent = $osents{$knode}->[0];
        if ($ent && $ent->{provmethod}
            && (($ent->{provmethod} eq 'install') || ($ent->{provmethod} eq 'netboot') || ($ent->{provmethod} eq 'statelite')))
        {
            my @ents = xCAT::TableUtils->get_site_attribute("disablenodesetwarning");
            my $site_ent = $ents[0];
            if (!defined($site_ent) || ($site_ent =~ /no/i) || ($site_ent =~ /0/))
            {
               if (!defined($::DISABLENODESETWARNING)) {  # set by AAsn.pm
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
    }
    foreach $node (@nodes)
    {
        my $os;
        my $tftpdir;
        my $arch;
        my $profile;
        my $tmplfile;
        my $pkgdir;
        my $pkglistfile;
        my $imagename; # set it if running of 'nodeset osimage=xxx'
        my $platform;
        my $xcatmaster;
        my $partfile;
        my $netdrivers;
        my $driverupdatesrc;
        my $osupdir;

        my $ient = $rents{$node}->[0];
        if ($ient and $ient->{xcatmaster})
        {
            $xcatmaster = $ient->{xcatmaster};
        } else {
            $xcatmaster = '!myipfn!';
        }

        my $osinst;
        if ($rents{$node}->[0] and $rents{$node}->[0]->{tftpdir}) {
		$tftpdir = $rents{$node}->[0]->{tftpdir};
        } else {
		$tftpdir = $globaltftpdir;
        }
        my $ent = $osents{$node}->[0]; #$ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite')) {
	    $imagename=$ent->{provmethod};
	    #print "imagename=$imagename\n";
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
			    $img_hash{$imagename}->{partitionfile} = $ref1->{'partitionfile'};
			}
			if ($ref1->{'driverupdatesrc'}) {
			    $img_hash{$imagename}->{driverupdatesrc}=$ref1->{'driverupdatesrc'};
			}
			if ($ref1->{'netdrivers'}) {
			    $img_hash{$imagename}->{netdrivers}=$ref1->{'netdrivers'};
			}
		    }
		    # if the install template wasn't found, then lets look for it in the default locations.
		    unless($img_hash{$imagename}->{template}){
	                my $pltfrm=xCAT_plugin::anaconda::getplatform($ref->{'osvers'});
	    		my $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$pltfrm", 
		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
	    		if (! $tmplfile) { $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$pltfrm", 
		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
					 }
			# if we managed to find it, put it in the hash:
			if($tmplfile){
			    $img_hash{$imagename}->{template}=$tmplfile;
			}
		    }
                    #if the install pkglist wasn't found, then lets look for it in the default locations
		    unless($img_hash{$imagename}->{pkglist}){
	                my $pltfrm=xCAT_plugin::anaconda::getplatform($ref->{'osvers'});
	    		my $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$pltfrm", 
		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
	    		if (! $pkglistfile) { $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$pltfrm", 
		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
					 }
			# if we managed to find it, put it in the hash:
			if($pkglistfile){
			    $img_hash{$imagename}->{pkglist}=$pkglistfile;
			}
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
          $partfile = $ph->{partitionfile};
	    $platform=xCAT_plugin::anaconda::getplatform($os);
	
	    $tmplfile=$ph->{template};
	    $pkgdir=$ph->{pkgdir};
	    if (!$pkgdir) {
		$pkgdir="$installroot/$os/$arch";
	    }
	    $pkglistfile=$ph->{pkglist};

	    $netdrivers = $ph->{netdrivers};
	    $driverupdatesrc = $ph->{driverupdatesrc};
	    $osupdir = $ph->{'osupdir'};
	}
	else {
	    $os = $ent->{os};
	    $arch    = $ent->{arch};
	    $profile = $ent->{profile};
	    $platform=xCAT_plugin::anaconda::getplatform($os);
	    my $genos = $os;
	    $genos =~ s/\..*//;
	    if ($genos =~ /rh.*(\d+)\z/)
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

	    $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$platform", $profile, $os, $arch, $genos);
	    if (! $pkglistfile) { $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$platform", $profile, $os, $arch, $genos); }

	    $pkgdir="$installroot/$os/$arch";
        #get the partition file from the linuximage table
        my $imgname = "$os-$arch-install-$profile";

        if ( ! $linuximagetab ) {
            $linuximagetab = xCAT::Table->new('linuximage');
        }

        if ( $linuximagetab ) {
            (my $ref1) = $linuximagetab->getAttribs({imagename => $imgname}, 'partitionfile');
            if ( $ref1 and $ref1->{'partitionfile'}){
                $partfile = $ref1->{'partitionfile'};
            }
        }
        #can not find the linux osiamge object, tell users to run "nodeset <nr> osimage=***"
        else {
                $callback->(
                     { error => [qq{ Cannot find the linux image called "$imgname", maybe you need to use the "nodeset <nr> osimage=<your_image_name>" command to set the boot state}], errorcode => [1] }
            );
        }
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
                                     . " in directory $installroot/custom/install/$platform or $::XCATROOT/share/xcat/install/$platform"
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
                    $node,
		            $pkglistfile,
                    $pkgdir,
                    $platform,
                    $partfile,
                    $os
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
         
        #To support multiple paths for osimage.pkgdir. We require the first value of osimage.pkgdir
        # should be the os base pkgdir.
        my @srcdirs = split(",", $pkgdir);
        $pkgdir = $srcdirs[0];

        # create the node-specific post scripts
        #mkpath "/install/postscripts/";
        #xCAT::Postage->writescript($node,"/install/postscripts/".$node, "install", $callback);
        my $kernpath;
        my $initrdpath;
        my $maxmem;
        my $esxi = 0;
        my $pkvm = 0;
        if ($os =~ /^pkvm/) {
            $pkvm = 1;
        }

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
                    ) or ( #Handle the case seen in VMware ESXi 4.1 media scripted installs.
                         -r "$pkgdir/mboot.c32"
                         and -r "$pkgdir/vmkboot.gz"
                         and -r "$pkgdir/vmkernel.gz"
                         and -r "$pkgdir/sys.vgz"
                         and -r "$pkgdir/cim.vgz"
                         and -r "$pkgdir/ienviron.vgz"
                         and -r "$pkgdir/install.vgz"
                         and $esxi = 'true'

                    )
            ) or (    $arch =~ /ppc/
                and -r "$pkgdir/ppc/ppc64/vmlinuz"
                and $kernpath = "$pkgdir/ppc/ppc64/vmlinuz"
                and ((-r "$pkgdir/ppc/ppc64/ramdisk.image.gz"
                and $initrdpath = "$pkgdir/ppc/ppc64/ramdisk.image.gz")
                or (-r "$pkgdir/ppc/ppc64/initrd.img"
                and $initrdpath = "$pkgdir/ppc/ppc64/initrd.img")))
          )
        {
            #TODO: driver slipstream, targetted for network.
            # Copy the install resource to /tftpboot and check to only copy once
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
                $tftppath = "/$tftpdir/xcat/$os/$arch/$profile";
                $rtftppath = "xcat/$os/$arch/$profile";
                unless ($donetftp{"$os|$arch|$profile|$tftpdir"}) {
                    $docopy = 1;
                    $donetftp{"$os|$arch|$profile|$tftpdir"} = 1;
                }
            }
            
            if ($docopy) {
                mkpath("$tftppath");
                if($esxi){
                    copyesxiboot($pkgdir, "$tftppath", osver=>$os);		
                }else{
                    unless ($noupdateinitrd) {
                        copy($kernpath,"$tftppath");
                        copy($initrdpath,"$tftppath/initrd.img");
                        &insert_dd($callback, $os, $arch, "$tftppath/initrd.img", "$tftppath/vmlinuz", $driverupdatesrc, $netdrivers, $osupdir, $ignorekernelchk);
                    }
                }
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
            my $instserver = $xcatmaster;
            if ($ent and $ent->{nfsserver}) {
	    	$instserver=$ent->{nfsserver};
	    }

            if ($::XCATSITEVALS{managedaddressmode} =~ /static/){
               unless($instserver eq '!myipfn!'){
                  my($host,$ip)=xCAT::NetworkUtils->gethostnameandip($instserver);
                  $instserver=$ip;
               }
            }
	    my $httpprefix=$pkgdir;
	    if ($installroot =~ /\/$/) {
	       $httpprefix =~ s/^$installroot/\/install\//;
	    } else {
	       $httpprefix =~ s/^$installroot/\/install/;
	    }

            my $kcmdline;
            if ($pkvm) {
                $kcmdline = "ksdevice=bootif kssendmac text selinux=0 rd.dm=0 rd.md=0 repo=$httpmethod://$instserver:$httpport$httpprefix/packages/ kvmp.inst.auto=$httpmethod://$instserver:$httpport/install/autoinst/$node root=live:$httpmethod://$instserver:$httpport$httpprefix/LiveOS/squashfs.img";
            } else {
            $kcmdline ="quiet repo=$httpmethod://$instserver:$httpport$httpprefix ks=$httpmethod://"
              . $instserver . ":". $httpport
              . "/install/autoinst/"
              . $node;
            }
            if ($maxmem) {
                $kcmdline.=" mem=$maxmem";
            }
            my $ksdev = "";
            if ($ent->{installnic})
            {
                if ($ent->{installnic} eq "mac")
                {
                    my $mactab = xCAT::Table->new("mac");
                    my $macref = $mactab->getNodeAttribs($node, ['mac']);
                    $ksdev = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                }
                else
                {
                    $ksdev = $ent->{installnic};
                }
            }
            elsif ($ent->{primarynic})
            {
                if ($ent->{primarynic} eq "mac")
                {
                    my $mactab = xCAT::Table->new("mac");
                    my $macref = $mactab->getNodeAttribs($node, ['mac']);
                    $ksdev = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                }
                else
                {
                    $ksdev = $ent->{primarynic};
                }
            }
            else
            {
                $ksdev = "bootif"; #if not specified, fall back to bootif
            }
            if ($ksdev eq "")
            {
                $callback->(
                        {
                         error => ["No MAC address defined for " . $node],
                         errorcode => [1]
                        }
                        );
             }
             if($esxi){
                 $ksdev =~ s/eth/vmnic/g;
             }
             unless ($ksdev eq "bootif" and $os =~ /7/) {
                 $kcmdline .= " ksdevice=" . $ksdev;
            }
            
            #if site.managedaddressmode=static, specify the network configuration as kernel options 
            #to avoid multicast dhcp
            if($::XCATSITEVALS{managedaddressmode} =~ /static/){
               my ($ipaddr,$hostname,$gateway,$netmask)=xCAT::NetworkUtils->getNodeNetworkCfg($node);
               unless($ipaddr) { 
                    $callback->(
                        {
                         error => [
                             "cannot resolve the ip address of $node"
                         ],
                         errorcode => [1]
                        }
                        );
               }         

               if($gateway eq '<xcatmaster>'){
                      $gateway = xCAT::NetworkUtils->my_ip_facing($ipaddr);
               }

               $kcmdline .=" ip=$ipaddr netmask=$netmask gateway=$gateway  hostname=$hostname ";


                my %nameservers=%{xCAT::NetworkUtils->getNodeNameservers([$node])};
                my @nameserverARR=split (",",$nameservers{$node});
                my @nameserversIP;
                foreach (@nameserverARR)
                {
                   my $ip;
                   if($_ eq '<xcatmaster>'){
                      $ip = xCAT::NetworkUtils->my_ip_facing($gateway);
                   }else{
                      (undef,$ip) = xCAT::NetworkUtils->gethostnameandip($_);
                   }
                   push @nameserversIP, $ip;

                }
               
               if(scalar @nameserversIP){
                  $kcmdline .=" dns=".join(",",@nameserversIP);
               }
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
		#go cmdline if serial console is requested, the shiny ansi is just impractical
                $kcmdline .=
                    " cmdline console=tty0 console=ttyS"
                  . $sent->{serialport} . ","
                  . $sent->{serialspeed};
                if ($sent->{serialflow} =~ /(hard|cts|ctsrts)/)
                {
                    $kcmdline .= "n8r";
                }
            }
            #$kcmdline .= " noipv6";
            # add the addkcmdline attribute  to the end
            # of the command, if it exists
            #my $addkcmd   = $addkcmdhash->{$node}->[0];
            # add the extra addkcmd command info, if in the table
            #if ($addkcmd->{'addkcmdline'}) {
            #        $kcmdline .= " ";
            #        $kcmdline .= $addkcmd->{'addkcmdline'};
            #}
            my $k;
            my $i;
            if($esxi){
                $k = "$rtftppath/mboot.c32";
                $i = "";
                my @addfiles = qw(vmkernel.gz sys.vgz cim.vgz ienviron.vgz install.vgz mod.tgz);
                $kcmdline = "$rtftppath/vmkboot.gz " . $kcmdline;
                foreach(@addfiles){
                    $kcmdline .= " --- $rtftppath/$_";
                }
            #}elsif ($pkvm) {
            #    $k = "$httpmethod://$instserver:$httpport$tftppath/vmlinuz";
            #    $i = "$httpmethod://$instserver:$httpport$tftppath/initrd.img";
            }else{
                    $k = "$rtftppath/vmlinuz";
                    $i = "$rtftppath/initrd.img";
            }

            $bptab->setNodeAttribs(
                $node,
                {
                    kernel   => $k,
                    initrd   => $i,
                    kcmdline => $kcmdline
                }
            );
        }
        else
        {
            $callback->(
                    {
                     error => ["Install image not found in $pkgdir"],
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

sub mksysclone
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my @nodes    = @{$request->{node}};
    my $linuximagetab;
    my $osimagetab;
    my %img_hash=();

    my $installroot;
    my $globaltftpdir;
    $installroot = "/install";
    $globaltftpdir = "/tftpboot";

    my @ents = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if( defined($site_ent) )    
    {
        $installroot = $site_ent;
    }
    @ents = xCAT::TableUtils->get_site_attribute("tftpdir");
    $site_ent = $ents[0];
    if( defined($site_ent) )    
    {
        $globaltftpdir = $site_ent;
    }

    my $node;
    my $ostab = xCAT::Table->new('nodetype');
    my %donetftp;
    my $restab = xCAT::Table->new('noderes');
    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $hmtab  = xCAT::Table->new('nodehm');
    my %osents = %{$ostab->getNodesAttribs(\@nodes, ['profile', 'os', 'arch', 'provmethod'])};
    my %rents =
              %{$restab->getNodesAttribs(\@nodes,
                                     ['xcatmaster', 'nfsserver', 'tftpdir', 'primarynic', 'installnic'])};
    my %hents = 
              %{$hmtab->getNodesAttribs(\@nodes,
                                     ['serialport', 'serialspeed', 'serialflow'])};
    my @entries =  xCAT::TableUtils->get_site_attribute("xcatdport");
    my $port_entry = $entries[0];
    my $xcatdport="3001";
    if ( defined($port_entry)) {
       $xcatdport = $port_entry;
    }

    my @entries =  xCAT::TableUtils->get_site_attribute("master");
    my $master_entry = $entries[0];

    require xCAT::Template;

    # Warning message for nodeset <noderange> install/netboot/statelite
    foreach my $knode (keys %osents)
    {
        my $ent = $osents{$knode}->[0];
        if ($ent && $ent->{provmethod}
            && (($ent->{provmethod} eq 'install') || ($ent->{provmethod} eq 'netboot') || ($ent->{provmethod} eq 'statelite')))
        {
            my @ents = xCAT::TableUtils->get_site_attribute("disablenodesetwarning");
            my $site_ent = $ents[0];
            if (!defined($site_ent) || ($site_ent =~ /no/i) || ($site_ent =~ /0/))
            {
               if (!defined($::DISABLENODESETWARNING)) {  # set by AAsn.pm
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
    }

    # copy postscripts, the xCAT scripts may update, but the image is captured long time ago
    # should update the scripts at each nodeset
    my $script1 = "configefi";
    my $script2 = "updatenetwork";
    my $pspath = "$installroot/sysclone/scripts/post-install/";
    my $clusterfile = "$installroot/sysclone/scripts/cluster.txt";
    
    mkpath("$pspath");
    copy("$installroot/postscripts/$script1","$pspath/15all.$script1");
    copy("$installroot/postscripts/$script2","$pspath/16all.$script2");
    copy("$installroot/postscripts/runxcatpost","$pspath/17all.runxcatpost");
    copy("$installroot/postscripts/makeinitrd","$pspath/20all.makeinitrd");

    unless (-r "$pspath/10all.fix_swap_uuids")
    {
        mkpath("$pspath");
        copy("/var/lib/systemimager/scripts/post-install/10all.fix_swap_uuids","$pspath");
    }

    #unless (-r "$pspath/95all.monitord_rebooted")
    #{
    #    mkpath("$pspath");
    #    copy("/var/lib/systemimager/scripts/post-install/95all.monitord_rebooted","$pspath");
    #}


    if(-e "$pspath/95all.monitord_rebooted")
    {
        `rm $pspath/95all.monitord_rebooted`;
    }


    # copy hosts
    copy("/etc/hosts","$installroot/sysclone/scripts/");
    
    foreach $node (@nodes)
    {
        my $os;
        my $tftpdir;
        my $arch;
        my $profile;
        my $tmplfile;
        my $pkglistfile;
        my $imagename; # set it if running of 'nodeset osimage=xxx'
        my $platform;
        my $xcatmaster;
        my $instserver;
        my $partfile;
        my $netdrivers;
        my $driverupdatesrc;

        my $ient = $rents{$node}->[0];
        if ($ient and $ient->{xcatmaster})
        {
            $xcatmaster = $ient->{xcatmaster};
        } else {
            $xcatmaster = $master_entry;
        }

        my $osinst;
        if ($rents{$node}->[0] and $rents{$node}->[0]->{tftpdir}) {
		$tftpdir = $rents{$node}->[0]->{tftpdir};
        } else {
		$tftpdir = $globaltftpdir;
        }
        my $ent = $osents{$node}->[0]; #$ostab->getNodeAttribs($node, ['profile', 'os', 'arch']);
        if ($ent and $ent->{provmethod} and ($ent->{provmethod} ne 'install') and ($ent->{provmethod} ne 'netboot') and ($ent->{provmethod} ne 'statelite') and ($ent->{provmethod} ne 'sysclone')) {
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
		    $img_hash{$imagename}->{provmethod}=$ref->{'provmethod'}; #sysclone
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
			    $img_hash{$imagename}->{partitionfile} = $ref1->{'partitionfile'};
			}
			if ($ref1->{'driverupdatesrc'}) {
			    $img_hash{$imagename}->{driverupdatesrc}=$ref1->{'driverupdatesrc'};
			}
			if ($ref1->{'netdrivers'}) {
			    $img_hash{$imagename}->{netdrivers}=$ref1->{'netdrivers'};
			}
		    }

		    # template is meanless for sysclone, so comment it out.
		    # if the install template wasn't found, then lets look for it in the default locations.
#		    unless($img_hash{$imagename}->{template}){
#	                my $pltfrm=xCAT_plugin::anaconda::getplatform($ref->{'osvers'});
#	    		my $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$pltfrm", 
#		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
#	    		if (! $tmplfile) { $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$pltfrm", 
#		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
#					 }
#			# if we managed to find it, put it in the hash:
#			if($tmplfile){
#			    $img_hash{$imagename}->{template}=$tmplfile;
#			}
#		    }

                  #if the install pkglist wasn't found, then lets look for it in the default locations
		    unless($img_hash{$imagename}->{pkglist}){
	                my $pltfrm=xCAT_plugin::anaconda::getplatform($ref->{'osvers'});
	    		my $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$pltfrm", 
		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
	    		if (! $pkglistfile) { $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$pltfrm", 
		 			$ref->{'profile'}, $ref->{'osvers'}, $ref->{'osarch'}, $ref->{'osvers'});
					 }
			# if we managed to find it, put it in the hash:
			if($pkglistfile){
			    $img_hash{$imagename}->{pkglist}=$pkglistfile;
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
          $partfile = $ph->{partitionfile};
	    $platform=xCAT_plugin::anaconda::getplatform($os);
	
	    #$tmplfile=$ph->{template};
	    $pkglistfile=$ph->{pkglist};

	    $netdrivers = $ph->{netdrivers};
	    $driverupdatesrc = $ph->{driverupdatesrc};
	}
	else {
	    $os = $ent->{os};
	    $arch    = $ent->{arch};
	    $profile = $ent->{profile};
	    $platform=xCAT_plugin::anaconda::getplatform($os);
	    my $genos = $os;
	    $genos =~ s/\..*//;
	    if ($genos =~ /rh.*(\d+)\z/)
	    {
		unless (-r "$installroot/custom/install/$platform/$profile.$genos.$arch.tmpl"
			or -r "/install/custom/install/$platform/$profile.$genos.tmpl"
			or -r "$::XCATROOT/share/xcat/install/$platform/$profile.$genos.$arch.tmpl"
			or -r "$::XCATROOT/share/xcat/install/$platform/$profile.$genos.tmpl")
		{
		    $genos = "rhel$1";
		}
	    }
	    
#	    $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$installroot/custom/install/$platform", $profile, $os, $arch, $genos);
#	    if (! $tmplfile) { $tmplfile=xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$platform", $profile, $os, $arch, $genos); }

#	    $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$installroot/custom/install/$platform", $profile, $os, $arch, $genos);
#	    if (! $pkglistfile) { $pkglistfile=xCAT::SvrUtils::get_pkglist_file_name("$::XCATROOT/share/xcat/install/$platform", $profile, $os, $arch, $genos); }

        #get the partition file from the linuximage table
        my $imgname = "$os-$arch-install-$profile";

        if ( ! $linuximagetab ) {
            $linuximagetab = xCAT::Table->new('linuximage');
        }

        if ( $linuximagetab ) {
            (my $ref1) = $linuximagetab->getAttribs({imagename => $imgname}, 'partitionfile');
            if ( $ref1 and $ref1->{'partitionfile'}){
                $partfile = $ref1->{'partitionfile'};
            }
        }
        #can not find the linux osiamge object, tell users to run "nodeset <nr> osimage=***"
        else {
                $callback->(
                     { error => [qq{ Cannot find the linux image called "$imgname", maybe you need to use the "nodeset <nr> osimage=<your_image_name>" command to set the boot state}], errorcode => [1] }
            );
        }
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
      
        # copy kernel and initrd from image dir to /tftpboot
=pod
        my $kernpath;
        my $initrdpath;
        my $ramdisk_size = 200000;
	 
        if (
            -r "$tftpdir/xcat/genesis.kernel.$arch"
            and $kernpath = "$tftpdir/xcat/genesis.kernel.$arch"
            and -r "$tftpdir/xcat/genesis.fs.$arch.lzma"
            and $initrdpath = "$tftpdir/xcat/genesis.fs.$arch.lzma"
        )
=cut
        my $ramdisk_size = 200000;
        my $kernpath=`ls -l $tftpdir/xcat/|grep "genesis.kernel.$arch"|awk '{print \$9}'`;
        chomp($kernpath);
        my $initrdpath=`ls -l $tftpdir/xcat/|grep "genesis.fs.$arch"| awk '{print \$9}'`;
        chomp($initrdpath);

        if($kernpath ne '' and $initrdpath ne '')
        {
            #We have a shot...
            my $ent    = $rents{$node}->[0];
            my $sent = $hents{$node}->[0];

            my $kcmdline =
                "ramdisk_size=$ramdisk_size";
            my $ksdev = "";
            if ($ent->{installnic})
            {
                if ($ent->{installnic} eq "mac")
                {
                    my $mactab = xCAT::Table->new("mac");
                    my $macref = $mactab->getNodeAttribs($node, ['mac']);
                    $ksdev = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                }
                else
                {
                    $ksdev = $ent->{installnic};
                }
            }
            elsif ($ent->{primarynic})
            {
                if ($ent->{primarynic} eq "mac")
                {
                    my $mactab = xCAT::Table->new("mac");
                    my $macref = $mactab->getNodeAttribs($node, ['mac']);
                    $ksdev = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                }
                else
                {
                    $ksdev = $ent->{primarynic};
                }
            }
            else
            {
                $ksdev = "bootif"; #if not specified, fall back to bootif
            }
            if ($ksdev eq "")
            {
                $callback->(
                        {
                         error => ["No MAC address defined for " . $node],
                         errorcode => [1]
                        }
                        );
             }
             $kcmdline .= " ksdevice=" . $ksdev;

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
		#go cmdline if serial console is requested, the shiny ansi is just impractical
                $kcmdline .=
                    " cmdline console=tty0 console=ttyS"
                  . $sent->{serialport} . ","
                  . $sent->{serialspeed};
                if ($sent->{serialflow} =~ /(hard|cts|ctsrts)/)
                {
                    $kcmdline .= "n8r";
                }
            }
            $kcmdline .= " XCAT=$xcatmaster:$xcatdport xcatd=$xcatmaster:$xcatdport SCRIPTNAME=$imagename";

            my $nodetab = xCAT::Table->new('nodetype');
            my $archref = $nodetab->getNodeAttribs($node, ['arch']);
            if ($archref->{arch} eq "ppc64"){
                my $mactab = xCAT::Table->new('mac');
                my $macref = $mactab->getNodeAttribs($node, ['mac']);
                my $formatmac = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                $formatmac =~ s/:/-/g;
                $formatmac = "01-".$formatmac;
                $kcmdline .= " BOOTIF=$formatmac ";
            }

            #$kcmdline .= " noipv6";
            # add the addkcmdline attribute  to the end
            # of the command, if it exists
            #my $addkcmd   = $addkcmdhash->{$node}->[0];
            # add the extra addkcmd command info, if in the table
            #if ($addkcmd->{'addkcmdline'}) {
            #        $kcmdline .= " ";
            #        $kcmdline .= $addkcmd->{'addkcmdline'};
            #}

            my $k;
            my $i;
            #$k = "xcat/genesis.kernel.$arch";
            #$i = "xcat/genesis.fs.$arch.lzma";

             $k = "xcat/$kernpath";
             $i = "xcat/$initrdpath";

            $bptab->setNodeAttribs(
                $node,
                {
                    kernel   => $k,
                    initrd   => $i,
                    kcmdline => $kcmdline
                }
            );
        }
        else
        {
            $callback->(
                    {
                     error => ["Kernel and initrd not found in $tftpdir/xcat"],
                     errorcode => [1]
                    }
                    );
        }

        # assign nodes to an image
        if (-r "$clusterfile")
        {
            my $cmd = qq{cat $clusterfile | grep "$node"};
            my $out = xCAT::Utils->runcmd($cmd, -1);
             if ($::RUNCMD_RC == 0)
             {
                my $out = `sed -i /$node./d $clusterfile`;
             }
        }

        my $cmd =qq{echo "$node:compute:$imagename:" >> $clusterfile};
        my $rc = xCAT::Utils->runcmd($cmd, -1);
		
        my $imagedir;
        my $osimagetab = xCAT::Table->new('linuximage');
        my $osimageentry  = $osimagetab->getAttribs({imagename => $imagename}, 'rootimgdir');
        if($osimageentry){
            $imagedir = $osimageentry->{rootimgdir};
            $imagedir =~ s/^(\/.*)\/.+\/?$/$1/;
        }else{
            $imagedir = "$installroot/sysclone/images";
            $cmd = "chdef -t osimage $imagename rootimgdir=$imagedir/$imagename";
            $rc = `$cmd`;
        }
		
        my $cfgimagedir = `cat /etc/systemimager/rsync_stubs/40$imagename|grep path`;
        chomp($cfgimagedir);
        $cfgimagedir  =~ s/^\s+path=(\/.*)\/.+$/$1/g;
			
        if($imagedir ne $cfgimagedir){
            my $oldstr = `cat /etc/systemimager/rsync_stubs/40$imagename|grep path`;
            chomp($oldstr);
            $oldstr =~ s/\//\\\\\//g;

            my $targetstr="\tpath=".$imagedir."/".$imagename;
            $targetstr =~ s/\//\\\\\//g;
            $cmd= "sed -i \"s/$oldstr/$targetstr/\"  /etc/systemimager/rsync_stubs/40$imagename";
            $rc = `$cmd`;
        }

        $rc = `export PERL5LIB=/usr/lib/perl5/site_perl/;LANG=C si_mkrsyncd_conf`;

        unless (-r "$imagedir/$imagename/opt/xcat/xcatdsklspost")
        {
            mkpath("$imagedir/$imagename/opt/xcat/");
            copy("$installroot/postscripts/xcatdsklspost","$imagedir/$imagename/opt/xcat/");
        }

    }

    # check systemimager-server-rsyncd to make sure it's running.
    #my $out = xCAT::Utils->runcmd("service systemimager-server-rsyncd status", -1);
    # if ($::RUNCMD_RC != 0)  { # not running
    my $retcode=xCAT::Utils->checkservicestatus("systemimager-server-rsyncd");
    if($retcode!=0){
         my $rc = xCAT::Utils->startservice("systemimager-server-rsyncd");
         if ($rc != 0) {
            return 1;
         }
     }   
}
sub copycd
{
    my $request  = shift;
    my $callback = shift;
    my $doreq    = shift;
    my $installroot = "/install";
    my $sitetab = xCAT::Table->new('site');
    

    require xCAT::data::discinfo;

    #if ($sitetab)
    #{
    #    (my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
    my @ents = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if( defined($site_ent) )    
    {
        $installroot = $site_ent;
    }

    my $distname;
    my $arch;
    my $path;
    my $mntpath=undef;
    my $inspection=undef;
    my $noosimage=undef;
    my $nonoverwrite=undef;

    @ARGV = @{$request->{arg}};
    GetOptions(
               'n=s' => \$distname,
               'a=s' => \$arch,
               'p=s' => \$path,
               'm=s' => \$mntpath,
               'i'   => \$inspection,
               'o'   => \$noosimage,
               'w'   => \$nonoverwrite,   
               );
    unless ($mntpath)
    {

        #this plugin needs $mntpath...
        return;
    }
    if (    $distname
        and $distname !~ /^centos/
        and $distname !~ /^fedora/
        and $distname !~ /^SL/
        and $distname !~ /^ol/
        and $distname !~ /^pkvm/
        and $distname !~ /^rh/)
    {

        #If they say to call it something unidentifiable, give up?
        return;
    }
    unless (-r $mntpath . "/.discinfo")
    {
        return;
    }
    my $dinfo;
    open($dinfo, $mntpath . "/.discinfo");
    my $did = <$dinfo>;
    chomp($did);
    my $desc = <$dinfo>;
    chomp($desc);
    my $darch = <$dinfo>;
    chomp($darch);
    my $dno= <$dinfo>;
    chomp($dno);

    if ($darch and $darch =~ /i.86/)
    {
        $darch = "x86";
    }
    close($dinfo);
    if ($xCAT::data::discinfo::distnames{$did})
    {
        unless ($distname)
        {
            $distname =$xCAT::data::discinfo::distnames{$did};
        }
    }
    elsif ($desc =~ /^Oracle Linux (\d)\.(\d)/)
    {
        unless ($distname)
        {
            $distname = "ol$1.$2";
        }
    }
    elsif ($desc =~ /^RHEL-(\d)\.(\d) ([^.]*)\./) {
        my $edition = "";
        my $version = "$1.$2";
        my %editionmap = (
            "Server" => "s",
            );
        $edition = $editionmap{$3};
        unless ($distname)
        {
            $distname = "rhel$edition$version";
        }
    }
    elsif ($desc =~ /^Red Hat Enterprise Linux (\d)\.(\d)/)
    {
	my $edition;
	my $version = "$1.$2";
	if (-d "$mntpath/Server") {
		$edition = "s";
	} elsif (-d "$mntpath/Client") {
		$edition = "c";
	} elsif (-d "$mntpath/Workstation") {
		$edition = "w";
	} elsif (-d "$mntpath/ComputeNode") {
		$edition = "cn";
	}
        unless ($distname)
        {
            $distname = "rhel$edition$version";
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
    elsif ($desc =~ /^Scientific Linux (\d)\.(\d)/)
    {
        unless ($distname)
        {
            $distname = "SL$1.$2";
        }
    }
    elsif ($desc =~ /^LTS$/)
    {
        unless ($distname)
        {
            $distname = "SL5";
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

    if($inspection)
    {
            my $retinfo="DISTNAME:$distname\n"."ARCH:$arch\n";
            if($dno) {
               $retinfo=$retinfo."DISCNO:$dno\n";
            }
            $callback->(
                {
                 info =>"$retinfo"
                }
                );
            return;
    }


    %{$request} = ();    #clear request we've got it.
    my $disccopiedin=0;
    my $osdistroname=$distname."-".$arch;

    my $defaultpath="$installroot/$distname/$arch";
    unless($path)
    {
        $path=$defaultpath;
    }
    if ($::XCATSITEVALS{osimagerequired}){
	   my ($nohaveimages,$errstr) = xCAT::SvrUtils->update_tables_with_templates($distname, $arch,$path,$osdistroname,checkonly=>1);
	   if ($nohaveimages) { 
        	$callback->({error => "No Templates found to support $distname($arch)",errorcode=>2});
		return;
	   }
    }
    if ($::XCATSITEVALS{onlysupportarchs} and $::XCATSITEVALS{onlysupportarchs} ne $arch) {
        $callback->({error => "$arch is unsupported by this system",errorcode=>2});
	return;
    }


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
    my $osdistroname=$distname."-".$arch;
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
                              info  =>
                 	              ["The disc iso has already been copied in!"]}	       
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



    $callback->({data => "Copying media to $path"});
    my $omask = umask 0022;
    if(-l $path)
    {
        unlink($path);
    }
    mkpath("$path");    
    umask $omask;

    my $rc;
    my $reaped = 0;
    $SIG{INT} = $SIG{TERM} = sub {
        foreach(@cpiopid){
            kill 2, $_;
        }
        if ($mntpath) {
            chdir("/");
            system("umount $mntpath");
        }
    };

    my $KID;
    chdir $mntpath;
    my $numFiles = scalar(@sortedfilelist);
    my $child = open($KID, "|-");
    unless (defined $child)
    {
        $callback->({error => "Media copy operation fork failure"});
        return;
    }
    if ($child)
    {
        push @cpiopid, $child;
	chdir("/");
        for (@sortedfilelist)
        {
            print $KID $_."\n";
        }
        close($KID);
        $rc = $?;
    }
    else
    {
        nice 10;
        my $c = "nice -n 20 cpio -vdump $path";
        my $k2 = open(PIPE, "$c 2>&1 |") || exit(1); 
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
    #my $rc = system("cd $path; find . | nice -n 20 cpio -dump $installroot/$distname/$arch");
    #my $rc = system("cd $path;rsync -a . $installroot/$distname/$arch/");
    chmod 0755, "$path";

    #append the fingerprint to the .fingerprint file to indicate that the os media has been copied in    
    unless($disccopiedin)
    {
	my $ret=open(my $fpd,">>","$path/.fingerprint");
	if($ret){
        	print $fpd "$fingerprint,";
        	close($fpd);
	}
    }


    unless($path =~ /^($defaultpath)/)
    {
	mkpath($defaultpath); 
        if(-d $defaultpath)
        {
                rmtree($defaultpath);
        }
        else
        {
                unlink($defaultpath);
        }

        my $hassymlink = eval { symlink("",""); 1 };
        if ($hassymlink) {
                symlink($path,$defaultpath);
        }else
        {
                link($path,$defaultpath);
        }

    }

    require xCAT::Yum;
    xCAT::Yum->localize_yumrepo($installroot, $distname, $arch);
    
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
	
        unless($noosimage){
	    my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch,$path,$osdistroname);
	    if ($ret[0] != 0) {
		$callback->({data => "Error when updating the osimage tables: " . $ret[1]});
	    }

	    #hiding the messages about this not being found, since it may be intentional

            my @ret=xCAT::SvrUtils->update_tables_with_mgt_image($distname, $arch, $path,$osdistroname);

	    my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "netboot",$path,$osdistroname);
	    #if ($ret[0] != 0) {
		#$callback->({data => "Error when updating the osimage tables for stateless: " . $ret[1]});
	    #}

	    my @ret=xCAT::SvrUtils->update_tables_with_diskless_image($distname, $arch, undef, "statelite",$path,$osdistroname);
	    #if ($ret[0] != 0) {
		#$callback->({data => "Error when updating the osimage tables for statelite: " . $ret[1]});
	    #}
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
    elsif ($os =~ /esxi.*/)
    {
	$platform = "esxi";
    }
    elsif ($os =~ /esx.*/)
    {
	$platform = "esx";
    }
    elsif ($os =~ /SL.*/)
    {
        $platform = "SL";
    }
    elsif ($os =~ /ol.*/)
    {
        $platform = "ol";
    }

    return $platform;
}


sub copyesxiboot {
    my $srcdir = shift;
    my $targetdir = shift;
    my %args=@_;
    my $os='esxi';
    if ($args{osver}) { $os=$args{osver} }
    # this just does the same thing that the stateless version does.
    unless(-f "$targetdir/mod.tgz"){
	require xCAT_plugin::esx;
        xCAT_plugin::esx::makecustomizedmod($os, $targetdir);
    }
    my @files = qw(mboot.c32 vmkboot.gz vmkernel.gz sys.vgz cim.vgz ienviron.vgz install.vgz);
    foreach my $f (@files){
        copy("$srcdir/$f","$targetdir");
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

sub insert_dd {
    my $callback = shift;
    if ($callback eq "xCAT_plugin::anaconda") {
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
       
    my @inserted_dd = ();
    my @dd_drivers = ();
    
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

    # regenerate the original initrd for non dracut or need to add the drivers from rpm packages
    # dracut + drvier rpm
    # !dracut + driver rpm
    # !dracut + driver disk
    if (!<$install_dir/$os/$arch/Packages/dracut*> || (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list))) {
        mkpath "$dd_dir/initrd_img"; # The dir for the new initrd

        # unzip the initrd image
        $cmd = "file $img";
        my $initrdfmt;
        my @format = xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp;
            push @{$rsp->{data}}, "Could not get the format of the initrd.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        }

        if ( grep (/gzip compressed data/, @format)) {
            $initrdfmt = "gzip";
        } elsif ( grep (/LZMA compressed data/, @format)) {
            $initrdfmt = "lzma";
        } else {
            # check whether it can be handled by xz
            $cmd = "xz -t $img";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Could not handle the format of the initrd.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return ();
            } else {
                $initrdfmt = "lzma";
            }
        }
        

        if ($initrdfmt eq "gzip") {
            $cmd = "gunzip -c $img > $dd_dir/initrd";
        } elsif ($initrdfmt eq "lzma") {
            if (! -x "/usr/bin/xz") {
                my $rsp;
                push @{$rsp->{data}}, "The format of initrd for the target node is \'lzma\', but this management node has not xz command.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return ();
            }
            $cmd = "xzcat $img > $dd_dir/initrd";
        }
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp;
            push @{$rsp->{data}}, "Handle the driver update disk failed. Could not gunzip the initial initrd.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        }
    
        # Extract the files from original initrd
        $cmd = "cd $dd_dir/initrd_img; cpio -id --quiet < ../initrd";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp;
            push @{$rsp->{data}}, "Handle the driver update disk failed. Could not extract files from the initial initrd.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        }

        my $new_kernel_ver;
        if (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list)) {
            # Extract the files from rpm to the tmp dir
            mkpath "$dd_dir/rpm";
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
                # and copy it to the /tftpboot
                my @new_kernels = <$dd_dir/rpm/boot/vmlinuz*>;
                foreach my $new_kernel (@new_kernels) {
                    if (-r $new_kernel && $new_kernel =~ /\/vmlinuz-(.*(x86_64|ppc64|el\d+))$/) {
                        $new_kernel_ver = $1;
                        $cmd = "/bin/mv -f $new_kernel $kernelpath";
                        xCAT::Utils->runcmd($cmd, -1);
                        if ($::RUNCMD_RC != 0) {
                            my $rsp;
                            push @{$rsp->{data}}, "Handle the driver update failed. Could not move $new_kernel to $kernelpath.";
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
                $cmd = "/bin/mv -f $file $newname";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not move $file.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
            }
        }
    
        # The rh6 has different initrd format with old version (rh 5.x)
        # The new format of initrd is made by dracut, it has the /lib/modules/<kernel>
        # directory like the root image
        # If the os has dracut rpm packet, then copy the drivers to the /lib/modules/<kernel>
        # and recreate the dependency by the depmod command 
        
        if (<$install_dir/$os/$arch/Packages/dracut*>) { #rh6, fedora13 ...
            # For dracut mode, only copy the drivers from rpm packages to the /lib/modules/<kernel>
            # The driver disk will be handled that append the whole disk to the orignial initrd

            if (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list)) {
                # Copy the firmware to the rootimage
                if (-d "$dd_dir/rpm/lib/firmware") {
                    if (! -d "$dd_dir/initrd_img/lib/firmware") {
                        mkpath "$dd_dir/initrd_img/lib/firmware";
                    }
                    $cmd = "/bin/cp -rf $dd_dir/rpm/lib/firmware/* $dd_dir/initrd_img/lib/firmware";
                    xCAT::Utils->runcmd($cmd, -1);
                    if ($::RUNCMD_RC != 0) {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not copy firmware to the initrd.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
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
                
                # Copy the drivers to the initrd
                # Figure out the kernel version
                my @kernelpaths = <$dd_dir/initrd_img/lib/modules/*>;
                my @kernelvers;
                if ($new_kernel_ver) {
                    push @kernelvers, $new_kernel_ver;
                }
                
                # if new kernel is used, remove all the original kernel directories
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
                    foreach my $driver (@driver_list) {
                      $driver =~ s/\.gz$//;
                      $driver_name = $driver;
                      @all_real_path = ();
                      find(\&get_all_path, <$dd_dir/rpm/lib/modules/$kernelver/*>);
                      foreach my $real_path (@all_real_path) {
                          if ($real_path && $real_path =~ m!$dd_dir/rpm(/lib/modules/$kernelver/.*?)[^\/]*$!) {
                              if (! -d "$dd_dir/initrd_img$1") {
                                  mkpath "$dd_dir/initrd_img$1";
                              }
                              $cmd = "/bin/cp -rf $real_path $dd_dir/initrd_img$1";
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
                  } else {
                    # copy all the drviers to the rootimage
                    if (-d "$dd_dir/rpm/lib/modules/$kernelver") {
                        $cmd = "/bin/cp -rf $dd_dir/rpm/lib/modules/$kernelver $dd_dir/initrd_img/lib/modules/";
                        xCAT::Utils->runcmd($cmd, -1);
                        if ($::RUNCMD_RC != 0) {
                            my $rsp;
                            push @{$rsp->{data}}, "Handle the driver update failed. Could not copy /lib/modules/$kernelver to the initrd.";
                            xCAT::MsgUtils->message("I", $rsp, $callback);
                        }
                    } else {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not find /lib/modules/$kernelver from the driver rpms.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }
        
                # regenerate the modules dependency
                foreach my $kernelver (@kernelvers) {
                    $cmd = "depmod -b $dd_dir/initrd_img $kernelver";
                    xCAT::Utils->runcmd($cmd, -1);
                    if ($::RUNCMD_RC != 0) {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not generate the drivers depdency for $kernelver in the initrd.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }
              }
            }
        } else {# non dracut mode, for rh5, fedora12 ...
            # For non-dracut mode, the drviers need to be merged into the initrd with the specific format

            # Create directory for the driver modules hack
            mkpath "$dd_dir/modules";
            
            # Extract files from the modules.cgz of initrd
            $cmd = "cd $dd_dir/modules; gunzip -c $dd_dir/initrd_img/modules/modules.cgz | cpio -id";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Handle the driver update disk failed. Could not gunzip modules.cgz from the initial initrd.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return ();
            }
        
            my @modinfo = ();
            foreach my $dd (@dd_list) {
                mkpath "$dd_dir/mnt";
                mkpath "$dd_dir/dd_modules";
        
                $cmd = "mount -o loop $dd $dd_dir/mnt";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update disk failed. Could not mount the driver update disk.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return ();
                }
    
                $cmd = "cd $dd_dir/dd_modules; gunzip -c $dd_dir/mnt/modules.cgz | cpio -id";
                xCAT::Utils->runcmd($cmd, -1);
    
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update disk failed. Could not gunzip the modules.cgz from the driver update disk.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    system("umount -f $dd_dir/mnt");
                    return ();
                }
        
                # Copy all the driver files out
                $cmd = "/bin/cp -rf $dd_dir/dd_modules/* $dd_dir/modules";
                xCAT::Utils->runcmd($cmd, -1);
        
                # Copy the firmware into the initrd
                mkpath "$dd_dir/initrd_img/firmware";
                $cmd = "/bin/cp -rf $dd_dir/dd_modules/firmware/* $dd_dir/initrd_img/firmware";
                xCAT::Utils->runcmd($cmd, -1);
       
                my $drivername; 
                # Get the entries from modinfo
                open (DDMODINFO, "<", "$dd_dir/mnt/modinfo");
                while (<DDMODINFO>) {
                    if ($_ =~ /^Version/) { next; }
                    if ($_ =~ /^(\S+)/) {
                        push @dd_drivers, $1;
                        $drivername=$1;
                    }
                    push @modinfo, $_;
                }
                close (DDMODINFO);
        
                # Append the modules.alias
                if (-r "$dd_dir/mnt/modules.alias") {
                  $cmd = "cat $dd_dir/mnt/modules.alias >> $dd_dir/initrd_img/modules/modules.alias";
                  xCAT::Utils->runcmd($cmd, -1);
                }
        
                # Append the modules.dep
                my $depfile;
                my $target;
                open($target,">>","$dd_dir/initrd_img/modules/modules.dep");
                open($depfile,"<","$dd_dir/mnt/modules.dep");
                my $curline;
                while ($curline=<$depfile>) {
                    if ($curline !~ /:/) { #missing the rather important first half of the equation here....
                        $curline = $drivername.": ".$curline;
                    }
                    print $target $curline;
                }
                close($target);
                close($depfile);

                # Append the pcitable
                if (-r "$dd_dir/mnt/pcitable") {
                  $cmd = "cat $dd_dir/mnt/pcitable >> $dd_dir/initrd_img/modules/pcitable";
                  xCAT::Utils->runcmd($cmd, -1);
                }

                if (-r "$dd_dir/mnt/modules.pcimap") { 
                  $cmd = "cat $dd_dir/mnt/modules.pcimap >> $dd_dir/initrd_img/modules/modules.pcimap";
                  xCAT::Utils->runcmd($cmd, -1);
                }
        
                $cmd = "umount -f $dd_dir/mnt";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update disk failed. Could not unmount the driver update disk.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    system("umount -f $dd_dir/mnt");
                    return ();
                }
    
                # Clean the env
                rmtree "$dd_dir/mnt";
                rmtree "$dd_dir/dd_modules";
                
                push @inserted_dd, $dd;
            }

            # Merge the drviers from rpm packages to the initrd
            if (@rpm_list && ($Injectalldriver || $updatealldriver || @driver_list)) {
                # Copy the firmware to the rootimage
                if (-d "$dd_dir/rpm/lib/firmware") {
                    if (! -d "$dd_dir/initrd_img/lib") {
                        mkpath "$dd_dir/initrd_img/lib";
                    }
                    $cmd = "/bin/cp -rf $dd_dir/rpm/lib/firmware $dd_dir/initrd_img";
                    xCAT::Utils->runcmd($cmd, -1);
                    if ($::RUNCMD_RC != 0) {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not copy firmware to the initrd.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }

                # if the new kernel from update distro is not existed in initrd, create the path for it
                if (! -r "$dd_dir/modules/$new_kernel_ver/$arch/") {
                    mkpath ("$dd_dir/modules/$new_kernel_ver/$arch/");
                }

                # get the name list for all drivers in the original initrd if 'netdrivers=updateonly'
                # then only the drivers in this list will be updated from the drvier rpms
                if ($updatealldriver) {
                    $driver_name = "\*\.ko";
                    @all_real_path = ();
                    find(\&get_all_path, <$dd_dir/modules/*>);
                    foreach my $real_path (@all_real_path) {
                        my $driver = basename($real_path);
                        push @driver_list, $driver;
                    }
                }

                # Copy the drivers to the initrd
                # Figure out the kernel version
                my @kernelpaths = <$dd_dir/modules/*>;
                my @kernelvers;
                if ($new_kernel_ver) {
                    push @kernelvers, $new_kernel_ver;
                }
                foreach (@kernelpaths) {
                    my $kernelv = basename($_);
                    if ($kernelv =~ /^[\d\.]+/) {
                        if ($new_kernel_ver) {
                            rmtree ("$dd_dir/modules/$kernelv");
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

                  # create path for the new kernel in the modules package
                  unless (-d "$dd_dir/modules/$kernelver") {
                      mkpath ("$dd_dir/modules/$kernelver/$arch/");
                  }
                  # find the $kernelver/$arch dir in the $dd_dir/modules
                  my $arch4modules;
                  foreach (<$dd_dir/modules/$kernelver/*>) {
                      if (basename($_) =~ $arch) {
                          $arch4modules = basename($_);
                      }
                  }
                  if (!$arch4modules) {
                      $arch4modules = basename(<$dd_dir/modules/$kernelver/*>);
                  }
                  if (! -d "$dd_dir/modules/$kernelver/$arch4modules/") {
                      next;
                  }
                  if (@driver_list) {
                    # copy all the specific drviers to the initrd
                    foreach my $driver (@driver_list) {
                      $driver_name = $driver;
                      @all_real_path = ();
                      find(\&get_all_path, <$dd_dir/rpm/lib/modules/$kernelver/*>);
                      foreach my $real_path (@all_real_path) {
                          $cmd = "/bin/cp -rf $real_path $dd_dir/modules/$kernelver/$arch4modules/";
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
                  } elsif ($Injectalldriver) {
                    # copy all the drviers to the initrd
                    if (-d "$dd_dir/rpm/lib/modules/$kernelver") {
                        $driver_name = "\*\.ko";
                        @all_real_path = ();
                        find(\&get_all_path, <$dd_dir/rpm/lib/modules/$kernelver/*>);
                        foreach my $driverpath (@all_real_path) {
                            $cmd = "/bin/cp -rf $driverpath $dd_dir/modules/$kernelver/$arch4modules/";
                            xCAT::Utils->runcmd($cmd, -1);
                            if ($::RUNCMD_RC != 0) {
                                my $rsp;
                                push @{$rsp->{data}}, "Handle the driver update failed. Could not copy $driverpath to the initrd.";
                                xCAT::MsgUtils->message("I", $rsp, $callback);
                            }
                            if ($driverpath =~ s/([^\/]*)\.ko//) {
                                push @rpm_drivers, $1;
                            }
                        }
                    } else {
                        my $rsp;
                        push @{$rsp->{data}}, "Handle the driver update failed. Could not find /lib/modules/$kernelver from the driver rpms.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }

                # Append the modules.dep to the one in the initrd
                if (-f "$dd_dir/rpm/lib/modules/$kernelver/modules.dep") {
                    $cmd = "cat $dd_dir/rpm/lib/modules/$kernelver/modules.dep >> $dd_dir/initrd_img/modules/modules.dep";
                    xCAT::Utils->runcmd($cmd, -1);
                }
              }
            }

            # Regenerate the modules.dep
            # 'depmod' command only can handle the drivers in /lib/modules/kernelver strcuture, so copy the drivers to a temporary
            # dirctory $dd_dir/depmod/lib/modules/$mk, run 'depmod' and copy the modules.dep to the correct dir
            my ($mk, $ma);
            $mk = <$dd_dir/modules/*>;
            if (-d $mk) {
              $mk = basename($mk);
              $ma = <$dd_dir/modules/$mk/*>;
              if (-d $ma) {
                mkpath "$dd_dir/depmod/lib/modules/$mk";
                xCAT::Utils->runcmd("/bin/cp -rf $ma/* $dd_dir/depmod/lib/modules/$mk", -1);
                $cmd = "depmod -b $dd_dir/depmod/ $mk";
                #$cmd = "depmod -b $dd_dir/depmod/";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not generate the depdency for the drivers in the initrd.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                # remove the .ko postfix from the driver name for rh5
                $cmd = "/bin/sed ".'s/\.ko//g'." $dd_dir/depmod/lib/modules/$mk/modules.dep > $dd_dir/depmod/lib/modules/$mk/modules.dep1; mv -f $dd_dir/depmod/lib/modules/$mk/modules.dep1 $dd_dir/depmod/lib/modules/$mk/modules.dep";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Handle the driver update failed. Could not generate the depdency for the drivers in the initrd.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                if (-f "$dd_dir/depmod/lib/modules/$mk/modules.dep") {
                    copy ("$dd_dir/depmod/lib/modules/$mk/modules.dep", "$dd_dir/initrd_img/modules/modules.dep");
                }

                # remove the path and postfix of the driver modules from the new generated modules.dep since original format has not path and postfix
                my @newdep;
                if (open (DEP, "<$dd_dir/initrd_img/modules/modules.dep")) {
                  while (<DEP>) {
                    s/\/lib\/modules\/$mk\/([^\.]+)\.ko/$1/g;
                    if (/:\s*\S+/) {
                      push @newdep, $_;
                    }
                  }
                  close (DEP);
                }
                if (open (NEWDEP, ">$dd_dir/initrd_img/modules/modules.dep")) {
                  print NEWDEP @newdep;
                  close (NEWDEP);
                }
              }
            }
            
        
            # Append the modinfo into the module-info
            open (MODINFO, "<", "$dd_dir/initrd_img/modules/module-info");
            open (MODINFONEW, ">", "$dd_dir/initrd_img/modules/module-info.new");
            my $removeflag = 0;
            my @orig_drivers;
            while (<MODINFO>) {
                my $line = $_;
                if ($line =~ /^(\S+)/) {
                    if (grep /$1/, @dd_drivers) {
                        $removeflag = 1;
                        next;
                    } else {
                        push @orig_drivers, $1;
                        $removeflag = 0;
                    }
                }
        
                if ($removeflag == 1) { next; }
                print MODINFONEW $line;
            }
        
            print MODINFONEW @modinfo;

            # add the drivers from rpm
            foreach my $dr (@rpm_drivers) {
                $dr =~ s/\.ko//;
                if (! grep /^$dr$/, (@orig_drivers,@dd_drivers)) {
                    print MODINFONEW $dr."\n";
                }
            }

            close (MODINFONEW);
            close (MODINFO);
            move ("$dd_dir/initrd_img/modules/module-info.new", "$dd_dir/initrd_img/modules/module-info");
        
            # Repack the modules
            $cmd = "cd $dd_dir/modules; find . -print | cpio -o -H crc | gzip -9 > $dd_dir/initrd_img/modules/modules.cgz";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Handle the driver update disk failed. Could not pack the hacked modules.cgz.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return ();
            }
        } # End of non dracut
    
        # Repack the initrd
        if ($initrdfmt eq "gzip") {
            $cmd = "cd $dd_dir/initrd_img; find .|cpio -H newc -o|gzip -9 -c - > $dd_dir/initrd.img";
        } elsif ($initrdfmt eq "lzma") {
            $cmd = "cd $dd_dir/initrd_img; find .|cpio -H newc -o|xz --format=lzma -C crc32 -9 > $dd_dir/initrd.img";
        }
        
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0) {
            my $rsp;
            push @{$rsp->{data}}, "Handle the driver update disk failed. Could not pack the hacked initrd.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        }
    
        copy ("$dd_dir/initrd.img", $img);
    }

    # dracut + driver disk, just append the driver disk to the initrd
    if (<$install_dir/$os/$arch/Packages/dracut*> && @dd_list) { #new style, skip the fanagling, copy over the dds and append them...
	mkpath("$dd_dir/dd");
	if (scalar(@dd_list) == 1) { #only one, just append it..
		copy($dd_list[0],"$dd_dir/dd/dd.img");
	} elsif (scalar(@dd_list) > 1) {
		unless (-x "/usr/bin/createrepo" and -x "/usr/bin/mkisofs") {
        		my $rsp;
		        push @{$rsp->{data}}, "Merging multiple driver disks requires createrepo and mkisofs utilities";
		        xCAT::MsgUtils->message("E", $rsp, $callback);
		        return ();
		}
		mkpath("$dd_dir/newddimg");
		mkpath("$dd_dir/tmpddmnt");
		foreach my $dd (@dd_list) {
			xCAT::Utils->runcmd("mount -o loop $dd $dd_dir/tmpddmnt",-1);
			xCAT::Utils->runcmd("/bin/cp -a $dd_dir/tmpddmnt/* $dd_dir/newddimg",-1);
			xCAT::Utils->runcmd("umount $dd_dir/tmpddmnt",-1);
		}
		foreach my $repodir (<$dd_dir/newddimg/*/*/repodata>) {
			$repodir =~ s/\/repodata\z//;
			xCAT::Utils->runcmd("createrepo $repodir",-1);
		}
		chdir("$dd_dir/newddimg");
		xCAT::Utils->runcmd("mkisofs -J -R -o $dd_dir/dd/dd.img .",-1);
	} else { #there should be no else...
		die "This should never occur";
	}

	chdir($dd_dir."/dd");
		$cmd = "find .|cpio -H newc -o|gzip -9 -c - > ../dd.gz";
	xCAT::Utils->runcmd($cmd, -1);
	unless (-f "../dd.gz") {
		die "Error attempting to archive driver disk";
	}
	my $ddhdl;
		my $inithdl;
	open($inithdl,">>",$img);
	open($ddhdl,"<","../dd.gz");
	binmode($ddhdl);
	binmode($inithdl);
	{
		local $/ = \32768;
		while (my $block = <$ddhdl>) { print $inithdl $block; }
	}
	chdir("/");
	push @inserted_dd, @dd_list;
    }

    # clean the env
    rmtree $dd_dir;
        
    my $rsp;
    if (@dd_list) {
        push @{$rsp->{data}}, "The driver update disk:".join(',',@inserted_dd)." have been injected to initrd.";
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
        } elsif ($Injectalldriver) {
            push @{$rsp->{data}}, "All the drivers from: ".join(',', sort(@rpm_list))." have been injected to initrd.";
        } else {
            push @{$rsp->{data}}, "No driver was injected to initrd.";
        }
    }
    
    xCAT::MsgUtils->message("I", $rsp, $callback);

    return @inserted_dd;
}

1;
