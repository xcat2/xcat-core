#!/usr/bin/env perl
# The xCAT packages must declare their Perl module dependencies for openSUSE.
#
# The specs carry almost no Requires for Perl modules and rely on the automatic dependency
# generator. EL has perl-generators and derives 88 perl() requires from the module sources.
# openSUSE has no perl-generators, so the built rpms declare only what the specs name, and
# the modules below are never installed. xCAT::Table dies with "Can't locate JSON.pm in @INC",
# and xcatd dies with "Can't locate Date/Parse.pm in @INC" from xCAT::xcatd.
#
# The expected sets come from a comparison: every perl() capability the EL build generates,
# tested for availability on a Leap 15.6 management node with every other xCAT dependency
# installed. Only these are both required and absent.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

my %NEEDED = (
    'perl-xCAT/perl-xCAT.spec' =>
      ['perl(JSON)', 'perl(Expect)', 'perl(SNMP)', 'perl(HTML::Form)'],
    'xCAT-server/xCAT-server.spec' => ['perl(Date::Parse)'],
);

# requires <spec> <define> -- the Requires of one spec for one distro
sub requires {
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

foreach my $spec (sort keys %NEEDED) {
    my @suse = requires($spec, 'suse_version 1500');
    my @el   = requires($spec, 'rhel 10');

    foreach my $cap (@{ $NEEDED{$spec} }) {
        is(scalar(grep { $_ eq $cap } @suse), 1, "$spec requires $cap on openSUSE");
        # EL keeps relying on perl-generators, which derives these from the module sources.
        is(scalar(grep { $_ eq $cap } @el), 0,
            "$spec does not declare $cap on EL, where perl-generators derives it");
    }
}

done_testing();
