#!/usr/bin/env perl
# xCAT must declare the two Perl modules that carry every IPv6 socket path.
#
# xCAT::SLP, xCAT::IPMI, xCAT::Client, xCAT::NetworkUtils and the dhcp, nodestat and
# credentials plugins reach IPv6 only through Socket6 and IO::Socket::INET6, and each one
# loads them with eval { require ... }. A missing module is therefore not an error: the
# guard variable stays false and the IPv6 branch is never taken. SLP discovery and IPMI
# over IPv6 are silently off.
#
# Nothing derives the dependency anywhere. perl-generators reads use statements, not a
# require inside an eval, so the EL build generates no perl(Socket6) either. On a Leap 15.6
# management node both modules are absent and $ip6support evaluates to 0.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use File::Slurper qw(read_text);
use XCAT::Test::File qw(repo_path);

my @MODULES = ('Socket6', 'IO::Socket::INET6');

# Every RPM family needs the declaration, so this is not an openSUSE-only table. EL carries
# both in appstream and openSUSE in the main repository.
my @SPECS = ('perl-xCAT/perl-xCAT.spec', 'xCAT-server/xCAT-server.spec');

my @DISTROS = (
    [ 'openSUSE',  'suse_version 1500' ],
    [ 'EL',        'rhel 10' ],
    [ 'openEuler', 'openEuler 1' ],
);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

# requires <spec> <define> -- the Requires of one spec for one distro
sub requires
{
    my ($spec, $define) = @_;
    open(my $fh, '-|', $rpmspec, '-q', '--requires', '--target', 'x86_64',
        '--define', 'version 2.20.0', '--define', 'release 1', '--define', 'gitinfo none',
        '--undefine', 'rhel', '--undefine', 'suse_version', '--undefine', 'openEuler',
        '--define', $define, repo_path($spec)) or die "run rpmspec: $!";
    my @requires = <$fh>;
    close($fh) or die "rpmspec failed for $spec with $define";
    chomp @requires;
    return @requires;
}

# field <text> <name> -- one deb control field, with its continuation lines
sub field
{
    my ($text, $name) = @_;
    return '' unless $text =~ /^\Q$name\E:[ \t]*(.*(?:\n[ \t]+.*)*)/m;
    my $value = $1;
    $value =~ s/\s+/ /g;
    return $value;
}

foreach my $spec (@SPECS) {
    foreach my $distro (@DISTROS) {
        my ($name, $define) = @$distro;
        my @requires = requires($spec, $define);
        foreach my $module (@MODULES) {
            is(scalar(grep { $_ eq "perl($module)" } @requires), 1,
                "$spec requires perl($module) on $name");
        }
    }
}

# The deb packages name the modules directly. A Recommends is not enough: apt 3.0 solver3
# drops a Recommends it cannot place, which is how Ubuntu 26.04 lost bind9.
foreach my $package ('perl-xCAT', 'xCAT-server') {
    my $text     = read_text(repo_path("$package/debian/control"));
    my $depends  = field($text, 'Depends');
    my $suggests = field($text, 'Recommends');
    foreach my $deb ('libsocket6-perl', 'libio-socket-inet6-perl') {
        like($depends, qr/\b\Q$deb\E\b/, "$package/debian/control depends on $deb");
        unlike($suggests, qr/\b\Q$deb\E\b/,
            "$package/debian/control does not leave $deb a Recommends");
    }
}

done_testing();
