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
use xCAT::Table;

my $xcatdebugmode = 0;
$::VERBOSE        = 0;

sub handled_commands {
    return {
        nodeset => "nodehm:mgt",    
        copycd => 'onie',
      }
}

my $CALLBACK;                       # used to hanel the output from xdsh

sub preprocess_request {
    my $request  = shift;
    my $callback = shift;

    if ($request->{command}->[0] eq 'copycd')
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

    my %hosts;

    if ($::XCATSITEVALS{xcatdebugmode} != 0) { $::VERBOSE = 1}

    if ($command eq "copycd") {
        copycd($request, $callback);
    } elsif ($command eq "nodeset") {
        nodeset($request, $callback, $subreq, \%hosts);
    }

}

# build cumulus OS image 
sub copycd {
    my $request  = shift;
    my $callback = shift;
    
    #get install dir
    my $installroot = "/install";
    my $sitetab     = xCAT::Table->new('site');
    my @ents     = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if (defined($site_ent))
    {
        $installroot = $site_ent;
    }


    my $args = $request->{arg};
    my ($osname, $file);
    if ($args) {
        @ARGV = @{$args};
        GetOptions('n=s' => \$osname,
            'f=s' => \$file);
    }

    if ($osname !~ /^cumulus/) {
        return;
    }

    if (!(-x $file)) {
        xCAT::MsgUtils->message("E", { error => ["$file is not executable, will not process"], errorcode => ["1"] }, $callback);
        return;
    }

    my $filename = basename($file);

    my $arch = `$file | grep '^Architecture' | cut -d' ' -f2 `;
    chomp $arch;
    if ($arch !~ /armel/){
        xCAT::MsgUtils->message("E", { error => ["$arch is not support, only support armel Architecture for now"], errorcode => ["1"] }, $callback);
        return;
    }

    my $release = `$file | grep 'Release' | cut -d' ' -f2`;
    chomp $release;
    my $imagename = $osname . "-" . $release . "-" . $arch;
    my $distname = $osname . $release;
    my $defaultpath = "$installroot/$distname/$imagename";

    #check if file exists
    if (-e "$defaultpath/$filename") {
        $callback->({ data => "$defaultpath/$filename is already exists." });
    } else {
        $callback->({ data => "Copying media to $defaultpath" });
        mkpath ("$defaultpath");
        system("cp $file $defaultpath");
        $callback->({ data => "Media copy operation successful" });
    }

    # generate the image objects
    my $oitab = xCAT::Table->new('osimage');
    unless ($oitab) {
        xCAT::MsgUtils->message("E", { error => ["Error: Cannot open table osimage."], errorcode => ["1"] }, $callback);
        return 1;
    }
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

    my $litab = xCAT::Table->new('linuximage');
    unless ($litab) {
        xCAT::MsgUtils->message("E", { error => ["Error: Cannot open table linuximage."], errorcode => ["1"] }, $callback);
        return 1;
    }

    # set a default package list
    my $pkgdir = "$defaultpath/$filename";
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

    xCAT::MsgUtils->message("E", { error => ["DIDN't support nodeset yet"], errorcode => ["1"] }, $callback);
    return;

    my $usage_string = "nodeset noderange osimage[=imagename]";

    my $nodes = $request->{'node'};
    my $args  = $request->{arg};
    my $setosimg;
    foreach (@$args) {
        if (/osimage=(.*)/) {
            $setosimg = $1;
        }
    }

    # get the provision method for all the nodes
    my $nttab = xCAT::Table->new("nodetype");
    unless ($nttab) {
        xCAT::MsgUtils->message("E", { error => ["Cannot open the nodetype table."], errorcode => ["1"] }, $callback);
        return;
    }

    # if the osimage=xxx has been specified, then set it to the provmethod attr .
    if ($setosimg) {
        my %setpmethod;
        foreach (@$nodes) {
            $setpmethod{$_}{'provmethod'} = $setosimg;
        }
        $nttab->setNodesAttribs(\%setpmethod);
    }

}
1;
