package XCAT::Test::File;

use strict;
use warnings;

use Cwd qw(abs_path);
use Exporter qw(import);
use File::Basename qw(dirname);
use File::Spec;
use IO::Handle;

our @EXPORT_OK = qw(repo_path slurp_repo_file);

my $module_dir = dirname( File::Spec->rel2abs(__FILE__) );
my $repo_root = abs_path(
    File::Spec->catdir(
        $module_dir,
        File::Spec->updir(),
        File::Spec->updir(),
        File::Spec->updir(),
        File::Spec->updir(),
    )
);
die "Unable to resolve the repository root from $module_dir: $!" unless defined $repo_root;
my $module_path = File::Spec->catfile( $repo_root, 'xCAT-test', 'lib', 'XCAT', 'Test', 'File.pm' );
die "Unable to locate the repository test support at $module_path" unless -f $module_path;

sub repo_path {
    my ($relative) = @_;
    die "Repository-relative path is required" unless defined $relative && length $relative;
    die "Repository path must be relative: $relative" if File::Spec->file_name_is_absolute($relative);
    foreach my $part ( File::Spec->splitdir($relative) ) {
        die "Repository path must not escape the checkout: $relative" if $part eq File::Spec->updir();
    }

    return File::Spec->catfile( $repo_root, $relative );
}

sub slurp_repo_file {
    my ($relative) = @_;
    my $path = repo_path($relative);

    open( my $fh, '<:raw', $path ) or die "Unable to open $path for reading: $!";
    my $contents = do { local $/; <$fh> };
    unless ( defined $contents && !$fh->error ) {
        my $error = $!;
        close($fh);
        die "Unable to read $path: $error";
    }
    close($fh) or die "Unable to close $path: $!";

    return $contents;
}

1;

__END__

=head1 NAME

XCAT::Test::File - repository file helpers for source-tree tests

=head1 FUNCTIONS

=head2 repo_path

Returns the absolute path for a repository-relative path.

=head2 slurp_repo_file

Reads a repository-relative file in raw mode and returns its complete contents.

=cut
