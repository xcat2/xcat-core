#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Storable qw(dclone);
use Test::More;
use XCAT::Test::File qw(repo_path);

our $RCP;

BEGIN {
    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::Postage;
    $INC{'xCAT/Postage.pm'} = __FILE__;

    package xCAT::SvrUtils;
    our $synclist;
    sub getsynclistfile {
        my ( $class, $nodes ) = @_;
        return unless defined $synclist;
        return { map { $_ => $synclist->{$_} } @$nodes };
    }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    our @messages;
    sub message {
        my ( $class, @message ) = @_;
        push @messages, \@message;
        return;
    }
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    use Exporter qw(import);
    our @EXPORT = qw(noderange);
    our %nodes;
    sub noderange { return $nodes{ $_[0] }; }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/syncfiles.pm');
require $plugin;

sub run_syncfiles {
    my ($case) = @_;
    local %xCAT::NodeRange::nodes = (
        'node1.example.test' => 'node1',
        'node2.example.test' => 'node2',
    );
    local $xCAT::SvrUtils::synclist = $case->{synclist};
    local @xCAT::MsgUtils::messages;
    local @ARGV;
    local $RCP;
    my @sent;
    my $callback = sub { return; };
    my $request = dclone($case->{request} || {
        command          => ['syncfiles'],
        username         => ['operator'],
        arg              => $case->{args},
        _xcat_clienthost => [ $case->{client} ],
    });
    my $original = dclone($request);

    xCAT_plugin::syncfiles::process_request(
        $request,
        $callback,
        sub {
            my ( $outgoing, $response_callback ) = @_;
            push @sent, [ dclone($outgoing), $response_callback ];
            return;
        },
    );

    is_deeply( $request, $original, 'the caller request is unchanged' );
    is( scalar @sent, scalar @{ $case->{expected} }, 'the request count matches' );
    for my $index ( 0 .. $#{ $case->{expected} } ) {
        my ( $node, $file, $copy_args ) = @{ $case->{expected}->[$index] };
        my $sent = $sent[$index] || [];
        is_deeply(
            $sent->[0],
            {
                command  => ['xdcp'],
                username => ['root'],
                node     => [$node],
                arg      => [ '-F', $file, @$copy_args ],
                env      => ["DSH_RSYNC_FILE=$file"],
            },
            "request $index carries the root identity and copy parameters",
        );
        is( $sent->[1], $callback, "request $index retains the response callback" );
    }
    is( scalar @xCAT::MsgUtils::messages, scalar @{ $case->{messages} }, 'the diagnostic count matches' );
    for my $index ( 0 .. $#{ $case->{messages} } ) {
        my $message = $xCAT::MsgUtils::messages[$index] || [];
        is( $message->[0], 'S', 'the diagnostic goes to the system log' );
        like( $message->[1], $case->{messages}->[$index], 'the diagnostic identifies the failure' );
    }
    return;
}

my @cases = (
    {
        name     => 'daemon request without arguments or username',
        request  => { command => ['syncfiles'], _xcat_clienthost => ['node1.example.test'] },
        synclist => { node1 => '/install/custom/sync-a' },
        expected => [ [ 'node1', '/install/custom/sync-a', [] ] ],
        messages => [],
    },
    {
        name     => 'one sync file',
        client   => 'node1.example.test',
        args     => [],
        synclist => { node1 => '/install/custom/sync-a' },
        expected => [ [ 'node1', '/install/custom/sync-a', [] ] ],
        messages => [],
    },
    {
        name     => 'multiple sync files retain order and identity',
        client   => 'node2.example.test',
        args     => [],
        synclist => { node2 => '/install/custom/sync-b,/install/custom/sync-a,/install/custom/sync-c' },
        expected => [
            [ 'node2', '/install/custom/sync-b', [] ],
            [ 'node2', '/install/custom/sync-a', [] ],
            [ 'node2', '/install/custom/sync-c', [] ],
        ],
        messages => [],
    },
);

for my $option ( '-r', '-c', '--node-rcp' ) {
    push @cases, {
        name     => "copy override $option retains identity on every request",
        client   => 'node1.example.test',
        args     => [ $option, '/usr/bin/scp' ],
        synclist => { node1 => '/install/custom/sync-a,/install/custom/sync-b' },
        expected => [
            [ 'node1', '/install/custom/sync-a', [ '-r', '/usr/bin/scp' ] ],
            [ 'node1', '/install/custom/sync-b', [ '-r', '/usr/bin/scp' ] ],
        ],
        messages => [],
    };
}

push @cases,
    {
        name     => 'unavailable synclist lookup sends no request',
        client   => 'node1.example.test',
        args     => [],
        synclist => undef,
        expected => [],
        messages => [ qr/\ACannot find synclist file for the node1\z/ ],
    },
    {
        name     => 'node without a synclist sends no request',
        client   => 'node1.example.test',
        args     => [],
        synclist => { node1 => undef },
        expected => [],
        messages => [],
    },
    {
        name     => 'unresolved client sends no request',
        client   => 'unknown.example.test',
        args     => [],
        synclist => { node1 => '/install/custom/sync-a' },
        expected => [],
        messages => [ qr/couldn't be correlated to a node/ ],
    };

for my $case (@cases) {
    subtest $case->{name} => sub { run_syncfiles($case); };
}

done_testing();
