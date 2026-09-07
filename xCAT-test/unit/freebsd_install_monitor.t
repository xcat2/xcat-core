#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use Test::More;
use xCAT::FreeBSDInstall;

BEGIN {
    $INC{'xCAT/Table.pm'} = __FILE__;
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;
}
{
    package xCAT::NetworkUtils;
    our $address = '192.0.2.10';
    sub clearcache { return; }
    sub getipaddr { return $address; }
}
{
    package xCAT::Table;
    our (%entries, $unavailable);
    sub new { return undef if $unavailable; return bless { name => $_[1] }, $_[0]; }
    sub getNodeAttribs { return $entries{$_[0]->{name}}{$_[1]}; }
    sub close { return; }
}

my $temporary = tempdir(CLEANUP => 1);
my $sequence = 0;
my $attempt = 'b' x 32;

sub fixture {
    my $directory = "$temporary/state-" . ++$sequence;
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $directory);
    %xCAT::Table::entries = (chain => { node1 => { currstate => 'install' } },
        nodelist => { node1 => { status => 'booting' } });
    $xCAT::Table::unavailable = 0;
    return ($directory, $generation);
}

sub dispatch {
    my ($request) = @_;
    my ($command, $node, $argument) = map { $request->{$_}[0] } qw(command node arg);
    if ($command eq 'nodeset') {
        $xCAT::Table::entries{chain}{$node}{currstate} = $argument;
    } elsif ($command eq 'updatenodestat') {
        $xCAT::Table::entries{nodelist}{$node}{status} = $argument;
    } else {
        die "Unexpected command $command\n";
    }
    return {};
}

sub status {
    my ($directory, $generation, $phase, $run, $peer) = @_;
    $run ||= \&dispatch;
    $peer = '192.0.2.10' unless defined($peer);
    return xCAT::FreeBSDInstall::handle_status('node1', $peer,
        "freebsd-install-v1 $generation $attempt $phase\n", $run, directory => $directory);
}

sub rejected {
    my ($code, $pattern, $label) = @_;
    my $ok = eval { $code->(); 1 };
    ok(!$ok, "$label fails");
    like($@, $pattern, "$label reports the reason");
}

my ($directory, $generation) = fixture();
my @requests;
my $run = sub { push @requests, $_[0]; return dispatch($_[0]); };
is(status($directory, $generation, 'begin', $run), "freebsd-install-v1 $generation begin ok\n",
    'begin acknowledges a confirmed installing status');
is(status($directory, $generation, 'complete', $run), "freebsd-install-v1 $generation complete ok\n",
    'completion acknowledges confirmed local boot and installed status');
is(status($directory, $generation, 'booted', $run, '::ffff:192.0.2.10'),
    "freebsd-install-v1 $generation booted ok\n", 'IPv4-mapped source can report first boot');
is_deeply(\@requests, [
    {command => ['updatenodestat'], node => ['node1'], arg => ['installing']},
    {command => ['nodeset'], node => ['node1'], arg => ['boot']},
    {command => ['updatenodestat'], node => ['node1'], arg => ['installed']},
    {command => ['updatenodestat'], node => ['node1'], arg => ['booted']},
], 'completion changes boot policy before installed status');
status($directory, $generation, 'booted', sub { die 'must not run'; });
status($directory, $generation, 'complete', sub { die 'must not run'; });
is($xCAT::Table::entries{nodelist}{node1}{status}, 'booted', 'duplicate completion preserves first-boot status');

for my $peer ('192.0.2.11', '', 'node1', '2001:db8::10') {
    my ($root, $token) = fixture();
    rejected(sub { status($root, $token, 'begin', sub { die 'must not run'; }, $peer); },
        qr/Unexpected installation client/, 'incorrect source');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'prepared',
        'source mismatch leaves the generation unclaimed');
}
{
    my ($root, $token) = fixture();
    local $xCAT::NetworkUtils::address = 0;
    rejected(sub { status($root, $token, 'begin'); }, qr/Unexpected installation client/, 'unresolved node address');
}

for my $failure (
    ['top-level error', {error => ['cannot write']}],
    ['top-level error code', {errorcode => [0, 1]}],
    ['node error', {node => [{name => ['node1'], error => ['cannot write']}]}],
    ['later node error', {node => [{name => ['node1']}, {name => ['node1'], errorcode => [1]}]}],
    ['nested response error', {xcatresponse => [{node => [{errorcode => [1]}]}]}],
    ['missing response', undef],
    ['invalid response', []],
    ['invalid node record', {node => [undef, {errorcode => [1]}]}],
    ['invalid node container', {node => {errorcode => [1]}}],
) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin');
    my @seen;
    rejected(sub { status($root, $token, 'complete', sub {
        push @seen, $_[0]->{command}[0];
        return $failure->[1];
    }); }, qr/failed|response/, $failure->[0]);
    is_deeply(\@seen, ['nodeset'], 'failed boot command prevents installed status');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'completing',
        'boot command error leaves completion retryable');
    status($root, $token, 'complete');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'installed',
        'retry after command recovery completes');
}

for my $phase (qw(begin complete booted failed)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin') if $phase eq 'complete' || $phase eq 'booted';
    status($root, $token, 'complete') if $phase eq 'booted';
    rejected(sub { status($root, $token, $phase, sub {
        return dispatch($_[0]) if $_[0]->{command}[0] eq 'nodeset';
        return {errorcode => [1]};
    }); }, qr/updatenodestat failed/, "$phase status command error");
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase},
        {begin => 'installing', complete => 'completing', booted => 'installed', failed => 'failed'}->{$phase},
        "$phase status error does not commit successful completion");
}

for my $missed (qw(nodeset updatenodestat)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin');
    my @seen;
    rejected(sub { status($root, $token, 'complete', sub {
        push @seen, $_[0]->{command}[0];
        return {} if $_[0]->{command}[0] eq $missed;
        return dispatch($_[0]);
    }); }, qr/was not updated/, "$missed silent write failure");
    is(scalar(@seen), $missed eq 'nodeset' ? 1 : 2, 'failed readback stops the command sequence');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'completing',
        'readback failure remains retryable');
}
{
    my ($root, $token) = fixture();
    local $xCAT::Table::unavailable = 1;
    rejected(sub { status($root, $token, 'begin'); }, qr/Cannot read nodelist/, 'database unavailable');
}
{
    my ($root, $token) = fixture();
    rejected(sub { status($root, $token, 'begin', sub { die "dispatcher failed\n"; }); },
        qr/dispatcher failed/, 'dispatcher exception');
}

done_testing();
