#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::kvm;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::GlobalDef;
use xCAT::NodeRange;
use xCAT::VMCommon;
use xCAT_monitoring::monitorctrl;

use xCAT::Table;
use XML::Simple qw(XMLout);
use Thread qw(yield);
use File::Basename qw/fileparse/;
use File::Path qw/mkpath/;
use IO::Socket;
use IO::Select;
use strict;
#use warnings;
my $use_xhrm=0; #xCAT Hypervisor Resource Manager, to satisfy networking and storage prerequisites, default to not using it for the moment
my $imgfmt='raw'; #use raw format by default
my $clonemethod='qemu-img'; #use qemu-img command
my %vm_comm_pids;
my %offlinehyps;
my %hypstats;
my %offlinevms;
my @destblacklist;
my $updatetable; #when a function is performing per-node operations, it can queue up a table update by populating parts of this hash
my $confdata; #a reference to serve as a common pointer betweer VMCommon functions and this plugin
my $libvirtsupport;
$libvirtsupport = eval { 
    require Sys::Virt; 
    if (Sys::Virt->VERSION < "0.2.0") {
        die;
    }
    1;
};

use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use IO::Select;
use IO::Handle;
use Time::HiRes qw(gettimeofday sleep);
use xCAT::DBobjUtils;
use Getopt::Long;
use xCAT::SvrUtils;

my %runningstates;
my $vmmaxp=64;
my $mactab;
my %usedmacs;
my $status_noop="XXXno-opXXX";

sub handled_commands {
  #unless ($libvirtsupport) {
  #    return {};
  #}
  return {
    rpower => 'nodehm:power,mgt',
    mkvm => 'nodehm:power,mgt',
    chvm => 'nodehm:power,mgt',
    rmigrate => 'nodehm:mgt',
    getcons => 'nodehm:mgt',
    #rvitals => 'nodehm:mgt',
    #rinv => 'nodehm:mgt',
    getrvidparms => 'nodehm:mgt',
    rbeacon => 'nodehm:mgt',
    revacuate => 'hypervisor:type',
    vmstatenotify => 'hypervisor:type',
    #rspreset => 'nodehm:mgt',
    #rspconfig => 'nodehm:mgt',
    #rbootseq => 'nodehm:mgt',
    #reventlog => 'nodehm:mgt',
  };
}

my $hypconn;
my $hyp;
my $doreq;
my %hyphash;
my $node;
my $vmtab;
my $kvmdatatab;


sub build_pool_xml {
    my $url = shift;
    my $mounthost = shift;
    unless ($mounthost) { $mounthost = $hyp; }
    my $pool;
    my $host = $url;
    $host =~ s/.*:\/\///;
    $host =~ s/(\/.*)//;
    my $srcpath = $1;
    my $uuid = xCAT::Utils::genUUID(url=>$url);
    my $pooldesc = '<pool type="netfs">';
    $pooldesc .= '<name>'.$url.'</name>'; #Hey, at least libvirt doesn't have stupid name restrictions...
    $pooldesc .= '<uuid>'.$uuid.'</uuid>>';
    $pooldesc .= '<source>';
    $pooldesc .= '<host name="'.$host.'"/>';
    $pooldesc .= '<dir path="'.$srcpath.'"/>';
    $pooldesc .= '</source>';
    $pooldesc .= '<target><path>/var/lib/xcat/pools/'.$uuid.'</path></target></pool>';
    system("ssh $mounthost mkdir -p /var/lib/xcat/pools/$uuid"); #ok, so not *technically* just building XML, but here is the cheapest
                                                            #place to know uuid...  And yes, we must be allowed to ssh in
                                                            #libvirt just isn't capable enough for this sort of usage
    return $pooldesc;
}



sub get_storage_pool_by_url {
    my $url = shift;
    my $virtconn = shift;
    my $mounthost = shift;
    unless ($virtconn) { $virtconn = $hypconn; }
    my @currpools = $virtconn->list_storage_pools();
    my $poolobj;
    my $pool;
    foreach my $poolo (@currpools) {
        $poolobj = $poolo;
        $pool = XMLin($poolobj->get_xml_description());
        if ($pool->{name} eq $url) {
            last;
        }
        $pool = undef;
    }
    if ($pool) { return $poolobj; }
    $poolobj = $virtconn->create_storage_pool(build_pool_xml($url,$mounthost));
    return $poolobj;
}

sub get_multiple_paths_by_url {
    my %args =@_;
    my $url = $args{url};
    my $node = $args{node};
    my $poolobj = get_storage_pool_by_url($url);
    unless ($poolobj) { die "Cound not get storage pool for $url"; }
    $poolobj->refresh(); #if volumes change on nfs storage, libvirt is too dumb to notice
    my @volobjs = $poolobj->list_volumes();
    my %paths;
    foreach (@volobjs) {
        if ($_->get_name() =~ /^$node\.([^\.]*)\.([^\.]*)$/) {
            $paths{$_->get_path()} = {device=>$1,format=>$2};
        } elsif ($_->get_name() =~ /^$node\.([^\.]*)$/) {
             $paths{$_->get_path()} = {device=>$1,format=>'raw'}; 
             #this requires any current user of qcow2 to migrate, unfortunate to escape
             #a vulnerability where raw user could write malicious qcow2 to header
             #and use that to get at files on the hypervisor os with escalated privilege
        }
    }
    return \%paths;
}
sub get_filepath_by_url { #at the end of the day, the libvirt storage api gives the following capability:
                          #mount, limited ls, and qemu-img
                          #it does not frontend mkdir, and does not abstract away any nitty-gritty detail, you must know:
                          #the real mountpoint, and the real full path to storage
                          #in addition to this, subdirectories are not allowed, and certain extra metadata must be created
                          #not a big fan compared to ssh and run the commands myself, but it's the most straightforward path
                          #to avoid ssh for users who dislike that style access
    my %args = @_;
    my $url = $args{url};
    my $dev = $args{dev};
    my $create = $args{create};
    my $force = $args{force};
    my $format = $args{format};
    unless ($format) {
        $format = 'qcow2';
    }
    #ok, now that we have the pool, we need the storage volume from the pool for the node/dev
    my $poolobj = get_storage_pool_by_url($url);
    unless ($poolobj) { die "Could not get storage pool for $url"; }
    $poolobj->refresh(); #if volumes change on nfs storage, libvirt is too dumb to notice
    my @volobjs = $poolobj->list_volumes();
    my $desiredname = $node.'.'.$dev.'.'.$format;
    foreach (@volobjs) {
        if ($_->get_name() eq $desiredname) {
            if ($create) {
                if ($force) { #must destroy the storage
                    $_->delete();
                } else {
                    die "Path already exists";
                }
            } else {
                return $_->get_path();
            }
        }
    }
    if ($create) { 
        if ($create =~ /^clone=/) {
        } else {
            my $vol = $poolobj->create_volume("<volume><name>".$desiredname."</name><target><format type='$format'/></target><capacity>".getUnits($create,"G",1)."</capacity><allocation>0</allocation></volume>");
            if ($vol) { return $vol->get_path(); }
        }
    } else {
        return undef;
    }
}

sub nodesockopen {
   my $node = shift;
   my $port = shift;
   unless ($node) { return 0; }
   my $socket;
   my $addr = gethostbyname($node);
   my $sin = sockaddr_in($port,$addr);
   my $proto = getprotobyname('tcp');
   socket($socket,PF_INET,SOCK_STREAM,$proto) || return 0;
   connect($socket,$sin) || return 0;
   return 1;
}


        
sub waitforack {
    my $sock = shift;
    my $select = new IO::Select;
    $select->add($sock);
    my $str;
    if ($select->can_read(60)) { # Continue after 10 seconds, even if not acked...
        if ($str = <$sock>) {
        } else {
           $select->remove($sock); #Block until parent acks data
        }
    }
}

sub build_oshash {
    my %rethash;
    $rethash{type}->{content}='hvm';
    if (defined $confdata->{vm}->{$node}->[0]->{bootorder}) {
        my $bootorder = $confdata->{vm}->{$node}->[0]->{bootorder};
        my @bootdevs = split(/[:,]/,$bootorder);
        my $bootnum = 0;
        foreach (@bootdevs) {
            if ("net" eq $_ or "n" eq $_) {
                $rethash{boot}->[$bootnum]->{dev}="network";
            } else {
                $rethash{boot}->[$bootnum]->{dev}=$_;
            }
            $bootnum++;
        }
    } else {
        $rethash{boot}->[0]->{dev}='network';
        $rethash{boot}->[1]->{dev}='hd';
    }
    return \%rethash;
}

sub build_diskstruct {
    my $cdloc=shift;
    my @returns=();
    my $currdev;
    my @suffixes=('a','b','d'..'z');
    my $suffidx=0;
    if ($cdloc) {
        my $cdhash;
        $cdhash->{device}='cdrom';
        if ($cdloc =~ /^\/dev/) {
            $cdhash->{type}='block';
        } else {
            $cdhash->{type}='file';
        }
        $cdhash->{source}->{file}=$cdloc;
        $cdhash->{readonly};
        $cdhash->{target}->{dev}='hdc';
        push @returns,$cdhash;
    }


    if (defined $confdata->{vm}->{$node}->[0]->{storage}) {
        my $disklocs=$confdata->{vm}->{$node}->[0]->{storage};
        my @locations=split /\|/,$disklocs; 
        foreach my $disk (@locations) {
            #Setting default values of a virtual disk backed by a file at hd*.
            my $diskhash;
            $disk =~ s/=(.*)//;
            my $model = $1;
            unless ($model) { $model = 'ide'; }
            my $prefix='hd';
            if ($model eq 'virtio') {
                $prefix='vd';
            } elsif ($model eq 'scsi') {
                $prefix='sd';
            }
            $diskhash->{type} = 'file';
            $diskhash->{device} = 'disk';
            $diskhash->{target}->{dev} = $prefix.$suffixes[$suffidx];
            $diskhash->{target}->{bus} = $model;

            my @disk_parts = split(/,/, $disk);
            #Find host file and determine if it is a file or a block device.
            if (substr($disk_parts[0], 0, 4) eq 'phy:') {
                $diskhash->{type}='block';
                $diskhash->{source}->{dev} = substr($disk_parts[0], 4);
            } elsif ($disk_parts[0] =~ m/^nfs:\/\/(.*)$/) {
                my %disks = %{get_multiple_paths_by_url(url=>$disk_parts[0],node=>$node)};
                unless (keys %disks) {
                    die "Unable to find any persistent disks at ".$disk_parts[0];
                }
                foreach (keys %disks) {
                    my $tdiskhash;
                    $tdiskhash->{type};
                    $tdiskhash->{device}='disk';
                    $tdiskhash->{driver}->{name}='qemu';
                    $tdiskhash->{driver}->{type}=$disks{$_}->{format};
                    $tdiskhash->{source}->{file}=$_;
                    $tdiskhash->{target}->{dev} = $disks{$_}->{device};
                    if ($disks{$_} =~ /^vd/) {
                        $tdiskhash->{target}->{bus} = 'virtio';
                    } elsif ($disks{$_} =~ /^hd/) {
                        $tdiskhash->{target}->{bus} = 'ide';
                    } elsif ($disks{$_} =~ /^sd/) {
                        $tdiskhash->{target}->{bus} = 'scsi';
                    }
                    push @returns,$tdiskhash;

                }
                next; #nfs:// skips the other stuff
                #$diskhash->{source}->{file} = get_filepath_by_url(url=>$disk_parts[0],dev=>$diskhash->{target}->{dev}); #"/var/lib/xcat/vmnt/nfs_".$1."/$node/".$diskhash->{target}->{dev};
            } else { #currently, this would be a bare file to slap in as a disk
                $diskhash->{source}->{file} = $disk_parts[0];
            }

            #See if there are any other options. If not, increment suffidx because the already determined device node was used.
            #evidently, we support specificying explicitly how to target the system..
            if (@disk_parts gt 1) {
                my @disk_opts = split(/:/, $disk_parts[1]);
                if ($disk_opts[0] ne '') {
                    $diskhash->{target}->{dev} = $disk_opts[0];
                } else {
                    $suffidx++;
                }
                if ($disk_opts[1] eq 'cdrom') {
                    $diskhash->{device}='cdrom';
                }
            } else {
                $suffidx++;
            }

            push @returns,$diskhash;
        }
    }
    return \@returns;
}
sub getNodeUUID {
    my $node = shift;
    if ($confdata->{vpd}->{$node}->[0] and $confdata->{vpd}->{$node}->[0]->{uuid}) {
        return $confdata->{vpd}->{$node}->[0]->{uuid};
    }
    if ($confdata->{mac}->{$node}->[0]->{mac}) { #a uuidv1 is possible, generate that for absolute uniqueness guarantee
        my $mac = $confdata->{mac}->{$node}->[0]->{mac};
        $mac =~ s/\|.*//;
        $mac =~ s/!.*//;
        $updatetable->{vpd}->{$node}={uuid=>xCAT::Utils::genUUID(mac=>$mac)};
    } else {
        $updatetable->{vpd}->{$node}={uuid=>xCAT::Utils::genUUID()};
    }
    return $updatetable->{vpd}->{$node};

}
sub build_nicstruct {
    my $rethash;
    my $node = shift;
    my @macs=();
    my @nics=();
    if ($confdata->{vm}->{$node}->[0]->{nics}) {
        @nics = split /,/,$confdata->{vm}->{$node}->[0]->{nics};
    } else {
        @nics = ('virbr0');
    }
    if ($confdata->{mac}->{$node}->[0]->{mac}) {
        my $macdata=$confdata->{mac}->{$node}->[0]->{mac};
        foreach my $macaddr (split /\|/,$macdata) {
            $macaddr =~ s/\!.*//;
            push @macs,$macaddr;
        }
    }
    unless (scalar(@macs) >= scalar(@nics)) {
        #TODO: MUST REPLACE WITH VMCOMMON CODE
        my $neededmacs=scalar(@nics) - scalar(@macs);
        my $macstr;
        my $tmac;
        my $leading;
        srand;
        while ($neededmacs--) {
            my $allbutmult = 65279; # & mask for bitwise clearing of the multicast bit of mac
            my $localad=512; # | to set the bit for locally admnistered mac address
            $leading=int(rand(65535)); 
            $leading=$leading|512;
            $leading=$leading&65279;
            my $n=inet_aton($node);
            my $tail;
            if ($n) {
               $tail=unpack("N",$n);
            }
            unless ($tail) {
                $tail=int(rand(4294967295));
            }
            $tmac = sprintf("%04x%08x",$leading,$tail);
            $tmac =~ s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
	    if ($usedmacs{$tmac}) { #If we have a collision we can actually perceive, retry the generation of this mac
		$neededmacs++;
		next;
            }
            $usedmacs{$tmac}=1;
            push @macs,$tmac;
        }
        #$mactab->setNodeAttribs($node,{mac=>join('|',@macs)});
        #$nrtab->setNodeAttribs($node,{netboot=>'pxe'});
        #$doreq->({command=>['makedhcp'],node=>[$node]});
    }
    my @rethashes;
    foreach (@macs) {
        my $rethash;
        my $nic = shift @nics;
        my $type = 'e1000'; #better default fake nic than rtl8139, relevant to most
        unless ($nic) {
            last; #Don't want to have multiple vnics tied to the same switch
        }
        $nic =~ s/.*://; #the detail of how the bridge was built is of no
                        #interest to this segment of code
        if ($nic =~ /=/) {
            ($nic,$type) = split /=/,$nic,2;
        }
        $rethash->{type}='bridge';
        $rethash->{mac}->{address}=$_;
        $rethash->{source}->{bridge}=$nic;
        $rethash->{model}->{type}=$type;
        push @rethashes,$rethash;
    }
    return \@rethashes;
}
sub getUnits {
    my $amount = shift;
    my $defunit = shift;
    my $divisor=shift;
    unless ($divisor) {
        $divisor = 1;
    }
    if ($amount =~ /(\D)$/) { #If unitless, add unit
        $defunit=$1;
        chop $amount;
    }
    if ($defunit =~ /k/i) {
        return $amount*1024/$divisor;
    } elsif ($defunit =~ /m/i) {
        return $amount*1048576/$divisor;
    } elsif ($defunit =~ /g/i) {
        return $amount*1073741824/$divisor;
    } 
}

sub build_xmldesc {
    my $node = shift;
    my $cdloc=shift;
    my %xtree=();
    $xtree{type}='kvm';
    $xtree{name}->{content}=$node;
    $xtree{uuid}->{content}=getNodeUUID($node);
    $xtree{os} = build_oshash();
    if (defined $confdata->{vm}->{$node}->[0]->{memory}) {
        $xtree{memory}->{content}=getUnits($confdata->{vm}->{$node}->[0]->{memory},"M",1024);
    } else {
        $xtree{memory}->{content}=524288;
    }
    if (defined $confdata->{vm}->{$node}->[0]->{cpus}) {
        $xtree{vcpu}->{content}=$confdata->{vm}->{$node}->[0]->{cpus};
    } else {
        $xtree{vcpu}->{content}=1;
    }
    if (defined ($confdata->{vm}->{$node}->[0]->{clockoffset})) {
        #If user requested a specific behavior, give it
        $xtree{clock}->{offset}=$confdata->{vm}->{$node}->[0]->{clockoffset};
    } else {
        #Otherwise, only do local time for things that look MS
        if (defined ($confdata->{nodetype}->{$node}->[0]->{os}) and $confdata->{nodetype}->{$node}->[0]->{os} =~ /win.*/) {
            $xtree{clock}->{offset}='localtime';
        } else { #For everyone else, utc is preferred generally
            $xtree{clock}->{offset}='utc';
        }
    }

    $xtree{features}->{pae}={};
    $xtree{features}->{acpi}={};
    $xtree{features}->{apic}={};
    $xtree{features}->{content}="\n";
    $xtree{devices}->{disk}=build_diskstruct($cdloc);
    $xtree{devices}->{interface}=build_nicstruct($node);
    #use content to force xml simple to not make model the 'name' of video
    $xtree{devices}->{video}= [ { 'content'=>'','model'=> {type=>'vga',vram=>8192}}];
    $xtree{devices}->{input}->{type}='tablet';
    $xtree{devices}->{input}->{bus}='usb';
    $xtree{devices}->{graphics}->{type}='vnc';
    $xtree{devices}->{console}->{type}='pty';
    $xtree{devices}->{console}->{target}->{port}='1';
    return XMLout(\%xtree,RootName=>"domain");
}

sub refresh_vm {
    my $dom = shift;

    my $newxml=XMLin($dom->get_xml_description());
    $updatetable->{kvm_nodedata}->{$node}={xml=>$newxml};
    my $vncport=$newxml->{devices}->{graphics}->{port};
    my $stty=$newxml->{devices}->{console}->{tty};
    $updatetable->{vm}->{$node}={vncport=>$vncport,textconsole=>$stty};
    #$vmtab->setNodeAttribs($node,{vncport=>$vncport,textconsole=>$stty});
    return {vncport=>$vncport,textconsole=>$stty};
}

sub getcons {
    my $node = shift();
    my $type = shift();
    my $dom;
    eval {
     $dom = $hypconn->get_domain_by_name($node);
    };
    unless ($dom) {
        return 1,"Unable to query running VM";
    }
    my $consdata=refresh_vm($dom);
    my $hyper=$confdata->{vm}->{$node}->[0]->{host};

    if ($type eq "text") {
        my $serialspeed;
        if ($confdata->{nodehm}) {
            $serialspeed=$confdata->{nodehm}->{$node}->[0]->{serialspeed};
        }
        my $sconsparms = {node=>[{name=>[$node]}]};
        $sconsparms->{node}->[0]->{sshhost}=[$hyper];
        $sconsparms->{node}->[0]->{psuedotty}=[$consdata->{textconsole}];
        $sconsparms->{node}->[0]->{baudrate}=[$serialspeed];
        return (0,$sconsparms);
    } elsif ($type eq "vnc") {
        return (0,'ssh+vnc@'.$hyper.": localhost:".$consdata->{vncport}); #$consdata->{vncport});
    }
}
sub getrvidparms {
    my $node=shift;
    my $location = getcons($node,"vnc");
    if ($location =~ /ssh\+vnc@([^:]*):([^:]*):(\d+)/) {
        my @output = (
        "method: kvm",
        "server: $1",
        "vncdisplay: $2:$3",
        "virturi: ".$hypconn->get_uri(),
        "virtname: $node",
        );
        return  0,@output;
    } else {
        return (1,"Error: Unable to determine rvid destination for $node");
    }
}

sub pick_target {
    my $node = shift;
    my $addmemory = shift;
    my $target;
    my $mostfreememory=undef;
    my $currentfreememory;
    my $candidates= $confdata->{vm}->{$node}->[0]->{migrationdest};
    my $currhyp=$confdata->{vm}->{$node}->[0]->{host};
#caching strategy is implicit on whether $addmemory is passed.
    unless ($candidates) {
        return undef;
    }
    foreach (noderange($candidates)) {
        my $targconn;
        my $cand=$_;
        if ($_ eq $currhyp) { next; } #skip current node
        if ($offlinehyps{$_}) { next }; #skip already offlined nodes
        if (grep { "$_" eq $cand } @destblacklist) { next; } #skip blacklisted destinations
        if ($addmemory and defined $hypstats{$_}->{freememory}) { #only used cache results when addmemory suggests caching can make sense
            $currentfreememory=$hypstats{$_}->{freememory}
        } else {
            if (not nodesockopen($_,22)) { $offlinehyps{$_}=1; next; } #skip unusable destinations
                eval {  #Sys::Virt has bugs that cause it to die out in weird ways some times, contain it here
                    $targconn = Sys::Virt->new(uri=>"qemu+ssh://root@".$_."/system?no_tty=1&netcat=nc");
                };
                unless ($targconn) {
                    eval {  #Sys::Virt has bugs that cause it to die out in weird ways some times, contain it here
                        $targconn = Sys::Virt->new(uri=>"qemu+ssh://root@".$_."/system?no_tty=1");
                    };
                }
            unless ($targconn) { next; } #skip unreachable destinations
            $currentfreememory=$targconn->get_node_info()->{memory};
            foreach ($targconn->list_domains()) {
                if ($_->get_name() eq 'Domain-0') { next; } #Dom0 memory usage is elastic, we are interested in HVM DomU memory, which is inelastic
    
                $currentfreememory -= $_->get_info()->{memory};
            }
            $hypstats{$cand}->{freememory}=$currentfreememory;
        }
        if ($addmemory and $addmemory->{$_}) {
            $currentfreememory -= $addmemory->{$_};
        }
        if (not defined ($mostfreememory)) {
            $mostfreememory=$currentfreememory;
            $target=$_;
        } elsif ($currentfreememory > $mostfreememory) {
            $mostfreememory=$currentfreememory;
            $target=$_;
        }
    }
    return $target;
}


sub migrate {
    $node = shift();
    my $targ = shift();
    if ($offlinevms{$node}) {
        return power("on");
    }
#TODO: currently, we completely serialize migration events.  Some IO fabrics can facilitate concurrent migrations
#One trivial example is an ethernet port aggregation where a single conversation may likely be unable to utilize all the links
#because traffic is balanced by a mac address hashing algorithim, but talking to several hypervisors would have
#distinct peers that can be balanced more effectively.
#The downside is that migration is sufficiently slow that a lot can change in the intervening time on a target hypervisor, but
#this should not be an issue if:
#xCAT is the only path a configuration is using to make changes in the virtualization stack
#xCAT implements a global semaphore mechanism that this plugin can use to assure migration targets do not change by our own hand..
#failing that.. flock.
    unless ($targ) {
        $targ = pick_target($node);
    }
    unless ($targ) {
        return (1,"Unable to identify a suitable target host for guest $node");
    }
    if ($use_xhrm) {
        xhrm_satisfy($node,$targ);
    }
    my $prevhyp;
    my $target = "qemu+ssh://root@".$targ."/system?no_tty=1";
    my $currhyp="qemu+ssh://root@";
    if ($confdata->{vm}->{$node}->[0]->{host}) {
        $prevhyp=$confdata->{vm}->{$node}->[0]->{host};
        $currhyp.=$prevhyp;
    } else {
        return (1,"Unable to find current location of $node");
    }
    $currhyp.="/system?no_tty=1";
    if ($currhyp eq $target) {
        return (0,"Guest is already on host $targ");
    }
    my $srchypconn;
    my $desthypconn;
    unless ($offlinehyps{$prevhyp} or nodesockopen($prevhyp,22)) {
        $offlinehyps{$prevhyp}=1;
    }
    my $srcnetcatadd="&netcat=nc";
    unless ($offlinehyps{$prevhyp}) {
        eval {#Contain Sys::Virt bugs
            $srchypconn= Sys::Virt->new(uri=>"qemu+ssh://root@".$prevhyp."/system?no_tty=1$srcnetcatadd");
        };
        unless ($srchypconn) {
            $srcnetcatadd="";
            eval {#Contain Sys::Virt bugs
                $srchypconn= Sys::Virt->new(uri=>"qemu+ssh://root@".$prevhyp."/system?no_tty=1");
            };
        }
    }
    unless ($srchypconn) {
        return (1,"Unable to reach $prevhyp to perform operation of $node, use nodech to change vm.host if certain of no split-brain possibility exists");
    }
    unless ($offlinehyps{$targ} or nodesockopen($targ,22)) {
        $offlinehyps{$targ}=1;
    }
    my $destnetcatadd="&netcat=nc";
    unless ($offlinehyps{$targ}) {
        eval {#Contain Sys::Virt bugs
            $desthypconn= Sys::Virt->new(uri=>$target.$destnetcatadd);
        };
        unless ($desthypconn) {
            $destnetcatadd="";
            eval {#Contain Sys::Virt bugs
                $desthypconn= Sys::Virt->new(uri=>$target);
            };
        }
    }
    unless ($desthypconn) {
        return (1,"Unable to reach $targ to perform operation of $node, destination unusable.");
    }
    if (defined $confdata->{vm}->{$node}->[0]->{storage} and $confdata->{vm}->{$node}->[0]->{storage} =~ /^nfs:/) {
        my $urls =  $confdata->{vm}->{$node}->[0]->{storage} and $confdata->{vm}->{$node}->[0]->{storage};
        foreach (split /,/,$urls) {
            s/=.*//;
            get_storage_pool_by_url($_,$desthypconn,$targ);
        }
    }
    my $sock = IO::Socket::INET->new(Proto=>'udp');
    my $ipa=inet_aton($node);
    my $pa;
    if ($ipa) {
        $pa=sockaddr_in(7,$ipa); #UDP echo service, not needed to be actually
    }
    #serviced, we just want to trigger MAC move in the switch forwarding dbs
    my $nomadomain;
    eval { 
        $nomadomain = $srchypconn->get_domain_by_name($node);
    };
    unless ($nomadomain) {
        return (1,"Unable to find $node on $prevhyp, vm.host may be incorrect or a split-brain condition, such as libvirt forgetting a guest due to restart or bug.");
    }
    my $newdom;
    my $errstr;
    eval {
        $newdom=$nomadomain->migrate($desthypconn,&Sys::Virt::Domain::MIGRATE_LIVE,undef,undef,0);
    };
    if ($@) { $errstr = $@; }
#TODO: If it looks like it failed to migrate, ensure the guest exists only in one place
    if ($errstr) { 
        return (1,"Failed migration of $node from $prevhyp to $targ: $errstr");
    }
    unless ($newdom) {
        return (1,"Failed migration from $prevhyp to $targ");
    }
    if ($ipa) {
        system("arp -d $node"); #Make ethernet fabric take note of change
        send($sock,"dummy",0,$pa);  #UDP packet to force forwarding table update in switches, ideally a garp happened, but just in case...
    }
    #BTW, this should all be moot since the underlying kvm seems good about gratuitous traffic, but it shouldn't hurt anything
    refresh_vm($newdom);
    #The migration seems tohave suceeded, but to be sure...
    close($sock);
    if ($desthypconn->get_domain_by_name($node)) {
        #$updatetable->{vm}->{$node}->{host} = $targ;
        $vmtab->setNodeAttribs($node,{host=>$targ});
        return (0,"migrated to $targ");
    } else { #This *should* not be possible
        return (1,"Failed migration from $prevhyp to $targ, despite normal looking run...");
    }
}


sub getpowstate {
    my $dom = shift;
    my $vmstat;
    if ($dom) {
        $vmstat = $dom->get_info;
    }
    if ($vmstat and $runningstates{$vmstat->{state}}) {
        return "on";
    } else {
        return "off";
    }
}

sub xhrm_satisfy {
    my $node = shift;
    my $hyp = shift;
    my $rc=0;
    my @nics=();
    my @storage=();
    if ($confdata->{vm}->{$node}->[0]->{nics}) {
        @nics = split /,/,$confdata->{vm}->{$node}->[0]->{nics};
    }
    foreach (@nics) {
        s/=.*//; #this code cares not about the model of virtual nic
        $rc |=system("ssh $hyp xHRM bridgeprereq $_");
    }
    return $rc;
}
sub makedom {
    my $node=shift;
    my $cdloc = shift;
    my $dom;
    my $xml;
    if ($confdata->{kvmnodedata}->{$node}) {
        $xml = $confdata->{kvmnodedata}->{$node}->[0];
    } else {
        $xml = build_xmldesc($node,$cdloc);
    }
    my $errstr;
    eval { $dom=$hypconn->create_domain($xml); };
    if ($@) { $errstr = $@; }
    if (ref $errstr) {
       $errstr = ":".$errstr->{message};
    }
    if ($errstr) { return (undef,$errstr); }
    if ($dom) {
           refresh_vm($dom);
    }
    return $dom,undef;
}

sub createstorage {
#svn rev 6638 held the older vintage of createstorage
    my $filename=shift;
    my $mastername=shift;
    my $size=shift;
    my $cfginfo = shift;
    my $force = shift;
    #my $diskstruct = shift;
    my $node = $cfginfo->{node};
    my @flags = split /,/,$cfginfo->{virtflags};
    foreach (@flags) {
        if (/^imageformat=(.*)\z/) {
            $imgfmt=$1;
        } elsif (/^clonemethod=(.*)\z/) {
            $clonemethod=$1;
        }
    }
    my $mountpath;
    my $pathappend;


    #for nfs paths and qemu-img, we do the magic locally only for now
    my $basename;
    my $dirname;
    if ($mastername and $size) {
        return 1,"Can not specify both a master to clone and size(s)";
    }
    $filename=~s/=(.*)//;
    my $model=$1;
    my $prefix='hd';
    if ($model eq 'scsi') {
        $prefix='sd';
    } elsif ($model eq 'virtio') {
        $prefix='vd';
    }
    my @suffixes=('a','b','d'..'z');
    if ($filename =~ /^nfs:/) { #libvirt storage pool to be used for this
        my @sizes = split /,/,$size;
        foreach (@sizes) {
            get_filepath_by_url(url=>$filename,dev=>$prefix.shift(@suffixes),create=>$_);
        }
    }
    my $masterserver;
    if ($mastername) { #cloning
    }
    if ($size) {#new volume
    }
}



sub chvm {
    shift;
    my @addsizes;
    my %resize;
    my $cpucount;
    my @purge;
    my @derefdisks;
    my $memory;
    @ARGV=@_;
    require Getopt::Long;
    GetOptions(
        "a=s"=>\@addsizes,
        "d=s"=>\@derefdisks,
        "mem=s"=>\$memory,
        "p=s"=>\@purge,
        "resize=s%" => \%resize,
        "cpu=s" => \$cpucount,
        );
    my %useddisks;
    if (defined $confdata->{vm}->{$node}->[0]->{storage}) {
        my $store;
        foreach $store (split /\|/, $confdata->{vm}->{$node}->[0]->{storage}) {
            $store =~ s/,.*//;
            $store =~ s/=.*//;
            if ($store =~ /^nfs:\/\//) {
                my %disks = %{get_multiple_paths_by_url(url=>$store,node=>$node)};
                foreach (keys %disks) {
                    $useddisks{$disks{$_}->{device}}=1;
                }
            }
        }
    }
    if (@addsizes) { #need to add disks, first identify used devnames
        my @diskstoadd;
        my $location = $confdata->{vm}->{$node}->[0]->{storage};
        $location =~ s/.*\|//; #use the rightmost location for making new devices
        $location =~ s/,.*//; #no comma specified parameters are valid
        $location =~ s/=(.*)//; #store model if specified here
        my $model = $1;
        my $prefix='hd';
        if ($model eq 'scsi') {
            $prefix='sd';
        } elsif ($model eq 'virtio') {
            $prefix='vd';
        }
        my @suffixes;
        if ($prefix eq 'hd') { 
            @suffixes=('a','b','d'..'z');
        } else {
            @suffixes=('a'..'z');
        }
        my @newsizes;
        foreach (@addsizes) {
            push @newsizes,split /,/,$_;
        }
        foreach (@newsizes) {
            my $dev;
            do {
                $dev = $prefix.shift(@suffixes);
            } while ($useddisks{$dev});
            #ok, now I need a volume created to attach
            push @diskstoadd,get_filepath_by_url(url=>$location,dev=>$dev,create=>$_);
        }
        #now that the volumes are made, must build xml for each and attempt attach if and only if the VM is live
        my $dom = $hypconn->get_domain_by_name($node);
        my $currstate=getpowstate($dom);
        if ($currstate eq 'on') { #attempt live attach
            foreach (@diskstoadd) {
                my $suffix;
                my $format;
                if (/^[^\.]*\.([^\.]*)\.([^\.]*)/) {
                    $suffix=$1;
                    $format=$2;
                } elsif (/^[^\.]*\.([^\.]*)/) {
                    $suffix=$1;
                    $format='raw';
                }
                my $bus;
                if ($suffix =~ /^sd/) {
                    $bus='scsi';
                } elsif ($suffix =~ /^hd/) {
                    sendmsg("Reboot required to add IDE drives",$node);
                    next;
                } elsif ($suffix =~ /vd/) {
                    $bus='virtio';
                }
                my $xml = "<disk type='file' device='disk'><driver name='qemu' type='$format'/><source file='$_'/><target dev='$suffix' bus='$bus'/></disk>";
                $dom->attach_device($xml);
            }
            my $newxml=XMLin($dom->get_xml_description());
            $updatetable->{kvm_nodedata}->{$node}={xml=>$newxml};
        } else { #TODO: chvm to modify offline xml structure
        }
    } elsif (@purge) {
        my $dom = $hypconn->get_domain_by_name($node);
        my $vmxml=$dom->get_xml_description();
        my $currstate=getpowstate($dom);
        foreach (get_disks_by_userspecs(\@purge,$vmxml)) {
            my $devxml=$_->[0];
            my $file=$_->[1];
            $file =~ m!/([^/]*)/($node\..*)\z!;
            my $pooluuid=$1;
            my $volname=$2;
            #first, detach the device.
            eval {
            if ($currstate eq 'on') { 
                $dom->detach_device($devxml); 
                my $newxml=XMLin($dom->get_xml_description());
                $updatetable->{kvm_nodedata}->{$node}={xml=>$newxml};
            } else {
                #TODO: manipulate offline xml data
            }
            };
            if ($@) {
                sendmsg([1,"Unable to remove device"],$node);
            } else {
                #if that worked, remove the disk..
                my $pool = $hypconn->get_storage_pool_by_uuid($pooluuid);
                if ($pool) {
                    $pool->refresh(); #Amazingly, libvirt maintains a cached view of the volume rather than scan on demand
                    my $vol = $pool->get_volume_by_name($volname);
                    if ($vol) {
                        $vol->delete();
                    }
                }
                
            }

        }
    }

}
sub get_disks_by_userspecs {
    my $specs = shift;
    my $xml = shift;
    my $struct = XMLin($xml);
    my @returnxmls;
    foreach my $spec (@$specs) {
        foreach (@{$struct->{devices}->{disk}}) {
            if ($spec =~ /^.d./) { #vda, hdb, sdc, etc, match be equality to target->{dev}
                if ($_->{target}->{dev} eq $spec) {
                    push @returnxmls,[XMLout($_,RootName=>'disk'),$_->{source}->{file}];
                }
            } elsif ($spec =~ /^d(.*)/) { #delete by scsi unit number..
            if ($_->{address}->{unit} == $1) {
                    push @returnxmls,[XMLout($_,RootName=>"disk"),$_->{source}->{file}];
                }
            } #other formats TBD
        }
    }
    return @returnxmls;
}

sub mkvm {
 shift; #Throuw away first argument
 @ARGV=@_;
 my $disksize;
 my $mastername;
 my $force=0;
 require Getopt::Long;
 GetOptions(
    'master|m=s'=>\$mastername,
    'size|s=s'=>\$disksize,
    'force|f'=>\$force
 );
 if (defined $confdata->{vm}->{$node}->[0]->{storage}) {
    my $diskname=$confdata->{vm}->{$node}->[0]->{storage};
    if ($diskname =~ /^phy:/) { #in this case, mkvm should have no argumens
        if ($mastername or $disksize) {
            return 1,"mkvm management of block device storage not implemented";
        }
    }
    if ($mastername or $disksize) {
       return createstorage($diskname,$mastername,$disksize,$confdata->{vm}->{$node}->[0],$force);
    }
 } else {
     if ($mastername or $disksize) {
         return 1,"Requested initialization of storage, but vm.storage has no value for node";
     }
 }
}
sub power {
    @ARGV=@_;
    require Getopt::Long;
    my $cdloc;
    GetOptions('cdrom|iso|c|i=s'=>\$cdloc);
    my $subcommand = shift @ARGV;
    my $retstring;
    my $dom;
    eval {
     $dom = $hypconn->get_domain_by_name($node);
    };
    if ($subcommand eq "boot") {
        my $currstate=getpowstate($dom);
        $retstring=$currstate." ";
        if ($currstate eq "off") {
            $subcommand="on";
        } elsif ($currstate eq "on") {
            $subcommand="reset";
        }
    }
    my $errstr;
    if ($subcommand eq 'on') {
        unless ($dom) {
            if ($use_xhrm) {
                if (xhrm_satisfy($node,$hyp)) {
			return (1,"Failure satisfying networking and storage requirements on $hyp for $node");
		} 
            }
            ($dom,$errstr) = makedom($node,$cdloc);
            if ($errstr) { return (1,$errstr); }
        } else {
          $retstring .= "$status_noop";
        }
    } elsif ($subcommand eq 'off') {
        if ($dom) {
            $dom->destroy();
            undef $dom;
        } else { $retstring .= "$status_noop"; }
    } elsif ($subcommand eq 'softoff') {
        if ($dom) {
            $dom->shutdown();
        } else { $retstring .= "$status_noop"; } 
    } elsif ($subcommand eq 'reset') {
        if ($dom) {
            $dom->destroy();
            undef $dom;
            if ($use_xhrm) {
                xhrm_satisfy($node,$hyp);
            }
            ($dom,$errstr) = makedom($node,$cdloc);
            if ($errstr) { return (1,$errstr); }
            $retstring.="reset";
        } else { $retstring .= "$status_noop"; } 
    } else { 
        unless ($subcommand =~ /^stat/) {
            return (1,"Unsupported power directive '$subcommand'");
        }
    }

    unless ($retstring =~ /reset/) {
        $retstring=$retstring.getpowstate($dom);
    }
    return (0,$retstring);
}


sub guestcmd {
  $hyp = shift;
  $node = shift;
  my $command = shift;
  my @args = @_;
  my $error;
  if ($command eq "rpower") {
    return power(@args);
  } elsif ($command eq "mkvm") {
      return mkvm($node,@args);
  } elsif ($command eq "chvm") {
      return chvm($node,@args);
  } elsif ($command eq "rmigrate") {
      return migrate($node,@args);
  } elsif ($command eq "getrvidparms") {
      return getrvidparms($node,@args);
  } elsif ($command eq "getcons") {
      return getcons($node,@args);
  }
=cut
  } elsif ($command eq "rvitals") {
    return vitals(@args);
  } elsif ($command =~ /r[ms]preset/) {
    return resetmp(@args);
  } elsif ($command eq "rspconfig") {
    return mpaconfig($mpa,$user,$pass,$node,$slot,@args);
  } elsif ($command eq "rbootseq") {
    return bootseq(@args);
  } elsif ($command eq "switchblade") {
     return switchblade(@args);
  } elsif ($command eq "getmacs") {
    return getmacs(@args);
  } elsif ($command eq "rinv") {
    return inv(@args);
  } elsif ($command eq "reventlog") {
    return eventlog(@args);
  } elsif ($command eq "rscan") {
    return rscan(\@args);
  }
  
=cut
  return (1,"$command not a supported command by kvm method");
}

sub preprocess_request { 
  my $request = shift;
  if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
  my $callback=shift;
  my @requests;

  my $noderange = $request->{node}; #Should be arrayref
  my $command = $request->{command}->[0];
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }

  my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
  if ($usage_string) {
    $callback->({data=>$usage_string});
    $request = {};
    return;
  }

  if (!$noderange) {
    $usage_string=xCAT::Usage->getUsage($command);
    $callback->({data=>$usage_string});
    $request = {};
    return;
  }   
  
  #print "noderange=@$noderange\n";

  # find service nodes for requested nodes
  # build an individual request for each service node
  my $service  = "xcat";
  my $sn = xCAT::Utils->get_ServiceNode($noderange, $service, "MN");

  # build each request for each service node

  foreach my $snkey (keys %$sn)
  {
    #print "snkey=$snkey\n";
    my $reqcopy = {%$request};
    $reqcopy->{node} = $sn->{$snkey};
    $reqcopy->{'_xcatdest'} = $snkey;
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    push @requests, $reqcopy;
  }
  return \@requests;
}
 
    
sub adopt {
    my $orphash = shift;
    my $hyphash = shift;
    my %addmemory = ();
    my $node;
    my $target;
    my $vmupdates;
    foreach $node (keys %{$orphash}) {
        $target=pick_target($node,\%addmemory);
        unless ($target) {
            next;
        }
        if ($confdata->{vm}->{$node}->[0]->{memory}) {
            $addmemory{$target}+=getUnits($confdata->{vm}->{$node}->[0]->{memory},"M",1024);
        } else {
            $addmemory{$target}+=getUnits("512","M",1024);
        }
        $hyphash{$target}->{nodes}->{$node}=1;
        delete $orphash->{$node};
        $vmupdates->{$node}->{host}=$target;
    }
    $vmtab->setNodesAttribs($vmupdates);
    if (keys %{$orphash}) {
        return 0;
    } else { 
        return 1;
    }
}

sub process_request { 
  $SIG{INT} = $SIG{TERM} = sub { 
     foreach (keys %vm_comm_pids) {
        kill 2, $_;
     }
     exit 0;
  };
  %offlinehyps=();
  %hypstats=();
  %offlinevms=();
  my $request = shift;
  my $callback = shift;
  unless ($libvirtsupport) {
      $libvirtsupport = eval { 
      require Sys::Virt; 
      if (Sys::Virt->VERSION < "0.2.0") {
          die;
      }
      1;
      };
  }
  unless ($libvirtsupport) { #Still no Sys::Virt module
      $callback->({error=>"Sys::Virt perl module missing or older than 0.2.0, unable to fulfill KVM plugin requirements",errorcode=>[42]});
      return [];
  }
  require Sys::Virt::Domain;
  %runningstates = (&Sys::Virt::Domain::STATE_NOSTATE=>1,&Sys::Virt::Domain::STATE_RUNNING=>1,&Sys::Virt::Domain::STATE_BLOCKED=>1);

  $doreq = shift;
  my $level = shift;
  my $noderange = $request->{node};
  my $command = $request->{command}->[0];
  my @exargs;
  unless ($command) {
     return; #Empty request
  }
  if (ref($request->{arg})) {
    @exargs = @{$request->{arg}};
  } else {
    @exargs = ($request->{arg});
  }
  my $forcemode = 0;
  my %orphans=();
  if ($command eq 'vmstatenotify') {
      unless ($vmtab) { $vmtab = new xCAT::Table('vm',-create=>1); }
      my $state = $exargs[0];
      if ($state eq 'vmoff') {
          $vmtab->setNodeAttribs($exargs[1],{powerstate=>'off'});
          return;
      } elsif ($state eq 'vmon') {
          $vmtab->setNodeAttribs($exargs[1],{powerstate=>'on'});
          return;
      } elsif ($state eq 'hypshutdown') { #turn this into an evacuate
          my $nodelisttab = xCAT::Table->new('nodelist');
          my $appstatus = $nodelisttab->getNodeAttribs($noderange->[0],['appstatus']);
          my @apps =split /,/,$appstatus->{'appstatus'};
          my @newapps;
          foreach (@apps) {
              if ($_ eq 'virtualization') { next; }
              push @newapps,$_;
          }
          $nodelisttab->setNodeAttribs($noderange->[0],{appstatus=>join(',',@newapps)});
          $command="revacuate";
          @exargs=();
      } elsif ($state eq 'hypstartup') { #if starting up, check for nodes on this hypervisor and start them up
          my $nodelisttab = xCAT::Table->new('nodelist');
          my $appstatus = $nodelisttab->getNodeAttribs($noderange->[0],['appstatus']);
          my @apps =split /,/,$appstatus->{appstatus};
          unless (grep {$_ eq 'virtualization'} @apps) {
              push @apps,'virtualization';
              $nodelisttab->setNodeAttribs($noderange->[0],{appstatus=>join(',',@apps)});
          }
          my @tents = $vmtab->getAttribs({host=>$noderange->[0],power=>'on'},['node']);
          $noderange=[];
          foreach (@tents) {
              push @$noderange,noderange($_->{node});
          }
          $command="rpower";
          @exargs=("on");
      }

  }
  if ($command eq 'revacuate') {
      my $newnoderange;
      if (grep { $_ eq '-f' } @exargs) {
          $forcemode=1;
      }
      foreach (@$noderange) {
        my $hyp = $_; #I used $_ too much here... sorry
        $hypconn=undef;
        push @destblacklist,$_;
        if ((not $offlinehyps{$_}) and nodesockopen($_,22)) {
            eval { #Contain bugs that won't be in $@
                $hypconn= Sys::Virt->new(uri=>"qemu+ssh://root@".$_."/system?no_tty=1&netcat=nc");
            };
            unless ($hypconn) { #retry for socat
                eval { #Contain bugs that won't be in $@
                    $hypconn= Sys::Virt->new(uri=>"qemu+ssh://root@".$_."/system?no_tty=1");
                };
            }
        }
        unless ($hypconn)  {
            $offlinehyps{$hyp}=1;
            if ($forcemode) { #forcemode indicates the hypervisor is probably already dead, and to clear vm.host of all the nodes, and adopt the ones that are supposed to be 'on', power them on
                unless ($vmtab) { $vmtab = new xCAT::Table('vm',-create=>0); }
                unless ($vmtab) { next; }
                my @vents = $vmtab->getAttribs({host=>$hyp},['node','powerstate']);
                my $vent;
                my $nodestozap;
                foreach $vent (@vents) {
                    my @nodes = noderange($vent->{node});
                    if ($vent->{powerstate} eq 'on') {
                        foreach (@nodes) { 
                            $offlinevms{$_}=1;
                            $orphans{$_}=1; 
                            push @$newnoderange,$_;
                        }
                    }
                    push @$nodestozap,@nodes;
                }
                $vmtab->setNodesAttribs($nodestozap,{host=>'|^.*$||'});
            } else {
                $callback->({node=>[{name=>[$_],error=>["Cannot communicate via libvirt to node"]}]});
            }
            next;
        }
        if ($hypconn) {
            foreach ($hypconn->list_domains()) {
                my $guestname = $_->get_name();
                if ($guestname eq 'Domain-0') {
                    next;
                }
                push @$newnoderange,$guestname;
            }
        }
      }
      $hypconn=undef;
      $noderange = $newnoderange;
      $command = 'rmigrate';
  }

  my $sitetab = xCAT::Table->new('site');
  if ($sitetab) {
      my $xhent = $sitetab->getAttribs({key=>'usexhrm'},['value']);
      if ($xhent and $xhent->{value} and $xhent->{value} !~ /no/i and $xhent->{value} !~ /disable/i) {
          $use_xhrm=1;
      }
  }
  $vmtab = xCAT::Table->new("vm");
  $confdata={};
  xCAT::VMCommon::grab_table_data($noderange,$confdata,$callback);
  $kvmdatatab = xCAT::Table->new("kvm_nodedata",-create=>0); #grab any pertinent pre-existing xml
  if ($kvmdatatab) {
      $confdata->{kvmnodedata} = $kvmdatatab->getNodesAttribs($noderange,[qw/xml/]);
  } else {
      $confdata->{kvmnodedata} = {};
  }
  if ($command eq 'mkvm' or $command eq 'rpower' and (grep { "$_" eq "on"  or $_ eq "boot" or $_ eq "reset" } @exargs)) {
      xCAT::VMCommon::requestMacAddresses($confdata,$noderange);
      my @dhcpnodes;
      foreach (keys %{$confdata->{dhcpneeded}}) {
        push @dhcpnodes,$_;
        delete $confdata->{dhcpneeded}->{$_};
     }
     $doreq->({command=>['makedhcp'],node=>\@dhcpnodes});
  }

  if ($command eq 'revacuate' or $command eq 'rmigrate') {
      $vmmaxp=1; #for now throttle concurrent migrations, requires more sophisticated heuristics to ensure sanity
  } else {
      my $tmp;
      if ($sitetab) {
        ($tmp)=$sitetab->getAttribs({'key'=>'vmmaxp'},'value');
        if (defined($tmp)) { $vmmaxp=$tmp->{value}; }
      }
  }

  my $children = 0;
  $SIG{CHLD} = sub { my $cpid; while (($cpid = waitpid(-1, WNOHANG)) > 0) { if ($vm_comm_pids{$cpid}) { delete $vm_comm_pids{$cpid}; $children--; } } };
  my $inputs = new IO::Select;;
  my $sub_fds = new IO::Select;
  %hyphash=();
  foreach (keys %{$confdata->{vm}}) {
      if ($confdata->{vm}->{$_}->[0]->{host}) {
          $hyphash{$confdata->{vm}->{$_}->[0]->{host}}->{nodes}->{$_}=1;
      } else {
          $orphans{$_}=1;
      }
  }
  if (keys %orphans) {
      if ($command eq "rpower") {
          if (grep /^on$/,@exargs or grep /^boot$/,@exargs) {
            unless (adopt(\%orphans,\%hyphash)) {
                $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
                return 1;
              }
          } else {
              foreach (keys %orphans) {
                  $callback->({node=>[{name=>[$_],data=>[{contents=>['off']}]}]});
              }
          }
      } elsif ($command eq "rmigrate") {
          if ($forcemode) {
            unless (adopt(\%orphans,\%hyphash)) {
                $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
                return 1;
              }
          } else {
            $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
            return;
          }
      } elsif ($command eq "mkvm") { #must adopt to create
            unless (adopt(\%orphans,\%hyphash)) {
                $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
                return 1;
              }
          #mkvm used to be able to happen devoid of any hypervisor, make a fake hypervisor entry to allow this to occur
          #commenting that out for now
#          foreach (keys %orphans) {
#              $hyphash{'!@!XCATDUMMYHYPERVISOR!@!'}->{nodes}->{$_}=1;
#          }
      } else {
          $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
          return;
      }
  }
  if ($command eq "rbeacon") {
      my %req=();
      $req{command}=['rbeacon'];
      $req{arg}=\@exargs;
      $req{node}=[keys %hyphash];
      $doreq->(\%req,$callback);
      return;
  }

  #get new node status
  my %oldnodestatus=(); #saves the old node status
  my @allerrornodes=();
  my $check=0;
  my $global_check=1;
  if ($sitetab) {
    (my $ref) = $sitetab->getAttribs({key => 'nodestatus'}, 'value');
    if ($ref) {
       if ($ref->{value} =~ /0|n|N/) { $global_check=0; }
    }
  }


  if ($command eq 'rpower') {
    my $subcommand=$exargs[0];
    if (($global_check) && ($subcommand ne 'stat') && ($subcommand ne 'status')) { 
      $check=1; 
      my @allnodes=@$noderange;

      #save the old status
      my $nodelisttab = xCAT::Table->new('nodelist');
      if ($nodelisttab) {
        my $tabdata     = $nodelisttab->getNodesAttribs(\@allnodes, ['node', 'status']);
        foreach my $node (@allnodes)
        {
            my $tmp1 = $tabdata->{$node}->[0];
            if ($tmp1) { 
		if ($tmp1->{status}) { $oldnodestatus{$node}=$tmp1->{status}; }
		else { $oldnodestatus{$node}=""; }
	    }
	}
      }
      #print "oldstatus:" . Dumper(\%oldnodestatus);
      
      #set the new status to the nodelist.status
      my %newnodestatus=(); 
      my $newstat;
      if (($subcommand eq 'off') || ($subcommand eq 'softoff')) { 
	  my $newstat=$::STATUS_POWERING_OFF; 
	  $newnodestatus{$newstat}=\@allnodes;
      } else {
        #get the current nodeset stat
        if (@allnodes>0) {
	  my $nsh={};
          my ($ret, $msg)=xCAT::SvrUtils->getNodesetStates(\@allnodes, $nsh);
          if (!$ret) { 
            foreach (keys %$nsh) {
		my $newstat=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($_, "rpower");
		$newnodestatus{$newstat}=$nsh->{$_};
	    }
	  } else {
	      $callback->({data=>$msg});
	  }
        }
      }
      #print "newstatus" . Dumper(\%newnodestatus);
      xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
    }
  }

  my $sent = $sitetab->getAttribs({key=>'masterimgdir'},'value');
  if ($sent) {
    $xCAT_plugin::kvm::masterdir=$sent->{value};
  }



  foreach $hyp (sort (keys %hyphash)) {
    while ($children > $vmmaxp) { 
      my $handlednodes={};
      forward_data($callback,$sub_fds,$handlednodes);
      #update the node status to the nodelist.status table
      if ($check) {
        updateNodeStatus($handlednodes, \@allerrornodes);
      }
    }
    $children++;
    my $cfd;
    my $pfd;
    socketpair($pfd, $cfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
    $cfd->autoflush(1);
    $pfd->autoflush(1);
    my $cpid = xCAT::Utils->xfork;
    unless (defined($cpid)) { die "Fork error"; }
    unless ($cpid) {
      close($cfd);
      dohyp($pfd,$hyp,$command,-args=>\@exargs);
      exit(0);
    }
    $vm_comm_pids{$cpid} = 1;
    close ($pfd);
    $sub_fds->add($cfd);
  }
  while ($sub_fds->count > 0 or $children > 0) {
    my $handlednodes={};
    forward_data($callback,$sub_fds,$handlednodes);
    #update the node status to the nodelist.status table
    if ($check) {
      updateNodeStatus($handlednodes, \@allerrornodes);
    }
  }

  #Make sure they get drained, this probably is overkill but shouldn't hurt
  my $rc=1;
  while ( $rc>0 ) {
    my $handlednodes={};
    $rc=forward_data($callback,$sub_fds,$handlednodes);
    #update the node status to the nodelist.status table
    if ($check) {
      updateNodeStatus($handlednodes, \@allerrornodes);
    }
  } 

  if ($check) {
      #print "allerrornodes=@allerrornodes\n";
      #revert the status back for there is no-op for the nodes
      my %old=(); 
      foreach my $node (@allerrornodes) {
	  my $stat=$oldnodestatus{$node};
	  if (exists($old{$stat})) {
	      my $pa=$old{$stat};
	      push(@$pa, $node);
	  }
	  else {
	      $old{$stat}=[$node];
	  }
      } 
      xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%old, 1);
  }   
}

sub updateNodeStatus {
  my $handlednodes=shift;
  my $allerrornodes=shift;
  foreach my $node (keys(%$handlednodes)) {
    if ($handlednodes->{$node} == -1) { push(@$allerrornodes, $node); }  
  }
}

sub forward_data {
  my $callback = shift;
  my $fds = shift;
  my $errornodes=shift;
  my @ready_fds = $fds->can_read(1);
  my $rfh;
  my $rc = @ready_fds;
  foreach $rfh (@ready_fds) {
    my $data;
    if ($data = <$rfh>) {
      while ($data !~ /ENDOFFREEZE6sK4ci/) {
        $data .= <$rfh>;
      }
      eval { print $rfh "ACK\n"; }; #ignore failures to send inter-process ack
      my $responses=thaw($data);
      foreach (@$responses) {
        #save the nodes that has errors and the ones that has no-op for use by the node status monitoring
        my $no_op=0;
        if ($_->{node}->[0]->{errorcode}) { $no_op=1; }
        else { 
          my $text=$_->{node}->[0]->{data}->[0]->{contents}->[0];
          #print "data:$text\n";
          if (($text) && ($text =~ /$status_noop/)) {
	    $no_op=1;
            #remove the symbols that meant for use by node status
            $_->{node}->[0]->{data}->[0]->{contents}->[0] =~ s/$status_noop//; 
          }
        }  
	#print "data:". $_->{node}->[0]->{data}->[0]->{contents}->[0] . "\n";
        if ($no_op) {
          if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=-1; } 
      } else {
          if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=1; } 
      }
        $callback->($_);
      }
    } else {
      $fds->remove($rfh);
      close($rfh);
    }
  }
  yield(); #Try to avoid useless iterations as much as possible
  return $rc;
}


sub dohyp {
  my $out = shift;
  $hyp = shift;
  my $command=shift;
  my %namedargs=@_;
  my @exargs=@{$namedargs{-args}};
  my $node;
  my $args = \@exargs;
  $vmtab = xCAT::Table->new("vm");
  unless ($offlinehyps{$hyp} or ($hyp eq '!@!XCATDUMMYHYPERVISOR!@!') or nodesockopen($hyp,22)) {
    $offlinehyps{$hyp}=1;
  }


  eval { #Contain Sys::Virt bugs that make $@ useless
    if ($hyp eq '!@!XCATDUMMYHYPERVISOR!@!') {  #Fake connection for commands that have a fake hypervisor key
        $hypconn = 1;
    } elsif (not $offlinehyps{$hyp}) { 
        $hypconn= Sys::Virt->new(uri=>"qemu+ssh://root@".$hyp."/system?no_tty=1&netcat=nc");
    }
  };
  unless ($hypconn or $offlinehyps{$hyp}) {
    eval { #Contain Sys::Virt bugs that make $@ useless
        $hypconn= Sys::Virt->new(uri=>"qemu+ssh://root@".$hyp."/system?no_tty=1");
    };
  }
  unless ($hypconn) {
     my %err=(node=>[]);
     foreach (keys %{$hyphash{$hyp}->{nodes}}) {
        push (@{$err{node}},{name=>[$_],error=>["Cannot communicate via libvirt to $hyp"],errorcode=>[1]});
     }
     print $out freeze([\%err]);
     print $out "\nENDOFFREEZE6sK4ci\n";
     yield();
     waitforack($out);
     return 1,"General error establishing libvirt communication";
  }
  foreach $node (sort (keys %{$hyphash{$hyp}->{nodes}})) {
    my ($rc,@output) = guestcmd($hyp,$node,$command,@$args); 

    foreach(@output) {
      my %output;
      if (ref($_)) {
          print $out freeze([$_]);
          print $out "\nENDOFFREEZE6sK4ci\n";
          yield();
          waitforack($out);
          next;
      }
      
      (my $desc,my $text) = split (/:/,$_,2);
      unless ($text) {
        $text=$desc;
      } else {
        $desc =~ s/^\s+//;
        $desc =~ s/\s+$//;
        if ($desc) {
          $output{node}->[0]->{data}->[0]->{desc}->[0]=$desc;
        }
      }
      $text =~ s/^\s+//;
      $text =~ s/\s+$//;
      $output{node}->[0]->{errorcode} = $rc;
      $output{node}->[0]->{name}->[0]=$node;
      $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
      $output{node}->[0]->{error} = $text unless $rc == 0;
      print $out freeze([\%output]);
      print $out "\nENDOFFREEZE6sK4ci\n";
      yield();
      waitforack($out);
    }
    yield();
  }
  foreach (keys %$updatetable) {
      my $tabhandle = xCAT::Table->new($_,-create=>1);
      $tabhandle->setNodesAttribs($updatetable->{$_});
  }
  #my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
  #print $out $msgtoparent; #$node.": $_\n";
}
    
1;
