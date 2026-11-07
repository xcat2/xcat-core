#!/usr/bin/env perl
# After discovery xcatd opens a TCP connection back to the node and sends "restart".
# nodediscover.pm and send_tcp_msg built that socket with IO::Socket::INET, which cannot
# reach an IPv6 address, so an IPv6 node never got the message and exited on the discovery
# timeout. open_tcp_socket chooses the class. Both classes are replaced here, so nothing
# connects to anything.
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoWarnings)

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

BEGIN {
    package xCAT::Table;
    sub new { return bless {}, shift; }
    sub getAllAttribs { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub get_site_attribute { return; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;
}

require xCAT::NetworkUtils;

my @attempts;
my %answer;
my $written = '';

{
    no warnings 'redefine';
    foreach my $class (qw(IO::Socket::INET IO::Socket::INET6)) {
        no strict 'refs';
        *{"${class}::new"} = sub {
            my (undef, %args) = @_;
            push @attempts, { class => $class, %args };
            return undef unless $answer{$class};
            # An IO::Socket is a filehandle, and send_tcp_msg prints to it. An
            # in-memory handle collects what it writes.
            open(my $handle, '>', \$written) or die "Unable to open a scratch handle: $!";
            return $handle;
        };
        $INC{ join('/', split(/::/, $class)) . '.pm' } = __FILE__;
    }
}

sub attempt {
    @attempts = ();
    my $sock = xCAT::NetworkUtils->open_tcp_socket(@_);
    return ($sock, [@attempts]);
}

# An IPv6 node: the family-neutral class is asked, and it is the one that can reach it.
local $xCAT::NetworkUtils::inet6support = 1;
%answer = ('IO::Socket::INET6' => 1);
my ($sock, $tried) = attempt('2001:db8:177::2', 3001, 1);
ok($sock, 'a connection to an IPv6 node is opened');
is(scalar(@{$tried}), 1, 'one class is asked for it');
is($tried->[0]{class}, 'IO::Socket::INET6', 'and it is the one that carries AF_INET6');
is($tried->[0]{PeerAddr}, '2001:db8:177::2', 'the node address is passed unbracketed');
is($tried->[0]{PeerPort}, 3001, 'the port is passed');
is($tried->[0]{Proto}, 'tcp', 'the connection is TCP');
is($tried->[0]{Timeout}, 1, 'the connect timeout is passed');

# An IPv4 node keeps working through whichever class answers.
%answer = ('IO::Socket::INET6' => 1);
($sock, $tried) = attempt('192.168.201.10', 3001, 1);
ok($sock, 'a connection to an IPv4 node is opened');
is($tried->[0]{PeerAddr}, '192.168.201.10', 'the IPv4 address is passed');

# A management node without the IPv6 modules keeps the original IPv4 path.
{
    local $xCAT::NetworkUtils::inet6support = undef;
    %answer = ('IO::Socket::INET' => 1);
    ($sock, $tried) = attempt('192.168.201.10', 3001, 1);
    ok($sock, 'a connection is opened without the IPv6 modules');
    is_deeply([ map { $_->{class} } @{$tried} ], ['IO::Socket::INET'],
        'only the IPv4 class is asked when the IPv6 modules are absent');
}

# The IPv4 class is the fallback when the family-neutral attempt fails.
%answer = ('IO::Socket::INET' => 1);
($sock, $tried) = attempt('192.168.201.10', 3001, 1);
ok($sock, 'the IPv4 class answers after the family-neutral one does not');
is_deeply([ map { $_->{class} } @{$tried} ],
    [ 'IO::Socket::INET6', 'IO::Socket::INET' ],
    'the family-neutral class is asked first and the IPv4 one second');

# Nothing answers.
%answer = ();
($sock, $tried) = attempt('2001:db8:177::2', 3001, 1);
ok(!$sock, 'a node that cannot be reached returns no socket');

is(xCAT::NetworkUtils->open_tcp_socket(undef, 3001), undef, 'no address opens nothing');
is(xCAT::NetworkUtils->open_tcp_socket('192.168.201.10', undef), undef, 'no port opens nothing');

# send_tcp_msg is the other caller, and it writes the message it was given.
%answer = ('IO::Socket::INET6' => 1);
@attempts = ();
$written = '';
is(xCAT::NetworkUtils->send_tcp_msg('2001:db8:177::2', 3001, 'restart'), 0,
    'send_tcp_msg reports success for an IPv6 node');
is($attempts[0]{class}, 'IO::Socket::INET6', 'and it reached that node through the IPv6 class');
is($written, 'restart', 'the message is written to the socket');

%answer = ();
is(xCAT::NetworkUtils->send_tcp_msg('2001:db8:177::2', 3001, 'restart'), 1,
    'send_tcp_msg reports failure when nothing answers');

done_testing();
