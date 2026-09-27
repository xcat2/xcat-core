package XCAT::Test::DHCP;

# Process helpers for the integration tests that run a DHCP daemon. They signal only the processes
# that a test started, never a daemon found by name.

use strict;
use warnings;

use Exporter qw(import);
use IO::Select;
use IO::Socket::INET;
use POSIX qw(WNOHANG _exit setgid setuid);
use Socket qw(inet_aton pack_sockaddr_in);
use Test::More ();
use Time::HiRes qw(sleep time);

our @EXPORT_OK = qw(
  start_daemon
  process_running
  stop_daemons
  wait_for_socket
  wait_for_file
  diag_file
  discover_packet
  offer_boot_file
  relay_discover
  relay_discover_main
);

sub start_daemon {
    my ( $account, $command, $log, @args ) = @_;
    my $pid = fork();
    die "Unable to fork $command: $!" unless defined $pid;
    if ($pid == 0) {
        open(STDOUT, '>', $log) or child_exit("Unable to write $log: $!");
        open(STDERR, '>&', \*STDOUT) or child_exit("Unable to redirect stderr: $!");
        _assume_account($account) if $account;
        {
            no warnings 'exec';
            exec { $command } $command, @args;
            child_exit("Unable to exec $command: $!");
        }
    }
    return $pid;
}

sub _assume_account {
    my ($account) = @_;

    $) = "$account->{gid} $account->{gid}";
    defined( setgid( $account->{gid} ) )
      or child_exit("Unable to set group identity to $account->{gid}: $!");
    my @group_ids = split /\s+/, $);
    $( == $account->{gid} && @group_ids && !grep { $_ != $account->{gid} } @group_ids
      or child_exit("The child did not assume group identity $account->{gid}");
    defined( setuid( $account->{uid} ) )
      or child_exit("Unable to set user identity to $account->{uid}: $!");
    $> == $account->{uid} && $< == $account->{uid}
      or child_exit("The child did not assume user identity $account->{uid}");
}

sub child_exit {
    my ($message) = @_;

    warn "$message\n";
    _exit(127);
}

sub wait_for_socket {
    my ( $pid, $socket_path, $children ) = @_;

    for (1 .. 100) {
        return 0 unless process_running( $pid, $children );
        return 1 if -S $socket_path;
        sleep 0.1;
    }

    return 0;
}

sub wait_for_file {
    my ( $pid, $path, $children ) = @_;

    for (1 .. 100) {
        return 0 unless process_running( $pid, $children );
        return 1 if -f $path;
        sleep 0.1;
    }

    return 0;
}

sub process_running {
    my ( $pid, $children ) = @_;

    my $waited = waitpid( $pid, WNOHANG );
    return 1 if $waited == 0;

    delete $children->{$pid};
    return 0;
}

sub stop_daemons {
    my ($children) = @_;

    my @pids = keys %$children;
    kill 'TERM', @pids if @pids;
    foreach my $pid (@pids) {
        for (1 .. 50) {
            last unless process_running( $pid, $children );
            sleep 0.1;
        }
        next unless exists $children->{$pid};

        kill 'KILL', $pid;
        waitpid( $pid, 0 );
        delete $children->{$pid};
    }

    return;
}

sub diag_file {
    my ($path) = @_;

    return unless -e $path;
    open( my $fh, '<', $path ) or return;
    local $/;
    my $content = <$fh>;
    close($fh) or Test::More::diag("Unable to close $path: $!");
    Test::More::diag($content) if defined($content) && $content ne '';

    return;
}

# A DHCPDISCOVER that a relay agent at $opts{relay} forwards for a PXE client. $opts{ipxe} lists the
# option 175 sub-options in the order to send, as [code, value] pairs.
sub discover_packet {
    my (%opts) = @_;

    my $mac = pack( 'H12', join '', split /:/, $opts{mac} );
    my $packet = pack( 'C4 N n n a4 a4 a4 a4 a16 a64 a128 N',
        1, 1, 6, 1, $opts{xid}, 0, 0, "\0" x 4, "\0" x 4, "\0" x 4, inet_aton( $opts{relay} ),
        $mac, '', '', 0x63825363 );

    my @options = (
        [ 53, pack( 'C', 1 ) ],
        [ 61, "\x01$mac" ],
        [ 60, sprintf( 'PXEClient:Arch:%05d:UNDI:002001', $opts{arch} ) ],
        [ 93, pack( 'n', $opts{arch} ) ],
        [ 97, "\0" . substr( $mac x 3, 0, 16 ) ],
    );
    push @options, [ 77, $opts{user_class} ] if defined $opts{user_class};
    push @options, [ 175, join '', map { pack( 'CC', $_->[0], length $_->[1] ) . $_->[1] } @{ $opts{ipxe} } ]
      if $opts{ipxe};
    $packet .= pack( 'CC', $_->[0], length $_->[1] ) . $_->[1] for @options;

    return $packet . "\xff";
}

# The boot file of a DHCPOFFER for transaction $xid: option 67 when the server sends it, otherwise
# the file field. Nothing for any other packet.
sub offer_boot_file {
    my ( $packet, $xid ) = @_;

    return if length($packet) < 240;
    my ( $op, $got_xid, $file, $cookie ) = unpack( 'C x3 N x100 Z128 N', $packet );
    return if $op != 2 || $got_xid != $xid || $cookie != 0x63825363;

    my ( $type, $option67 );
    my $offset = 240;
    while ( $offset < length $packet ) {
        my $code = ord substr( $packet, $offset, 1 );
        last if $code == 255;
        if ( $code == 0 ) { $offset++; next; }
        my $length = ord substr( $packet, $offset + 1, 1 );
        my $value = substr( $packet, $offset + 2, $length );
        $type = ord $value if $code == 53;
        ( $option67 = $value ) =~ s/\0+\z// if $code == 67;
        $offset += 2 + $length;
    }
    return if !defined $type || $type != 2;
    return defined $option67 ? $option67 : $file;
}

# Send a relayed DHCPDISCOVER to the server and return the boot file of its DHCPOFFER, or undef when
# no offer comes. Each try waits 3 s, and there are 3 tries.
sub relay_discover {
    my (%opts) = @_;

    my $socket = IO::Socket::INET->new(
        LocalAddr => $opts{relay},
        LocalPort => 67,
        Proto     => 'udp',
        ReuseAddr => 1,
    ) or die "Unable to bind $opts{relay}:67: $!";
    my $server = pack_sockaddr_in( 67, inet_aton( $opts{server} ) );
    my $select = IO::Select->new($socket);

    for my $try ( 1 .. 3 ) {
        my $xid = int( rand( 0xffffffff ) );
        send( $socket, discover_packet( %opts, xid => $xid ), 0, $server ) or die "Unable to send: $!";
        my $deadline = time + 3;
        while ( ( my $left = $deadline - time ) > 0 ) {
            last unless $select->can_read($left);
            my $reply = '';
            recv( $socket, $reply, 1500, 0 );
            my $file = offer_boot_file( $reply, $xid );
            return $file if defined $file;
        }
    }
    return;
}

# Run relay_discover for the client that a JSON object describes, with each option 175 value in hex,
# and print the boot file or NO-OFFER. A test runs it in the client network namespace.
sub relay_discover_main {
    my ($json) = @_;

    require JSON;
    my $opts = JSON::decode_json($json);
    $opts->{ipxe} = [ map { [ $_->[0], pack( 'H*', $_->[1] ) ] } @{ $opts->{ipxe} } ] if $opts->{ipxe};
    my $file = relay_discover(%$opts);
    print defined $file ? "$file\n" : "NO-OFFER\n";
    return;
}

1;
