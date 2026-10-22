package XCAT::NFSLock;

# NFS lock protocol
#
# Copies
#   This module is vendored three times, because no repo installs another's build tooling:
#     xcat-dep         lib/XCAT/NFSLock.pm              (this file, the original)
#     xcat-core        build-utils/lib/XCAT/NFSLock.pm
#     xcat-core-ci-cd  ci/lib/XCAT/NFSLock.pm
#   The three must stay identical. They have diverged once already: sweep_stranded was added to
#   the ci-cd copy alone, so the protocol hole it covers stayed open in the other two.
#
# A lock on a shared, possibly re-exported, NFS tree. flock and fcntl are not
# available there. The protocol uses mkdir, rmdir, unlink and plain file
# writes. It uses no rename.
#
# Names in this module
#   lock.d           the lock path given to acquire
#   lock.d/metadata  the metadata of the owner
#   lock.borrow      <lock path>.borrow, beside lock.d
#   R, T, δ          the options retries, delay and jitter
#
# Assumptions
#   1. mkdir(path) is atomic and exclusive among contenders, and successful
#      namespace changes eventually become visible.
#   2. machine-id is unique among participating hosts.
#      Cloned VMs and images can share it by accident unless it is regenerated.
#   3. Metadata writes eventually become readable completely and consistently.
#   4. A host never declares one of its own live process incarnations dead.
#   5. A process cannot die after it creates lock.d, until it publishes valid metadata.
#      It MAY die while it holds lock.borrow: the borrow carries the same metadata as the lock,
#      so a borrow whose taker is provably dead is recovered by the same rule. A borrow left by
#      the earlier protocol carries none, and sweep_stranded removes those.
#   6. A crashed worker leaves recoverable state. The owning host eventually
#      returns and retries. Eventually one worker and its release complete.
#   7. All participants follow the protocol.
#
# Metadata
#   lock.d/metadata contains:
#     machine-id, boot-id, pid, pstart, token, hash
#
#   Ownership identity: (machine-id, boot-id, pid, pstart, token)
#   token is random per acquisition.
#   hash = HASH(canonical(SORT(k, v))) over all fields except hash.
#
#   If the metadata is missing, cannot be parsed or hashed, or the hash does not
#   match, assume a partial or inconsistent read and retry. Never infer stale
#   ownership from invalid metadata.
#
# Retry
#   R = max retries, T = base delay, δ = jitter
#   R > 0, δ >= 0, T >= 3, T > 2δ
#
#   Generic retry:
#     if retries >= R: fail
#     sleep(T + rand(-δ, δ))
#     retries++
#     goto 1
#
# Protocol
#   1. mkdir lock.d
#      - success: write valid metadata, go to 8
#      - EEXIST: continue
#      - other error: fail
#   2. Read and validate the metadata.
#      - invalid or missing: retry
#      - different machine-id: retry
#      - same host: save the observed ownership identity
#   3. mkdir lock.borrow, then write valid metadata into it
#      - EEXIST: recover the borrow if its metadata proves its taker dead, then retry
#      - other failure: retry
#   4. Read and validate the metadata again.
#      - invalid, missing, or ownership identity changed: rmdir lock.borrow, retry
#   5. Prove that the recorded (boot-id, pid, pstart) is dead.
#      - not provably dead: rmdir lock.borrow, retry
#      - dead: continue
#   6. Replace the metadata with the identity of this process and a fresh token.
#   7. rmdir lock.borrow
#   8. Call the worker.
#   9. mkdir lock.borrow, then write valid metadata into it
#      - EEXIST: recover the borrow if its metadata proves its taker dead
#      - failure: sleep(T + rand(-δ, δ)), retry step 9
#  10. unlink lock.d/metadata
#  11. rmdir lock.d (the actual unlock)
#  12. rmdir lock.borrow
#
# Core invariants
#   lock.d exists         => locked
#   lock.d absent         => acquirable
#   invalid metadata      => retry only
#   different machine-id  => never recover here
#   lock.borrow exists    => ownership transition or release in progress,
#                            unless its metadata proves its taker dead
#
# Steps 1 to 7 are acquire, step 8 is the caller, steps 9 to 12 are release.
# release does steps 10 and 11 only when the metadata names this acquisition.
#
# Log
#   Unless quiet => 1, each lock event prints one line to the selected output handle:
#     [nfslock] <UTC time> <host> pid=<pid> <event> <label> <lock.d> [detail]
#   Events: acquired (step 1), took-over (step 6), reaped-borrow (step 3 or 9), wait (a retry),
#   released (step 11), release-skipped. The time has milliseconds, so the lines of two hosts sort into one order.

use strict;
use warnings;
use Cwd qw(abs_path);
use File::Find ();
use Digest::SHA qw(sha256_hex);
use Errno qw(EEXIST ENOENT);
use Exporter 'import';
use File::Basename qw(dirname basename);
use POSIX qw(strftime);
use Sys::Hostname qw(hostname);
use Time::HiRes ();

our @EXPORT_OK = qw(this_process format_metadata parse_metadata owner_is_dead process_start
                    sweep_stranded);

my @IDENTITY = qw(machine-id boot-id pid pstart token);

#--------------------------------------------------------------------------------

=head3 acquire

    Descriptions:
        Take the lock at $path with steps 1 to 7 of the protocol.
    Arguments:
        $path: path of lock.d
        %opt:
            label   => word for messages (default "lock")
            delay   => T, seconds, 3 or more (default 3)
            jitter  => δ, seconds, 0 or more and less than T/2 (default 0.5)
            retries => R, more than 0 (default: timeout / T, at least 1)
            timeout => seconds to wait, used when retries is not given (default 0)
            quiet   => 1 to print no log lines for this lock
    Returns:
        A lock object. Dies after R retries, naming the lock and its owner.

=cut

#--------------------------------------------------------------------------------
sub acquire {
    my ($class, $path, %opt) = @_;
    my $label  = $opt{label}  // 'lock';
    my $delay  = $opt{delay}  // 3;
    my $jitter = $opt{jitter} // 0.5;
    die "Invalid delay $delay for $label: must be 3s or more\n" unless $delay >= 3;
    die "Invalid jitter $jitter for $label: must be 0 or more\n" unless $jitter >= 0;
    die "Invalid jitter $jitter for $label: must be less than half the delay\n"
      unless $delay > 2 * $jitter;
    my $retries = $opt{retries};
    unless (defined($retries)) {
        my $timeout = $opt{timeout} // 0;
        $retries = int($timeout / $delay);
        $retries++ if $retries * $delay < $timeout;
        $retries = 1 if $retries < 1;
    }
    die "Invalid retries $retries for $label: must be a whole number more than 0\n"
      unless $retries =~ /\A[1-9][0-9]*\z/;

    # The last component names the lock itself. basename would turn '' into './' and drop a
    # trailing slash, so the raw path is checked.
    my ($name) = ($path // '') =~ m{(?:\A|/)([^/]+)\z};
    die "Invalid $label path '" . ($path // '') . "'\n"
      if !defined($name) || $name eq '.' || $name eq '..';
    my $abs    = _absolute($path);
    my $borrow = "$abs.borrow";
    my $self   = bless {
        path   => $abs,
        label  => $label,
        pid    => $$,
        delay  => $delay,
        jitter => $jitter,
        quiet  => $opt{quiet} ? 1 : 0,
    }, $class;
    my $here = _here();
    my $seen;

    for (my $count = 0 ; ; $count++) {
        # Step 1.
        if (mkdir($abs)) {
            $self->{identity} = this_process();
            if (eval { _write_metadata($abs, $self->{identity}); 1 }) {
                $self->_log('acquired');
                return $self;
            }
            my $error = $@;
            unlink("$abs/metadata");
            rmdir($abs);
            die $error;
        }
        die "Cannot create $label $abs: $!\n" unless $! == EEXIST;

        # Step 2.
        my $observed = _read_metadata($abs);
        $seen = $observed if defined($observed);
        if (defined($observed) && $observed->{'machine-id'} eq $here->{'machine-id'}) {
            if (mkdir($borrow)) {
                # Steps 3 to 7.
                my $taken = eval {
                    # The borrow names its taker, so a taker that dies here can be recovered
                    # below. Written before the death check, which is where a SIGKILL lands.
                    _write_metadata($borrow, this_process());
                    my $again = _read_metadata($abs);
                    return 0 unless defined($again) && _key($again) eq _key($observed);
                    return 0 unless owner_is_dead($again, $here);
                    $self->{identity} = this_process();
                    _write_metadata($abs, $self->{identity});
                    1;
                };
                my $error = $@;
                _drop_borrow($borrow);
                die $error unless defined($taken);
                if ($taken) {
                    $self->_log('took-over', 'from dead pid ' . $observed->{pid});
                    return $self;
                }
            }
            elsif ($! == EEXIST) {
                # Step 3 fails for as long as the borrow exists, and that skips steps 4 to 7, so
                # a taker killed here blocked the lock for every later acquire.
                $self->_log('reaped-borrow', "taker pid $1 is dead")
                    if _reap_borrow($borrow, $here) =~ /\Apid (\d+)\z/;
            }
        }

        last if $count >= $retries;
        $self->_log('wait', sprintf('retry %d/%d, owner %s', $count + 1, $retries, _describe($seen)));
        _sleep(_wait($delay, $jitter));
    }

    my $who = _describe($seen);
    my $s   = $retries == 1 ? 'retry' : 'retries';
    die "Trying to unlock $abs failed after $retries $s; $label owned by $who.\n"
      . "If you are sure it is safe, remove the lock: rm -rf $abs\n";
}

#--------------------------------------------------------------------------------

=head3 release

    Descriptions:
        Steps 9 to 12 of the protocol. Waits while another process holds
        lock.borrow. A forked child of the owner does nothing, and a lock whose
        metadata names another acquisition is left alone.
    Arguments:
        none
    Returns:
        1 when the lock was removed, 0 otherwise.

=cut

#--------------------------------------------------------------------------------
sub release {
    my ($self) = @_;
    return 0 if $self->{released} || $$ != $self->{pid};
    # acquire blesses $self before it holds anything, and sets identity only once it does. An
    # acquire that dies would otherwise reach the wait loop below and never leave it.
    return 0 unless defined($self->{identity});
    my $path   = $self->{path};
    my $borrow = "$path.borrow";
    while (1) {
        # Step 9.
        if (mkdir($borrow)) {
            eval { _write_metadata($borrow, $self->{identity}); 1 };
            my $current = _read_metadata($path);
            if (defined($current) && _key($current) eq _key($self->{identity})) {
                $self->{released} = 1;
                unlink("$path/metadata");
                my $removed = rmdir($path);
                my $error   = $!;
                _drop_borrow($borrow);
                warn "Cannot remove $path: $error\n" unless $removed;
                $self->_log($removed ? 'released' : 'release-skipped', $removed ? () : ("rmdir: $error"));
                return $removed ? 1 : 0;
            }
            _drop_borrow($borrow);
            # Valid metadata of another acquisition, or no lock.d at all: this lock is gone.
            if (defined($current) || !-d $path) {
                $self->{released} = 1;
                $self->_log('release-skipped', defined($current) ? 'owned by ' . _describe($current) : 'no lock.d');
                return 0;
            }
        }
        elsif ($! != EEXIST) {
            warn "Cannot create $borrow: $!\n";
            return 0;
        }
        else {
            # A taker killed while holding the borrow would otherwise block this release for ever.
            _reap_borrow($borrow, _here());
        }
        _sleep(_wait($self->{delay}, $self->{jitter}));
    }
}

sub path { return $_[0]{path} }

#--------------------------------------------------------------------------------

=head3 this_process

    Descriptions:
        The ownership identity of this process with a fresh token.
    Arguments:
        none
    Returns:
        A hash ref with machine-id, boot-id, pid, pstart and token.

=cut

#--------------------------------------------------------------------------------
sub this_process {
    my $here = _here();
    return {
        'machine-id' => $here->{'machine-id'},
        'boot-id'    => $here->{'boot-id'},
        pid          => $$,
        pstart       => process_start($$) // die("Cannot read the start time of pid $$\n"),
        token        => _token(),
    };
}

#--------------------------------------------------------------------------------

=head3 format_metadata

    Descriptions:
        The content of lock.d/metadata: one "key=value" line per field, sorted
        by key, and the hash line.
    Arguments:
        $fields: hash ref with machine-id, boot-id, pid, pstart and token
    Returns:
        The metadata string.

=cut

#--------------------------------------------------------------------------------
sub format_metadata {
    my ($fields) = @_;
    my $canonical = _canonical($fields);
    return $canonical . 'hash=' . sha256_hex($canonical) . "\n";
}

#--------------------------------------------------------------------------------

=head3 parse_metadata

    Descriptions:
        Validate the content of lock.d/metadata. A partial read, an unknown or
        repeated field, a malformed value and a hash that does not match all
        make the metadata invalid.
    Arguments:
        $text: the content of lock.d/metadata, or undef
    Returns:
        A hash ref of the identity fields, or undef when the metadata is invalid.

=cut

#--------------------------------------------------------------------------------
sub parse_metadata {
    my ($text) = @_;
    return undef unless defined($text) && $text =~ /\n\z/;
    my %field;
    for my $line (split(/\n/, $text)) {
        my ($key, $value) = $line =~ /\A([a-z-]+)=([^=\s]+)\z/ or return undef;
        return undef if exists($field{$key});
        $field{$key} = $value;
    }
    my $hash = delete($field{hash});
    return undef unless defined($hash) && keys(%field) == @IDENTITY;
    for my $key (@IDENTITY) {
        return undef unless defined($field{$key});
    }
    return undef unless $field{pid} =~ /\A[1-9][0-9]*\z/ && $field{pstart} =~ /\A[0-9]+\z/;
    return undef unless $hash eq sha256_hex(_canonical(\%field));
    return \%field;
}

#--------------------------------------------------------------------------------

=head3 owner_is_dead

    Descriptions:
        Step 5: decide from facts alone whether a recorded owner is dead. Only
        the owner's machine can know. Any other machine answers "not proven".
    Arguments:
        $owner: a hash ref from parse_metadata, or undef
        $here: hash ref with machine-id, boot-id and start_of, a code ref that
               returns the start time of a pid on this machine, or undef when
               no such process exists
    Returns:
        1 when the owner is provably dead, 0 otherwise.

=cut

#--------------------------------------------------------------------------------
sub owner_is_dead {
    my ($owner, $here) = @_;
    return 0 unless defined($owner);
    return 0 unless $owner->{'machine-id'} eq $here->{'machine-id'};
    return 1 unless $owner->{'boot-id'} eq $here->{'boot-id'};
    my $start = $here->{start_of}->($owner->{pid});
    return 1 unless defined($start);
    return $start eq $owner->{pstart} ? 0 : 1;
}

#--------------------------------------------------------------------------------

=head3 process_start

    Descriptions:
        The start time of a process, field 22 of /proc/<pid>/stat, in clock ticks
        since boot. A reused pid has a later start time.
    Arguments:
        $pid: the process id
    Returns:
        The start time, or undef when no such process exists.

=cut

#--------------------------------------------------------------------------------
sub process_start {
    my ($pid) = @_;
    open(my $fh, '<', "/proc/$pid/stat") or return undef;
    my $stat = <$fh>;
    close($fh);
    return undef unless defined($stat);
    # The command name, field 2, may contain spaces and parentheses.
    $stat =~ s/\A.*\)\s+//s or return undef;
    my @field = split(/\s+/, $stat);
    return $field[19];
}

sub _log {
    my ($self, $event, $detail) = @_;
    return if $self->{quiet};
    my $now  = Time::HiRes::time();
    my $time = strftime('%Y-%m-%dT%H:%M:%S', gmtime($now)) . sprintf('.%03dZ', ($now - int($now)) * 1000);
    my $host = (split(/\./, hostname() || 'unknown'))[0];
    my $line = join(' ', '[nfslock]', $time, $host, "pid=$$", $event, $self->{label}, $self->{path},
        defined($detail) ? $detail : ());
    print "$line\n";
}

sub _canonical {
    my ($fields) = @_;
    return join('', map { "$_=$fields->{$_}\n" } sort @IDENTITY);
}

# _drop_borrow: remove a borrow this process created, metadata first.
sub _drop_borrow {
    my ($borrow) = @_;
    unlink("$borrow/metadata");
    return rmdir($borrow);
}

# _reap_borrow: remove a borrow whose taker is provably dead, and say what was found.
#
# The same rule the lock itself uses: a borrow is recovered only when its metadata is valid, names
# this machine, and names a process this host can prove is dead. A borrow with no metadata is one
# the previous protocol left, and staleness is never inferred from metadata that cannot be
# validated -- sweep_stranded removes those.
sub _reap_borrow {
    my ($borrow, $here) = @_;
    $here //= _here();
    my $taker = _read_metadata($borrow);
    return 'invalid' unless defined($taker);
    return 'other machine' unless $taker->{'machine-id'} eq $here->{'machine-id'};
    return 'alive' unless owner_is_dead($taker, $here);
    _drop_borrow($borrow);
    return "pid $taker->{pid}";
}

sub _key {
    my ($fields) = @_;
    return join("\n", map { $fields->{$_} } @IDENTITY);
}

# A reader can see this file half written. The hash makes that read invalid.
sub _write_metadata {
    my ($path, $identity) = @_;
    my $file = "$path/metadata";
    my $fh;
    open($fh, '>', $file) && print({$fh} format_metadata($identity)) && close($fh)
      or die "Cannot write $file: $!\n";
}

sub _read_metadata {
    my ($path) = @_;
    open(my $fh, '<', "$path/metadata") or return undef;
    local $/;
    my $text = <$fh>;
    close($fh);
    return parse_metadata($text);
}

sub _wait {
    my ($delay, $jitter) = @_;
    return $delay + (2 * rand() - 1) * $jitter;
}

sub _sleep {
    my ($seconds) = @_;
    Time::HiRes::sleep($seconds);
}

sub _token {
    if (open(my $fh, '<:raw', '/dev/urandom')) {
        my $read = read($fh, my $bytes, 16);
        close($fh);
        return unpack('H*', $bytes) if defined($read) && $read == 16;
    }
    return join('', map { sprintf('%08x', int(rand(2**32))) } 1 .. 4);
}

# Assumption 2 needs a real machine-id. A host without one cannot take part.
sub _here {
    return {
        'machine-id' => _first_line('/etc/machine-id')
          // die("Cannot read /etc/machine-id: an NFS lock needs a machine id\n"),
        'boot-id' => _first_line('/proc/sys/kernel/random/boot_id')
          // die("Cannot read the boot id of this machine\n"),
        start_of => \&process_start,
    };
}

sub _first_line {
    my ($file) = @_;
    open(my $fh, '<', $file) or return undef;
    my $line = <$fh>;
    close($fh);
    return undef unless defined($line);
    chomp($line);
    return length($line) ? $line : undef;
}

sub _describe {
    my ($owner) = @_;
    return 'an unknown owner' unless defined($owner);
    return sprintf('pid %s on machine %s', $owner->{pid}, $owner->{'machine-id'});
}

# An absolute path in the message, without resolving the lock itself.
sub _absolute {
    my ($path) = @_;
    my $dir = abs_path(dirname($path)) // dirname($path);
    return "$dir/" . basename($path);
}

#--------------------------------------------------------------------------------

=head3 DESTROY

    Descriptions:
        Release the lock when the caller stops holding the returned object.

        Without this a guard that goes out of scope keeps its lock to the end of the process, and
        no take-over can recover it either, because its owner is alive. Every caller in this
        project keeps its guards in an array for exactly that reason. release checks the pid, so a
        forked child cannot free its parent's lock, and it is idempotent.

    Arguments:
        none
    Returns:
        nothing

=cut

#--------------------------------------------------------------------------------
sub DESTROY {
    local ($@, $!, $?);
    my ($self) = @_;
    eval { $self->release; 1 };
    return;
}

#--------------------------------------------------------------------------------

=head3 sweep_stranded

    Descriptions:
        Remove lock state that a killed process left behind, under one root.

        Assumption 5 says a process cannot die while it holds lock.borrow. Under this CI it does:
        the run policy aborts a condemned run and Jenkins sends SIGTERM. A borrow stranded that
        way makes its lock PERMANENTLY unacquirable, because step 3 is mkdir(lock.borrow) and a
        failure there skips steps 4 to 7 -- so the dead owner is never evicted and every later
        acquire waits out its retries. xcat-ci #80 stranded one, and #81 exited 17 on it.

        A dead owner's lock.d is removed as well. acquire would take it over, so this only saves
        the wait.

        It never infers staleness from metadata it cannot validate, and it never removes a lock
        owned by a live process or by another machine.

    Arguments:
        $root: the directory to walk
        $here: hash ref with machine-id, boot-id and start_of, as owner_is_dead takes
        %opt:  exclusive => 1 when the caller holds the run's exclusive claim on $root, so no
               live take-over can be in progress. Only then is a borrow removed: a borrow is
               otherwise a transition that is milliseconds from finishing, and removing it lets
               two takers rewrite one metadata file.
    Returns:
        A list of hash refs: path, action (removed or kept), why.

=cut

#--------------------------------------------------------------------------------
sub sweep_stranded {
    my ($root, $here, %opt) = @_;
    $here //= _here();
    my @found;
    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            my $d = $File::Find::name;
            return unless -d $d;
            # Both spellings. mockbuild-all.pl names a cell lock <dir>/.<arch>.lock, while
            # cluster-test.pl names its build lock <repo>/.build.lock.d and sbuild-all.pl uses
            # .sbuild-all.<arch>.nfslock. A matcher for '.lock' alone swept only the first.
            push @found, $d if $d =~ /\.(?:lock(?:\.d)?|nfslock)(?:\.borrow)?\z/;
        },
    }, $root) if -d $root;

    my @report;
    # A borrow before its own lock: removing the borrow is what lets the lock be taken over.
    for my $d (sort { ($b =~ /\.borrow\z/ ? 1 : 0) <=> ($a =~ /\.borrow\z/ ? 1 : 0) || $a cmp $b } @found) {
        if ($d =~ /\.borrow\z/) {
            unless ($opt{exclusive}) {
                push @report, { path => $d, action => 'kept',
                                why => 'a borrow may be a live take-over; no exclusive claim' };
                next;
            }
            push @report, _remove($d, 'borrow stranded by a killed take-over');
            next;
        }
        my $owner = _read_metadata($d);
        unless (defined($owner)) {
            push @report, { path => $d, action => 'kept',
                            why => 'metadata missing or invalid; staleness is never inferred' };
            next;
        }
        if ($owner->{'machine-id'} ne $here->{'machine-id'}) {
            push @report, { path => $d, action => 'kept',
                            why => "owned by machine $owner->{'machine-id'}" };
            next;
        }
        unless (owner_is_dead($owner, $here)) {
            push @report, { path => $d, action => 'kept',
                            why => "pid $owner->{pid} is alive" };
            next;
        }
        push @report, _remove($d, "owner pid $owner->{pid} is provably dead");
    }
    return @report;
}

sub _remove {
    my ($dir, $why) = @_;
    unlink("$dir/metadata");
    if (rmdir($dir)) { return { path => $dir, action => 'removed', why => $why } }
    return { path => $dir, action => 'kept', why => "cannot remove: $!" };
}

1;
