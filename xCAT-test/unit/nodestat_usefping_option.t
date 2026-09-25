#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::File qw(repo_path);
use File::Temp qw(tempdir);
use Getopt::Long ();
use Storable qw(dclone);
use Test::More;

BEGIN {
    $INC{"xCAT/$_.pm"} = __FILE__
      for qw(NetworkUtils Utils TableUtils ServiceNodeUtils);
}

{
    package xCAT::Utils;
    sub Version { return 'fixture version'; }

    package xCAT::MsgUtils;
    sub message {
        my ($class, $severity, $response, $callback) = @_;
        die "Unexpected message severity: $severity" unless $severity eq 'I';
        $callback->($response);
    }
}

local $ENV{XCATROOT} = tempdir(CLEANUP => 1);
local $ENV{POSIXLY_CORRECT};
delete $ENV{POSIXLY_CORRECT};
my $global_def = repo_path('perl-xCAT/xCAT/GlobalDef.pm');
require $global_def;
$INC{'xCAT/GlobalDef.pm'} = $global_def;
my $plugin = repo_path('xCAT-server/lib/xcat/plugins/nodestat.pm');
require $plugin;

my @probes;
my $probe = sub {
    my ($backend, $request, $callback, $doreq, $nodes, $services) = @_;
    push @probes, { backend => $backend, nodes => dclone($nodes),
        services => dclone($services) };
    return { node01 => { status => 'ping', appstatus => 'sshd', appsd => 'sshd=up' } };
};

no warnings qw(once redefine);
local *xCAT_plugin::nodestat::process_request_nmap = sub { $probe->('nmap', @_); };
local *xCAT_plugin::nodestat::process_request_port = sub { $probe->('fping', @_); };
local @ARGV;
local ($::MON, $::QUIET, $::UPDATE, $::POWER, $::USEFPING, $::HELP, $::VERSION);

my $has_system_nmap = -x '/usr/bin/nmap' ? 1 : 0;
diag($has_system_nmap ? '/usr/bin/nmap executable: backend selection is exercised'
    : '/usr/bin/nmap unavailable: fping fallback only; backend selection is not exercised');

my @cases = (
    [ 'no arguments',       [],                      {} ],
    [ 'short fping',        ['-f'],                  { f => 1 } ],
    [ 'long fping',         ['--usefping'],           { f => 1 } ],
    [ 'legacy fping name',  ['--useping'],            { f => 1 } ],
    [ 'short monitoring',   ['-m'],                  { mon => 1 } ],
    [ 'long monitoring',    ['--usemon'],            { mon => 1 } ],
    [ 'use abbreviation',   ['--use'],               { mon => 1 } ],
    [ 'us abbreviation',    ['--us'],                { mon => 1 } ],
    [ 'monitor then fping', ['-mf'],                 { mon => 1, f => 1 } ],
    [ 'fping then monitor', ['-fm'],                 { mon => 1, f => 1 } ],
    [ 'separate options',   ['--usemon', '--usefping'], { mon => 1, f => 1 } ],
    [ 'short update',       ['-u'],                  { update => 1 } ],
    [ 'long update',        ['--updatedb'],          { update => 1 } ],
    [ 'short quiet',        ['-q'],                  { quiet => 1 } ],
    [ 'long quiet',         ['--quiet'],             { quiet => 1 } ],
    [ 'short power',        ['-p'],                  { power => 1 } ],
    [ 'long power',         ['--powerstat'],         { power => 1 } ],
    [ 'all short options',  ['-muqpf'],              { mon => 1, update => 1, quiet => 1, power => 1, f => 1 } ],
    [ 'missing arg field',  undef,                   {} ],
);

for my $case (@cases) {
    my ($name, $args, $flags) = @$case;
    subtest $name => sub {
        Getopt::Long::Configure('default', 'pass_through');
        ($::MON, $::QUIET, $::UPDATE, $::POWER, $::USEFPING, $::HELP, $::VERSION) = (1) x 7;
        my $request = { command => ['nodestat'], node => ['node01'] };
        $request->{arg} = [@$args] if defined $args;
        my @responses;
        @probes = ();
        my $callback = sub { push @responses, dclone($_[0]); };
        my $result = xCAT_plugin::nodestat::preprocess_request($request, $callback);
        my $expected = dclone($request);
        $expected->{$_} = [$flags->{$_} || 0] for qw(mon update quiet power);
        is_deeply($result, [$expected], 'preprocessor returns the requested flags');
        is_deeply($request->{node}, ['node01'], 'node selection is retained');
        is_deeply($request->{arg}, $args, 'original arguments are retained');
        is_deeply(\@responses, [], 'ordinary options do not emit help or errors');
        is_deeply(\@probes, [], 'preprocessing does not probe nodes');

        my $internal = {
            command => ['nodestat_internal'], node => ['node01'],
            portapps => [1], portapps1 => ['sshd'],
            portapps1port => ['22'], portapps1node => ['node01'],
        };
        $internal->{arg} = [@$args] if defined $args;
        $::USEFPING = $flags->{f} ? 0 : 1;
        @ARGV = ('-f');
        # The handler shares Getopt settings with the preprocessor when both run in one daemon process.
        xCAT_plugin::nodestat::process_request($internal, $callback,
            sub { die 'Unexpected subrequest'; });
        my $backend = $flags->{f} || !$has_system_nmap ? 'fping' : 'nmap';
        is_deeply(\@probes, [{ backend => $backend, nodes => ['node01'],
            services => { 22 => 'sshd' } }], 'handler selects the requested probe backend');
        is_deeply(\@responses, [{ node => [{ name => ['node01'],
            data => ['pingXXXXXYYYYYZZZZZsshdXXXXXYYYYYZZZZZsshd=up'] }] }],
            'handler returns the probe result');
    };
}

for my $arg (qw(-f --usefping --useping --use --us)) {
    subtest "strict parser accepts $arg" => sub {
        Getopt::Long::Configure('default');
        my (@responses, @warnings);
        local $SIG{__WARN__} = sub { push @warnings, $_[0]; };
        my $request = { command => ['nodestat'], node => ['node01'], arg => [$arg] };
        my $result = xCAT_plugin::nodestat::preprocess_request($request,
            sub { push @responses, dclone($_[0]); });
        is_deeply($result, [$request], 'recognized option proceeds to dispatch');
        is_deeply(\@responses, [], 'recognized option produces no error response');
        is_deeply(\@warnings, [], 'recognized option produces no parser warning');
    };
}

subtest 'strict parser rejects an unknown option' => sub {
    Getopt::Long::Configure('default');
    my (@responses, @warnings);
    local $SIG{__WARN__} = sub { push @warnings, $_[0]; };
    my $result = xCAT_plugin::nodestat::preprocess_request(
        { command => ['nodestat'], node => ['node01'], arg => ['--not-a-nodestat-option'] },
        sub { push @responses, dclone($_[0]); });
    is($result, 1, 'unrecognized option stops dispatch');
    is_deeply($responses[0]->{errorcode}, [1], 'usage reports the failure');
};

for my $arg (qw(-h --help -v --version)) {
    subtest "$arg without nodes" => sub {
        Getopt::Long::Configure('default', 'pass_through');
        my @responses;
        @probes = ();
        my $result = xCAT_plugin::nodestat::preprocess_request(
            { command => ['nodestat'], arg => [$arg] },
            sub { push @responses, dclone($_[0]); });
        is($result, 0, 'information request succeeds');
        is(scalar @responses, 1, 'one response is returned');
        if ($arg eq '-h' || $arg eq '--help') {
            like(join("\n", @{$responses[0]->{data}}), qr/\Q-f|--usefping\E/,
                'help advertises the accepted fping option');
            like(join("\n", @{$responses[0]->{data}}), qr/\Q-m|--usemon\E/,
                'help advertises the accepted monitoring option');
        } else {
            is_deeply($responses[0]->{data}, ['fixture version'], 'version is returned');
        }
        ok(!exists $responses[0]->{errorcode}, 'information request has no error code');
        is_deeply(\@probes, [], 'information request does not probe nodes');
    };
}

subtest 'missing nodes' => sub {
    Getopt::Long::Configure('default', 'pass_through');
    my @responses;
    my $result = xCAT_plugin::nodestat::preprocess_request(
        { command => ['nodestat'], arg => ['--usefping'] },
        sub { push @responses, dclone($_[0]); });
    is($result, 1, 'missing nodes fail validation');
    is_deeply($responses[0]->{errorcode}, [1], 'usage reports the failure');
};

done_testing();
