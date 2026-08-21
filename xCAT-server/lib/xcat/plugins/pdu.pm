# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle pdu

   Supported command:
        rpower
        rinv
        rvitals

=cut

#-------------------------------------------------------
package xCAT_plugin::pdu;

BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::Utils;
use xCAT::FifoPipe;
use xCAT::MsgUtils;
use xCAT::State;
use xCAT::SvrUtils;
use xCAT::Usage;
use xCAT::NodeRange;
use Data::Dumper;
use Getopt::Long;
use File::Path;
use Term::ANSIColor;
use Time::Local;
use strict;
use Class::Struct;
use XML::Simple;
use Storable qw(dclone);
use SNMP;
use Expect;
use Net::Ping;

my $VERBOSE = 0;
my %allerrornodes = ();
my $callback;
my $pdutab;
my $pduhash;

#-------------------------------------------------------
# PDU2-MIB OIDs, used for pdutype=genpdu (generic SNMP PDU).
#
# A single MIB covers the Raritan PX2/PX3/PX4/PXC/SRC/PXO/BCM/BCM2 series, the
# Server Technology PRO3X/PRO4X series and the Legrand intelligent PDUs, so
# these OIDs are model-independent (PDU2-MIB rev 4.3.0, 202410070000Z).
#
# Both outlet tables are INDEX { pduId, outletId }. Per the pduId DESCRIPTION,
# pduId is the PDU's link ID and is 1 when linking is not used; BCM2/PMC use 0
# for the main controller. Linked and BCM2/PMC deployments are out of scope for
# genpdu, because pduoutlet.pdu is parsed as PDU:outlet and has no field for a
# link ID. pduCount reports how many units are behind one agent and is 1 on a
# standalone PDU.
#-------------------------------------------------------
my $PDU2_PDUCOUNT    = ".1.3.6.1.4.1.13742.6.3.1.0";      #pduCount,             ro, scalar
my $PDU2_SWITCHOP    = ".1.3.6.1.4.1.13742.6.4.1.2.1.2";  #switchingOperation,  rw, off(0) on(1) cycle(2)
my $PDU2_OUTLETSTATE = ".1.3.6.1.4.1.13742.6.4.1.2.1.3";  #outletSwitchingState, ro, on(7) off(8)
my $PDU2_OUTLETCOUNT = ".1.3.6.1.4.1.13742.6.3.2.2.1.4";  #outletCount,          ro, INDEX { pduId }
my $PDU2_PDUID       = 1;

#rinv / rvitals sources. The nameplate and unitConfiguration entries are
#INDEX { pduId }; the measurement and sensor-configuration entries are
#INDEX { pduId, <inlet|outlet>Id, sensorType }.
#A sensor whose SensorSignedMinimum is below zero can read negative and must be
#taken from the signed value column, per the SensorSignedMinimum DESCRIPTION.
#The two columns are not interchangeable in either direction: the unsigned
#column is undefined for such a sensor (a PX4 answers 0 for inlet reactive
#power), and the signed column is undefined for sensors whose range exceeds
#Integer32 (the same PX4 answers 0 for active and apparent energy).
my $PDU2_NAMEPLATE       = ".1.3.6.1.4.1.13742.6.3.2.1.1";    #nameplateEntry
my $PDU2_UNITCONF        = ".1.3.6.1.4.1.13742.6.3.2.2.1";    #unitConfigurationEntry
my $PDU2_INLETVAL        = ".1.3.6.1.4.1.13742.6.5.2.3.1.4";  #measurementsInletSensorValue
my $PDU2_INLETSIGNEDVAL  = ".1.3.6.1.4.1.13742.6.5.2.3.1.6";  #measurementsInletSensorSignedValue
my $PDU2_INLETSIGNEDMIN  = ".1.3.6.1.4.1.13742.6.3.3.4.1.27"; #inletSensorSignedMinimum
my $PDU2_INLETUNITS      = ".1.3.6.1.4.1.13742.6.3.3.4.1.6";  #inletSensorUnits
my $PDU2_INLETDEC        = ".1.3.6.1.4.1.13742.6.3.3.4.1.7";  #inletSensorDecimalDigits
my $PDU2_OUTLETVAL       = ".1.3.6.1.4.1.13742.6.5.4.3.1.4";  #measurementsOutletSensorValue
my $PDU2_OUTLETSIGNEDVAL = ".1.3.6.1.4.1.13742.6.5.4.3.1.6";  #measurementsOutletSensorSignedValue
my $PDU2_OUTLETSIGNEDMIN = ".1.3.6.1.4.1.13742.6.3.5.4.1.27"; #outletSensorSignedMinimum
my $PDU2_OUTLETUNITS     = ".1.3.6.1.4.1.13742.6.3.5.4.1.6";  #outletSensorUnits
my $PDU2_OUTLETDEC       = ".1.3.6.1.4.1.13742.6.3.5.4.1.7";  #outletSensorDecimalDigits

#The five columns pdu2_sensor_fmt reads, grouped per entity type.
my $PDU2_INLET_SENSOR = {
    val    => $PDU2_INLETVAL,
    signed => $PDU2_INLETSIGNEDVAL,
    min    => $PDU2_INLETSIGNEDMIN,
    units  => $PDU2_INLETUNITS,
    dec    => $PDU2_INLETDEC,
};
my $PDU2_OUTLET_SENSOR = {
    val    => $PDU2_OUTLETVAL,
    signed => $PDU2_OUTLETSIGNEDVAL,
    min    => $PDU2_OUTLETSIGNEDMIN,
    units  => $PDU2_OUTLETUNITS,
    dec    => $PDU2_OUTLETDEC,
};

#PDU2-MIB has no pollable PDU-level firmware version (boardFirmwareVersion is
#per-controller under unit 3, imageVersion is trap payload only), so the
#firmware string is taken from sysDescr in SNMPv2-MIB.
my $SYSDESCR         = ".1.3.6.1.2.1.1.1.0";

#SensorTypeEnumeration subset reported for inlets and outlets, and the
#SensorUnitsEnumeration values those sensors use. Readings are scaled by the
#matching ...SensorDecimalDigits and labelled from ...SensorUnits, so this
#works unchanged on any PDU2 model regardless of which sensors it populates.
my %PDU2_SENSOR_NAME = (
    1  => "RMS Current",       2  => "Peak Current",
    3  => "Unbalanced Current", 4 => "RMS Voltage",
    5  => "Active Power",      6  => "Apparent Power",
    7  => "Power Factor",      8  => "Active Energy",
    9  => "Apparent Energy",   10 => "Temperature",
    23 => "Frequency",         29 => "Reactive Power",
);
my %PDU2_SENSOR_UNIT = (
    -1 => "",   0 => "",    1 => "V",  2 => "A",   3 => "W",
     4 => "VA", 5 => "Wh",  6 => "VAh", 7 => "C",  8 => "Hz",
     9 => "%", 20 => "deg", 23 => "var",
);
#Ordered for readability rather than by enum value.
my @PDU2_INLET_SENSORS  = (4, 1, 5, 6, 7, 23, 3, 29, 8, 9, 10);
my @PDU2_OUTLET_SENSORS = (1, 5, 8);


#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
       rpower => ["nodehm:mgt","pduoutlet:pdu=\.\*"],
       rinv   => ["nodehm:mgt"],
       rvitals => ["nodehm:mgt"],
       nodeset => ["nodehm:mgt"],
       rspconfig => ["nodehm:mgt"],
       pdudiscover => "pdu",
    };
}

sub pdu_usage
{
    my ($callback, $command) = @_;
    my $usagemsg =
    "Usage:
     The following commands support both type of PDUs :
        pdudiscover [<noderange>|--range ipranges] [-r|-x|-z] [-w] [-V|--verbose] [--setup]
        rpower pdunodes [off|on|stat|reset]
        rinv      pdunodes
        rvitals   pdunodes

     The following commands support IR PDU with pdutype=irpdu :
        rpower computenodes [pduoff|pduon|pdustat|pdustatus|pdureset]
        rspconfig irpdunode [hostname=<NAME>|ip=<IP>|gateway=<GATEWAY>|mask=<MASK>]

     The following commands support Generic SNMP PDU with pdutype=genpdu :
        rpower    pdunodes [off|on|stat|reset]
        rpower    computenodes [pduoff|pduon|pdustat|pdureset]
        rinv      pdunodes
        rvitals   pdunodes
        (rspconfig is not supported for pdutype=genpdu)

     The following commands support CR PDU with pdutype=crpdu :
        rpower    pdunodes relay=[1|2|3] [on|off]
        rspconfig pdunodes sshcfg
        rspconfig pdunodes snmpcfg
        rspconfig pdunode [hostname=<NAME>|ip=<IP>|mask=<MASK>]
        \n";

    if ($callback)
    {
        my $rsp = {};
        $rsp->{data}->[0] = $usagemsg;
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    else
    {
        xCAT::MsgUtils->message("I", $usagemsg);
    }
    return;

}

#--------------------------------------------------------------------------------
=head3   preprocess_request

Parse the arguments and display the usage or the version string.

=cut
#--------------------------------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my @requests;

    my $command = $req->{command}->[0];
    my $noderange = $req->{node};           #Should be arrayref
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }

    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
         &pdu_usage($callback, $command);
         return 1;
    }

    if ((!$noderange) && ($command ne "pdudiscover") ){
        &pdu_usage($callback, $command);
        return;
    }

    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    return \@result;

}


#-------------------------------------------------------

=head3  process_request

  Process the command.

=cut

#-------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $command  = $request->{command}->[0];
    my $noderange = $request->{node};           #Should be arrayref
    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});

    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    # get all entries from pdu table
    my @attrs=();
    my $schema = xCAT::Table->getTableSchema('pdu');
    my $desc   = $schema->{descriptions};
    foreach my $c (@{ $schema->{cols} }) {
        push @attrs, $c;
    }

    $pdutab = xCAT::Table->new('pdu');
    if ($pdutab) {
        $pduhash = $pdutab->getAllNodeAttribs(\@attrs, 1);
    }

    if( $command eq "rinv") {
        #for higher performance, handle node in batch
        return showMFR($noderange, $callback);
    }elsif ($command eq "rvitals") {
        return showMonitorData($noderange, $callback);
    }elsif ($command eq "rpower") {
        my $subcmd = $exargs[0];
        my $subcmd2 = $exargs[1];
        if (($subcmd eq 'pduoff') || ($subcmd eq 'pduon') || ($subcmd eq 'pdustat')|| ($subcmd eq 'pdureset') ){
            #if one day, pdu node have pdu attribute, handle in this section too
            return powerpduoutlet($noderange, $subcmd, $callback);
        } else {
            #-------------------------------------------
            #there are 2 cases will enter this block
            #one is if node's mgt is pdu
            #another is if node has pdu attribute but mgt isn't pdu
            #if the node has pdu attribute but mgt isn't pdu,
            #should do nothing for this node, let other plugin to hanle this node
            #-------------------------------------------
            my @allpdunodes=();
            my $nodehm = xCAT::Table->new('nodehm');
            my $nodehmhash = $nodehm->getNodesAttribs($noderange, ['mgt']);
            foreach my $node (@$noderange) {
                if($nodehmhash->{$node}->[0]->{mgt} eq 'pdu'){
                    push @allpdunodes, $node;
                }
            }
            if(@allpdunodes) {
                if ( ($subcmd =~ /relay/) || ($subcmd2 =~ /relay/) ) {
                    process_powerrelay($request,$subreq,\@allpdunodes,$callback);
                } elsif(($subcmd eq 'on') || ($subcmd eq 'off') || ($subcmd eq 'stat') || ($subcmd eq 'state') || ($subcmd eq 'reset') ){
                    return powerpdu(\@allpdunodes, $subcmd, $callback);
                } else {
                    my $pdunode = join (",", @allpdunodes);
                    $callback->({ errorcode => [1],error => "The option $subcmd is not support for pdu node(s) $pdunode."});
                    &pdu_usage($callback, $command);
                }
            }
        }
    }elsif($command eq "rspconfig") {
        my $subcmd = $exargs[0];
        if ($subcmd eq 'sshcfg') {
            process_sshcfg($noderange, $subcmd, $callback);
        }elsif ($subcmd eq 'snmpcfg') {
            process_snmpcfg($noderange, $subcmd, $callback);
        }elsif ($subcmd =~ /ip|gateway|netmask|hostname/) {
            process_netcfg($request, $subreq, $subcmd, $callback);
        } else {
            $callback->({ errorcode => [1],error => "The input $command $subcmd is not support for pdu"});
            &pdu_usage($callback, $command);
        }
    }elsif($command eq "pdudiscover") {
        process_pdudiscover($request, $subreq, $callback);
    }elsif($command eq "nodeset") {
        $callback->({ errorcode => [1],error => "The input $command is not support for pdu"});
        &pdu_usage($callback, $command);
    }else{
        #reserve for other new command in future
    }

    return;
}

#-------------------------------------------------------

=head3  fill_outletcount

  Get outlet count for IR PDU.

=cut

#-------------------------------------------------------
sub fill_outletCount {
    my $session = shift;
    my $pdu = shift;
    my $callback = shift;

    #genpdu: outletCount is the authoritative count; the outletSwitchControlTable
    #DESCRIPTION states its entry count is given by outletCount. If the 'outlet'
    #attribute is set on the pdu node, callers use it first and this never runs.
    if ($session->{genpdu}) {
        my $count = $session->get("$PDU2_OUTLETCOUNT.$PDU2_PDUID");
        if ($count) {
            my $pdutab = xCAT::Table->new('pdu');
            $pdutab->setNodeAttribs($pdu, { outlet => $count });
        } else {
            xCAT::SvrUtils::sendmsg("Could not read outletCount, set the 'outlet' attribute on $pdu", $callback, $pdu);
        }
        return $count;
    }

    my $outletoid = ".1.3.6.1.4.1.2.6.223.8.2.1.0";
    my $pdutab = xCAT::Table->new('pdu');

    my $count = $session->get("$outletoid");
    if ($count) {
        $pdutab->setNodeAttribs($pdu, {outlet => $count});
    } else {
        xCAT::SvrUtils::sendmsg("Invalid Outlet number ", $callback,$pdu);
    }

    return $count;


}

#-------------------------------------------------------

=head3  powerpdu

    Process power command (stat/off/on) for pdu/pdus

=cut

#-------------------------------------------------------
sub powerpdu {
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;

    if (($subcmd eq "stat") || ($subcmd eq "state")){
        return powerstat($noderange, $callback);
    }

    foreach my $node (@$noderange) {
        if ($pduhash->{$node}->[0]->{pdutype} eq 'crpdu') {
            process_relay($node,$subcmd,$callback,1,3);
            next;
        }

        my $session = connectTopdu($node,$callback);
        if (!$session) {
            $callback->({ errorcode => [1],error => "Couldn't connect to $node"});
            next;
        }
        if (defined $session->{genpdu_switchable} and !$session->{genpdu_switchable}) {
            xCAT::SvrUtils::sendmsg("this PDU does not support outlet switching", $callback, $node);
            next;
        }
        my $count = $pduhash->{$node}->[0]->{outlet};
        unless ($count) {
            $count = fill_outletCount($session, $node, $callback);
        }

        my $value;
        my $statstr;
        if ($subcmd eq "off") {
            $value = 0;
            $statstr = "off";
        } elsif ( $subcmd eq "on") {
            $value = 1;
            $statstr = "on";
        } else  {
            $value = 2;
            $statstr = "reset";
        }

        for (my $outlet =1; $outlet <= $count; $outlet++)
        {
            outletpower($session, $outlet, $value);
            if ($session->{ErrorStr}) {
                $callback->({ errorcode => [1],error => "Failed to get outlet status for $node"});
            } else {
                my $output = " outlet $outlet is $statstr";
                xCAT::SvrUtils::sendmsg($output, $callback, $node, %allerrornodes);
            }
        }
    }
}

#-------------------------------------------------------

=head3  powerpduoutlet

    Process power command (pdustat/pduoff/pduon) for compute nodes,
    the pdu attribute needs to be set

=cut

#-------------------------------------------------------
sub powerpduoutlet {
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;
    my $output;
    my $value;
    my $statstr;

    my $tmpnodestr = join(",", @$noderange);

    my $nodetab = xCAT::Table->new('pduoutlet');
    my $nodepdu = $nodetab->getNodesAttribs($noderange,['pdu']);

    foreach my $node (@$noderange) {
        # the pdu attribute needs to be set
        if(! $nodepdu->{$node}->[0]->{pdu}){
            $callback->({ error => "$node: without pdu attribute"});
            next;
        }

        my @pdus = split /,/, $nodepdu->{$node}->[0]->{pdu};
        foreach my $pdu_outlet (@pdus) {
            my ($pdu, $outlet) = split /:/, $pdu_outlet;
            if ($pduhash->{$pdu}->[0]->{pdutype} eq 'crpdu') {
                $callback->({ error => "$node: This command doesn't supports CONSTELLATION PDU with pdutype=crpdu for $pdu"});
                next;
            }
            my $session = connectTopdu($pdu,$callback);
            if (!$session) {
                $callback->({ errorcode => [1],error => "$node: Couldn't connect to $pdu"});
                next;
            }
            if (defined $session->{genpdu_switchable} and !$session->{genpdu_switchable}) {
                $callback->({ errorcode => [1],error => "$node: $pdu does not support outlet switching"});
                next;
            }
            my $count = $pduhash->{$pdu}->[0]->{outlet};
            unless ($count) {
                $count = fill_outletCount($session, $pdu, $callback);
            }
            if ($outlet > $count ) {
                $callback->({ error => "$node: $pdu outlet number $outlet is invalid"});
                next;
            }
            my $cmd;
            if ($subcmd eq "pdustat") {
                $statstr=outletstat($session, $outlet);
            } elsif ($subcmd eq "pduoff") {
                $value = 0;
                $statstr = "off";
                outletpower($session, $outlet, $value);
            } elsif ($subcmd eq "pduon") {
                $value = 1;
                $statstr = "on";
                outletpower($session, $outlet, $value);
            } elsif ($subcmd eq "pdureset") {
                $value = 2;
                $statstr = "reset";
                outletpower($session, $outlet, $value);
            } else {
                $callback->({ error => "$subcmd is not support"});
            }

            if ($session->{ErrorStr}) {
                $callback->({ errorcode => [1],error => "$node: $pdu outlet $outlet has error = $session->{ErrorStr}"});
            } else {
                $output = "$pdu operational state for outlet $outlet is $statstr";
                xCAT::SvrUtils::sendmsg($output, $callback, $node, %allerrornodes);
            }
        }
    }
}

#-------------------------------------------------------

=head3  outletpower

    Process power command for one pdu outlet,

=cut

#-------------------------------------------------------
sub outletpower {
    my $session = shift;
    my $outlet = shift;
    my $value = shift;

    #genpdu: PDU2-MIB switchingOperation is off(0) on(1) cycle(2), and the
    #callers (powerpdu / powerpduoutlet) already pass 0=off, 1=on, 2=reset, so
    #the value maps directly onto the MIB enum with no translation.
    if ($session->{genpdu}) {
        my $varbind = new SNMP::Varbind([ $PDU2_SWITCHOP, "$PDU2_PDUID.$outlet", $value, "INTEGER" ]);
        return $session->set($varbind);
    }

    my $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.11";
    my $type = "INTEGER";
    if ($session->{newmib}) {
        $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.13";
    }


    my $varbind = new SNMP::Varbind([ $oid, $outlet, $value, $type ]);
    return $session->set($varbind);
}

#-------------------------------------------------------

=head3  powerstat

    Process command to query status of pdu

=cut

#-------------------------------------------------------
sub powerstat {
    my $noderange = shift;
    my $callback = shift;
    my $output;

    foreach my $pdu (@$noderange) {
        if ($pduhash->{$pdu}->[0]->{pdutype} eq 'crpdu') {
            my $snmpversion = $pduhash->{$pdu}->[0]->{snmpversion};
            my $snmpcmd;
            if ($snmpversion =~ /3/) {
                my $snmpuser = $pduhash->{$pdu}->[0]->{snmpuser};
                my $seclevel = $pduhash->{$pdu}->[0]->{seclevel};
                if ((defined $snmpuser) && (defined $seclevel)) {
                    my $authtype = $pduhash->{$pdu}->[0]->{authtype};
                    if (!defined $authtype) {
                        $authtype="MD5";
                    }
                    my $authkey = $pduhash->{$pdu}->[0]->{authkey};
                    my $privtype = $pduhash->{$pdu}->[0]->{privtype};
                    if (!defined $privtype) {
                        $privtype="DES";
                    }
                    my $privkey = $pduhash->{$pdu}->[0]->{privkey};
                    if (!defined $privkey) {
                        if (defined $authkey) {
                            $privkey=$authkey;
                        }
                    }
                    if ($seclevel eq "authNoPriv") {
                        $snmpcmd = "snmpwalk -v3 -u $snmpuser -a $authtype -A $authkey -l $seclevel";
                    } elsif ($seclevel eq "authPriv") {
                        $snmpcmd = "snmpwalk -v3 -u $snmpuser -a $authtype -A $authkey -l $seclevel -x $privtype -X $privkey";
                    } else {   #default to notAuthNoPriv
                        $snmpcmd = "snmpwalk -v3 -u $snmpuser -l $seclevel";
                    }
                } else {
                    xCAT::SvrUtils::sendmsg("ERROR: No snmpuser or Security level defined for snmpV3 configuration", $callback,$pdu);
                    xCAT::SvrUtils::sendmsg("    use chdef command to add pdu snmpV3 attributes to pdu table", $callback,$pdu);
                    xCAT::SvrUtils::sendmsg("    ex:  chdef coral-pdu snmpversion=3, snmpuser=admin, authtype=MD5 authkey=password1 privtype=DES privkey=password2 seclevel=authPriv", $callback,$pdu);
                    xCAT::SvrUtils::sendmsg("    then run 'rspconfig $pdu snmpcfg' command ", $callback,$pdu);
                    next;
                }
            } else {
                # use default value
                $snmpcmd = "snmpwalk -v3 -u admin -a MD5 -A password1 -l authPriv -x DES -X password2";
            }
            for (my $relay = 1; $relay <= 3; $relay++) {
                relaystat($pdu, $relay, $snmpcmd, $callback);
            }
            next;
        }
        my $session = connectTopdu($pdu,$callback);
        if (!$session) {
            $callback->({ errorcode => [1],error => "Couldn't connect to $pdu"});
            next;
        }
        if (defined $session->{genpdu_switchable} and !$session->{genpdu_switchable}) {
            xCAT::SvrUtils::sendmsg("this PDU does not support outlet switching", $callback, $pdu);
            next;
        }
        my $count = $pduhash->{$pdu}->[0]->{outlet};
        unless ($count) {
            $count = fill_outletCount($session, $pdu, $callback);
        }
        for (my $outlet =1; $outlet <= $count; $outlet++)
        {
            my $statstr = outletstat($session, $outlet);
            my $msg = " operational state for the outlet $outlet is $statstr";
            xCAT::SvrUtils::sendmsg($msg, $callback, $pdu, %allerrornodes);
        }
    }
}

#-------------------------------------------------------

=head3  outletstat

    Process command to query status of one pdu outlet
    ibmPduOutletState defined from mib file
         off(0)
         on(1)
         cycling(2)
         delaySwitch10(3)
         delaySwitch30(4)
         delaySwitch60(5)

=cut

#-------------------------------------------------------
sub outletstat {
    my $session = shift;
    my $outlet = shift;

    #genpdu: PDU2-MIB outletSwitchingState uses SensorStateEnumeration, of which
    #on(7) and off(8) are the switching states. The value may come back as the
    #integer or as the MIB label depending on which MIBs the Net-SNMP perl
    #module has loaded, so both forms are accepted.
    if ($session->{genpdu}) {
        my $val = $session->get("$PDU2_OUTLETSTATE.$PDU2_PDUID.$outlet");
        return "unknown state" unless (defined $val);
        if    ($val eq "7" or $val eq "on")  { return "on"; }
        elsif ($val eq "8" or $val eq "off") { return "off"; }
        else                                 { return "$val(unknown state)"; }
    }

    my $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.11";
    my $output;
    my $statstr;
    if ($session->{newmib}) {
        $oid = ".1.3.6.1.4.1.2.6.223.8.2.2.1.13";
    }

    $output = $session->get("$oid.$outlet");
    if ($output eq 0) {
        $statstr = "off";
    } elsif ($output eq 1) {
        $statstr = "on";
    } elsif ($output eq 2) {
        $statstr = "cycling";
    } elsif ($output eq 3) {
        $statstr = "delaySwitch10";
    } elsif ($output eq 4) {
        $statstr = "delaySwitch30";
    } elsif ($output eq 5) {
        $statstr = "delaySwitch60";
    } else {
        $statstr = "$output(unknown state)" ;
    }
    return $statstr;
}

#-------------------------------------------------------

=head3  connectTopdu

   connect pdu via snmp session

=cut

#-------------------------------------------------------
sub connectTopdu {
    my $pdu = shift;
    my $callback = shift;

    #genpdu uses its own v1/v2c/v3 session builder and the PDU2-MIB OIDs; skip
    #the IBM-specific version probe below, which a non-IBM agent will not answer.
    if (($pduhash->{$pdu}->[0]->{pdutype} || '') eq 'genpdu') {
        return connectTopdu_gen($pdu, $callback);
    }

    #get community string from pdu table if defined,
    #otherwise, use default
    my $community;
    if ($pduhash->{$pdu}->[0]->{community}) {
        $community = $pduhash->{$pdu}->[0]->{community};
    } else {
        $community = "public";
    }

    my $snmpver = "1";
    my $session;
    my $msg = "connectTopdu";
    my $versionoid = ".1.3.6.1.4.1.2.6.223.7.3.0";

    $session = new SNMP::Session(
        DestHost       => $pdu,
        Version        => $snmpver,
        Community      => $community,
        UseSprintValue => 1,
    );
    unless ($session) {
        return;
    }

    my $varbind = new SNMP::Varbind([ $versionoid, '' ]);
    my $pduversion = $session->get($varbind);
    if ($session->{ErrorStr}) {
        return;
    }

    $session->{newmib} = 0;
    if ($pduversion =~ /sLEN/) {
        $session->{newmib} = 1;
    }

    return $session;

}

#-------------------------------------------------------

=head3  connectTopdu_gen

   Build an SNMP v1/v2c/v3 session for a generic SNMP PDU (pdutype=genpdu),
   driven by the PDU2-MIB.

   SNMP parameters come from the 'pdu' table, following the same model xCAT
   already uses for ethernet switches in xCAT::MacMap::getsnmpsession:
     - one secret is reused (community for v1/v2c; the auth passphrase for v3),
       and privkey falls back to authkey when only one is provided.
     - SecLevel is derived: authNoPriv unless a privacy protocol is set.

=cut

#-------------------------------------------------------
sub connectTopdu_gen {
    my $pdu = shift;
    my $callback = shift;

    my $session = new SNMP::Session(pdu2_session_args($pdu, $pduhash->{$pdu}->[0]));
    unless ($session) {
        return;
    }
    $session->{genpdu} = 1;

    unless (pdu2_session_probe($session, $pdu, $callback)) {
        return;
    }

    return $session;
}

#-------------------------------------------------------

=head3  pdu2_session_args

   Map a 'pdu' table row onto the SNMP::Session arguments for that PDU.

=cut

#-------------------------------------------------------
sub pdu2_session_args {
    my ($pdu, $ent) = @_;

    my $snmpver = $ent->{snmpversion};
    if    (!defined $snmpver) { $snmpver = "1"; }
    elsif ($snmpver =~ /3/)   { $snmpver = "3"; }
    elsif ($snmpver =~ /2/)   { $snmpver = "2"; }
    else                      { $snmpver = "1"; }

    if ($snmpver ne "3") {
        return (
            DestHost       => $pdu,
            Version        => $snmpver,
            Community      => $ent->{community} || "public",
            UseSprintValue => 1,
        );
    }

    my $authpass = $ent->{authkey};
    my $privpass = (defined $ent->{privkey}) ? $ent->{privkey} : $authpass;
    my $seclevel = $ent->{seclevel};
    unless ($seclevel) {
        $seclevel = ($ent->{privtype}) ? "authPriv" : "authNoPriv";
    }
    my %args = (
        DestHost       => $pdu,
        Version        => 3,
        SecName        => $ent->{snmpuser},
        SecLevel       => $seclevel,
        AuthProto      => uc($ent->{authtype} || "SHA"),
        AuthPass       => $authpass,
        UseSprintValue => 1,
    );
    if ($seclevel eq "authPriv") {
        $args{PrivProto} = uc($ent->{privtype} || "DES");
        $args{PrivPass}  = $privpass;
    }

    return %args;
}

#-------------------------------------------------------

=head3  pdu2_session_probe

   First exchange with a generic SNMP PDU. Returns false when the PDU does not
   answer at all, so callers report a connection failure, and records whether
   its outlets can be switched.

=cut

#-------------------------------------------------------
sub pdu2_session_probe {
    my ($session, $pdu, $callback) = @_;

    #SNMP::Session->new does not contact the device, so this GET is where an
    #unreachable PDU or a wrong credential first shows up. pduCount is a
    #mandatory PDU2-MIB scalar, which makes it a reliable liveness check: the
    #switching probe below cannot serve that purpose, because a PDU that never
    #answers looks exactly like a PDU that has no switched outlets.
    my $pducount = $session->get("$PDU2_PDUCOUNT");
    unless (defined $pducount and $pducount =~ /^\d+$/) {
        #Every PDU2 device tested answers pduCount, but genpdu is meant for any
        #implementation of the MIB, so fall back to sysDescr before calling the
        #PDU unreachable: it is mandatory in SNMPv2-MIB, and rinv reads it
        #already. The unit count is then unknown rather than assumed to differ,
        #so no linking warning is issued.
        my $descr = $session->get("$SYSDESCR");
        unless (defined $descr and $descr ne '' and $descr !~ /No Such/i) {
            return 0;
        }
        $pducount = 1;
    }

    #pduCount is the number of link units including the primary, or for BCM2 and
    #PMC the number of power meters plus the main controller. genpdu only drives
    #pduId 1, which is the primary on a linked unit but a power meter on
    #BCM2/PMC. Warn rather than refuse: driving the primary alone stays correct,
    #and pduoutlet.pdu has no field for a link id in any case.
    if ($pducount != 1) {
        xCAT::SvrUtils::sendmsg("pduCount is $pducount, only the primary unit (pduId $PDU2_PDUID) is managed", $callback, $pdu);
    }

    #Metered-only PDU2 models (for example PX2-1901U) answer the nameplate and
    #measurement tables normally but have no outletSwitchControlTable instances.
    #Probe once here, the same way the irpdu path above probes a version OID,
    #so callers can refuse switching with one clear message instead of leaking
    #the agent's "No Such Instance" text from every outlet read.
    my $probe = $session->get("$PDU2_OUTLETSTATE.$PDU2_PDUID.1");
    $session->{genpdu_switchable} =
        ((defined $probe) and ($probe =~ /^\d+$/ or $probe =~ /^(on|off)$/i)) ? 1 : 0;

    return 1;
}

#-------------------------------------------------------

=head3  pdu2_sensor_fmt

   Read one PDU2-MIB sensor and return it formatted with its unit, or undef if
   the sensor is not present on this device.

   $oids is one of the PDU2_*_SENSOR column sets and $idx is the full instance
   suffix (pduId.entityId.sensorType). The value column, scaling factor and unit
   all come from the matching sensor-configuration table, so no unit, precision
   or column choice is hardcoded. They are formally per-entity but are uniform
   across entities on PDU2 devices, so they are cached per sensorType to keep
   this to one GET per entity per sensor rather than four. The cache is filled
   only once a sensor is known to exist, so an entity that lacks a sensor cannot
   seed it with fallbacks for the entities behind it.

=cut

#-------------------------------------------------------
sub pdu2_sensor_fmt {
    my ($session, $oids, $idx, $cache) = @_;

    my $st = (split /\./, $idx)[-1];
    my $meta = $cache->{$st};

    #SensorSignedMinimum below zero means the sensor can read negative and the
    #signed value column has to be used. Treat an unreadable minimum as zero:
    #firmware that does not implement the column keeps the unsigned reading it
    #has always returned.
    my $min = (defined $meta) ? $meta->[2] : $session->get("$oids->{min}.$idx");
    $min = 0 unless (defined $min and $min =~ /^-?\d+$/);

    my $valoid = ($min < 0) ? $oids->{signed} : $oids->{val};
    my $raw = $session->get("$valoid.$idx");
    return undef unless (defined $raw and $raw =~ /^-?\d+$/);

    unless (defined $meta) {
        my $u = $session->get("$oids->{units}.$idx");
        my $d = $session->get("$oids->{dec}.$idx");
        $u = -1 unless (defined $u and $u =~ /^-?\d+$/);
        $d = 0  unless (defined $d and $d =~ /^\d+$/);
        $meta = $cache->{$st} = [ $u, $d, $min ];
    }
    my ($units, $digits) = @$meta;

    my $val = sprintf("%.*f", $digits, $raw / (10 ** $digits));
    my $sfx = (defined $PDU2_SENSOR_UNIT{$units}) ? $PDU2_SENSOR_UNIT{$units} : "";
    return ($sfx ne "") ? "$val $sfx" : $val;
}

#-------------------------------------------------------

=head3  rinv_for_genpdu

   Inventory for a generic SNMP PDU, from the PDU2-MIB nameplate and
   unitConfiguration entries plus sysDescr for the firmware string.

=cut

#-------------------------------------------------------
sub rinv_for_genpdu {
    my $pdu = shift;
    my $session = shift;
    my $callback = shift;

    #The rated* nameplate objects are DisplayStrings with the unit already
    #included (for example "24A", "15.0-17.3kVA"), so nothing is appended.
    my @fields = (
        [ $PDU2_NAMEPLATE, 2, "PDU Manufacturer" ],
        [ $PDU2_NAMEPLATE, 3, "PDU Model" ],
        [ $PDU2_NAMEPLATE, 4, "PDU Serial Number" ],
        [ $PDU2_NAMEPLATE, 5, "PDU Rated Voltage" ],
        [ $PDU2_NAMEPLATE, 6, "PDU Rated Current" ],
        [ $PDU2_NAMEPLATE, 7, "PDU Rated Frequency" ],
        [ $PDU2_NAMEPLATE, 8, "PDU Rated VA" ],
        [ $PDU2_UNITCONF,  2, "PDU Inlet Count" ],
        [ $PDU2_UNITCONF,  3, "PDU Overcurrent Protector Count" ],
        [ $PDU2_UNITCONF,  4, "PDU Outlet Count" ],
    );

    foreach my $f (@fields) {
        my $output = $session->get("$f->[0].$f->[1].$PDU2_PDUID");
        next unless (defined $output and $output ne '');
        #UseSprintValue returns DisplayStrings quoted; strip for readability.
        $output =~ s/^"(.*)"$/$1/;
        next if ($output eq '');
        xCAT::SvrUtils::sendmsg("$f->[2]: $output", $callback, $pdu);
    }

    my $output = $session->get("$SYSDESCR");
    if (defined $output and $output ne '') {
        $output =~ s/^"(.*)"$/$1/;
        xCAT::SvrUtils::sendmsg("PDU Description: $output", $callback, $pdu);
    }
}

#-------------------------------------------------------

=head3  rvitals_for_genpdu

   Sensor readings for a generic SNMP PDU: every supported inlet sensor the
   device reports, then current, active power and active energy per outlet.

=cut

#-------------------------------------------------------
sub rvitals_for_genpdu {
    my $pdu = shift;
    my $count = shift;
    my $session = shift;
    my $callback = shift;

    my $inlets = $session->get("$PDU2_UNITCONF.2.$PDU2_PDUID");
    $inlets = 1 unless (defined $inlets and $inlets =~ /^\d+$/ and $inlets > 0);

    my %inlet_cache;
    for (my $inlet = 1; $inlet <= $inlets; $inlet++) {
        foreach my $st (@PDU2_INLET_SENSORS) {
            my $fmt = pdu2_sensor_fmt($session, $PDU2_INLET_SENSOR,
                        "$PDU2_PDUID.$inlet.$st", \%inlet_cache);
            next unless (defined $fmt);
            my $name = $PDU2_SENSOR_NAME{$st} || "sensor $st";
            xCAT::SvrUtils::sendmsg("inlet $inlet $name: $fmt", $callback, $pdu);
        }
    }

    my %outlet_cache;

    #Metered-only models (PX2-1901U, PX3-1901U) populate the inlet tables but
    #have no per-outlet sensors. Probe one before looping: a 48-outlet unit
    #otherwise costs 192 GETs that all return No Such Instance and print
    #nothing, which matters when rvitals is run against a group. The unsigned
    #column is the right one to probe because the first outlet sensor is
    #rmsCurrent, which cannot read negative.
    my $probe = $session->get("$PDU2_OUTLETVAL.$PDU2_PDUID.1.$PDU2_OUTLET_SENSORS[0]");
    return unless (defined $probe and $probe =~ /^-?\d+$/);

    for (my $outlet = 1; $outlet <= $count; $outlet++) {
        foreach my $st (@PDU2_OUTLET_SENSORS) {
            my $fmt = pdu2_sensor_fmt($session, $PDU2_OUTLET_SENSOR,
                        "$PDU2_PDUID.$outlet.$st", \%outlet_cache);
            next unless (defined $fmt);
            my $name = $PDU2_SENSOR_NAME{$st} || "sensor $st";
            xCAT::SvrUtils::sendmsg("outlet $outlet $name: $fmt", $callback, $pdu);
        }
    }
}

#-------------------------------------------------------

=head3  process_netcfg

    Config hostname of PDU
    Config ip/netmask of PDU via PduManager command
      PduManager is a tool for CoralPdu to manager the PDU.
      * /dev/shm/bin/PduManager -h
          '-i' set PDU system IP
          '-n' set system ip netmask. e.g.:PduManager -i xxx.xxx.xxx.xxx -n xxx.xxx.xxx.xxx

    example:  rspconfig coralpdu hostname=coralpdu
              rspconfig coralpdu ip=1.1.1.1 netmask=255.0.0.0

=cut

#-------------------------------------------------------
sub process_netcfg {
    my $request = shift;
    my $subreq    = shift;
    my $subcmd    = shift;
    my $callback = shift;
    my $hostname;
    my $ip;
    my $netmask;
    my $args;
    my $exp;
    my $errstr;

    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    my $nodes = $request->{node};
    my $node_number = @$nodes;
    if ($node_number gt "1") {
        xCAT::SvrUtils::sendmsg("Can not configure more than 1 nodes", $callback);
        return;
    }

    my $pdu = @$nodes[0];
    my $rsp = {};

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($nodes,['ip','otherinterfaces']);
    my $static_ip = $nodehash->{$pdu}->[0]->{ip};
    my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};

    if (($pduhash->{$pdu}->[0]->{pdutype} || '') eq 'genpdu') {
        xCAT::SvrUtils::sendmsg("rspconfig $subcmd is not supported for pdutype=genpdu", $callback, $pdu);
        return;
    }

    unless ($pduhash->{$pdu}->[0]->{pdutype} eq "crpdu") {
        netcfg_for_irpdu($pdu, $static_ip, $discover_ip, $request, $subreq, $callback);
        return;
    }

    # connect to PDU
    my $username = $pduhash->{$pdu}->[0]->{username};
    my $password = $pduhash->{$pdu}->[0]->{password};
    ($exp, $errstr) = session_connect($static_ip, $discover_ip,$username,$password);
    if (defined $errstr) {
        xCAT::SvrUtils::sendmsg("Failed to connect", $callback,$pdu);
        return;
    }

    foreach my $cmd (@exargs) {
        my ($key, $value) = split(/=/, $cmd);
        if ($key =~ /hostname/) {
            $hostname = $value;
            my ($ret, $err) = session_exec($exp, "echo $hostname > /etc/hostname;/etc/init.d/hostname.sh");
            if (defined $err) {
               xCAT::SvrUtils::sendmsg("Failed to set hostname", $callback);
            }
        }elsif ($key =~ /ip/) {
            $ip = $value;
        } elsif ($key =~ /netmask/) {
            $netmask = $value;
        } else {
            xCAT::SvrUtils::sendmsg("rspconfig $cmd is not support yet, ignored", $callback);
        }
    }

    $args = "/dev/shm/bin/PduManager ";
    my $opt;
    if ($ip) {
        $opt = "-i $ip ";
    }
    if ($netmask) {
        $opt = $opt . "-n $netmask";
    }
    if ($opt) {
        my $dshcmd = $args . $opt ;
        my ($ret, $err) = session_exec($exp, $dshcmd);
        if (defined $err) {
            #session will be hung if ip address changed
            my $p = Net::Ping->new();
            if  ( ($p->ping($ip)) && ($err =~ /TIMEOUT/) ) {
               xCAT::SvrUtils::sendmsg("$ip is reachable", $callback);
            } else {
                xCAT::SvrUtils::sendmsg("Failed to run $dshcmd, error=$err", $callback);
                return;
            }
        }
        xCAT::SvrUtils::sendmsg("$dshcmd ran successfully", $callback);
        xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','node','-o',$pdu,"ip=$ip","otherinterfaces="] }, $subreq, 0, 1);
        xCAT::Utils->runxcmd({ command => ['makehosts'], node => [$pdu] },  $subreq, 0, 1);
    }
    if (defined $exp) {
        $exp->hard_close();
    }
}

#-------------------------------------------------------

=head3  process_sshcfg

    Config passwordless for coralpdu

    example:  rspconfig coralpdu sshcfg

=cut

#-------------------------------------------------------
sub process_sshcfg {
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;

    my $keyfile = "/root/.ssh/id_rsa.pub";
    my $rootkey = `cat /root/.ssh/id_rsa.pub`;
    my $cmd;

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);

    foreach my $pdu (@$noderange) {
        unless ($pduhash->{$pdu}->[0]->{pdutype} eq "crpdu") {
            xCAT::SvrUtils::sendmsg("This command only supports CONSTELLATION PDU with pdutype=crpdu", $callback,$pdu);
            next;
        }

        my $msg = " process_sshcfg";
        xCAT::SvrUtils::sendmsg($msg, $callback, $pdu, %allerrornodes);

        #remove old host key from /root/.ssh/known_hosts
        $cmd = "ssh-keygen -R $pdu";
        xCAT::Utils->runcmd($cmd, 0);

        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my $username = $pduhash->{$pdu}->[0]->{username};
        my $password = $pduhash->{$pdu}->[0]->{password};

        my ($exp, $errstr) = session_connect($static_ip, $discover_ip,$username,$password);
        if (!defined $exp) {
            $msg = " Failed to connect $errstr";
            xCAT::SvrUtils::sendmsg($msg, $callback, $pdu, %allerrornodes);
            next;
        }

        my $ret;
        my $err;

        ($ret, $err) = session_exec($exp, "mkdir -p /home/root/.ssh");
        ($ret, $err) = session_exec($exp, "chmod 700 /home/root/.ssh");
        ($ret, $err) = session_exec($exp, "echo \"$rootkey\" >/home/root/.ssh/authorized_keys");
        ($ret, $err) = session_exec($exp, "chmod 644 /home/root/.ssh/authorized_keys");

        $exp->hard_close();
    }

    return;
}

#-------------------------------------------------------

=head3  session_connect

  open a expect session and connect to CR PDU.

=cut

#-------------------------------------------------------
sub session_connect {
    my $static_ip   = shift;
    my $discover_ip   = shift;
    my $userid = shift;
    my $password = shift;

    #default password for coral pdu
    if (!defined $userid) {
        $userid = "root";
    }
    if (!defined $password) {
        $password = "password8";
    }

    my $timeout = 30;

    my $ssh_ip;
    my $p = Net::Ping->new();
    if ($p->ping($static_ip)) {
        $ssh_ip = $static_ip;
    } elsif ($p->ping($discover_ip)) {
        $ssh_ip = $discover_ip;
    } else {
        return(undef, " is not reachable\n");
    }

    my $ssh      = Expect->new;
    my $command     = 'ssh';
    my @parameters  = ($userid . "@" . $ssh_ip);

     $ssh->debug(0);
     $ssh->log_stdout(0);    # suppress stdout output..

     unless ($ssh->spawn($command, @parameters))
     {
         my $err = $!;
         $ssh->soft_close();
         my $rsp;
         return(undef, "unable to run command $command $err\n");
     }

     $ssh->expect($timeout,
                   [ "-re", qr/WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED/, sub {die "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\n"; } ],
                   [ "-re", qr/\(yes\/no\)\?\s*$/, sub { $ssh->send("yes\n");  exp_continue; } ],
                   [ "-re", qr/ password:/,        sub {$ssh->send("$password\n"); exp_continue; } ],
                   [ "-re", qr/:~\$/,              sub { $ssh->send("sudo su\n"); exp_continue; } ],
                   [ "-re", qr/.*#/,               sub { $ssh->clear_accum(); } ],
                   [ timeout => sub { die "No login.\n"; } ]
                  );
     $ssh->clear_accum();
     return ($ssh);
}

#-------------------------------------------------------

=head3  session_exec

  execute command to CR PDU.

=cut

#-------------------------------------------------------
sub session_exec {
     my $exp = shift;
     my $cmd = shift;
     my $timeout    = shift;
     my $prompt =  shift;

     $timeout = 30 unless defined $timeout;
     $prompt = qr/.*#/ unless defined $prompt;


     $exp->clear_accum();
     $exp->send("$cmd\n");
     my ($mpos, $merr, $mstr, $mbmatch, $mamatch) = $exp->expect(6,  "-re", $prompt);

     if (defined $merr) {
         return(undef,$merr);
     }
     return($mbmatch);
}

#-----------------------------------------------------------------

=head3  process_pdudiscover

    Discover the pdu for a given range of DHCP ip address
    it will call switchdiscover command with -s snmp --pdu options

    example: pdudiscover --range iprange -w

=cut

#------------------------------------------------------------------
sub process_pdudiscover {
    my $request  = shift;
    my $sub_req  = shift;
    my $callback = shift;
    my $extrargs = $request->{arg};
    my @exargs   = ($request->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }

    #check case in GetOptions
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );
    Getopt::Long::Configure("no_pass_through");
    my %opt;
    if (!GetOptions( \%opt,
                    qw(h|help V|verbose x z w r range=s setup))) {
        my $usage_string = xCAT::Usage->getUsage($request->{command}->[0]);
        $callback->({ data => $usage_string });
        return;

    }

    push @exargs, "-s snmp --pdu";
    my $cmd = "switchdiscover @exargs";
    my $result = xCAT::Utils->runcmd($cmd, 0);

    my $rsp = {};
    push @{ $rsp->{data} }, "$result";
    xCAT::MsgUtils->message("I", $rsp, $callback);
}

#-------------------------------------------------------

=head3  showMFR

    show MFR information of PDU via PduManager command
      PduManager is a tool for CoralPdu to manager the PDU.
      * /dev/shm/bin/PduManager -h
          '-m' show MFR info

    example:  rinv coralpdu

=cut

#-------------------------------------------------------

sub showMFR {
    my $noderange = shift;
    my $callback = shift;
    my $output;

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);

    foreach my $pdu (@$noderange) {
        if (($pduhash->{$pdu}->[0]->{pdutype} || '') eq 'genpdu') {
            my $session = connectTopdu($pdu, $callback);
            if (!$session) {
                $callback->({ errorcode => [1], error => "Couldn't connect to $pdu" });
                next;
            }
            rinv_for_genpdu($pdu, $session, $callback);
            next;
        }
        unless ($pduhash->{$pdu}->[0]->{pdutype} eq "crpdu") {
            rinv_for_irpdu($pdu, $callback);
            next;
        }

        # connect to PDU
        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my $username = $pduhash->{$pdu}->[0]->{username};
        my $password = $pduhash->{$pdu}->[0]->{password};

        my ($exp, $errstr) = session_connect($static_ip, $discover_ip,$username,$password);
        if (defined $errstr) {
            xCAT::SvrUtils::sendmsg("Failed to connect: $errstr", $callback);
        }

        my ($ret, $err) = session_exec($exp, "/dev/shm/bin/PduManager -m");
        if (defined $err) {
            xCAT::SvrUtils::sendmsg("Failed to list MFR information: $err", $callback);
        }
        if (defined $ret) {
            foreach my $line (split /[\r\n]+/, $ret) {
                if ($line) {
                    $line = join(' ',split(' ',$line));
                    xCAT::SvrUtils::sendmsg("$line", $callback,$pdu);
                }
            }
        }

        $exp->hard_close();
    }
}

sub rinv_for_irpdu
{
    my $pdu = shift;
    my $callback = shift;
    my $output;

    my $session = connectTopdu($pdu,$callback);
    if (!$session) {
        $callback->({ errorcode => [1],error => "Couldn't connect to $pdu"});
        next;
    }
    #ibmPduSoftwareVersion
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.3.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Software Version: $output", $callback,$pdu);
    }
    #ibmPduMachineType
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.4.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Machine Type: $output", $callback,$pdu);
    }
    #ibmPduModelNumber
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.5.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Model Number: $output", $callback,$pdu);
    }
    #ibmPduPartNumber
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.6.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Part Number: $output", $callback,$pdu);
    }
    #ibmPduName
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.7.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Name: $output", $callback,$pdu);
    }
    #ibmPduSerialNumber
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.9.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Serial Number: $output", $callback,$pdu);
    }
    #ibmPduDescription
    $output = $session->get(".1.3.6.1.4.1.2.6.223.7.10.0");
    if ($output) {
        xCAT::SvrUtils::sendmsg("PDU Description: $output", $callback,$pdu);
    }
}



#-------------------------------------------------------

=head3  showMonitorData

    Show realtime monitor data(input voltage, current, power)
        of PDU via PduManager command
    PduManager is a tool for CoralPdu to manager the PDU.
      * /dev/shm/bin/PduManager -h
          '-d' show realtime monitor data(input voltage, current, power)

    example:  rvitals coralpdu

=cut

#-------------------------------------------------------
sub showMonitorData {
    my $noderange = shift;
    my $callback = shift;
    my $output;

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);

    foreach my $pdu (@$noderange) {
        if (($pduhash->{$pdu}->[0]->{pdutype} || '') eq 'genpdu') {
            my $session = connectTopdu($pdu, $callback);
            if (!$session) {
                $callback->({ errorcode => [1], error => "Couldn't connect to $pdu" });
                next;
            }
            my $count = $pduhash->{$pdu}->[0]->{outlet};
            unless ($count) {
                $count = fill_outletCount($session, $pdu, $callback);
            }
            rvitals_for_genpdu($pdu, $count, $session, $callback);
            next;
        }
        unless ($pduhash->{$pdu}->[0]->{pdutype} eq "crpdu") {
            my $session = connectTopdu($pdu,$callback);
            if (!$session) {
                $callback->({ errorcode => [1],error => "Couldn't connect to $pdu"});
                next;
            }
            my $count = $pduhash->{$pdu}->[0]->{outlet};
            unless ($count) {
                $count = fill_outletCount($session, $pdu, $callback);
            }
            if ($count > 0) {
                rvitals_for_irpdu($pdu, $count, $session, $callback);
            }
            next;
        }

        # connect to PDU
        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my $username = $pduhash->{$pdu}->[0]->{username};
        my $password = $pduhash->{$pdu}->[0]->{password};

        my ($exp, $errstr) = session_connect($static_ip, $discover_ip,$username,$password);

        my $ret;
        my $err;

        ($ret, $err) = session_exec($exp, "/dev/shm/bin/PduManager -d");
        if (defined $err) {
            xCAT::SvrUtils::sendmsg("Failed to show monitor data: $err", $callback);
        }
        if (defined $ret) {
            foreach my $line (split /[\r\n]+/, $ret) {
                if ($line) {
                    $line = join(' ',split(' ',$line));
                    xCAT::SvrUtils::sendmsg("$line", $callback,$pdu);
                }
            }
        }

        $exp->hard_close();
    }
}


sub rvitals_for_irpdu
{
    my $pdu = shift;
    my $count = shift;
    my $session = shift;
    my $callback = shift;
    my $output;

    #ibmPduVoltageWarning:  (voltageNormal(0),voltageOutOfRange(1))
    my $voltagewarning = ".1.3.6.1.4.1.2.6.223.0.1.1.7.0";
    $output = $session->get("$voltagewarning");
    xCAT::SvrUtils::sendmsg("Voltage Warning: $output", $callback,$pdu);

    # get power info for each outlet
    # starts oid .2.6.223.8.2.2.1.7  to .2.6.223.8.2.2.1.14
    #ibmPduOutletCurrent
    my $outletcurrent = ".1.3.6.1.4.1.2.6.223.8.2.2.1.7";
    #ibmPduOutletMaxCapacity
    my $outletmaxcap = ".1.3.6.1.4.1.2.6.223.8.2.2.1.8";
    #ibmPduOutletCurrentThresholdWarning
    my $currentthrewarning = ".1.3.6.1.4.1.2.6.223.8.2.2.1.9";
    #ibmPduOutletCurrentThresholdCritical
    my $currentthrecrit = ".1.3.6.1.4.1.2.6.223.8.2.2.1.10";
    #ibmPduOutletLastPowerReading
    my $lastpowerreading = ".1.3.6.1.4.1.2.6.223.8.2.2.1.13";
    for (my $outlet = 1; $outlet <= $count; $outlet++) {
        $output = $session->get("$outletcurrent.$outlet");
        xCAT::SvrUtils::sendmsg("outlet $outlet Current: $output mA", $callback,$pdu);
        $output = $session->get("$outletmaxcap.$outlet");
        xCAT::SvrUtils::sendmsg("outlet $outlet Max Capacity of the current: $output mA", $callback,$pdu);
        $output = $session->get("$currentthrewarning.$outlet");
        xCAT::SvrUtils::sendmsg("outlet $outlet Current Threshold Warning: $output mA", $callback,$pdu);
        $output = $session->get("$currentthrecrit.$outlet");
        xCAT::SvrUtils::sendmsg("outlet $outlet Current Threshold Critical: $output mA", $callback,$pdu);
        $output = $session->get("$lastpowerreading.$outlet");
        xCAT::SvrUtils::sendmsg("outlet $outlet Last Power Reading: $output Watts", $callback,$pdu);
    }

}

#-------------------------------------------------------

=head3  relaystat

  process individual relay stat for CR PDU.
  The OID for 3 relay:
	1.3.6.1.4.1.2.6.262.15.2.13
	1.3.6.1.4.1.2.6.262.15.2.14
	1.3.6.1.4.1.2.6.262.15.2.15

=cut

#-------------------------------------------------------
sub relaystat {
    my $pdu = shift;
    my $relay = shift;
    my $snmpcmd = shift;
    my $callback = shift;

    my $relayoid = $relay + 12;

    #default pdu snmpv3, won't show up for snmpv1
    my $cmd = "$snmpcmd $pdu 1.3.6.1.4.1.2.6.262.15.2.$relayoid";

    my $result = xCAT::Utils->runcmd($cmd, 0);
    my ($msg,$stat) = split /: /, $result;
    if ($stat eq "1" ) {
        xCAT::SvrUtils::sendmsg(" relay $relay is on", $callback, $pdu, %allerrornodes);
    } elsif ( $stat eq "0" ) {
        xCAT::SvrUtils::sendmsg(" relay $relay is off", $callback, $pdu, %allerrornodes);
    } else {
        xCAT::SvrUtils::sendmsg(" relay $relay is $stat=unknown", $callback, $pdu, %allerrornodes);
    }

    return;
}

#-------------------------------------------------------

=head3  process_powerrelay

  process relay action for CR PDU.

=cut

#-------------------------------------------------------
sub process_powerrelay {
    my $request = shift;
    my $subreq    = shift;
    my $subcmd    = shift;
    my $callback = shift;

    my $relay;
    my $action;

    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    my $nodes = $request->{node};

    foreach my $cmd (@exargs) {
        if ($cmd =~ /=/ ) {
            my ($key, $value) = split(/=/, $cmd);
            $relay = $value;
        } else {
            $action = $cmd;
        }
    }
    if ( (defined $relay) && (defined $action) ) {
        my $relay_count = 1;
        foreach my $pdu (@$nodes) {
            process_relay($pdu, $action, $callback, $relay, $relay_count);
        }
    } else {
        xCAT::SvrUtils::sendmsg(" This command is not support, please define relay number and action", $callback);
    }

}

#-------------------------------------------------------

=head3  process_relay

  process relay action for CR PDU.

=cut

#-------------------------------------------------------
sub process_relay {
    my $pdu = shift;
    my $subcmd = shift;
    my $callback = shift;
    my $relay_num = shift;
    my $relay_count = shift;

    if ( !defined $relay_count ) {
        $relay_num = 1;
        $relay_count = 3;
    }

    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodeAttribs($pdu,['ip','otherinterfaces']);
    my $username = $pduhash->{$pdu}->[0]->{username};
    my $passwd = $pduhash->{$pdu}->[0]->{password};

    # connect to PDU
    my $static_ip = $nodehash->{$pdu}->[0]->{ip};
    my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
    my ($session, $errstr) = session_connect($static_ip, $discover_ip,$username,$passwd);

    my $ret;
    my $err;
    my $statestr;


    for (my $i = 0; $i < $relay_count; $i++) {
        my $relay = $relay_num;
        xCAT::SvrUtils::sendmsg(" power $subcmd for relay $relay_num", $callback,$pdu);
        if ($subcmd eq "off") {
            relay_action($session, $pdu, $relay, "OFF", $callback);
        } elsif ( $subcmd eq "on") {
            relay_action($session, $pdu, $relay, "ON", $callback);
        } elsif ( $subcmd eq "reset") {
            relay_action($session, $pdu, $relay, "OFF", $callback);
            relay_action($session, $pdu, $relay, "ON", $callback);
        } else {
            xCAT::SvrUtils::sendmsg(" subcmd $subcmd is not support", $callback,$pdu);
        }
        $relay_num++;
    }
    $session->hard_close();

}

#-------------------------------------------------------

=head3  realy_action

  process individual relay action for CR PDU.

=cut

#-------------------------------------------------------
sub relay_action {
    my $session = shift;
    my $pdu = shift;
    my $relay = shift;
    my $action = shift;
    my $callback = shift;

    my ($ret, $err) = session_exec($session, "/dev/shm/bin/PduManager -r $relay -v $action");
    if (defined $err) {
        xCAT::SvrUtils::sendmsg("Failed to process relay action: $err", $callback);
    }
    if (defined $ret) {
        xCAT::SvrUtils::sendmsg("$ret", $callback,$pdu);
    }
}

#-------------------------------------------------------

=head3  process_snmpcfg

  config snmp and snmpv3 for CR PDU.

=cut

#-------------------------------------------------------
sub process_snmpcfg {
    my $noderange = shift;
    my $subcmd = shift;
    my $callback = shift;
    my $snmp_conf="/etc/snmp/snmpd.conf";
    my $xCATSettingsSTART="xCAT settings START";
    my $xCATSettingsEND="xCAT settings END";
    my $xCATSettingsInfo="Entries between the START and END lines will be replaced each time by xCAT command";


    my $nodetab = xCAT::Table->new('hosts');
    my $nodehash = $nodetab->getNodesAttribs($noderange,['ip','otherinterfaces']);

    foreach my $pdu (@$noderange) {
        unless ($pduhash->{$pdu}->[0]->{pdutype} eq "crpdu") {
            xCAT::SvrUtils::sendmsg("This command only supports CONSTELLATION PDU with pdutype=crpdu", $callback,$pdu);
            next;
        }

        my $community = $pduhash->{$pdu}->[0]->{community};
        my $snmpversion = $pduhash->{$pdu}->[0]->{snmpversion};
        my $snmpuser = $pduhash->{$pdu}->[0]->{snmpuser};
        my $authtype = $pduhash->{$pdu}->[0]->{authtype};
        if (!defined $authtype) {
            $authtype="MD5";
        }
        my $authkey = $pduhash->{$pdu}->[0]->{authkey};
        my $privtype = $pduhash->{$pdu}->[0]->{privtype};
        if (!defined $privtype) {
            $privtype="DES";
        }
        my $privkey = $pduhash->{$pdu}->[0]->{privkey};
        if (!defined $privkey) {
            if (defined $authkey) {
                $privkey=$authkey;
            }
        }
        my $seclevel = $pduhash->{$pdu}->[0]->{seclevel};

        # connect to PDU
        my $static_ip = $nodehash->{$pdu}->[0]->{ip};
        my $discover_ip = $nodehash->{$pdu}->[0]->{otherinterfaces};
        my $username = $pduhash->{$pdu}->[0]->{username};
        my $password = $pduhash->{$pdu}->[0]->{password};

        my ($exp, $errstr) = session_connect($static_ip, $discover_ip,$username,$password);

        my $ret;
        my $err;

        ($ret, $err) = session_exec($exp, "sed -i '/$xCATSettingsSTART/,/$xCATSettingsEND/ d' $snmp_conf");
        ($ret, $err) = session_exec($exp, "echo '# $xCATSettingsSTART' >> $snmp_conf");
        ($ret, $err) = session_exec($exp, "echo '# $xCATSettingsInfo' >> $snmp_conf");
        if (defined $community) {
            ($ret, $err) = session_exec($exp, "echo 'com2sec readwrite  default        $community' >> $snmp_conf");
        }
        #set snmpv3 configuration
        if ($snmpversion =~ /3/) {
            if ((defined $snmpuser) && (defined $seclevel)) {
                my $msg1;
                if ($seclevel eq "authNoPriv") {
                    $msg1 = "createUser $snmpuser $authtype $authkey";
                } elsif ($seclevel eq "authPriv") {
                    $msg1 = "createUser $snmpuser $authtype $authkey $privtype $privkey";
                } else {   #default to notAuthNoPriv
                    $msg1 = "createUser $snmpuser";
                }
                my $msg2 = "rwuser $snmpuser $seclevel .1.3.6.1.4.1.2.6.262";
                ($ret, $err) = session_exec($exp, "sed -i '/\"$snmpuser\"/ d' /var/lib/net-snmp/snmpd.conf");
                ($ret, $err) = session_exec($exp, "echo $msg1 >> $snmp_conf");
                ($ret, $err) = session_exec($exp, "echo $msg2 >> $snmp_conf");
            } else {
                xCAT::SvrUtils::sendmsg("Need to define user name and security level for snmpv3 configuration", $callback);
            }
        }
        ($ret, $err) = session_exec($exp, "echo '# $xCATSettingsEND' >> $snmp_conf");

        #need to restart snmpd after config file changes
        ($ret, $err) = session_exec($exp, "ps | grep snmpd | grep -v grep | awk '{ print $1}' | xargs kill -9");
        ($ret, $err) = session_exec($exp, "/usr/sbin/snmpd -Lsd -Lf /dev/null -p /var/run/snmpd");
        if (defined $err) {
            xCAT::SvrUtils::sendmsg("Failed to configure snmp : $err", $callback);
        }


        $exp->hard_close();
    }
}

#-------------------------------------------------------

=head3  netcfg_for_irpdu

  change hostname and network setting for IR PDU.

=cut
#-------------------------------------------------------
sub netcfg_for_irpdu {
    my $pdu = shift;
    my $static_ip = shift;
    my $discover_ip = shift;
    my $request = shift;
    my $subreq = shift;
    my $callback = shift;
    my $hostname;
    my $ip;
    my $gateway;
    my $netmask;

    my $extrargs  = $request->{arg};
    my @exargs    = ($request->{arg});
    if (ref($extrargs)) {
        @exargs = @$extrargs;
    }

    #get user/password from pdu table if defined
    #default password for irpdu
    my $passwd = "1001";
    my $username = "ADMIN";

    if ($pduhash->{$pdu}->[0]->{username}) {
        $username = $pduhash->{$pdu}->[0]->{username};
    }
    if ($pduhash->{$pdu}->[0]->{password}) {
        $passwd = $pduhash->{$pdu}->[0]->{password};
    }

    my $timeout = 10;
    my $send_change = "N";

    my $login_ip;

    # somehow, only system command works for checking if irpdu is pingable
    # Net::Ping Module and xCAT::NetworkUtils::isPingable both are not working
    if (system("ping -c 2 $static_ip") == 0 ) {
        $login_ip = $static_ip;
    } elsif (system("ping -c 2 $discover_ip") == 0) {
        $login_ip = $discover_ip;
    } else {
        xCAT::SvrUtils::sendmsg(" is not reachable", $callback,$pdu);
        return;
    }

    foreach my $cmd (@exargs) {
        my ($key, $value) = split(/=/, $cmd);
        if ($key =~ /hostname/) {
            $hostname = $value;
            xCAT::SvrUtils::sendmsg("change pdu hostname to $hostname", $callback);
        }
        if ($key =~ /ip/) {
            $ip = $value;
            $send_change = "Y";
            xCAT::SvrUtils::sendmsg("change ip address for $pdu to $ip", $callback);
        }
        if ($key =~ /gateway/) {
            $gateway = $value;
            $send_change = "Y";
            xCAT::SvrUtils::sendmsg("change gateway for $pdu to $gateway", $callback);
        }
        if ($key =~ /netmask/) {
            $netmask = $value;
            $send_change = "Y";
            xCAT::SvrUtils::sendmsg("change netmask for $pdu to $netmask", $callback);
        }

    }

    my $login_cmd = "telnet $login_ip\r";
    my $user_prompt = " Login: ";
    my $pwd_prompt = "Password: ";
    my $pdu_prompt = "Please Enter Your Selection => ";
    my $send_zero = 0;
    my $send_one = 1;
    my $send_two = 2;

    my $mypdu = new Expect;

    $mypdu->debug(0);
    $mypdu->log_stdout(0);    # suppress stdout output..

    unless ($mypdu->spawn($login_cmd))
    {
        $mypdu->soft_close();
        xCAT::SvrUtils::sendmsg("Unable to run $login_cmd", $callback);
        return;
    }
    my @result = $mypdu->expect(
        $timeout,
        [
            $user_prompt,
            sub {
                $mypdu->clear_accum();
                $mypdu->send("$username\r");
                $mypdu->clear_accum();
                $mypdu->exp_continue();
            }
        ],
        [
            $pwd_prompt,
            sub {
                $mypdu->clear_accum();
                $mypdu->send("$passwd\r");
                $mypdu->clear_accum();
                $mypdu->exp_continue();
            }
        ],
        [
            $pdu_prompt,
            sub {
                $mypdu->clear_accum();
                $mypdu->send("$send_one\r");
                $mypdu->send("$send_one\r");
                #change hostname
                $mypdu->send("$send_one\r");
                $mypdu->send("$hostname\r");
                $mypdu->send("$send_zero\r");
                #change network setting
                $mypdu->send("$send_two\r");
                $mypdu->send("$send_one\r");
                $mypdu->send("$ip\r");
                $mypdu->send("$gateway\r");
                $mypdu->send("$netmask\r");
                $mypdu->send("$send_change\r");
                # go back Previous Menu
                $mypdu->send("$send_zero\r");
                $mypdu->send("$send_zero\r");
            }
        ],
    );

    if (defined($result[1]))
    {
        my $errmsg = $result[1];
        $mypdu->soft_close();
        xCAT::SvrUtils::sendmsg("Failed expect command: $errmsg", $callback,$pdu);
        return;
    }
    $mypdu->soft_close();

    xCAT::SvrUtils::sendmsg("hostname or network setting changed, update node definition ", $callback);
    xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','node','-o',$pdu,"otherinterfaces="] }, $subreq, 0, 1);
    if ( (defined $ip) and ($static_ip ne $ip) ) {
        xCAT::Utils->runxcmd({ command => ['chdef'], arg => ['-t','node','-o',$pdu,"ip=$ip",'status=configured'] }, $subreq, 0, 1);
        xCAT::Utils->runxcmd({ command => ['makehosts'], node => [$pdu] },  $subreq, 0, 1);
    }

    return;
}





1;
