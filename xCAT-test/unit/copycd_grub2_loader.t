#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# copycd publishes the grub2 UEFI image of the installation media so that nodes
# of an architecture xCAT builds no boot loader for -- riscv64 -- can net boot
# without a further step. An image the management node already has is never
# replaced, and the media of every other architecture is left alone.

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm');
plan skip_all => "$plugin not found" unless -r $plugin;

my $source = slurp_repo_file('xCAT-server/lib/xcat/plugins/anaconda.pm');

# anaconda.pm needs a database to load, so take just the loader publication out
# of it, the way the other unit tests here isolate a shipped sub.
my ($loaders) = $source =~ /^(my %MEDIA_GRUB2_LOADERS = \([^)]*\);)$/m;
ok( $loaders, 'the media boot loader map was located in anaconda.pm' )
  or BAIL_OUT('anaconda.pm no longer defines %MEDIA_GRUB2_LOADERS');
my ($sub) = $source =~ /^(sub _install_media_grub2_loader \{.*?^\})$/ms;
ok( $sub, 'the media boot loader publication was located in anaconda.pm' )
  or BAIL_OUT('anaconda.pm no longer defines _install_media_grub2_loader');

my $tftpdir;
{
    package xCAT::TableUtils;
    sub getTftpDir { return $tftpdir; }
}

eval "use File::Path qw(mkpath); use File::Copy; $loaders $sub 1;" or die $@;

sub media {
    my ( $root, $name, $image ) = @_;
    my $path = File::Spec->catdir( $root, $name );
    make_path( File::Spec->catdir( $path, 'EFI', 'BOOT' ) );
    if ($image) {
        my $file = File::Spec->catfile( $path, 'EFI', 'BOOT', $image );
        open( my $fh, '>', $file ) or die "Unable to create $file: $!";
        print $fh "boot loader from the media\n";
        close($fh);
    }
    return $path;
}

sub messages {
    my ($responses) = @_;
    return join( ' ', map { ref($_) eq 'HASH' && $_->{data} ? "@{[ $_->{data} ]}" : () } @{$responses} );
}

my $root = tempdir( CLEANUP => 1 );
$tftpdir = File::Spec->catdir( $root, 'tftpboot' );
make_path($tftpdir);

# riscv64 media, nothing published yet: the image is installed
my $riscv_media = media( $root, 'rocky10-riscv64', 'grubriscv64.efi' );
my @responses;
my $written = _install_media_grub2_loader( $riscv_media, 'riscv64', sub { push @responses, @_; } );
my $loader = File::Spec->catfile( $tftpdir, 'boot', 'grub2', 'grub2.riscv64' );
is( $written, $loader, 'riscv64 media publish their grub2 image as the riscv64 boot loader' );
ok( -f $loader, 'the boot loader is written under the TFTP root' );
is( ( stat($loader) )[7], ( stat( File::Spec->catfile( $riscv_media, 'EFI', 'BOOT', 'grubriscv64.efi' ) ) )[7],
    'the published image is the one from the media' );
like( messages( \@responses ), qr/\QInstalled $loader from the media\E/, 'the published boot loader is reported' );

# a boot loader that is already there is never replaced
open( my $fh, '>', $loader ) or die "Unable to rewrite $loader: $!";
print $fh "installed by grub2-xcat\n";
close($fh);
@responses = ();
is( scalar _install_media_grub2_loader( $riscv_media, 'riscv64', sub { push @responses, @_; } ),
    undef, 'an existing boot loader is kept' );
open( my $rfh, '<', $loader ) or die "Unable to read $loader: $!";
my $content = do { local $/; <$rfh> };
close($rfh);
is( $content, "installed by grub2-xcat\n", 'the existing boot loader is left untouched' );
is( messages( \@responses ), '', 'nothing is reported when there is nothing to do' );
unlink($loader);

# other architectures are not touched, even when their media carry an image.
# Start from an empty TFTP root so the check covers the directory as well.
$tftpdir = File::Spec->catdir( $root, 'tftpboot-x86' );
make_path($tftpdir);
my $x86_media = media( $root, 'rocky10-x86_64', 'grubx64.efi' );
@responses = ();
is( scalar _install_media_grub2_loader( $x86_media, 'x86_64', sub { push @responses, @_; } ),
    undef, 'x86_64 media publish no boot loader' );
ok( !-e File::Spec->catfile( $tftpdir, 'boot', 'grub2', 'grub2.x86_64' ), 'no x86_64 boot loader is written' );
ok( !-d File::Spec->catdir( $tftpdir, 'boot' ), 'the grub2 directory is only created when there is an image to put in it' );

# riscv64 media without the image are a no-op rather than an error
$tftpdir = File::Spec->catdir( $root, 'tftpboot-bare' );
make_path($tftpdir);
my $bare_media = media( $root, 'rocky10-riscv64-bare' );
@responses = ();
is( scalar _install_media_grub2_loader( $bare_media, 'riscv64', sub { push @responses, @_; } ),
    undef, 'media without a grub2 image publish nothing' );
is( messages( \@responses ), '', 'media without a grub2 image report nothing' );
ok( !-d File::Spec->catdir( $tftpdir, 'boot' ), 'media without a grub2 image create no directories' );

done_testing();
