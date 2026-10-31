#!/usr/bin/env perl
# xCAT-server must ask for DB_File by a name that resolves on openSUSE.
#
# openSUSE ships DB_File in perl-core-DB_File. The spec asked for perl-DB_File on every
# platform below EL10, so zypper answered "nothing provides 'perl-DB_File' needed by the to
# be installed xCAT-server" and the management node could not install xCAT at all.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $rpmspec = qx(command -v rpmspec 2>/dev/null);
chomp($rpmspec);
plan skip_all => 'rpmspec is required' unless $rpmspec && -x $rpmspec;

my $SPEC = 'xCAT-server/xCAT-server.spec';

# requires <define> -- the Requires of xCAT-server for one distro
sub requires {
    my ($define) = @_;
    open(my $fh, '-|', $rpmspec, '-q', '--requires', '--target', 'x86_64',
        '--define', 'version 2.20.0', '--define', 'release 1',
        '--undefine', 'rhel', '--undefine', 'suse_version', '--undefine', 'openEuler',
        '--define', $define, repo_path($SPEC)) or die "run rpmspec: $!";
    my @requires = <$fh>;
    close($fh) or die "rpmspec failed for $define";
    chomp @requires;
    return @requires;
}

my @suse = requires('suse_version 1500');
# The capability, not the package name: openSUSE calls the package perl-core-DB_File.
is(scalar(grep { $_ eq 'perl(DB_File)' } @suse), 1,
    'xCAT-server requires the perl(DB_File) capability on openSUSE');
is(scalar(grep { $_ eq 'perl-DB_File' } @suse), 0,
    'xCAT-server does not ask openSUSE for the EL package name perl-DB_File');

# EL9 keeps the hard requirement under the name EPEL publishes.
my @el9 = requires('rhel 9');
is(scalar(grep { $_ eq 'perl-DB_File' } @el9), 1,
    'xCAT-server keeps perl-DB_File on EL9');

# EL10 asks weakly, because riscv64 has no EPEL to provide it.
my @el10 = requires('rhel 10');
is(scalar(grep { /DB_File/ } @el10), 0,
    'xCAT-server has no hard DB_File requirement on EL10');

done_testing();
