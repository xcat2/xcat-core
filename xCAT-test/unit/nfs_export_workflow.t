#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use xCAT::SvrUtils;

my $export_options = 'rw,no_root_squash,sync,no_subtree_check,insecure';

for my $caller (qw(setupNFSTree setupStatemnt)) {
    subtest "$caller creates active and persistent exports once" => sub {
        my $result = exercise_workflow( $caller, 'missing' );
        my @prefix = command_prefix( $caller, $result->{directory} );
        my $append = append_command( $caller, $result->{directory} );

        is_deeply(
            $result->{runs}->[0]->{commands},
            [
                @prefix,
                "/usr/sbin/exportfs :$result->{directory} -o $export_options",
                $append,
            ],
            'the first run activates and persists the missing export'
        );
        is_deeply(
            $result->{runs}->[0]->{messages},
            [
                "now $result->{directory} is exported!",
                added_message( $caller, $result->{directory} ),
            ],
            'the first run retains its caller-specific messages'
        );
        is_deeply(
            $result->{runs}->[1]->{commands},
            [ command_prefix( $caller, $result->{directory} ) ],
            'the second run does not repeat export mutations'
        );
        is_deeply(
            $result->{runs}->[1]->{messages},
            [ "$result->{directory} has been exported already!" ],
            'the second run reports the active export'
        );
        ok( -d $result->{directory}, 'the missing export directory is created' );
        is_deeply(
            $result->{ensure_calls},
            [
                [ $result->{directory}, 'insecure' ],
                [ $result->{directory}, 'insecure' ],
            ],
            'persistent options are checked on every run'
        );
        is( $result->{exists_calls}, 2,
            'persistent existence is checked when no option changes' );
        is_deeply(
            $result->{command_args}, expected_command_args( $result->{runs} ),
            'every command retains the suppressed-error mode'
        );
        is_deeply(
            $result->{getipaddr_calls}, expected_getipaddr_calls($caller),
            'the state-mount caller resolves the NFS server'
        );
    };

    subtest "$caller reloads an export after adding insecure" => sub {
        my $result = exercise_workflow( $caller, 'missing-option' );
        my @prefix = command_prefix( $caller, $result->{directory} );

        is_deeply(
            $result->{runs}->[0]->{commands},
            [ @prefix, '/usr/sbin/exportfs -r' ],
            'the first run reloads after updating the persistent export'
        );
        is_deeply(
            $result->{runs}->[0]->{messages},
            [
                "$result->{directory} has been exported already!",
                "added insecure to existing $result->{directory} export",
            ],
            'the option update retains its callback messages'
        );
        is_deeply(
            $result->{runs}->[1]->{commands},
            [ command_prefix( $caller, $result->{directory} ) ],
            'the second run does not reload an unchanged export'
        );
        is_deeply(
            $result->{runs}->[1]->{messages},
            [ "$result->{directory} has been exported already!" ],
            'the unchanged export has only the active message'
        );
        ok( -d $result->{directory},
            'a file at the export path is replaced with a directory' );
        is( $result->{exists_calls}, 1,
            'persistent existence is skipped when the option changed' );
        is_deeply(
            $result->{command_args}, expected_command_args( $result->{runs} ),
            'reload commands retain the suppressed-error mode'
        );
    };

    subtest "$caller ignores exports hosted elsewhere" => sub {
        my $result = exercise_remote_export($caller);
        my @expected = $caller eq 'setupNFSTree'
          ? ('XCATBYPASS=Y litetree node1')
          : ();
        is_deeply( $result->{commands}, \@expected,
            'no export command runs for a remote server' );
        is_deeply( $result->{messages}, [],
            'no callback message is emitted for a remote server' );
        ok( !-e $result->{directory},
            'a remote export directory is not created locally' );
        is_deeply(
            $result->{command_args},
            [ map { [ $_, 0 ] } @expected ],
            'remote-server checks retain the suppressed-error mode'
        );
        my $expected_getipaddr = $caller eq 'setupStatemnt'
          ? [ ['nfs-server'] ]
          : [];
        is_deeply( $result->{getipaddr_calls}, $expected_getipaddr,
            'only the state-mount caller resolves the remote server' );
    };
}

subtest 'setupNFSTree handles multiple litetree entries independently' => sub {
    my $result = exercise_multiple_tree_uris();
    is_deeply(
        $result->{command_args},
        [
            [ 'XCATBYPASS=Y litetree node1', 0 ],
            [ 'showmount -e nfs-server', 0 ],
        ],
        'only the local URI reaches the export workflow'
    );
    is_deeply(
        $result->{messages},
        [ "$result->{local_directory} has been exported already!" ],
        'the local URI emits one callback message'
    );
    ok( -d $result->{local_directory}, 'the local URI directory is created' );
    ok( !-e $result->{remote_directory},
        'the remote URI directory is not created' );
};

done_testing();

sub exercise_workflow {
    my ( $caller, $scenario ) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $directory = "$root/export";
    if ( $scenario eq 'missing-option' ) {
        open( my $fh, '>', $directory )
          or die "Unable to create $directory: $!";
        close($fh) or die "Unable to close $directory: $!";
    }

    my $active = $scenario eq 'missing' ? 0 : 1;
    my $persistent = $scenario eq 'missing' ? 0 : 1;
    my $option_missing = $scenario eq 'missing-option' ? 1 : 0;
    my @commands;
    my @command_args;
    my @getipaddr_calls;
    my @messages;
    my @ensure_calls;
    my $exists_calls = 0;
    my @runs;

    no warnings 'redefine';
    local *xCAT::Utils::runcmd = sub {
        my @args = @_;
        shift @args if @args && $args[0] eq 'xCAT::Utils';
        my ($command) = @args;
        push @commands, $command;
        push @command_args, [@args];

        if ( $command eq 'XCATBYPASS=Y litetree node1' ) {
            return ("node1: nfs-server:$directory");
        }
        if ( $command eq 'showmount -e nfs-server' ) {
            return $active
              ? ( 'Export list for nfs-server:', "$directory *" )
              : ('Export list for nfs-server:');
        }
        if ( $command eq "/usr/sbin/exportfs :$directory -o $export_options" ) {
            $active = 1;
        } elsif ( $command eq append_command( $caller, $directory ) ) {
            $persistent = 1;
        }
        return;
    };
    local *xCAT::NetworkUtils::getipaddr = sub {
        my @args = @_;
        shift @args if @args && $args[0] eq 'xCAT::NetworkUtils';
        push @getipaddr_calls, [@args];
        return '192.0.2.10';
    };
    local *xCAT::SvrUtils::ensure_nfs_export_option = sub {
        push @ensure_calls, [@_];
        if ($option_missing) {
            $option_missing = 0;
            return 1;
        }
        return 0;
    };
    local *xCAT::SvrUtils::nfs_export_exists = sub {
        $exists_calls++;
        return $persistent;
    };

    my $callback = sub {
        my ($response) = @_;
        push @messages, $response->{data}->[0];
    };

    for ( 1 .. 2 ) {
        my $command_start = scalar @commands;
        my $message_start = scalar @messages;
        invoke_caller( $caller, $directory, $callback );
        push @runs,
          {
            commands => [ @commands[ $command_start .. $#commands ] ],
            messages => [ @messages[ $message_start .. $#messages ] ],
          };
    }

    return {
        command_args    => \@command_args,
        directory       => $directory,
        ensure_calls    => \@ensure_calls,
        exists_calls    => $exists_calls,
        getipaddr_calls => \@getipaddr_calls,
        runs            => \@runs,
    };
}

sub exercise_remote_export {
    my ($caller) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $directory = "$root/export";
    my @command_args;
    my @commands;
    my @getipaddr_calls;
    my @messages;

    no warnings 'redefine';
    local *xCAT::Utils::runcmd = sub {
        my @args = @_;
        shift @args if @args && $args[0] eq 'xCAT::Utils';
        my ($command) = @args;
        push @commands, $command;
        push @command_args, [@args];
        return ("node1: nfs-server:$directory")
          if $command eq 'XCATBYPASS=Y litetree node1';
        return;
    };
    local *xCAT::NetworkUtils::getipaddr = sub {
        my @args = @_;
        shift @args if @args && $args[0] eq 'xCAT::NetworkUtils';
        push @getipaddr_calls, [@args];
        return '192.0.2.10';
    };
    local *xCAT::SvrUtils::ensure_nfs_export_option = sub {
        die 'persistent export options must not be checked for a remote server';
    };
    local *xCAT::SvrUtils::nfs_export_exists = sub {
        die 'persistent exports must not be checked for a remote server';
    };

    my $callback = sub {
        my ($response) = @_;
        push @messages, $response->{data}->[0];
    };
    if ( $caller eq 'setupNFSTree' ) {
        xCAT::SvrUtils->setupNFSTree( 'node1', 'other-server', $callback );
    } else {
        xCAT::SvrUtils->setupStatemnt(
            '192.0.2.11', "nfs-server:$directory", $callback
        );
    }

    return {
        command_args    => \@command_args,
        commands        => \@commands,
        directory       => $directory,
        getipaddr_calls => \@getipaddr_calls,
        messages        => \@messages,
    };
}

sub exercise_multiple_tree_uris {
    my $root = tempdir( CLEANUP => 1 );
    my $local_directory = "$root/local";
    my $remote_directory = "$root/remote";
    my @command_args;
    my @messages;

    no warnings 'redefine';
    local *xCAT::Utils::runcmd = sub {
        my @args = @_;
        shift @args if @args && $args[0] eq 'xCAT::Utils';
        my ($command) = @args;
        push @command_args, [@args];
        if ( $command eq 'XCATBYPASS=Y litetree node1' ) {
            return (
                "node1: other-server:$remote_directory",
                "node1: nfs-server:$local_directory",
            );
        }
        if ( $command eq 'showmount -e nfs-server' ) {
            return ( 'Export list for nfs-server:', "$local_directory *" );
        }
        return;
    };
    local *xCAT::SvrUtils::ensure_nfs_export_option = sub { return 0; };
    local *xCAT::SvrUtils::nfs_export_exists = sub { return 1; };

    my $callback = sub {
        my ($response) = @_;
        push @messages, $response->{data}->[0];
    };
    xCAT::SvrUtils->setupNFSTree( 'node1', 'nfs-server', $callback );

    return {
        command_args     => \@command_args,
        local_directory  => $local_directory,
        messages         => \@messages,
        remote_directory => $remote_directory,
    };
}

sub invoke_caller {
    my ( $caller, $directory, $callback ) = @_;
    if ( $caller eq 'setupNFSTree' ) {
        xCAT::SvrUtils->setupNFSTree( 'node1', 'nfs-server', $callback );
    } else {
        xCAT::SvrUtils->setupStatemnt(
            '192.0.2.10', "nfs-server:$directory", $callback
        );
    }
}

sub command_prefix {
    my ( $caller, $directory ) = @_;
    my @commands;
    push @commands, 'XCATBYPASS=Y litetree node1'
      if $caller eq 'setupNFSTree';
    push @commands, 'showmount -e nfs-server';
    return @commands;
}

sub append_command {
    my ( $caller, $directory ) = @_;
    my $separator = $caller eq 'setupNFSTree'
      ? ' >> /etc/exports'
      : ' >>/etc/exports';
    return qq{echo "$directory *($export_options)"$separator};
}

sub added_message {
    my ( $caller, $directory ) = @_;
    return $caller eq 'setupNFSTree'
      ? "$directory is added to /etc/exports with default option"
      : "$directory is added into /etc/exports with default options";
}

sub expected_command_args {
    my ($runs) = @_;
    my @commands = map { @{ $_->{commands} } } @{$runs};
    return [ map { [ $_, 0 ] } @commands ];
}

sub expected_getipaddr_calls {
    my ($caller) = @_;
    return $caller eq 'setupStatemnt'
      ? [ [ 'nfs-server' ], [ 'nfs-server' ] ]
      : [];
}
