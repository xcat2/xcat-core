package xCAT_plugin::hostbasedauth;

use strict;
use warnings;
use Fcntl        qw(:flock);
use File::Temp   qw(tempfile);
use Getopt::Long ();
use JSON::PP     qw(encode_json decode_json);
use POSIX        ();
use xCAT::Utils;

my $fanout = 16;
my $usage  = <<'USAGE';
Usage: mkhostbased-auth noderange --user account [--check] < verified-known-hosts
       mkhostbased-auth noderange --remove [--check] < verified-known-hosts
       mkhostbased-auth --help
USAGE

=head3 handled_commands

Return the commands handled by this plugin.

=cut

sub handled_commands {
    return { 'mkhostbased-auth' => 'hostbasedauth' };
}

=head3 process_request

Validate the command options and the management-node identity before enrolling hosts.

=cut

sub process_request {
    my ($request, $callback) = @_;
    my @args = @{ $request->{arg} || [] };
    my ($user, $remove, $check, $help);
    my $options = Getopt::Long::Parser->new(config => [qw(no_auto_abbrev no_ignore_case)]);
    my $parsed = $options->getoptionsfromarray(
        \@args,
        'user=s' => \$user,
        'remove' => \$remove,
        'check'  => \$check,
        'h|help' => \$help,
    );
    if (!$parsed || @args) {
        $callback->({ error => [$usage], errorcode => [1] });
        return 1;
    }
    if ($help) {
        $callback->({ data => [$usage] });
        return 0;
    }

    my $ok = eval {
        die "Run this command as root on the management node.\n"
          unless xCAT::Utils->isMN() && ($request->{_xcat_authname}->[0] // '') eq 'root';
        die $usage unless $remove ? !defined($user) : defined($user) && $user =~ /\A[a-z_][a-z0-9_-]*\z/ && $user ne 'root';
        my @nodes = sort @{ $request->{node} || [] };
        die "Select at least two compute nodes (one or more for --remove).\n" if @nodes < ($remove ? 1 : 2);
        my $pins = parse_pins(\@nodes, $request->{stdin}->[0] // '');
        configure(\@nodes, $pins, $user, $remove, $check, $callback);
        1;
    };
    if (!$ok) {
        my $error = $@ || "Host-based authentication configuration failed.\n";
        chomp $error;
        $callback->({ error => [$error], errorcode => [1] });
        return 1;
    }
    return 0;
}

# Read the same limited format used by the resulting dedicated OpenSSH pin file.
sub parse_pins {
    my ($nodes, $text) = @_;
    my %selected = map { $_ => 1 } @$nodes;
    for my $node (@$nodes) {
        die "Invalid node name '$node'.\n"
          unless $node =~ /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/ && $node ne 'localhost';
    }

    my (%pins, %owner);
    for my $line (split /\r?\n/, $text) {
        next if $line =~ /\A\s*(?:#|\z)/;
        my ($node, $algorithm, $blob) = $line =~ /\A(\S+)[ \t]+(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521))[ \t]+([A-Za-z0-9+\/]+={0,2})(?:[ \t]+[^\r\n]*)?\z/;
        die "Expected an exact node name and an OpenSSH public host key on every input line.\n" unless defined $node;
        die "Unexpected host key entry for '$node'.\n" unless $selected{$node};
        my $key = "$algorithm $blob";
        die "Nodes '$owner{$key}' and '$node' have the same host key.\n"
          if exists($owner{$key}) && $owner{$key} ne $node;
        next if exists $owner{$key};
        $owner{$key} = $node;
        push @{ $pins{$node} }, $key;
    }
    for my $node (@$nodes) {
        die "Missing verified host key for '$node'.\n" unless $pins{$node};
    }
    return \%pins;
}

sub reject_management_keys {
    my ($keys) = @_;
    my $config = $ENV{XCATCFG} || '/etc/xcat';
    for my $directory ('/etc/ssh', "$config/hostkeys") {
        for my $type (qw(ed25519 ecdsa rsa)) {
            my $path = "$directory/ssh_host_${type}_key";
            next unless -e $path || -e "$path.pub";
            my $key;
            if (-e $path) {
                my $result = xCAT::Utils::runcmd3(command => [ '/usr/bin/ssh-keygen', '-y', '-P', '', '-f', $path ]);
                die "Could not verify the management host key at $path.\n" if $result->{exitcode};
                $key = $result->{output};
            } else {
                open(my $public, '<', "$path.pub") or die "Cannot read $path.pub: $!\n";
                $key = <$public>;
                close $public;
            }
            my ($identity) = ($key // '') =~ /\A(\S+ \S+)/;
            die "Invalid management host key at $path.\n" unless defined $identity;
            die "Node '$keys->{$identity}' uses a shared xCAT or management SSH host key.\n" if exists $keys->{$identity};
        }
    }
}

sub configure {
    my ($nodes, $pins, $user, $remove, $check, $callback) = @_;
    my $root = $::XCATROOT || '/opt/xcat';
    open(my $helper_file, '<', "$root/share/xcat/scripts/xcat-hostbased-auth.py")
      or die "Cannot read the host-based authentication helper: $!\n";
    my $helper = do { local $/; <$helper_file> };
    close $helper_file;

    open(my $lock, '>>', '/run/xcat-mkhostbased-auth.lock') or die "Cannot open the management lock: $!\n";
    flock($lock, LOCK_EX | LOCK_NB) or die "Another mkhostbased-auth operation is in progress.\n";
    my ($known_hosts, $path) = tempfile('xcat-mkhostbased-XXXXXX', TMPDIR => 1, UNLINK => 1);
    my %identities;
    for my $node (@$nodes) {
        for my $key (@{ $pins->{$node} }) {
            print {$known_hosts} "$node $key\n" or die "Cannot write the verified host keys: $!\n";
            $identities{$key} = $node;
        }
    }
    close $known_hosts or die "Cannot save the verified host keys: $!\n";
    reject_management_keys(\%identities);

    my @peers;
    my %addresses_by_node;
    unless ($remove) {
        my (%addresses, %key_owner);
        my $installed = remote_batch($nodes, $helper, $path, sub { { operation => 'inspect', user => $user } });
        for my $node (@$nodes) {
            my $info    = $installed->{$node};
            my $address = $info->{address};
            die "$node returned an invalid or repeated IPv4 peer address.\n"
              unless defined($address) && $address =~ /\A(?:\d{1,3}\.){3}\d{1,3}\z/ && !$addresses{$address}++;
            my %available = map { $_ => 1 } @{ $info->{keys} };
            for my $key (keys %available) {
                die "Nodes '$key_owner{$key}' and '$node' have the same installed host key.\n" if exists $key_owner{$key};
                $key_owner{$key} = $node;
            }
            for my $key (@{ $pins->{$node} }) {
                die "Verified key for '$node' is missing from its standard OpenSSH host keys.\n" unless $available{$key};
            }
            push @peers, { name => $node, address => $address, keys => $pins->{$node} };
            $addresses_by_node{$node} = $address;
        }
        reject_management_keys(\%key_owner);
    }

    # Complete preflight on all nodes before starting any writes.
    for my $operation ($check ? ('check') : ('check', 'apply')) {
        my $request_for = sub {
            my ($node) = @_;
            return { operation => $operation, user => $user,
                remove => $remove ? 1 : 0, peers => \@peers, address => $addresses_by_node{$node} };
        };
        my $report;
        if ($check || $operation eq 'apply') {
            my $message = $check ? 'configuration validated' : $remove ? 'configuration removed' : 'configuration applied';
            $report = sub { $callback->({ data => ["$_[0]: $message"] }); };
        }
        remote_batch($nodes, $helper, $path, $request_for, $report);
    }
}

# Limit the number of live management SSH connections while retaining explicit host-key pins.
sub remote_batch {
    my ($nodes, $helper, $known_hosts, $request_for, $report) = @_;
    my @remaining = @$nodes;
    my (%results, @errors);
    local $SIG{CHLD} = 'DEFAULT';
    while (@remaining) {
        my @workers;
        for my $node (splice @remaining, 0, $fanout) {
            my ($reader, $writer);
            if (!pipe($reader, $writer)) {
                push @errors, "$node: Cannot open the worker pipe: $!\n";
                last;
            }
            my $pid = xCAT::Utils->xfork();
            if (!defined($pid)) {
                push @errors, "$node: Cannot start the SSH worker: $!\n";
                last;
            }
            if (!$pid) {
                close $reader;
                my $result = eval { remote($helper, $known_hosts, $node, $request_for->($node)); };
                my $written = print {$writer} encode_json({ result => $result, error => "$@" });
                my $closed = close $writer;
                POSIX::_exit($written && $closed ? 0 : 1); # Keep the parent's temporary pin file.
            }
            close $writer;
            push @workers, [ $node, $pid, $reader ];
        }
        for my $worker (@workers) {
            my ($node, $pid, $reader) = @$worker;
            my $reply = do { local $/; <$reader> };
            close $reader;
            waitpid($pid, 0);
            my $response = $? == 0 && eval { decode_json($reply // ''); };
            if (!$response) {
                push @errors, "$node: SSH worker returned no result.\n";
            } elsif ($response->{error}) {
                push @errors, $response->{error};
            } else {
                $results{$node} = $response->{result};
                $report->($node) if $report;
            }
        }
        last if @errors;
    }
    die join('', @errors) if @errors;
    return \%results;
}

sub remote {
    my ($helper, $known_hosts, $node, $request) = @_;

    # A JSON string literal also works as a Python string literal for this ASCII payload.
    my $payload = encode_json(encode_json($request));
    my $input   = "$helper\nmain($payload)\n";
    local $SIG{PIPE} = 'IGNORE';
    my @command = (
        '/usr/bin/ssh', '-4', '-T', '-F', '/dev/null',
        '-o',           "UserKnownHostsFile=$known_hosts",
        '-o',           'GlobalKnownHostsFile=/dev/null',
        '-o',           'StrictHostKeyChecking=yes',
        '-o',           'HostbasedAuthentication=no',
        '-o',           'BatchMode=yes',
        '-o',           'ConnectTimeout=8',
        '-o',           'ServerAliveInterval=5',
        '-o',           'ServerAliveCountMax=3',
        '--',           "root\@$node", 'exec /usr/bin/python3 -',
    );
    my $result = xCAT::Utils::runcmd3(command => \@command, input => $input);
    if ($result->{exitcode}) {
        my $error = $result->{errors} || 'SSH or remote configuration failed';
        chomp $error;
        die "$node: $error\n";
    }
    my $output = eval { decode_json($result->{output} // '') };
    die "$node returned an invalid configuration response.\n" unless ref($output) eq 'HASH';
    return $output;
}

1;
