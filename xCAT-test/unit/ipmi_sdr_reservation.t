#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings qw(once redefine);

use File::Spec;
use FindBin;
use Test::More;

# Get SDR Repository Info can leave the reservation bit clear on a BMC that grants Reserve
# SDR Repository. The SDR read must still ask for the reservation and use it.

BEGIN {
    for my $module (qw(
      xCAT::GlobalDef xCAT_monitoring::monitorctrl xCAT::IPMI
      xCAT::BMCUtils xCAT::PasswordUtils xCAT::Utils xCAT::TableUtils
      xCAT::IMMUtils xCAT::ServiceNodeUtils xCAT::NetworkUtils xCAT::Usage
      xCAT::data::ibmhwtypes xCAT::data::ibmleds
      xCAT::data::ipmigenericevents xCAT::data::ipmisensorevents
      IBM::EnergyManager
    )) {
        (my $file = $module) =~ s{::}{/}g;
        $INC{"$file.pm"} = __FILE__;
        no strict 'refs';
        *{"${module}::import"} = sub { };
    }

    package xCAT::SvrUtils;
    our @messages;
    sub import { }
    sub sendmsg { push @messages, { text => $_[0], node => $_[2] }; }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;

    package xCAT::SPD;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::decode_spd"} = sub { return; };
    }
    $INC{'xCAT/SPD.pm'} = __FILE__;

    package File::Path;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::mkpath"} = sub { return; };
    }
    $INC{'File/Path.pm'} = __FILE__;

    package Thread;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::yield"} = sub { return; };
    }
    $INC{'Thread.pm'} = __FILE__;

    package LWP;
    our $VERSION = 5.64;
    sub import { }
    $INC{'LWP.pm'} = __FILE__;

    package HTTP::Request::Common;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::GET"}  = sub { return; };
        *{"${caller}::POST"} = sub { return; };
    }
    $INC{'HTTP/Request/Common.pm'} = __FILE__;

    package main;
    *CORE::GLOBAL::chmod = sub (@) { return 1; };
}

package FakeSession;
sub new { return bless { calls => [] }, shift; }
sub subcmd { my ($self, %args) = @_; push @{ $self->{calls} }, \%args; return; }

package main;

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');
$ENV{XCATROOT} = File::Spec->catdir($repo_root, 'xCAT-server');
my $plugin = File::Spec->catfile($repo_root, qw(xCAT-server lib xcat plugins ipmi.pm));
do $plugin or die $@ || "Unable to load $plugin: $!";

# A device identity that no SDR cache file holds, so the SDR is read from the BMC.
sub new_sessdata {
    return {
        node          => 'node01',
        ipmisession   => FakeSession->new(),
        mfg_id        => 0xfffe,
        prod_id       => 0xfffe,
        device_id     => 0xfe,
        device_rev    => 0,
        firmware_rev1 => 0,
        firmware_rev2 => 0,
    };
}

# The Get SDR Repository Info reply of an OpenBMC that grants reservations, with the
# operation support byte last.
sub repository_info {
    my ($operation_support) = @_;
    return { code => 0, data => [ 0x51, 0x2b, 0x00, 0xff, 0xff, (0) x 8, $operation_support ] };
}

sub requests { return $_[0]->{ipmisession}->{calls}; }

subtest 'a BMC that does not advertise the reservation is asked for one' => sub {
    my $sessdata = new_sessdata();
    local @xCAT::SvrUtils::messages = ();
    xCAT_plugin::ipmi::got_sdr_rep_info(repository_info(0x00), $sessdata);
    is_deeply(\@xCAT::SvrUtils::messages, [], 'no error is reported');
    is(scalar @{ requests($sessdata) }, 1, 'one request follows');
    my $request = requests($sessdata)->[0] || {};
    is($request->{netfn},   0x0a, 'the request is a storage command');
    is($request->{command}, 0x22, 'the request is Reserve SDR Repository');

    ok($request->{callback}, "the request has a reply handler") or return;
    $sessdata->{ipmisession}->{calls} = [];
    $request->{callback}->({ code => 0, data => [ 0x01, 0x00 ] }, $request->{callback_args});
    is_deeply(\@xCAT::SvrUtils::messages, [], 'the granted reservation reports no error');
    my $fetch = requests($sessdata)->[0] || {};
    is($fetch->{command}, 0x23, 'Get SDR follows the reservation');
    is_deeply([ @{ $fetch->{data} || [] }[ 0, 1 ] ], [ 0x01, 0x00 ],
        'Get SDR carries the granted reservation ID');
};

subtest 'a refused reservation that was not advertised is reported as unsupported' => sub {
    my $sessdata = new_sessdata();
    local @xCAT::SvrUtils::messages = ();
    xCAT_plugin::ipmi::got_sdr_rep_info(repository_info(0x00), $sessdata);
    my $request = requests($sessdata)->[0] || {};
    ok($request->{callback}, "a reservation is requested") or return;
    $sessdata->{ipmisession}->{calls} = [];
    $request->{callback}->({ code => 0xc1, data => [] }, $request->{callback_args});
    is(scalar @xCAT::SvrUtils::messages, 1, 'one message');
    my $message = $xCAT::SvrUtils::messages[0] || {};
    is($message->{node}, 'node01', 'the message names the node');
    is_deeply($message->{text}, [ 1, 'SDR reservation unsupported.' ], 'the message keeps its text');
    is(scalar @{ requests($sessdata) }, 0, 'no Get SDR request follows');
};

subtest 'other refusals of a reservation that was not advertised keep their reason' => sub {
    for my $refusal (
        [ 0xc0, 'Node busy, command could not be processed' ],
        [ 0xd4, 'Insufficient privilege level' ],
    ) {
        my ($code, $reason) = @$refusal;
        my $sessdata = new_sessdata();
        local @xCAT::SvrUtils::messages = ();
        xCAT_plugin::ipmi::got_sdr_rep_info(repository_info(0x00), $sessdata);
        my $request = requests($sessdata)->[0] || {};
        ok($request->{callback}, "a reservation is requested") or next;
        $sessdata->{ipmisession}->{calls} = [];
        $request->{callback}->({ code => $code, data => [] }, $request->{callback_args});
        is_deeply([ map { $_->{text} } @xCAT::SvrUtils::messages ], [ [ 1, $reason ] ],
            sprintf('completion code %02x is reported as itself', $code));
        is(scalar @{ requests($sessdata) }, 0, 'no Get SDR request follows');
    }
};

subtest 'a BMC that advertises the reservation is still asked for one' => sub {
    my $sessdata = new_sessdata();
    local @xCAT::SvrUtils::messages = ();
    xCAT_plugin::ipmi::got_sdr_rep_info(repository_info(0x02), $sessdata);
    is_deeply(\@xCAT::SvrUtils::messages, [], 'no error is reported');
    my $request = requests($sessdata)->[0] || {};
    is($request->{command}, 0x22, 'the request is Reserve SDR Repository');
};

done_testing();
