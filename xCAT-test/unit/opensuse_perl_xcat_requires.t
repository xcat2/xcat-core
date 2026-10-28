#!/usr/bin/env perl
# perl-xCAT must declare its Perl module dependencies for openSUSE.
#
# perl-xCAT.spec carries no Requires at all and relies on the automatic Perl dependency
# generator. EL has perl-generators and produces 99 perl() requires from the module sources.
# openSUSE has no perl-generators, so the built rpm requires nothing but /bin/sh, and four
# modules xCAT loads are absent from the management node: JSON, Expect, SNMP and HTML::Form.
# xcatconfig then dies with "Can't locate JSON.pm in @INC" from xCAT::Table, and xcatd never
# starts.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

my $SPEC = 'perl-xCAT/perl-xCAT.spec';

# The modules xCAT loads that an openSUSE management node does not already carry. Measured by
# loading each one on a Leap 15.6 node with every other xCAT dependency installed.
my @NEEDED = ('perl(JSON)', 'perl(Expect)', 'perl(SNMP)', 'perl(HTML::Form)');

# requires <define> -- the Requires of perl-xCAT for one distro
sub requires {
    my ($define) = @_;
    open(my $fh, '-|', $rpmspec, '-q', '--requires', '--target', 'noarch',
        '--define', 'version 2.20.0', '--define', 'release 1', '--define', 'gitinfo none',
        '--undefine', 'rhel', '--undefine', 'suse_version', '--undefine', 'openEuler',
        '--define', $define, repo_path($SPEC)) or die "run rpmspec: $!";
    my @requires = <$fh>;
    close($fh) or die "rpmspec failed for $define";
    chomp @requires;
    return @requires;
}

my @suse = requires('suse_version 1500');
foreach my $cap (@NEEDED) {
    is(scalar(grep { $_ eq $cap } @suse), 1, "perl-xCAT requires $cap on openSUSE");
}

# EL keeps relying on perl-generators, which derives these from the module sources.
my @el = requires('rhel 10');
foreach my $cap (@NEEDED) {
    is(scalar(grep { $_ eq $cap } @el), 0,
        "perl-xCAT does not declare $cap on EL, where perl-generators derives it");
}

done_testing();
