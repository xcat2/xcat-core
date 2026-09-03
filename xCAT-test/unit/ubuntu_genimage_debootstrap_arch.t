#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# debootstrap takes the Debian architecture name, which differs from the name xCAT uses for
# the node. Drive the assignment genimage makes and check the name it computes. The
# invocation that consumes it is not exercised here.

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::Utils;

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));
my $genimage  = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'netboot', 'ubuntu', 'genimage');
plan skip_all => "genimage not found at $genimage" unless -f $genimage;

my $src = do { local $/; open my $fh, '<', $genimage or die $!; <$fh> };
# Take every line that assigns $uarch, not just the first: the name has been built in
# more than one statement before, and half of it would look like a different value.
my ($assignment) = $src =~ /^(my \$uarch\b.*?)\n\s*\n/ms;
ok(defined $assignment, 'found the debootstrap architecture assignment in genimage')
  or do { done_testing(); exit };

sub debootstrap_arch {
    my ($arch) = @_;
    my $uarch;
    my $code = $assignment;
    $code =~ s/^my\s+//;
    no strict 'subs';    ## the script itself does not enable strict subs
    eval "$code 1" or die $@;    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    return $uarch;
}

is(debootstrap_arch('x86_64'),  'amd64',   'x86_64 resolves to the Debian name amd64');
is(debootstrap_arch('ppc64el'), 'ppc64el', 'the Debian spelling of POWER LE is kept');
is(debootstrap_arch('ppc64le'), 'ppc64le', 'the POWER LE alias is passed through, as it is today');
is(debootstrap_arch('s390x'),   's390x',   'an architecture Debian names the same is passed through');

done_testing();
