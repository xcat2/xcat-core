#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm');
plan skip_all => 'anaconda.pm not found' unless -r $plugin;
$ENV{XCATROOT} ||= repo_path('xCAT-server');
require $plugin;

# Build a media tree holding the given package file names.
sub media_with {
    my @rpms = @_;
    my $root = tempdir( CLEANUP => 1 );
    make_path( File::Spec->catdir( $root, 'BaseOS', 'Packages' ) );
    foreach my $rpm (@rpms) {
        my $path = File::Spec->catfile( $root, 'BaseOS', 'Packages', $rpm );
        write_text( $path, '' );
    }
    return $root;
}

sub distname_for { return xCAT_plugin::anaconda::_centos_linux_distname(@_); }

# Every CentOS Linux 8 medium describes itself as "CentOS Linux 8", so these
# are the real package names each release shipped in BaseOS/Packages.
my %release_media = (
    '8.0' => ['centos-release-8.0-0.1905.0.9.el8.i686.rpm',
              'centos-release-8.0-0.1905.0.9.el8.x86_64.rpm'],
    '8.1' => ['centos-release-8.1-1.1911.0.8.el8.x86_64.rpm',
              'centos-release-8.1-1.1911.0.9.el8.x86_64.rpm'],
    '8.2' => ['centos-release-8.2-2.2004.0.1.el8.x86_64.rpm',
              'centos-release-8.2-2.2004.0.2.el8.x86_64.rpm'],
    '8.3' => ['centos-linux-release-8.3-1.2011.el8.noarch.rpm'],
    '8.4' => ['centos-linux-release-8.4-1.2105.el8.noarch.rpm'],
    '8.5' => ['centos-linux-release-8.5-1.2111.el8.noarch.rpm'],
);

foreach my $minor ( sort keys %release_media ) {
    my $root = media_with( @{ $release_media{$minor} } );
    is( distname_for( 'CentOS Linux 8', $root ), "centos$minor",
        "CentOS Linux $minor media is identified as centos$minor" );
}

# The package was renamed in 8.3, so both names have to be read.
my $renamed = media_with('centos-linux-release-8.5-1.2111.el8.noarch.rpm');
is( distname_for( 'CentOS Linux 8', $renamed ), 'centos8.5',
    'the renamed release package is read' );
my $original = media_with('centos-release-8.2-2.2004.0.1.el8.x86_64.rpm');
is( distname_for( 'CentOS Linux 8', $original ), 'centos8.2',
    'the original release package name is still read' );

# Without a usable package the description is all there is, which is what
# xCAT reported before.
is( distname_for( 'CentOS Linux 8', media_with() ), 'centos8',
    'media with no release package keeps the version from the description' );
is( distname_for( 'CentOS Linux 8', tempdir( CLEANUP => 1 ) ), 'centos8',
    'media with no BaseOS directory keeps the version from the description' );
is( distname_for( 'CentOS Linux 8', '/nonexistent/media/path' ), 'centos8',
    'an unreadable media path keeps the version from the description' );
my @warnings;
{
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    is( distname_for('CentOS Linux 8'), 'centos8',
        'a missing media path keeps the version from the description' );
}
is( scalar @warnings, 0,
    'a missing media path draws no warning into the daemon log' );

# Other packages share the centos-release prefix and name no release version.
my $siblings = media_with(
    'centos-release-storage-common-2-2.el8.noarch.rpm',
    'centos-release-ceph-nautilus-1.2-2.el8.noarch.rpm',
    'centos-release-stream-8.1-1.1911.0.7.el8.x86_64.rpm',
    'centos-release-advanced-virtualization-1.0-2.el8.noarch.rpm',
);
is( distname_for( 'CentOS Linux 8', $siblings ), 'centos8',
    'a package that names no release version is not read as one' );

# The same packages must not mask a real release package either.
my $mixed = media_with(
    'centos-release-storage-common-2-2.el8.noarch.rpm',
    'centos-linux-release-8.4-1.2105.el8.noarch.rpm',
);
is( distname_for( 'CentOS Linux 8', $mixed ), 'centos8.4',
    'a real release package is read alongside its namesakes' );

# A release package for another major version does not describe this medium.
my $mismatch = media_with('centos-linux-release-9.1-1.el9.noarch.rpm');
is( distname_for( 'CentOS Linux 8', $mismatch ), 'centos8',
    'a release package for another major version is not read' );

my $mixed_major = media_with(
    'centos-linux-release-9.1-1.el9.noarch.rpm',
    'centos-linux-release-8.4-1.2105.el8.noarch.rpm',
);
is( distname_for( 'CentOS Linux 8', $mixed_major ), 'centos8.4',
    'the release package of this major version is the one that is read' );

# A medium that names more than one minor version does not pin a minor, so
# it keeps the unversioned name rather than a guess between them.
my $ambiguous = media_with(
    'centos-linux-release-8.4-1.2105.el8.noarch.rpm',
    'centos-linux-release-8.5-1.2111.el8.noarch.rpm',
);
is( distname_for( 'CentOS Linux 8', $ambiguous ), 'centos8',
    'a medium that names two minor versions keeps the unversioned name' );

# Several packages of the SAME minor version still name one release.
my $repeated = media_with(
    'centos-release-8.0-0.1905.0.9.el8.i686.rpm',
    'centos-release-8.0-0.1905.0.9.el8.x86_64.rpm',
    'centos-release-8.0-0.1905.0.8.el8.x86_64.rpm',
);
is( distname_for( 'CentOS Linux 8', $repeated ), 'centos8.0',
    'several packages of one minor version still name that version' );

# Only CentOS Linux takes this path. Every other distribution keeps the
# branch it had, and CentOS Stream carries no minor version by design.
my $any = media_with('centos-linux-release-8.5-1.2111.el8.noarch.rpm');
foreach my $other (
    'CentOS Stream 9',            'CentOS Stream 10',
    'AlmaLinux 9.8',              'AlmaLinux 10.2',
    'Rocky Linux 9.8',            'Rocky Linux 10.2',
    'Red Hat Enterprise Linux 9.6', 'Oracle Linux 9.3',
    'IBM_PowerKVM 3.1',           '7.9',
  )
{
    is( distname_for( $other, $any ), undef,
        "'$other' media is left to its own branch" );
}
is( distname_for( undef, $any ), undef, 'media with no description is skipped' );

done_testing();
