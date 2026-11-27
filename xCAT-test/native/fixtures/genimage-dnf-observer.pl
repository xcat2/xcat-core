#!/usr/bin/env perl
use strict;
use warnings;
use lib '/repo/xCAT-test/lib';
use File::Slurper qw(read_text write_text);
use JSON::PP qw(encode_json);
use XCAT::Test::Lifecycle ();

my $phase = (grep { $_ eq 'xcat-gpg-extra' } @ARGV) ? 'extra' : 'base';
exec '/usr/bin/dnf', @ARGV unless grep { $_ eq 'install' } @ARGV;
my ($config) = map { $ARGV[$_ + 1] } grep { $ARGV[$_] eq '-c' } 0 .. $#ARGV;
die 'DNF invocation has no config' unless defined $config;
my $text = read_text($config);
my %keys = map { $_ => read_text($_) } $text =~ /^gpgkey=file:\/\/(.+)$/mg;
my ($rc, $out, $err) = -f '/work/capture-extra' && $phase eq 'extra'
    ? (88, '', '') : XCAT::Test::Lifecycle::command('/usr/bin/dnf', @ARGV);
write_text("/work/$phase.json", encode_json({
    argv => \@ARGV, config => $text, keys => \%keys, rc => $rc, out => $out, err => $err,
}));
print $out;
print STDERR $err;
# Stop after the observed transaction; the fixture has no kernel or initramfs tools.
exit($rc || ($phase eq 'extra' ? 88 : 0));
