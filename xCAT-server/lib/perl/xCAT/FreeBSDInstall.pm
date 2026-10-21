package xCAT::FreeBSDInstall;

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:DEFAULT :flock);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON;
use POSIX ();

my $json = JSON->new->canonical->allow_nonref;
my %phases = map { $_ => 1 } qw(prepared installing completing installed booted failed cancelled);

sub _fail { die "FreeBSD installation: $_[0]\n"; }

sub _identifier {
    my ($value, $length) = @_;
    return defined($value) && !ref($value) && $value =~ /\A[0-9a-f]{$length}\z/;
}

sub _os_policy {
    my $value = shift;
    require xCAT::FreeBSDConfig;
    my $canonical = xCAT::FreeBSDConfig::os_disk_policy($value);
    _fail('Invalid retained OS disk policy') unless $json->encode($canonical) eq $json->encode($value)
        && length($json->encode($value)) <= 24576;
    return;
}

sub _os_record {
    my $value = shift;
    _fail('Invalid retained OS disk record') unless ref($value) eq 'HASH' && keys(%$value) == 3
        && _identifier($value->{generation}, 32) && _identifier($value->{attempt}, 32);
    _os_policy($value->{layout});
    my $layout = $value->{layout};
    _fail('Retained OS disk record is unresolved') if ($layout->{target_disk} || '') eq 'auto'
        || ($layout->{zfs_vdevs} || '') =~ /\Aauto:/x;
    return;
}

sub _resolved_record {
    my ($policy, $generation, $attempt, $members) = @_;
    require xCAT::FreeBSDConfig;
    my $record = { generation => $generation, attempt => $attempt,
        layout => xCAT::FreeBSDConfig::resolve_os_disks($policy, $members) };
    _os_record($record);
    return $record;
}

sub disk_history {
    my $state = shift;
    return 0 unless $state;
    return 1 if exists($state->{os_disks}) || $state->{os_disk_rebind};
    return $state->{os_disk_history} if exists($state->{os_disk_history});
    return exists($state->{attempt}) ? 1 : 0;
}

sub disk_rebind_pending {
    my ($state, $pool, $record) = @_;
    return 0 unless $state && $state->{os_disk_rebind};
    return 1 unless $pool && $state->{service_pool} && $record
        && $pool->{coordinator} eq $state->{service_pool}{coordinator};
    return $state->{os_disk_rebind} eq sha256_hex($json->encode($record)) ? 1 : 0;
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
    _service_pool($state->{service_pool}) if exists($state->{service_pool});
    _os_policy($state->{os_policy}) if exists($state->{os_policy});
    _os_record($state->{os_disks}) if exists($state->{os_disks});
    _fail('Invalid OS disk history marker') if exists($state->{os_disk_history})
        && (!defined($state->{os_disk_history}) || ref($state->{os_disk_history})
            || $state->{os_disk_history} !~ /\A[01]\z/x
            || (!$state->{os_disk_history} && exists($state->{os_disks})));
    _fail('Invalid OS disk rebind marker') if exists($state->{os_disk_rebind})
        && (!_identifier($state->{os_disk_rebind}, 64) || exists($state->{os_disks}));
    return $state;
}

sub _save_state {
    my ($directory, $node, $state) = @_;
    my ($handle, $temporary) = tempfile(".$node.XXXXXX", DIR => $directory, UNLINK => 0);
    my $ok = eval {
        chmod(0600, $temporary) == 1 or _fail("Cannot protect state: $!");
        my $bytes = $json->encode($state) . "\n";
        _fail('Installation state exceeds its size limit') if length($bytes) > 65536;
        print {$handle} $bytes or _fail("Cannot write state: $!");
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
    _fail('Invalid registration callback') if exists($options{register}) && ref($options{register}) ne 'CODE';
    _os_policy($options{os_policy}) if exists($options{os_policy});
    _os_record($options{previous_os_disks}) if defined($options{previous_os_disks});
    _fail('Invalid OS disk rebind option') if exists($options{os_disk_rebind})
        && (!defined($options{os_disk_rebind}) || ref($options{os_disk_rebind}) || $options{os_disk_rebind} ne '1');
    $fingerprint = sha256_hex("xcat-freebsd-os-disks-1\n$fingerprint\n" . $json->encode($options{os_policy}))
        if exists($options{os_policy});
    if (exists($options{service_pool})) {
        _service_pool($options{service_pool});
        $fingerprint = sha256_hex("xcat-freebsd-service-pool-1\n$fingerprint\n" . $json->encode($options{service_pool}));
    }
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
            if ($state->{service_pool} && $options{service_pool}
                && $state->{service_pool}{epoch} eq $options{service_pool}{epoch}) {
                _fail('Pool preparation changed; run nodeset osimage to prepare a new pool epoch')
                    unless $state->{phase} eq 'prepared' && $state->{fingerprint} eq $fingerprint;
            }
        }
        _fail('OS disk record changed during preparation') if exists($options{previous_os_disks})
            && !$options{service_pool} && $json->encode($options{previous_os_disks}) ne
                $json->encode($state ? $state->{os_disks} : undef);
        my $record = exists($options{previous_os_disks}) ? $options{previous_os_disks}
            : $state ? $state->{os_disks} : undef;
        my $rebind = $options{os_disk_rebind} ? sha256_hex($json->encode($record))
            : disk_rebind_pending($state, $options{service_pool}, $record) ? $state->{os_disk_rebind} : undef;
        my $changed = !$state || $state->{phase} ne 'prepared' || $state->{fingerprint} ne $fingerprint
            || ($rebind || '') ne ($state->{os_disk_rebind} || '');
        if ($changed) {
            my $history = disk_history($state);
            $record = undef if $rebind;
            $state = { version => 1, node => $node, fingerprint => $fingerprint,
                generation => _generation(), phase => 'prepared' };
            $state->{os_disks} = $record if defined($record);
            $state->{os_disk_history} = $history || defined($record) || $rebind ? 1 : 0;
            $state->{os_disk_rebind} = $rebind if $rebind;
            $state->{os_policy} = $options{os_policy} if exists($options{os_policy});
            $state->{postscript_preparations} = $preparations if defined($preparations);
            $state->{service_pool} = {%{$options{service_pool}}} if exists($options{service_pool});
        }
        if (!exists($state->{os_disk_history})) {
            $state->{os_disk_history} = disk_history($state);
            $changed = 1;
        }
        $options{register}->($state->{generation}) if $options{register};
        $save->($state) if $changed;
        $options{publish}->($state->{generation}) if $options{publish};
        return $state->{generation};
    });
}

sub state {
    my ($node, %options) = @_;
    _fail('Invalid node name') unless defined($node) && !ref($node)
        && $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/;
    my $directory = $options{directory} || '/var/lib/xcat/freebsd-install';
    return unless -e $directory || -l $directory;
    return _locked($node, \%options, sub { return $_[0]; });
}

sub _pool_ip {
    my $ip = shift;
    return 0 if !defined($ip) || ref($ip) || $ip !~ /\A(?:[0-9]{1,3}[.]){3}[0-9]{1,3}\z/x;
    return 0 if grep { $_ > 255 || (length($_) > 1 && /^0/x) } split(/[.]/x, $ip);
    return 1;
}

sub _service_pool {
    my $metadata = shift;
    _fail('Invalid service-node preparation') unless ref($metadata) eq 'HASH'
      && keys(%$metadata) == 3 && _identifier($metadata->{epoch}, 32)
      && _pool_ip($metadata->{coordinator}) && _pool_ip($metadata->{server});
    return;
}

sub _pool_authorize {
    my ($node, $state, $attempt, $phase, $dispatch, $members) = @_;
    return unless exists($state->{service_pool});
    require xCAT::FreeBSDPool;
    xCAT::FreeBSDPool::event($node, $state, $attempt, $phase, $dispatch, $members);
    return;
}

sub _pool_registration {
    my $entry = shift;
    _fail('Invalid pool registration') unless ref($entry) eq 'HASH' && keys(%$entry) == 3
      && _identifier($entry->{generation}, 32) && _identifier($entry->{fingerprint}, 64)
      && _pool_ip($entry->{master});
    return;
}

sub _pool_state {
    my $state = shift;
    my $pool = $state->{pool};
    _fail('Invalid service-node pool state') unless ref($pool) eq 'HASH'
      && ref($pool->{servers}) eq 'ARRAY' && ref($pool->{registrations}) eq 'HASH';
    _fail('Invalid service-node pool fields') if grep { $_ !~ /\A(?:servers|registrations|owner|os_policy)\z/x } keys %$pool;
    _os_policy($pool->{os_policy}) if exists($pool->{os_policy});
    _fail('Invalid service-node pool size') if !@{$pool->{servers}} || @{$pool->{servers}} > 32;
    my %servers;
    for my $server (@{$pool->{servers}}) {
        _fail('Invalid pool server') unless _pool_ip($server);
        _fail('Repeated pool server') if $servers{$server}++;
    }
    for my $server (keys %{$pool->{registrations}}) {
        _fail('Registered server is not a pool member') unless $servers{$server};
        _pool_registration($pool->{registrations}{$server});
    }
    _fail('Invalid pool installation owner') if exists($pool->{owner})
      && (!defined($pool->{owner}) || ref($pool->{owner}) || !$pool->{registrations}{$pool->{owner}});
    _fail('Pool attempt and owner differ') if exists($state->{attempt}) != exists($pool->{owner});
    return $pool;
}

sub _pool_prepare {
    my ($node, $current, $input) = @_;
    _fail('Invalid pool preparation fingerprint') unless _identifier($input->{fingerprint}, 64);
    _fail('Stop the node and run nodeset offline before rearming this pool installation')
      if $current && $current->{phase} =~ /\A(?:installing|completing|failed)\z/x;
    my $next = {version => 1, node => $node, generation => _generation(),
        fingerprint => $input->{fingerprint}, phase => 'prepared',
        pool => {servers => $input->{servers}, registrations => {}}};
    $next->{os_disks} = $current->{os_disks} if $current && exists($current->{os_disks});
    $next->{os_disk_history} = disk_history($current);
    _pool_state($next);
    return $next;
}

sub _pool_match {
    my ($current, $input) = @_;
    _fail('Pool installation is not armed') if !$current || $current->{phase} eq 'cancelled';
    _fail('Stale pool installation generation') unless _identifier($input->{epoch}, 32)
      && $input->{epoch} eq $current->{generation};
    _fail('Invalid pool server address') unless _pool_ip($input->{server});
    _fail('Server is not in this installation pool') unless
      grep { $_ eq $input->{server} } @{$current->{pool}{servers}};
    _fail('Invalid prepared server generation') unless _identifier($input->{generation}, 32);
    return;
}

sub _pool_register {
    my ($current, $input) = @_;
    _fail('Pool registration requires an unclaimed installation') unless $current->{phase} eq 'prepared';
    my $pool = $current->{pool};
    my $server = $input->{server};
    my $entry = {map { $_ => $input->{$_} } qw(generation fingerprint master)};
    _pool_registration($entry);
    _os_policy($input->{os_policy}) if exists($input->{os_policy});
    _fail('Service nodes prepared different OS disk policies') if keys(%{$pool->{registrations}})
        && $json->encode($pool->{os_policy}) ne $json->encode($input->{os_policy});
    $pool->{os_policy} = $input->{os_policy} if exists($input->{os_policy});
    _fail('Prepared server changed within this pool generation') if exists($pool->{registrations}{$server})
      && $json->encode($pool->{registrations}{$server}) ne $json->encode($entry);
    $pool->{registrations}{$server} = $entry;
    return;
}

sub _pool_event {
    my ($current, $input) = @_;
    my $pool = $current->{pool};
    my $server = $input->{server};
    my $registered = $pool->{registrations}{$server};
    _fail('Server installation was not registered') unless $registered
      && $registered->{generation} eq $input->{generation};
    _fail('Invalid pool installation attempt') unless _identifier($input->{attempt}, 32);
    my $phase = $input->{phase};
    _fail('Invalid pool installation phase') if !defined($phase) || ref($phase)
      || $phase !~ /\A(?:begin|completing|complete|booted|failed)\z/x;
    _fail('OS disk members are only accepted at installation begin') if exists($input->{members}) && $phase ne 'begin';
    my $record;
    if ($phase eq 'begin') {
        _fail('OS disk reporting differs from the pool preparation') unless
            exists($pool->{os_policy}) == exists($input->{members});
        $record = _resolved_record($pool->{os_policy}, $input->{generation}, $input->{attempt}, $input->{members})
            if exists($input->{members});
    }
    if (exists($pool->{owner})) {
        _fail('Another service node or attempt owns this installation') unless
          $pool->{owner} eq $server && $current->{attempt} eq $input->{attempt};
        _fail('Claimed OS disk record changed') if $phase eq 'begin'
            && $json->encode($current->{os_disks}) ne $json->encode($record);
    } elsif ($phase eq 'begin') {
        _fail('Pool installation cannot begin in this state') unless $current->{phase} eq 'prepared';
        $pool->{owner} = $server;
        $current->{attempt} = $input->{attempt};
    } elsif ($phase ne 'failed') {
        _fail('Pool installation has no owner');
    }
    return unless exists($pool->{owner});
    my %previous = (begin => qr/\A(?:prepared|installing)\z/x,
        completing => qr/\A(?:installing|completing|installed|booted)\z/x,
        complete => qr/\A(?:completing|installed|booted)\z/x,
        booted => qr/\A(?:installed|booted)\z/x, failed => qr/\A(?:installing|completing|failed)\z/x);
    _fail('Invalid pool installation transition') unless $current->{phase} =~ $previous{$phase};
    my %next = (begin => 'installing', completing => 'completing', complete => 'installed', booted => 'booted', failed => 'failed');
    $current->{phase} = $next{$phase} unless $current->{phase} eq 'booted'
      || ($phase eq 'completing' && $current->{phase} eq 'installed');
    if ($phase eq 'begin') {
        $current->{os_disk_history} = 1;
        if ($record) { $current->{os_disks} = $record; }
        else { delete $current->{os_disks}; }
    }
    return;
}

sub pool_request {
    my ($node, $operation, $input, %options) = @_;
    _fail('Invalid pool operation') if !defined($operation) || ref($operation)
      || $operation !~ /\A(?:prepare|register|event|inspect|cancel)\z/x;
    _fail('Invalid pool request') unless ref($input) eq 'HASH';
    my %fields = (
        prepare => [qw(fingerprint servers)], register => [qw(epoch server generation fingerprint master)],
        event => [qw(epoch server generation attempt phase)], inspect => [], cancel => [],
    );
    my %allowed = map { $_ => 1 } @{$fields{$operation}};
    $allowed{os_policy} = 1 if $operation eq 'register' && exists($input->{os_policy});
    $allowed{members} = 1 if $operation eq 'event' && exists($input->{members});
    _fail('Unexpected pool request fields') if keys(%$input) != keys(%allowed)
      || grep { !$allowed{$_} } keys %$input;
    $options{directory} ||= '/var/lib/xcat/freebsd-pools';
    return _locked($node, \%options, sub {
        my ($current, $save) = @_;
        _pool_state($current) if $current;
        if ($operation eq 'prepare') {
            $current = _pool_prepare($node, $current, $input);
            $save->($current);
        } elsif ($operation eq 'cancel') {
            if ($current) {
                $current->{phase} = 'cancelled';
                $save->($current);
            }
        } elsif ($operation ne 'inspect') {
            _pool_match($current, $input);
            if ($operation eq 'register') {
                _pool_register($current, $input);
            } else {
                _pool_event($current, $input);
            }
            $save->($current);
        }
        return {phase => 'absent'} unless $current;
        my $pool = $current->{pool};
        return {epoch => $current->{generation}, phase => $current->{phase},
            servers => [@{$pool->{servers}}],
            os_disk_history => disk_history($current),
            exists($current->{os_disks}) ? (os_disks => $current->{os_disks}) : (),
            exists($pool->{owner}) ? (owner => $pool->{owner},
                master => $pool->{registrations}{$pool->{owner}}{master}) : ()};
    });
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
    _fail('Invalid installation status') unless defined($message) && !ref($message) && length($message) <= 4300 &&
        $message =~ /\Afreebsd-install-v([12]) ([0-9a-f]{32}) ([0-9a-f]{32}) (begin|complete|failed|booted)(?: ([A-Za-z0-9_.:+@,;-]+))?\n?\z/;
    my ($version, $generation, $attempt, $phase, $members) = ($1, $2, $3, $4, $5);
    _fail('Invalid OS disk status fields') unless $version eq '2'
        ? ($phase eq 'begin' && defined($members)) : !defined($members);
    _fail('Missing installation action') unless ref($action) eq 'CODE';
    return _locked($node, \%options, sub {
        my ($state, $save) = @_;
        _fail('Installation is not armed') unless $state && $state->{phase} ne 'cancelled';
        _fail('Service-node pool requires a registered local preparation')
          if $options{require_pool} && !$state->{service_pool};
        _fail('Stale installation generation') unless $state->{generation} eq $generation;
        _fail('Another installation attempt owns this generation')
            if exists($state->{attempt}) && $state->{attempt} ne $attempt;
        if ($phase eq 'begin') {
            _fail('Installation cannot begin in this state') unless $state->{phase} =~ /\A(?:prepared|installing)\z/;
            _fail('OS disk reporting differs from the installation preparation') unless
                exists($state->{os_policy}) == defined($members);
            my $record = defined($members) ? _resolved_record($state->{os_policy}, $generation, $attempt, $members) : undef;
            _fail('Claimed OS disk record changed') if $state->{phase} eq 'installing'
                && $json->encode($state->{os_disks}) ne $json->encode($record);
            _pool_authorize($node, $state, $attempt, $phase, $options{dispatch}, $members);
            if ($record) { $state->{os_disks} = $record; delete $state->{os_disk_rebind}; }
            else { delete $state->{os_disks}; }
            $state->{os_disk_history} = 1;
            $state->{attempt} = $attempt;
            $state->{phase} = 'installing';
            $save->($state);
            $action->('begin', $state);
        } elsif ($phase eq 'complete') {
            _fail('Installation cannot complete in this state') unless
                $state->{phase} =~ /\A(?:installing|completing|installed|booted)\z/;
            my $pending = $state->{phase} ne 'installed' && $state->{phase} ne 'booted';
            _pool_authorize($node, $state, $attempt, $pending ? 'completing' : 'complete', $options{dispatch});
            if ($state->{phase} ne 'installed' && $state->{phase} ne 'booted') {
                $state->{phase} = 'completing';
                $save->($state);
                $action->('complete', $state);
                $state->{phase} = 'installed';
                $save->($state);
                _pool_authorize($node, $state, $attempt, 'complete', $options{dispatch});
            }
        } elsif ($phase eq 'booted') {
            _fail('Installation is not complete') unless $state->{phase} =~ /\A(?:installed|booted)\z/;
            _pool_authorize($node, $state, $attempt, 'complete', $options{dispatch}) if $state->{phase} eq 'installed';
            _pool_authorize($node, $state, $attempt, $phase, $options{dispatch});
            if ($state->{phase} ne 'booted') {
                $action->('booted', $state);
                $state->{phase} = 'booted';
                $save->($state);
            }
        } else {
            _fail('Installation cannot fail in this state') unless $state->{phase} =~ /\A(?:prepared|installing|completing|failed)\z/;
            _pool_authorize($node, $state, $attempt, $phase, $options{dispatch});
            $state->{attempt} = $attempt;
            $state->{phase} = 'failed';
            $save->($state);
            $action->('failed', $state);
        }
        return "freebsd-install-v$version $generation $phase ok\n";
    });
}

sub _command {
    my ($node, $command, $argument, $dispatch, %fields) = @_;
    my $response = $dispatch->({ %fields, command => [$command], node => [$node], arg => [$argument] });
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

sub pool_boot {
    my ($node, $input, $dispatch, %options) = @_;
    _fail('Invalid pool boot request') unless ref($input) eq 'HASH' && keys(%$input) == 2
        && _identifier($input->{epoch}, 32) && _pool_ip($input->{server});
    require xCAT::FreeBSDPool;
    return _locked($node, \%options, sub {
        my $state = shift;
        _fail('Stale standby boot request') unless $state && $state->{service_pool}
            && $state->{service_pool}{epoch} eq $input->{epoch}
            && $state->{service_pool}{server} eq $input->{server}
            && !xCAT::NetworkUtils->thishostisnot($input->{server});
        my $pool = xCAT::FreeBSDPool::request($node, 'inspect', {}, $dispatch);
        _fail('Pool installation has not completed') unless ($pool->{epoch} || '') eq $input->{epoch}
            && ($pool->{phase} || '') =~ /\A(?:installed|booted)\z/x;
        _command($node, 'nodeset', 'boot', $dispatch, _xcatpreprocessed => [1],
            _disparatetftp => [1], _disjointmode => [1], _freebsd_owner => [$input->{server}]);
        _attribute($node, 'chain', 'currstate', 'boot');
        return {epoch => $input->{epoch}, phase => 'boot'};
    });
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
    require xCAT::FreeBSDPool;
    $options{require_pool} = xCAT::FreeBSDPool::node_topology($node) ? 1 : 0;
    return _boot_status($node, $message, $dispatch, %options)
        if defined($message) && !ref($message) && $message =~ /\Afreebsd-install-postscripts-/;
    my $reply = transition($node, $message, sub {
        my ($phase, $state) = @_;
        if ($phase eq 'complete') {
            my %fields = exists($state->{service_pool}) ? (_xcatpreprocessed => [1],
                _disparatetftp => [1], _disjointmode => [1],
                _freebsd_owner => [$state->{service_pool}{server}]) : ();
            _command($node, 'nodeset', 'boot', $dispatch, %fields);
            _attribute($node, 'chain', 'currstate', 'boot');
        }
        my $status = { begin => 'installing', complete => 'installed', failed => 'failed', booted => 'booted' }->{$phase};
        _command($node, 'updatenodestat', $status, $dispatch);
        _attribute($node, 'nodelist', 'status', $status);
    }, %options, dispatch => $dispatch);
    if ($message =~ /[ ]complete\n?\z/x) {
        my $state = state($node, %options);
        xCAT::FreeBSDPool::refresh_boot($node, $state->{service_pool}, $dispatch) if $state->{service_pool};
    }
    return $reply;
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
        _fail('Service-node pool requires a registered local preparation')
          if $options{require_pool} && !$state->{service_pool};
        _fail('Boot postscript deployment differs') unless $state->{generation} eq $generation && $state->{attempt} eq $attempt;
        _pool_authorize($node, $state, $attempt, 'booted', $dispatch);
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
    # The install monitor owns per-node ordering and the shared handler limit.
    _fail('Missing status worker cleanup') unless ref($options{cleanup}) eq 'CODE';
    _fail('Missing status worker logger') unless ref($options{log}) eq 'CODE';
    require xCAT::Utils;
    my $pid = xCAT::Utils->xfork();
    unless (defined($pid)) {
        $options{log}->("Cannot start status worker: $!\n");
        close($connection);
        return 0;
    }
    if ($pid) {
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
