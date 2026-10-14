#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Cwd qw(realpath);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use IO::Socket::UNIX;
use Test::More;

my $fixture = realpath(tempdir(CLEANUP => 1));
make_path("$fixture/db", "$fixture/run");
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
xCAT::Table->new('site', -create => 1)->setAttribs({ key => 'one' }, { value => 'first' });

my $parent = $$;
{
    no strict 'refs';
    no warnings qw(redefine once);

    # The DB worker listens in /var/run/xcat, so its socket goes to the fixture.
    my $socket = \&IO::Socket::UNIX::new;
    *IO::Socket::UNIX::new = sub {
        my ($class, %args) = @_;
        $args{$_} =~ s{^/var/run/xcat/}{$fixture/run/} foreach grep { defined $args{$_} } qw(Local Peer);
        return $socket->($class, %args);
    };
    *xCAT::Table::mkpath = sub { };

    # A method dies in the DB worker while the fixture has a file of its name, which the worker removes.
    foreach my $method (qw(commit setAttribs getAttribs)) {
        my $call = \&{"xCAT::Table::$method"};
        *{"xCAT::Table::$method"} = sub {
            die "$method failed in the DB worker\n" if $$ != $parent && unlink("$fixture/fail-$method");
            goto &$call;
        };
    }
}

my $worker = xCAT::Table::init_dbworker();
END { kill('TERM', $worker) && waitpid($worker, 0) if $worker && $$ == $parent }
ok($worker > 0, 'the DB worker starts');

my $site = xCAT::Table->new('site');
sub value { my $row = $site->getAttribs({ key => 'one' }, 'value'); return $row && $row->{value} }
is(value(), 'first', 'a request through the DB worker succeeds');

for my $case ([ setAttribs => sub { $site->setAttribs({ key => 'one' }, { value => 'changed' }) } ],
    [ getAttribs => sub { $site->getAttribs({ key => 'one' }, 'value') } ],
    [ commit     => sub { $site->commit } ])
{
    my ($method, $call) = @$case;
    open(my $flag, '>', "$fixture/fail-$method") or die $!;
    close($flag);
    my @result = eval { $call->() };
    ok(!-e "$fixture/fail-$method", "the DB worker runs $method");
    is($@, "$method failed in the DB worker\n", "$method dies with the exception of the DB worker");
}
is(value(), 'first', 'the DB worker serves the next request, and the requests that died change no row');

done_testing();
