#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::MacMap;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

require Exporter;
our @ISA=qw/Exporter/;
our @EXPORT_OK=qw/walkoid/;
use strict;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::TableUtils;
use IO::Select;
use IO::Handle;
use Sys::Syslog;
#use Data::Dumper;
use POSIX qw/WNOHANG/;
use SNMP;
my %cisco_vlans; #Special hash structure to reflect discovered VLANS on Cisco equip
#use IF-MIB (1.3.6.1.2.1.2) for all switches
#   1.3.6.1.2.1.31.1.1 - ifXtable
#       1.3.6.1.2.1.31.1.1.1.1.N = name - ifName
#Using BRIDGE-MIB for most switches( 1.3.6.1.2.1.17 )
#   1.3.6.1.2.1.17.1.4 - dot1dBasePortTable
#       1.3.6.1.2.1.17.1.4.1.1.X = N - dot1dBasePort
#   1.3.6.1.2.1.17.4.3 - dot1dTpFdbTable #FAILS on FORCE10,
#       
#If particular result fails, fallback to Q-BRIDGE-MIB for Force10 (1.3.6.1.2.1.17.7)
#   1.3.6.1.2.1.17.7.1.2.2 - dot1qTpFdbTable 


#now for the lldp fun.  lldp mib uses yet another index.  The mib states
#that the index should correlate to dot1dbaseport, however
#limits the index to 4096 while dot1dbaseport can go much higher
#confirmed on various switches that this index cannot be numerically correlated
#to if-mib in a reliable fashion immediately for all switches
#LldpPortIdSubtype dictates the format
#in order of preference on subtype:
#if 5, then portid==ifName (my favorite, least work, no further lookups)
#if 3, then may be able to link into IF-MIB via ifPhysAddress matching more reliably
#if 7, then it may be anything at all, portDesc may be best option when encounterd, though occasionally looks like a 5.  In the cases where it looks like a 5,
#portdesc seems usable too.
#detailed switch by switch results below
#on Force10, the following happens:
#   -index violates mib by going over max value
#   -subtype is 5, meaning portid should be == ifName, usable
#   -lldpPortDesc is blank, cannot be used
#on juniper:
#   -index violates mib by not matching dot1dbaseport
#   -lldpPortId is 'helpfully', the index in ascii form (gee thanks), useless example of type 7
#   -lldpPortDesc looks like "ge-1/0/43.0",only hope.
#bigiron, fcx, turboiron, :
#   -lldpPortId is a 3 mac address
#   --lldpportdesc looks useful 10GigabitEthernet6/6
#netiron ces: no support
#cisco ios:
#   -the portid is == ifname
#   subtype is 5 or 7, but either way it acts like 5
#   -portdesc == ifdesc, useful for when 7 is seen for fallback
#
#voltaire 10ge: no support
#
#bnt g8124 and 8052
#   -subtype of 7
#   -the index, portid, and portdesc are all the same (i.e. 18="18"="18")

#smc 8848:
#   -subtype of 3, hex mac string
#   -portdesc matches ifDesc, no mapping to ifName
#smc 8126: no support for lldp mib
#ibm b32l: no support

#



sub namesmatch {
=pod

MacMap attempts to do it's best to determine whether or not a particular SNMP description of
a port matches the user specified value in the configuration.  Generally, if the configuration
consists of non-stacked switches without line cards, the user should only need to specify the
port number without any characters or / characters.  If the configuration contains line cards 
or stacked switches, use of that particular switch's appropriate / syntax in generally called 
for.  The exception being stacked SMC 8848 switches, in which all ports are still single 
numbers, and the ports on the second switch begin at 57.

If difficulty is encountered, or a switch is attempted with a format that doesn't match any 
existing rule, it is recommended to use snmpwalk on the switch with the .1.3.6.1.2.1.31.1.1.1.1
OID, and have the switch table port value match exactly the format suggested by that OID. 

=cut
  my $namepercfg = shift;
  my $namepersnmp = shift;
  if ($namepercfg eq $namepersnmp) {
    return 1; # They matched perfectly
  }
  #Begin guessing, first off, all tested scenarios have likely correct guesses ending
  #in the cfg string, with some non-numeric prefix before it.
  #3com convention, contributed by Aaron Knister
  if ( $namepersnmp =~ /^RMON Port (0?)(\d+) on unit \d+/ ) {
     if ( $2 =~ $namepercfg ) {
         return 1;
     }
  }

  # dell 6248 convention
  if ( $namepersnmp =~ /^Unit \d Port (\d+)$/ ) {
    if ( $1 eq $namepercfg ) {
        return 1;
    }
  }


  unless ($namepersnmp =~ /[^0123456789]$namepercfg(\.0)?\z/)  { #ensure name from user exists in the string without being preceeded immediately by a number, and allowing a .0 to exist after the cfg for juniper
    #Most common case, won't match at all
    return 0;
  }
  #at this point we know the string the user wanted does exist on this port, now we move on to non-ethernet ports that may ambiguously match the user request as well

  #stop contemplating vlan, Nu, stacking ports, and console interfaces
  if (($namepersnmp =~ /vl/i) or ($namepersnmp =~ /Nu/) or ($namepersnmp =~ /onsole/) or ($namepersnmp =~ /Stack/) or ($namepersnmp =~ /Trunk/))  {
    return 0;
  }
  #broken up for code readablitiy, don't check port channel numbers or CPU
  #have to distinguish betweer Port and Po and PortChannel
  if (($namepersnmp !~ /Port #/) and ($namepersnmp !~ /Port\d/) and ($namepersnmp =~ /Po/) or ($namepersnmp =~ /po\d/) or ($namepersnmp =~ /XGE/) or ($namepersnmp =~ /LAG/) or ($namepersnmp =~ /CPU/)) {
    return 0;
  }
  #don't contemplate ManagementEthernet
  if (($namepersnmp =~ /Management/)) {
    return 0;
  }
  #The blacklist approach has been exhausted.  For now, assuming that means good,
  #if something ambiguous happens, the whitelist would have been:
  #'Port','Port #','/' (if namepercfg has no /, then / would be...),
  #'Gi','Te','GigabitEthernet','TenGigabitEthernet'
  return 1;
}

sub new {
  my $self = {};
  # Since switch.pm and lsslp.pm both create a MacMap object, SNMP is still required at xcatd start up.
  # So we are going back to "use SNMP;" at the top of this file so RPM will automatically generate a prereq.
  #eval { require SNMP; };
  #if ($@) { die "SNMP support required to use MacMAP"; }
  my $proto = shift;
  my $class = ref($proto) || $proto;

  bless ($self, $class);
  return $self;
}

sub rvlan {
    #The Q-BRIDGE way:
    #IF-MIB for ifName<->ifIndex (much like the find_mac code)
    #BRIDGE-MIB for ifIndex<->BridgeIndex (again, familiar)
    #Q-BRIDGE-MIB for vlanId<->vlanIndex
    #             and vlanIndex<->dot1qVlanStaticUntaggedPorts
    #             and vlanIndex<->dot1qVlanStaticEgressPorts (tagged allowed ports)
    # for changing the PVID of a port, the current bitfields must be read, the offset into the bitfield of the correct bridge index must be zero everywhere but vlan 1, then must be 1 in the target vlan.  If it is zeroed in a vlan other than 1 without being 'oned' elsewhere, it reverts to vlan 1
    #that is the documented steps for brocade
    #some switches support vlan creation via qbridge, either via writing to the table or write to the row.  SMC has write to non-existent row and vlanId==vlanIndex, which is logical.  If a switches vlanIndex!=vlanId, QBridge doesnet' offer a clean injection point.
    #QBridge also has dot1qPvid, but wasn't writable in Brocade.. it is readable though, so can guide the read, mask out, mask in activity above
    #argument specification:
    #  nodes => [ list reference of nodes to query/set ]
    #  operation => "pvid=<vid> or vlan=<vid>" for now, addvlan= and delvlan= for tagged vlans, 'pvid', vlan, or stat without = checks current value
    my $self=shift;
    my $community = "public";
    #$self->{sitetab} = xCAT::Table->new('site');
    #my $tmp = $self->{sitetab}->getAttribs({key=>'snmpc'},'value');
    my @snmpcs =  xCAT::TableUtils->get_site_attribute("snmpc");
    my $tmp = $snmpcs[0];
    if ( defined($tmp) ) { $community = $tmp }
    my %args = @_;
    my $op=$args{operation};
    my $nodes=$args{nodes};
    #first order of business is to identify the target switches
    my $switchtab=xCAT::Table->new('switch',-create=>0);
    unless ($switchtab) { return; }
    my $switchents = $switchtab->getNodesAttribs($nodes,[qw/switch port interface/]);
    my $node;
    foreach $node (keys %$switchents) {
        my $entry;
        foreach $entry (@{$switchents->{$node}}) {
            #skip the none primary interface.
            # The vlaue of the primary interface could be empty, primary or primary:ethx
	    if (defined($entry->{interface})) {
		if ($entry->{interface} !~ /primary/) {
		    next;
		}
	    }

            $self->{switches}->{$entry->{switch}}->{$entry->{port}} = $node;
        }
    } 
    my $switches=[keys %{$self->{switches}}];
    my $switchestab=xCAT::Table->new('switches',-create=>0);
    my @switchesents;
    if ($switchestab) {
        foreach (values %{$switchestab->getNodesAttribs($switches,[qw(switch snmpversion username password privacy auth)])}) {
            push @switchesents,@$_;
        }
    }
    $self->fill_switchparms(community=>$community,switchesents=>\@switchesents);
    my $switch;
    foreach $switch (keys %{$self->{switches}}) { #first we'll extract the lay of the land...
          $self->refresh_switch(undef,$community,$switch);
          unless ($self->{switchinfo}->{$switch}->{vlanidtoindex}) { #need vlan id to vlanindex map for qbridge unless cisco
            $self->scan_qbridge_vlans(switch=>$switch,community=>$community);
          }
    }
    #print Dumper($self->{switchinfo});
       #   $self->{switchinfo}->{$switch}->{bridgeidxtoifname}->{$boid}=$portname;
       #   $self->{switchinfo}->{$switch}->{ifnametobridgeidx}->{$portname}=$boid;
    $op =~ s/stat/pvid/;
    $op =~ s/vlan/pvid/;
    if ($op =~ /^addpvid/) { # add tagged vlan
    } elsif ($op =~ /delpvid/) { #remove tagged vlan
    } else { #native vlan query or set
    }
}
sub scan_qbridge_vlans {
    my $self = shift;
    my %args = @_;
    my $switch = $args{switch};
    my $session = $self->{switchsessions}->{$switch};
    $self->{switchinfo}->{vlanindextoid} = walkoid($session,'.1.3.6.1.2.1.17.7.1.4.2.1.3');
    foreach (keys %{$self->{switchinfo}->{vlanindextoid}}) {
#TODO: try to scan
    }
}
sub find_mac {
# This function is given a mac address, checks for given mac address
# and returns undef if unable to find the node, and the nodename otherwise
  my $self = shift;
  my $mac = shift;
  my $cachedonly = shift;
# For now HARDCODE (TODO, configurable?) a cache as stale after five minutes
# Also, if things are changed in the config, our cache could be wrong, 
# invalidate on switch table write?
  if ($self->{mactable}->{lc($mac)} and ($self->{timestamp} > (time() - 300))) { 
    my $reftbl = 0;
    foreach (keys %{$self->{mactable}}) {
      if ((lc($mac) ne $_) and ($self->{mactable}->{lc($mac)} eq $self->{mactable}->{$_})) {
        #$reftbl = 1;
        #Delete *possibly* stale data, without being heavy handed..
        #But if this mac indicates multiple nodes, leave it there
        if ( $self->{mactable}->{lc($mac)} !~ /,/)
        {
            delete $self->{mactable}->{$_};
        }
      }
    }
    unless ($reftbl) { return $self->{mactable}->{lc($mac)};}
  }
  #If requesting a cache only check or the cache is a mere 20 seconds old
  #don't bother querying switches
  if ($cachedonly or ($self->{timestamp} > (time() - 20))) { return undef; }
  $self->refresh_table; #not cached or stale cache, refresh
  if ($self->{mactable}->{lc($mac)}) {
    return $self->{mactable}->{lc($mac)};
  }
  return undef;
}

sub fill_switchparms {
  my $self = shift;
  my %args = @_;
  my $community=$args{community};
  $self->{switchparmhash}={};
  my @switchentries = @{$args{switchesents}};
  foreach (@switchentries) {
     my $curswitch=$_->{switch};
     $self->{switchparmhash}->{$curswitch}=$_;
     if ($_->{snmpversion}) {
          if ($_->{snmpversion} =~ /3/) { #clean up to accept things like v3 or ver3 or 3, whatever.
              $self->{switchparmhash}->{$curswitch}->{snmpversion}=3;
              unless ($_->{auth}) {
                $self->{switchparmhash}->{$curswitch}->{auth}='md5'; #Default to md5 auth if not specified but using v3
              }
          } elsif ($_->{snmpversion} =~ /2/) {
              $self->{switchparmhash}->{$curswitch}->{snmpversion}=2;
          } else {
              $self->{switchparmhash}->{$curswitch}->{snmpversion}=1; #Default to lowest common denominator, snmpv1
          }
     }
     unless (defined $_->{password}) { #if no password set, inherit the community
         $self->{switchparmhash}->{$curswitch}->{password}=$community;
     }
  }
}

sub refresh_table {
  my $self = shift;
  my $curswitch;
  $self->{mactable}={};
  $self->{switchtab} = xCAT::Table->new('switch', -create => 1);
  $self->{switchestab} = xCAT::Table->new('switches', -create => 1);
  my @switchentries=$self->{switchestab}->getAllNodeAttribs([qw(switch snmpversion username password privacy auth)]);
  my $community = "public";
  #$self->{sitetab} = xCAT::Table->new('site');
  #my $tmp = $self->{sitetab}->getAttribs({key=>'snmpc'},'value');
  #if ($tmp and $tmp->{value}) { $community = $tmp->{value} }
  my @snmpcs =  xCAT::TableUtils->get_site_attribute("snmpc");
  my $tmp = $snmpcs[0];
  if ( defined($tmp) ) { $community = $tmp }
  else { #Would warn here.. 
  }
  $self->{switchparmhash}={};
  foreach (@switchentries) {
      $curswitch=$_->{switch};
      $self->{switchparmhash}->{$curswitch}=$_;
      if ($_->{snmpversion}) {
          if ($_->{snmpversion} =~ /3/) { #clean up to accept things like v3 or ver3 or 3, whatever.
              $self->{switchparmhash}->{$curswitch}->{snmpversion}=3;
              unless ($_->{auth}) {
                $self->{switchparmhash}->{$curswitch}->{auth}='md5'; #Default to md5 auth if not specified but using v3
              }
          } elsif ($_->{snmpversion} =~ /2/) {
              #$self->{switchparmhash}->{$curswitch}->{snmpversion}=2;
              # we have Juniper switch enabled snmp v2c, not v2
              $self->{switchparmhash}->{$curswitch}->{snmpversion}=$_->{snmpversion};
          } else {
              $self->{switchparmhash}->{$curswitch}->{snmpversion}=1; #Default to lowest common denominator, snmpv1
          }
        }
        unless (defined $_->{password}) { #if no password set, inherit the community
            $self->{switchparmhash}->{$curswitch}->{password}=$community;
        }
  }
  my %checked_pairs;
  my @entries = $self->{switchtab}->getAllNodeAttribs(['node','port','switch']);
  #Build hash of switch port names per switch
  $self->{switches} = {};
  foreach my $entry (@entries) {
    if (defined($entry->{switch}) and $entry->{switch} ne "" and defined($entry->{port}) and $entry->{port} ne "") {

    	if ( !$self->{switches}->{$entry->{switch}}->{$entry->{port}})
        {
            $self->{switches}->{$entry->{switch}}->{$entry->{port}} = $entry->{node};
        }
        else
        {
            $self->{switches}->{$entry->{switch}}->{$entry->{port}} .= ",$entry->{node}";
        }
    } else {
        xCAT::MsgUtils->message("S","xCAT Table error:".$entry->{node}."Has missing or invalid switch.switch and/or switch.port fields");
    }
  } 
  my $children = 0;
  my $inputs = new IO::Select;
  $SIG{CHLD}= sub { while(waitpid(-1,WNOHANG) > 0) { $children-- } };
  foreach my $entry (@entries) {
    if ($checked_pairs{$entry->{switch}}) {
      next;
    }
    while($children > 64) {
    	$self->handle_output($inputs);
    }
    $checked_pairs{$entry->{switch}}=1;
    pipe my $child,my $parent;
    $child->autoflush(1);
    $parent->autoflush(1);
    $children++;
    my $cpid = xCAT::Utils->xfork;
    unless (defined $cpid) { die "Cannot fork" };
    if ($cpid == 0) {
      close($child);
      $self->refresh_switch($parent,$community,$entry->{switch});
      exit(0);
    }
    close($parent);
    $inputs->add($child);
  }
  while($children) {
    $self->handle_output($inputs);
  }
  while ($self->handle_output($inputs)) {}; #Drain the pipes
  $self->{timestamp}=time;
}

sub handle_output {
  my $self = shift;
  my $inputs = shift;
  my @readied = $inputs->can_read(1);
  my $rc = @readied;
  my $ready;
  foreach $ready (@readied) {
    my $line = <$ready>;
    unless ($line) {
      $inputs->remove($ready);
      close($ready);
      next;
    }
    $line =~ m/^([^|]*)\|(.*)/;
    $self->{mactable}->{$1}=$2;
  }
  return $rc;
}

sub walkoid {
  my $session = shift;
  my $oid = shift;
  my %namedargs = @_;
  my $retmap = undef; 
  my $varbind = new SNMP::Varbind([$oid,'']);
  $session->getnext($varbind);
  if ($session->{ErrorStr}) {
    unless ($namedargs{silentfail}) {
        if ($namedargs{ciscowarn}) {
            xCAT::MsgUtils->message("S","Error communicating with ".$session->{DestHost}." (First attempt at indexing by VLAN failed, ensure that the switch has the vlan configured such that it appears in 'show vlan'): ".$session->{ErrorStr});
        } else {
            xCAT::MsgUtils->message("S","Error communicating with ".$session->{DestHost}.": ".$session->{ErrorStr});
        }
    }
    return undef;
  }
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

sub getsnmpsession {
#gets an snmp v3 session appropriate for a switch using the switches table for guidance on the hows
#arguments: switch => $switchname and optionally vlan=> $vid if needed for community string indexing
    my $self = shift;
    my %args = @_;
    my $switch = $args{'switch'};
    my $vlanid = $args{'vlanid'};
    my $community = $args{'community'};
    my $session;
    my $snmpver='1';
    my $swent = $self->{switchparmhash}->{$switch};

  if ($swent) {
      $snmpver=$swent->{snmpversion};
      $community=$swent->{password};
  }
  if ($snmpver ne '3') {
      if ($vlanid) { $community .= '@'.$vlanid; }
      $session = new SNMP::Session(
                      DestHost => $switch,
                      Version => $snmpver,
                      Community => $community,
                      UseNumeric => 1
                 );
  } else { #we have snmp3
       my %args= (
                      DestHost => $switch,
                      SecName => $swent->{username},
                      AuthProto => uc($swent->{auth}),
                      AuthPass => $community,
                      Version => $snmpver,
                      SecLevel => 'authNoPriv',
                      UseNumeric => 1
       );
      if ($vlanid) { $args{Context}="vlan-".$vlanid; }
      if ($swent->{privacy}) {
          $args{SecLevel}='authPriv';
          $args{PrivProto} = uc($swent->{privacy});
          $args{PrivPass} = $community;
      }
      $session = new SNMP::Session(%args);
  }
  return $session;
}

sub refresh_switch {
  my $self = shift;
  my $output = shift;
  my $community = shift;
  my $switch = shift;

  #if ($error) { die $error; }
  my $session = $self->getsnmpsession('community'=>$community,'switch'=>$switch);
  unless ($session) { xCAT::MsgUtils->message("S","Failed to communicate with $switch"); return; }
  my $namemap = walkoid($session,'.1.3.6.1.2.1.31.1.1.1.1');
    #namemap is the mapping of ifIndex->(human readable name)
  if ($namemap) {
     my $ifnamesupport=0; #Assume broken ifnamesupport until proven good... (Nortel switch)
     foreach (keys %{$namemap}) {
        if ($namemap->{$_}) {
           $ifnamesupport=1;
           last;
        }
     }
     unless ($ifnamesupport) {
        $namemap=0;
     }
  }
  unless ($namemap) { #Failback to ifDescr.  ifDescr is close, but not perfect on some switches
     $namemap = walkoid($session,'.1.3.6.1.2.1.2.2.1.2');
  }
  unless ($namemap) {
    return;
  }
  #Above is valid without community string indexing, on cisco, we need it on the next one and onward
  my $iftovlanmap = walkoid($session,'.1.3.6.1.4.1.9.9.68.1.2.2.1.2',silentfail=>1); #use cisco vlan membership mib to ascertain vlan
  my $trunktovlanmap = walkoid($session,'.1.3.6.1.4.1.9.9.46.1.6.1.1.5',silentfail=>1); #for trunk ports, we are interested in the native vlan
                                                                                        #so we need cisco vtp mib too
  my %vlans_to_check;
  if (defined($iftovlanmap) or defined($trunktovlanmap)) { #We have a cisco, the intelligent thing is to do SNMP gets on the ports 
      $self->{switchinfo}->{$switch}->{vlanidtoindex}="NA";#mark this switch to ignore for qbridge scans
# that we can verify are populated per switch table
    my $portid;
    foreach $portid (keys %{$namemap}) {
      my $portname;
      my $switchport = $namemap->{$portid};
      foreach $portname (keys %{$self->{switches}->{$switch}}) {
        unless (namesmatch($portname,$switchport)) {
            next;
        }
        if (not defined  $iftovlanmap->{$portid} and not defined $trunktovlanmap->{$portid}) {
            xCAT::MsgUtils->message("S","$portid missing from switch");
            next;
        }
        if (defined  $iftovlanmap->{$portid}) {
            $vlans_to_check{"".$iftovlanmap->{$portid}} = 1; #cast to string, may not be needed
            $self->{nodeinfo}->{$self->{switches}->{$switch}->{$portname}}->{vlans}->{$portname}=$iftovlanmap->{$portid};
        } else { #given above if statement, brigetovlanmap *must* be defined*
            $vlans_to_check{"".$trunktovlanmap->{$portid}} = 1; #cast to string, may not be needed
            $self->{nodeinfo}->{$self->{switches}->{$switch}->{$portname}}->{vlans}->{$portname}=$trunktovlanmap->{$portid};
        }
      }
    }
  } else {
    $vlans_to_check{'NA'}=1;
  }

  my $vlan;
  my $iscisco=0;
  foreach $vlan (sort keys %vlans_to_check) { #Sort, because if numbers, we want 1 first, because that vlan should not get communiy string indexed query
    unless (not $vlan or $vlan eq 'NA' or $vlan eq '1') { #don't subject users to the context pain unless needed
        $iscisco=1;
        $session = $self->getsnmpsession('switch'=>$switch,'community'=>$community,'vlanid'=>$vlan);
    }
    unless ($session) { return; } 
    my $bridgetoifmap = walkoid($session,'.1.3.6.1.2.1.17.1.4.1.2',ciscowarn=>$iscisco); # Good for all switches
    if (not ref $bridgetoifmap or !keys %{$bridgetoifmap}) { 
            xCAT::MsgUtils->message("S","Error communicating with ".$session->{DestHost}.": failed to get a valid response to BRIDGE-MIB request");
	    return;
    }

    # my $mactoindexmap = walkoid($session,'.1.3.6.1.2.1.17.4.3.1.2'); 
    my $mactoindexmap = walkoid($session,'.1.3.6.1.2.1.17.7.1.2.2.1.2',silentfail=>1);
    unless (defined($mactoindexmap)) { #if no qbridge defined, try bridge mib, probably cisco
      #$mactoindexmap = walkoid($session,'.1.3.6.1.2.1.17.7.1.2.2.1.2');
      $mactoindexmap = walkoid($session,'.1.3.6.1.2.1.17.4.3.1.2',ciscowarn=>$iscisco); 
    } #Ok, time to process the data
    if (not ref $mactoindexmap or !keys %{$mactoindexmap}) { 
            xCAT::MsgUtils->message("S","Error communicating with ".$session->{DestHost}.": Unable to get MAC entries via either BRIDGE or Q-BRIDE MIB");
	   return;
    }
    foreach my $oid (keys %$namemap) {
    #$oid =~ m/1.3.6.1.2.1.31.1.1.1.1.(.*)/;
      my $ifindex = $oid;
      my $portname;
      my $switchport = $namemap->{$oid};
      foreach $portname (keys %{$self->{switches}->{$switch}}) { # a little redundant, but 
                                                                 # computationally trivial
        unless (namesmatch($portname,$switchport)) { next }
        #if still running, we have match
        foreach my $boid (keys %$bridgetoifmap) {
          unless ($bridgetoifmap->{$boid} == $ifindex) { next; }
          $self->{switchinfo}->{$switch}->{bridgeidxtoifname}->{$boid}=$portname;
          $self->{switchinfo}->{$switch}->{ifnametobridgeidx}->{$portname}=$boid;
          $self->{nodeinfo}->{$self->{switches}->{$switch}->{$portname}}->{portnametobridgeindex}->{$portname}=$boid;
          $self->{nodeinfo}->{$self->{switches}->{$switch}->{$portname}}->{bridgeindextoportname}->{$boid}=$portname;
          my $bridgeport = $boid;
          foreach (keys %$mactoindexmap) { 
            if ($mactoindexmap->{$_} == $bridgeport) {
              my @tmp = split /\./, $_;
              my @mac = @tmp[-6 .. -1];
              my $macstring=sprintf("%02x:%02x:%02x:%02x:%02x:%02x",@mac);
              if ($output) {
                printf $output  "$macstring|%s\n",$self->{switches}->{$switch}->{$portname};
              }
              push @{$self->{nodeinfo}->{$self->{switches}->{$switch}->{$portname}}->{macs}->{$portname}},$macstring; #this could be used as getmacs sort of deal
            }
          }
        }
      }
    }
  }
  $self->{switchsessions}->{$switch}=$session; #save session for future use
}
                



1;
