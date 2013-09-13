#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::blade;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';

  if (defined $ENV{ENABLE_TRACE_CODE}) {
    use xCAT::Enabletrace qw(loadtrace filter);
    loadtrace();
  }

}
use lib "$::XCATROOT/lib/perl";
#use Net::SNMP qw(:snmp INTEGER);
use xCAT::Table;
use Thread qw(yield);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
use xCAT::ServiceNodeUtils;
use xCAT::IMMUtils;
use xCAT::Usage;
use IO::Socket;
use IO::Pty; #needed for ssh password login
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use strict;
use LWP;
require xCAT::data::ibmhwtypes;

#use warnings;
my %mm_comm_pids;

#a 'browser' for http actions
my $browser;
use XML::Simple;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
#use Data::Dumper;
use POSIX "WNOHANG";
use Storable qw(freeze thaw store_fd fd_retrieve);
use IO::Select;
use IO::Handle;
use Time::HiRes qw(gettimeofday sleep);
use xCAT::DBobjUtils;
use Getopt::Long;
use xCAT::SvrUtils;
use xCAT::FSPUtils;
my $indiscover=0;
my $CALLBACK = undef;
my $verbose_cmd = undef;
my $vitals_info = undef; #used by 'rvitals <node> all' to show lcds info for Firebird blade
my %x222_info = (); #used to collect x222 infomations
my $has_x222 = undef;

sub handled_commands {
  return {
    findme => 'blade',
    getmacs => 'nodehm:getmac,mgt',
    rscan => 'nodehm:mgt',
    rpower => 'nodehm:power,mgt',
    getbladecons => 'blade',
    getrvidparms => 'nodehm:mgt',
    rvitals => 'nodehm:mgt=blade|fsp',
    rinv => 'nodehm:mgt',
    rbeacon => 'nodehm:mgt=blade|fsp',
    rspreset => 'nodehm:mgt',
    rspconfig => 'nodehm:mgt=blade|fsp|ipmi', # Get into blade.pm for rspconfig if mgt equals blade or fsp
    rbootseq => 'nodehm:mgt',
    reventlog => 'nodehm:mgt=blade|fsp',
    switchblade => 'nodehm:mgt',
    renergy => 'nodehm:mgt=blade|fsp|ipmi',
    lsflexnode => 'blade',
    mkflexnode => 'blade',
    rmflexnode => 'blade',
  };
}

my %macmap; #Store responses from rinv for discovery
my %uuidmap;
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
my $bladeuuidoid = '1.3.6.1.4.1.2.3.51.2.2.21.4.1.1.8'; #bladeHardwareVpdUuid
my $componentuuidoid = '.1.3.6.1.4.1.2.3.51.2.2.23.1.1.1.13'; #componentInventoryUUID
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
my $chassisfanbase = '.1.3.6.1.4.1.2.3.51.2.2.3.50.1.';
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
my $mmoname = #chassisName
  { 'mm' => '1.3.6.1.4.1.2.3.51.2.22.4.3',
    'cmm' => '.1.3.6.1.4.1.2.3.51.2.4.5.1'};
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
my @sidecardoids = (
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.164', #bladeSideCardMACAddress1Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.165', #bladeSideCardMACAddress2Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.166', #bladeSideCardMACAddress3Vpd
  '1.3.6.1.4.1.2.3.51.2.2.21.4.2.1.167', #bladeSideCardMACAddress4Vpd
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
  11 => 'usbflash',
  12 => 'hypervisor',
  13 => 'uefi',
  14 => 'legacy'
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
  'hypervisor' => 12,
  'flash' => 11,
  'uefi' => 13,
  'legacy' => 14,
  'usb' => 11
);

my @rscan_attribs = qw(nodetype name id mtm serial mpa hcp groups mgt cons hwtype);
my @rscan_header = (
  ["type",          "%-8s" ],
  ["name",          "" ],
  ["id",            "%-8s" ],
  ["type-model",    "%-12s" ],
  ["serial-number", "%-15s" ],
  ["mpa",           "" ],
  ["address",       "%s\n" ]);

my $session;
my $slot;
my @moreslots;
my $didchassis = 0;
my @eventlog_array = ();
my $activemm;
my %mpahash;
my $currnode;
my $mpa;
my $mptype; # The type of mp node. For cmm, it's 'cmm'
my $mpatype; # The type of node's mpa. Used for SNMP OIDs.
my $mpauser;
my $mpapass;
my $allinchassis=0;
my $curn;
my @cfgtext;
my $status_noop="XXXno-opXXX";

my %telnetrscan; # Store the rscan result by telnet command line

sub fillresps {
  my $response = shift;
  my $mac = $response->{node}->[0]->{data}->[0]->{contents}->[0];
  my $node = $response->{node}->[0]->{name}->[0];
  unless ($mac) { return; } #The event that a bay is empty should not confuse 
#xcat into having an odd mapping
  $mac = uc($mac); #Make sure it is uppercase, the MM people seem to change their mind on this..
  if ($mac =~ /........-....-....-....-............/) { #a uuid
       $uuidmap{$mac} = $node;
  } elsif ($mac =~ /->/) { #The new and 'improved' syntax for pBlades

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
    if ($select->can_read(60)) { # Continue after 60 seconds, even if not acked...
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
  @ARGV=@_;
  my $force;
  #GetOptions(
  #	"f" => \$force,
  #	);
  my $cmd = undef;
  my $order = undef;
  my $arg = shift @ARGV;
  while ($arg) {
      if ($arg eq "all" or $arg eq "clear" or $arg =~/^\d+$/) {
          if (defined($cmd)) {
              return(1, "reventlog $cmd $arg invalid");
          }
          $cmd = $arg;
      } elsif ($arg =~ /^-s$/) {
          $order = 1;
      } elsif ($arg =~ /^-f$/) {
          $force = 1;
      } else {
          return(1, "unsupported command reventlog $arg");
      }
      $arg = shift @ARGV;
  }

  my $data;
  my @output;
  my $oid = $eventlogoid;
  unless ($cmd) {
   $cmd='all';
  }
  if (defined($force) and $cmd ne "clear") {
      return(1, "option \"-f\" can only work with \"clear\"");
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
        #$matchstring=sprintf("BLADE_%02d",$slot);
        $matchstring=sprintf("(NODE_%02d|BLADE_%02d)",$slot,$slot);
      } else {
        #$matchstring="^(?!BLADE).*";
        $matchstring="^(?!(NODE|BLADE)).*";
      }
      if ($source =~ m/$matchstring$/i) { #MM guys changed their minds on capitalization
        if (defined($order)) {
            $numentries++;
            push @output, "$sev:$date $time $text";
        } else {
            unshift @output,"$sev:$date $time $text"; #unshift to get it in a sane order
            if ($#output >= $requestednumber) {
                pop @output;
            }
        }
      } else {
          foreach (@moreslots) {
            #$matchstring=sprintf("BLADE_%02d",$_);
            $matchstring=sprintf("(NODE_%02d|BLADE_%02d",$_,$_);
            if ($source =~ m/$matchstring$/i) { #MM guys changed their minds on capitalization
                if (defined($order)) {
                    $numentries++;
                    push @output, "$sev:$date $time $text";
                } else {
                    unshift @output,"$sev:$date $time $text"; #unshift to get it in a sane order
                    if ($#output >= $requestednumber) {
                        pop @output;
                    }
                }
            }
          }
      }
      if ($numentries >= $requestednumber) {
        last;
      }
    }
    return (0,@output);
  }
  if ($cmd eq "clear") {
    unless ($force or isallchassis) {
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
   my @morenodeids;
   if ($nodeid =~ /-(.*)/) {
       my $highid = $1;
       $nodeid =~ s/-.*//;
       @morenodeids = ($nodeid+1..$highid);
   }
   if (scalar @moreslots) {
       push @morenodeids,@moreslots;
   }


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
      elsif ($parameter =~ /^network$/) {
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
      elsif ($parameter eq "textid") {
         $textid = 1;
         if ($assignment) {
           my $txtid = ($value =~ /^\*/) ? $node : $value;
           setoid("1.3.6.1.4.1.2.3.51.2.22.1.7.1.1.5",$nodeid,$txtid,'OCTET');
           my $extrabay=2;
           foreach(@morenodeids) {
            setoid("1.3.6.1.4.1.2.3.51.2.22.1.7.1.1.5",$_,$txtid.", slot $extrabay",'OCTET');
            $extrabay+=1;
           }
         } else {
         my $data;
         if ($slot > 0) {
           $data = $session->get([$bladeoname,$nodeid]);
         }
         else {
           $data = $session->get([$mmoname->{$mptype},0]);
         }
         push @cfgtext,"textid: $data";
         foreach(@morenodeids) {
            $data = $session->get([$bladeoname,$_]);
            push @cfgtext,"textid: $data";
           }
         }
      }
      elsif ($parameter =~ /^snmpcfg$/i) {
         my $data = $session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.1.6',0]);
         if ($data) {
            push @cfgtext,"SNMP: enabled";
         }
         else {
            push @cfgtext,"SNMP: disabled";
         }
         next;
      }
      elsif ($parameter =~ /^snmpdest/ or $parameter eq "snmpdest") {
         if ($parameter eq "snmpdest") {
            $parameter = "snmpdest1";
         }
         $parameter =~ /snmpdest(\d+)/;
         if ($1 > 3) {
            $returncode |= 1;
            push(@cfgtext,"Only up to three snmp destinations may be defined");
            next;
         }
         my $dstindex = $1;
         if ($assignment) {
            my $restorev1agent = 0;
            if (($session->get(['1.3.6.1.4.1.2.3.51.2.4.9.3.1.5',0])) == 1) { #per the BLADE MIB, this *must* be zero in order to change SNMP IPs
               $restorev1agent=1;
               setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.1.5',0,0,'INTEGER');
            }
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.".(2+$dstindex),1,$value,'OCTET');
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.6.1",1,1,'INTEGER'); #access type: read-traps, don't give full write access to the community
            if ($restorev1agent) { #If we had to transiently disable the v1 agent, put it back the way it was
               setoid('1.3.6.1.4.1.2.3.51.2.4.9.3.1.5',0,1,'INTEGER');
            }

         }
         my $data = $session->get(["1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.".(2+$dstindex).".1"]);
         push @cfgtext,"SP SNMP Destination $1: $data";
         next;
      }
      elsif ($parameter =~ /^community/i) {
         if ($assignment) {
            setoid("1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.2.1",0,$value,'OCTET');
         }
         my $data = $session->get(["1.3.6.1.4.1.2.3.51.2.4.9.3.1.4.1.1.2.1"]);
         push @cfgtext,"SP SNMP Community: $data";
         next;
      }
      elsif ($parameter =~ /^alert/i) {
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
         } elsif (defined $data and $data == 0) {
            push @cfgtext,"SP Alerting: disabled";
            next;
         } else { 
            $returncode |= 1;
            push @cfgtext,"Unable to get alert configuration (is SNMP enabled?)";
            next;
         }
      } elsif ($parameter =~ /^solcfg/i) {
         my $data = $session->get(['.1.3.6.1.4.1.2.3.51.2.4.10.1.1',0]);
         if ($data) {
            push @cfgtext,"solcfg: enabled on mm";
         } else {
            push @cfgtext,"solcfg: disabled on mm";
         }
      } else {
         $returncode |= 1;
         push(@cfgtext,"Unrecognized argument $parameter");
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

sub cleantemp {
#Taken a bladecenter string, reformat/convert to be consistent with ipmi presentation choices
    my $temp = shift;
    my $tnum;
    $temp =~ /(\d+\.\d+) Centigrade/;
    $tnum=$1;
    $temp =~ s/ = /:/;
    $temp =~ s/\+(\d+)/$1/; #remove + sign from temperature readings if put in
    $temp =~ s/Centigrade/C/; #remove controversial use of Centigrade
    if ($tnum) {
         $temp .= " (".sprintf("%.2f",$tnum*(9/5)+32)." F)";
    }
    return $temp;
}

sub collect_health_summary { #extracts the health summary table
    my %summarymap;
    my %idmap;
    my $varbind = new SNMP::VarList(
      ['.1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.2','1'], 
      );
    $session->get($varbind);
    while ($varbind->[0]->[0] eq '.1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.2') {
        $idmap{$varbind->[0]->[1]} = $varbind->[0]->[2];
        $session->getnext($varbind);
    }
    my $numentries = scalar (keys %idmap);
    my @bindlist;
    foreach (1..$numentries) {
        push @bindlist,['.1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.3',$_];
    }
    my $sevbind =  new SNMP::VarList(@bindlist);
    $session->get($sevbind);
    my $id;
    my $bladeid;
    foreach (@$sevbind) {
        $id = $_->[1];
        $bladeid = $idmap{$id};
        $summarymap{$bladeid}->{$id}->{severity} = $_->[2];
    }
    @bindlist=();
    foreach (1..$numentries) {
        push @bindlist,['.1.3.6.1.4.1.2.3.51.2.22.1.5.2.1.4',$_];
    }
    my $detailbind = new SNMP::VarList(@bindlist);
    $session->get($detailbind);
    foreach (@$detailbind) {
        $id = $_->[1];
        $bladeid = $idmap{$id};
        $summarymap{$bladeid}->{$id}->{detail} = $_->[2];
    }
    return \%summarymap;
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
     verbose_message("slotid:$slot, options:@vitems.");
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
     verbose_message("for chassis, options:@vitems.");
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
       my $tmp_oid = "1.3.6.1.4.1.2.3.51.2.2.10.2.1.1.7.";
       if ($mpatype eq 'cmm') {
           $tmp_oid .= ($slot+24);
       } else {
           if ($slot < 8) {
               $tmp_oid .= ($slot+16);
               #$tmp = $session->get(["1.3.6.1.4.1.2.3.51.2.2.10.2.1.1.7.".($slot+16)]);
           } else {
               $tmp_oid = "1.3.6.1.4.1.2.3.51.2.2.10.3.1.1.7.".($slot+9);
               #$tmp = $session->get(["1.3.6.1.4.1.2.3.51.2.2.10.3.1.1.7.".($slot+9)]);
           }
       }
       $tmp = $session->get([$tmp_oid]);
       unless ($tmp =~ /Not Readable/) {
         if ($tmp =~ /(\d+)W/) {
             $tmp = "$1 Watts (". int($tmp * 3.413+0.5)." BTUs/hr)";
         }
         $tmp =~ s/^/Power Usage:/;
         push @output,"$tmp";
       } else {
         verbose_message("OID:$tmp_oid, value:$tmp.");
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
              $tmp->[2] =~ s/ = /:/;
              push @output,$tmp->[2];
            } else {
              verbose_message("OID:$tmp->[0].$tmp->[1], value:$tmp->[2].");
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
      my $tnum;
      for my $tmp (@$bindobj) {
        if ($tmp and defined $tmp->[2] and $tmp->[2] !~ /Not Readable/ and $tmp->[2] ne "") {
            my $restype=$tmp->[0];
            $restype =~ s/^.*\.(\d*)$/$1/;
            if ($restype =~ /^([6789])$/) {
                $tmp->[2] = "CPU ".($1 - 5)." Temp: ".$tmp->[2]; 
            }
            push @output,cleantemp($tmp->[2]);
        } else {
            verbose_message("OID:$tmp->[0].$tmp->[1], value:$tmp->[2].");
        }
      }
      unless (defined $chassiswidevitals{ambient}) {
          $chassiswidevitals{ambient} = [];
          my @ambientbind=([".1.3.6.1.4.1.2.3.51.2.2.1.5.1","0"],
                           [".1.3.6.1.4.1.2.3.51.2.2.1.5.2","0"]);
          if ($mpatype eq 'cmm') {
              pop @ambientbind;
          }
          my $targ = new SNMP::VarList(@ambientbind);
          my $tempidx=1;
          $session->get($targ);
          for my $result (@$targ) {
              #if ($result->[2] eq "NOSUCHINSTANCE") { 
              if ($result->[2] =~ /NOSUCH/) { 
                  verbose_message("OID:$result->[0].$result->[1], value:$result->[2].");
                  next; 
              }
              push @{$chassiswidevitals{ambient}},"Ambient ".$tempidx++." :".cleantemp($result->[2]);
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
      unless ($chassiswidevitals{healthsummary}) {
          $chassiswidevitals{healthsummary} = collect_health_summary();
      }
      foreach (values %{$chassiswidevitals{healthsummary}->{$slot}}) {
          push @output,"Status: ".$_->{severity}.", ".$_->{detail};
      }
      foreach (@moreslots) {
          foreach (values %{$chassiswidevitals{healthsummary}->{$_}}) {
              push @output,"Status: ".$_->{severity}.", ".$_->{detail};
          }
      }
    }

    my %ledresults=();
    my $ledstring="";
    if (grep /led/,@vitems) {
 	$session = new SNMP::Session(
                   DestHost => $mpa,
                   Version => '3',
                   SecName => $mpauser,
                   AuthProto => 'SHA',
                   AuthPass => $mpapass,
                   PrivProto => 'DES',
                   SecLevel => 'authPriv',
                   UseNumeric => 1,
                   Retries => 1, # Give up sooner to make commands go smoother
                   Timeout=>300000000, #Beacon, for one, takes a bit over a second to return
                   PrivPass => $mpapass);
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


     if ((grep /volt/,@vitems) and ($mpatype ne 'cmm')) {
       my $voltbase = "1.3.6.1.4.1.2.3.51.2.2.2.1";
       my %voltlabels = ( 1=>"+5V", 2=>"+3.3V", 3=>"+12V", 5=>"-5V", 6=>"+2.5V", 8=>"+1.8V" );
       foreach my $idx ( keys %voltlabels ) {
        $tmp=$session->get(["$voltbase.$idx.0"]);
             unless ((not $tmp) or $tmp =~ /Not Readable/) {
               push @output,sprintf("Voltage %s: %s",$voltlabels{$idx},$tmp);
             }
             if ($tmp =~ /^NOSUCH/) {
                 verbose_message("OID:$voltbase.$idx.0, value:$tmp.");
             }
       }
     }

     if (grep /ammtemp/,@vitems) {
         $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.2.1.1.2.0"]);
         #push @output,sprintf("AMM temp: %s",$tmp) if $tmp !~ /NOSUCHINSTANCE/;
         push @output,sprintf("AMM temp: %s",$tmp) if $tmp !~ /^NOSUCH/;
         if ($tmp =~ /^NOSUCH/) {
            verbose_message("OID:.1.3.6.1.4.1.2.3.51.2.2.1.1.2.0, value:$tmp.");
         }
      }

     if (grep /ambient/,@vitems) {
       my %oids = ();
       if ($mpatype ne 'cmm') {
       %oids = (
        "Ambient 1",".1.3.6.1.4.1.2.3.51.2.2.1.5.1.0",
        "Ambient 2",".1.3.6.1.4.1.2.3.51.2.2.1.5.2",	
       ); 
       } else {
         %oids = ("Ambient 1",".1.3.6.1.4.1.2.3.51.2.2.1.5.1.0");
       }
       foreach my $oid ( keys %oids ) {
         $tmp=$session->get([$oids{$oid}]);
         #push @output,sprintf("%s: %s",$oid,$tmp) if $tmp !~ /NOSUCHINSTANCE/;
         push @output,sprintf("%s: %s",$oid,$tmp) if $tmp !~ /^NOSUCH/;
         if ($tmp =~ /^NOSUCH/) {
             verbose_message("OID:$oids{$oid}, value:$tmp.");
         } 
       }
      }

     if (grep /watt/,@vitems) {
         $tmp=$session->get([".1.3.6.1.4.1.2.3.51.2.2.10.5.1.2.0"]);
         #push @output,sprintf("Total power used: %s (%d BTUs/hr)",$tmp,int($tmp * 3.412+0.5)) if $tmp !~ /NOSUCHINSTANCE/;
         push @output,sprintf("Total power used: %s (%d BTUs/hr)",$tmp,int($tmp * 3.412+0.5)) if $tmp !~ /^NOSUCH/;
         if ($tmp =~ /^NOSUCH/) {
            verbose_message("OID:.1.3.6.1.4.1.2.3.51.2.2.10.5.1.2.0, value:$tmp.");
         }
     }


     if (grep /power/,@vitems) {
         my %oids = ();
         if ($mpatype ne 'cmm') {
          %oids = (
          "PD1",".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.3.1",
          "PD2",".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.3.2",
         );}
         else {
             %oids = ("PD1",".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.3.1");
         }
         foreach my $oid ( keys %oids ) {
           $tmp=$session->get([$oids{$oid}]);
           #push @output,sprintf("%s: %s",$oid,$tmp) if $tmp !~ /NOSUCHINSTANCE/;
           push @output,sprintf("%s: %s",$oid,$tmp) if $tmp !~ /^NOSUCH/;
           if ($tmp =~ /^NOSUCH/) {
            verbose_message("OID:$oids{$oid}, value:$tmp.");
           }
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
        #if ($_->[2] eq "NOSUCHINSTANCE") { 
        if ($_->[2] =~ /^NOSUCH/) { 
            verbose_message("OID:$_->[0].$_->[1], value:$_->[2].");
            next; 
        }
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
sub by_number {
    if ($a < $b) {
        -1;
    } elsif ($a > $b) {
        1;
    } else {
        0;
    }
} 
sub populateblowervitals {
          $chassiswidevitals{blower}=[];
          my %blowerstats=();
          my @bindoid = ();
          if ($mpatype ne 'cmm') {
              @bindoid = (
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
          } else {
              foreach my $fanentry (3..6) {
                  foreach (1..10) {
                      push @bindoid, [$chassisfanbase.$fanentry, "$_"]; 
                  }
              }
          }
          my $bind = new SNMP::VarList(@bindoid);
          $session->get($bind);
          foreach (@$bind) {
              #if ($_->[2] eq "NOSUCHINSTANCE") { 
              if ($_->[2] =~ /^NOSUCH/) { 
                  verbose_message("OID:$_->[0].$_->[1], value:$_->[2].");
                  next; 
              }
              if ($mpatype ne 'cmm') {
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
              } else {
                  my $idx = $_->[1];
                  my $tmp_type = $_->[0];
                  $tmp_type =~ s/^.*\.(\d*)$/$1/;
                  if ($tmp_type eq 3) {
                      $blowerstats{$idx}->{percentage}=$_->[2];
                      $blowerstats{$idx}->{percentage}=~ s/^(\d*)%.*$/$1/;
                  } elsif ($tmp_type eq 4) {
                      $blowerstats{$idx}->{state}=$_->[2];
                  } elsif ($tmp_type eq 5) {
                      $blowerstats{$idx}->{rpm}=$_->[2];
                  } elsif ($tmp_type eq 6) {
                      $blowerstats{$idx}->{cstate}=$_->[2];
                  }         
              }
          }
          foreach my $blowidx (sort by_number keys %blowerstats) {
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
              } elsif ($bdata->{state} == 1) {
                  $text .= " Good state";
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

  if ( !GetOptions(\%opt,qw(V|verbose w x z u))){
    return(1,usage());
  }
  if ( defined($ARGV[0]) ) {
    return(1,usage("Invalid argument: @ARGV\n"));
  }
  if (exists($opt{x}) and exists($opt{z})) {
    return(1,usage("-x and -z are mutually exclusive\n"));
  }

  # Get the mm type from the telnet cli 
  my $mmtypestr;
  if (defined($telnetrscan{'mm'}) && defined ($telnetrscan{'mm'}{'type'})) {
    $mmtypestr = $telnetrscan{'mm'}{'type'};
  } else {
    $mmtypestr = "mm";
  }

  my $mmname = $session->get([$mmoname->{$mptype},0]);;
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
  push @values,join(",",$mmtypestr,$mmname,0,"$mmtype$mmmodel",$mmserial,$mpa,$mpa);
  my $namemax = length($mmname);
  my $mpamax = length($mpa);

  foreach (1..14) {
    my $tmp = $session->get([$bladexistsoid.".$_"]);
    if ($tmp eq 1) {
      my $type = $session->get([$blademtmoid,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      $type =~ s/Not available/null/i;

      my $model = $session->get([$bladeomodel,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      $model =~ s/Not available/null/i;

      my $serial = $session->get([$bladeserialoid,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }
      $serial =~ s/Not available/null/i;

      my $name = $session->get([$bladeoname,$_]);
      if ($session->{ErrorStr}) {
        return(1,$session->{ErrorStr});
      }

      # The %telnetrscan has the entires for the fsp. For NGP ppc blade, set the ip of fsp.
      if (defined($telnetrscan{$_}{'0'}) && $telnetrscan{$_}{'0'}{'type'} eq "fsp") {
        # give the NGP ppc blade an internal specific name to identify 
        push @values, join( ",","ppcblade",$name,$_,"$type$model",$serial,$mpa,$telnetrscan{$_}{'0'}{'ip'});
      } elsif (defined($telnetrscan{$_}{'1'}) && $telnetrscan{$_}{'1'}{'type'} eq "fsp") {
        # give the NGP ppc blade an internal specific name to identify 
        push @values, join( ",","ppcblade",$name,$_,"$type$model",$serial,$mpa,$telnetrscan{$_}{'1'}{'ip'});
      } elsif (defined($telnetrscan{$_}{'0'}) && $telnetrscan{$_}{'0'}{'type'} eq "bmc") {
        # give the NGP x blade an internal specific name to identify
        push @values, join( ",","xblade",$name,$_,"$type$model",$serial,$mpa,$telnetrscan{$_}{'0'}{'ip'});
      } else {
        push @values, join( ",","blade",$name,$_,"$type$model",$serial,$mpa,"");
      }

      my $namelength  = length($name);
      $namemax = ($namelength > $namemax) ? $namelength : $namemax;
      my $mpalength  = length($mpa);
      $mpamax = ($mpalength > $mpamax) ? $mpalength : $mpamax;
    }
  }


  if (defined($has_x222)) {
      foreach (sort (keys %x222_info)) {
          my $name = $x222_info{$_}{node_name};
          my $namelength = length($name);
          my $type = $x222_info{$_}{type};
          my $mtm = $x222_info{$_}{mtm};
          my $serial = $x222_info{$_}{serial};
          my $slotid = $x222_info{$_}{slotid};
          my $ip = (defined($x222_info{$_}{'0'})) ? ($x222_info{$_}{'0'}{'ip'}) : ($x222_info{$_}{'1'}{'ip'});
          $namemax = ($namemax > $namelength) ? $namemax : $namelength;
          if (defined $type) {
              push @values, join(",",$type,$name,$slotid,$mtm,$serial,$mpa,$ip);
          }
      }
  }
  my $format = sprintf "%%-%ds",($namemax+2);
  $rscan_header[1][1] = $format;
  $format = sprintf "%%-%ds",($mpamax+2);
  $rscan_header[5][1] = $format;

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
      if ($data[0] eq "ppcblade" or $data[0] eq "xblade") {
        $data[0] = "blade";
      }
      my $i = 0;

      foreach (@rscan_header) {
        $result .= sprintf @$_[1],$data[$i++];
      }
    }
  }
  if (!exists($opt{w}) && !exists($opt{u})) {
    return(0,$result);
  }
  my @tabs = qw(mp nodehm nodelist nodetype vpd ppc ipmi);
  my %db   = ();

  foreach (@tabs) {
    $db{$_} = xCAT::Table->new( $_, -create=>1, -autocommit=>0 );
    if ( !$db{$_} ) {
      return(1,"Error opening '$_'" );
    }
  }
  my @msg4update;
  foreach (@values) {
    my @data = split /,/;
    my $type = $data[0];
    my $name = $data[1];
    my $id = $data[2];
    my $mtm= $data[3];
    my $serial = $data[4];
    my $ip = $data[6];

    # ignore the blade server which status is 'Comm Error'
    if ($name =~ /Comm Error/) {
      next;
    }
    if ($data[1] =~ /\(\s*([^\s]*)\s*\)/) {
        $name = $1;
    } elsif ($data[1] =~ /^\s*([^s]*)\s*$/) {
        $name = $1;
        $name =~ s/ /_/;
        $name =~ tr/A-Z/a-z/;
    }
    if (exists($opt{u})) {
      ## TRACE_LINE print "Rscan: orig_name [$name]\n";
      
      # search the existed node for updating
      # for the cmm, using the type-serial number to match
      my $matched = 0;
      if ($type eq "cmm") {
        my @vpdlist = $db{vpd}->getAllNodeAttribs(['node','serial','mtm']);
        foreach (@vpdlist) {
          if ($_->{'mtm'} eq $mtm && $_->{'serial'} eq $serial) {
            push @msg4update, sprintf("%-7s$format Matched To =>$format", $type, '['.$name.']', '['.$_->{'node'}.']');
            $name = $_->{'node'};
            $matched = 1;
            last;
          }
        }
      } elsif ($type eq "blade" || $type eq "ppcblade" || $type eq "xblade") {
        # for the blade server, using the mp.mpa and mp.id to match
        my @mplist = $db{mp}->getAllNodeAttribs(['node','mpa','id']);
        foreach (@mplist) {
          if ($_->{'mpa'} eq $mpa && $_->{'id'} eq $id) {
            push @msg4update, sprintf("%-7s$format Matched To =>$format", "blade", '['.$name.']', '['.$_->{'node'}.']');
            $name = $_->{'node'};
            $matched = 1;
            last;
          }
        }
      } 
      
      ## TRACE_LINE print "Rscan: matched_name[$name]\n";
      if (!$matched) {
        my $displaytype = ($type eq "ppcblade") ? "blade" : $type;
        push @msg4update, sprintf("%-7s$format NOT Matched. MM [%s]: Slot ID [%s]", $displaytype, '['.$name.']',$mpa, $id);
        next;
      }
    }

    # Update the ppc table for the fsp and ppcblade
    my ($k1,$u1);
    $k1->{node} = $name;
    if ($type eq "ppcblade") {
      #$u1->{hcp} = $ip;
      $u1->{nodetype} = "blade";
      $u1->{id} = "1";
      $u1->{parent} = $mpa;
      $db{ppc}->setAttribs($k1,$u1);
      $db{ppc}{commit} = 1;
    }

    # Update the entry in mp table for ppcblade and general blade
    my ($k11,$u11);
    $k11->{node} = $name;
    $u11->{mpa}  = $mpa;
    $u11->{id}   = $id;
    if ($type eq "ppcblade") {
      $u11->{nodetype} = "blade";
    } elsif ($type eq "xblade") {
      $u11->{nodetype}   = "blade";
    } else {
      $u11->{nodetype}   = $type;
    }
    $db{mp}->setAttribs($k11,$u11);
    $db{mp}{commit} = 1;

    # Update the entry in nodehm table
    my ($k2,$u2);
    $k2->{node} = $name;
    if ($type eq "ppcblade") {
      $u2->{mgt}  = "fsp";
      $u2->{cons} = "fsp";
    } elsif ($type eq "xblade") {
      $u2->{mgt}  = "ipmi";
      $u2->{cons} = "ipmi";
    } else {
      $u2->{mgt}  = "blade";
      if($type eq "blade"){
        $u2->{cons} = "blade";
      }
    }
    $db{nodehm}->setAttribs($k2,$u2);
    $db{nodehm}{commit} = 1;

    # Update the entry in nodelist table
    my ($k3,$u3);
    $k3->{node}   = $name;
    my $append;
    if (($type eq "ppcblade") or ($type eq "xblade")){
        $append = "blade";
    } else {
        $append = $type;
    }
    $u3->{groups} = $append.",all";
    my $tmp_groups = $db{nodelist}->getNodeAttribs($name,['groups']);
    if (defined($tmp_groups) and defined($tmp_groups->{groups})) {
        $u3->{groups} =$tmp_groups->{groups};
        my @groups_array = split /,/,$tmp_groups->{groups};
        if (!grep(/^$append$/, @groups_array)) {
            $u3->{groups} .= ",$append";
        }
        if (!grep(/^all$/, @groups_array)) {
            $u3->{groups} .= ",all";
        }
    }
    $db{nodelist}->setAttribs($k3,$u3);
    $db{nodelist}{commit} = 1;

    # Update the entry in nodetype table
    my ($k4, $u4);
    $k4->{node} = $name;
    if ($type eq "ppcblade"){
      $u4->{nodetype} = "ppc,osi";
    } elsif ($type eq "blade") {
      $u4->{nodetype} = "mp,osi";
    } elsif ($type eq "mm" || $type eq "cmm" || $type eq "xblade") {
      $u4->{nodetype} = "mp";
    }
    $db{nodetype}->setAttribs($k4,$u4);
    $db{nodetype}{commit} = 1;

    # Update the entry in vpd table
    my ($k5, $u5);
    $k5->{node} = $name;
    $u5->{mtm} = $data[3];
    $u5->{serial} = $data[4];
    $db{vpd}->setAttribs($k5,$u5);
    $db{vpd}{commit} = 1;
    # Update the entry in ipmi table for x blade
    if ($type eq "xblade") {
        my ($k6, $u6);
        $k6->{node} = $name;
        $u6->{bmc} = $ip;
        $db{ipmi}->setAttribs($k6,$u6);
        $db{ipmi}{commit} = 1;
    }
  }
  foreach ( @tabs ) {
    if ( exists( $db{$_}{commit} )) {
       $db{$_}->commit;
    }
  }

  if (exists($opt{u})) {
    $result = join("\n", @msg4update);
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
    my $type = $data[0];
    my $origtype = $type;
    if ($type eq "ppcblade" or $type eq "xblade") {
      $type = "blade";
    }
    # ignore the blade server which status is 'Comm Error'
    if ($data[1] =~ /Comm Error/) {
      next;
    }

    my $href = {
        Node => { }
    };
    my $mtm = undef;
    foreach ( @rscan_attribs ) {
        my $d = $data[$i++];

        my $ignore;
        if ( /^name$/ ) {
            next;
        } elsif ( /^nodetype$/ ) {
            if ($origtype eq "ppcblade") {
              $d = "ppc,osi";
            } elsif ($origtype eq "blade") {
              $d = "mp,osi";
            } else {
              $d = "mp";
            }
        } elsif ( /^groups$/ ) {
            $d = "$type,all";
            $ignore = 1;
        } elsif ( /^mgt$/ ) {
            if ($origtype eq "ppcblade") {
              $d = "fsp";
            } elsif ($origtype eq "xblade") {
              $d = "ipmi";
            } else {
              $d = "blade";
            }
        } elsif ( /^cons$/ ) {
            if($origtype eq "blade"){
              $d = "blade";
            } elsif ($origtype eq "ppcblade"){
              $d = "fsp";
            } elsif ($origtype eq "xblade") {
              $d = "ipmi";
            } else {
              $ignore = 1;
            }
        } elsif ( /^mpa$/ ) {
              $d = $mpa;
        } elsif ( /^hwtype$/ ) {
            if ($origtype eq "ppcblade" or $origtype eq "xblade") {
              $d = "blade";
            } else {
              $d = $type;
            }
        } elsif (/^id$/) {
            # for the NGP ppc blade, add the slotid to mp.id
            if ($origtype eq "ppcblade") {
              $href->{Node}->{slotid} = $d;
              $d = "1";
            }
            elsif ($origtype eq "xblade") {
              $href->{Node}->{slotid} = $d;
              $ignore = 1;
            }
        } elsif (/^hcp/) {
            if ($origtype eq "ppcblade") {
              $href->{Node}->{parent} = $mpa;
            } else {
              $ignore = 1;
            }
        } elsif (/^mtm$/) {
            $d =~ /^(\w{4})/;
            $mtm = $1;
        }

        if (!$ignore) {
            $href->{Node}->{$_} = $d;
        }
    }
    my $tmp_groups = "$type,all";
    if (defined($mtm)) {
        my $tmp_pre = xCAT::data::ibmhwtypes::parse_group($mtm);
        if (defined($tmp_pre)) {
            $tmp_groups .= ",$tmp_pre";
        }
    } 
    $href->{Node}->{groups} = $tmp_groups;
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
    my $origtype = $type;
    if ($type eq "ppcblade" or $type eq "xblade") {
      $type = "blade";
    }
    # ignore the blade server which status is 'Comm Error'
    if ($data[1] =~ /Comm Error/) {
      next;
    }
    my $objname;
    if ($data[1] =~ /\(\s*([^\s]*)\s*\)/) {
        $objname = $1;
    } elsif ($data[1] =~ /^\s*([^s]*)\s*$/) {
        $objname = $1;
        $objname =~ s/ /_/;
        $objname =~ tr/A-Z/a-z/;
    } else {
        $objname = $data[1];
    }
    $result .= "$objname:\n\tobjtype=node\n";
    my $mtm = undef;
    foreach ( @rscan_attribs ) {
        my $d = $data[$i++];

        my $ignore;
        if ( /^name$/ ) {
            next; 
        } elsif ( /^nodetype$/ ) {
            if ($origtype eq "ppcblade") {
              $d = "ppc,osi";
            } elsif ($origtype eq "blade") {
              $d = "mp,osi";
            } else {
              $d = "mp";
            }
        } elsif ( /^groups$/ ) {
            $d = "$type,all";
            $ignore = 1;
        } elsif ( /^mgt$/ ) {
            if ($origtype eq "ppcblade") {
              $d = "fsp";
            } elsif ($origtype eq "xblade") {
              $d = "ipmi";
            } else {
              $d = "blade"; 
            }
        } elsif ( /^cons$/ ) {
            if($origtype eq "blade"){
              $d = "blade";
            } elsif ($origtype eq "ppcblade"){
              $d = "fsp";
            } elsif ($origtype eq "xblade") {
              $d = "ipmi";
            } else {
              $ignore = 1;
            }
        } elsif ( /^mpa$/ ) {
              $d = $mpa;
        } elsif ( /^hwtype$/ ) {
            if ($origtype eq "ppcblade" or $origtype eq "xblade") {
              $d = "blade";
            } else {
              $d = $type;
            }
        } elsif (/^id$/) {
            # for the NGP ppc blade, add the attirbute 'slotid' that match to mp.id
            if ($origtype eq "ppcblade") {
              $result .= "\tslotid=$d\n";
              $d = "1";
            }
            elsif ($origtype eq "xblade") {
              $result .= "\tslotid=$d\n";
              $ignore = 1;
            }
        } elsif (/^hcp/) {
            if ($origtype eq "ppcblade") {
              $result .= "\tparent=$mpa\n";
            } else {
              $ignore = 1;
            }
        } elsif (/^mtm$/) {
            $d =~ /^(\w{4})/;
            $mtm = $1;
        }

        if (!$ignore) {
            $result .= "\t$_=$d\n";
        }
    }
    my $tmp_groups = "$type,all";
    if (defined ($mtm)) {
        my $tmp_pre = xCAT::data::ibmhwtypes::parse_group($mtm);
        if (defined ($tmp_pre)) {
            $tmp_groups .= ",$tmp_pre";
        }
    }
    $result .= "\tgroups=$tmp_groups\n";
  }
  return( $result );
}

sub getmacs {
   my ($node, @args) = @_;

   my $display = ();
   my $byarp = ();
   my $installnic = undef;
   #foreach my $arg (@args) {
   #   if ($arg eq "-d") {
   #      $display = "yes";
   #   } elsif ($arg eq "--arp") {
   #      $byarp = "yes";
   #   }
   #}
   while (@args) {
       my $arg = shift @args;
       if ($arg eq "-d") {
          $display = "yes";
       } elsif ($arg eq "--arp") {
          $byarp = "yes";
       } elsif ($arg eq "-i") {
          $installnic = shift @args;
          $installnic =~ s/eth|en//;
       }
   }

   if ($byarp eq "yes") {
       my $output = xCAT::SvrUtils->get_mac_by_arp([$node], $display);
       my @ret = ();
       foreach my $n (keys %$output) {
           if ($n ne $node) {
               next;
           }
           push @ret, $output->{$n};
       }
       return (0, @ret);
   }

   my @macs = ();
   (my $code,my @orig_macs)=inv('mac');
   my $ignore_gen_mac = 0;
   foreach my $mac (@orig_macs) {
       if ($mac =~ /(.*) -> (.*)/) { 
           #Convert JS style mac ranges to pretend to be simple
           #this is not a guarantee of how the macs work, but 
           #this is as complex as this function can reasonably accomodate
           #if you need more complexity, the auto-discovery process
           #can actually cope

           my $basemac = $1;
           my $lastmac = $2;
           push @macs, $basemac;
           $basemac =~ s/mac address \d: //i;
           $lastmac =~ s/mac address \d: //i;

           while ($basemac ne $lastmac) {
               $basemac =~ s/://g;
               # Since 32bit Operating System can only handle 32bit integer, 
               # split the mac address as high 24bit and low 24bit 
               $basemac =~ /(......)(......)/;
               my ($basemac_h6, $basemac_l6) = ($1, $2);
               my $macnum_l6 = hex($basemac_l6);
               my $macnum_h6 = hex($basemac_h6);
               $macnum_l6 += 1;
               if ($macnum_l6 > 0xFFFFFF) {
                   $macnum_h6 += 1;
               }
               my $newmac_l6 = sprintf("%06X", $macnum_l6);
               $newmac_l6 =~ /(......)$/;
               $newmac_l6 = $1;
               my $newmac_h6 = sprintf("%06X", $macnum_h6);
               my $newmac = $newmac_h6.$newmac_l6;
               $newmac =~ s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
               my $newidx = scalar(@macs)+1;
               push @macs,"MAC Address $newidx: ".$newmac;

               $basemac = $newmac;
           }

           # If one mac address has -> as a range, this must be a system P blade. 
           # Then ignore the following mac with prefix "mac address"
           $ignore_gen_mac = 1;
       } elsif (!$ignore_gen_mac || $mac =~ /\w+ mac address \d:/i) {
           push @macs, $mac;
       }
   }

   my $midx=0;
   my @midxary;
   if (defined($installnic)) {
      push @midxary, $installnic;
   } else {
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
                   while ( $nent->{$mkey} =~ /[en|eth](\d+)/g ) {
                       push @midxary,$1;
                   }
               }
           #} elsif ($display !~ /yes/){
           #   return -1, "please set noderes.installnic or noderes.primarynic";
           }
           $nrtab->close;
       }
   }
   if ($code==0) {
     if ($display =~ /yes/) {
      my $allmac = join("\n", @macs);
      return 0,":The mac address is:\n$allmac";
     }
     if (!@midxary) {
         push @midxary, '0';
     }
     my @allmacs;
     foreach my $midx ( @midxary) {
       (my $macd,my $mac) = split (/:/,$macs[$midx],2);
       $mac =~ s/\s+//g;
       $mac =~ s/(.*)/\L$1/g;
       if ($macd !~ /mac address \d/i) {
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
  @ARGV=@_;
  my $updatetable;
  GetOptions(
	"t|table" => \$updatetable,
  );
  foreach (@ARGV) {
    push @invitems,split( /,/,$_);
  }
  my $item;
  unless (scalar(@invitems)) {
      @invitems = ("all");
  }
  my %updatehash;
  while (my $item = shift @invitems) {
    if ($item =~ /^all/) {
      push @invitems,(qw(mtm serial mac firm));
      next;
    }
    if ($item =~ /^firm/) {
      push @invitems,(qw(bios diag mprom mparom));
      next;
    }
    if ($item =~ /^bios/ and $mptype !~ /mm/) {
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
    if ($item =~ /^diag/ and $mptype !~ /mm/) {
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
    if ($item =~ /^[sm]prom/ and $mptype !~ /mm/) {
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
      if ($mptype eq 'cmm') {
        my $type = $session->get(['1.3.6.1.4.1.2.3.51.2.2.21.1.1.1', '0']);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        my $model = $session->get(['1.3.6.1.4.1.2.3.51.2.2.21.1.1.2', '0']);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        push @output, "Machine Type/Model: ".$type.$model;
        $updatehash{mtm}=$type.$model;
      } else {
        my $type=$session->get([$blademtmoid,$slot]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        my $model = $session->get([$bladeomodel, $slot]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        push @output,"Machine Type/Model: ".$type.$model;
        $updatehash{mtm}=$type.$model;
      }
    }
    if ($item =~ /^uuid/ or $item =~ /^guid/) {
      if ($mptype eq 'cmm') {
          $data=$session->get(['.1.3.6.1.4.1.2.3.51.2.2.21.2.1.1.6', '1']);
      } elsif ($slot =~ /^(.*):(.*)\z/) {
	my $idx = "1.1.3.$1.3.$2"; #1.1 means chassis 1, 3.<bay> means blade <bay>, 3.<index> is the offset into the slot
        $data=$session->get([$componentuuidoid,$idx]);
      } else {
          $data=$session->get([$bladeuuidoid,$slot]);
      }
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      $data =~ s/ //;
      $data =~ s/ /-/;
      $data =~ s/ /-/;
      $data =~ s/ /-/;
      $data =~ s/ /-/;
      $data =~ s/ //g;
      push @output,"UUID/GUID: ".$data;
      $updatehash{uuid}=$data;
    }
    if ($item =~ /^serial/) {
      if ($mptype eq 'cmm') {
          #chassisInfoVpd->chassisVpd->chassisSerialNumber
          $data=$session->get(['1.3.6.1.4.1.2.3.51.2.2.21.1.1.3','0']);
      } else {
          $data=$session->get([$bladeserialoid,$slot]);
      }
      if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
      push @output,"Serial Number: ".$data;
      $updatehash{serial}=$data;
    }

    if ($item =~ /^mac/ and $slot !~ /:/) {
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
      foreach (0..3) {
        $data=$session->get([$sidecardoids[$_],$slot]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($data =~ /:/) {
          push @output,"Side card MAC Address ".($_+1).": ".$data;
        }
      }
    }
  }
  if ($updatetable and $updatehash{mtm}) {
      #updatenodegroups
      my $tmp_pre = xCAT::data::ibmhwtypes::parse_group($updatehash{mtm}) ;
      if (defined($tmp_pre)) {
          xCAT::TableUtils->updatenodegroups($currnode, $tmp_pre);
      }
  }
  if ($updatetable and keys %updatehash) {
  	my $vpdtab = xCAT::Table->new('vpd');
	$vpdtab->setNodeAttribs($currnode,\%updatehash);
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
  unless ($subcommand) { $subcommand = "stat"; }
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
  	$session = new SNMP::Session(
                    DestHost => $mpa,
                    Version => '3',
                    SecName => $mpauser,
                    AuthProto => 'SHA',
                    AuthPass => $mpapass,
                    PrivProto => 'DES',
                    SecLevel => 'authPriv',
                    UseNumeric => 1,
                    Retries => 1, # Give up sooner to make commands go smoother
                    Timeout=>300000000, #Beacon, for one, takes a bit over a second to return
                    PrivPass => $mpapass);
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


# The oids which are used in the renergy command
my $bladetype_oid = ".1.3.6.1.4.1.2.3.51.2.2.21.1.1.1.0";    #bladeCenterVpdMachineType

my $pdstatus_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.3";    #fuelGaugeStatus
my $pdpolicy_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.6";    #fuelGaugePowerManagementPolicySetting
my $pdmodule1_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.4";    #fuelGaugeFirstPowerModule
my $pdmodule2_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.5";    #fuelGaugeSecondPowerModule
my $pdavailablepower_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.7";    #fuelGaugeTotalPower
my $pdreservepower_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.8";    #fuelGaugeAllocatedPower
my $pdremainpower_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.9";    #fuelGaugeRemainingPower
my $pdinused_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.1.1.1.10";    #fuelGaugePowerInUsed

my $chassisDCavailable_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.5.1.1.0";    #chassisTotalDCPowerAvailable
my $chassisACinused_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.5.1.2.0";    #chassisTotalACPowerInUsed
my $chassisThermalOutput_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.5.1.3.0";    #chassisTotalThermalOutput

my $chassisFrontTmp_oid = ".1.3.6.1.4.1.2.3.51.2.2.1.5.1.0";    #frontPanelTemp
my $mmtemp_oid = ".1.3.6.1.4.1.2.3.51.2.2.1.1.2.0";    #mmTemp

my $bladewidth_oid = ".1.3.6.1.4.1.2.3.51.2.22.1.5.1.1.15";    #bladeWidth

my $curallocpower_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.pdnum.1.1.7";    #pd1ModuleAllocatedPowerCurrent
my $maxallocpower_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.pdnum.1.1.8";    #pd1ModuleAllocatedPowerMax
my $minallocpower_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.pdnum.1.1.9";    #pd1ModuleAllocatedPowerMin
my $powercapability_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.pdnum.1.1.12";    #pd1ModulePowerCapabilities

my $powercapping_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.3";    #bladeDetailsMaxPowerConfig
my $effCPU_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.4";    #bladeDetailsEffectiveClockRate
my $maxCPU_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.5";    #bladeDetailsMaximumClockRate
my $savingstatus_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.6";    #bladeDetailsPowerSaverMode
my $dsavingstatus_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.7";    #bladeDetailsDynamicPowerSaver
my $dsperformance_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.8";    #bladeDetailsDynamicPowerFavorPerformanceOverPower

# New attributes which supported by CMM
my $PowerControl_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.9"; #bladeDetailsPowerControl
my $PowerPcapMin_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.10"; #bladeDetailsPcapMin
my $PowerPcapGMin_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.11"; #bladeDetailsPcapGuaranteedMin
my $PowerPcapMax_oid = ".1.3.6.1.4.1.2.3.51.2.2.10.4.1.1.1.12"; #bladeDetailsPcapMax

# New table used to control the power management
#my $powerPcapMin =".1.3.6.1.4.1.2.3.51.2.22.31.6.1.10";    # componentPowerDetailsPcapMin
#my $powerPcapGMin = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.11";    # componentPowerDetailsPcapGuaranteedMin
#my $powerPcapMax = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.12";    # componentPowerDetailsPcapMax

#my $powerPcapSet = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.3"; # componentPowerDetailsMaxPowerConfig
#my $powerControl = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.9"; # componentPowerDetailsPowerControl
#my $powersavingstatus_oid = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.6";    #componentPowerDetailsPowerSaverMode
#my $powerdsavingstatus_oid = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.7";    #componentPowerDetailsDynamicPowerSaver
#my $powerdsperformance_oid = ".1.3.6.1.4.1.2.3.51.2.22.31.6.1.8";    #componentPowerDetailsDynamicPowerFavorPerformanceOverPower



# The meaning of obj fuelGaugePowerManagementPolicySetting
my %pdpolicymap = (
    '0' => "redundantWithoutPerformanceImpact",
    '1' => "redundantWithPerformanceImpact",
    '2' => "nonRedundant",
    '3' => "redundantACPowerSource",
    '4' => "acPowerSourceWithBladeThrottlingAllowed",
    '255' => "notApplicable",
);

# The meaning of obj pd1/2ModulePowerCapabilities
my %capabilitymap = (
    '0' => "noAbility",
    '1' => "staticPowerManagement",
    '2' => "fixedPowerManagement",
    '3' => "dynamicPowerManagement",
    '4' => "dynamicPowerMeasurement1",
    '5' => "dynamicPowerMeasurement2",
    '6' => "dynamicPowerMeasurementWithPowerCapping",
    '255' => "notApplicable",
);

# The valid attributes the renergy command can support
# 1 for readonly; 2 for write; 3 readwrite

my %mm_valid_items = (
    'pd1status' => 1,
    'pd2status' => 1,
    'pd1policy' => 1,
    'pd2policy' => 1,
    'pd1powermodule1' => 1,
    'pd1powermodule2' => 1,
    'pd2powermodule1' => 1,
    'pd2powermodule2' => 1,
    'pd1avaiablepower' => 1,
    'pd2avaiablepower' => 1,
    'pd1reservedpower' => 1,
    'pd2reservedpower' => 1,
    'pd1remainpower' => 1,
    'pd2remainpower' => 1,
    'pd1inusedpower' => 1,
    'pd2inusedpower' => 1,
    'availableDC' => 1,
    'averageAC' => 1,
    'thermaloutput' => 1,
    'ambienttemp' => 1,
    'mmtemp' => 1,
);

my %cmm_valid_items = (
    'powerstatus' => 1,
    'powerpolicy' => 1,
    'powermodule' => 1,
    'avaiablepower' => 1,
    'reservedpower' => 1,
    'remainpower' => 1,
    'inusedpower' => 1,
    'availableDC' => 1,
    'averageAC' => 1,
    'thermaloutput' => 1,
    'ambienttemp' => 1,
    'mmtemp' => 1,
);

my %pd1_valid_items = (
    'pd1status' => 1,
    'pd1policy' => 1,
    'pd1powermodule1' => 1,
    'pd1powermodule2' => 1,
    'pd1avaiablepower' => 1,
    'pd1reservedpower' => 1,
    'pd1remainpower' => 1,
    'pd1inusedpower' => 1,
);

my %pd2_valid_items = (
    'pd2status' => 1,
    'pd2policy' => 1,
    'pd2powermodule1' => 1,
    'pd2powermodule2' => 1,
    'pd2avaiablepower' => 1,
    'pd2reservedpower' => 1,
    'pd2remainpower' => 1,
    'pd2inusedpower' => 1,
);

my %blade_valid_items = (
    'averageDC' => 1,
    'cappingmaxmin' => 0,
    'cappingmax' => 0,
    'cappingmin' => 0,
    'capability' => 1,
    'cappingvalue' => 1,
    'cappingwatt' => 0,
    'cappingperc' => 0,
    'CPUspeed' => 1,
    'maxCPUspeed' => 1,
    'savingstatus' => 3,
    'dsavingstatus' => 3,
);

my %flex_blade_valid_items = (
    'averageDC' => 1,
    'cappingmaxmin' => 1,
    'cappingmax' => 1,
    'cappingmin' => 1,
    'cappingGmin' => 1,
    'capability' => 1,
    'cappingvalue' => 1,
    'cappingwatt' => 2,
    'cappingperc' => 2,
    'CPUspeed' => 1,
    'maxCPUspeed' => 1,
    'cappingstatus' => 3,
    'savingstatus' => 3,
    'dsavingstatus' => 3,
);

# use the slot number of serverblade to get the powerdomain number
# and the bay number in the powerdomain
sub getpdbayinfo {
    my ($bc_type, $slot) = @_;

    my $pdnum = 0;
    my $pdbay = 0;
    
    if ($bc_type =~ /^1886|7989|8852$/) {  # for blade center H
        if ($slot < 8) {
            $pdnum = 1;
            $pdbay = $slot + 16;
        } elsif ($slot < 15) {
            $pdnum = 2;
            $pdbay = $slot + 16 -7;
        }
    } elsif ($bc_type =~ /^8740|8750$/) { # for blade center HT
        if ($slot < 7) {
            $pdnum = 1;
            $pdbay = $slot + 22;
        } elsif ($slot < 13) {
            $pdnum = 2;
            $pdbay = $slot + 12 -6;
        }
    } elsif ($bc_type =~ /^8720|8730$/) { # for blade center T
        if ($slot < 5) {
            $pdnum = 1;
            $pdbay = $slot + 12;
        } elsif ($slot < 9) {
            $pdnum = 2;
            $pdbay = $slot + 2 -4;
        }
    } elsif ($bc_type =~ /^8720|8730$/) { # for blade center S
        if ($slot < 7) {
            $pdnum = 1;
            $pdbay = $slot + 17;
        } 
    } elsif ($bc_type =~ /^7893$/) { # for flex
        $pdnum = 1;
        $pdbay = $slot + 18;
    } else { # for common blade center
        if ($slot < 7) {
            $pdnum = 1;
            $pdbay = $slot + 10;
        } elsif ($slot < 15) {
            $pdnum = 2;
            $pdbay = $slot - 6;
        }
    }

    return ($pdnum, $pdbay);
}

# command to hand the renergy request
sub renergy {
    my ($mpa, $node, $slot, @items) = @_;

    if (!$mpa) {
        return (1, "The attribute [mpa] needs to be set for the node $node.");
    }
    if (!$slot && ($mpa ne $node)) {
        return (1, "The attribute [id] needs to be set for the node $node.");
    }

    # the type of blade center
    my $bc_type = ""; 
    
    #check the validity of all the attributes
    
    my @readlist = ();
    my %writelist = ();
    my @r4wlist = ();
    foreach my $item (@items) {
        if (!$item) {
            next;
        }
        my $readpath = ();
        my $checkpath = ();
        if ($item =~ /^all$/) {
            if ($mpa eq $node) {
                #handle the mm itself
                if ($mptype eq "cmm") {
                    $readpath = \%cmm_valid_items;
                } else { # Assume it's AMM
                    $readpath = \%mm_valid_items;
                }
            } else {
                if ($mptype eq "cmm") {
                    $readpath = \%flex_blade_valid_items;
                } else { # Assume it's AMM
                    $readpath = \%blade_valid_items;
                }
            }
        } elsif ($item =~ /^pd1all$/) {
            if ($mpa ne $node) {
                return (1, "pd1all is NOT available for flex or blade center server.");
            }
            if ($mptype eq "cmm") { # It only works for AMM
                return (1, "pd1all is NOT available for flex chassis.");
            }
            $readpath = \%pd1_valid_items;
        } elsif ($item =~ /^pd2all$/) {
            if ($mpa ne $node) {
                return (1, "pd2all is NOT available for flex or blade center server.");
            }
            if ($mptype eq "cmm") { # It only works for AMM
                return (1, "pd2all is NOT available for flex chassis.");
            }
            $readpath = \%pd2_valid_items;
        } elsif ($item =~ /^cappingmaxmin$/) {
            push @readlist, ('cappingmin','cappingmax');
        } elsif ($item =~ /(.*)=(.*)/) {
            my $name = $1;
            my $value = $2;
            if ($mpa eq $node) {
                if ($mptype eq "cmm") {
                    $checkpath = \%cmm_valid_items;
                } else {
                    $checkpath = \%mm_valid_items;
                }
            } else {
                if ($mptype eq "cmm") {
                    $checkpath = \%flex_blade_valid_items;
                } else {
                    $checkpath = \%blade_valid_items;
                }
            }
            
            if ($checkpath->{$name} < 2) {
                return (1, "$name is NOT writable.");
            }
                
            $writelist{$name} = $value;
            if ($name eq "cappingwatt" || $name eq "cappingperc") {
                push @r4wlist, ('cappingmin','cappingmax');
            }
        } else {
            if ($mpa eq $node) {
                if ($mptype eq "cmm") {
                    $checkpath = \%cmm_valid_items;
                } else {
                    $checkpath = \%mm_valid_items;
                }
            } else {
                if ($mptype eq "cmm") {
                    $checkpath = \%flex_blade_valid_items;
                } else {
                    $checkpath = \%blade_valid_items;
                }
            }

            if ($checkpath->{$item} != 1 && $checkpath->{$item} != 3) {
                return (1, "$item is NOT a valid attribute.");
            }

            push @readlist, $item;
        }

        # Handle the attribute equals 'all', 'pd1all', 'pd2all'
        if ($readpath) {
            foreach (keys %$readpath) {
                if ($readpath->{$_} == 1 || $readpath->{$_} == 3) {
                    if (/^cappingmaxmin$/) { next;}
                    push @readlist, $_;
                }
            }
        }
    }


    # does not support to read and write in one command
    if ( @readlist && %writelist ) {
        return (1, "Cannot handle read and write in one command.");
    }

    if (scalar(keys %writelist) > 1) {
        return (1, "renergy cannot set multiple attributes at one command.");
    }

    if (! (@readlist || %writelist) ) {
        return (1, "Does not get any valid attributes.");
    }

    if ((!@readlist) && %writelist) {
        push @readlist, @r4wlist;
    }

    # get the blade center type first
    if (grep (/^averageAC|averageDC|cappingmax|cappingmin|capability$/, @readlist)) {
        $bc_type =$session->get([$bladetype_oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    }

    my @output = ();
    foreach my $item (sort(@readlist)) {
        my $oid = "";
        if ($item =~ /^(pd1status|powerstatus)$/) {
            $oid = $pdstatus_oid.".1";
        } elsif ($item eq "pd2status") {
            $oid = $pdstatus_oid.".2";
        } elsif ($item =~ /^(pd1policy|powerpolicy)$/) {
            $oid = $pdpolicy_oid.".1";
        } elsif ($item eq "pd2policy") {
            $oid = $pdpolicy_oid.".2";
        } elsif ($item =~ /^(pd1powermodule1|powermodule)$/) {
            $oid = $pdmodule1_oid.".1";
        } elsif ($item eq "pd2powermodule1") {
            $oid = $pdmodule1_oid.".2";
        } elsif ($item eq "pd1powermodule2") {
            $oid = $pdmodule2_oid.".1";
        } elsif ($item eq "pd2powermodule2") {
            $oid = $pdmodule2_oid.".2";
        } elsif ($item =~ /^(pd1avaiablepower|avaiablepower)$/) {
            $oid = $pdavailablepower_oid.".1";
        } elsif ($item eq "pd2avaiablepower") {
            $oid = $pdavailablepower_oid.".2";
        } elsif ($item =~ /^(pd1reservedpower|reservedpower)$/) {
            $oid = $pdreservepower_oid.".1";
        } elsif ($item eq "pd2reservedpower") {
            $oid = $pdreservepower_oid.".2";
        } elsif ($item =~ /^(pd1remainpower|remainpower)$/) {
            $oid = $pdremainpower_oid.".1";
        } elsif ($item eq "pd2remainpower") {
            $oid = $pdremainpower_oid.".2";
        } elsif ($item =~ /^(pd1inusedpower|inusedpower)$/) {
            $oid = $pdinused_oid.".1";
        } elsif ($item eq "pd2inusedpower") {
            $oid = $pdinused_oid.".2";
        } elsif ($item eq "availableDC") {
            $oid = $chassisDCavailable_oid;
        } elsif ($item eq "thermaloutput") {
            $oid = $chassisThermalOutput_oid;
        } elsif ($item eq "ambienttemp") {
            $oid = $chassisFrontTmp_oid;
        } elsif ($item eq "mmtemp") {
            $oid = $mmtemp_oid;
        } elsif ($item eq "averageAC") {
            # just for management module
            $oid = $chassisACinused_oid;
        } elsif ($item eq "averageDC") {
            # just for server blade
            my ($pdnum, $pdbay) = getpdbayinfo($bc_type, $slot);
            $oid = $curallocpower_oid;
            $pdnum++;
            $oid =~ s/pdnum/$pdnum/;
            $oid = $oid.".".$pdbay;
        }  elsif ($item eq "capability") {
            my ($pdnum, $pdbay) = getpdbayinfo($bc_type, $slot);
            $oid = $powercapability_oid;
            $pdnum++;
            $oid =~ s/pdnum/$pdnum/;
            $oid = $oid.".".$pdbay;
        } elsif ($item eq "cappingmax") {
            $oid = $PowerPcapMax_oid.".".$slot;
        } elsif ($item eq "cappingmin") {
            $oid = $PowerPcapMin_oid.".".$slot;
        } elsif ($item eq "cappingGmin") {
            $oid = $PowerPcapGMin_oid.".".$slot;
        } elsif ($item eq "cappingvalue") {
            $oid = $powercapping_oid.".".$slot;
        } elsif ($item eq "CPUspeed") {
            $oid = $effCPU_oid.".".$slot;
        } elsif ($item eq "maxCPUspeed") {
            $oid = $maxCPU_oid.".".$slot;
        } elsif ($item eq "cappingstatus") {
            $oid = $PowerControl_oid.".".$slot;
        } elsif ($item eq "savingstatus") {
            $oid = $savingstatus_oid.".".$slot;
        } elsif ($item eq "dsavingstatus") {
            $oid = $dsavingstatus_oid.".".$slot;
        } else {
            push @output, "$item is NOT a valid attribute.";
        } 

        if ($oid ne "") {
            my $data=$session->get([$oid]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

            if ($data ne "" 
                && $data ne "NOSUCHINSTANCE"
                && $data ne "notApplicable" ) {
                if ($item =~ /^(pd1|pd2|power)policy$/) {
                    push @output, "$item: $pdpolicymap{$data}";
                } elsif ($item eq "capability") {
                    push @output, "$item: $capabilitymap{$data}";
                } elsif ($item =~/cappingvalue|averageDC|cappingmax|cappingmin|cappingGmin/) {
                    if ($item eq "cappingvalue" && $data eq "0") {
                        push @output,"$item: na";
                    } else {
                        my $bladewidth = $session->get([$bladewidth_oid.".$slot"]);
                        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                        $data =~ s/[^\d]*$//;
                        foreach (1..$bladewidth-1) {
                            $oid =~ /(\d+)$/;
                            my $next = $1+$_;
                            $oid =~ s/(\d+)$/$next/;
                            my $nextdata=$session->get([$oid]);
                            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                            $nextdata =~ s/[^\d]*$//;
                            $data += $nextdata;
                        }
                        push @output, "$item: $data"."W";
                    }
                } elsif ($item eq "cappingstatus") {
                    if ($data eq "2" || $data eq "5" || $data eq "10") {
                        # 1 all off; 2 cap; 
                        # 4 staticsaving; 5 cap + staticsaving; 
                        # 9 dynamicsaving; 10 cap + dynamicsaving;
                        push @output,"$item: on";
                    } elsif ($data eq "0" || $data eq "1" || $data eq "3" || $data eq "4" || $data eq "9") {
                        push @output, "$item: off";
                    } else {
                        push @output,"$item: na";
                    }
                } elsif ($item eq "savingstatus") {
                    if ($data eq "0") {
                        push @output,"$item: off";
                    } elsif ($data eq "1") {
                        push @output, "$item: on";
                    } else {
                        push @output,"$item: na";
                    }
                } elsif ($item eq "dsavingstatus") {
                    # get the favor performance
                    my $pdata=$session->get([$dsperformance_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    
                    if ($data eq "0") {
                        push @output,"$item: off";
                    } elsif ($data eq "1" && $pdata eq "0") {
                        push @output, "$item: on-norm";
                    } elsif ($data eq "1" && $pdata eq "1") {
                        push @output, "$item: on-maxp";
                    } else {
                        push @output,"$item: na";
                    }
                } else {
                    push @output,"$item: $data";
                }
            } else {
                push @output,"$item: na";
            }
        }
    }

    # save the values gotten for setting
    my @setneed;
    if (scalar(keys %writelist)) {
        @setneed = @output;
        @output = ();
    }

    # Handle the setting operation
    foreach my $item (keys %writelist) {
        my $oid = "";
        my $svalue;
        my $cvalue;

        my $capmax;
        my $capmin;
         if ($item eq "cappingstatus") {
            if ($writelist{$item} eq "on") {
                $cvalue = "1";
            } elsif ($writelist{$item} eq "off") {
                $cvalue = "0";
            } else {
                return (1, "The setting value should be on|off.");
            }
            # Get the power control value
            my $cdata = $session->get([$PowerControl_oid.".".$slot]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

            # 1 all off; 2 cap; 
            # 4 staticsaving; 5 cap + staticsaving; 
            # 9 dynamicsaving; 10 cap + dynamicsaving;

            if ($cvalue eq "1") {
                # to enable capping
                if ($cdata eq "2" || $cdata eq "5" || $cdata eq "10") {
                    return (0, "Power capping has been enabled.");
                } elsif ($cdata eq "0" || $cdata eq "1") {
                    $cvalue = "2";
                } elsif ($cdata eq "4") {
                    $cvalue = "5";
                } elsif ($cdata eq "9") {
                    $cvalue = "10";
                } else {
                    return (1, "Encountered error to turn on capping.");
                }
            } else {
                # to disable capping
                if ($cdata eq "1" || $cdata eq "4" || $cdata eq "9") {
                    return (0, "Power capping has been disabled.");
                } elsif ($cdata eq "2") {
                    $cvalue = "1";
                } elsif ($cdata eq "5") {
                    $cvalue = "4";
                } elsif ($cdata eq "10") {
                    $cvalue = "9";
                } else {
                    return (1, "Encountered error to turn off capping.");
                }
            }
            
            my $data = $session->set(new SNMP::Varbind([$PowerControl_oid, $slot, $cvalue ,'INTEGER']));
            unless ($data) { return (1,$session->{ErrorStr}); }
            
            my $rdata=$session->get([$PowerControl_oid.".".$slot]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
            if ($rdata ne $cvalue) {
                return (1, "$item: set operation failed.");
            }
         } elsif ($item eq "cappingwatt" || $item eq "cappingperc") {
            my $bladewidth = $session->get([$bladewidth_oid.".$slot"]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
            if ($bladewidth == 1) {
               foreach my $i (@setneed) {
                   if ($i =~ /^cappingmax: (\d*)W/) {
                       $capmax = $1;
                   } elsif ($i =~ /^cappingmin: (\d*)W/) {
                       $capmin = $1;
                   }
               }
   
               if (! (defined ($capmax) && defined ($capmin))) {
                   return (1, "Cannot get the value of cappingmin or cappingmax.");
               }
   
               if ($item eq "cappingwatt" && ($writelist{$item} > $capmax || $writelist{$item} < $capmin)) {
                   return (1, "The set value should be in the range $capmin - $capmax.");
               }
   
               if ($item eq "cappingperc") {
                   if ($writelist{$item} > 100 || $writelist{$item} < 0) {
                       return (1, "The percentage value should be in the range 0 - 100");
                   }
                   $writelist{$item} = int (($capmax-$capmin)*$writelist{$item}/100 + $capmin);
               }
   
               my $data = $session->set(new SNMP::Varbind([$powercapping_oid, $slot, $writelist{$item} ,'INTEGER']));
               unless ($data) { return (1,$session->{ErrorStr}); }
   
               my $ndata=$session->get([$powercapping_oid.".".$slot]);
               if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
               if ($ndata ne $writelist{$item}) {
                   return (1, "$item: set operation failed.");
               }
            } elsif ($bladewidth == 2) {
                # for double wide blade, the capping needs to be set for the two slots one by one
                # base on the min/max of the slots to know the rate of how many set to slot1 and how many set to slot2
                my $min1 = $session->get([$PowerPcapMin_oid.".".$slot]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                my $min2 = $session->get([$PowerPcapMin_oid.".".($slot+1)]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                my $max1 = $session->get([$PowerPcapMax_oid.".".$slot]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                my $max2 = $session->get([$PowerPcapMax_oid.".".($slot+1)]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

                my ($cv1, $cv2);
                if ($item eq "cappingperc") {
                   if ($writelist{$item} > 100 || $writelist{$item} < 0) {
                       return (1, "The percentage value should be in the range 0 - 100");
                   }
                   $cv1 = int (($max1-$min1)*$writelist{$item}/100 + $min1);
                   $cv2 = int (($max2-$min2)*$writelist{$item}/100 + $min2);
               } elsif ($item eq "cappingwatt") {
                   if (($min1 + $min2)>$writelist{$item} || ($max1+$max2)< $writelist{$item}) {
                       return (1, "The set value should be in the range ".($min1 + $min2)." - ".($max1+$max2).".");
                   } elsif (($max1 + $max2) == $writelist{$item}) {
                       $cv1 = $max1;
                       $cv2 = $max2;
                   } elsif (($min1 + $min2) == $writelist{$item}) {
                       $cv1 = $min1;
                       $cv2 = $min2;
                   } else {
                       my $x1 = ($max1+$min1)/2;
                       my $x2 = ($max2+$min2)/2;
                       # cv1/cv2 = $x1/$x2; cv1+cv2=$writelist{$item}
                       $cv1 = int ($writelist{$item}*$x1/($x1+$x2));
                       $cv2 = $writelist{$item} - $cv1;
                   }
               }
               my $data = $session->set(new SNMP::Varbind([$powercapping_oid, $slot, $cv1 ,'INTEGER']));
               unless ($data) { return (1,$session->{ErrorStr}); }

               $data = $session->set(new SNMP::Varbind([$powercapping_oid, ($slot+1), $cv2 ,'INTEGER']));
               unless ($data) { return (1,$session->{ErrorStr}); }
            } else {
                return (1, "Don't know the wide of the blade.");
            }
        } elsif ($item eq "savingstatus") {
            if ($writelist{$item} eq "on") {
                $svalue = "1";
            } elsif ($writelist{$item} eq "off") {
                $svalue = "0";
            } else {
                return (1, "The setting value should be on|off.");
            }
            
            # static power saving and dynamic power saving cannot be turn on at same time
            if ($svalue eq "1") {
                my $gdata = $session->get([$dsavingstatus_oid.".".$slot]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

                if ($gdata eq "1") {
                    return (1, "The attributes savingstatus and dsavingstatus cannot be turn on at same time.");
                }
            }

            # get the attribute static power save
            my $data=$session->get([$savingstatus_oid.".".$slot]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
            if ($data eq "NOSUCHINSTANCE" || $data eq "notApplicable" || $data eq "255") {
                return (1, "Does not supported by this blade server.");
            }
            if ($data ne $svalue) {
                
                # set it  
                my $sdata = $session->set(new SNMP::Varbind([$savingstatus_oid, $slot, $svalue ,'INTEGER']));
                unless ($sdata) { return (1,$session->{ErrorStr}); }

                my $ndata=$session->get([$savingstatus_oid.".".$slot]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                if ($ndata ne $svalue) {
                    return (1, "Set operation failed.");
                }
            }
        } elsif ($item eq "dsavingstatus") {
            if ($writelist{$item} eq "on-norm") {
                $svalue = "1";
            } elsif ($writelist{$item} eq "on-maxp") {
                $svalue = "2";
            } elsif ($writelist{$item} eq "off") {
                $svalue = "0";
            } else {
                return (1, "The setting value should be one of on-norm|on-maxp|off.");
            }

            # static power saving and dynamic power saving cannot be turn on at same time
            if ($svalue gt "0") {
                my $gdata = $session->get([$savingstatus_oid.".".$slot]);
                if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

                if ($gdata eq "1") {
                    return (1, "The attributes savingstatus and dsavingstatus cannot be turn on at same time.");
                }
            }

            # get the attribute dynamic power save
            my $data = $session->get([$dsavingstatus_oid.".".$slot]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
            if ($data eq "NOSUCHINSTANCE" || $data eq "notApplicable" || $data eq "255") {
                return (1, "Does not supported by this blade server.");
            }

            # get the attribute favor performance 
            my $pdata = $session->get([$dsperformance_oid.".".$slot]);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
            if ($pdata eq "NOSUCHINSTANCE" || $pdata eq "notApplicable" || $pdata eq "255") {
                $pdata = "255";
            }

            # turn off the dynamic power save
            if ($svalue eq "0" && ($data eq "1" || $pdata eq "1")) {
                if ($data eq "1") {
                    my $sdata = $session->set(new SNMP::Varbind([$dsavingstatus_oid, $slot, "0" ,'INTEGER']));
                    unless ($sdata) { return (1,$session->{ErrorStr}); }

                    my $ndata=$session->get([$dsavingstatus_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    if ($ndata ne "0") {
                        return (1, "Set operation failed.");
                    }
                }
                if ($pdata eq "1") {
                    my $sdata = $session->set(new SNMP::Varbind([$dsperformance_oid, $slot, "0" ,'INTEGER']));
                    unless ($sdata) { return (1,$session->{ErrorStr}); }

                    my $ndata=$session->get([$dsperformance_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    if ($ndata ne "0") {
                        return (1, "Set operation failed.");
                    }
                }
            }

            # trun on the dynamic power save but trun off the favor performance
            if ($svalue eq "1" && ($data eq "0" || $pdata eq "1")) {
                if ($data eq "0") {
                    my $sdata = $session->set(new SNMP::Varbind([$dsavingstatus_oid, $slot, "1" ,'INTEGER']));
                    unless ($sdata) { return (1,$session->{ErrorStr}); }

                    my $ndata=$session->get([$dsavingstatus_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    if ($ndata ne "1") {
                        return (1, "Set operation failed.");
                    }
                }

                if ($pdata eq "1") {
                    my $sdata = $session->set(new SNMP::Varbind([$dsperformance_oid, $slot, "0" ,'INTEGER']));
                    unless ($sdata) { return (1,$session->{ErrorStr}); }

                    my $ndata=$session->get([$dsperformance_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    if ($ndata ne "0") {
                        return (1, "Set operation failed.");
                    }
                }
            }

            # trun on the dynamic power save and trun on the favor performance
            if ($svalue eq "2" && $pdata eq "255") {
                return (1, "The on-maxp is NOT supported.");
            }
            if ($svalue eq "2" && ($data eq "0" || $pdata eq "0")) {
                if ($data eq "0") {
                    my $sdata = $session->set(new SNMP::Varbind([$dsavingstatus_oid, $slot, "1" ,'INTEGER']));
                    unless ($sdata) { return (1,$session->{ErrorStr}); }

                    my $ndata=$session->get([$dsavingstatus_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    if ($ndata ne "1") {
                        return (1, "Set operation failed.");
                    }
                }

                if ($pdata eq "0") {
                    my $sdata = $session->set(new SNMP::Varbind([$dsperformance_oid, $slot, "1" ,'INTEGER']));
                    unless ($sdata) { return (1,$session->{ErrorStr}); }

                    my $ndata=$session->get([$dsperformance_oid.".".$slot]);
                    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
                    if ($ndata ne "1") {
                        return (1, "Set operation failed.");
                    }
                }
            }
        } else {
            return (1, "$item is NOT a valid attribute..");
        }

        push @output, "$item: Set operation succeeded.";
    }

    return (0, @output);
}


# the mib object of complex table
my $comp_table_oid = ".1.3.6.1.4.1.2.3.51.2.24.1";    #scalableComplexTable
my $comppart_table_oid = ".1.3.6.1.4.1.2.3.51.2.24.2";    #scalableComplexPartitionTable
my $compnode_table_oid = ".1.3.6.1.4.1.2.3.51.2.24.3";    #scalableComplexNodeTable

# the mib object used for flexnode management
my $comp_id_oid = ".1.3.6.1.4.1.2.3.51.2.24.1.1.1";    #scalableComplexIdentifier
my $comp_part_num_oid = ".1.3.6.1.4.1.2.3.51.2.24.1.1.2";    #scalableComplexNumPartitions
my $comp_node_num_oid = ".1.3.6.1.4.1.2.3.51.2.24.1.1.3";    #scalableComplexNumNodes

# following two oid are used for create partition
my $comp_node_start_oid = ".1.3.6.1.4.1.2.3.51.2.24.1.1.4";    #scalableComplexPartStartSlot
my $comp_partnode_num_oid = ".1.3.6.1.4.1.2.3.51.2.24.1.1.5";    #scalableComplexPartNumNodes

# operate for the partition
my $comp_action_oid = ".1.3.6.1.4.1.2.3.51.2.24.1.1.6";    #scalableComplexAction


# oid for complex partitions
my $comp_part_comp_id_oid = ".1.3.6.1.4.1.2.3.51.2.24.2.1.1";   #scalableComplexId
my $comp_part_mode_oid = ".1.3.6.1.4.1.2.3.51.2.24.2.1.3";    #scalableComplexPartitionMode
my $comp_part_nodenum_oid = ".1.3.6.1.4.1.2.3.51.2.24.2.1.4";   #scalableComplexPartitionNumNodes
my $comp_part_status_oid = ".1.3.6.1.4.1.2.3.51.2.24.2.1.5";    #scalableComplexPartitionStatus
my $comp_part_action_oid = ".1.3.6.1.4.1.2.3.51.2.24.2.1.6";    #scalableComplexPartitionAction


#oid for complex nodes
my $comp_node_slot_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.1";    #scalableComplexNodeSlot
my $comp_node_type_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.3";    #scalableComplexNodeType
my $comp_node_res_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.4";    #scalableComplexNodeResources
my $comp_node_role_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.5";    #scalableComplexNodeRole
my $comp_node_state_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.6";    #scalableComplexNodeState
my $comp_node_cid_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.10";    #scalableComplexNodeComplexID
my $comp_node_pid_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.11";    #scalableComplexNodePartitionID
my $comp_node_lid_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.12";    #scalableComplexNodeLogicalID
my $comp_node_action_oid = ".1.3.6.1.4.1.2.3.51.2.24.3.1.14";    #scalableComplexNodeAction

my %compdata = ();

# get all the attributes for a specified complex
sub getcomplex {
    my ($complex_id) = @_;

    my $oid = $comp_part_num_oid.".$complex_id";
    my $data = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'Partition number'} = $data;

    $oid = $comp_node_num_oid.".$complex_id";
    $data = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'Complex node number'} = $data;
}

# get all the attributes for a partition which belong a certain complex
sub getcomppart {
    my ($complex_id, $part_id) = @_;

    my $oid = $comp_part_mode_oid.".$complex_id".".$part_id";
    my $data = $session->get([$oid]);
    if ($data == 1) {
        $data = "partition";
    } elsif ($data == 2) {
        $data = "standalone";
    }
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'Partition Mode'} = $data;

    $oid = $comp_part_nodenum_oid.".$complex_id".".$part_id";
    $data = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'Partition node number'} = $data;

    $oid = $comp_part_status_oid.".$complex_id".".$part_id";
    $data = $session->get([$oid]);
    if ($data == 1) {
        $data = "poweredoff";
    } elsif ($data == 2) {
        $data = "poweredon";
    } elsif ($data == 3) {
        $data = "resetting";
    } else {
        $data = "invalid";
    }
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'Partition status'} = $data;
}

# get all the attributes for a node in a complex
sub getcomnode {
    my ($node_id) = @_;

    my $oid = $comp_node_lid_oid.".$node_id";
    my $node_logic_id = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    $oid = $comp_node_cid_oid.".$node_id";
    my $complex_id = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    $oid = $comp_node_pid_oid.".$node_id";
    my $part_id = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    $oid = $comp_node_slot_oid.".$node_id";
    my $slot_id = $session->get([$oid]);

    if($part_id == 255) {
        $part_id = "unassigned";
        $node_logic_id = $slot_id;
    }

    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_logic_id}{'Node slot'} = $slot_id;

    $oid = $comp_node_type_oid.".$node_id";
    my $data = $session->get([$oid]);
    if ($data == 1) {
        $data = "processor";
    } elsif ($data == 2) {
        $data = "memory";
    } elsif ($data == 3) {
        $data = "io";
    }
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_logic_id}{'Node type'} = $data;

    $oid = $comp_node_res_oid.".$node_id";
    my $data = $session->get([$oid]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_logic_id}{'Node resource'} = $data;

    $oid = $comp_node_role_oid.".$node_id";
    my $data = $session->get([$oid]);
    if ($data == 1) {
        $data = "primary";
    } elsif ($data == 2) {
        $data = "secondary";
    } else {
        $data = "unassigned";
    } 
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_logic_id}{'Node role'} = $data;

    $oid = $comp_node_state_oid.".$node_id";
    my $data = $session->get([$oid]);
    if ($data == 1) {
        $data = "poweredoff";
    } elsif ($data == 2) {
        $data = "poweredon";
    } elsif ($data == 3) {
        $data = "resetting";
    }
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    $compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_logic_id}{'Node state'} = $data;

    return ($complex_id, $part_id, $node_logic_id);
}

# display the flexnodes for amm
sub lsflexnode {
    my ($mpa, $node, $slot, @moreslot) = @_;

    my @output = ();
    %compdata = ();
    
    # if specify the mpa as node, then list all the complex, partition and node in this chassis
    if ($node eq $mpa) {
      my @attrs = ($comp_id_oid);
      while (1) {
        my $orig_oid = $attrs[0];
        $session->getnext(\@attrs);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

        # if success of getnext, the @attrs will be set to (obj,iid,val,type)
        my $complex_obj = $attrs[0];
        my $complex_id = $attrs[1];
        if ($orig_oid =~ /^$complex_obj/) {
          &getcomplex($complex_id);

          # search all the partitions in the complex
          my @part_attrs = ($comp_part_comp_id_oid.".$complex_id");
          while (1) {
            my $orig_part_oid = $part_attrs[0];
            $session->getnext(\@part_attrs);
            if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

            my $part_obj = $part_attrs[0];
            my $part_id = $part_attrs[1];
            if ($orig_part_oid =~ /^$part_obj/) {
              &getcomppart($complex_id, $part_id);

            } else {
              last;
            }

            @part_attrs = ($part_obj.".$part_id");
          } # end of searching partition

        } else {
          last;
        }

        @attrs = ($complex_obj.".$complex_id");
      } # end of searching complex

      # search all the nodes in the complex
      my @node_attrs = ($comp_node_slot_oid);
      while (1) {
        my $orig_node_oid = $node_attrs[0];
        $session->getnext(\@node_attrs);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

        my $node_obj = $node_attrs[0];
        my $node_id = $node_attrs[1];
        if ($orig_node_oid =~ /^$node_obj/) {
          &getcomnode($node_id);
        } else {
          last;
        }

        @node_attrs = ($node_obj.".$node_id");
      }

      # display complex, parition and nodes in a chassis
      foreach my $comp (keys %compdata) {
        push @output, "Complex - $comp";
      
        foreach my $compattr (keys %{$compdata{$comp}}) {
          if ($compattr ne "partition") {
            push @output, "..$compattr - $compdata{$comp}{$compattr}";
          } else {
            foreach my $part (sort(keys %{$compdata{$comp}{'partition'}})) {
              push @output, "..Partition = $part";
              foreach my $partattr (keys %{$compdata{$comp}{'partition'}{$part}}) {
                if ($partattr ne "node") {
                  push @output, "....$partattr - $compdata{$comp}{'partition'}{$part}{$partattr}";
                } else {
                  foreach my $node (sort(keys %{$compdata{$comp}{'partition'}{$part}{'node'}})) {
                    if ($node eq "unassigned") {
                      push @output, "....Node - $node (slot id)";
                    } else {
                      push @output, "....Node - $node (logic id)";
                    }
                    foreach my $nodeattr (keys %{$compdata{$comp}{'partition'}{$part}{'node'}{$node}}) {
                      push @output, "......$nodeattr - $compdata{$comp}{'partition'}{$part}{'node'}{$node}{$nodeattr}";
                    }
                  } #end of node go ghrough
                }
              } #end of partition attributes
            } #end of parition go through
          }
        } #end of complex attributes
      } #end of complex go through

    } else { # display the information of a node
      my @slots = ($slot, @moreslot);
      my @sortslots = sort(@slots);
      foreach (0..$#sortslots-1) {
        if ($sortslots[$_]+1 != $sortslots[$_+1]) {
          return (1, "The slots used to create flexed node should be consecutive.");
        }
      }

      #get the slot information
      my $complex_flag = "";
      my $part_flag = "";
      foreach my $slot (@sortslots) {
        my ($complex_id, $part_id, $node_id) = &getcomnode($slot);
        if ($complex_id eq "NOSUCHINSTANCE") {
          return (1, "This node should belong to a complex.");
        }
        if ($complex_flag ne "" && $complex_flag ne $complex_id) {
          return (1, "All the slots of this flexnode should be located in one complex.");
        } else {
          $complex_flag = $complex_id;
        }
        if ($part_flag ne "" && $part_flag ne $part_id) {
          return (1, "All the slots of this flexnode should belong to one parition.");
        } else {
          $part_flag = $part_id;
        }

        if ($slot eq $sortslots[0]) {
          my $oid = $comp_part_status_oid.".$complex_id".".$part_id";
          my $data = $session->get([$oid]);
          if ($data == 1) {
              $data = "poweredoff";
          } elsif ($data == 2) {
              $data = "poweredon";
          } elsif ($data == 3) {
              $data = "resetting";
          } else {
              $data = "invalid";
          }
          if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
          push @output, "Flexnode state - $data";
          push @output, "Complex id - $complex_id";
          push @output, "Partition id - $part_id";
        }
        foreach my $nodeattr (keys %{$compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_id}}) {
          push @output, "Slot$slot: $nodeattr - $compdata{$complex_id}{'partition'}{$part_id}{'node'}{$node_id}{$nodeattr}";
        }
      }
    }

    return (0, @output);
}

# Create a flexnode
sub mkflexnode {
    my ($mpa, $node, $slot, @moreslot) = @_;

    my @slots = ($slot, @moreslot);

    # the slots assigned for a partition must be consecutive
    my @sortslots =  sort(@slots);
    foreach (0..$#sortslots-1) {
        if ($sortslots[$_]+1 != $sortslots[$_+1]) {
            return (1, "The slots used to create flexed node should be consecutive.");
        }
    }

    # get the status of all the nodes
    my $complex_id = "";
    foreach my $slot (@sortslots) {
        #get the complex of the node
        my $oid = $comp_node_cid_oid.".$slot";
        my $node_comp = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_comp eq 'NOSUCHINSTANCE') {
            return (1, "The slot [$slot] is NOT a member of a complex.");
        }

        # all the nodes should be located in one complex
        if ($complex_id ne "" && $node_comp ne $complex_id) {
            return (1, "All the slots of this flexnode should be located in one complex.");
        } else {
            $complex_id = $node_comp;
        }

        $oid = $comp_node_pid_oid.".$slot";
        my $node_part = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_part ne '255') {
            return (1, "The slot [$slot] has been assigned to one partition.");
        }

        $oid = $comp_node_state_oid.".$slot";
        my $node_state = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_state != 1) {  # 1 is power off
            return (1, "The slot [$slot] is NOT in power off state.");
        }
    }

    # set the startslot
    my $startslot = @sortslots[0];
    $session->set(new SNMP::Varbind([$comp_node_start_oid, $complex_id, $startslot, 'INTEGER']));
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    # set the slot number
    my $slotnum = $#sortslots+1;
    $session->set(new SNMP::Varbind([$comp_partnode_num_oid, $complex_id, $slotnum, 'INTEGER']));
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    # create the partition
    $session->set(new SNMP::Varbind([$comp_action_oid, $complex_id, 3, 'INTEGER']));
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    # check to make sure the parition has been created
    my $waiting = 60;  #waiting time before creating parition take affect
    while ($waiting > 0) {
        sleep 1;
        my $oid = $comp_node_pid_oid.".$slot";
        my $node_part = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_part ne '255') {
            my $slotlist = join(',', @slots);
            return (0, "Creating flexed node succeeded with slots: $slotlist.");
        }
        $waiting--;
    }

    return (1, "Failed to create the flexnode.");
}

# remove a flexnode
sub rmflexnode {
    my ($mpa, $node, $slot, @moreslot) = @_;

    my @slots = ($slot, @moreslot);

    # get the status of all the nodes
    my $complex_id = "";
    my $part_id = "";
    foreach my $slot (@slots) {
        #get the complex of the node
        my $oid = $comp_node_cid_oid.".$slot";
        my $node_comp = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_comp eq 'NOSUCHINSTANCE') {
            return (1, "The slot [$slot] is NOT a member of one complex.");
        }

        # all the nodes should be located in one complex
        if ($complex_id ne "" && $node_comp ne $complex_id) {
            return (1, "All the slots of this node should be located in one complex.");
        } else {
            $complex_id = $node_comp;
        }

        # get the partition of the node
        $oid = $comp_node_pid_oid.".$slot";
        my $node_part = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_part eq '255') {
            return (1, "The slot [$slot] was NOT assigned to a partition.");
        }

        # all the nodes should belong to one parition
        if ($part_id ne "" && $node_part ne $part_id) {
            return (1, "All the slots of this flexnode should belong to one parition.");
        } else {
            $part_id = $node_part;
        }

        $oid = $comp_node_state_oid.".$slot";
        my $node_state = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($node_state != 1) {  # 1 is power off
            return (1, "The slot [$slot] is NOT in power off state.");
        }
    }

    my $output = $session->set(new SNMP::Varbind([$comp_part_action_oid.".$complex_id", $part_id, 1, 'INTEGER']));
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }

    # check to make sure the parition has been deleted
    my $waiting = 60;  #waiting time before delete parition take affect
    while ($waiting > 0) {
        sleep 1;
        my $oid = $comp_part_comp_id_oid.".$complex_id".".$part_id";
        my $part_comp = $session->get([$oid]);
        if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
        if ($part_comp eq 'NOSUCHINSTANCE') {
            return (0, "The flexnode has been removed successfully."); 
        } 
        $waiting--;
    }
    return (1, "Failed to remove the flexnode.");
}

sub bladecmd {
  $mpa = shift;
  my $node = shift;
  $currnode = $node;
  $slot = shift;
  if ($slot =~ /-/) {
      $slot =~ s/-(.*)//;
      @moreslots = ($slot+1..$1);
  } else {
      @moreslots = ();
  }
  my $user = shift;
  my $pass = shift;
  my $command = shift;
  my @args = @_;
  my $error;

  if ($slot > 0 and not $slot =~ /:/) {
    my $tmp = $session->get([$bladexistsoid.".$slot"]);
    if ($session->{ErrorStr}) { return (1,$session->{ErrorStr}); }
    unless ($tmp eq 1) { return (1,"Target bay empty"); }
  }
  if ($command eq "rbeacon") {
    return beacon(@args);
  } elsif ($command eq "rpower") {
    return power(@args);
  } elsif ($command eq "rvitals") {
    my ($rc, @result) = vitals(@args);
    if (defined($vitals_info) and defined($vitals_info->{$currnode})) {
        my $attr = $vitals_info->{$currnode};
        my $fsp_api = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api";
        my $cmd = "$fsp_api -a pblade_query_lcds -T 0 -t 0:$$attr[3]:$$attr[0]:$currnode: 2>&1";
        my $res = xCAT::Utils->runcmd($cmd, -1);
        if ($res !~ /error/i) {
            my @array = split(/\n/, $res);
            foreach my $a (@array) {
                my ($name,$data) = split(/:/, $a);
                if ($data =~ /1\|(\w[\w\s]*)/) {
                    push @result, "Current LCD: $1";
                } else {
                    push @result, "Current LCD: blank";
                }
            }
        }
    }
    return ($rc, @result);
    #return vitals(@args);
  } elsif ($command =~ /r[ms]preset/) {
    return resetmp(@args);
  } elsif ($command eq "rspconfig") {
    return mpaconfig($mpa,$user,$pass,$node,$slot,@args);
  } elsif ($command eq "rbootseq") {
    return bootseq(@args);
  } elsif ($command eq "switchblade") {
     return switchblade(@args);
  } elsif ($command eq "getmacs") {
    return getmacs($node, @args);
  } elsif ($command eq "rinv") {
    return inv(@args);
  } elsif ($command eq "reventlog") {
    return eventlog(@args);
  } elsif ($command eq "rscan") {
    return rscan(\@args);
  } elsif ($command eq "renergy") {
    return renergy($mpa, $node, $slot, @args);
  } elsif ($command eq "lsflexnode") {
    return lsflexnode($mpa, $node, $slot, @moreslots);
  } elsif ($command eq "mkflexnode") {
    return mkflexnode($mpa, $node, $slot, @moreslots);
  } elsif ($command eq "rmflexnode") {
    return rmflexnode($mpa, $node, $slot, @moreslots);
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
       my $prefix="http://";
       my $url="http://$mpa/shared/userlogin.php";
       $browser = LWP::UserAgent->new;
       $browser->cookie_jar({});
       my $response = $browser->post("$prefix$mpa/shared/userlogin.php",{userid=>$user,password=>$pass,login=>"Log In"});
       if ($response->{_rc} eq '301') { #returned when https is enabled
           $prefix="https://";
           $response = $browser->post("$prefix$mpa/shared/userlogin.php",{userid=>$user,password=>$pass,login=>"Log In"});
       }
       $response = $browser->post("$prefix$mpa/shared/welcome.php",{timeout=>1,save=>""});
       unless ($response->{_rc} =~ /^2.*/) { 
           $response = $browser->post("$prefix$mpa/shared/welcomeright.php",{timeout=>1,save=>""});
       }
       unless ($response->{_rc} =~ /^2.*/) { 
           return undef;
       }
       return $prefix;

}
sub get_kvm_params {
    my $mpa = shift;
    my $method=shift;
    my $response = $browser->get("$method$mpa/private/vnc_only.php");
    my $html = $response->{_content};
    my $destip;
    my $rbs;
    my $fwrev;
    my $port;
    foreach (split /\n/,$html) {
        if (/<param\s+name\s*=\s*"([^"]*)"\s+value\s*=\s*"([^"]*)"/) {
           if ($1 eq 'ip') {
               $destip=$2;
           } elsif ($1 eq 'rbs') {
                $rbs = $2;
           } elsif ($1 eq 'cdl') {
               $fwrev=$2;
           }
        }
    }
    my $ba;
    unless (defined $destip and defined $rbs) { #Try another way
        $response = $browser->get("$method$mpa/private/remotecontrol.js.php");
        if ($response->{_rc} == 404) { #In some firmwares, its "shared" instead of private
            $response = $browser->get("$method$mpa/shared/remotecontrol.js.php");
        }
        $html = $response->{_content};
        foreach (split /\n/,$html) {
            if (/<param\s+name\s*=\s*"?([^"]*)"?\s+value\s*=\s*"?([^"]*)"?/i) {
               if ($1 eq 'ip') {
                   $destip=$2;
               } elsif ($1 eq 'rbs') {
                    $rbs = $2;
               #} elsif ($1 eq 'ba') {
               #    $ba=$2; #NOTE: This is the username and password.  The client seems to required it for this version of firmware, not exporting for SECURITY
               } elsif ($1 eq 'cdl') {
                   $fwrev=$2;
               } elsif ($1 eq 'port') {
                   $port=$2;
               }

            }
        }
    }
    return ($destip,$rbs,$fwrev,$port,$ba);
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
          if (defined($checkedmpas{$ent->{mpa}}) or not defined $mpatab) {
            if (defined($mpausers{$ent->{mpa}})) {
                $rsp->{node}->[0]->{username}=[$mpausers{$ent->{mpa}}];
            } else {
                $rsp->{node}->[0]->{username}=[$user];
            }
          } else {
              $checkedmpas{$ent->{mpa}}=1;
              ($tmp)=$mpatab->getNodeAttribs($ent->{mpa}, ['username']);
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
          $rsp->{node}->[0]->{slot}=[$ent->{id}];
      } else { 
          $rsp->{node}->[0]->{slot}=[""];
      }
      $callback->($rsp);
   }
}

sub preprocess_request { 
  my $request = shift;
  #if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
  
  if ($request->{_xcatpreprocessed}->[0] == 1 ) { return [$request]; }
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

  #parse the arguments for commands
  if ($command eq "getmacs") {
    my (@mpnodes, @nohandle);
    xCAT::Utils->filter_nodes($request, \@mpnodes, undef, undef, \@nohandle);
    if (@nohandle) {
        $callback->({data=>"Cannot figure out plugin for nodes:@nohandle"});
    }
    if (@mpnodes) {
      $noderange = \@mpnodes;
      my @args = @exargs;
      while (@args) {
          my $arg = shift @args;
          if ($arg =~ /^-V|--verbose|-d|--arp$/) {
              next;
          } elsif ($arg =~ /^-i$/) {
              my $int = shift @args;
              if (defined($int) && $int =~ /^(eth|en)\d$/) {
                  next;
              }
          } elsif ($arg eq '') {
              next;
          }
          $usage_string= ":Error arguments\n";
          $usage_string .=xCAT::Usage->getUsage($command);
          $callback->({data=>$usage_string});
          $request = {};
          return;         
      }
    } else {
      $request = {};
      return;
    }
  } elsif ($command eq "renergy") {
    if (! @exargs) {
        $usage_string="Missing arguments\n";
        $usage_string .=xCAT::Usage->getUsage($command);
        $callback->({data=>$usage_string});
        $request = {};
        return;
    }
    my (@mpnodes, @nohandle);
    xCAT::Utils->filter_nodes($request, \@mpnodes, undef, undef, \@nohandle);
    if (@nohandle) {
        $callback->({data=>"Error: Cannot figure out plugin for nodes:@nohandle"});
    }
    if (@mpnodes) {
      $noderange = \@mpnodes;
    } else {
      $request = {};
      return;
    }
  } elsif ($command =~  /^(rspconfig|rvitals)$/) {
    # All the nodes with mgt=blade or mgt=fsp will get here
    # filter out the nodes for blade.pm 
    my (@mpnodes, @nohandle);
    xCAT::Utils->filter_nodes($request, \@mpnodes, undef, undef, \@nohandle);
    if (@nohandle) {
        $callback->({data=>"Cannot figure out plugin for nodes:@nohandle"});
    }
    if (@mpnodes) {
      $noderange = \@mpnodes;
    } else {
      $request = {};
      return;
    }
  }

  if (!$noderange) {
    $usage_string="Missing Noderange\n";
    $usage_string .=xCAT::Usage->getUsage($command);
    $callback->({error=>[$usage_string],errorcode=>[1]});
    $request = {};
    return;
  }   
  
  #get the MMs for the nodes in order to figure out which service nodes to send the requests to
  my $mptab = xCAT::Table->new("mp");
  unless ($mptab) { 
    $callback->({data=>["Cannot open mp table"]});
    $request = {};
    return;
  }
  my %mpa_hash=();
  my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id','nodetype']);
  if ($request->{command}->[0] eq "getbladecons") { #Can handle it here and now
      getbladecons($noderange,$callback);
      return [];
  }

  my %mpatype = ();
  foreach my $node (@$noderange) {
    my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
    my $mpaent;
    if (defined($ent->{mpa})) { 
        push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;
        unless ($mpatype{$ent->{mpa}}) {
            my $mpaent = $mptab->getNodeAttribs($ent->{mpa},['nodetype']);
            if ($mpaent && $mpaent->{'nodetype'}) {
                $mpatype{$ent->{mpa}} = $mpaent->{'nodetype'};
            }
        }
    } elsif ($indiscover) {
	next;
    } else {
        $callback->({data=>["no mpa defined for node $node"]});
        $request = {};
        return;
    }
    if (defined($ent->{id})) { push @{$mpa_hash{$ent->{mpa}}{ids}}, $ent->{id};}
    else { push @{$mpa_hash{$ent->{mpa}}{ids}}, "";} 
    if (defined($mpatype{$ent->{mpa}})) { push @{$mpa_hash{$ent->{mpa}}{nodetype}}, $mpatype{$ent->{mpa}};}
    else { push @{$mpa_hash{$ent->{mpa}}{nodetype}}, "mm";}
  }

  # find service nodes for the MMs
  # build an individual request for each service node
  my $service  = "xcat";
  my @mms=keys(%mpa_hash);
  my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@mms, $service, "MN");

  # build each request for each service node
  foreach my $snkey (keys %$sn)
  {
    #print "snkey=$snkey\n";
    my $reqcopy = {%$request};
    $reqcopy->{'_xcatdest'} = $snkey;
    $reqcopy->{_xcatpreprocessed}->[0] = 1; 
    my $mms1=$sn->{$snkey};
    my @moreinfo=();
    my @nodes=();
    foreach (@$mms1) { 
      push @nodes, @{$mpa_hash{$_}{nodes}};
      push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]\[" . join(',',@{$mpa_hash{$_}{nodetype}}) . "\]";
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
  unless ($noderange) { return []; }
  my $mptab = xCAT::Table->new("mp");
  my @moreinfo=();
  unless ($mptab) { 
    $callback->({data=>["Cannot open mp table"]});
    return @moreinfo;
  }
  my %mpa_hash=();
  my $mptabhash = $mptab->getNodesAttribs($noderange,['mpa','id','nodetype']);

  my %mpatype = ();
  foreach my $node (@$noderange) {
    my $ent=$mptabhash->{$node}->[0]; #$mptab->getNodeAttribs($node,['mpa', 'id']);
    if (defined($ent->{mpa})) { 
        push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;
        unless ($mpatype{$ent->{mpa}}) {
            my $mpaent = $mptab->getNodeAttribs($ent->{mpa},['nodetype']);
            if ($mpaent && $mpaent->{'nodetype'}) {
                $mpatype{$ent->{mpa}} = $mpaent->{'nodetype'};
            }
        }
    } else {
        $callback->({data=>["no mpa defined for node $node"]});
        return @moreinfo;;
    }
    if (defined($ent->{id})) { push @{$mpa_hash{$ent->{mpa}}{ids}}, $ent->{id};}
    else { push @{$mpa_hash{$ent->{mpa}}{ids}}, "";} 
    if (defined($mpatype{$ent->{mpa}})) { push @{$mpa_hash{$ent->{mpa}}{nodetype}}, $mpatype{$ent->{mpa}};}
    else { push @{$mpa_hash{$ent->{mpa}}{nodetype}}, "mm";} 
  }

  foreach (keys %mpa_hash) {
    push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]\[" . join(',',@{$mpa_hash{$_}{nodetype}}) . "\]";
  }

  return \@moreinfo;
}

sub verbose_message {
    my $data = shift;
    if (!defined($CALLBACK) or !defined($verbose_cmd))  {
        return;   
    }
    my ($sec,$min,$hour,$mday,$mon,$yr,$wday,$yday,$dst) = localtime(time);
    my $time = sprintf "%04d%02d%02d.%02d:%02d:%02d", $yr+1900,$mon+1,$mday,$hour,$min,$sec;
    $data = "$time ($$) $verbose_cmd:".$data; 
    my %rsp;
    $rsp{data} = [$data];
    xCAT::MsgUtils->message("I", \%rsp, $CALLBACK); 
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
  # Since switch.pm and lsslp.pm both create a MacMap object (which requires SNMP), SNMP is still required at xcatd start up.
  # So do not bother trying to do this require in an eval.
  #eval { 
      require SNMP;
  #};
  #if ($@) { $callback->{error=>['Missing SNMP perl support'],errorcode=>[1]};  return; }

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
  $CALLBACK = $callback;
  if (grep /-V|--verbose/, @exargs) {
      $verbose_cmd = $command;
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
      $callback->({error=>["Single node required when changing textid"],
                   errorcode=>1});
      return;
    }
  }
  my $bladeuser = 'USERID';
  my $bladepass = 'PASSW0RD';
  my $blademaxp = 64;
  #my $sitetab = xCAT::Table->new('site');
  my $mpatab = xCAT::Table->new('mpa');
  my $mptab = xCAT::Table->new('mp');
  my $tmp;
  my @entries =  xCAT::TableUtils->get_site_attribute("blademaxp");
  my $site_entry = $entries[0];
  if(defined($site_entry)) {
      $blademaxp = $site_entry;
  }
  #if ($sitetab) {
  #  ($tmp)=$sitetab->getAttribs({'key'=>'blademaxp'},'value');
  #  if (defined($tmp)) { $blademaxp=$tmp->{value}; }
  #}
  if ($request->{environment}->[0]->{XCAT_BLADEUSER}) {
      $bladeuser=$request->{environment}->[0]->{XCAT_BLADEUSER}->[0];
      $bladepass=$request->{environment}->[0]->{XCAT_BLADEPASS}->[0];
  } else {
    my $passtab = xCAT::Table->new('passwd');
    if ($passtab) {
        ($tmp)=$passtab->getAttribs({'key'=>'blade'},'username','password');
        if (defined($tmp)) {
          $bladeuser = $tmp->{username};
          $bladepass = $tmp->{password};
        }
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
    $invreq{arg} = ['mac,uuid'];
    $invreq{command} = ['rinv'];
    my $mac;
    my $ip = $request->{'_xcat_clientip'};
    my $arptable;
    if ( -x "/usr/sbin/arp" ) {
        $arptable = `/usr/sbin/arp -n`;
    }
    else{
        $arptable = `/sbin/arp -n`;
    }
    my @arpents = split /\n/,$arptable;
    foreach  (@arpents) {
      if (m/^($ip)\s+\S+\s+(\S+)\s/) {
        $mac=$2;
        last;
      }
    }

    #Only refresh the the cache when the request permits and no useful answer
    if ($macmaptimestamp < (time() - 300)) { #after five minutes, invalidate cache
       %macmap = ();
    }
    
    unless ($request->{cacheonly}->[0] or $macmap{$mac} or $macmaptimestamp > (time() - 20)) { #do not refresh cache if requested not to, if it has an entry, or is recent
      %macmap = ();
      $macmaptimestamp=time();
      $indiscover=1;
      my $reqs = preprocess_request(\%invreq,\&fillresps);
      my @reql;
      if ($reqs) { @reql = @{$reqs}; }
      foreach (@reql) {
         %invreq = %$_;
         process_request(\%invreq,\&fillresps);
      }
      $indiscover=0;
    }
    my $found=0;
    if ($mac and $macmap{$mac}) { 
        $found=1;
    } else {
        foreach (@{$request->{mac}}) {
           /.*\|.*\|([\dABCDEFabcdef:]+)(\||$)/;
           if ($1 and $macmap{$1}) {
               $mac = $1; #the mac of consequence is identified here
               $found=1;
               last;
           }
        }
    }
    my $node;
    if ($found) {
       $node = $macmap{$mac};
    } else {
       my $ruid;
       foreach $ruid (@{$request->{uuid}}) {
         my $uuid = uc($ruid);
         if ($uuid and $uuidmap{$uuid}) {
            $node = $uuidmap{$uuid};
            last;
         }
         $uuid =~ s/(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
         if ($uuid and $uuidmap{$uuid}) {
            $node = $uuidmap{$uuid};
            last;
         }
       }
    }
    unless ($node) {
      return 1; #failure
    }
    if ($request->{mtm} and $request->{mtm} =~ /^(\w{4})/) {
        my $group = xCAT::data::ibmhwtypes::parse_group($request->{mtm});
        if (defined($group)) {
            xCAT::TableUtils->updatenodegroups($node, $group); 
        }
    }
    if ($mac) {
       my $mactab = xCAT::Table->new('mac',-create=>1);
       $mactab->setNodeAttribs($macmap{$mac},{mac=>$mac});
       $mactab->close();
       undef $mactab;
    }

    #my %request = (
    #  command => ['makedhcp'],
    #  node => [$macmap{$mac}]
    #  );
    #$doreq->(\%request);
    $request->{command}=['discovered'];
    $request->{noderange} = [$node];
    $request->{discoverymethod} = ['blade'];
    $doreq->($request);
    %{$request}=(); #Clear request. it is done
    return 0;
  }


  my $children = 0;
  $SIG{CHLD} = sub { my $cpid; while (($cpid = waitpid(-1, WNOHANG)) > 0) { if ($mm_comm_pids{$cpid}) { delete $mm_comm_pids{$cpid}; $children--; } } };
  my $inputs = new IO::Select;;
  foreach my $info (@$moreinfo) {
    $info=~/^\[(.*)\]\[(.*)\]\[(.*)\]\[(.*)\]/;
    ## TRACE_LINE print "Target info: node [$2], mpa [$1], slotid [$3], mptype [$4].\n";
    my $mpa=$1;
    my @nodes=split(',', $2);
    my @ids=split(',', $3);
    my @mptypes=split(',', $4);
    my $user=$bladeuser;
    my $pass=$bladepass;
    my $ent;
    if (defined($mpatab)) {
      my @user_array = $mpatab->getNodeAttribs($mpa, qw(username password));
      foreach my $entry (@user_array) {
          if ($entry->{username}) {
              if ($entry->{username} =~ /^USERID$/) {
                  $ent = $entry;
                  last;
              }
          }
      } 
      if (defined($ent->{password})) { $pass = $ent->{password}; }
      if (defined($ent->{username})) { $user = $ent->{username}; }
    }
    $mpahash{$mpa}->{username} = $user;
    $mpahash{$mpa}->{password} = $pass;
    my $nodehmtab  = xCAT::Table->new('nodehm');
    my $hmdata = $nodehmtab->getNodesAttribs(\@nodes, ['node', 'mgt']);
    for (my $i=0; $i<@nodes; $i++) {
      my $node=$nodes[$i];;
      my $nodeid=$ids[$i];
      $mpahash{$mpa}->{nodes}->{$node}=$nodeid;
      my $mptype=$mptypes[$i];
      $mpahash{$mpa}->{nodetype}->{$node}=$mptype;
        my $tmp1 = $hmdata->{$node}->[0];
        if ($tmp1){
            if ($tmp1->{mgt} =~ /ipmi/) {
                $mpahash{$mpa}->{ipminodes}->{$node}=$nodeid;
            
            }
        }
        
    }
  }
  my @mpas = (keys %mpahash);
  my $mpatypes = $mptab->getNodesAttribs(\@mpas, ['nodetype']);
  my $sub_fds = new IO::Select;
  foreach $mpa (sort (keys %mpahash)) {
    if (defined($mpatypes->{$mpa}->[0]->{'nodetype'})) {
        $mpahash{$mpa}->{mpatype} =$mpatypes->{$mpa}->[0]->{'nodetype'};
    }
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
      eval {
        dompa($pfd,$mpa,\%mpahash,$command,-args=>\@exargs);
        exit(0);
      };
      if ($@) { die "$@"; }
      die "blade plugin encountered a general error while communication with $mpa";
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

sub clicmds {

  my $mpa=shift;
  my $user=shift;
  my $pass=shift;
  my $node=shift;
  my $nodeid=shift;
  my %args=@_;
  my $ipmiflag = 0;
  $ipmiflag = 1 if ($node =~ s/--ipmi//);
  my $value;
  my @unhandled;
  my %handled = ();
  my $result;
  my @tcmds = qw(snmpcfg sshcfg network swnet pd1 pd2 textid network_reset rscanfsp initnetwork solcfg userpassword USERID updateBMC);
  verbose_message("start deal with $mptype CLI options:@{$args{cmds}}.");
  # most of these commands should be able to be done
  # through SNMP, but they produce various errors.
  foreach my $cmd (@{$args{cmds}}) {
    if ($cmd =~ /^swnet|pd1|pd2|sshcfg|rscanfsp|USERID|userpassword|updateBMC|=/) {
      if (($cmd =~ /^textid/) and ($nodeid > 0)) {
        push @unhandled,$cmd;
        next;
      }
      my ($command,$value) = split /=/,$cmd,2;

      #$command =~ /^swnet/) allows for swnet1, swnet2, etc.
      if (grep(/^$command$/,@tcmds) || $command =~ /^swnet/) {
        $handled{$command} = $value;
        next;
      }
    }
    if ($cmd =~ /-V|--verbose/) {
        next;
    }
    push @unhandled,$cmd;
  }

  # the option 'updateBMC' and 'USERID' can only work together when specified value for 'updateBMC', otherwise we shall only run 'rspconfig cmm updateBMC' to update BMC passwords associate with this cmm.
  if (defined($handled{updateBMC}) and !($handled{USERID})) {
      push @cfgtext, "'updateBMC' mush work with 'USERID'";
      return([1, \@unhandled, ""]);
  } 
  if (exists($handled{updateBMC}) and !defined($handled{updateBMC}) and $handled{USERID}) {
      push @cfgtext, "No value specified for 'updateBMC'";
      return([1, \@unhandled, ""]);
  }
  unless (%handled) {
    verbose_message("no option needed to be handled with $mptype CLI.");
    return([0,\@unhandled]);
  }
  my $curruser = $user;
  my $currpass = $pass;
  my $nokeycheck=0; #default to checking ssh key
  if ($args{defaultcfg}) {
    $curruser="USERID";
    $currpass = "PASSW0RD";
    $nokeycheck=1;
  } else {
	if ($args{curruser}) { $curruser = $args{curruser}; $nokeycheck=1; }
	if ($args{currpass}) { $currpass = $args{currpass}; $nokeycheck=1; }
  }
	
  if ($args{nokeycheck}) {
    $nokeycheck=1;
  }
  my $promote_pass = $pass; #used for genesis state processing
  my $curraddr = $mpa;
  if ($args{curraddr}) {
	$curraddr = $args{curraddr};
  } elsif (defined($handled{'initnetwork'}) or defined($handled{'USERID'})) {
    # get the IP of mpa from the hosts.otherinterfaces
    my $hoststab = xCAT::Table->new('hosts');
    if ($hoststab) {
      my $hostdata = $hoststab->getNodeAttribs($node, ['otherinterfaces']);
      if (!$hostdata->{'otherinterfaces'}) {
         if (!defined($handled{'USERID'})) {
             push @cfgtext, "Cannot find the temporary IP from the hosts.otherinterfaces";
             return ([1,\@unhandled,""]);
         }
      } else {
      	$curraddr = $hostdata->{'otherinterfaces'};
      }
    }
  } 
  require xCAT::SSHInteract;
  my $t;
  verbose_message("start SSH mpa:$mpa session for node:$node.");
  eval {
  $t = new  xCAT::SSHInteract(
		-username=>$curruser,
		-password=>$currpass,
		-host=>$curraddr,
		-nokeycheck=>$nokeycheck,
		-output_record_separator=>"\r",
                Timeout=>15, 
                Errmode=>'return',
                Prompt=>'/system> $/'
		);
  };
  my $errmsg=$@;
  if ($errmsg) {
        if ($errmsg =~ /Known_hosts issue/) {
            $errmsg = "The entry for $mpa in known_hosts table is out of date, pls run 'makeknownhosts $mpa -r' to delete it from known_hosts table.";
           push @cfgtext, $errmsg;
           return([1, \@unhandled, $errmsg]);
        }
	if ($errmsg =~ /Login Failed/) {
	    $errmsg = "Failed to login to $mpa";
	    if ($curraddr ne $mpa) { $errmsg .= " (currently at $curraddr)" }
        push @cfgtext,$errmsg;
	    return([1,\@unhandled,$errmsg]);
    } else { 
        push @cfgtext, $errmsg;
        return([1,\@unhandled,$errmsg]);
        #die $@; 
    }
  }
  my $Rc=1;
  if ($t and not $t->atprompt) { #we sshed in, but we may be forced to deal with initial password set
	my $output = $t->get();
	if ($output =~ /Enter current password/) {
        if (defined($handled{USERID})) {
            $promote_pass = $handled{USERID};
        }
                verbose_message("deal with genesis state for mpa:$mpa.");
		$t->print($currpass);
		$t->waitfor(-match=>"/password:/i");
		$t->print($promote_pass);
		$t->waitfor(-match=>"/password:/i");
		$t->print($promote_pass);
		my $result=$t->getline();
		chomp($result);
		$result =~ s/\s*//;
		while ($result eq "") {
			$result = $t->getline();
			$result =~ s/\s*//;
		}
		if ($result =~ /not compliant/) {
                        push @cfgtext,"The current account password has expired, please modify it first";
         		return ([1,\@unhandled,"Management module refuses requested password as insufficiently secure, try another password"]);
		}
  		$t->waitfor(match=>"/system> /");
		$t->cmd("accseccfg -rc 0 -pe 0 -pi 0 -ct 0 -lp 0 -lf 0 -T system:mm[1]");
  		$t->waitfor(match=>"/system> /");
		$t->cmd("accseccfg -rc 0 -pe 0 -pi 0 -ct 0 -lp 0 -lf 0 -T system:mm[2]");
	}
  	$t->waitfor(match=>"/system> /");
  } elsif (not $t) {#ssh failed.. fallback to a telnet attempt for older AMMs with telnet disabled by default
     verbose_message("start telnet mpa:$curraddr session for node:$node.");
     require Net::Telnet;
     $t = new Net::Telnet(
                   Timeout=>15, 
                   Errmode=>'return',
                   Prompt=>'/system> $/'
     );
     $Rc = $t->open($curraddr);
     if ($Rc) {
       $Rc = $t->login($user,$pass); 
     }
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

  my $reset;
  my $cmm_modified = 0;
  my $bmc_modified = 0;
  foreach (keys %handled) {
    if (/^snmpcfg/)     { $result = snmpcfg($t,$handled{$_},$user,$pass,$mm); }
    elsif (/^sshcfg$/)  { $result = sshcfg($t,$handled{$_},$user,$mm); }
    elsif (/^network$/) { $node .= "--ipmi" if($ipmiflag); $result = network($t,$handled{$_},$mpa,$mm,$node,$nodeid); $node =~ s/--ipmi//; }
    elsif (/^initnetwork$/) { $result = network($t,$handled{$_},$mpa,$mm,$node,$nodeid,1); $reset=1; }
    elsif (/^swnet/)   { $result = swnet($t,$_,$handled{$_}); }
    elsif (/^pd1|pd2$/) { $result = pd($t,$_,$handled{$_}); }
    elsif (/^textid$/)  { $result = mmtextid($t,$mpa,$handled{$_},$mm); }
    elsif (/^rscanfsp$/)  { $result = rscanfsp($t,$mpa,$handled{$_},$mm); }
    elsif (/^solcfg$/)  { $result = solcfg($t,$handled{$_},$mm); }
    elsif (/^network_reset$/) { $result = network($t,$handled{$_},$mpa,$mm,$node,$nodeid,1); $reset=1; }
    elsif (/^(USERID)$/ and !$cmm_modified) {$result = passwd($t, $mpa, $1, "=".$handled{$_}, $promote_pass, $mm); $cmm_modified = 1;}
    elsif (/^userpassword$/) {$result = passwd($t, $mpa, $1, $handled{$_}, $promote_pass, $mm);}
    if((/^updateBMC$/ or ($cmm_modified)) and !($bmc_modified)) {
        unless (defined($handled{updateBMC}) and $handled{updateBMC} =~ /(0|n|no)/i) {
        if (defined($handled{updateBMC}) and !$cmm_modified) {
            $result = passwd($t, $mpa, "USERID", "=".$handled{USERID}, $promote_pass, $mm);
            $cmm_modified = 1;
        }
        verbose_message("start update password for all BMCs.");
        my $start = Time::HiRes::gettimeofday();
        updateBMC($mpa,$user,$handled{USERID});
        verbose_message("Finish update password for all BMCs.");
        my $slp = Time::HiRes::gettimeofday() - $start;
        my $msg = sprintf("The main process time slp: %.3f sec", $slp);
        verbose_message($msg);
        }
        $bmc_modified = 1;
    }
    if (!defined($result)) {next;}
    push @data, "$_: @$result";
    if (/^initnetwork$/) {
        if (!@$result[0]) {
            my $hoststab = xCAT::Table->new('hosts');
            if ($hoststab)  {
                $hoststab->setNodeAttribs($mpa, {otherinterfaces=>''});
            }       
        }
    }
    $Rc |= shift(@$result);
    push @cfgtext,@$result;
  }
  # dealing with SNMP v3 disable in genesis state#
  if ($promote_pass ne $pass) {
    snmpcfg($t, 'disable', $user, $promote_pass, $mm);
  }
  if ($reset) {
    $t->cmd("reset -T system:$mm");
    push @data, "The management module has been reset to load the configuration";
  } 
  $t->close;
  verbose_message("finished SSH mpa:$curraddr session for node:$node.");
  return([$Rc,\@unhandled,\@data]);
}

# Enable/Disable the sol against the mm and blades
# The target node is mm, but all the blade servers belongs to this mm will be 
# handled implicated
sub solcfg {
  my $t = shift;
  my $value = shift;
  my $mm = shift;

  if ($value !~ /^enable|disable$/i) {
    return([1,"Invalid argument '$value' (enable|disable)"]); 
  }

  my $setval;
  if ($value eq "enable") {
    $setval = "enabled";
  } else {
    $setval = "disabled";
  }

  my @output;
  my $rc = 0;
  my @data = $t->cmd("sol -status $setval -T system:$mm");
  if (grep (/OK/, @data)) {
    push @output, "$value: succeeded on $mm";
  } else {
    push @output, "$value: failed on $mm";
    $rc = 1;
  }

  # Get the component list
  my @data = $t->cmd("list -l 2");
  foreach (@data) {
    if (/^\s*(blade\[\d+\])\s+/) {
      my @ret = $t->cmd("sol -status $setval -T $1");
      if (grep (/OK/, @ret)) {
        push @output, "$value: succeeded on $1";
      } else {
        push @output, "$value: failed on $1";
        $rc = 1;
      }
    }
  }

  return ([$rc, @output]); 
}

sub load_x222_info {
    my $t = shift;
    my $id_flag = undef;
    my $id_start;
    my $id_sub;
    my @id_array = ();
    my @data = $t->cmd("list -l 3");
    ## find out the x222 nodes
    foreach (@data) {
        if (/^(\s*)(bladegroup\[\d+\])\s*/) {
            $id_flag = $1;
            $id_start = $2;
            $id_sub = undef;
        } elsif (/^(\s*)(blade\[\d+\])\s*/) {
            if (defined($id_flag) and $id_flag ne $1) {
                $id_sub = $id_start.":$2";
            } else {
                $id_flag = undef;
                $id_sub = undef;
                next;
            }
        } else {
            next;
        }
        if (defined($id_sub)) {
            push @id_array, $id_sub;
        }
    }
    foreach (@id_array) {
        my $node = $_;
        @data = $t->cmd("info -T system:$node");
        my $node_name = $node;
        foreach (@data) {
            if (/^Name:\s/) {
                if (/^Name:\s*(.*)\s\(\s*(.*)\s\).*$/) {
                    if (grep (/ /, $2)) {
                        $node_name = $1;
                    } else {
                        $node_name = $2;
                    }
                } elsif (/^Name:\s*(.*)\s*$/) {
                    $node_name = $1;
                }
                $node_name =~ s/ /_/;
                $node_name =~ tr/A-Z/a-z/;
                $x222_info{$node}{node_name}=$node_name;
            } elsif (/^Mach type\/model: (\w+)/) {
                $x222_info{$node}{mtm} = $1;
            } elsif (/^Mach serial number: (\w+)/) {
                $x222_info{$node}{serial} = $1;
            } elsif (/(Product Name: IBM Flex System p)|(Mach type\/model:.*PPC)|(Mach type\/model: pITE)|(Mach type\/model: IBM Flex System p)|(Firebird)/) {
                $x222_info{$node}{type} = "ppcblade";
            } elsif (/(Product Name: IBM Flex System x)|(Device Description: HX)/) {
                $x222_info{$node}{type} = "xblade";
            } elsif (/^MAC Address (\d+):\s*(\w+:\w+:\w+:\w+:\w+:\w+)/) {
                my $macid = "mac$1";
                my $mac = $2;
                $mac =~ tr/A-Z/a-z/;
                $x222_info{$node}{$macid} = $mac;
            } elsif (/^Slots: (\d+:\d+|\d+)/) {
                $x222_info{$node}{slotid} = $1;
            }
        }
        @data = $t->cmd("ifconfig -T system:$node");
        my $side = undef;
        foreach (@data) {
            if (/eth(\d+)/) {
                $side = $1;
            }
            if (defined($side) && /-i (\d+.\d+.\d+.\d+)/) {
                $x222_info{$node}{$side}{side} = $side;
                $x222_info{$node}{$side}{ip} = $1;
            }
        }
        $has_x222 = '1';        
    }
    return ;
}

# Scan the fsp for the NGP ppc nodes
sub rscanfsp {
  my $t = shift;
  my $mpa = shift;
  my $value = shift;
  my $mm = shift;

  my @blade;
  # Get the component list
  my @data = $t->cmd("list -l 2");
  if (grep /bladegroup/, @data) {
      &load_x222_info($t);
  }
  foreach (@data) {
    if (/^\s*(blade\[\d+\])\s+/) {
      push @blade, $1;
    }
    if (/(mm\[\d+\])\s+primary/) {
      # get the type of mm
      @data = $t->cmd("info -T system:$1");
      if (grep /(Mach type\/model: Chassis Management Module)|(Mach type\/model: CMM)|(Product Name:.*Chassis Management Module)/, @data) {
        $telnetrscan{'mm'}{'type'} = "cmm";
      }
    }
  }

  # Get the interface side of fsp
  # mm[1] -> eth1; mm[2] -> eth0;
  my $ifside;
  if ($mm =~ /\[(\d)\]/) {
    if ($1 eq "1") {
      $ifside = "1";
    } elsif ($1 eq "2") {
      $ifside = "0";
    } else {
      $ifside = $1;
    }
  }
  # for fsp
  foreach (@blade) {
    /blade\[(\d+)\]/;
    my $id = $1;
    # get the hardware type, only get the fsp for PPC blade
    @data = $t->cmd("info -T system:$_");
    if (! grep /(Product Name: IBM Flex System p)|(Mach type\/model:.*PPC)|(Mach type\/model: pITE)|(Mach type\/model: IBM Flex System p)|(Firebird)/, @data) {
      next;
    }
    @data = $t->cmd("ifconfig -T system:$_");
    my $side;
    foreach (@data) {
      if (/eth(\d)/) {
        if ($1 eq $ifside) {
          $side = $1;
          $telnetrscan{$id}{$side}{'side'} = $side;
          $telnetrscan{$id}{$side}{'type'} = "fsp";
        } else {
          undef $side;
        }
      }
      if (/-i (\d+\.\d+\.\d+\.\d+)/ && defined($side)) {
        $telnetrscan{$id}{$side}{'ip'} = $1;
        ## TRACE_LINE print "rscanfsp found: blade[$id] - ip [$telnetrscan{$id}{$side}{'ip'}], type [$telnetrscan{$id}{$side}{'type'}], side [$telnetrscan{$id}{$side}{'side'}].\n";
      }
    }
  }
  # for bmc
  foreach (@blade) {
    /blade\[(\d+)\]/;
    my $id = $1;
    # get the hardware type, only get the fsp for PPC blade
    @data = $t->cmd("info -T system:$_");
    if ((! grep /(Product Name: IBM Flex System x)/, @data) and (! grep /Device Description: HX/, @data)){
      next;
    }
    @data = $t->cmd("ifconfig -T system:$_");
    my $side = "0";
    foreach (@data) {
        if (/eth(\d)/) {
              $telnetrscan{$id}{$side}{'side'} = $side;
              $telnetrscan{$id}{$side}{'type'} = "bmc";
        }
        if (/-i (\d+\.\d+\.\d+\.\d+)/ && defined($side)) {
          $telnetrscan{$id}{$side}{'ip'} = $1;
          ## TRACE_LINE print "rscanfsp found: blade[$id] - ip [$telnetrscan{$id}{$side}{'ip'}], type [$telnetrscan{$id}{$side}{'type'}], side [$telnetrscan{$id}{$side}{'side'}].\n";
        }
    }
  }
  return [0];
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
  my @data = $t->cmd("config -name \"$value\" -T system"); #on cmms, this identifier is frequently relevant...
  return undef; #([0,"textid: $value"]);
}

sub get_blades_for_mpa {
  my $mpa = shift;
  my %blades_hash = ();
  my $mptab = xCAT::Table->new('mp');
  my $ppctab = xCAT::Table->new('ppc');
  my @attribs = qw(id nodetype parent hcp);
  if (!defined($mptab) or !defined($ppctab)) {
    return undef;
  }
  my @nodearray = $mptab->getAttribs({mpa=>$mpa}, qw(node));
  my @blades = ();
  my $nodesattrs;
  if (!(@nodearray)) {
    return (\%blades_hash);
  } else {
      foreach (@nodearray) {
          if (defined($_->{node})) {
              push @blades, $_->{node};
          }
      }
      $nodesattrs = $ppctab->getNodesAttribs(\@blades, \@attribs);
  }
  foreach my $node (@blades) {
      my @values = ();
      my $att = $nodesattrs->{$node}->[0];
      if (!defined($att)) {
          next;
      } elsif (!defined($att->{parent}) or ($att->{parent} ne $mpa) or !defined($att->{nodetype}) or ($att->{nodetype} ne "blade")) {
          next;
      }
      my $request;
      my $hcp_ip = xCAT::FSPUtils::getIPaddress($request, $att->{nodetype}, $att->{hcp});
      if (!defined($hcp_ip) or ($hcp_ip == -3)) {
          next;
      }
      push @values, $att->{id};
      push @values, '0';
      push @values, '0';
      push @values, $hcp_ip;
      push @values, "blade";
      push @values, $mpa;
      $blades_hash{$node} = \@values; 
      verbose_message("values for node:$node, value:@values.");
  }
  return (\%blades_hash);
}

sub updateBMC {
    my $mpa = shift;
    my $user = shift;
    my $pass = shift;
    my @nodes = ();
    my $mptab = xCAT::Table->new('mp');
    if ($mptab) {
        my @mpents = $mptab->getAllNodeAttribs(['node','mpa','id']);
        foreach (@mpents) {
            my $node = $_->{node};
            if (defined($_->{mpa}) and ($_->{mpa} eq $mpa) and defined($_->{id}) and ($_->{id} ne '0')) {
                push @nodes, $node;
            }
        }
    }
    my $ipmitab = xCAT::Table->new('ipmi');
    if ($ipmitab) {
        my $ipmihash = $ipmitab->getNodesAttribs(\@nodes, ['bmc']);
        foreach (@nodes) {
            if (defined($ipmihash->{$_}->[0]) && defined ($ipmihash->{$_}->[0]->{'bmc'})) {
                xCAT::IMMUtils::setupIMM($_,curraddr=>$ipmihash->{$_}->[0]->{'bmc'},skipbmcidcheck=>1,skipnetconfig=>1,cliusername=>$user,clipassword=>$pass,callback=>$CALLBACK);
            }  
        }
    }
    return ;
}

sub passwd {
  my $t = shift;
  my $mpa = shift;
  my $user = shift;
  my $pass = shift;
  my $oldpass = shift;
  my $mm = shift;
  if ($pass =~ /^=/) {
	$pass=~ s/=//;
  } elsif ($pass =~ /=/) {
	($user,$pass) = split /=/,$pass;
  }
	
  if (!$pass) {
    return ([1, "No param specified for '$user'"]);
  }
  my $mpatab = xCAT::Table->new('mpa');
  if ($mpatab) {
    my ($ent)=$mpatab->getAttribs({mpa=>$mpa, username=>$user},qw(password));
    #my $oldpass = 'PASSW0RD';
    #if (defined($ent->{password})) {$oldpass = $ent->{password}};
    my @data = ();
    if ($oldpass ne $pass) {
        my $cmd = "users -n $user -op $oldpass -p $pass -T system:$mm";
        my @data = $t->cmd($cmd);
        if (!grep(/OK/i, @data)) {
            return ([1, @data]);
        }
    }
    @data = ();
    my $snmp_cmd = "users -n $user -ap sha -pp des -ppw $pass -T system:$mm";
    @data = $t->cmd($snmp_cmd);
    if (!grep(/ok/i, @data)) {
        my $cmd = "users -n $user -op $pass -p $oldpass -T system:$mm";
        my @back_pwd = $t->cmd($cmd);
        if (!grep(/OK/i, @back_pwd)) {
            $mpatab->setAttribs({mpa=>$mpa,username=>$user},{password=>$pass});
        }
        return ([1, @data]);
    }
    
    $mpatab->setAttribs({mpa=>$mpa,username=>$user},{password=>$pass});
    if ($user eq "USERID") {
        my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api";
        my $blades = &get_blades_for_mpa($mpa);
        if (!defined($blades)) {
            return ([1, "Find blades failed for $mpa"]);
        }
        my @failed_blades = ();
        foreach (keys %$blades) {
            my $node_name = $_;
            my $att = $blades->{$node_name};
            my $con_cmd = "$fsp_api -a query_connection -T 0 -t 0:$$att[3]:$$att[0]:$node_name: 2>&1";
            #print "===>query_con_cmd=$con_cmd\n";
            my $res = xCAT::Utils->runcmd($con_cmd, -1);
            if ($res =~ /No connection information found/i) {
                next;  #we don't need to update password for FSPs that havn't created DFM links#
            } elsif ($res =~ /The hdwr_svr daemon is not currently running/i) {
                return ([1, "Update password for 'hdwr_svr' failed because the 'hdwr_svr' daemon is not currently running. Please recreate the connections between blades and hdwr_svr."]);
            }
            my $hws_cmd = "$fsp_api -a reset_hws_pw -u HMC -p $oldpass -P $pass -T 0 -t 0:$$att[3]:$$att[0]:$node_name: 2>&1";
            #print "===>set_hws_cmd=$hws_cmd\n";

            $res = xCAT::Utils->runcmd($hws_cmd, -1);
            if ($res =~ /Error/i) {
                push @failed_blades, $node_name;
            }  
        }
        if (scalar(@failed_blades)) {
            my $fblades = join (',',@failed_blades);
            return ([1, "Update password of HMC for '$fblades' failed. Please recreate the DFM connections for them."]);
        }
    } else {
	#TODO: add new user if name mismatches what MM alread understands..
	#additionally, may have to delete USERID in this event
    }
  } else {
    return ([1, "Update password for $user in 'mpa' table failed"]);
  }
  return ([0, "Succeeded"]);
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
  my $mm = shift;
  my $node = shift;
  my $slot = shift;
  my $reset = shift;

  my $ipmiflag = 0;
  $ipmiflag = 1 if ($node =~ s/--ipmi//);
  my $cmd;
  if ($mpa eq $node) {
    # The network setting for the mm
    $cmd = "ifconfig -eth0 -c static -r auto -d auto -m 1500 -T system:$mm";
  } else {
    # The network setting for the service processor of blade
    my @data = $t->cmd("ifconfig -T system:blade[$slot]");
    # get the active interface
    # MM[1] - FSP eth1 MM[2] - FSP eth0
    my $if;
    if ($mm =~ /\[(\d)\]/) {
      if($1 eq "1") {
        $if = "eth1";
      } elsif($1 eq "2") {
        $if = "eth0";
      } else {
        $if = "eth".$1;
      }
    } else {
      foreach (@data) {
        if (/eth(\d)/) { $if = "eth".$1; last;}
      }
    }
    if (!$if) {return ([1, "Cannot find the interface of blade."])};
    $cmd = "ifconfig -$if -c static -T system:blade[$slot]";
  }
  my ($ip,$host,$gateway,$mask);

  if ($value) {
    if ($value !~ /\*/) {
      ($ip,$host,$gateway,$mask) = split /,/,$value;
      if (!$ip and !$host and !$gateway and !$mask) {
        return([1,"No changes specified"]);
      }
      if ($mpa ne $node) {
          $host = undef;
      }
    }
    else {
      if ( $value !~ /^\*$/) {
        return([1,"Invalid format: 'network=*'"]);
      }
      if ($mpa eq $node) { #for network configure to management module
        my %nethash = xCAT::DBobjUtils->getNetwkInfo([$node]);
        my $gate = $nethash{$node}{gateway};
        my $result; 

        if ($gate) {
          $result = xCAT::NetworkUtils::toIP($gate);
          if (@$result[0] == 0) {
            $gateway = @$result[1];
          }
        }
        $mask = $nethash{$node}{mask};
        #the host is only needed for the mpa network configuration
        $host = $node;

        my $hosttab = xCAT::Table->new( 'hosts' );
        if ($hosttab) {
          my ($ent) = $hosttab->getNodeAttribs($node,['ip']);
          if (defined($ent)) {
            $ip = $ent->{ip};
          }
          $hosttab->close();
        }
	unless ($ip) {
		$ip = xCAT::NetworkUtils->getipaddr($node);
	}
      } else {
      
        if($ipmiflag) {
            my $ipmitab = xCAT::Table->new( 'ipmi' );
            if ($ipmitab) {
              my $bmcip = $ipmitab->getNodeAttribs($node,['bmc']);
              if (defined($bmcip)) {
                $ip = $bmcip->{bmc};
              }
            }
        } else {
            my $ppctab = xCAT::Table->new( 'ppc' );
            if ($ppctab) {
              my $ppcent = $ppctab->getNodeAttribs($node,['hcp']);
              if (defined($ppcent)) {
                $ip = $ppcent->{hcp};
              }
            }
        }
        my %nethash = xCAT::DBobjUtils->getNetwkInfo([$ip]);
        my $gate = $nethash{$ip}{gateway};
        my $result;

        if ($gate) {
          $result = xCAT::NetworkUtils::toIP($gate);
          if (@$result[0] == 0) {
            $gateway = @$result[1];
          }
        }
        $mask = $nethash{$ip}{mask};
      }
    }
  } else {
    return([1,"No changes specified"]);
  }

  if ($ip)     { $cmd.=" -i $ip"; }
  if ($host)   { $cmd.=" -n $host"; }
  if ($gateway){ $cmd.=" -g $gateway"; }
  if ($mask)   { $cmd.=" -s $mask"; }

  ## TRACE_LINE print "The cmd to set for the network = $cmd\n";
  my @data = $t->cmd($cmd);
  if (!@data) {
    return ([1,"Failed"]);
  }

  my @result = grep(/These configuration changes will become active/,@data);
  ## TRACE_LINE print "  rc = @data\n"; 
  if (!@result) {
    if (!(@result = grep (/OK/,@data))) {
      return([1,@data]);
    }
  } elsif (defined($reset)) {
    @result = ();
  }

  if ($ip)     { push @result,"IP: $ip"; }
  if ($host)   { push @result,"Hostname: $host"; }
  if ($gateway){ push @result,"Gateway: $gateway"; }
  if ($mask)   { push @result,"Subnet Mask: $mask"; }

  return([0,@result]);

}


sub swnet {

  my $t = shift;
  my $command = shift;
  my $value = shift;
  my @result;
  my ($ip,$gateway,$mask);

  #default is switch[1].  if the user specificed a number, use it instead
  my $switch = "switch[1]";
  if ($command !~ /^swnet$/) {
    my $switchNum = $command;
    $switchNum =~ s/swnet//;
    $switch = "switch[$switchNum]";
  }

  if (!$value) {
    my @data = $t->cmd("ifconfig -T system:$switch");
    my $s = join('',@data);
    if ($s =~ /-i\s+(\S+)/) { $ip = $1; }
    if ($s =~ /-g\s+(\S+)/) { $gateway = $1; }
    if ($s =~ /-s\s+(\S+)/) { $mask = $1; }
  }
  else {
    my $cmd =
       "ifconfig -em disabled -ep enabled -pip enabled -T system:$switch";
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
  # Check the type of mm
  my @data = $t->cmd("info -T system:$mm");
  if (grep(/: Chassis Management Module/, @data) && $mptype ne "cmm") {
    $mptype="cmm";
    #return ([1,"The hwtype attribute should be set to \'cmm\' for a Chassis Management Module."]);
  }
  # Query users on MM
  my $id;
  if ($mptype =~ /^[a]?mm$/) {
    @data = $t->cmd("users -T system:$mm");
    my ($user) = grep(/\d+\.\s+$uid/, @data);
    if (!$user) {
      return([1,"Cannot find user: '$uid' on MM"]);
    }
    $user =~ /^(\d+)./;
    $id = $1;
  } elsif ($mptype eq "cmm") {
    @data = $t->cmd("users -n $uid -T system:$mm");
    if (! grep (/Account is active/, @data)) {
      return([1,"Cannot find user: '$uid' on MM"]);
    }
  } else {
    return([1,"Hardware type [$mptype] is not supported. Valid types: mm,cmm."]);
  }

  my $pp  = ($value =~ /^enable$/i) ? "des" : "none";
  if ($pp eq "des") {
     @data = $t->cmd("snmp -a3 -on -T system:$mm");
  } else {
     @data = $t->cmd("snmp -a3 -off -T system:$mm");
  }

  my $cmd;
  if ($mptype =~ /^[a]?mm$/) {
    $cmd= "users -$id -ap sha -at write -ppw $pass -pp $pp -T system:$mm";
  } elsif ($mptype eq "cmm"){
    $cmd= "users -n $uid  -ap sha -at set -ppw $pass -pp $pp -T system:$mm";
  }
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

  # Check the type of mm
  @data = $t->cmd("info -T system:$mm");
  if (grep(/: Chassis Management Module/, @data) && $mptype ne "cmm") {
    #return ([1,"The hwtype attribute should be set to \'cmm\' for a Chassis Management Module."]);
    $mptype="cmm"; #why in the world wouldn't we have just done this from the get go????
  }

  # Get firmware version on MM
  if ($mptype =~ /^[a]?mm$/) {
    @data = $t->cmd("update -a -T system:$mm");
    my ($line) = grep(/Build ID:\s+\S+/, @data);

    # Minumum firmware version BPET32 required for SSH
    $line =~ /(\d.)/;
    if (hex($1) < hex(32)) {
      return([1,"SSH supported on AMM with minimum firmware BPET32"]);
    }
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
  my $user;
  @data = $t->cmd("users -T system:$mm");
  if ($mptype =~ /^[a]?mm$/) {
    ($user) = grep(/\d+\.\s+$uid/, @data);
  } elsif ($mptype eq "cmm") {
    my $getin;  # The userid is wrapped insied the lines with keywords 'Users' and 'User Permission Groups'
    foreach my $line (@data) {
      chomp($line);
      if ($line =~ /^Users$/) {
        $getin = 1;
      } elsif ($line =~ /^User Permission Groups$/) {
        last;
      }

      if ($getin) {
        if (($line =~ /^([^\s]+)$/) && ($uid eq $1)) {
          $user = $uid;
          last;
        }
      }
    }
  } 
  if (!$user) {
    return([1,"Cannot find user: '$uid' on MM"]);
  }
  $user =~ /^(\d+)./;
  my $id = $1;

  # Determine is key already exists on MM
  if ($mptype =~ /^[a]?mm$/) {
    @data = $t->cmd("users -$id -pk all -T system:$mm");
  } elsif ($mptype eq "cmm") {
    @data = $t->cmd("users -n $uid -ki all -T system:$mm");
  }

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
      if ($mptype =~ /^[a]?mm$/) {
        @data = $t->cmd("users -$id -pk -$key -remove -T system:$mm");
      } elsif ($mptype eq "cmm") {
        @data = $t->cmd("users -n $uid -remove -ki $key -T system:$mm");
      }
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
  if ($mptype =~ /^[a]?mm$/) {
    $t->cmd("users -$id -at set -T system:$mm");
    @data = $t->cmd("users -$id -pk -T system:$mm -add $sshkey");
  } elsif ($mptype eq "cmm") {
    chomp($sshkey);
    $t->cmd("users -n $uid -at set -T system:$mm");
    @data = $t->cmd("users -n $uid -add -kf openssh -T system:$mm -key \"$sshkey\"");
  }

  if ($data[0]=~/Error/i) {
    if ($data[0]=~/Error writing data for option -add/i) {
      return([1,"Maximum number of SSH keys reached for this chassis"]);
    }
    return([1,$data[0]]);
  } elsif (! grep /OK/, @data) {
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
    my $responses;
    eval {
    	$responses = fd_retrieve($rfh); 
    };
    if ($@ and $@ =~ /^Magic number checking on storable file/) { #this most likely means we ran over the end of available input
      $fds->remove($rfh);
      close($rfh);
    } else {
      eval { print $rfh "ACK\n"; }; #Ignore ack loss due to child giving up and exiting, we don't actually explicitly care about the acks
      foreach (@$responses) {
        $callback->($_);
      }
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
      my $method;
      unless ($method=httplogin($mpa,$user,$pass)) {
        foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
          my %outh;
          %outh = (
            node=>[{
                name=>[$node],
                error=>["Unable to perform http login to $mpa"],
                errorcode=>['3']
          }]);
	  store_fd([\%outh],$out);
          yield;
          waitforack($out);
           %outh=();
          }
          return;
      }
      (my $target, my $authtoken, my $fwrev, my $port, my $ba) = get_kvm_params($mpa,$method);
      #an http logoff would invalidate the KVM token, so we can't do it here
      #For the instant in time, banking on the http session timeout to cleanup for us
      #It may be possible to provide the session id to client so it can logoff when done, but
      #that would give full AMM access to the KVM client
      foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
          my $slot = $mpahash->{$mpa}->{nodes}->{$node};
          $slot =~ s/-.*//;
          my @output = ();
          push(@output,"method:blade");
          push(@output,"server:$target");
          push(@output,"authtoken:$authtoken");
          push(@output,"slot:$slot");
          push(@output,"fwrev:$fwrev");
          push(@output,"prefix:$method");
          if ($port) {
            push(@output,"port:$port");
          }
          #if ($ba) { #SECURITY: This exposes AMM credentials, use at own risk
          #  push(@output,"ba:$ba");
          #}
          my %outh;
          $outh{node}->[0]->{name}=[$node];
          $outh{node}->[0]->{data}=[];
          foreach (@output) {
              (my $tag, my $text)=split /:/,$_,2;
              push (@{$outh{node}->[0]->{data}},{desc=>[$tag],contents=>[$text]});
	      store_fd([\%outh],$out);
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
      my $slot = $mpahash->{$mpa}->{nodes}->{$node}; #this should preserve '-' in multi-blade configs
      my $user = $mpahash->{$mpa}->{username};
      my $pass = $mpahash->{$mpa}->{password};
      $mptype = $mpahash->{$mpa}->{nodetype}->{$node};
      my $rc;
      my $result;
      if ($mpa eq $node && $mptype && $mptype !~ /^mm|cmm$/) {
        push @cfgtext, "Hardware type $mptype is not supported. Valid types(mm,cmm).\n";
        $rc = 1;
        $args = [];
      } elsif ($mpa ne $node && grep /(updateBMC|USERID)/, @exargs) {
        push @cfgtext, "The option $1 only supported for the CMM";
        $rc = 1;
        $args = [];
      } else {
        my $ipmiflag = 0;
        if($mpahash->{$mpa}->{ipminodes}->{$node}) {$node .= "--ipmi";};
        $result = clicmds($mpa,$user,$pass,$node,$slot,cmds=>\@exargs);
        $node =~ s/--ipmi//;
        $rc |= @$result[0];
        $args = @$result[1];
      }

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
        # Don't use the {error} keyword to avoid the auto added 'Error'
        # in the output especially for part of the nodes failed.
        $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
        #if ($rc) {
        #    $output{node}->[0]->{error}->[0]=$text;
        #} else {
        #    $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
        #}
        
	store_fd([\%output],$out);
        yield;
        waitforack($out);
      }
    }
  }

  if ($command eq "rscan") {
    foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
      @cfgtext=();
      my $slot = $mpahash->{$mpa}->{nodes}->{$node}; #this should preserve '-' in multi-blade configs
      my $user = $mpahash->{$mpa}->{username};
      my $pass = $mpahash->{$mpa}->{password};
      $mptype = $mpahash->{$mpa}->{nodetype}->{$node};
      my $rc;
      my $result;
      if ($mptype eq "cmm") {
        # For the cmm, call the rscanfsp to discover the fsp for ppc blade
        my @telargs = ("rscanfsp");
        clicmds($mpa,$user,$pass,$node,$slot,cmds=>\@telargs);
      }
    }
  }
  # Only telnet commands
  unless ( @$args ) {
    if(($command ne "getmacs") && ($command ne "rbeacon")){
      return;
    }
  }
  verbose_message("start deal with SNMP session.");
  $mpauser= $mpahash->{$mpa}->{username};
  $mpapass = $mpahash->{$mpa}->{password};
  $session = new SNMP::Session(
                    DestHost => $mpa,
                    Version => '3',
                    SecName => $mpauser,
                    AuthProto => 'SHA',
                    AuthPass => $mpapass,
                    PrivProto => 'DES',
                    SecLevel => 'authPriv',
                    UseNumeric => 1,
                    Retries => 1, # Give up sooner to make commands go smoother
                    Timeout=>10000000, #Beacon, for one, takes a bit over a second to return
                    PrivPass => $mpapass);
  if ($session->{ErrorStr}) {return 1,$session->{ErrorStr}; }
  unless ($session and keys %$session) {
     my %err=(node=>[]);
     foreach (keys %{$mpahash{$mpa}->{nodes}}) {
        push (@{$err{node}},{name=>[$_],error=>["Cannot communicate with $mpa"],errorcode=>[1]});
     }
     store_fd([\%err],$out);
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
  my %oldnodestatus=(); #saves the old node status
  my @allerrornodes=();
  my $check=0;
  my $global_check=1;
  my @entries =  xCAT::TableUtils->get_site_attribute("nodestatus");
  my $site_entry = $entries[0];
  if(defined($site_entry)) {
      if ($site_entry =~ /0|n|N/) { $global_check=0; }
  }
  #my $sitetab = xCAT::Table->new('site');
  #if ($sitetab) {
  #  (my $ref) = $sitetab->getAttribs({key => 'nodestatus'}, 'value');
  #  if ($ref) {
  #     if ($ref->{value} =~ /0|n|N/) { $global_check=0; }
  #  }
  #}


  if ($command eq 'rpower') {
    if (($global_check) && ($args->[0]  ne 'stat') && ($args->[0]  ne 'status') && ($args->[0]  ne 'state')) { 
      $check=1; 
      my @allnodes=keys %{$mpahash->{$mpa}->{nodes}};

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
      if (($args->[0] eq 'off') || ($args->[0] eq 'softoff')) { 
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
	  }
        }
      }


      #donot update node provision status (installing or netbooting) here
      xCAT::Utils->filter_nostatusupdate(\%newnodestatus);
      #print "newstatus" . Dumper(\%newnodestatus);
      xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
    }
  }
  if ($command eq "rvitals") {
      if ((scalar(@$args) == 1 and $args->[0] eq '') or grep (/all/,@$args)) {
          $vitals_info = &get_blades_for_mpa($mpa);
      }
  }

  foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})) {
    $curn = $node;
    $mptype = $mpahash->{$mpa}->{nodetype}->{$node};
    $mpatype = $mpahash->{$mpa}->{mpatype};
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
    if (($check) && ($no_op)) {
	push(@allerrornodes, $node);
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
        if ($rc) {
            $output{node}->[0]->{error}->[0]=$text;
        } else {
            $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
        }
      }
      store_fd([\%output],$out);
      yield;
      waitforack($out);
    }
    yield;
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
  verbose_message("SNMP session completed.");
  #my $msgtoparent=freeze(\@outhashes); # = XMLout(\%output,RootName => 'xcatresponse');
  #print $out $msgtoparent; #$node.": $_\n";
}

##########################################################################
# generate hardware tree, called from lstree.
##########################################################################
sub genhwtree
{
    my $nodelist = shift;  # array ref
	my $callback = shift;
	my %hwtree;

    # get mm and bladeid
    my $mptab = xCAT::Table->new('mp');
    unless ($mptab)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Can not open mp table.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
    }

    my @entries = $mptab->getAllNodeAttribs(['node','mpa','id']);

    foreach my $node (@$nodelist)
    {

        # read mp.mpa, mp.id.
        my $mpent = $mptab->getNodeAttribs($node, ['mpa','id']);
        if ($mpent)
        {
            if ($mpent->{mpa} eq $node)
            {
                # it's mm, need to list all blades managed by this mm
                foreach my $ent (@entries)
                {
                    # need to exclude mm if needed.
                    if ($ent->{mpa} eq $ent->{node})
                    {
                        next;
                    }
                    elsif ($ent->{mpa} =~ /$node/)
                    {
                        $hwtree{$node}{$ent->{id}} = $ent->{node};
                    }
                }
            }
            else
            {
                # it's blade
                $hwtree{$mpent->{mpa}}{$mpent->{id}} = $node;
            }
        }    
    }

    return \%hwtree;    
}




    
1;















