#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: the NTP backend selector was well covered and nothing connected it to makentp.
#
# ntp_backend_selection.t exercises xCAT::NTP::Backend thoroughly, but copying the BASE
# makentp.pm over the head one left the whole unit suite byte-identical -- so the call site
# that consumes the selector, the --backend pass-through and the abort branches ran in no test
# at all. A helper can be perfectly covered while nothing calls it.
#
# process_request needs a management node, so the decisions it makes about the selector's
# answer live in two small routines that take their inputs and return an answer, and those are
# what this drives. The side effects (send_msg, runcmd, updatenode) stay in the caller.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $plugin = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'makentp.pm'
);
plan skip_all => "makentp.pm not found" unless -f $plugin;

my $src = do { local $/; open my $fh, '<', $plugin or die $!; <$fh> };

# BAIL_OUT rather than skip, so a rename fails loudly instead of silently covering nothing.
my @wanted = qw(ntp_backend_action setupntp_command);
my $body = '';
for my $name (@wanted) {
    my ($sub) = $src =~ /\n(sub \Q$name\E \{.*?\n\})\n/s;
    BAIL_OUT("could not extract $name from makentp.pm") unless defined $sub;
    $body .= "$sub\n";
}

{
    package T;
    eval "$body; 1" or main::BAIL_OUT("could not eval the makentp helpers: $@");
}

# --- the selector said no backend is usable at all -------------------------
{
    my $r = T::ntp_backend_action( { error => 'site.ntpbackend is nonsense' }, 'mn1' );
    is( $r->{action}, 'abort', 'a selector error aborts makentp' );
    is( $r->{error}, 'site.ntpbackend is nonsense',
        'and the selector error is what the caller reports' );
}

# --- neither daemon installed ----------------------------------------------
{
    my $r = T::ntp_backend_action( { name => 'chrony', install => 1 }, 'mn1' );
    is( $r->{action}, 'abort', 'nothing installed aborts rather than configuring' );
    like( $r->{error}, qr/Neither chrony nor ntp is installed on mn1/,
        'the abort names the node' );
    like( $r->{error}, qr/set site\.ntpbackend/,
        'and tells the admin how to override the choice' );
}

# --- the requested backend is absent, so the selector downgraded ------------
{
    my $r = T::ntp_backend_action(
        { name => 'chrony', downgraded => 'ntpd' }, 'mn1' );
    is( $r->{action}, 'configure', 'a downgrade still configures' );
    is( $r->{name}, 'chrony', 'using the daemon that is actually installed' );
    like( join( '|', @{ $r->{notes} } ),
        qr/ntpd is not installed; using chrony instead/,
        'and says so, rather than silently using something else' );
}

# --- the ordinary case ------------------------------------------------------
{
    my $r = T::ntp_backend_action( { name => 'chrony' }, 'mn1' );
    is( $r->{action}, 'configure', 'an installed backend configures' );
    is( $r->{name}, 'chrony', 'with the name the selector chose' );
    is_deeply( $r->{notes}, [], 'and says nothing extra' );
}

{
    my $r = T::ntp_backend_action( { name => 'ntpd' }, 'mn1' );
    is( $r->{name}, 'ntpd', 'ntpd is carried through as chosen' );
}

# --- the --backend pass-through, which is what setupntp reads ---------------
{
    is( T::setupntp_command( 'chrony', '10.0.0.1,10.0.0.2' ),
        '/install/postscripts/setupntp --backend chrony 10.0.0.1 10.0.0.2',
        'the chosen backend reaches setupntp and the server list is space separated' );

    is( T::setupntp_command( 'ntpd', '10.0.0.1' ),
        '/install/postscripts/setupntp --backend ntpd 10.0.0.1',
        'a different backend produces a different command' );

    unlike( T::setupntp_command( 'chrony', '10.0.0.1' ), qr/,/,
        'no comma survives into the argument list' );
}

done_testing();
