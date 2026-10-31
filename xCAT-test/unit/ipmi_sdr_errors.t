#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings qw(once redefine);

use File::Spec;
use FindBin;
use Test::More;

# An IPMI command reads the device ID and then the SDR repository before it can answer.
# A failure in that chain must reach the administrator as an error of the node and must end
# the chain, instead of being dropped or reported under no node.

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

# Run one callback of the chain with a reply and return what it reported and requested.
sub run_step {
    my ($step, $rsp, %state) = @_;
    my $sessdata = { node => 'node01', ipmisession => FakeSession->new(), %state };
    local @xCAT::SvrUtils::messages = ();
    my $ok = eval { $step->($rsp, $sessdata); 1 };
    return {
        died     => $ok ? '' : ($@ || 'died'),
        messages => [@xCAT::SvrUtils::messages],
        requests => $sessdata->{ipmisession}->{calls},
    };
}

sub assert_node_error {
    my ($result, $text, $case) = @_;
    is($result->{died}, '', "$case: the callback returns");
    is(scalar @{ $result->{messages} }, 1, "$case: one message");
    my $message = $result->{messages}->[0] || {};
    is($message->{node}, 'node01', "$case: the message names the node");
    is_deeply($message->{text}, [ 1, $text ], "$case: the message is an error with the reply text");
    is(scalar @{ $result->{requests} }, 0, "$case: the chain stops");
}

my $invalid_command = { code => 0xc1, data => [] };
my $timeout         = { error => 'timeout' };

for my $step (
    [ 'Get Device ID',              \&xCAT_plugin::ipmi::gotdevid ],
    [ 'Get SDR Repository Info',    \&xCAT_plugin::ipmi::got_sdr_rep_info ],
    [ 'Reserve SDR Repository',     \&xCAT_plugin::ipmi::reserved_sdr_repo ],
    [ 'the first Get SDR',          \&xCAT_plugin::ipmi::start_sdr_record ],
    [ 'a following Get SDR',        \&xCAT_plugin::ipmi::add_sdr_data ],
) {
    my ($name, $callback) = @$step;
    assert_node_error(run_step($callback, $timeout), 'timeout', "$name times out");
}

my $result = run_step(\&xCAT_plugin::ipmi::reserved_sdr_repo, $invalid_command,
    sdr_info => { resv_sdr => 1 });
assert_node_error($result, "Invalid or unsupported command", "a refused SDR reservation");

done_testing();
