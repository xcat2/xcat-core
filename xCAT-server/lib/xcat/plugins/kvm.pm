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
use xCAT::Usage;
use XML::LibXML; #now that we are in the business of modifying xml data, need something capable of preserving more of the XML structure

#TODO: convert all uses of XML::Simple to LibXML?  Using both seems wasteful in a way..
use XML::Simple qw(XMLout);
use Thread qw(yield);
use xCAT::Utils qw/genpassword/;
use File::Basename qw/fileparse/;
use File::Path qw/mkpath/;
use IO::Socket;
use IO::Select;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use strict;
use feature "switch"; # For given-when block

#use warnings;
my $use_xhrm = 0; #xCAT Hypervisor Resource Manager, to satisfy networking and storage prerequisites, default to not using it for the moment
my $imgfmt      = 'raw';         #use raw format by default
my $clonemethod = 'qemu-img';    #use qemu-img command
my %vm_comm_pids;
my %offlinehyps;
my %hypstats;
my %offlinevms;
my $parser;
my @destblacklist;
my $updatetable; #when a function is performing per-node operations, it can queue up a table update by populating parts of this hash
my $confdata;    #a reference to serve as a common pointer betweer VMCommon functions and this plugin
my %allnodestatus;
require Sys::Virt;

if (Sys::Virt->VERSION =~ /^0\.[10]\./) {
    die;
}
use XML::Simple;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw store_fd fd_retrieve);
use IO::Select;
use IO::Handle;
use Time::HiRes qw(gettimeofday sleep);
use xCAT::DBobjUtils;
use Getopt::Long;
use xCAT::SvrUtils;

my %runningstates;
my $vmmaxp = 64;
my $mactab;
my %usedmacs;
my $status_noop = "XXXno-opXXX";
my $callback;
my $requester;    #used to track the user

sub handled_commands {
    return {
        rpower   => 'nodehm:power,mgt',
        mkvm     => 'nodehm:power,mgt',
        clonevm  => 'nodehm:power,mgt',
        chvm     => 'nodehm:power,mgt',
        rmvm     => 'nodehm:power,mgt',
        rinv     => 'nodehm:power,mgt',
        rmigrate => 'nodehm:mgt',
        getcons  => 'nodehm:mgt',
        rscan    => 'nodehm:mgt=ipmi',

        #rvitals => 'nodehm:mgt',
        #rinv => 'nodehm:mgt',
        getrvidparms  => 'nodehm:mgt',
        lsvm          => ['nodehm:mgt=ipmi', 'nodehm:mgt=kvm'], #allow both hypervisor and VMs as params
        rbeacon       => 'nodehm:mgt',
        revacuate     => 'hypervisor:type',
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


sub get_path_for_pool {
    my $poolobj = shift;
    my $poolxml = $poolobj->get_xml_description();
    my $pooldom = $parser->parse_string($poolxml);
    my @paths   = $pooldom->findnodes("/pool/target/path/text()");
    if (scalar @paths != 1) {
        return undef;
    }
    return $paths[0]->data;
}

sub build_pool_xml {
    my $url = shift;
    my $pooldesc;
    my $name = $url;
    $name =~ s!nfs://!nfs_!;
    $name =~ s!dir://!dir_!;
    $name =~ s!lvm://!lvm_!;
    $name =~ s/\//_/g; #though libvirt considers / kosher, sometimes it wants to create a local xml file using name for filename...
    if ($url =~ /^dir:/) {    #directory style..
        my $path = $url;
        $path =~ s/dir:\/\///g;
        return "<pool type=\"dir\"><name>$name</name><target><path>$path</path></target></pool>";
    } elsif ($url =~ /^lvm:\/\//) {    #lvm specified
        my $path = $url;
        $path =~ s/^lvm:\/\///;
        $path =~ s/:(.*)\z//;
        my $volumes = $1;
        my $mount   = "/dev/$path";
        my $xml = '<pool type="logical"><name>' . $path . '</name><target><path>' . $mount . '</path></target>';
        if ($volumes) {
            $xml .= "<source>";
            my @vols = split /,/, $volumes;
            foreach (@vols) {
                $xml .= '<device path="' . $_ . '"/>';
            }
            $xml .= "</source>";
        }
        $xml .= "</pool>";
        return $xml;
    }
    my $mounthost = shift;
    unless ($mounthost) { $mounthost = $hyp; }
    my $pool;
    my $host = $url;
    $host =~ s/.*:\/\///;
    $host =~ s/(\/.*)//;
    my $srcpath = $1;
    my $uuid = xCAT::Utils::genUUID(url => $url);

    #first, we make a pool desc that won't have slashes in them
    $pooldesc = '<pool type="netfs">';
    $pooldesc .= '<name>' . $name . '</name>';
    $pooldesc .= '<uuid>' . $uuid . '</uuid>>';
    $pooldesc .= '<source>';
    $pooldesc .= '<host name="' . $host . '"/>';
    $pooldesc .= '<dir path="' . $srcpath . '"/>';
    $pooldesc .= '</source>';
    $pooldesc .= '<target><path>/var/lib/xcat/pools/' . $uuid . '</path></target></pool>';

    #turns out we can 'define', then 'build', then 'create' on the poolobj instead of 'create', to get mkdir -p like function
    #system("ssh $mounthost mkdir -p /var/lib/xcat/pools/$uuid"); #ok, so not *technically* just building XML, but here is the cheapest
    #place to know uuid...  And yes, we must be allowed to ssh in
    #libvirt just isn't capable enough for this sort of usage
    return $pooldesc;
}



sub get_storage_pool_by_url {
    my $url       = shift;
    my $virtconn  = shift;
    my $mounthost = shift;
    unless ($virtconn) { $virtconn = $hypconn; }
    my @currpools = $virtconn->list_storage_pools();
    push @currpools, $virtconn->list_defined_storage_pools();
    my $poolobj;
    my $pool;
    my $islvm = 0;

    foreach my $poolo (@currpools) {
        $poolobj = $poolo;
        $pool = $parser->parse_string($poolobj->get_xml_description()); #XMLin($poolobj->get_xml_description());
        if ($url =~ /^nfs:\/\/([^\/]*)(\/.*)$/) { #check the essence of the pool rather than the name
            my $host = $1;
            my $path = $2;
            unless ($pool->findnodes("/pool")->[0]->getAttribute("type") eq "netfs") {
                $pool = undef;
                next;
            }

            #ok, it is netfs, now check source..
            my $checkhost = $pool->findnodes("/pool/source/host")->[0]->getAttribute("name");
            my $checkpath = $pool->findnodes("/pool/source/dir")->[0]->getAttribute("path");
            if ($checkhost eq $host and $checkpath eq $path) { #TODO: check name resolution to see if they match really even if not strictly the same
                last;
            }
        } elsif ($url =~ /^dir:\/\/(.*)\z/) {    #a directory, simple enough
            my $path = $1;
            unless ($path =~ /^\//) {
                $path = '/' . $path;
            }
            $path =~ s/\/\z//; #delete trailing / if table specifies, a perfectly understable 'mistake'
            my $checkpath = $pool->findnodes("/pool/target/path/text()")->[0]->data;
            if ($checkpath eq $path) {
                last;
            }
        } elsif ($url =~ /^lvm:\/\/([^:]*)/) {    #lvm volume group....
            my $vgname    = $1;
            my $checkname = $pool->findnodes("/pool/name/text()")->[0]->data;
            if ($checkname eq $vgname) {
                $islvm = 1;
                last;
            }
        } elsif ($pool->findnodes('/pool/name/text()')->[0]->data eq $url) { #$pool->{name} eq $url) {
            last;
        }
        $pool = undef;
    }
    if ($pool) {
        my $inf = $poolobj->get_info();
        if ($inf->{state} == 0) { #Sys::Virt::StoragePool::STATE_INACTIVE) { #if pool is currently inactive, bring it up
            unless ($islvm) { $poolobj->build(); } #if lvm and defined, it's almost certainly been built
            $poolobj->create();
        }
        eval {    #we *try* to do this, but various things may interfere.
              #this is basically to make sure the list of contents is up to date
            $poolobj->refresh();
        };
        return $poolobj;
    }
    $poolobj = $virtconn->define_storage_pool(build_pool_xml($url, $mounthost));
    eval { $poolobj->build(); };
    if ($@) {
        my $error = $@;

        # Some errors from building storage pool object are safe to ignore.
        # For example, "File exists" is returned when a directory location for storage pool is already there.
        # The storage pool still gets built, and the next statement to create storage pool will work.
        unless ($error =~ /vgcreate.*exit status 3/ or $error =~ /pvcreate.*exit status 5/ or $error =~ /File exists/) {
            die $@;
        }
    }
    $poolobj->create();
    eval { #wrap in eval, not likely to fail here, but calling it at all may be superfluous anyway
        $poolobj->refresh();
    };
    return $poolobj;
}

sub get_multiple_paths_by_url {
    my %args    = @_;
    my $url     = $args{url};
    my $node    = $args{node};
    my $poolobj = get_storage_pool_by_url($url);
    unless ($poolobj) { die "Cound not get storage pool for $url"; }
    eval {   #refresh() can 'die' if cloning in progress, accept stale data then
        $poolobj->refresh(); #if volumes change on nfs storage, libvirt is too dumb to notice
    };
    my @volobjs = $poolobj->list_volumes();
    my %paths;
    foreach (@volobjs) {
        if ($_->get_name() =~ /^$node\.([^\.]*)\.([^\.]*)$/) {
            $paths{ $_->get_path() } = { device => $1, format => $2 };
        } elsif ($_->get_name() =~ /^$node\.([^\.]*)$/) {
            $paths{ $_->get_path() } = { device => $1, format => 'raw' };

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
    my %args   = @_;
    my $url    = $args{url};
    my $dev    = $args{dev};
    my $create = $args{create};
    my $force  = $args{force};
    my $format = $args{format};
    my $sparse = 1;
    if ($url =~ /^lvm:/) {
        $sparse = 0;
        $format = 'raw';
    }
    unless ($format) {
        $format = 'qcow2';
    }

    #print "url=$url, dev=$dev,create=$create, force=$force, format=$format\n";
    #ok, now that we have the pool, we need the storage volume from the pool for the node/dev
    my $poolobj = get_storage_pool_by_url($url);
    unless ($poolobj) { die "Could not get storage pool for $url"; }
    eval { #make a refresh attempt non-fatal to fail, since cloning can block it
        $poolobj->refresh(); #if volumes change on nfs storage, libvirt is too dumb to notice
    };
    my @volobjs     = $poolobj->list_volumes();
    my $desiredname = $node . '.' . $dev . '.' . $format;

    #print "desiredname=$desiredname, volobjs=@volobjs\n";
    foreach (@volobjs) {
        if ($_->get_name() eq $desiredname) {
            if ($create) {
                if ($force) {    #must destroy the storage
                    $_->delete();
                } else {
                    die "Path $desiredname already exists";
                }
            } else {
                return $_->get_path();
            }
        }
    }
    if ($create) {
        if ($create =~ /^clone=(.*)$/) {
            my $src = $1;
            my $fmt = 'raw';
            if ($src =~ /\.qcow2$/) {
                $fmt = 'qcow2';
            }
            my $vol = $poolobj->create_volume("<volume><name>" . $desiredname . "</name><target><format type='$format'/></target><capacity>100</capacity><backingStore><path>$src</path><format type='$fmt'/></backingStore></volume>");

            #ok, this is simply hinting, not the real deal, so to speak
            #  1)  sys::virt complains if capacity isn't defined.  We say '100', knowing full well it will be promptly ignored down the code.  This is aggravating
            #      and warrants recheck with the RHEL6 stack
            #  2) create_volume with backingStore is how we do the clone from master (i.e. a thin clone, a la qemu-img create)
            #     note how backing store is full path, allowing cross-pool clones
            #  3) clone_volume is the way to invoke qemu-img convert (i.e. to 'promote' and flatten a vm image to a standalone duplicate volume
            #     incidentally, promote to master will be relatively expensive compared to the converse operation, as expected
            #     will have to verify as it is investigated whether this can successfully cross pools (hope so)
            #  4) qemu-img was so much more transparent and easy to figure out than this
            #  additionally, when mastering a powered down node, we should rebase the node to be a cow clone of the master it just spawned
        } else {
            my $vol;
            unless ($sparse) {    #skip allocation specification for now
                 #currently, LV can have reduced allocation, but *cannot* grow.....
                $vol = $poolobj->create_volume("<volume><name>" . $desiredname . "</name><target><format type='$format'/></target><capacity>" . getUnits($create, "G", 1) . "</capacity></volume>");
            } else {
                $vol = $poolobj->create_volume("<volume><name>" . $desiredname . "</name><target><format type='$format'/></target><capacity>" . getUnits($create, "G", 1) . "</capacity><allocation>0</allocation></volume>");
            }
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
    if (!$addr) {
        xCAT::SvrUtils::sendmsg([ 1, "Cannot not resolve host $node" ], $callback);
        return 0;
    }
    my $sin = sockaddr_in($port, $addr);
    my $proto = getprotobyname('tcp');
    socket($socket, PF_INET, SOCK_STREAM, $proto) || return 0;
    connect($socket, $sin) || return 0;
    return 1;
}



sub waitforack {
    my $sock   = shift;
    my $select = new IO::Select;
    $select->add($sock);
    my $str;
    if ($select->can_read(60)) { # Continue after 10 seconds, even if not acked...
        if ($str = <$sock>) {
        } else {
            $select->remove($sock);    #Block until parent acks data
        }
    }
}

sub reconfigvm {
    $node = shift;
    my $xml      = shift;
    my $domdesc  = $parser->parse_string($xml);
    my @bootdevs = $domdesc->findnodes("/domain/os/boot");
    my $curroffset = $domdesc->findnodes("/domain/clock")->[0]->getAttribute("offset");
    my $newoffset;
    my $needfixin = 0;
    if (defined($confdata->{vm}->{$node}->[0]->{clockoffset})) {

        #If user requested a specific behavior, give it
        $newoffset = $confdata->{vm}->{$node}->[0]->{clockoffset};
    } else {

        #Otherwise, only do local time for things that look MS
        if (defined($confdata->{nodetype}->{$node}->[0]->{os}) and $confdata->{nodetype}->{$node}->[0]->{os} =~ /win.*/) {
            $newoffset = 'localtime';
        } else {    #For everyone else, utc is preferred generally
            $newoffset = 'utc';
        }
    }
    if ($curroffset ne $newoffset) {
        $needfixin = 1;
        $domdesc->findnodes("/domain/clock")->[0]->setAttribute("offset", $newoffset);
    }
    my @oldbootdevs;
    if (defined $confdata->{vm}->{$node}->[0]->{memory}) {
        $needfixin = 1;
        $domdesc->findnodes("/domain/memory/text()")->[0]->setData(getUnits($confdata->{vm}->{$node}->[0]->{memory}, "M", 1024));
        foreach ($domdesc->findnodes("/domain/currentMemory/text()")) {
            $_->setData(getUnits($confdata->{vm}->{$node}->[0]->{memory}, "M", 1024));
        }
    }
    if (defined $confdata->{vm}->{$node}->[0]->{vcpus}) {
        $needfixin = 1;
        $domdesc->findnodes("/domain/vcpu/text()")->[0]->setData($confdata->{vm}->{$node}->[0]->{vcpus});
    }
    if (defined $confdata->{vm}->{$node}->[0]->{bootorder}) {
        my @expectedorder = split(/[:,]/, $confdata->{vm}->{$node}->[0]->{bootorder});
        foreach (@expectedorder) { #this loop will check for changes and fix 'n' and 'net'
            my $currdev = shift @bootdevs;
            if ("net" eq $_ or "n" eq $_) {
                $_ = "network";
            }
            unless ($currdev and $currdev->getAttribute("dev") eq $_) {
                $needfixin = 1;
            }
            if ($currdev) {
                push @oldbootdevs, $currdev;
            }
        }
        if (scalar(@bootdevs)) {
            $needfixin = 1;
            push @oldbootdevs, @bootdevs;
        }
        unless ($needfixin) { return 0; }

        #ok, we need to remove all 'boot' nodes from current xml, and put in new ones in the order we like
        foreach (@oldbootdevs) {
            $_->parentNode->removeChild($_);
        }

        #now to add what we want...
        my $osnode = $domdesc->findnodes("/domain/os")->[0];
        foreach (@expectedorder) {
            my $fragment = $parser->parse_balanced_chunk('<boot dev="' . $_ . '"/>');
            $osnode->appendChild($fragment);
        }
    }
    if ($needfixin) {
        return $domdesc->toString();
    } else { return 0; }
}

sub build_oshash {
    my %rethash;
    $rethash{type}->{content} = 'hvm';

    my $hypcpumodel = $confdata->{ $confdata->{vm}->{$node}->[0]->{host} }->{cpumodel};
    unless (defined($hypcpumodel) and $hypcpumodel eq "ppc64le") {
        $rethash{bios}->{useserial} = 'yes';
    }

    if (defined $confdata->{vm}->{$node}->[0]->{bootorder}) {
        my $bootorder = $confdata->{vm}->{$node}->[0]->{bootorder};
        my @bootdevs  = split(/[:,]/, $bootorder);
        my $bootnum   = 0;
        foreach (@bootdevs) {
            if ("net" eq $_ or "n" eq $_) {
                $rethash{boot}->[$bootnum]->{dev} = "network";
            } else {
                $rethash{boot}->[$bootnum]->{dev} = $_;
            }
            $bootnum++;
        }
    } else {
        $rethash{boot}->[0]->{dev} = 'network';
        $rethash{boot}->[1]->{dev} = 'hd';
    }
    return \%rethash;
}

sub build_diskstruct {
    print "build_diskstruct called\n";
    my $cdloc   = shift;
    my @returns = ();
    my $currdev;
    my @suffixes     = ('a', 'b', 'd' .. 'zzz');
    my $suffidx      = 0;
    my $storagemodel = $confdata->{vm}->{$node}->[0]->{storagemodel};
    my $cachemethod  = "none";
    if ($confdata->{vm}->{$node}->[0]->{storagecache}) {
        $cachemethod = $confdata->{vm}->{$node}->[0]->{storagecache};
    }


    if (defined $confdata->{vm}->{$node}->[0]->{storage}) {
        my $disklocs = $confdata->{vm}->{$node}->[0]->{storage};
        my @locations = split /\|/, $disklocs;
        foreach my $disk (@locations) {

            #Setting default values of a virtual disk backed by a file at hd*.
            my $diskhash;
            $disk =~ s/=(.*)//;
            my $model = $1;
            unless ($model) {

                #if not defined, model will stay undefined like above
                $model = $storagemodel;
                unless ($model) { $model = 'ide'; }   #if still not defined, ide
            }
            my $prefix = 'hd';
            if ($model eq 'virtio') {
                $prefix = 'vd';
            } elsif ($model eq 'scsi') {
                $prefix = 'sd';
            }
            $diskhash->{type}          = 'file';
            $diskhash->{device}        = 'disk';
            $diskhash->{target}->{dev} = $prefix . $suffixes[$suffidx];
            $diskhash->{target}->{bus} = $model;

            my @disk_parts = split(/,/, $disk);

            #Find host file and determine if it is a file or a block device.
            if (substr($disk_parts[0], 0, 4) eq 'phy:') {
                $diskhash->{type} = 'block';
                $diskhash->{source}->{dev} = substr($disk_parts[0], 4);
            } elsif ($disk_parts[0] =~ m/^nfs:\/\/(.*)$/ or $disk_parts[0] =~ m/^dir:\/\/(.*)$/ or $disk_parts[0] =~ m/^lvm:\/\/(.*)$/) {
                my %disks = %{ get_multiple_paths_by_url(url => $disk_parts[0], node => $node) };
                unless (keys %disks) {
                    return (1, "Unable to find any persistent disks at $disk_parts[0] for $node");
                }
                foreach (keys %disks) {
                    my $tdiskhash;
                    $tdiskhash->{type};
                    $tdiskhash->{device}          = 'disk';
                    $tdiskhash->{driver}->{name}  = 'qemu';
                    $tdiskhash->{driver}->{type}  = $disks{$_}->{format};
                    $tdiskhash->{driver}->{cache} = $cachemethod;
                    $tdiskhash->{source}->{file}  = $_;
                    $tdiskhash->{target}->{dev}   = $disks{$_}->{device};

                    if ($disks{$_} =~ /^vd/) {
                        $tdiskhash->{target}->{bus} = 'virtio';
                    } elsif ($disks{$_} =~ /^hd/) {
                        $tdiskhash->{target}->{bus} = 'ide';
                    } elsif ($disks{$_} =~ /^sd/) {
                        $tdiskhash->{target}->{bus} = 'scsi';
                    }
                    push @returns, $tdiskhash;

                }
                next;    #nfs:// skips the other stuff
                 #$diskhash->{source}->{file} = get_filepath_by_url(url=>$disk_parts[0],dev=>$diskhash->{target}->{dev}); #"/var/lib/xcat/vmnt/nfs_".$1."/$node/".$diskhash->{target}->{dev};
            } else {  #currently, this would be a bare file to slap in as a disk
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
                    $diskhash->{device} = 'cdrom';
                }
            } else {
                $suffidx++;
            }

            push @returns, $diskhash;
        }
    }
    my $cdprefix = 'hd';

    # Normally for vmstoragemodel=virtio, we would set prefix of "vd", but device name vd*
    # doesn't work for CDROM, so for now use the same prefix "sd" as for vmstoragemodel=scsi.
    if ($storagemodel eq 'virtio') {
        $cdprefix='sd';
    } elsif ($storagemodel eq 'scsi') {
        $cdprefix = 'sd';
    }
    $suffidx += 1;
    if ($cdloc) {
        my $cdhash;
        $cdhash->{device} = 'cdrom';
        if ($cdloc =~ /^\/dev/) {
            $cdhash->{type} = 'block';
        } else {
            $cdhash->{type} = 'file';
        }
        $cdhash->{source}->{file} = $cdloc;
        $cdhash->{readonly};
        $cdhash->{target}->{dev} = $cdprefix . $suffixes[$suffidx];
        push @returns, $cdhash;
    } else { #give the VM an empty optical drive, to allow chvm live attach/remove
        my $cdhash;
        $cdhash->{device} = 'cdrom';
        $cdhash->{type}   = 'file';
        $cdhash->{readonly};
        $cdhash->{target}->{dev} = $cdprefix . $suffixes[$suffidx];
        push @returns, $cdhash;
    }

    return \@returns;
}

sub getNodeUUID {
    my $node = shift;
    my $uuid;
    if ($confdata->{vpd}->{$node}->[0] and $confdata->{vpd}->{$node}->[0]->{uuid}) {
        $uuid = $confdata->{vpd}->{$node}->[0]->{uuid};
        $uuid =~ s/^(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
        return $uuid;
    }
    if ($confdata->{mac}->{$node}->[0]->{mac}) { #a uuidv1 is possible, generate that for absolute uniqueness guarantee
        my $mac = $confdata->{mac}->{$node}->[0]->{mac};
        $mac =~ s/\|.*//;
        $mac =~ s/!.*//;
        $updatetable->{vpd}->{$node} = { uuid => xCAT::Utils::genUUID(mac => $mac) };
    } else {
        $updatetable->{vpd}->{$node} = { uuid => xCAT::Utils::genUUID() };
    }
    $uuid = $updatetable->{vpd}->{$node}->{uuid};
    $uuid =~ s/^(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
    return $uuid;

}

sub build_nicstruct {
    my $rethash;
    my $node = shift;
    my @nics = ();
    if ($confdata->{vm}->{$node}->[0]->{nics}) {
        @nics = split /,/, $confdata->{vm}->{$node}->[0]->{nics};
    }
    my @macs = xCAT::VMCommon::getMacAddresses($confdata, $node, scalar @nics);
    my @rethashes;
    foreach (@macs) {
        my $rethash;
        my $nic = shift @nics;
        my $type = 'virtio'; #better default fake nic than rtl8139, relevant to most
        unless ($nic) {
            last;    #Don't want to have multiple vnics tied to the same switch
        }
        $nic =~ s/.*://;    #the detail of how the bridge was built is of no
                            #interest to this segment of code
        if ($confdata->{vm}->{$node}->[0]->{nicmodel}) {
            $type = $confdata->{vm}->{$node}->[0]->{nicmodel};
        }
        if ($nic =~ /=/) {
            ($nic, $type) = split /=/, $nic, 2;
        }
        $rethash->{type}             = 'bridge';
        $rethash->{mac}->{address}   = $_;
        $rethash->{source}->{bridge} = $nic;
        $rethash->{model}->{type}    = $type;
        push @rethashes, $rethash;
    }
    return \@rethashes;
}

sub getUnits {
    my $amount  = shift;
    my $defunit = shift;
    my $divisor = shift;
    unless ($divisor) {
        $divisor = 1;
    }
    if ($amount =~ /(\D)$/) {    #If unitless, add unit
        $defunit = $1;
        chop $amount;
    }
    if ($defunit =~ /k/i) {
        return $amount * 1024 / $divisor;
    } elsif ($defunit =~ /m/i) {
        return $amount * 1048576 / $divisor;
    } elsif ($defunit =~ /g/i) {
        return $amount * 1073741824 / $divisor;
    }
}

sub build_xmldesc {
    my $node  = shift;
    my %args  = @_;
    my $cdloc = $args{cd};
    my %xtree = ();
    my $hypcpumodel = $confdata->{ $confdata->{vm}->{$node}->[0]->{host} }->{cpumodel};
    my $hypcputype = $confdata->{ $confdata->{vm}->{$node}->[0]->{host} }->{cputype};
    my $hypcputhreads = $confdata->{ $confdata->{vm}->{$node}->[0]->{host} }->{cpu_thread};
    unless ($hypcputhreads) {
        $hypcputhreads = "1";
    }

    $xtree{type}            = 'kvm';
    $xtree{name}->{content} = $node;
    $xtree{uuid}->{content} = getNodeUUID($node);
    $xtree{os}              = build_oshash();
    if (defined($hypcpumodel) and $hypcpumodel eq "ppc64") {
        $xtree{os}->{type}->{arch}    = "ppc64";
        $xtree{os}->{type}->{machine} = "pseries";
        delete $xtree{os}->{bios};
    }
    if ($args{memory}) {
        $xtree{memory}->{content} = getUnits($args{memory}, "M", 1024);
        if ($confdata->{vm}->{$node}->[0]->{memory}) {
            $updatetable->{vm}->{$node}->{memory} = $args{memory};
        }
    } elsif (defined $confdata->{vm}->{$node}->[0]->{memory}) {
        $xtree{memory}->{content} = getUnits($confdata->{vm}->{$node}->[0]->{memory}, "M", 1024);
    } else {
        $xtree{memory}->{content} = 524288;
    }

    my %cpupinhash;
    my @passthrudevices;
    my $memnumanodes;
    my $advsettings = undef;
    if (defined $confdata->{vm}->{$node}->[0]->{othersettings}) {
        $advsettings = $confdata->{vm}->{$node}->[0]->{othersettings};
    }

    #parse the additional settings in attrubute vm.othersettings
    #the settings are semicolon delimited, the format of each setting is:
    #cpu pining:         "vcpupin:<physical cpu set>"
    #pci passthrough:    "devpassthrough:<pci device name1>,<pci device name2>..."
    #memory binding:     "membind:<numa node set>"
    if ($advsettings) {
        my @tmp_array = split ";", $advsettings;
        foreach (@tmp_array) {
            if (/vcpupin:['"]?([^:'"]*)['"]?:?['"]?([^:'"]*)['"]?/) {
                if ($2) {

                    #this is for cpu pining in the vcpu level,which is not currently supported
                    #reserved for future use
                    $cpupinhash{$1} = $2;
                } else {
                    $cpupinhash{ALL} = $1;
                }
            }

            if (/devpassthrough:(.*)/) {
                @passthrudevices = split ",", $1;
            }

            if (/membind:(.*)/) {
                $memnumanodes = $1;
            }

        }
    }

    #prepare the xml hash for memory binding
    if (defined $memnumanodes) {
        my %numatunehash;
        $numatunehash{memory} = [ { nodeset => "$memnumanodes" } ];
        $xtree{numatune} = \%numatunehash;
    }

    #prepare the xml hash for cpu pining
    if (exists $cpupinhash{ALL}) {
        $xtree{vcpu}->{placement} = 'static';
        $xtree{vcpu}->{cpuset}    = "$cpupinhash{ALL}";
        $xtree{vcpu}->{cpuset} =~ s/\"\'//g;
    }

    #prepare the xml hash for pci passthrough
    my @prdevarray;
    foreach my $devname (@passthrudevices) {
        #This is for SR-IOV vfio
        #Change vfio format 0000:01:00.2 to pci_0000_01_00_2
        if ( $devname =~ m/(\w:)+(\w)+.(\w)/ ){
            $devname =~ s/[:|.]/_/g;
            if ( $devname !~ /^pci_/ ) {
                $devname ="pci_".$devname
            }
        }

        my $devobj = $hypconn->get_node_device_by_name($devname);
        unless ($devobj) {
            return -1;
        }

        #get the xml description of the pci device
        my $devxml = $devobj->get_xml_description();
        unless ($devxml) {
            return -1;
        }

        my $devhash = XMLin($devxml);
        if (defined $devhash->{capability}->{type} and $devhash->{capability}->{type} =~ /pci/i) {
            my %tmphash;
            $tmphash{mode}           = 'subsystem';
            $tmphash{type}           = $devhash->{capability}->{type};
            $tmphash{managed}        = "yes";
            $tmphash{driver}->{name} = "vfio";
            $tmphash{source}->{address}->[0] = \%{ $devhash->{'capability'}->{'iommuGroup'}->{'address'} };
            push(@prdevarray, \%tmphash);

        }
    }

    $xtree{devices}->{hostdev} = \@prdevarray;


    if ($hypcpumodel eq "ppc64" or $hypcpumodel eq "ppc64le") {
        my %cpuhash = ();
        if ($hypcputype) {
            $cpuhash{model} = $hypcputype;
        }
        if ($args{cpus}) {
            $xtree{vcpu}->{content}             = $args{cpus} * $hypcputhreads;
            $cpuhash{topology}->{sockets}       = 1;
            $cpuhash{topology}->{cores}         = $args{cpus};
            $cpuhash{topology}->{threads}       = $hypcputhreads;
            $updatetable->{vm}->{$node}->{cpus} = $args{cpus};
        } elsif (defined $confdata->{vm}->{$node}->[0]->{cpus}) {
            $xtree{vcpu}->{content} = $confdata->{vm}->{$node}->[0]->{cpus} * $hypcputhreads;
            $cpuhash{topology}->{sockets} = 1;
            $cpuhash{topology}->{cores} = $confdata->{vm}->{$node}->[0]->{cpus};
            $cpuhash{topology}->{threads} = $hypcputhreads;
        } else {
            $xtree{vcpu}->{content}       = 1 * $hypcputhreads;
            $cpuhash{topology}->{sockets} = 1;
            $cpuhash{topology}->{cores}   = 1;
            $cpuhash{topology}->{threads} = $hypcputhreads;
        }
        $xtree{cpu} = \%cpuhash;
    } else {
        if ($args{cpus}) {
            $xtree{vcpu}->{content} = $args{cpus};
            if ($confdata->{vm}->{$node}->[0]->{cpus}) {
                $updatetable->{vm}->{$node}->{cpus} = $args{cpus};
            }
        } elsif (defined $confdata->{vm}->{$node}->[0]->{cpus}) {
            $xtree{vcpu}->{content} = $confdata->{vm}->{$node}->[0]->{cpus};
        } else {
            $xtree{vcpu}->{content} = 1;
        }
    }
    if (defined($confdata->{vm}->{$node}->[0]->{clockoffset})) {

        #If user requested a specific behavior, give it
        $xtree{clock}->{offset} = $confdata->{vm}->{$node}->[0]->{clockoffset};
    } else {

        #Otherwise, only do local time for things that look MS
        if (defined($confdata->{nodetype}->{$node}->[0]->{os}) and $confdata->{nodetype}->{$node}->[0]->{os} =~ /win.*/) {
            $xtree{clock}->{offset} = 'localtime';
        } else {    #For everyone else, utc is preferred generally
            $xtree{clock}->{offset} = 'utc';
        }
    }

    $xtree{features}->{pae}     = {};
    $xtree{features}->{acpi}    = {};
    $xtree{features}->{apic}    = {};
    $xtree{features}->{content} = "\n";
    ($xtree{devices}->{disk}, my $errstr) = build_diskstruct($cdloc);
    if ($errstr) {
        return (-1, $errstr);
    }
    $xtree{devices}->{interface} = build_nicstruct($node);

    #use content to force xml simple to not make model the 'name' of video
    if (defined($confdata->{vm}->{$node}->[0]->{vidmodel})) {
        my $model = $confdata->{vm}->{$node}->[0]->{vidmodel};
        my $vram  = '8192';
        if ($model eq 'qxl') {
            $xtree{devices}->{channel}->{type}           = 'spicevmc';
            $xtree{devices}->{channel}->{target}->{type} = 'virtio';
            $xtree{devices}->{channel}->{target}->{name} = 'com.redhat.spice.0';
            $vram = 65536; } #surprise, spice blows up with less vram than this after version 0.6 and up
        $xtree{devices}->{video} = [ { 'content' => '', 'model' => { type => $model, vram => $vram } } ];
    } else {
        $xtree{devices}->{video} = [ { 'content' => '', 'model' => { type => 'vga', vram => 8192 } } ];
    }
    $xtree{devices}->{input}->{type} = 'tablet';
    $xtree{devices}->{input}->{bus}  = 'usb';
    if (defined($confdata->{vm}->{$node}->[0]->{vidproto})) {
        $xtree{devices}->{graphics}->{type} = $confdata->{vm}->{$node}->[0]->{vidproto};
    } else {
        $xtree{devices}->{graphics}->{type} = 'vnc';
    }
    $xtree{devices}->{graphics}->{autoport} = 'yes';
    $xtree{devices}->{graphics}->{listen}   = '0.0.0.0';
    if ($confdata->{vm}->{$node}->[0]->{vidpassword}) {
        $xtree{devices}->{graphics}->{password} = $confdata->{vm}->{$node}->[0]->{vidpassword};
    } else {
        $xtree{devices}->{graphics}->{password} = genpassword(20);
    }
    if (defined($hypcpumodel) and $hypcpumodel eq 'ppc64') {
        $xtree{devices}->{emulator}->{content} = "/usr/bin/qemu-system-ppc64";
    } elsif (defined($hypcpumodel) and $hypcpumodel eq 'ppc64le') {
        # do nothing for ppc64le, do not support sound at this time
        ;
    } else {
        $xtree{devices}->{sound}->{model} = 'ac97';
    }

    $xtree{devices}->{console}->{type} = 'pty';
    $xtree{devices}->{console}->{target}->{port} = '1';
    return XMLout(\%xtree, RootName => "domain");
}

sub refresh_vm {
    my $dom = shift;

    my $newxml = $dom->get_xml_description();
    $updatetable->{kvm_nodedata}->{$node}->{xml} = $newxml;
    $newxml = XMLin($newxml);
    my $vidport  = $newxml->{devices}->{graphics}->{port};
    my $vidproto = $newxml->{devices}->{graphics}->{type};
    my $stty     = $newxml->{devices}->{console}->{tty};

    #$updatetable->{vm}->{$node}={vncport=>$vncport,textconsole=>$stty};
    #$vmtab->setNodeAttribs($node,{vncport=>$vncport,textconsole=>$stty});
    return { vidport => $vidport, textconsole => $stty, vidproto => $vidproto };
}

sub getcons {
    my $node = shift();
    my $type = shift();
    my $dom;
    eval {
        $dom = $hypconn->get_domain_by_name($node);
    };
    unless ($dom) {
        return 1, "Unable to query running VM";
    }
    my $consdata = refresh_vm($dom);
    my $hyper    = $confdata->{vm}->{$node}->[0]->{host};

    if ($type eq "text") {
        my $serialspeed;
        if ($confdata->{nodehm}) {
            $serialspeed = $confdata->{nodehm}->{$node}->[0]->{serialspeed};
        }
        my $sconsparms = { node => [ { name => [$node] } ] };
        $sconsparms->{node}->[0]->{sshhost}   = [$hyper];
        $sconsparms->{node}->[0]->{psuedotty} = [ $consdata->{textconsole} ];
        $sconsparms->{node}->[0]->{baudrate}  = [$serialspeed];
        return (0, $sconsparms);
    } elsif ($type eq "vid") {
        $consdata->{server} = $hyper;
        my $domxml         = $dom->get_xml_description();
        my $parseddom      = $parser->parse_string($domxml);
        my ($graphicsnode) = $parseddom->findnodes("//graphics");
        my $tpasswd;
        if ($confdata->{vm}->{$node}->[0]->{vidpassword}) {
            $tpasswd = $confdata->{vm}->{$node}->[0]->{vidpassword};
            $graphicsnode->removeAttribute("passwdValidTo");
        } else {
            $tpasswd = genpassword(16);
            my $validto = POSIX::strftime("%Y-%m-%dT%H:%M:%S", gmtime(time() + 60));
            $graphicsnode->setAttribute("passwdValidTo", $validto);
        }
        $graphicsnode->setAttribute("passwd", $tpasswd);
        $dom->update_device($graphicsnode->toString());

        #$dom->update_device("<graphics type='".$consdata->{vidproto}."' passwd='$tpasswd' passwdValidTo='$validto' autoport='yes'/>");
        $consdata->{password} = $tpasswd;
        return $consdata;

        #return (0,{$consdata->{vidproto}.'@'.$hyper.":".$consdata->{vidport}); #$consdata->{vncport});
    }
}

sub getrvidparms {
    my $node = shift;
    my $location = getcons($node, "vid");
    unless (ref $location) {
        return (1, "Error: Unable to determine rvid destination for $node (appears VM is off)");
    }
    my @output = (
        "method: kvm"
    );
    foreach (keys %$location) {
        push @output, $_ . ":" . $location->{$_};
    }
    return 0, @output;
}

my %cached_noderanges;

sub pick_target {
    my $node      = shift;
    my $addmemory = shift;
    my $target;
    my $mostfreememory = undef;
    my $currentfreememory;
    my $candidates = $confdata->{vm}->{$node}->[0]->{migrationdest};
    my $currhyp    = $confdata->{vm}->{$node}->[0]->{host};

    #caching strategy is implicit on whether $addmemory is passed.
    unless ($candidates) {
        return undef;
    }
    my @fosterhyps; #noderange is relatively expensive, and generally we only will have a few distinct noderange descriptions to contend with in a mass adoption, so cache eache one for reuse across pick_target() calls
    if (defined $cached_noderanges{$candidates}) {
        @fosterhyps = @{ $cached_noderanges{$candidates} };
    } else {
        @fosterhyps = noderange($candidates);
        $cached_noderanges{$candidates} = \@fosterhyps;
    }
    foreach (@fosterhyps) {
        my $targconn;
        my $cand = $_;
        if ($_ eq $currhyp)   { next; }    #skip current node
        if ($offlinehyps{$_}) { next };    #skip already offlined nodes
        if (grep { "$_" eq $cand } @destblacklist) { next; } #skip blacklisted destinations
        if ($addmemory and defined $hypstats{$_}->{freememory}) { #only used cache results when addmemory suggests caching can make sense
            $currentfreememory = $hypstats{$_}->{freememory}
        } else {
            if (not nodesockopen($_, 22)) { $offlinehyps{$_} = 1; next; } #skip unusable destinations
            eval { #Sys::Virt has bugs that cause it to die out in weird ways some times, contain it here
                $targconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $_ . "/system?no_tty=1&netcat=nc");
            };
            unless ($targconn) {
                eval { #Sys::Virt has bugs that cause it to die out in weird ways some times, contain it here
                    $targconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $_ . "/system?no_tty=1");
                };
            }
            unless ($targconn) { next; }    #skip unreachable destinations
            $currentfreememory = $targconn->get_node_info()->{memory};
            foreach ($targconn->list_domains()) {
                if ($_->get_name() eq 'Domain-0') { next; } #Dom0 memory usage is elastic, we are interested in HVM DomU memory, which is inelastic

                $currentfreememory -= $_->get_info()->{memory};
            }
            $hypstats{$cand}->{freememory} = $currentfreememory;
        }
        if ($addmemory and $addmemory->{$_}) {
            $currentfreememory -= $addmemory->{$_};
        }
        if (not defined($mostfreememory)) {
            $mostfreememory = $currentfreememory;
            $target         = $_;
        } elsif ($currentfreememory > $mostfreememory) {
            $mostfreememory = $currentfreememory;
            $target         = $_;
        }
    }
    return $target;
}


sub migrate {
    $node = shift();
    my @args = @_;
    my $targ;
    foreach (@args) {
        if (/^-/) { next; }
        $targ = $_;
    }
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
        return (1, "Unable to identify a suitable target host for guest $node");
    }
    if ($use_xhrm) {
        xhrm_satisfy($node, $targ);
    }
    my $prevhyp;
    my $target  = "qemu+ssh://root@" . $targ . "/system?no_tty=1";
    my $currhyp = "qemu+ssh://root@";
    if ($confdata->{vm}->{$node}->[0]->{host}) {
        $prevhyp = $confdata->{vm}->{$node}->[0]->{host};
        $currhyp .= $prevhyp;
    } else {
        return (1, "Unable to find current location of $node");
    }
    $currhyp .= "/system?no_tty=1";
    if ($currhyp eq $target) {
        return (0, "Guest is already on host $targ");
    }
    my $srchypconn;
    my $desthypconn;
    unless ($offlinehyps{$prevhyp} or nodesockopen($prevhyp, 22)) {
        $offlinehyps{$prevhyp} = 1;
    }
    my $srcnetcatadd = "&netcat=nc";
    unless ($offlinehyps{$prevhyp}) {
        eval {    #Contain Sys::Virt bugs
            $srchypconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $prevhyp . "/system?no_tty=1$srcnetcatadd");
        };
        unless ($srchypconn) {
            $srcnetcatadd = "";
            eval {    #Contain Sys::Virt bugs
                $srchypconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $prevhyp . "/system?no_tty=1");
            };
        }
    }
    unless ($srchypconn) {
        if (grep { $_ eq '-f' } @args) {
            unless ($vmtab) { $vmtab = new xCAT::Table('vm', -create => 1); }
            $vmtab->setNodeAttribs($node, { host => $targ });
            return (0, "migrated to $targ");
        } else {
            return (1, "Unable to reach $prevhyp to perform operation of $node, use nodech to change vm.host if certain of no split-brain possibility exists (or use -f on rmigrate)");
        }
    }
    unless ($offlinehyps{$targ} or nodesockopen($targ, 22)) {
        $offlinehyps{$targ} = 1;
    }
    my $destnetcatadd = "&netcat=nc";
    unless ($offlinehyps{$targ}) {
        eval {    #Contain Sys::Virt bugs
            $desthypconn = Sys::Virt->new(uri => $target . $destnetcatadd);
        };
        unless ($desthypconn) {
            $destnetcatadd = "";
            eval {    #Contain Sys::Virt bugs
                $desthypconn = Sys::Virt->new(uri => $target);
            };
        }
    }
    unless ($desthypconn) {
        return (1, "Unable to reach $targ to perform operation of $node, destination unusable.");
    }
    if (defined $confdata->{vm}->{$node}->[0]->{storage} and $confdata->{vm}->{$node}->[0]->{storage} =~ /^nfs:/) {

        #first, assure master is in place
        if ($confdata->{vm}->{$node}->[0]->{master}) {
            my $vmmastertab = xCAT::Table->new('vmmaster', -create => 0);
            my $masterent;
            if ($vmmastertab) {
                $masterent = $vmmastertab->getAttribs({ name => $confdata->{vm}->{$node}->[0]->{master} }, ['storage']);
            }
            if ($masterent and $masterent->{storage}) {
                foreach (split /,/, $masterent->{storage}) {
                    s/=.*//;
                    get_storage_pool_by_url($_, $desthypconn, $targ);
                }
            }
        }
        my $urls = $confdata->{vm}->{$node}->[0]->{storage} and $confdata->{vm}->{$node}->[0]->{storage};
        foreach (split /,/, $urls) {
            s/=.*//;
            get_storage_pool_by_url($_, $desthypconn, $targ);
        }
    }
    my $sock = IO::Socket::INET->new(Proto => 'udp');
    my $ipa = inet_aton($node);
    my $pa;
    if ($ipa) {
        $pa = sockaddr_in(7, $ipa); #UDP echo service, not needed to be actually
    }

    #serviced, we just want to trigger MAC move in the switch forwarding dbs
    my $nomadomain;
    eval {
        $nomadomain = $srchypconn->get_domain_by_name($node);
    };
    unless ($nomadomain) {
        unless ($vmtab) { $vmtab = new xCAT::Table('vm', -create => 1); }
        $vmtab->setNodeAttribs($node, { host => $targ });
        return (0, "migrated to $targ");

        #return (1,"Unable to find $node on $prevhyp, vm.host may be incorrect or a split-brain condition, such as libvirt forgetting a guest due to restart or bug.");

    }
    my $newdom;
    my $errstr;
    eval {
        $newdom = $nomadomain->migrate($desthypconn, &Sys::Virt::Domain::MIGRATE_LIVE, undef, undef, 0);
    };
    if ($@) { $errstr = $@; }

    #TODO: If it looks like it failed to migrate, ensure the guest exists only in one place
    if ($errstr) {
        return (1, "Failed migration of $node from $prevhyp to $targ: $errstr");
    }
    unless ($newdom) {
        return (1, "Failed migration from $prevhyp to $targ");
    }
    if ($ipa) {
        system("arp -d $node");    #Make ethernet fabric take note of change
        send($sock, "dummy", 0, $pa); #UDP packet to force forwarding table update in switches, ideally a garp happened, but just in case...
    }

    #BTW, this should all be moot since the underlying kvm seems good about gratuitous traffic, but it shouldn't hurt anything
    refresh_vm($newdom);

    #The migration seems tohave suceeded, but to be sure...
    close($sock);
    if ($desthypconn->get_domain_by_name($node)) {

        #$updatetable->{vm}->{$node}->{host} = $targ;
        unless ($vmtab) { $vmtab = new xCAT::Table('vm', -create => 1); }
        $vmtab->setNodeAttribs($node, { host => $targ });
        return (0, "migrated to $targ");
    } else {    #This *should* not be possible
        return (1, "Failed migration from $prevhyp to $targ, despite normal looking run...");
    }
}


sub getpowstate {
    my $dom = shift;
    my $vmstat;
    if ($dom) {
        $vmstat = $dom->get_info;
    }
    if ($vmstat and $runningstates{ $vmstat->{state} }) {
        return "on";
    } else {
        return "off";
    }
}

# Return storageformat definition
sub getstorageformat {
    my $cfginfo = shift;

    my @flags = split /,/, $cfginfo->{virtflags};
    my $format;
    foreach (@flags) {
        if (/^imageformat=(.*)\z/) {
            $format = $1;
        } elsif (/^clonemethod=(.*)\z/) {
            $clonemethod = $1;
        }
    }
    if ($cfginfo->{storageformat}) {
        $format = $cfginfo->{storageformat};
    }
    return $format;
}

sub xhrm_satisfy {
    my $node    = shift;
    my $hyp     = shift;
    my $rc      = 0;
    my @nics    = ();
    my @storage = ();
    if ($confdata->{vm}->{$node}->[0]->{nics}) {
        @nics = split /,/, $confdata->{vm}->{$node}->[0]->{nics};
    }

    $rc |= system("scp $::XCATROOT/share/xcat/scripts/xHRM $hyp:/usr/bin");

    foreach (@nics) {
        s/=.*//;    #this code cares not about the model of virtual nic
        my $nic = $_;
        my $vlanip;
        my $netmask;
        my $subnet;
        my $vlan;
        my $interface;
        if ($nic =~ /^vl([\d]+)$/) {
            $vlan = $1;
            my $nwtab = xCAT::Table->new("networks", -create => 0);
            if ($nwtab) {
                my $sent = $nwtab->getAttribs({ vlanid => "$vlan" }, 'net', 'mask');
                if ($sent and ($sent->{net})) {
                    $subnet  = $sent->{net};
                    $netmask = $sent->{mask};
                }
                if (($subnet) && ($netmask)) {
                    my $hoststab = xCAT::Table->new("hosts", -create => 0);
                    if ($hoststab) {
                        my $tmp = $hoststab->getNodeAttribs($hyp, ['otherinterfaces']);
                        if (defined($tmp) && ($tmp) && $tmp->{otherinterfaces})
                        {
                            my $otherinterfaces = $tmp->{otherinterfaces};
                            my @itf_pairs = split(/,/, $otherinterfaces);
                            foreach (@itf_pairs) {
                                my ($name, $vip) = split(/:/, $_);
                                if (xCAT::NetworkUtils->ishostinsubnet($vip, $netmask, $subnet)) {
                                    $vlanip = $vip;
                                    last;
                                }
                            }
                        }
                    }

                    #get the vlan ip from nics table
                    unless ($vlanip) {
                        my $nicstable = xCAT::Table->new("nics", -create => 0);
                        if ($nicstable) {
                            my $tmp = $nicstable->getNodeAttribs($hyp, ['nicips']);
                            if ($tmp && $tmp->{nicips}) {
                                $tmp =~ /vl${vlan}nic!([^,]*)/;
                                $vlanip = $1;
                            }
                        }
                    }
                }
            }
        }

        #get the nic that vlan tagged
        my $swtab = xCAT::Table->new("switch", -create => 0);
        if ($swtab) {
            my $tmp_switch = $swtab->getNodesAttribs([$hyp], [ 'vlan', 'interface' ]);
            if (defined($tmp_switch) && (exists($tmp_switch->{$hyp}))) {
                my $tmp_node_array = $tmp_switch->{$hyp};
                foreach my $tmp (@$tmp_node_array) {
                    if (exists($tmp->{vlan})) {
                        my $vlans = $tmp->{vlan};
                        foreach my $vlan_tmp (split(',', $vlans)) {
                            if ($vlan_tmp == $vlan) {
                                if (exists($tmp->{interface})) {
                                    $interface = $tmp->{interface};
                                }
                                last;
                            }
                        }
                    }
                }
            }
        }

        if (($interface) || ($interface =~ /primary/)) {
            $interface =~ s/primary(:)?//g;
        }

        #print "interface=$interface nic=$nic vlanip=$vlanip netmask=$netmask\n";
        if ($interface) {
            $rc |= system("ssh $hyp xHRM bridgeprereq $interface:$nic $vlanip $netmask");
        } else {
            $rc |= system("ssh $hyp xHRM bridgeprereq $nic $vlanip $netmask");
        }

        #TODO: surprise! there is relatively undocumented libvirt capability for this...
        #./tests/interfaceschemadata/ will have to do in lieu of documentation..
        #note that RHEL6 is where that party starts
        #of course, they don't have a clean 'migrate from normal interface to bridge' capability
        #consequently, would have to have some init script at least pre-bridge it up..
        #even then, may not be able to intelligently modify the bridge remotely, so may still not be feasible for our use..
        #this is sufficiently hard, punting to 2.6 at least..
    }
    return $rc;
}

sub makedom {
    my $node  = shift;
    my $cdloc = shift;
    my $xml   = shift;
    my $dom;
    my $errstr;
    if (not $xml and $confdata->{kvmnodedata}->{$node} and $confdata->{kvmnodedata}->{$node}->[0] and $confdata->{kvmnodedata}->{$node}->[0]->{xml}) {

        #we do this to trigger storage prereq fixup
        if (defined $confdata->{vm}->{$node}->[0]->{storage} and ($confdata->{vm}->{$node}->[0]->{storage} =~ /^nfs:/ or $confdata->{vm}->{$node}->[0]->{storage} =~ /^dir:/ or $confdata->{vm}->{$node}->[0]->{storage} =~ /^lvm:/)) {
            if ($confdata->{vm}->{$node}->[0]->{master}) {
                my $vmmastertab = xCAT::Table->new('vmmaster', -create => 0);
                my $masterent;
                if ($vmmastertab) {
                    $masterent = $vmmastertab->getAttribs({ name => $confdata->{vm}->{$node}->[0]->{master} }, ['storage']);
                }
                if ($masterent and $masterent->{storage}) {
                    foreach (split /,/, $masterent->{storage}) {
                        s/=.*//;
                        get_storage_pool_by_url($_);
                    }
                }
            }
            my $urls = $confdata->{vm}->{$node}->[0]->{storage} and $confdata->{vm}->{$node}->[0]->{storage};
            foreach (split /,/, $urls) {
                s/=.*//;
                get_storage_pool_by_url($_);
            }
        }
        $xml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
        my $newxml = reconfigvm($node, $xml);
        if ($newxml) {
            $xml = $newxml;
        }
    } elsif (not $xml) {
        ($xml, $errstr) = build_xmldesc($node, cd => $cdloc);
        if ($errstr) {
            return (1, $errstr);
        }
    }
    my $parseddom = $parser->parse_string($xml);
    my ($graphics) = $parseddom->findnodes("//graphics");
    if (defined($graphics)) {
        if ($confdata->{vm}->{$node}->[0]->{vidpassword}) {
            $graphics->setAttribute("passwd", $confdata->{vm}->{$node}->[0]->{vidpassword});
        } else {
            $graphics->setAttribute("passwd", genpassword(20));
        }
        $graphics->setAttribute("listen", '0.0.0.0');
    }
    $xml = $parseddom->toString();
    eval {
        if ($::XCATSITEVALS{persistkvmguests}) {
            $dom = $hypconn->define_domain($xml);
            $dom->create()
        } else {
            $dom = $hypconn->create_domain($xml);
        }
    };
    if ($@) { $errstr = $@; }
    if (ref $errstr) {
        $errstr = ":" . $errstr->{message};
    }
    if ($errstr) { return (undef, $errstr); }
    if ($dom) {
        refresh_vm($dom);
    }
    return $dom, undef;
}

sub createstorage {

    #svn rev 6638 held the older vintage of createstorage
    #print "createstorage called\n";
    my $filename   = shift;
    my $mastername = shift;
    my $size       = shift;
    my $cfginfo    = shift;
    my $force      = shift;

    my $node = $cfginfo->{node};
    my $mountpath;
    my $pathappend;
    my $format = getstorageformat($cfginfo);

    #for nfs paths and qemu-img, we do the magic locally only for now
    my $basename;
    my $dirname;
    if ($mastername and $size) {
        return 1, "Can not specify both a master to clone and size(s)";
    }
    $filename =~ s/=(.*)//;
    my $model = $1;
    unless ($model) {

        #if not defined, model will stay undefined like above
        $model = $cfginfo->{storagemodel};
    }
    my $prefix = 'hd';
    if ($model eq 'scsi') {
        $prefix = 'sd';
    } elsif ($model eq 'virtio') {
        $prefix = 'vd';
    }
    my @suffixes = ('a', 'b', 'd' .. 'zzz');
    if ($filename =~ /^nfs:/ or $filename =~ /^dir:/ or $filename =~ /^lvm:/) { #libvirt storage pool to be used for this
        my @sizes = split /,/, $size;
        foreach (@sizes) {
            get_filepath_by_url(url => $filename, dev => $prefix . shift(@suffixes), create => $_, force => $force, format => $format);
        }
    } else {
        oldCreateStorage($filename, $mastername, $size, $cfginfo, $force);
    }
    my $masterserver;
    if ($mastername) {    #cloning
    }
    if ($size) {          #new volume
    }
}

sub oldCreateStorage {
    my $filename   = shift;
    my $mastername = shift;
    my $size       = shift;
    my $cfginfo    = shift;
    my $force      = shift;
    my $node       = $cfginfo->{node};
    my @flags      = split /,/, $cfginfo->{virtflags};
    foreach (@flags) {

        if (/^imageformat=(.*)\z/) {
            $imgfmt = $1;
        } elsif (/^clonemethod=(.*)\z/) {
            $clonemethod = $1;
        }
    }
    my $mountpath;
    my $pathappend;
    my $storageserver;

    #for nfs paths and qemu-img, we do the magic locally only for now
    my $basename;
    my $dirname;
    ($basename, $dirname) = fileparse($filename);
    unless ($storageserver) {
        if (-f $filename) {
            unless ($force) {
                return 1, "Storage already exists, delete manually or use --force";
            }
            unlink $filename;
        }
    }
    if ($storageserver and $mastername and $clonemethod eq 'reflink') {
        my $rc = system("ssh $storageserver mkdir -p $dirname");
        if ($rc) {
            return 1, "Unable to manage storage on remote server $storageserver";
        }
    } elsif ($storageserver) {
        my @mounts = `mount`;
        my $foundmount;
        foreach (@mounts) {
            if (/^$storageserver:$mountpath/) {
                chomp;
                s/^.* on (\S*) type nfs.*$/$1/;
                $dirname = $_;
                mkpath($dirname . $pathappend);
                $foundmount = 1;
                last;
            }
        }
        unless ($foundmount) {
            return 1, "qemu-img cloning requires that the management server have the directory $mountpath from $storageserver mounted";
        }
    } else {
        mkpath($dirname);
    }
    if ($mastername and $size) {
        return 1, "Can not specify both a master to clone and a size";
    }
    my $masterserver;
    if ($mastername) {
        unless ($mastername =~ /^\// or $mastername =~ /^nfs:/) {
            $mastername = $xCAT_plugin::kvm::masterdir . '/' . $mastername;
        }
        if ($mastername =~ m!nfs://([^/]*)(/.*\z)!) {
            $mastername   = $2;
            $masterserver = $1;
        }
        if ($masterserver ne $storageserver) {
            return 1, "Not supporting cloning between $masterserver and $storageserver at this time, for now ensure master images and target VM images are on the same server";
        }
        my $rc;
        if ($clonemethod eq 'qemu-img') {
            my $dirn;
            my $filn;
            ($filn, $dirn) = fileparse($filename);
            chdir($dirn);
            $rc = system("qemu-img create -f qcow2 -b $mastername $filename");
        } elsif ($clonemethod eq 'reflink') {
            if ($storageserver) {
                $rc = system("ssh $storageserver cp --reflink $mastername $filename");
            } else {
                $rc = system("cp --reflink $mastername $filename");
            }
        }
        if ($rc) {
            return $rc, "Failure creating image $filename from $mastername";
        }
    }
    if ($size) {
        my $rc = system("qemu-img create -f $imgfmt $filename " . getUnits($size, "g", 1024));
        if ($rc) {
            return $rc, "Failure creating image $filename of size $size\n";
        }
    }
}

sub rinv {
    shift;
    my $dom;
    eval {
        $dom = $hypconn->get_domain_by_name($node);
    };
    my $currstate = getpowstate($dom);
    my $currxml;
    if ($currstate eq 'on') {
        $currxml = $dom->get_xml_description();
    } else {
        $currxml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
    }
    unless ($currxml) {
        xCAT::SvrUtils::sendmsg([ 1, "VM does not appear to exist" ], $callback, $node);
        return;
    }
    my $domain = $parser->parse_string($currxml);
    my $uuid   = $domain->findnodes('/domain/uuid')->[0]->to_literal;
    $uuid =~ s/^(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
    xCAT::SvrUtils::sendmsg("UUID/GUID: $uuid", $callback, $node);
    my $cpus = $domain->findnodes('/domain/vcpu')->[0]->to_literal;
    xCAT::SvrUtils::sendmsg("CPUs: $cpus", $callback, $node);
    my $memnode    = $domain->findnodes('/domain/currentMemory')->[0];
    my $maxmemnode = $domain->findnodes('/domain/memory')->[0];

    unless ($memnode) {
        $memnode = $maxmemnode;
    }
    if ($memnode) {
        my $mem = $memnode->to_literal;
        $mem = $mem / 1024;
        xCAT::SvrUtils::sendmsg("Memory: $mem MB", $callback, $node);
    }
    if ($maxmemnode) {
        my $maxmem = $maxmemnode->to_literal;
        $maxmem = $maxmem / 1024;
        xCAT::SvrUtils::sendmsg("Maximum Memory: $maxmem MB", $callback, $node);

    }
    invstorage($domain, $dom);
    invnics($domain);
}

sub get_storage_pool_by_volume {
    my $vol  = shift;
    my $path = $vol->get_path();
    return get_storage_pool_by_path($path);
}

sub get_storage_pool_by_path {

    #attempts to get pool for a volume, returns false on failure
    my $file = shift;
    my $pool;
    return eval {
        my @currpools = $hypconn->list_storage_pools();
        push @currpools, $hypconn->list_defined_storage_pools();
        foreach $pool (@currpools) {
            my $parsedpool = $parser->parse_string($pool->get_xml_description());
            my $currpath = $parsedpool->findnodes("/pool/target/path/text()")->[0]->data;
            if ($currpath eq $file or $file =~ /^$currpath\/[^\/]*$/) {
                return $pool;
            }
        }
        return undef;

        # $pool = $hypconn->get_storage_pool_by_uuid($pooluuid);
    };
}

sub invstorage {
    my $domain = shift;    # the dom obj of XML
    my $dom    = shift;    # the real domain obj
    my @disks = $domain->findnodes('/domain/devices/disk');
    my $disk;
    foreach $disk (@disks) {
        my $name = $disk->findnodes('./target')->[0]->getAttribute("dev");
        my $xref = "";
        my $addr = $disk->findnodes('./address')->[0];
        if ($addr) {
            if ($name =~ /^vd/) {
                $xref = " (v" . $addr->getAttribute("bus") . ":" . $addr->getAttribute('slot') . "." . $addr->getAttribute("function") . ")";
                $xref =~ s/0x//g;
            } else {
                $xref = " (d" . $addr->getAttribute("controller") . ":" . $addr->getAttribute("bus") . ":" . $addr->getAttribute("unit") . ")";
            }
        }

        my @candidatenodes = $disk->findnodes('./source');
        unless (scalar @candidatenodes) {
            next;
        }
        my $file = $candidatenodes[0]->getAttribute('file');
        my $dev  = $candidatenodes[0]->getAttribute('dev');
        my $vollocation;
        my $size;
        my %info;
        if ($file) {    # for the volumn is a file in storage poll
                #we'll attempt to map file path to pool name and volume name
                #fallback to just reporting filename if not feasible
             #libvirt lacks a way to lookup a storage pool by path, so we'll only do so if using the 'default' xCAT scheme with uuid in the path
            $file =~ m!/([^/]*)/($node\..*)\z!;
            my $volname = $2;
            $vollocation = $file;
            eval {
                my $pool     = get_storage_pool_by_path($file);
                my $poolname = $pool->get_name();
                $vollocation = "[$poolname] $volname";
            };

            #at least I get to skip the whole pool mess here
            my $vol = $hypconn->get_storage_volume_by_path($file);
            if ($vol) {
                %info = %{ $vol->get_info() };
            }
        } elsif ($dev) {    # for the volumn is a block device
            $vollocation = $dev;
            %info        = %{ $dom->get_block_info($dev) };
        }

        if ($info{allocation} and $info{capacity}) {
            $size = $info{allocation};
            $size = $size / 1048576;          #convert to MB
            $size = sprintf("%.3f", $size);
            $size .= "/" . ($info{capacity} / 1048576);
        }

        $callback->({
                node => {
                    name => $node,
                    data => {
                        desc     => "Disk $name$xref",
                        contents => "$size MB @ $vollocation",
                      }
                  }
        });
    }
}

sub invnics {
    my $domain = shift;
    my @nics   = $domain->findnodes('/domain/devices/interface');
    my $nic;
    foreach $nic (@nics) {
        my $mac  = $nic->findnodes('./mac')->[0]->getAttribute('address');
        my $addr = $nic->findnodes('./address')->[0];
        my $loc;
        if ($addr) {
            my $bus = $addr->getAttribute('bus');
            $bus =~ s/^0x//;
            my $slot = $addr->getAttribute('slot');
            $slot =~ s/^0x//;
            my $function = $addr->getAttribute('function');
            $function =~ s/^0x//;
            $loc = " at $bus:$slot.$function";
        }
        $callback->({
                node => {
                    name => $node,
                    data => {
                        desc     => "Network adapter$loc",
                        contents => $mac,
                      }
                  }
        });
    }
}

sub rmvm {
    shift;
    @ARGV = @_;
    my $force;
    my $purge;
    GetOptions(
        'f' => \$force,
        'p' => \$purge,
    );
    my $dom;
    eval {
        $dom = $hypconn->get_domain_by_name($node);
    };
    my $currstate = getpowstate($dom);
    my $currxml;
    if ($currstate eq 'on') {
        if ($force) {
            $currxml = $dom->get_xml_description();
            $dom->destroy();
        } else {
            xCAT::SvrUtils::sendmsg([ 1, "Cannot rmvm active guest (use -f argument to force)" ], $callback, $node);
            return;
        }
    } else {
        $currxml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
        unless ($currxml) {
            xCAT::SvrUtils::sendmsg([ 1, "Cannot remove guest vm, no such vm found" ], $callback, $node);
            return;
        }
    }
    if ($purge and $currxml) {
        my $deadman    = $parser->parse_string($currxml);
        my @purgedisks = $deadman->findnodes("/domain/devices/disk/source");
        my $disk;
        foreach $disk (@purgedisks) {
            my $disktype = $disk->parentNode()->getAttribute("device");
            if ($disktype eq "cdrom") { next; }

            my @driver = $disk->parentNode()->findnodes("driver");
            unless ($driver[0]) { next; }
            my $drivertype = $driver[0]->getAttribute("type");
            if (($drivertype eq "raw") || ($disktype eq "block")) { 
                #For raw or block devices, do not remove, even if purge was specified. Log info message.
                xCAT::MsgUtils->trace(0, "i", "Not purging raw or block storage device: $disk");
                next; 
            }
            my $file = $disk->getAttribute("file");
            unless ($file) { 
                xCAT::MsgUtils->trace(0, "w", "Not able to find 'file' attribute value for: $disk");
                next; 
            }

            # try to check the existence first, if cannot find, do nothing.
            # we do retry because we found sometimes the delete might fail
            my $retry = 0;
            my $vol;
            while ($retry < 10) {
                eval { $vol = $hypconn->get_storage_volume_by_path($file); };
                if ($@) {

                    # Cannot find volumn, then stop delete
                    xCAT::MsgUtils->trace(0, "e", "kvm: $@") if ($retry == 0);
                    last;
                }
                if ($vol) {
                    eval {
                        # Need to call get_info() before deleting a volume, without that, delete() will sometimes fail. Issue #455
                        $vol->get_info();
                        $vol->delete();
                    };
                    if ($@) {
                        xCAT::MsgUtils->trace(0, "e", "kvm: $@");
                    }
                }
                $retry++;
            }
        }
    }
    eval { #try to fetch the domain by name even after it has been destroyed, if it is still there it needs an 'undefine'
        $dom = $hypconn->get_domain_by_name($node);
        $dom->undefine();
    };

    $updatetable->{kvm_nodedata}->{'!*XCATNODESTODELETE*!'}->{$node} = 1;
}

sub chvm {
    shift;
    my @addsizes;
    my $resize;
    my $cpucount;
    my @purge;
    my @derefdisks;
    my $memory;
    my $cdrom;
    my $eject;
    my $pcpuset;
    my $numanodeset;
    my $passthrudevices;
    my $devicestodetach;
    @ARGV = @_;
    require Getopt::Long;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");

    if (!GetOptions(
            "a=s"                 => \@addsizes,
            "d=s"                 => \@derefdisks,
            "mem|memory=s"        => \$memory,
            "optical|dvd|cdrom=s" => \$cdrom,
            "eject"               => \$eject,
            "cpus|cpu=s"          => \$cpucount,
            "p=s"                 => \@purge,
            "resize=s"            => \$resize,
            "cpupin=s"            => \$pcpuset,
            "membind=s"           => \$numanodeset,
            "devpassthru=s"       => \$passthrudevices,
            "devdetach=s"         => \$devicestodetach,
        )) {
        my $usage_string = xCAT::Usage->getUsage("chvm");
        my $rsp;
        push @{ $rsp->{data} }, "$usage_string";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;
    }
    if (@derefdisks) {
        xCAT::SvrUtils::sendmsg([ 1, "Detach without purge TODO for kvm" ], $callback, $node);
        return;
    }
    if (@addsizes and @purge) {
        xCAT::SvrUtils::sendmsg([ 1, "Currently adding and purging concurrently is not supported" ], $callback, $node);
        return;
    }


    if (defined $pcpuset) {
        $pcpuset =~ s/["']//g;
        if ("###$pcpuset" eq "###" or $pcpuset =~ /[^\d\,\^\-]/) {
            xCAT::SvrUtils::sendmsg([ 1, "cpu pining: invalid cpuset" ], $callback, $node);
            return;
        }
    }

    if (defined $numanodeset) {
        $numanodeset =~ s/["']//g;
        if ("###$numanodeset" eq "###" or $numanodeset =~ /[^\d\,\^\-]/) {
            xCAT::SvrUtils::sendmsg([ 1, "memory binding: invalid NUMA nodeset" ], $callback, $node);
            return;
        }
    }

    my %useddisks;
    my $dom;
    eval {
        $dom = $hypconn->get_domain_by_name($node);
    };
    my $vmxml;
    if ($dom) {
        $vmxml = $dom->get_xml_description();
    } else {
        $vmxml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
    }
    my $currstate = getpowstate($dom);
    if (defined $confdata->{vm}->{$node}->[0]->{storage}) {
        my $store;
        foreach $store (split /\|/, $confdata->{vm}->{$node}->[0]->{storage}) {
            $store =~ s/,.*//;
            $store =~ s/=.*//;
            if (($store =~ /^nfs:\/\//) || ($store =~ /^dir:\/\//) || ($store =~ /^lvm:/)) {
                my %disks = %{ get_multiple_paths_by_url(url => $store, node => $node) };
                foreach (keys %disks) {
                    $useddisks{ $disks{$_}->{device} } = 1;
                }
            }
        }
    }

    # The function get_multiple_paths_by_url() is used to polulate useddisks hash, 
    # but it only returns disk volumes from kvm host.
    # cdrom is not returned by get_multiple_paths_by_url() but is defined as a disk device
    # in xml definition of the VM.
    # We add cdrom entry to useddisks hash to make sure the device name used by cdrom is not 
    # selected for the new disk about to be added (chvm -a)
    my @cdrom_names = get_cdrom_device_names($vmxml);
    foreach my $cdrom_name (@cdrom_names) {
        $useddisks{$cdrom_name} = 1;
    }

    if (@addsizes) {    #need to add disks, first identify used devnames
        my @diskstoadd;
        my $location = $confdata->{vm}->{$node}->[0]->{storage};
        unless ($location) {
            # Calling add disk for a vm with no storage defined
            xCAT::SvrUtils::sendmsg([ 1, "Can not add storage, vmstorage attribute not defined." ], $callback, $node);
            return;
        }
        $location =~ s/.*\|//; #use the rightmost location for making new devices
        $location =~ s/,.*//;  #no comma specified parameters are valid
        $location =~ s/=(.*)//;    #store model if specified here
        my $model = $1;
        unless ($model) {

            #if not defined, model will stay undefined like above
            $model = $confdata->{vm}->{$node}->[0]->{storagemodel}
        }
        my $prefix = 'hd';
        if ($model eq 'scsi') {
            $prefix = 'sd';
        } elsif ($model eq 'virtio') {
            $prefix = 'vd';
        }
        if ($prefix eq 'hd' and $currstate eq 'on') {
            xCAT::SvrUtils::sendmsg("VM must be powered off to add IDE drives", $callback, $node);
            next;
        }
        my @suffixes;
        if ($prefix eq 'hd') {
            @suffixes = ('a', 'b', 'd' .. 'zzz');
        } else {
            @suffixes = ('a' .. 'zzz');
        }
        my @newsizes;
        foreach (@addsizes) {
            push @newsizes, split /,/, $_;
        }
        my $format = getstorageformat($confdata->{vm}->{$node}->[0]);
        foreach (@newsizes) {
            my $dev;
            do {
                $dev = $prefix . shift(@suffixes);
            } while ($useddisks{$dev});


            #ok, now I need a volume created to attach
            push @diskstoadd, get_filepath_by_url(url => $location, dev => $dev, create => $_, format => $format);
        }

        #now that the volumes are made, must build xml for each and attempt attach if and only if the VM is live
        foreach (@diskstoadd) {
            my $suffix;
            my $format;
            if (/^[^\.]*\.([^\.]*)\.([^\.]*)/) {
                $suffix = $1;
                $format = $2;
            } elsif (/^[^\.]*\.([^\.]*)/) {
                $suffix = $1;
                $format = 'raw';
            }
            if ($confdata->{vm}->{$node}->[0]->{storageformat}) {
                $format = $confdata->{vm}->{$node}->[0]->{storageformat};
            }

            #when creating a new disk not cloned from anything, disable cache as copy on write content similarity is a lost cause...
            my $cachemode = 'none';

            #unless user knows better
            if ($confdata->{vm}->{$node}->[0]->{storagecache}) {
                $cachemode = $confdata->{vm}->{$node}->[0]->{storagecache};
            }
            my $bus;
            if ($suffix =~ /^sd/) {
                $bus = 'scsi';
            } elsif ($suffix =~ /hd/) {
                $bus = 'ide';
            } elsif ($suffix =~ /vd/) {
                $bus = 'virtio';
            }
            my $xml = "<disk type='file' device='disk'><driver name='qemu' type='$format' cache='$cachemode'/><source file='$_'/><target dev='$suffix' bus='$bus'/></disk>";
            if ($currstate eq 'on') {    #attempt live attach
                eval {
                    $dom->attach_device($xml);
                };
                if ($@) {
                    my $err = $@;
                    if ($err =~ /No more available PCI addresses/) {
                        xCAT::SvrUtils::sendmsg([ 1, "Exhausted Virtio limits trying to add $_" ], $callback, $node);
                    } else {
                        xCAT::SvrUtils::sendmsg([ 1, "Unable to attach $_ because of " . $err ], $callback, $node);
                    }
                    my $file = $_;
                    my $vol  = $hypconn->get_storage_volume_by_path($file);
                    if ($vol) {
                        $vol->delete();
                    }
                }
                $vmxml = $dom->get_xml_description();
            } elsif ($confdata->{kvmnodedata}->{$node}->[0]->{xml}) {
                $vmxml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
                my $disknode    = $parser->parse_balanced_chunk($xml);
                my $vmdoc       = $parser->parse_string($vmxml);
                my $devicesnode = $vmdoc->findnodes("/domain/devices")->[0];
                $devicesnode->appendChild($disknode);
                $vmxml = $vmdoc->toString();
            }
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
        }
    } elsif (@purge) {
        my $dom;
        eval {
            $dom = $hypconn->get_domain_by_name($node);
        };
        my $vmxml;
        if ($dom) {
            $vmxml = $dom->get_xml_description();
        } else {
            $vmxml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
        }
        my $currstate = getpowstate($dom);
        my @disklist = get_disks_by_userspecs(\@purge, $vmxml, 'returnmoddedxml');
        my $moddedxml = shift @disklist;
        foreach (@disklist) {
            my $devxml = $_->[0];
            my $file   = $_->[1];
            $file =~ m!/([^/]*)/($node\..*)\z!;

            #first, detach the device.
            eval {
                if ($currstate eq 'on') {
                    $dom->detach_device($devxml);
                    $vmxml = $dom->get_xml_description();
                } else {
                    $vmxml = $moddedxml;
                }
                $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
            };
            if ($@) {
                xCAT::SvrUtils::sendmsg([ 1, "Unable to remove device" ], $callback, $node);
            } else {

                #if that worked, remove the disk..
                my $vol = $hypconn->get_storage_volume_by_path($file);
                if ($vol) {
                    $vol->delete();
                }
            }

        }
    }
    my $newcdxml;
    if ($cdrom) {
        my $cdpath;
        if ($cdrom =~ m!://!) {
            my $url = $cdrom;
            $url =~ s!([^/]+)\z!!;
            my $imagename = $1;
            my $poolobj   = get_storage_pool_by_url($url);
            unless ($poolobj) { die "Cound not get storage pool for $url"; }
            my $poolxml = $poolobj->get_xml_description(); #yes, I have to XML parse for even this...
            my $parsedpool = $parser->parse_string($poolxml);
            $cdpath = $parsedpool->findnodes("/pool/target/path/text()")->[0]->data;
            $cdpath .= "/" . $imagename;
        } else {
            if ($cdrom =~ m!^/dev/!) {
                die "TODO: device pass through if anyone cares";
            } elsif ($cdrom =~ m!^/!) {                    #full path... I guess
                $cdpath = $cdrom;
            } else {
                die "TODO: relative paths, use client cwd as hint?";
            }
        }
        unless ($cdpath) {
            die "unable to understand cd path specification";
        }
        $newcdxml = "<disk type='file' device='cdrom'><source file='$cdpath'/><target dev='hdc'/><readonly/></disk>";
    } elsif ($eject) {
        $newcdxml = "<disk type='file' device='cdrom'><target dev='hdc'/><readonly/></disk>";
    }
    if ($newcdxml) {
        if ($currstate eq 'on') {
            $dom->attach_device($newcdxml);
            $vmxml = $dom->get_xml_description();
        } else {
            unless ($vmxml) {
                $vmxml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
            }
            my $domparsed = $parser->parse_string($vmxml);
            my $candidatenodes = $domparsed->findnodes("//disk[\@device='cdrom']");
            if (scalar(@$candidatenodes) != 1) {
                die "shouldn't be possible, should only have one cdrom";
            }
            my $newcd = $parser->parse_balanced_chunk($newcdxml);
            $candidatenodes->[0]->replaceNode($newcd);
            my $moddedxml = $domparsed->toString;
            if ($moddedxml) {
                $vmxml = $moddedxml;
            }
        }
        if ($vmxml) {
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
        }
    }
    if ($resize) {
        my $shrinking_not_supported = "qcow2 doesn't support shrinking images yet";
        # Get a list of disk=size pairs
        my @resize_disks = split(/,/, $resize);
        for my $single_disk (@resize_disks) {
            # For each comma separated disk, get disk name and the size to change it to
            my ($disk_to_resize, $value) = split(/=/, $single_disk);
            if ($disk_to_resize) {
                unless (exists $useddisks{$disk_to_resize}) {
                    # Disk name given does not match any disks for this vm
                    xCAT::SvrUtils::sendmsg([ 1, "Disk $disk_to_resize does not exist" ], $callback, $node);
                    next;
                }
                # Get desired (new) disk size
                $value = getUnits($value, "G", 1);
                # Now search kvm_nodedata table to find the volume for this disk
                my $myxml    = $parser->parse_string($vmxml);
                my @alldisks = $myxml->findnodes("/domain/devices/disk");
                # Look through all the disk entries
                foreach my $disknode (@alldisks) {
                    my $devicetype = $disknode->getAttribute("device");
                    # Skip cdrom devices
                    if ($devicetype eq "cdrom") { next; }
                    # Get name of the disk
                    my $diskname = $disknode->findnodes('./target')->[0]->getAttribute('dev');
                    # Is this a disk we were looking for to resize ?
                    if ($diskname eq $disk_to_resize) {
                        my $file = $disknode->findnodes('./source')->[0]->getAttribute('file');
                        my $vol = $hypconn->get_storage_volume_by_path($file);
                        if ($vol) {
                            # Always pass RESIZE_SHRINK flag to resize(). It is required when shrinking
                            # the volume size and is ignored when growing volume size
                            eval {
                                $vol->resize($value, &Sys::Virt::StorageVol::RESIZE_SHRINK);
                            };
                            if ($@) {
                                if ($@ =~ /$shrinking_not_supported/) {
                                    # qcow2 does not support shrinking volumes, display more readable error
                                    xCAT::SvrUtils::sendmsg([ 1, "Resizing disk $disk_to_resize failed, $shrinking_not_supported" ], $callback, $node);
                                }
                                else {
                                    # some other resize error from libvirt, just display it
                                    xCAT::SvrUtils::sendmsg([ 1, "Resizing disk $disk_to_resize failed, $@" ], $callback, $node);
                                }
                            }
                            else {
                                # success
                                xCAT::SvrUtils::sendmsg([ 0, "Resized disk $disk_to_resize" ], $callback, $node);
                            }
                        }
                        last; # Found the disk we were looking for. Go to the next disk.
                    }
                }
            }
        }
    }
    if ($cpucount or $memory) {
        if ($currstate eq 'on') {
            if ($cpucount) { xCAT::SvrUtils::sendmsg([ 1, "Hot add of cpus not supported (VM must be powered down to successfuly change)" ], $callback, $node); }
            if ($cpucount) {

                #$dom->set_vcpus($cpucount); this didn't work out as well as I hoped..
                #xCAT::SvrUtils::sendmsg([1,"Hot add of cpus not supported"],$callback,$node);
            }
            if ($memory) {
                eval {
                    $dom->set_memory(getUnits($memory, "M", 1024));
                };
                if ($@) {
                    if ($@ =~ /cannot set memory higher/) {
                        xCAT::SvrUtils::sendmsg([ 1, "Unable to increase memory beyond current capacity (requires VM to be powered down to change)" ], $callback, $node);
                    }
                } else {
                    if ($confdata->{vm}->{$node}->[0]->{memory} and $confdata->{vm}->{$node}->[0]->{memory} != $memory) {
                        $updatetable->{vm}->{$node}->{memory} = $memory;
                    }
                }
                $vmxml = $dom->get_xml_description();
                if ($vmxml) {
                    $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
                }
            }
        } else {    #offline xml edits
            my $parsed = $parser->parse_string($vmxml); #TODO: should only do this once, oh well
            if ($cpucount) {
                my $hypcpumodel = $confdata->{ $confdata->{vm}->{$node}->[0]->{host} }->{cpumodel};
                if ($hypcpumodel eq "ppc64") {
                    my $cputhreads = $parsed->findnodes("/domain/cpu/topology")->[0]->getAttribute('threads');
                    unless ($cputhreads) {
                        $cputhreads = "1";
                    }
                    $parsed->findnodes("/domain/cpu/topology")->[0]->setAttribute('cores' => $cpucount);
                    $cpucount *= $cputhreads;
                }
                $parsed->findnodes("/domain/vcpu/text()")->[0]->setData($cpucount);
            }
            if ($memory) {
                $parsed->findnodes("/domain/memory/text()")->[0]->setData(getUnits($memory, "M", 1024));
                my @currmem = $parsed->findnodes("/domain/currentMemory/text()");
                foreach (@currmem) {
                    $_->setData(getUnits($memory, "M", 1024));
                }
                if ($confdata->{vm}->{$node}->[0]->{memory} and $confdata->{vm}->{$node}->[0]->{memory} != $memory) {
                    $updatetable->{vm}->{$node}->{memory} = $memory;
                }

            }
            $vmxml = $parsed->toString;
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
        }
    }


    if (defined $pcpuset) {
        if ($currstate eq 'on') {

            #get the vcpuinfo of the domain
            my @vcpuinfo;
            eval { @vcpuinfo = $dom->get_vcpu_info(); };
            if ($@) {
                xCAT::SvrUtils::sendmsg([ 1, "$@" ], $callback, $node);
                return;
            }

            #get the cpuinfo of the host
            my ($totcpus, $onlinemap, $totonline);
            eval { ($totcpus, $onlinemap, $totonline) = $hypconn->get_node_cpu_map(); };
            if ($@) {
                xCAT::SvrUtils::sendmsg([ 1, "$@" ], $callback, $node);
                return;
            }

            #convert the cpuset to bitmap,which is required by pin_vcpu()
            my @pcpumaparr = (0) x $totcpus;
            my @cpurange = split ",", $pcpuset;
            foreach my $rangeslice (@cpurange) {
                if ($rangeslice =~ /^(\d*)-(\d*)$/) {
                    my ($left, $right) = ($1, $2);
                    @pcpumaparr[ $left .. $right ] = (1) x ($right - $left + 1);
                } elsif ($rangeslice =~ /^\^(\d*)$/) {
                    if ($pcpumaparr[$1] == 0) {
                        xCAT::SvrUtils::sendmsg([ 1, "\'$rangeslice\' is ignored, please make sure the specified cpu set is correct" ], $callback, $node);
                        return;
                    } else {
                        $pcpumaparr[$1] = 0;
                    }

                } elsif ($rangeslice =~ /^(\d*)$/) {
                    $pcpumaparr[$1] = 1;
                }
            }

            my $pcpumap = join //, @pcpumaparr;
            my $mask = pack("b*", $pcpumap);

            #Pin the virtual CPU given to physical CPUs given
            foreach (@vcpuinfo) {
                eval {
                    $dom->pin_vcpu($_->{number}, $mask);
                };
                if ($@) {
                    xCAT::SvrUtils::sendmsg([ 1, "$@" ], $callback, $node);
                }
            }

            $vmxml = $dom->get_xml_description();
            my $parsed = $parser->parse_string($vmxml);
            my $ref    = $parsed->findnodes("/domain/vcpu");
            $ref->[0]->removeAttribute("cpuset");
            $vmxml = $parsed->toString;
            if ($vmxml) {
                $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
            }
        } else {
            my $parsed = $parser->parse_string($vmxml);
            my $ref    = $parsed->findnodes("/domain/vcpu");
            $ref->[0]->setAttribute("cpuset", $pcpuset);

            #for virtual CPUs which have the vcpupin specified,
            # the cpuset specified by/domain/vcpu/cpuset  will be ignored
            my $ref        = $parsed->findnodes("/domain");
            my $cputuneref = $parsed->findnodes("/domain/cputune");
            $cputuneref->[0]->parentNode->removeChild($cputuneref->[0]);
            $vmxml = $parsed->toString;
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
        }
    }

    if (defined $numanodeset) {
        if ($currstate eq 'on') {
            eval {
                my %tmphash = (Sys::Virt::Domain->NUMA_NODESET => "$numanodeset");
                $dom->set_numa_parameters(\%tmphash);
            };
            if ($@) {
                xCAT::SvrUtils::sendmsg([ 1, "$@" ], $callback, $node);
                return;
            }
            $vmxml = $dom->get_xml_description();
            if ($vmxml) {
                $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
            }
        } else {
            my %numatunehash;
            $numatunehash{memory} = [ { nodeset => "$numanodeset" } ];
            my $numatunexml = XMLout(\%numatunehash, RootName => "numatune");


            my $parsed      = $parser->parse_string($vmxml);
            my $numatuneref = $parsed->findnodes("/domain/numatune");

            if ($numatuneref)
            {
                #/domain/numatune exist,modify the numatune/nodeset
                my $ref = $parsed->findnodes("/domain/numatune/memory");
                $ref->[0]->setAttribute("nodeset", $numanodeset);
            } else {

                #/domain/numatune does not exist,create one
                my $ref          = $parsed->findnodes("/domain");
                my $numatunenode = $parser->parse_balanced_chunk($numatunexml);
                $ref->[0]->appendChild($numatunenode);
            }
            $vmxml = $parsed->toString;
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
        }
    }



    $passthrudevices =~ s/["']//g;
    if (defined $passthrudevices) {
        my @prdevarr = split ",", $passthrudevices;
        unless (scalar @prdevarr) {
            xCAT::SvrUtils::sendmsg([ 1, "device passthrough: no device specified" ], $callback, $node);
            return;
        }

        foreach my $devname (@prdevarr) {
            my $devobj;
            eval {
                $devobj = $hypconn->get_node_device_by_name($devname);
            };
            if ($@) {
                xCAT::SvrUtils::sendmsg([ 1, "$@" ], $callback, $node);
                next;
            }

            my $devxml = $devobj->get_xml_description();
            unless ($devxml) {
                next;
            }



            my $devhash = XMLin($devxml);
            if (defined $devhash->{capability}->{type} and $devhash->{capability}->{type} =~ /pci/i) {
                my %tmphash;
                $tmphash{mode}           = 'subsystem';
                $tmphash{type}           = $devhash->{capability}->{type};
                $tmphash{managed}        = "yes";
                $tmphash{driver}->{name} = "vfio";
                $tmphash{source}->{address}->[0] = \%{ $devhash->{'capability'}->{'iommuGroup'}->{'address'} };

                my $newxml = XMLout(\%tmphash, RootName => "hostdev");

                if ($currstate eq 'on') {

                    #for a running KVM guest, first unbind the device from the existing driver,
                    #reset the device, and bind it
                    #If the <hostdev> description of a PCI device includes the attribute managed='yes',
                    #and the hypervisor driver supports it, then the device is in managed mode, and attempts to
                    #use that passthrough device in an active guest will automatically behave as if nodedev-detach
                    #(guest start, device hot-plug) and nodedev-reattach (guest stop, device hot-unplug)
                    #were called at the right points.
                    #in case the hypervisor driver does not support managed mode, do this explicitly here
                    eval {
                        $devobj->dettach(undef, 0);
                    };
                    if ($@) {
                        xCAT::SvrUtils::sendmsg([ 0, "detaching $devname from host:$@" ], $callback, $node);
                    }

                    eval {
                        $devobj->reset();
                    };
                    if ($@) {
                        xCAT::SvrUtils::sendmsg([ 0, "resetting $devname:$@" ], $callback, $node);
                    }

                    my $flag = 0;
                    if ($dom->is_persistent()) {
                        $flag = &Sys::Virt::Domain::DEVICE_MODIFY_LIVE | &Sys::Virt::Domain::DEVICE_MODIFY_CONFIG;
                    } else {
                        $flag = &Sys::Virt::Domain::DEVICE_MODIFY_LIVE;
                    }

                    eval {
                        $dom->attach_device($newxml, $flag);
                    };
                    if ($@) {
                        xCAT::SvrUtils::sendmsg([ 1, "attaching device to guest:$@" ], $callback, $node);
                        next;
                    } else {
                        $vmxml = $dom->get_xml_description();
                        if ($vmxml) {
                            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
                        }
                        xCAT::SvrUtils::sendmsg([ 0, "passthrough: $devname attached to guest successfully " ], $callback, $node);
                    }

                } else {

                    my $hostdevfound;
                    $hostdevfound = 0;
                    my $parsed = $parser->parse_string($vmxml);
                    my $ref    = $parsed->findnodes("/domain/devices");

                    my @hostdevlist = $ref->[0]->findnodes("./hostdev");

                    #check whether the hostdev existed in guest xml
                    foreach my $hostdevref (@hostdevlist) {
                        my $devaddrref = $hostdevref->findnodes("./source/address");

                        my $domain = $devaddrref->[0]->getAttribute("domain");
                        my $bus    = $devaddrref->[0]->getAttribute("bus");
                        my $slot   = $devaddrref->[0]->getAttribute("slot");
                        my $function = $devaddrref->[0]->getAttribute("function");

                        my $curdevaddr = \%{ $devhash->{'capability'}->{'iommuGroup'}->{'address'} };



                        if (("$curdevaddr->{domain}" eq "$domain") and
                            ("$curdevaddr->{bus}" eq "$bus")   and
                            ("$curdevaddr->{slot}" eq "$slot") and
                            ("$curdevaddr->{function}" eq "$function")) {

                            #hostdev existed in guest xml
                            $hostdevfound = 1;
                            goto PROCESS_HOSTDEV_XML_ATTATCH;
                        }
                    }

                  PROCESS_HOSTDEV_XML_ATTATCH:
                    unless ($hostdevfound) {

                        #hostdev does not exist,add into guest xml
                        my $hostdevnode = $parser->parse_balanced_chunk($newxml);
                        $ref->[0]->appendChild($hostdevnode);
                        $vmxml = $parsed->toString;
                        $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;

                    }


                }
            }

        }
    }

    $devicestodetach =~ s/["']//g;
    if (defined $devicestodetach) {
        my @devarr = split ",", $devicestodetach;
        unless (scalar @devarr) {
            xCAT::SvrUtils::sendmsg([ 1, "device detaching: no device specified" ], $callback, $node);
            return;
        }

        foreach my $devname (@devarr) {
            my $devobj;
            eval {
                $devobj = $hypconn->get_node_device_by_name($devname);
            };
            if ($@) {
                xCAT::SvrUtils::sendmsg([ 1, "$@" ], $callback, $node);
                next;
            }


            my $devxml = $devobj->get_xml_description();
            unless ($devxml) {
                next;
            }

            my $devhash = XMLin($devxml);
            if (defined $devhash->{capability}->{type} and $devhash->{capability}->{type} =~ /pci/i) {
                my %tmphash;
                $tmphash{mode}           = 'subsystem';
                $tmphash{type}           = $devhash->{capability}->{type};
                $tmphash{managed}        = "yes";
                $tmphash{driver}->{name} = "vfio";
                $tmphash{source}->{address}->[0] = \%{ $devhash->{'capability'}->{'iommuGroup'}->{'address'} };

                my $newxml = XMLout(\%tmphash, RootName => "hostdev");
                if ($currstate eq 'on') {
                    my $flag = 0;
                    if ($dom->is_persistent()) {
                        $flag = &Sys::Virt::Domain::DEVICE_MODIFY_LIVE | &Sys::Virt::Domain::DEVICE_MODIFY_CONFIG;
                    } else {
                        $flag = &Sys::Virt::Domain::DEVICE_MODIFY_LIVE;
                    }
                    eval {
                        $dom->detach_device($newxml, $flag);
                    };
                    if ($@) {
                        xCAT::SvrUtils::sendmsg([ 1, "detaching device from guest:$@" ], $callback, $node);
                        next;
                    } else {
                        $vmxml = $dom->get_xml_description();
                        if ($vmxml) {
                            $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
                        }

                        eval {
                            $devobj->reattach();
                        };
                        if ($@) {
                            xCAT::SvrUtils::sendmsg([ 0, "reattaching device to host:$@" ], $callback, $node);
                        }

                        xCAT::SvrUtils::sendmsg([ 0, "devdetach: $devname detached from guest successfully " ], $callback, $node);
                    }

                } else {

                    my $hostdevfound;
                    $hostdevfound = 0;
                    my $hostdevobj;
                    my $parsed = $parser->parse_string($vmxml);
                    my $ref    = $parsed->findnodes("/domain/devices");

                    my @hostdevlist = $ref->[0]->findnodes("./hostdev");

                    #check whether the hostdev existed in guest xml
                    foreach my $hostdevref (@hostdevlist) {
                        my $devaddrref = $hostdevref->findnodes("./source/address");

                        my $domain = $devaddrref->[0]->getAttribute("domain");
                        my $bus    = $devaddrref->[0]->getAttribute("bus");
                        my $slot   = $devaddrref->[0]->getAttribute("slot");
                        my $function = $devaddrref->[0]->getAttribute("function");

                        my $curdevaddr = \%{ $devhash->{'capability'}->{'iommuGroup'}->{'address'} };


                        if (("$curdevaddr->{domain}" eq "$domain") and
                            ("$curdevaddr->{bus}" eq "$bus")   and
                            ("$curdevaddr->{slot}" eq "$slot") and
                            ("$curdevaddr->{function}" eq "$function")) {

                            #hostdev existed in guest xml
                            $hostdevfound = 1;
                            $hostdevobj   = $hostdevref;
                            goto PROCESS_HOSTDEV_XML_DETATCH;
                        }
                    }



                  PROCESS_HOSTDEV_XML_DETATCH:
                    if ($hostdevfound) {

                        #hostdev exist,remove it from guest xml
                        my $hostdevnode = $parser->parse_balanced_chunk($newxml);
                        $hostdevobj->parentNode()->removeChild($hostdevobj);
                        $vmxml = $parsed->toString;
                        $updatetable->{kvm_nodedata}->{$node}->{xml} = $vmxml;
                        xCAT::SvrUtils::sendmsg([ 0, "devdetach: $devname detached from guest $node successfully " ], $callback, $node);

                    } else {
                        xCAT::SvrUtils::sendmsg([ 1, "device detaching: the specified device $devname is not attached to $node yet" ], $callback, $node);
                        return;
                    }
                }

            }
        }
    }
}

#######################################################################
# get_disks_by_userspecs
# Description: get the storage device info ( xml and source file ) of 
#              the user specified disk devices 
# Arguments:   
#              $specs : ref to the user specified disk name list           
#              $xml   : the xml string of the domain
#              $returnmoddedxml : switch on whether to prepend
#              the domain xml with the user specified disk removed
#              to the beginning of the return array  
# Return   :
#              An array with the structure 
#             [
#              <domain xml>(optional: with the user specified disk removed, 
#                           exist only if $returnmoddedxml specified),
#              [<the disk device xml>, <the source file of the disk device>],
#              [<the disk device xml>, <the source file of the disk device>],
#              ...
#             ]
# Example  :   
#             1. my @disklist = get_disks_by_userspecs(\@diskname, $vmxml, 'returnmoddedxml');
#                my $moddedxml = shift @disklist;
#             2. my @disklist = get_disks_by_userspecs(\@diskname, $vmxml)
#
#######################################################################
sub get_disks_by_userspecs {
    my $specs           = shift;
    my $xml             = shift;
    my $returnmoddedxml = shift;
    my $struct          = XMLin($xml, forcearray => 1);
    my $dominf          = $parser->parse_string($xml);
    my @disknodes       = $dominf->findnodes('/domain/devices/disk');
    my @returnxmls;
    foreach my $spec (@$specs) {
        my $disknode;
        foreach $disknode (@disknodes) {
            if ($spec =~ /^.d./) { #vda, hdb, sdc, etc, match be equality to target->{dev}
                if ($disknode->findnodes('./target')->[0]->getAttribute("dev") eq $spec) {
                    push @returnxmls, [ $disknode->toString(), $disknode->findnodes('./source')->[0]->getAttribute('file') ];
                    if ($returnmoddedxml) {
                        $disknode->parentNode->removeChild($disknode);
                    }
                }
            } elsif ($spec =~ /^d(.*)/) {    #delete by scsi unit number..
                my $loc  = $1;
                my $addr = $disknode->findnodes('./address')->[0];
                if ($loc =~ /:/) {           #controller, bus, unit
                    my $controller;
                    my $bus;
                    my $unit;
                    ($controller, $bus, $unit) = split /:/, $loc;
                    if (hex($addr->getAttribute('controller')) == hex($controller) and ($addr->getAttribute('bus')) == hex($bus) and ($addr->getAttribute('unit')) == hex($unit)) {
                        push @returnxmls, [ $disknode->toString(), $disknode->findnodes('./source')->[0]->getAttribute('file') ];
                        if ($returnmoddedxml) {
                            $disknode->parentNode->removeChild($disknode);
                        }
                    }

                } else { #match just on unit number, not helpful on ide as much generally, but whatever
                    if (hex($addr->getAttribute('unit')) == hex($loc)) {
                        push @returnxmls, [ $disknode->toString(), $disknode->findnodes('./source')->[0]->getAttribute('file') ];
                        if ($returnmoddedxml) {
                            $disknode->parentNode->removeChild($disknode);
                        }
                    }
                }
            } elsif ($spec =~ /^v(.*)/) {    #virtio pci selector
                my $slot = $1;
                $slot =~ s/^(.*)://;   #remove pci bus number (not used for now)
                my $bus = $1;
                $slot =~ s/\.0$//;
                my $addr = $disknode->findnodes('./address')->[0];
                if (hex($addr->getAttribute('slot')) == hex($slot) and hex($addr->getAttribute('bus') == hex($bus))) {
                    push @returnxmls, [ $disknode->toString(), $disknode->findnodes('./source')->[0]->getAttribute('file') ];
                    if ($returnmoddedxml) {
                        $disknode->parentNode->removeChild($disknode);
                    }
                }
            }    #other formats TBD
        }
    }
    if ($returnmoddedxml) {    #there are list entries to delete
        unshift @returnxmls, $dominf->toString();
    }
    return @returnxmls;
}

sub promote_vm_to_master {
    my %args   = @_;
    my $target = $args{target};
    my $force  = $args{force};
    my $detach = $args{detach};
    if ($target !~ m!://!) {    #if not a url, use same place as source
        my $sourcedir = $confdata->{vm}->{$node}->[0]->{storage};
        $sourcedir =~ s/=.*//;
        $sourcedir =~ s/,.*//;
        $sourcedir =~ s!/\z!!;
        $target = $sourcedir . "/" . $target;
    }
    unless ($target =~ /^nfs:\/\//) {
        my $rsp;
        push @{ $rsp->{data} }, "VM cloning is only supported for nfs server vmstorage attribute. Current setting is $target";
        xCAT::MsgUtils->message('E', $rsp, $callback);
        return;
    }
    my $dom;
    eval {
        $dom = $hypconn->get_domain_by_name($node);
    };
    if ($dom and not $force) {
        xCAT::SvrUtils::sendmsg([ 1, "VM shut be shut down before attempting to clone (-f to copy unclean disks)" ], $callback, $node);
        return;
    }
    my $xml;
    if ($dom) {
        $xml    = $dom->get_xml_description();
        $detach = 1;                             #can't rebase if vm is on
    } else {
        $xml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
    }
    unless ($xml) {
        xCAT::SvrUtils::sendmsg([ 1, "VM must be created before it can be cloned" ], $callback, $node);
        return;
    }
    my $parsedxml = $parser->parse_string($xml);
    my ($tmpnod) = $parsedxml->findnodes('/domain/uuid/text()');
    if ($tmpnod) {
        $tmpnod->setData("none");    #get rid of the VM specific uuid
    }

    $target =~ m!^(.*)/([^/]*)\z!;
    my $directory  = $1;
    my $mastername = $2;

    ($tmpnod) = $parsedxml->findnodes('/domain/name/text()');
    if ($tmpnod) {
        $tmpnod->setData($mastername); #name the xml whatever the master name is to be
    }
    foreach ($parsedxml->findnodes("/domain/devices/interface/mac")) { #clear all mac addresses
        if ($_->hasAttribute("address")) { $_->setAttribute("address" => ''); }
    }
    my $poolobj = get_storage_pool_by_url($directory);
    unless ($poolobj) {
        xCAT::SvrUtils::sendmsg([ 1, "Unable to reach $directory from hypervisor" ], $callback, $node);
        return;
    }

    #arguments validated, on with our lives
    #firrder of business, calculate all the image names to be created and ensure none will conflict.
    my @disks = $parsedxml->findnodes('/domain/devices/disk/source');
    my %volclonemap;
    foreach (@disks) {
        my $filename = $_->getAttribute('file');
        my $volname  = $filename;
        $volname =~ s!.*/!!;    #perl is greedy by default
        $volname =~ s/^$node/$mastername/;
        my $novol;
        eval { #use two evals, there is a chance the pool has a task blocking refresh like long-running clone.... libvirt should do better IMO, oh well
            $poolobj->refresh();
        };
        eval {
            $novol = $poolobj->get_volume_by_name($volname);
        };
        if ($novol) {
            xCAT::SvrUtils::sendmsg([ 1, "$volname already exists in target storage pool" ], $callback, $node);
            return;
        }
        my $sourcevol;
        eval {
            $sourcevol = $hypconn->get_storage_volume_by_path($filename);
        };
        unless ($sourcevol) {
            xCAT::SvrUtils::sendmsg([ 1, "Unable to access $filename to clone" ], $callback, $node);
            return;
        }
        $volclonemap{$filename} = [ $sourcevol, $volname ];
        $filename = get_path_for_pool($poolobj);
        $filename =~ s!/\z!!;
        $filename .= '/' . $volname;
        $_->setAttribute(file => $filename);
    }
    foreach (keys %volclonemap) {
        my $sourcevol = $volclonemap{$_}->[0];
        my $targname  = $volclonemap{$_}->[1];
        my $format;
        $targname =~ /([^\.]*)$/;
        $format = $1;
        my $newvol;
        my %sourceinfo = %{ $sourcevol->get_info() };
        my $targxml = "<volume><name>$targname</name><target><format type='$format'/></target><capacity>" . $sourceinfo{capacity} . "</capacity></volume>";
        xCAT::SvrUtils::sendmsg("Cloning " . $sourcevol->get_name() . " (currently is " . ($sourceinfo{allocation} / 1048576) . " MB and has a capacity of " . ($sourceinfo{capacity} / 1048576) . "MB)", $callback, $node);
        eval {
            $newvol = $poolobj->clone_volume($targxml, $sourcevol);
        };
        if ($newvol) {
            %sourceinfo = %{ $newvol->get_info() };
            xCAT::SvrUtils::sendmsg("Cloning of " . $sourcevol->get_name() . " complete (clone uses " . ($sourceinfo{allocation} / 1048576) . " for a disk size of " . ($sourceinfo{capacity} / 1048576) . "MB)", $callback, $node);
            unless ($detach) {
                my $rebasepath = $sourcevol->get_path();
                my $rebasename = $sourcevol->get_name();
                my $rebasepool = get_storage_pool_by_volume($sourcevol);
                unless ($rebasepool) {
                    xCAT::SvrUtils::sendmsg([ 1, "Skipping rebase of $rebasename, unable to find correct storage pool" ], $callback, $node);
                    next;
                }
                xCAT::SvrUtils::sendmsg("Rebasing $rebasename from master", $callback, $node);
                $sourcevol->delete();
                my $newbasexml = "<volume><name>$rebasename</name><target><format type='$format'/></target><capacity>" . $sourceinfo{capacity} . "</capacity><backingStore><path>" . $newvol->get_path() . "</path><format type='$format'/></backingStore></volume>";
                my $newbasevol;
                eval {
                    $newbasevol = $rebasepool->create_volume($newbasexml);
                };
                if ($newbasevol) {
                    xCAT::SvrUtils::sendmsg("Rebased $rebasename from master", $callback, $node);
                } else {
                    xCAT::SvrUtils::sendmsg([ 1, "Critical failure, rebasing process failed halfway through, source VM trashed" ], $callback, $node);
                }
            }
        } else {
            xCAT::SvrUtils::sendmsg([ 1, "Cloning of " . $sourcevol->get_name() . " failed due to " . $@ ], $callback, $node);
            return;
        }
    }
    my $mastertabentry = {};
    foreach (qw/os arch profile/) {
        if (defined($confdata->{nodetype}->{$node}->[0]->{$_})) {
            $mastertabentry->{$_} = $confdata->{nodetype}->{$node}->[0]->{$_};
        }
    }
    foreach (qw/storagemodel nics/) {
        if (defined($confdata->{vm}->{$node}->[0]->{$_})) {
            $mastertabentry->{$_} = $confdata->{vm}->{$node}->[0]->{$_};
        }
    }
    $mastertabentry->{storage}    = $directory;
    $mastertabentry->{vintage}    = localtime;
    $mastertabentry->{originator} = $requester;
    unless ($detach) {
        $updatetable->{vm}->{$node}->{master} = $mastername;
    }
    $updatetable->{vmmaster}->{$mastername} = $mastertabentry;
    $updatetable->{kvm_masterdata}->{$mastername}->{xml} = $parsedxml->toString();
}

sub clonevm {
    shift;    #throw away node
    @ARGV = @_;
    my $target;
    my $base;
    my $detach;
    my $force;
    GetOptions(
        'f'   => \$force,
        'b=s' => \$base,
        't=s' => \$target,
        'd'   => \$detach,
    );
    if ($base and $target) {
        xCAT::SvrUtils::sendmsg([ 1, "Cannot specify both base (-b) and target (-t)" ], $callback, $node);
        return;
    }
    if ($target) {    #we need to take a single vm and create a master out of it
        return promote_vm_to_master(target => $target, force => $force, detach => $detach);
    } elsif ($base) {
        return clone_vm_from_master(base => $base, detach => $detach);
    }
}

sub clone_vm_from_master {
    my %args         = @_;
    my $base         = $args{base};
    my $detach       = $args{detach};
    my $vmmastertab  = xCAT::Table->new('vmmaster', -create => 0);
    my $kvmmastertab = xCAT::Table->new('kvm_masterdata', -create => 0);
    unless ($vmmastertab and $kvmmastertab) {
        xCAT::SvrUtils::sendmsg([ 1, "No KVM master images in tables" ], $callback, $node);
        return;
    }
    my $mastername = $base;
    $mastername =~ s!.*/!!; #shouldn't be needed, as storage is in there, but just in case
    my $masteref = $vmmastertab->getAttribs({ name => $mastername }, [qw/os arch profile storage storagemodel nics/]);
    my $kvmmasteref = $kvmmastertab->getAttribs({ name => $mastername }, ['xml']);
    unless ($masteref and $kvmmasteref) {
        xCAT::SvrUtils::sendmsg([ 1, "KVM master $mastername not found in tables" ], $callback, $node);
        return;
    }
    my $newnodexml = $parser->parse_string($kvmmasteref->{xml});
    $newnodexml->findnodes("/domain/name/text()")->[0]->setData($node); #set name correctly
    my $uuid = getNodeUUID($node);
    $newnodexml->findnodes("/domain/uuid/text()")->[0]->setData($uuid); #put in correct uuid
        #set up mac addresses and such right...
    fixup_clone_network(mastername => $mastername, mastertableentry => $masteref, kvmmastertableentry => $kvmmasteref, xmlinprogress => $newnodexml);

    #ok, now the fun part, storage...
    my $disk;
    if ($masteref->{storage}) {
        foreach (split /,/, $masteref->{storage}) {
            s/=.*//;
            get_storage_pool_by_url($_);
        }
    }
    my $url;
    if ($confdata->{vm}->{$node}->[0]->{storage}) {
        unless ($confdata->{vm}->{$node}->[0]->{storage} =~ /^nfs:/) {
            die "not implemented";
        }
        $url = $confdata->{vm}->{$node}->[0]->{storage};
    } else {
        $url = $masteref->{storage};
        $updatetable->{vm}->{$node}->{storage} = $url;
    }
    if ($masteref->{storagemodel} and not $confdata->{vm}->{$node}->[0]->{storagemodel}) {
        $updatetable->{vm}->{$node}->{storagemodel} = $masteref->{storagemodel};
    }
    $url =~ s/,.*//;
    my $destinationpool = get_storage_pool_by_url($url);
    foreach $disk ($newnodexml->findnodes("/domain/devices/disk")) {
        my ($source) = ($disk->findnodes("./source"));
        unless ($source) { next; }    #most likely an empty cdrom
        my $srcfilename = $source->getAttribute("file");
        my $filename    = $srcfilename;
        $filename =~ s/^.*$mastername/$node/;
        $filename =~ m!\.([^\.]*)\z!;
        my $format = $1;
        my $newvol;

        if ($detach) {
            my $sourcevol  = $hypconn->get_storage_volume_by_path($srcfilename);
            my %sourceinfo = %{ $sourcevol->get_info() };
            my $targxml = "<volume><name>$filename</name><target><format type='$format'/></target><capacity>" . $sourceinfo{capacity} . "</capacity></volume>";
            xCAT::SvrUtils::sendmsg("Cloning " . $sourcevol->get_name() . " (currently is " . ($sourceinfo{allocation} / 1048576) . " MB and has a capacity of " . ($sourceinfo{capacity} / 1048576) . "MB)", $callback, $node);
            eval {
                $newvol = $destinationpool->clone_volume($targxml, $sourcevol);
            };
            if ($@) {
                if ($@ =~ /already exists/) {
                    return 1, "Storage creation request conflicts with existing file(s)";
                } else {
                    return 1, "Unknown issue $@";
                }
            }
        } else {
            my $sourcevol  = $hypconn->get_storage_volume_by_path($srcfilename);
            my %sourceinfo = %{ $sourcevol->get_info() };
            my $newbasexml = "<volume><name>$filename</name><target><format type='$format'/></target><capacity>" . $sourceinfo{capacity} . "</capacity><backingStore><path>$srcfilename</path><format type='$format'/></backingStore></volume>";
            eval {
                $newvol = $destinationpool->create_volume($newbasexml);
            };
            if ($@) {
                if ($@ =~ /already in use/) {
                    return 1, "Storage creation request conflicts with existing file(s)";
                } else {
                    return 1, "Unknown issue $@";
                }
            }
            $updatetable->{vm}->{$node}->{master} = $mastername;
        }
        my $newfilename = $newvol->get_path();
        $disk->findnodes("./source")->[0]->setAttribute("file" => $newfilename);
        if (not $detach) { #if we are a copied image, enable writethrough cache in order to reduce trips out to disk
                #but if the format is not qcow2, still leave it at 'none'
            my $type = $disk->findnodes("./driver")->[0]->getAttribute("type");
            if ($type eq "qcow2") { $disk->findnodes("./driver")->[0]->setAttribute("cache" => "writethrough"); }
        }

    }
    my $textxml = $newnodexml->toString();
    $updatetable->{kvm_nodedata}->{$node}->{xml} = $textxml;

}

sub fixup_clone_network {
    my %args        = @_;
    my $newnodexml  = $args{xmlinprogress};
    my $mastername  = $args{mastername};
    my $masteref    = $args{mastertableentry};
    my $kvmmasteref = $args{kvmmastertableentry};
    unless (ref($confdata->{vm}->{$node})) {
        $confdata->{vm}->{$node} = [ { nics => $masteref->{nics} } ];
        $updatetable->{vm}->{$node}->{nics} = $masteref->{nics};
    }
    unless ($confdata->{vm}->{$node}->[0]->{nics}) { #if no nic configuration yet, take the one stored in the master
        $confdata->{vm}->{$node}->[0]->{nics} = $masteref->{nics};
        $updatetable->{vm}->{$node}->{nics} = $masteref->{nics};
    }
    my @nics;
    if ($confdata->{vm}->{$node}->[0]->{nics}) { #could still be empty if it came from master that way
        @nics = split /,/, $confdata->{vm}->{$node}->[0]->{nics};
    }
    my @nicsinmaster = $newnodexml->findnodes("/domain/devices/interface");
    if (scalar @nicsinmaster > scalar @nics) { #we don't have enough places to attach nics to..
        xCAT::SvrUtils::sendmsg([ 1, "KVM master $mastername has " . scalar @nicsinmaster . " but this vm only has " . scalar @nics . " defined" ], $callback, $node);
        return;
    }
    my $nicstruct;
    my @macs = xCAT::VMCommon::getMacAddresses($confdata, $node, scalar @nics);
    foreach $nicstruct (@nicsinmaster) {
        my $bridge = shift @nics;
        $bridge =~ s/.*://;
        $bridge =~ s/=.*//;
        $nicstruct->findnodes("./mac")->[0]->setAttribute("address" => shift @macs);
        $nicstruct->findnodes("./source")->[0]->setAttribute("bridge" => $bridge);
    }
    my $nic;
    my $deviceroot = $newnodexml->findnodes("/domain/devices")->[0];
    foreach $nic (@nics) {    #need more xml to throw at it..
        my $type = 'virtio'; #better default fake nic than rtl8139, relevant to most
        $nic =~ s/.*://;     #the detail of how the bridge was built is of no
                             #interest to this segment of code
        if ($confdata->{vm}->{$node}->[0]->{nicmodel}) {
            $type = $confdata->{vm}->{$node}->[0]->{nicmodel};
        }
        if ($nic =~ /=/) {
            ($nic, $type) = split /=/, $nic, 2;
        }
        my $xmlsnippet = "<interface type='bridge'><mac address='" . (shift @macs) . "'/><source bridge='" . $nic . "'/><model type='$type'/></interface>";
        my $chunk = $parser->parse_balanced_chunk($xmlsnippet);
        $deviceroot->appendChild($chunk);
    }
}

sub mkvm {
    shift;    #Throw away first argument
    @ARGV = @_;
    my $disksize;
    my $mastername;
    my $force = 0;
    require Getopt::Long;
    my $memory;
    my $cpucount;
    my $errstr;
    GetOptions(
        'master|m=s' => \$mastername,
        'size|s=s'   => \$disksize,
        "mem=s"      => \$memory,
        "cpus=s"     => \$cpucount,
        'force|f'    => \$force
    );
    if (defined $confdata->{vm}->{$node}->[0]->{othersettings}) {
        my $vmothersettings = $confdata->{vm}->{$node}->[0]->{othersettings};
        if ($vmothersettings =~ /nodefromrscan/) {
            return 1, "this node was defined through rscan, 'mkvm' is not supported.";
        }
    }
    if (defined $confdata->{vm}->{$node}->[0]->{storage}) {
        my $diskname = $confdata->{vm}->{$node}->[0]->{storage};
        if ($diskname =~ /^phy:/) {  #in this case, mkvm should have no argumens
            if ($mastername or $disksize) {
                return 1, "mkvm management of block device storage not implemented";
            }
        }

        #print "force=$force\n";
        my @return;
        if ($mastername or $disksize) {
            eval {
                @return = createstorage($diskname, $mastername, $disksize, $confdata->{vm}->{$node}->[0], $force);
            };
            if ($@) {
                if ($@ =~ /Path (\S+) already exists at /) {
                    return 1, "Storage creation request conflicts with existing file(s) $1. To force remove the existing storage file, rerun mkvm with the -f option.";

                } else {
                    return 1, "Unknown issue $@";
                }
            }

            unless ($confdata->{kvmnodedata}->{$node} and $confdata->{kvmnodedata}->{$node}->[0] and $confdata->{kvmnodedata}->{$node}->[0]->{xml}) {
                my $xml;
                ($xml, $errstr) = build_xmldesc($node, cpus => $cpucount, memory => $memory);
                if ($errstr) {

                    # The caller splits the error message on ":", prepend ":" so that if actual
                    # error message contains ":" it will not be split in the middle
                    return (1, ":" . $errstr);
                }
                $updatetable->{kvm_nodedata}->{$node}->{xml} = $xml;
            }
        }
        my $xml;
        if ($confdata->{kvmnodedata}->{$node} and $confdata->{kvmnodedata}->{$node}->[0] and $confdata->{kvmnodedata}->{$node}->[0]->{xml}) {
            $xml = $confdata->{kvmnodedata}->{$node}->[0]->{xml};
        } else { # ($confdata->{kvmnodedata}->{$node} and $confdata->{kvmnodedata}->{$node}->[0] and $confdata->{kvmnodedata}->{$node}->[0]->{xml}) {
            ($xml, $errstr) = build_xmldesc($node, cpus => $cpucount, memory => $memory);
            if ($errstr) {

                # The caller splits the error message on ":", prepend ":" so that if actual
                # error message contains ":" it will not be split in the middle
                return (1, ":" . $errstr);
            }
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $xml;
        }
        if ($::XCATSITEVALS{persistkvmguests}) {
            $hypconn->define_domain($xml);
        }
        return @return;
    } else {
        if ($mastername or $disksize) {
            return 1, "Requested initialization of storage, but vm.storage has no value for node";
        }
    }
}

sub power {
    @ARGV = @_;
    require Getopt::Long;
    my $cdloc;
    GetOptions('cdrom|iso|c|i=s' => \$cdloc);
    my $subcommand = shift @ARGV;
    my $retstring;
    my $dom;
    eval {
        $dom = $hypconn->get_domain_by_name($node);
    };
    if ($subcommand eq "boot") {
        my $currstate = getpowstate($dom);
        $retstring = $currstate . " ";
        if ($currstate eq "off") {
            $subcommand = "on";
        } elsif ($currstate eq "on") {
            $subcommand = "reset";
        }
    }
    my $errstr;

    if ($subcommand eq 'on') {
        unless ($dom) {
            if ($use_xhrm) {
                if (xhrm_satisfy($node, $hyp)) {
                    return (1, "Failure satisfying networking and storage requirements on $hyp for $node");
                }
            }

            #TODO: here, storage validation is not necessarily performed, consequently, must explicitly do storage validation
            #this worked before I started doing the offline xml store because every rpower on tried to rebuild
            ($dom, $errstr) = makedom($node, $cdloc);
            if ($errstr) { return (1, $errstr); }
            else {
                $allnodestatus{$node} = $::STATUS_POWERING_ON;
            }
        } elsif (not $dom->is_active()) {
            eval{
                $dom->create();
            };
            if($@){
                return (1, "Error: $@");
            }
            $allnodestatus{$node} = $::STATUS_POWERING_ON;
        } else {
            $retstring .= "$status_noop";
        }
    } elsif ($subcommand eq 'off') {
        if ($dom) {
            my $newxml = $dom->get_xml_description();
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $newxml;
            if ($dom->is_active()) {
                eval{
                    $dom->destroy();
                };
                if($@){
                    return (1, "Error: $@");
                }               
                $allnodestatus{$node} = $::STATUS_POWERING_OFF;
            }
            undef $dom;
        } else { $retstring .= "$status_noop"; }
    } elsif ($subcommand eq 'softoff') {
        if ($dom) {
            my $newxml = $dom->get_xml_description();
            $updatetable->{kvm_nodedata}->{$node}->{xml} = $newxml;
            $dom->shutdown();
            $allnodestatus{$node} = $::STATUS_POWERING_OFF;
        } else { $retstring .= "$status_noop"; }
    } elsif ($subcommand eq 'reset') {
        if ($dom && $dom->is_active()) {
            my $oldxml = $dom->get_xml_description();
            my $newxml = reconfigvm($node, $oldxml);

            #This *was* to be clever, but libvirt doesn't even frontend the capability, great...
            unless ($newxml) { $newxml = $oldxml; } #TODO: remove this when the 'else' line can be sanely filled out
            if ($newxml) {    #need to destroy and repower..
                $updatetable->{kvm_nodedata}->{$node}->{xml} = $newxml;
                my $persist = $dom->is_persistent();
                eval {$dom->destroy();};
                if($@){
                    return (1, "Error: $@");
                }
                $allnodestatus{$node} = $::STATUS_POWERING_OFF;
                if ($persist) { $dom->undefine(); }
                undef $dom;
                if ($use_xhrm) {
                    xhrm_satisfy($node, $hyp);
                }
                ($dom, $errstr) = makedom($node, $cdloc, $newxml);
                if ($errstr) { return (1, $errstr); }
                else {
                    $allnodestatus{$node} = $::STATUS_POWERING_ON;
                }

            } else { #no changes, just restart the domain TODO when possible, stupid lack of feature...
            }
            $retstring .= "reset";
        } else { $retstring .= "$status_noop"; }
    } else {
        unless ($subcommand =~ /^stat/) {
            return (1, "Unsupported power directive '$subcommand'");
        }
    }

    unless ($retstring =~ /reset/) {
        $retstring = $retstring . getpowstate($dom);
    }
    return (0, $retstring);
}

sub rscan {
    my $hyper = shift;
    @ARGV = @_;
    my ($write, $update, $create);
    GetOptions(
        'w' => \$write,
        'u' => \$update,
        'n' => \$create,
    );
    my @doms;
    my $dom;
    eval {
        @doms = $hypconn->list_all_domains();
    };
    if ($@) {
        xCAT::SvrUtils::sendmsg([ 1, "Unable to list all domains for $hyper: $@" ], $callback);
    }
    my %host2kvm;
    my @displaymsg;
    my $handle_vmtab;
    $handle_vmtab = xCAT::Table->new("vm", -create => 1, -autocommit => 0);
    if (!$handle_vmtab) {
        xCAT::SvrUtils::sendmsg([ 1, "Can't open vm table" ], $callback, $hyper);
        return;
    }

    #get existing 'node' and 'host' attributes in current vm table...
    my %hash_vm2host;
    my @vm_nodes_hosts = $handle_vmtab->getAllNodeAttribs([ 'node', 'host' ]);
    foreach my $vm_node_host (@vm_nodes_hosts) {
        $hash_vm2host{ $vm_node_host->{node} } = $vm_node_host->{host};
    }

    my @maxlength;
    my @rscan_header = (
        [ "type",       "" ],
        [ "name",       "" ],
        [ "hypervisor", "" ],
        [ "id",         "" ],
        [ "cpu",        "" ],
        [ "memory",     "" ],
        [ "nic",        "" ],
        [ "disk",       "" ]);

    #operate every domain in current hypervisor
    foreach $dom (@doms) {
        my $name    = $dom->get_name();
        my $currxml = $dom->get_xml_description();
        unless ($currxml) {
            xCAT::SvrUtils::sendmsg([ 1, "fail to get the xml definition of $name" ], $callback, $hyper);
            next;
        }
        my $domain = $parser->parse_string($currxml);
        my ($uuid, $node, $vmcpus, $vmmemory, $vmnics, $vmstorage, $arch, $mac, $vmnicnicmodel);
        my @uuidobj = $domain->findnodes("/domain/uuid");
        if (@uuidobj) {
            $uuid = $uuidobj[0]->to_literal;
            $uuid =~ s/^(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
        }
        my $type = $domain->findnodes("/domain")->[0]->getAttribute("type");
        if (length($type) > $maxlength[0]) {
            $maxlength[0] = length($type);
        }
        my @nodeobj = $domain->findnodes("/domain/name");
        if (@nodeobj) {
            $node = $nodeobj[0]->to_literal;
        }
        if (length($node) > $maxlength[1]) {
            $maxlength[1] = length($node);
        }
        my $hypervisor = $hyper;
        if (length($hypervisor) > $maxlength[2]) {
            $maxlength[2] = length($hypervisor);
        }
        my $id = $domain->findnodes("/domain")->[0]->getAttribute("id");
        if (length($id) > $maxlength[3]) {
            $maxlength[3] = length($id);
        }
        my @vmcpusobj = $domain->findnodes("/domain/vcpu");
        if (@vmcpusobj) {
            $vmcpus = $vmcpusobj[0]->to_literal;
        }
        if (length($vmcpus) > $maxlength[4]) {
            $maxlength[4] = length($vmcpus);
        }
        my @vmmemoryobj = $domain->findnodes("/domain/memory");
        if (@vmmemoryobj) {
            my $mem  = $vmmemoryobj[0]->to_literal;
            my $unit = $vmmemoryobj[0]->getAttribute("unit");
            if (($unit eq "KiB") or ($unit eq "k")) {
                $vmmemory = ($mem * 1024) / (1024 * 1024);
            } elsif ($unit eq "KB") {
                $vmmemory = ($mem * 1000) / (1024 * 1024);
            } elsif (($unit eq "MiB") or ($unit eq "M")) {
                $vmmemory = $mem;
            } elsif ($unit eq "MB") {
                $vmmemory = ($mem * 1000000) / (1024 * 1024);
            } elsif (($unit eq "GiB") or ($unit eq "G")) {
                $vmmemory = $mem * 1024;
            } elsif ($unit eq "GB") {
                $vmmemory = ($mem * 1000000000) / (1024 * 1024);
            } elsif (($unit eq "TiB") or ($unit eq "T")) {
                $vmmemory = $mem * 1024 * 1024;
            } elsif ($unit eq "TB") {
                $vmmemory = ($mem * 1000000000000) / (1024 * 1024);
            } else {
                $vmmemory = ($mem * 1024) / (1024 * 1024);
            }
        }
        if (length($vmmemory) > $maxlength[5]) {
            $maxlength[5] = length($vmmemory);
        }
        my @vmstoragediskobjs = $domain->findnodes("/domain/devices/disk");
        foreach my $vmstoragediskobj (@vmstoragediskobjs) {
            my ($vmstorage_file_obj, $vmstorage_block_obj);
            if (($vmstoragediskobj->getAttribute("device") eq "disk") and ($vmstoragediskobj->getAttribute("type") eq "file")) {
                my @vmstorageobj = $vmstoragediskobj->findnodes("./source");
                if (@vmstorageobj) {
                    $vmstorage_file_obj = $vmstorageobj[0]->getAttribute("file");
                }
                $vmstorage .= "$vmstorage_file_obj,";
            }
            if (($vmstoragediskobj->getAttribute("device") eq "disk") and ($vmstoragediskobj->getAttribute("type") eq "block")) {
                my @vmstorageobj = $vmstoragediskobj->findnodes("./source");
                if (@vmstorageobj) {
                    $vmstorage_block_obj = $vmstorageobj[0]->getAttribute("dev");
                }
                $vmstorage .= "$vmstorage_block_obj,";
            }
        }
        chop($vmstorage);
        if (length($vmstorage) > $maxlength[7]) {
            $maxlength[7] = length($vmstorage);
        }
        my @archobj = $domain->findnodes("/domain/os/type");
        if (@archobj) {
            $arch = $archobj[0]->getAttribute("arch");
        }
        my @interfaceobjs = $domain->findnodes("/domain/devices/interface");
        foreach my $interfaceobj (@interfaceobjs) {
            if (($interfaceobj->getAttribute("type")) eq "bridge") {
                my ($vmnics_obj, $mac_obj, $vmnicnicmodel_obj);
                my @vmnicsobj        = $interfaceobj->findnodes("./source");
                my @macobj           = $interfaceobj->findnodes("./mac");
                my @vmnicnicmodelobj = $interfaceobj->findnodes("./model");
                if (@vmnicsobj) {
                    $vmnics_obj = $vmnicsobj[0]->getAttribute("bridge");
                }
                if (@macobj) {
                    $mac_obj = $macobj[0]->getAttribute("address");
                }
                if (@vmnicnicmodelobj) {
                    $vmnicnicmodel_obj = $vmnicnicmodelobj[0]->getAttribute("type");
                }
                $vmnics        .= "$vmnics_obj,";
                $mac           .= "$mac_obj,";
                $vmnicnicmodel .= "$vmnicnicmodel_obj,";
            }
        }
        chop($vmnics);
        chop($mac);
        chop($vmnicnicmodel);
        if (length($vmnics) > $maxlength[6]) {
            $maxlength[6] = length($vmnics);
        }
        push @{ $host2kvm{$uuid} }, join(":", $type, $node, $hypervisor, $id, $vmcpus, $vmmemory, $vmnics, $vmstorage, $arch, $mac, $vmnicnicmodel);
        if ($write) {
            unless (exists $hash_vm2host{$node}) {
                $updatetable->{vm}->{$node}->{host}           = $hypervisor;
                $updatetable->{vm}->{$node}->{storage}        = $vmstorage;
                $updatetable->{vm}->{$node}->{memory}         = $vmmemory;
                $updatetable->{vm}->{$node}->{cpus}           = $vmcpus;
                $updatetable->{vm}->{$node}->{nics}           = $vmnics;
                $updatetable->{vm}->{$node}->{nicmodel}       = $vmnicnicmodel;
                $updatetable->{vm}->{$node}->{othersettings}  = "nodefromrscan";
                $updatetable->{mac}->{$node}->{mac}           = $mac;
                $updatetable->{vpd}->{$node}->{uuid}          = $uuid;
                $updatetable->{nodelist}->{$node}->{groups}   = "vm,all";
                $updatetable->{nodetype}->{$node}->{arch}     = $arch;
                $updatetable->{nodehm}->{$node}->{mgt}        = "kvm";
                $updatetable->{nodehm}->{$node}->{serialport} = "0";
                $updatetable->{nodehm}->{$node}->{serialspeed} = "115200";
                $updatetable->{kvm_nodedata}->{$node}->{xml}   = $currxml;
            }
            else {
                if ($hash_vm2host{$node} eq $hypervisor) {

                    #mark this node to delete in 'vm' 'mac' vpd' 'nodelist' 'nodetype' 'nodehm' tables
                    $updatetable->{vm}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;

                    $updatetable->{vm}->{$node}->{host}     = $hypervisor;
                    $updatetable->{vm}->{$node}->{storage}  = $vmstorage;
                    $updatetable->{vm}->{$node}->{memory}   = $vmmemory;
                    $updatetable->{vm}->{$node}->{cpus}     = $vmcpus;
                    $updatetable->{vm}->{$node}->{nics}     = $vmnics;
                    $updatetable->{vm}->{$node}->{nicmodel} = $vmnicnicmodel;
                    $updatetable->{vm}->{$node}->{othersettings} = "nodefromrscan";
                    $updatetable->{mac}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                    $updatetable->{mac}->{$node}->{mac} = $mac;
                    $updatetable->{vpd}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                    $updatetable->{vpd}->{$node}->{uuid} = $uuid;
                    $updatetable->{nodelist}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                    $updatetable->{nodelist}->{$node}->{groups} = "vm,all";
                    $updatetable->{nodetype}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                    $updatetable->{nodetype}->{$node}->{arch} = $arch;
                    $updatetable->{nodehm}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                    $updatetable->{nodehm}->{$node}->{mgt}         = "kvm";
                    $updatetable->{nodehm}->{$node}->{serialport}  = "0";
                    $updatetable->{nodehm}->{$node}->{serialspeed} = "115200";
                    $updatetable->{kvm_nodedata}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                    $updatetable->{kvm_nodedata}->{$node}->{xml} = $currxml;
                }
                else {
                    $callback->({ data => "the name of KVM guest $node on $hypervisor conflicts with the existing node in xCAT table." });
                }
            }
        }
        if ($update) {
            if ((exists $hash_vm2host{$node}) and ($hash_vm2host{$node} eq $hypervisor)) {
                $updatetable->{vm}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{vm}->{$node}->{host}          = $hypervisor;
                $updatetable->{vm}->{$node}->{storage}       = $vmstorage;
                $updatetable->{vm}->{$node}->{memory}        = $vmmemory;
                $updatetable->{vm}->{$node}->{cpus}          = $vmcpus;
                $updatetable->{vm}->{$node}->{nics}          = $vmnics;
                $updatetable->{vm}->{$node}->{nicmodel}      = $vmnicnicmodel;
                $updatetable->{vm}->{$node}->{othersettings} = "nodefromrscan";
                $updatetable->{mac}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{mac}->{$node}->{mac}                     = $mac;
                $updatetable->{vpd}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{vpd}->{$node}->{uuid}                    = $uuid;
                $updatetable->{nodelist}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{nodelist}->{$node}->{groups} = "vm,all";
                $updatetable->{nodetype}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{nodetype}->{$node}->{arch} = $arch;
                $updatetable->{nodehm}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{nodehm}->{$node}->{mgt}         = "kvm";
                $updatetable->{nodehm}->{$node}->{serialport}  = "0";
                $updatetable->{nodehm}->{$node}->{serialspeed} = "115200";
                $updatetable->{kvm_nodedata}->{'!*XCATNODESTODELETE*!'}->{$node} = $node;
                $updatetable->{kvm_nodedata}->{$node}->{xml} = $currxml;
            }
        }
        if ($create) {
            unless (exists $hash_vm2host{$node}) {
                $updatetable->{vm}->{$node}->{host}           = $hypervisor;
                $updatetable->{vm}->{$node}->{storage}        = $vmstorage;
                $updatetable->{vm}->{$node}->{memory}         = $vmmemory;
                $updatetable->{vm}->{$node}->{cpus}           = $vmcpus;
                $updatetable->{vm}->{$node}->{nics}           = $vmnics;
                $updatetable->{vm}->{$node}->{nicmodel}       = $vmnicnicmodel;
                $updatetable->{vm}->{$node}->{othersettings}  = "nodefromrscan";
                $updatetable->{mac}->{$node}->{mac}           = $mac;
                $updatetable->{vpd}->{$node}->{uuid}          = $uuid;
                $updatetable->{nodelist}->{$node}->{groups}   = "vm,all";
                $updatetable->{nodetype}->{$node}->{arch}     = $arch;
                $updatetable->{nodehm}->{$node}->{mgt}        = "kvm";
                $updatetable->{nodehm}->{$node}->{serialport} = "0";
                $updatetable->{nodehm}->{$node}->{serialspeed} = "115200";
                $updatetable->{kvm_nodedata}->{$node}->{xml}   = $currxml;
            }
        }
    }

    if ((!$write) and (!$update) and (!$create)) {
        my $header;
        $rscan_header[0][1] = sprintf "%%-%ds", ($maxlength[0] + 3);
        $rscan_header[1][1] = sprintf "%%-%ds", ($maxlength[1] + 3);
        $rscan_header[2][1] = sprintf "%%-%ds", ($maxlength[2] + 3);
        $rscan_header[3][1] = sprintf "%%-%ds", ($maxlength[3] + 3);
        $rscan_header[4][1] = sprintf "%%-%ds", ($maxlength[4] + 3);
        $rscan_header[5][1] = sprintf "%%-%ds", ($maxlength[5] + 3);
        $rscan_header[6][1] = sprintf "%%-%ds", ($maxlength[6] + 3);
        $rscan_header[7][1] = sprintf "%%-%ds", ($maxlength[7] + 3);
        foreach (@rscan_header) {
            $header .= sprintf(@$_[1], @$_[0]);
        }
        push @displaymsg, $header;
        foreach (keys %host2kvm) {
            my $entry;
            my $host = $_;
            my $i    = 0;
            my @data;
            foreach (@{ $host2kvm{$host} }) {
                my $info = $_;
                foreach (split(':', $info)) {
                    my $attr = $_;
                    push @data, "$attr";
                }
            }
            foreach (@rscan_header) {
                $entry .= sprintf(@$_[1], $data[ $i++ ]);
            }
            push @displaymsg, $entry;
        }
    }
    $callback->({ data => \@displaymsg });
    return;
}

sub lsvm {
    my $host = shift;
    my $vm = shift;
    my @doms = $hypconn->list_domains();
    my @vms;

    if ($host ne $vm) {
        # Processing lsvm for a VM, display details about that VM
        foreach (@doms) {
            if ($_->get_name() eq $vm) {
                push @vms, "Id:" . $_->get_id();
                push @vms, "Host:" . $host;
                push @vms, "OS:" . $_->get_os_type();
                my $domain_info = $_->get_info();
                if (exists $domain_info->{"memory"}) {
                    push @vms, "Memory:" . $domain_info->{"memory"};
                }
                if (exists $domain_info->{"nrVirtCpu"}) {
                    push @vms, "CPU: " . $domain_info->{"nrVirtCpu"};
                }
                if (exists $domain_info->{"state"}) {
                    my $state =  $domain_info->{"state"};
                    my $state_string;
                    given($state) {
                        when ($state == &Sys::Virt::Domain::STATE_NOSTATE) 
                            {$state_string = "The domain is active, but is not running / blocked (eg idle)";}
                        when ($state == &Sys::Virt::Domain::STATE_RUNNING) 
                            {$state_string = "The domain is active and running";}
                        when ($state == &Sys::Virt::Domain::STATE_BLOCKED) 
                            {$state_string = "The domain is active, but execution is blocked";}
                        when ($state == &Sys::Virt::Domain::STATE_PAUSED) 
                            {$state_string = "The domain is active, but execution has been paused";}
                        when ($state == &Sys::Virt::Domain::STATE_SHUTDOWN) 
                            {$state_string = "The domain is active, but in the shutdown phase";}
                        when ($state == &Sys::Virt::Domain::STATE_SHUTOFF) 
                            {$state_string = "The domain is inactive, and shut down";}
                        when ($state == &Sys::Virt::Domain::STATE_CRUSHED) 
                            {$state_string = "The domain is inactive, and crashed";}
                        when ($state == &Sys::Virt::Domain::STATE_PMSUSPENDED) 
                            {$state_string = "The domain is active, but in power management suspend state";}
                        default {$state_string = "Unknown"};
                    }
                    push @vms, "State :" . $domain_info->{"state"} . " ($state_string)";
                }
                # The following block of code copied from rscan command processng for disks
                my $currxml = $_->get_xml_description();
                if ($currxml) {
                    my $domain = $parser->parse_string($currxml);
                    my @vmstoragediskobjs = $domain->findnodes("/domain/devices/disk");
                    foreach my $vmstoragediskobj (@vmstoragediskobjs) {
                        my ($vmstorage_file_obj, $vmstorage_block_obj);
                        if (($vmstoragediskobj->getAttribute("device") eq "disk") and ($vmstoragediskobj->getAttribute("type") eq "file")) {
                            my @vmstorageobj = $vmstoragediskobj->findnodes("./source");
                            if (@vmstorageobj) {
                                $vmstorage_file_obj = $vmstorageobj[0]->getAttribute("file");
                                push @vms, "Disk file:" . $vmstorage_file_obj;
                            }
                        }
                        if (($vmstoragediskobj->getAttribute("device") eq "disk") and ($vmstoragediskobj->getAttribute("type") eq "block")) {
                            my @vmstorageobj = $vmstoragediskobj->findnodes("./source");
                            if (@vmstorageobj) {
                                $vmstorage_block_obj = $vmstorageobj[0]->getAttribute("dev");
                                push @vms, "Disk object:" . $vmstorage_block_obj;
                            }
                        }
                    }
                }
            }
        }
    }
    else {
        # Processing lsvm for hypervisor, display a list of VMs on that hypervisor
        foreach (@doms) {
            push @vms, $_->get_name();
        }
    }
    # Check if we were able to get any data 
    unless (@vms) {
        push @vms, "Could not get any information about specified object";
    }
    return (0, @vms);
}


sub guestcmd {
    $hyp  = shift;
    $node = shift;
    my $command = shift;
    my @args    = @_;
    my $error;
    if ($command eq "rpower") {
        return power(@args);
    } elsif ($command eq "mkvm") {
        return mkvm($node, @args);
    } elsif ($command eq "clonevm") {
        return clonevm($node, @args);
    } elsif ($command eq "chvm") {
        return chvm($node, @args);
    } elsif ($command eq "rmvm") {
        return rmvm($node, @args);
    } elsif ($command eq "rinv") {
        return rinv($node, @args);
    } elsif ($command eq "rmigrate") {
        return migrate($node, @args);
    } elsif ($command eq "getrvidparms") {
        return getrvidparms($node, @args);
    } elsif ($command eq "getcons") {
        return getcons($node, @args);
    } elsif ($command eq "lsvm") {
        return lsvm($hyp, $node, @args);
    } elsif ($command eq "rscan") {
        return rscan($node, @args);
    }

    return (1, "$command not a supported command by kvm method");
}

sub preprocess_request {
    my $request = shift;
    if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
    my $callback = shift;
    my @requests;

    my $noderange = $request->{node};           #Should be arrayref
    my $command   = $request->{command}->[0];
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    my $usage_string = xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({ data => $usage_string });
        $request = {};
        return;
    }

    if (!$noderange) {
        $usage_string = xCAT::Usage->getUsage($command);
        $callback->({ data => $usage_string });
        $request = {};
        return;
    }

    #print "noderange=@$noderange\n";

    # find service nodes for requested nodes
    # build an individual request for each service node
    my $service = "xcat";
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, $service, "MN");

    # build each request for each service node

    foreach my $snkey (keys %$sn)
    {
        #print "snkey=$snkey\n";
        my $reqcopy = {%$request};
        $reqcopy->{node}                   = $sn->{$snkey};
        $reqcopy->{'_xcatdest'}            = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;
        push @requests, $reqcopy;
    }
    return \@requests;
}


sub adopt {
    my $orphash   = shift;
    my $hyphash   = shift;
    my %addmemory = ();
    my $node;
    my $target;
    my $vmupdates;
    foreach $node (keys %{$orphash}) {
        $target = pick_target($node, \%addmemory);
        unless ($target) {
            next;
        }
        if ($confdata->{vm}->{$node}->[0]->{memory}) {
            $addmemory{$target} += getUnits($confdata->{vm}->{$node}->[0]->{memory}, "M", 1024);
        } else {
            $addmemory{$target} += getUnits("4096", "M", 1024);
        }
        $hyphash{$target}->{nodes}->{$node} = 1;
        delete $orphash->{$node};
        $vmupdates->{$node}->{host} = $target;
    }
    unless ($vmtab) { $vmtab = new xCAT::Table('vm', -create => 1); }
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
    unless ($parser) {
        $parser = XML::LibXML->new();
    }
    %offlinehyps = ();
    %hypstats    = ();
    %offlinevms  = ();
    my $request = shift;
    if ($request->{_xcat_authname}->[0]) {
        $requester = $request->{_xcat_authname}->[0];
    }
    $callback = shift;
    require Sys::Virt;
    if (xCAT::Utils::version_cmp(Sys::Virt->VERSION, "0.2.0") < 0) {
        die;
    }
    require Sys::Virt::Domain;
    %runningstates = (&Sys::Virt::Domain::STATE_NOSTATE => 1, &Sys::Virt::Domain::STATE_RUNNING => 1, &Sys::Virt::Domain::STATE_BLOCKED => 1);

    $doreq = shift;
    my $level     = shift;
    my $noderange = $request->{node};
    my $command   = $request->{command}->[0];
    my @exargs;
    unless ($command) {
        return;    #Empty request
    }
    if (ref($request->{arg})) {
        @exargs = @{ $request->{arg} };
    } else {
        @exargs = ($request->{arg});
    }

    #pdu commands will be handled in the pdu plugin
    if ($command eq "rpower" and grep(/^pduon|pduoff|pdureset|pdustat$/, @exargs)) {
        return;
    }


    my $forcemode = 0;
    my %orphans   = ();
    if ($command eq 'vmstatenotify') {
        unless ($vmtab) { $vmtab = new xCAT::Table('vm', -create => 1); }
        my $state = $exargs[0];
        if ($state eq 'vmoff') {
            $vmtab->setNodeAttribs($exargs[1], { powerstate => 'off' });
            return;
        } elsif ($state eq 'vmon') {
            $vmtab->setNodeAttribs($exargs[1], { powerstate => 'on' });
            return;
        } elsif ($state eq 'hypshutdown') {    #turn this into an evacuate
            my $nodelisttab = xCAT::Table->new('nodelist');
            my $appstatus = $nodelisttab->getNodeAttribs($noderange->[0], ['appstatus']);
            my @apps = split /,/, $appstatus->{'appstatus'};
            my @newapps;
            foreach (@apps) {
                if ($_ eq 'virtualization') { next; }
                push @newapps, $_;
            }
            $nodelisttab->setNodeAttribs($noderange->[0], { appstatus => join(',', @newapps) });
            $command = "revacuate";
            @exargs  = ();
        } elsif ($state eq 'hypstartup') { #if starting up, check for nodes on this hypervisor and start them up
            my $nodelisttab = xCAT::Table->new('nodelist');
            my $appstatus = $nodelisttab->getNodeAttribs($noderange->[0], ['appstatus']);
            my @apps = split /,/, $appstatus->{appstatus};
            unless (grep { $_ eq 'virtualization' } @apps) {
                push @apps, 'virtualization';
                $nodelisttab->setNodeAttribs($noderange->[0], { appstatus => join(',', @apps) });
            }
            my @tents = $vmtab->getAttribs({ host => $noderange->[0], power => 'on' }, ['node']);
            $noderange = [];
            foreach (@tents) {
                push @$noderange, noderange($_->{node});
            }
            $command = "rpower";
            @exargs  = ("on");
        }

    }
    if ($command eq 'revacuate') {
        my $newnoderange;
        if (grep { $_ eq '-f' } @exargs) {
            $forcemode = 1;
        }
        foreach (@$noderange) {
            my $hyp = $_;    #I used $_ too much here... sorry
            $hypconn = undef;
            push @destblacklist, $_;
            if ((not $offlinehyps{$_}) and nodesockopen($_, 22)) {
                eval {       #Contain bugs that won't be in $@
                    $hypconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $_ . "/system?no_tty=1&netcat=nc");
                };
                unless ($hypconn) {    #retry for socat
                    eval {             #Contain bugs that won't be in $@
                        $hypconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $_ . "/system?no_tty=1");
                    };
                }
            }
            unless ($hypconn) {
                $offlinehyps{$hyp} = 1;
                if ($forcemode) { #forcemode indicates the hypervisor is probably already dead, and to clear vm.host of all the nodes, and adopt the ones that are supposed to be 'on', power them on
                    unless ($vmtab) { $vmtab = new xCAT::Table('vm', -create => 0); }
                    unless ($vmtab) { next; }
                    my @vents = $vmtab->getAttribs({ host => $hyp }, [ 'node', 'powerstate' ]);
                    my $vent;
                    my $nodestozap;
                    foreach $vent (@vents) {
                        my @nodes = noderange($vent->{node});
                        if ($vent->{powerstate} eq 'on') {
                            foreach (@nodes) {
                                $offlinevms{$_} = 1;
                                $orphans{$_}    = 1;
                                push @$newnoderange, $_;
                            }
                        }
                        push @$nodestozap, @nodes;
                    }
                    $vmtab->setNodesAttribs($nodestozap, { host => '|^.*$||' });
                } else {
                    $callback->({ node => [ { name => [$_], error => ["Cannot communicate via libvirt to node"] } ] });
                }
                next;
            }
            if ($hypconn) {
                foreach ($hypconn->list_domains()) {
                    my $guestname = $_->get_name();
                    if ($guestname eq 'Domain-0') {
                        next;
                    }
                    push @$newnoderange, $guestname;
                }
            }
        }
        $hypconn   = undef;
        $noderange = $newnoderange;
        $command   = 'rmigrate';
    }

    if ($::XCATSITEVALS{usexhrm}) { $use_xhrm = 1; }
    $vmtab    = xCAT::Table->new("vm");
    $confdata = {};
    unless ($command eq 'rscan') {
        xCAT::VMCommon::grab_table_data($noderange, $confdata, $callback);
        # Add debug info for issue 1958, the rmvm issue
        my $test_file_fd;
        open($test_file_fd, ">> $::XCATROOT//share/xcat/tools/autotest/result/$command.$$.rec");
        print $test_file_fd "====================start==========================\n";
        my $kvmdatatab = xCAT::Table->new("kvm_nodedata", -create => 0); #grab any pertinent pre-existing xml
        if ($kvmdatatab) {
            $confdata->{kvmnodedata} = $kvmdatatab->getNodesAttribs($noderange, [qw/xml/]);
            print $test_file_fd Dumper($confdata->{kvmnodedata});
        } else {
            $confdata->{kvmnodedata} = {};
            print $test_file_fd "***Error: Can not open kvm_nodedata table==\n";
        }
        print $test_file_fd "====================end==========================\n";
        close $test_file_fd;
    }
    if ($command eq 'mkvm' or ($command eq 'clonevm' and (grep { "$_" eq '-b' } @exargs)) or ($command eq 'rpower' and (grep { "$_" eq "on" or $_ eq "boot" or $_ eq "reset" } @exargs))) {
        xCAT::VMCommon::requestMacAddresses($confdata, $noderange);
        my @dhcpnodes;
        foreach (keys %{ $confdata->{dhcpneeded} }) {
            push @dhcpnodes, $_;
            delete $confdata->{dhcpneeded}->{$_};
        }
        unless ($::XCATSITEVALS{'dhcpsetup'} and ($::XCATSITEVALS{'dhcpsetup'} =~ /^n/i or $::XCATSITEVALS{'dhcpsetup'} =~ /^d/i or $::XCATSITEVALS{'dhcpsetup'} eq '0')) {
            $doreq->({ command => ['makedhcp'], node => \@dhcpnodes });
        }
    }

    if ($command eq 'revacuate' or $command eq 'rmigrate') {
        $vmmaxp = 1; #for now throttle concurrent migrations, requires more sophisticated heuristics to ensure sanity
    } else {
        my $tmp;
        if ($::XCATSITEVALS{vmmaxp}) { $vmmaxp = $::XCATSITEVALS{vmmaxp}; }
    }

    my $children = 0;
    $SIG{CHLD} = sub { my $cpid; while (($cpid = waitpid(-1, WNOHANG)) > 0) { if ($vm_comm_pids{$cpid}) { delete $vm_comm_pids{$cpid}; $children--; } } };
    my $inputs  = new IO::Select;
    my $sub_fds = new IO::Select;
    %hyphash = ();

    if ($command eq 'rscan') { #command intended for hypervisors, not guests
        foreach (@$noderange) { $hyphash{$_}->{nodes}->{$_} = 1; }
    } else {
        foreach (keys %{ $confdata->{vm} }) {
            if ($confdata->{vm}->{$_}->[0]->{host}) {
                $hyphash{ $confdata->{vm}->{$_}->[0]->{host} }->{nodes}->{$_} = 1;
            } else {
                $orphans{$_} = 1;
            }
        }
    }
    if (keys %orphans) {
        if ($command eq "rpower") {
            if (grep /^on$/, @exargs or grep /^boot$/, @exargs) {
                unless (adopt(\%orphans, \%hyphash)) {
                    $callback->({ error => "Can't find " . join(",", keys %orphans), errorcode => [1] });
                    return 1;
                }
            } else {
                foreach (keys %orphans) {
                    $callback->({ node => [ { name => [$_], data => [ { contents => ['off'] } ] } ] });
                }
            }
        } elsif ($command eq "rmigrate") {
            if ($forcemode) {
                unless (adopt(\%orphans, \%hyphash)) {
                    $callback->({ error => "Can't find " . join(",", keys %orphans), errorcode => [1] });
                    return 1;
                }
            } else {
                $callback->({ error => "Can't find " . join(",", keys %orphans), errorcode => [1] });
                return;
            }
        } elsif ($command eq "mkvm" or $command eq "clonevm") { #must adopt to create
            unless (adopt(\%orphans, \%hyphash)) {
                $callback->({ error => "Can't find " . join(",", keys %orphans), errorcode => [1] });
                return 1;
            }

            #mkvm used to be able to happen devoid of any hypervisor, make a fake hypervisor entry to allow this to occur
            #commenting that out for now
            #          foreach (keys %orphans) {
            #              $hyphash{'!@!XCATDUMMYHYPERVISOR!@!'}->{nodes}->{$_}=1;
            #          }
        } elsif ($command eq "lsvm") {
            # Special processing for lsvm command, which takes vm name or hypervisor name
            unless (%hyphash) {
                # if hyperhash has not been set already, we are processing vms, set it here
                foreach (@$noderange) { $hyphash{$_}->{nodes}->{$_} = 1; }
            }
        } else {
            $callback->({ error => "Can't find " . join(",", keys %orphans), errorcode => [1] });
            return;
        }
    }
    if ($command eq "rbeacon") {
        my %req = ();
        $req{command} = ['rbeacon'];
        $req{arg}     = \@exargs;
        $req{node}    = [ keys %hyphash ];
        $doreq->(\%req, $callback);
        return;
    }

    if ($::XCATSITEVALS{masterimgdir}) { $xCAT_plugin::kvm::masterdir = $::XCATSITEVALS{masterimgdir} }

    foreach $hyp (sort (keys %hyphash)) {
        while ($children > $vmmaxp) {
            my $handlednodes = {};
            forward_data($callback, $sub_fds, $handlednodes);
        }
        $children++;
        my $cfd;
        my $pfd;
        socketpair($pfd, $cfd, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die "socketpair: $!";
        $cfd->autoflush(1);
        $pfd->autoflush(1);
        my $cpid = xCAT::Utils->xfork;
        unless (defined($cpid)) { die "Fork error"; }

        unless ($cpid) {
            close($cfd);
            dohyp($pfd, $hyp, $command, -args => \@exargs);
            exit(0);
        }
        $vm_comm_pids{$cpid} = 1;
        close($pfd);
        $sub_fds->add($cfd);
    }
    while ($sub_fds->count > 0) { # or $children > 0) { #if count is zero, even if we have live children, we can't possibly get data from them
        my $handlednodes = {};
        forward_data($callback, $sub_fds, $handlednodes);
    }

    #while (wait() > -1) { } #keep around just in case we find the absolute need to wait for children to be gone

    #Make sure they get drained, this probably is overkill but shouldn't hurt
    #my $rc=1;
    #while ( $rc>0 ) {
    #  my $handlednodes={};
    #  $rc=forward_data($callback,$sub_fds,$handlednodes);
    #  #update the node status to the nodelist.status table
    #  if ($check) {
    #    updateNodeStatus($handlednodes, \@allerrornodes);
    #  }
    #}

}

sub updateNodeStatus {
    my $handlednodes  = shift;
    my $allerrornodes = shift;
    foreach my $node (keys(%$handlednodes)) {
        if ($handlednodes->{$node} == -1) { push(@$allerrornodes, $node); }
    }
}

sub forward_data {
    my $callback   = shift;
    my $fds        = shift;
    my $errornodes = shift;
    my @ready_fds  = $fds->can_read(1);
    my $rfh;
    my $rc = @ready_fds;
    foreach $rfh (@ready_fds) {
        my $data;
        my $responses;
        eval {
            $responses = fd_retrieve($rfh);
        };
        if ($@ and $@ =~ /^Magic number checking on storable file/) { #this most likely means we ran over the end of available input
            $fds->remove($rfh);
            close($rfh);
        } else {
            eval { print $rfh "ACK\n"; }; #ignore failures to send inter-process ack
            foreach (@$responses) {

                #save the nodes that has errors and the ones that has no-op for use by the node status monitoring
                my $no_op = 0;
                if ($_->{node}->[0]->{errorcode}->[0]) { $no_op = 1; }
                else {
                    my $text = $_->{node}->[0]->{data}->[0]->{contents}->[0];

                    #print "data:$text\n";
                    if (($text) && ($text =~ /$status_noop/)) {
                        $no_op = 1;

                        #remove the symbols that meant for use by node status
                        $_->{node}->[0]->{data}->[0]->{contents}->[0] =~ s/$status_noop//;
                    }
                }

                #print "data:". $_->{node}->[0]->{data}->[0]->{contents}->[0] . "\n";
                if ($no_op) {
                    if ($errornodes) { $errornodes->{ $_->{node}->[0]->{name}->[0] } = -1; }
                } else {
                    if ($errornodes) { $errornodes->{ $_->{node}->[0]->{name}->[0] } = 1; }
                }
                $callback->($_);
            }
        }
    }
    yield();    #Try to avoid useless iterations as much as possible
    return $rc;
}


sub dohyp {
    my $out = shift;
    $hyp = shift;
    my $command   = shift;
    my %namedargs = @_;
    my @exargs    = @{ $namedargs{-args} };
    my $node;
    my $args = \@exargs;

    #$vmtab = xCAT::Table->new("vm");
    $vmtab = undef;
    unless ($offlinehyps{$hyp} or ($hyp eq '!@!XCATDUMMYHYPERVISOR!@!') or nodesockopen($hyp, 22)) {
        $offlinehyps{$hyp} = 1;
    }

    eval {    #Contain Sys::Virt bugs that make $@ useless
        if ($hyp eq '!@!XCATDUMMYHYPERVISOR!@!') { #Fake connection for commands that have a fake hypervisor key
            $hypconn = 1;
        } elsif (not $offlinehyps{$hyp}) {
            $hypconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $hyp . "/system?no_tty=1&netcat=nc");
        }
    };
    unless ($hypconn or $offlinehyps{$hyp}) {
        eval {    #Contain Sys::Virt bugs that make $@ useless
            $hypconn = Sys::Virt->new(uri => "qemu+ssh://root@" . $hyp . "/system?no_tty=1");
        };
    }
    unless ($hypconn) {
        my %err = (node => []);
        foreach (keys %{ $hyphash{$hyp}->{nodes} }) {
            push(@{ $err{node} }, { name => [$_], error => ["Cannot communicate via libvirt to $hyp"], errorcode => [1] });
        }
        store_fd([ \%err ], $out);
        yield();
        waitforack($out);
        %err = (node => []);
        if ($command eq 'rmigrate' and grep { $_ eq '-f' } @$args) {
            foreach (keys %{ $hyphash{$hyp}->{nodes} }) {
                push(@{ $err{node} }, { name => [$_], error => ["Forcibly relocating VM from $hyp"], errorcode => [1] });
            }
            store_fd([ \%err ], $out);
        } else {
            return 1, "General error establishing libvirt communication";
        }
    }
    if (($command =~ /^mkvm$|^chvm$|^rpower$|^lsvm$/) and $hypconn) {
        my $nodeinfo = $hypconn->get_node_info();
        if (exists($nodeinfo->{model})) {
            $confdata->{$hyp}->{cpumodel} = $nodeinfo->{model};
            if ($nodeinfo->{model} eq "ppc64") {
                my $sysinfo = $hypconn->get_sysinfo();
                if ($sysinfo) {
                    my $syshash = XMLin($sysinfo);
                    my $processor_content = $syshash->{processor}->[0]->{entry}->{type}->{content};
                    if ($processor_content =~ /POWER8/i) {
                        $confdata->{$hyp}->{cputype}    = "power8";
                        $confdata->{$hyp}->{cpu_thread} = "8";
                    } elsif ($processor_content =~ /POWER7/i) {
                        $confdata->{$hyp}->{cputype}    = "power7";
                        $confdata->{$hyp}->{cpu_thread} = "4";
                    } elsif ($processor_content =~ /POWER6/i) {
                        $confdata->{$hyp}->{cputype}    = "power6";
                        $confdata->{$hyp}->{cpu_thread} = "2";
                    }
                }
            }
        }
    }

    if ($command eq 'rpower') {
        my $subcommand = $exargs[0];
        if (($subcommand ne 'stat') && ($subcommand ne 'status')) {
            %allnodestatus = ();
        }
    }

    my %newnodestatus;

    foreach $node (sort (keys %{ $hyphash{$hyp}->{nodes} })) {
        unless ($confdata->{vm}->{$node}->[0]->{storagemodel}) {
            # Storage model is not set, default to  scsi for all architectures
            $confdata->{vm}->{$node}->[0]->{storagemodel} = "scsi";
        }
        if ($confdata->{$hyp}->{cpu_thread}) {
            $confdata->{vm}->{$node}->[0]->{cpu_thread} = $confdata->{$hyp}->{cpu_thread};
        }
        if ($confdata->{$hyp}->{cputype}) {
            $confdata->{vm}->{$node}->[0]->{cputype} = $confdata->{$hyp}->{cputype};
        }

        my ($rc, @output) = guestcmd($hyp, $node, $command, @$args);

        foreach (@output) {
            my %output;
            if (ref($_)) {
                store_fd([$_], $out);
                yield();
                waitforack($out);
                next;
            }

            (my $desc, my $text) = split(/:/, $_, 2);
            unless ($text) {
                $text = $desc;
            } else {
                $desc =~ s/^\s+//;
                $desc =~ s/\s+$//;
                if ($desc) {
                    if($rc == 0){
                        $output{node}->[0]->{data}->[0]->{desc}->[0] = $desc;
                    }
                }
            }
            $text =~ s/^\s+//;
            $text =~ s/\s+$//;
            $output{node}->[0]->{errorcode} = [$rc];
            $output{node}->[0]->{name}->[0] = $node;
            if ($rc == 0) {
                $output{node}->[0]->{data}->[0]->{contents}->[0] = $text;
            } else {
                $output{node}->[0]->{error}->[0] = $text;
            }

            if ($command eq 'rpower') {
                if (!$rc and $text !~ /$status_noop/) {
                    if (%allnodestatus) {
                        push @{ $newnodestatus{ $allnodestatus{$node} } }, $node;
                    }
                }
            }
            store_fd([ \%output ], $out);
            yield();
            waitforack($out);
        }
        yield();
    }

    if ($command eq 'rpower') {
        xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
    }

    foreach (keys %$updatetable) {
        my $tabhandle = xCAT::Table->new($_, -create => 1);
        my $updates = $updatetable->{$_};
        if ($updates->{'!*XCATNODESTODELETE*!'}) {
            my @delkeys;
            foreach (keys %{ $updates->{'!*XCATNODESTODELETE*!'} }) {
                if ($_) { push @delkeys, { node => $_ }; }
            }
            if (@delkeys) { $tabhandle->delEntries(\@delkeys); }
            delete $updates->{'!*XCATNODESTODELETE*!'};
        }
        $tabhandle->setNodesAttribs($updatetable->{$_});
    }

    #my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
    #print $out $msgtoparent; #$node.": $_\n";
}

# Return array of device names used by cdrom as defined in the kvm_nodedata table
sub get_cdrom_device_names() {
    my $xml = shift;
    my $device_name;
    my @cdrom_device_names;

    my $myxml    = $parser->parse_string($xml);
    my @alldisks = $myxml->findnodes("/domain/devices/disk");
    # Look through all the disk entries defined in the xml
    foreach my $disknode (@alldisks) {
         my $devicetype = $disknode->getAttribute("device");
         # Check if it is cdrom
         if ($devicetype eq "cdrom") {
             # Get name of the cdrom
             $device_name = $disknode->findnodes('./target')->[0]->getAttribute('dev');
             push @cdrom_device_names, $device_name;
         }
    }
    return @cdrom_device_names;
}

1;
