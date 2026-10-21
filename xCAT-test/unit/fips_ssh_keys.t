#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::Utils;

my $tmpdir = tempdir(CLEANUP => 1);
my $fips_status = File::Spec->catfile($tmpdir, 'fips_enabled');

write_text($fips_status, "1\n");
ok(xCAT::Utils->isFIPS($fips_status), 'kernel status 1 enables FIPS mode');

write_text($fips_status, "0\n");
ok(!xCAT::Utils->isFIPS($fips_status), 'kernel status 0 disables FIPS mode');
write_text($fips_status, "  1  \n");
ok(xCAT::Utils->isFIPS($fips_status), 'kernel status permits surrounding whitespace');
write_text($fips_status, "enabled\n");
ok(!xCAT::Utils->isFIPS($fips_status), 'malformed kernel status does not enable FIPS mode');
write_text($fips_status, '');
ok(!xCAT::Utils->isFIPS($fips_status), 'empty kernel status does not enable FIPS mode');
ok(!xCAT::Utils->isFIPS(File::Spec->catfile($tmpdir, 'missing')), 'missing kernel status is not FIPS mode');

foreach my $case (
    ['el7', 1], ['el8', 1], ['el9', 1], ['el10', 0], ['el11', 0],
    ['ubuntu', 1], ['sles12', 1], ['sles15', 1], ['aix', 1],
) {
    my ($platform, $legacy_allowed) = @{$case};
    is(xCAT::Utils->dsaHostKeyAllowed($platform, 0), $legacy_allowed,
        "$platform retains its non-FIPS DSA policy");
    is(xCAT::Utils->dsaHostKeyAllowed($platform, 1), 0,
        "$platform rejects DSA in FIPS mode");
}

done_testing();
