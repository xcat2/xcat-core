#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_REPO_MODULE_DIR};
use Archive::Tar;
use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempdir);
use Fcntl qw(LOCK_EX LOCK_NB);
use JSON;
use Test::More;
use xCAT::FreeBSDPostscript;

umask 0077;
my $temporary = tempdir(CLEANUP => 1);
my $json = JSON->new->canonical->utf8;
my $run = 'a' x 32;
my $generation = 'c' x 32;
my $attempt = 'd' x 32;
my $sequence = 0;

sub write_file {
    my ($path, $bytes) = @_;
    open(my $file, '>:raw', $path) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

sub read_file {
    open(my $file, '<:raw', shift) or croak $!;
    my $bytes = do { local $/ = undef; <$file> };
    close($file) or croak $!;
    return $bytes;
}

sub fields {
    my ($format, @pairs) = @_;
    return "format\t$format\n" . join('', map { join("\t", @$_) . "\n" } @pairs);
}

sub fixture {
    my ($version, $exit, $boot) = @_;
    my $root = "$temporary/store-" . ++$sequence;
    mkdir($root, 0700) or croak $!;
    mkdir("$root/export-$run", 0700) or croak $!;
    my %members;
    my $raw = sha256_hex('scripts/one "two words" ""');
    my $script = sha256_hex("#!/bin/sh\nexit 0\n");
    $members{'bundle/entries'} = "1\tpostscripts\t$raw\t$script\tscripts/one\n";
    $members{'bundle/manifest'} = fields($boot ? 'xcat-freebsd-postscript-bundle-3' : 'xcat-freebsd-postscript-bundle-2',
        [run => $run], [node => 'node1'], [generation => $generation], [attempt => $attempt],
        [kind => $boot ? 'firstboot' : 'update'], [preparation => '2' x 64], [source => '1' x 64], [plan => 'e' x 64],
        [request => '3' x 64], ['package-mode' => 'verify'], [driver => '4' x 64],
        [entries => sha256_hex($members{'bundle/entries'})], [tree => '5' x 64], [scripts => 1],
        ['entry-timeout' => 30], ['run-timeout' => 120], ['log-limit' => 4096], $boot ? ([boot => $boot]) : ());
    my $snapshot = sha256_hex($members{'bundle/manifest'});
    $members{snapshot} = "$snapshot\n";
    $members{started} = fields('xcat-freebsd-postscript-start-1', [run => $run],
        [snapshot => $snapshot], [boot => $boot || '6' x 64], [pid => 123], [process => '7' x 64]);
    $members{'driver.complete'} = "1\n";
    $members{'packages.result'} = "package proof\n";
    $members{'driver.stdout'} = "driver output\n";
    $members{'driver.stderr'} = '';
    $members{'entries/1/argv'} = "scripts/one\0two words\0\0";
    $members{'entries/1/stdout'} = "output\0with binary bytes\xff\n";
    $members{'entries/1/stderr'} = "diagnostic\n";
    my @timing = $version >= 2 ? (['started-epoch' => 1700000000]) : ();
    push @timing, ['started-uptime' => 100] if $version >= 3;
    $members{'entries/1/started'} = fields("xcat-freebsd-postscript-entry-start-$version",
        [ordinal => 1], ['raw-sha256' => $raw], ['script-sha256' => $script], @timing);
    @timing = $version >= 2 ? (['started-sha256' => sha256_hex($members{'entries/1/started'})],
        ['finished-epoch' => 1700000002]) : ();
    push @timing, ['finished-uptime' => 102] if $version >= 3;
    $members{'entries/1/result'} = fields("xcat-freebsd-postscript-entry-result-$version",
        [ordinal => 1], [status => $exit], @timing,
        (map { ["$_-sha256" => sha256_hex($members{"entries/1/$_"})] } qw(argv stdout stderr)),
        $version == 4 ? (['log-limit' => 4096], ['stdout-bytes' => length($members{'entries/1/stdout'})],
            ['stderr-bytes' => length($members{'entries/1/stderr'})], ['stdout-truncated' => 'no'],
            ['stderr-truncated' => 'no'], ['stdout-open' => 'no'], ['stderr-open' => 'no']) : (),
        [complete => 'yes']);
    $members{results} = "1\t$exit\t" . sha256_hex($members{'entries/1/result'}) . "\n";
    $members{result} = fields('xcat-freebsd-postscript-result-1', [run => $run], [node => 'node1'],
        [generation => $generation], [attempt => $attempt], [snapshot => $snapshot], [plan => 'e' x 64],
        [entries => 1], ['results-sha256' => sha256_hex($members{results})],
        ['packages-sha256' => sha256_hex($members{'packages.result'})],
        ['stdout-sha256' => sha256_hex($members{'driver.stdout'})], ['stderr-sha256' => sha256_hex('')],
        [outcome => $exit ? 'failed' : 'success'], [complete => 'yes']);
    my $bundle = "\0" x 10240;
    my $export = { kind => 'freebsd-postscript-export-v1', node => 'node1', source => '1' x 64,
        snapshot => $snapshot, scripts => 1, binding => { preparation => '2' x 64, run => $run,
            generation => $generation, attempt => $attempt, package_mode => 'verify', $boot ? (boot => $boot) : (),
            entry_timeout => 30, run_timeout => 120, log_limit => 4096 },
        archive => { bytes => length($bundle), sha256 => sha256_hex($bundle) } };
    write_file("$root/export-$run/manifest.json", $json->encode($export) . "\n");
    write_file("$root/export-$run/bundle.tar", $bundle);
    write_file("$root/delivery-$run.result", $members{result});
    return { root => $root, export => $export, members => \%members, calls => [] };
}

sub seal_rejected {
    my $state = shift;
    my $members = $state->{members};
    my ($mode) = $members->{'packages.rejected'} =~ /^mode\t(\w+)$/mx;
    my $native = "packages/local-$mode.rejected";
    if (exists($members->{$native})) {
        my $digest = sha256_hex($members->{$native});
        $members->{'packages.rejected'} =~ s/^native-sha256\t[^\n]+/native-sha256\t$digest/mx;
    }
    for my $pair ([results => 'results-sha256'], ['packages.rejected' => 'packages-sha256'],
        ['prerequisite.stdout' => 'stdout-sha256'], ['prerequisite.stderr' => 'stderr-sha256']) {
        my $digest = sha256_hex($members->{$pair->[0]});
        $members->{result} =~ s/^$pair->[1]\t[^\n]+/$pair->[1]\t$digest/mx;
    }
    write_file("$state->{root}/delivery-$run.result", $members->{result});
    return;
}

sub rejected_fixture {
    my ($phase, $mode, $boot) = @_;
    my $state = fixture(3, 0, $boot);
    my $members = $state->{members};
    delete $members->{$_} for grep { m{\A(?:entries/|driver[.]|packages[.]result\z)}x } keys %$members;
    $members->{'bundle/manifest'} =~ s/^package-mode\tverify$/package-mode\t$mode/mx;
    my $snapshot = sha256_hex($members->{'bundle/manifest'});
    $members->{snapshot} = "$snapshot\n";
    $members->{started} =~ s/^snapshot\t[^\n]+/snapshot\t$snapshot/mx;
    $state->{export}{snapshot} = $snapshot;
    $state->{export}{binding}{package_mode} = $mode;
    write_file("$state->{root}/export-$run/manifest.json", $json->encode($state->{export}) . "\n");
    $members->{results} = "1\tnot-run\t-\t-\t-\n";
    $members->{'prerequisite.stdout'} = '';
    $members->{'prerequisite.stderr'} = "Package prerequisite diagnostic\n";
    $members->{'packages.rejected'} = fields('xcat-freebsd-postscript-package-rejection-1',
        [run => $run], [snapshot => $snapshot], [plan => 'e' x 64], [mode => $mode], [phase => $phase],
        ['previous-head-sha256' => '9' x 64], ['native-sha256' => '-'], [complete => 'yes']);
    if ($phase eq 'native') {
        $members->{"packages/local-$mode.rejected"} = fields('xcat-freebsd-local-rejection-1',
            [scope => "local-$mode"], ['plan-reference' => 'e' x 64], ['request-sha256' => '3' x 64],
            ['prior-request-sha256' => 'a' x 64], ['config-sha256' => 'b' x 64],
            [pkg => '2.6.2'], [apply => 'not-started'], [outcome => 'rejected'], [complete => 'yes']);
    }
    $members->{result} = fields('xcat-freebsd-postscript-result-2', [run => $run], [node => 'node1'],
        [generation => $generation], [attempt => $attempt], [snapshot => $snapshot], [plan => 'e' x 64],
        [entries => 1], map { [$_ => '0' x 64] } qw(results-sha256 packages-sha256 stdout-sha256 stderr-sha256));
    $members->{result} .= "outcome\tfailed\ncomplete\tyes\n";
    $state->{rejected} = 1;
    seal_rejected($state);
    return $state;
}

sub archive {
    my $state = shift;
    my $tar = Archive::Tar->new;
    for my $name (sort keys %{$state->{members}}) {
        $tar->add_data($name, $state->{members}{$name}, { mode => oct('0600'), uid => 0, gid => 0, mtime => 0 });
    }
    $state->{tar_filter}->($tar) if $state->{tar_filter};
    my $bytes = $tar->write;
    croak 'Cannot write fixture archive' unless defined($bytes);
    return $bytes;
}

sub seal_interrupted {
    my $state = shift;
    my $members = $state->{members};
    $members->{'interrupted.inventory'} = join('', map {
        join("\t", $_, length($members->{$_}), sha256_hex($members->{$_})) . "\n"
    } sort grep { $_ ne 'interrupted.inventory' && $_ ne 'interrupted.receipt' } keys %$members);
    $members->{'interrupted.receipt'} = fields('xcat-freebsd-postscript-interrupted-1',
        [run => $run], [node => 'node1'], [generation => $generation], [attempt => $attempt],
        [snapshot => $state->{export}{snapshot}], [plan => 'e' x 64], [entries => 3],
        ['results-sha256' => sha256_hex($members->{'interrupted.results'})],
        ['inventory-sha256' => sha256_hex($members->{'interrupted.inventory'})], [outcome => 'uncertain'], [complete => 'no']);
    return;
}

sub interrupted_fixture {
    my ($exit, $boot) = @_;
    my $state = fixture(2, $exit, $boot);
    my $members = $state->{members};
    delete @{$members}{qw(result results driver.complete)};
    unlink("$state->{root}/delivery-$run.result") or croak $!;
    my $script = sha256_hex("#!/bin/sh\nexit 0\n");
    my $raw = sha256_hex('scripts/two waiting');
    $members->{'bundle/entries'} .= "2\tpostbootscripts\t$raw\t$script\tscripts/two\n3\tpostbootscripts\t"
      . sha256_hex('scripts/three') . "\t$script\tscripts/three\n";
    my $entries_digest = sha256_hex($members->{'bundle/entries'});
    $members->{'bundle/manifest'} =~ s/^entries\t[^\n]+/entries\t$entries_digest/mx;
    $members->{'bundle/manifest'} =~ s/^scripts\t1$/scripts\t3/mx;
    my $snapshot = sha256_hex($members->{'bundle/manifest'});
    $members->{snapshot} = "$snapshot\n";
    $members->{started} =~ s/^snapshot\t[^\n]+/snapshot\t$snapshot/mx;
    $members->{released} = fields('xcat-freebsd-postscript-release-1', [run => $run], [snapshot => $snapshot], [boot => '8' x 64]);
    $members->{'entries/2/started'} = fields('xcat-freebsd-postscript-entry-start-2',
        [ordinal => 2], ['raw-sha256' => $raw], ['script-sha256' => $script], ['started-epoch' => 1700000003]);
    $members->{'entries/2/argv'} = "scripts/two\0waiting\0";
    $members->{'entries/2/stdout'} = "partial\0output\n";
    $members->{'entries/2/stderr'} = '';
    $members->{'interrupted.results'} = "1\tcomplete\t$exit\t" . sha256_hex($members->{'entries/1/started'})
      . "\t" . sha256_hex($members->{'entries/1/result'}) . "\n2\tuncertain\t-\t"
      . sha256_hex($members->{'entries/2/started'}) . "\t-\n3\tnot-run\t-\t-\t-\n";
    $state->{partial} = 1;
    $state->{native_outcome} = 'uncertain';
    $state->{export}{snapshot} = $snapshot;
    $state->{export}{scripts} = 3;
    write_file("$state->{root}/export-$run/manifest.json", $json->encode($state->{export}) . "\n");
    seal_interrupted($state);
    return $state;
}

sub transport {
    my $state = shift;
    return sub {
        my ($request, $callback) = @_;
        my $command = $request->{command}[0];
        push @{$state->{calls}}, $command;
        is_deeply($request->{node}, ['node1'], 'collection targets the exported node');
        my $body = '';
        if ($command eq 'xdsh') {
            if ($request->{arg}[3] eq "/usr/local/libexec/xcat-postscript receipt $run") {
                $body = fields('xcat-freebsd-postscript-status-1', [run => $run], [snapshot => $state->{export}{snapshot}],
                    [outcome => $state->{native_outcome}], [complete => 'no']);
            } else {
                is($request->{arg}[3], "/usr/local/libexec/xcat-postscript evidence $run", 'collection cannot execute scripts');
                $state->{archive} = archive($state);
                my $receipt = $state->{partial} ? $state->{members}{'interrupted.receipt'} : read_file("$state->{root}/delivery-$run.result");
                $body = fields('xcat-freebsd-postscript-evidence-' . ($state->{partial} ? 2 : $state->{rejected} ? 3 : $state->{failure} ? 4 : 1), [run => $run],
                    [snapshot => $state->{export}{snapshot}], ['receipt-sha256' => sha256_hex($receipt)],
                    ['archive-sha256' => sha256_hex($state->{archive})], ['archive-bytes' => length($state->{archive})],
                    [path => "/var/db/xcat/postscripts/runs/$run/evidence/archive.tar"]);
                $body = $state->{status_filter}->($body) if $state->{status_filter};
            }
        } else {
            is($command, 'xdcp', 'evidence uses the xCAT copy transport');
            is_deeply([@{$request->{arg}}[3..4]], ['-P', "/var/db/xcat/postscripts/runs/$run/evidence/archive.tar"],
                'copy pulls only the bound native archive');
            my $bytes = $state->{archive};
            $bytes .= 'corrupt' if $state->{corrupt_transfer};
            write_file("$request->{arg}[5]/archive.tar._node1", $bytes);
            croak 'Lost copy acknowledgement' if delete($state->{disconnect});
        }
        my @lines = map { "node1: $_" } split(/\n/x, $body);
        push @lines, 'node1: Remote_command_successful' unless $state->{missing_status};
        $callback->({ data => [join("\n", @lines)] });
        return;
    };
}

sub collect {
    my ($state, $callback) = @_;
    return xCAT::FreeBSDPostscript::collect_execution($run, $callback || transport($state), directory => $state->{root});
}

sub reject {
    my ($state, $description) = @_;
    my $report;
    my $ok = eval { $report = collect($state); 1; };
    ok(!$ok, "$description fails");
    my $prefix = 'FreeBSD postscript reporting failed during ';
    like($@, qr/\A\Q$prefix\E[a-z -]+\n\z/x, 'failure identifies a private stage');
    ok(!defined($report), 'failure returns no accepted report');
    return;
}

sub test_results {
    for my $version (1, 2, 3, 4) {
        for my $exit (0, 3, 124, 143) {
            my $state = fixture($version, $exit);
            my $receipt = xCAT::FreeBSDPostscript::deliver_execution($run,
                sub { croak 'Retained terminal receipt attempted transport'; }, directory => $state->{root});
            is($receipt->{outcome}, $exit ? 'failed' : 'success', 'payload retirement preserves the terminal outcome');
            ok(!-e "$state->{root}/export-$run/bundle.tar", 'report collection does not require the retired payload');
            my $report = collect($state);
            is_deeply([glob("$state->{root}/.report-$run.*")], [], 'successful report removes its transport attempt');
            is($report->{receipt}{outcome}, $exit ? 'failed' : 'success', 'script failures stay failed');
            my $entry = $report->{entries}[0];
            is($entry->{status}, $exit, 'exact child status is retained');
            is($entry->{phase}, 'postscripts', 'phase is retained');
            is($entry->{script}, 'scripts/one', 'selected script is retained');
            is($entry->{started_epoch}, $version >= 2 ? 1700000000 : undef, 'start time or explicit legacy absence');
            is($entry->{finished_epoch}, $version >= 2 ? 1700000002 : undef, 'finish time or explicit legacy absence');
            is($entry->{started_uptime}, $version >= 3 ? 100 : undef, 'monotonic start or explicit legacy absence');
            is($entry->{finished_uptime}, $version >= 3 ? 102 : undef, 'monotonic finish or explicit legacy absence');
            for my $stream (qw(argv stdout stderr)) {
                is(read_file($entry->{$stream}{path}), $state->{members}{"entries/1/$stream"}, "$stream retains all bytes");
            }
            is_deeply(collect($state, sub { croak 'Completed report attempted transport'; }), $report, 'completed collection needs no transport');
        }
    }
    return;
}

sub test_delivery {
    for my $field (qw(run snapshot receipt-sha256 archive-sha256 archive-bytes path)) {
        my $state = fixture(2, 0);
        $state->{status_filter} = sub { my $bytes = shift; $bytes =~ s/^\Q$field\E\t[^\n]*/$field\twrong/mx; return $bytes; };
        reject($state, "wrong $field");
        ok(!-e "$state->{root}/report-$run", 'invalid response cannot publish a report');
    }
    for my $fault (qw(corrupt_transfer missing_status)) {
        my $state = fixture(2, 0); $state->{$fault} = 1;
        reject($state, $fault);
        ok(!-e "$state->{root}/report-$run", 'failed transfer cannot publish a report');
    }
    my $state = fixture(2, 0);
    unlink("$state->{root}/delivery-$run.result") or croak $!;
    $state->{native_outcome} = 'admitted';
    reject($state, 'run has not executed');
    is_deeply($state->{calls}, ['xdsh'], 'unstarted run is observed without evidence collection');
    return;
}

sub reseal_entry {
    my $state = shift;
    my $members = $state->{members};
    my $digest = sha256_hex($members->{'entries/1/started'});
    $members->{'entries/1/result'} =~ s/^started-sha256\t[^\n]+/started-sha256\t$digest/mx;
    $digest = sha256_hex($members->{'entries/1/result'});
    $members->{results} = "1\t0\t$digest\n";
    $digest = sha256_hex($members->{results});
    $members->{result} =~ s/^results-sha256\t[^\n]+/results-sha256\t$digest/mx;
    write_file("$state->{root}/delivery-$run.result", $members->{result});
    return;
}

sub test_monotonic_times {
    my $state = fixture(3, 0);
    $state->{members}{'entries/1/result'} =~ s/^finished-epoch\t[^\n]+/finished-epoch\t1699999400/mx;
    reseal_entry($state);
    my $report = collect($state);
    is($report->{entries}[0]{finished_epoch}, 1699999400, 'backward wall-clock correction remains recorded');
    is($report->{entries}[0]{finished_uptime}, 102, 'elapsed execution remains monotonic');
    for my $fault ([started => '-1'], [started => '00'], [finished => '99'], [finished => '102x']) {
        my ($part, $value) = @$fault;
        $state = fixture(3, 0);
        my $member = $part eq 'started' ? 'started' : 'result';
        $state->{members}{"entries/1/$member"} =~ s/^$part-uptime\t[^\n]+/$part-uptime\t$value/mx;
        reseal_entry($state);
        reject($state, "invalid monotonic $part $value");
    }
    return;
}

sub test_output_limits {
    for my $stream (qw(stdout stderr)) {
        for my $truncated (qw(no yes)) {
            my $state = fixture(4, 0);
            my $members = $state->{members};
            $members->{"entries/1/$stream"} = 'x' x 4096;
            my $digest = sha256_hex($members->{"entries/1/$stream"});
            $members->{'entries/1/result'} =~ s/^$stream-sha256\t[^\n]+/$stream-sha256\t$digest/mx;
            $members->{'entries/1/result'} =~ s/^$stream-bytes\t[^\n]+/$stream-bytes\t4096/mx;
            $members->{'entries/1/result'} =~ s/^$stream-truncated\t[^\n]+/$stream-truncated\t$truncated/mx;
            $members->{'entries/1/result'} =~ s/^$stream-open\t[^\n]+/$stream-open\tyes/mx;
            reseal_entry($state);
            my $report = collect($state);
            is($report->{receipt}{outcome}, 'success', 'bounded output preserves successful command status');
            is($report->{entries}[0]{$stream}{bytes}, 4096, 'retained output reaches its exact bound');
            is($report->{entries}[0]{$stream}{limit}, 4096, 'report gives the manifest-bound stream limit');
            is($report->{entries}[0]{$stream}{truncated}, $truncated eq 'yes' ? 1 : 0, 'exact and truncated output remain distinct');
            is($report->{entries}[0]{$stream}{open_after_exit}, 1, 'inherited open output remains visible');
        }
        for my $fault (["$stream-bytes" => '00'], ["$stream-bytes" => '4097'],
            ["$stream-truncated" => 'yes'], ["$stream-truncated" => 'maybe'], ["$stream-open" => '1'],
            ['log-limit' => '4097'], ['log-limit' => '04096']) {
            my $state = fixture(4, 0);
            my ($key, $value) = @$fault;
            $state->{members}{'entries/1/result'} =~ s/^$key\t[^\n]+/$key\t$value/mx;
            reseal_entry($state);
            reject($state, "invalid capture $key=$value");
        }
    }
    return;
}

sub test_evidence {
    for my $member (qw(bundle/manifest bundle/entries snapshot driver.complete result results packages.result
        driver.stdout driver.stderr entries/1/started entries/1/result entries/1/argv entries/1/stdout entries/1/stderr)) {
        my $state = fixture(2, 0);
        $state->{members}{$member} .= "changed\n";
        reject($state, "changed $member");
        ok(!-e "$state->{root}/report-$run", 'corrupt evidence cannot publish a report');
    }
    for my $fault (qw(missing extra duplicate symlink oversized)) {
        my $state = fixture(2, 0);
        $state->{tar_filter} = sub {
            my $tar = shift;
            if ($fault eq 'missing') { $tar->remove('entries/1/stdout'); }
            elsif ($fault eq 'oversized') { $tar->replace_content('entries/1/stdout', 'x' x 4097); }
            else {
                my $name = $fault eq 'duplicate' ? 'entries/1/stdout' : '../escape';
                $tar->add_data($name, '', { mode => oct('0600'), uid => 0, gid => 0,
                    type => $fault eq 'symlink' ? 2 : 0, linkname => $fault eq 'symlink' ? '/etc/passwd' : '' });
            }
            return;
        };
        reject($state, $fault);
        ok(!-e "$state->{root}/report-$run", 'invalid member cannot publish a report');
    }
    return;
}

sub test_retry {
    my $state = fixture(2, 0); $state->{disconnect} = 1;
    reject($state, 'lost acknowledgement');
    ok(!-e "$state->{root}/report-$run", 'failed collection has no terminal report');
    my $failed_attempts = [glob("$state->{root}/.report-$run.*")];
    is(scalar(@$failed_attempts), 1, 'failed report retains its diagnostic attempt');
    my $report = collect($state);
    is($report->{entries}[0]{status}, 0, 'retry returns the completed entry');
    is_deeply($state->{calls}, [qw(xdsh xdcp xdsh xdcp)], 'retry repeats only evidence creation and retrieval');
    is_deeply([glob("$state->{root}/.report-$run.*")], $failed_attempts, 'successful retry preserves only the failed attempt');
    return;
}

sub test_release_attempts {
    for my $outcome (qw(uncertain pending transport-error)) {
        my $state = fixture(4, 0);
        my $response;
        my $ok = eval {
            $response = xCAT::FreeBSDPostscript::release_execution($run, sub {
                my ($request, $callback) = @_;
                is($request->{command}[0], 'xdsh', 'release uses the command transport');
                is($request->{arg}[3], "/usr/local/libexec/xcat-postscript release-after-reboot $run $state->{export}{snapshot}",
                    'release binds the retained run and snapshot');
                croak 'Fixture release transport failure' if $outcome eq 'transport-error';
                my $body = fields('xcat-freebsd-postscript-status-1', [run => $run],
                    [snapshot => $state->{export}{snapshot}], [outcome => $outcome], [complete => 'no']);
                $callback->({ data => [join("\n", (map { "node1: $_" } split(/\n/x, $body)), 'node1: Remote_command_successful')] });
                return;
            }, directory => $state->{root});
            1;
        };
        my @attempts = glob("$state->{root}/.release-$run.*");
        if ($outcome eq 'uncertain') {
            ok($ok, 'valid release completes');
            is($response->{outcome}, 'uncertain', 'release does not claim script success');
            is_deeply(\@attempts, [], 'successful release removes its transport attempt');
        } else {
            ok(!$ok, 'failed or invalid release is rejected');
            is(scalar(@attempts), 1, 'unsuccessful release retains its transport evidence');
        }
    }
    return;
}

sub test_retained {
    for my $member (qw(archive.tar status observation result report.json entries.1.stdout)) {
        my $state = fixture(2, 0); collect($state);
        write_file("$state->{root}/report-$run/$member", 'corrupt');
        my $before = [@{$state->{calls}}];
        reject($state, "retained $member");
        is_deeply($state->{calls}, $before, 'corruption is rejected without contacting the node');
    }
    my $state = fixture(2, 0);
    open(my $lock, '>', "$state->{root}/report-$run.lock") or croak $!;
    flock($lock, LOCK_EX | LOCK_NB) or croak $!;
    reject($state, 'report lock held');
    close($lock) or croak $!;
    is_deeply($state->{calls}, [], 'busy report does not contact the node');
    return;
}

sub test_interrupted {
    for my $exit (0, 3, 143) {
        my $state = interrupted_fixture($exit);
        my $report = collect($state);
        is($report->{receipt}{outcome}, 'uncertain', 'interrupted run never claims success');
        is($report->{receipt}{complete}, 'no', 'interrupted run stays incomplete');
        ok(!exists($report->{prerequisite_logs}), 'older evidence has no invented prerequisite logs');
        is_deeply([map { $_->{state} } @{$report->{entries}}], [qw(complete uncertain not-run)], 'every selected entry has its actual disposition');
        is_deeply([map { $_->{status} } @{$report->{entries}}], [$exit, undef, undef], 'only completed entries have an exit status');
        is($report->{entries}[1]{started_epoch}, 1700000003, 'uncertain entry retains a valid start time');
        is($report->{entries}[1]{finished_epoch}, undef, 'uncertain entry has no invented finish time');
        is(read_file($report->{entries}[1]{stdout}{path}), "partial\0output\n", 'partial log bytes survive collection');
        is($report->{entries}[2]{stdout}, undef, 'unstarted script has no invented log');
        my $before = [@{$state->{calls}}];
        is_deeply(collect($state, sub { croak 'Interrupted report attempted transport'; }), $report, 'sealed interrupted report retries locally');
        is_deeply($state->{calls}, $before, 'retry cannot execute or contact scripts');
    }
    for my $outcome (qw(admitted pending)) {
        my $state = interrupted_fixture(0);
        $state->{native_outcome} = $outcome;
        reject($state, "mutable $outcome run");
        is_deeply($state->{calls}, ['xdsh'], 'mutable state is observed without sealing evidence');
    }
    my $state = interrupted_fixture(0);
    $state->{members}{'entries/2/started'} = "partial record\n";
    my $sha = sha256_hex($state->{members}{'entries/2/started'});
    $state->{members}{'interrupted.results'} =~ s/^2\tuncertain\t-\t[^\t]+/2\tuncertain\t-\t$sha/mx;
    seal_interrupted($state);
    my $report = collect($state);
    is($report->{entries}[1]{started_record_valid}, 0, 'malformed interrupted start is not trusted');
    is($report->{entries}[1]{started_epoch}, undef, 'malformed start produces no timestamp');
    is($report->{entries}[1]{state}, 'uncertain', 'malformed start remains uncertain');
    return;
}

sub test_interrupted_validation {
    for my $member (qw(released started interrupted.results interrupted.inventory entries/2/argv entries/2/stdout)) {
        my $state = interrupted_fixture(0);
        $state->{members}{$member} .= "changed\n";
        reject($state, "changed interrupted $member");
        ok(!-e "$state->{root}/report-$run", 'corrupt interrupted evidence is not published');
    }
    my %mutations = (
        'same-boot' => sub { $_[0]{released} =~ s/^boot\t[^\n]+/"boot\t" . ('6' x 64)/emx; },
        'false-exit' => sub { $_[0]{'interrupted.results'} =~ s/^2\tuncertain\t-/2\tuncertain\t0/mx; },
        'unstarted-log' => sub { $_[0]{'entries/3/stdout'} = 'unexplained'; },
        'missing-entry' => sub { $_[0]{'interrupted.results'} =~ s/^3\t[^\n]+\n//mx; },
        'wrong-plan' => sub { $_[0]{'bundle/manifest'} =~ s/^plan\t[^\n]+/"plan\t" . ('f' x 64)/emx; },
    );
    for my $fault (sort keys %mutations) {
        my $state = interrupted_fixture(0);
        my $members = $state->{members};
        $mutations{$fault}->($members);
        seal_interrupted($state);
        reject($state, $fault);
        ok(!-e "$state->{root}/report-$run", 'inconsistent interrupted state is not published');
    }
    return;
}

sub seal_observed_release {
    my $state = shift;
    my $members = $state->{members};
    $members->{released} = fields('xcat-freebsd-postscript-release-2', [run => $run],
        [snapshot => $state->{export}{snapshot}], [boot => '6' x 64], [proof => 'release.1234abcd'],
        map { ["$_->[0]-sha256" => sha256_hex($members->{$_->[1]} // '')] }
          [started => 'started'], [supervision => 'supervision'], [process => 'release.process'], [captures => 'release.captures']);
    seal_interrupted($state);
    return;
}

sub observed_release_fixture {
    my ($mode, $exit) = @_;
    $exit //= 3;
    my $state = interrupted_fixture($exit);
    my $members = $state->{members};
    my $original = sha256_hex('123:100.000001');
    $members->{started} =~ s/^process\t[^\n]+/process\t$original/mx;
    $members->{supervision} = fields('xcat-freebsd-postscript-supervision-1', [run => $run],
        [snapshot => $state->{export}{snapshot}], ['started-sha256' => sha256_hex($members->{started})],
        ['helper-sha256' => 'a' x 64], ['capture-version' => 1]);
    $members->{'release.process'} = fields('xcat-freebsd-process-state-1', [pid => 123], [state => $mode],
        [identity => $mode eq 'absent' ? '-' : $mode eq 'zombie' ? '123:100.000001' : '123:200.000002']);
    $members->{'release.captures'} = join('', map {
        join("\t", sha256_hex("$_\n"), $_, ('a' x 64, 'b' x 64, 'c' x 64),
            m{\A(?:entries|packages)/}x ? 'guard' : 'inherit', 125, 'no', 'no') . "\n"
    } qw(framework.stdout prerequisite.stdout driver.stdout packages/stdout entries/1/stdout entries/2/stdout));
    $members->{'framework.stderr'} = "Driver execution is incomplete\0retained\n";
    $members->{'supervisor.stderr'} = '';
    seal_observed_release($state);
    return $state;
}

sub test_observed_release {
    for my $mode (qw(absent zombie running)) {
        my $state = observed_release_fixture($mode);
        my $report = eval { collect($state); };
        ok($report, "$mode observation permits a same-boot report");
        if (!$report) { diag($@); next; }
        is($report->{receipt}{outcome}, 'uncertain', 'release does not invent successful execution');
        is_deeply([map { $_->{status} } @{$report->{entries}}], [3, undef, undef], 'release preserves observed entry statuses');
        is(read_file($report->{framework_logs}{'framework.stderr'}{path}), $state->{members}{'framework.stderr'},
            'framework diagnostics retain their exact bytes');
        is_deeply(collect($state, sub { croak 'Observed release retried transport'; }), $report, 'released evidence is immutable and cached');
    }
    my %changes = (
        live => sub { $_[0]{'release.process'} =~ s/123:200[.]000002/123:100.000001/x; },
        'unknown-state' => sub { $_[0]{'release.process'} =~ s/state\trunning/state\tunknown/x; },
        'wrong-pid' => sub { $_[0]{'release.process'} =~ s/pid\t123/pid\t124/x; },
        'bad-identity' => sub { $_[0]{'release.process'} =~ s/123:200[.]000002/invalid/x; },
        'wrong-supervision' => sub { $_[0]{supervision} =~ s/capture-version\t1/capture-version\t2/x; },
        'missing-process' => sub { delete $_[0]{'release.process'}; },
        'missing-supervision' => sub { delete $_[0]{supervision}; },
        'empty-captures' => sub { $_[0]{'release.captures'} = ''; },
        'missing-framework' => sub { $_[0]{'release.captures'} =~ s/^[^\n]*\tframework[.]stdout\t[^\n]*\n//mx; },
        'duplicate-capture' => sub { $_[0]{'release.captures'} .= $_[0]{'release.captures'}; },
        'unguarded-command' => sub { $_[0]{'release.captures'} =~ s/\tguard\t/\tclose\t/x; },
        'open-packages' => sub { $_[0]{'release.captures'} =~ s{(\tpackages/stdout\t[^\n]*)\tno\tno\n}{$1\tyes\tno\n}x; },
    );
    for my $name (sort keys %changes) {
        my $state = observed_release_fixture('running');
        $changes{$name}->($state->{members});
        seal_observed_release($state);
        reject($state, "invalid same-boot observation: $name");
        ok(!-e "$state->{root}/report-$run", 'invalid observation publishes no report');
    }
    return;
}

sub seal_failure {
    my $state = shift;
    my $members = $state->{members};
    $members->{'failure.inventory'} = join('', map {
        join("\t", $_, length($members->{$_}), sha256_hex($members->{$_})) . "\n"
    } sort grep { $_ ne 'failure.inventory' && $_ ne 'result' } keys %$members);
    $members->{result} = fields('xcat-freebsd-postscript-result-3', [run => $run], [node => 'node1'],
        [generation => $generation], [attempt => $attempt], [snapshot => $state->{export}{snapshot}],
        [plan => 'e' x 64], [entries => 3],
        (map { ["$_->[0]-sha256" => sha256_hex($members->{$_->[1]} // '')] }
          [results => 'failure.results'], [packages => 'packages.result'], [stdout => 'framework.stdout'],
          [stderr => 'framework.stderr'], [inventory => 'failure.inventory']),
        [outcome => 'failed'], [complete => 'yes']);
    write_file("$state->{root}/delivery-$run.result", $members->{result});
    return;
}

sub failure_fixture {
    my $state = observed_release_fixture('absent', shift);
    my $members = $state->{members};
    $members->{'failure.captures'} = delete $members->{'release.captures'};
    $members->{'failure.results'} = delete $members->{'interrupted.results'};
    delete @{$members}{qw(released release.process interrupted.inventory interrupted.receipt)};
    $members->{'framework.stdout'} = '';
    $state->{partial} = 0;
    $state->{failure} = 1;
    seal_failure($state);
    return $state;
}

sub test_framework_failure {
    for my $exit (0, 3) {
        my $state = failure_fixture($exit);
        my $report = eval { collect($state); };
        ok($report, 'observed framework failure has a terminal report');
        if (!$report) { diag($@); next; }
        is($report->{receipt}{outcome}, 'failed', 'framework outcome is independent of observed script exit');
        is($report->{receipt}{complete}, 'yes', 'framework completion does not complete unfinished scripts');
        is_deeply([map { $_->{state} } @{$report->{entries}}], [qw(complete uncertain not-run)], 'all script dispositions survive');
        is_deeply([map { $_->{status} } @{$report->{entries}}], [$exit, undef, undef], 'unfinished scripts have no invented exit');
        is(read_file($report->{framework_logs}{'framework.stderr'}{path}), $state->{members}{'framework.stderr'},
            'terminal framework diagnostic preserves exact bytes');
        is_deeply(collect($state, sub { croak 'Terminal failure attempted transport'; }), $report, 'terminal failure retries use retained evidence');
        write_file($report->{framework_logs}{'framework.stderr'}{path}, 'changed');
        reject($state, 'corrupt retained framework diagnostic');
    }
    for my $member (qw(packages.result supervision failure.captures framework.stdout framework.stderr)) {
        my $state = failure_fixture(0);
        delete $state->{members}{$member};
        seal_failure($state);
        reject($state, "missing failure evidence: $member");
        ok(!-e "$state->{root}/report-$run", 'incomplete failure publishes no report');
    }
    for my $fault (qw(success incomplete inventory missing-framework false-exit)) {
        my $state = failure_fixture(0);
        my $members = $state->{members};
        if ($fault eq 'missing-framework') {
            $members->{'failure.captures'} =~ s/^[^\n]*\tframework[.]stdout\t[^\n]*\n//mx;
        } elsif ($fault eq 'false-exit') {
            $members->{'failure.results'} =~ s/^2\tuncertain\t-/2\tuncertain\t0/mx;
        }
        seal_failure($state);
        $members->{result} =~ s/outcome\tfailed/outcome\tsuccess/x if $fault eq 'success';
        $members->{result} =~ s/complete\tyes/complete\tno/x if $fault eq 'incomplete';
        $members->{'failure.inventory'} .= "corrupt\n" if $fault eq 'inventory';
        write_file("$state->{root}/delivery-$run.result", $members->{result});
        reject($state, "invalid framework failure: $fault");
        ok(!-e "$state->{root}/report-$run", 'invalid failure publishes no report');
    }
    return;
}

sub test_interrupted_prerequisite_logs {
    for my $streams ([qw(stdout stderr)], ['stdout'], ['stderr']) {
        my $state = interrupted_fixture(0);
        for my $stream (@$streams) {
            $state->{members}{"prerequisite.$stream"} = "package $stream\0bytes\xff\n";
        }
        seal_interrupted($state);
        my $report = eval { collect($state); };
        ok($report, 'interrupted prerequisite logs are reportable');
        if (!$report) { diag($@); next; }
        is($report->{receipt}{outcome}, 'uncertain', 'logs do not invent a prerequisite outcome');
        is($report->{receipt}{complete}, 'no', 'diagnostics do not complete the run');
        is_deeply([sort keys %{$report->{prerequisite_logs}}], [sort @$streams], 'only captured streams are reported');
        for my $stream (@$streams) {
            my $log = $report->{prerequisite_logs}{$stream};
            my $expected = $state->{members}{"prerequisite.$stream"};
            is(read_file($log->{path}), $expected, 'exact prerequisite bytes survive collection');
            is($log->{bytes}, length($expected), 'log size is retained');
            is($log->{sha256}, sha256_hex($expected), 'log digest is retained');
        }
        is_deeply([map { $_->{state} } @{$report->{entries}}], [qw(complete uncertain not-run)],
            'diagnostics preserve every entry disposition');
        is_deeply(collect($state, sub { croak 'Prerequisite report attempted transport'; }), $report,
            'retained diagnostics require no transport or execution');
        write_file($report->{prerequisite_logs}{$streams->[0]}{path}, 'changed');
        reject($state, 'changed retained prerequisite log');
    }
    for my $stream (qw(stdout stderr)) {
        for my $fault (qw(changed oversized)) {
            my $state = interrupted_fixture(0);
            $state->{members}{"prerequisite.$stream"} = $fault eq 'oversized' ? 'x' x 4097 : 'original';
            seal_interrupted($state);
            $state->{members}{"prerequisite.$stream"} .= 'changed' if $fault eq 'changed';
            reject($state, "$fault interrupted prerequisite $stream");
            ok(!-e "$state->{root}/report-$run", 'invalid prerequisite log publishes no report');
        }
    }
    return;
}

sub seal_recovery {
    my $state = shift;
    my $members = $state->{members};
    for my $binding ([native => 'result'], [capture => 'capture'], [stdout => 'stdout'], [stderr => 'stderr']) {
        next unless exists($members->{"packages/recovery.$binding->[1]"}) && exists($members->{'packages.recovered'});
        my $digest = sha256_hex($members->{"packages/recovery.$binding->[1]"});
        $members->{'packages.recovered'} =~ s/^$binding->[0]-sha256\t[^\n]+/$binding->[0]-sha256\t$digest/mx;
    }
    seal_interrupted($state);
    return;
}

sub recovery_fixture {
    my ($mode, $actions, $rejected) = @_;
    my $state = interrupted_fixture(0);
    my $members = $state->{members};
    delete $members->{'packages.result'};
    delete @{$members}{grep { m{\Aentries/}x } keys %$members};
    $members->{'interrupted.results'} = join('', map { "$_\tnot-run\t-\t-\t-\n" } 1 .. 3);
    $members->{'bundle/manifest'} =~ s/^package-mode\tverify$/package-mode\t$mode/mx;
    my $snapshot = sha256_hex($members->{'bundle/manifest'});
    $members->{snapshot} = "$snapshot\n";
    for my $name (qw(started released)) { $members->{$name} =~ s/^snapshot\t[^\n]+/snapshot\t$snapshot/mx; }
    $state->{export}{snapshot} = $snapshot;
    $state->{export}{binding}{package_mode} = $mode;
    write_file("$state->{root}/export-$run/manifest.json", $json->encode($state->{export}) . "\n");
    $members->{'packages/recovery.stdout'} = "observed\0bytes\xff\n";
    $members->{'packages/recovery.stderr'} = '';
    $members->{'packages/recovery.capture'} = fields('xcat-freebsd-postscript-capture-1',
        [status => 0], ['stdout-bytes' => length($members->{'packages/recovery.stdout'})], ['stderr-bytes' => 0],
        ['stdout-truncated' => 'no'], ['stderr-truncated' => 'no'], ['stdout-open' => 'no'], ['stderr-open' => 'no']);
    $members->{'packages/recovery.result'} = fields('xcat-freebsd-local-recover-1',
        [scope => 'provenance-only'], ['plan-reference' => 'e' x 64], ['request-sha256' => '3' x 64],
        ['prior-request-sha256' => 'a' x 64], ['started-sha256' => 'b' x 64], ['before-sha256' => 'c' x 64],
        ['observed-sha256' => 'd' x 64], ['managed-request-sha256' => 'f' x 64], ['operation-scope' => "local-$mode"],
        ['actions-sha256' => $actions ? '1' x 64 : '-'], ['rejected-sha256' => $rejected ? '2' x 64 : '-'],
        [pkg => '2.6.2'], [packages => 4], [execution => 'uncertain'], [complete => 'yes']);
    $members->{'packages.recovered'} = fields('xcat-freebsd-postscript-package-recovery-1',
        [run => $run], [snapshot => $snapshot], [plan => 'e' x 64], [mode => $mode],
        ['initial-sha256' => '1' x 64], ['previous-sha256' => '2' x 64], ['request-sha256' => '3' x 64],
        ['config-sha256' => '4' x 64], [attempt => 'recovery.TEST0001'], ['native-sha256' => '0' x 64],
        ['managed-sha256' => 'f' x 64], ['capture-sha256' => '0' x 64], ['stdout-sha256' => '0' x 64],
        ['stderr-sha256' => '0' x 64], [execution => 'uncertain'], [complete => 'yes']);
    seal_recovery($state);
    return $state;
}

sub test_package_recovery {
    for my $variant (['update', 1, 0], ['update', 0, 1], ['verify', 0, 1]) {
        my $state = recovery_fixture(@$variant);
        my $report = eval { collect($state); };
        ok($report, "$variant->[0] recovery is reportable");
        if (!$report) { diag($@); next; }
        is($report->{receipt}{outcome}, 'uncertain', 'recovery preserves the interrupted outcome');
        is($report->{receipt}{complete}, 'no', 'recovery does not complete the original run');
        is_deeply([map { $_->{state} } @{$report->{entries}}], [qw(not-run not-run not-run)],
            'recovery does not change any script disposition');
        my $recovery = $report->{package_recovery};
        is($recovery->{scope}, 'provenance-only', 'report identifies the narrow recovery scope');
        is($recovery->{execution}, 'uncertain', 'native script execution stays uncertain');
        is($recovery->{packages}, 4, 'report carries the observed installed count');
        for my $stream (qw(stdout stderr)) {
            is(read_file($recovery->{$stream}{path}), $state->{members}{"packages/recovery.$stream"},
                "exact recovery $stream survives collection");
        }
        is_deeply(collect($state, sub { croak 'Recovery report attempted transport'; }), $report,
            'cached recovery reporting performs no execution');
    }
    return;
}

sub test_package_recovery_validation {
    for my $missing (qw(packages.recovered packages/recovery.result packages/recovery.capture
        packages/recovery.stdout packages/recovery.stderr)) {
        my $state = recovery_fixture('verify', 0, 1);
        delete $state->{members}{$missing};
        seal_interrupted($state);
        reject($state, "missing recovery member $missing");
    }
    for my $change (
        ['packages.recovered', 'run', 'b' x 32], ['packages.recovered', 'attempt', '../other'],
        ['packages.recovered', 'format', 'xcat-freebsd-postscript-package-recovery-9'],
        ['packages.recovered', 'snapshot', 'b' x 64], ['packages.recovered', 'plan', 'b' x 64],
        ['packages.recovered', 'initial-sha256', 'bad'], ['packages.recovered', 'mode', 'update'],
        ['packages.recovered', 'execution', 'success'], ['packages.recovered', 'request-sha256', 'f' x 64],
        ['packages.recovered', 'complete', 'no'],
        ['packages/recovery.result', 'scope', 'installed'], ['packages/recovery.result', 'execution', 'success'],
        ['packages/recovery.result', 'format', 'xcat-freebsd-local-recover-9'],
        ['packages/recovery.result', 'plan-reference', 'b' x 64], ['packages/recovery.result', 'request-sha256', 'b' x 64],
        ['packages/recovery.result', 'pkg', '2.6.1'], ['packages/recovery.result', 'complete', 'no'],
        ['packages/recovery.result', 'operation-scope', 'local-update'], ['packages/recovery.result', 'packages', '0'],
        ['packages/recovery.result', 'packages', '8193'], ['packages/recovery.result', 'packages', '04'],
        ['packages/recovery.result', 'actions-sha256', 'bad'], ['packages/recovery.result', 'rejected-sha256', 'bad'],
        ['packages/recovery.result', 'started-sha256', 'bad'], ['packages/recovery.result', 'managed-request-sha256', 'a' x 64],
        ['packages/recovery.capture', 'status', '1'], ['packages/recovery.capture', 'stdout-bytes', '00'],
        ['packages/recovery.capture', 'stdout-open', 'yes'], ['packages/recovery.capture', 'stdout-truncated', 'yes'],
        ['packages/recovery.capture', 'stderr-open', 'yes'], ['packages/recovery.capture', 'stderr-truncated', 'yes']) {
        my $state = recovery_fixture('verify', 0, 1);
        my ($member, $key, $value) = @$change;
        $state->{members}{$member} =~ s/^$key\t[^\n]+/$key\t$value/mx;
        seal_recovery($state);
        reject($state, "recovery $member $key=$value");
        ok(!-e "$state->{root}/report-$run", 'invalid recovery publishes no report');
    }
    return;
}

sub preservation_fixture {
    my ($mode, $reason) = @_;
    my $state = recovery_fixture($mode, 0, 0);
    my $members = $state->{members};
    delete @{$members}{grep { m{\Apackages(?:[.]recovered|/recovery[.])}x } keys %$members};
    my $native_digest = '-';
    if ($reason eq 'native-rejected') {
        my $name = "packages/local-$mode.rejected";
        $members->{$name} = fields('xcat-freebsd-local-rejection-1', [scope => "local-$mode"],
            ['plan-reference' => 'e' x 64], ['request-sha256' => '3' x 64],
            ['prior-request-sha256' => 'a' x 64], ['config-sha256' => 'b' x 64],
            [pkg => '2.6.2'], [apply => 'not-started'], [outcome => 'rejected'], [complete => 'yes']);
        $native_digest = sha256_hex($members->{$name});
    }
    $members->{'packages.preserved'} = fields('xcat-freebsd-postscript-package-preserved-1',
        [run => $run], [snapshot => $state->{export}{snapshot}], [plan => 'e' x 64], [mode => $mode],
        ['initial-sha256' => '1' x 64], ['previous-sha256' => '2' x 64], [reason => $reason],
        ['native-sha256' => $native_digest], [execution => 'uncertain'], [complete => 'yes']);
    seal_interrupted($state);
    return $state;
}

sub test_package_preservation {
    for my $mode (qw(verify update)) {
        for my $reason (qw(no-actions native-rejected)) {
            my $state = preservation_fixture($mode, $reason);
            my $report = eval { collect($state); };
            ok($report, "$mode $reason preservation is reportable");
            if (!$report) { diag($@); next; }
            is($report->{receipt}{outcome}, 'uncertain', 'preservation retains uncertainty');
            is($report->{receipt}{complete}, 'no', 'preservation does not complete execution');
            is($report->{package_preservation}{scope}, 'previous-provenance', 'the previous provenance is retained');
            is($report->{package_preservation}{reason}, $reason, 'report identifies the no-apply proof');
            is_deeply([map { $_->{state} } @{$report->{entries}}], [qw(not-run not-run not-run)],
                'no selected script executed');
            is_deeply(collect($state, sub { croak 'Preservation report attempted transport'; }), $report,
                'cached reporting does not repeat release');
        }
    }
    return;
}

sub test_package_preservation_validation {
    for my $change ([format => 'bad'], [run => 'b' x 32], [snapshot => 'b' x 64], [plan => 'b' x 64],
        [mode => 'update'], ['initial-sha256' => 'bad'], ['previous-sha256' => 'bad'],
        [reason => 'unknown'], ['native-sha256' => 'b' x 64], [execution => 'success'], [complete => 'no']) {
        my $state = preservation_fixture('verify', 'no-actions');
        my ($key, $value) = @$change;
        $state->{members}{'packages.preserved'} =~ s/^$key\t[^\n]+/$key\t$value/mx;
        seal_interrupted($state);
        reject($state, "preservation $key=$value");
    }
    for my $change ([format => 'bad'], [scope => 'local-update'], ['plan-reference' => 'b' x 64],
        ['request-sha256' => 'b' x 64], ['prior-request-sha256' => 'bad'], ['config-sha256' => 'bad'],
        [pkg => '2.6.1'], [apply => 'started'], [outcome => 'success'], [complete => 'no']) {
        my $state = preservation_fixture('verify', 'native-rejected');
        my ($key, $value) = @$change;
        my $native = \$state->{members}{'packages/local-verify.rejected'};
        $$native =~ s/^$key\t[^\n]+/$key\t$value/mx;
        my $digest = sha256_hex($$native);
        $state->{members}{'packages.preserved'} =~ s/^native-sha256\t[^\n]+/native-sha256\t$digest/mx;
        seal_interrupted($state);
        reject($state, "preserved rejection $key=$value");
    }
    for my $missing (qw(packages.preserved packages/local-verify.rejected)) {
        my $state = preservation_fixture('verify', 'native-rejected');
        delete $state->{members}{$missing};
        seal_interrupted($state);
        reject($state, "missing preservation member $missing");
    }
    for my $kind (qw(recovery preservation)) {
        for my $conflict (qw(script completion)) {
            my $state = $kind eq 'recovery' ? recovery_fixture('verify', 0, 1)
              : preservation_fixture('verify', 'no-actions');
            my $other = interrupted_fixture(0);
            if ($conflict eq 'script') {
                $state->{members}{'interrupted.results'} = $other->{members}{'interrupted.results'};
                for my $name (grep { m{\Aentries/}x } keys %{$other->{members}}) {
                    $state->{members}{$name} = $other->{members}{$name};
                }
            } else {
                $state->{members}{'packages.result'} = $other->{members}{'packages.result'};
            }
            seal_interrupted($state);
            reject($state, "$kind conflicts with $conflict");
        }
    }
    return;
}

subtest 'package rejection retains failed and not-run results' => sub {
    for my $phase (qw(preparation native)) {
        for my $variant (['verify', undef], ['update', undef], ['verify', '6' x 64]) {
            my $state = rejected_fixture($phase, @$variant);
            my $report = eval { collect($state); };
            ok($report, "$phase $variant->[0] rejection is reportable");
            if (!$report) { diag($@); next; }
            is($report->{kind}, 'freebsd-postscript-report-v3', 'failure has a distinct report contract');
            is($report->{receipt}{outcome}, 'failed', 'rejection is a terminal failure');
            is($report->{receipt}{complete}, 'yes', 'failed report is complete');
            is($report->{entries}[0]{state}, 'not-run', 'selected script did not run');
            is($report->{entries}[0]{status}, undef, 'unstarted script has no invented exit status');
            is($report->{entries}[0]{started_epoch}, undef, 'unstarted script has no invented start time');
            is($report->{entries}[0]{stdout}, undef, 'unstarted script has no invented log');
            is($report->{prerequisite}{phase}, $phase, 'report retains the failed phase');
            is(read_file($report->{prerequisite}{stderr}{path}), "Package prerequisite diagnostic\n", 'exact bounded diagnostic is retained');
            is_deeply(collect($state, sub { croak 'Rejected run attempted transport'; }), $report,
                'report retry reads retained evidence without executing');
        }
    }
    done_testing();
};

subtest 'package rejection cannot claim an applied or executed operation' => sub {
    my %mutations = (
        'application-started' => sub { $_[0]{'packages/local-verify.rejected'} =~ s/^apply\tnot-started$/apply\tstarted/mx; },
        'native-success' => sub { $_[0]{'packages/local-verify.rejected'} =~ s/^outcome\trejected$/outcome\tsuccess/mx; },
        'wrong-native-scope' => sub { $_[0]{'packages/local-verify.rejected'} =~ s/^scope\tlocal-verify$/scope\tlocal-update/mx; },
        'wrong-native-request' => sub { $_[0]{'packages/local-verify.rejected'} =~ s/^request-sha256\t[^\n]+/"request-sha256\t" . ('f' x 64)/emx; },
        'invalid-configuration-binding' => sub { $_[0]{'packages/local-verify.rejected'} =~ s/^config-sha256\t[^\n]+/config-sha256\tbad/mx; },
        'missing-native-proof' => sub { delete $_[0]{'packages/local-verify.rejected'}; },
        'preparation-with-native-proof' => sub { $_[0]{'packages.rejected'} =~ s/^phase\tnative$/phase\tpreparation/mx; },
        'invalid-package-head' => sub { $_[0]{'packages.rejected'} =~ s/^previous-head-sha256\t[^\n]+/previous-head-sha256\tbad/mx; },
        'script-executed' => sub { $_[0]{results} = "1\tcomplete\t0\t-\t-\n"; },
        'unstarted-script-log' => sub { $_[0]{'entries/1/stdout'} = 'unexpected'; },
        'driver-executed' => sub { $_[0]{'driver.complete'} = "1\n"; },
        'success-receipt' => sub { $_[0]{result} =~ s/^outcome\tfailed$/outcome\tsuccess/mx; },
        'invalid-worker' => sub { $_[0]{started} =~ s/^pid\t123$/pid\t0/mx; },
    );
    for my $fault (sort keys %mutations) {
        my $state = rejected_fixture('native', 'verify');
        $mutations{$fault}->($state->{members});
        seal_rejected($state);
        reject($state, $fault);
        ok(!-e "$state->{root}/report-$run", 'invalid rejected evidence is not published');
    }
    my $changed = rejected_fixture('preparation', 'verify');
    $changed->{members}{'prerequisite.stderr'} .= 'changed';
    reject($changed, 'changed prerequisite diagnostic');
    done_testing();
};

if ($ENV{XCAT_FREEBSD_REJECTION_ONLY}) { done_testing(); exit 0; }

subtest 'boot reports require the bound worker start' => sub {
    for my $partial (0, 1) {
        my $make = sub { return $partial ? interrupted_fixture(0, '6' x 64) : fixture(2, 0, '6' x 64); };
        my $state = $make->();
        my $report = eval { collect($state); };
        ok($report, $partial ? 'interrupted boot retains its report' : 'completed boot retains its report');
        if (!$report) { diag($@); next; }
        is($report->{receipt}{outcome}, $partial ? 'uncertain' : 'success', 'boot binding preserves the execution outcome');
        is_deeply(collect($state, sub { croak 'Retained boot report attempted transport'; }), $report,
            'boot report retry uses retained evidence');
        for my $field (qw(format run snapshot boot pid process)) {
            my $invalid = $make->();
            my $value = $field eq 'boot' || $field eq 'snapshot' ? 'a' x 64
              : $field eq 'run' ? 'b' x 32 : 'wrong';
            $invalid->{members}{started} =~ s/^\Q$field\E\t[^\n]+/$field\t$value/mx;
            seal_interrupted($invalid) if $partial;
            reject($invalid, "wrong boot worker $field");
            ok(!-e "$invalid->{root}/report-$run", 'invalid worker binding publishes no report');
        }
    }
    done_testing();
};

subtest 'timed and legacy results retain exact status and binary logs' => \&test_results;
subtest 'clock corrections preserve timestamps and invalid elapsed times fail' => \&test_monotonic_times;
subtest 'bounded output retains truncation and inherited-pipe flags' => \&test_output_limits;
subtest 'delivery receipt, export and transport status bind collection' => \&test_delivery;
subtest 'archive members and every evidence layer are checked' => \&test_evidence;
subtest 'lost copy acknowledgement retries collection without execution' => \&test_retry;
subtest 'release removes successful attempts and retains failures' => \&test_release_attempts;
subtest 'retained files, report and locking remain checked' => \&test_retained;
subtest 'interrupted runs preserve complete uncertain and unstarted entries' => \&test_interrupted;
subtest 'interrupted evidence binds release and every selected entry' => \&test_interrupted_validation;
subtest 'observed release binds process and capture completion without inventing script exits' => \&test_observed_release;
subtest 'framework failure is terminal without inventing unfinished script results' => \&test_framework_failure;
subtest 'interrupted prerequisite logs retain their bytes and limits' => \&test_interrupted_prerequisite_logs;
subtest 'recovered package provenance leaves execution uncertain' => \&test_package_recovery;
subtest 'package recovery binds its scope receipts capture and complete roster' => \&test_package_recovery_validation;
subtest 'unstarted package application preserves previous provenance' => \&test_package_preservation;
subtest 'preservation binds no-apply evidence and unstarted scripts' => \&test_package_preservation_validation;

done_testing;
