#!/usr/bin/env perl
# Three rules hold for every unit test, and no single test can check them for itself:
#   - XCAT::Test::Source is the first module a test loads, so no xCAT module can put the
#     installed tree in front of the checkout before it;
#   - no test bails out, because prove then stops every test file after it;
#   - no test skips because a file of the checkout is missing, because a broken checkout then
#     passes.
# This file reads the test files. It does not read product code.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(repo_path);

use File::Find ();
use File::Spec;
use Test::More;

my $unit = repo_path('xCAT-test/unit');

my @files;
File::Find::find(
    {
        no_chdir => 1,
        wanted   => sub { push @files, $File::Find::name if /\.t\z/ && -f $_ },
    },
    $unit
);
@files = sort @files;
ok( @files > 1, 'the unit test files are found' );

# Written in two parts so that this file does not match its own rule.
my $bail = 'BAIL' . '_OUT';

my ( @late_source, @bails, @missing_skips );
foreach my $file (@files) {
    open( my $fh, '<', $file ) or die "Unable to read $file: $!\n";
    my @lines = <$fh>;
    close($fh);
    my $name = File::Spec->abs2rel( $file, $unit );

    my $first;
    foreach my $line (@lines) {
        last if $line =~ /^__(?:END|DATA)__\b/;
        next unless $line =~ /^\s*(use|require)\s+([\w:]+)/;
        my ( $keyword, $module ) = ( $1, $2 );
        next if $keyword eq 'use' && $module =~ /\A(?:strict|warnings|utf8|FindBin|v?\d)/;
        next if $keyword eq 'use' && $module eq 'lib' && $line =~ m{"\$FindBin::Bin/\.\./lib"};
        $first = $module;
        last;
    }
    push @late_source, $name unless defined $first && $first eq 'XCAT::Test::Source';

    push @bails,         $name if grep { !/^\s*#/ && /\b$bail\b/ } @lines;
    push @missing_skips, $name if grep { !/^\s*#/ && /\bskip(?:_all)?\b.*\bnot found\b/ } @lines;
}

is_deeply( \@late_source, [], 'every unit test loads XCAT::Test::Source before any other module' );
is_deeply( \@bails, [], "no unit test calls $bail, which stops every test file after it" );
is_deeply( \@missing_skips, [], 'no unit test skips because a file of the checkout is missing' );

done_testing();
