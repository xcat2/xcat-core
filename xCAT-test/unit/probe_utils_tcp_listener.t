#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use Test::More;

require probe_utils;

is(
    probe_utils::_capture_command_output($^X, '-e', 'print "captured output\\n"'),
    "captured output\n",
    'command output is captured without a shell'
);
ok(
    !defined(probe_utils::_capture_command_output($^X, '-e', 'exit 1')),
    'failed command does not return listener output'
);

my $ss_output = <<'EOF';
State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
LISTEN 0      128          0.0.0.0:3001      0.0.0.0:*
LISTEN 0      128             [::]:3002         [::]:* users:(("xcatd",pid=100,fd=5))
LISTEN 0      511                *:80               *:* users:(("httpd",pid=200,fd=4))
EOF

my $netstat_output = <<'EOF';
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 0.0.0.0:3001            0.0.0.0:*               LISTEN      100/xcatd
tcp6       0      0 :::3002                 :::*                    LISTEN      100/xcatd
tcp6       0      0 :::80                   :::*                    LISTEN      200/apache2
EOF

ok(probe_utils::_tcp_listener_output_has_port($ss_output, 3001), 'ss IPv4 listener is detected');
ok(probe_utils::_tcp_listener_output_has_port($ss_output, 3002), 'ss IPv6 listener is detected');
ok(!probe_utils::_tcp_listener_output_has_port($ss_output, 300), 'ss listener requires an exact port match');
ok(probe_utils::_tcp_listener_output_has_port($ss_output, 80, qr/httpd|apache/), 'ss listener process can be matched');
ok(!probe_utils::_tcp_listener_output_has_port($ss_output, 80, qr/xcatd/), 'ss listener rejects the wrong process');

ok(probe_utils::_tcp_listener_output_has_port($netstat_output, 3001), 'netstat IPv4 listener is detected');
ok(probe_utils::_tcp_listener_output_has_port($netstat_output, 3002), 'netstat IPv6 listener is detected');
ok(probe_utils::_tcp_listener_output_has_port($netstat_output, 80, qr/httpd|apache/), 'netstat listener process can be matched');
ok(!probe_utils::_tcp_listener_output_has_port($netstat_output, 0), 'invalid port is rejected');
ok(!probe_utils::_tcp_listener_output_has_port($netstat_output, 'http'), 'non-numeric port is rejected');

{
    no warnings 'redefine';
    my @commands;
    local *probe_utils::_command_available = sub { return 1; };
    local *probe_utils::_capture_command_output = sub {
        push @commands, [@_];
        return $ss_output;
    };

    ok(probe_utils->is_tcp_port_listening(3001), 'class-style listener check succeeds with ss');
    is_deeply($commands[0], ['ss', '-lnt'], 'listener check prefers ss');
}

{
    no warnings 'redefine';
    my @commands;
    local *probe_utils::_command_available = sub { return 1; };
    local *probe_utils::_capture_command_output = sub {
        push @commands, [@_];
        return $ss_output;
    };

    ok(probe_utils::is_tcp_port_listening(80, qr/httpd|apache/), 'process-aware listener check succeeds with ss');
    is_deeply($commands[0], ['ss', '-lntp'], 'process-aware listener check requests ss process data');
}

{
    no warnings 'redefine';
    my @commands;
    local *probe_utils::_command_available = sub { return 1; };
    local *probe_utils::_capture_command_output = sub {
        push @commands, [@_];
        return $_[0] eq 'ss' ? $ss_output : $netstat_output;
    };

    ok(!probe_utils::is_tcp_port_listening(4000), 'successful ss output is authoritative when a port is absent');
    is(scalar(@commands), 1, 'missing port in successful ss output does not consult netstat');
}

{
    no warnings 'redefine';
    my @commands;
    local *probe_utils::_command_available = sub { return 1; };
    local *probe_utils::_capture_command_output = sub {
        push @commands, [@_];
        return if $_[0] eq 'ss';
        return $netstat_output;
    };

    ok(probe_utils::is_tcp_port_listening(3002), 'listener check falls back when ss fails');
    is_deeply(
        \@commands,
        [['ss', '-lnt'], ['netstat', '-ant']],
        'failed ss invocation falls back to netstat'
    );
}

{
    no warnings 'redefine';
    my @commands;
    local *probe_utils::_command_available = sub { return $_[0] eq 'netstat'; };
    local *probe_utils::_capture_command_output = sub {
        push @commands, [@_];
        return $netstat_output;
    };

    ok(probe_utils::is_tcp_port_listening(80, qr/httpd|apache/), 'process-aware listener check uses netstat fallback');
    is_deeply($commands[0], ['netstat', '-tnlp'], 'process-aware fallback preserves legacy netstat options');
}

{
    no warnings 'redefine';
    local *probe_utils::_command_available = sub { return 0; };
    ok(!probe_utils::is_tcp_port_listening(3001), 'missing socket inspection commands fail cleanly');
}

done_testing();
