#!/usr/bin/env perl
# Every IPv6 socket path in xCAT goes through Socket6 and IO::Socket::INET6.
#
# xCAT::SLP, xCAT::IPMI, xCAT::Client, xCAT::NetworkUtils and the dhcp, nodestat and
# credentials plugins load both with eval { require ... }, so a missing module is not an
# error: the guard variable stays false and the IPv6 branch is never taken. SLP discovery
# and IPMI over IPv6 then do nothing and report nothing.
#
# A recommendation is the right strength where the package manager installs one, which is
# what dnf does. It is not enough on openSUSE: the Minimal-VM image sets
# solver.onlyRequires = true in /etc/zypp/zypp.conf, so zypper installs no recommended
# package at all. Measured on a Leap 15.6 management node carrying every other xCAT
# dependency, both modules were absent and the SLP guard evaluated to 0. xCAT already names
# a DHCP server directly for this same reason.
#
# So openSUSE requires both, and the families whose package manager honours a weak
# dependency recommend them.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use File::Slurper qw(read_text);
use XCAT::Test::File qw(repo_path);

my @SPECS = ('perl-xCAT/perl-xCAT.spec', 'xCAT-server/xCAT-server.spec');

# The two specs spell the dependency differently: one names the capability and the other
# the openSUSE and EL package name. Either one resolves.
my %SPELLINGS = (
    'Socket6'           => [ 'perl(Socket6)',           'perl-Socket6' ],
    'IO::Socket::INET6' => [ 'perl(IO::Socket::INET6)', 'perl-IO-Socket-INET6' ],
);

# The families whose package manager installs a recommendation by default.
my @WEAK = ( [ 'EL', 'rhel 10' ], [ 'openEuler', 'openEuler 1' ] );

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

# dependencies <spec> <kind> <define> -- one dependency kind of one spec for one distro
sub dependencies
{
    my ($spec, $kind, $define) = @_;
    open(my $fh, '-|', $rpmspec, '-q', "--$kind", '--target', 'x86_64',
        '--define', 'version 2.20.0', '--define', 'release 1', '--define', 'gitinfo none',
        '--undefine', 'rhel', '--undefine', 'suse_version', '--undefine', 'openEuler',
        '--define', $define, repo_path($spec)) or die "run rpmspec: $!";
    my @found = <$fh>;
    close($fh) or die "rpmspec failed for $spec with $define";
    chomp @found;
    return @found;
}

# declares <list> <module> -- whether the list names the module in either spelling
sub declares
{
    my ($list, $module) = @_;
    foreach my $spelling (@{ $SPELLINGS{$module} }) {
        return 1 if grep { $_ eq $spelling } @$list;
    }
    return 0;
}

foreach my $spec (@SPECS) {
    my @suse_requires   = dependencies($spec, 'requires',   'suse_version 1500');
    my @suse_recommends = dependencies($spec, 'recommends', 'suse_version 1500');

    foreach my $module (sort keys %SPELLINGS) {
        ok(declares(\@suse_requires, $module),
            "$spec requires $module on openSUSE, where a recommendation is not installed");
        ok(!declares(\@suse_recommends, $module),
            "$spec does not leave $module a recommendation on openSUSE");
    }

    foreach my $family (@WEAK) {
        my ($name, $define) = @$family;
        my @requires   = dependencies($spec, 'requires',   $define);
        my @recommends = dependencies($spec, 'recommends', $define);

        foreach my $module (sort keys %SPELLINGS) {
            ok(declares(\@recommends, $module), "$spec recommends $module on $name");
            ok(!declares(\@requires, $module),
                "$spec does not require $module on $name, where the code works without it");
        }
    }
}

# apt installs a recommendation by default, so the deb packages need no hard dependency.
# perl-xCAT has carried one since before this rule and keeps it; nothing is gained by
# weakening a dependency that already resolves everywhere apt runs.
my %DEB_FIELD = ('perl-xCAT' => 'Depends', 'xCAT-server' => 'Recommends');

foreach my $package (sort keys %DEB_FIELD) {
    my $field = $DEB_FIELD{$package};
    my $text  = read_text(repo_path("$package/debian/control"));
    foreach my $deb ('libsocket6-perl', 'libio-socket-inet6-perl') {
        like($text, qr/^\Q$field\E:.*\b\Q$deb\E\b/m,
            "$package/debian/control names $deb in $field");
    }
}

done_testing();
