#!/usr/bin/env perl
# Socket6 and IO::Socket::INET6 are loaded with an eval at every call site, and
# the caller keeps working on IPv4 when the load fails. A hard dependency in
# either packaging manifest would state a dependency the code does not have,
# and would stop xCAT installing where the modules are missing.
#
# openSUSE is the exception, and it is asserted in
# xCAT-test/unit/ipv6_socket_modules_declared.t: the Minimal-VM image sets
# solver.onlyRequires = true, so zypper installs no recommended package and the
# modules have to be required there. This file reads the EL and Debian spelling
# of the dependency, which carries no openSUSE branch.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(slurp_repo_file);

my $control = slurp_repo_file('xCAT-server/debian/control');
my ($server) = $control =~ /^Package: xcat-server\n(.*?)(?:\n\n|\z)/ms;
$server //= '';

foreach my $package (qw(libsocket6-perl libio-socket-inet6-perl)) {
    like( $server, qr/^Recommends:.*\b\Q$package\E\b/m,
        "the Debian server package recommends $package" );
    unlike( $server, qr/^Depends:.*\b\Q$package\E\b/m,
        "the Debian server package does not require $package" );
}

my $spec = slurp_repo_file('xCAT-server/xCAT-server.spec');
foreach my $package (qw(perl-Socket6 perl-IO-Socket-INET6)) {
    like( $spec, qr/^Recommends:.*\b\Q$package\E\b/m,
        "the RPM server package recommends $package" );
    unlike( $spec, qr/^Requires:.*\b\Q$package\E\b/m,
        "the RPM server package does not require $package" );
}

done_testing();
