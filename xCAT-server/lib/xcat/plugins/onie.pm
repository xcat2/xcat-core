#!/usr/bin/env perl
## IBM(c) 20013 EPL license http://www.eclipse.org/legal/epl-v10.html
#
# This plugin is used to handle the command requests for cumulus OS support
#


package xCAT_plugin::onie;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use Getopt::Long;
use File::Path;
use File::Basename;

use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::TableUtils;
use xCAT::SvrUtils;
use xCAT::Table;
my $xcatdebugmode = 0;
$::VERBOSE        = 0;

sub handled_commands {
    return {
        nodeset => 'nodehm:mgt=switch',    
        copydata => 'onie',
      }
}

my $CALLBACK;                       # used to hanel the output from xdsh

sub preprocess_request {
    my $request  = shift;
    my $callback = shift;

    if ($request->{command}->[0] eq 'copydata')
    {
        return [$request];
    }

    # if already preprocessed, go straight to request
    if ((defined($request->{_xcatpreprocessed}->[0]))
        && ($request->{_xcatpreprocessed}->[0] == 1)) {
        return [$request];
    }

    my $nodes     = $request->{node};
    my $command   = $request->{command}->[0];
    my $extraargs = $request->{arg};

    if ($extraargs) {
        @ARGV = @{$extraargs};
        my ($verbose, $help, $ver);
        GetOptions("V" => \$verbose, 'h|help' => \$help, 'v|version' => \$ver);
        if ($help) {
            my $usage_string = xCAT::Usage->getUsage($command);
            my $rsp;
            push @{ $rsp->{data} }, $usage_string;
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return ();
        }
        if ($ver) {
            my $ver_string = xCAT::Usage->getVersion($command);
            my $rsp;
            push @{ $rsp->{data} }, $ver_string;
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return ();
        }

        if ($verbose) {
            $::VERBOSE = 1;
        }
    }

    return [$request];
}

sub process_request {
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;

    my $nodes   = $request->{node};
    my $command = $request->{command}->[0];
    my $args    = $request->{arg};

    if ($::XCATSITEVALS{xcatdebugmode} != 0) { $::VERBOSE = 1}

    if ($command eq "copydata") {
        copydata($request, $callback);
    } elsif ($command eq "nodeset") {
        nodeset($request, $callback, $subreq);
    }

}

# build cumulus OS image 
sub copydata {
    my $request  = shift;
    my $callback = shift;
    my $file;
    my $inspection   = undef;
    my $noosimage    = undef;
    my $nooverwrite = undef;
    
    # get arguments
    my $args = $request->{arg};
    if ($args) {
        @ARGV = @{$args};
        GetOptions(
            'w'   => \$nooverwrite,
            'o'   => \$noosimage,
            'i'   => \$inspection,
            'f=s' => \$file
        );
    }

    if (!(-x $file)) {
        xCAT::MsgUtils->message("E", { error => ["$file is not executable, will not process"], errorcode => ["1"] }, $callback);
        return;
    }

    #get install dir
    my $installroot = "/install";
    my $sitetab     = xCAT::Table->new('site');
    my @ents     = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if (defined($site_ent))
    {
        $installroot = $site_ent;
    }

    my $arch;
    my $desc;
    my $release;
    my $osname;
    my $filename = basename($file);
    my $output = `$file`;
    if ($inspection) {
        $callback->({ data => "file output: $output" });
        return;
    }
    foreach my $line (split /[\r\n]+/, $output) {
        if ($line =~ /^Architecture/) {
            ($desc, $arch) = split /: /, $line ;
            chomp $arch;
        }
        if ($line =~ /^Release/) {
            ($desc, $release) = split /: /, $line ;
            chomp $release;
        }
        if ($line =~ /cumulus/) {
            $osname = "cumulus" ;
        }
    }
    unless ($osname) {
        $osname="image";
    }

    my $distname = $osname . $release;
    my $imagename = $distname . "-" . $arch;
    my $defaultpath = "$installroot/$distname/$arch";

    #check if file exists
    if ( (-e "$defaultpath/$filename") && ($nooverwrite)){
        $callback->({ data => "$defaultpath/$filename is already exists, will not overwrite" });
    } else {
        $callback->({ data => "Copying media to $defaultpath" });
        mkpath ("$defaultpath");
        system("cp $file $defaultpath");
        $callback->({ data => "Media copy operation successful" });
    }

    if ($noosimage) {
        $callback->({ data => "Option noosimage is specified, will not create osimage definition" });
        return;
    }

    # generate the image objects
    my $oitab = xCAT::Table->new('osimage');
    unless ($oitab) {
        xCAT::MsgUtils->message("E", { error => ["Error: Cannot open table osimage."], errorcode => ["1"] }, $callback);
        return 1;
    }
    my $litab = xCAT::Table->new('linuximage');
    unless ($litab) {
        xCAT::MsgUtils->message("E", { error => ["Error: Cannot open table linuximage."], errorcode => ["1"] }, $callback);
        return 1;
    }
    my $pkgdir = "$defaultpath/$filename";
    my $imgdir = $litab->getAttribs({ 'imagename' => $imagename }, 'pkgdir');

    if ($::VERBOSE) {
        $callback->({ data => "creating image $imagename with osarch=$arch, osvers=$distname" });
    }

    my %values;
    $values{'imagetype'}   = "linux";
    $values{'provmethod'}  = "install";
    $values{'description'} = "Cumulus Linux";
    $values{'osname'}      = "$osname";
    $values{'osvers'}      = "$distname";
    $values{'osarch'}      = "$arch";

    $oitab->setAttribs({ 'imagename' => $imagename }, \%values);

    # set a default package list
    $litab->setAttribs({ 'imagename' => $imagename }, { 'pkgdir' => $pkgdir });
    if ($::VERBOSE) {
        $callback->({ data => "setting pkgdir=$pkgdir for image $imagename" });
    }

    #Need to update osdistro table?
    my @ret = xCAT::SvrUtils->update_osdistro_table($distname, $arch, $defaultpath, $imagename);
    if ($ret[0] != 0) {
        xCAT::MsgUtils->message("E", { error => ["Error when updating the osdistro tables."], errorcode => ["1"] }, $callback);
    }

    xCAT::MsgUtils->message("I", { data => ["The image $imagename is created."] }, $callback);
}


# run the nodeset to updatenode provmethod 
sub nodeset {
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;

    my $switches = $request->{'node'};
    my $args  = $request->{arg};
    my $provmethod; 
    my $image_pkgdir;

    my $setosimg;
    foreach (@$args) {
        if (/osimage=(.*)/) {
            $setosimg = $1;
        }
    }

    my $switchestab = xCAT::Table->new('switches');
    my $switcheshash = $switchestab->getNodesAttribs($switches, ['switchtype']);

    my $nodetab  = xCAT::Table->new('nodetype');
    my $nodehash = $nodetab->getNodesAttribs($switches, [ 'provmethod' ]);

    foreach my $switch (@$switches) {
        if ($switcheshash->{$switch}->[0]->{switchtype} ne "onie") {
            xCAT::MsgUtils->message("E", { error => ["nodeset command is not processed for $switch, only supports switchtype=onie"], errorcode => ["1"] }, $callback);
            next;
        }


        if ($setosimg) {
            $provmethod = $setosimg;
        } else {
            $provmethod = $nodehash->{$switch}->[0]->{provmethod}; 
        }
        if ($::VERBOSE) {
            xCAT::MsgUtils->message("I", { data => ["$switch has provmethod=$provmethod"] }, $callback);
        }

        #get pkgdir from osimage
        my $linuximagetab = xCAT::Table->new('linuximage');
        my $osimagetab = xCAT::Table->new('osimage');
        my $imagetab = $linuximagetab->getAttribs({ imagename => $provmethod },'pkgdir');
        my $osimghash = $osimagetab->getAttribs({ imagename => $provmethod },'osvers','osarch');
        unless($imagetab and $osimghash){
            xCAT::MsgUtils->message("E", { error => ["cannot find osimage \"$provmethod\" for $switch, please make sure the osimage specified in command line or node.provmethod exists!"], errorcode => ["1"] }, $callback);
            next;            
        }


        my %attribs=('provmethod' => $provmethod,'os'=>$osimghash->{'osvers'},'arch'=>$osimghash->{'osarch'} );
        $nodetab->setAttribs({ 'node' => $switch }, \%attribs);
        $image_pkgdir = $imagetab->{'pkgdir'};
       
        #validate the image pkgdir 
        my $flag=0;
        if (-r $image_pkgdir) {
            my @filestat = `file $image_pkgdir`;
            if (grep /$image_pkgdir: data/, @filestat) {
                $flag=1;
            }
        }
        unless ($flag) {
            xCAT::MsgUtils->message("E", { error => ["The image '$image_pkgdir' is invalid"], errorcode => ["1"] }, $callback);
            next;
        }
        if ($::VERBOSE) {
            xCAT::MsgUtils->message("I", { data => ["osimage=$provmethod, pkgdir=$image_pkgdir"] }, $callback);
        }

        #updateing DHCP entries
        my $ret = xCAT::Utils->runxcmd({ command => ["makedhcp"], node => [$switch] }, $subreq, 0, 1);
        if ($::RUNCMD_RC) {
            xCAT::MsgUtils->message("E", { error => ["Failed to run 'makedhcp' command"], errorcode => ["$::RUNCMD_RC"] }, $callback);
        }

        xCAT::MsgUtils->message("I", { data => ["$switch: install $provmethod"] }, $callback);
    }
    return;
}
1;
