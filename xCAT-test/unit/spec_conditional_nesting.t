#!/usr/bin/perl
# Every *.spec in the tree must carry a well formed conditional structure.
# rpmbuild rejects a spec with two %else in one block, and a merge of two
# branches that both rewrite the same conditional can produce that without a
# git conflict.
use strict;
use warnings;
use Test::More;
use File::Find ();
use File::Basename qw(dirname);
use File::Spec ();
use File::Slurper qw(read_lines);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..', '..'));

my @specs;
File::Find::find(
    {
        no_chdir => 1,
        wanted   => sub {
            my $p = $File::Find::name;
            return if $p =~ m{/\.git/};
            push @specs, $p if $p =~ /\.spec$/;
        },
    },
    $root
);
@specs = sort @specs;

ok(scalar(@specs) >= 20, 'the tree holds the spec files to check (' . scalar(@specs) . ')');

#---------------------------------------------------------------------------

=head3 conditional_faults

Descriptions:
    Reports every malformed rpm conditional in one spec file.

Arguments:
    $path - the spec file to read

Returns:
    A list of message strings. An empty list means the file is well formed.

=cut

#---------------------------------------------------------------------------
sub conditional_faults {
    my ($path) = @_;
    my @faults;
    my @stack;    # one entry per open conditional: { line, seen_else }
    my $n = 0;
    for my $line (read_lines($path)) {
        $n++;
        next if $line =~ /^\s*#/;
        if ($line =~ /^\s*%(if|ifos|ifnos|ifarch|ifnarch)\b/) {
            push @stack, { line => $n, seen_else => 0 };
            next;
        }
        if ($line =~ /^\s*%else\b/) {
            if (!@stack) {
                push @faults, "line $n: %else with no open conditional";
                next;
            }
            if ($stack[-1]->{seen_else}) {
                push @faults,
                  "line $n: %else after %else (conditional opened at line " . $stack[-1]->{line} . ")";
                next;
            }
            $stack[-1]->{seen_else} = 1;
            next;
        }
        if ($line =~ /^\s*%elif\b/) {
            if (!@stack) {
                push @faults, "line $n: %elif with no open conditional";
                next;
            }
            if ($stack[-1]->{seen_else}) {
                push @faults, "line $n: %elif after %else";
            }
            next;
        }
        if ($line =~ /^\s*%endif\b/) {
            if (!@stack) {
                push @faults, "line $n: %endif with no open conditional";
                next;
            }
            pop @stack;
            next;
        }
    }
    push @faults, "unterminated conditional opened at line " . $_->{line} for @stack;
    return @faults;
}

for my $spec (@specs) {
    my $rel = $spec;
    $rel =~ s/^\Q$root\E\/?//;
    my @faults = conditional_faults($spec);
    is_deeply(\@faults, [], "$rel: conditionals are well formed")
      or diag("$rel\n  " . join("\n  ", @faults));
}

# The parser itself must report the fault it exists to catch.
my $probe = File::Spec->catfile(File::Spec->tmpdir(), "spec_conditional_nesting.$$.spec");
open(my $fh, '>', $probe) or die "cannot write $probe: $!";
print {$fh} "%if 0%{?suse_version}\nBuildRequires: perl\n%else\nBuildRequires: perl-Pod-Html\n%else\nBuildRequires: perl\n%endif\n";
close($fh);
my @probe_faults = conditional_faults($probe);
like(($probe_faults[0] // ''), qr/%else after %else/, 'the check reports a second %else');
unlink($probe);

done_testing();
