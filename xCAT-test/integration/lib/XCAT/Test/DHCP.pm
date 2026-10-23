package XCAT::Test::DHCP;

# Process helpers for the integration tests that run a DHCP daemon. They signal only the processes
# that a test started, never a daemon found by name.

use strict;
use warnings;

use Exporter qw(import);
use IO::Select;
use IO::Socket::INET;
use POSIX qw(WNOHANG _exit setgid setuid);
use Socket qw(AF_INET6 IN6ADDR_ANY IPPROTO_IPV6 IPV6_MULTICAST_IF SOCK_DGRAM inet_aton inet_ntop inet_pton
  pack_sockaddr_in pack_sockaddr_in6);
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
  dhcp6_exchange
  dhcp6_exchange_main
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

# DHCPv6 options, as an option code and its value, in the order of a message.
sub _dhcp6_options {
    return join '', map { pack( 'n n', $_->[0], length $_->[1] ) . $_->[1] } @_;
}

sub _dhcp6_parse_options {
    my ($data) = @_;
    my @options;
    my $offset = 0;
    while ( $offset + 4 <= length $data ) {
        my ( $code, $length ) = unpack( 'n n', substr( $data, $offset, 4 ) );
        last if $offset + 4 + $length > length $data;
        push @options, [ $code, substr( $data, $offset + 4, $length ) ];
        $offset += 4 + $length;
    }
    return @options;
}

# The address, the status code of the IA_NA, the bootfile-url and the server identifier of an Advertise
# or a Reply for transaction $xid. Nothing for any other packet.
sub _dhcp6_answer {
    my ( $packet, $type, $xid ) = @_;

    return if length($packet) < 4;
    my ( $got_type, $got_xid ) = ( ord( substr( $packet, 0, 1 ) ), substr( $packet, 1, 3 ) );
    return if $got_type != $type || $got_xid ne $xid;

    my %answer;
    foreach my $option ( _dhcp6_parse_options( substr( $packet, 4 ) ) ) {
        my ( $code, $value ) = @$option;
        $answer{server_id} = $value if $code == 2;
        $answer{bootfile_url} = $value if $code == 59;
        $answer{status} = unpack( 'n', $value ) if $code == 13;
        next unless $code == 3 && length($value) >= 12;
        foreach my $ia_option ( _dhcp6_parse_options( substr( $value, 12 ) ) ) {
            my ( $ia_code, $ia_value ) = @$ia_option;
            $answer{address} = inet_ntop( AF_INET6, substr( $ia_value, 0, 16 ) ) if $ia_code == 5 && length($ia_value) >= 24;
            $answer{status} = unpack( 'n', $ia_value ) if $ia_code == 13;
        }
    }
    return \%answer;
}

# Send a message from the DHCPv6 client port of $interface to All_DHCP_Relay_Agents_and_Servers and
# return the answer of type $type, or undef when none comes. Each try waits 2 s, and there are 3 tries.
sub _dhcp6_send {
    my ( $socket, $ifindex, $type, $answer_type, @options ) = @_;

    my $servers = pack_sockaddr_in6( 547, inet_pton( AF_INET6, 'ff02::1:2' ), $ifindex );
    my $select = IO::Select->new($socket);
    for my $try ( 1 .. 3 ) {
        my $xid = pack( 'N', int( rand(0xffffff) ) );
        $xid = substr( $xid, 1, 3 );
        send( $socket, chr($type) . $xid . _dhcp6_options( @options, [ 8, pack( 'n', 0 ) ] ), 0, $servers )
          or die "Unable to send: $!";
        my $deadline = time + 2;
        while ( ( my $left = $deadline - time ) > 0 ) {
            last unless $select->can_read($left);
            my $reply = '';
            recv( $socket, $reply, 2048, 0 );
            my $answer = _dhcp6_answer( $reply, $answer_type, $xid );
            return $answer if $answer;
        }
    }
    return;
}

# A DHCPv6 exchange of a client with the DUID $opts{duid} on $opts{interface}, as UEFI firmware sends
# it: a Solicit for an address with the bootfile-url, and with $opts{request} the Request for the
# advertised address. Returns the Advertise and, when requested, the Reply.
sub dhcp6_exchange {
    my (%opts) = @_;

    my $ifindex = do {
        open( my $fh, '<', "/sys/class/net/$opts{interface}/ifindex" ) or die "Unable to read the index of $opts{interface}: $!";
        my $index = <$fh>;
        close($fh);
        chomp $index;
        $index;
    };
    socket( my $socket, AF_INET6, SOCK_DGRAM, 0 ) or die "Unable to create a socket: $!";
    setsockopt( $socket, IPPROTO_IPV6, IPV6_MULTICAST_IF, pack( 'I', $ifindex ) ) or die "Unable to select $opts{interface}: $!";
    bind( $socket, pack_sockaddr_in6( 546, IN6ADDR_ANY ) ) or die "Unable to bind the DHCPv6 client port: $!";

    my $duid = pack( 'H*', join '', split /:/, $opts{duid} );
    my @common = ( [ 1, $duid ], [ 6, pack( 'n n', 59, 23 ) ], [ 61, pack( 'n', 7 ) ] );
    my %result;
    my $advertise = _dhcp6_send( $socket, $ifindex, 1, 2, @common, [ 3, pack( 'N N N', 1, 0, 0 ) ] );
    $result{advertise} = $advertise ? { %$advertise } : undef;
    delete $result{advertise}{server_id} if $advertise;
    if ( $opts{request} && $advertise && $advertise->{address} ) {
        my $ia = pack( 'N N N', 1, 0, 0 ) . _dhcp6_options( [ 5, inet_pton( AF_INET6, $advertise->{address} ) . pack( 'N N', 0, 0 ) ] );
        my $reply = _dhcp6_send( $socket, $ifindex, 3, 7, @common, [ 2, $advertise->{server_id} ], [ 3, $ia ] );
        $result{reply} = $reply ? { %$reply } : undef;
        delete $result{reply}{server_id} if $reply;
    }
    close($socket);
    return \%result;
}

# Run dhcp6_exchange for the client that a JSON object describes, and print its result as JSON. A
# test runs it in the client network namespace.
sub dhcp6_exchange_main {
    my ($json) = @_;

    require JSON;
    print JSON->new->canonical->encode( dhcp6_exchange( %{ JSON::decode_json($json) } ) ), "\n";
    return;
}

1;
