#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# A netboot image resolves names with the libnss libraries of its own architecture, and
# Ubuntu keeps them in a per-architecture directory. Build a root filesystem for each
# architecture and run genimage's selection over it.

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));
my $genimage  = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'netboot', 'ubuntu', 'genimage');
plan skip_all => "genimage not found at $genimage" unless -f $genimage;

my $src = do { local $/; open my $fh, '<', $genimage or die $!; <$fh> };
my ($selection) =
  $src =~ /^(\s*if \(\$arch =~ \/x86_64\/\) \{.*?\n\s*\} else \{.*?\n\s*\}\n)/ms;
ok(defined $selection, 'found the resolver library selection in genimage')
  or do { done_testing(); exit };

sub selected {
    my ($arch, @present) = @_;
    my $rootimg_dir = tempdir(CLEANUP => 1);
    foreach my $file (@present) {
        my $full = "$rootimg_dir/$file";
        ($full =~ m{^(.*)/[^/]+$}) and make_path($1);
        open(my $fh, '>', $full) or die $!;
        close($fh);
    }
    my @filestoadd;
    eval "$selection 1" or die $@;    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    return join(',', sort @filestoadd);
}

is(
    selected('riscv64', 'lib/riscv64-linux-gnu/libnss_files.so.2',
                        'lib/riscv64-linux-gnu/libnss_dns.so.2'),
    'lib/riscv64-linux-gnu/libnss_dns.so.2,lib/riscv64-linux-gnu/libnss_files.so.2',
    'a riscv64 image takes the riscv64 resolver libraries',
);
is(
    selected('riscv64', 'lib/libnss_dns.so.2'),
    '',
    'riscv64 does not fall back to the path that holds no riscv64 library',
);
is(
    selected('x86_64', 'lib/x86_64-linux-gnu/libnss_dns.so.2'),
    'lib/x86_64-linux-gnu/libnss_dns.so.2',
    'x86_64 selection is unchanged',
);
is(
    selected('ppc64el', 'lib/powerpc64le-linux-gnu/libnss_files.so.2'),
    'lib/powerpc64le-linux-gnu/libnss_files.so.2',
    'ppc64el selection is unchanged',
);
is(
    selected('s390x', 'lib/libnss_dns.so.2'),
    'lib/libnss_dns.so.2',
    'an architecture with no branch keeps the generic library',
);

done_testing();
