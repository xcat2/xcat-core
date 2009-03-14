#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::kvm;
my $libvirtsupport;
$libvirtsupport = eval { require Sys::Virt; };
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::GlobalDef;
use xCAT::NodeRange;
use xCAT_monitoring::monitorctrl;

#use Net::SNMP qw(:snmp INTEGER);
use xCAT::Table;
use XML::Simple qw(XMLout);
use Thread qw(yield);
use IO::Socket;
use IO::Select;
use SNMP;
use strict;
#use warnings;
my %vm_comm_pids;
my @destblacklist;
my $vmhash;
my $hmhash;

use XML::Simple;
if ($^O =~ /^linux/i) {
 $XML::Simple::PREFERRED_PARSER='XML::Parser';
}
use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use IO::Select;
use IO::Handle;
use Time::HiRes qw(gettimeofday sleep);
use xCAT::DBobjUtils;
use Getopt::Long;

my %runningstates;
my $vmmaxp=64;
my $mactab;
my $nrtab;
my $machash;
my $status_noop="XXXno-opXXX";

sub handled_commands {
  #unless ($libvirtsupport) {
  #    return {};
  #}
  return {
    rpower => 'nodehm:power,mgt',
    mkvm => 'nodehm:power,mgt',
    rmigrate => 'nodehm:mgt',
    getcons => 'nodehm:mgt',
    #rvitals => 'nodehm:mgt',
    #rinv => 'nodehm:mgt',
    getrvidparms => 'nodehm:mgt',
    rbeacon => 'nodehm:mgt',
    revacuate => 'vm:virtflags',
    #rspreset => 'nodehm:mgt',
    #rspconfig => 'nodehm:mgt',
    #rbootseq => 'nodehm:mgt',
    #reventlog => 'nodehm:mgt',
  };
}

my $virsh;
my $vmhash;
my $hypconn;
my $hyp;
my $doreq;
my %hyphash;
my $node;
my $hmtab;
my $vmtab;

sub waitforack {
    my $sock = shift;
    my $select = new IO::Select;
    $select->add($sock);
    my $str;
    if ($select->can_read(10)) { # Continue after 10 seconds, even if not acked...
        if ($str = <$sock>) {
        } else {
           $select->remove($sock); #Block until parent acks data
        }
    }
}

sub build_oshash {
    my %rethash;
    $rethash{type}->{content}='hvm';
    if (defined $vmhash->{$node}->[0]->{bootorder}) {
        my $bootorder = $vmhash->{$node}->[0]->{bootorder};
        my @bootdevs = split(/:/,$bootorder);
        my $bootnum = 0;
        foreach (@bootdevs) {
            $rethash{boot}->[$bootnum]->{dev}=$_;
            $bootnum++;
        }
    } else {
        $rethash{boot}->[0]->{dev}='network';
        $rethash{boot}->[1]->{dev}='hd';
    }
    return \%rethash;
}

sub build_diskstruct {
    my @returns=();
    my $currdev;
    my @suffixes=('a'..'z');
    my $suffidx=0;
    if (defined $vmhash->{$node}->[0]->{storage}) {
        my $disklocs=$vmhash->{$node}->[0]->{storage};
        my @locations=split /\|/,$disklocs;
        foreach my $disk (@locations) {
            #Setting default values of a virtual disk backed by a file at hd*.
            my $diskhash;
            $diskhash->{type} = 'file';
            $diskhash->{device} = 'disk';
            $diskhash->{target}->{dev} = 'hd'.$suffixes[$suffidx];

            my @disk_parts = split(/,/, $disk);
            #Find host file and determine if it is a file or a block device.
            if (substr($disk_parts[0], 0, 4) eq 'phy:') {
                $diskhash->{type}='block';
                $diskhash->{source}->{dev} = substr($disk_parts[0], 4);
            } else {
                $diskhash->{source}->{file} = $disk_parts[0];
            }

            #See if there are any other options. If not, increment suffidx because the already determined device node was used.
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
    return xCAT::Utils::genUUID();
}
sub build_nicstruct {
    my $rethash;
    my $node = shift;
    my @macs=();
    my @nics=();
    if ($vmhash->{$node}->[0]->{nics}) {
        @nics = split /,/,$vmhash->{$node}->[0]->{nics};
    } else {
        @nics = ('virbr0');
    }
    if ($machash->{$node}->[0]->{mac}) {
        my $macdata=$machash->{$node}->[0]->{mac};
        foreach my $macaddr (split /\|/,$macdata) {
            $macaddr =~ s/\!.*//;
            push @macs,$macaddr;
        }
    }
    unless (scalar(@macs)) {
        my $allbutmult = 65279; # & mask for bitwise clearing of the multicast bit of mac
        my $localad=512; # | to set the bit for locally admnistered mac address
        my $leading=int(rand(65535));
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
        my $macstr = sprintf("%04x%08x",$leading,$tail);
        $macstr =~ s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
        $mactab->setNodeAttribs($node,{mac=>$macstr});
        $nrtab->setNodeAttribs($node,{netboot=>'pxe'});
        $doreq->({command=>['makedhcp'],node=>[$node]});
        push @macs,$macstr;
    }
    my @rethashes;
    foreach (@macs) {
        my $rethash;
        my $nic = shift @nics;
        my $type = 'e1000'; #better default fake nic than rtl8139, relevant to most
        unless ($nic) {
            last; #Don't want to have multiple vnics tied to the same switch
        }
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
    my %xtree=();
    $xtree{type}='kvm';
    $xtree{name}->{content}=$node;
    $xtree{uuid}->{content}=getNodeUUID($node);
    $xtree{os} = build_oshash();
    if (defined $vmhash->{$node}->[0]->{memory}) {
        $xtree{memory}->{content}=getUnits($vmhash->{$node}->[0]->{memory},"M",1024);
    } else {
        $xtree{memory}->{content}=524288;
    }
    if (defined $vmhash->{$node}->[0]->{cpus}) {
        $xtree{vcpu}->{content}=$vmhash->{$node}->[0]->{cpus};
    } else {
        $xtree{vcpu}->{content}=1;
    }
    $xtree{features}->{pae}={};
    $xtree{features}->{acpi}={};
    $xtree{features}->{apic}={};
    $xtree{features}->{content}="\n";
    $xtree{devices}->{disk}=build_diskstruct();
    $xtree{devices}->{interface}=build_nicstruct($node);
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
    my $vncport=$newxml->{devices}->{graphics}->{port};
    my $stty=$newxml->{devices}->{console}->{tty};
    $vmtab->setNodeAttribs($node,{vncport=>$vncport,textconsole=>$stty});
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
    my $hyper=$vmhash->{$node}->[0]->{host};

    if ($type eq "text") {
        my $serialspeed;
        if ($hmhash) {
            $serialspeed=$hmhash->{$node}->[0]->{serialspeed};
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
        );
        return  0,@output;
    } else {
        return (1,"Error: Unable to determine rvid destination for $node");
    }
}

sub pick_target {
    my $node = shift;
    my $target;
    my $leastusedmemory=undef;
    my $currentusedmemory;
    my $candidates= $vmhash->{$node}->[0]->{migrationdest};
    my $currhyp=$vmhash->{$node}->[0]->{host};
    unless ($candidates) {
        return undef;
    }
    print "$node with $candidates\n";
    foreach (noderange($candidates)) {
        my $targconn;
        my $cand=$_;
        $currentusedmemory=0;
        if ($_ eq $currhyp) { next; } #skip current node
        if (grep { "$_" eq $cand } @destblacklist) { print "$_ was blacklisted\n"; next; } #skip blacklisted destinations
            print "maybe $_\n";
            eval {  #Sys::Virt has bugs that cause it to die out in weird ways some times, contain it here
                $targconn = Sys::Virt->new(uri=>"qemu+ssh://".$_."/system?no_tty=1&netcat=nc");
            };
            unless ($targconn) {
                eval {  #Sys::Virt has bugs that cause it to die out in weird ways some times, contain it here
                    $targconn = Sys::Virt->new(uri=>"qemu+ssh://".$_."/system?no_tty=1");
                };
            }
        unless ($targconn) { next; } #skip unreachable destinations
        foreach ($targconn->list_domains()) {
            if ($_->get_name() eq 'Domain-0') { next; } #Dom0 memory usage is elastic, we are interested in HVM DomU memory, which is inelastic

            $currentusedmemory += $_->get_info()->{memory};
        }
        if (not defined ($leastusedmemory)) {
            $leastusedmemory=$currentusedmemory;
            $target=$_;
        } elsif ($currentusedmemory < $leastusedmemory) {
            $leastusedmemory=$currentusedmemory;
            $target=$_;
        }
    }
    return $target;
}


sub migrate {
    my $node = shift();
    my $targ = shift();
    unless ($targ) {
        $targ = pick_target($node);
    }
    unless ($targ) {
        return (1,"Unable to identify a suitable target host for guest $node");
    }
    my $prevhyp;
    my $target = "qemu+ssh://".$targ."/system?no_tty=1";
    my $currhyp="qemu+ssh://";
    if ($vmhash->{$node}->[0]->{host}) {
        $prevhyp=$vmhash->{$node}->[0]->{host};
        $currhyp.=$prevhyp;
    } else {
        return (1,"Unable to find current location of $node");
    }
    $currhyp.="/system?no_tty=1";
    if ($currhyp eq $target) {
        return (0,"Guest is already on host $targ");
    }
    my $testhypconn;
    my $srcnetcatadd="&netcat=nc";
    eval {#Contain Sys::Virt bugs
        $testhypconn= Sys::Virt->new(uri=>"qemu+ssh://".$prevhyp."/system?no_tty=1$srcnetcatadd");
    };
    unless ($testhypconn) {
        $srcnetcatadd="";
        eval {#Contain Sys::Virt bugs
            $testhypconn= Sys::Virt->new(uri=>"qemu+ssh://".$prevhyp."/system?no_tty=1");
        };
    }
    unless ($testhypconn) {
        return (1,"Unable to reach $prevhyp to perform operation of $node, use nodech to change vm.host if certain of no split-brain possibility exists");
    }
    my $destnetcatadd="&netcat=nc";
    undef $testhypconn;
    eval {#Contain Sys::Virt bugs
        $testhypconn= Sys::Virt->new(uri=>$target.$destnetcatadd);
    };
    unless ($testhypconn) {
        $destnetcatadd="";
        eval {#Contain Sys::Virt bugs
            $testhypconn= Sys::Virt->new(uri=>$target);
        };
    }
    unless ($testhypconn) {
        return (1,"Unable to reach $targ to perform operation of $node, destination unusable.");
    }
    my $sock = IO::Socket::INET->new(Proto=>'udp');
    my $ipa=inet_aton($node);
    my $pa=sockaddr_in(7,$ipa); #UDP echo service, not needed to be actually
    #serviced, we just want to trigger MAC move in the switch forwarding dbs
    my $rc=system("virsh -c '$currhyp".$srcnetcatadd."' migrate --live $node '$target"."$destnetcatadd'");
    system("arp -d $node"); #Make ethernet fabric take note of change
    send($sock,"dummy",0,$pa);  #UDP packet to force forwarding table update in switches, ideally a garp happened, but just in case...
    if ($rc) {
        return (1,"Failed migration from $prevhyp to $targ");
    } else {
        $vmtab->setNodeAttribs($node,{host=>$targ});
        my $newhypconn;
        eval {#Contain Sys::Virt bugs
            $newhypconn= Sys::Virt->new(uri=>"qemu+ssh://".$targ."/system?no_tty=1&netcat=nc");
        };
        unless ($newhypconn) {
            eval {#Contain Sys::Virt bugs
                $newhypconn= Sys::Virt->new(uri=>"qemu+ssh://".$targ."/system?no_tty=1");
            };
        }
        if ($newhypconn) {
            my $dom;
            eval {
             $dom = $newhypconn->get_domain_by_name($node);
            };
            if ($dom) {
                refresh_vm($dom);
            }
        } else {
            return (0,"migrated to $targ");
        }
        return (0,"migrated to $targ");
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

sub makedom {
    my $node=shift;
    my $dom;
    my $xml=build_xmldesc($node);
    print $xml;
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


sub mkvm {
 build_xmldesc($node);
}
sub power {
    my $subcommand = shift;
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
            ($dom,$errstr) = makedom($node);
            if ($errstr) { return (1,$errstr); }
        } else {
          $retstring .= " $status_noop";
        }
    } elsif ($subcommand eq 'off') {
        if ($dom) {
            $dom->destroy();
        } else { $retstring .= " $status_noop"; }
    } elsif ($subcommand eq 'softoff') {
        if ($dom) {
            $dom->shutdown();
        } else { $retstring .= " $status_noop"; } 
    } elsif ($subcommand eq 'reset') {
        if ($dom) {
            $dom->destroy();
            ($dom,$errstr) = makedom($node);
            if ($errstr) { return (1,$errstr); }
            $retstring.="reset";
        } else { $retstring .= " $status_noop"; } 
    } else { 
        unless ($subcommand =~ /^stat/) {
            return (1,"Unsupported power directive '$subcommand'");
        }
    }

    unless ($retstring =~ /reset/) {
        $retstring=getpowstate($dom).$retstring;
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
      return mkvm();
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
  if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
  my $callback=shift;
  unless ($libvirtsupport) { #Try to see if conditions changed since last check (no xCATd restart for it to take effect)
        $libvirtsupport = eval { require Sys::Virt; };
  }
  unless ($libvirtsupport) { #Still no Sys::Virt module
      $callback->({error=>"Sys::Virt perl module missing, unable to fulfill Xen plugin requirements",errorcode=>[42]});
      return [];
  }
  require Sys::Virt::Domain;
  %runningstates = (&Sys::Virt::Domain::STATE_NOSTATE=>1,&Sys::Virt::Domain::STATE_RUNNING=>1,&Sys::Virt::Domain::STATE_BLOCKED=>1);
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
    push @requests, $reqcopy;
  }
  return \@requests;
}
 
    
sub adopt {
#TODO: adopt orphans into suitable homes if possible
    return 0;
}
     
sub grab_table_data{ #grab table data relevent to VM guest nodes
  my $noderange=shift;
  my $callback=shift;
  $vmtab = xCAT::Table->new("vm");
  $hmtab = xCAT::Table->new("nodehm");
  if ($hmtab) {
      $hmhash  = $hmtab->getNodesAttribs($noderange,['serialspeed']);
  }
  unless ($vmtab) { 
    $callback->({data=>["Cannot open vm table"]});
    return;
  }
  $vmhash = $vmtab->getNodesAttribs($noderange,['node','host','migrationdest','storage','memory','cpus','nics','bootorder','virtflags']);
  $mactab = xCAT::Table->new("mac",-create=>1);
  $nrtab= xCAT::Table->new("noderes",-create=>1);
  $machash = $mactab->getNodesAttribs($noderange,['mac']);
}

sub process_request { 
  $SIG{INT} = $SIG{TERM} = sub { 
     foreach (keys %vm_comm_pids) {
        kill 2, $_;
     }
     exit 0;
  };

  my $request = shift;
  my $callback = shift;
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
  if ($command eq 'revacuate') {
      my $newnoderange;
      foreach (@$noderange) {
        $hypconn=undef;
        push @destblacklist,$_;
        eval { #Contain bugs that won't be in $@
            $hypconn= Sys::Virt->new(uri=>"qemu+ssh://".$_."/system?no_tty=1&netcat=nc");
        };
        unless ($hypconn) { #retry for socat
            eval { #Contain bugs that won't be in $@
                $hypconn= Sys::Virt->new(uri=>"qemu+ssh://".$_."/system?no_tty=1");
            };
        }
        unless ($hypconn)  {
            $callback->({node=>[{name=>[$_],error=>["Cannot communicate BC via libvirt to node"]}]});
            next;
        }
        foreach ($hypconn->list_domains()) {
            my $guestname = $_->get_name();
            if ($guestname eq 'Domain-0') {
                next;
            }
            push @$newnoderange,$guestname;
        }
      }
      $hypconn=undef;
      $noderange = $newnoderange;
      $command = 'rmigrate';
  }

  grab_table_data($noderange,$callback);

  if ($command eq 'revacuate' or $command eq 'rmigrate') {
      $vmmaxp=1; #for now throttle concurrent migrations, requires more sophisticated heuristics to ensure sanity
  } else {
      my $sitetab = xCAT::Table->new('site');
      my $tmp;
      if ($sitetab) {
        ($tmp)=$sitetab->getAttribs({'key'=>'vmmaxp'},'value');
        if (defined($tmp)) { $vmmaxp=$tmp->{value}; }
      }
  }

  my $children = 0;
  $SIG{CHLD} = sub { my $cpid; while ($cpid = waitpid(-1, WNOHANG) > 0) { delete $vm_comm_pids{$cpid}; $children--; } };
  my $inputs = new IO::Select;;
  my $sub_fds = new IO::Select;
  %hyphash=();
  my %orphans=();
  foreach (keys %{$vmhash}) {
      if ($vmhash->{$_}->[0]->{host}) {
          $hyphash{$vmhash->{$_}->[0]->{host}}->{nodes}->{$_}=1;
      } else {
          $orphans{$_}=1;
      }
  }
  if (keys %orphans) {
      if ($command eq "rpower" and (grep /^on$/,@exargs or grep /^boot$/,@exargs)) {
          unless (adopt(\%orphans,\%hyphash)) {
            $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
            return 1;
          }
         
      } elsif ($command eq "rmigrate") {
          $callback->({error=>"Can't find ".join(",",keys %orphans),errorcode=>[1]});
          return;
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
  my %nodestat=();
  my $check=0;
  my $newstat;
  if ($command eq 'rpower') {
    my $subcommand=$exargs[0];
    if (($subcommand ne 'stat') && ($subcommand ne 'status')) { 
      $check=1; 
      my @allnodes=@$noderange;
      if ($subcommand eq 'off') { $newstat=$::STATUS_POWERING_OFF; }
      else { $newstat=$::STATUS_BOOTING;}
      foreach (@allnodes) { $nodestat{$_}=$newstat; }

      if ($subcommand ne 'off') {
        #get the current nodeset stat
        if (@allnodes>0) {
	  my $nsh={};
          my ($ret, $msg)=xCAT::Utils->getNodesetStates(\@allnodes, $nsh);
          if (!$ret) { 
            foreach (keys %$nsh) {
	      my $currstate=$nsh->{$_};
              $nodestat{$_}=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($currstate, "rpower");
	    }
	  }
        }
      }
    }
  }

  #foreach (keys %nodestat) { print "node=$_,status=" . $nodestat{$_} ."\n"; } #Ling:remove


  foreach $hyp (sort (keys %hyphash)) {
    while ($children > $vmmaxp) { 
      my $errornodes={};
      forward_data($callback,$sub_fds,$errornodes);
      #update the node status to the nodelist.status table
      if ($check) {
        updateNodeStatus(\%nodestat, $errornodes);
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
    my $errornodes={};
    forward_data($callback,$sub_fds,$errornodes);
    #update the node status to the nodelist.status table
    if ($check) {
      updateNodeStatus(\%nodestat, $errornodes);
    }
  }

  #Make sure they get drained, this probably is overkill but shouldn't hurt
  my $rc=1;
  while ( $rc>0 ) {
    my $errornodes={};
    $rc=forward_data($callback,$sub_fds,$errornodes);
    #update the node status to the nodelist.status table
    if ($check) {
      updateNodeStatus(\%nodestat, $errornodes);
    }
  }   
}

sub updateNodeStatus {
  my $nodestat=shift;
  my $errornodes=shift;
  my %node_status=();
  foreach my $node (keys(%$errornodes)) {
    if ($errornodes->{$node} == -1) { next;} #has error, not updating status
    my $stat=$nodestat->{$node};
    if (exists($node_status{$stat})) {
      my $pa=$node_status{$stat};
      push(@$pa, $node);
    }
    else {
      $node_status{$stat}=[$node];
    }
  }
  xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1);
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
      print $rfh "ACK\n";
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
            $_->{node}->[0]->{data}->[0]->{contents}->[0] =~ s/ $status_noop//; 
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


  eval { #Contain Sys::Virt bugs that make $@ useless
    $hypconn= Sys::Virt->new(uri=>"qemu+ssh://".$hyp."/system?no_tty=1&netcat=nc");
  };
  unless ($hypconn) {
    eval { #Contain Sys::Virt bugs that make $@ useless
        $hypconn= Sys::Virt->new(uri=>"qemu+ssh://".$hyp."/system?no_tty=1");
    };
  }
  unless ($hypconn) {
     my %err=(node=>[]);
     foreach (keys %{$hyphash{$hyp}->{nodes}}) {
        push (@{$err{node}},{name=>[$_],error=>["Cannot communicate AB via libvirt to $hyp"],errorcode=>[1]});
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
      print $out freeze([\%output]);
      print $out "\nENDOFFREEZE6sK4ci\n";
      yield();
      waitforack($out);
    }
    yield();
  }
  #my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
  #print $out $msgtoparent; #$node.": $_\n";
}
    
1;
