#!/usr/bin/env perl
# openSUSE has no perl-generators, and its chroot carries only perl-base, which ships
# no Pod::Man and no pod2man. A spec that converts pods in %build must therefore name a
# build dependency that holds under suse_version, or the buildroot holds none by accident.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

#-------------------------------------------------------------------------------

=head3 converts_pods

Descriptions: Say whether a spec runs a pod converter in an active line. A commented
call does not count: xCAT-confluent carries one and needs no converter.

Arguments: the spec text

Returns: the number of converter calls

=cut

#-------------------------------------------------------------------------------
sub converts_pods {
    my ($text) = @_;
    return scalar(grep { /^\s*(\.\/xpod2man|pod2man|pod2html)\b/ } split /\n/, $text);
}

#-------------------------------------------------------------------------------

=head3 suse_buildrequires

Descriptions: Collect the BuildRequires of a spec that apply when suse_version is
defined. Only the suse_version conditionals are evaluated; any other %if is entered,
because its BuildRequires can still reach a SUSE build.

Arguments: the spec text

Returns: the list of required package names

=cut

#-------------------------------------------------------------------------------
sub suse_buildrequires {
    my ($text) = @_;
    my @dead;    # one entry per open conditional: true means the branch is not taken
    my @names;
    for my $line (split /\n/, $text) {
        if ($line =~ /^%if\s*(!?)\s*0%\{\?suse_version\}\s*$/) {
            push @dead, ($1 eq '!' ? 1 : 0);
        }
        elsif ($line =~ /^%if/) {
            push @dead, 0;
        }
        elsif ($line =~ /^%else\b/) {
            $dead[-1] = $dead[-1] ? 0 : 1 if @dead;
        }
        elsif ($line =~ /^%endif/) {
            pop @dead;
        }
        elsif ($line =~ /^BuildRequires:\s*(.+?)\s*$/ && !grep { $_ } @dead) {
            push @names, split /[,\s]+/, $1;
        }
    }
    return @names;
}

my %text;
for my $absolute (glob repo_path('*/*.spec')) {
    my @parts = File::Spec->splitdir($absolute);
    my $relative = File::Spec->catfile(@parts[-2, -1]);
    $text{$relative} = slurp_repo_file($relative);
}
die "read no package spec from the checkout" unless keys %text > 10;

my @converting = sort grep { converts_pods($text{$_}) } keys %text;
plan skip_all => 'no spec converts pods' unless @converting;
plan tests => 1 + scalar(@converting);

cmp_ok(scalar(@converting), '>=', 4, 'several specs convert pods in %build');

# On Leap 15.6 perl(Pod::Man), perl(Pod::Html) and /usr/bin/pod2man are all in "perl";
# "perl-Pod-Html" does not exist there at all.
for my $relative (@converting) {
    my @required = suse_buildrequires($text{$relative});
    ok(scalar(grep { $_ eq 'perl' } @required),
        "$relative build-requires perl on SUSE, which provides Pod::Man and pod2man")
        or diag("BuildRequires under suse_version: "
            . (@required ? join(', ', @required) : '(none)'));
}
