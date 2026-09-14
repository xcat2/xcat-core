#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use XCAT::BuildUtils qw(read_line snap_release);

# builddebs.pl takes the Release file as authoritative. The tracked file holds the
# placeholder snap000000000000, and only buildrpms.pl overwrites it with the commit
# time. A pipeline that does not run buildrpms.pl keeps the placeholder.
#
# The release decision is extracted from builddebs.pl and run here, so the assertions
# measure the shipped code rather than a copy of it.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $builder = File::Spec->catfile( $repo_root, 'builddebs.pl' );
plan skip_all => "builddebs.pl not found" unless -f $builder;

my $src = do { local $/; open my $fh, '<', $builder or die $!; <$fh> };

# die rather than skip: a rewrite that stops this matching must fail loudly
# instead of silently covering nothing.
my ($block) = $src =~ /^(my \$FILE_RELEASE\b.*?^my \$RELEASE\s*=.*?;\n)/ms;
die('could not extract the release decision from builddebs.pl')
    unless defined $block;

my $dir = tempdir( CLEANUP => 1 );
my $run = 0;

# Resolve the release the way builddebs.pl does, for one Release file content and one
# --release option. Returns the release string.
sub release_for {
    my ( $file_content, $opt_release ) = @_;
    $run++;
    my $ROOT = File::Spec->catdir( $dir, "run$run" );
    mkdir $ROOT or die $!;
    if ( defined $file_content ) {
        open( my $fh, '>', File::Spec->catfile( $ROOT, 'Release' ) ) or die $!;
        print {$fh} $file_content;
        close($fh);
    }
    my $EPOCH = 1756000000;
    my %opts;
    $opts{release} = $opt_release if defined $opt_release;
    my $got = eval "$block\n\$RELEASE";
    die $@ if $@;
    return $got;
}

my $from_epoch = snap_release(1756000000);

is( release_for("snap000000000000\n"), $from_epoch,
    'the tracked placeholder is not a release, so the commit time is used' );

is( release_for("snap202608240826\n"), 'snap202608240826',
    'a release buildrpms.pl wrote is still authoritative' );

is( release_for(undef), $from_epoch,
    'no Release file gives the commit time' );

is( release_for( "snap000000000000\n", 'snap209901010000' ), 'snap209901010000',
    '--release still wins over the placeholder' );

done_testing();
