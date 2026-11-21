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

# getbmcconfig asks the node on the callback port whether it sent the request.
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

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/bmcconfig.pm";

# xCAT::IMMUtils loads xCAT_plugin::bmcconfig, which is this file.
BEGIN { $INC{'xCAT_plugin/bmcconfig.pm'} = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/bmcconfig.pm"; }
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
    is(xCAT_plugin::bmcconfig::ok_with_node('::1', $port), 1,
        'an IPv6 node that started the credential listener approves the request');
    is(received($pid, $reader), "CREDOKBYYOU?\n",
        'the IPv6 node receives the credential challenge');
}

{
    my ($port, $pid, $reader) = listener('127.0.0.1', 'CREDOKBYME');
    is(xCAT_plugin::bmcconfig::ok_with_node('127.0.0.1', $port), 1,
        'an IPv4 node that started the credential listener approves the request');
    is(received($pid, $reader), "CREDOKBYYOU?\n",
        'the IPv4 node receives the credential challenge');
}

{
    my ($port, $pid, $reader) = listener('::1', 'SOMETHINGELSE');
    is(xCAT_plugin::bmcconfig::ok_with_node('::1', $port), 0,
        'an IPv6 node that gives another answer does not approve the request');
    received($pid, $reader);
}

{
    # process_request always calls back on port 300, which a test cannot bind
    # without root. Only the port is moved; the exchange is real.
    my ($port, $pid, $reader) = listener('::1', 'CREDOKBYME');
    my $open = \&xCAT::NetworkUtils::open_tcp_socket;
    my (@responses, @messages);
    {
        no warnings qw(once redefine);
        local *xCAT::NetworkUtils::open_tcp_socket = sub {
            my @args = @_;
            $args[2] = $port if $args[2] == 300;
            return $open->(@args);
        };
        local *xCAT::Table::new = sub {
            return bless {}, 'BmcconfigCallbackTest::Table';
        };
        local *xCAT::PasswordUtils::getIPMIAuth = sub {
            return { '::1' => { username => 'USERID', password => 'test-password' } };
        };
        local *xCAT_plugin::bmcconfig::net_parms = sub {
            return ('2001:db8:1::20', '64', '2001:db8:1::1', '2001:db8:1::');
        };
        local *xCAT::MsgUtils::message = sub { push @messages, $_[2]; };
        local %::XCATSITEVALS = ();
        xCAT_plugin::bmcconfig::process_request(
            { command => ['getbmcconfig'], _xcat_clienthost => ['::1'] },
            sub { push @responses, $_[0]; });
    }
    is(received($pid, $reader), "CREDOKBYYOU?\n",
        'getbmcconfig sends the credential challenge to the IPv6 node');
    is_deeply(\@responses, [ {
                bmcip        => '2001:db8:1::20',
                netmask      => '64',
                gateway      => '2001:db8:1::1',
                routerprefix => '2001:db8:1::',
                username     => 'USERID',
                password     => 'test-password',
            } ],
        'getbmcconfig gives the BMC configuration to a node that asked over IPv6')
      or diag explain \@responses, \@messages;
}

{
    package BmcconfigCallbackTest::Table;
    sub getNodesAttribs { return { '::1' => [ { bmc => '2001:db8:1::20' } ] }; }
}

done_testing();
