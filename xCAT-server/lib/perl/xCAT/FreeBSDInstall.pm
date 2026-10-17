package xCAT::FreeBSDInstall;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Errno qw(ECHILD);
use Fcntl qw(:DEFAULT :flock);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON;
use POSIX qw(WNOHANG);

my $json = JSON->new->canonical;
my %phases = map { $_ => 1 } qw(prepared installing completing installed booted failed cancelled);
my %status_workers;

sub _fail { die "FreeBSD installation: $_[0]\n"; }

sub _identifier {
    my ($value, $length) = @_;
    return defined($value) && !ref($value) && $value =~ /\A[0-9a-f]{$length}\z/;
}

sub _postscript_preparations {
    my $value = shift;
    _fail('Invalid boot postscript preparations') unless ref($value) eq 'HASH'
      && keys(%$value) == 2 && _identifier($value->{firstboot}, 64) && _identifier($value->{repeat}, 64);
    return;
}

sub _postscript_result {
    my $value = shift;
    _fail('Invalid boot postscript result') unless ref($value) eq 'HASH' && keys(%$value) == 2
      && defined($value->{outcome}) && !ref($value->{outcome})
      && $value->{outcome} =~ /\A(?:success|failed|uncertain)\z/
      && defined($value->{complete}) && !ref($value->{complete})
      && $value->{complete} eq ($value->{outcome} eq 'uncertain' ? 'no' : 'yes');
    return;
}

sub _postscript_state {
    my $state = shift;
    for my $key (qw(postscript_boot postscript_first)) {
        next unless exists($state->{$key});
        my $value = $state->{$key};
        _fail('Invalid boot postscript state') unless exists($state->{postscript_preparations})
          && ref($value) eq 'HASH' && _identifier($value->{run}, 32);
        if ($key eq 'postscript_first') {
            _fail('Invalid first boot postscript state') unless keys(%$value) == 2;
            _postscript_result($value->{result});
            next;
        }
        _fail('Invalid boot postscript decision') unless defined($value->{kind}) && !ref($value->{kind})
          && $value->{kind} =~ /\A(?:firstboot|repeat)\z/ && _identifier($value->{boot}, 64)
          && _identifier($value->{preparation}, 64)
          && $value->{preparation} eq $state->{postscript_preparations}{$value->{kind}}
          && !grep { $_ !~ /\A(?:run|kind|boot|preparation|snapshot|result)\z/ } keys %$value;
        _fail('Invalid boot postscript snapshot') if exists($value->{snapshot}) && !_identifier($value->{snapshot}, 64);
        if (exists($value->{result})) {
            _fail('Boot postscript result has no snapshot') unless exists($value->{snapshot});
            _postscript_result($value->{result});
        }
    }
    my $decision = $state->{postscript_boot};
    my $first = $state->{postscript_first};
    _fail('First boot result has no decision') if $first && !$decision;
    _fail('Repeat boot has no first boot result') if $decision && $decision->{kind} eq 'repeat' && !$first;
    if ($first && $decision->{kind} eq 'firstboot') {
        _fail('First boot result differs from its decision') unless $first->{run} eq $decision->{run}
          && exists($decision->{result}) && $json->encode($first->{result}) eq $json->encode($decision->{result});
    }
    return;
}

sub _read_state {
    my ($path, $node) = @_;
    return undef unless -e $path || -l $path;
    sysopen(my $handle, $path, O_RDONLY | O_NOFOLLOW) or _fail("Cannot read state: $!");
    my @stat = stat($handle);
    _fail('Unsafe state file') unless -f $handle && $stat[4] == $> && !($stat[2] & 0077) && $stat[7] <= 65536;
    local $/;
    my $text = <$handle>;
    close($handle) or _fail("Cannot close state: $!");
    my $state = eval { $json->decode($text) };
    _fail('Invalid state file') unless ref($state) eq 'HASH' &&
        defined($state->{version}) && $state->{version} eq '1' &&
        defined($state->{node}) && $state->{node} eq $node &&
        defined($state->{phase}) && $phases{$state->{phase}} &&
        _identifier($state->{generation}, 32) && _identifier($state->{fingerprint}, 64) &&
        (!exists($state->{attempt}) || _identifier($state->{attempt}, 32));
    _fail('State has no installation attempt') if
        $state->{phase} =~ /\A(?:installing|completing|installed|booted|failed)\z/ && !exists($state->{attempt});
    _postscript_preparations($state->{postscript_preparations}) if exists($state->{postscript_preparations});
    _postscript_state($state);
    return $state;
}

sub _save_state {
    my ($directory, $node, $state) = @_;
    my ($handle, $temporary) = tempfile(".$node.XXXXXX", DIR => $directory, UNLINK => 0);
    my $ok = eval {
        chmod(0600, $temporary) == 1 or _fail("Cannot protect state: $!");
        print {$handle} $json->encode($state), "\n" or _fail("Cannot write state: $!");
        $handle->flush or _fail("Cannot flush state: $!");
        $handle->sync or _fail("Cannot sync state: $!");
        close($handle) or _fail("Cannot close state: $!");
        rename($temporary, "$directory/$node.json") or _fail("Cannot publish state: $!");
        sysopen(my $parent, $directory, O_RDONLY | O_NOFOLLOW) or _fail("Cannot open state directory: $!");
        $parent->sync or _fail("Cannot sync state directory: $!");
        close($parent) or _fail("Cannot close state directory: $!");
        1;
    };
    my $error = $@;
    unlink($temporary) if -e $temporary;
    die $error unless $ok;
    return;
}

sub _state_lock {
    my ($node, $options, $boot) = @_;
    _fail('Invalid node name') unless defined($node) && !ref($node) &&
        $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/;
    my $directory = $options->{directory} || '/var/lib/xcat/freebsd-install';
    make_path($directory, { mode => 0700 }) unless -e $directory || -l $directory;
    my @stat = lstat($directory);
    _fail('Unsafe state directory') unless @stat && -d _ && !-l _ && $stat[4] == $> && !($stat[2] & 0077);
    my $suffix = $boot ? '.boot' : '';
    sysopen(my $lock, "$directory/$node$suffix.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0600)
        or _fail("Cannot open installation lock: $!");
    @stat = stat($lock);
    _fail('Unsafe installation lock') unless -f $lock && $stat[4] == $> && !($stat[2] & 0077);
    flock($lock, LOCK_EX | ($boot ? LOCK_NB : 0))
        or _fail($boot ? 'Boot postscript delivery is busy' : "Cannot lock installation: $!");
    return ($directory, $lock);
}

sub _locked {
    my ($node, $options, $operation) = @_;
    my ($directory, $lock) = _state_lock($node, $options);
    my $state = _read_state("$directory/$node.json", $node);
    my $result = $operation->($state, sub { _save_state($directory, $node, $_[0]); });
    close($lock) or _fail("Cannot close installation lock: $!");
    return $result;
}

sub _boot_transaction {
    my ($node, $options, $dispatch, $operation) = @_;
    my (undef, $lock) = _state_lock($node, $options, 1);
    my $state = state($node, %$options);
    my $expected = $json->encode($state);
    my $save = sub {
        my $next = shift;
        return _locked($node, $options, sub {
            my ($current, $publish) = @_;
            _fail('Installation changed during boot postscript delivery') unless $json->encode($current) eq $expected;
            if (defined($next)) {
                $publish->($next);
                $expected = $json->encode($next);
            }
            return;
        });
    };
    my $transport = sub { $save->(); return $dispatch->(@_); };
    my $result = $operation->($state, $save, $transport);
    $save->();
    close($lock) or _fail("Cannot close boot delivery lock: $!");
    return $result;
}

sub _generation {
    sysopen(my $random, '/dev/urandom', O_RDONLY) or _fail("Cannot open random source: $!");
    my $bytes = '';
    while (length($bytes) < 16) {
        my $count = sysread($random, my $part, 16 - length($bytes));
        _fail('Cannot read random source') unless defined($count) && $count > 0;
        $bytes .= $part;
    }
    close($random) or _fail("Cannot close random source: $!");
    return unpack('H*', $bytes);
}

sub prepare {
    my ($node, $fingerprint, %options) = @_;
    _fail('Invalid installation fingerprint') unless _identifier($fingerprint, 64);
    _fail('Invalid publication callback') if exists($options{publish}) && ref($options{publish}) ne 'CODE';
    my $preparations;
    if (exists($options{postscript_preparations})) {
        _postscript_preparations($options{postscript_preparations});
        $preparations = { %{$options{postscript_preparations}} };
        $fingerprint = sha256_hex("xcat-freebsd-install-postscripts-1\n$fingerprint\n" . $json->encode($preparations));
    }
    return _locked($node, \%options, sub {
        my ($state, $save) = @_;
        if ($state) {
            _fail('Stop the node and run nodeset offline before rearming this installation')
                if $state->{phase} =~ /\A(?:installing|completing|failed)\z/;
        }
        unless ($state && $state->{phase} eq 'prepared' && $state->{fingerprint} eq $fingerprint) {
            $state = { version => 1, node => $node, fingerprint => $fingerprint,
                generation => _generation(), phase => 'prepared' };
            $state->{postscript_preparations} = $preparations if defined($preparations);
            $save->($state);
        }
        $options{publish}->($state->{generation}) if $options{publish};
        return $state->{generation};
    });
}

sub state {
    my ($node, %options) = @_;
    return _locked($node, \%options, sub { return $_[0]; });
}

sub cancel {
    my ($node, %options) = @_;
    return _locked($node, \%options, sub {
        my ($state, $save) = @_;
        return 0 unless $state;
        $state->{phase} = 'cancelled';
        $save->($state);
        return 1;
    });
}

sub transition {
    my ($node, $message, $action, %options) = @_;
    _fail('Invalid installation status') unless defined($message) && !ref($message) &&
        $message =~ /\Afreebsd-install-v1 ([0-9a-f]{32}) ([0-9a-f]{32}) (begin|complete|failed|booted)\n?\z/;
    my ($generation, $attempt, $phase) = ($1, $2, $3);
    _fail('Missing installation action') unless ref($action) eq 'CODE';
    return _locked($node, \%options, sub {
        my ($state, $save) = @_;
        _fail('Installation is not armed') unless $state && $state->{phase} ne 'cancelled';
        _fail('Stale installation generation') unless $state->{generation} eq $generation;
        _fail('Another installation attempt owns this generation')
            if exists($state->{attempt}) && $state->{attempt} ne $attempt;
        if ($phase eq 'begin') {
            _fail('Installation cannot begin in this state') unless $state->{phase} =~ /\A(?:prepared|installing)\z/;
            $state->{attempt} = $attempt;
            $state->{phase} = 'installing';
            $save->($state);
            $action->('begin');
        } elsif ($phase eq 'complete') {
            _fail('Installation cannot complete in this state') unless
                $state->{phase} =~ /\A(?:installing|completing|installed|booted)\z/;
            if ($state->{phase} ne 'installed' && $state->{phase} ne 'booted') {
                $state->{phase} = 'completing';
                $save->($state);
                $action->('complete');
                $state->{phase} = 'installed';
                $save->($state);
            }
        } elsif ($phase eq 'booted') {
            _fail('Installation is not complete') unless $state->{phase} =~ /\A(?:installed|booted)\z/;
            if ($state->{phase} ne 'booted') {
                $action->('booted');
                $state->{phase} = 'booted';
                $save->($state);
            }
        } else {
            _fail('Installation cannot fail in this state') unless $state->{phase} =~ /\A(?:prepared|installing|completing|failed)\z/;
            $state->{attempt} = $attempt;
            $state->{phase} = 'failed';
            $save->($state);
            $action->('failed');
        }
        return "freebsd-install-v1 $generation $phase ok\n";
    });
}

sub _command {
    my ($node, $command, $argument, $dispatch) = @_;
    my $response = $dispatch->({ command => [$command], node => [$node], arg => [$argument] });
    _fail("No response from $command") unless ref($response) eq 'HASH';
    my @pending = ($response);
    while (@pending) {
        my $part = shift @pending;
        _fail("Invalid response from $command") unless ref($part) eq 'HASH';
        for my $field (qw(error errorcode)) {
            next unless exists($part->{$field});
            my @values = ref($part->{$field}) eq 'ARRAY' ? @{$part->{$field}} : ($part->{$field});
            _fail("$command failed") if grep { defined($_) && (ref($_) || ($_ ne '' && $_ ne '0')) } @values;
        }
        for my $field (qw(node xcatresponse)) {
            next unless exists($part->{$field});
            _fail("Invalid response from $command") unless ref($part->{$field}) eq 'ARRAY';
            push @pending, @{$part->{$field}};
        }
    }
    return;
}

sub _attribute {
    my ($node, $name, $attribute, $expected) = @_;
    require xCAT::Table;
    my $table = xCAT::Table->new($name);
    _fail("Cannot read $name") unless $table;
    my $entry = $table->getNodeAttribs($node, [$attribute]);
    $table->close();
    _fail("$name.$attribute was not updated") unless $entry &&
        defined($entry->{$attribute}) && $entry->{$attribute} eq $expected;
    return;
}

sub handle_status {
    my ($node, $peer, $message, $dispatch, %options) = @_;
    _fail('Missing command dispatcher') unless ref($dispatch) eq 'CODE';
    require xCAT::NetworkUtils;
    xCAT::NetworkUtils->clearcache();
    my $address = xCAT::NetworkUtils->getipaddr($node, OnlyV4 => 1);
    $peer =~ s/\A::ffff:// if defined($peer) && !ref($peer);
    _fail('Unexpected installation client') unless defined($peer) && !ref($peer) &&
        defined($address) && $address ne '0' && $peer eq $address;
    return _boot_status($node, $message, $dispatch, %options)
        if defined($message) && !ref($message) && $message =~ /\Afreebsd-install-postscripts-/;
    return transition($node, $message, sub {
        my ($phase) = @_;
        if ($phase eq 'complete') {
            _command($node, 'nodeset', 'boot', $dispatch);
            _attribute($node, 'chain', 'currstate', 'boot');
        }
        my $status = { begin => 'installing', complete => 'installed', failed => 'failed', booted => 'booted' }->{$phase};
        _command($node, 'updatenodestat', $status, $dispatch);
        _attribute($node, 'nodelist', 'status', $status);
    }, %options);
}

sub _boot_report {
    my ($state, $save, $dispatch, @transport) = @_;
    my $decision = $state->{postscript_boot};
    my $report = xCAT::FreeBSDPostscript::collect_execution($decision->{run}, $dispatch, @transport);
    my $receipt = $report->{receipt};
    _fail('Boot report binding differs') unless ref($receipt) eq 'HASH'
      && $receipt->{run} eq $decision->{run} && $receipt->{snapshot} eq $decision->{snapshot};
    my $result = { map { $_ => $receipt->{$_} } qw(outcome complete) };
    _postscript_result($result);
    _fail('Boot report changed') if exists($decision->{result})
      && $json->encode($decision->{result}) ne $json->encode($result);
    $decision->{result} = $result;
    $state->{postscript_first} = { run => $decision->{run}, result => { %$result } } if $decision->{kind} eq 'firstboot';
    $save->($state);
    return $result->{outcome};
}

sub _boot_status {
    my ($node, $message, $dispatch, %options) = @_;
    _fail('Invalid boot postscript status') unless $message =~
      /\Afreebsd-install-postscripts-v1 ([0-9a-f]{32}) ([0-9a-f]{32}) ([0-9a-f]{64})\n?\z/;
    my ($generation, $attempt, $boot) = ($1, $2, $3);
    require xCAT::FreeBSDPostscript;
    my @transport = exists($options{postscript_directory}) ? (directory => $options{postscript_directory}) : ();
    return _boot_transaction($node, \%options, $dispatch, sub {
        my ($state, $save, $transport_dispatch) = @_;
        _fail('Boot postscripts require a completed installation') unless $state && $state->{phase} eq 'booted'
          && exists($state->{postscript_preparations});
        _fail('Boot postscript deployment differs') unless $state->{generation} eq $generation && $state->{attempt} eq $attempt;
        my $decision = $state->{postscript_boot};
        my $observed = xCAT::FreeBSDPostscript::observe_boot($node, $generation, $attempt,
            $decision ? $decision->{run} : '-', $transport_dispatch, @transport);
        _fail('Reported boot differs from the installed node') unless $observed->{boot} eq $boot;
        my $reply = sub { return "freebsd-install-postscripts-v1 $generation $boot $_[0] $_[1]\n"; };
        if ($decision) {
            if ($observed->{outcome} !~ /\A(?:absent|incomplete)\z/) {
                _fail('Observed boot run differs') unless exists($decision->{snapshot})
                  && $observed->{snapshot} eq $decision->{snapshot} && $observed->{'run-boot'} eq $decision->{boot};
            }
            my $finished = $observed->{complete} eq 'yes' || $observed->{released} eq 'yes';
            _fail('Completed boot run is no longer retained') if exists($decision->{result}) && !$finished;
            if ($finished) {
                my $outcome = _boot_report($state, $save, $transport_dispatch, @transport);
                return $reply->($decision->{run}, $outcome) if $decision->{boot} eq $boot;
            } elsif ($decision->{boot} ne $boot) {
                _fail('Previous boot run requires explicit interruption recovery')
                  unless $observed->{outcome} =~ /\A(?:absent|incomplete|admitted)\z/x;
            } elsif ($observed->{outcome} eq 'uncertain') {
                return $reply->($decision->{run}, 'uncertain');
            }
        }
        if (!$decision || $decision->{boot} ne $boot) {
            my $kind = exists($state->{postscript_first}) ? 'repeat' : 'firstboot';
            my $preparation = $state->{postscript_preparations}{$kind};
            my $compiled = xCAT::FreeBSDPostscript::compile_execution($preparation, @transport);
            return $reply->('-', 'disabled') if $kind eq 'repeat' && !$compiled->{enabled};
            $decision = { run => _generation(), boot => $boot, kind => $kind, preparation => $preparation };
            $state->{postscript_boot} = $decision;
            $save->($state);
        }
        my $export = xCAT::FreeBSDPostscript::export_execution($decision->{preparation}, @transport,
            run => $decision->{run}, generation => $generation, attempt => $attempt, boot => $boot);
        _fail('Boot export node differs') unless $export->{node} eq $node;
        _fail('Boot export changed') if exists($decision->{snapshot}) && $decision->{snapshot} ne $export->{snapshot};
        $decision->{snapshot} = $export->{snapshot};
        $save->($state);
        my $receipt = xCAT::FreeBSDPostscript::deliver_execution($decision->{run}, $transport_dispatch, @transport);
        return $reply->($decision->{run}, _boot_report($state, $save, $transport_dispatch, @transport)) if $receipt->{complete} eq 'yes';
        return $reply->($decision->{run}, $receipt->{outcome} eq 'uncertain' ? 'uncertain' : 'pending');
    });
}

sub _status_responses {
    my ($dispatch, $request, $responses) = @_;
    my $wire = JSON->new->canonical->utf8->max_depth(32);
    my $size = 0;
    $dispatch->($request, sub {
        my $bytes = $wire->encode(shift) . "\n";
        $size += length($bytes);
        _fail('Transport responses exceed their limit') if $size > 1048576;
        print {$responses} $bytes or _fail("Cannot write transport response: $!");
    });
    return;
}

sub _status_dispatch {
    my ($connection, $dispatch, $request) = @_;
    close($connection) or _fail("Cannot close transport connection: $!");
    open(my $responses, '>&', \*STDOUT) or _fail("Cannot open transport responses: $!");
    $responses->autoflush(1);
    open(STDOUT, '>&', \*STDERR) or _fail("Cannot redirect transport output: $!");
    my $ok = eval { _status_responses($dispatch, $request, $responses); 1; };
    my $error = $@;
    close($responses) or _fail("Cannot close transport responses: $!");
    print STDERR substr($error, 0, 8192) or _fail("Cannot write transport failure: $!") unless $ok;
    return $ok ? 0 : 1;
}

sub _status_transport {
    my ($connection, $dispatch, $request, $callback) = @_;
    return $dispatch->($request, $callback) unless $request->{command}[0] =~ /\A(?:xdsh|xdcp)\z/x;
    my $arguments = $request->{arg};
    _fail('Invalid supervised transport deadline') if ref($arguments) ne 'ARRAY'
      || @$arguments < 3 || $arguments->[0] ne '--nodestatus' || $arguments->[1] ne '-t'
      || $arguments->[2] !~ /\A[1-9][0-9]*\z/x || $arguments->[2] > 7200;
    require xCAT::FreeBSDPkg;
    my %environment = map { $_ => $ENV{$_} } grep { defined($ENV{$_}) } keys %ENV;
    # DSHCLI changes signal handlers. Keep it outside the status worker.
    my $result = xCAT::FreeBSDPkg::run_in_child(sub {
        return _status_dispatch($connection, $dispatch, $request);
    }, timeout => $arguments->[2], environment => \%environment,
        stdout_limit => 1048576, stderr_limit => 1048576);
    my $wire = JSON->new->canonical->utf8->max_depth(32);
    my @responses = split(/\n/x, $result->{stdout}, -1);
    my $tail = pop @responses;
    $callback->($wire->decode($_)) for @responses;
    _fail('Transport subprocess failed: ' . substr(join(' ',
        map { defined($_) ? $_ : '' } @{$result}{qw(failure setup stderr)}), 0, 8192))
      if !$result->{callback_complete} || $result->{callback_status}
        || !$result->{streams_complete} || $result->{failure};
    _fail('Incomplete transport response') if defined($tail) && length($tail);
    return;
}

sub start_status_worker {
    my ($node, $peer, $message, $connection, $dispatch, %options) = @_;
    my $limit = $options{limit} || 64;
    _fail('Invalid status worker limit') unless $limit =~ /\A[1-9][0-9]*\z/ && $limit <= 64;
    _fail('Missing status worker cleanup') unless ref($options{cleanup}) eq 'CODE';
    _fail('Missing status worker logger') unless ref($options{log}) eq 'CODE';
    for my $pid (keys %status_workers) {
        my $reaped = waitpid($pid, WNOHANG);
        delete $status_workers{$pid} if $reaped == $pid || ($reaped == -1 && $! == ECHILD);
    }
    if (keys(%status_workers) >= $limit || grep { $_ eq $node } values %status_workers) {
        close($connection);
        return 0;
    }
    require xCAT::Utils;
    my $pid = xCAT::Utils->xfork();
    unless (defined($pid)) {
        $options{log}->("Cannot start status worker: $!\n");
        close($connection);
        return 0;
    }
    if ($pid) {
        $status_workers{$pid} = $node;
        close($connection);
        return $pid;
    }
    local @SIG{qw(TERM INT USR2)} = (sub { die "FreeBSD status command interrupted\n"; }) x 3;
    $SIG{PIPE} = 'IGNORE';
    $SIG{ALRM} = sub { die "FreeBSD status command timed out\n"; };
    my $ok = eval {
        # Boot delivery includes bounded exports and file transfers.
        alarm(defined($message) && !ref($message) && $message =~
            /\Afreebsd-install-postscripts-v1 [0-9a-f]{32} [0-9a-f]{32} [0-9a-f]{64}\n?\z/ ? 7200 : 60);
        $options{cleanup}->();
        my %state_options = map { exists($options{$_}) ? ($_ => $options{$_}) : () }
            qw(directory postscript_directory);
        my $transport = sub { return _status_transport($connection, $dispatch, @_); };
        my $reply = handle_status($node, $peer, $message, $transport, %state_options);
        print {$connection} $reply or _fail("Cannot acknowledge installation: $!");
        close($connection) or _fail("Cannot close installation connection: $!");
        alarm(0);
        1;
    };
    my $error = $@;
    alarm(0);
    $options{log}->($error) unless $ok;
    POSIX::_exit($ok ? 0 : 1);
}

1;
