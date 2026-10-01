#!/usr/bin/env perl
use strict;
use warnings;
use File::Glob qw(bsd_glob);
use JSON::PP qw(encode_json);

open(my $trace, '>>', $ENV{DNF_TRACE}) or die $!;
print {$trace} encode_json(\@ARGV) . "\n" or die $!;
close($trace) or die $!;
if (!grep({ $_ eq 'clean' } @ARGV) && $ENV{REMOVE_REPO}) {
    unlink($_) or die $! for bsd_glob("/etc/yum.repos.d/$ENV{REMOVE_REPO}");
}
exec '/usr/bin/dnf', "--installroot=$ENV{TEST_ROOT}", '--releasever=1',
    '--setopt=reposdir=/etc/yum.repos.d', '--setopt=install_weak_deps=False',
    '--setopt=tsflags=noscripts', '--noplugins', @ARGV;
die "exec dnf: $!";
