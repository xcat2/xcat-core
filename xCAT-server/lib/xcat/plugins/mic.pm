#!/usr/bin/env perl
## IBM(c) 20013 EPL license http://www.eclipse.org/legal/epl-v10.html
#
# This plugin is used to handle the command requests for Xeon Phi (mic) support
#

package xCAT_plugin::mic;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

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
        rpower => 'nodehm:mgt',
        nodeset => "nodehm:mgt", # generate the osimage for mic on the host
        rflash => 'nodehm:mgt',     # update the firmware of mics
        rinv => 'nodehm:mgt',
        rvitals => 'nodehm:mgt',
        copytar => 'mic',
        getcons => 'nodehm:mgt',        
    }
}

my $CALLBACK;  # used to hanel the output from xdsh

# since the mic is attached to the host node and management of mic needs to be 
# done via host node, the host will be used as the target to get the service node
sub preprocess_request { 
    my $request = shift;
    my $callback = shift;
   
    if ($request->{command}->[0] eq 'copytar')
    {
        # don't handle copytar (copycds)
        return [$request];
    } 
    # if already preprocessed, go straight to request
    if ((defined($request->{_xcatpreprocessed}->[0]))
        && ($request->{_xcatpreprocessed}->[0] == 1)) {
        return [$request];
    }

    my $nodes = $request->{node};
    my $command = $request->{command}->[0];
    my $extraargs = $request->{arg};

    if ($extraargs) {
        @ARGV=@{$extraargs};
        my ($verbose, $help, $ver);
        GetOptions("V" => \$verbose, 'h|help' => \$help, 'v|version' => \$ver); 
        if ($help) {
            my $usage_string = xCAT::Usage->getUsage($command);
            my $rsp;
            push @{$rsp->{data}}, $usage_string;
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return ();
        }
        if ($ver) {
            my $ver_string = xCAT::Usage->getVersion($command);
            my $rsp;
            push @{$rsp->{data}}, $ver_string;
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return ();
        }
    }

    # Get the host for the mic nodes
    my %hosts;
    my $mictab = xCAT::Table->new("mic");
    unless ($mictab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the mic table."], errorcode=>["1"]}, $callback);
        return;
    }
    my $mictabhash = $mictab->getNodesAttribs($nodes,['host']);
    foreach my $node (@$nodes) {
        if (!defined ($mictabhash->{$node}->[0]->{'host'})) {
            xCAT::MsgUtils->message("E", {error=>["The michost attribute was not set for $node"], errorcode=>["1"]}, $callback);
            return;
        }
        push @{$hosts{$mictabhash->{$node}->[0]->{'host'}}}, $node;
    }

    my @requests;
    # get the service nodes of hosts instread of mic nodes
    my @hosts=keys(%hosts);
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@hosts, 'xcat', "MN");
    foreach my $snkey (keys %$sn){
        my $reqcopy = {%$request};
        my @nodes4sn;
        foreach (@{$sn->{$snkey}}) {
            push @nodes4sn, @{$hosts{$_}};
        }
        $reqcopy->{node} = \@nodes4sn;   # the node attribute will have the real mic nodes
        unless ($snkey eq '!xcatlocal!') {
            $reqcopy->{'_xcatdest'} = $snkey;
        }
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        push @requests, $reqcopy;
    }
    return \@requests;
}

sub process_request {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $nodes = $request->{node};
    my $command = $request->{command}->[0];
    my $args = $request->{arg};

    # get the mapping between host and mic
    my %hosts;
    my $mictab = xCAT::Table->new("mic");
    unless ($mictab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the mic table."], errorcode=>["1"]}, $callback);
        return;
    }
    my $mictabhash = $mictab->getNodesAttribs($nodes,['host', 'id']);
    foreach my $node (@$nodes) {
        $hosts{$mictabhash->{$node}->[0]->{'host'}}{$mictabhash->{$node}->[0]->{'id'}} = $node;    # $hosts{host}{micid} = micname
        $hosts{$mictabhash->{$node}->[0]->{'host'}}{'ids'} .= " $mictabhash->{$node}->[0]->{'id'}";  # $hosts{host}{ids} = " id0 id1 id2 ..."
    }

    if ($command eq "rvitals"){
        rinv($request, $callback, $subreq, \%hosts);
    } elsif ($command eq "rmicctrl") {
        rmicctrl($callback, $args);
    } elsif ($command eq "rinv") {
        rinv($request, $callback, $subreq, \%hosts);
    } elsif ($command eq "rpower") {
        rpower($request, $callback, $subreq, \%hosts);
    } elsif ($command eq "copytar") {
        copytar($request, $callback);
    } elsif ($command eq "getcons") {
        getcons($request, $callback);
    } elsif ($command eq "rflash") {
        rflash($request, $callback, $subreq, \%hosts);
    } elsif ($command eq "nodeset") {
        nodeset($request, $callback, $subreq, \%hosts);
    }

}

# handle the rpower command for the mic node
sub rpower {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;
    my $host2mic = shift;

    my $usage_string = "rpower noderange [stat|state|on|off|reset|boot]";

    my $args = $request->{arg};
    my ($wait, $timeout, $action);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('w' => \$wait,
                   't=s' => \$timeout);
        foreach (@ARGV) {
            if (/^stat/) {
                $action = "--status";
            } elsif (/^on$/) {
                $action = "--boot";
            } elsif (/^off$/) {
                $action = "--shutdown";
            } elsif (/^reset$/) {
                $action = "--reset";
            } elsif (/^boot$/) {
                $action = "--reboot";
            } else {
                my $rsp;
                push @{$rsp->{data}}, $usage_string;
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return;
            }
        }
    } else {
        my $rsp;
        push @{$rsp->{data}}, $usage_string;
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }

    # get all the hosts
    # use the id list as the key to classify the host, since the handle the host against
    # same mic list will be run in a batch
    my %hostclass;  
    foreach (keys %$host2mic) {
        push @{$hostclass{$host2mic->{$_}{'ids'}}}, $_;
    }

    foreach (keys %hostclass) {
        my $idlist = $_;
        my @hosts = @{$hostclass{$idlist}};
        my $miclist = $idlist;  # currently ,it's " 0 1 2 .."
        $miclist =~ s/(\d+)/mic$1/g;  # then, it should be "mic0 mic1 mic2 ..."

        my @cmd = ("/usr/sbin/micctrl", $action, $miclist);
        if ($wait) {
            if ($timeout) {
                push @cmd, (" --wait", "--timeout=$timeout");
            } else {
                push @cmd, " --wait";
            }
        }
    
        my $output = xCAT::Utils->runxcmd({ command => ['xdsh'],
                                           node => \@hosts,
                                           arg => \@cmd }, $subreq, 0, 1);
    
        # parse the output
        # replace the mic name from the host like mic0:xxx, mic1:xxx to the real mic name
        # which defined in xCAT
        foreach (@$output) {
            foreach my $line (split /\n/, $_) {
                if ($line =~ /([^:]*):\s*([^:]*):(.*)/) {
                    my $host = $1;
                    my $mic = $2;
                    my $msg = $3;
                    chomp ($host);
                    chomp ($mic);
                    chomp ($msg);
                    if ($mic =~ /^mic\d+/) {
                        my $micid = $mic;
                        $micid =~ s/[^\d]*//g;
                        my $micname = $host2mic->{$host}{$micid};
                        xCAT::MsgUtils->message("I", {data=>["$micname: $msg"]}, $callback);
                    } else {
                        xCAT::MsgUtils->message("E", {data=>[$line]}, $callback);
                    }
                }
            }
        }
    } # end of foreach host class with same mic list
}

# display the inventory information for mic
# this subroutine will handle the both rinv and rvitals commands
sub rinv {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;
    my $host2mic = shift;

    my $command = $request->{command}->[0];
    my $usage_string;
    my %validargs;

    # set the valid argurments and correspoding groups which can be recognized by 
    # micinfo command
    if ($command eq "rinv") {
        $usage_string = "rinv noderange {system|ver|board|core|gddr|all}";
        %validargs = ("system" => "System", "ver" => "Version", "board" => "Board", 
                      "core" => "Core", "gddr" => "GDDR", "all" => "all");
    } elsif ($command eq "rvitals") {
        $usage_string = "rvitals noderange {thermal|all}";
        %validargs = ("thermal" => "Thermal", "all" => "all");
    }

    my @args;
    if (defined ($request->{arg})) {
        @args = @{$request->{arg}};
        unless (@args) {
            push @args, "all";
        }
    } else {
        push @args, "all";
    }
    my @groups; # the groups name which could be displayed by micinfo 
    foreach my $arg (@args) {
        if ($validargs{$arg}) {
            if ($arg eq "all") {
                if ($command eq "rinv") {
                    push @groups, ("System", "Version", "Board", "Core", "GDDR");
                } elsif ($command eq "rvitals") {
                    push @groups, ("Thermal");
                }
            } else {
                push @groups, $validargs{$arg};
            }
        } else {
            my $rsp;
            push @{$rsp->{data}}, $usage_string;
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }
    }

    my %groupflag;
    foreach (@groups) {
        $groupflag{$_} = 1;
    }

    # run micinfo on the host to get all the mic information first
    my @hosts = (keys  %$host2mic);
    my $output = xCAT::Utils->runxcmd({ command => ['xdsh'],
                                           node => \@hosts,
                                           arg => ["/opt/intel/mic/bin/micinfo"]}, $subreq, 0, 1);

    # classify all the output with the host name
    my %outofhost;
    foreach (@$output) {
        if (/\@\@\@/) { next; } # remove the part of ssh connection warning
        foreach my $line (split /\n/, $_) {
            $line =~ s/(\s)+/ /g;
            if ($line =~ /([^:]*):(.*)/) {
                push @{$outofhost{$1}}, $2;
            }
        }
    }

    foreach my $host (keys %outofhost) {
        my $micid;
        my $micname; # which is the node name of the mic
        my $curgroup;
        my @sysinfo;
        my $rsp;
        foreach (@{$outofhost{$host}}) {
            if (/^\s*Device No:\s*(\d+)/) {
                # get the mic name
                $micid = $1;
                $micname = $host2mic->{$host}->{$micid};

                # display the System infor first
                foreach (@sysinfo) {
                    if ($groupflag{'System'} == 1 && $micname) {
                        push @{$rsp->{data}}, "$micname: $_";
                    }
                }
            } elsif (/^\s*System Info$/) {
                $curgroup = "System";
            } elsif (/^\s*Version$/) {
                $curgroup = "Version";
            } elsif (/^\s*Board$/) {
                $curgroup = "Board";
            } elsif (/^\s*Cores$/) {
                $curgroup = "Core";
            } elsif (/^\s*Thermal$/) {
                $curgroup = "Thermal";
            }  elsif (/^\s*GDDR$/) {
                $curgroup = "GDDR";
            } else {
                my $msg = $_;
                if ($msg =~ /^\s*$/) { next;}
                $msg =~ s/^\s*//;
                if ($curgroup eq "System") {
                    push @sysinfo, $msg;
                } elsif ($groupflag{$curgroup} == 1 && $micname) {
                    push @{$rsp->{data}}, "$micname: $msg";
                }
            }
        }
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
}

# do the copy of metarials (root file system, flash image, kernel) for mic support from mpss tar 
sub copytar {
    my $request = shift;
    my $callback = shift;

    my $args = $request->{arg};
    my ($osname, $file);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('n=s' => \$osname,
                   'f=s' => \$file);
    }

    my $installroot = "/install";
    my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
    my $t_entry = $entries[0];
    if ( defined($t_entry) ) {
        $installroot = $t_entry;
    }
    
    my $tmpdir = "/tmp/mictmp";
    my $destdir = "$installroot/$osname";
    rmtree ($tmpdir);
    mkpath ($tmpdir);
    mkpath ($destdir);

    # extract the files from the mpss tar file
    my $cmd = "tar xvf $file -C $tmpdir";
    my @output = xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0) {
        xCAT::MsgUtils->message("E", {error=>["Error when run [$cmd], @output"], errorcode=>["1"]}, $callback);
        return 1;
    }

    # get the rpm packages intel-mic-gpl and intel-mic-flash which include the files for root file system, flash ...
    my @micgpl = <$tmpdir/*/intel-mic-gpl*>;
    my @micflash = <$tmpdir/*/intel-mic-flash*>;
    unless (-r $micgpl[0] && -r $micflash[0]) {
        xCAT::MsgUtils->message("E", {error=>["Error: Cannot get the rpm files intel-mic-gpl or intel-mic-flash from the tar file."], errorcode=>["1"]}, $callback);
        return 1;
    }

    # extract the files from rpm packages
    $cmd = "cd $destdir; rpm2cpio $micgpl[0] | cpio -idum; rpm2cpio $micflash[0] | cpio -idum";
    @output = xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0) {
        xCAT::MsgUtils->message("E", {error=>["Error when run [$cmd], @output"], errorcode=>["1"]}, $callback);
        return 1;
    }

    # generate the image objects
    my $oitab = xCAT::Table->new('osimage');
    unless ($oitab) {
        xCAT::MsgUtils->message("E", {error=>["Error: Cannot open table osimage."], errorcode=>["1"]}, $callback);
        return 1;
    }

    my %values;
    $values{'imagetype'} = "linux";
    $values{'provmethod'} = "netboot";
    $values{'rootfstype'} = "ramdisk";
    $values{'description'} = "Linux for Intel mic";
    $values{'osname'} = "Linux";
    $values{'osvers'} = "mic";
    $values{'osarch'} = "x86_64";
    $values{'profile'} = "compute";

    my $imagename = "$osname-netboot-compute";
    $oitab->setAttribs({'imagename' => $imagename}, \%values);

    my $litab = xCAT::Table->new('linuximage');
    unless ($litab) {
        xCAT::MsgUtils->message("E", {error=>["Error: Cannot open table linuximage."], errorcode=>["1"]}, $callback);
        return 1;
    }
    
    # set a default package list
    my $pkglist = "$::XCATROOT/share/xcat/netboot/mic/compute.pkglist";
    $litab->setAttribs({'imagename' => $imagename}, {'pkgdir' => $destdir, 'pkglist' => $pkglist});

    xCAT::MsgUtils->message("I", {data=>["The image $imagename has been created."]}, $callback);
    rmtree ($tmpdir);
}

# get the console configuration for rcons: 
# see /opt/xcat/share/xcat/cons/mic
sub getcons {
    my $request = shift;
    my $callback = shift;

    my $node = $request->{node}->[0];
    my $mictab = xCAT::Table->new("mic");
    unless ($mictab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the mic table."], errorcode=>["1"]}, $callback);
        return;
    }

    # get the console parameters
    my $sconsparms = {node=>[{name=>[$node]}]};
    my $mictabhash = $mictab->getNodeAttribs($node,['host', 'id']);
    if (defined ($mictabhash->{'host'})) {
        $sconsparms->{node}->[0]->{sshhost} = [$mictabhash->{'host'}];
    }
    if (defined ($mictabhash->{'id'})) {
        $sconsparms->{node}->[0]->{psuedotty} = ["/dev/ttyMIC".$mictabhash->{'id'}];
    }
    $sconsparms->{node}->[0]->{baudrate}=["115200"];

    $callback->($sconsparms);
}

# do the flash of firmware for mic
sub rflash {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;
    my $host2mic = shift;

    my $usage_string = "rflash noderange";

    my $nodes = $request->{'node'};
    
    # get the provision method for all the nodes
    my $nttab = xCAT::Table->new("nodetype");
    unless ($nttab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the nodetype table."], errorcode=>["1"]}, $callback);
        return;
    }
    
    my $nthash = $nttab->getNodesAttribs($nodes,['provmethod']);
    foreach my $node (@$nodes) {
        unless (defined ($nthash->{$node}->[0]->{'provmethod'})) {
            xCAT::MsgUtils->message("E", {error=>["The provmethod for the node $node should be set before the rflash."], errorcode=>["1"]}, $callback);
            return;
        }
    }

    # get pkgdir for the osimage
    my $litab = xCAT::Table->new("linuximage");
    unless ($litab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the linuximage table."], errorcode=>["1"]}, $callback);
        return;
    }
    my @osimages = $litab->getAllAttribs("imagename", "pkgdir");
    my %osimage;
    foreach (@osimages) {
        $osimage{$_->{'imagename'}} = $_->{'pkgdir'};
    }

    # get the tftp dir and create the path for the mic configuration files
    my $tftpdir = "/tftpboot";
    my @entries =  xCAT::TableUtils->get_site_attribute("$tftpdir");
    my $t_entry = $entries[0];
    if ( defined($t_entry) ) {
        $tftpdir = $t_entry;
    }
    mkpath ("$tftpdir/xcat/miccfg/");

    # generate the rflash configuration files for each host
    # the configureation file should have the following format
    #miclist=mic0
    #0:name=host1-mic0
    #imgpath=/install/mpss3.new
    my @hosts = (keys %$host2mic);
    foreach my $host (@hosts) {
        my @cfgfile;
        push @cfgfile, "#XCAT MIC FLASH CONFIGURATION FILE#";
        my $miclist = $host2mic->{$host}{'ids'};
        my @micids = split (/ /, $miclist);
        $miclist =~ s/(\d+)/mic$1/g;
        $miclist =~ s/ /,/g;
        $miclist =~ s/^,//;
        
        push @cfgfile, "miclist=$miclist";

        my $osimg;
        foreach my $micid (@micids) {
            if ($micid eq '') { next;}
            my $micname = $host2mic->{$host}{$micid};
            # get the pkgdir of the osimage which set to the mic node.
            # and make sure the osimage which set to the mic shold be same for all the mics on one host
            if ($osimg) {
                if ($osimg ne $nthash->{$micname}->[0]->{'provmethod'}) {
                    xCAT::MsgUtils->message("E", {error=>["The provmethod for the nodes in the same host should be same."], errorcode=>["1"]}, $callback);
                    return;
                }
            } else {
                $osimg = $nthash->{$micname}->[0]->{'provmethod'};
            }
            push @cfgfile, "$micid:name=$micname";
        }
        push @cfgfile, "imgpath=$osimage{$osimg}";
        
        if (open (CFG, ">$tftpdir/xcat/miccfg/micflash.$host")) {
            foreach (@cfgfile) {
                print CFG $_."\n";
            }
            close (CFG);
        } else {
            xCAT::MsgUtils->message("E", {error=>["Cannot open the file $tftpdir/xcat/miccfg/micflash.$host to write."], errorcode=>["1"]}, $callback);
            return;
        }
    }

    # run the cmd on the host to flash the mic
    my @args = ("-s", "-v", "-e");
    push @args, "$::XCATROOT/sbin/flashmic";
    my $master = $request->{'_xcatdest'};
    push @args, ("-m", "$master");
    push @args, ("-p", "$tftpdir/xcat/miccfg");

    $CALLBACK = $callback;
    $subreq->({ command => ['xdsh'],
                      node => \@hosts,
                      arg => \@args }, \&michost_cb);
}

# run the nodeset to genimage the osimage for each mic
# it gets on host first and mount the root file system from MN:/install/mpssxxx
# to host, and then configure and generate the mic specific osimage for each mic.
#
# If running 'odeset noderange osimage=imagename', the imagename will be used to generate
# image for mic and imagename will be set to the provmethod attr for the mic. If no 'osimage=xx' 
# is specified, the osimage will be get from provmethod attr.
sub nodeset {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;
    my $host2mic = shift;

    my $usage_string = "nodeset noderange osimage[=imagename]";

    my $nodes = $request->{'node'};
    my $args = $request->{arg};
    my $setosimg;
    foreach (@$args) {
        if (/osimage=(.*)/) {
            $setosimg = $1;
        }
    }
    
    # get the provision method for all the nodes
    my $nttab = xCAT::Table->new("nodetype");
    unless ($nttab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the nodetype table."], errorcode=>["1"]}, $callback);
        return;
    }

    # if the osimage=xxx has been specified, then set it to the provmethod attr for the mic.
    if ($setosimg) {
        my %setpmethod;
        foreach (@$nodes) {
            $setpmethod{$_}{'provmethod'} = $setosimg;
        }
        $nttab->setNodesAttribs(\%setpmethod);
    }

    # get the provision method from nodetype table
    my $nthash = $nttab->getNodesAttribs($nodes,['provmethod']);
    foreach my $node (@$nodes) {
        unless (defined ($nthash->{$node}->[0]->{'provmethod'})) {
            xCAT::MsgUtils->message("E", {error=>["The provmethod for the node $node must be set by [nodeset <node> osimage=<image name>] or set in the provmethod attribute of the node."], errorcode=>["1"]}, $callback);
            return;
        }
    }

    # get the virtual bridge, onboot, vlog information for the mic nodes
    my $mictab = xCAT::Table->new("mic");
    unless ($mictab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the mic table."], errorcode=>["1"]}, $callback);
        return;
    }
    my $michash = $mictab->getNodesAttribs($nodes, ['bridge', 'onboot', 'vlog']);

    # get ip for the mic nodes from hosts table
    my $hosttab = xCAT::Table->new("hosts");
    unless ($hosttab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the host table."], errorcode=>["1"]}, $callback);
        return;
    }
    my $hosthash = $hosttab->getNodesAttribs($nodes, ['ip']);

    # get pkgdir from the osimage
    my $litab = xCAT::Table->new("linuximage");
    unless ($litab) {
        xCAT::MsgUtils->message("E", {error=>["Cannot open the linuximage table."], errorcode=>["1"]}, $callback);
        return;
    }
    my @osimages = $litab->getAllAttribs("imagename", "pkgdir");
    my %osimage;
    foreach (@osimages) {
        $osimage{$_->{'imagename'}} = $_->{'pkgdir'};
    }

    # get the tftp dir and create the path for mic configuration
    my $tftpdir = "/tftpboot";
    my @entries =  xCAT::TableUtils->get_site_attribute("$tftpdir");
    my $t_entry = $entries[0];
    if ( defined($t_entry) ) {
        $tftpdir = $t_entry;
    }
    mkpath ("$tftpdir/xcat/miccfg/");

    # generate the configuration file for each host
    # the configureation file should have the following format
    #miclist=mic0
    #0:ip=10.10.10.1|br=mybr0|name=host1-mic0|onboot=yes|vlog=no
    #imgpath=/install/mpss3.1
    #overlay=ol1
    my %imghash; # cache of osimage information
    my @hosts = (keys %$host2mic);
    foreach my $host (@hosts) {
        my @cfgfile;
        push @cfgfile, "#XCAT MIC CONFIGURATION FILE#";
        my $miclist = $host2mic->{$host}{'ids'};
        my @micids = split (/ /, $miclist);
        $miclist =~ s/(\d+)/mic$1/g;
        $miclist =~ s/ /,/g;
        $miclist =~ s/^,//;
        
        push @cfgfile, "miclist=$miclist";

        my $osimg;
        foreach my $micid (@micids) {
            if ($micid eq '') { next;}
            my $micname = $host2mic->{$host}{$micid};
            # get the pkgdir of the osimage which set to the mic node,
            # and make sure the osimage which set to the mic shold be same for all the mics on one host
            if ($osimg) {
                if ($osimg ne $nthash->{$micname}->[0]->{'provmethod'}) {
                    xCAT::MsgUtils->message("E", {error=>["The provmethod for the nodes in the same host should be same."], errorcode=>["1"]}, $callback);
                    return;
                }
            } else {
                $osimg = $nthash->{$micname}->[0]->{'provmethod'};
            }

            # get the ip of the mic node
            # get the ip from system resolution first, if failed, get from host table
            my $micip = xCAT::NetworkUtils->getipaddr($micname);
            unless ($micip) {
                $micip = $hosthash->{$micname}->[0]->{'ip'};
                unless ($micip) {
                    xCAT::MsgUtils->message("E", {error=>["Cannot get the IP from hosts table or system resolution for the $micname."], errorcode=>["1"]}, $callback);
                    return;
                }
            }

            # get the virtual bridge for the mic node
            my $micbrg = $michash->{$micname}->[0]->{'bridge'};
            unless ($micbrg) {
                xCAT::MsgUtils->message("E", {error=>["Cannot get the micbridge for the $micname."], errorcode=>["1"]}, $callback);
                return;
            }

            # generate the mic specific entry in the configuration file
            my $micattrs = "$micid:ip=$micip|br=$micbrg|name=$micname";
            if (defined ($michash->{$micname}->[0]->{'onboot'})) {
                $micattrs .= "|onboot=$michash->{$micname}->[0]->{'onboot'}";
            }
            if (defined ($michash->{$micname}->[0]->{'vlog'})) {
                $micattrs .= "|vlog=$michash->{$micname}->[0]->{'vlog'}";
            }
            push @cfgfile, $micattrs;

        }
        push @cfgfile, "imgpath=$osimage{$osimg}";

        # get all the overlay entries for the osimage and do the cache for image
        # search all the dir in the overlay dir execpt the system dir (system dir includes the files
        # which generated by genimage command, and will be copied to mic osimage separated)
        if (defined ($imghash{$osimg}{'ollist'})) {
            push @cfgfile, "overlay=$imghash{$osimg}{'ollist'}";
        } else {
            my @overlays = <$osimage{$osimg}/opt/intel/mic/filesystem/overlay/*>;
            my $ollist; # overlay list
            foreach my $obj (@overlays) {
                my $objname = basename($obj);
                if (-d $obj && $objname ne "system") {
                    $ollist .= ",$objname";
                }
            }
            $ollist =~ s/^,//;

            $imghash{$osimg}{'ollist'} = $ollist;
            push @cfgfile, "overlay=$ollist";
        }

        if (open (CFG, ">$tftpdir/xcat/miccfg/miccfg.$host")) {
            foreach (@cfgfile) {
                print CFG $_."\n";
            }
            close (CFG);
        } else {
            xCAT::MsgUtils->message("E", {error=>["Cannot open the file $tftpdir/xcat/miccfg/miccfg.$host to write."], errorcode=>["1"]}, $callback);
            return;
        }
    }

    # run the cmd on the host to configure the mic
    my @args = ("-s", "-v", "-e");
    push @args, "$::XCATROOT/sbin/configmic";
    my $master = $request->{'_xcatdest'};
    push @args, ("-m", "$master");
    push @args, ("-p", "$tftpdir/xcat/miccfg");

    $CALLBACK = $callback;
    $subreq->({ command => ['xdsh'],
                      node => \@hosts,
                      #arg => \@args }, $callback);
                      arg => \@args }, \&michost_cb);
}

# Handle the return message from xdsh command for 'configmic' and 'flashmic' scripts to
# replace the message with correct mic name at head. And remove the unnecessary messages 
sub michost_cb {
    no strict;
    my $response = shift;
    my $rsp;
    foreach my $type (keys %$response)
    {
        my @newop;
        foreach my $output (@{$response->{$type}})
        {
            # since the remote run of mic configuration will be closed by force in the configmic
            # script, remove the error message from xdsh
            if ($type eq "error" && $output =~ /(remote shell had error code|remote Command had return code)/) {
                delete $response->{error};
                delete $rsp->{error};
            } elsif ($type eq "data" && $output =~ /Connection to(.*)closed by remote host/) {
                delete $response->{error};
                delete $response->{errorcode};
                delete $rsp->{error};
                delete $rsp->{errorcode};
            } else {
                $output =~ s/^[^:]+:\s*MICMSG://g;
                $output =~ s/\n[^:]+:\s*MICMSG:/\n/g;
                push @newop, $output;
            }
        }
        $rsp->{$type} = \@newop;
    }
    $CALLBACK->($rsp);
}

1;
