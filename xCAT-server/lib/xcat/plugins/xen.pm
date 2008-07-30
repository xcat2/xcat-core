#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::xen;
my $libvirtsupport;
$libvirtsupport = eval { require Sys::Virt; };


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
my $vmhash;

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
use Net::Telnet;
use xCAT::DBobjUtils;
use Getopt::Long;

my %runningstates;
my $vmmaxp;
my $mactab;
my $nrtab;
my $machash;
sub handled_commands {
  unless ($libvirtsupport) {
      return {};
  }
  return {
    rpower => 'nodehm:power,mgt',
    rmigrate => 'nodehm:mgt',
    getvmcons => 'nodehm:mgt',
    #rvitals => 'nodehm:mgt',
    #rinv => 'nodehm:mgt',
    rbeacon => 'nodehm:mgt',
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
    $rethash{loader}->{content}='/usr/lib/xen/boot/hvmloader';
    $rethash{boot}->[0]->{dev}='network';
    $rethash{boot}->[1]->{dev}='hd';
    return \%rethash;
}

sub build_diskstruct {
    my @returns;
    my $diskhash;
    $diskhash->{type}='file';
    $diskhash->{source}->{file}="/cluster2/vm/$node";
    $diskhash->{target}->{dev}='hda';
    push @returns,$diskhash;
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
        $rethash->{type}='bridge';
        $rethash->{mac}->{address}=$_;
        push @rethashes,$rethash;
    }
    return \@rethashes;
}
sub build_xmldesc {
    my $node = shift;
    my %xtree=();
    $xtree{type}='xen';
    $xtree{name}->{content}=$node;
    $xtree{uuid}->{content}=getNodeUUID($node);
    $xtree{os} = build_oshash();
    $xtree{memory}->{content}=524288;
    $xtree{vcpu}->{content}=1;
    $xtree{features}->{pae}={};
    $xtree{features}->{acpi}={};
    $xtree{features}->{apic}={};
    $xtree{features}->{content}="\n";
    $xtree{devices}->{emulator}->{content}='/usr/lib64/xen/bin/qemu-dm';
    $xtree{devices}->{disk}=build_diskstruct();
    $xtree{devices}->{interface}=build_nicstruct($node);
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

sub getvmcons {
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
        return (0,'tty@'.$hyper.": ".$consdata->{textconsole});
    } elsif ($type eq "vnc") {
        print Dumper($consdata);
        return (0,'ssh+vnc@'.$hyper.": ".$consdata->{vncport});
    }
}

sub migrate {
    my $node = shift();
    my $targ = shift();
    my $prevhyp;
    my $target = "xen+ssh://".$targ;
    my $currhyp="xen+ssh://";
    if ($vmhash->{$node}->[0]->{host}) {
        $prevhyp=$vmhash->{$node}->[0]->{host};
        $currhyp.=$prevhyp;
    } else {
        return (1,Dumper($vmhash)."Unable to find current location of $node");
    }
    my $sock = IO::Socket::INET->new(Proto=>'udp');
    my $ipa=inet_aton($node);
    my $pa=sockaddr_in(7,$ipa); #UDP echo service, not needed to be actually
    #serviced, we just want to trigger an arp query
    my $rc=system("virsh -c $currhyp migrate --live $node $target");
    system("arp -d $node"); #Make ethernet fabric take note of change
    send($sock,"dummy",0,$pa); 
    my $newhypconn= Sys::Virt->new(uri=>"xen+ssh://".$targ);
    my $dom;
    eval {
     $dom = $newhypconn->get_domain_by_name($node);
    };
    $vmtab->setNodeAttribs($node,{host=>$targ});
    if ($dom) {
        refresh_vm($dom);
    }
    if ($rc) {
        return (1,"Failed migration from $prevhyp to $targ");
    } else {
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
    if ($subcommand eq 'on') {
        unless ($dom) {
            my $xml=build_xmldesc($node);
            my $errstr;
            eval { $dom=$hypconn->create_domain($xml); };

            if ($@) { $errstr = $@; }
            if ($errstr) { return (1,$errstr); }
            if ($dom) {
                refresh_vm($dom);
            }
        }
    } elsif ($subcommand eq 'off') {
        if ($dom) {
            $dom->destroy();
        }
    } elsif ($subcommand eq 'softoff') {
        if ($dom) {
            $dom->shutdown();
        }
    } else { 
        unless ($subcommand =~ /^stat/) {
            return (1,"Unsupported power directive '$subcommand'");
        }
    }

    $retstring.=getpowstate($dom);
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
  } elsif ($command eq "rmigrate") {
      return migrate($node,@args);
  } elsif ($command eq "getvmcons") {
      return getvmcons($node,@args);
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
  return (1,"$command not a supported command by xen method");
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
     
sub grab_table_data{
  my $noderange=shift;
  my $callback=shift;
  $vmtab = xCAT::Table->new("vm");
  unless ($vmtab) { 
    $callback->({data=>["Cannot open vm table"]});
    return;
  }
  $vmhash = $vmtab->getNodesAttribs($noderange,['node','host','migrationdest','storage','memory','cpu','nics','bootorder','virtflags']);
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
  grab_table_data($noderange,$callback);

  my $sitetab = xCAT::Table->new('site');
  my $tmp;
  if ($sitetab) {
    ($tmp)=$sitetab->getAttribs({'key'=>'vmmaxp'},'value');
    if (defined($tmp)) { $vmmaxp=$tmp->{value}; }
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

  foreach $hyp (sort (keys %hyphash)) {
    while ($children > $vmmaxp) { forward_data($callback,$sub_fds); }
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
    forward_data($callback,$sub_fds);
  }
  while (forward_data($callback,$sub_fds)) {}
}

sub forward_data {
  my $callback = shift;
  my $fds = shift;
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


  $hypconn= Sys::Virt->new(uri=>"xen+ssh://".$hyp);
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
