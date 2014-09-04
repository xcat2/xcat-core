#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::imgcapture;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";

use strict;

use Data::Dumper;   # for debug purpose
use Getopt::Long;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::SvrUtils;
use xCAT::Table;
use File::Path qw(mkpath);

Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $verbose = 0;
my $installroot = "/install";
my $sysclone_home = $installroot . "/sysclone";

sub handled_commands {
    return { "imgcapture" => "imgcapture" };
}

sub process_request {
    my $request = shift;
    my $callback = shift;
    my $doreq = shift;

    my $node;
    if (exists $request->{node}) {
        $node = $request->{node}->[0];
    }

    $installroot = xCAT::TableUtils->getInstallDir();
    @ARGV = @{$request->{arg}} if (defined $request->{arg});
    my $argc = scalar @ARGV;

    my $usage = "Usage: imgcapture <node> -t|--type diskless [-p | --profile <profile>] [-o|--osimage <osimage>] [-i <nodebootif>] [-n <nodenetdrivers>] [-d | --device <devicesToCapture>] [-V | --verbose] \n imgcapture <node> -t|--type sysclone -o|--osimage <osimage> [-V | --verbose] \n imgcapture [-h|--help] \n imgcapture [-v|--version]";

    my $os;
    my $arch;
    my $device;
    my $profile;
    my $bootif;
    my $netdriver;
    my $osimg;
    my $help;
    my $version;
    my $type;

    GetOptions(
        "profile|p=s" => \$profile,
        "i=s" => \$bootif,
        'n=s' => \$netdriver,
        'osimage|o=s' => \$osimg,
        "device|d=s" => \$device,
        "help|h" => \$help,
        "version|v" => \$version,
        "verbose|V" => \$verbose,
        "type|t=s" => \$type
    );

    if ( defined( $ARGV[0] )) {
        my $rsp = {};
        $rsp->{data}->[0] = "Invalid Argument: $ARGV[0]";
        $rsp->{data}->[1] = $usage;
        xCAT::MsgUtils->message("D", $rsp, $callback);
        return 0;
    }
    
    if($version) {
        my $version = xCAT::Utils->Version();
        my $rsp = {};
        $rsp->{data}->[0] = $version;
        xCAT::MsgUtils->message("D", $rsp, $callback);
        return 0;
    }

    if($help) {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("D", $rsp, $callback);
        return 0;
    }

    if( ! $node ) {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("D", $rsp, $callback);
        return 0;
    }

    if(($type =~ /sysclone/) && (!$osimg)){
        my $rsp = {};
        push @{$rsp->{data}}, "You must specify osimage name if you are using \"sysclone\".";
        push @{$rsp->{data}}, $usage;
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;    
    }
    
    my $nodetypetab = xCAT::Table->new("nodetype");
    my $ref_nodetype = $nodetypetab->getNodeAttribs($node, ['os','arch','profile']);
    $os = $ref_nodetype->{os};
    $arch = $ref_nodetype->{arch};
    unless($profile) {
        $profile = $ref_nodetype->{profile};
    }
    
    # sysclone
    unless($type =~ /diskless/)
    {
    	# Handle image capture separately for s390x 
    	if ($arch eq 's390x') {
            eval { require xCAT_plugin::zvm; };  # Load z/VM plugin dynamically
            xCAT_plugin::zvm->imageCapture($callback, $node, $os, $arch, $profile, $osimg, $device);
            return;
        }
    
        my $shortname = xCAT::InstUtils->myxCATname();

        my $rc;
        $rc  = sysclone_configserver($shortname, $osimg, $callback, $doreq);
        if($rc){
            my $rsp = {};
            $rsp->{data}->[0] = qq{Can not configure Imager Server on $shortname.};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        
        $rc = sysclone_prepclient($node, $shortname, $osimg, $callback, $doreq);
        if($rc){
            my $rsp = {};
            $rsp->{data}->[0] = qq{Can not prepare Golden Client on $node.};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        
        $rc = sysclone_getimg($node, $shortname, $osimg, $callback, $doreq);
        if($rc){
            my $rsp = {};
            $rsp->{data}->[0] = qq{Can not get image $osimg from $node.};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        $rc = sysclone_createosimgdef($node, $shortname, $osimg, $callback, $doreq);
        if($rc){
            my $rsp = {};
            $rsp->{data}->[0] = qq{Can not create osimage definition for $osimg on $shortname.};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        return;
    }
    
    # -i flag is required with sles genimage
    if (!$bootif && $os =~ /^sles/) {
        $bootif = "eth0";
    }
    
    # check whether the osimage exists or not
    if($osimg) {
        my $osimgtab=xCAT::Table->new('osimage', -create=>1);
        unless($osimgtab) {
            # the osimage table doesn't exist
            my $rsp = {};
            $rsp->{data}->[0] = qq{Cannot open the osimage table};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        my $linuximgtab = xCAT::Table->new('linuximage', -create=>1);
        unless($linuximgtab) {
            # the linuximage table doesn't exist
            my $rsp = {};
            $rsp->{data}->[0] = qq{Cannot open the linuximage table};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        my ($ref) = $osimgtab->getAttribs({imagename => $osimg}, 'osvers', 'osarch', 'profile');
        unless($ref) {
            my $rsp = {};
            $rsp->{data}->[0] = qq{Cannot find $osimg from the osimage table.};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        my ($ref1) = $linuximgtab->getAttribs({imagename => $osimg}, 'imagename');
        unless($ref1) {
            my $rsp = {};
            $rsp->{data}->[0] = qq{Cannot find $osimg from the linuximage table};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        # make sure the "osvers" and "osarch" attributes match the node's attribute
        unless($os eq $ref->{'osvers'} and $arch eq $ref->{'osarch'}) {
            my $rsp = {};
            $rsp->{data}->[0] = qq{The 'osvers' or 'osarch' attribute of the "$osimg" table doesn't match the node's attribute};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }
    }
    
    imgcapture($node, $os, $arch, $profile, $osimg, $bootif, $netdriver, $callback, $doreq);
}

sub imgcapture {
    my ($node, $os, $arch, $profile, $osimg, $bootif, $netdriver, $callback, $subreq) = @_;
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = "nodename is $node; os is $os; arch is $arch; profile is $profile";
        $rsp->{data}->[1] = "bootif is $bootif; netdriver is $netdriver";
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    # make sure the "/" partion is on the disk, 
    my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => [$node], arg =>["stat / -f |grep Type"]}, $subreq, -1, 1);
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{the output of "stat / -f |grep Type" on $node is:};
        foreach my $o (@$output) {
            push @{$rsp->{data}}, $o;
        }
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC) { #failed
        my $rsp = {};
        $rsp->{data}->[0] = qq{The "xdsh" command fails to run on the $node};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # parse the output of "stat / -f |grep Type", 
    $output->[0] =~ m/Type:\s+(.*)$/;
    my $fstype =  $1;
    if ($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{The file type is $fstype};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    # make sure the rootfs type is not nfs or tmpfs
    if($fstype eq "nfs" or $fstype eq "tmpfs") {
        my $rsp = {};
        $rsp->{data}->[0] = qq{This node might not be diskful Linux node, please check it.};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my $distname = $os;
    while ( $distname and ( ! -r "$::XCATROOT/share/xcat/netboot/$distname/") ) {
        chop($distname);
    }

    unless($distname) {
        $callback->({error=>["Unable to find $::XCATROOT/share/xcat/netboot directory for $os"], errorcode => [1]});
        return;
    }

    my $exlistloc = xCAT::SvrUtils->get_imgcapture_exlist_file_name("$installroot/custom/netboot/$distname", $profile, $os, $arch);
    unless ($exlistloc) {
        $exlistloc = xCAT::SvrUtils->get_imgcapture_exlist_file_name("$::XCATROOT/share/xcat/netboot/$distname", $profile, $os, $arch);
    }

    my $xcat_imgcapture_tmpfile = "/tmp/xcat_imgcapture.$$";

    my $excludestr = "cd /; find .";

    if($exlistloc) {
        my $exlist;
        open $exlist, "<", $exlistloc;

        while(<$exlist>) {
            $_ =~ s/^\s+//;
            chomp $_;
            unless($_ =~ m{^#}) {
                $excludestr .= qq{ ! -path "$_"};
            }
        }

        close $exlist;
    } else {
        # the following directories must be exluded when capturing the image
        my @default_exlist = ("./tmp/*", "./proc/*", "./sys/*", "./dev/*", "./xcatpost/*", "./install/*");
        foreach my $item (@default_exlist) {
            $excludestr .= qq{ ! -path "$item"};
        }
    }

    $excludestr .= " |cpio -H newc -o |gzip -c - >$xcat_imgcapture_tmpfile";
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{The excludestr is "$excludestr"};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    # run the command via "xdsh"

    xCAT::Utils->runxcmd({command => ["xdsh"], node => [$node], arg => ["echo -n >$xcat_imgcapture_tmpfile"]}, $subreq, -1, 1);
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{running "echo -n > $xcat_imgcapture_tmpfile" on $node};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC) { # the xdsh command fails
        my $rsp = {};
        $rsp->{data}->[0] = qq{The "xdsh" command fails to run "echo -n > $xcat_imgcapture_tmpfile" on $node};
        xCAT:MsgUtils->message("E", $rsp, $callback);
        return;
    }

    my $rsp = {};
    $rsp->{data}->[0] = qq{Capturing image on $node...};
    xCAT::MsgUtils->message("D", $rsp, $callback);

    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{running "$excludestr" on $node via the "xdsh" command};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    xCAT::Utils->runxcmd({command => ["xdsh"], node => [$node], arg => [$excludestr]}, $subreq, -1, 1);

    if($::RUNCMD_RC) { # the xdsh command fails
        my $rsp = {};
        $rsp->{data}->[0] = qq{The "xdsh" command fails to run "$excludestr" on $node};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }

    $rsp = {};
    $rsp->{data}->[0] = qq{Transfering the image captured on $node back...};
    xCAT::MsgUtils->message("D", $rsp, $callback);

    # copy the image captured on $node back via the "scp" command
    xCAT::Utils->runcmd("scp $node:$xcat_imgcapture_tmpfile $xcat_imgcapture_tmpfile");
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{Running "scp $node:$xcat_imgcapture_tmpfile $xcat_imgcapture_tmpfile"};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC) {
        my $rsp ={};
        $rsp->{data}->[0] = qq{The scp command fails};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }

    xCAT::Utils->runxcmd({command => ["xdsh" ], node => [$node], arg => ["rm -f $xcat_imgcapture_tmpfile"]}, $subreq, -1, 1);

    # extract the $xcat_imgcapture_tmpfile file to /install/netboot/$os/$arch/$profile/rootimg
    my $rootimgdir = "$installroot/netboot/$os/$arch/$profile/rootimg";

    # empty the rootimg directory before extracting the image captured on the diskful Linux node
    if( -d $rootimgdir ) {
        unlink $rootimgdir;
    }
    mkpath($rootimgdir);

    xCAT::Utils->runcmd("cd $rootimgdir; gzip -cd $xcat_imgcapture_tmpfile|cpio -idum");
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{Extracting the image to $rootimgdir};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }
    if($::RUNCMD_RC) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{fails to run the "gzip -cd xx |cpio -idum" command};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }
    
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{Creating the spots exluded when capturing on $node...};
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    # the next step is to call "genimage"
    my $platform = getplatform($os);
    if( -e "$::XCATROOT/share/xcat/netboot/$platform/genimage" ) {
        my $cmd;

        if( $osimg ) {
            $cmd = "$::XCATROOT/bin/genimage $osimg ";
        } else {
            $cmd = "$::XCATROOT/share/xcat/netboot/$platform/genimage -o $os -a $arch -p $profile ";
        }

        if($bootif) {
            $cmd .= "-i $bootif ";
        }
        if($netdriver) {
            $cmd .= "-n $netdriver";
        }

        my $rsp = {};
        $rsp->{data}->[0] = qq{Generating kernel and initial ramdisks...};
        xCAT::MsgUtils->message("D", $rsp, $callback);

        if($verbose) {
            my $rsp = {};
            $rsp->{data}->[0] = qq{"The genimage command is: $cmd"};
            xCAT::MsgUtils->message("D", $rsp, $callback);
        }
        my @cmdoutput = xCAT::Utils->runcmd($cmd, 0);
        if($::RUNCMD_RC) {
            my $rsp = {};
            foreach (@cmdoutput) {
                push @{$rsp->{data}}, $_;
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            unlink $xcat_imgcapture_tmpfile;
            return;
        }
    } else {
        my $rsp = {};
        $rsp->{data}->[0] = qq{Can't run the "genimage" command for $os};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }

    my $rsp = {};
    $rsp->{data}->[0] = qq{Done.};
    xCAT::MsgUtils->message("D", $rsp, $callback);

    unlink $xcat_imgcapture_tmpfile;

    return 0;
}

sub getplatform {
    my $os = shift;
    my $platform;
    if ($os =~ m/rh.*/) {
        $platform = "rh";
    } elsif ($os =~ m/centos.*/) {
        $platform = "centos";
    } elsif ($os =~ m/fedora.*/) {
        $platform = "fedora";
    } elsif ($os =~ m/SL.*/) {
        $platform = "SL";
    } elsif ($os =~ m/sles.*/) {
        $platform = "sles";
    } elsif ($os =~ m/suse.*/) {
        $platform = "suse";
    }

    return $platform;
}

sub sysclone_configserver{
    my ($server, $osimage, $callback, $subreq) = @_;
    
    # check if systemimager is installed on the imager server
    my $rsp = {};
    $rsp->{data}->[0] = qq{Checking if systemimager packages are installed on $server.};
    xCAT::MsgUtils->message("D", $rsp, $callback);
    
    my $cmd = "rpm -qa|grep systemimager-server";
    my $output = xCAT::Utils->runcmd("$cmd", -1);    
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{the output of $cmd on $server is:};
        push @{$rsp->{data}}, $output;
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC != 0) { #failed
        my $rsp = {};
        $rsp->{data}->[0] = qq{systemimager-server is not installed on the $server.};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # update /etc/systemimager/systemimager.conf
    my $rc = `sed -i "s/\\/var\\/lib\\/systemimager/\\/install\\/sysclone/g" /etc/systemimager/systemimager.conf`;
    if (!(-e $sysclone_home))
    {
        mkpath($sysclone_home);
    }

    my $sysclone_images = $sysclone_home . "/images";
    if (!(-e $sysclone_images))
    {
        mkpath($sysclone_images);
    }

    my $sysclone_scripts = $sysclone_home . "/scripts";
    if (!(-e $sysclone_scripts))
    {
        mkpath($sysclone_scripts);
    }

    my $sysclone_overrides = $sysclone_home . "/overrides";
    if (!(-e $sysclone_overrides))
    {
        mkpath($sysclone_overrides);
    }
	
    my $imagedir;
    my $osimgtab  = xCAT::Table->new('osimage');
    my $entry = ($osimgtab->getAllAttribsWhere("imagename = '$osimage'", 'ALL' ))[0];
    if(!$entry){
        $imagedir = $sysclone_home . "/images/" . $osimage;  
    }else{
        my $osimagetab = xCAT::Table->new('linuximage');
        my $osimageentry  = $osimagetab->getAttribs({imagename => $osimage}, 'rootimgdir');
        if($osimageentry){
            $imagedir = $osimageentry->{rootimgdir};
            if (!(-e $imagedir)){
		        mkpath($imagedir);
            }
        }else{
            $imagedir = $sysclone_home . "/images/" . $osimage;   
            $cmd = "chdef -t osimage $osimage rootimgdir=$imagedir";
            $rc = `$cmd`;
        }
    }

    $imagedir =~ s/^(\/.*)\/.+\/?$/$1/;
    $imagedir =~ s/\//\\\\\//g;
    $imagedir = "DEFAULT_IMAGE_DIR = ".$imagedir;
				
    my $olddir = `more /etc/systemimager/systemimager.conf |grep DEFAULT_IMAGE_DIR`;
    $olddir =~ s/\//\\\\\//g;
    chomp($olddir);
		
    $cmd= "sed -i \"s/$olddir/$imagedir/\"  /etc/systemimager/systemimager.conf";
    $rc = `$cmd`;
	
    # update /etc/systemimager/rsync_stubs/10header to generate new /etc/systemimager/rsyncd.conf
    $rc = `sed -i "s/\\/var\\/lib\\/systemimager/\\/install\\/sysclone/g" /etc/systemimager/rsync_stubs/10header`;
    $rc = `export PERL5LIB=/usr/lib/perl5/site_perl/;LANG=C si_mkrsyncd_conf`;
    
    return 0;
}

sub sysclone_prepclient {
    my ($node, $server, $osimage, $callback, $subreq) = @_;
    
    # check if systemimager is installed on the golden client
    my $rsp = {};
    $rsp->{data}->[0] = qq{Checking if systemimager packages are installed on $node.};
    xCAT::MsgUtils->message("D", $rsp, $callback);
    
    my $cmd = "rpm -qa|grep systemimager-client";
    my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => [$node], arg =>[$cmd]}, $subreq, 0, 1);
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{the output of $cmd on $node is:};
        foreach my $o (@$output) {
            push @{$rsp->{data}}, $o;
        }
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC != 0) { #failed
        my $rsp = {};
        $rsp->{data}->[0] = qq{systemimager-client is not installed on the $node.};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # prepare golden client
    my $rsp = {};
    $rsp->{data}->[0] = qq{Preparing osimage $osimage on $node.};
    xCAT::MsgUtils->message("D", $rsp, $callback);
    
    my $cmd = "export PERL5LIB=/usr/lib/perl5/site_perl/;LANG=C si_prepareclient --server $server --no-uyok --yes";
    my $output = xCAT::Utils->runxcmd(
                                            {
                                            command => ["xdsh"], 
                                            node => [$node], 
                                            arg =>["-s", $cmd]
                                            }, 
                                            $subreq, 0, 1);
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{the output of $cmd on $node is:};
        foreach my $o (@$output) {
            push @{$rsp->{data}}, $o;
        }
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC != 0) { #failed
        my $rsp = {};
        $rsp->{data}->[0] = qq{$cmd failed on the $node.};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # fix systemimager bug
    $cmd  = qq{sed -i 's/p_name=\"(v1)\"/p_name=\"-\"/' /etc/systemimager/autoinstallscript.conf};
    $output = xCAT::Utils->runxcmd(
                                            {
                                            command => ["xdsh"], 
                                            node => [$node], 
                                            arg =>[$cmd]
                                            }, 
                                            $subreq, 0, 1);
                                            
    my @nodes = ($node);
    my $nodetypetab = xCAT::Table->new("nodetype");
    my $nthash = $nodetypetab->getNodesAttribs(\@nodes, ['arch']);
    my $tmp = $nthash->{$node}->[0]->{arch};
    if ( $tmp eq 'ppc64'){
        $cmd  = qq(if ! cat /etc/systemimager/autoinstallscript.conf |grep 'part  num=\\\"1\\\"' |grep 'id=' >/dev/null ;then sed -i 's:\\(.*<part  num=\\\"1\\\".*\\)\\(/>\\):\\1 id=\\\"41\\\" \\2:' /etc/systemimager/autoinstallscript.conf;fi);
        $output = xCAT::Utils->runxcmd(
                                            {
                                            command => ["xdsh"],
                                            node => [$node],
                                            arg =>[$cmd]
                                            },
                                            $subreq, 0, 1);
    }

    return 0;
}

sub sysclone_getimg{
    my ($node, $server, $osimage, $callback, $subreq) = @_;

    my $rsp = {};
    $rsp->{data}->[0] = qq{Getting osimage "$osimage" from $node to $server.};
    xCAT::MsgUtils->message("D", $rsp, $callback);

    my $cmd = "export PERL5LIB=/usr/lib/perl5/site_perl/;";
    $cmd .= "LANG=C si_getimage -golden-client $node -image $osimage -ip-assignment dhcp -post-install reboot -quiet -update-script YES";
    my $output = xCAT::Utils->runcmd($cmd, -1);
    if($verbose) {
        my $rsp = {};
        $rsp->{data}->[0] = qq{the output of $cmd on $server is:};
        if(ref $output){
            foreach my $o (@$output) {
                push @{$rsp->{data}}, $o;
            }
        } else {
            @{$rsp->{data}} = ($output);
        }
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    if($::RUNCMD_RC != 0) { #failed
        my $rsp = {};
        $rsp->{data}->[0] = qq{$cmd failed on the $server.};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # use reboot in genesis
    my $masterscript = $sysclone_home . "/scripts" . "/$osimage.master";
    my $rc = `sed -i "s/shutdown -r now/reboot -f/g" $masterscript`;

    #on redhat5 and centos5, the fs inode size must be 128
    my $node_osver = getOsVersion($node);
    if ( $node_osver =~ /rh.*5.*/ || $node_osver =~ /centos5.*/ ) {
        `sed -i "s/mke2fs/mke2fs -I 128/g" $masterscript`
    }
    return 0;
}

sub sysclone_createosimgdef{
    my ($node, $server, $osimage, $callback, $subreq) = @_;
    my $createnew = 0;
    my %osimgdef;

    my $osimgtab  = xCAT::Table->new('osimage');
    my $entry = ($osimgtab->getAllAttribsWhere("imagename = '$osimage'", 'ALL' ))[0];
     if($entry){
        my $rsp = {};
        $rsp->{data}->[0] = qq{Using the existing osimage "$osimage" defined on $server.};
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
     }
    
    # try to see if we can get the osimage def from golden client.
    my $nttab  = xCAT::Table->new('nodetype');
    if (!$nttab){
        my $rsp = {};
        $rsp->{data}->[0] = qq{Can not open nodebype table.};
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my @nodes = ($node);
    my $nthash = $nttab->getNodesAttribs(\@nodes, ['node', 'provmethod']);
    my $tmp = $nthash->{$node}->[0];
    if (($tmp) && ($tmp->{provmethod})){

        my %objtype;
        my $oldimg = $tmp->{provmethod};

        # see if osimage exists
        $objtype{$oldimg} = 'osimage';
        my %imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
        if (!($imagedef{$oldimg}{osvers})){ # just select one attribute for test
            # create new one
            $createnew = 1;
        }else{
            # based on the existing one
            $osimgdef{$osimage} = $imagedef{$oldimg};

            # only update a few attributes which are meanless for sysclone
            $osimgdef{$osimage}{provmethod} = "sysclone";
            $osimgdef{$osimage}{template} = "";
            $osimgdef{$osimage}{otherpkglist} = "";
            $osimgdef{$osimage}{pkglist} = "";
			
            if(!($imagedef{$oldimg}{rootimgdir})){
                $imagedef{$oldimg}{rootimgdir} = $sysclone_home . "/images/" . $osimage;      
				
                my $imagedir = $imagedef{$oldimg}{rootimgdir};
                $imagedir =~ s/^(\/.*)\/.+\/?$/$1/;
                $imagedir =~ s/\//\\\\\//g;
                $imagedir = "DEFAULT_IMAGE_DIR = ".$imagedir;
				
                my $olddir = `more /etc/systemimager/systemimager.conf |grep DEFAULT_IMAGE_DIR`;
                $olddir =~ s/\//\\\\\//g;
                chomp($olddir);
		
                my $cmd= "sed -i \"s/$olddir/$imagedir/\"  /etc/systemimager/systemimager.conf";
                my $rc = `$cmd`;
            }
        }
    } else {
        $createnew = 1;
    }

    if($createnew){
        my $file = $sysclone_home . "/images/" . $osimage. "/etc/systemimager/boot/ARCH";
        my $cmd = "cat $file";
        my $output = xCAT::Utils->runcmd($cmd, -1);
        chomp $output;
        my $arch = $output;
        my $osver = getOsVersion($node);
        my $platform = getplatform($osver);

        # create a baic one
        $osimgdef{$osimage}{objtype} = "osimage";
        $osimgdef{$osimage}{provmethod} = "sysclone";
        $osimgdef{$osimage}{profile} = "compute";  # use compute?
        $osimgdef{$osimage}{imagetype} = "Linux";
        $osimgdef{$osimage}{osarch} = $arch;
        $osimgdef{$osimage}{osname} = "Linux";
        $osimgdef{$osimage}{osvers} =  $osver;
        $osimgdef{$osimage}{osdistroname} =  "$osver-$arch";
		
        $osimgdef{$osimage}{rootimgdir} = $sysclone_home . "/images/" . $osimage;
        my $imagedir = $osimgdef{$osimage}{rootimgdir};
        $imagedir =~ s/^(\/.*)\/.+\/?$/$1/;
        $imagedir =~ s/\//\\\\\//g;
        $imagedir = "DEFAULT_IMAGE_DIR = ".$imagedir;
        my $olddir = `more /etc/systemimager/systemimager.conf |grep DEFAULT_IMAGE_DIR`;
        $olddir =~ s/\//\\\\\//g;
        chomp($olddir);
        my $cmd= "sed -i \"s/$olddir/$imagedir/\"  /etc/systemimager/systemimager.conf";
        my $rc = `$cmd`;
		
        #$osimgdef{$osimage}{pkgdir} =  "/install/$osver/$arch";
        #$osimgdef{$osimage}{otherpkgdir} =  "/install/post/otherpkgs/$osver/$arch";
    }

    if (xCAT::DBobjUtils->setobjdefs(\%osimgdef) != 0)
    {
        my $rsp;
        $rsp->{data}->[0] = "Could not create xCAT definition for $osimage.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my $rsp = {};
    $rsp->{data}->[0] = qq{The osimage definition for $osimage was created.};
    xCAT::MsgUtils->message("D", $rsp, $callback);

    return 0;    
}

sub getOsVersion {
    my ($node) = @_;

    my $os = '';
    my $version = '';

    # Get operating system
    my $release = `ssh -o ConnectTimeout=2 $node "cat /etc/*release"`;
    my @lines = split('\n', $release);
    if (grep(/SLES|Enterprise Server/, @lines)) {
        $os = 'sles';
        $version = $lines[0];
        $version =~ tr/\.//;
        $version =~ s/[^0-9]*([0-9]+).*/$1/;
        $os = $os . $version;
        
        # Append service level
        $version = `echo "$release" | grep "LEVEL"`;
        $version =~ tr/\.//;
        $version =~ s/[^0-9]*([0-9]+).*/$1/;
        $os = $os . 'sp' . $version;
    } elsif (grep(/Red Hat/, @lines)) {
        $os = "rh";
        $version = $lines[0];
        $version =~ s/[^0-9]*([0-9.]+).*/$1/;
        if    ($lines[0] =~ /AS/)     { $os = 'rhas' }
        elsif ($lines[0] =~ /ES/)     { $os = 'rhes' }
        elsif ($lines[0] =~ /WS/)     { $os = 'rhws' }
        elsif ($lines[0] =~ /Server/) { $os = 'rhels' }
        elsif ($lines[0] =~ /Client/) { $os = 'rhel' }
        #elsif (-f "/etc/fedora-release") { $os = 'rhfc' }
        $os = $os . $version;
    }
    elsif (grep (/CentOS/, @lines)) {
        $os = "centos";
        $version = $lines[0];
        $version =~ s/[^0-9]*([0-9.]+).*/$1/;
        $os = $os . $version;
    }
    elsif (grep (/Fedora/, @lines)) {
        $os = "fedora";
        $version = $lines[0];
        $version =~ s/[^0-9]*([0-9.]+).*/$1/;
        $os = $os . $version;
    }
    

    return $os;
}
1;
