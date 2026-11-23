#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../lib";
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempdir);
use JSON;
use POSIX ();
use Storable qw(dclone);
use Test::More;
use Time::HiRes qw(time sleep);
use XCAT::Test::PostageFixture qw(fixture write_file read_file inventory
    $root $custom $stock $template $expected);
require xCAT::Postage;
use xCAT::FreeBSDPostscript;

my $private = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;
my $json = JSON->new->canonical->utf8;
my ($mode, $witness);

{
    package XCAT::CaptureTest;
    sub observe {
        if ($mode eq 'isolation') {
            my $old = $ENV{XCAT_CAPTURE_PARENT};
            $ENV{XCAT_CAPTURE_PARENT} = 'child';
            return $json->encode({ pid => $$, environment => $old,
                unset_present => exists($ENV{XCAT_CAPTURE_UNSET}) ? 1 : 0,
                empty_present => exists($ENV{XCAT_CAPTURE_EMPTY}) ? 1 : 0,
                empty_value => $ENV{XCAT_CAPTURE_EMPTY},
                inherited_db => scalar(grep { defined($_) } values %{$::XCAT_DBHS}) });
        }
        if ($mode eq 'throw') {
            print "private pre-exception stdout" or die $!;
            print STDERR "private pre-exception stderr" or die $!;
            die "private hook failure: secret-1847\n";
        }
        if ($mode eq 'signal') {
            kill('TERM', $$) or die $!;
            Time::HiRes::sleep(20);
        }
        if ($mode eq 'timeout') {
            $SIG{TERM} = 'IGNORE';
            Time::HiRes::sleep(20);
        }
        if ($mode eq 'stdout-exact' || $mode eq 'stderr-exact') {
            my $bytes = 'x' x 1048576;
            if ($mode eq 'stdout-exact') { print $bytes or die $!; }
            else { print STDERR $bytes or die $!; }
        }
        if ($mode eq 'stdout' || $mode eq 'stderr') {
            my $bytes = 'x' x 1048577;
            if ($mode eq 'stdout') { print $bytes or die $!; }
            else { print STDERR $bytes or die $!; }
        }
        if ($mode eq 'streams') {
            print "private stdout\0secret-1847" or die $!;
            print STDERR "private stderr\0secret-1847" or die $!;
        }
        if ($mode eq 'closed-descendant' || $mode eq 'open-descendant') {
            pipe(my $reader, my $writer) or die $!;
            my $child = fork();
            die $! unless defined($child);
            if (!$child) {
                close($reader) or die $!;
                $SIG{TERM} = 'IGNORE';
                XCAT::Test::PostageFixture::write_file($witness, "$$\n");
                syswrite($writer, 'r') == 1 or die $!;
                close($writer) or die $!;
                POSIX::close($_) for $mode eq 'closed-descendant' ? (0 .. 255) : ();
                Time::HiRes::sleep(20);
                POSIX::_exit(0);
            }
            close($writer) or die $!;
            sysread($reader, my $byte, 1) == 1 or die $!;
            close($reader) or die $!;
        }
        return 'hook-result';
    }
}

sub new_store { return "$private/capture-" . ++$sequence; }

sub entries {
    my ($directory, $pattern) = @_;
    return [] unless -d $directory;
    opendir(my $handle, $directory) or croak $!;
    my @names = sort grep { /$pattern/ } readdir($handle);
    closedir($handle) or croak $!;
    return \@names;
}

sub failed_capture {
    my ($directory, $phase, @options) = @_;
    my $result;
    my $ok = eval {
        $result = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $directory, @options);
        1;
    };
    ok(!$ok, "$phase failure is not successful capture");
    is($@, "FreeBSD postscript capture failed during $phase\n", "$phase exposes only its fixed public error");
    ok(!defined($result), "$phase failure returns no descriptor");
    is_deeply(entries($directory, qr/\A[0-9a-f]{64}\z/x), [], "$phase failure has no published content");
    my $attempts = entries($directory, qr/\A[.]attempt[.]/x);
    is(scalar(@$attempts), 1, "$phase failure retains exactly its private attempt");
    return "$directory/$attempts->[0]";
}

sub hook_template {
    write_file($custom, $template . 'HOOK=#Subroutine:XCAT::CaptureTest::observe:$NODE#' . "\n");
    return;
}

sub protected_file {
    my ($path, $name) = @_;
    my @state = lstat($path);
    ok(@state && -f _ && !-l _, "$name is a real regular file");
    is($state[2] & oct('07777'), oct('0600'), "$name is private and nonexecutable");
    is($state[4], $>, "$name has the capture owner");
    is($state[3], 1, "$name has no hard links");
    return;
}

sub exact_capture_cases {
    fixture(1);
    my $store = new_store();
    my $before = inventory();
    my $rows = dclone(\%xCAT::Table::rows);
    my $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store);
    is(read_file("$capture->{directory}/rendered"), $expected,
        'real selected custom rendering preserves exact bytes, quoting and blank lines');
    is($capture->{rendered_bytes}, length($expected), 'descriptor gives exact byte count');
    is($capture->{rendered_sha256}, sha256_hex($expected), 'descriptor binds exact render bytes');
    unlike($json->encode($capture), qr/private fixture value/, 'public descriptor contains no rendered secret');
    is_deeply([sort keys %$capture], [sort qw(id directory node nodesetstate rendered_sha256 rendered_bytes attempt)],
        'public capture return has only descriptor fields');
    is_deeply(inventory(), $before, 'real renderer leaves public template trees unchanged');
    is_deeply(\%xCAT::Table::rows, $rows, 'child rendering leaves parent table fixtures unchanged');
    protected_file("$capture->{directory}/rendered", 'rendered bytes');
    protected_file("$capture->{directory}/manifest.json", 'manifest');
    my $manifest_bytes = read_file("$capture->{directory}/manifest.json");
    is(sha256_hex($manifest_bytes), $capture->{id}, 'content identity is the exact canonical manifest digest');
    my $manifest = $json->decode($manifest_bytes);
    is($manifest->{kind}, 'freebsd-postscript-render-v1', 'manifest has the capture-only format');
    is_deeply([map { $_->{name} } @{$manifest->{markers}}],
        [qw(postscripts defaults-postscripts osimage-postscripts node-postscripts
            postbootscripts defaults-postbootscripts osimage-postbootscripts node-postbootscripts)],
        'markers retain actual default-image-node order inside both phases');
    for my $range (@{$manifest->{markers}}) {
        is(substr($expected, $range->{begin}, $range->{body} - $range->{begin}),
            "# $range->{name}-start-here\n", 'stored start range selects the actual whole marker line');
        is(substr($expected, $range->{end}, $range->{after} - $range->{end}),
            "# $range->{name}-end-here\n", 'stored end range selects the actual whole marker line');
    }
    my $second = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store);
    is($second->{id}, $capture->{id}, 'repeat identical render reuses its content identity');
    isnt($second->{attempt}, $capture->{attempt}, 'repeat attempt keeps distinct diagnostic originals');
    is_deeply(entries($store, qr/\A[0-9a-f]{64}\z/x), [$capture->{id}], 'only one content directory is published');
    $xCAT::Table::rows{postscripts}[0]{postscripts} = 'changed-after-capture';
    @xCAT::Table::opened = ();
    my $loaded = xCAT::FreeBSDPostscript::read_capture($capture->{id}, directory => $store);
    is($loaded->{id}, $capture->{id}, 'readback preserves the old capture after table changes');
    is(read_file("$loaded->{directory}/rendered"), $expected, 'readback never rerenders changed selection');
    is_deeply(\@xCAT::Table::opened, [], 'readback opens no tables');
    fixture(0);
    $store = new_store();
    my $stock_expected = $expected;
    $stock_expected =~ s/ORIGIN='custom'/ORIGIN='stock'/;
    $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store);
    is(read_file("$capture->{directory}/rendered"), $stock_expected, 'absent custom template uses the real stock path');
    ok(!-e "$root/tftp/mypostscripts", 'stock capture creates no public directory');
    fixture(1);
    my $shell_witness = "$private/shell-must-not-run";
    my $shell_text = "\n: > '$shell_witness'\nprintf '%s\\n' \"quoted argument\" | sed 's/a/b/'\n";
    write_file($custom, $template . $shell_text);
    $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => new_store());
    is(read_file("$capture->{directory}/rendered"), $expected . $shell_text,
        'administrator shell quoting and control operators remain opaque exact content');
    ok(!-e $shell_witness, 'capture does not execute target shell content on the management node');
    return;
}

sub inherited_environment_cases {
    fixture(1);
    $mode = 'isolation';
    hook_template();
    local $ENV{XCAT_CAPTURE_PARENT} = 'parent';
    local $ENV{XCAT_CAPTURE_UNSET};
    local $ENV{XCAT_CAPTURE_EMPTY} = '';
    my $capture = eval { xCAT::FreeBSDPostscript::capture('node1', 'install', directory => new_store()); };
    is($@, '', 'undefined daemon environment bindings do not reject rendering');
    ok($capture, 'the real child publishes a capture');
    return unless $capture;
    my ($hook) = read_file("$capture->{directory}/rendered") =~ /^HOOK=(.+)$/m;
    my $observed = $json->decode($hook);
    is($observed->{unset_present}, 0, 'undefined binding is absent in the child environment');
    is($observed->{empty_present}, 1, 'defined empty binding remains present');
    is($observed->{empty_value}, '', 'defined empty value is unchanged');
    is($observed->{environment}, 'parent', 'ordinary rendering environment is inherited');
    ok(exists($ENV{XCAT_CAPTURE_UNSET}) && !defined($ENV{XCAT_CAPTURE_UNSET}), 'parent binding remains untouched');
    is($ENV{XCAT_CAPTURE_EMPTY}, '', 'parent empty value remains untouched');
    return;
}

sub isolation_cases {
    fixture(1);
    my $store = new_store();
    $mode = 'isolation';
    hook_template();
    local $ENV{XCAT_CAPTURE_PARENT} = 'parent';
    local $::XCAT_DBHS = { fixture => { Active => 1 } };
    my $parent = $$;
    my $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store);
    my ($hook) = read_file("$capture->{directory}/rendered") =~ /^HOOK=(.+)$/m;
    my $observed = $json->decode($hook);
    isnt($observed->{pid}, $parent, 'trusted hook ran in the actual child');
    is($observed->{environment}, 'parent', 'child receives inherited rendering environment');
    is($observed->{inherited_db}, 0, 'real xfork clears inherited database handles before rendering');
    is($ENV{XCAT_CAPTURE_PARENT}, 'parent', 'trusted hook does not alter parent environment');
    is_deeply($::XCAT_DBHS, { fixture => { Active => 1 } }, 'parent database handle is preserved');
    fixture(1);
    $mode = 'streams';
    hook_template();
    $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => new_store());
    is(read_file("$capture->{attempt}/stdout"), "private stdout\0secret-1847", 'raw child stdout remains private and exact');
    is(read_file("$capture->{attempt}/stderr"), "private stderr\0secret-1847", 'raw child stderr remains private and separate');
    unlike(read_file("$capture->{directory}/rendered"), qr/private std/, 'diagnostic bytes are not appended to rendered bytes');
    unlike($json->encode($capture), qr/secret-1847/, 'descriptor does not expose diagnostic secrets');
    my $outcome = $json->decode(read_file("$capture->{attempt}/outcome.json"));
    is($outcome->{callback_complete}, 1, 'accepted capture has authenticated internal completion');
    is($outcome->{exitcode}, 0, 'accepted capture records actual zero exit');
    is($outcome->{signal}, 0, 'accepted capture records actual nonsignal completion');
    return;
}

sub render_failure_cases {
    for my $case (qw(missing unknown excluded export throw unreadable)) {
        fixture($case eq 'missing' ? 0 : 1);
        my $store = new_store();
        unlink($stock) or croak $! if $case eq 'missing';
        $xCAT::Table::rows{nodelist} = [] if $case eq 'unknown';
        $xCAT::Table::rows{nodetype}[0]{os} = '' if $case eq 'excluded';
        $xCAT::Table::rows{nodetype}[0]{arch} = '' if $case eq 'excluded';
        write_file($custom, $template . "export INVALID-NAME\n") if $case eq 'export';
        if ($case eq 'throw') { $mode = 'throw'; hook_template(); }
        my $before = inventory();
        chmod(0, $custom) == 1 or croak $! if $case eq 'unreadable';
        my $attempt = failed_capture($store, 'rendering');
        chmod(0644, $custom) == 1 or croak $! if $case eq 'unreadable';
        is_deeply(inventory(), $before, "$case leaves renderer-owned public files unchanged");
        protected_file("$attempt/failure", "$case private failure");
        if ($case eq 'unknown' || $case eq 'excluded' || $case eq 'export') {
            like(read_file("$attempt/callbacks.jsonl"), qr/error/, "$case preserves actual renderer error callbacks privately");
        }
        if ($case eq 'throw') {
            like(read_file("$attempt/setup"), qr/private hook failure: secret-1847/, 'original hook exception remains private');
            is(read_file("$attempt/stdout"), 'private pre-exception stdout', 'failed hook retains buffered stdout privately');
            is(read_file("$attempt/stderr"), 'private pre-exception stderr', 'failed hook retains buffered stderr privately');
        }
    }
    return;
}

sub marker_cases {
    for my $case (
        ['missing phase', sub { my $s = shift; $s =~ s/^# postbootscripts-(?:start|end)-here\n//mg; return $s; }],
        ['duplicate phase', sub { return $_[0] . "# postscripts-start-here\n# postscripts-end-here\n"; }],
        ['crossed phases', sub { my $s = shift; $s =~ s/postscripts-end-here/postbootscripts-end-here/; return $s; }],
        ['ambiguous inner section', sub { return "# node-postscripts-start-here\n# node-postscripts-end-here\n" . $_[0]; }],
    ) {
        fixture(1);
        write_file($custom, $case->[1]->($template));
        my $attempt = failed_capture(new_store(), 'artifact validation');
        my $outcome = $json->decode(read_file("$attempt/outcome.json"));
        is($outcome->{callback_complete}, 1, "$case->[0] reaches the real successful renderer before marker rejection");
    }
    fixture(1);
    write_file($custom, "#!/bin/sh\n# postscripts-start-here\n# postscripts-end-here\n"
        . "# postbootscripts-start-here\n# postbootscripts-end-here");
    my $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => new_store());
    is(read_file("$capture->{directory}/rendered"), read_file($custom),
        'empty phases and an absent final newline retain exact valid bytes');
    return;
}

sub artifact_cases {
    for my $case (qw(bytes manifest extra symlink hardlink public-mode)) {
        fixture(1);
        my $store = new_store();
        my $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store);
        my $path = "$capture->{directory}/rendered";
        write_file($path, $expected . "# changed bytes\n") if $case eq 'bytes';
        write_file("$capture->{directory}/manifest.json", "{}\n") if $case eq 'manifest';
        write_file("$capture->{directory}/extra", 'unexpected') if $case eq 'extra';
        if ($case eq 'symlink') {
            unlink($path) or croak $!;
            symlink($custom, $path) or croak $!;
        }
        link($path, "$store/linked-rendered") or croak $! if $case eq 'hardlink';
        chmod(0644, $path) == 1 or croak $! if $case eq 'public-mode';
        my $read;
        my $ok = eval { $read = xCAT::FreeBSDPostscript::read_capture($capture->{id}, directory => $store); 1; };
        ok(!$ok, "$case corruption is rejected through public readback");
        is($@, "FreeBSD postscript capture verification failed\n", "$case has no secret-bearing public diagnostic");
        ok(!defined($read), "$case returns no valid descriptor");
    }
    fixture(1);
    my $store = new_store();
    mkdir($store, 0755) or croak $!;
    my $ok = eval { xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store); 1; };
    ok(!$ok, 'capture rejects an existing nonprivate state directory');
    is((stat($store))[2] & oct('07777'), oct('0755'), 'capture never repairs permissions of an unsafe directory');
    is_deeply(entries($store, qr/./x), ['.', '..'], 'unsafe directory gets no capture attempt');
    return;
}

sub bound_cases {
    for my $stream (qw(stdout stderr)) {
        fixture(1);
        $mode = "$stream-exact";
        hook_template();
        my $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => new_store());
        ok(read_file("$capture->{attempt}/$stream") eq ('x' x 1048576),
            "$stream exact-limit bytes remain private and complete");
        is(length(read_file("$capture->{attempt}/$stream")), 1048576, "$stream exact limit succeeds");
        is(read_file("$capture->{directory}/rendered"), $expected . "HOOK=hook-result\n",
            "$stream diagnostics do not change the rendered artifact");
        my $outcome = $json->decode(read_file("$capture->{attempt}/outcome.json"));
        is($outcome->{exitcode}, 0, "$stream exact limit preserves actual successful exit");
        is($outcome->{streams_complete}, 1, "$stream exact limit reaches real stream completion");
        is_deeply($outcome->{overflow}, {}, "$stream exact limit has no excess-byte witness");
    }
    for my $stream (qw(stdout stderr)) {
        fixture(1);
        $mode = $stream;
        hook_template();
        my $attempt = failed_capture(new_store(), 'rendering');
        is(length(read_file("$attempt/$stream")), 1048576, "$stream overflow retains only its bounded prefix");
        my $outcome = $json->decode(read_file("$attempt/outcome.json"));
        is($outcome->{overflow}{$stream}, '78', "$stream overflow retains the actual excess-byte witness");
        like($outcome->{failure}, qr/exceeds its output limit/, "$stream truncation is explicitly failed");
    }
    for my $terminal (qw(timeout signal)) {
        fixture(1);
        $mode = $terminal;
        hook_template();
        my $start = time();
        my $attempt = failed_capture(new_store(), 'rendering', timeout => 0.2);
        cmp_ok(time() - $start, '<', 3, "$terminal capture and cleanup remain bounded");
        my $outcome = $json->decode(read_file("$attempt/outcome.json"));
        is($outcome->{signal}, $terminal eq 'signal' ? 15 : 9, "$terminal preserves its actual wait signal");
        is($outcome->{callback_complete}, 0, "$terminal has no invented callback completion");
    }
    fixture(1);
    my $tail = 'x' x (8388608 - length($expected));
    write_file($custom, $template . $tail);
    my $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => new_store());
    is($capture->{rendered_bytes}, 8388608, 'exact render limit succeeds');
    ok(read_file("$capture->{directory}/rendered") eq $expected . $tail, 'exact-limit bytes are not normalized');
    write_file($custom, $template . $tail . 'x');
    failed_capture(new_store(), 'rendering');
    return;
}

sub descendant_cases {
    for my $closed (0, 1) {
        fixture(1);
        $mode = $closed ? 'closed-descendant' : 'open-descendant';
        $witness = "$private/child-" . ++$sequence;
        hook_template();
        my ($attempt, $capture);
        if ($closed) {
            $capture = xCAT::FreeBSDPostscript::capture('node1', 'install',
                directory => new_store(), timeout => 0.4);
            $attempt = $capture->{attempt};
            ok(defined($capture->{id}), 'closed-FD child permits capture only after owned cleanup');
        } else {
            $attempt = failed_capture(new_store(), 'rendering', timeout => 0.4);
        }
        my $outcome = $json->decode(read_file("$attempt/outcome.json"));
        my $pid = read_file($witness);
        chomp($pid);
        croak 'Invalid fixture child identity' unless $pid =~ /\A[1-9][0-9]*\z/x && $pid != $$;
        my $status = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'stat=', '-p', $pid], timeout => 2);
        my $stopped = $status->{exitcode} != 0 || $status->{stdout} =~ /\A\s*Z/x;
        if (!$stopped) {
            my $group = -$outcome->{cleanup}{target};
            my $process = xCAT::FreeBSDPkg::run_command(['/bin/ps', '-o', 'pgid=', '-p', $pid], timeout => 2);
            croak 'Refusing cleanup outside fixture group' unless $process->{exitcode} == 0
              && $process->{stdout} =~ /\A\s*\Q$group\E\s*\z/x;
            kill('KILL', $pid) or croak $!;
        }
        ok($stopped, $closed ? 'closed-FD child is stopped before capture returns' : 'pipe-holder child is stopped on failed capture');
        is($outcome->{streams_complete}, $closed ? 1 : 0, 'capture records actual stream completion separately');
    }
    return;
}

sub durable_failure_cases {
    my $native_sync = \&IO::Handle::sync;
    for my $member (qw(rendered manifest.json)) {
        fixture(1);
        my $store = new_store();
        my $calls = "$private/sync-fault-" . ++$sequence;
        my $attempt;
        {
            no warnings 'redefine';
            local *IO::Handle::sync = sub {
                my ($handle) = @_;
                my $name = readlink('/proc/' . $$ . '/fd/' . fileno($handle));
                if (defined($name) && index($name, "$store/") == 0 && $name =~ m{/\Q$member\E\z}x) {
                    write_file($calls, $name);
                    return 0;
                }
                return $native_sync->(@_);
            };
            $attempt = failed_capture($store, $member eq 'rendered' ? 'rendering' : 'artifact validation');
        }
        like(read_file($calls), qr{/\Q$member\E\z}x, 'fault reaches the real created capture member fsync');
        like(read_file("$attempt/failure"), qr/(?:Incomplete postscript render|Cannot sync capture file)/,
            'durable write failure retains a private failure record');
        is(\&IO::Handle::sync, $native_sync, 'native fsync method is restored after the isolated fault');
    }
    return;
}

sub callback_bound_cases {
    my $prefix = "In your configuration, the invalid charactor '-' is used in the following names: ";
    my $empty = $json->encode({ data => [], error => [$prefix . '-'], errorcode => [1] }) . "\n";
    for my $extra (0, 1) {
        fixture(1);
        my $name = '-' . ('x' x (1048576 - length($empty) + $extra));
        my $record = $json->encode({ data => [], error => [$prefix . $name], errorcode => [1] }) . "\n";
        write_file($custom, $template . "export $name\n");
        my $attempt = failed_capture(new_store(), 'rendering');
        my $actual = read_file("$attempt/callbacks.jsonl");
        if (!$extra) {
            is(length($actual), 1048576, 'exact callback JSONL byte limit is retained');
            ok($actual eq $record, 'exact-limit callback retains the real renderer error record');
            like(read_file("$attempt/setup"), qr/Postscript rendering failed/,
                'exact-limit callback reaches the ordinary renderer failure');
        } else {
            ok($actual eq '', 'oversize first callback is rejected before any JSONL bytes are written');
            like(read_file("$attempt/setup"), qr/Render callbacks exceed their limit/,
                'callback overflow has the private size failure, not ordinary renderer failure');
        }
    }
    return;
}

sub parent_sync_failure_case {
    fixture(1);
    my $store = new_store();
    my $calls = "$private/parent-sync-fault-" . ++$sequence;
    my $native_sync = \&IO::Handle::sync;
    my ($capture, $ok, $error);
    {
        no warnings 'redefine';
        local *IO::Handle::sync = sub {
            my ($handle) = @_;
            my $name = readlink('/proc/' . $$ . '/fd/' . fileno($handle));
            if (defined($name) && $name eq $store) {
                my $visible = entries($store, qr/\A[0-9a-f]{64}\z/x);
                if (@$visible == 1) {
                    write_file($calls, "$name\n$visible->[0]\n");
                    return 0;
                }
            }
            return $native_sync->(@_);
        };
        $ok = eval {
            $capture = xCAT::FreeBSDPostscript::capture('node1', 'install', directory => $store);
            1;
        };
        $error = $@;
    }
    ok(!$ok, 'parent fsync failure after rename is not a successful capture');
    is($error, "FreeBSD postscript capture failed during artifact validation\n",
        'post-rename failure exposes only the fixed public error');
    ok(!defined($capture), 'post-rename failure returns no deployable descriptor');
    my ($observed_path, $id) = split(/\n/x, read_file($calls));
    is($observed_path, $store, 'fault reaches the actual parent handle after content becomes visible');
    is_deeply(entries($store, qr/\A[0-9a-f]{64}\z/x), [$id],
        'post-rename failure retains the visible content as evidence');
    my $attempts = entries($store, qr/\A[.]attempt[.]/x);
    is(scalar(@$attempts), 1, 'post-rename failure retains its private attempt');
    is(read_file("$store/$attempts->[0]/failure"), "Cannot sync capture directory\n",
        'post-rename failure retains the original private cause');
    is(read_file("$store/$id/rendered"), $expected, 'retained visible content has the exact rendered bytes');
    my $readback = xCAT::FreeBSDPostscript::read_capture($id, directory => $store);
    is($readback->{id}, $id, 'readback validates current content, not historical durability');
    ok(!exists($readback->{attempt}), 'readback cannot supply a successful capture attempt');
    is(\&IO::Handle::sync, $native_sync, 'parent fsync observer is restored before readback completes');
    return;
}

subtest 'exact real render and private immutable descriptor' => sub { exact_capture_cases(); done_testing(); };
subtest 'real child isolation and separate private diagnostics' => sub { isolation_cases(); done_testing(); };
subtest 'inherited environment omits undefined daemon bindings' => sub { inherited_environment_cases(); done_testing(); };
subtest 'real renderer failures remain private failed attempts' => sub { render_failure_cases(); done_testing(); };
subtest 'exact marker validation without shell parsing' => sub { marker_cases(); done_testing(); };
subtest 'public readback rejects changed artifact identity' => sub { artifact_cases(); done_testing(); };
subtest 'bounded exact output and failed native terminal states' => sub { bound_cases(); done_testing(); };
subtest 'real rendering descendants cannot outlive capture completion' => sub { descendant_cases(); done_testing(); };
subtest 'durable writes fail closed at file and parent boundaries' => sub {
    durable_failure_cases(); parent_sync_failure_case(); done_testing();
};
subtest 'real callback records obey the exact JSONL byte bound' => sub { callback_bound_cases(); done_testing(); };
done_testing();
