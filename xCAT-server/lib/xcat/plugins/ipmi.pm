#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#egan@us.ibm.com
#modified by jbjohnso@us.ibm.com
#(C)IBM Corp

package xCAT_plugin::ipmi;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use xCAT::SPD qw/decode_spd/;
use xCAT::IPMI;
use xCAT::PasswordUtils;
my %needbladeinv;

use POSIX qw(ceil floor);
use Storable qw(nstore_fd retrieve_fd thaw freeze);
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::IMMUtils;
use xCAT::ServiceNodeUtils;
use xCAT::SvrUtils;
use xCAT::Usage;
use Thread qw(yield);
use LWP 5.64;
use HTTP::Request::Common;
my $iem_support;
my $vpdhash;
my %allerrornodes=();
my $global_sessdata;
require xCAT::data::ibmhwtypes;

eval {
    require IBM::EnergyManager;
    $iem_support=1;
};

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
	ipmicmd
);

sub handled_commands {
  return {
    rpower => 'nodehm:power,mgt', #done
    renergy => 'nodehm:power,mgt',
    getipmicons => 'ipmi', #done
    rspconfig => 'nodehm:mgt', #done
    rspreset => 'nodehm:mgt', #done
    rvitals => 'nodehm:mgt', #done
    rinv => 'nodehm:mgt', #done
    rflash => 'nodehm:mgt', #done
    rsetboot => 'nodehm:mgt', #done
    rbeacon => 'nodehm:mgt', #done
    reventlog => 'nodehm:mgt',
    ripmi => 'ipmi',
#    rfrurewrite => 'nodehm:mgt', #deferred, doesn't even work on several models, no one asks about it, keeping it commented for future requests
    getrvidparms => 'nodehm:mgt', #done
    rscan => 'nodehm:mgt', # used to scan the mic cards installed on the target node
  }
}

    
#use Data::Dumper;
use POSIX "WNOHANG";
use IO::Handle;
use IO::Socket;
use IO::Select;
use Class::Struct;
use Digest::MD5 qw(md5);
use POSIX qw(WNOHANG mkfifo strftime);
use Fcntl qw(:flock);


#local to module
my $callback;
my $ipmi_bmcipaddr;
my $timeout;
my $port;
my $debug;
my $ndebug = 0;
my $sock;
my $noclose;
my %sessiondata; #hold per session variables, in preparation for single-process strategy
my %pendingtransactions; #list of peers with callbacks, callback arguments, and timer expiry data
my $ipmiv2=0;
my $authoffset=0;
my $enable_cache="yes";
my $cache_dir = "/var/cache/xcat";
#my $ibmledtab = $ENV{XCATROOT}."/lib/GUMI/ibmleds.tab";
use xCAT::data::ibmleds;
use xCAT::data::ipmigenericevents;
use xCAT::data::ipmisensorevents;
my $cache_version = 4;
my %sdr_caches; #store sdr cachecs in memory indexed such that identical nodes do not hit the disk multiple times

#my $status_noop="XXXno-opXXX";

my %idpxthermprofiles = (
    '0z' => [0x37,0x41,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e],
    '1a' => [0x30,0x3c,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e], 
    '2b' => [0x30,0x3c,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e], 
    '3c' => [0x30,0x3c,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e], 
    '4d' => [0x37,0x44,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e], 
    '5e' => [0x37,0x44,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e], 
    '6f' => [0x35,0x44,0,0,0,0,5,0xa,0x3c,0xa,0xa,0x1e], 
);
my %codes = (
	0x00 => "Command Completed Normal",
	0xC0 => "Node busy, command could not be processed",
	0xC1 => "Invalid or unsupported command",
	0xC2 => "Command invalid for given LUN",
	0xC3 => "Timeout while processing command, response unavailable",
	0xC4 => "Out of space, could not execute command",
	0xC5 => "Reservation canceled or invalid reservation ID",
	0xC6 => "Request data truncated",
	0xC7 => "Request data length invalid",
	0xC8 => "Request data field length limit exceeded",
	0xC9 => "Parameter out of range",
	0xCA => "Cannot return number of requested data bytes",
	0xCB => "Requested Sensor, data, or record not present",
	0xCB => "Not present",
	0xCC => "Invalid data field in Request",
	0xCD => "Command illegal for specified sensor or record type",
	0xCE => "Command response could not be provided",
	0xCF => "Cannot execute duplicated request",
	0xD0 => "Command reqponse could not be provided. SDR Repository in update mode",
	0xD1 => "Command response could not be provided. Device in firmware update mode",
	0xD2 => "Command response could not be provided. BMC initialization or initialization agent in progress",
	0xD3 => "Destination unavailable",
	0xD4 => "Insufficient privilege level",
	0xD5 => "Command or request parameter(s) not supported in present state",
	0xFF => "Unspecified error",
);

#Payload types:
#  0 => IPMI  (format 1 0)
#  1 => SOL 1 0
#  0x10 => rmcp+ open req 1 0
#  0x11 => rmcp+ response 1 0
#  0x12 => rakp1 (all 1 0)
#  0x13 => rakp2
#  0x14 => rakp3
#  0x15 => rakp4
  
my %units = (
	0 => "", #"unspecified",
	1 => "C",
	2 => "F",
	3 => "K",
	4 => "Volts",
	5 => "Amps",
	6 => "Watts",
	7 => "Joules",
	8 => "Coulombs",
	9 => "VA",
	10 => "Nits",
	11 => "lumen",
	12 => "lux",
	13 => "Candela",
	14 => "kPa",
	15 => "PSI",
	16 => "Newton",
	17 => "CFM",
	18 => "RPM",
	19 => "Hz",
	20 => "microsecond",
	21 => "millisecond",
	22 => "second",
	23 => "minute",
	24 => "hour",
	25 => "day",
	26 => "week",
	27 => "mil",
	28 => "inches",
	29 => "feet",
	30 => "cu in",
	31 => "cu feet",
	32 => "mm",
	33 => "cm",
	34 => "m",
	35 => "cu cm",
	36 => "cu m",
	37 => "liters",
	38 => "fluid ounce",
	39 => "radians",
	40 => "steradians",
	41 => "revolutions",
	42 => "cycles",
	43 => "gravities",
	44 => "ounce",
	45 => "pound",
	46 => "ft-lb",
	47 => "oz-in",
	48 => "gauss",
	49 => "gilberts",
	50 => "henry",
	51 => "millihenry",
	52 => "farad",
	53 => "microfarad",
	54 => "ohms",
	55 => "siemens",
	56 => "mole",
	57 => "becquerel",
	58 => "PPM",
	59 => "reserved",
	60 => "Decibels",
	61 => "DbA",
	62 => "DbC",
	63 => "gray",
	64 => "sievert",
	65 => "color temp deg K",
	66 => "bit",
	67 => "kilobit",
	68 => "megabit",
	69 => "gigabit",
	70 => "byte",
	71 => "kilobyte",
	72 => "megabyte",
	73 => "gigabyte",
	74 => "word",
	75 => "dword",
	76 => "qword",
	77 => "line",
	78 => "hit",
	79 => "miss",
	80 => "retry",
	81 => "reset",
	82 => "overflow",
	83 => "underrun",
	84 => "collision",
	85 => "packets",
	86 => "messages",
	87 => "characters",
	88 => "error",
	89 => "correctable error",
	90 => "uncorrectable error",
);

my %chassis_types = (
	0 => "Unspecified",
	1 => "Other",
	2 => "Unknown",
	3 => "Desktop",
	4 => "Low Profile Desktop",
	5 => "Pizza Box",
	6 => "Mini Tower",
	7 => "Tower",
	8 => "Portable",
	9 => "LapTop",
	10 => "Notebook",
	11 => "Hand Held",
	12 => "Docking Station",
	13 => "All in One",
	14 => "Sub Notebook",
	15 => "Space-saving",
	16 => "Lunch Box",
	17 => "Main Server Chassis",
	18 => "Expansion Chassis",
	19 => "SubChassis",
	20 => "Bus Expansion Chassis",
	21 => "Peripheral Chassis",
	22 => "RAID Chassis",
	23 => "Rack Mount Chassis",
);

my %MFG_ID = (
	2 => "IBM",
	343 => "Intel",
	20301 => "IBM",
);

my %PROD_ID = (
	"2:34869" => "e325",
	"2:3" => "x346",
	"2:4" => "x336",
	"343:258" => "Tiger 2",
	"343:256" => "Tiger 4",
);

my $localtrys = 3;
my $localdebug = 0;

struct SDR => {
	rec_type			=> '$',
	sensor_owner_id		=> '$',
	sensor_owner_lun	=> '$',
	sensor_number		=> '$',
	entity_id			=> '$',
	entity_instance		=> '$',
	sensor_init			=> '$',
	sensor_cap			=> '$',
	sensor_type			=> '$',
	event_type_code		=> '$',
	ass_event_mask		=> '@',
	deass_event_mask	=> '@',
	dis_read_mask		=> '@',
	sensor_units_1		=> '$',
	sensor_units_2		=> '$',
	sensor_units_3		=> '$',
	linearization		=> '$',
	M					=> '$',
	tolerance			=> '$',
	B					=> '$',
	accuracy			=> '$',
	accuracy_exp		=> '$',
	R_exp				=> '$',
	B_exp				=> '$',
	analog_char_flag	=> '$',
	nominal_reading		=> '$',
	normal_max			=> '$',
	normal_min			=> '$',
	sensor_max_read		=> '$',
	sensor_min_read		=> '$',
	upper_nr_threshold	=> '$',
	upper_crit_thres	=> '$',
	upper_ncrit_thres	=> '$',
	lower_nr_threshold	=> '$',
	lower_crit_thres	=> '$',
	lower_ncrit_thres	=> '$',
	pos_threshold		=> '$',
	neg_threshold		=> '$',
	id_string_type		=> '$',
	id_string		=> '$',
	#LED id
	led_id		=> '$',
    fru_type  => '$',
    fru_subtype  => '$',
    fru_oem  => '$',
};

struct FRU => {
	rec_type			=> '$',
	desc				=> '$',
	value				=> '$',
};

sub decode_fru_locator { #Handle fru locator records
    my @locator = @_;
	my $sdr = SDR->new();
	$sdr->rec_type(0x11);
    $sdr->sensor_owner_id("FRU");
    $sdr->sensor_owner_lun("FRU");
    $sdr->sensor_number($locator[7]);
    unless ($locator[8] & 0x80 and ($locator[8] & 0x1f) == 0 and $locator[9] == 0) {
        #only logical devices at lun 0 supported for now
        return undef;
    }
    unless (($locator[16] & 0xc0) == 0xc0) { #Only unpacked ASCII for now, no unicode or BCD plus yet
        return undef;
    }
    my $idlen = $locator[16] & 0x3f;
    unless ($idlen > 1) { return undef; }
    $sdr->id_string(pack("C*",@locator[17..17+$idlen-1]));
    $sdr->fru_type($locator[11]);
    $sdr->fru_subtype($locator[12]);
    $sdr->fru_oem($locator[15]);

    return $sdr;
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
sub translate_sensor {
   my $reading = shift;
   my $sdr = shift;
   my $unitdesc;
   my $value;
   my $lformat;
   my $per;
   $unitdesc = $units{$sdr->sensor_units_2};
   if ($sdr->rec_type == 1) {
    $value = (($sdr->M * $reading) + ($sdr->B * (10**$sdr->B_exp))) * (10**$sdr->R_exp);
   } else {
    $value = $reading;
   }
   if($sdr->rec_type !=1 or $sdr->linearization == 0) {
      $reading = $value;
      if($value == int($value)) {
         $lformat = "%-30s%8d%-20s";
      } else {
         $lformat = "%-30s%8.3f%-20s";
      }
   } elsif($sdr->linearization == 7) {
      if($value > 0) {
         $reading = 1/$value;
      } else {
         $reading = 0;
      }
      $lformat = "%-30s%8d %-20s";
   } else {
      $reading = "RAW($sdr->linearization) $reading";
   }
   if($sdr->sensor_units_1 & 1) {
      $per = "% ";
   } else {
      $per = " ";
   }
   my $numformat = ($sdr->sensor_units_1 & 0b11000000) >> 6;
   if ($numformat) {
     if ($numformat eq 0b11)  {
        #Not sure what to do.. leave it alone for now
     } else {
        if ($reading & 0b10000000) {
          if ($numformat eq 0b01) {
             $reading = 0-((~($reading&0b01111111))&0b1111111);
          } elsif ($numformat eq 0b10) {
             $reading = 0-(((~($reading&0b01111111))&0b1111111)+1);
          }
        }
     }
   }
   if($unitdesc eq "Watts") {
      my $f = ($reading * 3.413);
      $unitdesc = "Watts (" . int($f + .5) . " BTUs/hr)";
      #$f = ($reading * 0.00134);
      #$unitdesc .= " $f horsepower)";
   }
   if($unitdesc eq "C") {
      my $f = ($reading * 9/5) + 32;
      $unitdesc = "C (" . int($f + .5) . " F)";
   }
   if($unitdesc eq "F") {
      my $c = ($reading - 32) * 5/9;
      $unitdesc = "F (" . int($c + .5) . " C)";
   }
   return "$reading $unitdesc";
}

sub ipmicmd {
    my $sessdata = shift;


	my $rc=0;
	my $text="";
	my $error="";
	my @output;
	my $noclose=0;

    $sessdata->{ipmisession}->login(callback=>\&on_bmc_connect,callback_args=>$sessdata);
}

sub on_bmc_connect {
    my $status = shift;
    my $sessdata = shift;
	my $command = $sessdata->{command};
    if ($status =~ /ERROR:/) {
        xCAT::SvrUtils::sendmsg([1,$status],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    #ok, detect some common prereqs here, notably:
    #getdevid
    if ($command eq "getrvidparms" or $command eq "rflash") {
        unless (defined $sessdata->{device_id}) {
            $sessdata->{ipmisession}->subcmd(netfn=>6,command=>1,data=>[],callback=>\&gotdevid,callback_args=>$sessdata);
	    return;
        }
        if ($command eq "getrvidparms") {
            getrvidparms($sessdata);
        } else {
            rflash($sessdata);
        }
    }
    #initsdr
    if ($command eq "rinv" or $command eq "reventlog" or $command eq "rvitals") {
        unless (defined $sessdata->{device_id}) {
            $sessdata->{ipmisession}->subcmd(netfn=>6,command=>1,data=>[],callback=>\&gotdevid,callback_args=>$sessdata);
            return;
        }
        unless ($sessdata->{sdr_hash}) {
            initsdr($sessdata);
	    return;
        }
    }
	if($command eq "ping") {
		xCAT::SvrUtils::sendmsg("ping",$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	if ($command eq "rpower") {
        	unless (defined $sessdata->{device_id}) { #need get device id data initted for S3 support
	            $sessdata->{ipmisession}->subcmd(netfn=>6,command=>1,data=>[],callback=>\&gotdevid,callback_args=>$sessdata);
		    return;
	        }
		return power($sessdata);
	} elsif ($command eq "ripmi") {
		return ripmi($sessdata);
	} elsif ($command eq "rspreset") {
        return resetbmc($sessdata);
    } elsif($command eq "rbeacon") {
		return beacon($sessdata);
	} elsif($command eq "rsetboot") {
		return setboot($sessdata);
	} elsif($command eq "rspconfig") {
       shift @{$sessdata->{extraargs}};
       if ($sessdata->{subcommand} =~ /=/) {
           setnetinfo($sessdata);
       } else {
           getnetinfo($sessdata);
       }
	} elsif($command eq "rvitals") {
        vitals($sessdata);
	} elsif($command eq "rinv") {
        inv($sessdata);
    } elsif($command eq "reventlog") {
        eventlog($sessdata);
    } elsif($command eq "renergy") {
        renergy($sessdata);
    }
    return;
    my @output;

    my $rc; #in for testing, evaluated as a TODO
    my $text;
    my $error;
    my $node;
	my $subcommand = "";
	if($command eq "rvitals") {
		($rc,@output) = vitals($subcommand);
	}
	elsif($command eq "renergy") {
		($rc,@output) = renergy($subcommand);
	}
	elsif($command eq "rspreset") {
		($rc,@output) = resetbmc();
		$noclose=1;
	}
	elsif($command eq "reventlog") {
		if($subcommand eq "decodealert") {
			($rc,$text) = decodealert(@_);
		}
		else {
			($rc,@output) = eventlog($subcommand);
		}
	}
	elsif($command eq "rinv") {
		($rc,@output) = inv($subcommand);
	}
	elsif($command eq "fru") {
		($rc,@output) = fru($subcommand);
	}
	elsif($command eq "rgetnetinfo") {
      my @subcommands = ($subcommand);
		if($subcommand eq "all") {
			@subcommands = (
				"ip",
				"netmask",
				"gateway",
				"backupgateway",
				"snmpdest1",
				"snmpdest2",
				"snmpdest3",
				"snmpdest4",
				"community",
				"textid",
			);

			my @coutput;

			foreach(@subcommands) {
				$subcommand = $_;
				($rc,@output) = getnetinfo($subcommand);
				push(@coutput,@output);
			}

			@output = @coutput;
		}
		else {
			($rc,@output) = getnetinfo($subcommand);
		}
	}
	elsif($command eq "generic") {
		($rc,@output) = generic($subcommand);
	}
	elsif($command eq "rfrurewrite") {
		($rc,@output) = writefru($subcommand,shift);
	}
	elsif($command eq "fru") {
		($rc,@output) = fru($subcommand);
	}
	elsif($command eq "rsetboot") {
        	($rc,@output) = setboot($subcommand);
	}

	else {
		$rc = 1;
		$text = "unsupported command $command $subcommand";
	}
	if($debug) {
		print "$node: command completed\n";
	}

	if($text) {
		push(@output,$text);
	}

	return($rc,@output);
}

sub resetbmc {
    my $sessdata = shift;
    $sessdata->{ipmisession}->subcmd(netfn=>6,command=>2,data=>[],callback=>\&resetedbmc,callback_args=>$sessdata);
}
sub resetedbmc {
    my $rsp = shift;
    my $sessdata = shift;
	if ($rsp->{error}) {
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
	} else {
        if ($rsp->{code}) {
            if ($codes{$rsp->{code}}) {
                xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
            } else {
                xCAT::SvrUtils::sendmsg([1,sprintf("Unknown error %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
            }
            return;
        } 
        xCAT::SvrUtils::sendmsg("BMC reset",$callback,$sessdata->{node},%allerrornodes);
        $sessdata->{ipmisession} = undef; #throw away now unusable session
	}
}

sub setnetinfo {
    my $sessdata = shift;
	my $subcommand = $sessdata->{subcommand};
   my $argument;
   ($subcommand,$argument) = split(/=/,$subcommand);
	my @input = @_;

	my $netfun = 0x0c;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;
	my $match;
    my $channel_number = $sessdata->{ipmisession}->{currentchannel};

	if($subcommand eq "snmpdest") {
		$subcommand = "snmpdest1";
	}
        

   unless(defined($argument)) { 
      return 0;
   }
   if ($subcommand eq "thermprofile") {
       return idpxthermprofile($argument);
   }
   if ($subcommand eq "alert" and $argument eq "on" or $argument =~ /^en/ or $argument =~ /^enable/) {
      $netfun = 0x4;
      @cmd = (0x12,0x9,0x1,0x18,0x11,0x00);
   } elsif ($subcommand eq "alert" and $argument eq "off" or $argument =~ /^dis/ or $argument =~ /^disable/) {
      $netfun = 0x4;
      @cmd = (0x12,0x9,0x1,0x10,0x11,0x00);
   }
	elsif($subcommand eq "garp") {
		my $halfsec = $argument * 2; #pop(@input) * 2;

		if($halfsec > 255) {
			$halfsec = 255;
		}
		if($halfsec < 4) {
			$halfsec = 4;
		}

		@cmd = (0x01,$channel_number,0x0b,$halfsec);
	}
   elsif($subcommand =~ m/community/ ) {
      my $cindex = 0;
      my @clist;
      foreach (0..17) {
         push @clist,0;
      }
      foreach (split //,$argument)  {
         $clist[$cindex++]=ord($_);
      }
      @cmd = (1,$channel_number,0x10,@clist);
   }
	elsif ($subcommand eq "textid") {
		if (1 or $sessdata->{isite}) { #if we have an IBM ITE system, we can go ahead and pursue this via vpd interface a la rinv
			$sessdata->{do_textid}=1;
			$sessdata->{set_textid}=$argument;
			$sessdata->{currfruid}=0;
    			$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,0x2,0x0,1,0,1,1,0],callback=>\&got_vpd_version,callback_args=>$sessdata);
			return;
		} else {
			return(1,"unsupported command rspconfig $subcommand on this platform");
		}
	}
	elsif($subcommand =~ m/snmpdest(\d+)/ ) {
		my $dstip = $argument; #pop(@input);
        $dstip = inet_ntoa(inet_aton($dstip));
		my @dip = split /\./, $dstip;
		@cmd = (0x01,$channel_number,0x13,$1,0x00,0x00,$dip[0],$dip[1],$dip[2],$dip[3],0,0,0,0,0,0);
	}
	#elsif($subcommand eq "alert" ) {
	#    my $action=pop(@input);
            #print "action=$action\n";
        #    $netfun=0x28; #TODO: not right
 
            # mapping alert action to number
        #    my $act_number=8;   
        #    if ($action eq "on") {$act_number=8;}  
        #    elsif ($action eq "off") { $act_number=0;}  
        #    else { return(1,"unsupported alert action $action");}    
	#    @cmd = (0x12, $channel_number,0x09, 0x01, $act_number+16, 0x11,0x00);
	#}
	else {
		return(1,"configuration of $subcommand is not implemented currently");
	}
    my $command = shift @cmd;
    $sessdata->{ipmisession}->subcmd(netfn=>$netfun,command=>$command,data=>\@cmd,callback=>\&netinfo_set,callback_args=>$sessdata);
}
sub netinfo_set {
    my $rsp = shift;
    my $sessdata = shift;
    if ($rsp->{error}) { 
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    if ($rsp->{code}) {
        if ($codes{$rsp->{code}}) {
            xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
        } else {
            xCAT::SvrUtils::sendmsg([1,sprintf("Unknown ipmi error %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
        }
        return;
    }
    getnetinfo($sessdata);
    return;
}

sub getnetinfo {
    my $sessdata = shift;
	my $subcommand = $sessdata->{subcommand};
    my $channel_number = $sessdata->{ipmisession}->{currentchannel};
   $subcommand =~ s/=.*//;
   if ($subcommand eq "thermprofile") {
       my $code;
       my @returnd;
       my $thermdata;
       my $netfun=0x2e<<2; #currently combined netfun & lun, to be simplified later
       my @cmd = (0x41,0x4d,0x4f,0x00,0x6f,0xff,0x61,0x00);
       my @bytes;
       my $error = docmd($netfun,\@cmd,\@bytes);
       @bytes=splice @bytes,16;
       my $validprofiles="";
       foreach (keys %idpxthermprofiles) {
           if (sprintf("%02x %02x %02x %02x %02x %02x %02x",@bytes) eq sprintf("%02x %02x %02x %02x %02x %02x %02x",@{$idpxthermprofiles{$_}})) {
               $validprofiles.="$_,";
           }
       }
       if ($validprofiles) {
           chop($validprofiles);
           return (0,"The following thermal profiles are in effect: ".$validprofiles);
       }
       return (1,sprintf("Unable to identify current thermal profile: \"%02x %02x %02x %02x %02x %02x %02x\"",@bytes));
   }

	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;

	if ($subcommand eq "snmpdest") {
		$subcommand = "snmpdest1";
	}

    my $netfun = 0x0c;
   if ($subcommand eq "alert") {
      $netfun = 0x4;
      @cmd = (0x13,9,1,0);
   }
	elsif($subcommand eq "garp") {
		@cmd = (0x02,$channel_number,0x0b,0x00,0x00);
	}
	elsif ($subcommand =~ m/^snmpdest(\d+)/ ) {
		@cmd = (0x02,$channel_number,0x13,$1,0x00);
	}
	elsif ($subcommand eq "ip") {
		@cmd = (0x02,$channel_number,0x03,0x00,0x00);
	}
	elsif ($subcommand eq "netmask") {
		@cmd = (0x02,$channel_number,0x06,0x00,0x00);
	}
	elsif ($subcommand eq "gateway") {
		@cmd = (0x02,$channel_number,0x0C,0x00,0x00);
	}
	elsif ($subcommand eq "backupgateway") {
		@cmd = (0x02,$channel_number,0x0E,0x00,0x00);
	}
	elsif ($subcommand eq "community") {
		@cmd = (0x02,$channel_number,0x10,0x00,0x00);
	}
	elsif ($subcommand eq "textid") {
		if (1 or $sessdata->{isite}) { #if we have an IBM ITE system, we can go ahead and pursue this via vpd interface a la rinv
			$sessdata->{get_textid}=1;
			$sessdata->{do_textid}=1;
			$sessdata->{currfruid}=0;
    			$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,0x2,0x0,1,0,1,1,0],callback=>\&got_vpd_version,callback_args=>$sessdata);
			return;
		} else {
			return(1,"unsupported command rspconfig $subcommand on this platform");
		}
	}
	else {
		return(1,"unsupported command getnetinfo $subcommand");
	}

    my $command = shift @cmd;
    $sessdata->{ipmisession}->subcmd(netfn=>$netfun,command=>$command,data=>\@cmd,callback=>\&getnetinfo_response,callback_args=>$sessdata);
}
sub getnetinfo_response {
    my $rsp = shift;
    my $sessdata = shift;
    my $subcommand = $sessdata->{subcommand};
    $sessdata->{subcommand} = shift @{$sessdata->{extraargs}};
    if ($rsp->{error}) { 
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    if ($rsp->{code}) {
        if ($codes{$rsp->{code}}) {
            xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
        } else {
            xCAT::SvrUtils::sendmsg([1,sprintf("Unknown ipmi error %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
        }
        return;
    }
    if ($subcommand eq "snmpdest") {
        $subcommand = "snmpdest1";
    }
    my $bmcifo="";
    if ($sessdata->{bmcnum} != 1) { $bmcifo.= " on BMC ".$sessdata->{bmcnum}; }
    my @returnd = (0,@{$rsp->{data}});
	my $format = "%-25s";
	if($subcommand eq "garp") {
			my $code = $returnd[2] / 2;
				xCAT::SvrUtils::sendmsg(sprintf("$format %d","Gratuitous ARP seconds:",$code),$callback,$sessdata->{node},%allerrornodes);
	}
    elsif($subcommand eq "alert") {
        if ($returnd[3] & 0x8) { 
           xCAT::SvrUtils::sendmsg("SP Alerting: enabled".$bmcifo,$callback,$sessdata->{node},%allerrornodes);
        } else {
           xCAT::SvrUtils::sendmsg("SP Alerting: disabled".$bmcifo,$callback,$sessdata->{node},%allerrornodes);
        }
     }
	elsif($subcommand =~ m/^snmpdest(\d+)/ ) {
			xCAT::SvrUtils::sendmsg(sprintf("$format %d.%d.%d.%d".$bmcifo,
				"SP SNMP Destination $1:",
				$returnd[5],
				$returnd[6],
				$returnd[7],
				$returnd[8]),$callback,$sessdata->{node},%allerrornodes);
	} elsif($subcommand eq "ip") {
			xCAT::SvrUtils::sendmsg(sprintf("$format %d.%d.%d.%d".$bmcifo,
				"BMC IP:",
				$returnd[2],
				$returnd[3],
				$returnd[4],
				$returnd[5]),$callback,$sessdata->{node},%allerrornodes);
	} elsif($subcommand eq "netmask") {
			xCAT::SvrUtils::sendmsg(sprintf("$format %d.%d.%d.%d".$bmcifo,
				"BMC Netmask:",
				$returnd[2],
				$returnd[3],
				$returnd[4],
				$returnd[5]),$callback,$sessdata->{node},%allerrornodes);
	} elsif($subcommand eq "gateway") {
			xCAT::SvrUtils::sendmsg(sprintf("$format %d.%d.%d.%d".$bmcifo,
				"BMC Gateway:",
				$returnd[2],
				$returnd[3],
				$returnd[4],
				$returnd[5]),$callback,$sessdata->{node},%allerrornodes);
	} elsif($subcommand eq "backupgateway") {
			xCAT::SvrUtils::sendmsg(sprintf("$format %d.%d.%d.%d".$bmcifo,
				"BMC Backup Gateway:",
				$returnd[2],
				$returnd[3],
				$returnd[4],
				$returnd[5]),$callback,$sessdata->{node},%allerrornodes);
	} elsif ($subcommand eq "community") {
			my $text = sprintf("$format ","SP SNMP Community:");
			my $l = 2;
			while ($returnd[$l] ne 0) {
				$l = $l + 1;
			}
			my $i=2;
			while ($i<$l) {
				$text = $text . sprintf("%c",$returnd[$i]);
				$i = $i + 1;
			}
			$text.=$bmcifo;
            xCAT::SvrUtils::sendmsg($text,$callback,$sessdata->{node},%allerrornodes);
	}
    if ($sessdata->{subcommand}) {
        if ($sessdata->{subcommand} =~ /=/) {
            setnetinfo($sessdata);
        } else {
            getnetinfo($sessdata);
        }
    }
    return;
}

sub setboot {
    my $sessdata = shift;
    #This disables the 60 second timer
    $sessdata->{ipmisession}->subcmd(netfn=>0,command=>8,data=>[3,8],callback=>\&setboot_timerdisabled,callback_args=>$sessdata);
}
sub setboot_timerdisabled {
    my $rsp = shift;
    my $sessdata = shift;
    if ($rsp->{error}) { 
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    if ($rsp->{code}) {
        if ($codes{$rsp->{code}}) {
            xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
            return;
        } elsif ($rsp->{code} == 0x80) {
            xCAT::SvrUtils::sendmsg("Unable to disable countdown timer, boot device may revert in 60 seconds",$callback,$sessdata->{node},%allerrornodes);
        } else {
            xCAT::SvrUtils::sendmsg([1,sprintf("Unknown ipmi error %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
            return;
        }
    }
    my $error;
    @ARGV=@{$sessdata->{extraargs}};
    my $persistent=0;
    my $uefi=0;
    use Getopt::Long;
    unless(GetOptions(
        'p' => \$persistent,
        'u' => \$uefi,
        )) {
        xCAT::SvrUtils::sendmsg([1,"Error parsing arguments"],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    my $subcommand=shift @ARGV;

    my @cmd;
    my $overbootflags=0x80 | $persistent<<6|$uefi << 5;
    if ($subcommand eq "net") {
        @cmd=(0x5,$overbootflags,0x4,0x0,0x0,0x0);
    }
    elsif ($subcommand eq "hd" ) {
        @cmd=(0x5,$overbootflags,0x8,0x0,0x0,0x0);
    }
    elsif ($subcommand eq "cd" ) {
        @cmd=(0x5,$overbootflags,0x14,0x0,0x0,0x0);
    }
    elsif ($subcommand eq "floppy" ) {
        @cmd=(0x5,$overbootflags,0x3c,0x0,0x0,0x0);
    }
    elsif ($subcommand =~ m/^def/) {
        @cmd=(0x5,0x0,0x0,0x0,0x0,0x0);
    }
    elsif ($subcommand eq "setup" ) { #Not supported by BMCs I've checked so far..
        @cmd=(0x5,$overbootflags,0x18,0x0,0x0,0x0);
    }
    elsif ($subcommand =~ m/^stat/) {
        setboot_stat("NOQUERY",$sessdata);
        return;
    }
    else {
        xCAT::SvrUtils::sendmsg([1,"unsupported command setboot $subcommand"],$callback,$sessdata->{node},%allerrornodes);
    }
    $sessdata->{ipmisession}->subcmd(netfn=>0,command=>8,data=>\@cmd,callback=>\&setboot_stat,callback_args=>$sessdata);
}
sub setboot_stat {
    my $rsp = shift;
    my $sessdata = shift;
    if (ref $rsp) {
        if ($rsp->{error}) { xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes); }
        elsif ($rsp->{code}) {
        if ($codes{$rsp->{code}}) {
            xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
        } else {
            xCAT::SvrUtils::sendmsg([1,sprintf("Unknown ipmi error %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
        }
        return;
        }
    }
    $sessdata->{ipmisession}->subcmd(netfn=>0,command=>9,data=>[5,0,0],callback=>\&setboot_gotstat,callback_args=>$sessdata);
}
sub setboot_gotstat {
    my $rsp = shift;
    my $sessdata = shift;
    if ($rsp->{error}) { xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes); }
    elsif ($rsp->{code}) {
    if ($codes{$rsp->{code}}) {
        xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
    } else {
        xCAT::SvrUtils::sendmsg([1,sprintf("Unknown ipmi error %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
    }
    return;
    }
    my %bootchoices = (
        0 => 'BIOS default',
        1 => 'Network',
        2 => 'Hard Drive',
        5 => 'CD/DVD',
        6 => 'BIOS Setup',
        15 => 'Floppy'
    );
    my @returnd = ($rsp->{code},@{$rsp->{data}});
    unless ($returnd[3] & 0x80) {
        xCAT::SvrUtils::sendmsg("boot override inactive",$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    my $boot=($returnd[4] & 0x3C) >> 2;
    xCAT::SvrUtils::sendmsg($bootchoices{$boot},$callback,$sessdata->{node},%allerrornodes);
    return;
}

sub idpxthermprofile {
    #iDataplex thermal profiles as of 6/10/2008
    my $subcommand = lc(shift);
    my @returnd;
    my $netfun = 0xb8;
    my @cmd = (0x41,0x4d,0x4f,0x00,0x6f,0xfe,0x60,0,0,0,0,0,0,0,0xff);
    if ($idpxthermprofiles{$subcommand}) {
        push @cmd,@{$idpxthermprofiles{$subcommand}};
    } else {
        return (1,"Not an understood thermal profile, expected a 2 hex digit value corresponding to chassis label on iDataplex server");
    }
    docmd(
        $netfun,
        \@cmd,
        \@returnd
    );
    return (0,"OK");
}


sub getrvidparms {
    my $sessdata = shift;
    unless ($sessdata) { die "not fixed yet" }
#check devide id
    if ($sessdata->{mfg_id} == 20301 and $sessdata->{prod_id} == 220) {
        my $browser = LWP::UserAgent->new();
        my $message = "WEBVAR_USERNAME=".$sessdata->{ipmisession}->{userid}."&WEBVAR_PASSWORD=".$sessdata->{ipmisession}->{password};
        $browser->cookie_jar({});
        my $baseurl = "https://".$sessdata->{ipmisession}->{bmc}."/";
        my $response = $browser->request(GET $baseurl."rpc/WEBSES/validate.asp");
        $response = $browser->request(POST $baseurl."rpc/WEBSES/create.asp",'Content-Type'=>"application/x-www-form-urlencoded",Content=>$message);
        $response = $response->content;
        if ($response and $response =~ /SESSION_COOKIE' : '([^']*)'/) {
            foreach (keys  %{$browser->cookie_jar->{COOKIES}}) {
                $browser->cookie_jar()->set_cookie(1,"SessionCookie",$1,"/",$_);
            }
        }
        $response = $browser->request(GET $baseurl."/Java/jviewer.jnlp?ext_ip=".$sessdata->{ipmisession}->{bmc});
        $response = $response->content;
        xCAT::SvrUtils::sendmsg("method:imm",$callback,$sessdata->{node},%allerrornodes);
        xCAT::SvrUtils::sendmsg("jnlp:$response",$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    unless ($sessdata->{mfg_id} == 2 or $sessdata->{mfg_id} == 20301) { #Only implemented for IBM servers
        xCAT::SvrUtils::sendmsg([1,"Remote video is not supported on this system"],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    #TODO: use get bmc capabilities to see if rvid is actually supported before bothering the client java app
    $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x50,data=>[],callback=>\&getrvidparms_with_buildid,callback_args=>$sessdata);
}
sub check_rsp_errors { #TODO: pass in command-specfic error code translation table
    my $rsp = shift;
    my $sessdata = shift;
	if($rsp->{error}) { #non ipmi error
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
        return 1;
	}
    if ($rsp->{code}) { #ipmi error
        if ($codes{$rsp->{code}}) {
            xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback,$sessdata->{node},%allerrornodes);
        } else {
             xCAT::SvrUtils::sendmsg([1,sprintf("Unknown error code %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
        }
        return 1;
    }
    return 0;
}
sub getrvidparms_imm2 {
	my $rsp = shift;
	my $sessdata = shift;
    #wvid should be a possiblity, time to do the http...
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0; #TODO: for standalone IMMs, automate CSR retrieval and granting at setup itme
					    #for flex, grab the CA from each CMM and store in a way accessible to this command
					    #for now, accept the MITM risk no worse than http, the intent being feature parity
					    #with http: for envs with https only, like Flex
    my $browser = LWP::UserAgent->new();
	if ($sessdata->{ipmisession}->{bmc} =~ /^fe80/ and $sessdata->{ipmisession}->{bmc} =~ /%/) {
        xCAT::SvrUtils::sendmsg ([1,"wvid not supported with IPv6 LLA addressing mode"],$callback,$sessdata->{node},%allerrornodes);
        return;
	}
	my $host = $sessdata->{ipmisession}->{bmc};
        my $ip6mode=0;
	if ($host =~ /:/) { $ip6mode=1; $host = "[".$host."]"; }
    my $message = "user=".$sessdata->{ipmisession}->{userid}."&password=".$sessdata->{ipmisession}->{password}."&SessionTimeout=1200";
    $browser->cookie_jar({});
    my $httpport=443;
    my $baseurl = "https://$host/";
    my $response = $browser->request(POST $baseurl."data/login",Referer=>"https://$host/designs/imm/index.php",'Content-Type'=>"application/x-www-form-urlencoded",Content=>$message);
    if ($response->code == 500) {
	$httpport=80;
       $baseurl = "http://$host/";
       $response = $browser->request(POST $baseurl."data/login",Referer=>"http://$host/designs/imm/index.php",'Content-Type'=>"application/x-www-form-urlencoded",Content=>$message);
    }
    my $sessionid;
    unless ($response->content =~ /\"ok\"?(.*)/ and $response->content =~ /\"authResult\":\"0\"/) {
        xCAT::SvrUtils::sendmsg ([1,"Server returned unexpected data"],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    $response = $browser->request(GET $baseurl."/designs/imm/remote-control.php");
    if ($response->content =~ /isRPInstalled\s*=\s*'0'/) {
        xCAT::SvrUtils::sendmsg ([1,"Node does not have feature key for remote video"],$callback,$sessdata->{node},%allerrornodes);
    	$response = $browser->request(GET $baseurl."data/logout");
	return;
    }
    $response = $browser->request(GET $baseurl."designs/imm/viewer(".$sessdata->{ipmisession}->{bmc}.'@'.$ip6mode.'@'.time().'@1@0@1@jnlp)');
     #arguments are host, then ipv6 or not, then timestamp, then whether to encrypte or not, singleusermode, finally 'notwin32'
    my $jnlp = $response->content;
    unless ($jnlp) { #ok, might be the newer syntax...
    	$response = $browser->request(GET $baseurl."designs/imm/viewer(".$sessdata->{ipmisession}->{bmc}.'@'.$httpport.'@'.$ip6mode.'@'.time().'@1@0@1@jnlp'.'@USERID@0@0@0@0'.')');
     	#arguments are host, then ipv6 or not, then timestamp, then whether to encrypte or not, singleusermode, finally 'notwin32'
    	$jnlp = $response->content;
    }
    $response = $browser->request(GET $baseurl."data/logout");
    my $currnode = $sessdata->{node};
    $jnlp =~ s!argument>title=.*Video Viewer</argument>!argument>title=$currnode wvid</argument>!;
    xCAT::SvrUtils::sendmsg("method:imm",$callback,$sessdata->{node},%allerrornodes);
    xCAT::SvrUtils::sendmsg("jnlp:$jnlp",$callback,$sessdata->{node},%allerrornodes);
}

sub getrvidparms_with_buildid {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    my @build_id = (0,@{$rsp->{data}});
    if ($build_id[1]==0x31 and $build_id[2]==0x41 and $build_id[3]==0x4f and $build_id[4]==0x4f) { #Only know how to cope with yuoo builds
       return getrvidparms_imm2($rsp,$sessdata);
    }

    unless ($build_id[1]==0x59 and $build_id[2]==0x55 and $build_id[3]==0x4f and $build_id[4]==0x4f) { #Only know how to cope with yuoo builds
        xCAT::SvrUtils::sendmsg([1,"Remote video is not supported on this system"],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    #wvid should be a possiblity, time to do the http...
    my $browser = LWP::UserAgent->new();
    my $message = $sessdata->{ipmisession}->{userid}.",".$sessdata->{ipmisession}->{password};
    $browser->cookie_jar({});
    my $baseurl = "http://".$sessdata->{ipmisession}->{bmc}."/";
    my $response = $browser->request(POST $baseurl."/session/create",'Content-Type'=>"text/xml",Content=>$message);
    my $sessionid;
    if ($response->content =~ /^ok:?(.*)/) {
        $sessionid=$1;
    } else {
        xCAT::SvrUtils::sendmsg ([1,"Server returned unexpected data"],$callback,$sessdata->{node},%allerrornodes);
        return;
    }

    $response = $browser->request(GET $baseurl."/page/session.html"); #we don't care, but some firmware is confused if we don't
    if ($sessionid) {
        $response = $browser->request(GET $baseurl."/kvm/kvm/jnlp?session_id=$sessionid");
    } else {
        $response = $browser->request(GET $baseurl."/kvm/kvm/jnlp");
    }
    my $jnlp = $response->content;
    if ($jnlp =~ /This advanced option requires the purchase and installation/) {
        xCAT::SvrUtils::sendmsg ([1,"Node does not have feature key for remote video"],$callback,$sessdata->{node},%allerrornodes);
	return;
    }
    my $currnode = $sessdata->{node};
    $jnlp =~ s!argument>title=.*Video Viewer</argument>!argument>title=$currnode wvid</argument>!;
    xCAT::SvrUtils::sendmsg("method:imm",$callback,$sessdata->{node},%allerrornodes);
    xCAT::SvrUtils::sendmsg("jnlp:$jnlp",$callback,$sessdata->{node},%allerrornodes);
    my @cmdargv = @{$sessdata->{extraargs}};
    if (grep /-m/,@cmdargv) {
        if ($sessionid) {
            $response = $browser->request(GET $baseurl."/kvm/vm/jnlp?session_id=$sessionid");
        } else {
            $response = $browser->request(GET $baseurl."/kvm/vm/jnlp");
        }
        xCAT::SvrUtils::sendmsg("mediajnlp:".$response->content,$callback,$sessdata->{node},%allerrornodes);;
    }
    return;
}


sub ripmi { #implement generic raw ipmi commands
	my $sessdata = shift;
	my $netfun = hex(shift @{$sessdata->{extraargs}});
	my $command = hex(shift @{$sessdata->{extraargs}});
	my @data;
	foreach (@{$sessdata->{extraargs}}) {
		push @data,hex($_);
	}
	$sessdata->{ipmisession}->subcmd(netfn=>$netfun,command=>$command,data=>\@data,callback=>\&ripmi_callback,callback_args=>$sessdata);
}

sub ripmi_callback {
    if (check_rsp_errors(@_)) {
        return;
    }
        my $rsp = shift;
	my $sessdata = shift;
	if ($rsp->{error}) {
		xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	my $output=sprintf("%02X "x(scalar(@{$rsp->{data}})),@{$rsp->{data}});
	xCAT::SvrUtils::sendmsg($output,$callback,$sessdata->{node},%allerrornodes);
}
	
sub isfpc {
    my $sessdata = shift;
    return 1
}
sub rflash {
    my $sessdata = shift;
    if (isfpc($sessdata)) {
        #first, start a fpc firmware transaction
        $sessdata->{firmpath} = $sessdata->{subcommand};
        $sessdata->{firmctx} = "init";
        $sessdata->{ipmisession}->subcmd(netfn=>0x8, command=>0x17,
                                            data=>[0,0,1,0,0,0,0],
                                            callback=>\&fpc_firmup_config,
                                            callback_args=>$sessdata);
    } else {
        die "Unimplemented";
    }
}

sub fpc_firmup_config {
    if (check_rsp_errors(@_)) {
        abort_fpc_update($_[1]);
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    unless ($sessdata->{firmupxid}) {
        $sessdata->{firmupxid} = $rsp->{data}->[0];
    }
    my $data;
    if ($sessdata->{firmctx} eq 'init') {
        $data =[0, $sessdata->{firmupxid}, 1, 0, 1, 0, 0, 0,
                length($sessdata->{firmpath}),
                unpack("C*",$sessdata->{firmpath})];
        $sessdata->{firmctx} = 'p1';
    } elsif ($sessdata->{firmctx} eq 'p1') {
        $data = [0, $sessdata->{firmupxid}, 3, 0, 5];
        $sessdata->{firmctx} = 'p2';
    } elsif ($sessdata->{firmctx} eq 'p2') {
        $data = [0, $sessdata->{firmupxid}, 4, 0, 0xa];
        $sessdata->{firmctx} = 'p3';
    } elsif ($sessdata->{firmctx} eq 'p3') {
        $data = [0, $sessdata->{firmupxid}, 5, 0, 3];
        $sessdata->{firmctx} = 'p4';
    } elsif ($sessdata->{firmctx} eq 'p4') {
        $data = [0, $sessdata->{firmupxid}, 6, 0, 1];
        $sessdata->{firmctx} = 'xfer';
		xCAT::SvrUtils::sendmsg("Transferring firmware",$callback,$sessdata->{node},%allerrornodes);
        $sessdata->{ipmisession}->subcmd(netfn=>0x8, command=>0x19,
                        data=>[0, $sessdata->{firmupxid}],
                        callback=>\&fpc_firmxfer_watch,
                        callback_args=>$sessdata);
        return;

    }
    $sessdata->{ipmisession}->subcmd(netfn=>0x8, command=>0x18,
                                data=>$data,
                                callback=>\&fpc_firmup_config,
                                callback_args=>$sessdata);
}
sub abort_fpc_update {
    my $sessdata = shift;
    $sessdata->{ipmisession}->subcmd(netfn=>0x8, command=>0x15, data=>[], callback=>\&fpc_update_aborted, callback_args=>$sessdata);
}

sub fpc_update_aborted {
    check_rsp_errors(@_);
    return;
}

sub fpc_firmxfer_watch {
    if ($_[0]->{code} == 0x89) {
	    xCAT::SvrUtils::sendmsg([1,"Transfer failed (wrong url?)"],$callback,$_[1]->{node},%allerrornodes);
        abort_fpc_update($_[1]);
        return;
    }
    if (check_rsp_errors(@_)) {
        abort_fpc_update($_[1]);
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    my $delay=1;
    my $watch=2;
    if ($sessdata->{firmctx} eq 'apply') { $delay = 15; $watch = 1;}
    if (check_rsp_errors(@_)) {
        return;
    }
    my $percent = 0;
    if ($rsp->{data} and (length(@{$rsp->{data}}) > 0)) {
        $percent = $rsp->{data}->[0];
    }
    #$callback->({sinfo=>"$percent%"});
    if ($percent == 100) {
        if ($sessdata->{firmctx} eq 'xfer') {
		    xCAT::SvrUtils::sendmsg("Applying firmware",$callback,$sessdata->{node},%allerrornodes);
            $sessdata->{firmctx} = "apply";
            $sessdata->{ipmisession}->subcmd(netfn=>0x8, command=>0x20,
                                data=>[0, $sessdata->{firmupxid}],
                                callback=>\&fpc_firmxfer_watch,
                                callback_args=>$sessdata);
            return;
        } else {
		    xCAT::SvrUtils::sendmsg("Resetting FPC",$callback,$sessdata->{node},%allerrornodes);
            resetbmc($sessdata);
        }
    } else {
        $sessdata->{ipmisession}->subcmd(netfn=>0x8, command=>0x12,
                                data=>[$watch],
                                delayxmit=>$delay,
                                callback=>\&fpc_firmxfer_watch,
                                callback_args=>$sessdata);
    }
}

sub reseat_node {
    my $sessdata = shift;
    if (1) { # TODO: FPC path checked for
        my $mptab = xCAT::Table->new('mp', -create=>0);
        unless ($mptab) {
		    xCAT::SvrUtils::sendmsg([1,"mp table must be configured for reseat"],$callback,$sessdata->{node},%allerrornodes);
            return;
        }
        my $mpent = $mptab->getNodeAttribs($sessdata->{node},[qw/mpa id/]);
        unless ($mpent and $mpent->{mpa} and $mpent->{id}) {
		    xCAT::SvrUtils::sendmsg([1,"mp table must be configured for reseat"],$callback,$sessdata->{node},%allerrornodes);
            return;
        }
        my $fpc = $mpent->{mpa};
        my $ipmitab = xCAT::Table->new("ipmi");
	    my $ipmihash = $ipmitab->getNodesAttribs([$fpc],['bmc','username','password']) ;
	    my $authdata = xCAT::PasswordUtils::getIPMIAuth(noderange=>[$fpc],ipmihash=>$ipmihash);
		my $nodeuser=$authdata->{$fpc}->{username};
		my $nodepass=$authdata->{$fpc}->{password};
        $sessdata->{slotnumber} = $mpent->{id};
        $sessdata->{fpcipmisession} = xCAT::IPMI->new(bmc=>$mpent->{mpa},userid=>$nodeuser,password=>$nodepass);
        $sessdata->{fpcipmisession}->login(callback=>\&fpc_node_reseat,callback_args=>$sessdata);
    }
}

sub fpc_node_reseat {
    my $status = shift;
    my $sessdata = shift;
    if ($status =~ /ERROR:/) {
        xCAT::SvrUtils::sendmsg([1,$status],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    $sessdata->{fpcipmisession}->subcmd(netfn=>0x32, command=>0xa4,
        data=>[$sessdata->{slotnumber}, 2],
        callback=>\&fpc_node_reseat_complete, callback_args=>$sessdata);
}

sub fpc_node_reseat_complete {
    my $rsp = shift;
    my $sessdata = shift;
	if ($rsp->{error}) {
		xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	if ($rsp->{code} == 0) {
        xCAT::SvrUtils::sendmsg("reseat",$callback,$sessdata->{node},%allerrornodes);
    } elsif ($rsp->{code} == 0xd5) {
		xCAT::SvrUtils::sendmsg([1,"No node in slot"],$callback,$sessdata->{node},%allerrornodes);
    } else {
		xCAT::SvrUtils::sendmsg([1,"Unknown error code ".$rsp->{code}],$callback,$sessdata->{node},%allerrornodes);
    }
}

sub power {
	my $sessdata = shift;

	my $netfun = 0x00;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;
    if ($sessdata->{subcommand} eq "reseat") {
        reseat_node($sessdata);
    } elsif (not $sessdata->{acpistate} and $sessdata->{mfg_id} == 20301) { #Only implemented for IBM servers
		$sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x1d,data=>[1],callback=>\&power_with_acpi,callback_args=>$sessdata);
	} else {
		$sessdata->{ipmisession}->subcmd(netfn=>0,command=>1,data=>[],callback=>\&power_with_context,callback_args=>$sessdata);
	}
}
sub power_with_acpi {
	my $rsp = shift;
	my $sessdata = shift;
	if ($rsp->{error}) {
		xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	if ($rsp->{code} == 0) {
		if ($rsp->{data}->[0] == 3) {
			$sessdata->{acpistate} = "suspend";
		}
	}
		#unless ($text) { $text = sprintf("Unknown error code %02xh",$rsp->{code}); }
		#xCAT::SvrUtils::sendmsg([1,$text],$callback,$sessdata->{node},%allerrornodes);
	#}
	$sessdata->{ipmisession}->subcmd(netfn=>0,command=>1,data=>[],callback=>\&power_with_context,callback_args=>$sessdata);
}
sub power_with_context {
	my $rsp = shift;
	my $sessdata = shift;
	my $text="";
	if ($rsp->{error}) {
		xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	if ($rsp->{code} != 0) {
		$text = $codes{$rsp->{code}};
		unless ($text) { $text = sprintf("Unknown error code %02xh",$rsp->{code}); }
		xCAT::SvrUtils::sendmsg([1,$text],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	$sessdata->{powerstatus} = ($rsp->{data}->[0] & 1 ? "on" : "off");
	my $reportstate;
	if ($sessdata->{acpistate}) {
		$reportstate = $sessdata->{acpistate};
	} else {
		$reportstate = $sessdata->{powerstatus};
	}
		
	if ($sessdata->{subcommand} eq "stat" or $sessdata->{subcommand} eq "state" or $sessdata->{subcommand} eq "status") { 
        if ($sessdata->{powerstatprefix}) {
		    xCAT::SvrUtils::sendmsg($sessdata->{powerstatprefix}.$reportstate,$callback,$sessdata->{node},%allerrornodes);
        } else {
		    xCAT::SvrUtils::sendmsg($reportstate,$callback,$sessdata->{node},%allerrornodes);
        }
        if ($sessdata->{sensorstoread} and scalar @{$sessdata->{sensorstoread}}) { #if we are in an rvitals path, hook back into good graces
            $sessdata->{currsdr} = shift @{$sessdata->{sensorstoread}};
            readsensor($sessdata); #next
        }
		return;
	}
	my $subcommand = $sessdata->{subcommand};
	if ($sessdata->{subcommand} eq "boot") {
		$text = $sessdata->{powerstatus}. " ";
		$subcommand = ($sessdata->{powerstatus} eq "on" ? "reset" : "on");
		$sessdata->{subcommand}=$subcommand; #lazy typing..
	}
	my %argmap = ( #english to ipmi dictionary
		"on" => 1,
		"off" => 0,
		"softoff" => 5,
		"reset" => 3,
		"nmi" => 4
		);
	if($subcommand eq "on") {
		if ($sessdata->{powerstatus} eq "on") {
			if ($sessdata->{acpistate} and $sessdata->{acpistate} eq "suspend") { #ok, make this a wake
				$sessdata->{subcommand}="wake";
				$sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x1d,data=>[0,0],callback=>\&power_response,callback_args=>$sessdata);
				return;
			} 
			xCAT::SvrUtils::sendmsg("on",$callback,$sessdata->{node},%allerrornodes);
            $allerrornodes{$sessdata->{node}}=1;
			return; # don't bother sending command
		}
	} elsif ($subcommand eq "softoff" or $subcommand eq "off" or $subcommand eq "reset") {
		if ($sessdata->{powerstatus} eq "off") {
			xCAT::SvrUtils::sendmsg("off",$callback,$sessdata->{node},%allerrornodes);
            $allerrornodes{$sessdata->{node}}=1;
			return;
		}
	} elsif ($subcommand eq "suspend") {
		my $waitforsuspend;
		my $failtopowerdown;
		my $failtoreset;
		if ($sessdata->{powerstatus} eq "off") {
		        xCAT::SvrUtils::sendmsg([1,"System is off, cannot be suspended"],$callback,$sessdata->{node},%allerrornodes);
		        return;
		}
			
		if (@{$sessdata->{extraargs}} > 1) {
    			@ARGV=@{$sessdata->{extraargs}};
    			use Getopt::Long;
			    unless(GetOptions(
			        'w:i' => \$waitforsuspend,
				'o' => \$failtopowerdown,
				'r' => \$failtoreset,
		        )) {
		        xCAT::SvrUtils::sendmsg([1,"Error parsing arguments"],$callback,$sessdata->{node},%allerrornodes);
		        return;
		    }
		}
		if (defined $waitforsuspend) {
			if ($waitforsuspend == 0) { $waitforsuspend=30; }
			$sessdata->{waitforsuspend}=time()+$waitforsuspend;
		}
		$sessdata->{failtopowerdown}=$failtopowerdown;
		$sessdata->{failtoreset}=$failtoreset;
		$sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x1d,data=>[0,3],callback=>\&power_response,callback_args=>$sessdata);
		return;
	} elsif ($subcommand eq "wake") {
		$sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x1d,data=>[0,0],callback=>\&power_response,callback_args=>$sessdata);
	} elsif (not $argmap{$subcommand}) {
		xCAT::SvrUtils::sendmsg([1,"unsupported command power $subcommand"],$callback);
		return;
	}

	$sessdata->{ipmisession}->subcmd(netfn=>0,command=>2,data=>[$argmap{$subcommand}],callback=>\&power_response,callback_args=>$sessdata);
}
sub power_response { 
	my $rsp = shift;
	my $sessdata = shift;
	if($rsp->{error}) {
		xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	my @returnd = ($rsp->{code},@{$rsp->{data}});
	if ($rsp->{code}) {
		my $text = $codes{$rsp->{code}};
		unless ($text) { $text = sprintf("Unknown response %02xh",$rsp->{code}); }
		xCAT::SvrUtils::sendmsg([1,$text],$callback,$sessdata->{node},%allerrornodes);
	}
	if ($sessdata->{waitforsuspend}) { #have to repeatedly power stat until happy or timeout exceeded
		$sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x1d,data=>[1],callback=>\&power_wait_for_suspend,callback_args=>$sessdata);
		return;
	}
	xCAT::SvrUtils::sendmsg($sessdata->{subcommand},$callback,$sessdata->{node},%allerrornodes);
}

sub power_wait_for_suspend {
	my $rsp = shift;
	my $sessdata = shift;
	if ($rsp->{error}) {
		xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
		return;
	}
	if ($rsp->{code} == 0) {
		if ($rsp->{data}->[0] == 3) {
			$sessdata->{acpistate} = "suspend";
		}
	}
	if ($sessdata->{acpistate} eq "suspend") {
		xCAT::SvrUtils::sendmsg("suspend",$callback,$sessdata->{node},%allerrornodes);
	} elsif ($sessdata->{waitforsuspend} <= time()) {
		delete $sessdata->{waitforsuspend};
		if ($sessdata->{failtopowerdown}) {
			$sessdata->{subcommand}='off',
			xCAT::SvrUtils::sendmsg([1,"Failed to enter suspend state, forcing off"],$callback,$sessdata->{node},%allerrornodes);
			power($sessdata);
		} elsif ($sessdata->{failtoreset}) {
			$sessdata->{subcommand}='reset',
			xCAT::SvrUtils::sendmsg([1,"Failed to enter suspend state, forcing reset"],$callback,$sessdata->{node},%allerrornodes);
			power($sessdata);
		} else {
			xCAT::SvrUtils::sendmsg([1,"Failed to enter suspend state"],$callback,$sessdata->{node},%allerrornodes);
		}
	} else {
		$sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x1d,delayxmit=>5,data=>[1],callback=>\&power_wait_for_suspend,callback_args=>$sessdata);
	}
}

sub generic {
	my $subcommand = shift;
	my $netfun;
	my @args;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;

	($netfun,@args) = split(/-/,$subcommand);

	$netfun=oct($netfun);
	printf("netfun:  0x%02x\n",$netfun);

	print "command: ";
	foreach(@args) {
		push(@cmd,oct($_));
		printf("0x%02x ",oct($_));
	}
	print "\n\n";

	$error = docmd(
		$netfun,
		\@cmd,
		\@returnd
	);

	if($error) {
		$rc = 1;
		$text = $error;
	}

	$code = $returnd[0];

	if($code == 0x00) {
	}
	else {
		$rc = 1;
		$text = $codes{$code};
	}

	printf("return code: 0x%02x\n\n",$code);

	print "return data:\n";
	my @rdata = @returnd[1..@returnd-2]; 
	hexadump(\@rdata);
	print "\n";

	print "full output:\n";
	hexadump(\@returnd);
	print "\n";

#	if(!$text) {
#		$rc = 1;
#		$text = sprintf("unknown response %02x",$code);
#	}

	return($rc,$text);
}

sub beacon {
    my $sessdata = shift;
	my $subcommand = $sessdata->{subcommand};
    my $ipmiv2=0;
    if ($sessdata->{ipmisession}->{ipmiversion} eq '2.0') {
        $ipmiv2 = 1;
    }
	if($subcommand ne "on" and $subcommand ne "off"){
                xCAT::SvrUtils::sendmsg([1,"please specify on or off for ipmi nodes (stat impossible)"],$callback,$sessdata->{node},%allerrornodes);
     }

    #if stuck with 1.5, say light for 255 seconds.  In 2.0, specify to turn it on forever
	if($subcommand eq "on") {
        if ($ipmiv2) {
            $sessdata->{ipmisession}->subcmd(netfn=>0,command=>4,data=>[0,1],callback=>\&beacon_answer,callback_args=>$sessdata);
        } else {
            $sessdata->{ipmisession}->subcmd(netfn=>0,command=>4,data=>[0xff],callback=>\&beacon_answer,callback_args=>$sessdata);
        }
	} 
	elsif($subcommand eq "off") {
        if ($ipmiv2) {
            $sessdata->{ipmisession}->subcmd(netfn=>0,command=>4,data=>[0,0],callback=>\&beacon_answer,callback_args=>$sessdata);
        } else {
            $sessdata->{ipmisession}->subcmd(netfn=>0,command=>4,data=>[0x0],callback=>\&beacon_answer,callback_args=>$sessdata);
        }
	}
	else {
        return;
	}
}
sub beacon_answer {
    my $rsp = shift;
    my $sessdata = shift;

	if($rsp->{error}) { #non ipmi error
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
        return;
	}
    if ($rsp->{code}) { #ipmi error
        if ($codes{$rsp->{code}}) {
            xCAT::SvrUtils::sendmsg([1,$codes{$rsp->{code}}],$callback);
        } else {
             xCAT::SvrUtils::sendmsg([1,sprintf("Unknown error code %02xh",$rsp->{code})],$callback,$sessdata->{node},%allerrornodes);
        }
        return;
    }
    xCAT::SvrUtils::sendmsg($sessdata->{subcommand},$callback,$sessdata->{node},%allerrornodes);
}

sub inv {
    my $sessdata = shift;
	my $subcommand = $sessdata->{subcommand};

	my $rc = 0;
	my $text;
	my @output;
	my @types;


    unless ($subcommand) {
        $subcommand = "all";
    }
	if($subcommand eq "all") {
		@types = qw(model serial deviceid mprom guid misc hw asset firmware mac wwn);
	}
	elsif($subcommand eq "asset") {
        $sessdata->{skipotherfru}=1;
		@types = qw(asset);
	}
	elsif($subcommand eq "model") {
        $sessdata->{skipotherfru}=1;
		@types = qw(model);
	}
	elsif($subcommand eq "serial") {
        $sessdata->{skipotherfru}=1;
		@types = qw(serial);
	}
	elsif($subcommand eq "vpd") {
        $sessdata->{skipotherfru}=1;
		@types = qw(model serial deviceid mprom);
	}
	elsif($subcommand eq "mprom") {
        $sessdata->{skipfru}=1; #full fru read is expensive, skip it
		@types = qw(mprom);
	}
	elsif($subcommand eq "misc") {
        $sessdata->{skipotherfru}=1;
		@types = qw(misc);
	}
	elsif($subcommand eq "deviceid") {
        $sessdata->{skipfru}=1; #full fru read is expensive, skip it
		@types = qw(deviceid);
	}
	elsif($subcommand eq "guid") {
        $sessdata->{skipfru}=1; #full fru read is expensive, skip it
		@types = qw(guid);
	}
	elsif($subcommand eq "uuid") {
        $sessdata->{skipfru}=1; #full fru read is expensive, skip it
		@types = qw(guid);
	}
	else {
        @types = ($subcommand);
		#return(1,"unsupported BMC inv argument $subcommand");
	}
    $sessdata->{invtypes} = \@types;
	initfru($sessdata);
}
sub fru_initted {
    my $sessdata = shift;
	my $key;
    my @args = @{$sessdata->{extraargs}}; 
    my $up_group = undef;
    if (grep /-t/, @args) {
        $up_group = '1';
    }
    my @types = @{$sessdata->{invtypes}};
	my $format = "%-20s %s";

	foreach $key (sort keys %{$sessdata->{fru_hash}}) {
		my $fru = $sessdata->{fru_hash}->{$key};
        my $type;
        foreach $type (split /,/,$fru->rec_type) {
    		if(grep {$_ eq $type} @types) {
			    my $bmcifo="";
			    if ($sessdata->{bmcnum} != 1) { 
				    $bmcifo=" on BMC ".$sessdata->{bmcnum};
			    }
    		    xCAT::SvrUtils::sendmsg(sprintf($format.$bmcifo,$sessdata->{fru_hash}->{$key}->desc . ":",$sessdata->{fru_hash}->{$key}->value),$callback,$sessdata->{node},%allerrornodes);
                if ($up_group and $type eq "model" and $fru->desc =~ /MTM/) {
                    my $tmp_pre = xCAT::data::ibmhwtypes::parse_group($fru->value);
                    if (defined($tmp_pre)) {
                        xCAT::TableUtils->updatenodegroups($sessdata->{node}, $tmp_pre);
                    } 
                }
                last;
            }
        }
	}
	if ($sessdata->{isite} and (grep {$_ eq "mac"} @types)) {
		$needbladeinv{$_}="mac";
        }
}

sub add_textual_fru {
    my $parsedfru = shift;
    my $description = shift;
    my $category = shift;
    my $subcategory = shift;
    my $types = shift;
    my $sessdata = shift;
    my %args = @_;

    if ($parsedfru->{$category} and $parsedfru->{$category}->{$subcategory}) {
        my $fru;
        my @subfrus;

        if (ref $parsedfru->{$category}->{$subcategory} eq 'ARRAY') {
            @subfrus = @{$parsedfru->{$category}->{$subcategory}};
        } else {
            @subfrus = ($parsedfru->{$category}->{$subcategory})
        }
	my $index=0;
        foreach (@subfrus) {
	    $index++;
            $fru = FRU->new();
            $fru->rec_type($types);
	    if ($args{addnumber}) {  
            $fru->desc($description." ".$index);
		} else {
            $fru->desc($description);
		}
            if (not ref $_) {
                $fru->value($_);
            } else {
                if ($_->{encoding} == 3) {
                    $fru->value($_->{value});
                } else {
                    $fru->value(phex($_->{value}));
                }
                    
            }
            $sessdata->{fru_hash}->{$sessdata->{frudex}} = $fru;
            $sessdata->{frudex} += 1;
        }
    }
}
sub add_textual_frus {
    my $parsedfru = shift;
    my $desc = shift;
    my $categorydesc = shift;
    my $category = shift;
    my $type = shift;
    my $sessdata = shift;
    unless ($type) { $type = 'hw'; }
    add_textual_fru($parsedfru,$desc." ".$categorydesc."Part Number",$category,"partnumber",$type,$sessdata);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."Manufacturer",$category,"manufacturer",$type,$sessdata);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."Serial Number",$category,"serialnumber",$type,$sessdata);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."FRU Number",$category,"frunum",$type,$sessdata);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."Version",$category,"version",$type,$sessdata);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."MAC Address",$category,"macaddrs","mac",$sessdata,addnumber=>1);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."WWN",$category,"wwns","wwn",$sessdata,addnumber=>1);
    add_textual_fru($parsedfru,$desc." ".$categorydesc."",$category,"name",$type,$sessdata);
    if ($parsedfru->{$category}->{builddate}) {
        add_textual_fru($parsedfru,$desc." ".$categorydesc."Manufacture Date",$category,"builddate",$type,$sessdata);
    }
    if ($parsedfru->{$category}->{buildlocation}) {
        add_textual_fru($parsedfru,$desc." ".$categorydesc."Manufacture Location",$category,"buildlocation",$type,$sessdata);
    }
    if ($parsedfru->{$category}->{model})  {
        add_textual_fru($parsedfru,$desc." ".$categorydesc."Model",$category,"model",$type,$sessdata);
    }
    add_textual_fru($parsedfru,$desc." ".$categorydesc."Additional Info",$category,"extra",$type,$sessdata);
}

sub initfru {
	my $netfun = 0x28;
    my $sessdata = shift;
    $sessdata->{fru_hash} = {};

    my $mfg_id = $sessdata->{mfg_id};
    my $prod_id = $sessdata->{prod_id};
	my $device_id=$sessdata->{device_id};

	my $fru = FRU->new();
	$fru->rec_type("deviceid");
	$fru->desc("Manufacturer ID");
	my $value = $mfg_id;
	if($MFG_ID{$mfg_id}) {
		$value = "$MFG_ID{$mfg_id} ($mfg_id)";
	}
	$fru->value($value);
	$sessdata->{fru_hash}->{mfg_id} = $fru;

	$fru = FRU->new();
	$fru->rec_type("deviceid");
	$fru->desc("Product ID");
	$value = $prod_id;
	my $tmp = "$mfg_id:$prod_id";
	if($PROD_ID{$tmp}) {
		$value = "$PROD_ID{$tmp} ($prod_id)";
	}
	$fru->value($value);
	$sessdata->{fru_hash}->{prod_id} = $fru;

	$fru = FRU->new();
	$fru->rec_type("deviceid");
	$fru->desc("Device ID");
	$fru->value($device_id);
	$sessdata->{fru_hash}->{device_id} = $fru;

    $sessdata->{ipmisession}->subcmd(netfn=>0x6,command=>0x37,data=>[],callback=>\&gotguid,callback_args=>$sessdata);
}
sub got_bmc_fw_info {
    my $rsp = shift;
    my $sessdata = shift;
	my $fw_rev1=$sessdata->{firmware_rev1};
    my $fw_rev2=$sessdata->{firmware_rev2};
    my $mprom;
    my $isanimm=0;
    if (ref $rsp and not $rsp->{error} and not $rsp->{code}) { #I am a callback and the command worked
        my @returnd = (@{$rsp->{data}});
			my @a = ($fw_rev2);
            my $prefix = pack("C*",@returnd[0..3]);
            if ($prefix =~ /yuoo/i or $prefix =~ /1aoo/i) { #we have an imm
                $isanimm=1;
            }
			$mprom = sprintf("%d.%s (%s)",$fw_rev1,decodebcd(\@a),getascii(@returnd));
	} else { #either not a callback or IBM call failed
		my @a = ($fw_rev2);
		$mprom = sprintf("%d.%s",$fw_rev1,decodebcd(\@a));
	}
    my $fru = FRU->new();
   	$fru->rec_type("mprom,firmware,bmc,imm");
   	$fru->desc("BMC Firmware");
   	$fru->value($mprom);
   	$sessdata->{fru_hash}->{mprom} = $fru;
    $sessdata->{isanimm}=$isanimm;
    if ($isanimm) {
	#get_imm_property(property=>"/v2/bios/build_id",callback=>\&got_bios_buildid,sessdata=>$sessdata);
	check_for_ite(sessdata=>$sessdata);
    } else {
        initfru_with_mprom($sessdata);
    }
}
sub got_bios_buildid {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{data}) {
        $sessdata->{biosbuildid} = $res{data};
	get_imm_property(property=>"/v2/bios/build_version",callback=>\&got_bios_version,sessdata=>$sessdata);
   } else {
        initfru_with_mprom($sessdata);
   }
}
sub got_bios_version {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{data}) {
        $sessdata->{biosbuildversion} = $res{data};
	get_imm_property(property=>"/v2/bios/build_date",callback=>\&got_bios_date,sessdata=>$sessdata);
   } else {
        initfru_with_mprom($sessdata);
   }
}
sub got_bios_date {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{data}) {
        $sessdata->{biosbuilddate} = $res{data};
	my $fru = FRU->new();
	$fru->rec_type("bios,uefi,firmware");
	$fru->desc("UEFI Version");
	$fru->value($sessdata->{biosbuildversion}." (".$sessdata->{biosbuildid}." ".$sessdata->{biosbuilddate}.")");
	$sessdata->{fru_hash}->{uefi} = $fru;
	get_imm_property(property=>"/v2/fpga/build_id",callback=>\&got_fpga_buildid,sessdata=>$sessdata);
   } else {
        initfru_with_mprom($sessdata);
   }
}
sub got_fpga_buildid {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{data}) {
        $sessdata->{fpgabuildid} = $res{data};
	get_imm_property(property=>"/v2/fpga/build_version",callback=>\&got_fpga_version,sessdata=>$sessdata);
   } else {
    	get_imm_property(property=>"/v2/ibmc/dm/fw/bios/backup_build_id",callback=>\&got_backup_bios_buildid,sessdata=>$sessdata);
   }
}
sub got_backup_bios_buildid {
    my %res = @_;
    my $sessdata = $res{sessdata};
    if ($res{data}) {
        $sessdata->{backupbiosbuild} = $res{data};
    	get_imm_property(property=>"/v2/ibmc/dm/fw/bios/backup_build_version",callback=>\&got_backup_bios_version,sessdata=>$sessdata);
    } else {
        initfru_with_mprom($sessdata);
    }
}

sub got_backup_bios_version {
    my %res = @_;
    my $sessdata = $res{sessdata};
    if ($res{data}) {
        $sessdata->{backupbiosversion} = $res{data};
	    my $fru = FRU->new();
    	$fru->rec_type("bios,uefi,firmware");
    	$fru->desc("Backup UEFI Version");
    	$fru->value($sessdata->{backupbiosversion}." (".$sessdata->{backupbiosbuild}.")");
    	$sessdata->{fru_hash}->{backupuefi} = $fru;
       	get_imm_property(property=>"/v2/ibmc/dm/fw/imm2/backup_build_id",callback=>\&got_backup_imm_buildid,sessdata=>$sessdata);
    } else {
        initfru_with_mprom($sessdata);
    }
}

sub got_backup_imm_buildid {
    my %res = @_;
    my $sessdata = $res{sessdata};
    if ($res{data}) {
        $sessdata->{backupimmbuild} = $res{data};
    	get_imm_property(property=>"/v2/ibmc/dm/fw/imm2/backup_build_version",callback=>\&got_backup_imm_version,sessdata=>$sessdata);
    } else {
        initfru_with_mprom($sessdata);
    }
}
sub got_backup_imm_version {
    my %res = @_;
    my $sessdata = $res{sessdata};
    if ($res{data}) {
        $sessdata->{backupimmversion} = $res{data};
    	get_imm_property(property=>"/v2/ibmc/dm/fw/imm2/backup_build_date",callback=>\&got_backup_imm_builddate,sessdata=>$sessdata);
    } else {
        initfru_with_mprom($sessdata);
    }
}
sub got_backup_imm_builddate {
    my %res = @_;
    my $sessdata = $res{sessdata};
    if ($res{data}) {
        $sessdata->{backupimmdate} = $res{data};
	my $fru = FRU->new();
	$fru->rec_type("bios,uefi,firmware");
	$fru->desc("Backup IMM Version");
	$fru->value($sessdata->{backupimmversion}." (".$sessdata->{backupimmbuild}." ".$sessdata->{backupimmdate}.")");
	$sessdata->{fru_hash}->{backupimm} = $fru;
    }
        initfru_with_mprom($sessdata);
}
sub got_fpga_version {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{data}) {
        $sessdata->{fpgabuildversion} = $res{data};
	get_imm_property(property=>"/v2/fpga/build_date",callback=>\&got_fpga_date,sessdata=>$sessdata);
   } else {
        initfru_with_mprom($sessdata);
   }
}
sub got_fpga_date {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{data}) {
        $sessdata->{fpgabuilddate} = $res{data};
	my $fru = FRU->new();
	$fru->rec_type("fpga,firmware");
	$fru->desc("FPGA Version");
	$fru->value($sessdata->{fpgabuildversion}." (".$sessdata->{fpgabuildid}." ".$sessdata->{fpgabuilddate}.")");
	$sessdata->{fru_hash}->{fpga} = $fru;
   }
   initfru_with_mprom($sessdata);
}
sub check_for_ite {
   my %args = @_;
   my @getpropertycommand;
   my $sessdata = $args{sessdata};
   $sessdata->{property_callback} = \&got_ite_check; #$args{callback};
   @getpropertycommand = unpack("C*","/v2/cmm/");
   my $length = 0b10000000 | (scalar @getpropertycommand);#use length to store tlv
	unshift @getpropertycommand,$length;
	#command also needs the overall length
	$length = (scalar @getpropertycommand);
	unshift @getpropertycommand,0; #do not recurse, though it's not going to matter anyway since we are just checking for the existence of the category
	unshift @getpropertycommand,$length&0xff;
	unshift @getpropertycommand,($length>>8)&0xff;
	unshift @getpropertycommand,2; #get all properties command,
        $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0xc4,data=>\@getpropertycommand,callback=>\&got_imm_property,callback_args=>$sessdata);
}
sub got_ite_check {
   my %res = @_;
   my $sessdata = $res{sessdata};
   if ($res{ccode} == 9) { #success, end of tree means an ITE, remember this
	$sessdata->{isite}=1;
   } else {
	$sessdata->{isite}=0;
   }
   get_imm_property(property=>"/v2/bios/build_id",callback=>\&got_bios_buildid,sessdata=>$sessdata);
}
sub get_imm_property {
   my %args = @_;
   my @getpropertycommand;
   my $sessdata = $args{sessdata};
   $sessdata->{property_callback} = $args{callback};
   @getpropertycommand = unpack("C*",$args{property});
   my $length = 0b10000000 | (scalar @getpropertycommand);#use length to store tlv
	unshift @getpropertycommand,$length;
	#command also needs the overall length
	$length = (scalar @getpropertycommand);
	unshift @getpropertycommand,$length&0xff;
	unshift @getpropertycommand,($length>>8)&0xff;
	unshift @getpropertycommand,0; #the actual 'get proprety' command is 0.
        $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0xc4,data=>\@getpropertycommand,callback=>\&got_imm_property,callback_args=>$sessdata);
}
sub got_imm_property {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    my @data = @{$rsp->{data}};
    my $propval = shift @data;
    my %res;
    $res{sessdata}=$sessdata;
    $res{ccode}=$propval;
    if ($propval == 0) { #success
    	shift @data; #discard payload size
    	shift @data; #discard payload size
	while (@data) {
		my $tlv = shift @data;
		if ($tlv & 0b10000000) {
			$tlv = $tlv & 0b1111111;
			my @val = splice(@data,0,$tlv);
			$res{data}= unpack("Z*",pack("C*",@val));
		}
	}
   }
   $sessdata->{property_callback}->(%res);
}

sub initfru_withguid {
    my $sessdata = shift;
    my $mfg_id = $sessdata->{mfg_id};
    my $prod_id = $sessdata->{prod_id};
	my $mprom;

	if($mfg_id == 20301 or $mfg_id == 2 && $prod_id != 34869) {
        $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0x50,data=>[],callback=>\&got_bmc_fw_info,callback_args=>$sessdata);
	} else {
        got_bmc_fw_info(0,$sessdata);
    }
}
sub initfru_with_mprom {
    my $sessdata = shift;
    if ($sessdata->{skipfru}) {
        fru_initted($sessdata);
        return;
    }
    $sessdata->{currfruid}=0;
    $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x10,data=>[0],callback=>\&process_currfruid,callback_args=>$sessdata);
}
sub process_currfruid {
    my $rsp = shift;
    my $sessdata = shift;
    if ($rsp->{code} == 0xcb) {
            $sessdata->{currfrudata}="Not Present";
            $sessdata->{currfrudone}=1;
            add_fruhash($sessdata);
            return;
    }
    if ($rsp and $rsp->{code}) { #non-zero return code..
            $sessdata->{currfrudata}="Unable to read";
	    if  ($codes{$rsp->{code}}) {
		$sessdata->{currfrudata} .= " (".$codes{$rsp->{code}}.")";
	    } else {
		$sessdata->{currfrudata} .= sprintf(" (Unknown reason %02xh)",$rsp->{code});
            }
            $sessdata->{currfrudone}=1;
            add_fruhash($sessdata);
            return;
    }
	
    if (check_rsp_errors($rsp,$sessdata)) {
        return;
    }
    my @bytes =@{$rsp->{data}};
    $sessdata->{currfrusize} = ($bytes[1]<<8)+$bytes[0];
    readcurrfrudevice(0,$sessdata);
}
sub initfru_zero {
    my $sessdata = shift;
    my $fruhash = shift;
    my $frudex=0;
    my $fru;
    if (defined $fruhash->{product}->{manufacturer}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("misc");
    	$fru->desc("System Manufacturer");
        if ($fruhash->{product}->{product}->{encoding}==3) {
        	$fru->value($fruhash->{product}->{manufacturer}->{value});
        } else {
        	$fru->value(phex($fruhash->{product}->{manufacturer}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if (defined $fruhash->{product}->{product}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("model");
    	$fru->desc("System Description");
        if ($fruhash->{product}->{product}->{encoding}==3) {
        	$fru->value($fruhash->{product}->{product}->{value});
        } else {
        	$fru->value(phex($fruhash->{product}->{product}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if (defined $fruhash->{product}->{model}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("model");
    	$fru->desc("System Model/MTM");
        if ($fruhash->{product}->{model}->{encoding}==3) {
        	$fru->value($fruhash->{product}->{model}->{value});
        } else {
        	$fru->value(phex($fruhash->{product}->{model}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if (defined $fruhash->{product}->{version}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("misc");
    	$fru->desc("System Revision");
        if ($fruhash->{product}->{version}->{encoding}==3) {
        	$fru->value($fruhash->{product}->{version}->{value});
        } else {
        	$fru->value(phex($fruhash->{product}->{version}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if (defined $fruhash->{product}->{serialnumber}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("serial");
    	$fru->desc("System Serial Number");
        if ($fruhash->{product}->{serialnumber}->{encoding}==3) {
        	$fru->value($fruhash->{product}->{serialnumber}->{value});
        } else {
        	$fru->value(phex($fruhash->{product}->{serialnumber}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if (defined $fruhash->{product}->{asset}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("asset");
    	$fru->desc("System Asset Number");
        if ($fruhash->{product}->{asset}->{encoding}==3) {
        	$fru->value($fruhash->{product}->{asset}->{value});
        } else {
        	$fru->value(phex($fruhash->{product}->{asset}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    foreach (@{$fruhash->{product}->{extra}}) {
        $fru = FRU->new();
        $fru->rec_type("misc");
        $fru->desc("Product Extra data");
        if ($_->{encoding} == 3) {
            $fru->value($_->{value});
        } else {
            #print Dumper($_);
            #print $_->{encoding};
            next;
            $fru->value(phex($_->{value}));
        }
        $sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    

    if ($fruhash->{chassis}->{serialnumber}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("serial");
    	$fru->desc("Chassis Serial Number");
        if ($fruhash->{chassis}->{serialnumber}->{encoding}==3) {
        	$fru->value($fruhash->{chassis}->{serialnumber}->{value});
        } else {
        	$fru->value(phex($fruhash->{chassis}->{serialnumber}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }

    if ($fruhash->{chassis}->{partnumber}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("model");
    	$fru->desc("Chassis Part Number");
        if ($fruhash->{chassis}->{partnumber}->{encoding}==3) {
        	$fru->value($fruhash->{chassis}->{partnumber}->{value});
        } else {
        	$fru->value(phex($fruhash->{chassis}->{partnumber}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }


    foreach (@{$fruhash->{chassis}->{extra}}) {
        $fru = FRU->new();
        $fru->rec_type("misc");
        $fru->desc("Chassis Extra data");
        if ($_->{encoding} == 3) {
            $fru->value($_->{value});
        } else {
            next;
            #print Dumper($_);
            #print $_->{encoding};
            $fru->value(phex($_->{value}));
        }
        $sessdata->{fru_hash}->{$frudex++} = $fru;
    }

    if ($fruhash->{board}->{builddate})  {
        $fru = FRU->new();
        $fru->rec_type("misc");
        $fru->desc("Board manufacture date");
        $fru->value($fruhash->{board}->{builddate});
        $sessdata->{fru_hash}->{$frudex++} = $fru;
    }

    if ($fruhash->{board}->{manufacturer}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("misc");
    	$fru->desc("Board manufacturer");
        if ($fruhash->{board}->{manufacturer}->{encoding}==3) {
        	$fru->value($fruhash->{board}->{manufacturer}->{value});
        } else {
        	$fru->value(phex($fruhash->{board}->{manufacturer}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if ($fruhash->{board}->{frunum}) {
	$fru = FRU->new();
	$fru->rec_type("misc");
	$fru->desc("Board FRU Number");
	$fru->value($fruhash->{board}->{frunum});
	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if ($fruhash->{board}->{revision}) {
	$fru = FRU->new();
	$fru->rec_type("misc");
	$fru->desc("Board Revision");
	$fru->value($fruhash->{board}->{revision});
	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if ($fruhash->{board}->{macaddrs}) {
	my $macindex=1;
	foreach my $mac (@{$fruhash->{board}->{macaddrs}}) {
		$fru = FRU->new();
		$fru->rec_type("mac");
		$fru->desc("MAC Address $macindex");
		$macindex++;
		$fru->value($mac);
		$sessdata->{fru_hash}->{$frudex++} = $fru;
	}
    }
    if ($fruhash->{board}->{wwns}) {
	my $macindex=1;
	foreach my $mac (@{$fruhash->{board}->{wwns}}) {
		$fru = FRU->new();
		$fru->rec_type("wwn");
		$fru->desc("WWN $macindex");
		$macindex++;
		$fru->value($mac);
		$sessdata->{fru_hash}->{$frudex++} = $fru;
	}
    }
    if ($fruhash->{board}->{name}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("misc");
    	$fru->desc("Board Description");
        if ($fruhash->{board}->{name}->{encoding}==3) {
        	$fru->value($fruhash->{board}->{name}->{value});
        } else {
        	$fru->value(phex($fruhash->{board}->{name}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if ($fruhash->{board}->{serialnumber}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("misc");
    	$fru->desc("Board Serial Number");
        if ($fruhash->{board}->{serialnumber}->{encoding}==3) {
        	$fru->value($fruhash->{board}->{serialnumber}->{value});
        } else {
        	$fru->value(phex($fruhash->{board}->{serialnumber}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    if ($fruhash->{board}->{partnumber}->{value}) {
	    $fru = FRU->new();
    	$fru->rec_type("misc");
    	$fru->desc("Board Model Number");
        if ($fruhash->{board}->{partnumber}->{encoding}==3) {
        	$fru->value($fruhash->{board}->{partnumber}->{value});
        } else {
        	$fru->value(phex($fruhash->{board}->{partnumber}->{value}));
        }
    	$sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    foreach (@{$fruhash->{board}->{extra}}) {
        $fru = FRU->new();
        $fru->rec_type("misc");
        $fru->desc("Board Extra data");
        if ($_->{encoding} == 3) {
            $fru->value($_->{value});
        } else {
            next;
            #print Dumper($_);
            #print $_->{encoding};
            $fru->value(phex($_->{value}));
        }
        $sessdata->{fru_hash}->{$frudex++} = $fru;
    }
    #Ok, done with fru 0, on to the other fru devices from SDR
    $sessdata->{frudex} = $frudex;
    if ($sessdata->{skipotherfru}) { #skip non-primary fru devices
        fru_initted($sessdata);
        return;
    }
    my $key;
    my $subrc;
    my %sdr_hash = %{$sessdata->{sdr_hash}};
    $sessdata->{dimmfru} = [];
    $sessdata->{genhwfru} = [];
    foreach $key (sort {$sdr_hash{$a}->id_string cmp $sdr_hash{$b}->id_string} keys %sdr_hash) {
        my $sdr = $sdr_hash{$key};
        unless ($sdr->rec_type == 0x11 and $sdr->fru_type == 0x10) { #skip non fru sdr stuff and frus I don't understand
            next;
        }
        
        if ($sdr->fru_type == 0x10) { #supported
            if ($sdr->fru_subtype == 0x1) { #DIMM
                push @{$sessdata->{dimmfru}},$sdr;
            } elsif ($sdr->fru_subtype == 0 or $sdr->fru_subtype == 2) {
                push @{$sessdata->{genhwfru}},$sdr;
            }
        }
    }
   if (scalar @{$sessdata->{dimmfru}}) {
        $sessdata->{currfrusdr} = shift  @{$sessdata->{dimmfru}};
        $sessdata->{currfruid} = $sessdata->{currfrusdr}->sensor_number;
        $sessdata->{currfrutype}="dimm";
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x10,data=>[$sessdata->{currfruid}],callback=>\&process_currfruid,callback_args=>$sessdata);
  } elsif (scalar @{$sessdata->{genhwfru}}) {
        $sessdata->{currfrusdr} = shift  @{$sessdata->{genhwfru}};
        $sessdata->{currfruid} = $sessdata->{currfrusdr}->sensor_number;
        $sessdata->{currfrutype}="genhw";
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x10,data=>[$sessdata->{currfruid}],callback=>\&process_currfruid,callback_args=>$sessdata);
  } else {
      fru_initted($sessdata);
  }
}
sub get_frusize {
    my $fruid=shift;
    my $netfun = 0x28; # Storage (0x0A << 2)
    my @cmd=(0x10,$fruid);
	my @bytes;
    my $error = docmd($netfun,\@cmd,\@bytes);
    pop @bytes;
    unless (defined $bytes[0] and $bytes[0] == 0) {
        if ($codes{$bytes[0]}) {
            return (0,$codes{$bytes[0]});
        }
        return (0,"FRU device $fruid inaccessible");
    }
    return ($bytes[2]<<8)+$bytes[1];
}

sub formfru {
    my $fruhash = shift;
    my $frusize = shift;
    $frusize-=8; #consume 8 bytes for mandatory header
    my $availindex=1;
    my @bytes=(1,0,0,0,0,0,0,0); #
    if ($fruhash->{internal}) { #Allocate the space at header time
        $bytes[1]=$availindex;
        $availindex+=ceil((scalar @{$fruhash->{internal}})/8);
        $frusize-=(scalar @{$fruhash->{internal}}); #consume internal bytes
        push @bytes,@{$fruhash->{internal}};
    } 
    if ($fruhash->{chassis}) {
        $bytes[2]=$availindex;
        push @bytes,@{$fruhash->{chassis}->{raw}};
        $availindex+=ceil((scalar @{$fruhash->{chassis}->{raw}})/8);
        $frusize -= ceil((scalar @{$fruhash->{chassis}->{raw}})/8)*8;
    }
    if ($fruhash->{board}) {
        $bytes[3]=$availindex;
        push @bytes,@{$fruhash->{board}->{raw}};
        $availindex+=ceil((scalar @{$fruhash->{board}->{raw}})/8);
        $frusize -= ceil((scalar @{$fruhash->{board}->{raw}})/8)*8;
    }
    #xCAT will always have a product FRU in this process
    $bytes[4]=$availindex;
    unless (defined $fruhash->{product}) { #Make sure there is a data structure
                        #to latch onto..
        $fruhash->{product}={};
    }
    my @prodbytes = buildprodfru($fruhash->{product});
    push @bytes,@prodbytes;
    $availindex+=ceil((scalar @prodbytes)/8);
    $frusize -= ceil((scalar @prodbytes)/8)*8;;
    #End of product fru setup
    if ($fruhash->{extra}) {
        $bytes[5]=$availindex;
        push @bytes,@{$fruhash->{extra}};
        $frusize -= ceil((scalar @{$fruhash->{extra}})/8)*8;
        #Don't need to track availindex anymore
    }
    $bytes[7] = dochksum([@bytes[0..6]]);
    if ($frusize<0) {
        return undef;
    } else {
        return \@bytes;
    }
}

sub transfieldtobytes {
    my $hashref=shift;
    unless (defined $hashref) {
        return (0xC0);
    }
    my @data;
    my $size;
    if ($hashref->{encoding} ==3) {
        @data=unpack("C*",$hashref->{value});
    } else {
        @data=@{$hashref->{value}};
    }
    $size=scalar(@data);
    if ($size > 64) {
        die "Field too large for IPMI FRU specification";
    }
    unshift(@data,$size|($hashref->{encoding}<<6));
    return @data;
}
sub mergefru {
    my $sessdata = shift;
    my $phash = shift; #Product hash
    unless ($phash) { die "here" }
    my $currnode = $sessdata->{node};
    if ($vpdhash->{$currnode}->[0]->{mtm}) {
        $phash->{model}->{encoding}=3;
        $phash->{model}->{value}=$vpdhash->{$currnode}->[0]->{mtm};
    }
    if ($vpdhash->{$currnode}->[0]->{serial}) {
        $phash->{serialnumber}->{encoding}=3;
        $phash->{serialnumber}->{value}=$vpdhash->{$currnode}->[0]->{serial};
    }
    if ($vpdhash->{$currnode}->[0]->{asset}) {
        $phash->{asset}->{encoding}=3;
        $phash->{asset}->{value}=$vpdhash->{$currnode}->[0]->{asset};
    }
}

sub buildprodfru {
    my $sessdata = shift;
    my $prod=shift;
    mergefru($sessdata,$prod);
    my $currnode = $sessdata->{node};
    my @bytes=(1,0,0);
    my @data;
    my $padsize;
    push @bytes,transfieldtobytes($prod->{manufacturer});
    push @bytes,transfieldtobytes($prod->{product});
    push @bytes,transfieldtobytes($prod->{model});
    push @bytes,transfieldtobytes($prod->{version});
    push @bytes,transfieldtobytes($prod->{serialnumber});
    push @bytes,transfieldtobytes($prod->{asset});
    push @bytes,transfieldtobytes($prod->{fruid});
    push @bytes,transfieldtobytes($prod->{fruid});
    foreach (@{$prod->{extra}}) {
        my $sig=getascii(transfieldtobytes($_));
        unless ($sig and $sig =~ /FRU by xCAT/) {
            push @bytes,transfieldtobytes($_);
        }
    }
    push @bytes,transfieldtobytes({encoding=>3,value=>"$currnode FRU by xCAT ".xCAT::Utils::Version('short')});
    push @bytes,(0xc1);
    $bytes[1]=ceil((scalar(@bytes)+1)/8);
    $padsize=(ceil((scalar(@bytes)+1)/8)*8)-scalar(@bytes)-1;
    while ($padsize--) {
        push @bytes,(0x00);
    }
    $padsize=dochksum(\@bytes);#reuse padsize for a second to store checksum
    push @bytes,$padsize;

    return @bytes;
}

sub fru {
	my $subcommand = shift;
	my $netfun = 0x28;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my @output;
	my $code;

	@cmd=(0x10,0x00);
	$error = docmd(
		$netfun,
		\@cmd,
		\@returnd
	);

	if($error) {
		$rc = 1;
		$text = $error;
		return($rc,$text);
	}

	$code = $returnd[0];

	if($code == 0x00) {
	}
	else {
		$rc = 1;
		$text = $codes{$code};
	}

	if($rc != 0) {
		if(!$text) {
			$text = sprintf("unknown response %02x",$code);
		}
		return($rc,$text);
	}

	my $fru_size_ls = $returnd[1];
	my $fru_size_ms = $returnd[2];
	my $fru_size = $fru_size_ms*256 + $fru_size_ls;

	if($subcommand eq "dump") {
		print "FRU Size: $fru_size\n";
		my ($rc,@output) = frudump(0,$fru_size,8);
		if($rc) {
			return($rc,@output);
		}
		hexadump(\@output);
		return(0,"");
	}
	if($subcommand eq "wipe") {
		my @bytes = ();

		for(my $i = 0;$i < $fru_size;$i++) {
			push(@bytes,0xff);
		}
		my ($rc,$text) = fruwrite(0,\@bytes,8);
		if($rc) {
			return($rc,$text);
		}
		return(0,"FRU $fru_size bytes wiped");
	}

	return(0,"");
}

sub add_fruhash {
    my $sessdata = shift;
    my $fruhash;
    if ($sessdata->{currfruid} !=0 and not ref $sessdata->{currfrudata}) {
        my $fru = FRU->new();
        if ($sessdata->{currfrutype} and $sessdata->{currfrutype} eq 'dimm') {
            $fru->rec_type("dimm,hw");
        } else {
             $fru->rec_type("hw");
        }
        $fru->value($sessdata->{currfrudata});
        $fru->desc($sessdata->{currfrusdr}->id_string);
        $sessdata->{fru_hash}->{$sessdata->{frudex}} = $fru;
        $sessdata->{frudex} += 1;
    } elsif ($sessdata->{currfrutype} and $sessdata->{currfrutype} eq 'dimm') {
        $fruhash = decode_spd(@{$sessdata->{currfrudata}});
    } else {
            my $err;
	    $global_sessdata=$sessdata; #pass by global, evil, but practical this time
            ($err,$fruhash) = parsefru($sessdata->{currfrudata});
	    $global_sessdata=undef; #revert state of global 
            if ($err) {
		my $fru = FRU->new();
        if ($sessdata->{currfrutype} and $sessdata->{currfrutype} eq 'dimm') {
            $fru->rec_type("dimm,hw");
        } else {
             $fru->rec_type("hw");
        }
        $fru->value($err);
        $fru->desc($sessdata->{currfrusdr}->id_string);
        $sessdata->{fru_hash}->{$sessdata->{frudex}} = $fru;
        $sessdata->{frudex} += 1;
        undef $sessdata->{currfrudata}; #skip useless calls to add more frus when parsing failed miserably anyway

                #xCAT::SvrUtils::sendmsg([1,":Error reading fru area ".$sessdata->{currfruid}.": $err"],$callback);
                #return;
            }
    }
    if ($sessdata->{currfruid} == 0) {
        initfru_zero($sessdata,$fruhash);
        return;
    } elsif (ref $sessdata->{currfrudata}) {
        if ($sessdata->{currfrutype} and $sessdata->{currfrutype} eq 'dimm') {
            add_textual_frus($fruhash,$sessdata->{currfrusdr}->id_string,"","product","dimm,hw",$sessdata);
        } else {
            add_textual_frus($fruhash,$sessdata->{currfrusdr}->id_string,"Board ","board",undef,$sessdata);
            add_textual_frus($fruhash,$sessdata->{currfrusdr}->id_string,"Product ","product",undef,$sessdata);
            add_textual_frus($fruhash,$sessdata->{currfrusdr}->id_string,"Chassis ","chassis",undef,$sessdata);
        }
    }
    if (scalar @{$sessdata->{dimmfru}}) {
        $sessdata->{currfrusdr} = shift  @{$sessdata->{dimmfru}};
        $sessdata->{currfruid} = $sessdata->{currfrusdr}->sensor_number;
        $sessdata->{currfrutype}="dimm";
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x10,data=>[$sessdata->{currfruid}],callback=>\&process_currfruid,callback_args=>$sessdata);
    } elsif (scalar @{$sessdata->{genhwfru}}) {
        $sessdata->{currfrusdr} = shift  @{$sessdata->{genhwfru}};
        $sessdata->{currfruid} = $sessdata->{currfrusdr}->sensor_number;
        $sessdata->{currfrutype}="genhw";
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x10,data=>[$sessdata->{currfruid}],callback=>\&process_currfruid,callback_args=>$sessdata);
    } else {
        fru_initted($sessdata);
    }
}

sub readcurrfrudevice {
    my $rsp = shift;
    my $sessdata = shift;
    my $chunk=16; #we have no idea how much will be supported to grab at a time, stick to 16 as a magic number for the moment
    if (not ref $rsp) {
        $sessdata->{currfruoffset}=0;
        $sessdata->{currfrudata}=[];
        $sessdata->{currfrudone}=0;
        $sessdata->{currfruchunk}=16;
    } else {
        if ($rsp->{code} != 0xcb and check_rsp_errors($rsp,$sessdata)) {
            return;
        } elsif ($rsp->{code} == 0xcb) {
            $sessdata->{currfrudata}="Not Present";
            $sessdata->{currfrudone}=1;
            add_fruhash($sessdata);
            return;
        }
        my @data = @{$rsp->{data}};
        if ($data[0] != $sessdata->{currfruchunk}) {
            xCAT::SvrUtils::sendmsg([1,"Received incorrect data from BMC"],$callback,$sessdata->{node},%allerrornodes);
            return;
        }
        shift @data;
        push @{$sessdata->{currfrudata}},@data;
        if ($sessdata->{currfrudone}) {
	    if ($sessdata->{isite}) {
		#IBM OEM command, d0,51,0 further qualifies the command name, we'll first take a stop at block 0, offset 2, one byte, to get VPD version number
		#command structured as:
		#d0,51,0 = command set identifier
		#lsb of offset
		#msb of offset
		#address type (1 for fru id)
		#address (fru id for our use)
		#1 - fixed value
		#lsb - size
		#msb - size
		#vpd_base_specivication_ver2.x
    		$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,0x2,0x0,1,$sessdata->{currfruid},1,1,0],callback=>\&got_vpd_version,callback_args=>$sessdata);
	    } else {
            	add_fruhash($sessdata);
	    }
            return;
        }
    }

    my $ms=$sessdata->{currfruoffset}>>8;
    my $ls=$sessdata->{currfruoffset}&0xff;
    if ($sessdata->{currfruoffset}+16  >= $sessdata->{currfrusize}) {
        $chunk =  $sessdata->{currfrusize}-$sessdata->{currfruoffset}; # shrink chunk to only get the remainder data
        $sessdata->{currfrudone}=1;
    } else {
        $sessdata->{currfruoffset}+=$chunk;
    }
    $sessdata->{currfruchunk}=$chunk;
    $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x11,data=>[$sessdata->{currfruid},$ls,$ms,$chunk],callback=>\&readcurrfrudevice,callback_args=>$sessdata);
}

sub got_vpd_version {
    my $rsp = shift;
    my $sessdata = shift;
        unless ($rsp and not $rsp->{error} and $rsp->{code} == 0 and $rsp->{data}->[5] == 2) { #unless the query was successful and major vpd version was 2
												#short over to adding the fru hash as-is
            	add_fruhash($sessdata);
		return;
        }
	#making it this far, we have affirmative confirmation of ibm oem vpd data, time to chase component mac, wwpn, and maybe mezz firmware
	#will need:
	#	block 0, offset 0c8h use the offset to add to block 1 offsets (usually 400h), denoting as $blone
	#       block 1, $blone+6 - 216 bytes: 6 sets of 36 byte version information (TODO)
	#	block 1, $blone+0x1d0: port type first 4 bits protocol, last 3 bits addressing
	#	block 1, $blone+0x240: 64 bytes, up to 8 sets of addresses, mac is left aligned
	#	block 1, $blone+0x300: if mac+wwn, grab wwn
	if ($sessdata->{do_textid}) {
        	$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,0xca,0x0,1,$sessdata->{currfruid},1,2,0],callback=>\&got_vpd_block2,callback_args=>$sessdata);
	} else {
        $sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,0xc8,0x0,1,$sessdata->{currfruid},1,2,0],callback=>\&got_vpd_block1,callback_args=>$sessdata);
	}
}
sub got_vpd_block2 {
    my $rsp = shift;
    my $sessdata = shift;
    unless ($rsp and not $rsp->{error} and $rsp->{code} == 0) { # if this should go wonky, jump ahead
            	add_fruhash($sessdata);
		return;
    }
    $sessdata->{vpdblock2offset}=$rsp->{data}->[5]<<8+$rsp->{data}->[6];
    my $ptoffset = $sessdata->{vpdblock2offset} + 0xf0;
    $sessdata->{textidoffset}=$ptoffset;
    if ($sessdata->{get_textid}) {
    	$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,$ptoffset&0xff,$ptoffset>>8,1,$sessdata->{currfruid},1,16,0],callback=>\&got_textid,callback_args=>$sessdata);
    } elsif (defined $sessdata->{set_textid}) {
    	my $name = $sessdata->{set_textid};
	if ($name eq '*') { $name = $sessdata->{node}; }
    	my @textid = unpack("C*",$name);
	my $neededspaces = 16 - scalar(@textid);
	push @textid,unpack("C*"," "x$neededspaces);
    	$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,$ptoffset&0xff,$ptoffset>>8,1,$sessdata->{currfruid},2,16,0,@textid],callback=>\&set_textid,callback_args=>$sessdata);
    }
}
sub set_textid {
	my $rsp = shift;
	my $sessdata = shift;
	my $ptoffset =  $sessdata->{textidoffset};
    	$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,$ptoffset&0xff,$ptoffset>>8,1,$sessdata->{currfruid},1,16,0],callback=>\&got_textid,callback_args=>$sessdata);
}
sub got_textid {
	my $rsp = shift;
	my $sessdata = shift;
	my @data = @{$rsp->{data}};
	@data = @data[5..20];
	my $text = pack("C*",@data);
	$text =~ s/\s*$//;
        xCAT::SvrUtils::sendmsg("textid:".$text,$callback,$sessdata->{node});
}
sub got_vpd_block1 {
    my $rsp = shift;
    my $sessdata = shift;
    unless ($rsp and not $rsp->{error} and $rsp->{code} == 0) { # if this should go wonky, jump ahead
            	add_fruhash($sessdata);
		return;
    }
    $sessdata->{vpdblock1offset}=$rsp->{data}->[5]<<8+$rsp->{data}->[6];
    my $ptoffset = $sessdata->{vpdblock1offset} + 0x1d0;
    $sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,$ptoffset&0xff,$ptoffset>>8,1,$sessdata->{currfruid},1,1,0],callback=>\&got_portaddr_type,callback_args=>$sessdata);
}
sub got_portaddr_type {
    my $rsp = shift;
    my $sessdata = shift;
    unless ($rsp and not $rsp->{error} and $rsp->{code} == 0) { # if this should go wonky, jump ahead
            	add_fruhash($sessdata);
		return;
    }
    my $addrtype = $rsp->{data}->[5] & 0b111;
    if ($addrtype == 0b101) { 
	$sessdata->{needmultiaddr}=1;
	$sessdata->{curraddrtype}="mac";
    } elsif ($addrtype == 0b1) {
	$sessdata->{curraddrtype}="mac";
    } elsif ($addrtype == 0b10) {
	$sessdata->{curraddrtype}="wwn";
    } else { #for now, skip polling addresses I haven't examined directly
            	add_fruhash($sessdata);
		return;
    }
    my $addroffset = $sessdata->{vpdblock1offset} + 0x240;
    $sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,$addroffset&0xff,$addroffset>>8,1,$sessdata->{currfruid},1,64,0],callback=>\&got_vpd_addresses,callback_args=>$sessdata);

    
}
sub got_vpd_addresses { 
    my $rsp = shift;
    my $sessdata = shift;
    unless ($rsp and not $rsp->{error} and $rsp->{code} == 0) { # if this should go wonky, jump ahead
            	add_fruhash($sessdata);
		return;
    }
    my @addrdata = @{$rsp->{data}};
    splice @addrdata,0,5; # remove the header info
        my $macstring = "1";
	while ($macstring !~ /^00:00:00:00:00:00/) {
		my @currmac = splice @addrdata,0,8;
		unless ((scalar @currmac) == 8) {
			last;
		}
		$macstring = sprintf("%02x:%02x:%02x:%02x:%02x:%02x:%02x:%02x",@currmac);
		if ($macstring =~ /^00:00:00:00:00:00:00:00/) { 
			last;
		}
		if ($sessdata->{curraddrtype} eq "mac") {
			$macstring =~ s/:..:..$//;
			push @{$sessdata->{currmacs}},$macstring;
		} elsif ($sessdata->{curraddrtype} eq "wwn") {
			push @{$sessdata->{currwwns}},$macstring;
		}
	}
	if ($sessdata->{needmultiaddr}) {
		$sessdata->{needmultiaddr}=0;
		$sessdata->{curraddrtype}="wwn";
    		my $addroffset = $sessdata->{vpdblock1offset} + 0x300;
    		$sessdata->{ipmisession}->subcmd(netfn=>0x2e,command=>0x51,data=>[0xd0,0x51,0,$addroffset&0xff,$addroffset>>8,1,$sessdata->{currfruid},1,64,0],callback=>\&got_vpd_addresses,callback_args=>$sessdata);
		return;
	}
         	add_fruhash($sessdata);
}

sub parsefru {
    my $bytes = shift;
    my $fruhash;
    my $curridx; #store indexes as needed for convenience
    my $currsize; #store current size
    my $subidx;
    my @currarea;
    unless (ref $bytes) {
        return $bytes,undef;
    }
    unless ($bytes->[0]==1) {
        if ($bytes->[0]==0 or $bytes->[0]==0xff) { #not in spec, but probably unitialized, xCAT probably will rewrite fresh
            return "clear",undef;
        } else { #some meaning suggested, but not parsable, xCAT shouldn't meddle
            return "Unrecognized FRU format",undef;
        }
    }
    if ($bytes->[1]) { #The FRU spec, unfortunately, gave no easy way to tell the size of internal area
        #consequently, will find the next defined field and preserve the addressing and size of current FRU 
        #area until then
        my $internal_size;
        if ($bytes->[2]) {
            $internal_size=$bytes->[2]*8-($bytes->[1]*8);
        } elsif ($bytes->[3]) {
            $internal_size=$bytes->[3]*8-($bytes->[1]*8);
        } elsif ($bytes->[4]) {
            $internal_size=$bytes->[4]*8-($bytes->[1]*8);
        } elsif ($bytes->[5]) {
            $internal_size=$bytes->[5]*8-($bytes->[1]*8);
        } else { #The FRU area is intact enough to signify xCAT can't safely manipulate contents
            return "unknown-winternal",undef;
        }
        #capture slice of bytes
        $fruhash->{internal}=[@{$bytes}[($bytes->[1]*8)..($bytes->[1]*8+$internal_size-1)]]; #,$bytes->[1]*8,$internal_size];
    }
    if ($bytes->[2]) { #Chassis info area, xCAT will preserve fields, not manipulate them
        $curridx=$bytes->[2]*8;
        unless ($bytes->[$curridx]==1) { #definitely unparsable, but the section is preservable
            return "unknown-COULDGUESS",undef; #be lazy for now, TODO revisit this and add guessing if it ever matters
        }
        $currsize=($bytes->[$curridx+1])*8;
        @currarea=@{$bytes}[$curridx..($curridx+$currsize-1)]; #splice @$bytes,$curridx,$currsize;
        $fruhash->{chassis} = parsechassis(@currarea);
    }
    if ($bytes->[3]) { #Board info area, to be preserved
        $curridx=$bytes->[3]*8;
        unless ($bytes->[$curridx]==1) {
            return "unknown-COULDGUESS",undef;
        }
        $currsize=($bytes->[$curridx+1])*8;
        @currarea=@{$bytes}[$curridx..($curridx+$currsize-1)];
        $fruhash->{board} = parseboard(@currarea);
    }
    if (ref $global_sessdata->{currmacs}) {
	$fruhash->{board}->{macaddrs}=[];
	push @{$fruhash->{board}->{macaddrs}},@{$global_sessdata->{currmacs}};
	delete $global_sessdata->{currmacs}; # consume the accumulated mac addresses to avoid afflicting subsequent fru
    }
    if (ref $global_sessdata->{currwwns}) {
	push @{$fruhash->{board}->{wwns}},@{$global_sessdata->{currwwns}};
	delete $global_sessdata->{currwwns}; # consume wwns
    }
    if ($bytes->[4]) { #Product info area present, will probably be thoroughly modified
        $curridx=$bytes->[4]*8;
        unless ($bytes->[$curridx]==1) {
            return "unknown-COULDGUESS",undef;
        }
        $currsize=($bytes->[$curridx+1])*8;
        @currarea=@{$bytes}[$curridx..($curridx+$currsize-1)];
        $fruhash->{product} = parseprod(@currarea);
    }
    if ($bytes->[5]) { #Generic multirecord present..
        $fruhash->{extra}=[];
        my $last=0;
        $curridx=$bytes->[5]*8;
        my $currsize;
	if ($bytes->[$curridx] <= 5) { #don't even try to parse unknown stuff
			#some records don't comply to any SPEC
	        while (not $last) {
	            if ($bytes->[$curridx+1] & 128) {
	                $last=1;
	            }
	            $currsize=$bytes->[$curridx+2];
	            push @{$fruhash->{extra}},$bytes->[$curridx..$curridx+4+$currsize-1];
        	}
        }
    }
    return 0,$fruhash;
}

sub parseprod {
    my @area = @_;
    my %info;
    my $language=$area[2];
    my $idx=3;
    my $currsize;
    my $currdata;
    my $encode;
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{manufacturer}->{encoding}=$encode;
        $info{manufacturer}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{product}->{encoding}=$encode;
        $info{product}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{model}->{encoding}=$encode;
        $info{model}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{version}->{encoding}=$encode;
        $info{version}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{serialnumber}->{encoding}=$encode;
        $info{serialnumber}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{asset}->{encoding}=$encode;
        $info{asset}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%info;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $info{fruid}->{encoding}=$encode;
        $info{fruid}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    if ($currsize) {
        $info{extra}=[];
    }
    while ($currsize>0) {
        if ($currsize>1) {
            push @{$info{extra}},{value=>$currdata,encoding=>$encode};
        }
        $idx+=$currsize;
        ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
        if ($currsize < 0) { last }
    }
    return \%info;

}
sub parseboard {
    my @area = @_;
    my %boardinf;
    my $idx=6;
    my $language=$area[2];
    my $tstamp = ($area[3]+($area[4]<<8)+($area[5]<<16))*60+820472400; #820472400 is meant to be 1/1/1996
    $boardinf{raw}=[@area]; #store for verbatim replacement
    unless ($tstamp == 820472400) {
        $boardinf{builddate}=scalar localtime($tstamp);
    }
    my $encode;
    my $currsize;
    my $currdata;
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%boardinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $boardinf{manufacturer}->{encoding}=$encode;
        $boardinf{manufacturer}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%boardinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $boardinf{name}->{encoding}=$encode;
        $boardinf{name}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%boardinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $boardinf{serialnumber}->{encoding}=$encode;
        $boardinf{serialnumber}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%boardinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $boardinf{partnumber}->{encoding}=$encode;
        $boardinf{partnumber}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    unless ($currsize) {
        return \%boardinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $boardinf{fruid}->{encoding}=$encode;
        $boardinf{fruid}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
    if ($currsize) {
        $boardinf{extra}=[];
    }
    while ($currsize>0) {
        if ($currsize>1) {
            push @{$boardinf{extra}},{value=>$currdata,encoding=>$encode};
        }
        $idx+=$currsize;
        ($currsize,$currdata,$encode)=extractfield(\@area,$idx);
        if ($currsize < 0) { last }
    }
    if ($global_sessdata->{isanimm}) { #we can understand more specifically some of the extra fields...
	$boardinf{frunum}=$boardinf{extra}->[0]->{value};
	$boardinf{revision}=$boardinf{extra}->[4]->{value};
	#time to process the mac field...
	my $macdata = $boardinf{extra}->[6]->{value};
        my $macstring = "1";
	while ($macstring !~ /00:00:00:00:00:00/ and not ref $global_sessdata->{currmacs}) {
		my @currmac = splice @$macdata,0,6;
		unless ((scalar @currmac) == 6) {
			last;
		}
		$macstring = sprintf("%02x:%02x:%02x:%02x:%02x:%02x",@currmac);
		if ($macstring !~ /00:00:00:00:00:00/) { 
			push @{$boardinf{macaddrs}},$macstring;
		}
	}
	delete $boardinf{extra};
    } 
    return \%boardinf;
}
sub parsechassis {
    my @chassarea=@_;
    my %chassisinf;
    my $currsize;
    my $currdata;
    my $idx=3;
    my $encode;
    $chassisinf{raw}=[@chassarea]; #store for verbatim replacement
    $chassisinf{type}="unknown";
    if ($chassis_types{$chassarea[2]}) {
        $chassisinf{type}=$chassis_types{$chassarea[2]};
    }
    if ($chassarea[$idx] == 0xc1) {
        return \%chassisinf;
    }
    ($currsize,$currdata,$encode)=extractfield(\@chassarea,$idx);
    unless ($currsize) {
        return \%chassisinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $chassisinf{partnumber}->{encoding}=$encode;
        $chassisinf{partnumber}->{value}=$currdata;
    } 
    ($currsize,$currdata,$encode)=extractfield(\@chassarea,$idx);
    unless ($currsize) {
        return \%chassisinf;
    }
    $idx+=$currsize;
    if ($currsize>1) {
        $chassisinf{serialnumber}->{encoding}=$encode;
        $chassisinf{serialnumber}->{value}=$currdata;
    }
    ($currsize,$currdata,$encode)=extractfield(\@chassarea,$idx);
    if ($currsize) {
        $chassisinf{extra}=[];
    }
    while ($currsize>0) {
        if ($currsize>1) {
            push @{$chassisinf{extra}},{value=>$currdata,encoding=>$encode};
        }
        $idx+=$currsize;
        ($currsize,$currdata,$encode)=extractfield(\@chassarea,$idx);
        if ($currsize < 0) { last }
    }
    return \%chassisinf;
}

sub extractfield { #idx is location of the type/length byte, returns something appropriate
    my $area = shift;
    my $idx = shift;
    my $language=shift;
    my $data;
    if ($idx >= scalar @$area)  {
        xCAT::SvrUtils::sendmsg([1,"Error parsing FRU data from BMC"],$callback);
        return -1,undef,undef;
    }
    my $size = $area->[$idx] & 0b00111111;
    my $encoding = ($area->[$idx] & 0b11000000)>>6;
    unless ($size) {
        return 1,undef,undef;
    }
    if ($size==1 && $encoding==3) { 
        return 0,'','';
    }
    if ($encoding==3) {
        $data=getascii(@$area[$idx+1..$size+$idx]);
    } else {
        $data = [@$area[$idx+1..$size+$idx]];
    }
    return $size+1,$data,$encoding;
}






sub writefru {
    my $netfun = 0x28; # Storage (0x0A << 2)
    my @cmd=(0x10,0);
	my @bytes;
    my $error = docmd($netfun,\@cmd,\@bytes);
    pop @bytes;
    unless (defined $bytes[0] and $bytes[0] == 0) {
        return (1,"FRU device 0 inaccessible");
    }
    my $frusize=($bytes[2]<<8)+$bytes[1];
    ($error,@bytes) = frudump(0,$frusize,16);
    if ($error) {
        return (1,"Error retrieving FRU: ".$error);
    }
    my $fruhash; 
    ($error,$fruhash) = parsefru(\@bytes);
    my $newfru=formfru($fruhash,$frusize);
    unless ($newfru) {
        return (1,"FRU data will not fit in BMC FRU space, fields too long");
    }
    my $rc=1;
    my $writeattempts=0;
    my $text;
    while ($rc and $writeattempts<15) {
        if ($writeattempts) {
            sleep 1;
        }
    	($rc,$text) = fruwrite(0,$newfru,8);
        if ($text =~ /rotected/) {
            last;
        }
        $writeattempts++;
    }
	if($rc) {
		return($rc,$text);
	}
	return(0,"FRU Updated");
}

sub fruwrite {
	my $offset = shift;
	my $bytes = shift;
	my $chunk = shift;
	my $length = @$bytes;

	my $netfun = 0x28;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my @output;
	my $code;
	my @fru_data=();

	for(my $c=$offset;$c < $length+$offset;$c += $chunk) {
		my $ms = int($c / 0x100);
		my $ls = $c - $ms * 0x100;

		@cmd=(0x12,0x00,$ls,$ms,@$bytes[$c-$offset..$c-$offset+$chunk-1]);
		$error = docmd(
			$netfun,
			\@cmd,
			\@returnd
		);

		if($error) {
			$rc = 1;
			$text = $error;
			return($rc,$text);
		}

		$code = $returnd[0];

		if($code == 0x00) {
		}
		else {
			$rc = 1;
			$text = $codes{$code};
		}

		if($rc != 0) {
            if ($code == 0x80) {
                $text = "Write protected FRU";
            }
			if(!$text) {
				$text = sprintf("unknown response %02x",$code);
			}
			return($rc,$text);
		}

		my $count = $returnd[1];
		if($count != $chunk) {
			$rc = 1;
			$text = "FRU write error (bytes requested: $chunk, wrote: $count)";
			return($rc,$text);
		}
	}

	return(0);
}

sub decodealert {
    my $sessdata = shift;
  my $skip_sdrinit=0;
    unless (ref $sessdata) { #called from xcat traphandler
        $sessdata = { sdr_hash => {} };
        $skip_sdrinit=1; #TODO sdr_init, cache only to avoid high trap handling overhead
    }
  my $trap = shift;
  if ($trap =~ /xCAT_plugin::ipmi/) {
    $trap=shift;
    $skip_sdrinit=1;
  }
	my $node = shift;
	my @pet = @_;
	my $rc;
	my $text;
    
	my $type;
	my $desc;
	#my $ipmisensoreventtab = "$ENV{XCATROOT}/lib/GUMI/ipmisensorevent.tab";
	#my $ipmigenericeventtab = "$ENV{XCATROOT}/lib/GUMI/ipmigenericevent.tab";

	my $offsetmask     = 0b00000000000000000000000000001111;
	my $offsetrmask    = 0b00000000000000000000000001110000;
	my $assertionmask  = 0b00000000000000000000000010000000;
	my $eventtypemask  = 0b00000000000000001111111100000000;
	my $sensortypemask = 0b00000000111111110000000000000000;
	my $reservedmask   = 0b11111111000000000000000000000000;

	my $offset      = $trap & $offsetmask;
	my $offsetr     = $trap & $offsetrmask;
	my $event_dir   = $trap & $assertionmask;
	my $event_type  = ($trap & $eventtypemask) >> 8;
	my $sensor_type = ($trap & $sensortypemask) >> 16;
	my $reserved    = ($trap & $reservedmask) >> 24;

	if($debug >= 2) {
		printf("offset:     %02xh\n",$offset);
		printf("offsetr:    %02xh\n",$offsetr);
		printf("assertion:  %02xh\n",$event_dir);
		printf("eventtype:  %02xh\n",$event_type);
		printf("sensortype: %02xh\n",$sensor_type);
		printf("reserved:   %02xh\n",$reserved);
	}

	my @hex = (0,@pet);
	my $pad = $hex[0];
	my @uuid = @hex[1..16];
	my @seqnum = @hex[17,18];
	my @timestamp = @hex[19,20,21,22];
	my @utcoffset = @hex[23,24];
	my $trap_source_type = $hex[25];
	my $event_source_type = $hex[26];
	my $sev = $hex[27];
	my $sensor_device = $hex[28];
	my $sensor_num = $hex[29];
	my $entity_id = $hex[30];
	my $entity_instance = $hex[31];
	my $event_data_1 = $hex[32];
	my $event_data_2 = $hex[33];
	my $event_data_3 = $hex[34];
	my @event_data = @hex[35..39];
	my $langcode = $hex[40];
	my $mfg_id = $hex[41] + $hex[42] * 0x100 + $hex[43] * 0x10000 + $hex[44] * 0x1000000;
	my $prod_id = $hex[45] + $hex[46] * 0x100;
	my @oem = $hex[47..@hex-1];

	if($sev == 0x00) {
		$sev = "LOG";
	}
	elsif($sev == 0x01) {
		$sev = "MONITOR";
	}
	elsif($sev == 0x02) {
		$sev = "INFORMATION";
	}
	elsif($sev == 0x04) {
		$sev = "OK";
	}
	elsif($sev == 0x08) {
		$sev = "WARNING";
	}
	elsif($sev == 0x10) {
		$sev = "CRITICAL";
	}
	elsif($sev == 0x20) {
		$sev = "NON-RECOVERABLE";
	}
	else {
		$sev = "UNKNOWN-SEVERITY:$sev";
	}
	$text = "$sev:";

	($rc,$type,$desc) = getsensorevent($sensor_type,$offset,"ipmisensorevents");
	if($rc == 1) {
		$type = "Unknown Type $sensor_type";
		$desc = "Unknown Event $offset";
		$rc = 0;
	}

	if($event_type <= 0x0c) {
		my $gtype;
		my $gdesc;
		($rc,$gtype,$gdesc) = getsensorevent($event_type,$offset,"ipmigenericevents");
		if($rc == 1) {
			$gtype = "Unknown Type $gtype";
			$gdesc = "Unknown Event $offset";
			$rc = 0;
		}

		$desc = $gdesc;
	}

	if($type eq "" || $type eq "-") {
		$type = "OEM Sensor Type $sensor_type"
	}
	if($desc eq "" || $desc eq "-") {
		$desc = "OEM Sensor Event $offset"
	}

	if($type eq $desc) {
		$desc = "";
	}

	my $extra_info = getaddsensorevent($sensor_type,$offset,$event_data_1,$event_data_2,$event_data_3);
	if($extra_info) {
		if($desc) {
			$desc = "$desc $extra_info";
		}
		else {
			$desc = "$extra_info";
		}
	}

	$text = "$text $type,";
	$text = "$text $desc";

	my $key;
	my $sensor_desc = sprintf("Sensor 0x%02x",$sensor_num);
    my %sdr_hash = %{$sessdata->{sdr_hash}};
	foreach $key (keys %sdr_hash) {
		my $sdr = $sdr_hash{$key};
		if($sdr->sensor_number == $sensor_num  and $sdr->rec_type != 192 and $sdr->rec_type != 17) {
			$sensor_desc = $sdr_hash{$key}->id_string;
			if($sdr->rec_type == 0x01) {
				last;
			}
		}
	}

	$text = "$text ($sensor_desc)";

	if($event_dir) {
		$text = "$text - Recovered";
	}

	return(0,$text);
}

sub readauxentry {
    my $netfn=0x2e<<2;
    my $entrynum = shift;
    my $entryls = ($entrynum&0xff);
    my $entryms = ($entrynum>>8);
    my @cmd = (0x93,0x4d,0x4f,0x00,$entryls,$entryms,0,0,0xff,0x5); #Get log size andup to 1275 bytes of data, keeping it under 1500 to accomodate mixed-mtu circumstances
    my @data;
    my $error = docmd(
        $netfn,
        \@cmd,
        \@data
        );
    if ($error) { return $error; }
    if ($data[0]) { return $data[0]; }
    my $text;
    unless ($data[1] == 0x4d and $data[2] == 0x4f and $data[3] == 0) { return "Unrecognized response format" }
    $entrynum=$data[6]+($data[7]<<8);
    if (($data[10]&1) == 1) {
        $text="POSSIBLY INCOMPLETE DATA FOLLOWS:\n";
    }
    my $addtext="";
    if ($data[5] > 5) {
        $addtext="\nTODO:SUPPORT MORE DATA THAT WAS SEEN HERE";
    }
    @data = splice @data,11;
    pop @data;
    while(scalar(@data)) {
        my @subdata = splice @data,0,30;
        my $numbytes = scalar(@subdata);
        my $formatstring="%02x"x$numbytes;
        $formatstring =~ s/%02x%02x/%02x%02x /g;
        $text.=sprintf($formatstring."\n",@subdata);
    }
    $text.=$addtext;
    return (0,$entrynum,$text);


}



sub eventlog {
    my $sessdata = shift;
	my $subcommand = $sessdata->{subcommand};
        my $cmdargv = $sessdata->{extraargs};
    unless ($sessdata) { die "not fixed yet" }

	my $netfun = 0x0a;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;
	my @output;
	my $entry;
    $sessdata->{fullsel}=0;
	my @sel;
	my $mfg_id;
	my $prod_id;
	my $device_id;

#device id needed here
	$rc=0;
#reventlog <node> [[all] [-s] | <num> [-s]| clear]
        $subcommand = undef;
        my $arg = shift(@$cmdargv);
        while ($arg) {
            if ($arg eq "all" or $arg eq "clear" or $arg =~ /^\d+$/) {
                if (defined($subcommand)) {
                    return(1,"revenglog $subcommand $arg invalid");
                }
                $subcommand = $arg;
            } elsif ($arg =~ /^-s$/) {
                $sessdata->{sort}=1;
            } else {
                return(1,"unsupported command eventlog $arg");
            } 
            $arg = shift(@$cmdargv);
        }        

   unless (defined($subcommand)) {
      $subcommand = 'all';
   }
	if($subcommand eq "all") {
         $sessdata->{fullsel}=1;
	}
	elsif($subcommand eq "clear") {
            if (exists($sessdata->{sort})) {
                return(1,"option \"first\" can not work with $subcommand");
            }
	}
	elsif($subcommand =~ /^\d+$/) {
        $sessdata->{numevents} = $subcommand;
	$sessdata->{displayedevents} = 0;
	}
	else {
		return(1,"unsupported command eventlog $subcommand");
	}
        $sessdata->{subcommand} = $subcommand;
    $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x48,data=>[],callback=>\&eventlog_with_time,callback_args=>$sessdata);
}
sub eventlog_with_time {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    my @returnd = (0,@{$rsp->{data}});

   #Here we set tfactor based on the delta between the BMC reported time and our
   #time.  The IPMI spec says the BMC should return seconds since 1970 in local
   #time, but the reality is the firmware pushing to the BMC has no context
   #to know, so here we guess and adjust all timestamps based on delta between
   #our now and the BMC's now
   $sessdata->{tfactor} = $returnd[4]<<24 | $returnd[3]<<16 | $returnd[2]<<8 | $returnd[1];
   if ($sessdata->{tfactor} > 0x20000000) {
      $sessdata->{tfactor} -= time(); 
   } else {
      $sessdata->{tfactor} = 0;
   }
   $sessdata->{ipmisession}->subcmd(netfn=>0x0a,command=>0x40,data=>[],callback=>\&eventlog_with_selinfo,callback_args=>$sessdata);
}
sub eventlog_with_selinfo {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
	my $code = $rsp->{code}; 
    my @returnd = (0,@{$rsp->{data}});

	#sif($code == 0x81) { 
	#	$rc = 1;
	#	$text = "cannot execute command, SEL erase in progress";
	#}

	my $sel_version = $returnd[1];
	if($sel_version != 0x51) {
		xCAT::SvrUtils::sendmsg(sprintf("SEL version 51h support only, version reported: %x",$sel_version),$callback,$sessdata->{node},%allerrornodes);
		return;
	}

    hexdump(\@returnd);
	my $num_entries = ($returnd[3]<<8) + $returnd[2];
	if($num_entries <= 0) {
		xCAT::SvrUtils::sendmsg("no SEL entries",$callback,$sessdata->{node},%allerrornodes);
        return;
	}

	my $canres = $returnd[14] & 0b00000010;
	if(!$canres) {
        xCAT::SvrUtils::sendmsg([1,"SEL reservation not supported"],$callback,$sessdata->{node},%allerrornodes);
        return;
	}

    my $subcommand = $sessdata->{subcommand};
    if ($subcommand =~ /clear/) { #Don't bother with a reservation unless a clear is involved
        #atomic SEL retrieval need not require it, so an event during retrieval will not kill reventlog effort off
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x42,data=>[],callback=>\&clear_sel_with_reservation,callback_args=>$sessdata);
        return;
    } elsif ($sessdata->{mfg_id} == 2) {
        #read_ibm_auxlog($sessdata); #TODO JBJ fix this back in
        #return;
        #For requests other than clear, we check for IBM extended auxillary log data
    }
    $sessdata->{selentries} = [];
    $sessdata->{selentry}=0;
    if (exists($sessdata->{sort})) {
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x43,data=>[0,0,0xFF,0xFF,0x00,0xFF],callback=>\&got_sel,callback_args=>$sessdata);
    } else {
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x43,data=>[0,0,0x00,0x00,0x00,0xFF],callback=>\&got_sel,callback_args=>$sessdata);
    }
}
sub got_sel {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    my @returnd = (0,@{$rsp->{data}});
		#elsif($code == 0x81) {
		#	$rc = 1;
		#	$text = "cannot execute command, SEL erase in progress";
		#}


	my $next_rec_ls;
	my $next_rec_ms;
	my @sel_data = @returnd[3..19];
        if (exists($sessdata->{sort})) {
            $next_rec_ls = $sel_data[0] - 1;
            $next_rec_ms = $sel_data[1];
            if (($next_rec_ls < 0) && ($next_rec_ms > 0)) {
                $next_rec_ls += 256;
                $next_rec_ms -= 1;
            }
        } else {
            $next_rec_ls = $returnd[1];
            $next_rec_ms = $returnd[2];
        }
		$sessdata->{selentry}+=1;
        if ($debug) {
			print $sessdata->{selentry}.": ";
			hexdump(\@sel_data);
        }

		my $record_id = $sel_data[0] + $sel_data[1]*256;
		my $record_type = $sel_data[2];

		if($record_type == 0x02) {
		}
		else {
			my $text=getoemevent($record_type,$sessdata->{mfg_id},\@sel_data);
            my $entry =  $sessdata->{selentry};
            if ($sessdata->{auxloginfo} and $sessdata->{auxloginfo}->{$entry}) { 
                $text.=" With additional data:\n".$sessdata->{auxloginfo}->{$entry};
            }
            if ($sessdata->{fullsel}) {
               xCAT::SvrUtils::sendmsg($text,$callback,$sessdata->{node},%allerrornodes);
            } else {
			    push(@{$sessdata->{selentries}},$text);
            }
			if(($next_rec_ms == 0xFF && $next_rec_ls == 0xFF) or 
                           ($next_rec_ms == 0x0 && $next_rec_ls == 0x0)) {
				sendsel($sessdata);
                return;
			}
            $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x43,data=>[0,0,$next_rec_ls,$next_rec_ms,0x00,0xFF],callback=>\&got_sel,callback_args=>$sessdata);
            return;
		}

		my $timestamp = ($sel_data[3] | $sel_data[4]<<8 | $sel_data[5]<<16 | $sel_data[6]<<24);
      unless ($timestamp < 0x20000000) { #IPMI Spec says below this is effectively BMC uptime, not correctable
         $timestamp -= $sessdata->{tfactor}; #apply correction factor based on how off the current BMC clock is from management server
      }
		my ($seldate,$seltime) = timestamp2datetime($timestamp);
#		$text = "$entry: $seldate $seltime";
		my $text = ":$seldate $seltime";

#		my $gen_id_slave_addr = ($sel_data[7] & 0b11111110) >> 1;
#		my $gen_id_slave_addr_hs = ($sel_data[7] & 0b00000001);
#		my $gen_id_ch_num = ($sel_data[8] & 0b11110000) >> 4;
#		my $gen_id_ipmb = ($sel_data[8] & 0b00000011);

		my $sensor_owner_id = $sel_data[7];
		my $sensor_owner_lun = $sel_data[8];

		my $sensor_type = $sel_data[10];
		my $sensor_num = $sel_data[11];
		my $event_dir = $sel_data[12] & 0b10000000;
		my $event_type = $sel_data[12] & 0b01111111;
		my $offset = $sel_data[13] & 0b00001111;
		my $event_data_1 = $sel_data[13];
		my $event_data_2 = $sel_data[14];
		my $event_data_3 = $sel_data[15];
		my $sev = 0;
		$sev = ($sel_data[14] & 0b11110000) >> 4;
#		if($event_type != 1) {
#			$sev = ($sel_data[14] & 0b11110000) >> 4;
#		}
#		$text = "$text $sev:";

		my $type;
		my $desc;
        my $rc;
		($rc,$type,$desc) = getsensorevent($sensor_type,$offset,"ipmisensorevents");
		if($rc == 1) {
			$type = "Unknown Type $sensor_type";
			$desc = "Unknown Event $offset";
			$rc = 0;
		}

		if($event_type <= 0x0c) {
			my $gtype;
			my $gdesc;
			($rc,$gtype,$gdesc) = getsensorevent($event_type,$offset,"ipmigenericevents");
			if($rc == 1) {
				$gtype = "Unknown Type $gtype";
				$gdesc = "Unknown Event $offset";
				$rc = 0;
			}

			$desc = $gdesc;
		}

		if($type eq "" || $type eq "-") {
			$type = "OEM Sensor Type $sensor_type"
		}
		if($desc eq "" || $desc eq "-") {
			$desc = "OEM Sensor Event $offset"
		}

		if($type eq $desc) {
			$desc = "";
		}

		my $extra_info = getaddsensorevent($sensor_type,$offset,$event_data_1,$event_data_2,$event_data_3);
		if($extra_info) {
			if($desc) {
				$desc = "$desc $extra_info";
			}
			else {
				$desc = "$extra_info";
			}
		}

		$text = "$text $type,";
		$text = "$text $desc";

#		my $key;
		my $key = $sensor_owner_id . "." . $sensor_owner_lun . "." . $sensor_num;
		my $sensor_desc = sprintf("Sensor 0x%02x",$sensor_num);
#		foreach $key (keys %sdr_hash) {
#			my $sdr = $sdr_hash{$key};
#			if($sdr->sensor_number == $sensor_num) {
#				$sensor_desc = $sdr_hash{$key}->id_string;
#				last;
#			}
#		}
        my %sdr_hash = %{$sessdata->{sdr_hash}};
		if(defined $sdr_hash{$key}) {
			$sensor_desc = $sdr_hash{$key}->id_string;
         if ($sdr_hash{$key}->event_type_code == 1) {
            if (($event_data_1 & 0b11000000) == 0b01000000) {
               $sensor_desc .= " reading ".translate_sensor($event_data_2,$sdr_hash{$key});
               if (($event_data_1 & 0b00110000) == 0b00010000) {
                  $sensor_desc .= " with threshold " . translate_sensor($event_data_3,$sdr_hash{$key});
               }
            }
         }
		}

		$text = "$text ($sensor_desc)";

		if($event_dir) {
			$text = "$text - Recovered";
		}
        my $entry = $sessdata->{selentry};
        if ($sessdata->{bmcnum} !=1) {
		$text .= " on BMC ".$sessdata->{bmcnum};
	}
        if ($sessdata->{auxloginfo} and $sessdata->{auxloginfo}->{$entry}) {
             $text.=" with additional data:";
             if ($sessdata->{fullsel} || ( $sessdata->{numevents}
	        && $sessdata->{numevents} > $sessdata->{displayedevents})) {
                xCAT::SvrUtils::sendmsg($text,$callback,$sessdata->{node},%allerrornodes);
                foreach (split /\n/,$sessdata->{auxloginfo}->{$entry}) {
                    xCAT::SvrUtils::sendmsg($_,$sessdata->{node});
                }
                $sessdata->{displayedevents}++;
             } else {
        		push(@{$sessdata->{selentries}},$text);
                push @{$sessdata->{selentries}},split /\n/,$sessdata->{auxloginfo}->{$entry};
             } 

        } else {
            if ($sessdata->{fullsel} || ($sessdata->{numevents}
	        && $sessdata->{numevents} > $sessdata->{displayedevents})) {
                xCAT::SvrUtils::sendmsg($text,$callback,$sessdata->{node},%allerrornodes);
		$sessdata->{displayedevents}++;
            } else {
        		push(@{$sessdata->{selentries}},$text);
            }
        }

		if(($next_rec_ms == 0xFF && $next_rec_ls == 0xFF) or 
                   ($next_rec_ms == 0x0 && $next_rec_ls == 0x0)) {
				sendsel($sessdata);
                return;
		}
        $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x43,data=>[0,0,$next_rec_ls,$next_rec_ms,0x00,0xFF],callback=>\&got_sel,callback_args=>$sessdata);
}

sub sendsel {
    my $sessdata = shift;
####my @routput = reverse(@output);
####my @noutput;
####my $c;
####foreach(@routput) {
####	$c++;
####	if($c > $num) {
####		last;
####	}
####	push(@noutput,$_);
####}
####@output = reverse(@noutput);

####return($rc,@output);
}
sub clear_sel_with_reservation {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
    my @returnd = (0,@{$rsp->{data}});
    	#elsif($code == 0x81) {
    	#	$rc = 1;
    	#	$text = "cannot execute command, SEL erase in progress";
    	#}
        $sessdata->{res_id_ls} = $returnd[1];
        $sessdata->{res_id_ms} = $returnd[2];
    $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x47,data=>[$sessdata->{res_id_ls},$sessdata->{res_id_ms},0x43,0x4c,0x52,0xaa],callback=>\&wait_for_selerase,callback_args=>$sessdata);
}
sub wait_for_selerase {
    my $rsp = shift;
    my $sessdata = shift;
    my @returnd = (0,@{$rsp->{data}});
	my $erase_status = $returnd[1] & 0b00000001;
    xCAT::SvrUtils::sendmsg("SEL cleared",$callback,$sessdata->{node},%allerrornodes);
}

#commenting out usless 'while 0' loop.
#skip test for now, need to get new res id for some machines
#   	while($erase_status == 0 && 0) {
#   		sleep(1);
#   		@cmd=(0x47,$res_id_ls,$res_id_ms,0x43,0x4c,0x52,0x00);
#   		$error = docmd(
#   			$netfun,
#   			\@cmd,
#   			\@returnd
#   		);

#   		if($error) {
#   			$rc = 1;
#   			$text = $error;
#   			return($rc,$text);
#   		}

#   		$code = $returnd[0];

#   		if($code == 0x00) {
#   		}
#   		else {
#   			$rc = 1;
#   			$text = $codes{$code};
#   		}

#   		if($rc != 0) {
#   			if(!$text) {
#   				$text = sprintf("unknown response %02x",$code);
#   			}
#   			return($rc,$text);
#   		}

#   		$erase_status = $returnd[1] & 0b00000001;
#   	}

sub read_ibm_auxlog {
    my $sessdata = shift;
    my $entry = $sessdata->{selentry};
        my @auxdata;
        my $netfn = 0xa << 2;
        my @auxlogcmd = (0x5a,1);
        my $error = docmd(
            $netfn,
            \@auxlogcmd,
            \@auxdata);
        #print Dumper(\@auxdata);
        unless ($error or $auxdata[0] or $auxdata[5] != 0x4d or $auxdata[6] != 0x4f or $auxdata[7] !=0x0 ) { #Don't bother if support cannot be confirmed by service processor
            $netfn=0x2e<<2; #switch netfunctions to read
            my $numauxlogs = $auxdata[8]+($auxdata[9]<<8);
            my $auxidx=1;
            my $rc;
            my $entry;
            my $extdata;
            while ($auxidx<=$numauxlogs) {
                ($rc,$entry,$extdata) = readauxentry($auxidx++);
                unless ($rc) {
                    if ($sessdata->{auxloginfo}->{$entry}) {
                        $sessdata->{auxloginfo}->{$entry}.="!".$extdata;
                    } else {
                        $sessdata->{auxloginfo}->{$entry}=$extdata;
                    }
                }
            }
            if ($sessdata->{auxloginfo}->{0}) {
                if ($sessdata->{fullsel}) {
                    foreach (split /!/,$sessdata->{auxloginfo}->{0}) {
                        sendoutput(0,":Unassociated auxillary data detected:");
                        foreach (split /\n/,$_) {
                            sendoutput(0,$_);
                        }
                    }
                }
            }
            #print Dumper(\%auxloginfo);
        }
}

sub getoemevent {
	my $record_type = shift;
	my $mfg_id = shift;
	my $sel_data = shift;
    my $sessdata;
	my $text=":";
	if ($record_type < 0xE0 && $record_type > 0x2F) { #Should be timestampped, whatever it is
		my $timestamp =  (@$sel_data[3] | @$sel_data[4]<<8 | @$sel_data[5]<<16 | @$sel_data[6]<<24);
      unless ($timestamp < 0x20000000) {
         $timestamp -= $sessdata->{tfactor};
      }
		my ($seldate,$seltime) = timestamp2datetime($timestamp);
		my @rest = @$sel_data[7..15];
		if ($mfg_id==2) {
			$text.="$seldate $seltime IBM OEM Event-";
			if ($rest[3]==0 && $rest[4]==0 && $rest[7]==0) {
				$text=$text."PCI Event/Error, details in next event"
			} elsif ($rest[3]==1 && $rest[4]==0 && $rest[7]==0) {
				$text=$text."Processor Event/Error occurred, details in next event"
			} elsif ($rest[3]==2 && $rest[4]==0 && $rest[7]==0) {
				$text=$text."Memory Event/Error occurred, details in next event"
			} elsif ($rest[3]==3 && $rest[4]==0 && $rest[7]==0) {
				$text=$text."Scalability Event/Error occurred, details in next event"
			} elsif ($rest[3]==4 && $rest[4]==0 && $rest[7]==0) {
				$text=$text."PCI bus Event/Error occurred, details in next event"
			} elsif ($rest[3]==5 && $rest[4]==0 && $rest[7]==0) {
				$text=$text."Chipset Event/Error occurred, details in next event"
			} elsif ($rest[3]==6 && $rest[4]==1 && $rest[7]==0) {
				$text=$text."BIOS/BMC Power Executive mismatch (BIOS $rest[5], BMC $rest[6])"
			} elsif ($rest[3]==6 && $rest[4]==2 && $rest[7]==0) {
				$text=$text."Boot denied due to power limitations"
			} else {
				$text=$text."Unknown event ". phex(\@rest);
			}
		} else {
		     $text .= "$seldate $seltime " . sprintf("Unknown OEM SEL Type %02x:",$record_type) . phex(\@rest);
		}
	} else { #Non-timestamped
		my %memerrors = (
			0x00 => "DIMM enabled",
			0x01 => "DIMM disabled, failed ECC test",
			0x02 => "POST/BIOS memory test failed, DIMM disabled",
			0x03 => "DIMM disabled, non-supported memory device",
			0x04 => "DIMM disabled, non-matching or missing DIMM(s)",
		);
		my %pcierrors = (
			0x00 => "Device OK",
			0x01 => "Required ROM space not available",
			0x02 => "Required I/O Space not available",
			0x03 => "Required memory not available",
			0x04 => "Required memory below 1MB not available",
			0x05 => "ROM checksum failed",
			0x06 => "BIST failed",
			0x07 => "Planar device missing or disabled by user",
			0x08 => "PCI device has an invalid PCI configuration space header",
			0x09 => "FRU information for added PCI device",
			0x0a => "FRU information for removed PCI device",
			0x0b => "A PCI device was added, PCI FRU information is stored in next log entry",
			0x0c => "A PCI device was removed, PCI FRU information is stored in next log entry",
			0x0d => "Requested resources not available",
			0x0e => "Required I/O Space Not Available",
			0x0f => "Required I/O Space Not Available",
			0x10 => "Required I/O Space Not Available",
			0x11 => "Required I/O Space Not Available",
			0x12 => "Required I/O Space Not Available",
			0x13 => "Planar video disabled due to add in video card",
			0x14 => "FRU information for PCI device partially disabled ",
			0x15 => "A PCI device was partially disabled, PCI FRU information is stored in next log entry",
			0x16 => "A 33Mhz device is installed on a 66Mhz bus, PCI device information is stored in next log entry",
			0x17 => "FRU information, 33Mhz device installed on 66Mhz bus",
			0x18 => "Merge cable missing",
			0x19 => "Node 1 to Node 2 cable missing",
			0x1a => "Node 1 to Node 3 cable missing",
			0x1b => "Node 2 to Node 3 cable missing",
			0x1c => "Nodes could not merge",
			0x1d => "No 8 way SMP cable",
			0x1e => "Primary North Bridge to PCI Host Bridge IB Link has failed",
			0x1f => "Redundant PCI Host Bridge IB Link has failed",
		);
		my %procerrors = (
			0x00 => "Processor has failed BIST",
			0x01 => "Unable to apply processor microcode update",
			0x02 => "POST does not support current stepping level of processor",
			0x03 => "CPU mismatch detected",
		);
		my @rest = @$sel_data[3..15];
		if ($record_type == 0xE0 && $rest[0]==2 && $mfg_id==2 && $rest[1]==0 && $rest[12]==1) { #Rev 1 POST memory event
			$text="IBM Memory POST Event-";
			my $msuffix=sprintf(", chassis %d, card %d, dimm %d",$rest[3],$rest[4],$rest[5]);
			#the next bit is a basic lookup table, should implement as a table ala ibmleds.tab, or a hash... yeah, a hash...
			$text=$text.$memerrors{$rest[2]}.$msuffix;
		} elsif ($record_type == 0xE0 && $rest[0]==1 && $mfg_id==2 && $rest[12]==0) { #A processor error or event, rev 0 only known in the spec I looked at
			$text=$text.$procerrors{$rest[1]};
		} elsif ($record_type == 0xE0 && $rest[0]==0 && $mfg_id==2) { #A PCI error or event, rev 1 or 2, the revs differe in endianness
			my $msuffix;
			if ($rest[12]==0) {
				$msuffix=sprintf("chassis %d, slot %d, bus %s, device %02x%02x:%02x%02x",$rest[2],$rest[3],$rest[4],$rest[5],$rest[6],$rest[7],$rest[8]);
			} elsif ($rest[12]==1) {
				$msuffix=sprintf("chassis %d, slot %d, bus %s, device %02x%02x:%02x%02x",$rest[2],$rest[3],$rest[4],$rest[5],$rest[6],$rest[7],$rest[8]);
			} else {
				return ("Unknown IBM PCI event/error format");
			}
			$text=$text.$pcierrors{$rest[1]}.$msuffix;
		} else {
			#Some event we can't define that is OEM or some otherwise unknown event
			$text = sprintf("SEL Type %02x:",$record_type) . phex(\@rest);
		}
	} #End timestampped intepretation
	return ($text);
}

sub getsensorevent
{
	my $sensortype = sprintf("%02Xh",shift);
	my $sensoroffset = sprintf("%02Xh",shift);
	my $file = shift;

	my @line;
	my $type;
	my $code;
	my $desc;
	my $offset;
	my $rc = 1;

    if ($file eq "ipmigenericevents") {
      if ($xCAT::data::ipmigenericevents::ipmigenericevents{"$sensortype,$sensoroffset"}) {
        ($type,$desc) = split (/,/,$xCAT::data::ipmigenericevents::ipmigenericevents{"$sensortype,$sensoroffset"},2);
	    return(0,$type,$desc);
      }
      if ($xCAT::data::ipmigenericevents::ipmigenericevents{"$sensortype,-"}) {
        ($type,$desc) = split (/,/,$xCAT::data::ipmigenericevents::ipmigenericevents{"$sensortype,-"},2);
	    return(0,$type,$desc);
       }
    }
    if ($file eq "ipmisensorevents") {
      if ($xCAT::data::ipmisensorevents::ipmisensorevents{"$sensortype,$sensoroffset"}) {
        ($type,$desc) = split (/,/,$xCAT::data::ipmisensorevents::ipmisensorevents{"$sensortype,$sensoroffset"},2);
	    return(0,$type,$desc);
      }
      if ($xCAT::data::ipmisensorevents::ipmisensorevents{"$sensortype,-"}) {
        ($type,$desc) = split (/,/,$xCAT::data::ipmisensorevents::ipmisensorevents{"$sensortype,-"},2);
	    return(0,$type,$desc);
       }
    }
    return (0,"No Mappings found ($sensortype)","No Mappings found ($sensoroffset)");
}

sub getaddsensorevent {
	my $sensor_type = shift;
	my $offset = shift;
	my $event_data_1 = shift;
	my $event_data_2 = shift;
	my $event_data_3 = shift;
	my $text = "";

    if ($sensor_type == 0x08 && $offset == 6) {
        my %extra = (
            0x0 => "Vendor mismatch",
            0x1 => "Revision mismatch",
            0x2 => "Processor missing",
	    0x3 => "Power Supply rating mismatch",
	    0x4 => "Voltage rating mismatch",
            );
        if ($extra{$event_data_3}) {
            $text = $extra{$event_data_3};
        }
    }
    if ($sensor_type == 0x0C) {
        $text = sprintf ("Memory module %d",$event_data_3);
    }

	if($sensor_type == 0x0f) {
		if($offset == 0x00) {
			my %extra = (
				0x00 => "Unspecified",
				0x01 => "No system memory installed",
				0x02 => "No usable system memory",
				0x03 => "Unrecoverable hard disk failure",
				0x04 => "Unrecoverable system board failure",
				0x05 => "Unrecoverable diskette failure",
				0x06 => "Unrecoverable hard disk controller failure",
				0x07 => "Unrecoverable keyboard failure",
				0x08 => "Removable boot media not found",
				0x09 => "Unrecoverable video controller failure",
				0x0a => "No video device detected",
				0x0b => "Firmware (BIOS) ROM corruption detected",
				0x0c => "CPU voltage mismatch",
				0x0d => "CPU speed matching failure",
			);
			$text = $extra{$event_data_2};
		}
		if($offset == 0x02) {
			my %extra = (
				0x00 => "Unspecified",
				0x01 => "Memory initialization",
				0x02 => "Hard-disk initialization",
				0x03 => "Secondary processor(s) initialization",
				0x04 => "User authentication",
				0x05 => "User-initiated system setup",
				0x06 => "USB resource configuration",
				0x07 => "PCI resource configuration",
				0x08 => "Option ROM initialization",
				0x09 => "Video initialization",
				0x0a => "Cache initialization",
				0x0b => "SM Bus initialization",
				0x0c => "Keyboard controller initialization",
				0x0d => "Embedded controller/management controller initialization",
				0x0e => "Docking station attachement",
				0x0f => "Enabling docking station",
				0x10 => "Docking staion ejection",
				0x11 => "Disable docking station",
				0x12 => "Calling operating system wake-up vector",
				0x13 => "Starting operating system boot process, call init 19h",
				0x14 => "Baseboard or motherboard initialization",
				0x16 => "Floppy initialization",
				0x17 => "Keyboard test",
				0x18 => "Pointing device test",
				0x19 => "Primary processor initialization",
			);
			$text = $extra{$event_data_2};
		}
	}
    if ($sensor_type == 0x10) {
        if ($offset == 0x0) {
            $text = sprintf("Memory module %d",$event_data_2);
        } elsif ($offset == 0x01) {
            $text = "Disabled for ";
            unless ($event_data_3 & 0x20) {
                if ($event_data_3 & 0x10) {
                    $text .= "assertions of";
                } else {
                    $text .= "deassertions of";
                } 
            }
            $text .= sprintf ("type %02xh/offset %02xh",$event_data_2,$event_data_3&0x0F);
        } elsif ($offset == 0x05) {
            $text = "$event_data_3% full";
        }elsif($offset==0x06){
	    if(defined $event_data_2){
	    	if(defined($event_data_3) and ($event_data_3 & 0x80 == 0x80)){
			$text="Vendor-specific processor number:";
	    	}else{
	        	$text="Entity Instance number:";
	   	}
		$text.=sprintf("%02xh",$event_data_2 & 0xff);
	    }else{
		$text="for all Processor sensors";
	    }
	}
    }
            
	if($sensor_type == 0x12) {
		if($offset == 0x03) {
			my %extra={
				    0x0 => "Log Entry Action: entry added",
				    0x1 => "Log Entry Action: entry added because event did not be map to standard IPMI event",
				    0x2 => "Log Entry Action: entry added along with one or more corresponding SEL entries",
				    0x3 => "Log Entry Action: log cleared",
				    0x4 => "Log Entry Action: log disabled",
				    0x5 => "Log Entry Action: log enabled",
				  };
			$text="$text, ".$extra{($event_data_2>>4) & 0x0f};
			%extra={
				   0x0 => "Log Type:MCA Log",
				   0x1 => "Log Type:OEM 1",
				   0x2 => "Log Type:OEM 2",
				};
			$text="$text, ".$extra{($event_data_2) & 0x0f};
			$text =~ s/^, //;
		}

		if($offset == 0x04) {
			if($event_data_2 & 0b00100000) {
				$text = "$text, NMI";
			}
			if($event_data_2 & 0b00010000) {
				$text = "$text, OEM action";
			}
			if($event_data_2 & 0b00001000) {
				$text = "$text, power cycle";
			}
			if($event_data_2 & 0b00000100) {
				$text = "$text, reset";
			}
			if($event_data_2 & 0b00000010) {
				$text = "$text, power off";
			}
			if($event_data_2 & 0b00000001) {
				$text = "$text, Alert";
			}
			$text =~ s/^, //;
		}
	        if($offset == 0x05){
			if($event_data_2 & 0x80){
				$text="$text, event is second of pair";
			}elsif($event_data_2 & 0x80==0){
				$text="$text, event is first of pair";
			}		
			if($event_data_2 & 0x0F == 0x1){
				$text="$text, SDR Timestamp Clock updated";	
			}elsif($event_data_2 & 0x0F == 0x0){
				 $text="$text, SEL Timestamp Clock updated";
			}
			$text =~ s/^, //;
		}
     }

    if ($sensor_type == 0x1d && $offset == 0x07) {
        my %causes = (
            0 => "Unknown",
            1 => "Chassis reset via User command to BMC",
            2 => "Reset button",
            3 => "Power button",
            4 => "Watchdog action",
            5 => "OEM",
            6 => "AC Power apply force on",
            7 => "Restore previous power state on AC",
            8 => "PEF initiated reset",
            9 => "PEF initiated power cycle",
            10 => "Soft reboot",
            11 => "RTC Wake",
        );
        if ($causes{$event_data_2 & 0xf}) {
            $text = $causes{$event_data_2};
        } else {
            $text = "Unrecognized cause ".$event_data_2 & 0xf;
        }
        $text .= "via channel $event_data_3";
    }
    if ($sensor_type == 0x21) {
        my %extra = (
            0 => "PCI slot",
            1 => "Drive array",
            2 => "External connector",
            3 => "Docking port",
            4 => "Other slot",
            5 => "Sensor ID",
            6 => "AdvncedTCA",
            7 => "Memory slot",
            8 => "FAN",
            9 => "PCIe",
            10 => "SCSI",
            11 => "SATA/SAS",
         );

        $text=$extra{$event_data_2 & 127};
        unless ($text) {
            $text = "Unknown slot/conn type ".$event_data_2&127;
        }
        $text .= " $event_data_3";
    }
    if ($sensor_type == 0x23) {
        my %extra = (
            0x10 => "SMI",
            0x20 => "NMI",
            0x30 => "Messaging Interrupt",
            0xF0 => "Unspecified",
            0x01 => "BIOS FRB2",
            0x02 => "BIOS/POST",
            0x03 => "OS Load",
            0x04 => "SMS/OS",
            0x05 => "OEM",
            0x0F => "Unspecified"
        );
        if ($extra{$event_data_2 & 0xF0}) {
            $text = $extra{$event_data_2 & 0xF0};
        }
        if ($extra{$event_data_2 & 0x0F}) {
            $text .= ", ".$extra{$event_data_2 & 0x0F};
        }
        $text =~ s/^, //;
    }
    if ($sensor_type == 0x28) {
        if ($offset == 0x4) {
            $text = "Sensor $event_data_2";
        } elsif ($offset == 0x5) {
            $text = "";
            my $logicalfru=0;
            if ($event_data_2 & 128) {
                $logicalfru=1;
            }
            my $intelligent=1;
            if ($event_data_2 & 24) {
                $text .= "LUN ".($event_data_2&24)>>3;
            } else {
                $intelligent=0;
            }
            if ($event_data_2 & 7) {
                $text .= "Bus ID ".($event_data_2&7);
            }
            if ($logicalfru) {
                $text .= "FRU ID ".$event_data_3;
            } elsif (not $intelligent) {
                $text .= "I2C addr ".$event_data_3>>1;
            }
        }
    }

    if ($sensor_type == 0x2a) {
        $text = sprintf("Channel %d, User %d",$event_data_3&0x0f,$event_data_2&0x3f);
        if ($offset == 1) {
            if (($event_data_3 & 207) == 1) {
                $text .= " at user request";
            } elsif (($event_data_3 & 207) == 2) {
                $text .= " timed out";
            } elsif (($event_data_3 & 207) == 3) {
                $text .= " configuration change";
            }
        }
    }
    if ($sensor_type == 0x2b) {
        my %extra = (
            0x0 => "Unspecified",
            0x1 => "BMC device ID",
            0x2 => "BMC Firmware",
            0x3 => "BMC Hardware",
            0x4 => "BMC manufacturer",
            0x5 => "IPMI Version",
            0x6 => "BMC aux firmware ID",
            0x7 => "BMC boot block",
            0x8 => "Other BMC Firmware",
            0x09 => "BIOS/EFI change",
            0x0a => "SMBIOS change",
            0x0b => "OS change",
            0x0c => "OS Loader change",
            0x0d => "Diagnostics change",
            0x0e => "Management agent change",
            0x0f => "Management software change",
            0x10 => "Management middleware change",
            0x11 => "FPGA/CPLD/PSoC change",
            0x12 => "FRU change",
            0x13 => "device addition/removal",
            0x14 => "Equivalent replacement",
            0x15 => "Newer replacement",
            0x16 => "Older replacement",
            0x17 => "DIP/Jumper change",
        );
        if ($extra{$event_data_2}) {
            $text = $extra{$event_data_2};
        } else {
            $text = "Unknown version change type $event_data_2";
        }
    }
    if ($sensor_type == 0x2c) {
        my %extra = (
            0 => "",
            1 => "Software dictated",
            2 => "Latch operated",
            3 => "Hotswap buton pressed",
            4 => "automatic operation",
            5 => "Communication lost",
            6 => "Communication lost locally",
            7 => "Unexpected removal",
            8 => "Operator intervention",
            9 => "Unknwon IPMB address",
            10 => "Unexpected deactivation",
            0xf => "unknown",
            );
        if ($extra{$event_data_2>>4}) {
              $text = $extra{$event_data_2>>4};
          } else {
              $text = "Unrecognized cause ".$event_data_2>>4;
          }
          my $prev_state=$event_data_2 & 0xf;
          unless ($prev_state == $offset) {
              my %oldstates = ( 
                0 => "Not Installed",
                1 => "Inactive",
                2 => "Activation requested",
                3 => "Activating",
                4 => "Active",
                5 => "Deactivation requested",
                6 => "Deactivating",
                7 => "Communication lost",
            );
            if ($oldstates{$prev_state}) {
                $text .= "(was ".$oldstates{$prev_state}.")";
            } else {
                $text .= "(was in unrecognized state $prev_state)";
            }
          }
    }



	return($text);
}

sub initiem {
    my $sessdata = shift;
    $sessdata->{iem} =  IBM::EnergyManager->new();
    my @payload = $sessdata->{iem}->get_next_payload();
    my $netfun = shift @payload;
    my $command = shift @payload;
    $sessdata->{ipmisession}->subcmd(netfn=>$netfun,command=>$command,data=>\@payload,callback=>\&ieminitted,callback_args=>$sessdata);
}
sub ieminitted {
    my $rsp = shift;
    my $sessdata = shift;
    my @returnd = ($rsp->{code},@{$rsp->{data}});
    $sessdata->{iem}->handle_next_payload(@returnd);
    $sessdata->{iemcallback}->($sessdata);
}

sub readenergy {
    my $sessdata = shift;
    unless ($iem_support) { 
        xCAT::SvrUtils::sendmsg([1,"IBM::EnergyManager package required for this value"],$callback,$sessdata->{node},%allerrornodes);
        return;
    }
    my @entries;
    $sessdata->{iemcallback}=\&readenergy_withiem;
    initiem($sessdata);
}
sub readenergy_withiem {
    my $sessdata = shift;
    $sessdata->{iem}->prep_get_precision();
    $sessdata->{iemcallback} = \&got_precision;
    execute_iem_commands($sessdata); #this gets all precision data initialized for AC and DC
					# we need not make use of the generic extraction function, so we call execute_iem instead of process_data
					#sorry the perl api I wrote sucks..
}
sub got_precision {
    my $sessdata = shift;
    $sessdata->{iem}->prep_get_ac_energy();
    $sessdata->{iemcallback} = \&got_ac_energy;
    process_data_from_iem($sessdata);
}
sub got_ac_energy {
    my $sessdata = shift;
    unless ($sessdata->{abortediem}) {
    	$sessdata->{iemtextdata} .= sprintf(" +/-%.1f%%",$sessdata->{iem}->energy_ac_precision()*0.1); #note while \x{B1} would be cool, it's non-trivial to support
	xCAT::SvrUtils::sendmsg($sessdata->{iemtextdata},$callback,$sessdata->{node},%allerrornodes);
	$sessdata->{abortediem}=0;
   }
   #this would be 'if sessdata->{abortediem}'.  Thus far this is only triggered in the case of a system that fairly obviously
   #shouldn't have an AC meter.  As a consequence, don't output data that would suggest a user might actually get it
   #in that case, another entity can provide a measure of the AC usage, but only an aggregate measure not an individual measure
#        $sessdata->{iemtextdata} = "AC Energy Usage: ";
#        if ($sessdata->{abortediemreason}) {
#             $sessdata->{iemtextdata} .= $sessdata->{abortediemreason};
#         }
#        xCAT::SvrUtils::sendmsg($sessdata->{iemtextdata},$callback,$sessdata->{node},%allerrornodes);
    $sessdata->{iem}->prep_get_dc_energy();
    $sessdata->{iemcallback} = \&got_dc_energy;
    process_data_from_iem($sessdata);
}
sub got_ac_energy_with_precision {
    my $sessdata=shift;
    $sessdata->{iemtextdata} .= sprintf(" +/-%.1f%%",$sessdata->{iem}->energy_ac_precision()*0.1); #note while \x{B1} would be cool, it's non-trivial to support
    xCAT::SvrUtils::sendmsg($sessdata->{iemtextdata},$callback,$sessdata->{node},%allerrornodes);
    $sessdata->{iem}->prep_get_dc_energy();
    $sessdata->{iemcallback} = \&got_dc_energy;
    process_data_from_iem($sessdata);
}
sub got_dc_energy {
    my $sessdata = shift;
    $sessdata->{iemtextdata} .= sprintf(" +/-%.1f%%",$sessdata->{iem}->energy_dc_precision()*0.1);
    xCAT::SvrUtils::sendmsg($sessdata->{iemtextdata},$callback,$sessdata->{node},%allerrornodes);
    if (scalar @{$sessdata->{sensorstoread}}) {
        $sessdata->{currsdr} = shift @{$sessdata->{sensorstoread}};
        readsensor($sessdata); #next sensor
    }

}

sub execute_iem_commands {
    my $sessdata = shift;
    my @payload = $sessdata->{iem}->get_next_payload();
    if (scalar @payload) {
        my $netfun = shift @payload;
        my $command = shift @payload;
        $sessdata->{ipmisession}->subcmd(netfn=>$netfun,command=>$command,data=>\@payload,callback=>\&executed_iem_command,callback_args=>$sessdata);
    } else { #complete, return to callback
        $sessdata->{iemcallback}->($sessdata);
    }
}
sub executed_iem_command {
    my $rsp = $_[0];
    my $sessdata = $_[1];
    if ($rsp->{code} == 0xcb) {
	$sessdata->{abortediem}=1;
	$sessdata->{abortediemreason}="Not Present";
	$sessdata->{iemcallback}->($sessdata);
        return;	
    }
    if (check_rsp_errors(@_)) { #error while in an IEM transaction, skip to the end
	$sessdata->{abortediem}=1;
	$sessdata->{iemcallback}->($sessdata);
        return;
    }
    my @returnd = ($rsp->{code},@{$rsp->{data}});
    $sessdata->{iem}->handle_next_payload(@returnd);
    execute_iem_commands($sessdata);
}

sub process_data_from_iem {
    my $sessdata = shift;
    
    my @returnd;
    $sessdata->{iemdatacallback} = $sessdata->{iemcallback};
    $sessdata->{iemcallback} = \&got_data_to_process_from_iem;
    execute_iem_commands($sessdata);
}
sub got_data_to_process_from_iem {
    my $sessdata = shift;
    my @iemdata = $sessdata->{iem}->extract_data;
    my $label = shift @iemdata;
    my $units = shift @iemdata;
    my $value=0;
    my $shift=0;
    while (scalar @iemdata) { #stuff the 64-bits of data into an int, would break in 32 bit
        $value+=pop(@iemdata)<<$shift;
        #$value.=sprintf("%02x ",shift @iemdata);
        $shift+=8;
    }
    if ($units eq "mJ") {
        $units = "kWh";
        $value = $value / 3600000000;
        $sessdata->{iemtextdata} = sprintf("$label: %.4f $units",$value);
    } elsif ($units eq "mW") {
        $units = "W";
        $value = $value / 1000.0;
        $sessdata->{iemtextdata} = sprintf("$label: %.1f $units",$value);
    }
    $sessdata->{iemdatacallback}->($sessdata);
}

sub gotchassis { #get chassis status command
    my $rsp = shift;
    my $sessdata = shift;
    unless (check_rsp_errors($rsp,$sessdata)) {
        my @data = @{$rsp->{data}};
        my $powerstat;
        if ($data[0] & 1) { 
            $powerstat="on";
        } else {
            $powerstat="off";
        }
		xCAT::SvrUtils::sendmsg("Power Status: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[0] & 0b10) {
            $powerstat="true";
        } else {
            $powerstat="false";
        }
		xCAT::SvrUtils::sendmsg("Power Overload: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[0] & 0b100) {
            $powerstat="active";
        } else {
            $powerstat="inactive";
        }
		xCAT::SvrUtils::sendmsg("Power Interlock: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[0] & 0b1000) {
            $sessdata->{healthsummary} &= 2; #set to critical state
            $powerstat="true";
        } else {
            $powerstat="false";
        }
		xCAT::SvrUtils::sendmsg("Power Fault: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[0] & 0b10000) {
            $sessdata->{healthsummary} &= 2; #set to critical state
            $powerstat="true";
        } else {
            $powerstat="false";
        }
		xCAT::SvrUtils::sendmsg("Power Control Fault: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        my $powpolicy = ($data[0] & 0b1100000) >> 5;
        my %powpolicies = ( 0 => "Always off", 1 => "Last State", 2 => "Always on", 3 => "Unknown" );
		xCAT::SvrUtils::sendmsg("Power Restore Policy: ".$powpolicies{$powpolicy},$callback,$sessdata->{node},%allerrornodes);
        my @lastevents;
        if ($data[1] & 0b1) {
            push @lastevents,"AC failed";
        }
        if ($data[1] & 0b10) {
            $sessdata->{healthsummary} &= 2; #set to critical state
            push @lastevents,"Power overload";
        }
        if ($data[1] & 0b100) {
            $sessdata->{healthsummary} &= 1; #set to critical state
            push @lastevents,"Interlock activated";
        }
        if ($data[1] & 0b1000) {
            $sessdata->{healthsummary} &= 2; #set to critical state
            push @lastevents,"Power Fault";
        }
        if ($data[1] & 0b10000) {
            push @lastevents,"By Request";
        }
        my $lastevent = join(",",@lastevents);
		xCAT::SvrUtils::sendmsg("Last Power Event: $lastevent",$callback,$sessdata->{node},%allerrornodes);
        if ($data[2] & 0b1) {
            $sessdata->{healthsummary} &= 1; #set to warn state
            $powerstat = "active";
        } else {
            $powerstat = "inactive";
        }
		xCAT::SvrUtils::sendmsg("Chassis intrusion: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[2] & 0b10) {
            $powerstat = "active";
        } else { 
            $powerstat = "inactive";
        }
		xCAT::SvrUtils::sendmsg("Front Panel Lockout: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[2] & 0b100) { # drive fault
            $sessdata->{healthsummary} &= 2; #set to critical state
            $powerstat = "true";
        } else { 
            $powerstat = "false";
        }
		xCAT::SvrUtils::sendmsg("Drive Fault: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[2] & 0b1000) { # fan fault
            $sessdata->{healthsummary} &= 1; #set to warn state
            $powerstat = "true";
        } else { 
            $powerstat = "false";
        }
		xCAT::SvrUtils::sendmsg("Cooling Fault: $powerstat",$callback,$sessdata->{node},%allerrornodes);
        if ($data[2] & 0b1000000) { #can look at light status
            my $idstat = ($data[2] & 0b110000) >> 4;
            my %idstats = ( 0 => "off", 1 => "on", 2 => "on", 3 => "unknown" );
            xCAT::SvrUtils::sendmsg("Identify Light: ".$idstats{$idstat},$callback,$sessdata->{node},%allerrornodes);
        }
    }
            #$sessdata->{powerstatprefix}="Power Status: ";
    if ($sessdata->{sensorstoread} and scalar @{$sessdata->{sensorstoread}}) {
        $sessdata->{currsdr} = shift @{$sessdata->{sensorstoread}};
        readsensor($sessdata); #next sensor
    }
}
sub readchassis {
    my $sessdata = shift;
    $sessdata->{ipmisession}->subcmd(netfn=>0x0,command=>0x1,data=>[],callback=>\&gotchassis,callback_args=>$sessdata);
    
}
sub checkleds {
    my $sessdata = shift;
	my @cmd;
	my @returnd = ();
	my $error;
	my $led_id_ms;
	my $led_id_ls;
	my $rc = 0;
	my @output =();
	my $text="";
	my $key;
	my $mfg_id=$sessdata->{mfg_id};
#TODO device id
	if ($mfg_id != 2 and $mfg_id != 20301) {
		xCAT::SvrUtils::sendmsg("LED status not supported on this system",$callback,$sessdata->{node},%allerrornodes);
        return;
	}
	
    my %sdr_hash = %{$sessdata->{sdr_hash}};
    $sessdata->{doleds} = [];
	foreach $key (sort {$sdr_hash{$a}->id_string cmp $sdr_hash{$b}->id_string} keys %sdr_hash) {
		my $sdr = $sdr_hash{$key};
		if($sdr->rec_type == 0xC0 && $sdr->sensor_type == 0xED) {
			#this stuff is to help me build the file from spec paste
			#my $tehstr=sprintf("grep 0x%04X /opt/xcat/lib/x3755led.tab",$sdr->led_id);
			#my $tehstr=`$tehstr`;
			#$tehstr =~ s/^0x....//;
			
			#printf("%X.%X.0x%04x",$mfg_id,$prod_id,$sdr->led_id);
			#print $tehstr;
		
			#We are inconsistant in our spec, first try a best guess
			#at endianness, assume the smaller value is MSB
			if (($sdr->led_id&0xff) > ($sdr->led_id>>8)) {
				$led_id_ls=$sdr->led_id&0xff;
				$led_id_ms=$sdr->led_id>>8;
			} else {	
				$led_id_ls=$sdr->led_id>>8;
				$led_id_ms=$sdr->led_id&0xff;
			}
				
            push @{$sessdata->{doleds}},[$led_id_ms,$led_id_ls,$sdr];
        }
    }
    $sessdata->{doled} = shift @{$sessdata->{doleds}};
    if ($sessdata->{doled}) {
        $sessdata->{current_led_sdr} = pop @{$sessdata->{doled}};
        $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0xc0,data=>$sessdata->{doled},callback=>\&did_led,callback_args=>$sessdata);
    } else {
        xCAT::SvrUtils::sendmsg("No supported LEDs found in system",$callback,$sessdata->{node},%allerrornodes);
    }
#	if ($#output==-1) {
#		push(@output,"No active error LEDs detected");
#	}
}

sub did_led {
    my $rsp = $_[0];
    my $sessdata = $_[1];
    my $mfg_id = $sessdata->{mfg_id};
    my $prod_id = $sessdata->{prod_id};
    my $sdr = $sessdata->{current_led_sdr};
    if (not $sessdata->{ledswappedendian} and $_[0]->{code} == 0xc9) { #missed an endian guess probably
        $sessdata->{ledswappedendian}=1;
        my @doled;
        $doled[0]=$sessdata->{doled}->[1];
        $doled[1]=$sessdata->{doled}->[0];
        $sessdata->{doled} = \@doled;
        $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0xc0,data=>$sessdata->{doled},callback=>\&did_led,callback_args=>$sessdata);
        return;
    } elsif ( $_[0]->{code} == 0xc9) {
        $_[0]->{code} = 0; #TODO: some system actually gives an led locator record that doesn't exist....
                    print "DEBUG: unfindable LED record\n";
    }
    $sessdata->{ledswappedendian}=0; #reset ledswappedendian flag to allow future swaps
    if (check_rsp_errors(@_)) {
        return;
    }
    my $led_id_ls = $sessdata->{doled}->[1];
    my $led_id_ms = $sessdata->{doled}->[0];
    my @returnd = (0,@{$rsp->{data}});
		if ($returnd[2]) { # != 0) {
			#It's on...
			if ($returnd[6] == 4) {
				xCAT::SvrUtils::sendmsg(sprintf("BIOS or admininstrator has %s lit",getsensorname($mfg_id,$prod_id,$sdr->led_id,"ibmleds",$sdr)),$callback,$sessdata->{node},%allerrornodes);
            $sessdata->{activeleds}=1;
			}
			elsif ($returnd[6] == 3) {
				xCAT::SvrUtils::sendmsg(sprintf("A user has manually requested LED 0x%04x (%s) be active",$sdr->led_id,getsensorname($mfg_id,$prod_id,$sdr->led_id,"ibmleds",$sdr)),$callback,$sessdata->{node},%allerrornodes);
            $sessdata->{activeleds}=1;
			}
			elsif ($returnd[6] == 1 && $sdr->led_id !=0) {
				xCAT::SvrUtils::sendmsg(sprintf("LED 0x%02x%02x (%s) active to indicate LED 0x%02x%02x (%s) is active",$led_id_ms,$led_id_ls,getsensorname($mfg_id,$prod_id,$sdr->led_id,"ibmleds",$sdr),$returnd[4],$returnd[5],getsensorname($mfg_id,$prod_id,($returnd[4]<<8)+$returnd[5],"ibmleds")),$callback,$sessdata->{node},%allerrornodes);
            $sessdata->{activeleds}=1;
			}
			elsif ($sdr->led_id ==0 and $led_id_ms == 0 and $led_id_ls == 0) {
				xCAT::SvrUtils::sendmsg(sprintf("LED 0x0000 (%s) active to indicate system error condition.",getsensorname($mfg_id,$prod_id,$sdr->led_id,"ibmleds",$sdr)),$callback,$sessdata->{node},%allerrornodes);
            $sessdata->{activeleds}=1;
				if ($returnd[6] == 1 and $returnd[4] == 0xf and $returnd[5] == 0xff) {
					$sessdata->{doled} = [$returnd[4],$returnd[5]];
               $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0xc0,data=>$sessdata->{doled},callback=>\&did_led,callback_args=>$sessdata);
               return;
            }
			}
			elsif ($returnd[6] == 2) {
				my $sensor_desc;
				#Ok, LED is tied to a sensor..
				my $sensor_num=$returnd[5];
                my %sdr_hash = %{$sessdata->{sdr_hash}};
			        foreach my $key (keys %sdr_hash) {
					my $osdr = $sdr_hash{$key};
			                if($osdr->sensor_number == $sensor_num  and $osdr->rec_type != 192 and $osdr->rec_type != 17) {
			                        $sensor_desc = $sdr_hash{$key}->id_string;
			                        if($osdr->rec_type == 0x01) {
		                                	last;
						}
		                        }
		                }
				#push(@output,sprintf("Sensor 0x%02x (%s) has activated LED 0x%04x",$sensor_num,$sensor_desc,$sdr->led_id));
            if ($led_id_ms == 0xf and $led_id_ls == 0xff) { 
 	           xCAT::SvrUtils::sendmsg(sprintf("LED active to indicate Sensor 0x%02x (%s) error.",$sensor_num,$sensor_desc),$callback,$sessdata->{node},%allerrornodes);
            } else {
               xCAT::SvrUtils::sendmsg(sprintf("LED %02x%02x (%s) active to indicate Sensor 0x%02x (%s) error.",$led_id_ms,$led_id_ls,getsensorname($mfg_id,$prod_id,$sdr->led_id,"ibmleds",$sdr),$sensor_num,$sensor_desc),$callback,$sessdata->{node},%allerrornodes);
            }
            $sessdata->{activeleds}=1;
		        } else { #an LED is on for some other reason
                    #print "DEBUG: unknown LED reason code ".$returnd[6]."\n";
                    #TODO: discern meaning of more 'reason' codes, 5 and ff have come up
                }
                    
		} 
    $sessdata->{doled} = shift @{$sessdata->{doleds}};
    if ($sessdata->{doled}) {
        $sessdata->{current_led_sdr} = pop @{$sessdata->{doled}};
        $sessdata->{ipmisession}->subcmd(netfn=>0x3a,command=>0xc0,data=>$sessdata->{doled},callback=>\&did_led,callback_args=>$sessdata);
    } elsif (not $sessdata->{activeleds}) {
        xCAT::SvrUtils::sendmsg("No active error LEDs detected",$callback,$sessdata->{node},%allerrornodes);
    }
    if (scalar @{$sessdata->{sensorstoread}}) {
        $sessdata->{currsdr} = shift @{$sessdata->{sensorstoread}};
        readsensor($sessdata); #next sensor
    }
}
	
sub renergy {
    my $sessdata = shift;
    my @subcommands = @{$sessdata->{extraargs}};
    unless ($iem_support) {
        xCAT::SvrUtils::sendmsg("Command unsupported without IBM::EnergyManager installed",$callback,$sessdata->{node});
        return;
    }
    my @directives=();
    foreach (@subcommands) {
        if ($_ eq 'cappingmaxmin') {
            push @directives,'cappingmax','cappingmin';
        }
        push @directives,split /,/,$_;
    }
    $sessdata->{directives} = \@directives;
    $sessdata->{iemcallback}=\&renergy_withiem;
    initiem($sessdata);
}
sub renergy_withiem {
    my $sessdata = shift;
    my @settable_keys = qw/savingstatus cappingstatus cappingwatt cappingvalue/;
    my $directive = shift (@{$sessdata->{directives}});
    if ($sessdata->{iemtextdata}) {
        xCAT::SvrUtils::sendmsg($sessdata->{iemtextdata},$callback,$sessdata->{node},%allerrornodes);
        $sessdata->{iemtextdata}="";
    }
    if ($sessdata->{gotcapstatus}) {
        $sessdata->{gotcapstatus}=0;
        my $capenabled = $sessdata->{iem}->capping_enabled();
        xCAT::SvrUtils::sendmsg("cappingstatus: ".($capenabled ? "on" : "off"),$callback,$sessdata->{node},%allerrornodes);
    }
    if ($sessdata->{gothistogram}) {
        $sessdata->{gothistogram}=0;
        my @histdata = $sessdata->{iem}->extract_relative_histogram;
        foreach (sort { $a <=> $b } keys %{$histdata[0]}) {
            xCAT::SvrUtils::sendmsg("$_: ".$histdata[0]->{$_},$callback,$sessdata->{node},%allerrornodes);
        }
    }

    unless ($directive) { 
        return;
    }
    my $value=undef;
    my $key=undef;
    $sessdata->{iemcallback} = \&renergy_withiem;
    if ($directive =~ /(.*)=(.*)\z/) {
        $key = $1;
        $value = $2;
        unless (grep /$key/,@settable_keys and $value) {
            return (1,"Malformed argument $directive");
        }
        if ($key eq "cappingwatt" or $key eq "cappingvalue") {
            $value = $value*1000; #convert to milliwatts
            $sessdata->{iem}->prep_set_cap($value);
            execute_iem_commands($sessdata); #this gets all precision data initialized
        }
        if ($key eq "cappingstatus") {
            if (grep /$value/,qw/enable on 1/) {
                $value = 1;
            } else {
                $value = 0;
            }
            $sessdata->{iem}->prep_set_capenable($value);
            execute_iem_commands($sessdata); #this gets all precision data initialized
        }

    }
    if ($directive =~ /cappingmin/) {
        $sessdata->{iem}->prep_get_mincap();
        process_data_from_iem($sessdata);
    } elsif ($directive =~ /cappingmax$/) {
        $sessdata->{iem}->prep_get_maxcap();
        process_data_from_iem($sessdata);
    }
    if ($directive =~ /cappingvalue/) {
        $sessdata->{iem}->prep_get_cap();
        process_data_from_iem($sessdata);
    }
    if ($directive =~ /cappingstatus/) {
        $sessdata->{iem}->prep_get_powerstatus();
        $sessdata->{gotcapstatus}=1;
        execute_iem_commands($sessdata);
    }
    if ($directive =~ /relhistogram/) {
        $sessdata->{gothistogram}=1;
        $sessdata->{iem}->prep_retrieve_histogram();
        execute_iem_commands($sessdata);
    }
    return;
}
sub vitals {
    my $sessdata = shift;
    $sessdata->{healthsummary} = 0; #0 means healthy for now
    my %sdr_hash = %{$sessdata->{sdr_hash}};
    my @textfilters;
    foreach (@{$sessdata->{extraargs}}) {
        push @textfilters,(split /,/,$_);
    }
    unless (scalar @textfilters) { @textfilters = ("all"); }

	my $rc = 0;
	my $text;
	my $key;
	my %sensor_filters=();
	my @output;
	my $reading;
	my $unitdesc;
	my $value;
	my $extext;
	my $format = "%-30s%8s %-20s";
    my $doall;
    $doall=0;
	$rc=0;
    #filters: defined in sensor type codes and data table
    # 1 == temp, 2 == voltage 3== current (we lump in wattage here for lack of a better spot), 4 == fan

	if(grep { $_ eq "all"} @textfilters) {
	  $sensor_filters{1}=1; #,0x02,0x03,0x04); rather than filtering, unfiltered results
      $sensor_filters{energy}=1;
      $sensor_filters{chassis}=1;
      $sensor_filters{leds}=1;
      $doall=1;
	}
	if(grep /temp/,@textfilters) {
		$sensor_filters{0x01}=1;
	}
	if(grep /volt/,@textfilters) {
		$sensor_filters{0x02}=1;
	}
    if(grep /watt/,@textfilters) {
        $sensor_filters{0x03}=1;
    }
	if(grep /fan/,@textfilters) {
		$sensor_filters{0x04}=1;
	}
	if(grep /power/,@textfilters) {  #power does not really include energy, but most people use 'power' to mean both
        $sensor_filters{0x03}=1;
        $sensor_filters{powerstate}=1;
        $sensor_filters{energy}=1;
	}
	if(grep /energy/,@textfilters) { 
        $sensor_filters{energy}=1;
	}
	if(grep /led/,@textfilters) {
        $sensor_filters{leds}=1;
	}
	if(grep /chassis/,@textfilters) {
        $sensor_filters{chassis}=1;
	}
	unless (keys %sensor_filters) {
        xCAT::SvrUtils::sendmsg([1,"Unrecognized rvitals arguments ".join(" ",@{$sessdata->{extraargs}})],$callback,$sessdata->{node},%allerrornodes);;
	}

    $sessdata->{sensorstoread} = [];
    my %usedkeys;
	foreach(keys %sensor_filters) {
		my $filter = $_;
        if ($filter eq "energy" or $filter eq "leds") { next; }

		foreach $key (sort {$sdr_hash{$a}->id_string cmp $sdr_hash{$b}->id_string} keys %sdr_hash) {
            if ($usedkeys{$key}) { next; } #avoid duplicate requests for sensor data
			my $sdr = $sdr_hash{$key};
			if(($doall and not $sdr->rec_type == 0x11 and not $sdr->sensor_type==0xed) or ($sdr->rec_type == 0x01 and $sdr->sensor_type == $filter)) {
				my $lformat = $format;
                push @{$sessdata->{sensorstoread}},$sdr;
                $usedkeys{$key}=1;
            }
		}
	}

	if($sensor_filters{leds}) {
        push @{$sessdata->{sensorstoread}},"leds";
		#my @cleds;
		#($rc,@cleds) = checkleds();
        #push @output,@cleds;
    }
    if ($sensor_filters{powerstate} and not $sensor_filters{chassis}) {
        push @{$sessdata->{sensorstoread}},"powerstat";
		#($rc,$text) = power("stat");
		#$text = sprintf($format,"Power Status:",$text,"");
		#push(@output,$text);
    }
    if ($sensor_filters{energy}) {
        if ($iem_support) {
            push @{$sessdata->{sensorstoread}},"energy";
        } elsif (not $doall) {
            xCAT::SvrUtils::sendmsg([1,"Energy data requires additional IBM::EnergyManager plugin in conjunction with IMM managed IBM equipment"],$callback,$sessdata->{node},%allerrornodes);
        }
        #my @energies;
        #($rc,@energies)=readenergy();
        #push @output,@energies;
	}
    if ($sensor_filters{chassis}) {
        unshift  @{$sessdata->{sensorstoread}},"chassis";
    }
    if (scalar @{$sessdata->{sensorstoread}}) {
        $sessdata->{currsdr} = shift @{$sessdata->{sensorstoread}};
        readsensor($sessdata); #and we are off
    }
}



sub sensorformat {
    my $sessdata = shift;
    my $sdr = $sessdata->{currsdr};
    my $rc = shift;
    my $reading = shift;
    my $extext = shift;
	my $unitdesc = "";
    my $value;
	my $lformat = "%-30s %-20s";
	my $per = " ";
    my $data;
	if($rc == 0) {
        $data = translate_sensor($reading,$sdr);
	} else {
        $data = "N/A";
    }
#$unitdesc.= sprintf(" %x",$sdr->sensor_type);
#    use Data::Dumper;
#    print Dumper($lformat,$sdr->id_string,$data);
	my $text = sprintf($lformat,$sdr->id_string . ":",$data);
	if ($extext) {
		$text="$text ($extext)";
	}
	if ($sessdata->{bmcnum} != 1) { $text.=" on BMC ".$sessdata->{bmcnum}; }
    xCAT::SvrUtils::sendmsg($text,$callback,$sessdata->{node},%allerrornodes);
    if (scalar @{$sessdata->{sensorstoread}}) {
        $sessdata->{currsdr} = shift @{$sessdata->{sensorstoread}};
        readsensor($sessdata); #next
    }
}

sub readsensor {
    my $sessdata = shift;
    if (not ref $sessdata->{currsdr}) {
        if ($sessdata->{currsdr} eq "leds") {
            checkleds($sessdata);
            return;
        } elsif ($sessdata->{currsdr} eq "powerstat") {
            $sessdata->{powerstatprefix}="Power Status: ";
            $sessdata->{subcommand}="stat";
            power($sessdata);
            return;
        } elsif ($sessdata->{currsdr} eq "chassis") {
            readchassis($sessdata);
            return;
        } elsif ($sessdata->{currsdr} eq "energy") {
            readenergy($sessdata);
            return;
        } else {
        xCAT::SvrUtils::sendmsg([1,"TODO: make ".$sessdata->{currsdr}." work again"],$callback,$sessdata->{node},%allerrornodes);
        }
        return;
    }
	my $sensor = $sessdata->{currsdr}->sensor_number;
    $sessdata->{ipmisession}->subcmd(netfn=>0x4,command=>0x2d,data=>[$sensor],callback=>\&sensor_was_read,callback_args=>$sessdata);
}

sub sensor_was_read {
    my $rsp = shift;
    my $sessdata = shift;
    if ($rsp->{error}) {
        xCAT::SvrUtils::sendmsg([1,$rsp->{error}],$callback,$sessdata->{node},%allerrornodes);
	return;
    }
    if ($rsp->{code}) {
        my $text = $codes{$rsp->{code}};
        unless ($text) { $text = sprintf("Unknown error %02xh",$rsp->{code}) };
        return sensorformat($sessdata,1,$text);
    }

    my @returnd = (0,@{$rsp->{data}});
	
	if ($returnd[2] & 0x20) {
		return sensorformat($sessdata,1,"N/A");
	}
	my $text = $returnd[1];
    my $exdata1 = $returnd[3];
    my $exdata2 = $returnd[3];
    my $extext;
    my @exparts;
    my $sdr = $sessdata->{currsdr};
    if ($sdr->event_type_code == 0x1) {
        if ($exdata1 & 1<<5) {
            $extext = "At or above upper non-recoverable threshold";
        } elsif ($exdata1 & 1<<4)  {
            $extext = "At or above upper critical threshold";
        } elsif ($exdata1 & 1<<3) {
            $extext = "At or above upper non-critical threshold";
        } 
        if ($exdata1 & 1<<2) {
            $extext = "At or below lower non-critical threshold";
        } elsif ($exdata1 & 1<<1) {
            $extext = "At or below lower critical threshold";
        } elsif ($exdata1 & 1) {
            $extext = "At or below lower non-recoverable threshold";
        }
    } elsif ($sdr->event_type_code == 0x6f) {
        if ($sdr->sensor_type == 0x10) {
	    @exparts=();
            if ($exdata1 & 1<<4) {
                push @exparts,"SEL full";
            } elsif ($exdata1 & 1<<5) {
                push @exparts,"SEL almost full";
            }
	    if ($exdata1 & 1) {
	       push @exparts,"Correctable Memory Error Logging Disabled";
	    } 
	    if ($exdata1 & 1<<3) {
	       push @exparts,"All logging disabled";
	    } elsif ($exdata1 & 1<<1) {
	       push @exparts,"Some logging disabled";
	    }
	    if (@exparts) {
	       $extext = join(",",@exparts);
	    }
        } elsif ($sdr->sensor_type == 0x7) {
	   @exparts=();
	   if ($exdata1 & 1) {
	      push @exparts,"IERR";
	   }
	   if ($exdata1 & 1<<1) {
	      push @exparts,"Thermal trip";
	   }
	   if ($exdata1 & 1<<2) {
	      push @exparts,"FRB1/BIST failure";
	   }
	   if ($exdata1 & 1<<3) {
	      push @exparts,"FRB2/Hang in POST due to processor";
	   }
	   if ($exdata1 & 1<<4) {
	      push @exparts,"FRB3/Processor Initialization failure";
	   }
	   if ($exdata1 & 1<<5) {
	      push @exparts,"Configuration error";
	   }
	   if ($exdata1 & 1<<6) {
	      push @exparts,"Uncorrectable CPU-complex error";
	   }
	   if ($exdata1 & 1<<7) {
	      push @exparts,"Present";
	   }
	   if ($exdata1 & 1<<8) {
	      push @exparts,"Processor disabled";
	   }
	   if ($exdata1 & 1<<9) {
	      push @exparts,"Terminator present";
	   }
	   if ($exdata1 & 1<<10) {
	      push @exparts,"Hardware throttled";
	   }
        } elsif ($sdr->sensor_type == 0x8) {
	   @exparts=();
	   if ($exdata1 & 1) {
	        push @exparts,"Present";
	   }
	   if ($exdata1 & 1<<1) {
	        push @exparts,"Failed";
	   }
	   if ($exdata1 & 1<<2) {
	        push @exparts,"Failure predicted";
	   }
	   if ($exdata1 & 1<<3) {
	        push @exparts,"AC Lost";
	   }
	   if ($exdata1 & 1<<4) {
	        push @exparts,"AC input lost or out of range";
	   }
	   if ($exdata1 & 1<<5) {
	        push @exparts,"AC input out of range";
	   }
	   if ($exdata1 & 1<<6) {
	        push @exparts,"Configuration error";
	   }
	   if (@exparts) {
	      $extext = join(",",@exparts);
	   }
        } elsif ($sdr->sensor_type == 0x13) {
            @exparts=();
            if ($exdata1 & 1) {
                push @exparts,"Front panel NMI/Diagnostic";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"Bus timeout";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"I/O channel check NMI";
            }
            if ($exdata1 & 1<<3) {
                push @exparts,"Software NMI";
            }
            if ($exdata1 & 1<<4) {
                push @exparts,"PCI PERR";
            }
            if ($exdata1 & 1<<5) {
                push @exparts,"PCI SERR";
            }
            if ($exdata1 & 1<<6) {
                push @exparts,"EISA failsafe timeout";
            }
            if ($exdata1 & 1<<7) {
                push @exparts,"Bus correctable .rror";
            }
            if ($exdata1 & 1<<8) {
                push @exparts,"Bus uncorrectable error";
            }
            if ($exdata1 & 1<<9) {
                push @exparts,"Fatal NMI";
            }
            if ($exdata1 & 1<<10) {
                push @exparts,"Bus fatal error";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } elsif ($sdr->sensor_type == 0xc) {
            @exparts=();
            if ($exdata1 & 1) {
                push @exparts,"Correctable error(s)";
            } 
            if ($exdata1 & 1<<1) {
                push @exparts,"Uncorrectable error(s)";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Parity";
            }
            if ($exdata1 & 1<<3) {
                push @exparts,"Memory scrub failure";
            }
            if ($exdata1 & 1<<4) {
                push @exparts,"DIMM disabled";
            }
            if ($exdata1 & 1<<5) {
                push @exparts,"Correctable error limit reached";
            }
            if ($exdata1 & 1<<6) {
                push @exparts,"Present";
            }
            if ($exdata1 & 1<<7) {
                push @exparts,"Configuration error";
            }
            if ($exdata1 & 1<<8) {
                push @exparts,"Spare";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } elsif ($sdr->sensor_type == 0x21) {
            @exparts=();
            if ($exdata1 & 1) {
                push @exparts,"Fault";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"Identify";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Installed/attached";
            }
            if ($exdata1 & 1<<3) {
                push @exparts,"Ready for install";
            }
            if ($exdata1 & 1<<4) {
                push @exparts,"Ready for removal";
            }
            if ($exdata1 & 1<<5) {
                push @exparts,"Powered off";
            }
            if ($exdata1 & 1<<6) {
                push @exparts,"Removal requested";
            }
            if ($exdata1 & 1<<7) {
                push @exparts,"Interlocked";
            }
            if ($exdata1 & 1<<8) {
                push @exparts,"Disabled";
            }
            if ($exdata1 & 1<<9) {
                push @exparts,"Spare";
            }
        } elsif ($sdr->sensor_type == 0xf) {
            @exparts=();
            if ($exdata1 & 1) {
                push @exparts,"POST error";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"Firmware hang";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Firmware progress";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } elsif ($sdr->sensor_type == 0x9) {
	   @exparts=();
	   if ($exdata1 & 1) {
	      push @exparts,"Power off";
	   }
	   if ($exdata1 & 1<<1) {
	      push @exparts,"Power off";
	   }
	   if ($exdata1 & 1<<2) {
	      push @exparts,"240VA Power Down";
	   }
	   if ($exdata1 & 1<<3) {
	      push @exparts,"Interlock Power Down";
	   }
	   if ($exdata1 & 1<<4) {
	      push @exparts,"AC lost";
	   }
	   if ($exdata1 & 1<<5) {
	      push @exparts,"Soft power control failure";
	   }
	   if ($exdata1 & 1<<6) {
	      push @exparts,"Power unit failure";
	   }
	   if ($exdata1 & 1<<7) {
	      push @exparts,"Power unit failure predicted";
	   }
	   if (@exparts) {
	      $extext = join(",",@exparts);
	   }
        } elsif ($sdr->sensor_type == 0x12) {
            @exparts=();
            if ($exdata1 & 1) {
                push @exparts,"System Reconfigured";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"OEM System Boot Event";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Undetermined system hardware failure";
            }
            if ($exdata1 & 1<<3) {
                push @exparts,"Aux log manipulated";
            }
            if ($exdata1 & 1<<4) {
                push @exparts,"PEF Action";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } elsif ($sdr->sensor_type == 0x25) {
            if ($exdata1 & 1) {
                push @exparts,"Present";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"Absent";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Disabled";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } elsif ($sdr->sensor_type == 0x23) {
            if ($exdata1 & 1) {
                push @exparts,"Expired";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"Hard Reset";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Power Down";
            }
            if ($exdata1 & 1<<3) {
                push @exparts,"Power Cycle";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } elsif ($sdr->sensor_type == 0xd) {
            if ($exdata1 & 1) {
                push @exparts,"Present";
            }
            if ($exdata1 & 1<<1) {
                push @exparts,"Fault";
            }
            if ($exdata1 & 1<<2) {
                push @exparts,"Failure Predicted";
            }
            if ($exdata1 & 1<<3) {
                push @exparts,"Hot Spare";
            }
            if ($exdata1 & 1<<4) {
                push @exparts,"Consistency Check";
            }
            if ($exdata1 & 1<<5) {
                push @exparts,"Critical Array";
            }
            if ($exdata1 & 1<<6) {
                push @exparts,"Failed Array";
            }
            if ($exdata1 & 1<<7) {
                push @exparts,"Rebuilding";
            }
            if ($exdata1 & 1<<8) {
                push @exparts,"Rebuild aborted";
            }
            if (@exparts) {
                $extext = join(",",@exparts);
            }
        } else {
            $extext = "xCAT needs to add support for ".$sdr->sensor_type;
        }
    }

	return sensorformat($sessdata,0,$text,$extext);
}

sub initsdr {
    my $sessdata=shift;
	my $netfun;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;

	my $resv_id_ls;
	my $resv_id_ms;
	my $sdr_type;
	my $sdr_offset;
	my $sdr_len;
	my @sdr_data = ();
	my $offset;
	my $len;
	my $i;
#	my $numbytes = 27;
	my $ipmisensortab = "$ENV{XCATROOT}/lib/GUMI/ipmisensor.tab";
	my $byte_format;
	my $cache_file;

     #device id data TODO
    $sessdata->{ipmisession}->subcmd(netfn=>0x0a,command=>0x20,data=>[],callback=>\&got_sdr_rep_info,callback_args=>$sessdata);
}

sub  initsdr_withrepinfo {
    my $sessdata = shift;
	my $mfg_id=$sessdata->{mfg_id};
	my $prod_id=$sessdata->{prod_id};
	my $device_id=$sessdata->{device_id};
	my $dev_rev=$sessdata->{device_rev};
	my $fw_rev1=$sessdata->{firmware_rev1};
	my $fw_rev2=$sessdata->{firmware_rev2};
    #TODO: beware of dynamic SDR contents

	my $cache_file = "$cache_dir/sdr_$mfg_id.$prod_id.$device_id.$dev_rev.$fw_rev1.$fw_rev2";
    $sessdata->{sdrcache_file} = $cache_file;
	if($enable_cache eq "yes") {
        if ($sdr_caches{"$mfg_id.$prod_id.$device_id.$dev_rev.$fw_rev1.$fw_rev2"}) {
            $sessdata->{sdr_hash} = $sdr_caches{"$mfg_id.$prod_id.$device_id.$dev_rev.$fw_rev1.$fw_rev2"};
            on_bmc_connect("SUCCESS",$sessdata); #retry bmc_connect since sdr_cache is validated
            return; #don't proceed to slow load
        } else {
    		my $rc = loadsdrcache($sessdata,$cache_file);
    		if($rc == 0) {
                $sdr_caches{"$mfg_id.$prod_id.$device_id.$dev_rev.$fw_rev1.$fw_rev2"} = $sessdata->{sdr_hash};
                on_bmc_connect("SUCCESS",$sessdata); #retry bmc_connect since sdr_cache is validated
                return; #don't proceed to slow load
    		}
        }
	}


	if($sessdata->{sdr_info}->{version} != 0x51) {
        sendoutput(1,"SDR version unsupported.");
		return(1); #bail, do not try to continue
	}

	if($sessdata->{sdr_info}->{resv_sdr} != 1) {
        sendoutput(1,"SDR reservation unsupported.");
        return 1;
	}

    $sessdata->{ipmisession}->subcmd(netfn=>0x0a,command=>0x22,data=>[],callback=>\&reserved_sdr_repo,callback_args=>$sessdata);
}
sub initsdr_withreservation {
    my $sessdata = shift;
	my $rid_ls = 0;
	my $rid_ms = 0;
	if ($sessdata->{sdr_nrid_ls}) { $rid_ls = $sessdata->{sdr_nrid_ls}; }
	if ($sessdata->{sdr_nrid_ms}) { $rid_ms = $sessdata->{sdr_nrid_ms}; }

####if($debug) {
####	print "mfg,prod,dev: $mfg_id, $prod_id, $device_id\n";
####	printf("SDR info: %02x %d %d\n",$sdr_rep_info->version,$sdr_rep_info->rec_count,$sdr_rep_info->resv_sdr);
####	print "resv_id: $resv_id_ls $resv_id_ms\n";
####}
    my $resv_id_ls = $sessdata->{resv_id_ls};
    my $resv_id_ms = $sessdata->{resv_id_ms};
    if ( $rid_ls == 0xff and $rid_ms == 0xff) {
	    if($enable_cache eq "yes") { #cache SDR repository for future use
		    storsdrcache($sessdata->{sdrcache_file},$sessdata);
	    }
        on_bmc_connect("SUCCESS",$sessdata); #go back armed with a capable reserviction
        return; #Have reached the end
    }
    $sessdata->{sdr_fetch_args} = [$resv_id_ls,$resv_id_ms,$rid_ls,$rid_ms,0,5];
    $sessdata->{ipmisession}->subcmd(netfn=>0xa,command=>0x23,data=>$sessdata->{sdr_fetch_args},callback=>\&start_sdr_record,callback_args=>$sessdata);
    return;
}

sub start_sdr_record {
    my $rsp = shift;
    my $sessdata = shift;
	if($rsp->{error}) {
        sendoutput(1,$rsp->{error});
		return;
	}
    my $resv_id_ls = shift @{$sessdata->{sdr_fetch_args}};
    my $resv_id_ms = shift @{$sessdata->{sdr_fetch_args}};
    my $rid_ls = shift @{$sessdata->{sdr_fetch_args}};
    my $rid_ms = shift @{$sessdata->{sdr_fetch_args}};
    my @returnd = ($rsp->{code},@{$rsp->{data}});
	my $code = $returnd[0];
	if($code != 0x00) {
		my $text = $codes{$code};
		if(!$text) {
			$text = sprintf("unknown response %02x",$code);
		}
        sendoutput(1,$text);
		return;
	}
	$sessdata->{sdr_nrid_ls} = $returnd[1];
	$sessdata->{sdr_nrid_ms} = $returnd[2];
	my $sdr_ver = $returnd[5];
	my $sdr_type = $returnd[6];
   	$sessdata->{curr_sdr_type} = $sdr_type;
	$sessdata->{curr_sdr_len} = $returnd[7] + 5;

	if($sdr_type == 0x01) {
		$sessdata->{total_sdr_offset} = 0;
	}
	elsif($sdr_type == 0x02) {
		$sessdata->{total_sdr_offset} = 16; #TODO: understand this..
	}
	elsif($sdr_type == 0xC0) {
		#LED descriptor, maybe
	}
	elsif($sdr_type == 0x11) { #FRU locator
	}
	elsif($sdr_type == 0x12) {
        initsdr_withreservation($sessdata); #next, skip this unsupported record type
        return;
	}
	else {
        initsdr_withreservation($sessdata); #next
        return;
	}

	$sessdata->{sdr_data} = [0,0,0,$sdr_ver,$sdr_type,$sessdata->{curr_sdr_len}]; #seems that an extra zero is prepended to allow other code to do 1 based counting out of laziness to match our index to the spec indicated index
	$sessdata->{sdr_offset} = 5;
    my $offset=5; #why duplicate? to make for shorter typing
	my $numbytes = 22;
    if (5<$sessdata->{curr_sdr_len}) { #can't imagine this not bing the case,but keep logic in case
        if($offset+$numbytes > $sessdata->{curr_sdr_len}) { #scale back request for remainder
            $numbytes = $sessdata->{curr_sdr_len} - $offset;
        }
        $sessdata->{sdr_fetch_args} = [$resv_id_ls,$resv_id_ms,$rid_ls,$rid_ms,$offset,$numbytes];
        $sessdata->{ipmisession}->subcmd(netfn=>0x0a,command=>0x23,data=>$sessdata->{sdr_fetch_args},callback=>\&add_sdr_data,callback_args=>$sessdata);
        return;
    } else {
        initsdr_withreservation($sessdata); #next
        return;
    }
}
sub add_sdr_data {
    my $rsp = shift;
    my $sessdata = shift;
	my $numbytes = $sessdata->{sdr_fetch_args}->[5];
    my $offset = $sessdata->{sdr_offset}; #shorten typing a little
    if ($rsp->{error}) {
        sendoutput([1,$rsp->{error}]);
        return; #give up
    }
    my @returnd = ($rsp->{code},@{$rsp->{data}});
	my $code = $returnd[0];
	if($code != 0x00) {
		my $text = $codes{$code};
		if(!$text) {
			$text = sprintf("unknown response %02x",$code);
		}
        sendoutput([1,$text]);
        return; #abort the whole mess
	}
    push @{$sessdata->{sdr_data}},@returnd[3..@returnd-1];
	$sessdata->{sdr_offset} += $numbytes;
    if($sessdata->{sdr_offset}+$numbytes > $sessdata->{curr_sdr_len}) { #scale back request for remainder
       $numbytes = $sessdata->{curr_sdr_len} - $sessdata->{sdr_offset};
    }
    $sessdata->{sdr_fetch_args}->[4] = $sessdata->{sdr_offset};
    $sessdata->{sdr_fetch_args}->[5] = $numbytes;
    if ($sessdata->{sdr_offset}<$sessdata->{curr_sdr_len}) {
        $sessdata->{ipmisession}->subcmd(netfn=>0x0a,command=>0x23,data=>$sessdata->{sdr_fetch_args},callback=>\&add_sdr_data,callback_args=>$sessdata);
        return;
    } else { #in this case, time to parse the accumulated data
        parse_sdr($sessdata);
    }
}
sub parse_sdr { #parse sdr data, then cann initsdr_withreserveation to advance to next record
    my $sessdata = shift;
    my @sdr_data =  @{$sessdata->{sdr_data}};
    #not bothering trying to keep a packet pending concurrent with operation, harder to code that
	my $mfg_id=$sessdata->{mfg_id};
	my $prod_id=$sessdata->{prod_id};
	my $device_id=$sessdata->{device_id};
	my $dev_rev=$sessdata->{device_rev};
	my $fw_rev1=$sessdata->{firmware_rev1};
	my $fw_rev2=$sessdata->{firmware_rev2};
    my $sdr_type = $sessdata->{curr_sdr_type};
	if($sdr_type == 0x11) { #FRU locator
        my $sdr = decode_fru_locator(@sdr_data);
        if ($sdr) {
	        $sessdata->{sdr_hash}->{$sdr->sensor_owner_id . "." . $sdr->sensor_owner_lun . "." . $sdr->sensor_number} = $sdr;
        }
        initsdr_withreservation($sessdata); #advance to next record
        return;
    }

####if($debug) {
####	hexadump(\@sdr_data);
####}


    if($sdr_type == 0x12) { #if required, TODO support type 0x12
	   hexadump(\@sdr_data);
       initsdr_withreservation($sessdata); #next record
       return;
	}

	my $sdr = SDR->new();

	if (($mfg_id == 2 || $mfg_id == 20301) && $sdr_type==0xC0 && $sdr_data[9] == 0xED) {
			#printf("%02x%02x\n",$sdr_data[13],$sdr_data[12]);
		$sdr->rec_type($sdr_type);
		$sdr->sensor_type($sdr_data[9]);
			#Using an impossible sensor number to not conflict with decodealert
			$sdr->sensor_owner_id(260);
			$sdr->sensor_owner_lun(260);
            $sdr->id_string("LED");
			if ($sdr_data[12] > $sdr_data[13]) {
				$sdr->led_id(($sdr_data[13]<<8)+$sdr_data[12]);
			} else {
				$sdr->led_id(($sdr_data[12]<<8)+$sdr_data[13]);
			}
			if (scalar(@sdr_data) > 17) { #well what do you know, we have an ascii description, probably...
				my $id = unpack("Z*",pack("C*",@sdr_data[16..$#sdr_data]));
				if ($id) { $sdr->id_string($id); }
			}
			#$sdr->led_id_ms($sdr_data[13]);
			#$sdr->led_id_ls($sdr_data[12]);
			$sdr->sensor_number(sprintf("%04x",$sdr->led_id));
			#printf("%02x,%02x,%04x\n",$mfg_id,$prod_id,$sdr->led_id);	
			#Was going to have a human readable name, but specs
			#seem to not to match reality...
			#$override_string = getsensorname($mfg_id,$prod_id,$sdr->sensor_number,$ipmiledtab);
			#I'm hacking in owner and lun of 260 for LEDs....
			$sessdata->{sdr_hash}->{"260.260.".$sdr->led_id} = $sdr;
            initsdr_withreservation($sessdata); #next record
            return;
		}


		$sdr->rec_type($sdr_type);
		$sdr->sensor_owner_id($sdr_data[6]);
		$sdr->sensor_owner_lun($sdr_data[7]);
		$sdr->sensor_number($sdr_data[8]);
		$sdr->entity_id($sdr_data[9]);
		$sdr->entity_instance($sdr_data[10]);
		$sdr->sensor_type($sdr_data[13]);
		$sdr->event_type_code($sdr_data[14]);
		$sdr->sensor_units_2($sdr_data[22]);
		$sdr->sensor_units_3($sdr_data[23]);

		if($sdr_type == 0x01) {
		   $sdr->sensor_units_1($sdr_data[21]);
			$sdr->linearization($sdr_data[24] & 0b01111111);
			$sdr->M(comp2int(10,(($sdr_data[26] & 0b11000000) << 2) + $sdr_data[25]));
			$sdr->B(comp2int(10,(($sdr_data[28] & 0b11000000) << 2) + $sdr_data[27]));
			$sdr->R_exp(comp2int(4,($sdr_data[30] & 0b11110000) >> 4));
			$sdr->B_exp(comp2int(4,$sdr_data[30] & 0b00001111));
		} elsif ($sdr_type == 0x02) {
		   $sdr->sensor_units_1($sdr_data[21]);
        }

		$sdr->id_string_type($sdr_data[48-$sessdata->{total_sdr_offset}]);

		my $override_string = getsensorname($mfg_id,$prod_id,$sdr->sensor_number);

		if($override_string ne "") {
			$sdr->id_string($override_string);
		}
		else {
            unless (defined $sdr->id_string_type) { initsdr_withreservation($sessdata); return; }
			my $byte_format = ($sdr->id_string_type & 0b11000000) >> 6;
			if($byte_format == 0b11) {
				my $len = ($sdr->id_string_type & 0b00011111) - 1;
				if($len > 1) {
					$sdr->id_string(pack("C*",@sdr_data[49-$sessdata->{total_sdr_offset}..49-$sessdata->{total_sdr_offset}+$len]));
				}
				else {
					$sdr->id_string("no description");
				}
			}
			elsif($byte_format == 0b10) {
				$sdr->id_string("ASCII packed unsupported");
			}
			elsif($byte_format == 0b01) {
				$sdr->id_string("BCD unsupported");
			}
			elsif($byte_format == 0b00) {
                my $len = ($sdr->id_string_type & 0b00011111) - 1;
                if ($len > 1) { #It should be something, but need sample to code
				    $sdr->id_string("unicode unsupported");
                } else {
                    initsdr_withreservation($sessdata); return;
                }
			}
		}

		$sessdata->{sdr_hash}->{$sdr->sensor_owner_id . "." . $sdr->sensor_owner_lun . "." . $sdr->sensor_number} = $sdr;
        initsdr_withreservation($sessdata); return;
}

sub getsensorname
{
	my $mfgid = shift;
	my $prodid = shift;
	my $sensor = shift;
	my $file = shift;
	my $sdr = shift;

	my $mfg;
	my $prod;
	my $type;
	my $desc;
	my $name="";

    if ($file and $file eq "ibmleds") {
	    if ($sdr and $sdr->id_string ne "LED") { return $sdr->id_string; } # this is preferred mechanism
            if ($xCAT::data::ibmleds::leds{"$mfgid,$prodid"}->{$sensor}) {
              return $xCAT::data::ibmleds::leds{"$mfgid,$prodid"}->{$sensor}. " LED";
            } elsif ($ndebug) {
              return "Unknown $sensor/$mfgid/$prodid";
            } else {
              return sprintf ("LED 0x%x",$sensor);
            }
    } else {
      return "";
    }
}

sub getchassiscap {
	my $netfun = 0x00;
	my @cmd;
	my @returnd = ();
	my $error;
	my $rc = 0;
	my $text;
	my $code;

	@cmd = (0x00);
	$error = docmd(
		$netfun,
		\@cmd,
		\@returnd
	);

	if($error) {
		$rc = 1;
		$text = $error;
		return($rc,$text);
	}

	$code = $returnd[0];
	if($code == 0x00) {
		$text = "";
	}
	else {
		$rc = 1;
		$text = $codes{$code};
		if(!$text) {
			$rc = 1;
			$text = sprintf("unknown response %02x",$code);
		}
		return($rc,$text);
	}

	return($rc,@returnd[1..@returnd-2]);
}

sub gotdevid {
	#($rc,$text,$mfg_id,$prod_id,$device_id,$dev_rev,$fw_rev1,$fw_rev2) = getdevid();
    my $rsp = shift;
    my $sessdata = shift;
    my $text;

	if($rsp->{error}) {
        sendoutput([1,$rsp->{error}]);
        return;
	}
	else {
		my $code = $rsp->{code};

		if($code != 0x00) {
			my $text = $codes{$code};
			if(!$text) {
				$text = sprintf("unknown response %02x",$code);
			}
            sendoutput([1,$text]);
            return;
		}
	}
    my @returnd = ($rsp->{code},@{$rsp->{data}});

	$sessdata->{device_id} = $returnd[1];
	$sessdata->{device_rev} = $returnd[2] & 0b00001111;
	$sessdata->{firmware_rev1} = $returnd[3] & 0b01111111;
	$sessdata->{firmware_rev2} = $returnd[4];
	$sessdata->{ipmi_ver} = $returnd[5];
	$sessdata->{dev_support} = $returnd[6];
####my $sensor_device = 0;
####my $SDR = 0;
####my $SEL = 0;
####my $FRU = 0;
####my $IPMB_ER = 0;
####my $IPMB_EG = 0;
####my $BD = 0;
####my $CD = 0;
####if($dev_support & 0b00000001) {
####	$sensor_device = 1;
####}
####if($dev_support & 0b00000010) {
####	$SDR = 1;
####}
####if($dev_support & 0b00000100) {
####	$SEL = 1;
####}
####if($dev_support & 0b00001000) {
####	$FRU = 1;
####}
####if($dev_support & 0b00010000) {
####	$IPMB_ER = 1;
####}
####if($dev_support & 0b00100000) {
####	$IPMB_EG = 1;
####}
####if($dev_support & 0b01000000) {
####	$BD = 1;
####}
####if($dev_support & 0b10000000) {
####	$CD = 1;
####}
	$sessdata->{mfg_id} = $returnd[7] + $returnd[8]*0x100 +  $returnd[9]*0x10000;
	$sessdata->{prod_id} = $returnd[10] + $returnd[11]*0x100;
    on_bmc_connect("SUCCESS",$sessdata);
#	my @data = @returnd[12..@returnd-2];

#	return($rc,$text,$mfg_id,$prod_id,$device_id,$device_rev,$firmware_rev1,$firmware_rev2);
}

sub gotguid {
    if (check_rsp_errors(@_)) {
        return;
    }
    my $rsp = shift;
    my $sessdata = shift;
	#my @guidcmd = (0x18,0x37);
	#if($mfg_id == 2 && $prod_id == 34869) { TODO: if GUID is inaccurate on the products mentioned, this code may be uncommented
	#	@guidcmd = (0x18,0x08);
	#}
	#if($mfg_id == 2 && $prod_id == 4) {
	#	@guidcmd = (0x18,0x08);
	#}
	#if($mfg_id == 2 && $prod_id == 3) {
	#	@guidcmd = (0x18,0x08);
	#}
	my $fru = FRU->new();
	$fru->rec_type("guid");
	$fru->desc("UUID/GUID");
	$fru->value(sprintf("%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",@{$rsp->{data}}));
	$sessdata->{fru_hash}->{guid} = $fru;
    initfru_withguid($sessdata);
}

sub got_sdr_rep_info {
    my $rsp = shift;
    my $sessdata = shift;

	if($rsp->{error}) {
        sendoutput([1,$rsp->{error}]);
        return;
	}
	else {
		my $code = $rsp->{code};

		if($code != 0x00) {
			my $text = $codes{$code};
			if(!$text) {
				$text = sprintf("unknown response %02x",$code);
			}
            sendoutput(1,$text);
            return;
		}
	}
    my @returnd = @{$rsp->{data}};
    $sessdata->{sdr_info}->{version} = $returnd[0];
    $sessdata->{sdr_info}->{rec_count} = $returnd[1] + $returnd[2]<<8;
    $sessdata->{sdr_info}->{resv_sdr} = ($returnd[13] & 0b00000010)>>1;
    initsdr_withrepinfo($sessdata);
}

sub reserved_sdr_repo {
    my $rsp = shift;
    my $sessdata = shift;
	if($rsp->{error}) {
        sendoutput([1,$rsp->{error}]);;
        return;
	}
	else {
		my $code = $rsp->{code};

		if($code != 0x00) {
			my $text = $codes{$code};
			if(!$text) {
				$text = sprintf("unknown response %02x",$code);
			}
            sendoutput([1,$text]);
		}
	}
    my @returnd = @{$rsp->{data}};

    $sessdata->{resv_id_ls} =  $returnd[0];
    $sessdata->{resv_id_ms} =  $returnd[1];
    initsdr_withreservation($sessdata);
}

sub dochksum()
{
	my $data = shift;
	my $sum = 0;

	foreach(@$data) {
		$sum += $_;
	}

	$sum = ~$sum + 1;
	return($sum & 0xFF);
}

sub hexdump {
	my $data = shift;

	foreach(@$data) {
		printf("%02x ",$_);
	}
	print "\n";
}

sub getascii {
        my @alpha;
        my $text ="";
        my $c = 0;

        foreach(@_) {
                if (defined $_ and $_ < 128 and $_ > 0x20) {
                    $alpha[$c] = sprintf("%c",$_);
                } else {
                    $alpha[$c]=" ";
                }
                if($alpha[$c] !~ /[\S]/) {
        			if ($alpha[($c-1)] !~ /\s/) {
                    	    $alpha[$c] = " ";
	          		} else {
			        	$c--;
			        }
                }
                $c++;
        }
        foreach(@alpha) {
                $text=$text.$_;
        }
	$text =~ s/^\s+|\s+$//;
	return $text;
}
sub phex {
        my $data = shift;
        my @alpha;
        my $text ="";
        my $c = 0;

        foreach(@$data) {
                $text = $text . sprintf("%02x ",$_);
                $alpha[$c] = sprintf("%c",$_);
                if($alpha[$c] !~ /\w/) {
                        $alpha[$c] = " ";
                }
                $c++;
        }
        $text = $text . "(";
        foreach(@alpha) {
                $text=$text.$_;
        }
        $text = $text . ")";
        return $text;
}

sub hexadump {
	my $data = shift;
	my @alpha;
	my $c = 0;

	foreach(@$data) {
		printf("%02x ",$_);
		$alpha[$c] = sprintf("%c",$_);
		if($_ < 0x20 or $_ > 0x7e) {
			$alpha[$c] = ".";
		}
		$c++;
		if($c == 16) {
			print "   ";
			foreach(@alpha) {
				print $_;
			}
			print "\n";
			@alpha=();
			$c=0;
		}
	}
	foreach($c..16) {
		print "   ";
	}
	foreach(@alpha) {
		print $_;
	}
	print "\n";
}

sub comp2int {
	my $length = shift;
	my $bits = shift;
	my $neg = 0;

	if($bits & 2**($length - 1)) {
		$neg = 1;
	}

	$bits &= (2**($length - 1) - 1);

	if($neg) {
		$bits -= 2**($length - 1);
	}

	return($bits);
}

sub timestamp2datetime {
	my $ts = shift;
   if ($ts < 0x20000000) {
      return "BMC Uptime",sprintf("%6d s",$ts);
   }
	my @t = localtime($ts);
	my $time = strftime("%H:%M:%S",@t);
	my $date = strftime("%m/%d/%Y",@t);

	return($date,$time);
}

sub decodebcd {
	my $numbers = shift;
	my @bcd;
	my $text;
	my $ms;
	my $ls;

	foreach(@$numbers) {
		$ms = ($_ & 0b11110000) >> 4;
		$ls = ($_ & 0b00001111);
		push(@bcd,$ms);
		push(@bcd,$ls);
	}

	foreach(@bcd) {
		if($_ < 0x0a) {
			$text .= $_;
		}
		elsif($_ == 0x0a) {
			$text .= " ";
		}
		elsif($_ == 0x0b) {
			$text .= "-";
		}
		elsif($_ == 0x0c) {
			$text .= ".";
		}
	}

	return($text);
}

sub storsdrcache {
	my $file = shift;
    my $sessdata = shift;
    unless ($sessdata) { die "need to fix this one too" }
	my $key;
	my $fh;

	system("mkdir -p $cache_dir");
	if(!open($fh,">$file")) {
		return(1);
	}

	flock($fh,LOCK_EX) || return(1);

	my $hdr;
        $hdr->{xcat_sdrcacheversion} = $cache_version;
	nstore_fd($hdr,$fh);
	foreach $key (keys %{$sessdata->{sdr_hash}}) {
		my $r = $sessdata->{sdr_hash}->{$key};
		nstore_fd($r,$fh);
	}

	close($fh);

	return(0);
}

sub loadsdrcache {
    my $sessdata = shift;
	my $file = shift;
	my $r;
	my $c=0;
	my $fh;

	if(!open($fh,"<$file")) {
		return(1);
	}
	$r = retrieve_fd($fh);
        unless ($r) { close($fh); return 1; }
        unless ($r->{xcat_sdrcacheversion} and $r->{xcat_sdrcacheversion} == $cache_version) { close($fh); return 1; } #version mismatch

	flock($fh,LOCK_SH) || return(1);

	while() {
		eval {
			$r = retrieve_fd($fh);
		} || last;

		$sessdata->{sdr_hash}->{$r->sensor_owner_id . "." . $r->sensor_owner_lun . "." . $r->sensor_number} = $r;
	}

	close($fh);

	return(0);
}

sub randomizelist { #in place shuffle of list
	my $list = shift;
	my $index = @$list;
	while ($index--) {
		my $swap=int(rand($index+1));
		@$list[$index,$swap]=@$list[$swap,$index];
	}
}

sub preprocess_request { 
  my $request = shift;
  if (defined $request->{_xcatpreprocessed}->[0] and $request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }
  #exit if preprocessed
  my $callback=shift;
  my @requests;

  my $realnoderange = $request->{node}; #Should be arrayref
  my $command = $request->{command}->[0];
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  my $delay=0;
  my $delayincrement=0;
  my $chunksize=0;
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }

  my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
  if ($usage_string) {
    $callback->({data=>$usage_string});
    $request = {};
    return;
  }

  if ($command eq "rpower") {
      my $subcmd=$exargs[0];
			if($subcmd eq ''){
	  		$callback->({data=>["Please enter an action (eg: boot,off,on, etc)",  $usage_string]});
	  		$request = {};
				return 0;

			}
      if ( ($subcmd ne 'reseat') && ($subcmd ne 'stat') && ($subcmd ne 'state') && ($subcmd ne 'status') && ($subcmd ne 'on') && ($subcmd ne 'off') && ($subcmd ne 'softoff') && ($subcmd ne 'nmi')&& ($subcmd ne 'cycle') && ($subcmd ne 'reset') && ($subcmd ne 'boot') && ($subcmd ne 'wake') && ($subcmd ne 'suspend')) {
	  $callback->({data=>["Unsupported command: $command $subcmd", $usage_string]});
	  $request = {};
	  return;
      }
      if (($subcmd eq 'on' or $subcmd eq 'reset' or $subcmd eq 'boot') and $::XCATSITEVALS{syspowerinterval}) {
		unless($::XCATSITEVALS{syspowermaxnodes}) {
			$callback->({errorcode=>[1],error=>["IPMI plugin requires syspowermaxnodes be defined if syspowerinterval is defined"]});
		        $request = {};
			return 0;
		}
	$chunksize=$::XCATSITEVALS{syspowermaxnodes};
        $delayincrement=$::XCATSITEVALS{syspowerinterval};
      }
  } elsif ($command eq "renergy") {
      # filter out the nodes which should be handled by ipmi.pm
      my (@bmcnodes, @nohandle);
      xCAT::Utils->filter_nodes($request, undef, undef, \@bmcnodes, \@nohandle);
      $realnoderange = \@bmcnodes;
  } elsif ($command eq "rspconfig") {
      # filter out the nodes which should be handled by ipmi.pm
      my (@bmcnodes, @nohandle);
      xCAT::Utils->filter_nodes($request, undef, undef, \@bmcnodes, \@nohandle);
      $realnoderange = \@bmcnodes;
  } elsif ($command eq "rinv") {
      if ($exargs[0] eq "-t" and $#exargs == 0) {
          unshift @{$request->{arg}}, 'all';
      } elsif ((grep /-t/, @exargs) and !(grep /(all|vpd)/, @exargs) ) {
          $callback->({errorcode=>[1],error=>["option '-t' can only work with 'all' or 'vpd'"]});
          $request = {};
          return 0;
      }
  }

  if (!$realnoderange) {
    $usage_string=xCAT::Usage->getUsage($command);
    $callback->({data=>$usage_string});
    $request = {};
    return;
  }   
  
  #print "noderange=@$noderange\n";

  # find service nodes for requested nodes
  # build an individual request for each service node
  my @noderanges;
  srand();
  if ($chunksize) {
     #first, we try to spread out the chunks so they don't happen to correlate to constrained service nodes or circuits
     #for now, will get the sn map for all of them and interleave if dispatching
     #if not dispatching, will randomize the noderange instead to lower likelihood of turning everything on a circuit at once
     if (defined $::XCATSITEVALS{ipmidispatch} and $::XCATSITEVALS{ipmidispatch} =~ /0|n/i) { #no SN indicated, instead do randomize
	randomizelist($realnoderange);
     } else { # sn is indicated
	my $bigsnmap = xCAT::ServiceNodeUtils->get_ServiceNode($realnoderange, "xcat", "MN");
     	foreach my $servicenode (keys %$bigsnmap) { #let's also shuffle within each service node responsibliity
		randomizelist($bigsnmap->{$servicenode})
	}
	#now merge the per-servicenode list into a big list again
	$realnoderange=[];
	while (keys %$bigsnmap) {
		foreach my $servicenode (keys %$bigsnmap) {
			if (@{$bigsnmap->{$servicenode}}) {
				push(@$realnoderange,pop(@{$bigsnmap->{$servicenode}}));
			} else {
				delete $bigsnmap->{$servicenode};
			}
		}
	}
	
     }
     while (scalar(@$realnoderange)) {
             my @tmpnoderange;
	     while (scalar(@$realnoderange) and $chunksize) {
		push @tmpnoderange,(shift @$realnoderange);
		$chunksize--;
	     }
	     push @noderanges,\@tmpnoderange;
	     $chunksize=$::XCATSITEVALS{syspowermaxnodes};
      }	
  } else {
     @noderanges=($realnoderange);
  }
  foreach my $noderange (@noderanges) {  
     my $sn;
     if (defined $::XCATSITEVALS{ipmidispatch} and $::XCATSITEVALS{ipmidispatch} =~ /0|n/i) {
        $sn = { '!xcatlocal!' => $noderange };
     } else {
        $sn = xCAT::ServiceNodeUtils->get_ServiceNode($noderange, "xcat", "MN");
     }

     # build each request for each service node
 
     foreach my $snkey (keys %$sn)
     {
       #print "snkey=$snkey\n";
       my $reqcopy = {%$request};
       $reqcopy->{node} = $sn->{$snkey};
       unless ($snkey eq '!xcatlocal!') {
          $reqcopy->{'_xcatdest'} = $snkey;
       }
       $reqcopy->{_xcatpreprocessed}->[0] = 1;
       if ($delay) { $reqcopy->{'_xcatdelay'} = $delay; }
       push @requests, $reqcopy;
     }
     $delay += $delayincrement;
  }
  return \@requests;
}
    
     
sub getipmicons {
    my $argr=shift;
    #$argr is [$node,$nodeip,$nodeuser,$nodepass];
    my $cb = shift;
    my $ipmicons={node=>[{name=>[$argr->[0]]}]};
    $ipmicons->{node}->[0]->{bmcaddr}->[0]=$argr->[1];
    $ipmicons->{node}->[0]->{bmcuser}->[0]=$argr->[2];
    $ipmicons->{node}->[0]->{bmcpass}->[0]=$argr->[3];
    my $ipmisess =  xCAT::IPMI->new(bmc=>$argr->[1],userid=>$argr->[2],password=>$argr->[3]);
    if ($ipmisess->{error}) {
        xCAT::SvrUtils::sendmsg([1,$ipmisess->{error}],$cb,$argr->[0],%allerrornodes);
        return;
    } 
    $ipmisess->{ipmicons} = $ipmicons;
    $ipmisess->{cb} = $cb;
    $ipmisess->subcmd(netfn=>0x6,command=>0x38,data=>[0x0e,0x04],callback=>\&got_channel_auth_cap_foripmicons,callback_args=>$ipmisess);
}
sub got_channel_auth_cap_foripmicons {
    my $rsp = shift;
    my $ipmis = shift;
    if ($rsp->{error}) {
        return;
    }
    if ($rsp->{code} != 0) { return; }
    my $cb = $ipmis->{cb};
    $cb->($ipmis->{ipmicons}); #ipmicons);
}


# scan subroutine is used to scan the hardware devices which installed on the host node
# In current implementation, only the mic cards will be scanned.
# scan
# scan -u/-w/-z
my @rscan_header = (
  ["type",          "%-8s" ],
  ["name",          "" ],
  ["id",            "%-8s" ],
  ["host",           "" ]);

sub scan {
    my $request = shift;
    my $subreq = shift;
    my $nodes = shift;
    my $args = shift;

    my $usage_string = "rscan [-u][-w][-z]";

    my ($update, $write, $stanza);
    foreach (@$args) {
        if (/-w/) {
            $write= 1;
        } elsif (/-u/) {
            $update = 1;
        } elsif (/-z/) {
            $stanza = 1;
        } else {
            $callback->({error=>[$usage_string]});
            return;
        }
    }

    my $output = xCAT::Utils->runxcmd({ command => ['xdsh'], 
                                       node => $nodes,
                                       arg => ['/opt/intel/mic/bin/micinfo', '-listDevices'] }, $subreq, 0, 1);

    # parse the output from 'xdsh micinfo -listDevices'
    my %host2mic;
    my $maxhostname = 0;
    foreach (@$output) {
        foreach (split /\n/, $_) {
            if (/([^:]*):\s+(\d+)\s*\|/) {
                my $host = $1;
                my $deviceid = $2;
                push @{$host2mic{$host}}, $deviceid;
                if (length($host) > $maxhostname) {
                    $maxhostname = length($host);
                }
            }
        }
    }

    # generate the display message
    my @displaymsg;
    my $format = sprintf "%%-%ds",($maxhostname+10);
    $rscan_header[1][1] = $format;
    $format = sprintf "%%-%ds",($maxhostname+2);
    $rscan_header[3][1] = $format;
    if ($stanza) {
        # generate the stanza for each mic
        foreach (keys %host2mic) {
            my $host = $_;
            foreach (@{$host2mic{$host}}) {
                my $micid = $_;
                push @displaymsg, "$host-mic$micid:";
                push @displaymsg, "\tobjtype=node";
                push @displaymsg, "\tmichost=$host";
                push @displaymsg, "\tmicid=$micid";
                push @displaymsg, "\thwtype=mic";
                push @displaymsg, "\tmgt=mic";
            }
        }
    } else {
        # generate the headers for scan message
        my $header;
        foreach ( @rscan_header ) {
            $header .= sprintf @$_[1],@$_[0];
        }
        push @displaymsg, $header;

        # generate every entries
        foreach (keys %host2mic) {
            my $host = $_;
            foreach (@{$host2mic{$host}}) {
                my $micid = $_;
                my @data = ("mic", "$host-mic$micid", "$micid", "$host");
                my $i = 0;
                my $entry;
                foreach ( @rscan_header ) {
                    $entry .= sprintf @$_[1],$data[$i++];
                }
                push @displaymsg, $entry;
            }
        }
    }

    $callback->({data=>\@displaymsg});

    unless ($update || $write) {
        return;
    }

    # for -u / -w, write or update the mic node in the xCAT DB
    my $nltab = xCAT::Table->new('nodelist');
    my $mictab = xCAT::Table->new('mic');
    my $nhmtab = xCAT::Table->new('nodehm');
    if (!$nltab || !$mictab || !$nhmtab) {
        $callback->({error=>["Open database table failed."], errorcode=>1});
        return;
    }

    # update the node to the database
    foreach (keys %host2mic) {
        my $host = $_;
        foreach (@{$host2mic{$host}}) {
            my $micid = $_;
            my $micname = "$host-mic$micid";
            # update the nodelist table
            $nltab->setAttribs({node=>$micname}, {groups=>"all,mic"});
            # update the mic table
            $mictab->setAttribs({node=>$micname}, {host=>$host, id=>$micid, nodetype=>'mic'});
            # update the nodehm table
            $nhmtab->setAttribs({node=>$micname}, {mgt=>'mic',cons=>'mic'});
        }
    }
}

   
sub process_request {
  my $request = shift;
  $callback = shift;
  my $subreq = shift;
  my $noderange = $request->{node}; #Should be arrayref
  my $command = $request->{command}->[0];
  my $extrargs = $request->{arg};
  my @exargs=($request->{arg});
  if (ref($extrargs)) {
    @exargs=@$extrargs;
  }
	my $ipmiuser = 'USERID';
	my $ipmipass = 'PASSW0RD';
	my $ipmitrys = 3;
	my $ipmitimeout = 2;
	my $ipmitab = xCAT::Table->new('ipmi');
	my $tmp;
        if ($::XCATSITEVALS{ipmitimeout}) { $ipmitimeout = $::XCATSITEVALS{ipmitimeout} };
        if ($::XCATSITEVALS{ipmiretries}) { $ipmitrys = $::XCATSITEVALS{ipmitretries} };
        if ($::XCATSITEVALS{ipmisdrcache}) { $enable_cache = $::XCATSITEVALS{ipmisdrcache} };

    #my @threads;
    my @donargs=();
    if ($request->{command}->[0] =~ /fru/) {
        my $vpdtab = xCAT::Table->new('vpd');
        $vpdhash = $vpdtab->getNodesAttribs($noderange,[qw(serial mtm asset)]);
    }
	my $ipmihash = $ipmitab->getNodesAttribs($noderange,['bmc','username','password']) ;
	my $authdata = xCAT::PasswordUtils::getIPMIAuth(noderange=>$noderange,ipmihash=>$ipmihash);
	foreach(@$noderange) {
		my $node=$_;
		my $nodeuser=$authdata->{$node}->{username};
		my $nodepass=$authdata->{$node}->{password};
		my $nodeip = $node;
		my $ent;
		if (defined($ipmitab)) {
			$ent=$ipmihash->{$node}->[0];
			if (ref($ent) and defined $ent->{bmc}) { $nodeip = $ent->{bmc}; }
		}
	if ($nodeip =~ /,/ and grep ({ $_ eq $request->{command}->[0] } qw/rinv reventlog rvitals rspconfig/)) { #multi-node x3950 X5, for example
		my $bmcnum=1;
		foreach (split /,/,$nodeip) {
        		push @donargs,[$node,$_,$nodeuser,$nodepass,$bmcnum];
			$bmcnum+=1;
		}
	} else {
		$nodeip =~ s/,.*//; #stri
        	push @donargs,[$node,$nodeip,$nodeuser,$nodepass,1];
	}
    }
    if ($request->{command}->[0] eq "getipmicons") {
        foreach (@donargs) {
            getipmicons($_,$callback);
        }
    	while (xCAT::IPMI->waitforrsp()) { yield };
        return;
    }

    if ($request->{command}->[0] eq "rspconfig") {
        my $updatepasswd = 0;
        my $index = 0;
        foreach (@{$request->{arg}}) {
            if ($_ =~ /^USERID=\*$/) {
                 $updatepasswd = 1;
                 last;
            }
            $index++;
        }
        if ($updatepasswd) {
            splice(@{$request->{arg}}, $index, 1);
            @exargs=@{$request->{arg}};
            foreach (@donargs) {
                my $cliuser = $authdata->{$_->[0]}->{cliusername};
                my $clipass = $authdata->{$_->[0]}->{clipassword};
                xCAT::IMMUtils::setupIMM($_->[0],curraddr=>$_->[1],skipbmcidcheck=>1,skipnetconfig=>1,cliusername=>$cliuser,clipassword=>$clipass,callback=>$callback);
            }
            if ($#exargs == -1) {
                return;
            }
        }
    }

    # handle the rscan to scan the mic on the target node
    if ($request->{command}->[0] eq "rscan") {
        scan ($request, $subreq, $noderange, $extrargs);
        return;
    }

  #get new node status
  my %oldnodestatus=(); #saves the old node status
  my $check=0;
  my $global_check=1;
  if (defined $::XCATSITEVALS{nodestatus} and $::XCATSITEVALS{nodestatus} =~ /0|n|N/) { $global_check=0; }


  if ($command eq 'rpower') {
    if (($global_check) && ($extrargs->[0] ne 'stat') && ($extrargs->[0] ne 'status') && ($extrargs->[0] ne 'state') && ($extrargs->[0] ne 'suspend') && ($extrargs->[0] ne 'wake')) { 
      $check=1; 
      my @allnodes=();
      foreach (@donargs) { push(@allnodes, $_->[0]); }

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
      if (($extrargs->[0] eq 'off') || ($extrargs->[0] eq 'softoff')) { 
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

      #donot update node provision status (installing or netbooting) here
      xCAT::Utils->filter_nostatusupdate(\%newnodestatus);
      #print "newstatus" . Dumper(\%newnodestatus);
      xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
    }
  }

    my $children = 0;
    my $sub_fds = new IO::Select;
    foreach (@donargs) {
      donode($_->[0],$_->[1],$_->[2],$_->[3],$_->[4],$ipmitimeout,$ipmitrys,$command,-args=>\@exargs);
	}
    while (xCAT::IPMI->waitforrsp()) { yield };
    my $node;
    foreach $node (keys %sessiondata) {
        if ($sessiondata{$node}->{ipmisession}) {
            $sessiondata{$node}->{ipmisession}->logout();
        }
    }
    while (xCAT::IPMI->waitforrsp()) { yield };
    if (keys %needbladeinv) {
	#ok, we have some inventory data that, for now, suggests blade plugin to getdata from blade plugin
#	my @bladenodes = keys %needbladeinv;
#	$request->{arg}=['mac'];
#        $request->{node}=\@bladenodes;
#	require xCAT_plugin::blade;
#	xCAT_plugin::blade::process_request($request,$callback);
    }
####return;
####while ($sub_fds->count > 0 and $children > 0) {
####  my $handlednodes={};
####  forward_data($callback,$sub_fds,$handlednodes);
####  #update the node status to the nodelist.status table
####  if ($check) {
####    updateNodeStatus($handlednodes, \@allerrornodes);
####  }
####}
####
#####Make sure they get drained, this probably is overkill but shouldn't hurt
####my $rc=1;
####while ( $rc>0 ) {
####  my $handlednodes={};
####  $rc=forward_data($callback,$sub_fds,$handlednodes);
####  #update the node status to the nodelist.status table
####  if ($check) {
####    updateNodeStatus($handlednodes, \@allerrornodes);
####  }
####} 

    if ($check) {
        #print "allerrornodes=@allerrornodes\n";
        #revert the status back for there is no-op for the nodes
        my %old=(); 
        foreach my $node (keys %allerrornodes) {
    	    my $stat=$oldnodestatus{$node};
    	    if (exists($old{$stat})) {
    		    my $pa=$old{$stat};
        		push(@$pa, $node);
    	    } else {
          		$old{$stat}=[$node];
	        }
        } 
        xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%old, 1);
    }  
}

#sub updateNodeStatus {
#  my $handlednodes=shift;
#  my $allerrornodes=shift;
#  foreach my $node (keys(%$handlednodes)) {
#    if ($handlednodes->{$node} == -1) { push(@$allerrornodes, $node); }  
#  }
#}



#sub forward_data { #unserialize data from pipe, chunk at a time, use magic to determine end of data structure
# my $callback = shift;
# my $fds = shift;
# my $errornodes=shift;

# my @ready_fds = $fds->can_read(1);
# my $rfh;
# my $rc = @ready_fds;
# foreach $rfh (@ready_fds) {
#   my $data;
#   if ($data = <$rfh>) {
#     while ($data !~ /ENDOFFREEZE6sK4ci/) {
#       $data .= <$rfh>;
#     }
#     eval { print $rfh "ACK\n"; };  # Ignore ack loss to child that has given up and exited
#     my $responses=thaw($data);
#     foreach (@$responses) {
#       #save the nodes that has errors and the ones that has no-op for use by the node status monitoring
#       my $no_op=0;
#       if (exists($_->{node}->[0]->{errorcode})) { $no_op=1; }
#       else { 
#         my $text=$_->{node}->[0]->{data}->[0]->{contents}->[0];
#         #print "data:$text\n";
#         if (($text) && ($text =~ /$status_noop/)) {
#       $no_op=1;
#           #remove the symbols that meant for use by node status
#           $_->{node}->[0]->{data}->[0]->{contents}->[0] =~ s/ $status_noop//; 
#         }
#       }  
#   #print "data:". $_->{node}->[0]->{data}->[0]->{contents}->[0] . "\n";
#       if ($no_op) {
#         if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=-1; } 
#       } else {
#         if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=1; } 
#       }
#       $callback->($_);
#     }
#   } else {
#     $fds->remove($rfh);
#     close($rfh);
#   }
# }
# yield; #Avoid useless loop iterations by giving children a chance to fill pipes
# return $rc;
#}

sub donode {
  my $node = shift;
  my $bmcip = shift;
  my $user = shift;
  my $pass = shift;
  my $bmcnum = shift;
  my $timeout = shift;
  my $retries = shift;
  my $command = shift;
  my %namedargs=@_;
  my $extra=$namedargs{-args};
  my @exargs=@$extra;
  $sessiondata{$node} = {
      node => $node, #this seems redundant, but some code will not be privy to what the key was
      bmcnum => $bmcnum,
      ipmisession => xCAT::IPMI->new(bmc=>$bmcip,userid=>$user,password=>$pass),
      command => $command,
      extraargs => \@exargs,
      subcommand => $exargs[0],
  };
  if ($sessiondata{$node}->{ipmisession}->{error}) {
      xCAT::SvrUtils::sendmsg([1,$sessiondata{$node}->{ipmisession}->{error}],$callback,$node,%allerrornodes);
  } else {
    my ($rc,@output) = ipmicmd($sessiondata{$node});
    sendoutput($rc,@output);
    yield;
    return $rc;
  }
  #my $msgtoparent=freeze(\@outhashes);
 # print $outfd $msgtoparent;
}

sub sendoutput {
    my $rc=shift;
    foreach (@_) {
        my %output;
        (my $desc,my $text) = split(/:/,$_,2);
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
        $output{node}->[0]->{name}->[0]="BADCODE";
        if ($rc) {
          $output{node}->[0]->{errorcode}=[$rc];
            $output{node}->[0]->{error}->[0]=$text;
        } else {
            $output{node}->[0]->{data}->[0]->{contents}->[0]=$text;
        }
        $callback->(\%output);
        #push @outhashes,\%output; #Save everything for the end, don't know how to be slicker with Storable and a pipe
#        print $outfd freeze([\%output]);
#        print $outfd "\nENDOFFREEZE6sK4ci\n";
#        yield;
#        waitforack($outfd);
    }
}

##########################################################################
# generate hardware tree, called from lstree.
##########################################################################
sub genhwtree
{
    my $nodelist = shift;  # array ref
	my $callback = shift;
	my %hwtree;

    my $bmchash;
    # read ipmi.bmc
    my $ipmitab = xCAT::Table->new('ipmi');
    if ($ipmitab)
    {
        $bmchash = $ipmitab->getNodesAttribs($nodelist, ['bmc']);
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Can not open ipmi table.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
    }

    foreach my $node (@$nodelist)
    {
        if ($bmchash->{$node}->[0]->{'bmc'})
        {
            push @{$hwtree{$bmchash->{$node}->[0]->{'bmc'}}}, $node;
        }
    
    }

    return \%hwtree;

}




1;
