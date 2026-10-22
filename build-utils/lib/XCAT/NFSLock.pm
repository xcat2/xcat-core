package XCAT::NFSLock;

# NFS lock protocol
#
# Copies
#   This module is vendored three times, because no repo installs another's build tooling:
#     xcat-dep         lib/XCAT/NFSLock.pm              (the original)
#     xcat-core        build-utils/lib/XCAT/NFSLock.pm
#     xcat-core-ci-cd  ci/lib/XCAT/NFSLock.pm
#   The three must stay identical. They have diverged once already: sweep_stranded was added to
#   the ci-cd copy alone, so the protocol hole it covers stayed open in the other two. Its only
#   caller is still in xcat-core-ci-cd (ci/sweep-stranded-locks.pl); it stays in all three copies
#   because a copy that drops it reopens that hole.
#
# A lock on a shared, possibly re-exported, NFS tree. flock and fcntl are not
# available there. The protocol uses mkdir, rmdir, unlink and plain file
# writes. It uses no rename.
#
# Names in this module
#   lock.d           the lock path given to acquire
#   lock.d/metadata  the metadata of the owner
#   lock.borrow      <lock path>.borrow, beside lock.d: borrow generation 0
#   lock.borrow.N    borrow generation N, N >= 1
#   R, T, δ          the options retries, delay and jitter
#
# Borrow generations
#   The borrow is the mutex for an ownership transition. The one safe way to end a transition its
#   own taker did not end is to SUPERSEDE it, never to remove it. rmdir names a path and not the
#   inode that was validated, so a reaper that validates a borrow and then removes it deletes
#   whatever is at that path when it runs, which can be a live taker's borrow.
#
#   The taker is the process holding the HIGHEST generation present. A contender supersedes
#   generation N by mkdir(lock.borrow.<N+1>), and only after N's metadata proves its taker dead.
#   mkdir is exclusive, so exactly one contender wins a generation. A process removes only a
#   generation it created and still holds, so no process can delete another process's claim.
#
# Assumptions
#   1. mkdir(path) is atomic and exclusive among contenders, and successful
#      namespace changes eventually become visible.
#   2. machine-id is unique among participating hosts.
#      Cloned VMs and images can share it by accident unless it is regenerated.
#   3. Metadata writes eventually become readable completely and consistently.
#   4. A host never declares one of its own live process incarnations dead.
#   5. A process MAY die at any point, a borrow generation included. The borrow carries the same
#      metadata as the lock, so a generation whose taker is provably dead is superseded by the
#      next generation.
#      A generation with no valid metadata is a taker that died, or paused, between its mkdir and
#      its first write. Nothing can prove that taker dead, so it blocks every later acquire, and
#      only sweep_stranded removes it, under an exclusive claim on the root.
#      A lock.d with no valid metadata blocks the same way, for the same reason. The build lock in
#      xcat-core wrote no metadata and held lock.d for the whole build, so no fact on disk tells
#      that holder from a dead one.
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
#   ownership from invalid metadata. A directory unchanged for some time is not evidence either:
#   a live participant can pause for any length of time between two writes.
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
#   3. Take the borrow, then write valid metadata into it. Taking it is mkdir of generation 0
#      when no generation exists, and otherwise mkdir of the generation after the highest one
#      whose metadata proves its taker dead.
#      - the highest generation has no valid metadata, names another machine, or names a live
#        process: retry
#      - another contender won that generation: retry
#      - other failure: retry
#   4. Read and validate the metadata again.
#      - invalid, missing, or ownership identity changed: rmdir lock.borrow, retry
#   5. Prove that the recorded (boot-id, pid, pstart) is dead.
#      - not provably dead: rmdir lock.borrow, retry
#      - dead: continue
#   6. Replace the metadata with the identity of this process and a fresh token.
#   7. rmdir lock.borrow
#   8. Call the worker.
#   9. Take the borrow as in step 3, then write valid metadata into it
#      - not available: sleep(T + rand(-δ, δ)), retry step 9, R times at most, then give up
#  10. unlink lock.d/metadata
#  11. rmdir lock.d (the actual unlock)
#  12. rmdir lock.borrow
#
# Core invariants
#   lock.d exists         => locked
#   lock.d absent         => acquirable
#   invalid metadata      => retry only
#   different machine-id  => never recover here
#   a borrow generation   => a transition or a release is in progress, unless the highest
#                            generation's metadata proves its taker dead
#   removal               => a process removes only a generation it created and still holds
#
# Steps 1 to 7 are acquire, step 8 is the caller, steps 9 to 12 are release.
# release does steps 10 and 11 only when the metadata names this acquisition.
#
# Log
#   Unless quiet => 1, each lock event prints one line to the selected output handle:
#     [nfslock] <UTC time> <host> pid=<pid> <event> <label> <lock.d> [detail]
#   Events: acquired (step 1), took-over (step 6), took-borrow (a superseded generation),
#   wait (a retry), released (step 11), release-skipped. The time has milliseconds, so the lines
#   of two hosts sort into one order.

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
    my $abs  = _absolute($path);
    my $self = bless {
        path    => $abs,
        label   => $label,
        pid     => $$,
        delay   => $delay,
        jitter  => $jitter,
        retries => $retries,
        quiet   => $opt{quiet} ? 1 : 0,
    }, $class;
    my $here = _here();
    my $seen;

    for (my $count = 0 ; ; $count++) {
        # Step 1.
        if (mkdir($abs)) {
            my $mine = this_process();
            if (eval { _write_metadata($abs, $mine); 1 }) {
                # Only now. release acts on identity, and DESTROY calls release, so an acquire
                # that failed must leave nothing for the destructor to act on.
                $self->{identity} = $mine;
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
            # Step 3.
            my ($generation, $why) = _take_borrow($abs, $here);
            if (defined($generation)) {
                my $borrow = _borrow_path($abs, $generation);
                $self->_log('took-borrow', $why) if $generation;
                _at('borrow-created');
                # Steps 4 to 7.
                my $taken = eval {
                    # The borrow names its taker, so a taker that dies here is superseded by the
                    # next generation. Written before the death check, where a SIGKILL lands.
                    _write_metadata($borrow, this_process());
                    _at('borrow-held');
                    my $again = _read_metadata($abs);
                    return 0 unless defined($again) && _key($again) eq _key($observed);
                    return 0 unless owner_is_dead($again, $here);
                    my $mine = this_process();
                    _at('before-commit');
                    _write_metadata($abs, $mine);
                    $self->{identity} = $mine;
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
        }

        last if $count >= $retries;
        $self->_log('wait', sprintf('retry %d/%d, owner %s', $count + 1, $retries, _describe($seen)));
        _sleep(_wait($delay, $jitter));
    }

    my $who = _describe($seen);
    my $s   = $retries == 1 ? 'retry' : 'retries';
    # Names what happened, so a caller can tell a lock another process still holds from a mkdir
    # that failed outright. The earlier wording said "Trying to unlock", which is the reverse.
    die "Cannot lock $abs: still held after $retries $s by $who.\n"
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
    # acquire that dies would otherwise reach the wait loop below.
    return 0 unless defined($self->{identity});
    my $path = $self->{path};
    my $here = _here();
    my $why  = 'no attempt was made';
    # Bounded. DESTROY reaches this loop, so an unbounded wait turns a lock whose metadata
    # cannot be validated into a process that never returns its own error.
    for (my $count = 0 ; ; $count++) {
        # Step 9.
        my ($generation, $reason) = _take_borrow($path, $here);
        $why = $reason;
        if (defined($generation)) {
            my $borrow = _borrow_path($path, $generation);
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
            $why = 'the lock metadata cannot be validated';
        }
        if ($count >= $self->{retries}) {
            $self->{released} = 1;
            $self->_log('release-skipped', "gave up: $why");
            warn "Cannot release $path after $count retries: $why\n";
            return 0;
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

# _at: a point in the protocol a test can stop a process at, to force one interleaving instead of
# depending on timing. It does nothing here.
sub _at { return }

sub _borrow_path {
    my ($abs, $generation) = @_;
    return $generation ? "$abs.borrow.$generation" : "$abs.borrow";
}

# _borrow_top: the highest borrow generation present for this lock, or undef when none is.
sub _borrow_top {
    my ($abs) = @_;
    opendir(my $dh, dirname($abs)) or return undef;
    my $name = basename($abs);
    my $top;
    while (defined(my $entry = readdir($dh))) {
        next unless $entry =~ /\A\Q$name\E\.borrow(?:\.([0-9]+))?\z/;
        my $generation = defined($1) ? $1 + 0 : 0;
        $top = $generation if !defined($top) || $generation > $top;
    }
    closedir($dh);
    return $top;
}

# _take_borrow: become the taker of the ownership transition, or say why not.
#
# It never removes a generation. A transition whose taker is provably dead is ended by creating
# the NEXT generation, because rmdir names a path and not the inode that was validated: a reaper
# that validated a dead taker's borrow and then removed it by path could remove a live taker's
# borrow instead, and two processes then took over one lock.
#
# Returns ($generation, $why), or (undef, $why) when the borrow is not available.
sub _take_borrow {
    my ($abs, $here) = @_;
    my $top = _borrow_top($abs);
    unless (defined($top)) {
        _at('before-create');
        return (0, 'created the borrow') if mkdir(_borrow_path($abs, 0));
        return (undef, 'another process created the borrow') if $! == EEXIST;
        return (undef, "cannot create the borrow: $!");
    }
    my $taker = _read_metadata(_borrow_path($abs, $top));
    return (undef, "generation $top holds no valid metadata") unless defined($taker);
    return (undef, "generation $top is held by machine $taker->{'machine-id'}")
      unless $taker->{'machine-id'} eq $here->{'machine-id'};
    return (undef, "generation $top is held by live pid $taker->{pid}")
      unless owner_is_dead($taker, $here);
    _at('before-supersede');
    my $next = $top + 1;
    return ($next, "superseded generation $top, held by dead pid $taker->{pid}")
      if mkdir(_borrow_path($abs, $next));
    return (undef, "another process superseded generation $top");
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

        A process killed during a transition leaves a borrow generation behind. Under this CI
        that happens: the run policy aborts a condemned run and Jenkins sends SIGTERM. acquire
        supersedes a generation whose metadata proves its taker dead, so that one needs no
        sweep. A generation with NO valid metadata is a taker killed, or paused, between its
        mkdir and its first write, and nothing can prove that taker dead, so it blocks every
        later acquire. xcat-ci #80 stranded one, and #81 exited 17 on it.

        A dead owner's lock.d is removed as well. acquire would take it over, so this only saves
        the wait.

        It never removes a lock owned by a live process or by another machine, and it never
        infers staleness from a metadata file it cannot validate.

        A lock.d or a borrow generation with NO valid metadata is removed only with
        exclusive => 1. acquire refuses both, because nothing on disk tells a dead holder from a
        live one that has not written yet. Only a caller that claims the root exclusively can
        say either is abandoned.

    Arguments:
        $root: the directory to walk
        $here: hash ref with machine-id, boot-id and start_of, as owner_is_dead takes
        %opt:  exclusive => 1 when the caller holds the run's exclusive claim on $root, so no
               build and no transition can be in progress. Only then is a borrow generation
               removed, and only then a lock.d with no metadata: a generation is otherwise a
               transition that is milliseconds from finishing, and removing it lets two takers
               rewrite one metadata file.
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
            push @found, $d if $d =~ /\.(?:lock(?:\.d)?|nfslock)(?:\.borrow(?:\.[0-9]+)?)?\z/;
        },
    }, $root) if -d $root;

    my @report;
    # A borrow before its own lock: removing the borrow is what lets the lock be taken over.
    for my $d (sort { ($b =~ /\.borrow(?:\.[0-9]+)?\z/ ? 1 : 0) <=> ($a =~ /\.borrow(?:\.[0-9]+)?\z/ ? 1 : 0)
                      || $a cmp $b } @found) {
        if ($d =~ /\.borrow(?:\.[0-9]+)?\z/) {
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
            if (-e "$d/metadata") {
                push @report, { path => $d, action => 'kept',
                                why => 'metadata invalid; staleness is never inferred' };
                next;
            }
            unless ($opt{exclusive}) {
                push @report, { path => $d, action => 'kept',
                                why => 'no metadata; no exclusive claim on the root' };
                next;
            }
            push @report, _remove($d, 'no metadata, and the caller claims the root exclusively');
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
