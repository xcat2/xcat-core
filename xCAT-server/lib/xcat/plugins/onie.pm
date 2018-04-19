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

    my $filename = basename($file);

    #xCAT::MsgUtils->message("I", { data => ["running copycd for onie image: $file"] }, $callback);
    my $release = `$file | grep 'Release' | cut -d' ' -f2`;
    chomp $release;
    #xCAT::MsgUtils->message("I", { data => ["running copycd for onie image: $release"] }, $callback);
    my $arch = `$file | grep '^Architecture' | cut -d' ' -f2 `;
    chomp $arch;
    #xCAT::MsgUtils->message("I", { data => ["running copycd for onie image: $arch"] }, $callback);
    my $imagename = $osname . "-" . $release . "-" . $arch;
    #xCAT::MsgUtils->message("I", { data => ["running copycd for onie image: $imagename"] }, $callback);
    my $distname = $osname . $release;
    my $defaultpath = "$installroot/$distname/$imagename";
    #xCAT::MsgUtils->message("I", { data => ["running copycd for onie image: $distname, $defaultpath"] }, $callback);

    $callback->({ data => "Copying media to $defaultpath" });
    mkpath ("$defaultpath");
    system("cp $file $defaultpath");

    # generate the image objects
    my $oitab = xCAT::Table->new('osimage');
    unless ($oitab) {
        xCAT::MsgUtils->message("E", { error => ["Error: Cannot open table osimage."], errorcode => ["1"] }, $callback);
        return 1;
    }

    my %values;
    $values{'imagetype'}   = "linux";
    $values{'provmethod'} = "onie";
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

    my $pkgdir = "$defaultpath/$filename";
    $litab->setAttribs({ 'imagename' => $imagename }, { 'pkgdir' => $pkgdir });

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
