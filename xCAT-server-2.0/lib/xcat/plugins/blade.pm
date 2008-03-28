#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::blade;
#use Net::SNMP qw(:snmp INTEGER);
use xCAT::Table;
use Thread qw(yield);
use xCAT::Utils;
use IO::Socket;
use SNMP;
use strict;

use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use IO::Select;
use IO::Handle;
use Time::HiRes qw(gettimeofday sleep);

sub handled_commands {
  return {
    findme => 'blade',
    getmacs => 'nodehm:getmacs,mgt',
    rscan => 'nodehm:mgt',
    rpower => 'nodehm:power,mgt',
    rvitals => 'nodehm:vitals,mgt',
    rinv => 'nodehm:inv,mgt',
    rbeacon => 'nodehm:beacon,mgt',
    rspreset => 'nodehm:mgt',
    rspconfig => 'nodehm:mgt',
    rbootseq => 'nodehm:bootseq,mgt',
    reventlog => 'nodehm:eventlog,mgt',
    switchblade => 'nodehm:mgt',
  };
}
my %usage = (
    "rpower" => "Usage: rpower <noderange> [--nodeps][on|off|reset|stat|boot]",
    "rbeacon" => "Usage: rbeacon <noderange> [on|off|stat]",
    "rvitals" => "Usage: rvitals <noderange> [all|temp|voltage|fanspeed|power|leds]",
    "reventlog" => "Usage: reventlog <noderange> [all|clear|<number of entries to retrieve>]",
    "rinv" => "Usage: rinv <noderange> [all|model|serial|vpd|mprom|deviceid|uuid]",
    "rbootseq" => "Usage: rbootseq <noderange> [hd0|hd1|hd2|hd3|net|iscsi|usbflash|floppy|none],...",
    "rscan" => "Usage: rscan <noderange> [-w][-x|-z]"
);
my %macmap; #Store responses from rinv for discovery
my $macmaptimestamp; #reflect freshness of cache
my $mmprimoid = '1.3.6.1.4.1.2.3.51.2.22.5.1.1.4';#mmPrimary
my $beaconoid = '1.3.6.1.4.1.2.3.51.2.2.8.2.1.1.11'; #ledBladeIdentity
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

sub fillresps {
  my $response = shift;
  my $mac = $response->{node}->[0]->{data}->[0]->{contents}->[0];
  my $node = $response->{node}->[0]->{name}->[0];
  $mac = uc($mac); #Make sure it is uppercase, the MM people seem to change their mind on this..
  $macmap{$mac} = $node;
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
  } while ($varbind->[31] and $varbind->[31]->[2] != 'NOSUCHINSTANCE' and ($current < 600));

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
  my $data;
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
   





my @cfgtext;
sub mpaconfig {
   #OIDs of interest:
   #1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.4 snmpCommunityEntryCommunityIpAddress2
   #snmpCommunityEntryCommunityName 1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.2
   #remoteAlerts 1.3.6.1.4.1.2.3.51.2.4.2
   #remoteAlertIdEntryTextDescription 1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.4
   #remoteAlertIdEntryStatus 1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.2 (0 invalid, 2 enable)
   my $parameter;
   my $value;
   my $assignment;
   my $returncode=0;
   if ($didchassis) { return 0, @cfgtext } #"Chassis already configured for this command" }
   @cfgtext=();
   foreach $parameter (@_) {
      $assignment = 0;
      $value = undef;
      if ($parameter =~ /=/) {
         $assignment = 1;
         ($parameter,$value) = split /=/,$parameter,2;
      }
      if ($parameter eq "snmpdest") {
         $parameter = "snmpdest1";
      }
      if ($parameter =~ /snmpdest(\d+)/) {
         if ($1 > 3) {
            $returncode &= 1;
            push(@cfgtext,"Only up to three snmp destinations may be defined");
            next;
         }
         my $dstindex = $1;
         if ($assignment) {
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.".(2+$dstindex).".1",1,$value,'OCTET');
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
            if ($value =~ /^enable/i or $value =~ /^on$/i) {
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.4',12,'xCAT configured SNMP','OCTET'); #Set a description so the MM doesn't flip out
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.5',12,4); #Set Dest12 to SNMP
               setoid('1.3.6.1.4.1.2.3.51.2.4.1.3.1.1.2',12,2); #enable dest12
               setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.1.3',0,0); #Enable SNMP traps
               enabledefaultalerts();
            } elsif ($value =~ /^disable/i or $value =~ /^off$/i) {
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
   $didchassis=1;
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


sub vitals {
   my @output;
   my $tmp;
   my @vitems;
   foreach (@_) {
     if ($_ eq 'all') {
 push @vitems,qw(temp,wattage,voltage,fan,summary);
     } else {
 push @vitems,split( /,/,$_);
     }
   }
   my $tmp;
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
       
        
   if (grep /fan/,@vitems or grep /blower/,@vitems) {
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.3.1.0']);
     push @output,"Blower 1:  $tmp";
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.3.2.0']);
     push @output,"Blower 2:  $tmp";
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.3.3.0']);
     if ($tmp and $tmp !~ /NOSUCHINSTANCE/) { push @output,"Blower 3:  $tmp"; }
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.3.4.0']);
     if ($tmp and $tmp !~ /NOSUCHINSTANCE/) { push @output,"Blower 4:  $tmp"; }
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.6.1.1.5.1']);
     push @output,"Fan Pack 1:  $tmp";
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.6.1.1.5.2']);
     push @output,"Fan Pack 2:  $tmp";
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.6.1.1.5.3']);
     push @output,"Fan Pack 3:  $tmp";
     $tmp=$session->get(['1.3.6.1.4.1.2.3.51.2.2.6.1.1.5.4']);
     push @output,"Fan Pack 4:  $tmp";
   }
   if (grep /volt/,@vitems) {
 for my $idx (15..40) {
    $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.22.1.5.5.1.$idx.$slot"]);
           unless ((not $tmp) or $tmp =~ /Not Readable/) {
             $tmp =~ s/ = /:/;
             push @output,"$tmp";
           }
 }
    }

   if (grep /temp/,@vitems) {
      $tmp=$session->get(["1.3.6.1.4.1.2.3.51.2.2.1.5.1.0"]);
      push (@output,"Ambient: $tmp");
      for my $idx (6..20) {
 if ($idx eq 11) {
  next;
 }
        $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.22.1.5.3.1.$idx.$slot"]);
        unless ($tmp =~ /Not Readable/) {
          $tmp =~ s/ = /:/;
          push @output,"$tmp";
        }
      }
   }
   if (grep /summary/,@vitems) {
      $tmp="Status: ".$session->get(['1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.3.'.$slot]);
      $tmp.=", ".$session->get(['1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.4.'.$slot]);
      push @output,"$tmp";
   }
   return(0,@output);
}
 
sub rscan {

    my $subcommand = shift;
    my @values;
    my $result;
    my %opt;

    @ARGV = $subcommand;
    use Getopt::Long;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version w x z) )){
        return( usage() );
    }
    if ( exists($opt{x}) and exists($opt{z}) ) {
        return (1,"-x and -z are mutually exclusive" );
    } 
    my $mmname = $session->get([$mmoname,0]);
    if ($session->{ErrorStr}) {
        return (1,$session->{ErrorStr});
    }
    my $mmtype = $session->get([$mmotype,0]);
    if ($session->{ErrorStr}) {
        return (1,$session->{ErrorStr});
    }
    my $mmmodel = $session->get([$mmomodel,0]);
    if ($session->{ErrorStr}) {
        return (1,$session->{ErrorStr});
    }
    my $mmserial = $session->get([$mmoserial,0]);
    if ($session->{ErrorStr}) {
        return (1,$session->{ErrorStr});
    }
    push @values, join( ",", "mm", $mmname, 0, "$mmtype-$mmmodel", $mmserial, $mpa);
    my $max = length( $mmname );

    foreach (1..14) {
        my $tmp = $session->get([$bladexistsoid.".$_"]);
        if ( $tmp eq 1 ) {
            my $type = $session->get([$blademtmoid,$_]);
            if ($session->{ErrorStr}) {
                return (1,$session->{ErrorStr});
            }
            $type =~ s/Not available/null/;

            my $model = $session->get([$bladeomodel,$_]);
            if ($session->{ErrorStr}) {
                return (1,$session->{ErrorStr});
            }
            $model =~ s/Not available/null/;

            my $serial = $session->get([$bladeserialoid,$_]);
            if ($session->{ErrorStr}) {
                return (1,$session->{ErrorStr});
            }
            $serial =~ s/Not available/null/;

            my $name = $session->get([$bladeoname,$_]);
            if ($session->{ErrorStr}) {
                return (1,$session->{ErrorStr});
            }
            push @values, join( ",", "blade", $name, $_, "$type-$model", $serial, "");
            my $length  = length( $name );
            $max = ($length > $max) ? $length : $max;
        }
    }
    my $format = sprintf "%%-%ds", ($max + 2 );
    $rscan_header[1][1] = $format;

    if ( exists( $opt{x} )) {
       $result = rscan_xml( \@values ); 
    } 
    elsif ( exists( $opt{z} )) {
       $result = rscan_stanza( \@values ); 
    } 
    else {
        foreach ( @rscan_header ) {
            $result .= sprintf @$_[1], @$_[0];
        }
        foreach ( @values ) {
            my @data = split /,/;
            my $i = 0;

            foreach ( @rscan_header ) {
                $result .= sprintf @$_[1], $data[$i++];
            }
        }
    }
    if ( !exists( $opt{w} )) {
        return(0,$result);
    }
    my @tabs = qw(mp nodehm nodelist);
    my %db   = ();

    foreach ( @tabs ) {
        $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
        if ( !$db{$_} ) {
            return( 1,"Error opening '$_'" );
        }
    }
    foreach ( @values ) {
        my @data = split /,/;
        my $name = $data[1];
  
        my ($k1,$u1);
        $k1->{node} = $name;
        $u1->{mpa}  = $mpa;
        $u1->{id}   = $data[2];
        $db{mp}->setAttribs( $k1, $u1 );
        $db{mp}{commit} = 1;

        my ($k2,$u2);
        $k2->{node} = $name;
        $u2->{mgt}  = "blade";
        $db{nodehm}->setAttribs( $k2, $u2 );
        $db{nodehm}{commit} = 1;

        my ($k3,$u3);
        $k3->{node}   = $name;
        $u3->{groups} = "blade,all";
        $db{nodelist}->setAttribs( $k3, $u3 );
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

    my $values = shift;
    my $xml;

    foreach ( @$values ) {
      my @data = split /,/;
      my $i = 0;

      my $href = {
          Node => { }
      };
      foreach ( @rscan_header ) {
        $href->{Node}->{@$_[0]} = $data[$i++];
      }
      $xml.= XMLout($href,
                     NoAttr   => 1,
                     KeyAttr  => [],
                     RootName => undef );
    }
    return( $xml );
}
sub rscan_stanza {

    my $values = shift;
    my $result;

    foreach ( @$values ) {
      my @data = split /,/;
      my $i = 0;
      $result .= "$data[1]:\n\tobjtype=node\n";

      foreach ( @rscan_header ) {
        if ( @$_[0] ne "name" ) {
          $result .= "\t@$_[0]=$data[$i++]\n";      
        }
        $i++;
      }
    }
    return( $result );
}
 
sub getmacs {
   (my $code,my $macs)=inv('mac');
   if ($code==0) {
      my @macs = split /\n/,$macs;
      (my $macd,my $mac) = split (/:/,$macs[0],2);
      $mac =~ s/\s+//g;
      if ($macd =~ /mac address 1/i) {
         my $mactab = xCAT::Table->new('mac',-create=>1);
         $mactab->setNodeAttribs($curn,{mac=>$mac});
         $mactab->close;
         return 0,":mac.mac set to $mac";
      } else {
         return 1,"Unable to retrieve MAC address from Management Module";
      }
   } else {
      return $code,$macs;
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
  unless ($slot > 0) {
     if ($subcommand eq "reset" or $subcommand eq "boot") {
        $data = $session->set(new SNMP::Varbind([".1.3.6.1.4.1.2.3.51.2.7.4",0,1,'INTEGER']));
        unless ($data) { return (1,$session->{ErrorStr}); }
        return (0,"reset");
     } else {
        return (1,"$subcommand unsupported on the management module");
     }
  }
  if ($subcommand eq "stat" or $subcommand eq "boot") {
    $data = $session->get([$powerstatoid.".".$slot]);
    if ($data == 1) {
      $stat = "on";
    } elsif ( $data == 0) {
      $stat = "off";
    } else {
      $stat= "error";
    }
  } elsif ($subcommand eq "off") {
    $data = $session->set(new SNMP::Varbind([".".$powerchangeoid,$slot,0,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    $stat = "off";
  } 
  if ($subcommand eq "on" or ($subcommand eq "boot" and $stat eq "off")) {
    $data = $session->set(new SNMP::Varbind([".".$powerchangeoid,$slot,1,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    $stat .= " " . ($data ? "on" : "off");
  } elsif ($subcommand eq "reset" or ($subcommand eq "boot" and $stat eq "on")) {
    $data = $session->set(new SNMP::Varbind([".".$powerresetoid,$slot ,1,'INTEGER']));
    unless ($data) { return (1,$session->{ErrorStr}); }
    $stat = "on reset";
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
  $slot = shift;
  #my $user = shift;
  #my $pass = shift;
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
    return mpaconfig(@args);
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
    return rscan(@args);
  }
  
  return (1,"$command not a supported command by blade method");
}

sub handle_depend {
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my $dep = shift;
  my %node = ();
    
  # send all dependencies (along w/ those dependent on nothing)
  $request->{node} = [keys %$dep];
  process_request($request,$callback,$doreq,1);
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
      %mpahash = ();
      $request->{node} = \@noderange;
      process_request($request,$callback,$doreq,1);
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
  my %dp    = ();
  my %no_dp = ();

  if (!defined($depstab)) {
    return(\%dp);
  }
  foreach my $node (@$noderange) {
    my $delay = 0;
    my $dep;
    my $cmd;

    my $ent=$depstab->getNodeAttribs($node,[qw(nodedep msdelay cmd)]);
    if (defined($ent->{nodedep})) { $dep=$ent->{nodedep}; }
    if (defined($ent->{cmd}))     { $cmd=$ent->{cmd}; }
    if (defined($ent->{msdelay})) { $delay=$ent->{msdelay}; }

    if (!defined($dep)) {
      $no_dp{$node} = 1;
    }
    elsif ( grep(/^@$exargs[0]$/, split /,/, $cmd )) {
      foreach (split /,/,$dep ) {
        $dp{$_}{$node} = $delay;
      }
    }
    # if there are dependencies, add any non-dependent nodes
    if (scalar(%dp)) {
      foreach (keys %no_dp) {
        if (!exists( $dp{$_} )) {
          $dp{$_}{$_} = -1;
        }
      }
    }
  }
  return( \%dp );
}


sub process_request { 
  my $request = shift;
  my $callback = shift;
  my $doreq = shift;
  my $level = shift;
  my $noderange = $request->{node};
  my $command = $request->{command}->[0];
  my @exargs;

  unless ($noderange or $command eq "findme") {
      if ($usage{$command}) {
          $callback->({data=>$usage{$command}});
          $request = {};
      }
      return;
  }
  if (ref($request->{arg})) {
    @exargs = @{$request->{arg}};
  } else {
    @exargs = ($request->{arg});
  }

  if ($command eq "rpower" and grep(/^on|off|boot|reset|cycle$/, @exargs)) {
    if (!grep /^--nodeps$/, @exargs) {
      # handles 1 level of dependencies only
      if (!defined($level)) {
        my $dep = build_depend($noderange,\@exargs);
        if (scalar(%$dep)) {
          handle_depend( $request, $callback, $doreq, $dep );
          return 0;
        } 
      }
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
      process_request(\%invreq,\&fillresps);
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
  $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
  my $inputs = new IO::Select;;
  foreach (@$noderange) {
    my $node=$_;
    my $user=$bladeuser;
    my $pass=$bladepass;
    my $nodeid;
    my $mpa;
    my $ent;
    if (defined($mptab)) {
      $ent=$mptab->getNodeAttribs($node,['mpa','id']);
      if (defined($ent->{mpa})) { $mpa=$ent->{mpa}; }
      if (defined($ent->{id})) { $nodeid = $ent->{id}; }
    }
    if (defined($mpatab)) {
      ($ent)=$mpatab->getAttribs({'mpa'=>$mpa},'username','password');
      if (defined($ent->{password})) { $pass = $ent->{password}; }
      if (defined($ent->{username})) { $user = $ent->{username}; }
    }
    $mpahash{$mpa}->{nodes}->{$node}=$nodeid;
    $mpahash{$mpa}->{username} = $user;
    $mpahash{$mpa}->{password} = $pass;
  }
  my $sub_fds = new IO::Select;
  foreach $mpa (sort (keys %mpahash)) {
    while ($children > $blademaxp) { sleep (0.1); }
    $children++;
    my $cfd;
    my $pfd;
    pipe $cfd, $pfd;
    $cfd->autoflush(1);
    $pfd->autoflush(1);
    my $cpid = xCAT::Utils->xfork;
    unless (defined($cpid)) { die "Fork error"; }
    unless ($cpid) {
      close($cfd);
      dompa($pfd,$mpa,\%mpahash,$command,-args=>\@exargs);
      exit(0);
    }
    close ($pfd);
    $sub_fds->add($cfd);
  }
  while ($children > 0) {
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
  $session = new SNMP::Session(
                    DestHost => $mpa,
                    Version => '3',
                    SecName => $mpahash->{$mpa}->{username},
                    AuthProto => 'SHA',
                    AuthPass => $mpahash->{$mpa}->{password},
                    PrivProto => 'DES',
                    SecLevel => 'authPriv',
                    UseNumeric => 1,
                    Retries => 2, # Give up sooner to make commands go smoother
                    Timeout=>1300000, #Beacon, for one, takes a bit over a second to return
                    PrivPass => $mpahash->{$mpa}->{password});
  if ($session->{ErrorStr}) { return 1,$session->{ErrorStr}; }
  unless ($session and keys %$session) {
     my %err=(node=>[]);
     foreach (keys %{$mpahash{$mpa}->{nodes}}) {
        push (@{$err{node}},{name=>[$_],error=>["Cannot communicate with $mpa"],errorcode=>[1]});
     }
     print $out freeze([\%err]);
     print $out "\nENDOFFREEZE6sK4ci\n";
     yield;
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
  foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
    $curn = $node;
    my ($rc,@output) = bladecmd($mpa,$mpahash->{$mpa}->{nodes}->{$node},$command,@exargs);
    my @output_hashes;
    foreach(@output) {
      my %output;
      
      if ( $command eq "rscan" ) { 
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
        $output{node}->[0]->{name}->[0]=$node;
        $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
      }
      print $out freeze([\%output]);
      print $out "\nENDOFFREEZE6sK4ci\n";
    }
    yield;
  }
  #my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
  #print $out $msgtoparent; #$node.": $_\n";
}
    
1;




