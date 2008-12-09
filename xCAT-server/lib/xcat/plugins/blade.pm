#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::blade;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
#use Net::SNMP qw(:snmp INTEGER);
use xCAT::Table;
use Thread qw(yield);
use xCAT::Utils;
use xCAT::Usage;
use IO::Socket;
use SNMP;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use strict;
use LWP;

#use warnings;
my %mm_comm_pids;

#a 'browser' for http actions
my $browser;
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

sub handled_commands {
  return {
    findme => 'blade',
    getmacs => 'nodehm:getmac,mgt',
    rscan => 'nodehm:mgt',
    rpower => 'nodehm:power,mgt',
    getbladecons => 'blade',
    getrvidparms => 'nodehm:mgt',
    rvitals => 'nodehm:mgt',
    rinv => 'nodehm:mgt',
    rbeacon => 'nodehm:mgt',
    rspreset => 'nodehm:mgt',
    rspconfig => 'nodehm:mgt',
    rbootseq => 'nodehm:mgt',
    reventlog => 'nodehm:mgt',
    switchblade => 'nodehm:mgt',
  };
}

my %macmap; #Store responses from rinv for discovery
my $macmaptimestamp; #reflect freshness of cache
my $mmprimoid = '1.3.6.1.4.1.2.3.51.2.22.5.1.1.4';#mmPrimary
my $beaconoid = '1.3.6.1.4.1.2.3.51.2.2.8.2.1.1.11'; #ledBladeIdentity
my $erroroid = '1.3.6.1.4.1.2.3.51.2.2.8.2.1.1.7'; #ledBladeError
my $infooid = '1.3.6.1.4.1.2.3.51.2.2.8.2.1.1.8'; #ledBladeInfo
my $kvmoid = '1.3.6.1.4.1.2.3.51.2.2.8.2.1.1.9'; #ledBladeKVM
my $mtoid = '1.3.6.1.4.1.2.3.51.2.2.8.2.1.1.10'; #ledBladeMT
my $chassiserroroid = '1.3.6.1.4.1.2.3.51.2.2.8.1.1.0'; #ChassisLedError
my $chassisinfooid = '1.3.6.1.4.1.2.3.51.2.2.8.1.2.0'; #ChassisLedInfo
my $chassistempledoid = '1.3.6.1.4.1.2.3.51.2.2.8.1.3.0'; #ChassisLedTemperature
my $chassisbeaconoid = '1.3.6.1.4.1.2.3.51.2.2.8.1.4.0'; #ChassisLedIdentity
my $powerstatoid = '1.3.6.1.4.1.2.3.51.2.22.1.5.1.1.4';#bladePowerState
my $powerchangeoid = '1.3.6.1.4.1.2.3.51.2.22.1.6.1.1.7';#powerOnOffBlade
my $powerresetoid = '1.3.6.1.4.1.2.3.51.2.22.1.6.1.1.8';#restartBlade
my $mpresetoid = '1.3.6.1.4.1.2.3.51.2.22.1.6.1.1.9'; #restartBladeSMP
my $bladexistsoid = '1.3.6.1.4.1.2.3.51.2.22.1.5.1.1.3'; #bladeExists
my $bladeserialoid = '1.3.6.1.4.1.2.3.51.2.2.21.4.1.1.6'; #bladeHardwareVpdSerialNumber
my $blademtmoid = '1.3.6.1.4.1.2.3.51.2.2.21.4.1.1.7'; #bladeHardwareVpdMachineType
my $bladempveroid = '1.3.6.1.4.1.2.3.51.2.2.21.5.3.1.7'; #bladeSysMgmtProcVpdRevision
my $bladempaveroid = '1.3.6.1.4.1.2.3.51.2.2.21.3.1.1.4';#mmMainApplVpdRevisonNumber
my $bladempabuildidoid = '1.3.6.1.4.1.2.3.51.2.2.21.3.1.1.3';#mmMainApplVpdBuildId
my $bladempadateoid = '1.3.6.1.4.1.2.3.51.2.2.21.3.1.1.6';#mmMainApplVpdBuildDate
my $bladempbuildidoid = '1.3.6.1.4.1.2.3.51.2.2.21.5.3.1.6'; #bladeSysMgmtProcVpdBuildId
my $bladebiosveroid = '1.3.6.1.4.1.2.3.51.2.2.21.5.1.1.7'; #bladeBiosVpdRevision
my $bladebiosbuildidoid = '1.3.6.1.4.1.2.3.51.2.2.21.5.1.1.6'; #bladeBiosVpdBuildId
my $bladebiosdateoid = '1.3.6.1.4.1.2.3.51.2.2.21.5.1.1.8'; #bladeBiosVpdDate
my $bladediagveroid = '1.3.6.1.4.1.2.3.51.2.2.21.5.2.1.7'; #bladeDiagsVpdRevision
my $bladediagbuildidoid = '1.3.6.1.4.1.2.3.51.2.2.21.5.2.1.6'; #bladeDiagsVpdBuildId
my $bladediagdateoid = '1.3.6.1.4.1.2.3.51.2.2.21.5.2.1.8';#bladeDiagsVpdDate
my $eventlogoid = '1.3.6.1.4.1.2.3.51.2.3.4.2.1.2';#readEventLogString
my $clearlogoid = '.1.3.6.1.4.1.2.3.51.2.3.4.3';#clearEventLog
my $blower1speedoid = '.1.3.6.1.4.1.2.3.51.2.2.3.1';#blower2speed
my $blower2speedoid = '.1.3.6.1.4.1.2.3.51.2.2.3.2';#blower2speed
my $blower3speedoid = '.1.3.6.1.4.1.2.3.51.2.2.3.3';#blower2speed
my $blower4speedoid = '.1.3.6.1.4.1.2.3.51.2.2.3.4';#blower2speed
my $blower1stateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.10';#blower1State
my $blower2stateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.11';#blower2State
my $blower3stateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.12';#blower2State
my $blower4stateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.13';#blower2State
my $blower1rpmoid = '.1.3.6.1.4.1.2.3.51.2.2.3.20';#blower1SpeedRPM
my $blower2rpmoid = '.1.3.6.1.4.1.2.3.51.2.2.3.21';#blower2SpeedRPM
my $blower3rpmoid = '.1.3.6.1.4.1.2.3.51.2.2.3.22';#blower3SpeedRPM
my $blower4rpmoid = '.1.3.6.1.4.1.2.3.51.2.2.3.23';#blower4SpeedRPM
my $blower1contstateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.30';#blower1Controllerstote
my $blower2contstateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.31';#blower2''
my $blower3contstateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.32';#blower3''
my $blower4contstateoid = '.1.3.6.1.4.1.2.3.51.2.2.3.33';#blower4''
my $mmoname = '1.3.6.1.4.1.2.3.51.2.22.4.3';#chassisName
my $mmotype = '1.3.6.1.4.1.2.3.51.2.2.21.1.1.1';#bladeCenterVpdMachineType
my $mmomodel = '1.3.6.1.4.1.2.3.51.2.2.21.1.1.2';#bladeCenterVpdMachineModel
my $mmoserial = '1.3.6.1.4.1.2.3.51.2.2.21.1.1.3';#bladeCenterSerialNumber
my $bladeoname = '1.3.6.1.4.1.2.3.51.2.22.1.5.1.1.6';#bladeName
my $bladeomodel = '1.3.6.1.4.1.2.3.51.2.2.21.4.1.1.12';#bladeModel

my @macoids = (
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.2', #bladeMACAddress1Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.3', #bladeMACAddress2Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.4', #bladeMACAddress3Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.5', #bladeMACAddress4Vpd
);
my @dcmacoids = (
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.10', #bladeDaughterCard1MACAddress1Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.11', #bladeDaughterCard1MACAddress2Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.12', #bladeDaughterCard1MACAddress3Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.13', #bladeDaughterCard1MACAddress4Vpd
);
my @hsdcmacoids = (
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.100', #bladeHSDaughterCard1MACAddress1Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.101', #bladeHSDaughterCard1MACAddress2Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.102', #bladeHSDaughterCard1MACAddress3Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.103', #bladeHSDaughterCard1MACAddress4Vpd
);
my @bootseqoids = (
  '1.3.6.1.4.1.2.3.51.2.22.1.3.1.7', #bootSequence1
  '1.3.6.1.4.1.2.3.51.2.22.1.3.1.8', #bootSequence2
  '1.3.6.1.4.1.2.3.51.2.22.1.3.1.9', #bootSequence3
  '1.3.6.1.4.1.2.3.51.2.22.1.3.1.10', #bootSequence4
  );
my %bootdevices = (
  0 => 'none',
  1 => 'floppy',
  2 => 'cdrom',
  3 => 'hd0',
  4 => 'hd1',
  5 => 'hd2',
  6 => 'hd3',
  7 => 'net',
  8 => 'iscsi',
  9 => 'iscsicrit',
  10 => 'hd4',
  11 => 'usbflash'
);
my %bootnumbers = (
  'none' => 0,
  'f' => 1,
  'floppy' => 1,
  'c' => 2,
  'cd' => 2,
  'dvd' => 2,
  'cdrom' => 2,
  'dvdrom' => 2,
  'h' => 3, #in absence of an index, presuming hd0 intended
  'hd' => 3,
  'hardisk' => 3,
  'hd0' => 3,
  'harddisk0' => 3,
  'hd1' => 4,
  'harddisk1' => 4,
  'hd2' => 5,
  'harddisk2' => 5,
  'hd3' => 6,
  'harddisk3' => 6,
  'n' => 7,
  'network' => 7,
  'net' => 7,
  'iscsi' => 8,
  'iscsicrit' => 9,
  'hd4' => 10,
  'harddisk4' => 10,
  'usbflash' => 11,
  'flash' => 11,
  'usb' => 11
);

my @rscan_attribs = qw(nodetype name id mtm serial mpa groups mgt);
my @rscan_header = (
  ["type",          "%-8s" ],
  ["name",          "" ],
  ["id",            "%-8s" ],
  ["type-model",    "%-12s" ],
  ["serial-number", "%-15s" ],
  ["address",       "%s\n" ]);

my $session;
my $slot;
my $didchassis = 0;
my @eventlog_array = ();
my $activemm;
my %mpahash;
my $mpa;
my $allinchassis=0;
my $curn;
my @cfgtext;
my $status_noop="XXXno-opXXX";


sub fillresps {
  my $response = shift;
  my $mac = $response->{node}->[0]->{data}->[0]->{contents}->[0];
  my $node = $response->{node}->[0]->{name}->[0];
  $mac = uc($mac); #Make sure it is uppercase, the MM people seem to change their mind on this..
  if ($mac =~ /->/) { #The new and 'improved' syntax for pBlades
      $mac =~ /(\w+):(\w+):(\w+):(\w+):(\w+):(\w+)\s*->\s*(\w+):(\w+):(\w+):(\w+):(\w+):(\w+)/;
      my $fmac=hex($3.$4.$5.$6);
      my $lmac=hex($9.$10.$11.$12);
      my $pfx = $1.$2;
      foreach ($fmac..$lmac) {
          my $key = $pfx.sprintf("%08x",$_);
          $key =~ s/(\w{2})/$1:/g;
          chop($key);
          $key = uc($key);
          $macmap{$key} = $node;
      }
  } else {
    $macmap{$mac} = $node;
  }
  #$macmap{$response->{node}->[0]->{data}->{contents}->[0]}=$response->{node}->[0]->{name};
}
sub isallchassis {
  my $bladesinchassis = 0;
  if ($allinchassis) {
    return 1;
  }
  foreach (1..14) {
    my $tmp = $session->get([$bladexistsoid.".$_"]);
    if ($tmp eq 1) { $bladesinchassis++ }
  }
  my $count = keys %{$mpahash{$mpa}->{nodes}};
  if ($count >= $bladesinchassis) { $allinchassis++; return 1 }; #commands that affect entire are okayed, i.e eventlog clear
  return 0;  
}
sub resetmp {
  my $data;
  my $stat;
  my $rc;
  #$data = $session->set($mpresetoid.".$slot", 1);
  $data = $session->set(new SNMP::Varbind([".".$mpresetoid,$slot,1,'INTEGER']));
  unless ($data) { return (1,$session->{ErrorStr}); }
  return (0,"mpreset");
  #if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
  #if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
  #if ($data->{$mpresetoid.".$slot"} == 1) {
  #  return (0, "mpreset");
  #} else {
  #  return (1,"error");
  #}
}

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
sub walkelog {
  my $session = shift;
  my $oid = shift;
  unless ($oid =~ /^\./) {
    $oid = '.'.$oid;
  }
  my $retmap = undef;
  my $current = 1;
  my @bindlist;
  my $varbind;
  do {
    foreach ($current..$current+31) { #Attempt to retrive 32 ents at a time, seems to be working...
      push @bindlist,[$oid,$_];
    }
    $current+=32;
    $varbind = new SNMP::VarList(
      @bindlist
      );
    $session->get($varbind);
    foreach(@$varbind) {
      unless (${_}->[2]) {last;}
      if( ${_}->[2] =~ /NOSUCHINSTANCE/) {last;}
      $retmap->{$_->[1]}=$_->[2];
    }
    @bindlist=();
  } while ($varbind->[31] and $varbind->[31]->[2] ne 'NOSUCHINSTANCE' and ($current < 2000));

  return $retmap;
  print "Count was $current\n";
  #print Dumper($varbind->[60]->[2]);
  print "\n\n";
  return undef;
  my $count=0;
  while ($varbind->[0] =~ /^$oid\.?(.*)/) {
    $count++;
    if ($1) {
      $retmap->{$1.".".$varbind->[1]}=$varbind->[2]; #If $1 is set, means key should 
    } else {
      $retmap->{$varbind->[1]}=$varbind->[2]; #If $1 is set, means key should 
    }
    $session->getnext($varbind);
  }
  return $retmap;
}

sub eventlog { #Tried various optimizations, but MM seems not to do bulk-request
  #TODO: retrieval of non blade events, what should be syntax?
  #TODO: try retrieving 5 at a time, then 1 at a time when that stops working
  my $cmd=shift;
  my $data;
  my @output;
  my $oid = $eventlogoid;
  unless ($cmd) {
   $cmd='all';
  }
  if ($cmd eq 'all') {
    $cmd=65535; #no MM has this many logs possible, should be a good number
  }
  if ($cmd =~ /^(\d+)$/) {
    my $requestednumber=$1;
    unless (@eventlog_array) {
      #my $varbind=new SNMP::Varbind([$oid,0]);
      #while ($data=$session->getnext($varbind)) {
      #  print Dumper($data);
      #  if ($session->{ErrorStr}) { printf $session->{ErrorStr}."\n"; }
      #  foreach (keys %$data) {
      #    $oid=$_;
      #  }
      #  unless (oid_base_match($eventlogoid,$oid)) {
      #    last;
      #  }
        my $logents = walkelog($session,$oid);
        foreach (sort {$a <=> $b} (keys %$logents)) {
          push @eventlog_array,$logents->{$_}."\n";
        }
        #push @eventlog_array,$data->{$oid}; #TODO: filter against slot number, check for $allchassis for non-blade
      #}
    }
    my $numentries=0;
    #my $allchassis = isallchassis;
    foreach (@eventlog_array) {
      m/Severity:(\S+)\s+Source:(\S+)\s+Name:\S*\s+Date:(\S+)\s+Time:(\S+)\s+Text:(.+)/;
      my $sev=$1;
      my $source=$2;
      my $date=$3;
      my $time=$4;
      my $text=$5;
      my $matchstring;
      if ($slot > 0) {
        $matchstring=sprintf("BLADE_%02d",$slot);
      } else {
        $matchstring="^(?!BLADE).*";
      }
      if ($source =~ m/$matchstring$/i) { #MM guys changed their minds on capitalization
        $numentries++;
        unshift @output,"$sev:$date $time $text"; #unshift to get it in a sane order
      }
      if ($numentries >= $requestednumber) {
        last;
      }
    }
    return (0,@output);
  }
  if ($cmd eq "clear") {
    unless (isallchassis) {
      return (1,"Cannot clear eventlogs except for entire chassis");
    }
    if ($didchassis) { return 0, "eventlog cleared" }
    my $varbind = new SNMP::Varbind([$clearlogoid,0,1,'INTEGER']);
    $data = $session->set($varbind);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $didchassis=1;
    if ($varbind->[2] eq 1) {
      return 0, "eventlog cleared";
    }
  }
}

sub setoid {
   my $oid = shift;
   my $offset = shift;
   my $value = shift;
   my $type = shift;
   unless ($type) { $type = 'INTEGER'; }
   my $varbind = new SNMP::Varbind([$oid,$offset,$value,$type]);
   my $data = $session->set($varbind);
   if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
   return 0,$varbind;
}

sub enabledefaultalerts {
   #Customizers: most oids are listed, and some commented out. uncomment if you want to get them
   #deprecated options are in, but commented, will elect to use what the MM official strategy suggests
   my @enabledalerts = (
      #Deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.1', #critical temperature
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.2', #critical voltage
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.4', #critical blower
      '1.3.6.1.4.1.2.3.51.2.4.2.1.5', #critical power
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.6', #critical Hard drive
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.7', #critical VRM
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.8', #critical switch module
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.1.9', #critical config
      '1.3.6.1.4.1.2.3.51.2.4.2.1.10', #critical blade
      '1.3.6.1.4.1.2.3.51.2.4.2.1.11', #critical IO
      '1.3.6.1.4.1.2.3.51.2.4.2.1.12', #critical storage
      '1.3.6.1.4.1.2.3.51.2.4.2.1.13', #critical chassis
      '1.3.6.1.4.1.2.3.51.2.4.2.1.14', #critical fan
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.2.2', #warn single blower
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.2.3', #warn temp
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.2.4', #warn volt
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.2.6', #warn backup MM
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.2.7', #warn tray/KVM switch prob
      '1.3.6.1.4.1.2.3.51.2.4.2.2.10', #warn log full
      '1.3.6.1.4.1.2.3.51.2.4.2.2.15', #warn blade warning
      '1.3.6.1.4.1.2.3.51.2.4.2.2.16', #warn io warning 
      '1.3.6.1.4.1.2.3.51.2.4.2.2.17', #warn storage warning
      '1.3.6.1.4.1.2.3.51.2.4.2.2.18', #warn power module
      '1.3.6.1.4.1.2.3.51.2.4.2.2.19', #warn chassis
      '1.3.6.1.4.1.2.3.51.2.4.2.2.20', #warn cooling 
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.3.4', #info power off
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.3.5', #info power on
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.3.8', #info PFA
      '1.3.6.1.4.1.2.3.51.2.4.2.3.10', #info inventory (insert/remove)
      '1.3.6.1.4.1.2.3.51.2.4.2.3.11', #info 75% events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.12', #info net reconfig
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.3.13', #info throttling
      #deprecated '1.3.6.1.4.1.2.3.51.2.4.2.3.14', #info power management
      #annoying '1.3.6.1.4.1.2.3.51.2.4.2.3.15', #info login events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.16', #info blade events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.17', #info IO events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.18', #info storage events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.19', #info power module events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.20', #info  chassis events
      '1.3.6.1.4.1.2.3.51.2.4.2.3.21', #info  blower event
      '1.3.6.1.4.1.2.3.51.2.4.2.3.22', #info  power on/off
      );
   setoid('1.3.6.1.4.1.2.3.51.2.4.2.4',0,1);
   foreach (@enabledalerts) {
      setoid($_,0,1);
   }
}
   

sub mpaconfig {
   #OIDs of interest:
   #1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.4 snmpCommunityEntryCommunityIpAddress2
   #snmpCommunityEntryCommunityName 1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.2
   #remoteAlerts 1.3.6.1.4.1.2.3.51.2.4.2
   #remoteAlertIdEntryTextDescription 1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.4
   #remoteAlertIdEntryStatus 1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.2 (0 invalid, 2 enable)

   my $mpa=shift;
   my $user=shift;
   my $pass=shift;
   my $node=shift;
   my $nodeid=shift;
   my $parameter;
   my $value;
   my $assignment;
   my $returncode=0;
   my $textid=0;
   if ($didchassis) { return 0, @cfgtext } #"Chassis already configured for this command" }
   @cfgtext=();

   foreach $parameter (@_) {
      $assignment = 0;
      $value = undef;
      if ($parameter =~ /=/) {
         $assignment = 1;
         ($parameter,$value) = split /=/,$parameter,2;
      }
      if ($parameter =~ /^ntp$/) {
        my $result = ntp($value);
        $returncode |= shift(@$result);
        push @cfgtext,@$result;
        next;
      }
      if ($parameter =~ /^network$/) {
        my $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.1.1.4',0]);
        push @cfgtext,"MM IP: $data";
        $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.1.1.3',0]);
        push @cfgtext,"MM Hostname: $data";
        $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.1.1.9',0]);
        push @cfgtext,"Gateway: $data";
        $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.1.1.14',0]);
        push @cfgtext,"Subnet Mask: $data";
        next;
      }
      if ($parameter eq "textid") {
         if ($assignment) {
           my $txtid = ($value =~ /^\*/) ? $node : $value;
           setoid("1.3.6.1.4.1.2.3.51.2.22.1.7.1.1.5",$nodeid,$txtid,'OCTET');
         }
         my $data;
         if ($slot > 0) {
           $data = $session->get([$bladeoname,$nodeid]);
         }
         else {
           $data = $session->get([$mmoname,0]);
         }
         $textid = 1;
         push @cfgtext,"textid: $data";
      }
      if ($parameter =~ /^snmpcfg$/i) {
         my $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.1.6',0]);
         if ($data) {
            push @cfgtext,"SNMP: enabled";
         }
         else {
            push @cfgtext,"SNMP: disabled";
         }
         next;
      }
      if ($parameter eq "snmpdest") {
         $parameter = "snmpdest1";
      }
      if ($parameter =~ /snmpdest(\d+)/) {
         if ($1 > 3) {
            $returncode |= 1;
            push(@cfgtext,"Only up to three snmp destinations may be defined");
            next;
         }
         my $dstindex = $1;
         if ($assignment) {
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.".(2+$dstindex).".1",1,$value,'OCTET');
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.6.1",1,1,'INTEGER'); #access type: read-traps, don't give full write access to the community
         }
         my $data = $session->get(["1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.".(2+$dstindex).".1.1"]);
         push @cfgtext,"SP SNMP Destination $1: $data";
         next;
      }
      if ($parameter =~ /^community/i) {
         if ($assignment) {
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.2.1.1",0,$value,'OCTET');
         }
         my $data = $session->get(["1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.2.1.1"]);
         push @cfgtext,"SP SNMP Community: $data";
         next;
      }
      if ($parameter =~ /^alert/i) {
         if ($assignment) {
            if ($value =~ /^enable/i or $value =~ /^en/i or $value =~ /^on$/i) {
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.4',12,'xCAT configured SNMP','OCTET'); #Set a description so the MM doesn't flip out
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.5',12,4); #Set Dest12 to SNMP
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.2',12,2); #enable dest12
               setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.1.3',0,0); #Enable SNMP traps
               enabledefaultalerts();
            } elsif ($value =~ /^disable/i or $value =~ /^dis/i or $value =~ /^off$/i) {
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.2',12,0); #Disable alert dest 12
               setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.1.3',0,1); #Disable SNMP traps period
            }
         }
         my $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.2.12']);
         if ($data == 2) {
            push @cfgtext,"SP Alerting: enabled";
            next;
         } else {
            push @cfgtext,"SP Alerting: disabled";
            next;
         }
      }
   }
   unless ($textid) {
     $didchassis=1;
   }
   return $returncode,@cfgtext;
}
   

sub switchblade {
   #OIDS of interest:
   #1.3.6.1.4.1.2.3.51.2.22.1.1 media tray ownership
   #1.3.6.1.4.1.2.3.51.2.22.1.2 kvm ownership
   my @args=@_;
   my $data;
   my @rettext;
   my $domt=0;
   my $dokvm=0;
   my $targnum=$slot;
   if ($args[1] =~ /^\d+$/) {
      $targnum = $args[1];
   }
   if ($args[0] eq "list" or $args[0] eq "stat") {
      $data = $session->get(["1.3.6.1.4.1.2.3.51.2.22.1.1.0"]);
      push @rettext,"Media Tray slot: $data";
      $data = $session->get(["1.3.6.1.4.1.2.3.51.2.22.1.2.0"]);
      push @rettext,"KVM slot: $data";
   } elsif ($args[0] eq "both") {
      $domt=1;
      $dokvm=1;
   } elsif ($args[0] eq "mt" or $args[0] eq "media") {
      $domt=1;
   } elsif ($args[0] eq "kvm" or $args[0] eq "video") {
      $dokvm=1;
   }
   if ($domt) {
      setoid("1.3.6.1.4.1.2.3.51.2.22.1.1",0,$targnum);
      $data = $session->get(["1.3.6.1.4.1.2.3.51.2.22.1.1.0"]);
      push @rettext,"Media Tray slot: $data";
   }
   if ($dokvm) {
      setoid("1.3.6.1.4.1.2.3.51.2.22.1.2",0,$targnum);
      $data = $session->get(["1.3.6.1.4.1.2.3.51.2.22.1.2.0"]);
      push @rettext,"KVM slot: $data";
   }

   return 0,@rettext;
}

sub bootseq {
  my @args=@_;
  my $data;
  my @order=();
  if ($args[0] eq "list" or $args[0] eq "stat") {
    foreach my $oid (@bootseqoids) {
      $data=$session->get([$oid,$slot]);
      if ($session->{ErrorStr}) { return (1, $session->{ErrorStr}); }
      push @order,$bootdevices{$data};
    }
    return (0,join(',',@order));
  } else {
    foreach (@args) {
      my @neworder=(split /,/,$_);
      push @order,@neworder;
    }
    my $number=@order;
    if ($number > 4) {
      return (1,"Only four boot sequence entries allowed");
    }
    my $nonespecified=0;
    foreach (@order) {
      unless (defined($bootnumbers{$_})) { return (1,"Unsupported device $_"); }
      unless ($bootnumbers{$_}) { $nonespecified = 1; }
      if ($nonespecified and $bootnumbers{$_}) { return (1,"Error: cannot specify 'none' before a device"); }
    }
    unless ($bootnumbers{$order[0]}) {
        return (1,"Error: cannot specify 'none' as first device");
    }
    foreach (3,2,1,0) {
      my $param = $bootnumbers{$order[$_]};
      unless ($param) { 
        $param = 0;
        my $varbind = new SNMP::Varbind([$bootseqoids[$_],$slot,$param,'INTEGER']);
        $data = $session->set($varbind);
        #$session->set($bootseqoids[$_].".$slot",$param);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      }
    }
    foreach (0,1,2,3) {
      my $param = $bootnumbers{$order[$_]};
      if ($param) { 
        my $varbind = new SNMP::Varbind([$bootseqoids[$_],$slot,$param,'INTEGER']);
        $data = $session->set($varbind);
        #$session->set($bootseqoids[$_].".$slot",$param);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      }
    }
    return bootseq('list');
  }
}


my %chassiswidevitals;
sub vitals {
   my @output;
   my $tmp;
   my @vitems;

   if ( $#_ == 0 && $_[0] eq '' ) { pop @_; push @_,"all" }	#-- default is all if no argument given

   if ( defined $slot and $slot > 0 ) { 	#-- blade query
     foreach (@_) {
       if ($_ eq 'all') {
         push @vitems,qw(temp voltage wattage summary fan);
         push @vitems,qw(errorled beaconled infoled kvmled mtled);
       } elsif ($_ =~ '^led') {
         push @vitems,qw(errorled beaconled infoled kvmled mtled);
       } else {
         push @vitems,split( /,/,$_);
       }
     }
  } else {		#-- chassis query
     foreach (@_) {
       if ($_ eq 'all') {
         push @vitems,qw(voltage wattage power summary);
         push @vitems,qw(errorled beaconled infoled templed);
         push @vitems,qw(fan blower);
         push @vitems,qw(ammtemp ambient);
       } elsif ($_ =~ '^led') {
         push @vitems,qw(errorled beaconled infoled templed);
       } elsif ($_ =~ '^cool') {
         push @vitems,qw(fan blower);
       } elsif ($_ =~ '^temp') {
         push @vitems,qw(ammtemp ambient);
       } else {
         push @vitems,split( /,/,$_);
       }
     }
  }
  if (grep /fan/,@vitems or grep /blower/,@vitems) { #We'll lump blowers and fans together for blades, besides, BCS fans
                                                     #use the 'blower' OIDs anyway
      unless (defined $chassiswidevitals{blower}) {
          populateblowervitals();
      }
  }
  if (grep /fan/,@vitems) {  #Only put in fans if fan requested, use of word 'blower' would indicate omitting the 'fans'
                             #For those wondering why 'power supply' fans are considered relevant to a particular blade,
                             #note that blades capable of taking high speed daughtercards have holes along the edges.
                             #Those holes are air intakes fed by the PSU exhaust, to get cooler air into the expansion area
      unless (defined $chassiswidevitals{fan}) {
          populatefanvitals();
      }
  }
  my $tmp;

  if ( defined $slot and $slot > 0) {	#-- querying some blade

    if (grep /watt/,@vitems) {
       if ($slot < 8) {
        $tmp = $session->get(["1.3.6.1.4.1.2.3.51.2.2.10.2.1.1.7.".($slot+16)]);
       } else {
        $tmp = $session->get(["1.3.6.1.4.1.2.3.51.2.2.10.3.1.1.7.".($slot+9)]);
       }
       unless ($tmp =~ /Not Readable/) {
         if ($tmp =~ /(\d+)W/) {
             $tmp = "$1 Watts (". int($tmp * 3.413+0.5)." BTUs/hr)";
         }
         $tmp =~ s/^/Power Usage:/;
         push @output,"$tmp";
       }
   }
           
    my @bindlist;
    my $bindobj;
    if (grep /voltage/,@vitems) {
      
      for my $idx (15..40) {
          push @bindlist,[".1.3.6.1.4.1.2.3.51.2.22.1.5.5.1.$idx",$slot];
      }
      $bindobj= new SNMP::VarList(@bindlist);
      $session->get($bindobj); #[".1.3.6.1.4.1.2.3.51.2.22.1.5.5.1.$idx.$slot"]);
      for my $tmp (@$bindobj) {
            if ($tmp and defined $tmp->[2] and $tmp->[2] !~ /Not Readable/ and $tmp->[2] ne "") {
              $tmp =~ s/ = /:/;
              push @output,$tmp->[2];
            }
      }
      @bindlist=();
    }

    if (grep /temp/,@vitems) {
      for my $idx (6..20) {
        if ($idx eq 11) {
          next;
        }
        push @bindlist,[".1.3.6.1.4.1.2.3.51.2.22.1.5.3.1.$idx",$slot];
      }
      $bindobj= new SNMP::VarList(@bindlist);
      $session->get($bindobj);
      for my $tmp (@$bindobj) {
        if ($tmp and defined $tmp->[2] and $tmp->[2] !~ /Not Readable/ and $tmp->[2] ne "") {
          $tmp =~ s/ = /:/;
          push @output,$tmp->[2];
        }
      }
      unless (defined $chassiswidevitals{ambient}) {
          $chassiswidevitals{ambient} = [];
          my @ambientbind=([".1.3.6.1.4.1.2.3.51.2.2.1.5.1","0"],[".1.3.6.1.4.1.2.3.51.2.2.1.5.2","0"]);
          my $targ = new SNMP::VarList(@ambientbind);
          my $tempidx=1;
          $session->get($targ);
          for my $result (@$targ) {
              if ($result->[2] eq "NOSUCHINSTANCE") { next; }
              push @{$chassiswidevitals{ambient}},"Ambient ".$tempidx++." :".$result->[2];
          }
      }
      foreach (@{$chassiswidevitals{ambient}}) {
          push @output,$_;
      }
    }
            
    if (grep /blower/,@vitems) { #We'll lump blowers and fans together for blades, besides, BCS fans
                                                       #use the 'blower' OIDs anyway
        foreach (@{$chassiswidevitals{blower}}) {
            push @output,$_;
        }
    } elsif (grep /fan/,@vitems) { 
        foreach (@{$chassiswidevitals{blower}}) {
            push @output,$_;
        }
        foreach (@{$chassiswidevitals{fan}}) {
            push @output,$_;
        }
    }


    if (grep /summary/,@vitems) {
      $tmp="Status: ".$session->get(['1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.3.'.$slot]);
      $tmp.=", ".$session->get(['1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.4.'.$slot]);
      push @output,"$tmp";
    }

    my %ledresults=();
    my $ledstring="";
    if (grep /led/,@vitems) {
        my @bindset = (
            [$erroroid,$slot],
            [$beaconoid,$slot],
            [$infooid,$slot],
            [$kvmoid,$slot],
            [$mtoid,$slot],
        );
        my $bindlist = new SNMP::VarList(@bindset);
        $session->get($bindlist);
        foreach (@$bindlist) {
            $ledresults{$_->[0] .".". $_->[1]}=$_->[2];
        }
    }
    if (grep /errorled/,@vitems) {
      my $stat = $ledresults{".".$erroroid.".".$slot}; #$session->get([$erroroid.".".$slot]);
      if ($stat==1) { 
          $ledstring=1;
          push @output,"Error LED: on";
        }
      #$tmp="Error led: ".$stat;
    }
 
    if (grep /beaconled/,@vitems) {
      my $stat = $ledresults{".".$beaconoid.".".$slot}; #$session->get([$beaconoid.".".$slot]);
      if ($stat==1) { $stat = "on"; } 
         elsif ($stat==2) { $stat = "blinking"; }
      if ($stat) {
          $ledstring=1;
          $tmp="Beacon led: ".$stat;
          push @output,"$tmp";
      }
    }

    if (grep /infoled/,@vitems) {
      my $stat = $ledresults{".".$infooid.".".$slot}; #$session->get([$infooid.".".$slot]);
      if ($stat==1) { 
          $ledstring=1;
          push @output,"Info led: on";
      }
    }

    if (grep /kvmled/,@vitems) {
      my $stat = $ledresults{".".$kvmoid.".".$slot}; #$session->get([$kvmoid.".".$slot]);
      if ($stat==1) { $stat = "on"; } 
         elsif ($stat==2) { $stat = "blinking"; }
      if ($stat) {
          $ledstring=1;
          $tmp="KVM led: ".$stat;
          push @output,$tmp;
      }
    }

    if (grep /mtled/,@vitems) {
      my $stat = $ledresults{".".$mtoid.".".$slot}; #$session->get([$mtoid.".".$slot]);
      if ($stat==1) { $stat = "on"; } 
        elsif ($stat==2) { $stat = "blinking"; }
      if ($stat) {
          $ledstring=1;
          $tmp="MT led: ".$stat;
          push @output,"$tmp";
      }
    }
    if (grep /led/,@vitems and not $ledstring) {
        push @output,"No active LEDS";
    }

  } else {	#-- chassis query

    if (grep /blower/,@vitems) {
        foreach (@{$chassiswidevitals{blower}}) {
            push @output,$_;
        }
    } elsif (grep /fan/,@vitems) {
        foreach (@{$chassiswidevitals{blower}}) {
            push @output,$_;
        }
        foreach (@{$chassiswidevitals{fan}}) {
            push @output,$_;
        }
    }


     if (grep /volt/,@vitems) {
       my $voltbase = "1.3.6.1.4.1.2.3.51.2.2.2.1";
       my %voltlabels = ( 1=>"+5V", 2=>"+3.3V", 3=>"+12V", 5=>"-5V", 6=>"+2.5V", 8=>"+1.8V" );
       foreach my $idx ( keys %voltlabels ) {
        $tmp=$session->get(["$voltbase.$idx.0"]);
             unless ((not $tmp) or $tmp =~ /Not Readable/) {
               push @output,sprintf("Voltage %s: %s",$voltlabels{$idx},$tmp);
             }
       }
     }

     if (grep /ammtemp/,@vitems) {
         $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.2.1.1.2.0"]);
         push @output,sprintf("AMM temp: %s",$tmp) if $tmp !~ /NOSUCHINSTANCE/;
      }

     if (grep /ambient/,@vitems) {
       my %oids = (
        "Ambient 1",".1.3.6.1.4.1.2.3.51.2.2.1.5.1.0",
        "Ambient 2",".1.3.6.1.4.1.2.3.51.2.2.1.5.2",	
       );
       foreach my $oid ( keys %oids ) {
         $tmp=$session->get([$oids{$oid}]);
         push @output,sprintf("%s: %s",$oid,$tmp) if $tmp !~ /NOSUCHINSTANCE/;
       }
      }

     if (grep /watt/,@vitems) {
         $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.2.10.5.1.2.0"]);
         push @output,sprintf("Total power used: %s (%d BTUs/hr)",$tmp,int($tmp * 3.412+0.5)) if $tmp !~ /NOSUCHINSTANCE/;
     }


     if (grep /power/,@vitems) {
         my %oids = (
          "PD1",".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.3.1",
          "PD2",".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.3.2",
         );
         foreach my $oid ( keys %oids ) {
           $tmp=$session->get([$oids{$oid}]);
           push @output,sprintf("%s: %s",$oid,$tmp) if $tmp !~ /NOSUCHINSTANCE/;
         }
      }


   if (grep /errorled/,@vitems) {
     my $stat = $session->get([$chassiserroroid]);
     if ($stat==0) { $stat = "off"; } elsif ($stat==1) { $stat = "on"; }
     $tmp="Error led: ".$stat;
     push @output,"$tmp";
   }

   if (grep /infoled/,@vitems) {
     my $stat = $session->get([$chassisinfooid]);
     if ($stat==0) { $stat = "off"; } elsif ($stat==1) { $stat = "on"; }
     $tmp="Info led: ".$stat;
     push @output,"$tmp";
   }

   if (grep /templed/,@vitems) {
     my $stat = $session->get([$chassistempledoid]);
     if ($stat==0) { $stat = "off"; } elsif ($stat==1) { $stat = "on"; }
     $tmp="Temp led: ".$stat;
     push @output,"$tmp";
   }

   if (grep /beaconled/,@vitems) {
     my $stat = $session->get([$chassisbeaconoid]);
     if ($stat==0) { $stat = "off"; } elsif ($stat==1) { $stat = "on"; } 
       elsif ($stat==2) { $stat = "blinking"; } elsif ($stat==3) { $stat = "not available"; }
     $tmp="Beacon led: ".$stat;
     push @output,"$tmp";
   }

   if (grep /summary/,@vitems) {
      $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.2.7.1.0"]);
      if ($tmp==0) { $tmp = "critical"; } elsif ($tmp==2) { $tmp = "nonCritical"; } 
        elsif ($tmp==4) { $tmp = "systemLevel"; } elsif ($tmp==255) { $tmp = "normal"; }
      push @output,"Status: $tmp";
   }
}
   return(0,@output);
}
 
sub populatefanvitals { 
#This function populates the fan section of the chassis wide vitals hash
    $chassiswidevitals{fan}=[];
    my @bindlist = (
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.3",1],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.3",2],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.3",3],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.3",4],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.5",1],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.5",2],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.5",3],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.5",4],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.6",1],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.6",2],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.6",3],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.6",4],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.7",1],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.7",2],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.7",3],
        ["1.3.6.1.4.1.2.3.51.2.2.6.1.1.7",4],
     );
    my $bind = new SNMP::VarList(@bindlist);
    my %faninfo;
    $session->get($bind);
    foreach (@$bind) {
        if ($_->[2] eq "NOSUCHINSTANCE") { next; }
        my $restype=$_->[0];
        $restype =~ s/^.*\.(\d*)$/$1/;
        my $idx=$_->[1];
        if ($restype eq "3") {
            $faninfo{$idx}->{state}=$_->[2];
        } elsif ($restype eq "5") {
            $faninfo{$idx}->{percentage}=$_->[2];
        } elsif ($restype eq "6") {
            $faninfo{$idx}->{rpm}=$_->[2];
        } elsif ($restype eq "7") {
            $faninfo{$idx}->{cstate}=$_->[2];
        }
    }
    foreach (sort keys %faninfo) {
        my $text="Fan pack $_:";
        if (defined $faninfo{$_}->{rpm}) {
            $text.=" ".$faninfo{$_}->{rpm};
            if (defined $faninfo{$_}->{percentage}) {
                $text .=" (".$faninfo{$_}->{percentage}."%)";
            } 
            $text .= " RPM";
        } elsif (defined $faninfo{$_}->{percentage}) {
            $text .= " ".$faninfo{$_}->{percentage}."% RPM";
        }
        if ($faninfo{$_}->{state} eq "2") {
            $text .= " Warning";
        } elsif ($faninfo{$_}->{state} eq "3") {
            $text .= " Error";
        }
        if ($faninfo{$_}->{cstate} eq "1") {
            $text .= " (firmware update in progress)";
        } elsif ($faninfo{$_}->{cstate} eq "2") {
            $text .= " (not present)";
        } elsif ($faninfo{$_}->{cstate} eq "3") {
            $text .= " (communication failure";
        }
        push @{$chassiswidevitals{fan}},$text;
    }
}
sub populateblowervitals {
          $chassiswidevitals{blower}=[];
          my @bindoid = (
              [$blower1speedoid,"0"],
              [$blower2speedoid,"0"],
              [$blower3speedoid,"0"],
              [$blower4speedoid,"0"],
              [$blower1stateoid,"0"],
              [$blower2stateoid,"0"],
              [$blower3stateoid,"0"],
              [$blower4stateoid,"0"],
              [$blower1rpmoid,"0"],
              [$blower2rpmoid,"0"],
              [$blower3rpmoid,"0"],
              [$blower4rpmoid,"0"],
              [$blower1contstateoid,"0"],
              [$blower2contstateoid,"0"],
              [$blower3contstateoid,"0"],
              [$blower4contstateoid,"0"],
          );
          my $bind = new SNMP::VarList(@bindoid);
          $session->get($bind);
          my %blowerstats=();
          foreach (@$bind) {
              if ($_->[2] eq "NOSUCHINSTANCE") { next; }
              my $idx=$_->[0];
              $idx =~ s/^.*\.(\d*)$/$1/;
              if ($idx < 10) {
                  $blowerstats{$idx}->{percentage}=$_->[2];
                  $blowerstats{$idx}->{percentage}=~ s/^[^\d]*(\d*)[^\d].*$/$1/;
              } elsif ($idx < 20) {
                  $blowerstats{$idx-9}->{state}=$_->[2];
              } elsif ($idx < 30) {
                  $blowerstats{$idx-19}->{rpm}=$_->[2];
              } elsif ($idx < 40) {
                  $blowerstats{$idx-29}->{cstate}=$_->[2];
              }
          }
          foreach my $blowidx (sort keys %blowerstats) {
              my $bdata=$blowerstats{$blowidx};
              my $text="Blower/Fan $blowidx:";
              if (defined $bdata->{rpm}) {
                  $text.=$bdata->{rpm}." RPM (".$bdata->{percentage}."%)";
              } else {
                  $text.=$bdata->{percentage}."% RPM";
              }
              if ($bdata->{state} == 2) {
                  $text.=" Warning state";
              } elsif ($bdata->{state} == 3) {
                  $text.=" Bad state";
              } elsif ($bdata->{state} == 0) {
                  $text .= " Unknown state";
              }
              if ($bdata->{cstate} == 1) {
                  $text .= " Controller flashing";
              } elsif ($bdata->{cstate} == 2) {
                  $text .= " Not present";
              } elsif ($bdata->{cstate} == 3) {
                  $text .= " Communication failure to controller";
              }
              push @{$chassiswidevitals{blower}},$text;
          }
}
sub rscan {

  my $args = shift;
  my @values;
  my $result;
  my %opt;

  @ARGV = @$args;
  $Getopt::Long::ignorecase = 0;
  Getopt::Long::Configure("bundling");

  local *usage = sub {
    my $usage_string=xCAT::Usage->getUsage("rscan");
    return( join('',($_[0],$usage_string)));
  };

  if ( !GetOptions(\%opt,qw(V|Verbose w x z))){
    return(1,usage());
  }
  if ( defined($ARGV[0]) ) {
    return(1,usage("Invalid argument: @ARGV\n"));
  }
  if (exists($opt{x}) and exists($opt{z})) {
    return(1,usage("-x and -z are mutually exclusive\n"));
  } 
  my $mmname = $session->get([$mmoname,0]);
  if ($session->{ErrorStr}) {
    return(1,$session->{ErrorStr});
  }
  my $mmtype = $session->get([$mmotype,0]);
  if ($session->{ErrorStr}) {
    return(1,$session->{ErrorStr});
  }
  my $mmmodel = $session->get([$mmomodel,0]);
  if ($session->{ErrorStr}) {
    return(1,$session->{ErrorStr});
  }
  my $mmserial = $session->get([$mmoserial,0]);
  if ($session->{ErrorStr}) {
    return(1,$session->{ErrorStr});
  }
  push @values,join(",","mm",$mmname,0,"$mmtype-$mmmodel",$mmserial,$mpa);
  my $max = length($mmname);

  foreach (1..14) {
    my $tmp = $session->get([$bladexistsoid.".$_"]);
    if ($tmp eq 1) {
      my $type = $session->get([$blademtmoid,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      $type =~ s/Not available/null/;

      my $model = $session->get([$bladeomodel,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      $model =~ s/Not available/null/;

      my $serial = $session->get([$bladeserialoid,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      $serial =~ s/Not available/null/;

      my $name = $session->get([$bladeoname,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      push @values, join( ",","blade",$name,$_,"$type-$model",$serial,"");
      my $length  = length($name);
      $max = ($length > $max) ? $length : $max;
    }
  }
  my $format = sprintf "%%-%ds",($max+2);
  $rscan_header[1][1] = $format;

  if (exists($opt{x})) {
    $result = rscan_xml($mpa,\@values); 
  } 
  elsif ( exists( $opt{z} )) {
    $result = rscan_stanza($mpa,\@values); 
  } 
  else {
    foreach ( @rscan_header ) {
      $result .= sprintf @$_[1],@$_[0];
    }
    foreach (@values ){
      my @data = split /,/;
      my $i = 0;

      foreach (@rscan_header) {
        $result .= sprintf @$_[1],$data[$i++];
      }
    }
  }
  if (!exists( $opt{w})) {
    return(0,$result);
  }
  my @tabs = qw(mp nodehm nodelist);
  my %db   = ();

  foreach (@tabs) {
    $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
    if ( !$db{$_} ) {
      return(1,"Error opening '$_'" );
    }
  }
  foreach (@values) {
    my @data = split /,/;
    my $name = $data[1];
  
    my ($k1,$u1);
    $k1->{node} = $name;
    $u1->{mpa}  = $mpa;
    $u1->{id}   = $data[2];
    $db{mp}->setAttribs($k1,$u1);
    $db{mp}{commit} = 1;

    my ($k2,$u2);
    $k2->{node} = $name;
    $u2->{mgt}  = "blade";
    $db{nodehm}->setAttribs($k2,$u2);
    $db{nodehm}{commit} = 1;

    my ($k3,$u3);
    $k3->{node}   = $name;
    $u3->{groups} = "blade,all";
    $db{nodelist}->setAttribs($k3,$u3);
    $db{nodelist}{commit} = 1;
  }
  foreach ( @tabs ) {
    if ( exists( $db{$_}{commit} )) {
       $db{$_}->commit;
    }
  }
  return (0,$result);
}

sub rscan_xml {

  my $mpa = shift;
  my $values = shift;
  my $xml;

  foreach (@$values) {
    my @data = split /,/;
    my $i = 0;

    my $href = {
        Node => { }
    };
    foreach ( @rscan_attribs ) {
        my $d = $data[$i++];
        my $type = $data[0];

        if ( /^name$/ ) {
            next;
        } elsif ( /^nodetype$/ ) {
            $d = $type;
        } elsif ( /^groups$/ ) {
            $d = "$type,all";
        } elsif ( /^mgt$/ ) {
            $d = "blade";
        } elsif ( /^mpa$/ ) {
            $d = $mpa;
        }
        $href->{Node}->{$_} = $d;
    }
    $xml.= XMLout($href,NoAttr=>1,KeyAttr=>[],RootName=>undef);
  }
  return( $xml );
}

sub rscan_stanza {
  
  my $mpa = shift;
  my $values = shift;
  my $result;
  
  foreach (@$values) {
    my @data = split /,/;
    my $i = 0; 
    my $type = $data[0];
    $result .= "$data[1]:\n\tobjtype=node\n";

    foreach ( @rscan_attribs ) {
        my $d = $data[$i++];

        if ( /^name$/ ) {
            next; 
        } elsif ( /^nodetype$/ ) {
            $d = $type;
        } elsif ( /^groups$/ ) {
            $d = "$type,all";
        } elsif ( /^mgt$/ ) {
            $d = "blade"; 
        } elsif ( /^mpa$/ ) {
            $d = $mpa;
        }
        $result .= "\t$_=$d\n";
    }
  }
  return( $result );
}

sub getmacs {
   (my $code,my @macs)=inv('mac');
   my $midx=0;
   my @midxary;
   my $nrtab = xCAT::Table->new('noderes');
   if ($nrtab) {
       my $nent = $nrtab->getNodeAttribs($curn,['primarynic','installnic']);
       if ($nent) {
           my $mkey;
           if (defined $nent->{installnic}) { #Prefer the install nic
               $mkey="installnic";
           } elsif (defined $nent->{primarynic}) { #see if primary nic was set
               $mkey="primarynic";
           }
           if ($mkey) {
	     while ( $nent->{$mkey} =~ /(\d+)/g ) {
	       push @midxary,$1;
	     }
           }
       }
   }
   if ($code==0) {
      #my @macs = split /\n/,$macs;
    my @allmacs;
    foreach my $midx ( @midxary) {
       (my $macd,my $mac) = split (/:/,$macs[$midx],2);
       $mac =~ s/\s+//g;
       if ($macd =~ /mac address \d/i) {
          $mac =~ s/\s*->.*$//;
       } else {
           return 1,"Unable to retrieve MAC address for interface $midx from Management Module";
       }

       if ( $#midxary == 0 ) { #-- backward compatibility mode - do not add host name to mac.mac if only one iface is used
        push @allmacs,$mac;
       } else {
        push @allmacs,$mac."!".$curn."e".$midx;
       }
    }

    my $macstring = join("|",@allmacs);
    my $mactab = xCAT::Table->new('mac',-create=>1);
    $mactab->setNodeAttribs($curn,{mac=>$macstring});
    $mactab->close;
    return 0,":mac.mac set to $macstring";
   } else {
      return $code,$macs[0];
   }
}
   
sub inv {
  my @invitems;
  my $data;
  my @output;
  foreach (@_) {
    push @invitems,split( /,/,$_);
  }
  my $item;
  unless (scalar(@invitems)) {
      @invitems = ("all");
  }
  while (my $item = shift @invitems) {
    if ($item =~ /^all/) {
      push @invitems,(qw(mtm serial mac firm));
      next;
    }
    if ($item =~ /^firm/) {
      push @invitems,(qw(bios diag mprom mparom));
      next;
    }
    if ($item =~ /^bios/) {
      my $biosver;
      my $biosbuild;
      my $biosdate;
      $biosver=$session->get([$bladebiosveroid.".$slot"]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $biosbuild=$session->get([$bladebiosbuildidoid.".$slot"]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $biosdate=$session->get([$bladebiosdateoid.".$slot"]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      push @output,"BIOS: $biosver ($biosbuild $biosdate)";
    }
    if ($item =~ /^diag/) {
      my $diagver;
      my $diagdate;
      my $diagbuild;
      $data=$session->get([$bladediagveroid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $diagver = $data;
      $data=$session->get([$bladediagbuildidoid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $diagbuild = $data;
      $data=$session->get([$bladediagdateoid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $diagdate = $data;
      push @output,"Diagnostics:  $diagver ($diagbuild $diagdate)";
    }
    if ($item =~ /^[sm]prom/) {
      my $spver;
      my $spbuild;
      $data=$session->get([$bladempveroid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $spver=$data;
      $data=$session->get([$bladempbuildidoid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $spbuild=$data;
      push @output,"BMC/Mgt processor:  $spver ($spbuild)";
    }
    if ($item =~ /^mparom/) {
      my $mpabuild;
      my $mpaver;
      my $mpadate;
      $data=$session->get([$bladempaveroid,$activemm]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $mpaver=$data;
      $data=$session->get([$bladempabuildidoid,$activemm]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $mpabuild=$data;
      $data=$session->get([$bladempadateoid,$activemm]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $mpadate=$data;
      push @output,"Management Module firmware: $mpaver ($mpabuild $mpadate)";
    }
    if ($item =~ /^model/ or $item =~ /^mtm/) {
      $data=$session->get([$blademtmoid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      push @output,"Machine Type/Model: ".$data;
    }
    if ($item =~ /^serial/) {
      $data=$session->get([$bladeserialoid,$slot]);
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      push @output,"Serial Number: ".$data;
    }

    if ($item =~ /^mac/) {
      foreach (0..3) {
        $data=$session->get([$macoids[$_],$slot]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($data =~ /:/) {
          push @output,"MAC Address ".($_+1).": ".$data; 
        }
      }
      foreach (0..3) {
        my $oid=$hsdcmacoids[$_].".$slot";
        $data=$session->get([$hsdcmacoids[$_],$slot]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($data =~ /:/) {
          push @output,"HS Daughter card MAC Address ".($_+1).": ".$data;
        }
      }
      foreach (0..3) {
        $data=$session->get([$dcmacoids[$_],$slot]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($data =~ /:/) {
          push @output,"Daughter card 1 MAC Address ".($_+1).": ".$data;
        }
      }
    }
  }
  return (0,@output);
}
sub power {
  my $subcommand = shift;
  my $data;
  my $stat;
  my $validsub=0;
  unless ($slot > 0) {
     if ($subcommand eq "reset" or $subcommand eq "boot") {
        $data = $session->set(new SNMP::Varbind([".1.3.6.1.4.1.2.3.51.2.7.4",0,1,'INTEGER']));
        unless ($data) { return (1,$session->{ErrorStr}); }
        return (0,"reset");
     } else {
        return (1,"$subcommand unsupported on the management module");
     }
  }
   
  #get stat first  
  $validsub=1;
  $data = $session->get([$powerstatoid.".".$slot]);
  if ($data == 1) {
    $stat = "on";
  } elsif ( $data == 0) {
    $stat = "off";
  } else {
    $stat= "error";
  }
  
  my $old_stat=$stat;
  if ($subcommand eq "softoff") {
    $validsub=1;
    $data = $session->set(new SNMP::Varbind([".".$powerchangeoid,$slot,2,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    $stat = "softoff"; 
    if ($old_stat eq "off") { $stat .= " $status_noop"; }
  } 
  if ($subcommand eq "off") {
    $validsub=1;
    $data = $session->set(new SNMP::Varbind([".".$powerchangeoid,$slot,0,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    $stat = "off"; 
    if ($old_stat eq "off") { $stat .= " $status_noop"; }
  } 
  if ($subcommand eq "on" or ($subcommand eq "boot" and $stat eq "off")) {
    $data = $session->set(new SNMP::Varbind([".".$powerchangeoid,$slot,1,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    if ($subcommand eq "boot") { $stat .= " " . ($data ? "on" : "off"); } 
    if ($subcommand eq "on") {
      $stat = ($data ? "on" : "off");
      if ($old_stat eq "on") { $stat .= " $status_noop"; }
    }
  } elsif ($subcommand eq "reset" or ($subcommand eq "boot" and $stat eq "on")) {
    $data = $session->set(new SNMP::Varbind([".".$powerresetoid,$slot ,1,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    if ($subcommand eq "boot") { $stat = "on reset"; } else { $stat = "reset"; }
  } elsif (not $validsub) {
      return 1,"Unknown/Unsupported power command $subcommand";
  }
  if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
  if ($stat) { return (0,$stat); }
}
    

sub beacon {
  my $subcommand = shift;
  my $data;
  if ($subcommand eq "stat") {
  } elsif ($subcommand eq "on") {
    $data = $session->set(new SNMP::Varbind([$beaconoid,$slot , 1,'INTEGER']));
  } elsif ($subcommand eq "off") {
    $data = $session->set(new SNMP::Varbind([$beaconoid,$slot , 0,'INTEGER']));
  } elsif ($subcommand eq "blink") {
    $data = $session->set(new SNMP::Varbind([$beaconoid,$slot , 2,'INTEGER']));
  } else {
    return (1,"$subcommand unsupported");
  }
  my $stat = $session->get([$beaconoid.".".$slot]);
  if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
  if ($stat==0) {
    return (0,"off");
  } elsif ($stat==1) {
    return (0,"on");
  } elsif ($stat==2) {
    return (0,"blink");
  } elsif ($stat==3) {
    return (0,"unsupported");
  }
}

sub bladecmd {
  $mpa = shift;
  my $node = shift;
  $slot = shift;
  my $user = shift;
  my $pass = shift;
  my $command = shift;
  my @args = @_;
  my $error;

  if ($slot > 0) {
    my $tmp = $session->get([$bladexistsoid.".$slot"]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    unless ($tmp eq 1) { return (1,"Target bay empty"); }
  }
  if ($command eq "rbeacon") {
    return beacon(@args);
  } elsif ($command eq "rpower") {
    return power(@args);
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
  
  return (1,"$command not a supported command by blade method");
}

sub handle_depend {
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my $dp = shift;
  my %node = ();
  my $dep = @$dp[0];
  my $dep_hash = @$dp[1];
 
  # send all dependencies (along w/ those dependent on nothing)
  # build moreinfo for dependencies 
  my %mpa_hash = ();
  my @moreinfo=();
  my $reqcopy = {%$request};
  my @nodes=();

  foreach my $node (keys %$dep) {
    my $mpa = @{$dep_hash->{$node}}[0];
    push @{$mpa_hash{$mpa}{nodes}},$node;
    push @{$mpa_hash{$mpa}{ids}},  @{$dep_hash->{$node}}[1];
  }
  foreach (keys %mpa_hash) {
    push @nodes, @{$mpa_hash{$_}{nodes}};
    push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
  }
  $reqcopy->{node} = \@nodes;
  $reqcopy->{moreinfo}=\@moreinfo;
  process_request($reqcopy,$callback,$doreq,1); 
 
  my $start = Time::HiRes::gettimeofday();
    
  # build list of dependent nodes w/delays
  while(my ($name,$h) = each(%$dep) ) {
    foreach ( keys %$h ) { 
      if ( $h->{$_} =~ /(^\d+$)/ ) {
        $node{$_} = $1/1000.0;
      }
    }
  }
  # send each dependent node as its delay expires
  while (%node) {
    my @noderange = ();
    my $delay = 0.1;
    my $elapsed = Time::HiRes::gettimeofday()-$start;

    # sort in ascending delay order
    foreach (sort {$node{$a} <=> $node{$b}} keys %node) {
      if ($elapsed < $node{$_}) {
        $delay = $node{$_}-$elapsed;
        last;
      }
      push @noderange,$_;
      delete $node{$_};
    }
    if (@noderange) {
      %mpa_hash=();
      foreach my $node (@noderange) {
        my $mpa = @{$dep_hash->{$node}}[0];
        push @{$mpa_hash{$mpa}{nodes}},$node;
        push @{$mpa_hash{$mpa}{ids}},  @{$dep_hash->{$node}}[1];
      }

      @moreinfo=();
      $reqcopy = {%$request};
      @nodes=();

      foreach (keys %mpa_hash) {
        push @nodes, @{$mpa_hash{$_}{nodes}};
        push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
      }
      $reqcopy->{node} = \@nodes;
      $reqcopy->{moreinfo}=\@moreinfo;

      # clear global hash variable
      %mpahash = ();
      process_request($reqcopy,$callback,$doreq,1);
    }
    # millisecond sleep
    Time::HiRes::sleep($delay);
  }
  return 0;
}

sub build_depend {
  my $noderange = shift;
  my $exargs = shift;
  my $depstab  = xCAT::Table->new('deps');
  my $mptab    = xCAT::Table->new('mp');
  my %dp    = ();
  my %no_dp = ();
  my %mpa_hash;

  if (!defined($depstab)) {
    return([\%dp]);
  }
  unless ($mptab) {
    return("Cannot open mp table");
  }

  my $depset = $depstab->getNodesAttribs($noderange,[qw(nodedep msdelay cmd)]);
  foreach my $node (@$noderange) {
    my $delay = 0;
    my $dep;

    my @ent = @{$depset->{$node}}; #$depstab->getNodeAttribs($node,[qw(nodedep msdelay cmd)]);
    foreach my $h ( @ent ) {
        if ( grep(/^@$exargs[0]$/, split /,/, $h->{cmd} )) {
          if (exists($h->{nodedep})) { $dep=$h->{nodedep}; }
          if (exists($h->{msdelay})) { $delay=$h->{msdelay}; }
          last;
      }
    }
    if (!defined($dep)) {
      $no_dp{$node} = 1;
    }
    else {
      foreach my $n (split /,/,$dep ) {
        if ( !grep( /^$n$/, @$noderange )) {
          return( "Missing dependency on command-line: $node -> $n" );
        } elsif ( $n eq $node ) {
          next;  # ignore multiple levels
        }
        $dp{$n}{$node} = $delay;
      }
    }
  }
  # if there are dependencies, add any non-dependent nodes
  if (scalar(%dp)) {
    foreach (keys %no_dp) {
      if (!exists( $dp{$_} )) {
        $dp{$_}{$_} = -1;
      }
    }
    # build hash of all nodes in preprocess_request() format
    my @namelist = keys %dp;
    my $mphash = $mptab->getNodesAttribs(\@namelist,['mpa','id']);
    while(my ($name,$h) = each(%dp) ) {
      my $ent=$mphash->{$name}->[0]; #$mptab->getNodeAttribs($name,['mpa', 'id']);
      if (!defined($ent->{mpa})) {
        return("no mpa defined for node $name");
      }
      my $id = (defined($ent->{id})) ? $ent->{id} : "";
      push @{$mpa_hash{$name}},$ent->{mpa};
      push @{$mpa_hash{$name}},$id;

      @namelist = keys %$h;
      my $mpsubhash = $mptab->getNodesAttribs(\@namelist,['mpa','id']);
      foreach ( keys %$h ) {
        if ( $h->{$_} =~ /(^\d+$)/ ) {
          my $ent=$mpsubhash->{$_}->[0]; #$mptab->getNodeAttribs($_,['mpa', 'id']);
          if (!defined($ent->{mpa})) {
            return("no mpa defined for node $_");
          }
          my $id = (defined($ent->{id})) ? $ent->{id} : "";
          push @{$mpa_hash{$_}},$ent->{mpa};
          push @{$mpa_hash{$_}},$id;
        }
      }
    }
  }
  return( [\%dp,\%mpa_hash] );
}

sub httplogin {
       #TODO: Checked for failed login here.
       my $mpa = shift;
       my $user = shift;
       my $pass = shift;
       my $url="http://$mpa/shared/userlogin.php";
       $browser = LWP::UserAgent->new;
       $browser->cookie_jar({});
       my $response = $browser->post($url,{userid=>$user,password=>$pass,login=>"Log In"});
       $response = $browser->post("http://$mpa/shared/welcome.php",{timeout=>1,save=>""});
       $response = $browser->post("http://$mpa/shared/welcomeright.php",{timeout=>1,save=>""});
}
sub get_kvm_params {
    my $mpa = shift;
    my $response = $browser->get("http://$mpa/private/vnc_only.php");
    my $html = $response->{_content};
    my $destip;
    my $rbs;
    foreach (split /\n/,$html) {
        if (/<param\s+name\s*=\s*"([^"]*)"\s+value\s*=\s*"([^"]*)"/) {
           if ($1 eq 'ip') {
               $destip=$2;
           } elsif ($1 eq 'rbs') {
                $rbs = $2;
           }
        }
    }
    return ($destip,$rbs);
}
       




sub getbladecons {
   my $noderange = shift;
   my $callback=shift;
   my $mpatab = xCAT::Table->new('mpa');
   my $passtab = xCAT::Table->new('passwd');
   my $tmp;
   my $user="USERID";
   if ($passtab) {
     ($tmp)=$passtab->getAttribs({'key'=>'blade'},'username');
     if (defined($tmp)) {
       $user = $tmp->{username};
     }
   }
   my %mpausers;
   my %checkedmpas=();
   my $mptab=xCAT::Table->new('mp');
   my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id']);
   foreach my $node (@$noderange) {
      my $rsp = {node=>[{name=>[$node]}]};
      my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
      if (defined($ent->{mpa})) { 
          $rsp->{node}->[0]->{mm}->[0]=$ent->{mpa};
          if (defined($checkedmpas{$ent->{$mpa}}) or not defined $mpatab) {
            if (defined($mpausers{$ent->{mpa}})) {
                $rsp->{node}->[0]->{username}=[$mpausers{$ent->{mpa}}];
            } else {
                $rsp->{node}->[0]->{username}=[$user];
            }
          } else {
              $checkedmpas{$ent->{$mpa}}=1;
              ($tmp)=$mpatab->getAttribs({'mpa'=>$mpa},'username');
              if (defined($tmp) and defined $tmp->{username}) {
                  $mpausers{$ent->{mpa}}=$tmp->{username};
                  $rsp->{node}->[0]->{username}=[$tmp->{username}];
              } else {
                  $rsp->{node}->[0]->{username}=[$user];
              }

          }
      } else { 
          $rsp->{node}->[0]->{error}=["no mpa defined"];
          $rsp->{node}->[0]->{errorcode}=[1];
          $callback->($rsp);
          next;
      }
      if (defined($ent->{id})) { 
          $rsp->{node}->[0]->{slot}=$ent->{id};
      } else { 
          $rsp->{node}->[0]->{slot}="";
      }
      $callback->($rsp);
   }
}

sub preprocess_request { 
  my $request = shift;
  if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
  my $callback=shift;
  my @requests;

  #display usage statement if -h is present or no noderage is specified
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

  #get the MMs for the nodes for the nodes in order to figure out which service nodes to send the requests to
  my $mptab = xCAT::Table->new("mp");
  unless ($mptab) { 
    $callback->({data=>["Cannot open mp table"]});
    $request = {};
    return;
  }
  my %mpa_hash=();
  my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id']);
  if ($request->{command}->[0] eq "getbladecons") { #Can handle it here and now
      getbladecons($noderange,$callback);
      return [];
  }


  foreach my $node (@$noderange) {
    my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
    if (defined($ent->{mpa})) { push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;}
    else { 
      $callback->({data=>["no mpa defined for node $node"]});
      $request = {};
      return;
    }
    if (defined($ent->{id})) { push @{$mpa_hash{$ent->{mpa}}{ids}}, $ent->{id};}
    else { push @{$mpa_hash{$ent->{mpa}}{ids}}, "";} 
  }

  # find service nodes for the MMs
  # build an individual request for each service node
  my $service  = "xcat";
  my @mms=keys(%mpa_hash);
  my $sn = xCAT::Utils->get_ServiceNode(\@mms, $service, "MN");

  # build each request for each service node
  foreach my $snkey (keys %$sn)
  {
    #print "snkey=$snkey\n";
    my $reqcopy = {%$request};
    $reqcopy->{'_xcatdest'} = $snkey;
    my $mms1=$sn->{$snkey};
    my @moreinfo=();
    my @nodes=();
    foreach (@$mms1) { 
      push @nodes, @{$mpa_hash{$_}{nodes}};
      push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
    }
    $reqcopy->{node} = \@nodes;
    #print "nodes=@nodes\n";
    $reqcopy->{moreinfo}=\@moreinfo;
    push @requests, $reqcopy;
  }
  return \@requests;
}
    
     
sub build_more_info{
  my $noderange=shift;
  my $callback=shift;
  my $mptab = xCAT::Table->new("mp");
  my @moreinfo=();
  unless ($mptab) { 
    $callback->({data=>["Cannot open mp table"]});
    return @moreinfo;
  }
  my %mpa_hash=();
  my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id']);
  foreach my $node (@$noderange) {
    my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
    if (defined($ent->{mpa})) { push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;}
    else { 
      $callback->({data=>["no mpa defined for node $node"]});
      return @moreinfo;;
    }
    if (defined($ent->{id})) { push @{$mpa_hash{$ent->{mpa}}{ids}}, $ent->{id};}
    else { push @{$mpa_hash{$ent->{mpa}}{ids}}, "";} 
  }

  foreach (keys %mpa_hash) {
    push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";
    
  }

  return \@moreinfo;
}

sub process_request { 
  $SIG{INT} = $SIG{TERM} = sub { 
     foreach (keys %mm_comm_pids) {
        kill 2, $_;
     }
     exit 0;
  };

  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
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

  my $moreinfo;
  if ($request->{moreinfo}) { $moreinfo=$request->{moreinfo}; }
  else {  $moreinfo=build_more_info($noderange,$callback);} 

  if ($command eq "rpower" and grep(/^on|off|boot|reset|cycle$/, @exargs)) {

    if ( my ($index) = grep($exargs[$_]=~ /^--nodeps$/, 0..$#exargs )) {
      splice(@exargs, $index, 1);
    } else {
      # handles 1 level of dependencies only
      if (!defined($level)) {
        my $dep = build_depend($noderange,\@exargs);
        if ( ref($dep) ne 'ARRAY' ) {
          $callback->({data=>[$dep],errorcode=>1});
          return;
        }
        if (scalar(%{@$dep[0]})) {
          handle_depend( $request, $callback, $doreq, $dep );
          return 0;
        } 
      }
    }
  }
  # only 1 node when changing textid to something other than '*'
  if ($command eq "rspconfig" and grep(/^textid=[^*]/,@exargs)) {
    if ( @$noderange > 1 ) {
      $callback->({data=>["Single node required when changing textid"],
                   errorcode=>1});
      return;
    }
  }
  my $bladeuser = 'USERID';
  my $bladepass = 'PASSW0RD';
  my $blademaxp = 64;
  my $sitetab = xCAT::Table->new('site');
  my $mpatab = xCAT::Table->new('mpa');
  my $mptab = xCAT::Table->new('mp');
  my $tmp;
  if ($sitetab) {
    ($tmp)=$sitetab->getAttribs({'key'=>'blademaxp'},'value');
    if (defined($tmp)) { $blademaxp=$tmp->{value}; }
  }
  my $passtab = xCAT::Table->new('passwd');
  if ($passtab) {
    ($tmp)=$passtab->getAttribs({'key'=>'blade'},'username','password');
    if (defined($tmp)) {
      $bladeuser = $tmp->{username};
      $bladepass = $tmp->{password};
    }
  }
  if ($request->{command}->[0] eq "findme") {
    my $mptab = xCAT::Table->new("mp");
    unless ($mptab) { return 2; }
    my @bladents = $mptab->getAllNodeAttribs([qw(node)]);
    my @blades;
    foreach (@bladents) {
      push @blades,$_->{node};
    }
    my %invreq;
    $invreq{node} = \@blades;
    $invreq{arg} = ['mac'];
    $invreq{command} = ['rinv'];
    my $mac;
    my $ip = $request->{'_xcat_clientip'};
    my $arptable = `/sbin/arp -n`;
    my @arpents = split /\n/,$arptable;
    foreach  (@arpents) {
      if (m/^($ip)\s+\S+\s+(\S+)\s/) {
        $mac=$2;
        last;
      }
    }
    unless ($mac) { return };

    #Only refresh the the cache when the request permits and no useful answer
    if ($macmaptimestamp < (time() - 300)) { #after five minutes, invalidate cache
       %macmap = ();
    }
    
    unless ($request->{cacheonly}->[0] or $macmap{$mac} or $macmaptimestamp > (time() - 20)) { #do not refresh cache if requested not to, if it has an entry, or is recent
      %macmap = ();
      $macmaptimestamp=time();
      foreach (@{preprocess_request(\%invreq,\&fillresps)}) {
         %invreq = %$_;
         process_request(\%invreq,\&fillresps);
      }
    }
    unless ($macmap{$mac}) { 
      return 1; #failure
    }
    my $mactab = xCAT::Table->new('mac',-create=>1);
    $mactab->setNodeAttribs($macmap{$mac},{mac=>$mac});
    $mactab->close();
    #my %request = (
    #  command => ['makedhcp'],
    #  node => [$macmap{$mac}]
    #  );
    #$doreq->(\%request);
    $request->{command}=['discovered'];
    $request->{noderange} = [$macmap{$mac}];
    $doreq->($request);
    %{$request}=(); #Clear request. it is done
    undef $mactab;
    return 0;
  }


  my $children = 0;
  $SIG{CHLD} = sub { my $cpid; while ($cpid = waitpid(-1, WNOHANG) > 0) { delete $mm_comm_pids{$cpid}; $children--; } };
  my $inputs = new IO::Select;;
  foreach my $info (@$moreinfo) {
    $info=~/^\[(.*)\]\[(.*)\]\[(.*)\]/;
    my $mpa=$1;
    my @nodes=split(',', $2);
    my @ids=split(',', $3);
    #print "mpa=$mpa, nodes=@nodes, ids=@ids\n";
    my $user=$bladeuser;
    my $pass=$bladepass;
    my $ent;
    if (defined($mpatab)) {
      ($ent)=$mpatab->getAttribs({'mpa'=>$mpa},'username','password');
      if (defined($ent->{password})) { $pass = $ent->{password}; }
      if (defined($ent->{username})) { $user = $ent->{username}; }
    }
    $mpahash{$mpa}->{username} = $user;
    $mpahash{$mpa}->{password} = $pass;
    for (my $i=0; $i<@nodes; $i++) {
      my $node=$nodes[$i];;
      my $nodeid=$ids[$i];
      $mpahash{$mpa}->{nodes}->{$node}=$nodeid;
    }
  }
  my $sub_fds = new IO::Select;
  foreach $mpa (sort (keys %mpahash)) {
    while ($children > $blademaxp) { forward_data($callback,$sub_fds); }
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
      dompa($pfd,$mpa,\%mpahash,$command,-args=>\@exargs);
      exit(0);
    }
    $mm_comm_pids{$cpid} = 1;
    close ($pfd);
    $sub_fds->add($cfd);
  }
  while ($sub_fds->count > 0 or $children > 0) {
    forward_data($callback,$sub_fds);
  }
  while (forward_data($callback,$sub_fds)) {}
}

sub telnetcmds {

  my $mpa=shift;
  my $user=shift;
  my $pass=shift;
  my $nodeid=shift;
  my $value;
  my @unhandled;
  my %handled = ();
  my $result;
  my @tcmds = qw(snmpcfg sshcfg network swnet pd1 pd2 textid network_reset);

  # most of these commands should be able to be done
  # through SNMP, but they produce various errors.
  foreach my $cmd (@_) {
    if ($cmd =~ /^swnet|pd1|pd2|sshcfg|=/) {
      if (($cmd =~ /^textid/) and ($nodeid > 0)) {
        push @unhandled,$cmd;
        next;
      }
      my ($command,$value) = split /=/,$cmd;
      if (grep(/^$command$/,@tcmds)) {
        $handled{$command} = $value;
        next;
      }
    }
    push @unhandled,$cmd;
  }
  unless (%handled) {
    return([0,\@unhandled]);
  }
  my $t = new Net::Telnet(
                Timeout=>15, 
                Errmode=>'return',
                Prompt=>'/system> $/'
  );
  my $Rc = $t->open($mpa);
  if ($Rc) {
    $Rc = $t->login($user,$pass); 
  }
  if (!$Rc) {
    push @cfgtext,$t->errmsg;
    return([1,\@unhandled,$t->errmsg]);
  }
  $Rc = 0;
  my $mm;
  my @data = $t->cmd("list -l 2");
  foreach (@data) {
    if (/(mm\[\d+\])\s+primary/) {
      $mm = $1;
      last;
    }
  }
  if (!defined($mm)) {
    push @cfgtext,"Cannot find primary MM";
    return([1,\@unhandled]);
  }
  @data = ();

  foreach (keys %handled) {
    if (/^snmpcfg/)     { $result = snmpcfg($t,$handled{$_},$user,$pass,$mm); }
    elsif (/^sshcfg$/)  { $result = sshcfg($t,$handled{$_},$user,$mm); }
    elsif (/^network$/) { $result = network($t,$handled{$_},$mpa,$mm); }
    elsif (/^swnet$/)   { $result = swnet($t,$handled{$_}); }
    elsif (/^pd1|pd2$/) { $result = pd($t,$_,$handled{$_}); }
    elsif (/^textid$/)  { $result = mmtextid($t,$mpa,$handled{$_},$mm); }
    elsif (/^network_reset$/) { $result = network($t,$handled{$_},$mpa,1); }
    push @data, "$_: @$result";
    $Rc |= shift(@$result);
    push @cfgtext,@$result;
  }
  $t->close;
  return([$Rc,\@unhandled,\@data]);
}


sub mmtextid {

  my $t = shift;
  my $mpa = shift;
  my $value = shift;
  my $mm = shift;

  $value = ($value =~ /^\*/) ? $mpa : $value;
  my @data = $t->cmd("config -name $value -T system:$mm");
  if (!grep(/OK/i,@data)) {
    return([1,@data]);
  }
  return([0,"textid: $value"]);
}


sub pd {

  my $t = shift;
  my $pd = shift;
  my $value = shift;
  my @result;

  if ($value) {
    if ($value !~ /^nonred|redwoperf|redwperf$/) {
      return([1,"Invalid power management (redwoperf|redwperf|nonred)"]); 
    }
    my @data = $t->cmd("fuelg $pd -os $value");
    if (!grep(/OK/i,@data)) {
      return([1,@data]);
    }
    return([0,"$pd: $value"]);
  }
  my @data = $t->cmd("fuelg");
  my @pds = split /--------------/,join('',@data);
  $pd =~ /pd(\d)/;

  $pds[$1] =~ /Power Management Policy:\s+(.*)\n/;
  return([0,$1]);
}


sub network {

  my $t = shift;
  my $value = shift;
  my $mpa = shift;
  my $reset = shift;
  my $mm = shift;
  my $cmd = "ifconfig -eth0 -c static -r auto -d auto -m 1500 -T system:$mm";
  my ($ip,$host,$gateway,$mask);

  if ($value) {
    if ($value !~ /\*/) {
      ($ip,$host,$gateway,$mask) = split /,/,$value;
      if (!$ip and !$host and !$gateway and !$mask) {
        return([1,"No changes specified"]);
      }
    }
    else {
      if ( $value !~ /^\*$/) {
        return([1,"Invalid format: 'network=*'"]);
      }
      my %nethash = xCAT::DBobjUtils->getNetwkInfo([$mpa]);
      my $gate = $nethash{$mpa}{gateway};
      my $result; 

      if ($gate) {
        $result = xCAT::Utils::toIP($gate);
        if (@$result[0] == 0) {
          $gateway = @$result[1];
        }
      }
      $mask = $nethash{$mpa}{mask};
      $host = $mpa;

      my $hosttab = xCAT::Table->new( 'hosts' );
      if ($hosttab) {
        my ($ent) = $hosttab->getAttribs({node=>$mpa},'ip');
        if (defined($ent)) {
          $ip = $ent->{ip};
        }
        $hosttab->close();
      }
    }
  }

  if ($ip)     { $cmd.=" -i $ip"; }
  if ($host)   { $cmd.=" -n $host"; }
  if ($gateway){ $cmd.=" -g $gateway"; }
  if ($mask)   { $cmd.=" -s $mask"; }

  my @data = $t->cmd($cmd);
  my @result = grep(/These configuration changes will become active/,@data);
  if (!@result) {
    return([1,@data]);
  }
  if ($ip)     { push @result,"MM IP: $ip"; }
  if ($host)   { push @result,"MM Hostname: $host"; }
  if ($gateway){ push @result,"Gateway: $gateway"; }
  if ($mask)   { push @result,"Subnet Mask: $mask"; }

  if (defined($reset)) {
      $t->cmd("reset -T system:$mm");
  } 
  return([0,@result]);

}


sub swnet {

  my $t = shift;
  my $value = shift;
  my @result;
  my ($ip,$gateway,$mask);

  if (!$value) {
    my @data = $t->cmd("ifconfig -T system::switch[1]");
    my $s = join('',@data);
    if ($s =~ /-i\s+(\S+)/) { $ip = $1; }
    if ($s =~ /-g\s+(\S+)/) { $gateway = $1; }
    if ($s =~ /-s\s+(\S+)/) { $mask = $1; }
  }
  else {
    my $cmd =
       "ifconfig -em disabled -ep enabled -pip enabled -T system:switch[1]";
    ($ip,$gateway,$mask) = split /,/,$value;

    if (!$ip and !$gateway and !$mask) {
      return([1,"No changes specified"]);
    }
    if ($ip)     { $cmd.=" -i $ip"; }
    if ($gateway){ $cmd.=" -g $gateway"; }
    if ($mask)   { $cmd.=" -s $mask"; }
   
    my @data = $t->cmd($cmd);
    @result = grep(/OK/i,@data);
    if (!@result) {
      return([1,@data]);
    }
  }
  if ($ip)     { push @result,"Switch IP: $ip"; }
  if ($gateway){ push @result,"Gateway: $gateway"; }
  if ($mask)   { push @result,"Subnet Mask: $mask"; }
  return([0,@result]);

}

sub snmpcfg {

  my $t = shift;
  my $value = shift;
  my $uid = shift;
  my $pass = shift;
  my $mm = shift;

  if ($value !~ /^enable|disable$/i) {
    return([1,"Invalid argument '$value' (enable|disable)"]); 
  }
  # Query users on MM
  my @data = $t->cmd("users -T system:$mm");
  my ($user) = grep(/\d+\.\s+$uid/, @data);
  if (!$user) {
    return([1,"Cannot find user: '$uid' on MM"]);
  }
  $user =~ /^(\d+)./;
  my $id = $1;
  my $pp  = ($value =~ /^enable$/i) ? "des" : "none";
 
  my $cmd= "users -$id -ap sha -at write -ppw $pass -pp $pp -T system:$mm";
  @data = $t->cmd($cmd);

  if (grep(/OK/i,@data)) {
    return([0,"SNMP $value: OK"]);
  }
  return([1,@data]);
}


sub sshcfg {

  my $t = shift;
  my $value = shift;
  my $uid = shift;
  my $mm = shift;
  my $fname = ((xCAT::Utils::isAIX()) ? "/.ssh/":"/root/.ssh/")."id_rsa.pub";

  if ($value) {
    if ($value !~ /^enable|disable$/i) {
      return([1,"Invalid argument '$value' (enable|disable)"]);
    }
  }
  # Does MM support SSH
  my @data = $t->cmd("sshcfg -hk rsa -T system:$mm");

  if (grep(/Error: Command not recognized/,@data)) {
    return([1,"SSH supported on AMM with minimum firmware BPET32"]);
  }
  # Get firmware version on MM
  @data = $t->cmd("update -a -T system:$mm");
  my ($line) = grep(/Build ID:\s+\S+/, @data);

  # Minumum firmware version BPET32 required for SSH
  $line =~ /(\d+)/;
  if ($1 < 32) {
    return([1,"SSH supported on AMM with minimum firmware BPET32"]);
  }

  # Get SSH key on Management Node
  unless (open(RSAKEY,"<$fname")) {
    return([1,"Error opening '$fname'"]);
  }
  my ($sshkey)=<RSAKEY>;
  close(RSAKEY);

  if ($sshkey !~ /\s+(\S+\@\S+$)/) {
    return([1,"Cannot find userid\@host in '$fname'"]);
  }
  my $login = $1;

  # Query users on MM
  @data = $t->cmd("users -T system:$mm");
  my ($user) = grep(/\d+\.\s+$uid/, @data);
  if (!$user) {
    return([1,"Cannot find user: '$uid' on MM"]);
  }
  $user =~ /^(\d+)./;
  my $id = $1;

  # Determine is key already exists on MM
  @data = $t->cmd("users -$id -pk all -T system:$mm");

  # Query if enabled/disabled
  if (!$value) {
    my @ddata = $t->cmd("sshcfg -T system:$mm");

    if (my ($d) = grep(/^-cstatus\s+(\S+)$/,@ddata)) {
      if ($d=~ /\s(\S+)$/) {
        if ($1=~ /^disabled/i) {
          return([0,"SSH: disabled"]);
        }
      }
    }
    # Find login 
    foreach (split(/Key\s+/,join('',@data))) {
      if (/-cm\s+$login/) {
        return([0,"SSH: enabled"]);
      }
    }
    return([0,"SSH: disabled"]);
  }

  # Remove existing keys for this login
  foreach (split(/Key\s+/,join('',@data))) {
    if (/-cm\s+$login/) {
      /^(\d+)/;
      my $key = $1;
      @data = $t->cmd("users -$id -pk -$key -remove -T system:$mm");
    }
  }
  if ($value =~ /^disable$/i) {
    if (!grep(/^OK$/i, @data)) {
      return([1,"SSH Key not found on MM"]);
    }
    return([0,"disabled"]);
  }

  # Make sure SSH key is generated on MM
  @data = $t->cmd("sshcfg -hk rsa -T system:$mm");

  if (!grep(/ssh-rsa/,@data)) {
    @data = $t->cmd("sshcfg -hk gen -T system:$mm");
    if (!grep(/^OK$/i, @data)) {
      return([1,@data]);
    }
    # Wait for SSH key generation to complete
    my $timeout = time+240;

    while (1) {
      if (time >= $timeout) {
        return([1,"SSH key generation timeout"]);
      }
      sleep(15);
      @data = $t->cmd("sshcfg -hk rsa -T system:$mm");
      if (grep(/ssh-rsa/,@data)) {
        last;
      }
    }
  }
  # Transfer SSH key from Management Node to MM
  $sshkey =~ s/@/\@/;
  $t->cmd("users -$id -at set -T system:$mm");
  @data = $t->cmd("users -$id -pk -T system:$mm -add $sshkey");

  if ($data[0]=~/Error/i) {
    if ($data[0]=~/Error writing data for option -add/i) {
      return([1,"Maximum number of SSH keys reached for this chassis"]);
    }
    return([1,$data[0]]);
  }
  # Enable ssh on MM
  @data = $t->cmd("ports -sshe on -T system:$mm");
  return([0,"SSH $value: OK"]);
}

sub ntp {

  my $value = shift;
  my @result;

  my $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.8.1',0]);
  if ($data =~ /NOSUCHOBJECT/) {
    return([1,"NTP Not supported"]);
  }
  if ($value) {
    my ($ntp,$ip,$f,$v3) = split /,/,$value;

    if ($ntp) {
      if ($ntp !~ /^enable|disable$/i) { 
        return([1,"Invalid argument '$ntp' (enable|disable)"]);
      }
    }
    if ($v3) {
      if ($v3 !~ /^enable|disable$/i) {
        return([1,"Invalid argument '$v3' (enable|disable)"]);
      }
    }
    if (!$ntp and !$ip and !$f and !$v3) {
      return([1,"No changes specified"]);
    }
    if ($ntp) {
      my $d = ($ntp =~ /^enable$/i) ? 1 : 0;
      setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.8.1',0,$d,'INTEGER');
      push @result,"NTP: $ntp";
    }
    if ($ip) {
      setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.8.2',0,$ip,'OCTET');
      push @result,"NTP Server: $ip";
    }
    if ($f) {
      setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.8.3',0,$f,'INTEGER');
      push @result,"NTP Frequency: $f";
    }
    if ($v3) {
      my $d = ($v3 =~ /^enable$/i) ? 1 : 0;
      setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.8.7',0,$d,'INTEGER');
      push @result,"NTP v3: $v3";
    }
    return([0,@result]);
  }
  my $d = (!$data) ? "disabled" : "enabled";
  push @result,"NTP: $d";

  $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.8.2',0]);
  push @result,"NTP Server: $data";

  $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.8.3',0]);
  push @result,"NTP Frequency: $data (minutes)";

  $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.8.7',0]);
  $d = (!$data) ? "disabled" : "enabled";
  push @result,"NTP v3: $d";
  return([0,@result]);
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
  yield; #Try to avoid useless iterations as much as possible
  return $rc;
}


sub dompa {
  my $out = shift;
  $mpa = shift;
  my $mpahash = shift;
  my $command=shift;
  my %namedargs=@_;
  my @exargs=@{$namedargs{-args}};
  my $node;
  my $args = \@exargs;

  #Handle http commands on their own
  if ($command eq "getrvidparms") {
      my $user = $mpahash->{$mpa}->{username};
      my $pass = $mpahash->{$mpa}->{password};
      httplogin($mpa,$user,$pass);
      (my $target, my $authtoken) = get_kvm_params($mpa);
      #an http logoff would invalidate the KVM token, so we can't do it here
      #For the instant in time, banking on the http session timeout to cleanup for us
      #It may be possible to provide the session id to client so it can logoff when done, but
      #that would give full AMM access to the KVM client
      foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
          my $slot = $mpahash->{$mpa}->{nodes}->{$node};
          my @output = ();
          push(@output,"method:blade");
          push(@output,"server:$target");
          push(@output,"authtoken:$authtoken");
          push(@output,"slot:$slot");
          my %outh;
          $outh{node}->[0]->{name}=[$node];
          $outh{node}->[0]->{data}=[];
          foreach (@output) {
              (my $tag, my $text)=split /:/,$_,2;
              push (@{$outh{node}->[0]->{data}},{desc=>[$tag],contents=>[$text]});
              print $out freeze([\%outh]);
              print $out "\nENDOFFREEZE6sK4ci\n";
                yield;
              waitforack($out);
              %outh=();
              $outh{node}->[0]->{name}=[$node];
              $outh{node}->[0]->{data}=[];
          }

      }
      return;
  }
  # Handle telnet commands before SNMP
  if ($command eq "rspconfig") { 
    foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
      @cfgtext=();
      my $slot = $mpahash->{$mpa}->{nodes}->{$node};
      my $user = $mpahash->{$mpa}->{username};
      my $pass = $mpahash->{$mpa}->{password};
  
      my $result = telnetcmds($mpa,$user,$pass,$slot,@exargs);
      my $rc |= @$result[0];
      $args = @$result[1];

      foreach(@cfgtext) {
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
        yield;
        waitforack($out);
      }
    }
  }
  # Only telnet commands
  unless ( @$args ) {
    return;
  }

  $session = new SNMP::Session(
                    DestHost => $mpa,
                    Version => '3',
                    SecName => $mpahash->{$mpa}->{username},
                    AuthProto => 'SHA',
                    AuthPass => $mpahash->{$mpa}->{password},
                    PrivProto => 'DES',
                    SecLevel => 'authPriv',
                    UseNumeric => 1,
                    Retries => 4, # Give up sooner to make commands go smoother
                    Timeout=>1500000, #Beacon, for one, takes a bit over a second to return
                    PrivPass => $mpahash->{$mpa}->{password});
  if ($session->{ErrorStr}) {return 1,$session->{ErrorStr}; }
  unless ($session and keys %$session) {
     my %err=(node=>[]);
     foreach (keys %{$mpahash{$mpa}->{nodes}}) {
        push (@{$err{node}},{name=>[$_],error=>["Cannot communicate with $mpa"],errorcode=>[1]});
     }
     print $out freeze([\%err]);
     print $out "\nENDOFFREEZE6sK4ci\n";
     yield;
     waitforack($out);
     return 1,"General error establishing SNMP communication";
  }
  my $tmp = $session->get([$mmprimoid.".1"]);
  if ($session->{ErrorStr}) { print $session->{ErrorStr}; }
  $activemm = ($tmp ? 1 : 2);
  my @outhashes;
  if ($command eq "reventlog" and isallchassis) {
#Add a dummy node for eventlog to get non-blade events
    $mpahash{$mpa}->{nodes}->{$mpa}=-1;
  }

  #get new node status
  my %nodestat=();
  my $check=0;
  my $nsh={};

  if ($command eq 'rpower') {
    if (($args->[0] ne 'stat') && ($args->[0] ne 'status')) { 
      $check=1; 
      my @allnodes=keys %{$mpahash->{$mpa}->{nodes}};

      #get the current nodeset stat
      if (@allnodes>0) {
        my ($ret, $msg)=xCAT::Utils->getNodesetStates(\@allnodes, $nsh);
        if ($ret)  { xCAT::MsgUtils->message('S', "Cannot update node status: $msg\n"); }
      }
    }
  }

  foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
    $curn = $node;
    my ($rc,@output) = bladecmd($mpa,$node,$mpahash->{$mpa}->{nodes}->{$node},$mpahash->{$mpa}->{username},$mpahash->{$mpa}->{password},$command,@$args); 

    #print "output=@output\n";
    my $no_op=0;
    if ($rc) { $no_op=1; }
    elsif (@output>0) { 
      if ($output[0] =~ /$status_noop/) {
	$no_op=1;
        $output[0] =~ s/ $status_noop//; #remove the simbols that meant for use by node statu
      }
    }
    #print "output=@output\n";

    #update the node status
    if (($check) && (!$no_op)) {
      my $stattmp=$output[0];
      if ($stattmp) {
        my @atmp=split(' ', $stattmp); 
        my $newstat=$atmp[$#atmp];
        if (($newstat eq "on") || ($newstat eq "reset"))  {
          my $currstate=$nsh->{$node};
          $nodestat{$node}=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($currstate, "rpower");
        } else { $nodestat{$node}=$::STATUS_POWERING_OFF;}
      }
    }

    foreach(@output) {
      my %output;
      
      if ( $command eq "rscan" ) { 
        $output{errorcode}=$rc;
        $output{data} = [$_];
      }
      else {
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
      }
      print $out freeze([\%output]);
      print $out "\nENDOFFREEZE6sK4ci\n";
      yield;
      waitforack($out);
    }
    yield;
  }

  #update the node status to the nodelist.status table
  if ($check) {
    my %node_status=();

    #foreach (keys %nodestat) { print "node=$_,status=" . $nodestat{$_} ."\n"; } #Ling:remove

    foreach my $node (keys %nodestat) {
      my $stat=$nodestat{$node};
      if ($stat eq "no-op") { next; }
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
  #my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
  #print $out $msgtoparent; #$node.": $_\n";
}
    
1;















