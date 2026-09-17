#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw(capture);
use Cwd qw(abs_path getcwd);
use File::Path qw(make_path);
use File::Slurper qw(read_binary read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP qw(decode_json);
use Text::ParseWords qw(shellwords);
use Test::More;
use YAML::PP;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::File qw(repo_path);

my $driver = repo_path('github_action_xcat_test.pl');
my $fixture = repo_path('xCAT-test/unit/fixtures/github_action');
my $runner = abs_path(tempdir(CLEANUP => 1));
my $workspace = "$runner/work";
my $checkout = "$workspace/xcat-core";
my $runner_temp = "$runner/temp";
my $repository = "$checkout/dist/debs/xcat-core";
make_path($repository, $runner_temp);
write_text("$repository/mklocalrepo.sh", "#!/bin/sh\nexit 0\n");
chmod(0755, "$repository/mklocalrepo.sh") or die "chmod repository fixture: $!";

sub run_driver {
    my ($failure, $failed_case) = @_;
    local $ENV{XCAT_TEST_CI_COMMANDS} = "$runner/commands.jsonl";
    local $ENV{XCAT_TEST_CI_FAIL_COMMAND} = defined($failure) ? $failure : '';
    local $ENV{XCAT_TEST_CI_FAIL_CASE} = $failed_case || 0;
    local $ENV{RUNNER_WORKSPACE} = $workspace;
    local $ENV{RUNNER_TEMP} = $runner_temp;
    local $ENV{PWD} = $checkout;
    write_text($ENV{XCAT_TEST_CI_COMMANDS}, '');
    if (-e "$checkout/regression.conf") {
        unlink("$checkout/regression.conf") or die "remove regression fixture: $!";
    }
    my $cwd = getcwd();
    chdir($checkout) or die "chdir checkout: $!";
    my ($stdout, $stderr, $status);
    my $captured = eval {
        ($stdout, $stderr, $status) = capture {
            system($^X, '-I', $fixture, '-MCommands', $driver);
        };
        1;
    };
    my $error = $@;
    chdir($cwd) or die "restore working directory: $!";
    die $error unless $captured;
    my @commands = map { decode_json($_) }
      split /\n/, read_binary($ENV{XCAT_TEST_CI_COMMANDS});
    is($stderr, '', 'driver emits no warnings') or diag($stdout);
    return ($status, \@commands, $stdout);
}

my ($status, $commands, $output) = run_driver();
is($status, 0, 'the full CI driver succeeds with command fixtures') or diag($output);

my @apt = grep { /\bapt-get\b/ } @$commands;
is(scalar @apt, 4, 'the driver updates apt and installs all three packages');
is_deeply(
    [shellwords($apt[0] || '')],
    [qw(sudo timeout 600 apt-get -qq -o Acquire::Retries=3 -o Acquire::http::Timeout=30
        --allow-insecure-repositories update 2>&1)],
    'apt update has a time limit and bounded network retries',
);
my @packages = qw(xcat xcat-probe xcat-test);
for my $index (0 .. $#packages) {
    is_deeply(
        [shellwords($apt[$index + 1] || '')],
        [qw(sudo timeout 1200 env DEBIAN_FRONTEND=noninteractive apt-get
            -o Acquire::Retries=3 -o Acquire::http::Timeout=30 install -y),
            $packages[$index], qw(--allow-remove-essential --allow-unauthenticated 2>&1)],
        "$packages[$index] installation is noninteractive and bounded",
    );
}

my @checked = grep { /\bperl .* -c / } @$commands;
my @expected_files = (
    '/opt/xcat/lib/perl/xCAT/Example.pm',
    '/opt/xcat/share/xcat/tools/autotest/unit-extra/example.pl',
    '/opt/xcat/probe-extra/example.pl',
    '/opt/xcat/share/xcat/netboot/genesis-extra/example.pl',
    '/install/postscripts/example',
);
is_deeply(
    \@checked,
    [map { "sudo bash -c '. /etc/profile.d/xcat.sh && perl -I /opt/xcat/lib/perl -I /opt/xcat/lib -I /usr/lib/perl5 -I /usr/share/perl -c $_' 2>&1" } @expected_files],
    'syntax checks exclude payloads, installed unit tests, and non-Perl files',
);
ok(grep(/xcattest -f .* -t example_case/, @$commands),
    'the successful driver reaches the regression case');
like(read_text("$checkout/regression.conf"), qr/^MN=ci-node$/m,
    'the regression configuration uses the reported hostname');
ok(!-e "$workspace/regression.conf", 'changing directory does not change the configuration destination');

my $unitsrc = "$runner_temp/xcat-core-unitsrc";
my $preserve = "rm -rf $unitsrc && cp -a $checkout $unitsrc 2>&1";
my $build = 'sudo ./builddebs.pl --force 2>&1';
my $unit = "cd $unitsrc && prove -r xCAT-test/unit 2>&1";
my $bats = "cd $unitsrc && bats -r xCAT-test/bats 2>&1";
is_deeply([grep { $_ eq $preserve || $_ eq $build || $_ eq $unit || $_ eq $bats } @$commands],
    [$preserve, $build, $unit, $bats],
    'the source is preserved before building and both suites use the preserved tree');

for my $stage (
    ['apt update', $apt[0]], ['xcat install', $apt[1]], ['xcat-test install', $apt[3]],
    ['source preservation', $preserve], ['package build', $build],
    ['unit tests', $unit], ['BATS tests', $bats],
) {
    my ($name, $failure) = @$stage;
    subtest "stop after failed $name" => sub {
        my ($index) = grep { defined($failure) && $commands->[$_] eq $failure } 0 .. $#$commands;
        ok(defined($index), 'the command was reached in the successful run') or return;
        my ($failed_status, $failed_commands) = run_driver($failure);
        is($failed_status, 256, 'the driver reports failure');
        is_deeply($failed_commands, [@$commands[0 .. $index]],
            'no later command runs after the failed operation');
    };
}

my @setup_steps = grep { /setup-local-client\.sh/ } @$commands;
is(scalar @setup_steps, 1, 'local client setup runs once');
for my $stage (
    ['local client setup', $setup_steps[0]], ['xcat-probe install', $apt[2]],
) {
    my ($name, $failure) = @$stage;
    subtest "finish installation checks after failed $name" => sub {
        ok(defined($failure), 'the command was reached in the successful run') or return;
        my ($failed_status, $failed_commands) = run_driver($failure);
        is($failed_status, 256, 'the driver reports installation failure');
        my ($index) = grep { defined($apt[2]) && $commands->[$_] eq $apt[2] } 0 .. $#$commands;
        ok(defined($index), 'the probe installation ends the checks') or return;
        is_deeply($failed_commands, [@$commands[0 .. $index]],
            'installation completes its checks but does not start unit tests');
    };
}

subtest 'a syntax error does not suppress later file checks' => sub {
    ok(@checked, 'the successful run checked Perl files') or return;
    my ($failed_status, $failed_commands) = run_driver($checked[0]);
    is($failed_status, 256, 'the driver reports syntax failure');
    is_deeply([grep { /\bperl .* -c / } @$failed_commands], \@checked,
        'all eligible files are checked after the first error');
    ok(!grep(/\bapt-get .*install -y xcat-test\b/, @$failed_commands),
        'regression installation does not run after a syntax error');
};

subtest 'a failed regression case fails the driver' => sub {
    my ($failed_status, $failed_commands, $failed_output) = run_driver(undef, 1);
    is($failed_status, 256, 'the driver reports regression failure');
    is_deeply($failed_commands, $commands, 'the regression case runs after all prerequisite checks');
    like($failed_output, qr/FailedCases: example_case\./, 'the failing case is reported');
};

subtest 'installation requires the built repository' => sub {
    rename("$repository/mklocalrepo.sh", "$repository/mklocalrepo.saved") or die "hide repository fixture: $!";
    my ($failed_status, $failed_commands, $failed_output) = run_driver();
    rename("$repository/mklocalrepo.saved", "$repository/mklocalrepo.sh") or die "restore repository fixture: $!";
    is($failed_status, 256, 'the driver reports a missing repository');
    ok(!grep(/\bapt-get\b/, @$failed_commands), 'apt does not run without the repository');
    like($failed_output, qr/the build produced no apt repository/, 'the missing repository is reported');
};

my $workflow = YAML::PP->new->load_file(repo_path('.github/workflows/xcat_test.yml'));
my @dependency_steps = grep { ($_->{name} || '') eq 'Install dependencies' }
  @{ $workflow->{jobs}{xcat_pr_test}{steps} };
is(scalar @dependency_steps, 1, 'the CI job has one dependency installation step');
my @dependency_command = shellwords($dependency_steps[0]{run} || '');
is_deeply([@dependency_command[0 .. 5]],
    [qw(sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y)],
    'the parsed workflow dependency command is noninteractive');

done_testing();
