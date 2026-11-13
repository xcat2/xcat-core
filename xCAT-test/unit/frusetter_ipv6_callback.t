#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use IO::Socket::IP;
use POSIX ();
use Test::More;

# rewritemyfru asks the node on the callback port whether it sent the request.
# Each test runs that exchange against a real listener on the loopback address.

# xCAT-server requires IO::Socket::INET6. The unit suite host may not carry it,
# so IO::Socket::IP stands in for it there. NetworkUtils looks for the module
# when it loads, so the stand-in must exist first.
BEGIN {
    unless (eval { require IO::Socket::INET6; 1 }) {
        @IO::Socket::INET6::ISA = ('IO::Socket::IP');
        $INC{'IO/Socket/INET6.pm'} = __FILE__;
    }
}

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/frusetter.pm";
# frusetter.pm uses IO::Select without loading it. xcatd has it loaded when it
# calls a plugin.
require IO::Select;
require xCAT::NetworkUtils;
require $source;

# listener <address> <answer> -- accept one connection on a free port, read one
# line, answer with <answer>. Returns the port, the child pid and a handle that
# gives back the line the child read.
sub listener {
    my ($address, $answer) = @_;
    my $server = IO::Socket::IP->new(
        LocalHost => $address,
        LocalPort => 0,
        Listen    => 1,
        ReuseAddr => 1,
    ) or die "cannot listen on $address: $@";
    my $port = $server->sockport;
    pipe(my $reader, my $writer) or die "pipe: $!";
    STDOUT->flush;
    STDERR->flush;
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        close $reader;
        local $SIG{ALRM} = sub { POSIX::_exit(1) };
        alarm 10;
        my $client = $server->accept or POSIX::_exit(1);
        my $line = <$client>;
        $line = '' unless defined $line;
        print {$writer} $line;
        close $writer;
        print {$client} "$answer\n";
        close $client;
        POSIX::_exit(0);
    }
    close $writer;
    close $server;
    return ($port, $pid, $reader);
}

sub received {
    my ($pid, $reader) = @_;
    local $/;
    my $line = <$reader>;
    close $reader;
    waitpid($pid, 0);
    return defined $line ? $line : '';
}

{
    my ($port, $pid, $reader) = listener('::1', 'CREDOKBYME');
    is(xCAT_plugin::frusetter::ok_with_node('::1', $port), 1,
        'an IPv6 node that started the credential listener approves the request');
    is(received($pid, $reader), "CREDOKBYYOU?\n",
        'the IPv6 node receives the credential challenge');
}

{
    my ($port, $pid, $reader) = listener('127.0.0.1', 'CREDOKBYME');
    is(xCAT_plugin::frusetter::ok_with_node('127.0.0.1', $port), 1,
        'an IPv4 node that started the credential listener approves the request');
    is(received($pid, $reader), "CREDOKBYYOU?\n",
        'the IPv4 node receives the credential challenge');
}

{
    my ($port, $pid, $reader) = listener('::1', 'SOMETHINGELSE');
    is(xCAT_plugin::frusetter::ok_with_node('::1', $port), 0,
        'an IPv6 node that gives another answer does not approve the request');
    received($pid, $reader);
}

{
    # process_request always calls back on port 300, which a test cannot bind
    # without root. Only the port is moved; the exchange is real.
    my ($port, $pid, $reader) = listener('::1', 'CREDOKBYME');
    my $open = \&xCAT::NetworkUtils::open_tcp_socket;
    my (@responses, @requests);
    {
        no warnings qw(once redefine);
        local *xCAT::NetworkUtils::open_tcp_socket = sub {
            my @args = @_;
            $args[2] = $port if $args[2] == 300;
            return $open->(@args);
        };
        xCAT_plugin::frusetter::process_request(
            { command => ['rewritemyfru'], _xcat_clienthost => ['::1'] },
            sub { push @responses, $_[0]; },
            sub { push @requests, $_[0]; });
    }
    is(received($pid, $reader), "CREDOKBYYOU?\n",
        'rewritemyfru sends the credential challenge to the IPv6 node');
    is_deeply(\@responses, [], 'rewritemyfru reports no error to a node that asked over IPv6');
    is_deeply(\@requests, [ { command => ['rfrurewrite'], noderange => ['::1'] } ],
        'rewritemyfru rewrites the FRU of a node that asked over IPv6');
}

done_testing();
