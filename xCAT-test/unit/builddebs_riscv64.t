#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# A riscv64 management node needs an xcat and xcatsn deb built for the architecture and a
# mklocalrepo.sh that points the host at the matching repository instead of amd64.
#
# The generated script is extracted from builddebs.pl and run with a stub uname ahead of
# $PATH, so the mapping under test is the shipped code. Only the path it writes is
# redirected into the sandbox, because it writes an apt source list.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $builder = File::Spec->catfile( $repo_root, 'builddebs.pl' );
plan skip_all => "builddebs.pl not found" unless -f $builder;

my $src = do { local $/; open my $fh, '<', $builder or die $!; <$fh> };

# BAIL_OUT rather than skip: a rename that stops this matching must fail loudly instead of
# silently covering nothing.
my ($script) = $src =~ /write_script\("\$repodir\/mklocalrepo\.sh", <<'SCRIPT'\);\n(.*?)\nSCRIPT\n/ms;
BAIL_OUT('could not extract mklocalrepo.sh from builddebs.pl') unless defined $script;

my $dir = tempdir( CLEANUP => 1 );
my $run = 0;

# Run the generated script for one host architecture and return the apt source line it wrote.
sub sources_line_for {
    my ($uname) = @_;
    $run++;
    my $root = File::Spec->catdir( $dir, "run$run" );
    mkdir $root;
    mkdir "$root/bin";

    open( my $stub, '>', "$root/bin/uname" ) or die $!;
    print {$stub} "#!/bin/bash\necho $uname\n";
    close($stub);
    chmod 0755, "$root/bin/uname";

    my $release = File::Spec->catfile( $root, 'lsb-release' );
    open( my $rel, '>', $release ) or die $!;
    print {$rel} "DISTRIB_CODENAME=noble\n";
    close($rel);

    my $listed = File::Spec->catfile( $root, 'sources.list' );
    ( my $sandboxed = $script ) =~ s{/etc/lsb-release}{$release};
    $sandboxed =~ s{/etc/apt/sources\.list\.d/\S+}{$listed};

    my $harness = File::Spec->catfile( $root, 'harness.sh' );
    open( my $fh, '>', $harness ) or die $!;
    print {$fh} "#!/bin/bash\n$sandboxed\n";
    close($fh);

    local $ENV{PATH} = "$root/bin:$ENV{PATH}";
    system( '/bin/bash', $harness );
    open( my $out, '<', $listed ) or die $!;
    my $line = do { local $/; <$out> };
    close($out);
    return $line;
}

for my $case (
    [ 'riscv64', 'riscv64' ],
    [ 'ppc64le', 'ppc64el' ],
    [ 'x86_64',  'amd64' ],
  )
{
    my ( $uname, $want ) = @$case;
    like( sources_line_for($uname), qr/^deb \[arch=\Q$want\E\] /,
        "mklocalrepo.sh gives a $uname host the $want repository" );
}

# The debs themselves must exist for the architecture.
for my $case ( [ 'xCAT', 'xcat' ], [ 'xCATsn', 'xcatsn' ] ) {
    my ( $component, $package ) = @$case;
    my $control = File::Spec->catfile( $repo_root, $component, 'debian', 'control' );
    my $text = do { local $/; open my $fh, '<', $control or die $!; <$fh> };
    my ($arches) = $text =~ /^Package: \Q$package\E\nArchitecture: (.*)$/m;
    ok( defined $arches, "$package declares an architecture" );
    like( $arches || '', qr/\briscv64\b/, "$package is built for riscv64" );
    like( $arches || '', qr/\bamd64\b.*\bppc64el\b/, "$package keeps amd64 and ppc64el" );
}

done_testing();
