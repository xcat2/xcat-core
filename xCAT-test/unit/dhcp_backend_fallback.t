#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::Backend;

# Regression for issue #7710: on Ubuntu the `xcat` metapackage's
# `isc-dhcp-server | kea` Depends guarantees isc-dhcp-server, but the DHCP
# backend auto-selection prefers kea on 22.04+. A --no-install-recommends
# install then has only isc, and `makedhcp` (which calls new_backend with
# check_available => 1) used to fail hard: "The selected DHCP backend 'kea' is
# not available on this system." An AUTO selection must instead fall back to the
# backend that IS installed; only an admin-forced backend that is missing stays
# a hard error.

# ubuntu 24.04 auto-selects kea; with only isc installed it must fall back to isc.
{
    my $sel = xCAT::DHCP::Backend->choose(
        requested       => 'auto',
        platform        => '',
        os              => '',
        os_name         => 'ubuntu',
        version         => '24.04',
        check_available => 1,
        available       => { kea => 0, isc => 1 },
    );
    ok( !$sel->{error}, 'ubuntu 24.04 auto with only isc installed does not error' );
    is( $sel->{name}, 'isc', '... falls back to the installed isc backend' );
    is( $sel->{fallback_from}, 'kea', '... records that kea was the preferred backend' );
    is( $sel->{requested}, 'auto', '... the request is still auto' );
}

# ubuntu 20.04 auto-selects isc; with only kea installed it must fall back to kea.
{
    my $sel = xCAT::DHCP::Backend->choose(
        requested       => 'auto',
        platform        => '',
        os              => '',
        os_name         => 'ubuntu',
        version         => '20.04',
        check_available => 1,
        available       => { kea => 1, isc => 0 },
    );
    ok( !$sel->{error}, 'ubuntu 20.04 auto with only kea installed does not error' );
    is( $sel->{name}, 'kea', '... falls back to the installed kea backend' );
    is( $sel->{fallback_from}, 'isc', '... records that isc was the preferred backend' );
}

# When the preferred backend IS installed, no fallback happens.
{
    my $sel = xCAT::DHCP::Backend->choose(
        requested       => 'auto',
        platform        => '',
        os              => '',
        os_name         => 'ubuntu',
        version         => '24.04',
        check_available => 1,
        available       => { kea => 1, isc => 1 },
    );
    ok( !$sel->{error}, 'ubuntu 24.04 auto with kea installed does not error' );
    is( $sel->{name}, 'kea', '... uses the preferred kea backend' );
    ok( !defined $sel->{fallback_from}, '... no fallback recorded when preferred is available' );
}

# A backend the admin explicitly forced that is not installed stays a HARD error
# (per the Kea backend plan) -- no silent fallback.
{
    my $sel = xCAT::DHCP::Backend->choose(
        requested       => 'kea',
        platform        => '',
        os              => '',
        os_name         => 'ubuntu',
        version         => '20.04',
        check_available => 1,
        available       => { kea => 0, isc => 1 },
    );
    ok( $sel->{error}, 'a forced-but-missing kea backend is a hard error' );
    like( $sel->{error}, qr/not available/, '... with a clear message' );
    ok( !defined $sel->{fallback_from}, '... and no fallback for a forced backend' );
}

# If NEITHER backend is installed, auto still errors clearly.
{
    my $sel = xCAT::DHCP::Backend->choose(
        requested       => 'auto',
        platform        => '',
        os              => '',
        os_name         => 'ubuntu',
        version         => '24.04',
        check_available => 1,
        available       => { kea => 0, isc => 0 },
    );
    ok( $sel->{error}, 'auto with no DHCP backend installed errors' );
    like( $sel->{error}, qr/not available/, '... with a clear message' );
}

# The backend object exposes fallback_from so callers (dhcp.pm) can warn.
{
    my $backend = xCAT::DHCP::Backend->new_backend(
        requested       => 'auto',
        platform        => '',
        os              => '',
        os_name         => 'ubuntu',
        version         => '24.04',
        check_available => 1,
        available       => { kea => 0, isc => 1 },
    );
    isa_ok( $backend, 'xCAT::DHCP::Backend::ISC', 'new_backend returns the fallback object' );
    is( $backend->name, 'isc', '... named isc' );
    is( $backend->fallback_from, 'kea', '... fallback_from accessor returns kea' );
}

done_testing();
