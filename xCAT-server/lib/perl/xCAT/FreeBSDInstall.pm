package xCAT::FreeBSDInstall;

use strict;
use warnings;
use Fcntl qw(:DEFAULT :flock);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use IO::Handle;
use JSON;

my $json = JSON->new->canonical;
my %phases = map { $_ => 1 } qw(prepared installing completing installed booted failed cancelled);

sub _fail { die "FreeBSD installation: $_[0]\n"; }

sub _identifier {
    my ($value, $length) = @_;
    return defined($value) && !ref($value) && $value =~ /\A[0-9a-f]{$length}\z/;
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

sub _locked {
    my ($node, $options, $operation) = @_;
    _fail('Invalid node name') unless defined($node) && !ref($node) &&
        $node =~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/;
    my $directory = $options->{directory} || '/var/lib/xcat/freebsd-install';
    make_path($directory, { mode => 0700 }) unless -e $directory || -l $directory;
    my @stat = lstat($directory);
    _fail('Unsafe state directory') unless @stat && -d _ && !-l _ && $stat[4] == $> && !($stat[2] & 0077);
    sysopen(my $lock, "$directory/$node.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0600)
        or _fail("Cannot open installation lock: $!");
    @stat = stat($lock);
    _fail('Unsafe installation lock') unless -f $lock && $stat[4] == $> && !($stat[2] & 0077);
    flock($lock, LOCK_EX) or _fail("Cannot lock installation: $!");
    my $state = _read_state("$directory/$node.json", $node);
    my $result = $operation->($state, sub { _save_state($directory, $node, $_[0]); });
    close($lock) or _fail("Cannot close installation lock: $!");
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
    return _locked($node, \%options, sub {
        my ($state, $save) = @_;
        if ($state) {
            _fail('Stop the node and run nodeset offline before rearming this installation')
                if $state->{phase} =~ /\A(?:installing|completing|failed)\z/;
            return $state->{generation} if $state->{phase} eq 'prepared' && $state->{fingerprint} eq $fingerprint;
        }
        $state = { version => 1, node => $node, fingerprint => $fingerprint,
            generation => _generation(), phase => 'prepared' };
        $save->($state);
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
    my $address = xCAT::NetworkUtils->getipaddr($node);
    $peer =~ s/\A::ffff:// if defined($peer) && !ref($peer);
    _fail('Unexpected installation client') unless defined($peer) && !ref($peer) &&
        defined($address) && $address ne '0' && $peer eq $address;
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

1;
