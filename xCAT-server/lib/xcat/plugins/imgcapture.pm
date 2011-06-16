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
use xCAT::Table;
use File::Path qw(mkpath);

Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $verbose = 0;
my $installroot = "/install";

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

    $installroot = xCAT::Utils->getInstallDir();
    @ARGV = @{$request->{arg}} if (defined $request->{arg});
    my $argc = scalar @ARGV;

    my $usage = "Usage: imgcapture <node> [-p | --profile <profile>] [-o|--osimage <osimage>] [-i <nodebootif>] [-n <nodenetdrivers>] [-V | --verbose] \n imgcapture [-h|--help] \n imgcapture [-v|--version]";

    my $os;
    my $arch;
    my $profile;
    my $bootif;
    my $netdriver;
    my $osimg;
    my $help;
    my $version;

    GetOptions(
        "profile|p=s" => \$profile,
        "i=s" => \$bootif,
        'n=s' => \$netdriver,
        'osimage|o=s' => \$osimg,
        "help|h" => \$help,
        "version|v" => \$version,
        "verbose|V" => \$verbose
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

    my $nodetypetab = xCAT::Table->new("nodetype");
    my $ref_nodetype = $nodetypetab->getNodeAttribs($node, ['os','arch','profile']);
    $os = $ref_nodetype->{os};
    $arch = $ref_nodetype->{arch};
    unless($profile) {
        $profile = $ref_nodetype->{profile};
    }

    # check whether the osimage exists or not
    if($osimg) {
        my $osimgtab=xCAT::Table->new('osimage', -create=>1);
        unless($osimgtab) {
            # the osimage table doesn't exist
            my $rsp = {};
            $rsp->{data}->[0] = qq{Cannot open the osimage table};
            $xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        my $linuximgtab = xCAT::Table->new('linuximage', -create=>1);
        unless($linuximgtab) {
            # the linuximage table doesn't exist
            my $rsp = {};
            $rsp->{data}->[0] = qq{Cannot open the linuximage table};
            $xCAT::MsgUtils->message("E", $rsp, $callback);
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
            $cmd = "$::XCATROOT/share/xcat/netboot/$platform/genimage $osimg";
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

1;
