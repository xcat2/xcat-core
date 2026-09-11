#!/usr/bin/env perl
# Drive the DHCP client selection out of doxcat.
#
# doxcat cannot be sourced: it restarts rsyslogd, reads /proc/cmdline and ends in a loop that
# waits for an address. Extract the two routines and run them with the clients shadowed by
# stubs that record their own argv.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $DOXCAT = 'xCAT-genesis-scripts/usr/bin/doxcat';
my $ISC4   = 'dhclient -cf /etc/dhclient.conf -pf /var/run/dhclient.eth0.pid eth0';
my $ISC6   = 'dhclient -6 -pf /var/run/dhclient6.eth0.pid eth0 -lf /var/lib/dhclient/dhclient6.leases';

my $source = read_text( repo_path($DOXCAT) );
my $tmpdir = tempdir( CLEANUP => 1 );

# The failure this captures: doxcat named dhclient at six call sites, so on a release that
# packages no ISC client Genesis reported "dhclient: command not found" and no node ever got
# an address.
ok( $source !~ qr/^\s*dhclient\s/m,
    'doxcat starts no command line with dhclient' );
ok( $source !~ qr/;\s*dhclient\s/,
    'doxcat chains no command line into dhclient' );

# The build root has to carry a client, or the image installs none. EL8 and EL9 package the
# ISC client; AlmaLinux 10 baseos packages dhcpcd.
my $spec = read_text( repo_path('xCAT-genesis-builder/xCAT-genesis-base.spec') );
like( $spec, qr/^%if 0%\{\?rhel\} >= 10\nBuildRequires: dhcpcd$/m,
    'the spec build-requires dhcpcd on the releases that drop the ISC client' );

# The payload check has to name the client the release ships, or the build passes with no
# client in the image again.
like( $spec, qr{^%if 0%\{\?rhel\} >= 10\nGENESIS_REQUIRED="usr/sbin/dhcpcd"$}m,
    'the payload check requires dhcpcd on the releases that drop the ISC client' );

# dracut_install reports a missing binary and returns, so naming dhclient alone shipped an
# image with no client at all.
my $module = read_text( repo_path('xCAT-genesis-builder/dracut_105/el/module-setup.sh') );
ok( $module !~ qr/^\s*dracut_install dhclient lldpad$/m,
    'the dracut module no longer installs dhclient unconditionally' );
like( $module, qr/^\s*dracut_install dhcpcd$/m,
    'the dracut module installs dhcpcd when the build root carries it' );
like( $module, qr{^\s*dracut_install /usr/libexec/dhcpcd-run-hooks$}m,
    'the dracut module installs the hooks dhcpcd runs on every lease' );

my $selector = extract_function( $source, 'genesis_dhcp_command' );
my $runner   = extract_function( $source, 'genesis_start_dhcp' );

if ( !defined $selector || !defined $runner ) {
    fail('doxcat carries genesis_dhcp_command() to choose the client');
    fail('doxcat carries genesis_start_dhcp() to run the chosen client');
    done_testing();
    exit 0;
}

# EL8 and EL9 package the ISC client, and it stays the one Genesis uses there.
is( selected( 4, ['dhclient'] ), $ISC4, 'the ISC client keeps its IPv4 command line' );
is( selected( 6, ['dhclient'] ), $ISC6, 'the ISC client keeps its IPv6 command line' );
is( selected( 4, [ 'dhclient', 'dhcpcd' ] ), $ISC4,
    'the ISC client is preferred when the image carries both' );

# RHEL 10 packages no ISC client. AlmaLinux 10 baseos packages dhcpcd, which carries its own
# resolv.conf, hostname and ntp hooks, so it needs no dhclient-script.
is( selected( 4, ['dhcpcd'] ), 'dhcpcd -4 -b -p -t 0 eth0',
    'dhcpcd stands in for dhclient on IPv4' );
is( selected( 6, ['dhcpcd'] ), 'dhcpcd -6 -b -p -t 0 eth0',
    'dhcpcd stands in for dhclient on IPv6' );

# dhcpcd on a single interface exits when its timeout expires, and the default is 30 seconds.
# doxcat waits for the lease for as long as it takes, so the client must not give up first.
like( selected( 4, ['dhcpcd'] ), qr/(?:^|\s)-t 0(?:\s|$)/,
    'dhcpcd is asked to wait for a lease instead of timing out' );

# dhcpcd de-configures the interface when it exits unless it is persistent. Genesis keeps the
# address it was given.
like( selected( 4, ['dhcpcd'] ), qr/(?:^|\s)-p(?:\s|$)/,
    'dhcpcd is asked to leave the address in place' );

# An image with no client at all has to say so rather than run an empty command line.
is( selected( 4, [] ), '', 'nothing is chosen when the image carries no client' );

# The runner is what the call sites use, so it has to actually execute the chosen client.
is( started( 4, ['dhcpcd'] ), 'dhcpcd -4 -b -p -t 0 eth0',
    'genesis_start_dhcp runs dhcpcd when it is the only client' );
is( started( 4, ['dhclient'] ), $ISC4,
    'genesis_start_dhcp runs the ISC client when it is there' );
is( started( 4, [] ), '',
    'genesis_start_dhcp runs no client when the image carries none' );
isnt( start_status( 4, [] ), 0,
    'genesis_start_dhcp reports failure when the image carries no client' );

done_testing();

#---
# extract_function: lift one shell function out of a script that cannot be sourced.
# Returns undef when the function is absent, so the caller fails the assertion instead of
# bailing out of a suite that has already found the defect.
#---
sub extract_function {
    my ( $text, $name ) = @_;
    my ($body) = $text =~ /^($name\(\)\s*\{.*?^\})$/ms;
    return $body;
}

#---
# probe: run the extracted routines with only the named clients on PATH.
# Returns the standard output, the recorded argv of whatever ran, and the exit status.
#---
sub probe {
    my ( $call, $clients ) = @_;
    my $dir = tempdir( DIR => $tmpdir, CLEANUP => 1 );
    my $bin = "$dir/bin";
    make_path($bin);

    # PATH holds the stubs alone, so each one names itself rather than calling basename.
    my $record = "$dir/record";
    foreach my $client ( @{$clients} ) {
        write_text( "$bin/$client",
            qq{#!/bin/sh\necho "$client \$*" >> "$record"\nexit 0\n} );
        chmod 0755, "$bin/$client";
    }

    # logger writes to the console in the image and is not what these assertions measure.
    write_text( "$bin/logger", "#!/bin/sh\nexit 0\n" );
    chmod 0755, "$bin/logger";

    write_text( "$dir/probe.sh", "log_label=test\n$selector\n$runner\n$call\n" );
    my $out = `PATH="$bin" /bin/bash "$dir/probe.sh" 2>/dev/null`;
    my $status = $? >> 8;
    chomp $out;

    my $ran = -e $record ? read_text($record) : '';
    chomp $ran;

    return ( $out, $ran, $status );
}

sub selected {
    my ( $family, $clients ) = @_;
    my ( $out, undef, undef ) = probe( qq{genesis_dhcp_command $family eth0}, $clients );
    return $out;
}

sub started {
    my ( $family, $clients ) = @_;
    my ( undef, $ran, undef ) = probe( qq{genesis_start_dhcp $family eth0}, $clients );
    return $ran;
}

sub start_status {
    my ( $family, $clients ) = @_;
    my ( undef, undef, $status ) = probe( qq{genesis_start_dhcp $family eth0}, $clients );
    return $status;
}
