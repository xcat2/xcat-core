#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# Debian, xCAT and the kernel each name the same architecture differently. copycd reads the
# name from the media and genimage gives debootstrap the Debian one, so both directions have
# to agree on every architecture xCAT supports.

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::Utils;

# --- what debootstrap and the package lists are given ----------------------
is(xCAT::Utils->debian_arch('x86_64'), 'amd64',
    'Debian calls x86_64 amd64');
is(xCAT::Utils->debian_arch('ppc64el'), 'ppc64el',
    'the Debian name for POWER LE is unchanged');
is(xCAT::Utils->debian_arch('ppc64le'), 'ppc64le',
    'the POWER LE alias is left alone, because only ppc64el reaches the driver table');
is(xCAT::Utils->debian_arch('s390x'), 's390x',
    'an architecture Debian names the same is passed through');
is(xCAT::Utils->debian_arch('ppc64'), 'ppc64',
    'POWER BE is passed through');
is(xCAT::Utils->debian_arch(undef), undef,
    'no architecture resolves to nothing');

# --- what copycd reads from the media --------------------------------------
is(xCAT::Utils->xcat_arch_from_debian('amd64'), 'x86_64',
    'amd64 media installs x86_64 nodes');
is(xCAT::Utils->xcat_arch_from_debian('i386'), 'x86',
    'i386 media installs x86 nodes');
is(xCAT::Utils->xcat_arch_from_debian('i686'), 'x86',
    'every 32-bit x86 spelling installs x86 nodes');
is(xCAT::Utils->xcat_arch_from_debian('ppc64el'), 'ppc64el',
    'POWER LE media keeps the Debian name xCAT uses for Ubuntu');
is(xCAT::Utils->xcat_arch_from_debian('powerpc'), 'ppc64',
    'POWER BE media installs ppc64 nodes');
is(xCAT::Utils->xcat_arch_from_debian('nonesuch'), undef,
    'media xCAT has no name for resolves to nothing');
is(xCAT::Utils->xcat_arch_from_debian(''), undef,
    'media with no architecture resolves to nothing');

# --- the two directions agree ----------------------------------------------
foreach my $arch (qw(x86_64 ppc64el)) {
    is(xCAT::Utils->xcat_arch_from_debian(xCAT::Utils->debian_arch($arch)), $arch,
        "$arch survives a round trip through both directions");
}

done_testing();
