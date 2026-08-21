use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoWarnings, TestingAndDebugging::ProhibitNoStrict)
no warnings 'once';

use File::Spec;
use FindBin;
use Test::More;

BEGIN {
    #pdu.pm pulls in modules the genpdu code paths never touch and that are not
    #installed everywhere (SNMP, Expect, XML::Simple), plus xCAT modules that
    #would open the database. Stub them out. xCAT::SvrUtils::sendmsg is the one
    #that has to behave, since it is how the plugin returns its output.
    for my $mod (qw(xCAT::Table xCAT::Utils xCAT::FifoPipe xCAT::MsgUtils
                    xCAT::State xCAT::Usage xCAT::NodeRange
                    SNMP Expect XML::Simple)) {
        (my $file = $mod) =~ s{::}{/}g;
        $INC{"$file.pm"} = __FILE__;
        no strict 'refs';
        *{"${mod}::import"} = sub { };
    }

    #pdu.pm uses Expect's exp_continue constant in its crpdu code paths, so the
    #stub has to keep exporting that name.
    {
        no strict 'refs';
        no warnings 'redefine';
        *{'Expect::import'} = sub {
            my $caller = caller;
            no strict 'refs';
            *{"${caller}::exp_continue"} = sub { return; };
            return;
        };
    }

    package xCAT::SvrUtils;
    our @messages;
    sub import { }
    sub sendmsg {
        my ($msg, $cb, $node) = @_;
        push @messages, defined($node) ? "$node|$msg" : $msg;
        return;
    }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;
}

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');
$ENV{XCATROOT} = File::Spec->catdir($repo_root, 'xCAT-server');
my $plugin = File::Spec->catfile($repo_root, 'xCAT-server', 'lib', 'xcat',
    'plugins', 'pdu.pm');
do $plugin or die $@ || "Unable to load $plugin: $!";

{
    #A stand-in for SNMP::Session: answers GETs from a canned table and records
    #which OIDs were asked for, so tests can assert on request counts too.
    package FakeSession;
    sub new {
        my ($class, $resp) = @_;
        return bless { resp => $resp || {}, gets => [] }, $class;
    }
    sub get {
        my ($self, $oid) = @_;
        push @{ $self->{gets} }, $oid;
        return $self->{resp}->{$oid};
    }
}

my $PDUCOUNT     = ".1.3.6.1.4.1.13742.6.3.1.0";
my $OUTLETSTATE  = ".1.3.6.1.4.1.13742.6.4.1.2.1.3";
my $NAMEPLATE    = ".1.3.6.1.4.1.13742.6.3.2.1.1";
my $UNITCONF     = ".1.3.6.1.4.1.13742.6.3.2.2.1";
my $INLET_VAL    = ".1.3.6.1.4.1.13742.6.5.2.3.1.4";
my $INLET_SVAL   = ".1.3.6.1.4.1.13742.6.5.2.3.1.6";
my $INLET_MIN    = ".1.3.6.1.4.1.13742.6.3.3.4.1.27";
my $INLET_UNITS  = ".1.3.6.1.4.1.13742.6.3.3.4.1.6";
my $INLET_DEC    = ".1.3.6.1.4.1.13742.6.3.3.4.1.7";
my $OUTLET_VAL   = ".1.3.6.1.4.1.13742.6.5.4.3.1.4";
my $OUTLET_SVAL  = ".1.3.6.1.4.1.13742.6.5.4.3.1.6";
my $OUTLET_MIN   = ".1.3.6.1.4.1.13742.6.3.5.4.1.27";
my $OUTLET_UNITS = ".1.3.6.1.4.1.13742.6.3.5.4.1.6";
my $OUTLET_DEC   = ".1.3.6.1.4.1.13742.6.3.5.4.1.7";
my $SYSDESCR     = ".1.3.6.1.2.1.1.1.0";

#What a PDU2 agent answers for an instance that does not exist.
my $NOSUCH = "No Such Instance currently exists at this OID";

#Readings captured from a Raritan PX4-5851-E7V2 (fw 4.2.10.5-50400), inlet 1
#and outlet 1, as [sensorType, signedMinimum, value, signedValue, units, digits].
#Reactive power is the sensor with a negative signedMinimum: the unsigned column
#answers 0 there, the signed column carries the reading. Active and apparent
#energy are the reverse: the signed column answers 0 because their range
#exceeds Integer32, so neither column can be used unconditionally.
my @PX4_INLET = (
    [ 1,  0,      9503,     9503,  2,  3 ],
    [ 3,  0,      11,       11,    9,  0 ],
    [ 4,  0,      412,      412,   1,  0 ],
    [ 5,  0,      6002,     6002,  3,  0 ],
    [ 6,  0,      6194,     6194,  4,  0 ],
    [ 7,  0,      97,       97,    -1, 2 ],
    [ 8,  0,      93653612, 0,     5,  0 ],
    [ 9,  0,      97629274, 0,     6,  0 ],
    [ 23, 0,      600,      600,   8,  1 ],
    [ 29, -63000, 0,        -1360, 23, 0 ],
);
my @PX4_OUTLET = (
    [ 1, 0, 1042,    1042, 2, 3 ],
    [ 5, 0, 245,     245,  3, 0 ],
    [ 8, 0, 4088376, 0,    5, 0 ],
);

sub inlet_sensor {
    my ($resp, $inlet, $s) = @_;
    my ($st, $min, $val, $sval, $units, $digits) = @$s;
    $resp->{"$INLET_MIN.1.$inlet.$st"}   = $min;
    $resp->{"$INLET_VAL.1.$inlet.$st"}   = $val;
    $resp->{"$INLET_SVAL.1.$inlet.$st"}  = $sval;
    $resp->{"$INLET_UNITS.1.$inlet.$st"} = $units;
    $resp->{"$INLET_DEC.1.$inlet.$st"}   = $digits;
    return;
}

sub px4_responses {
    my %resp = (
        "$UNITCONF.2.1" => 1,     #inletCount
        "$UNITCONF.4.1" => 36,    #outletCount
    );
    inlet_sensor(\%resp, 1, $_) foreach (@PX4_INLET);
    foreach my $s (@PX4_OUTLET) {
        my ($st, $min, $val, $sval, $units, $digits) = @$s;
        foreach my $outlet (1 .. 2) {
            $resp{"$OUTLET_MIN.1.$outlet.$st"}   = $min;
            $resp{"$OUTLET_VAL.1.$outlet.$st"}   = $val;
            $resp{"$OUTLET_SVAL.1.$outlet.$st"}  = $sval;
            $resp{"$OUTLET_UNITS.1.$outlet.$st"} = $units;
            $resp{"$OUTLET_DEC.1.$outlet.$st"}   = $digits;
        }
    }
    return \%resp;
}

sub vitals_messages {
    my ($resp, $outlets) = @_;
    local @xCAT::SvrUtils::messages = ();
    my $session = FakeSession->new($resp);
    $session->{genpdu} = 1;
    xCAT_plugin::pdu::rvitals_for_genpdu('pdu1', $outlets, $session, undef);
    return ([ @xCAT::SvrUtils::messages ], $session);
}

#-- rvitals: value column selection ------------------------------------------

my ($msgs, $session) = vitals_messages(px4_responses(), 2);

ok(
    (grep { $_ eq 'pdu1|inlet 1 Reactive Power: -1360 var' } @$msgs),
    'a sensor with a negative signedMinimum is read from the signed column'
);
ok(
    (grep { $_ eq 'pdu1|inlet 1 Active Energy: 93653612 Wh' } @$msgs),
    'a sensor with signedMinimum 0 stays on the unsigned column'
);
ok(
    (grep { $_ eq 'pdu1|inlet 1 RMS Current: 9.503 A' } @$msgs),
    'readings are scaled by decimalDigits and labelled from sensorUnits'
);
ok(
    (grep { $_ eq 'pdu1|inlet 1 Power Factor: 0.97' } @$msgs),
    'a sensor reporting units none(-1) gets no unit suffix'
);
ok(
    (grep { $_ eq 'pdu1|outlet 2 RMS Current: 1.042 A' } @$msgs),
    'outlet sensors are read for every outlet in the count'
);

#-- rvitals: metered-only PDUs ------------------------------------------------

my %metered = ("$UNITCONF.2.1" => 1);
inlet_sensor(\%metered, 1, $PX4_INLET[0]);
foreach my $st (map { $_->[0] } @PX4_OUTLET) {
    $metered{"$OUTLET_MIN.1.1.$st"}  = $NOSUCH;
    $metered{"$OUTLET_VAL.1.1.$st"}  = $NOSUCH;
    $metered{"$OUTLET_SVAL.1.1.$st"} = $NOSUCH;
}

($msgs, $session) = vitals_messages(\%metered, 48);
is(
    scalar(grep { /\|outlet / } @$msgs), 0,
    'a PDU with no outlet sensors reports inlet readings only'
);
cmp_ok(
    scalar(grep { /^\Q$OUTLET_VAL\E\./ } @{ $session->{gets} }), '<=', 2,
    'the outlet sensor loop is skipped instead of walking every outlet'
);

#-- rvitals: sensor metadata cache -------------------------------------------

my %two_inlets = ("$UNITCONF.2.1" => 2);
foreach my $col ($INLET_MIN, $INLET_VAL, $INLET_SVAL, $INLET_UNITS, $INLET_DEC) {
    $two_inlets{"$col.1.1.1"} = $NOSUCH;
}
inlet_sensor(\%two_inlets, 2, $PX4_INLET[0]);

($msgs, $session) = vitals_messages(\%two_inlets, 0);
ok(
    (grep { $_ eq 'pdu1|inlet 2 RMS Current: 9.503 A' } @$msgs),
    'an absent sensor on one inlet does not seed the metadata cache for the next'
);

#-- rvitals: firmware without the signedMinimum column -----------------------

my %no_min = ("$UNITCONF.2.1" => 1);
inlet_sensor(\%no_min, 1, $PX4_INLET[0]);
$no_min{"$INLET_MIN.1.1.1"} = $NOSUCH;

($msgs, $session) = vitals_messages(\%no_min, 0);
ok(
    (grep { $_ eq 'pdu1|inlet 1 RMS Current: 9.503 A' } @$msgs),
    'a sensor with no signedMinimum column falls back to the unsigned column'
);

#-- session probe -------------------------------------------------------------

sub probe {
    my ($resp) = @_;
    local @xCAT::SvrUtils::messages = ();
    my $session = FakeSession->new($resp);
    my $ok = xCAT_plugin::pdu::pdu2_session_probe($session, 'pdu1', undef);
    return ($ok, $session, [ @xCAT::SvrUtils::messages ]);
}

my ($ok, $probed, $probe_msgs) = probe({});
ok(!$ok, 'a PDU that answers nothing at all is reported as unreachable');

($ok, $probed, $probe_msgs) = probe({
    $SYSDESCR          => '"Raritan PDU, MD:PX4-5851-E7V2"',
    "$OUTLETSTATE.1.1" => 7,
});
ok($ok, 'a PDU that answers sysDescr but not pduCount is still usable');
is(scalar(@$probe_msgs), 0, 'a PDU with no pduCount is not warned about');

($ok, $probed, $probe_msgs) = probe({
    $PDUCOUNT             => 1,
    "$OUTLETSTATE.1.1"    => 7,
});
ok($ok, 'a PDU that answers pduCount is usable');
is($probed->{genpdu_switchable}, 1, 'an answered outlet state marks the PDU switchable');

($ok, $probed, $probe_msgs) = probe({
    $PDUCOUNT             => 1,
    "$OUTLETSTATE.1.1"    => $NOSUCH,
});
ok($ok, 'a metered-only PDU is still usable for rinv and rvitals');
is($probed->{genpdu_switchable}, 0, 'a missing outlet state marks the PDU not switchable');

($ok, $probed, $probe_msgs) = probe({
    $PDUCOUNT             => 3,
    "$OUTLETSTATE.1.1"    => 7,
});
ok($ok, 'a linked PDU is not refused');
ok(
    (grep { /pduCount is 3/ } @$probe_msgs),
    'a pduCount other than 1 warns that only the primary unit is managed'
);

#-- session arguments from the pdu table -------------------------------------

my %v3 = xCAT_plugin::pdu::pdu2_session_args('pdu1', {
    snmpversion => 'v3',
    snmpuser    => 'admin',
    authtype    => 'sha',
    authkey     => 'authsecret',
    privtype    => 'aes',
});
is($v3{Version},   3,            'snmpversion v3 selects SNMPv3');
is($v3{SecName},   'admin',      'snmpuser becomes the v3 security name');
is($v3{SecLevel},  'authPriv',   'a privacy protocol implies authPriv');
is($v3{AuthProto}, 'SHA',        'the auth protocol is upper cased for net-snmp');
is($v3{PrivProto}, 'AES',        'the privacy protocol is upper cased for net-snmp');
is($v3{PrivPass},  'authsecret', 'privkey falls back to authkey when unset');

my %noauth = xCAT_plugin::pdu::pdu2_session_args('pdu1', {
    snmpversion => '3',
    snmpuser    => 'admin',
    authkey     => 'authsecret',
});
is($noauth{SecLevel}, 'authNoPriv', 'no privacy protocol implies authNoPriv');
ok(!exists $noauth{PrivProto}, 'authNoPriv sends no privacy protocol');

my %v2c = xCAT_plugin::pdu::pdu2_session_args('pdu1', {
    snmpversion => 'v2c',
    community   => 'private',
});
is($v2c{Version},   2,         'snmpversion v2c selects SNMPv2c');
is($v2c{Community}, 'private', 'the community comes from the pdu table');

my %v1 = xCAT_plugin::pdu::pdu2_session_args('pdu1', {});
is($v1{Version},   1,        'an unset snmpversion falls back to SNMPv1');
is($v1{Community}, 'public', 'an unset community falls back to public');

#-- outlet state translation --------------------------------------------------

sub outlet_state {
    my ($val) = @_;
    my $session = FakeSession->new({ "$OUTLETSTATE.1.4" => $val });
    $session->{genpdu} = 1;
    return xCAT_plugin::pdu::outletstat($session, 4);
}

is(outlet_state(7),        'on',            'outletSwitchingState on(7) reads as on');
is(outlet_state(8),        'off',           'outletSwitchingState off(8) reads as off');
is(outlet_state(undef),    'unknown state', 'an unanswered outlet state is unknown');

#-- rinv ----------------------------------------------------------------------

{
    local @xCAT::SvrUtils::messages = ();
    my $session = FakeSession->new({
        "$NAMEPLATE.2.1" => '"Raritan"',
        "$NAMEPLATE.3.1" => '"PX4-5851-E7V2"',
        "$NAMEPLATE.4.1" => '"R2BP0123456"',
        "$UNITCONF.4.1"  => 36,
        $SYSDESCR        => '"Raritan PDU, MD:PX4-5851-E7V2 HW:0x1D FW:4.2.10.5-50400"',
    });
    $session->{genpdu} = 1;
    xCAT_plugin::pdu::rinv_for_genpdu('pdu1', $session, undef);
    my @m = @xCAT::SvrUtils::messages;

    ok((grep { $_ eq 'pdu1|PDU Manufacturer: Raritan' } @m),
        'nameplate strings are reported without their quotes');
    ok((grep { $_ eq 'pdu1|PDU Outlet Count: 36' } @m),
        'the outlet count is reported from unitConfiguration');
    ok((grep { /^pdu1\|PDU Description: Raritan PDU, MD:PX4/ } @m),
        'the firmware string is reported from sysDescr');
}

done_testing();
