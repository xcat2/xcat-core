#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use XCAT::Test::PostageFixture ();
use xCAT::FreeBSDPostscript;

umask 0077;
my $root = tempdir(CLEANUP => 1);
my ($generation, $attempt, $run) = map { $_ x 32 } qw(a b c);
my ($boot, $snapshot, $older) = map { $_ x 64 } qw(d e f);
my $number = 0;

sub observation {
    my (%changes) = @_;
    my %record = (format => 'xcat-freebsd-boot-context-1', node => 'node1',
        generation => $generation, attempt => $attempt, boot => $boot, run => $run,
        snapshot => $snapshot, 'run-boot' => $boot, outcome => 'admitted', complete => 'no', released => 'no', %changes);
    return join('', map { "$_\t$record{$_}\n" }
        qw(format node generation attempt boot run snapshot run-boot outcome complete released));
}

sub observe {
    my ($bytes, $requested, $filter, $directory) = @_;
    $directory = "$root/probe-" . ++$number unless defined($directory);
    my $result = xCAT::FreeBSDPostscript::observe_boot('node1', $generation, $attempt, $requested,
        sub {
            my ($request, $callback) = @_;
            is_deeply($request, { command => ['xdsh'], node => ['node1'], _xcatpreprocessed => [1],
                arg => ['--nodestatus', '-t', '20', "/usr/local/libexec/xcat-postscript boot-context $generation $attempt $requested"] },
                'authenticated transport receives a bounded observation command');
            my @lines = (map { "node1: $_" } split(/\n/, $bytes));
            push @lines, 'node1: Remote_command_successful';
            my $response = { data => [join("\n", @lines)] };
            $filter->($response) if $filter;
            $callback->($response);
            return;
        }, directory => $directory);
    open(my $file, '<', "$result->{directory}/context") or die $!;
    is(do { local $/; <$file> }, $bytes, 'validated observation is retained verbatim');
    close($file) or die $!;
    ok(-s "$result->{directory}/context.request.json" && -s "$result->{directory}/context.responses.json",
        'request and transport responses are retained');
    return $result;
}

subtest 'boot observation accepts only bound native states' => sub {
    for my $outcome (qw(admitted pending uncertain success failed absent incomplete)) {
        my %record = (outcome => $outcome, complete => $outcome =~ /success|failed/ ? 'yes' : 'no');
        @record{qw(snapshot run-boot)} = ('-', '-') if $outcome eq 'absent' || $outcome eq 'incomplete';
        my $result = observe(observation(%record), $run);
        is($result->{outcome}, $outcome, "$outcome reaches the caller");
    }
    is(observe(observation(run => '-', outcome => 'absent', snapshot => '-', 'run-boot' => '-'), '-')->{run}, '-',
        'initial boot can query the installation without a run');
    is(observe(observation(outcome => 'uncertain', released => 'yes', 'run-boot' => $older), $run)->{released}, 'yes',
        'explicit release remains an uncertain outcome');
    is(observe(observation(outcome => 'uncertain', released => 'yes'), $run)->{released}, 'yes',
        'worker-verified same-boot release remains uncertain');
    done_testing();
};

subtest 'unchanged polls reuse the retained boot observation' => sub {
    my $directory = "$root/repeated";
    my $first = observe(observation(), $run, undef, $directory);
    for my $poll (1 .. 8) {
        my $result = observe(observation(), $run, sub {
            my @stages = glob("$directory/.boot-node1.*");
            is(scalar(@stages), 1, 'one transient observation exists during transport');
            ok(-s "$stages[0]/context.request.json", 'request remains available during the callback');
        }, $directory);
        is($result->{directory}, $first->{directory}, 'unchanged state returns the original evidence directory');
        is_deeply([glob("$directory/.boot-node1.*")], [], 'successful observation leaves no transient stage');
    }
    my $changed = observe(observation(outcome => 'pending'), $run, undef, $directory);
    isnt($changed->{directory}, $first->{directory}, 'a changed state retains separate evidence');
    is_deeply([sort glob("$directory/*")], [sort($first->{directory}, $changed->{directory})],
        'retention grows with observed states rather than poll count');
    ok(-s "$first->{directory}/context", 'the earlier observation remains readable');

    my $ok = eval {
        observe(observation(), $run, sub { $_[0]{errorcode} = [1]; }, $directory);
        1;
    };
    ok(!$ok, 'transport failure is still rejected');
    my @failed = glob("$directory/.boot-node1.*");
    is(scalar(@failed), 1, 'failed observation keeps its diagnostic stage');
    ok(-s "$failed[0]/context.responses.json", 'failed transport responses remain available');
    is(observe(observation(), $run, undef, $directory)->{directory}, $first->{directory},
        'retry reuses the successful observation');
    is_deeply([glob("$directory/.boot-node1.*")], \@failed, 'retry preserves the failed stage');
    done_testing();
};

subtest 'near matches and malformed observations fail closed' => sub {
    for my $changes (
        { node => 'node2' }, { generation => '1' x 32 }, { attempt => '2' x 32 },
        { boot => 'invalid' }, { run => '3' x 32 }, { format => 'unknown' },
        { snapshot => '-' }, { 'run-boot' => '-' }, { outcome => 'unknown' },
        { complete => 'yes' }, { outcome => 'success' }, { outcome => 'failed' },
        { released => 'yes' }, { released => 'maybe' },
        { outcome => 'pending', 'run-boot' => $older },
        { outcome => 'absent' }, { outcome => 'absent', snapshot => '-', 'run-boot' => $boot },
    ) {
        my $ok = eval { observe(observation(%$changes), $run); 1 };
        ok(!$ok, 'invalid binding is rejected: ' . encode_json($changes));
        like($@, qr/(?:Invalid|differs)/, 'rejection identifies the observation');
    }
    for my $bytes (observation() . "extra\tvalue\n", observation() . "boot\t$boot\n", substr(observation(), 0, -2)) {
        my $ok = eval { observe($bytes, $run); 1 };
        ok(!$ok, 'noncanonical fields are rejected');
    }
    my $ok = eval { observe(observation(run => '-'), '-'); 1 };
    ok(!$ok, 'a request without a run cannot describe an admitted execution');
    $ok = eval { observe(observation(run => '-', outcome => 'incomplete', snapshot => '-', 'run-boot' => '-'), '-'); 1 };
    ok(!$ok, 'incomplete delivery must identify a saved run');
    for my $filter (
        sub { $_[0]{errorcode} = [1] },
        sub { $_[0]{data}[0] =~ s/Remote_command_successful// },
        sub { $_[0]{data}[0] =~ s/node1:/node2:/ },
    ) {
        my $accepted = eval { observe(observation(), $run, $filter); 1 };
        ok(!$accepted, 'transport failures cannot attest a boot');
    }
    done_testing();
};

subtest 'invalid requests do not dispatch' => sub {
    for my $arguments (['node1', 'bad', $attempt, $run], ['node1', $generation, 'bad', $run],
        ['node1', $generation, $attempt, 'bad'], ['../node1', $generation, $attempt, $run]) {
        my $called = 0;
        my $ok = eval { xCAT::FreeBSDPostscript::observe_boot(@$arguments, sub { ++$called }, directory => $root); 1 };
        ok(!$ok, 'malformed request rejected');
        is($called, 0, 'no remote command issued');
    }
    done_testing();
};

done_testing();
