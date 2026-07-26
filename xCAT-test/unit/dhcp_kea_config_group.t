#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw/tempfile/;
use Test::More;

our ( %TEST_USERS, %TEST_GROUPS, %TEST_GROUP_NAMES );
our ( @USER_LOOKUPS, @GROUP_LOOKUPS, @GROUP_ID_LOOKUPS );

BEGIN {
    no warnings 'redefine';

    *CORE::GLOBAL::getpwnam = sub {
        my ($name) = @_;
        push @USER_LOOKUPS, $name;
        my $entry = $TEST_USERS{$name};
        return unless $entry;
        return @$entry if wantarray;
        return $entry->[0];
    };

    *CORE::GLOBAL::getgrnam = sub {
        my ($name) = @_;
        push @GROUP_LOOKUPS, $name;
        my $entry = $TEST_GROUPS{$name};
        return unless $entry;
        return @$entry if wantarray;
        return $entry->[0];
    };

    *CORE::GLOBAL::getgrgid = sub {
        my ($gid) = @_;
        push @GROUP_ID_LOOKUPS, $gid;
        my $name = $TEST_GROUP_NAMES{$gid};
        return unless defined $name;
        return ( $name, 'x', $gid, '' ) if wantarray;
        return $name;
    };
}

use xCAT::DHCP::Backend::Kea;

my $backend = xCAT::DHCP::Backend::Kea->new();

set_nss(
    users => {
        _kea => [ '_kea', 'x', 100, 300, '', '', '', '/var/empty', '/sbin/nologin' ],
    },
    groups => {
        kea  => [ 'kea',  'x', 200, '' ],
        _kea => [ '_kea', 'x', 400, '' ],
    },
    group_names => { 300 => 'daemon-primary' },
);

my $service_account = selected_service_account($backend);
is_deeply(
    $service_account,
    { name => '_kea', uid => 100, gid => 300 },
    'service account selection preserves the fallback daemon identity'
);

reset_lookups();
my ( $group, $gid ) = selected_config_group($backend);
is( $group, 'kea', 'the preferred named Kea group owns configuration files' );
is( $gid, 200, 'configuration ownership is independent of the daemon primary GID' );
isnt( $gid, $service_account->{gid}, 'configuration ownership does not inherit the daemon primary GID' );
is_deeply( \@GROUP_LOOKUPS, ['kea'], 'named configuration groups are checked in preference order' );
is_deeply( \@USER_LOOKUPS, [], 'configuration-group selection does not inspect service users' );
is_deeply( \@GROUP_ID_LOOKUPS, [], 'configuration-group selection does not resolve a primary GID' );

set_nss(
    groups => {
        _kea => [ '_kea', 'x', 400, '' ],
    },
);
( $group, $gid ) = selected_config_group($backend);
is( $group, '_kea', 'the fallback named Kea group is selected when needed' );
is( $gid, 400, 'the fallback named Kea group supplies configuration ownership' );
is_deeply( \@GROUP_LOOKUPS, [ 'kea', '_kea' ], 'both named groups are checked before falling back' );
is_deeply( \@USER_LOOKUPS, [], 'named-group fallback remains independent of service users' );
is_deeply( \@GROUP_ID_LOOKUPS, [], 'named-group fallback remains independent of primary GIDs' );

set_nss(
    users => {
        kea => [ 'kea', 'x', 101, 300, '', '', '', '/var/empty', '/sbin/nologin' ],
    },
    group_names => { 300 => 'daemon-primary' },
);
( $group, $gid ) = selected_config_group($backend);
ok( !defined($group), 'no configuration group is selected when named Kea groups are absent' );
ok( !defined($gid), 'no configuration GID is inherited from the service account' );
is_deeply( \@GROUP_LOOKUPS, [ 'kea', '_kea' ], 'all named groups are checked before the public-mode fallback' );
is_deeply( \@USER_LOOKUPS, [], 'the public-mode fallback does not inspect service users' );
is_deeply( \@GROUP_ID_LOOKUPS, [], 'the public-mode fallback does not resolve a primary GID' );

SKIP: {
    skip 'root privileges are required to verify file ownership and modes', 5 if $> != 0;

    set_nss(
        users => {
            _kea => [ '_kea', 'x', 100, 300, '', '', '', '/var/empty', '/sbin/nologin' ],
        },
        groups => {
            kea => [ 'kea', 'x', 200, '' ],
        },
        group_names => { 300 => 'daemon-primary' },
    );
    my ( $named_fh, $named_path ) = tempfile(UNLINK => 1);
    close($named_fh) or die "Unable to close $named_path: $!";
    my $named_result = apply_config_permissions( $backend, $named_path );
    ok( !$named_result->{error}, 'configuration permissions are applied with a named Kea group' )
      or diag $named_result->{error};
    is( ( stat $named_path )[5], 200, 'configuration file uses the named Kea group GID' );
    is( ( stat $named_path )[2] & 07777, 0640, 'configuration file is group-readable with a named Kea group' );

    set_nss(
        users => {
            kea => [ 'kea', 'x', 101, 300, '', '', '', '/var/empty', '/sbin/nologin' ],
        },
        group_names => { 300 => 'daemon-primary' },
    );
    my ( $public_fh, $public_path ) = tempfile(UNLINK => 1);
    close($public_fh) or die "Unable to close $public_path: $!";
    my $public_result = apply_config_permissions( $backend, $public_path );
    ok( !$public_result->{error}, 'configuration permissions fall back without a named Kea group' )
      or diag $public_result->{error};
    is( ( stat $public_path )[2] & 07777, 0644, 'missing named Kea groups preserve the public-read fallback' );
}

done_testing();

sub set_nss {
    my (%args) = @_;

    %TEST_USERS      = %{ $args{users}      || {} };
    %TEST_GROUPS     = %{ $args{groups}     || {} };
    %TEST_GROUP_NAMES = %{ $args{group_names} || {} };
    reset_lookups();

    return;
}

sub reset_lookups {
    @USER_LOOKUPS     = ();
    @GROUP_LOOKUPS    = ();
    @GROUP_ID_LOOKUPS = ();

    return;
}

sub selected_service_account {
    my ($kea_backend) = @_;

    if ( my $resolver = $kea_backend->can('service_account') ) {
        return $resolver->($kea_backend);
    }

    my $legacy_resolver = xCAT::DHCP::Backend::Kea->can('_kea_user');
    my $name = $legacy_resolver ? $legacy_resolver->() : undef;
    return unless defined $name;
    my @entry = getpwnam($name);
    return {
        name => $entry[0],
        uid  => $entry[2],
        gid  => $entry[3],
    };
}

sub selected_config_group {
    my ($kea_backend) = @_;

    if ( my $resolver = xCAT::DHCP::Backend::Kea->can('_kea_group') ) {
        return $resolver->();
    }

    my $resolver = $kea_backend->can('_service_group');
    return $resolver ? $resolver->($kea_backend) : undef;
}

sub apply_config_permissions {
    my ( $kea_backend, $path ) = @_;

    my $permissions = xCAT::DHCP::Backend::Kea->can('_set_config_permissions');
    return { error => 'Kea configuration-permission helper is unavailable' } unless $permissions;
    return $permissions->($path) if xCAT::DHCP::Backend::Kea->can('_kea_group');
    return $permissions->( $kea_backend, $path );
}
