#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Carp qw(croak);
use Storable qw(dclone);
use Symbol qw(gensym);
use Test::More;
use XCAT::Test::PostageFixture qw(fixture);
use xCAT::FreeBSDUpdate;

BEGIN { $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__; }
my $plugin = $ENV{XCAT_UPDATENODE_PLUGIN} || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/updatenode.pm";
require $plugin;

my (@responses, @legacy);
my $callback = sub { push @responses, dclone(shift); return; };
my $subrequest = sub { croak 'Unexpected remote operation during routing'; };
my $legacy_result;
{
    no warnings qw(redefine once);
    *xCAT_plugin::updatenode::_preprocess_updatenode_legacy = sub {
        my $request = shift;
        push @legacy, dclone($request);
        return $legacy_result;
    };
    *xCAT_plugin::updatenode::_updatenode_legacy = sub {
        my $request = shift;
        push @legacy, dclone($request);
        return 7;
    };
    *xCAT::NetworkUtils::getipaddr = sub { return $_[1]; };
    *xCAT::NetworkUtils::my_ip_facing = sub { return (0, '192.0.2.1'); };
    *xCAT::NetworkUtils::thishostisnot = sub { return $_[1] ne '192.0.2.1'; };
}

sub reset_fixture {
    fixture(1);
    @responses = ();
    @legacy = ();
    $legacy_result = [{ command => ['legacy-result'] }];
    push @{$xCAT::Table::rows{nodetype}},
      { node => 'linux1', os => 'rhels10', provmethod => 'install' },
      { node => 'aix1', os => 'AIX', provmethod => 'install' },
      { node => 'node2', os => 'freebsd15.1', provmethod => 'image1' },
      { node => 'image-only', provmethod => 'image1' };
    @{$xCAT::Table::rows{osimage}[0]}{qw(imagetype osname osvers osarch provmethod)}
      = qw(freebsd FreeBSD freebsd15.1 x86_64 install);
    $xCAT::Table::rows{noderes} = [
        { node => 'node1', xcatmaster => '192.0.2.1' },
        { node => 'node2', xcatmaster => '198.51.100.1' },
        { node => 'image-only', xcatmaster => '192.0.2.1' } ];
    return;
}

sub request {
    my ($nodes, @arguments) = @_;
    return { command => ['updatenode'], node => $nodes, arg => \@arguments,
        username => ['root'], _xcatpreprocessed => [0], context => [{ preserved => ['value'] }] };
}

sub preprocess {
    return xCAT_plugin::updatenode::preprocess_request(shift, $callback, $subrequest);
}

sub errors { return [map { @{$_->{error} || []} } @responses]; }

subtest 'Linux and AIX requests retain their legacy contract' => sub {
    reset_fixture();
    my $request = request(['aix1', 'linux1'], '-F', '-S', '-P', 'syslog');
    my $before = dclone($request);
    is_deeply(preprocess($request), $legacy_result, 'legacy preprocessing result is unchanged');
    is_deeply(\@legacy, [$before], 'legacy preprocessing receives every original field and node');
    is_deeply($request, $before, 'partitioning does not mutate the caller');
    is_deeply(errors(), [], 'no native option error is introduced');
    @legacy = ();
    is(xCAT_plugin::updatenode::process_request($request, $callback, $subrequest), 7,
        'legacy processing return code is unchanged');
    is_deeply(\@legacy, [$before], 'legacy processing receives original request');
    $legacy_result = undef;
    is(preprocess($request), undef, 'completed inline legacy preprocessing may return no requests');
    is_deeply(errors(), [], 'inline completion is not treated as failure');
    done_testing();
};

subtest 'mixed requests split before legacy preprocessing and preserve order' => sub {
    reset_fixture();
    my $request = request(['linux1', 'node1', 'aix1', 'node2'], '-P', 'custom "two words" ""');
    my $before = dclone($request);
    my $routed = preprocess($request);
    is_deeply($request, $before, 'the original mixed request is unchanged');
    is_deeply($legacy[0]{node}, ['linux1', 'aix1'], 'only Linux and AIX reach the legacy side-effect owner');
    is_deeply($legacy[0]{arg}, $before->{arg}, 'legacy arguments preserve quotes and empty values');
    is(scalar(@$routed), 3, 'two native owners and the legacy request are returned');
    is_deeply($routed->[0]{node}, ['node1'], 'local native owner gets its node');
    ok(!exists($routed->[0]{_xcatdest}), 'local owner needs no remote destination');
    is_deeply($routed->[1]{node}, ['node2'], 'remote native owner gets its node');
    is($routed->[1]{_xcatdest}, '198.51.100.1', 'remote destination uses the xcatmaster owner');
    is_deeply($routed->[1]{arg}, $before->{arg}, 'native script arguments remain opaque');
    is_deeply($routed->[1]{_xcatpreprocessed}, [1], 'native owner receives a preprocessed request');
    is_deeply($routed->[2], $legacy_result->[0], 'legacy handler retains its own dispatch result');
    is_deeply(errors(), [], 'mixed script request is valid');
    done_testing();
};

subtest 'native classification covers image identity and unsupported FreeBSD versions' => sub {
    reset_fixture();
    $xCAT::Table::rows{nodetype}[0]{os} = 'FreeBSD16.0';
    my $routed = preprocess(request(['node1', 'image-only', 'node1'], '-P'));
    is_deeply($routed->[0]{node}, ['node1', 'image-only'], 'FreeBSD image and version stay out of Linux dispatch');
    is_deeply(\@legacy, [], 'unsupported native versions cannot reach legacy side effects');
    is_deeply(errors(), [], 'version acceptance remains the native preparation owner responsibility');
    done_testing();
};

subtest 'invalid native requests cause no legacy or remote operation' => sub {
    for my $arguments (['--freebsd-run', 'a' x 32, '-P', 'custom'],
        ['--freebsd-run', 'a' x 32, '-F'],
        ['--freebsd-run', 'a' x 32, '-S'],
        ['--freebsd-release'], ['--freebsd-run', '../invalid'], ['-P', 'custom', '-t', '0'],
        ['-P', 'custom', '-t', '7201'], ['-P', 'custom', 'extra']) {
        reset_fixture();
        my $result = preprocess(request(['node1', 'linux1'], @$arguments));
        ok(!defined($result), 'invalid options produce no dispatch request');
        ok(@{errors()}, 'the command reports the rejection');
        is_deeply(\@legacy, [], 'legacy work has not started');
    }
    reset_fixture();
    preprocess(request(['node1', 'node2'], '--freebsd-run', 'a' x 32));
    like(join('', @{errors()}), qr/one[ ]FreeBSD[ ]node/x, 'retained run cannot target several nodes');
    reset_fixture();
    preprocess(request(['node1', 'linux1'], '--freebsd-run', 'a' x 32));
    like(join('', @{errors()}), qr/other[ ]operating[ ]systems/x, 'retained run cannot include a legacy node');
    is_deeply(\@legacy, [], 'mixed retry has no legacy effect');
    done_testing();
};

subtest 'retained release and implicit script-list requests route without execution' => sub {
    reset_fixture();
    my $routed = preprocess(request(['node1'], '--freebsd-run', 'a' x 32, '--freebsd-release'));
    is_deeply($routed->[0]{arg}, ['--freebsd-run', 'a' x 32, '--freebsd-release'], 'release remains an explicit operator request');
    is_deeply(errors(), [], 'release routing succeeds');
    reset_fixture();
    $routed = preprocess(request(['node1'], 'custom "two words" ""'));
    is_deeply($routed->[0]{arg}, ['custom "two words" ""'], 'implicit script selection is preserved');
    is_deeply(errors(), [], 'implicit selection is accepted');
    done_testing();
};

subtest 'help and malformed internal requests do not execute scripts' => sub {
    reset_fixture();
    is_deeply(preprocess(request(['node1'], '--help')), [], 'native help creates no worker request');
    ok(@responses, 'native help returns usage');
    is_deeply(errors(), [], 'help is not failure');
    reset_fixture();
    my $request = request(['node1'], '--freebsd-release');
    $request->{_xcatpreprocessed} = [1];
    is(xCAT_plugin::updatenode::process_request($request, $callback, $subrequest), 1,
        'process entry validates already-preprocessed options');
    is_deeply(\@legacy, [], 'internal requests cannot send native nodes to legacy processing');
    ok(@{errors()}, 'invalid internal request reports failure');
    done_testing();
};

subtest 'unresolved native owners prevent partial mixed dispatch' => sub {
    reset_fixture();
    $xCAT::Table::rows{noderes}[1]{xcatmaster} = 'unresolved-owner';
    my $routed = preprocess(request(['node1', 'linux1', 'node2'], '-P', 'custom'));
    ok(!defined($routed), 'no native request escapes an incomplete ownership map');
    like(join('', @{errors()}), qr/Missing[ ]FreeBSD[ ]update[ ]owner/x, 'missing owner is explicit');
    is_deeply(\@legacy, [], 'legacy operations have not started');
    done_testing();
};

subtest 'native file synchronization routes independently and with scripts' => sub {
    for my $arguments (['-F'], ['--sync'], ['-F', '-P', 'custom'], ['--sync', '--scripts', 'custom']) {
        reset_fixture();
        my $request = request(['node1', 'linux1', 'aix1'], @$arguments);
        my $routed = preprocess($request);
        is_deeply(errors(), [], 'file synchronization options are supported');
        is_deeply($routed->[0]{node}, ['node1'], 'native file synchronization has its own owner');
        is_deeply($routed->[0]{arg}, $arguments, 'native options remain intact');
        is_deeply($legacy[0]{node}, ['linux1', 'aix1'], 'legacy systems keep their existing file synchronization path');
        is_deeply($legacy[0]{arg}, $arguments, 'legacy options remain intact');
    }
    done_testing();
};

subtest 'software options preserve native and legacy routing' => sub {
    for my $arguments (['-S'], ['--sw'], ['-FSP'], ['-S', '-P', 'node-postbootscripts-start-here']) {
        reset_fixture();
        my $routed = preprocess(request(['node1', 'linux1', 'aix1'], @$arguments));
        is_deeply(errors(), [], 'software update options are supported');
        is_deeply($routed->[0]{arg}, $arguments, 'native request keeps exact options');
        is_deeply($legacy[0]{node}, ['linux1', 'aix1'], 'only native nodes leave the legacy path');
        is_deeply($legacy[0]{arg}, $arguments, 'Linux and AIX keep exact software options');
    }
    done_testing();
};

sub timeout_spellings {
    for my $option (qw(-t --timeout --timetout)) {
        reset_fixture();
        my $arguments = ['-P', 'custom', $option, '10'];
        my $routed = preprocess(request(['node1'], @$arguments));
        is_deeply(errors(), [], "$option accepts a valid timeout");
        is(ref($routed), 'ARRAY', 'valid timeout routes the request');
        is_deeply($routed->[0]{arg}, $arguments, 'routed request keeps the exact arguments') if $routed;
        for my $value (0, 7201) {
            reset_fixture();
            ok(!defined(preprocess(request(['node1'], '-P', 'custom', $option, $value))),
                "$option rejects an out-of-range timeout");
            like(join('', @{errors()}), qr/Invalid[ ]FreeBSD[ ]update[ ]timeout/x, 'timeout range error is explicit');
        }
    }
    done_testing();
    return;
}

subtest 'native timeout spellings keep the client contract' => \&timeout_spellings;

require xCAT::FreeBSDPostscript;
require xCAT::FreeBSDInstall;
my (@events, @updates, $preparation, $fault);
    local *xCAT::FreeBSDInstall::state = gensym();
    *xCAT::FreeBSDInstall::state = sub { return { phase => 'booted' }; };
    local *xCAT::TableUtils::setUpdateStatus = gensym();
    *xCAT::TableUtils::setUpdateStatus = sub { push @updates, [@{$_[1]}, $_[2]]; return; };
    local *xCAT::FreeBSDPostscript::prepare_update = gensym();
    *xCAT::FreeBSDPostscript::prepare_update = sub {
        my ($node, $selection, @options) = @_;
        push @events, ['prepare', $selection, @options];
        ++$preparation;
        croak 'Fixture second preparation failure' if $fault eq 'prepare' && $preparation == 2;
        return { node => $node, binding => { run => sprintf('%032x', $preparation) } };
    };
    local *xCAT::FreeBSDPostscript::read_export = gensym();
    *xCAT::FreeBSDPostscript::read_export = sub {
        push @events, ['read', $_[0]];
        return { node => $fault eq 'node' ? 'node2' : 'node1', binding => { run => $_[0] } };
    };
    local *xCAT::FreeBSDPostscript::release_execution = gensym();
    *xCAT::FreeBSDPostscript::release_execution = sub {
        push @events, ['release', $_[0]];
        croak 'Fixture release refused' if $fault eq 'release';
        return;
    };
    local *xCAT::FreeBSDPostscript::sync_files = gensym();
    *xCAT::FreeBSDPostscript::sync_files = sub {
        push @events, ['sync', $_[0], @_[3 .. $#_]];
        return { lists => 1, directory => '/fixture/sync' };
    };
    local *xCAT::FreeBSDPostscript::deliver_execution = gensym();
    *xCAT::FreeBSDPostscript::deliver_execution = sub {
        push @events, ['deliver', $_[0], @_[2 .. $#_]];
        croak 'Fixture delivery failure' if $fault eq 'deliver';
        return { complete => 'no', outcome => 'uncertain' } if $fault eq 'uncertain-collect' || $fault eq 'framework-logs';
        return { complete => 'yes', outcome => 'success' };
    };
    local *xCAT::FreeBSDPostscript::collect_execution = gensym();
    *xCAT::FreeBSDPostscript::collect_execution = sub {
        push @events, ['collect', $_[0]];
        croak 'Fixture collection failure' if $fault eq 'collect' || $fault eq 'uncertain-collect';
        my $archive = { path => "/fixture/report-$_[0]/archive.tar" };
        if ($fault eq 'capture') {
            return { archive => $archive, receipt => { complete => 'yes', outcome => 'success' },
                entries => [{ ordinal => 1, script => 'custom', phase => 'postscripts', status => 0,
                    stdout => { bytes => 4096, limit => 4096, truncated => 1, open_after_exit => 0 },
                    stderr => { bytes => 0, limit => 4096, truncated => 0, open_after_exit => 1 } }] };
        }
        if ($fault eq 'interrupted-logs' || $fault eq 'package-recovery' || $fault eq 'package-preservation' || $fault eq 'framework-logs') {
            return { kind => 'freebsd-postscript-report-v2', archive => $archive,
                receipt => { complete => 'no', outcome => 'uncertain' },
                $fault eq 'package-recovery' ? (package_recovery => { scope => 'provenance-only', execution => 'uncertain' }) : (),
                $fault eq 'package-preservation' ? (package_preservation => { scope => 'previous-provenance', execution => 'uncertain' }) : (),
                $fault eq 'framework-logs' ? (framework_logs => {
                    'framework.stderr' => { path => '/fixture/report/framework.stderr' } }) : (),
                prerequisite_logs => { stderr => { path => '/fixture/report/prerequisite.stderr' } },
                entries => [{ ordinal => 1, script => 'custom', phase => 'postscripts', state => 'not-run' }] };
        }
        if ($fault eq 'rejection') {
            return { kind => 'freebsd-postscript-report-v3', archive => $archive,
                receipt => { complete => 'yes', outcome => 'failed' },
                prerequisite => { phase => 'native', mode => 'update',
                    stderr => { path => '/fixture/report/prerequisite.stderr' } },
                entries => [{ ordinal => 1, name => 'custom', state => 'not-run' }] };
        }
        return { archive => $archive, entries => [],
            receipt => { complete => 'yes', outcome => $fault eq 'execute' ? 'failed' : 'success' } };
    };

sub reset_execution {
    reset_fixture();
    @events = ();
    @updates = ();
    $preparation = 0;
    $fault = '';
    return;
}
sub process_native {
    my @arguments = @_;
    return xCAT_plugin::updatenode::process_request(request(['node1'], @arguments), $callback, $subrequest);
}

subtest 'delivery and reporting failures publish failed update status' => sub {
    for my $phase (qw(deliver collect)) {
        reset_execution();
        $fault = $phase;
        is(process_native('-P', 'custom'), 1, "$phase exception reaches the public command");
        is_deeply(\@updates, [['node1', 'syncing'], ['node1', 'failed']],
            "$phase exception clears syncing");
        like(join('', @{errors()}), qr/Fixture[ ](?:delivery|collection)[ ]failure/x,
            'the underlying failure remains visible');
        is(scalar(grep { $_->[0] eq 'deliver' } @events), 1, 'exception does not restart delivery');
    }
    reset_execution();
    is(process_native('-P', 'custom'), 0, 'successful update completes');
    is_deeply(\@updates, [['node1', 'syncing'], ['node1', 'synced']], 'successful update publishes synced');
    done_testing();
};

subtest 'capture limits remain visible in the public script result' => sub {
    reset_execution();
    $fault = 'capture';
    is(process_native('-P', 'custom'), 0, 'truncated successful script retains its status');
    my $output = join('', map { @{$_->{data} || []} } @responses);
    like($output, qr/exit[ ]0;[ ]stdout[ ]truncated[ ]at[ ]4096[ ]bytes/x, 'CLI gives the effective output bound');
    like($output, qr/stderr[ ]remained[ ]open[ ]after[ ]command[ ]exit/x, 'CLI identifies an inherited output pipe');
    done_testing();
};

subtest 'software precedes an independently selected postscript pass' => sub {
    for my $selection ('', 'node-postbootscripts-start-here', q{custom "two words" ""}) {
        reset_execution();
        is(process_native('-F', '-S', '-P', $selection), 0, 'combined operation completes');
        is_deeply([map { $_->[0] } @events], [qw(prepare prepare sync deliver collect deliver collect)],
            'every export is prepared before synchronization and ordered execution');
        is_deeply([@events[0, 1]], [['prepare', 'ospkgs,otherpkgs', require_packages => 1], ['prepare', $selection]],
            'software requires a package update independently of the postscript selection');
        is_deeply($events[2], ['sync', 'node1', 'username', ['root']], 'synchronization retains the authenticated caller');
        is_deeply($events[3], ['deliver', sprintf('%032x', 1), 'username', ['root']], 'software is delivered first');
        is_deeply($events[5], ['deliver', sprintf('%032x', 2), 'username', ['root']], 'postscript pass is delivered second');
        is_deeply(errors(), [], 'successful execution reports no error');
    }
    reset_execution();
    is(process_native('--sw'), 0, 'software-only operation completes');
    is_deeply([map { $_->[0] } @events], [qw(prepare deliver collect)], 'software-only has one ordered run');
    done_testing();
};

sub busy_node_wait {
    for my $remains_busy (0, 1) {
        reset_execution();
        my ($polls, $clock) = (0, 0);
        my $deliver = \&xCAT::FreeBSDPostscript::deliver_execution;
        local *xCAT::FreeBSDPostscript::deliver_execution = gensym();
        *xCAT::FreeBSDPostscript::deliver_execution = sub {
            ++$polls;
            return $deliver->(@_) if !$remains_busy && $polls > 2;
            push @events, ['busy', $_[0]];
            return { complete => 'no', outcome => 'busy' };
        };
        local *xCAT::FreeBSDUpdate::clock_gettime = gensym();
        *xCAT::FreeBSDUpdate::clock_gettime = sub { return $clock; };
        local *xCAT::FreeBSDUpdate::sleep = gensym();
        *xCAT::FreeBSDUpdate::sleep = sub { $clock += $_[0]; return; };
        is(process_native('-P', 'custom', '-t', '2'), $remains_busy,
            'the public command distinguishes completion from a busy timeout');
        is($polls, 3, 'contention is retried within the existing deadline');
        is($preparation, 1, 'polling does not prepare another run');
        my $run = sprintf('%032x', 1);
        is_deeply([map { $_->[1] } grep { $_->[0] eq 'busy' || $_->[0] eq 'deliver' } @events],
            [$run, $run, $run], 'every poll retains the exact run identity');
        my @messages = map { @{$_->{data} || []} } @responses;
        is(scalar(grep { /Node[ ]is[ ]busy/x } @messages), 1, 'waiting is explained once');
        is(scalar(grep { $_->[0] eq 'collect' } @events), $remains_busy ? 0 : 1,
            'only the completed run is collected');
        if ($remains_busy) {
            my $resume = "--freebsd-run $run";
            like(join('', @{errors()}), qr/\Q$resume\E/x, 'timeout prints the exact resume command');
        } else {
            is_deeply(errors(), [], 'completed retry is successful');
            is_deeply($updates[-1], ['node1', 'synced'], 'completed retry updates durable node status');
        }
    }
    done_testing();
    return;
}

subtest 'busy nodes wait within the deadline and retain a resumable run' => \&busy_node_wait;

subtest 'a later invalid selection causes no synchronization or execution' => sub {
    reset_execution();
    $fault = 'prepare';
    is(process_native('-F', '-S', '-P', 'custom'), 1, 'preparation failure reaches the public command');
    is_deeply([map { $_->[0] } @events], [qw(prepare prepare)], 'all remote effects wait for successful preparations');
    like(join('', @{errors()}), qr/Fixture[ ]second[ ]preparation[ ]failure/x, 'the preparation failure is retained');
    done_testing();
};

subtest 'failed software stops the following postscript pass' => sub {
    reset_execution();
    $fault = 'execute';
    is(process_native('-S', '-P', 'custom'), 1, 'failed receipt fails the public command');
    is_deeply([map { $_->[0] } @events], [qw(prepare prepare deliver collect)], 'no later postscript run is delivered');
    ok(@{errors()}, 'failure is reported');
    done_testing();
};

subtest 'package rejection reports the prerequisite and unstarted scripts' => sub {
    reset_execution();
    $fault = 'rejection';
    is(process_native('-S', '-P', 'custom'), 1, 'rejected prerequisite fails the public command');
    is_deeply([map { $_->[0] } @events], [qw(prepare prepare deliver collect)],
        'a rejected prerequisite prevents the later postscript pass');
    my @data = map { @{$_->{data} || []} } @responses;
    my @errors = map { @{$_->{error} || []} } @responses;
    my $messages = join("\n", @data, @errors);
    like($messages, qr/Package[ ]prerequisite[ ]failed[ ]during[ ]native/x,
        'public output identifies the failed prerequisite phase');
    like($messages, qr{diagnostic:[ ]/fixture/report/prerequisite[.]stderr}x,
        'public output names the retained diagnostic');
    like($messages, qr/not-run/x, 'public output identifies the unstarted script');
    done_testing();
};

subtest 'retained observation and release never prepare another package update' => sub {
    for my $release (0, 1) {
        reset_execution();
        my $run = 'a' x 32;
        is(process_native('--freebsd-run', $run, $release ? ('--freebsd-release') : ()), 0,
            'retained run completes observation');
        is_deeply([map { $_->[0] } @events], $release ? [qw(read release deliver collect)] : [qw(read deliver collect)],
            'retained request does not prepare or synchronize again');
    }
    reset_execution();
    $fault = 'node';
    is(process_native('--freebsd-run', 'a' x 32), 1, 'another node cannot receive the retained run');
    is_deeply([map { $_->[0] } @events], ['read'], 'node mismatch is rejected before transport');
    done_testing();
};

subtest 'refused release marks the update failed without delivering another run' => sub {
    reset_execution();
    $fault = 'release';
    is(process_native('--freebsd-run', 'a' x 32, '--freebsd-release'), 1, 'refused release fails the public command');
    is_deeply([map { $_->[0] } @events], [qw(read release)], 'refusal prevents later delivery and reporting');
    is_deeply(\@updates, [['node1', 'syncing'], ['node1', 'failed']], 'refusal clears the in-progress node status');
    like(join('', @{errors()}), qr/Fixture[ ]release[ ]refused/x, 'the release diagnostic survives');
    done_testing();
};

subtest 'uncertain execution prints recovery guidance before unavailable evidence' => sub {
    reset_execution();
    $fault = 'uncertain-collect';
    my $run = 'a' x 32;
    is(process_native('--freebsd-run', $run), 1, 'unreleased evidence fails collection');
    is_deeply([map { $_->[0] } @events], [qw(read deliver collect)], 'observation does not run scripts or release automatically');
    my $messages = join("\n", map { join("\n", @{$_->{data} || []}, @{$_->{error} || []}) } @responses);
    my $command = "updatenode node1 --freebsd-run $run --freebsd-release";
    my $location = "/var/db/xcat/postscripts/runs/$run";
    like($messages, qr/\Q$location\E/x, 'diagnostic location survives collection failure');
    like($messages, qr/\Q$command\E/x, 'exact retained-run recovery command survives collection failure');
    cmp_ok(index($messages, $command), '<', index($messages, 'Fixture collection failure'), 'guidance precedes the transport failure');
    is_deeply(\@updates, [['node1', 'syncing'], ['node1', 'failed']], 'uncertain collection clears the in-progress state');
    done_testing();
};

subtest 'retained framework diagnostics preserve uncertainty' => sub {
    reset_execution();
    $fault = 'framework-logs';
    is(process_native('--freebsd-run', 'a' x 32), 1, 'framework diagnostics do not complete the interrupted run');
    my $messages = join("\n", map { @{$_->{data} || []} } @responses);
    my $location = 'Framework diagnostic: /fixture/report/framework.stderr';
    like($messages, qr/\Q$location\E/x, 'public output locates the collected framework diagnostic');
    like($messages, qr/custom:[ ]not-run/x, 'script disposition is preserved');
    done_testing();
};

subtest 'preserved provenance does not complete interrupted execution' => sub {
    reset_execution();
    $fault = 'package-preservation';
    is(process_native('--freebsd-run', 'a' x 32, '--freebsd-release'), 1, 'preservation retains the incomplete outcome');
    is_deeply([map { $_->[0] } @events], [qw(read release deliver collect)], 'preservation prepares no new update');
    my $messages = join("\n", map { @{$_->{data} || []} } @responses);
    my $explanation = 'Package application did not start; previous package provenance retained.';
    like($messages, qr/\Q$explanation\E/x, 'public output explains the retained package state');
    like($messages, qr/custom:[ ]not-run/x, 'selected scripts remain unstarted');
    unlike($messages, qr/:[ ]success/x, 'preservation does not announce success');
    done_testing();
};

subtest 'interrupted package diagnostics preserve uncertainty' => sub {
    reset_execution();
    $fault = 'interrupted-logs';
    is(process_native('--freebsd-run', 'a' x 32), 1, 'interrupted run does not report successful completion');
    is_deeply([map { $_->[0] } @events], [qw(read deliver collect)], 'observation does not prepare another operation');
    my $messages = join("\n", map { @{$_->{data} || []} } @responses);
    my $diagnostic = 'Package prerequisite stderr: /fixture/report/prerequisite.stderr';
    like($messages, qr/\Q$diagnostic\E/x,
        'public output locates the interrupted prerequisite diagnostic');
    like($messages, qr/uncertain/x, 'public output retains the uncertain outcome');
    like($messages, qr/custom:[ ]not-run/x, 'public output identifies the unstarted script');
    unlike($messages, qr/Package[ ]prerequisite[ ]failed|:[ ]success/x, 'logs alone do not assign an outcome');
    done_testing();
};

subtest 'recovered package provenance does not complete interrupted execution' => sub {
    reset_execution();
    $fault = 'package-recovery';
    is(process_native('--freebsd-run', 'a' x 32, '--freebsd-release'), 1,
        'release with recovered provenance keeps the uncertain outcome');
    is_deeply([map { $_->[0] } @events], [qw(read release deliver collect)],
        'explicit release does not prepare another update');
    my $messages = join("\n", map { @{$_->{data} || []} } @responses);
    my $recovery_message = 'Package provenance recovered; the interrupted execution remains uncertain.';
    like($messages, qr/\Q$recovery_message\E/x,
        'public output explains what recovery established');
    like($messages, qr/custom:[ ]not-run/x, 'unstarted scripts remain unstarted');
    unlike($messages, qr/:[ ]success/x, 'recovery does not announce success');
    done_testing();
};

sub report_locations {
    for my $outcome ('', qw(execute rejection interrupted-logs)) {
        reset_execution();
        $fault = $outcome;
        my $run = 'a' x 32;
        is(process_native('--freebsd-run', $run), $outcome ? 1 : 0, 'report location preserves the run outcome');
        my $expected = "node1: FreeBSD postscript report: /fixture/report-$run/report.json";
        my @locations = grep { $_ eq $expected } map { @{$_->{data} || []} } @responses;
        is_deeply(\@locations, [$expected], 'caller receives the retained JSON report location once');
    }
    done_testing();
    return;
}

subtest 'public output locates every collected report' => \&report_locations;

subtest 'pool updates follow the selected owner and require completed installation' => sub {
    reset_fixture();
    delete $xCAT::Table::rows{noderes}[0]{xcatmaster};
    $xCAT::Table::rows{noderes}[0]{servicenode} = '192.0.2.11,192.0.2.12';
    local $::XCATSITEVALS{master} = '192.0.2.1';
    for my $case ([prepared => 0], [installing => 1], [failed => 1], [cancelled => 0],
        [cancelled => 1], [installed => 1], [booted => 1]) {
        my ($phase, $has_owner) = @$case;
        @responses = ();
        my @queries;
        my $routed = xCAT_plugin::updatenode::preprocess_request(request(['node1'], '-P'), $callback, sub {
            my $request = shift;
            push @queries, dclone($request);
            return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
                operation => 'inspect', result => {phase => $phase, $has_owner ? (owner => '192.0.2.12') : ()}})]};
        });
        is($queries[0]{arg}[0], 'inspect', 'routing reads the installation owner');
        if ($phase eq 'installed' || $phase eq 'booted') {
            is_deeply(errors(), [], 'installed pool node has an update owner');
            is($routed->[0]{_xcatdest}, '192.0.2.12', 'update targets the server that owns its receipts');
        } else {
            ok(!defined($routed), 'incomplete pool installation receives no update dispatch');
            like(join('', @{errors()}), qr/no[ ]installed[ ]owner/x, 'unavailable owner is explained');
        }
    }
    return;
};

subtest 'pool and fixed owners retain separate maintenance destinations' => sub {
    reset_fixture();
    delete $xCAT::Table::rows{noderes}[0]{xcatmaster};
    $xCAT::Table::rows{noderes}[0]{servicenode} = '192.0.2.11,192.0.2.12';
    local $::XCATSITEVALS{master} = '192.0.2.1';
    my @queries;
    my $routed = xCAT_plugin::updatenode::preprocess_request(request(['node1', 'node2', 'linux1'], '-P'),
        $callback, sub {
            my $query = shift;
            push @queries, dclone($query);
            return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
                operation => 'inspect', result => {phase => 'booted', owner => '192.0.2.12'}})]};
        });
    is_deeply(errors(), [], 'mixed fixed and pool routing succeeds');
    is_deeply([map { $_->{node} } @queries], [['node1']], 'only the pool node queries its coordinator');
    is_deeply([map { [$_->{_xcatdest}, $_->{node}] } grep { $_->{command}[0] eq 'updatenode' } @$routed],
        [['192.0.2.12', ['node1']], ['198.51.100.1', ['node2']]], 'each native node keeps its actual owner');
    is_deeply($legacy[0]{node}, ['linux1'], 'Linux maintenance retains the legacy handler');
    return;
};

done_testing();
