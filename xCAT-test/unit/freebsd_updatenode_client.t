#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use Carp qw(croak);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use xCAT::FreeBSDPkg;

my $temporary = tempdir(CLEANUP => 1);
my $client = $ENV{XCAT_UPDATENODE_CLIENT} || "$FindBin::Bin/../../xCAT-client/bin/updatenode";
make_path("$temporary/bin", "$temporary/lib/perl/xCAT");
copy($client, "$temporary/bin/updatenode") or croak $!;

sub write_file {
    my ($name, $bytes) = @_;
    open(my $file, '>', "$temporary/lib/perl/xCAT/$name.pm") or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

write_file('Client', <<'CLIENT');
package xCAT::Client;
use strict;
use warnings;
use JSON;
our $EXITCODE = 0;
sub handle_response { return; }
sub submit_request {
    print JSON->new->canonical->encode($_[0]);
    return;
}
1;
CLIENT
write_file('MsgUtils', 'package xCAT::MsgUtils; sub message { print STDERR $_[2]; } 1;');
write_file('Usage', 'package xCAT::Usage; sub getUsage { return "usage"; } 1;');

sub command {
    my @arguments = @_;
    return xCAT::FreeBSDPkg::run_command([$^X, "$temporary/bin/updatenode", @arguments], cwd => $temporary,
        environment => { XCATROOT => $temporary, PATH => '/usr/bin:/bin', TERM => 'dumb', SHELL => '/bin/sh' },
        timeout => 10, stdout_limit => 1048576);
}

sub submitted {
    my ($node, @arguments) = @_;
    my $result = command($node, @arguments);
    is($result->{exitcode}, 0, 'client accepts the command syntax');
    is($result->{signal}, 0, 'client exits normally');
    my $request = eval { JSON->new->decode($result->{stdout}) };
    ok(defined($request), 'the real client reaches the submission boundary');
    return unless defined($request);
    is_deeply($request->{command}, ['updatenode'], 'the command identity is preserved');
    is_deeply($request->{noderange}, [$node], 'the node range is preserved');
    is_deeply($request->{arg}, \@arguments, 'all arguments reach the daemon unchanged');
    return;
}

subtest 'retained FreeBSD runs reach the daemon' => sub {
    submitted('node1', '--freebsd-run', 'a' x 32, '-t', '60');
    submitted('node1', '--freebsd-run', 'a' x 32, '--freebsd-release', '--timeout', '60');
};

subtest 'existing Linux and AIX argument forms are preserved' => sub {
    submitted('linux1', '-F', '-S', '-P', 'custom "two words" ""');
    submitted('linux1', '-P');
    submitted('linux1', 'custom "two words" ""');
    submitted('linux1', '-P', 'custom', '--timetout', '60');
    submitted('aix1', '-S', '-A', '-d', '/alternate/source', 'installp_flags=-a');
};

subtest 'invalid client syntax never submits a request' => sub {
    for my $arguments (['--freebsd-run'], ['--unrecognized-option']) {
        my $result = command('node1', @$arguments);
        is($result->{exitcode}, 1, 'invalid syntax is rejected');
        is($result->{stdout}, "usage\n", 'the client reports usage without submitting');
        isnt($result->{stderr}, '', 'the rejected option is reported');
    }
};

done_testing();
