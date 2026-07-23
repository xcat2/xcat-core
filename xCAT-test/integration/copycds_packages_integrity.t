#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Find;

# This test verifies that copycds does not leave empty Packages files
# alongside valid Packages.gz files.  An empty Packages file causes
# apt's cdrom handler to fail with a hash mismatch during autoinstall.

my $installdir = $ENV{INSTALLDIR} || '/install';

plan skip_all => "$installdir not found" unless -d $installdir;

my @empty_packages;
my @ok_packages;

find(sub {
    return unless $_ eq 'Packages';
    return unless -f $File::Find::name;

    my $gz = "$File::Find::name.gz";
    if (-s $File::Find::name == 0 && -f $gz && -s $gz > 0) {
        push @empty_packages, $File::Find::name;
    } elsif (-s $File::Find::name > 0) {
        push @ok_packages, $File::Find::name;
    }
}, "$installdir");

if (@empty_packages || @ok_packages) {
    is(scalar @empty_packages, 0,
       'no empty Packages files alongside valid Packages.gz')
        or diag("Empty Packages files found:\n  " . join("\n  ", @empty_packages));

    cmp_ok(scalar @ok_packages, '>', 0,
           'at least one non-empty Packages file exists')
        if @ok_packages;
} else {
    plan skip_all => "no apt repo trees found under $installdir";
}

done_testing();
