#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(slurp_repo_file);

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::Sandbox qw(replace_required assert_no_host_paths stub_bin run_confined);

# A riscv64 management node needs an xcat and xcatsn deb built for the architecture and a
# mklocalrepo.sh that points the host at the matching repository instead of amd64.
#
# The generated script is extracted from builddebs.pl and run with a stub uname, so the mapping
# under test is the shipped code. The script writes an apt source list, so the paths it reads and
# writes are redirected into the sandbox, and it runs confined.

my $src = slurp_repo_file('builddebs.pl');

# die rather than skip: a rename that stops this matching must fail loudly instead of silently
# covering nothing.
my ($script) = $src =~ /write_script\("\$repodir\/mklocalrepo\.sh", <<'SCRIPT'\);\n(.*?)\nSCRIPT\n/ms;
die "could not extract mklocalrepo.sh from builddebs.pl\n" unless defined $script;

my $dir = tempdir( CLEANUP => 1 );
my $run = 0;

# Run the generated script for one host architecture and return the apt source line it wrote.
sub sources_line_for {
    my ($uname) = @_;
    $run++;
    my $root = File::Spec->catdir( $dir, "run$run" );
    mkdir $root;

    my $release = File::Spec->catfile( $root, 'lsb-release' );
    open( my $rel, '>', $release ) or die $!;
    print {$rel} "DISTRIB_CODENAME=noble\n";
    close($rel);

    my $listed    = File::Spec->catfile( $root, 'sources.list' );
    my $sandboxed = $script;
    replace_required( \$sandboxed, '/etc/lsb-release',                       $release );
    replace_required( \$sandboxed, '/etc/apt/sources.list.d/xcat-core.list', $listed );
    assert_no_host_paths( $sandboxed, root => $root );

    my $harness = File::Spec->catfile( $root, 'harness.sh' );
    open( my $fh, '>', $harness ) or die $!;
    print {$fh} "#!/bin/bash\n$sandboxed\n";
    close($fh);

    my $bin = stub_bin(
        dir   => File::Spec->catdir( $root, 'bin' ),
        tools => [qw(bash dirname)],
        stubs => { uname => "echo $uname" },
    );
    my ( $status, $output ) = run_confined( cmd => [ 'bash', $harness ], bin => $bin, writable => [$root], dir => $root );
    is( $status, 0, "mklocalrepo.sh completes for a $uname host" ) or diag($output);

    open( my $out, '<', $listed ) or die "mklocalrepo.sh wrote no source list for $uname: $!";
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
    my $text = slurp_repo_file("$component/debian/control");
    my ($arches) = $text =~ /^Package: \Q$package\E\nArchitecture: (.*)$/m;
    ok( defined $arches, "$package declares an architecture" );
    like( $arches || '', qr/\briscv64\b/, "$package is built for riscv64" );
    like( $arches || '', qr/\bamd64\b.*\bppc64el\b/, "$package keeps amd64 and ppc64el" );
}

done_testing();
