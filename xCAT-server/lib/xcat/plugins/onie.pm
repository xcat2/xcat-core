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
use Expect;
use File::Path;
use File::Basename;
use File::Copy "cp";

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
        rspconfig => 'switches:switchtype',
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
    my @exargs    = ($request->{arg});
    if (ref($args)) {
        @exargs = @$args;
    }


    if ($::XCATSITEVALS{xcatdebugmode} != 0) { $::VERBOSE = 1}

    if ($command eq "copydata") {
        copydata($request, $callback);
    } elsif ($command eq "nodeset") {
        nodeset($request, $callback, $subreq);
    } elsif ($command eq "rspconfig") {
        my $subcmd = $exargs[0];
        if ($subcmd eq 'sshcfg') {
            process_sshcfg($nodes, $callback);
        } else {
            xCAT::MsgUtils->message("I", { data => ["The rspconfig command $subcmd is not supported"] }, $callback);
        }
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
        chmod 0755, "$defaultpath/$filename";
        $callback->({ data => "$defaultpath/$filename is already exists, will not overwrite" });
    } else {
        $callback->({ data => "Copying media to $defaultpath" });
        mkpath ("$defaultpath");
        cp "$file", "$defaultpath";
        chmod 0755, "$defaultpath/$filename"; 	
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
            if (!defined($::DISABLENODESETWARNING)) { # set by AAsn.pm
                xCAT::MsgUtils->message("I", { data => [ "$switch has provmethod=$provmethod" ] }, $callback);
            }
        }

        #get pkgdir from osimage
        my $linuximagetab = xCAT::Table->new('linuximage');
        my $osimagetab = xCAT::Table->new('osimage');
        my $imagetab = $linuximagetab->getAttribs({ imagename => $provmethod },'pkgdir');
        my $osimghash = $osimagetab->getAttribs({ imagename => $provmethod },'osvers','osarch');
        unless($imagetab and $osimghash){
            if (!defined($::DISABLENODESETWARNING)) {    # set by AAsn.pm
                xCAT::MsgUtils->message("E", { error => ["cannot find osimage \"$provmethod\" for $switch, please make sure the osimage specified in command line or node.provmethod exists!"], errorcode => ["1"] }, $callback);
            }
            next;
        }


        my %attribs=('provmethod' => $provmethod,'os'=>$osimghash->{'osvers'},'arch'=>$osimghash->{'osarch'} );
        $nodetab->setAttribs({ 'node' => $switch }, \%attribs);
        $image_pkgdir = $imagetab->{'pkgdir'};

        #validate the image pkgdir
        my $flag=0;
        if (-r $image_pkgdir) {
            my @filestat = `file $image_pkgdir`;
            if ((grep /$image_pkgdir: data/, @filestat) || (grep /$image_pkgdir: .* \(binary data/, @filestat)) {
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


sub process_sshcfg {
    my $noderange = shift;
    my $callback = shift;

    my $password = "CumulusLinux!";
    my $userid = "cumulus";
    my $timeout = 30;
    my $keyfile = "/root/.ssh/id_rsa.pub";
    my $rootkey = `cat /root/.ssh/id_rsa.pub`;

    foreach my $switch (@$noderange) {
        my $ip = xCAT::NetworkUtils->getipaddr($switch);

        #remove old host key from /root/.ssh/known_hosts
        my $cmd = "ssh-keygen -R $switch";
        xCAT::Utils->runcmd($cmd, 0);
        $cmd = "ssh-keygen -R $ip";
        xCAT::Utils->runcmd($cmd, 0);

        my ($exp, $errstr) = cumulus_connect($ip, $userid, $password, $timeout);
        if (!defined $exp) {
            xCAT::MsgUtils->message("E", { data => ["Failed to connect to $switch"] }, $callback);
            next;
        }

        my $ret;
        my $err;

        ($ret, $err) = cumulus_exec($exp, "mkdir -p /root/.ssh");
        ($ret, $err) = cumulus_exec($exp, "chmod 700 /root/.ssh");
        ($ret, $err) = cumulus_exec($exp, "echo \"$rootkey\" >/root/.ssh/authorized_keys");
        ($ret, $err) = cumulus_exec($exp, "chmod 644 /root/.ssh/authorized_keys");
        if (!defined $ret) {
            xCAT::MsgUtils->message("E", { data => ["Failed to run command on $switch"] }, $callback);
            next;
        }
        xCAT::MsgUtils->message("I", { data => ["$switch: SSH enabled"] }, $callback);
    }
}

sub cumulus_connect {
     my $server   = shift;
     my $userid   = shift;
     my $password = shift;
     my $timeout  = shift;

     my $ssh      = Expect->new;
     my $command     = 'ssh';
     my @parameters  = ($userid . "@" . $server);

     $ssh->debug(0);
     $ssh->log_stdout(0);    # suppress stdout output..

     unless ($ssh->spawn($command, @parameters))
     {
         my $err = $!;
         $ssh->soft_close();
         my $rsp;
         return(undef, "unable to run command $command $err\n");
     }

     $ssh->expect($timeout,
                   [ "-re", qr/WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED/, sub {die "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\n"; } ],
                   [ "-re", qr/\(yes\/no\)\?\s*$/, sub { $ssh->send("yes\n");  exp_continue; } ],
                   [ "-re", qr/ password:/,        sub {$ssh->send("$password\n"); exp_continue; } ],
                   [ "-re", qr/:~\$/,              sub { $ssh->send("sudo su\n"); exp_continue; } ],
                   [ "-re", qr/ password for cumulus:/, sub { $ssh->send("$password\n"); exp_continue; } ],
                   [ "-re", qr/.*\/home\/cumulus#/, sub { $ssh->clear_accum(); } ],
                   [ timeout => sub { die "No login.\n"; } ]
                  );
     $ssh->clear_accum();
     return ($ssh);
}

sub cumulus_exec {
     my $exp = shift;
     my $cmd = shift;
     my $timeout    = shift;
     my $prompt =  shift;

     $timeout = 10 unless defined $timeout;
     $prompt = qr/.*\/home\/cumulus#/ unless defined $prompt;


     $exp->clear_accum();
     $exp->send("$cmd\n");
     my ($mpos, $merr, $mstr, $mbmatch, $mamatch) = $exp->expect(6,  "-re", $prompt);

     if (defined $merr) {
         return(undef,$merr);
     }
     return($mbmatch);
}



1;
