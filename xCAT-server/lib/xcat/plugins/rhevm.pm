# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

# This module is used to support the rhev
# The rhev-m is used as the agent to manage the storage domain, network, rhev-h
# There are concepts Datacenter and Cluster for the rhev, SD and network belongs to DC, 
#   rhev-h (host) belongs to cluster
#
# When installing rhev-h, it will try to register to rhev-m. From xCAT point of view, just approve.
# The fence must be configured for the rhev-h to enable the SD management, otherwise when
#    when the SPM failed, the failure take over for the SPM cannot happen automatically.
#
# The SD needs to be created with a host as the SPM (Storage Pool Manager), when the current
#   SPM failed, SPM will switch to another available rhev-h.
#
# Add rhevh to the management 
#   for the rhevh, the adding should be done automatically that specify the rhev-m infor when installing of the rhev-h
# Need to run the approval for the host to be added to the rhevm
#
# The features that are not used
    # tag, to catalog the resources with tag
    # role, for access permission
    # domain, for user/group management
#TODO: handle the functions base on the version
#TODO: add the support of iscsi storage domain



package xCAT_plugin::rhevm;

use strict;
use warnings;

use POSIX qw(WNOHANG nice);
use POSIX qw(WNOHANG setsid :errno_h);
use IO::Select;
require IO::Socket::SSL; IO::Socket::SSL->import('inet4');
use Time::HiRes qw(gettimeofday sleep);

use Fcntl qw/:DEFAULT :flock/;
use File::Path;
use File::Copy;

use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

use HTTP::Headers;
use HTTP::Request;
use XML::LibXML;

use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;

use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::Usage;

sub handled_commands{
    return {
        copycd => 'rhevm',
        mkinstall => "nodetype:os=(rhevh.*)",
        rpower => 'nodehm:power,mgt',
        rsetboot => 'nodehm:mgt',
        rmigrate => 'nodehm:mgt',
        cfgve => 'rhevm',
        lsve => 'rhevm',
        lsvm => ['hypervisor:type=(rhev.*)','nodehm:mgt'],
        mkvm => 'nodehm:mgt',
        rmvm => 'nodehm:mgt',
        clonevm => 'nodehm:mgt',
        #rinv => 'nodehm:mgt',
        chvm => 'nodehm:mgt',
        #rshutdown => "nodetype:os=(rhev.*)",
        rmhypervisor => ['hypervisor:type','nodetype:os=(rhev.*)'],
        chhypervisor => ['hypervisor:type','nodetype:os=(rhev.*)'],
        rhevhupdateflag => "nodetype:os=(rhevh.*)",
        getrvidparms => 'nodehm:mgt',
    };
}

my $verbose;
my $global_callback;

sub preprocess_request {
    my $request = shift;
    my $callback = shift;
    
    #if already preprocessed, go straight to request
    if ((defined($request->{_xcatpreprocessed}->[0]))
        && ($request->{_xcatpreprocessed}->[0] == 1)) {
        return [$request];
    }

    unless ($request and $request->{command} and $request->{command}->[0]) { return; }
    if ($request->{command}->[0] eq 'copycd') {
    	  return [$request];
    }

    my $nodes = $request->{node};
    my $command = $request->{command}->[0];
    my $extraargs = $request->{arg};

    if ($extraargs) {
        @ARGV=@{$extraargs};
        my $help;
        my $ver;
        GetOptions("V" => \$verbose, 'h|help' => \$help, 'v|version' => \$ver); 
        $global_callback = $callback;
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

    # Read the user password for the rhevm
    # Only support the general password in passwd table
    my $passtab = xCAT::Table->new('passwd');
    my ($rhevmadminpw,$rhevhrootpw, $rhevhadminpw);
    if ($passtab) {
        my $pw = $passtab->getAttribs({'key'=>'rhevm', 'username'=>'admin'}, 'password');
        if (defined($pw)) {
            $rhevmadminpw = $pw->{password};
        }
        # The $rhevmadminpw must be unencrypted, since http need this to generate the authorized key
        if (!$rhevmadminpw) {
            my $rsp;
            push @{$rsp->{data}}, "The unencrypted password of \'admin\' for the rhevm much be set in the passwd table.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        } 

        $pw = $passtab->getAttribs({'key'=>'rhevh', 'username'=>'admin'}, 'password');
        if (defined($pw)) {
            $rhevhadminpw = $pw->{password};
        }
        if (!$rhevhadminpw) {
            my $rsp;
            push @{$rsp->{data}}, "The password of \'admin\' for the rhevh much be set in the passwd table.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        } else {
            $rhevhadminpw =  authpw($rhevhadminpw);
        }
        
        $pw = $passtab->getAttribs({'key'=>'rhevh', 'username'=>'root'}, 'password');
        if (defined($pw)) {
            $rhevhrootpw = $pw->{password};
            if ($rhevhrootpw) {
                $rhevhrootpw = authpw($rhevhrootpw);
            }
        }
    }

    # Get the host for the nodes
    my $vmtab = xCAT::Table->new("vm");
    my $vmtabhash = $vmtab->getNodesAttribs($nodes,['host','mgr']);
    my $hyptab = xCAT::Table->new("hypervisor");
    my $hyptabhash = $hyptab->getNodesAttribs($nodes,['type','mgr']);

    # The hash that use hyp as key
    # In following example: rhevm1 is rhev-m;  rhevh1 and rhevh2 are rhev-h
    # vm11 is vm which located at rhevh1, vm12 is vm which located at rhevh2
    # vm1 has not specific host to bind
    # The user and password for rhev-m and rhev-h also specified
    #  |0  'rhevm1'
    #  |1  HASH(0x99066e0)
    #  |   'host' => HASH(0x9906230)
    #  |      'rhevh1' => HASH(0x99064a0)
    #  |         'adminpw' => '$1$k343MVXm$tZrjCk5GUJgRguNxdyIrT0'
    #  |         'node' => ARRAY(0x98f91a8)
    #  |            0  'vm11'
    #  |         'rootpw' => '$1$k3Yvim3b$9NLOSVlIiQY3ZYluT.CqP/'
    #  |      'rhevh2' => HASH(0x99064e8)
    #  |         'adminpw' => '$1$k343MVXm$tZrjCk5GUJgRguNxdyIrT0'
    #  |         'node' => ARRAY(0x9905c60)
    #  |            0  'vm12'
    #  |         'rootpw' => '$1$k3Yvim3b$9NLOSVlIiQY3ZYluT.CqP/'
    #  |   'node' => ARRAY(0x98ff378)
    #  |      0  'vm1'
    #  |   'pw' => '$1$9IXfmatc$Vcoy23AF5q0BcBE0cB3Uq/'
    #  |   'user' => 'admin'
    my %rhevm_hash;

    foreach my $node (@$nodes){
        my $vment = $vmtabhash->{$node}->[0];
        my $hypent = $hyptabhash->{$node}->[0];
        if (defined($vment->{'mgr'})) {    # is a vm and has rhevm info
            $rhevm_hash{$vment->{'mgr'}}->{'user'} = "admin";
            $rhevm_hash{$vment->{'mgr'}}->{'pw'} = $rhevmadminpw;
            if (defined($vment->{'host'})) {    # is a vm and has rhevm, host info
                push @{$rhevm_hash{$vment->{'mgr'}}->{'host'}->{$vment->{'host'}}->{'node'}}, $node;
                $rhevm_hash{$vment->{'mgr'}}->{'host'}->{$vment->{'host'}}->{'adminpw'} = $rhevhadminpw;
                $rhevm_hash{$vment->{'mgr'}}->{'host'}->{$vment->{'host'}}->{'rootpw'} = $rhevhrootpw;
            } else {
                push @{$rhevm_hash{$vment->{'mgr'}}->{'node'}}, $node;
            }
        } elsif (defined($hypent->{'mgr'})) {    # is a rhevh
            $rhevm_hash{$hypent->{'mgr'}}->{'user'} = "admin";
            $rhevm_hash{$hypent->{'mgr'}}->{'pw'} = $rhevmadminpw;
            push @{$rhevm_hash{$hypent->{'mgr'}}->{'host'}->{$node}->{'node'}}, $node;
            $rhevm_hash{$hypent->{'mgr'}}->{'host'}->{$node}->{'adminpw'} = $rhevhadminpw;
            $rhevm_hash{$hypent->{'mgr'}}->{'host'}->{$node}->{'rootpw'} = $rhevhrootpw;
        } elsif ($command eq 'lsvm') {    # hope the node is a rhevm, that only the lsvm can be run to display
        } else {
            my $rsp;
            push @{$rsp->{data}}, "$node: Missing the management point in \'vm.mgr\' or \'hypervisor.mgr\'.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
    }

    # For the lsve or cfgve command, get the object from argument
    if ($command =~ /^(cfgve|lsve)$/) {
        # -t type -o obj -m mgr 
        my $mgr;
        unless ($extraargs) {
            return ();
        }
        @ARGV=@{$extraargs};
        GetOptions("m=s" => \$mgr); #use mgr to know where to dispatch this request
        if ($mgr) {
            $rhevm_hash{$mgr}->{'user'} = "admin";
            $rhevm_hash{$mgr}->{'pw'} = $rhevmadminpw;
        } else {
            my $rsp;
            push @{$rsp->{data}}, "The flag -m is necessary to perform the command.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return ();
        }
    }

    # Prepare the request for each service node
    # The dispatch depends on the rhevm. Since the operation is in serial, so no need to use the service node.
    my @requests;
    my @rhevms=keys(%rhevm_hash);
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@rhevms, 'xcat', "MN");
    foreach my $snkey (keys %$sn){
        my $reqcopy = {%$request};
        $reqcopy->{'_xcatdest'} = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        # Search the node base on the hypervisor
        my $rhevms=$sn->{$snkey};
        my @moreinfo=();
        my @nodes=();
        foreach my $rhevm (@$rhevms) {
            #[rhevm][user_rhevm][pw_rhevm][rhevh][user_rhevh][pw_rhevh][nodes]
            my $data_rhevm = "[$rhevm][$rhevm_hash{$rhevm}->{'user'}][$rhevm_hash{$rhevm}->{'pw'}]";
            if (defined ($rhevm_hash{$rhevm}->{'host'})) {
                foreach my $host (keys %{$rhevm_hash{$rhevm}->{'host'}}) {
                    my $data_rhevh = $data_rhevm."[$host][$rhevm_hash{$rhevm}->{'host'}->{$host}->{'adminpw'}][$rhevm_hash{$rhevm}->{'host'}->{$host}->{'rootpw'}][".join(',',@{$rhevm_hash{$rhevm}->{'host'}->{$host}->{'node'}})."]";
                    push @moreinfo, $data_rhevh;
                    push @nodes, @{$rhevm_hash{$rhevm}->{'host'}->{$host}->{'node'}};
                }
            }
            if (defined  ($rhevm_hash{$rhevm}->{'node'})) {
                my $data_node = $data_rhevm."[][][][".join(',',@{$rhevm_hash{$rhevm}->{'node'}})."]";
                push @moreinfo, $data_node;
                push @nodes, @{$rhevm_hash{$rhevm}->{'node'}};
            }
            unless (defined ($rhevm_hash{$rhevm}->{'host'}) || defined  ($rhevm_hash{$rhevm}->{'node'})) {
                push @moreinfo, $data_rhevm."[][][][]";
            }
        }
        if (scalar @nodes) {
            $reqcopy->{node} = \@nodes;
        }
        $reqcopy->{moreinfo}=\@moreinfo;
        if ($verbose) {
            $reqcopy->{verbose} = 1;
        }
        push @requests, $reqcopy;
    }

    return \@requests;
}


sub process_request {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $command = $request->{command}->[0];
    my $args = $request->{arg};
    my $nodes = $request->{node};

    $verbose = $request->{verbose};
    
    if($command eq 'copycd'){
        return copycd($request,$callback);
    }  elsif ($command eq 'rhevhupdateflag') {
        # handle the command to update bootloader configuration file for rhevh installation
        return rhevhupdateflag($request,$callback,$subreq);
    }

    my $moreinfo;
    if ($request->{moreinfo}) { 
        $moreinfo=$request->{moreinfo}; 
    } else {
        my $rsp;
        push @{$rsp->{data}}, "";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    my %rhevm_hash;
    foreach my $info (@$moreinfo) {
        $info=~/^\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]/;
        my $rhevm=$1;
        my $rhevmuser = $2;
        my $rhevmpw = $3;
        my $rhevh=$4;
        my $rhevhadminpw = $5;
        my $rhevhrootpw = $6;
        my @nodes;
        if ($7) { @nodes =split(',', $7) };

        $rhevm_hash{$rhevm}->{name} = $rhevm;
        $rhevm_hash{$rhevm}->{user} = $rhevmuser;
        $rhevm_hash{$rhevm}->{pw} = $rhevmpw;
        if ($rhevh) {
            $rhevm_hash{$rhevm}->{host}->{$rhevh}->{name} = $rhevh;
            $rhevm_hash{$rhevm}->{host}->{$rhevh}->{adminpw} = $rhevhadminpw;
            $rhevm_hash{$rhevm}->{host}->{$rhevh}->{rootpw} = $rhevhrootpw;
            push @{$rhevm_hash{$rhevm}->{host}->{$rhevh}->{node}}, @nodes;
        } elsif (@nodes) {
            push @{$rhevm_hash{$rhevm}->{node}}, @nodes;
        }
    }

    # TODO: Plan to make long http connection to the every rhevm, but it does not work well
    foreach my $rhevm (keys %rhevm_hash) {
        # TODO fork process for each rhev-m
        # get the ca.crt for the specific rhevm
        if (! -r "/etc/xcat/rhevm/$rhevm/ca.crt") {
            if (! -d "/etc/xcat/rhevm/$rhevm") {
                mkpath ("/etc/xcat/rhevm/$rhevm");
            }
            my $cmd = "cd /etc/xcat/rhevm/$rhevm/; wget -q http://$rhevm:8080/ca.crt";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Could not get the CA certificate from http://$rhevm:8080/ca.crt.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }
        }
   }

    if($command eq 'mkinstall'){
        mkinstall($request, $callback, \%rhevm_hash);
    } elsif ($command eq "rsetboot") {
        rsetboot($callback, \%rhevm_hash, $args);
    } elsif ($command eq "addhost") {
        addhost($callback, \%rhevm_hash);
    } elsif ($command eq "chhypervisor") {
        cfghost($callback, \%rhevm_hash, $nodes, $args);
    } elsif ($command eq "rmhypervisor") {
        push @$args, "-r";
        cfghost($callback, \%rhevm_hash, $nodes, $args);
    }elsif ($command eq "cfgve") {
        cfgve($callback, \%rhevm_hash,$args);
    } elsif ($command eq "lsve") {
        lsve($callback, \%rhevm_hash,$args);
    } elsif ($command eq "rmhost") {
        rmhost();
    } elsif ($command eq "lsvm") {
        lsvm($callback, \%rhevm_hash, $args);
    } elsif ($command eq "chvm") {
        chvm($callback, \%rhevm_hash, $nodes, $args);
    }elsif ($command eq "mkvm") {
        mkvm($callback, \%rhevm_hash, $nodes, $args);
    } elsif ($command eq "rmvm") {
        rmvm($callback, \%rhevm_hash, $args);
    } elsif ($command eq "clonevm") {
        clonevm($callback, \%rhevm_hash, $args);
    } elsif ($command eq "rmigrate") {
        rmigrate($callback, \%rhevm_hash, $args);
    } elsif ($command eq "rpower") {
        power ($callback, \%rhevm_hash, $args);
    } elsif ($command eq "getrvidparms") {
        getrvidparms ($callback, \%rhevm_hash, $nodes);
    }

}

my @cpiopid;

# Perform the copycds for rhev-h to a specific dirtory 
sub copycd {
    my $request = shift;
    my $callback = shift;

    my $distname;
    my $arch;
    my $path;
    my $mntpath;
    my $file;  # the iso source file must be passed to generate the initrd

    @ARGV = @{$request->{arg}};
    GetOptions( 'n=s' => \$distname,
                'a=s' => \$arch,
                'p=s' => \$path,
                'm=s' => \$mntpath,
                'f=s' => \$file,
              );

    unless ($distname && $arch && $mntpath) {
        return;
    }

    if ($distname && $distname !~ /^rhev/) {
        return;
    } elsif (! $file) {
        $callback->({error => "Only support to use the iso file for rhev"});
        return;
    }

    my $installroot = "/install";
    my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
    my $t_entry = $entries[0];
    if ( defined($t_entry) ) {
        $installroot = $t_entry;
    }
    my $rsp;
    push @{$rsp->{data}}, "Copying media to $installroot/$distname/$arch/";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    unless ($path) {
        $path = "$installroot/$distname/$arch";
    }
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
    my $numFiles = `find . -print | wc -l`;
    my $child = open($KID, "|-");
    unless (defined $child)
    {
        $callback->({error => "Media copy operation fork failure"});
        return;
    }
    if ($child)
    {
        push @cpiopid, $child;
        my @finddata = `find .`;
        for (@finddata)
        {
            print $KID $_;
        }
        close($KID);
        $rc = $?;
    }
    else
    {
        nice 10;
        my $c = "nice -n 20 cpio -vdump $path";
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

    # copy the iso to the source dir to generate the initrd by nodeset
    copy ($file, "$installroot/$distname/$arch/rhevh.iso");
}

# Perform the install preparation for the installation of rhev-h
sub mkinstall {
    my $request  = shift;
    my $callback = shift;
    my $rhevm_hash    = shift;
    my @nodes    = @{$request->{node}};

    my %doneimgs;

    my $installdir = "/install";
    my @ents = xCAT::TableUtils->get_site_attribute("installdir");
    my $site_ent = $ents[0];
    if( defined($site_ent) )
    {
        $installdir = $site_ent;
    }

    my $tftpdir = "/tftpboot";
    @ents = xCAT::TableUtils->get_site_attribute("tftpdir");
    $site_ent = $ents[0];
    if( defined($site_ent) )
    {
        $tftpdir = $site_ent;
    }

    my $nttab = xCAT::Table->new('nodetype');
    my %ntents = %{$nttab->getNodesAttribs(\@nodes, ['profile', 'os', 'arch', 'provmethod'])};

    my $bptab  = xCAT::Table->new('bootparams',-create=>1);
    my $restab = xCAT::Table->new('noderes',-create=>1);
    my %resents = %{$restab->getNodesAttribs(\@nodes, ['xcatmaster', 'tftpdir', 'primarynic', 'installnic'])};

    foreach my $rhevm (keys %{$rhevm_hash}) {
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $node (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if ($node eq $rhevm_hash->{$rhevm}->{host}->{$node}->{node}->[0]) {  #this is a rhev-h
                    my $ent = $ntents{$node}->[0];
                    my $os = $ent->{os};
                    my $arch    = $ent->{arch};
                    my $profile = $ent->{profile};
            
                    my ($kcmdline,$k,$i);
                    if ($arch =~ /x86/
                        && -r "$installdir/$os/$arch/isolinux/vmlinuz0"
                        && -r "$installdir/$os/$arch/isolinux/initrd0.img"
                        && -r "$installdir/$os/$arch/rhevh.iso") {
                        my $tftppath = "$tftpdir/xcat/$os/$arch";
                        mkpath($tftppath);
                        copy ("$installdir/$os/$arch/isolinux/vmlinuz0", $tftppath);
            
                        # append the full iso to the initrd. It will be downloaded to the node and as the installation source to install rhev-h
                        unless ($doneimgs{"$os|$arch"}) {
                            my $cmd = "cd $installdir/$os/$arch/; echo rhevh.iso | cpio -H newc --quiet -L -o | gzip -9 | cat $installdir/$os/$arch/isolinux/initrd0.img - > $tftppath/initrd0.img";
                            `$cmd`;
                            $doneimgs{"$os|$arch"} = 1;
                        }
                        $k = "xcat/$os/$arch/vmlinuz0";
                        $i = "xcat/$os/$arch/initrd0.img";
                    } else {
                        my $rsp;
                        push @{$rsp->{data}}, "Cannot find vmlinux";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
            
                    $kcmdline = " rootflags=loop";
                    $kcmdline .= " root=live:/rhevh.iso";
                    $kcmdline .= " rootfstype=auto ro liveimg nomodeset check rootflags=ro crashkernel=512M-2G:64M,2G-:128M elevator=deadline processor.max_cstate=1 install reinstall quiet rd_NO_LVM rhgb rd_NO_LUKS rd_NO_MD rd_NO_DM";

                    # set the boot device
                    my $ksdev = "";
                    $ent = $resents{$node}->[0];
                    if ($ent->{installnic}) {
                        if ($ent->{installnic} eq "mac") {
                            my $mactab = xCAT::Table->new("mac");
                            my $macref = $mactab->getNodeAttribs($node, ['mac']);
                            $ksdev = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                        }  else {
                            $ksdev = $ent->{installnic};
                        }
                     } elsif ($ent->{primarynic}) {
                        if ($ent->{primarynic} eq "mac") {
                            my $mactab = xCAT::Table->new("mac");
                            my $macref = $mactab->getNodeAttribs($node, ['mac']);
                            $ksdev = xCAT::Utils->parseMacTabEntry($macref->{mac},$node);
                        } else {
                            $ksdev = $ent->{primarynic};
                        }
                    }
                    
                    # set the storage parameters
                    $kcmdline .= " storage_init";
                    
                    # set the bootif
		    if ($ksdev) { 
                    	$kcmdline .= " BOOTIF=$ksdev ip=dhcp";
	            } else { #let boot firmware fill it in
                    	$kcmdline .= " ip=dhcp";
		    }
            
                    # set the passwd for admin and root
                    $kcmdline .=  " adminpw=$rhevm_hash->{$rhevm}->{host}->{$node}->{adminpw} rootpw=$rhevm_hash->{$rhevm}->{host}->{$node}->{rootpw} ssh_pwauth=1";
            
                    # set the hostname and password of the management server for the node so that node could register to the rhevm automatically.
                    $kcmdline .= " management_server=$rhevm_hash->{$rhevm}->{name} rhevm_admin_password=$rhevm_hash->{$rhevm}->{host}->{$node}->{rootpw}";
            
                    # set the flag update trigger, after installing of rhev-h, this url will be 'wget', xCAT MN will handle this event to run the upfateflag for this rhev-h
                    my $xcatmaster;
                    if ($ent and $ent->{xcatmaster}) {
                        $xcatmaster = $ent->{xcatmaster};
                    } else {
                        $xcatmaster = '!myipfn!';
                    }
                    $kcmdline .= " local_boot_trigger=http://$xcatmaster/xcatrhevh/rhevh_finish_install/\@HOSTNAME\@";
            
                    $bptab->setNodeAttribs($node,
                        { kernel   => $k,
                          initrd   => $i,
                          kcmdline => $kcmdline});
            
                }
            }
        }
    }
}

# Generate the REST API http request 
# $method: GET, PUT, POST, DELETE
# $api: the url of rest api
# $content: an xml section which including the data to perform the rest api
sub genreq {
    my $rhevm = shift;
    my $method = shift;
    my $api = shift;
    my $content = shift;

    if (! defined($content)) { $content = ""; }
    my $header = HTTP::Headers->new('content-type' => 'application/xml',
                             'Accept' => 'application/xml',
                             #'Connection' => 'keep-alive',
                             'Host' => $rhevm->{name}.':8443');
    $header->authorization_basic($rhevm->{user}.'@internal', $rhevm->{pw});

    my $ctlen = length($content);
    $header->push_header('Content-Length' => $ctlen);

    my $url = "https://".$rhevm->{name}.":8443".$api;
    my $request = HTTP::Request->new($method, $url, $header, $content);
    $request->protocol('HTTP/1.1');

    return $request;
}

# Make connection to rhev-m
# Send REST api request to rhev-m
# Receive the response from rhev-m
# Handle the error cases
#
# return 1-ssl connection error; 
#          2-http response error; 
#          3-return a http error message; 
#          5-operation failed
sub send_req {
    my $ref_rhevm = shift;
    my $request = shift;

    my $rhevm = $ref_rhevm->{name};

    my $rc = 0;
    my $response;
    my $connect;
    my $socket = IO::Socket::INET->new( PeerAddr => $rhevm, 
                                                              PeerPort => '8443',
                                                              Timeout => 15);
    if ($socket) {
        $connect = IO::Socket::SSL->start_SSL($socket, SSL_ca_file => "/etc/xcat/rhevm/$rhevm/ca.crt", Timeout => 0);
        if ($connect) {
            my $flags=fcntl($connect,F_GETFL,0);
            $flags |= O_NONBLOCK;
            fcntl($connect,F_SETFL,$flags);
        } else {
            $rc = 1;
            $response = "Could not make ssl connection to $rhevm:8443.";
        }
    } else {
        $rc = 1;
        $response = "Could not create socket to $rhevm:8443.";
    }

    if ($rc) {
        return ($rc, $response);
    }

    my $IOsel = new IO::Select;
    $IOsel->add($connect);

    if ($verbose) {
        my $rsp;
        push @{$rsp->{data}}, "\n===================================================\n$request----------------";
        xCAT::MsgUtils->message("I", $rsp, $global_callback);
    }

    print $connect $request;
    $response = "";
    my $retry;
    my $ischunked;
    my $firstnum;
    while ($retry++ < 10) {
        unless ($IOsel->can_read(2)) {
            next;
        }
        my $readbytes;
        my $res = "";
        do { $readbytes=sysread($connect,$res,65535,length($res)); } while ($readbytes);
        if ($res) {
            my @part = split (/\r\n/, $res);
            for my $data (@part) {
              # for chunk formated data, check the last chunk to finish
              if ($data =~ /Transfer-Encoding: (\S+)/) {
                if ($1 eq "chunked") {
                  $ischunked = 1;
                }
              }
              if ($ischunked && $data =~ /^([\dabcdefABCDEF]+)$/) {
                if ($1 eq 0) {
                  # last chunk
                  goto FINISH;
                }else {
                  # continue to get the rest chunks
                  $retry = 0;
                  next;
                }
              } else {
                # put all data together
                $response .= $data;
              }
           }
        }
        unless ($ischunked) {
            # for non chunk data, just read once
            if ($response) {
                last;
            } else {
                if (not defined $readbytes and $! == EAGAIN) { next; }
                $rc = 2;
                last;
            }
        }
    }

FINISH: 
    if ($retry >= 10 ) {$rc = 3;}

    if ($verbose) {
        my $rsp;
        push @{$rsp->{data}}, "$response===================================================\n";
        xCAT::MsgUtils->message("I", $rsp, $global_callback);
    }

    $IOsel->remove($connect);
    close($connect);

    if ($response) {
        if (grep (/<html>/, $response)) { # get a error message in the html
            $rc = 3; 
        }  elsif (grep (/<\?xml/, $response)) {
	    $response =~ s/.*?</</ms;
            my $parser = XML::LibXML->new();
            my $doc = $parser->parse_string($response);
            if ($doc ) {
                my $attr;
                if ($attr = getAttr($doc, "/fault/detail")) {
                    $response = $attr;
                    $rc = 5;
                } elsif ($attr = getAttr($doc, "/action/fault/detail")) {
                    if ($attr eq "[]") {
                        if ($attr = getAttr($doc, "/action/fault/reason")) {
                            $response = $attr;
                        } else {
                            $response = "failed";
                        }
                    } else {
                        $response = $attr;
                    }
                    $rc = 5;
                }
            }
        }
   }
    
    return ($rc, $response);
}

# Add the rhels host since it cannot register automatically.
sub addhost {
    my $callback = shift;
    my $rhevm_hash = shift;

    my @domain = xCAT::TableUtils->get_site_attribute("domain");
    if (!$domain[0]) {
        my $rsp;
        push @{$rsp->{data}}, "The site.domain must be set to enable the rhev support.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }

    # Create the xml data
    my $doc = XML::LibXML->createDocument();
    my $root = $doc->createElement("host");
    $doc->setDocumentElement($root);
    my $name_ele = $doc->createElement("name");
    $root->appendChild($name_ele);
    my $name_t = XML::LibXML::Text->new("");
    $name_ele->appendChild($name_t);
    
    my $add_ele = $doc->createElement("address");
    $root->appendChild($add_ele);
    my $add_t = XML::LibXML::Text->new("");
    $add_ele->appendChild($add_t);
    
    my $rootpw_ele= $doc->createElement("root_password");
    $root->appendChild($rootpw_ele);
    my $rootpw_t = XML::LibXML::Text->new("");
    $rootpw_ele->appendChild($rootpw_t);
    
    foreach my $rhevm (keys %{$rhevm_hash}) {
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if ($rhevh eq $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}->[0]) {
                    # Create the host first
                    my $api = "/api/hosts";
                    my $method = "POST";

                    # Generate the content
                    $name_t->setData($rhevh);
                    my $addofrhevh = $rhevh.".".$domain[0];
                    $add_t->setData($addofrhevh);
                    $rootpw_t->setData($rhevm_hash->{$rhevm}->{host}->{$rhevh}->{pw});
                    $rootpw_t->setData('$1$c5TJgKlJ$CuO6rR5B3d5mZc3Etu9HZ1');
                    my $content = $doc->toString();
                    
                    my $request = genreq($ref_rhevm, $method, $api, $content);
                    my ($rc, $response) = send_req($ref_rhevm, $request->as_string());

                    my $rsp;
                    if ($rc) {
                        push @{$rsp->{data}}, "$rhevh: $response";
                        next;
                    } else {
                        my $parser = XML::LibXML->new();
                        my $doc = $parser->parse_string($response);
                        if ($doc ) {
                            my $attr;
                            if ($attr = getAttr($doc, "/vms/hosts/status/state")) {
                                push @{$rsp->{data}}, "$rhevh: state: $attr";
                            }
                        }
                    }
                }
            }
        } 
    }
    # Adding the host to rhevm
}

# name -> path mapping for the resource display
my $display = {
    'datacenters' => {
        'description' => ["description"],
        'storagetype' => ['storage_type'],
        'storageformat' =>['storage_format'],
        'state' => ['status/state'],
    },
    'clusters' => {
        'description' => ["description"],
        'cpu' => ["cpu", "id"],
        'memory_overcommit' => ["memory_policy/overcommit", "percent"],
        'memory_hugepage' => ["memory_policy/transparent_hugepages/enabled"],
    },
    'storagedomains' => {
        'type' => ["type"],
        'ismaster' => ["master"],
        'storage_type' => ["storage/type"],
        'storage_add' => ["storage/address"],
        'storage_path' => ["storage/path"],
        'available' => ["available"],
        'used' => ["used"],
        'committed' => ["committed"],
        'storage_format' => ["storage_format"],
        'status' => ["status/state"],
    },
    'networks' => {
        'description' => ["description"],
        'vlan' => ["vlan", "id"],
        'stp' => ["stp"],
        'state' => ["status/state"],
    },
    'hosts' => {
        'address' => ["address"],
        'state' => ["status/state"],
        'type' => ["type"],
        'storage_manager' => ["storage_manager"],
        'powermgt' => ["power_management/enabled"],
        'powermgt_type' => ["power_management", "type"],
        'powermgt_addr' => ["power_management/address"],
        'powermgt_user' => ["power_management/username"],
        'ksm' => ["ksm/enabled"],
        'hugepages' => ["transparent_hugepages/enabled"],
        'iscsi' => ["iscsi/initiator"],
        'cpu' => ["cpu/name"],
        'cpuspeed' => ["cpu/speed"],
        'summary_active' => ["summary/active"],
        'summary_migrating' => ["summary/migrating"],
        'summary_total' => ["summary/total"],
    },
    'host_nics' => {
        'network' => ["network", "id", "networks", "/network/name"],
        'mac' => ["mac", "address"],
        'ip' => ["ip", "address"],
        'netmask' => ["ip", "netmask"],
        'gateway' => ["ip", "gateway"],
        'speed' => ["speed"],
        'boot_protocol' => ["boot_protocol"],
        'state' => ["status/state"],
    },
    'vms' => {
        'memory' => ["memory"],
        'state' => ["status/state"],
        'type' => ["type"],
        'cpusocket' => ["cpu/topology", "sockets"],
        'cpucore' => ["cpu/topology", "cores"],
        'bootorder' => ["os/boot", "dev"],
        'display' => ["display/type"],
        'start_time' => ["start_time"],
        'creation_time' => ["creation_time"],
        'stateless' => ["stateless"],
        'placement_policy' => ["placement_policy/affinity"],
        'memory_guaranteed' => ["memory_policy/guaranteed"],
        'host' => ["host", "id", "hosts", "/host/name"],
    },
    'templates' => {
        'memory' => ["memory"],
        'state' => ["status/state"],
        'type' => ["type"],
        'cpusocket' => ["cpu/topology", "sockets"],
        'cpucore' => ["cpu/topology", "cores"],
        'bootorder' => ["os/boot", "dev"],
        'display' => ["display/type"],
        'creation_time' => ["creation_time"],
        'stateless' => ["stateless"],
    },
    'disks' => {
        'size' => ["size"],
        'type' => ["type"],
        'state' => ["status/state"],
        'iftype' => ["interface"],
        'format' => ["format"],
        'bootable' => ["bootable"],
        'storage_domains' => ["storage_domains/storage_domain", "id", "storagedomains", "/storage_domain/name"],
    },
    'nics' => {
        'iftype' => ["interface"],
        'mac' => ["mac", "address"],
        'network' => ["network", "id", "networks", "/network/name"],
    },
};

# Display the resource, it's called by lsvm and lsve
# $reponse - xml response return from send_req
# $type -datacenters, clusters, storagedomains ...
# $prelead - space that will be displayed pre the real message
# $criteria - 'dc=<name>' or 'name=<name>', only display when matchs
sub displaysrc {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $response = shift;
    my $type = shift;
    my $prelead = shift;
    my $criteria = shift;
    my $individual = shift;

    my @output;
    my @displayed;
    
    my $prefix;
    if ($type eq "datacenters") {
        $prefix = "/data_centers/data_center";
    } elsif ($type eq "clusters") {
        $prefix = "/clusters/cluster";
    } elsif ($type eq "storagedomains") {
        if ($individual) {
            $prefix = "/storage_domain";
        } else {
            $prefix = "/storage_domains/storage_domain";
        }
    } elsif ($type eq "networks") {
        $prefix = "/networks/network";
    } elsif ($type eq "hosts") {
        $prefix = "/hosts/host";
    } elsif ($type eq "vms") {
        $prefix = "/vms/vm";
    } elsif ($type eq "templates") {
        $prefix = "/templates/template";
    } elsif ($type eq "disks") {
        $prefix = "/disks/disk";
    } elsif ($type eq "nics") {
        $prefix = "/nics/nic";
    } elsif ($type eq "host_nics") {
        $prefix = "/host_nics/host_nic";
    } else {
        return ();
    }
    
    my $parser = XML::LibXML->new();
    my $doc = $parser->parse_string($response);
    if ($doc) {
        my @nodes = $doc->findnodes($prefix);
        foreach my $node (@nodes) {
            # when crteria specified, the dc or name need to be checked
            if ($criteria) {
                my ($name, $value) = split('=', $criteria);
                my $curval;
                if ($name eq "dc") {
                    my $cnode = $node->findnodes("data_center");
                    if (defined($cnode->[0])) {
                        $curval = $cnode->[0]->getAttribute("id");
                    } else {
                        next;
                    }
                } elsif ($name eq "name") {
                    my $cnode = $node->findnodes("name");
                    if (defined($cnode->[0])) {
                        $curval = $cnode->[0]->textContent();
                    } else {
                        next;
                    }
                }

                unless ($curval eq $value) {
                    next;
                }
            }
            
            # Get the resource name first and display
            my $objname = getAttr($node, "name");
            push @displayed, getAttr($node, "", "id");
            push @output, $prelead.$type.": [".$objname."]";

            # Display each item for the specific type
            foreach my $name (sort (keys %{$display->{$type}})) {
                if (defined ($display->{$type}->{$name}->[2])) { # search the resource from the id
                    # If the [3] and [4] params are specified, use the [0] and [1] to get the target resouce id,
                    # Then search the resource of this id, [3] is type and [4] is the path to get the end message
                    my $id = getAttr($node, $display->{$type}->{$name}->[0], $display->{$type}->{$name}->[1]);
                    my $srctype = $display->{$type}->{$name}->[2];
                    my $srcpath = $display->{$type}->{$name}->[3];
                    my ($rc, $newid, $stat, $response) = search_src($ref_rhevm, $srctype, "/".$id, 1);
                    unless ($rc) {
                        my $parser = XML::LibXML->new();
                        my $doc = $parser->parse_string($response);
                        if ($doc ) {
                            my $attr;
                            if ($attr = getAttr($doc, $srcpath) || defined ($attr)) {
                                push @output, $prelead."  ".$name.": ".$attr;
                            }
                        }
                    }
                } else {
                    my $value = getAttr($node, $display->{$type}->{$name}->[0], $display->{$type}->{$name}->[1]);
                    if ($value) {
                        push @output, $prelead."  ".$name.": ".$value;
                    }
                }
            }
        }
    }
    
    my $rsp;
    if (@output) {
        push @{$rsp->{data}}, @output;
    }
    xCAT::MsgUtils->message("I", $rsp, $callback);

    return @displayed;
}

# Display the virtual environment
# -t - type of resouce: dc - datacenter; cl - cluster; sd - storage domain; nw - network; tpl - template
# -o - the object that needs to be displayed. It could be multiple objs separated with ','
# -m - the rhevm that manage the resources
sub lsve {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;
    my $nodes = shift;

    my @output;

    my ($type, $objs, $mgr, $approve, $create, $update, $active, $network, $power, $remove);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('t=s' => \$type,
                        'o=s' => \$objs,
                        'm=s' => \$mgr);
    }

    my $rhevm = (keys %{$rhevm_hash})[0];
    my $ref_rhevm = {'name' => $rhevm, 
                             'user' => $rhevm_hash->{$rhevm}->{user}, 
                             'pw' => $rhevm_hash->{$rhevm}->{pw}};

    my @objs;
    if ($objs) {
        @objs = split (',', $objs);
    } else {
        push @objs, 'xxxxxx_all_objs';
    }
    foreach my $obj (@objs) {
        if ($type eq "dc") {
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "datacenters", $obj);
            unless ($rc) {
                displaysrc($callback, $ref_rhevm, $response, "datacenters", "");
                my $dcid = $id;

                if ($obj ne 'xxxxxx_all_objs') {
                    # Display the cluster, storagedomain, network if requiring to display datacenter
                    ($rc, $id, $stat, $response) = search_src($ref_rhevm, "clusters", "datacenter%3D$obj");
                    unless ($rc) {
                        displaysrc($callback, $ref_rhevm, $response, "clusters", "    ");
                    }
                    #($rc, $id, $stat, $response) = search_src($ref_rhevm, "storagedomains", "datacenter%3D$obj");
                    ($rc, $id, $stat, $response) = search_src($ref_rhevm, "datacenters/$dcid/storagedomains:storagedomains");
                    unless ($rc) {
                        displaysrc($callback, $ref_rhevm, $response, "storagedomains", "    ");
                    }
                    ($rc, $id, $stat, $response) = search_src($ref_rhevm, "networks");
                    unless ($rc) {
                        displaysrc($callback, $ref_rhevm, $response, "networks", "    ", "dc=$dcid");
                    }
                    ($rc, $id, $stat, $response) = search_src($ref_rhevm, "templates", "datacenter%3D$obj");
                    unless ($rc) {
                        displaysrc($callback, $ref_rhevm, $response, "templates", "    ");
                    }
                }
            }
        } elsif ($type eq "cl") {
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "clusters", "$obj");
            unless ($rc) {
                displaysrc($callback, $ref_rhevm, $response, "clusters", "");
            }
        } elsif ($type eq "sd") {
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "storagedomains", "$obj");
            unless ($rc) {
                displaysrc($callback, $ref_rhevm, $response, "storagedomains", "");
            }
        } elsif ($type eq "nw") {
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "networks");
            unless ($rc) {
                if ($obj eq 'xxxxxx_all_objs') {
                    displaysrc($callback, $ref_rhevm, $response, "networks", "  ");
                } else {
                    displaysrc($callback, $ref_rhevm, $response, "networks", "  ", "name=$obj");
                }
            }
        } elsif ($type eq "tpl") {
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "templates", "$obj");
            unless ($rc) {
                displaysrc($callback, $ref_rhevm, $response, "templates", "");
            }
        } else {
            my $rsp;
            push @{$rsp->{data}}, "The type: $type is not supported.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }
    }
    
    return;
}

# Configure the rhev virtual environment
# -t - type of resouce: dc - datacenter; cl - cluster; sd - storage domain; nw - network
# -o - the object that needs to be configured. It could be multiple objs separated with ','
# -m - the rhevm that manage the resources
# -d - datacenter name that needs by creating
# -c - creating a resource
# -u - updating a resource
# -g - activate a resource
# -s - deactivate a resource
# -a - attach a resource
# -b - detach a resource
# -r - delete a resource

# Working format:
# cfgve -t sd -m <mgr> -o <name> -c
# cfgve -t sd -m <mgr> -o <name> -a/-g/-s
# cfgve -t nw -m <mgr> -o < name> -c
# cfgve -t tpl -m <mgr> -o <name> -r
# 
sub cfgve {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;
    my $nodes = shift;

    my ($type, $objlist, $mgr, $datacenter, $cluster, $create, $update, $remove, $activate, $deactivate, $attach, $detach, $force, $stype, $cputype, $vlan);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('t=s' => \$type,
                        'o=s' => \$objlist,
                        'm=s' => \$mgr,
                        'd=s' => \$datacenter,
                        'l=s' => \$cluster,
                        'c' => \$create,
                        'u' => \$update,
                        'g' => \$activate,
                        's' => \$deactivate,
                        'a' => \$attach,
                        'b' => \$detach,
                        'r' => \$remove,
                        'f' => \$force,
                        'k=s' => \$stype,
                        'p=s' => \$cputype,
                        'n=s' => \$vlan);
    }

    my $rhevm = (keys %{$rhevm_hash})[0];
    my $ref_rhevm = {'name' => $rhevm, 
                             'user' => $rhevm_hash->{$rhevm}->{user}, 
                             'pw' => $rhevm_hash->{$rhevm}->{pw}};

    my @objs;
    if ($objlist) {
        @objs = split (',', $objlist);
    }
    foreach my $obj (@objs) {
        if ($type eq "sd") {
            if ($create) {
                if (mkSD($callback, $ref_rhevm, $obj)) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: create storage domain succeeded.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    return;
                }
            } elsif ($activate || $deactivate || $attach || $detach || $remove) {
                # get the name of datacenter
                my $vsdtab = xCAT::Table->new('virtsd',-create=>0);
                my $vsdent = $vsdtab->getAttribs({'node'=>$obj}, ['datacenter']);
                my $datacenter = $vsdent->{datacenter};
                unless ($datacenter) {
                    $datacenter = "Default";
                }
                my ($rc, $dcid, $sdid, $stat);
                ($rc, $dcid, $stat) = search_src($ref_rhevm, "datacenters", $datacenter);
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: failed to get datacenter: $datacenter.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return;
                }
                ($rc, $sdid, $stat) = search_src($ref_rhevm, "storagedomains", $obj);
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: failed to get storagedomains: $obj.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return;
                }
                if ($activate || $deactivate) {
                    my $rsp;
                    if (activate($callback, $ref_rhevm,"/api/datacenters/$dcid/storagedomains/$sdid", $obj, $deactivate)) {
                        push @{$rsp->{data}}, "$obj: failed.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    } else {
                        push @{$rsp->{data}}, "$obj: succeeded.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                } elsif ($attach || $detach) {
                    my $rsp;
                    if (attach($callback, $ref_rhevm,"/api/datacenters/$dcid/storagedomains", "storage_domain", $sdid, $detach)) {
                        push @{$rsp->{data}}, "$obj: failed.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    } else {
                        push @{$rsp->{data}}, "$obj: succeeded.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                } elsif ($remove) {
                    if ($force) {
                        # deactivate the storage domain
                        activate($callback, $ref_rhevm,"/api/datacenters/$dcid/storagedomains/$sdid", $obj, 1);
                    
                        # detach the storage domain to the datacenter
                        attach($callback, $ref_rhevm,"/api/datacenters/$dcid/storagedomains", "storage_domain", $sdid, 1);
                    }
    
                    if (!deleteSD($callback, $ref_rhevm, "/api/storagedomains/$sdid", $obj)) {
                        my $rsp;
                        push @{$rsp->{data}}, "$obj: delete storage domain succeeded.";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                        return;
                    }
                }
            } 
        } elsif ($type eq "tpl") {
            if ($remove) {
                my ($rc, $tplid, $stat, $response) = search_src($ref_rhevm, "templates", "$obj");
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: cannot find the template: $obj.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                }
                generalaction($callback, $ref_rhevm, "/api/templates/$tplid", "DELETE", 1);
            }
        } elsif ($type eq "nw") {
            if ($create) {
                # serach datacenter
                unless ($datacenter) {
                    $datacenter = "Default";
                }
                my ($rc, $dcid, $stat) = search_src($ref_rhevm, "datacenters", $datacenter);
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: failed to get datacenter: $datacenter.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                
                # create the network
                my $api = "/api/networks";
                my $method = "POST";
                my $content = "<network><name>$obj</name><data_center id=\"$dcid\"/></network>";
                if ($vlan) {
                    $content = "<network><name>$obj</name><data_center id=\"$dcid\"/><vlan id=\"$vlan\"/></network>";
                }
                my $request = genreq($ref_rhevm, $method, $api, $content);
                my $response;
                ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: $response";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: succeeded";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }
            } elsif ($remove) {
                my ($rc, $nwid, $stat) = search_src($ref_rhevm, "networks", $obj);
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: failed to get networks: $obj.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                generalaction($callback, $ref_rhevm, "/api/networks/$nwid", "DELETE", 1);
            } elsif ($attach || $detach) {
                unless ($cluster) {
                    $cluster = "Default";
                }
                my ($rc, $clid, $stat, $response) = search_src($ref_rhevm, "clusters", "$cluster");
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: cannot find the cluster:$cluster.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                my $nwid;
                ($rc, $nwid, $stat) = search_src($ref_rhevm, "networks", "$obj");
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: cannot find the network.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                if ($attach) {
                    my $api = "/api/clusters/$clid/networks";
                    my $method = "POST";
                    my $content = "<network id=\"$nwid\"><name>$obj</name></network>";
                    my $request = genreq($ref_rhevm, $method, $api, $content);
                    my $response;
                    ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                    if ($rc) {
                        my $rsp;
                        push @{$rsp->{data}}, "$obj: $response";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    } else {
                        my $rsp;
                        push @{$rsp->{data}}, "$obj: succeeded";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                        next;
                    }
                } elsif($detach) {
                    generalaction($callback, $ref_rhevm, "/api/clusters/$clid/networks/$nwid", "DELETE", 1);
                }
            }
        } elsif ($type eq "dc") {
            my ($rc, $dcid, $stat, $response) = search_src($ref_rhevm, "datacenters", "$obj");
            
            if ($create) {
                if (!$rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: data center has been created.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                unless ($stype && $stype =~ /^(nfs|localfs)$/) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: the storage type needs to be specified by -k.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                # create the datacenter
                my $api = "/api/datacenters";
                my $method = "POST";
                my $content = "<data_center><name>$obj</name><storage_type>$stype</storage_type><version minor=\"0\" major=\"3\"/></data_center>";
                my $request = genreq($ref_rhevm, $method, $api, $content);
                my $response;
                ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: $response";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: succeeded";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }
            } elsif ($remove) {
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: cannot find the data center.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                generalaction($callback, $ref_rhevm, "/api/datacenters/$dcid", "DELETE", 1);
            }
        } elsif ($type eq "cl") {
            my ($rc, $clid) = search_src($ref_rhevm, "clusters", "$obj");
            
            if ($create) {
                if (!$rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: cluster has been created.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                unless ($datacenter) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: the datacenter for the cluster must be specified.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                my $dcid;
                ($rc, $dcid) = search_src($ref_rhevm, "datacenters", "$datacenter");
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: failed to get the datacenter: $datacenter.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                unless ($cputype) {
                    $cputype = "Intel Penryn Family";
                }
                
                # create the datacenter
                my $api = "/api/clusters";
                my $method = "POST";
                my $content = "<cluster><name>$obj</name><data_center id=\"$dcid\"/><cpu id=\"$cputype\"/></cluster>";
                my $request = genreq($ref_rhevm, $method, $api, $content);
                my $response;
                ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: $response";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: succeeded";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }
            } elsif ($remove) {
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$obj: cannot find the cluster.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                generalaction($callback, $ref_rhevm, "/api/clusters/$clid", "DELETE", 1, $force);
            }
        } else {
            my $rsp;
            push @{$rsp->{data}}, "The type: $type is not supported.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }
    }
                             
}


# configure host
# -a: approve the host that can be managed by rhev-m
# -n: configure the network for host
# -p: configure the power management for host.  
#      This will be used for rhev-m to check the power status of host, so that when SPM (Storage Pool Manager) host
#      down, rhev-m could switch the SPM role to another host automatically.
#      For rack mounted server, the ipmilan is used to do the power management. The IP of bmc and user:passwd are
#      neccessary to be configured for power management.
# -e: activate the host
# -d: deactivate a host to maintanance mode
sub cfghost {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $nodes = shift;
    my $args = shift;

    my ($approve, $network, $power, $activate, $deactivate, $remove, $force);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('a' => \$approve,
                        'n' => \$network,
                        'p' => \$power,
                        'e' => \$activate,
                        'd' => \$deactivate,
                        'r' => \$remove,
                        'f' => \$force);
    }

    # Set the default user:pw for ipmi
    my ($ipmiuser, $ipmipw) = ('USERID', 'PASSW0RD');
    my ($hment, $ipmient);
    my %hyper;

    # get the IP, user, passwd for the bmc of the host if requiring to configure power management
    if ($power) {
        my $hmtab = xCAT::Table->new('nodehm',-create=>0);
        $hment = $hmtab->getNodesAttribs($nodes,['mgt']);

        my $ipmitab = xCAT::Table->new('ipmi',-create=>0);
        $ipmient = $ipmitab->getNodesAttribs($nodes,['bmc', 'username', 'password']);

        #get the default password for bmc
        my $pwtab = xCAT::Table->new('passwd',-create=>0);
        my $pwent = $pwtab->getAttribs({'key'=>'ipmi'},['username', 'password']);
        if ($pwent) {
            $ipmiuser = $pwent->{'username'};
            $ipmipw = $pwent->{'password'};
        }
    }

    # get the network parameters for the host if requiring to configure the network for host
    if ($network || $approve) {
        # get the network interface for host
        my $hyptab = xCAT::Table->new('hypervisor',-create=>0);
        my $hypent = $hyptab->getNodesAttribs($nodes,['interface', 'datacenter', 'cluster']);
        foreach my $node (@$nodes) {
            if (defined ($hypent->{$node}->[0])) {
                $hyper{$node}{interface} = $hypent->{$node}->[0]->{interface};
                $hyper{$node}{datacenter} = $hypent->{$node}->[0]->{datacenter};
                $hyper{$node}{cluster} = $hypent->{$node}->[0]->{cluster};
            }
            if (!$hyper{$node}{datacenter}) {
                $hyper{$node}{datacenter} = "Default";
            }
            if (!$hyper{$node}{cluster}) {
                $hyper{$node}{cluster} = "Default";
            }
        }
    }

    foreach my $rhevm (keys %{$rhevm_hash}) {
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm,
                                 'user' => $rhevm_hash->{$rhevm}->{user},
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if ($rhevh eq $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}->[0]) {
                    # get the host
                    my ($rc, $hostid, $hoststat) = search_src($ref_rhevm, "hosts", $rhevh);
                    if ($rc) {
                        my $rsp;
                        push @{$rsp->{data}}, "$rhevh: host was not created.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }

                    if ($approve) {
                      if ($hoststat eq "pending_approval") {
                        # get the id of cluster
                        my ($rc, $clusterid, $clusterstat) = search_src($ref_rhevm, "clusters", $hyper{$rhevh}{cluster});
                        if ($rc) {
                            my $rsp;
                            push @{$rsp->{data}}, "$rhevh: failed to get cluster: $hyper{$rhevh}{cluster}.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                        my $approved = 0;
                        # Create the host first
                        my $api = "/api/hosts/$hostid/approve";
                        my $method = "POST";

                        # Generate the content
                        my $content = "<action><cluster id=\"$clusterid\"/></action>";

                        my $request = genreq($ref_rhevm, $method, $api, $content);
                        my $response;
                        ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                        
                        if ($rc) {
                            my $rsp;
                            push @{$rsp->{data}}, "$rhevh: $response";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        } else {
                            my $parser = XML::LibXML->new();
                            my $doc = $parser->parse_string($response);
                            if ($doc ) {
                                my $attr;
                                if ($attr = getAttr($doc, "/action/status/state")) {
                                    if ($attr eq "complete") {
                                        $approved = 1;
                                    }
                                }
                            }
                        }

                        my $rsp;
                        if ($approved) {
                            push @{$rsp->{data}}, "$rhevh: approved.";
                            xCAT::MsgUtils->message("I", $rsp, $callback);
                        } else {
                            push @{$rsp->{data}}, "$rhevh: failed to approve.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                      } else {
                          my $rsp;
                          push @{$rsp->{data}}, "$rhevh: the state of node is not correct for approve. Current state: $hoststat";
                          xCAT::MsgUtils->message("E", $rsp, $callback);
                      }
                    }

                    if ($activate || $deactivate) {
                        my $rsp;
                        if (activate($callback, $ref_rhevm,"/api/hosts/$hostid", $rhevh, $deactivate)) {
                            push @{$rsp->{data}}, "$rhevh: failed.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                        } else {
                            push @{$rsp->{data}}, "$rhevh: succeeded.";
                            xCAT::MsgUtils->message("I", $rsp, $callback);
                        }
                    }
                    
                    # configure the network interface for a host
                    if ($network) {
                        unless ($hyper{$rhevh}{interface}) {
                            my $rsp;
                            push @{$rsp->{data}}, "$rhevh: the hypervisor.interface needs to be configured to configure the network for a host.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                        
                        if ($hoststat eq "maintenance") {
                            cfghypnw($callback, $ref_rhevm, $rhevh, $hyper{$rhevh}{interface}, $hyper{$rhevh}{datacenter});
                        } else {
                            my $rsp;
                            push @{$rsp->{data}}, "$rhevh: the hypervisor needs to be deactivated to maintenance state for the network configuring.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                    }

                    if ($power) {
                        # Configure the power management for a host
                        # for rack mounted machine, use the 'ipmilan' type of power management
                        if (defined($hment->{$rhevh}->[0]) && $hment->{$rhevh}->[0]->{'mgt'}) {
                            if ($hment->{$rhevh}->[0]->{'mgt'} eq "ipmi") {
                                # get the bmc IP, user, password for the bmc
                                my ($user, $pw, $addr) = ($ipmiuser, $ipmipw);
                                if (defined($ipmient->{$rhevh}->[0]) && $ipmient->{$rhevh}->[0]->{bmc}) {
                                    $addr = $ipmient->{$rhevh}->[0]->{bmc};
                                } else {
                                    my $rsp;
                                    push @{$rsp->{data}}, "$rhevh: the ipmi.bmc was not set to know the hardware control point.";
                                    xCAT::MsgUtils->message("E", $rsp, $callback);
                                    next;
                                }
                                if (defined($ipmient->{$rhevh}->[0]) && $ipmient->{$rhevh}->[0]->{username}) {
                                    $user = $ipmient->{$rhevh}->[0]->{username};
                                }
                                if (defined($ipmient->{$rhevh}->[0]) && $ipmient->{$rhevh}->[0]->{password}) {
                                    $pw = $ipmient->{$rhevh}->[0]->{password};
                                }

                                my $doc = XML::LibXML->createDocument();
                                my $root = $doc->createElement("host");
                                $doc->setDocumentElement($root);
                                my $pm_ele = $doc->createElement("power_management");
                                $root->appendChild($pm_ele);
                                $pm_ele->setAttribute("type", "ipmilan");

                                $pm_ele->appendTextChild("enabled", "true");
                                $pm_ele->appendTextChild("address", $addr);
                                $pm_ele->appendTextChild("username", $user);
                                $pm_ele->appendTextChild("password", $pw);

                                my $api = "/api/hosts/$hostid";
                                my $method = "PUT";

                                my $request = genreq($ref_rhevm, $method, $api, $doc->toString);
                                my ($rc, $response) = send_req($ref_rhevm, $request->as_string());

                                my $rsp;
                                if ($rc) {
                                    push @{$rsp->{data}}, "$rhevh: $response";
                                    next;
                                } else {
                                    push @{$rsp->{data}}, "$rhevh: Setting power management: $addr";
                                }
                                xCAT::MsgUtils->message("I", $rsp, $callback);
                            } else {
                                my $rsp;
                                push @{$rsp->{data}}, "$rhevh: the supported power management method: ipmi.";
                                xCAT::MsgUtils->message("E", $rsp, $callback);
                            }
                        } else {
                            my $rsp;
                            push @{$rsp->{data}}, "$rhevh: the nodehm.mgt was not set to know the management method.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                        }
                    } # end of power management configure

                    if ($remove) {
                        if ($force && ($hoststat ne "maintenance")) {
                            # deactivate the host anyway
                            activate($callback, $ref_rhevm,"/api/hosts/$hostid", $rhevh, 1);
                            if (waitforcomplete($ref_rhevm, "/api/hosts/$hostid", "/host/status/state=maintenance", 30)) {
                                my $rsp;
                                push @{$rsp->{data}}, "$rhevh: failed to waiting the host gets to \"maintenance\" state.";
                                xCAT::MsgUtils->message("E", $rsp, $callback);
                                next;
                            }
                        }
                        generalaction($callback, $ref_rhevm, "/api/hosts/$hostid", "DELETE", 1);
                    }
                }
            } # end of for each host
        }
    }
}


sub rmhost {
}

# List the host and virtual machine
# -s short
# -v display virtual machines which belongs to the host
sub lsvm {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;
    my $nodes = shift;

    my ($short, $vm4host);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('s' => \$short,
                        'v' => \$vm4host);
    }
    
    foreach my $rhevm (keys %{$rhevm_hash}) {
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};
    
        # Get the node that will be handled
        my @vms;
        my @hyps;
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    foreach my $node (@{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}}) {
                        if ($rhevh eq $node) {
                            push @hyps, $rhevh;
                        } else {
                            push @vms, $node;
                        }
                    }
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
            push @vms, @{$rhevm_hash->{$rhevm}->{node}};
        }

        foreach my $hyp (@hyps) {
            # Get the host
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "hosts", "$hyp");
            unless ($rc) {
                my @hostids = displaysrc($callback, $ref_rhevm, $response, "hosts", "");

                # display the nics for the vm
                my $hostid = $hostids[0];
                ($rc, $id, $stat, $response) = search_src($ref_rhevm, "hosts:host_nics", "/$hostid/nics");
                unless ($rc) {
                    displaysrc($callback, $ref_rhevm, $response, "host_nics", "    ");
                }

                # TODO, display the vm for host always?
                if (1||$vm4host) {
                    my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "vms", "Host.name%3D$hyp");
                    unless ($rc) {
                        displaysrc($callback, $ref_rhevm, $response, "vms", "    ");
                    }
                }
            }
        }

        # Display virtual machines
        foreach my $vm (@vms) {
            # Get vm
            my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "vms", $vm);
            unless ($rc) {
                my @vmids = displaysrc($callback, $ref_rhevm, $response, "vms", "");
                
                # display the disks for the vm
                my $vmid = $vmids[0];
                my ($rc, $id, $stat, $response) = search_src($ref_rhevm, "vms:disks", "/$vmid/disks");
                unless ($rc) {
                    displaysrc($callback, $ref_rhevm, $response, "disks", "    ");
                }
                    
                # display the nics for the vm
                ($rc, $id, $stat, $response) = search_src($ref_rhevm, "vms:nics", "/$vmid/nics");
                unless ($rc) {
                    displaysrc($callback, $ref_rhevm, $response, "nics", "    ");
                }
            }
        }
    }
}

# Create virtual machine
# Since the configuration for a vm is complicated, all the parameters will be gotten from vm table
sub mkvm {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $nodes = shift;

    my $upmac;  # used to update the mac table
    my $mactab = new xCAT::Table('mac',-create=>1);

    # Get the attributes for the node from the vm table
    my $vmtab = xCAT::Table->new('vm',-create=>0);
    my $vment = $vmtab->getNodesAttribs($nodes,['master', 'host', 'cluster', 'virtflags', 'storage', 'storagemodel', 'memory', 'cpus', 'nics', 'nicmodel', 'bootorder', 'vidproto']);

    # Generate the xml content for add the storage
    # Note: this is an independent action after the vm creating
    my $adds = XML::LibXML->createDocument();
    my $asroot = $adds->createElement("disk");
    $adds->setDocumentElement($asroot);

    # set the disk type: system and data
    my $disktype_ele = $adds->createElement("type");
    $asroot->appendChild($disktype_ele);
    my $disktype_t = XML::LibXML::Text->new("system");
    $disktype_ele->appendChild($disktype_t);

    # set the bootable
    my $diskboot_ele = $adds->createElement("bootable");
    $asroot->appendChild($diskboot_ele);
    my $diskboot_t = XML::LibXML::Text->new("true");
    $diskboot_ele->appendChild($diskboot_t);
    
    my $sd_ele = $adds->createElement("storage_domains");
    $asroot->appendChild($sd_ele);
    my $sdid_ele = $adds->createElement("storage_domain");
    $sd_ele->appendChild($sdid_ele);

    # add size of disk
    my $sdsize_ele = $adds->createElement("size");
    $asroot->appendChild($sdsize_ele);
    my $sdsize_t = XML::LibXML::Text->new("");
    $sdsize_ele->appendChild($sdsize_t);

   # add the element for type of disk interface 
    my $sdif_ele = $adds->createElement("interface");
    $asroot->appendChild($sdif_ele);
    my $sdif_t = XML::LibXML::Text->new("virtio");
    $sdif_ele->appendChild($sdif_t);

    # add the disk format element
    my $sdft_ele = $adds->createElement("format");
    $asroot->appendChild($sdft_ele);
    my $sdfm_t = XML::LibXML::Text->new("cow");
    $sdft_ele->appendChild($sdfm_t);

    # Generate the xml content for add network interface
    # Note: this is an independent action after the vm creating
    my $addnw = XML::LibXML->createDocument();
    my $anwroot = $addnw->createElement("nic");
    $addnw->setDocumentElement($anwroot);

    # add the interface type element
    my $nwif_ele = $addnw->createElement("interface");
    $anwroot->appendChild($nwif_ele);
    my $nwif_t = XML::LibXML::Text->new("virtio");
    $nwif_ele->appendChild($nwif_t);

    # add the name element
    my $nwname_ele = $addnw->createElement("name");
    $anwroot->appendChild($nwname_ele);
    my $nwname_t = XML::LibXML::Text->new("nic1");
    $nwname_ele->appendChild($nwname_t);

    # add the network element which specify which network this nic 
    # will be added to
    my $nwnw_ele = $addnw->createElement("network");
    $anwroot->appendChild($nwnw_ele);
    my $nwnwname_ele = $addnw->createElement("name");
    $nwnw_ele->appendChild($nwnwname_ele);
    my $nwnwname_t = XML::LibXML::Text->new("rhevm");
    $nwnwname_ele->appendChild($nwnwname_t);

    # create a mac element
    my $nwmac_ele = $addnw->createElement("mac");
    
    foreach my $rhevm (keys %{$rhevm_hash}) {
        my %node_hyp;
        my %hostid;
        my $success = 0;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};
    
        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    foreach (@{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}}) {
                        $node_hyp{$_}{hyp} = $rhevh;
                        $hostid{$rhevh} = 1;
                    }
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
            foreach (@{$rhevm_hash->{$rhevm}->{node}}) {
                $node_hyp{$_}{hyp} = "";
            }
        }

        # get the host id
        # this is used for the case that needs locate vm to a spcific host
        foreach my $host (keys %hostid) {
            my ($rc, $id, $stat) = search_src($ref_rhevm, "hosts", $host);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "Cannot find $host in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return;
            }
            $hostid{$host} = $id;
        }
        my @nodes = (keys %node_hyp);
        my $macmac = $mactab->getNodesAttribs(\@nodes, ['mac']);
   
        foreach my $node (@nodes) {
            my $myvment = $vment->{$node}->[0];
            unless ($myvment) {
                my $rsp;
                push @{$rsp->{data}}, "$node: has NOT entry in vm table.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
            
            # Check the existence of the node
            my ($rc, $id, $stat) = search_src($ref_rhevm, "vms", $node);
            if (!$rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: virtual machine has been created.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
                next;
            }
            
            #Create the virtual machine first
            my $api = "/api/vms";
            my $method = "POST";
            
            # generate the content
            # configure the template
            my $hastpl = 0;
            my $tplele;
            if ($myvment->{master}) {
                $tplele = "<template><name>$myvment->{master}</name></template>";
                $hastpl = 1;
            } else {
                $tplele = "<template><name>Blank</name></template>";
            }
            
            # configure memory
            my $memele;
            if ($myvment->{memory}) {
                my $memsize = $myvment->{memory};
                $memsize =~ s/g/000000000/i;
                $memsize =~ s/m/000000/i;
                $memele = "<memory>$memsize</memory>";
            } elsif (!$hastpl) {
                $memele = "<memory>2000000000</memory>";
            }
            
            # set the cpu
            my $cpuele;
            if ($myvment->{cpus}) {
                my ($socketnum, $corenum) = split(':', $myvment->{cpus});
                unless ($corenum) {$corenum = 1;}
                $cpuele = "<cpu><topology cores=\"$corenum\" sockets=\"$socketnum\"/></cpu>";
            } elsif (!$hastpl) {
                $cpuele = "<cpu><topology cores=\"1\" sockets=\"1\"/></cpu>"
            }
            
            # configure bootorder
            # there's a bug that sequence is not correct to set two order, so currently just set one
            my $boele;
            if ($myvment->{bootorder}) {
                my ($firstbr, $secbr) = split (',', $myvment->{bootorder});
                if ($secbr) {
                    $boele = "<os><boot dev=\"$firstbr\"/><boot dev=\"$secbr\"/><boot/></os>";
                } else {
                    $boele = "<os><boot dev=\"$firstbr\"/><boot/></os>";
                }
            } elsif (!$hastpl) {
                $boele = "<os><boot dev=\"network\"/><boot/></os>";
            }

            my $disele;
            if ($myvment->{vidproto}) {
                $disele = "<display><type>$myvment->{vidproto}</type></display>";
            } else {
                $disele = "<display><type>vnc</type></display>";
            }

            my $affinity;
            if ($myvment->{virtflags}) {
                # parse the specific parameters from vm.virtflags
                my @pairs = split (':', $myvment->{virtflags});
                foreach my $pair (@pairs) {
                    my ($name, $value) = split('=', $pair);
                    if ($name eq "placement_affinity") {
                        # set the affinity for placement_policy
                        $affinity = "<affinity>$value</affinity>"
                    }
                }
            }

            if (!$affinity && !$hastpl) {
                $affinity = "<affinity>migratable</affinity>"
            }

            my $hostele;
            if ($myvment->{host}) {
                $hostele = "<host id=\"$hostid{$myvment->{host}}\"/>";
            }

            my $placement_policy;
            if ($affinity || $hostele) {
                $placement_policy= "<placement_policy>$hostele$affinity</placement_policy>";
            }

            # set the cluster for the vm
            my $clusterele;
            if ($myvment->{cluster}) {
                $clusterele = "<cluster><name>$myvment->{cluster}</name></cluster>";
            } else {
                $clusterele = "<cluster><name>Default</name></cluster>";
            }

            my $content = "<vm><type>server</type><name>$node</name>$clusterele$tplele$memele$cpuele$boele$placement_policy$disele</vm>";
            my $request = genreq($ref_rhevm, 
                               $method,
                               $api,
                               $content);
            my $response;
            my $vmid;
            ($rc, $response) = send_req($ref_rhevm, $request->as_string());
            if (!$rc) {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                my $newvm;
                if (defined ($doc->findnodes("/vm/name")->[0])) {
                    $newvm = $doc->findnodes("/vm/name")->[0]->textContent();
                }
                if ($newvm ne $node) {
                    my $rsp;
                    push @{$rsp->{data}}, "$node: create virtual machine failed.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
                my $vm = $doc->findnodes("/vm")->[0];
                $vmid = $vm->getAttribute('id');
                $success = 1;
            } else {
                my $rsp;
                push @{$rsp->{data}}, $response;
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
    
            #Add the disk for the vm from storage domain
            my @disklist = split ('\|', $myvment->{storage});
                foreach (@disklist) {
                my ($sdname, $disksize, $disktype) = split(':', $_);
                if ($sdname) {
                    if (waitforcomplete($ref_rhevm, "/api/vms/$vmid", "/vm/status/state=down", 30)) {
                        my $rsp;
                        push @{$rsp->{data}}, "$node: failed to waiting the vm gets to \"down\" state.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }
                    $success = 0;
    
                    #Get the storage domain by name
                    my $sdid;
                    ($rc, $sdid, $stat) = search_src($ref_rhevm, "storagedomains", $sdname);
                    if ($rc) {
                        my $rsp;
                        push @{$rsp->{data}}, "Could not get the storage domain $sdname.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    } 
    
                    if ($sdid) {
                        $api = "/api/vms/$vmid/disks";
                        $method = "POST";
                        
                        # generate the content
                        if ($disktype) {
                            $disktype_t->setData($disktype);
                            if ($disktype eq "system") {
                                $diskboot_t->setData("true");
                            } else {
                                $diskboot_t->setData("false");
                            }
                        } else {
                            $disktype_t->setData("system");
                            $diskboot_t->setData("true");
                        }
                        # set the size of disk
                        if ($disksize) {
                            $disksize =~ s/g/000000000/i;
                            $disksize =~ s/m/000000/i;
                        } else {
                            $disksize = "5000000000"; #5G is default
                        }
                        $sdid_ele->setAttribute("id", $sdid);
                        $sdsize_t->setData($disksize);
    
                        # set the interface type and format for disk
                        if ($myvment->{storagemodel}) {
                            my ($iftype,$iffmt) = split(':', $myvment->{storagemodel});
                            $sdif_t->setData($iftype);
                            $sdfm_t->setData($iffmt);
                        } else {
                            $sdif_t->setData("virtio");
                            $sdfm_t->setData("cow");
                        }
        
                        $request = genreq($ref_rhevm, $method, $api, $adds->toString());
                        ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                        if (!$rc) {
                            my $parser = XML::LibXML->new();
                            my $doc = $parser->parse_string($response);
                            if (defined($doc->findnodes("/fault")->[0])) {
                                my $rsp;
                                push @{$rsp->{data}}, "$node: Add disk failed for virtual machine";
                                if ($doc->findnodes("/fault/detail")->[0]) {
                                    push @{$rsp->{data}}, $doc->findnodes("/fault/detail")->[0]->textContent();
                                }
                                xCAT::MsgUtils->message("E", $rsp, $callback);
                                next;
                            }
                            my $state;
                            if (defined($doc->findnodes("/disk/creation_status/state")->[0])) {
                                $state = $doc->findnodes("/disk/creation_status/state")->[0]->textContent();
                            }
                            if ($state =~ /fail/i) {
                                my $rsp;
                                push @{$rsp->{data}}, "$node: Add disk failed for virtual machine";
                                xCAT::MsgUtils->message("E", $rsp, $callback);
                                next;
                            }
                            $success = 1;
                        } else {
                            my $rsp;
                            push @{$rsp->{data}}, $response;
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                    }
                }
            }
            
            # Add the network interface
            #Get the network by name
            my @nics;
            if ($myvment->{nics}) {
                @nics = split(/\|/, $myvment->{nics});
            }
            if (!@nics && !$hastpl) {
                # default is to add nic1 to manament network 'rhevm'
                push @nics, "rhevm:eth0:yes";
            }
            if (@nics) {
                if (waitforcomplete($ref_rhevm, "/api/vms/$vmid", "/vm/status/state=down", 30)) {
                    my $rsp;
                    push @{$rsp->{data}}, "$node: failed to waiting the vm gets to \"down\" state.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
            }
            
            # if no installnic is specified, set the firstmac to mac.mac
            my $firstmac;
            
            # Search the nic
            my %oldmac;
            ($rc, undef, $stat, $response) = search_src($ref_rhevm, "vms:nics", "/$vmid/nics");
            unless ($rc) {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                my @nicnodes = $doc->findnodes("/nics/nic");
                foreach my $nic (@nicnodes) {
                    if (defined($nic->findnodes("name"))) {
                        my $ethname = getAttr($nic, "name");
                        my $mac = getAttr($nic, "mac", "address");
                        $oldmac{$ethname} = $mac;
                        unless($firstmac) {
                             $firstmac = $mac;
                        }
                    }
                }
            }
            
            foreach my $nic (@nics) {
                # format of nic: [networkname:ifname:installnic]
                my ($nwname, $ifname, $instnic) = split(':', $nic);

                if (defined($oldmac{$ifname})) {
                    # The nic has been defined, mostly by clone
                    if ($instnic) {
                        $upmac->{$node}->{mac} = $oldmac{$ifname};
                    }
                    next;
                }

                # start the configuring
                $success = 0;
            
                my $nwid;
                ($rc, $nwid, $stat) = search_src($ref_rhevm, "networks", "$nwname");
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not get the network $nwname.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                } 

                $api = "/api/vms/$vmid/nics";
                $method = "POST";
                
                # generate the content
                # set the nic interface type
                if ($myvment->{nicmodel}) {
                    $nwif_t->setData($myvment->{nicmodel});
                } else {
                    $nwif_t->setData("virtio");
                }
                $nwname_t->setData($ifname);
                $nwnwname_t->setData($nwname);

                # set the mac address element
                # if no entry in mac.mac, and this is install nic, THEN use the existed mac
                # otherwise create a new mac automatically by rhev-m
                my $orgmac;
                if ($instnic && defined ($macmac->{$node}->[0]) && defined ($macmac->{$node}->[0]->{'mac'})) {
                    $orgmac = $macmac->{$node}->[0]->{'mac'};
                    $anwroot->appendChild($nwmac_ele);
                    $nwmac_ele->setAttribute("address", $orgmac);
                } else {
                    $anwroot->removeChild($nwmac_ele);
                }
                
                $content = $addnw->toString();
                $request = genreq($ref_rhevm, 
                                   $method,
                                   $api,
                                   $content);
                ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                if (!$rc) {
                    my $parser = XML::LibXML->new();
                    my $doc = $parser->parse_string($response);
                    if (defined($doc->findnodes("/nic/mac")->[0])) {
                        my $realmac = $doc->findnodes("/nic/mac")->[0]->getAttribute("address");
                        unless($firstmac) {
                             $firstmac = $realmac;
                        }
                        if ($instnic) {
                            $upmac->{$node}->{mac} = $realmac;
                        }
                        
                        $success = 1;
                        next;
                     } else {
                        my $rsp;
                        push @{$rsp->{data}}, "$node: failed to create virtual machine.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, $response;
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
            }

            if (!$upmac->{$node}->{mac} && $firstmac) {
                $upmac->{$node}->{mac} = $firstmac;
            }

            if ($success) {
                my $rsp;
                push @{$rsp->{data}}, "$node: Succeeded";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
    }

    $mactab->setNodesAttribs($upmac);
}

# Remove a virtual machine
sub rmvm {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;

    my $force;
    if ($args) {
        @ARGV=@{$args};
        GetOptions('f' => \$force);
    }

    foreach my $rhevm (keys %{$rhevm_hash}) {
        my @nodes;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};

        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    push @nodes, @{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}};
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
             push @nodes, @{$rhevm_hash->{$rhevm}->{node}};
        }

        # perform the action against the node
        foreach my $node (@nodes) {
            # Get the ID of node
            my ($rc, $id, $state) = search_src($ref_rhevm, "vms", $node);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: node was not defined in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            } elsif (! defined($id)) {
                my $rsp;
                push @{$rsp->{data}}, "$node: node was not defined in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }

            # Remove the vm
            my $api = "/api/vms/$id";
            my $method = "DELETE";
            
            my $content = "<action/>";
            if ($force) {
                $content = "<action><force>true</force></action>";
            }
            my $request = genreq($ref_rhevm, 
                               $method,
                               $api,
                               $content);
            my $response;
            ($rc, $response) = send_req($ref_rhevm, $request->as_string());
            if ($rc == 2) {
                my $rsp;
                push @{$rsp->{data}}, "$node: succeeded.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
                next;
            } else {
                my $rsp;
                push @{$rsp->{data}}, $response;
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
        }
    }
}

# Change virtual machine
sub chvm {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $nodes = shift;

    # Get the mac address for the nodes from the mac table
    my $mactab = new xCAT::Table('mac',-create=>1);

    # Get the attributes for the nodes from the vm table
    my $vmtab = xCAT::Table->new('vm',-create=>0);
    my $vment = $vmtab->getNodesAttribs($nodes,['master', 'host', 'cluster', 'virtflags', 'storage', 'storagemodel', 'memory', 'cpus', 'nics', 'nicmodel', 'bootorder', 'vidproto']);

    foreach my $rhevm (keys %{$rhevm_hash}) {
        my %node_hyp;
        my %hostid;
        my $success = 0;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};
    
        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    foreach (@{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}}) {
                        $node_hyp{$_}{hyp} = $rhevh;
                        $hostid{$rhevh} = 1;
                    }
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
            foreach (@{$rhevm_hash->{$rhevm}->{node}}) {
                $node_hyp{$_}{hyp} = "";
            }
        }

        # get the host id
        # this is used for the case that needs locate vm to a spcific host
        foreach my $host (keys %hostid) {
            my ($rc, $id, $stat) = search_src($ref_rhevm, "hosts", $host);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "Cannot find $host in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return;
            }
            $hostid{$host} = $id;
        }
        my @nodes = (keys %node_hyp);
        my $macmac = $mactab->getNodesAttribs(\@nodes, ['mac']);
   
        foreach my $node (@nodes) {
            my $myvment = $vment->{$node}->[0];
            unless ($myvment) {
                my $rsp;
                push @{$rsp->{data}}, "$node: has NOT entry in vm table.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
            
            # Check the existence of the node
            my ($rc, $vmid, $stat) = search_src($ref_rhevm, "vms", $node);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: virtual machine was not created.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
                next;
            }
            
            # generate the content
            my $tplele;
            if ($myvment->{master}) {
                $tplele = "<template><name>$myvment->{master}</name></template>";
            }
            
            # configure memory
            my $memele;
            if ($myvment->{memory}) {
                my $memsize = $myvment->{memory};
                $memsize =~ s/g/000000000/i;
                $memsize =~ s/m/000000/i;
                $memele = "<memory>$memsize</memory>";
            }
            
            # set the cpu
            my $cpuele;
            if ($myvment->{cpus}) {
                my ($socketnum, $corenum) = split(':', $myvment->{cpus});
                unless ($corenum) {$corenum = 1;}
                $cpuele = "<cpu><topology cores=\"$corenum\" sockets=\"$socketnum\"/></cpu>";
            }
            
            # configure bootorder
            # there's a bug that sequence is not correct to set two order, so currently just set one
            my $boele;
            if ($myvment->{bootorder}) {
                my ($firstbr, $secbr) = split (',', $myvment->{bootorder});
                if ($secbr) {
                    $boele = "<os><boot dev=\"$firstbr\"/><boot dev=\"$secbr\"/><boot/></os>";
                } else {
                    $boele = "<os><boot dev=\"$firstbr\"/><boot/></os>";
                }
            }

            my $disele;
            if ($myvment->{vidproto}) {
                $disele = "<display><type>$myvment->{vidproto}</type></display>";
            }

            my $affinity;
            if ($myvment->{virtflags}) {
                # parse the specific parameters from vm.virtflags
                my @pairs = split (':', $myvment->{virtflags});
                foreach my $pair (@pairs) {
                    my ($name, $value) = split('=', $pair);
                    if ($name eq "placement_affinity") {
                        # set the affinity for placement_policy
                        $affinity = "<affinity>$value</affinity>"
                    }
                }
            }

            my $hostele;
            if ($myvment->{host}) {
                $hostele = "<host id=\"$hostid{$myvment->{host}}\"/>";
            }

            my $placement_policy;
            if ($affinity) {
                $placement_policy = "<placement_policy>$hostele$affinity</placement_policy>";
            } elsif ($hostele) {
                $affinity = "<affinity>migratable</affinity>";
                $placement_policy = "<placement_policy>$hostele$affinity</placement_policy>";
            }

            # set the cluster for the vm
            my $clusterele;
            if ($myvment->{cluster}) {
                $clusterele = "<cluster><name>$myvment->{cluster}</name></cluster>";
            }

            my $api = "/api/vms/$vmid";
            my $method = "PUT";
            
            my $content = "<vm><type>server</type><name>$node</name>$clusterele$tplele$memele$cpuele$boele$placement_policy$disele</vm>";
            my $request = genreq($ref_rhevm, $method, $api, $content);
            my $response;
            ($rc, $response) = send_req($ref_rhevm, $request->as_string());
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: $response";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            } else {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                my $state;
                if ($node eq getAttr($doc, "/vm/name")) {
                    my $rsp;
                    push @{$rsp->{data}}, "$node: change vm completed.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$node: change vm failed.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
            } 
        }
    }
}

# Clone the virtual machine
# create template first
sub clonevm {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;

    my ($template, $basemaster);
    if ($args) {
        @ARGV=@{$args};
        GetOptions('t=s' => \$template,
                        'b' => \$basemaster);
    }

    my $ref_rhevm;
    my @nodes;
    foreach my $rhevm (keys %{$rhevm_hash}) {
        # generate the hash of rhevm which will be used for the action functions
        $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};

        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    push @nodes, @{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}};
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
             push @nodes, @{$rhevm_hash->{$rhevm}->{node}};
        }
    }

    my $node = $nodes[0];
    # create a template from a vm
    if ($template) {
        # Get the ID of node
        my ($rc, $vmid, $state) = search_src($ref_rhevm, "vms", $node);
        if ($rc) {
            my $rsp;
            push @{$rsp->{data}}, "$node: node was not defined in the rhevm.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        if ($state ne "down") {
            my $rsp;
            push @{$rsp->{data}}, "$node: vm needs to be shutdown to run the clone.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return;
        }

        my $api = "/api/templates";
        my $method = "POST";
        my $content = "<template><name>$template</name><vm id=\"$vmid\"/></template>";
        my $request = genreq($ref_rhevm, $method, $api, $content);
        my $response;
        ($rc, $response) = send_req($ref_rhevm, $request->as_string());
        if ($rc) {
            return (1, $response);
        } else {
            my $parser = XML::LibXML->new();
            my $doc = $parser->parse_string($response);
            if ($doc->findnodes("/template/status/state")->[0]) {
                my $state = $doc->findnodes("/template/status/state")->[0]->textContent();
    
                my $rsp;
                push @{$rsp->{data}}, "$template: $state.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            } else {
                my $rsp;
                push @{$rsp->{data}}, "$template: failed to get the status.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            return;
        }
    }

}

# Set the boot sequence for the vm
sub rsetboot {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;

    my ($showstat, $bootdev);
    if ($args) {
        my $arg = $args->[0];
        if ($arg =~ /^stat/) {
            $showstat = 1;
        } else {
            $bootdev = $arg;
        }
    } else {
        $showstat = 1;
    }

    my ($firstbr, $secbr);
    if ($bootdev) {
        ($firstbr, $secbr) = split (',', $bootdev);
        if (($firstbr && $firstbr !~ /^(network|hd)$/) || ($secbr && $secbr !~ /^(network|hd)$/)) {
            my $rsp;
            push @{$rsp->{data}}, "Supported boot device: network, hd";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    foreach my $rhevm (keys %{$rhevm_hash}) {
        my @nodes;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};

        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    push @nodes, @{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}};
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
             push @nodes, @{$rhevm_hash->{$rhevm}->{node}};
        }

        foreach my $node (@nodes) {
            # Get the ID of vm
            my ($rc, $vmid, $state, $response) = search_src($ref_rhevm, "vms", $node);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: node was not defined in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }

            if ($showstat) {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                my @bootdevs = getAttr($doc, "/vms/vm/os/boot", "dev");
                my $bootlist = join(',', @bootdevs);
                my $rsp;
                push @{$rsp->{data}}, "$node: $bootlist";
                xCAT::MsgUtils->message("I", $rsp, $callback);
                next;
            }

            # configure bootorder
            my $boele;
            if ($secbr) {
                $boele = "<os><boot dev=\"$firstbr\"/><boot dev=\"$secbr\"/><boot/></os>";
            } else {
                $boele = "<os><boot dev=\"$firstbr\"/><boot/></os>";
            }

            my $api = "/api/vms/$vmid";
            my $method = "PUT";
            
            my $content = "<vm>$boele</vm>";
            my $request = genreq($ref_rhevm, $method, $api, $content);
            ($rc, $response) = send_req($ref_rhevm, $request->as_string());
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: $response";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            } else {
                my $rsp;
                push @{$rsp->{data}}, "$node: set boot order completed.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
                next;
            } 
        }
    }
}

#Migrate the virtual machine
sub rmigrate {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;

    my ($template, $basemaster);
    unless ($args) {
        my $rsp;
        push @{$rsp->{data}}, "Needs a target host.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }

    my $host = $args->[0];

    foreach my $rhevm (keys %{$rhevm_hash}) {
        my @nodes;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};

        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    push @nodes, @{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}};
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
             push @nodes, @{$rhevm_hash->{$rhevm}->{node}};
        }

        foreach my $node (@nodes) {
            # Get the ID of vm
            my ($rc, $vmid, $state) = search_src($ref_rhevm, "vms", $node);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: node was not defined in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }

            my $hostid;
            ($rc, $hostid, $state) = search_src($ref_rhevm, "hosts", $host);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$host: host was not defined in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }

            # Remove the vm
            my $api = "/api/vms/$vmid/migrate";
            my $method = "POST";
            
            my $content = "<action><host id=\"$hostid\"/><force>true</force></action>";
            my $request = genreq($ref_rhevm, $method, $api, $content);
            my $response;
            ($rc, $response) = send_req($ref_rhevm, $request->as_string());
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: $response.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            } else {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                if ($doc->findnodes("/action/status/state")->[0]) {
                    my $state = $doc->findnodes("/action/status/state")->[0]->textContent();
        
                    my $rsp;
                    push @{$rsp->{data}}, "$node: migrated to $host: $state.";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$node: failed to migrate to $host.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                }
            }
        }
    }
}

# Hardware control 
# rpower <vm> on/off/reset
sub power {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $args = shift;

    foreach my $rhevm (keys %{$rhevm_hash}) {
        my @nodes;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};

        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    push @nodes, @{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}};
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
             push @nodes, @{$rhevm_hash->{$rhevm}->{node}};
        }

        # perform the action against the node
        foreach my $node (@nodes) {
            # Get the ID of node
            my ($rc, $id, $state) = search_src($ref_rhevm, "vms", $node);
            if ($rc) {
                my $rsp;
                push @{$rsp->{data}}, "$node: node was not defined in the rhevm.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
            
            my $output;
            if ($args->[0] eq 'on') {
                if ($state eq "up" || $state eq "powering_up") {
                    $output = "$node: on";
                } else {
                    my ($rc, $msg) = power_action($ref_rhevm, $id, 'start');
                    if (!$rc) {
                        $output = "$node: on";
                    } else {
                        $output = "$node: $msg";
                    }
                }
            } elsif ($args->[0] eq 'off') {
                if ($state eq "down" || $state eq "powering_down" || $state eq "powered_down") {
                    $output = "$node: off";
                } else {
                    my ($rc, $msg) = power_action($ref_rhevm, $id, 'stop');
                    if (!$rc) {
                        $output = "$node: off";
                    } else {
                        $output = "$node: $msg";
                    }
                }
            } elsif ($args->[0] eq 'reset' || $args->[0] eq 'boot') {
                if ($state eq "up" || $state eq "powering_up") {
                    my ($rc, $msg) = power_action($ref_rhevm, $id, 'stop');
                    if (!$rc) {
                        if (waitforcomplete($ref_rhevm, "/api/vms/$id", "/vm/status/state=down", 30)) {
                            my $rsp;
                            push @{$rsp->{data}}, "$node: failed to waiting the vm gets to \"down\" state.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                        ($rc, $msg) = power_action($ref_rhevm, $id, 'start');
                        if (!$rc) {
                            $output = "$node: $args->[0]";
                        } else {
                            $output = "$node: $msg";
                        }
                    } else {
                        $output = "$node: $msg";
                    }
                } else {
                    my ($rc, $msg) = power_action($ref_rhevm, $id, 'start');
                    if (!$rc) {
                        $output = "$node: $args->[0]";
                    } else {
                        $output = "$node: $msg";
                    }
                }
            } elsif ($args->[0] eq 'softoff') {
                if ($state eq "down" || $state eq "powering_down" || $state eq "powered_down") {
                    $output = "$node: softoff";
                } else {
                    my ($rc, $msg) = power_action($ref_rhevm, $id, 'shutdown');
                    if (!$rc) {
                        $output = "$node: softoff";
                    } else {
                        $output = "$node: $msg";
                    }
                }
            } elsif ($args->[0] eq 'suspend') {
                if ($state eq "suspended") {
                    $output = "$node: suspended";
                } else {
                    my ($rc, $msg) = power_action($ref_rhevm, $id, 'suspend');
                    if (!$rc) {
                        $output = "$node: suspended";
                    } else {
                        $output = "$node: $msg";
                    }
                }
            } elsif ($args->[0] =~ /^stat/) {
                if ($state eq "down") {
                    $output = "$node: off";
                } elsif ($state eq "up") {
                    $output = "$node: on";
                } else {
                    $output = "$node: $state";
                }
            }
            my $rsp;
            push @{$rsp->{data}}, $output;
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
    }

}

# Do the power control
sub power_action {
    my $rhevm = shift;
    my $id = shift;
    my $action = shift;
    
    my $api = "/api/vms/$id/$action";
    my $method = "POST";
    my $content = "<action/>";
    my $request = genreq($rhevm, 
                       $method,
                       $api,
                       $content);
    my ($rc, $response) = send_req($rhevm, $request->as_string());
    if ($rc) {
        return (1, $response);
    } else {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($response);
        my $state = $doc->findnodes("/action/status/state")->[0]->textContent();
        return (0, $state);
    }

    return (1);
}

# Search resource inside rhev-m
# $orgtype: format: [type] or [container:type]
#               [type] could be: datacenter, cluster ...
#               [container:type could be: 'vms:nics' ('vms' is the container of nic, 'nics' is the real type), vms:disk  
# $node: could be name for a resource; or the path of resource when start with '/'
#           if no $node specified, search all resource with the '$type'
# $individual: do search for a resource individually
#
# return -1-parameter error; 11-nosuch id; 
sub search_src {
    my $rhevm = shift;
    my $orgtype = shift;
    my $node = shift;
    my $individual = shift;

    my $api;
    my ($container, $type);
    if ($orgtype =~ /:/) {
        ($container, $type) = split (/:/, $orgtype);
    } else {
       $container = $type = $orgtype;
    }

    my $ispath;
    if ($node) {
        if ($node =~ /^\//) {
            # is a path
            $api = "/api/$container".$node;
            $ispath = 1;
        } elsif ($node =~ /\%3D/) {
            $api = "/api/$container?search=$node";
        } elsif ($node eq "xxxxxx_all_objs") {
            $api = "/api/$container";
        }else {
            $api = "/api/$container?search=name%3D$node";
            if ($type eq "hosts") {
                #append the domain for the hypervisor
                $api .= "*";
            }
        }
    } else {
        $api = "/api/$container";
    }
    my $method = "GET";
    my $content = "";

    my $request = genreq($rhevm, $method, $api, $content);
    my ($rc, $response) = send_req($rhevm, $request->as_string());

    if ($rc) {
        return ($rc, $response);
    } else {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($response);
        if ($doc ) {
            my ($id, $state, $idstr, $ststr);
            if ($type eq "vms") {
                $idstr = "/vms/vm";
            } elsif ($type eq "hosts") {
                if ($individual) {
                    $idstr = "/host";
                } else {
                    $idstr = "/hosts/host";
                }
            } elsif ($type eq "templates") {
                $idstr = "/templates/template";
            } elsif ($type eq "storagedomains") {
                if ($individual) {
                    $idstr = "/storage_domain";
                } else {
                    $idstr = "/storage_domains/storage_domain";
                }
            } elsif ($type eq "networks") {
                if ($individual) {
                    $idstr = "/network";
                } else {
                    $idstr = "/networks/network";
                }                
            } elsif ($type eq "datacenters") {
                $idstr = "/data_centers/data_center";
            } elsif ($type eq "clusters") {
                $idstr = "/clusters/cluster";
            } elsif ($type eq "disks") {
                $idstr = "/disks/disk";
            } elsif ($type eq "nics") {
                $idstr = "/nics/nic";
            } elsif ($type eq "host_nics") {
                $idstr = "/host_nics/host_nic";
            } else {
                return (-1);
            }

            my $idnode;
            # network is special that does not support to  serach a specific resource, 
            # so have to do the search by code from all the output
            if ($type eq "networks" && $node &&(!$ispath)) { 
                my @nodes = $doc->findnodes($idstr);
                foreach my $n (@nodes) {
                    if ($node eq getAttr($n, "name")) {
                        $idnode = $n;
                        last;
                    }
                }
            } else {
                $idnode = $doc->findnodes($idstr)->[0];
            }
            if (defined $idnode) {
              $id = $idnode->getAttribute('id');
              if ($type eq "vms") {
                  $ststr = "/vms/vm/status/state";
              } elsif ($type eq "hosts") {
                  $ststr = "/hosts/host/status/state";
              } elsif ($type eq "templates") {
                  $ststr = "/templates/template/status/state";
              } elsif ($type eq "storagedomains") {
                  if ($individual) {
                      $ststr = "/storage_domain/storage/type";
                  } else {
                      $ststr = "/storage_domains/storage_domain/storage/type";
                  }
              } elsif ($type eq "networks") {
                  $ststr = "status/state";
                  $doc = $idnode;
              } elsif ($type eq "datacenters") {
                  $ststr = "/data_centers/data_center/status/state";
              } elsif ($type eq "clusters") {
                  $ststr = "/clusters/cluster/name";
              } elsif ($type eq "disks") {
                  $ststr = "/disks/disk/status/state";
              } elsif ($type eq "nics") {
                  $ststr = "/nics/nic/name";
              } elsif ($type eq "host_nics") {
                  $ststr = "/host_nics/host_nic/status/state";
              } else {
                  return (-1);
              }
              my $statenode = $doc->findnodes($ststr)->[0];
              if (defined $statenode) {
                $state = $statenode->textContent();
              }

              # no id was found
              if (!$id) {
                  return (11);
              }
              
              return (0, $id, $state, $response);
            } else {
                return (11);
            }
        }
    }

    return (1);
}

# Get the value for a element from the xml of rest api response
sub getAttr {
    my $doc = shift;
    my $path = shift;
    my $att = shift;

    my @nodes;
    if ($path) {
        # handle the cases that has multiple entries for one atributes like boot order
        @nodes = $doc->findnodes($path);
    } else {
        push @nodes, $doc;
    }
    
    if (@nodes) {
        my @value;
        foreach my $node (@nodes) {
            if ($att) {
                push @value, $node->getAttribute($att);
            } else {
                push @value, $node->textContent();
            }
        }
        return join (',', @value);
    } else {
        return "";
    }
}

# It's a command that will be triggered from the httpd when the installation of rhev-h has finished
# Run nodeset and updatenodestat to update the status for the rhev-h
sub rhevhupdateflag {
    my $request = shift;
    my $callback = shift;
    my $subreq = shift;

    my $node = $request->{node};
    
    # run the nodeset xx next
    $subreq->({command=>['nodeset'], node=>$node, arg=>['next']}, $callback);

    # run the 'updatenodestat <node> booted'
    $subreq->({command=>['updatenodestat'], node=>$node, arg=>['booted']}, $callback);
}

# use the md5 to authorize the passwd
sub authpw {
    my $passwd = shift;

    if ($passwd =~ /^\$1\$/) {
        return $passwd;
    } else {
        my $cmd = "openssl passwd -1 $passwd";
        return xCAT::Utils->runcmd($cmd, -1);
    }
}

# Configure the network for host
# create the network for cluster if it does not exist
# configure the interface and add them to the corresponding network
sub cfghypnw {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $host = shift;
    my $interface = shift;
    my $datacenter = shift;
    
    # the format of the interface attirbute
    # networkname:interfacename:bootpro:IP:netmask:gateway
    my @if = split(/\|/, $interface);
    foreach (@if) {
        my ($netname, $ifname, $bprotocol, $ip, $nm, $gw) = split (':', $_);
        unless ($netname && $ifname) {
            my $rsp;
            push @{$rsp->{data}}, "$host: Missing network name or interface name: $_.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        }

        # get host id
        my ($rc, $hostid, $stat) = search_src($ref_rhevm, "hosts", $host);
        if ($rc) {
            my $rsp;
            push @{$rsp->{data}}, "$host: host was not created.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        }
        
        # get network interface and configure it
        my $nicid;
        my $api = "/api/hosts/$hostid/nics";
        my $method = "GET";
        my $request = genreq($ref_rhevm, $method, $api, "");
        my $response;
        ($rc, $response) = send_req($ref_rhevm, $request->as_string());
        if ($rc) {
            my $rsp;
            push @{$rsp->{data}}, "$host: $response";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        } else {
            my $parser = XML::LibXML->new();
            my $doc = $parser->parse_string($response);
            my @hostnics = $doc->findnodes("/host_nics/host_nic");
            foreach my $nicnode (@hostnics) {
                if ($ifname eq getAttr($nicnode, "name")) {
                    $doc = $nicnode;
                    last;
                }
            }
                
            if ($doc ) {
                my $attr;
                if ($attr = getAttr($doc, "", "id")) {
                    $nicid = $attr;
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$host: does not have interface $ifname.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                # get the network
                my $oldnetname;
                my $oldnetid;
                if ($attr = getAttr($doc, "network", "id")) {
                    $oldnetid = $attr;
                }
                if ($attr = getAttr($doc, "network/name")) {
                    $oldnetname = $attr;
                }

                # attach the nic to the network if needed
                # search the network
                my $newnetid;
                ($rc, $newnetid, $stat) = search_src($ref_rhevm, "networks", $netname);
                if ($rc) {
                    if ($rc == 11) {
                        my $rsp;
                        push @{$rsp->{data}}, "$host: network: $netname does not exist.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    } else {
                        my $rsp;
                        push @{$rsp->{data}}, "$host: failed to get the network: $netname.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                    next;
                }

                # detach the nic from current network if old != new
                if (($oldnetname && ($oldnetname ne $netname))
                  ||($oldnetid && ($oldnetid ne $newnetid))) { 
                     unless ($oldnetid) {
                         ($rc, $oldnetid, $stat) = search_src($ref_rhevm, "networks", $oldnetname);
                         if ($rc) {
                            my $rsp;
                            push @{$rsp->{data}}, "$host: failed to get the network: $oldnetname.";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                         }
                     }
                     #detach the interface to the network
                     if (attach($callback, $ref_rhevm, "/api/hosts/$hostid/nics/$nicid", "network", $oldnetid, 1)) {
                        my $rsp;
                        push @{$rsp->{data}}, "$host: failed to detach $ifname from $netname.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                     }
                }

                # attach the interface to the network
                if ((!$oldnetname || ($oldnetname ne $netname))
                  && (!$oldnetid || ($oldnetid ne $newnetid))) {
                    if (attach($callback, $ref_rhevm, "/api/hosts/$hostid/nics/$nicid", "network", $newnetid)) {
                        my $rsp;
                        push @{$rsp->{data}}, "$host: failed to attach $ifname to $netname.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                     }
                     generalaction($callback, $ref_rhevm, "/api/hosts/$hostid/commitnetconfig");
                 }
                
                # check the bootprotocol and network parameters, and configure if needed
                if (defined ($bprotocol) && $bprotocol =~ /^(dhcp|static)$/) {
                    my $newpro;
                    if ($attr = getAttr($doc, "boot_protocol")) {
                        if ($attr eq "dhcp") {
                            if ($bprotocol eq "static" ) {
                                $newpro = "static";
                            }
                        } elsif ($attr eq "static") {
                            if ($bprotocol eq "dhcp") {
                                $newpro = "dhcp";
                            } else {
                                my ($curip, $curnm, $curgw);
                                if ($attr = getAttr($doc, "ip", "address")) {
                                    $curip = $attr;
                                } 
                                if ($attr = getAttr($doc, "ip", "netmask")) {
                                    $curnm = $attr;
                                } 
                                if ($attr = getAttr($doc, "ip", "gateway")) {
                                    $curgw = $attr;
                                } 

                                if ($ip ne $curip || $nm ne $curnm || $gw ne $curgw) {
                                    $newpro = "static";
                                }
                            }
                        }
                    } else {
                        $newpro = $bprotocol;
                    }

                    # Set the attributes for the nic
                    $api = "/api/hosts/$hostid/nics/$nicid";
                    $method = "PUT";
                    my $content;
                    if (defined ($newpro) && $newpro eq "dhcp")  {
                        $content = "<host_nic><boot_protocol>dhcp</boot_protocol></host_nic>";
                    } elsif (defined ($newpro) && $newpro eq "static")  {
                        $content = "<host_nic><boot_protocol>static</boot_protocol><ip address=\"$ip\" netmask=\"$nm\" gateway=\"$gw\"/></host_nic>";
                    }
                    if (defined ($newpro)) {
                        my $request = genreq($ref_rhevm, $method, $api, $content);
                        ($rc, $response) = send_req($ref_rhevm, $request->as_string());
                        if ($rc) {
                            my $rsp;
                            push @{$rsp->{data}}, "$host: $response";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                    }
                } else {
                    my $rsp;
                    push @{$rsp->{data}}, "$host: the boot procotol was not set or invalid.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                 generalaction($callback, $ref_rhevm, "/api/hosts/$hostid/commitnetconfig");
            }
        }
    }
    
    return 0;
}

# Create a Storage Domain
# The parameters will be gotten from virtsd table
sub mkSD {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $sd = shift;

    # get the informage for the SD
    my ($rc, $sdid, $state) = search_src($ref_rhevm, "storagedomains", $sd);
    if (!$rc) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: storagedomains has been defined in the rhevm.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    } 

    # get the attributes for the SD
    my $vsdtab = xCAT::Table->new('virtsd',-create=>0);
    my $vsdent = $vsdtab->getAttribs({'node'=>$sd}, ['sdtype', 'stype', 'location', 'host', 'datacenter']);
    unless ($vsdent) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: cannot find the definition for $sd in the virtsd table.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    }

    unless ($vsdent->{host}) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: a SPM host needs to be specified.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    }
    unless ($vsdent->{stype} && (($vsdent->{stype} eq "localfs") || $vsdent->{location})) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: the sdtype and location need to be specified.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    }

    unless ($vsdent->{stype} =~ /^(nfs|localfs)$/) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: supported storage type: nfs, localfs.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    }

    # get the host as SPM
    my $hostid;
    ($rc, $hostid, $state) = search_src($ref_rhevm, "hosts", $vsdent->{host});
    if ($rc) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: cannot find the host $vsdent->{host}.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    } 
    
    # To create the SD
    my $api = "/api/storagedomains";
    my $method = "POST";

    # Create the xml data
    my $doc = XML::LibXML->createDocument();
    my $root = $doc->createElement("storage_domain");
    $doc->setDocumentElement($root);

    $root->appendTextChild("name", $sd);

    # set the host will be the SPM
    my $host_ele = $doc->createElement("host");
    $root->appendChild($host_ele);
    $host_ele->setAttribute("id", $hostid);

    # set the location of storage
    my $storage_ele = $doc->createElement("storage");
    $root->appendChild($storage_ele);
    $storage_ele->appendTextChild("type", $vsdent->{stype});
    
    my ($address, $path) = split(':', $vsdent->{location});
    if ($vsdent->{stype} eq "nfs") {
        $storage_ele->appendTextChild("address", $address);
        $storage_ele->appendTextChild("path", $path);
    } elsif ($vsdent->{stype} eq "localfs") {
        $storage_ele->appendTextChild("path", "/data/images/rhev");
    }

    if ($vsdent->{sdtype}) {
        $root->appendTextChild("type", $vsdent->{sdtype});
    } else {
        $root->appendTextChild("type", "data");
    }

    my $request = genreq($ref_rhevm, $method, $api, $doc->toString);
    my $response;
    ($rc, $response) = send_req($ref_rhevm, $request->as_string());

    
    if ($rc) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: $response";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 0;
    } else {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($response);
        if ($doc ) {
            my $sdid;
            if ($sdid = getAttr($doc, "/storage_domain", "id")) {
                if ($vsdent->{stype} eq "localfs") {
                    #return directly
                    return $sdid;
                }
                # attach the storage domain to the datacenter
                my $dc = $vsdent->{datacenter};
                unless ($dc) {$dc = "default"};
                my $dcid;
                ($rc, $dcid, $state) = search_src($ref_rhevm, "datacenters", $dc);
                if ($rc) {
                    my $rsp;
                    push @{$rsp->{data}}, "$sd: $response";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 0;
                }

                # attach the storage domain to the datacenter
                if (attach($callback, $ref_rhevm, "/api/datacenters/$dcid/storagedomains", "storage_domain", $sdid)) {
                    my $rsp;
                    push @{$rsp->{data}}, "$sd: failed to attach to datacenter:$dc.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 0;
                }

                # Check the state of the storage domain
                if (checkstat($callback, $ref_rhevm, "storage_domain", "/api/datacenters/$dcid/storagedomains/$sdid") ne "active") {
                    # active the storage domain
                    if (activate($callback, $ref_rhevm,"/api/datacenters/$dcid/storagedomains/$sdid", $sd)) {
                        my $rsp;
                        push @{$rsp->{data}}, "$sd: failed to activate the storage domain.";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        return 0;
                    }
                }
                
                return $sdid;
            }
        }
    }

    return 0;
}

# Activate or Deactive a resource
# 0 - suc; 1 - failed
sub activate {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $path = shift;
    my $name = shift;
    my $deactivate = shift;

    my $api;
    if ($deactivate) {
        $api = $path."/deactivate";
    } else {
        $api = $path."/activate";
    }
    my $method = "POST";
    my $content = "<action/>";
    my $request = genreq($ref_rhevm, $method, $api, $content);

    my ($rc, $response) = send_req($ref_rhevm, $request->as_string());
    if ($rc) {
            my $rsp;
            push @{$rsp->{data}}, "$name: $response";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
    } else {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($response);
        if ($doc ) {
            my $attr;
            if ($attr = getAttr($doc, "/action/status/state")) {
                if ($attr ne "complete") {
                    if (waitforcomplte()) {
                        return 1;
                    } else {
                        return 0;
                    }
                } else {
                    return 0;
                }
            }
        }
    }
    return 1;
}

# Attach or Detach a resource
# type: network (for host nic), storage_domain (for sd)
# 0 - suc; 1 - failed
sub attach {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $path = shift;
    my $type = shift;
    my $id = shift;
    my $detach = shift;

    my $method = "POST";
    my $api;
    my $content;
    if ($type eq "storage_domain") {
        if ($detach) {
            $api = "$path/$id";
            $method = "DELETE";
            $content = "";
        } else {
            $api = $path;
            $content = "<$type id=\"$id\"/>";
        }
    } else {
        if ($detach) {
            $api = $path."/detach";
        } else {
            $api = $path."/attach";
        }
        $content = "<action><$type id=\"$id\"/></action>";
    }
    
    
    my $request = genreq($ref_rhevm, $method, $api, $content);

    my ($rc, $response) = send_req($ref_rhevm, $request->as_string());
    if ($rc) {
        # no output for detaching sd from datacenter
        if ($rc == 2 && $type eq "storage_domain" && $detach) {
            return 0;
        }
        my $rsp;
        push @{$rsp->{data}}, "$response:$rc";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    } else {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($response);
        if ($doc ) {
            my $attr;
            if ($type eq "storage_domain") {
                 if (getAttr($doc, "/storage_domain/status/state") =~ /(inactive|active)/) {
                     return 0;
                 } else {
                     return 1;
                 }
            } else {
                if ("complete" eq getAttr($doc, "/action/status/state")) {
                    return 0;
                 } else {
                    return 1;
                }
            }
        }
    }
    return 1;
}

# Common subroutine for general action of rest api
sub generalaction {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $api = shift;
    my $method = shift;
    my $norsp = shift;
    my $force = shift;

    unless ($method) {
        $method = "POST";
    }

    my $content = "<action/>";
    if ($force) {
        $content = "<action><force>true</force></action>";
    }
    my $request = genreq($ref_rhevm, $method, $api, $content);
    my ($rc, $response) = send_req($ref_rhevm, $request->as_string());

    # no need to handle response for DELETE
    if ($norsp && !$response) {
        return;
    }
    
    if ($rc) {
        my $rsp;
        push @{$rsp->{data}}, "$response";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
}

# Check the state of a object
sub checkstat {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $type = shift;
    my $api = shift;

    my $request = genreq($ref_rhevm, "GET", $api, "");
    my ($rc, $response) = send_req($ref_rhevm, $request->as_string());
    if ($rc) {
        return "";
    } else {
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_string($response);
        if ($doc ) {
            if ($type eq "storage_domain") {
                 return getAttr($doc, "/storage_domain/status/state")
            } 
        }
    }

    return "";
}

# delete storage domain
sub deleteSD {
    my $callback = shift;
    my $ref_rhevm = shift;
    my $path = shift;
    my $sd = shift;

    # get the attributes for the SD
    my $vsdtab = xCAT::Table->new('virtsd',-create=>0);
    my $vsdent = $vsdtab->getAttribs({'node'=>$sd}, ['host']);
    unless ($vsdent) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: cannot find the definition for $sd in the virtsd table.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    unless ($vsdent->{host}) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: a SPM host needs to be specified.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    
    # get the id of host
    my ($rc, $hostid, $stat) = search_src($ref_rhevm, "hosts", $vsdent->{host});
    if ($rc) {
        my $rsp;
        push @{$rsp->{data}}, "$sd: Cannot find the host: $vsdent->{host} for the storag domain.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    
    my $method = "DELETE";
    my $api = $path;
    my $content;

    $content = "<storage_domain><host id=\"$hostid\"/><format>true</format></storage_domain>";

    my $request = genreq($ref_rhevm, $method, $api, $content);
    my $response;
    ($rc, $response) = send_req($ref_rhevm, $request->as_string());

    # no need to handle response for DELETE
    if ($rc) {
        # no output for detaching sd from datacenter
        if ($rc == 2) {
            return 0;
        }
        my $rsp;
        push @{$rsp->{data}}, "$response";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
}

sub waitforcomplete {
    my $ref_rhevm = shift;
    my $api = shift;
    my $criteria = shift;
    my $timeout = shift;

    unless ($timeout) {
        $timeout = 10;
    }

    my ($path, $target) = split ('=', $criteria);

    my $method = "GET";
    my $content = "";

    my $start = Time::HiRes::gettimeofday();

    while (1) {

        my $request = genreq($ref_rhevm, $method, $api, $content);
        my ($rc, $response) = send_req($ref_rhevm, $request->as_string());
    
        if ($rc) {
            return ($rc, $response);
        } else {
            my $parser = XML::LibXML->new();
            my $doc = $parser->parse_string($response);
            if ($doc ) {
                if ($target eq getAttr($doc, $path)) {
                    return 0;
                }
            }
        }

        my $now = Time::HiRes::gettimeofday();
        if (($now - $start) > $timeout) {
            return 2;
        } else {
            sleep (0.5);
        }
    }
    
    return 1;
}

# Get the vid prameters for external video console program to display console
sub getrvidparms {
    my $callback = shift;
    my $rhevm_hash = shift;
    my $nodes = shift;

    foreach my $rhevm (keys %{$rhevm_hash}) {
        my @nodes;
        # generate the hash of rhevm which will be used for the action functions
        my $ref_rhevm = {'name' => $rhevm, 
                                 'user' => $rhevm_hash->{$rhevm}->{user}, 
                                 'pw' => $rhevm_hash->{$rhevm}->{pw}};

        # generate the node that will be handled
        if (defined $rhevm_hash->{$rhevm}->{host}) {
            foreach my $rhevh (keys %{$rhevm_hash->{$rhevm}->{host}}) {
                if (defined $rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}) {
                    push @nodes, @{$rhevm_hash->{$rhevm}->{host}->{$rhevh}->{node}};
                }
            }
        }
        if (defined $rhevm_hash->{$rhevm}->{node}) {
             push @nodes, @{$rhevm_hash->{$rhevm}->{node}};
        }

        # perform the action against the node
        foreach my $node (@nodes) {
            my $node = $nodes->[0];
            my %consparam;
            $consparam{method} = 'kvm';
        
            # get the attributes for vm
            my ($rc, undef, undef, $response) = search_src($ref_rhevm, "vms", "$node");
        
            my $vmid;
            my $rsp;
            if ($rc) {
                $rsp->{node}->[0]->{errorcode} = $rc;
                $rsp->{node}->[0]->{name}->[0]=$node;
                $rsp->{node}->[0]->{error} = $response;
                $callback->($rsp);
                next;
            } else {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                if ($doc ) {
                    my $attr;
                    if ($attr = getAttr($doc, "/vms/vm", "id")) {
                        $vmid = $attr;
                    }
                    if ($attr = getAttr($doc, "/vms/vm/display/type")) {
                        $consparam{vidproto} = $attr;
                    }
                    if ($attr = getAttr($doc, "/vms/vm/display/address")) {
                        $consparam{server} = $attr;
                    }
                    if ($attr = getAttr($doc, "/vms/vm/display/port")) {
                        $consparam{vidport} = $attr;
                    }
                }
            }
        
            # get the password ticket for the external program to accesss the VNC
            my $api = "/api/vms/$vmid/ticket";
            my $method = "POST";
            my $content = "<action><ticket><expiry>120</expiry></ticket></action>";
        
            my $request = genreq($ref_rhevm, $method, $api, $content);
            ($rc, $response) = send_req($ref_rhevm, $request->as_string());
        
            if ($rc) {
                $rsp->{node}->[0]->{errorcode} = $rc;
                $rsp->{node}->[0]->{name}->[0]=$node;
                $rsp->{node}->[0]->{error} = $response;
                $callback->($rsp);
                next;
            } else {
                my $parser = XML::LibXML->new();
                my $doc = $parser->parse_string($response);
                if ($doc ) {
                    my $attr;
                    if ($attr = getAttr($doc, "/action/ticket/value")) {
                        $consparam{password} = $attr;
                    }    
                }
            }
        
            
            $rsp = ();
            $rsp->{node}->[0]->{name}->[0]=$node;
            foreach (keys %consparam) {
                $rsp->{node}->[0]->{data}->[0]->{desc}->[0] = $_;
                $rsp->{node}->[0]->{data}->[0]->{contents}->[0] = $consparam{$_};
                $callback->($rsp);
            }
        }
    }

    return;
}


1;    
