#!/usr/bin/env perl
# The genesis spec is the build root manifest: what it does not build-require, the buildroot
# only holds by accident, and dracut_install then installs nothing.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $relative = 'xCAT-genesis-builder/xCAT-genesis-base.spec';
plan skip_all => "$relative not found" unless -f repo_path($relative);
plan tests => 4;

my @lines = split /\n/, slurp_repo_file($relative);

# getcert, getdestiny, getipmi and getadapter all run the openssl command. el8 and el9
# held it in the buildroot as a dependency of something else; el10 does not.
my @openssl = grep { /^BuildRequires:\s*openssl\s*$/ } @lines;
is(scalar(@openssl), 1, 'the spec build-requires openssl');

my ($buildarch) = grep { $lines[$_] =~ /^BuildArch:\s*noarch/ } 0 .. $#lines;
ok(defined $buildarch, 'the spec sets BuildArch: noarch');

# rpm reads the spec a second time with the target set to noarch, so %{_target_cpu} is
# "noarch" from BuildArch onwards. %{tarch} keeps the real architecture.
my @late_target_cpu = grep { $lines[$_] =~ /_target_cpu/ } ($buildarch + 1) .. $#lines;
is(scalar(@late_target_cpu), 0,
    '%{_target_cpu} is not read after BuildArch: noarch')
    or diag(join "\n", map { ($_ + 1) . ": $lines[$_]" } @late_target_cpu);

my ($openssl_line) = grep { $lines[$_] =~ /^BuildRequires:\s*openssl\s*$/ } 0 .. $#lines;
my $guarded = 0;
if (defined $openssl_line) {
    for my $i (reverse 0 .. $openssl_line - 1) {
        last if $lines[$i] =~ /^%endif/;
        $guarded = 1, last if $lines[$i] =~ /^%if/;
    }
}
is($guarded, 0, 'openssl is build-required on every release');
