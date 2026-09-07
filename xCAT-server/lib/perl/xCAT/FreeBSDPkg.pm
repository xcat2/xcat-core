package xCAT::FreeBSDPkg;

use strict;
use warnings;
use Cwd qw(getcwd);
use Errno qw(EACCES EAGAIN EINTR EWOULDBLOCK);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK F_GETFD F_SETFD FD_CLOEXEC);
use IO::Select;
use POSIX qw(SIG_BLOCK SIG_SETMASK SIGCHLD WNOHANG);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC sleep);

sub _fail {
    my ($message, $stderr) = @_;
    $message = substr($message, 0, 1024);
    $message .= ': ' . substr($stderr, 0, 1024) if defined($stderr) && length($stderr);
    $message =~ s/[\x00-\x08\x0b-\x1f\x7f]/?/gx;
    die "$message\n";
}

sub _scalar {
    my $value = shift;
    return defined($value) && !ref($value) && $value !~ /\x00/x;
}

sub _environment {
    my $environment = shift;
    _fail('Command environment must be a hash') unless ref($environment) eq 'HASH';
    for my $key (keys %$environment) {
        _fail('Invalid command environment') unless $key =~ /\A[A-Za-z_][A-Za-z0-9_]*\z/x
          && _scalar($environment->{$key});
    }
    return;
}

sub _options {
    my ($argv, $options) = @_;
    _fail('Command arguments must be a nonempty array') unless ref($argv) eq 'ARRAY' && @$argv;
    _fail('Command arguments must be scalars without NUL') if grep { !_scalar($_) } @$argv;
    _fail('Command executable must be absolute') unless $argv->[0] =~ m{\A/}x;
    my %defaults = (environment => {}, cwd => getcwd(), timeout => 60,
        stdout_limit => 16777216, stderr_limit => 1048576);
    _fail('Unknown command option') if grep { !exists($defaults{$_}) } keys %$options;
    my %settings = (%defaults, %$options);
    _environment($settings{environment});
    _fail('Command directory must be an existing absolute directory')
      unless _scalar($settings{cwd}) && $settings{cwd} =~ m{\A/}x && -d $settings{cwd};
    _fail('Invalid command timeout') if !_scalar($settings{timeout})
      || $settings{timeout} !~ /\A(?:[0-9]+(?:[.][0-9]+)?|[.][0-9]+)\z/x
      || $settings{timeout} <= 0 || $settings{timeout} > 600;
    for my $item ([stdout_limit => 134217728], [stderr_limit => 16777216]) {
        my ($key, $maximum) = @$item;
        _fail("Invalid command $key") if !_scalar($settings{$key})
          || $settings{$key} !~ /\A[0-9]+\z/x || $settings{$key} > $maximum;
    }
    return \%settings;
}

sub _pipe {
    pipe(my $reader, my $writer) or _fail("Cannot create command pipe: $!");
    my $flags = fcntl($reader, F_GETFL, 0);
    _fail("Cannot inspect command pipe: $!") unless defined($flags);
    fcntl($reader, F_SETFL, $flags | O_NONBLOCK)
      or _fail("Cannot configure command pipe: $!");
    my $descriptor_flags = fcntl($writer, F_GETFD, 0);
    _fail("Cannot inspect command descriptor: $!") unless defined($descriptor_flags);
    fcntl($writer, F_SETFD, $descriptor_flags | FD_CLOEXEC)
      or _fail("Cannot configure command descriptor: $!");
    return [$reader, $writer];
}

sub _child {
    my ($argv, $settings, $pipes, $mask) = @_;
    my $ok = eval {
        defined(POSIX::setpgid(0, 0)) or die "Cannot create command process group: $!\n";
        local @SIG{qw(CHLD TERM INT HUP QUIT PIPE ALRM)} = ('DEFAULT') x 7;
        POSIX::sigprocmask(SIG_SETMASK, $mask)
          or die "Cannot restore command signal mask: $!\n";
        for my $pair (@$pipes) {
            close($pair->[0]) or die "Cannot close command pipe: $!\n";
        }
        open(STDIN, '<', '/dev/null') or die "Cannot open command input: $!\n";
        open(STDOUT, '>&', $pipes->[0][1]) or die "Cannot open command output: $!\n";
        open(STDERR, '>&', $pipes->[1][1]) or die "Cannot open command errors: $!\n";
        close($pipes->[0][1]) or die "Cannot close command output pipe: $!\n";
        close($pipes->[1][1]) or die "Cannot close command error pipe: $!\n";
        chdir($settings->{cwd}) or die "Cannot enter command directory: $!\n";
        local %ENV = %{$settings->{environment}};
        exec {$argv->[0]} @$argv or die "Cannot execute command: $!\n";
    };
    my $message = substr($ok ? 'Command setup returned unexpectedly' : ($@ || 'Command setup failed'), 0, 1024);
    while (length($message)) {
        my $written = syswrite($pipes->[2][1], $message);
        next if !defined($written) && $! == EINTR;
        last unless defined($written) && $written;
        substr($message, 0, $written, '');
    }
    POSIX::_exit(127);
    return;
}

sub _terminate {
    my $state = shift;
    return if !$state->{pid} || $state->{reaped};
    my $target = $state->{group} ? -$state->{pid} : $state->{pid};
    kill 'TERM', $target;
    sleep 0.1;
    kill 'KILL', $target;
    while (1) {
        my $waited = waitpid($state->{pid}, 0);
        next if $waited < 0 && $! == EINTR;
        $state->{reaped} = 1;
        last;
    }
    return;
}

sub _collect {
    my ($state, $settings, $pipes, $deadline) = @_;
    my $selector = IO::Select->new(map { $_->[0] } @$pipes);
    my %streams;
    my @names = qw(stdout stderr setup);
    for my $index (0 .. $#names) {
        $streams{fileno($pipes->[$index][0])} = $names[$index];
        $state->{$names[$index]} = '';
    }
    my %limits = (stdout => $settings->{stdout_limit}, stderr => $settings->{stderr_limit}, setup => 1024);
    while (1) {
        my $remaining = $deadline - clock_gettime(CLOCK_MONOTONIC);
        _fail('Command timed out', $state->{stderr}) if $remaining <= 0;
        my $pause = $remaining < 0.05 ? $remaining : 0.05;
        if ($selector->count()) {
            for my $handle ($selector->can_read($pause)) {
                my $stream = $streams{fileno($handle)};
                my $capacity = $limits{$stream} - length($state->{$stream}) + 1;
                my $read_size = $capacity < 65536 ? $capacity : 65536;
                my $read = sysread($handle, my $buffer, $read_size);
                if (!defined($read)) {
                    next if $! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK;
                    _fail("Cannot read command $stream: $!", $state->{stderr});
                }
                if ($read == 0) {
                    $selector->remove($handle);
                    close($handle) or _fail("Cannot close command $stream: $!", $state->{stderr});
                    next;
                }
                _fail("Command $stream exceeds its output limit", $state->{stderr})
                  if length($state->{$stream}) + $read > $limits{$stream};
                $state->{$stream} .= $buffer;
                _fail($state->{setup}, $state->{stderr}) if $stream eq 'setup';
            }
        } else {
            # Keep the leader unreaped while descendant-held pipes can require process-group cleanup.
            my $waited = waitpid($state->{pid}, WNOHANG);
            if ($waited == $state->{pid}) {
                my $status = $?;
                $state->{reaped} = 1;
                return { exitcode => $status >> 8, signal => $status & 127,
                    stdout => $state->{stdout}, stderr => $state->{stderr} };
            }
            if ($waited < 0) {
                next if $! == EINTR;
                $state->{reaped} = 1;
                _fail("Cannot wait for command: $!", $state->{stderr});
            }
            sleep $pause;
        }
    }
    return;
}

sub _run {
    my ($argv, $settings, $mask) = @_;
    my @pipes = map { _pipe() } 1 .. 3;
    my %state;
    my ($result, $error);
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + $settings->{timeout};
    my $ok = eval {
        require xCAT::Utils;
        my $pid = xCAT::Utils->xfork();
        _fail("Cannot fork command: $!") unless defined($pid);
        _child($argv, $settings, \@pipes, $mask) if $pid == 0;
        $state{pid} = $pid;
        if (defined(POSIX::setpgid($pid, $pid)) || $! == EACCES) {
            $state{group} = 1;
        } else {
            _fail("Cannot establish command process group: $!");
        }
        for my $pair (@pipes) {
            close($pair->[1]) or _fail("Cannot close command writer: $!");
        }
        $result = _collect(\%state, $settings, \@pipes, $deadline);
        1;
    };
    $error = $@ || 'Command failed' unless $ok;
    _terminate(\%state) if $error;
    for my $pair (@pipes) {
        for my $handle (@$pair) {
            close($handle) if defined(fileno($handle));
        }
    }
    _fail($error) if $error;
    return $result;
}

sub run_command {
    my ($argv, @options) = @_;
    _fail('Command options must be pairs') if @options % 2;
    my %options = @options;
    my $settings = _options($argv, \%options);
    my $old_mask = POSIX::SigSet->new();
    POSIX::sigprocmask(SIG_BLOCK, POSIX::SigSet->new(SIGCHLD), $old_mask)
      or _fail("Cannot block command child signal: $!");
    my ($result, $error);
    {
        my $handler = $SIG{CHLD} || 'DEFAULT';
        local $SIG{CHLD} = $handler eq 'IGNORE' ? 'DEFAULT' : $handler;
        my $ok = eval { $result = _run($argv, $settings, $old_mask); 1; };
        $error = $@ || 'Command failed' unless $ok;
    }
    POSIX::sigprocmask(SIG_SETMASK, $old_mask)
      or _fail("Cannot restore caller signal mask: $!");
    _fail($error) if $error;
    return $result;
}

1;
