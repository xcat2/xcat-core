package DispatchTrace;

use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use RedactionDependencies;
# Load the checkout's redactor before the daemon adds installed-library paths.
use xCAT::xcatd;

BEGIN {
    # Keep new daemon imports stubbed to avoid loading service dependencies during compilation.
    for my $module (qw(xCAT::TLSPolicy xCAT::NetworkUtils xCAT::RespawnUtils
        xCAT::CmdLog xCAT::State xCAT::Client xCAT::XML xCAT::NotifHandler
        xCAT_monitoring::monitorctrl)) {
        (my $file = "$module.pm") =~ s{::}{/}g;
        $INC{$file} = __FILE__;
    }
}

sub xCAT::MsgUtils::trace {
    die bless {trace => [@_]}, 'DispatchTrace::Captured';
}

sub main::nodesmissed { die 'Unexpected node-range lookup'; }

# INIT runs the compiled dispatch function before daemon startup, stopping at the trace sink before plugin execution.
INIT {
    my $request = decode_json(shift @ARGV);
    local $SIG{ALRM} = sub { die "Dispatch trace timed out\n"; };
    alarm(10);
    eval { main::dispatch_request($request, sub { die 'Unexpected callback'; }, 'testplugin'); };
    my $result = $@;
    alarm(0);
    die "Dispatch did not reach the trace sink: $result"
      unless ref($result) eq 'DispatchTrace::Captured';
    print encode_json({trace => $result->{trace}, request => $request});
    exit 0;
}

1;
