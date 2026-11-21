#!/usr/bin/env perl

use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings qw(once redefine);

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::IPMISDR qw(load_ipmi_plugin new_session);

# An IPMI command reads the device ID and then the SDR repository before it can answer.
# A failure in that chain must reach the administrator as an error of the node and must end
# the chain, instead of being dropped or reported under no node.

load_ipmi_plugin();

# Run one callback of the chain with a reply and return what it reported and requested.
sub run_step {
    my ($step, $rsp, %state) = @_;
    my $sessdata = { node => 'node01', ipmisession => new_session(), %state };
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
